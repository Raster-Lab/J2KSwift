//
// JPIPWebSocketClient.swift
// J2KSwift
//
/// # JPIPWebSocketClient
///
/// WebSocket-based JPIP client implementation.
///
/// Provides session management over WebSocket with multiplexed
/// request/response, low-latency data bin delivery via push,
/// and automatic fallback to HTTP transport on WebSocket failure.

import Foundation
import J2KCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - WebSocket Client Configuration

/// Configuration for the WebSocket JPIP client.
public struct JPIPWebSocketClientConfiguration: Sendable {
    /// Whether to enable automatic fallback to HTTP on WebSocket failure.
    public let enableHTTPFallback: Bool

    /// Reconnection configuration.
    public let reconnectionConfig: JPIPWebSocketReconnectionConfig

    /// Keepalive ping interval in seconds.
    public let keepaliveInterval: TimeInterval

    /// Request timeout in seconds.
    public let requestTimeout: TimeInterval

    /// Maximum number of concurrent requests via multiplexing.
    public let maxConcurrentRequests: Int

    /// Whether to accept server push data bins.
    public let acceptServerPush: Bool

    /// Creates a new client configuration.
    ///
    /// - Parameters:
    ///   - enableHTTPFallback: Enable HTTP fallback (default: true).
    ///   - reconnectionConfig: Reconnection config (default: .default).
    ///   - keepaliveInterval: Keepalive interval in seconds (default: 30).
    ///   - requestTimeout: Request timeout in seconds (default: 30).
    ///   - maxConcurrentRequests: Max concurrent requests (default: 16).
    ///   - acceptServerPush: Accept server push (default: true).
    public init(
        enableHTTPFallback: Bool = true,
        reconnectionConfig: JPIPWebSocketReconnectionConfig = .default,
        keepaliveInterval: TimeInterval = 30.0,
        requestTimeout: TimeInterval = 30.0,
        maxConcurrentRequests: Int = 16,
        acceptServerPush: Bool = true
    ) {
        self.enableHTTPFallback = enableHTTPFallback
        self.reconnectionConfig = reconnectionConfig
        self.keepaliveInterval = keepaliveInterval
        self.requestTimeout = requestTimeout
        self.maxConcurrentRequests = maxConcurrentRequests
        self.acceptServerPush = acceptServerPush
    }
}

// MARK: - WebSocket Client

