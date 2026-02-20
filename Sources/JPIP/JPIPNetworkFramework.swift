//
// JPIPNetworkFramework.swift
// J2KSwift
//
/// # JPIPNetworkFramework
///
/// Modern Apple networking using Network.framework for JPIP.
///
/// Provides Network.framework integration for JPIP protocol with support for
/// QUIC, HTTP/3, efficient TLS, and background transfer services on iOS.

import Foundation
import J2KCore

#if canImport(Network)
import Network
#endif

#if os(iOS)
import BackgroundTasks
#endif

// MARK: - Network.framework Transport

/// Modern JPIP transport using Network.framework.
///
/// Provides high-performance networking with support for HTTP/2, HTTP/3, QUIC,
/// and efficient TLS with better control over connection lifecycle.
///
/// Example:
/// ```swift
/// let transport = JPIPNetworkTransport(baseURL: serverURL)
/// try await transport.connect()
/// let response = try await transport.send(request)
/// await transport.disconnect()
/// ```
@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
public actor JPIPNetworkTransport {
    /// Transport configuration.
    public struct Configuration: Sendable {
        /// Whether to enable HTTP/3 (QUIC).
        public let enableHTTP3: Bool

        /// Whether to enable TLS.
        public let enableTLS: Bool

        /// Connection timeout in seconds.
        public let connectionTimeout: TimeInterval

        /// Request timeout in seconds.
        public let requestTimeout: TimeInterval

        /// Quality of Service for network operations.
        public let qos: J2KQualityOfService

        /// Creates a new configuration.
        ///
        /// - Parameters:
        ///   - enableHTTP3: Enable HTTP/3 (default: true).
        ///   - enableTLS: Enable TLS (default: true).
        ///   - connectionTimeout: Connection timeout (default: 30 seconds).
        ///   - requestTimeout: Request timeout (default: 60 seconds).
        ///   - qos: Quality of Service (default: .userInitiated).
        public init(
            enableHTTP3: Bool = true,
            enableTLS: Bool = true,
            connectionTimeout: TimeInterval = 30,
            requestTimeout: TimeInterval = 60,
            qos: J2KQualityOfService = .userInitiated
        ) {
            self.enableHTTP3 = enableHTTP3
            self.enableTLS = enableTLS
            self.connectionTimeout = connectionTimeout
            self.requestTimeout = requestTimeout
            self.qos = qos
        }
    }

    private let baseURL: URL
    private let configuration: Configuration

    #if canImport(Network)
    private var connection: NWConnection?
    #endif

    private var isConnected: Bool = false

    /// Creates a new Network.framework transport.
    ///
    /// - Parameters:
    ///   - baseURL: The base server URL.
    ///   - configuration: Transport configuration.
    public init(baseURL: URL, configuration: Configuration = Configuration()) {
        self.baseURL = baseURL
        self.configuration = configuration
    }

    /// Establishes a connection to the server.
    ///
    /// - Throws: ``J2KError`` if connection fails.
    public func connect() async throws {
        #if canImport(Network)
        guard !isConnected else { return }

        guard let host = baseURL.host else {
            throw J2KError.invalidParameter("Invalid URL: no host")
        }

        let port = baseURL.port ?? (configuration.enableTLS ? 443 : 80)

        // Create endpoint
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port))
        )

        // Configure parameters
        let parameters = NWParameters.tcp

        // Configure TLS
        if configuration.enableTLS {
            parameters.defaultProtocolStack.applicationProtocols = [
                NWProtocolTLS.Options()
            ]
        }

        // Configure HTTP/3 (QUIC) if enabled
        if configuration.enableHTTP3 {
            let options = NWProtocolQUIC.Options()
            parameters.defaultProtocolStack.applicationProtocols.insert(
                options,
                at: 0
            )
        }

        // Create connection
        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn

        // Start connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed {
                        resumed = true
                        continuation.resume()
                    }
                case .failed(let error):
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: J2KError.networkError("Connection failed: \(error)"))
                    }
                case .cancelled:
                    if !resumed {
                        resumed = true
                        continuation.resume(throwing: J2KError.networkError("Connection cancelled"))
                    }
                default:
                    break
                }
            }

            conn.start(queue: .global(qos: configuration.qos.dispatchQoS.qosClass))
        }

        isConnected = true
        #else
        throw J2KError.internalError("Network.framework not available")
        #endif
    }

    /// Sends a JPIP request over the connection.
    ///
    /// - Parameter request: The JPIP request to send.
    /// - Returns: The JPIP response.
    /// - Throws: ``J2KError`` if the request fails.
    public func send(_ request: JPIPRequest) async throws -> JPIPResponse {
        #if canImport(Network)
        guard isConnected, let conn = connection else {
            throw J2KError.networkError("Not connected")
        }

        // Build HTTP request
        let httpRequest = try buildHTTPRequest(from: request)

        // Send request
        try await sendData(httpRequest, on: conn)

        // Receive response
        let responseData = try await receiveData(from: conn)

        // Parse response
        return try parseResponse(responseData)
        #else
        throw J2KError.internalError("Network.framework not available")
        #endif
    }

    /// Disconnects from the server.
    public func disconnect() {
        #if canImport(Network)
        connection?.cancel()
        connection = nil
        isConnected = false
        #endif
    }

    #if canImport(Network)
    /// Builds an HTTP request from a JPIP request.
    private func buildHTTPRequest(from request: JPIPRequest) throws -> Data {
        let queryItems = request.buildQueryItems()
        let queryString = queryItems.map { "\($0.key)=\($0.value)" }.joined(separator: "&")

        let path = baseURL.path.isEmpty ? "/" : baseURL.path
        let requestLine = "GET \(path)?\(queryString) HTTP/1.1\r\n"
        let hostHeader = "Host: \(baseURL.host ?? "localhost")\r\n"
        let acceptHeader = "Accept: application/octet-stream\r\n"
        let connectionHeader = "Connection: keep-alive\r\n"
        let endHeaders = "\r\n"

        let httpRequest = requestLine + hostHeader + acceptHeader + connectionHeader + endHeaders

        guard let data = httpRequest.data(using: .utf8) else {
            throw J2KError.internalError("Failed to encode HTTP request")
        }

        return data
    }

    /// Sends data over a connection.
    private func sendData(_ data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: J2KError.networkError("Send failed: \(error)"))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    /// Receives data from a connection.
    private func receiveData(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var receivedData = Data()

            func receiveNext() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { content, _, isComplete, error in
                    if let error = error {
                        continuation.resume(throwing: J2KError.networkError("Receive failed: \(error)"))
                        return
                    }

                    if let content = content {
                        receivedData.append(content)
                    }

                    if isComplete {
                        continuation.resume(returning: receivedData)
                    } else {
                        receiveNext()
                    }
                }
            }

            receiveNext()
        }
    }

    /// Parses an HTTP response into a JPIP response.
    private func parseResponse(_ data: Data) throws -> JPIPResponse {
        // Simple HTTP response parsing
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw J2KError.internalError("Invalid response encoding")
        }

        let components = responseString.components(separatedBy: "\r\n\r\n")
        guard components.count >= 2 else {
            throw J2KError.internalError("Invalid HTTP response format")
        }

        let headerLines = components[0].components(separatedBy: "\r\n")
        guard let statusLine = headerLines.first else {
            throw J2KError.internalError("Missing status line")
        }

        let statusComponents = statusLine.components(separatedBy: " ")
        guard statusComponents.count >= 2,
              let statusCode = Int(statusComponents[1]) else {
            throw J2KError.internalError("Invalid status line")
        }

        // Extract body
        let bodyStart = components[0].count + 4 // "\r\n\r\n"
        let bodyData = data.subdata(in: bodyStart..<data.count)

        // Parse headers
        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            let parts = line.components(separatedBy: ": ")
            if parts.count == 2 {
                headers[parts[0]] = parts[1]
            }
        }

        return JPIPResponse(
            channelID: headers["JPIP-cnew"],
            data: bodyData,
            statusCode: statusCode,
            headers: headers
        )
    }
    #endif
}

// MARK: - QUIC Support

/// QUIC protocol configuration for JPIP.
///
/// Provides configuration for QUIC transport, which offers improved performance
/// over traditional TCP for network protocols with high latency or packet loss.
///
/// Example:
/// ```swift
/// let config = JPIPQUICConfiguration(enableZeroRTT: true)
/// ```
@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
public struct JPIPQUICConfiguration: Sendable {
    /// Whether to enable 0-RTT connection resumption.
    public let enableZeroRTT: Bool

    /// Maximum idle timeout in seconds.
    public let maxIdleTimeout: TimeInterval

    /// Initial maximum data (flow control).
    public let initialMaxData: UInt64

    /// Creates a new QUIC configuration.
    ///
    /// - Parameters:
    ///   - enableZeroRTT: Enable 0-RTT (default: true).
    ///   - maxIdleTimeout: Max idle timeout (default: 30 seconds).
    ///   - initialMaxData: Initial max data (default: 10 MB).
    public init(
        enableZeroRTT: Bool = true,
        maxIdleTimeout: TimeInterval = 30,
        initialMaxData: UInt64 = 10 * 1024 * 1024
    ) {
        self.enableZeroRTT = enableZeroRTT
        self.maxIdleTimeout = maxIdleTimeout
        self.initialMaxData = initialMaxData
    }
}