/// A JPIP client that communicates over WebSocket transport.
///
/// Provides full JPIP client functionality over a persistent WebSocket
/// connection, with support for:
/// - Session creation and management via WebSocket
/// - Multiplexed request/response over a single connection
/// - Low-latency data bin delivery via server push
/// - Automatic fallback to HTTP transport on WebSocket failure
///
/// Example usage:
/// ```swift
/// let client = JPIPWebSocketClient(
///     serverURL: URL(string: "ws://localhost:8080/jpip")!
/// )
/// try await client.connect()
/// let session = try await client.createSession(target: "image.jp2")
/// let response = try await client.sendRequest(request)
/// ```
public actor JPIPWebSocketClient {
    /// The server URL (ws:// or wss://).
    nonisolated public let serverURL: URL

    /// Client configuration.
    nonisolated public let configuration: JPIPWebSocketClientConfiguration

    /// WebSocket transport layer.
    private let webSocketTransport: JPIPWebSocketTransport

    /// HTTP fallback transport (lazy-initialized on failure).
    private var httpTransport: JPIPTransport?

    /// Whether currently using HTTP fallback.
    public private(set) var isUsingHTTPFallback: Bool

    /// Active session.
    private var session: JPIPSession?

    /// Number of in-flight requests.
    private var inFlightRequests: Int

    /// Client statistics.
    public private(set) var statistics: Statistics

    /// Client statistics.
    public struct Statistics: Sendable {
        /// Total requests sent via WebSocket.
        public var webSocketRequests: Int = 0

        /// Total requests sent via HTTP fallback.
        public var httpFallbackRequests: Int = 0

        /// Total data bins received via push.
        public var pushedDataBins: Int = 0

        /// Number of fallback activations.
        public var fallbackActivations: Int = 0

        /// Total sessions created.
        public var sessionsCreated: Int = 0
    }

    /// Creates a new WebSocket JPIP client.
    ///
    /// - Parameters:
    ///   - serverURL: The WebSocket URL of the JPIP server.
    ///   - configuration: Client configuration.
    public init(
        serverURL: URL,
        configuration: JPIPWebSocketClientConfiguration = .init()
    ) {
        self.serverURL = serverURL
        self.configuration = configuration
        self.webSocketTransport = JPIPWebSocketTransport(
            url: serverURL,
            reconnectionConfig: configuration.reconnectionConfig,
            keepaliveInterval: configuration.keepaliveInterval
        )
        self.httpTransport = nil
        self.isUsingHTTPFallback = false
        self.inFlightRequests = 0
        self.statistics = Statistics()
    }

    /// Connects to the JPIP server via WebSocket.
    ///
    /// - Throws: ``J2KError`` if connection fails and no fallback available.
    public func connect() async throws {
        do {
            try await webSocketTransport.connect()
            isUsingHTTPFallback = false
        } catch {
            if configuration.enableHTTPFallback {
                try activateHTTPFallback()
            } else {
                throw error
            }
        }
    }

    /// Creates a new JPIP session over WebSocket.
    ///
    /// - Parameter target: The target image identifier.
    /// - Returns: A JPIP session.
    /// - Throws: ``J2KError`` if session creation fails.
    public func createSession(target: String) async throws -> JPIPSession {
        let sessionID = UUID().uuidString
        let newSession = JPIPSession(sessionID: sessionID)
        await newSession.setTarget(target)

        // Send session creation request
        var request = JPIPRequest(target: target)
        request.cnew = isUsingHTTPFallback ? .http : .webSocket

        let response = try await sendRequest(request)

        if let channelID = response.channelID {
            await newSession.setChannelID(channelID)
            await newSession.activate()
        }

        self.session = newSession
        statistics.sessionsCreated += 1
        return newSession
    }

    /// Sends a JPIP request, using WebSocket or HTTP fallback.
    ///
    /// Supports multiplexed requests over WebSocket - multiple requests
    /// can be in flight simultaneously over the single connection.
    ///
    /// - Parameter request: The JPIP request to send.
    /// - Returns: The JPIP response.
    /// - Throws: ``J2KError`` if the request fails on both transports.
    public func sendRequest(_ request: JPIPRequest) async throws -> JPIPResponse {
        guard inFlightRequests < configuration.maxConcurrentRequests else {
            throw J2KError.invalidState(
                "Too many concurrent requests (\(configuration.maxConcurrentRequests) max)"
            )
        }

        inFlightRequests += 1
        defer { inFlightRequests -= 1 }

        if !isUsingHTTPFallback {
            do {
                let response = try await webSocketTransport.sendRequest(request)
                statistics.webSocketRequests += 1
                return response
            } catch {
                // Try fallback if enabled
                if configuration.enableHTTPFallback {
                    try activateHTTPFallback()
                    return try await sendViaHTTP(request)
                }
                throw error
            }
        } else {
            return try await sendViaHTTP(request)
        }
    }

    /// Sends a request via HTTP fallback transport.
    private func sendViaHTTP(_ request: JPIPRequest) async throws -> JPIPResponse {
        guard let transport = httpTransport else {
            throw J2KError.networkError("HTTP fallback transport not initialized")
        }
        let response = try await transport.send(request)
        statistics.httpFallbackRequests += 1
        return response
    }

    /// Activates HTTP fallback transport.
    private func activateHTTPFallback() throws {
        guard configuration.enableHTTPFallback else {
            throw J2KError.networkError("HTTP fallback is disabled")
        }

        // Convert ws:// to http:// for fallback
        let httpURLString = serverURL.absoluteString
            .replacingOccurrences(of: "wss://", with: "https://")
            .replacingOccurrences(of: "ws://", with: "http://")

        guard let httpURL = URL(string: httpURLString) else {
            throw J2KError.invalidParameter(
                "Cannot convert WebSocket URL to HTTP URL"
            )
        }

        httpTransport = JPIPTransport(baseURL: httpURL)
        isUsingHTTPFallback = true
        statistics.fallbackActivations += 1
    }

    /// Retrieves data bins pushed by the server.
    ///
    /// Only available when using WebSocket transport (not HTTP fallback).
    ///
    /// - Returns: Array of pushed data bins, empty if using HTTP fallback.
    public func drainPushedDataBins() async -> [JPIPDataBin] {
        guard !isUsingHTTPFallback else { return [] }
        let bins = await webSocketTransport.drainReceivedDataBins()
        statistics.pushedDataBins += bins.count
        return bins
    }

    /// Sends a keepalive ping.
    ///
    /// - Throws: ``J2KError`` if the ping cannot be sent.
    public func sendPing() async throws {
        guard !isUsingHTTPFallback else { return }
        try await webSocketTransport.sendPing()
    }

    /// Gets the measured WebSocket latency.
    ///
    /// - Returns: The measured round-trip latency, or nil if not measured.
    public func getLatency() async -> TimeInterval? {
        await webSocketTransport.measuredLatency
    }

    /// Gets the current connection state.
    ///
    /// - Returns: The WebSocket connection state.
    public func getConnectionState() async -> JPIPWebSocketConnectionState {
        if isUsingHTTPFallback {
            return .connected
        }
        return await webSocketTransport.connectionState
    }

    /// Gets the current session.
    ///
    /// - Returns: The active session, or nil.
    public func getSession() -> JPIPSession? {
        session
    }

    /// Gets the number of in-flight requests.
    ///
    /// - Returns: Number of currently in-flight requests.
    public func getInFlightRequestCount() -> Int {
        inFlightRequests
    }

    /// Disconnects from the server and cleans up resources.
    public func close() async throws {
        if let currentSession = session {
            try await currentSession.close()
            session = nil
        }

        await webSocketTransport.disconnect()

        if let transport = httpTransport {
            await transport.close()
            httpTransport = nil
        }

        isUsingHTTPFallback = false
    }
}