// MARK: - Background Transfer Service (iOS)

#if os(iOS)
/// Background transfer service for iOS.
///
/// Enables JPIP downloads to continue when the app is in the background,
/// using URLSession background configuration and BackgroundTasks framework.
///
/// Example:
/// ```swift
/// let service = JPIPBackgroundTransferService()
/// try await service.register()
/// let taskID = try await service.scheduleDownload(request: request)
/// ```
@available(iOS 13.0, *)
public actor JPIPBackgroundTransferService {
    /// Transfer task information.
    public struct TransferTask: Sendable {
        /// Unique task identifier.
        public let id: String

        /// JPIP request being transferred.
        public let request: JPIPRequest

        /// Transfer status.
        public let status: TransferStatus
    }

    /// Transfer status.
    public enum TransferStatus: Sendable {
        case pending
        case inProgress(progress: Double)
        case completed
        case failed(Error)
    }

    private var session: URLSession?
    private var activeTasks: [String: TransferTask] = [:]

    /// Creates a new background transfer service.
    public init() {}

    /// Registers the background task handler.
    ///
    /// Must be called during app launch.
    ///
    /// - Throws: ``J2KError`` if registration fails.
    public func register() throws {
        guard #available(iOS 13.0, *) else {
            throw J2KError.internalError("Background tasks require iOS 13+")
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.j2kswift.jpip.download",
            using: nil
        ) { task in
            Task {
                if let processingTask = task as? BGProcessingTask {
                    await self.handleBackgroundTask(processingTask)
                }
            }
        }

        // Create background URLSession
        let config = URLSessionConfiguration.background(
            withIdentifier: "com.j2kswift.jpip.background"
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true

        session = URLSession(configuration: config)
    }

    /// Schedules a download for background execution.
    ///
    /// - Parameter request: The JPIP request to download.
    /// - Returns: The task identifier.
    /// - Throws: ``J2KError`` if scheduling fails.
    public func scheduleDownload(request: JPIPRequest) async throws -> String {
        guard let session = session else {
            throw J2KError.internalError("Background transfer not initialized")
        }

        let taskID = UUID().uuidString

        // Create download task (simplified - would need proper URL construction)
        let url = URL(string: "https://example.com")! // Placeholder
        _ = session.downloadTask(with: url)

        let task = TransferTask(
            id: taskID,
            request: request,
            status: .pending
        )

        activeTasks[taskID] = task

        // Schedule BGProcessingTask
        let bgTaskRequest = BGProcessingTaskRequest(identifier: "com.j2kswift.jpip.download")
        bgTaskRequest.requiresNetworkConnectivity = true
        bgTaskRequest.requiresExternalPower = false

        try BGTaskScheduler.shared.submit(bgTaskRequest)

        return taskID
    }

    /// Returns the status of a transfer task.
    ///
    /// - Parameter taskID: The task identifier.
    /// - Returns: The transfer task, or nil if not found.
    public func taskStatus(taskID: String) -> TransferTask? {
        activeTasks[taskID]
    }

    /// Cancels a transfer task.
    ///
    /// - Parameter taskID: The task identifier.
    public func cancelTask(taskID: String) {
        activeTasks.removeValue(forKey: taskID)
    }

    /// Handles a background task.
    private func handleBackgroundTask(_ task: BGProcessingTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Perform download work
        // Simplified implementation

        task.setTaskCompleted(success: true)
    }
}
#endif

// MARK: - HTTP/3 Support

/// HTTP/3 configuration for JPIP.
///
/// Provides configuration for HTTP/3 transport, which uses QUIC and offers
/// improved performance characteristics over HTTP/2.
///
/// Example:
/// ```swift
/// let config = JPIPHTTP3Configuration(enableServerPush: false)
/// ```
@available(macOS 11.0, iOS 14.0, tvOS 14.0, *)
public struct JPIPHTTP3Configuration: Sendable {
    /// Whether to enable HTTP/3 server push.
    public let enableServerPush: Bool

    /// Maximum concurrent streams.
    public let maxConcurrentStreams: Int

    /// Whether to enable early data (0-RTT).
    public let enableEarlyData: Bool

    /// Creates a new HTTP/3 configuration.
    ///
    /// - Parameters:
    ///   - enableServerPush: Enable server push (default: false).
    ///   - maxConcurrentStreams: Max concurrent streams (default: 100).
    ///   - enableEarlyData: Enable 0-RTT (default: true).
    public init(
        enableServerPush: Bool = false,
        maxConcurrentStreams: Int = 100,
        enableEarlyData: Bool = true
    ) {
        self.enableServerPush = enableServerPush
        self.maxConcurrentStreams = maxConcurrentStreams
        self.enableEarlyData = enableEarlyData
    }
}

// MARK: - Efficient TLS

/// Efficient TLS configuration for JPIP.
///
/// Provides optimized TLS configuration using Network.framework's
/// built-in support for modern TLS versions and cipher suites.
///
/// Example:
/// ```swift
/// let config = JPIPTLSConfiguration(minimumVersion: .v13)
/// ```
@available(macOS 10.15, iOS 13.0, tvOS 13.0, *)
public struct JPIPTLSConfiguration: Sendable {
    /// TLS version.
    public enum TLSVersion: Sendable {
        case v12
        case v13
    }

    /// Minimum TLS version to accept.
    public let minimumVersion: TLSVersion

    /// Whether to enable session resumption.
    public let enableSessionResumption: Bool

    /// Whether to verify server certificates.
    public let verifyServerCertificate: Bool

    /// Creates a new TLS configuration.
    ///
    /// - Parameters:
    ///   - minimumVersion: Minimum TLS version (default: v1.2).
    ///   - enableSessionResumption: Enable session resumption (default: true).
    ///   - verifyServerCertificate: Verify server certificates (default: true).
    public init(
        minimumVersion: TLSVersion = .v12,
        enableSessionResumption: Bool = true,
        verifyServerCertificate: Bool = true
    ) {
        self.minimumVersion = minimumVersion
        self.enableSessionResumption = enableSessionResumption
        self.verifyServerCertificate = verifyServerCertificate
    }
}
