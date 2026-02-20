/// # JPIPWebSocketServer
///
/// WebSocket server implementation for JPIP protocol.
///
/// Provides WebSocket upgrade handling, concurrent session management,
/// efficient binary frame serialization, and connection health monitoring.

import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - WebSocket Connection

/// Represents an individual WebSocket connection to a client.
///
/// Tracks connection state, session binding, health metrics,
/// and handles frame-level communication.
public actor JPIPWebSocketConnection {
    /// Unique connection identifier.
    nonisolated public let connectionID: String

    /// The session bound to this connection, if any.
    public private(set) var sessionID: String?

    /// Current connection state.
    public private(set) var state: JPIPWebSocketConnectionState

    /// Last activity timestamp for health monitoring.
    public private(set) var lastActivity: Date

    /// Last keepalive pong received timestamp.
    public private(set) var lastPongReceived: Date?

    /// Measured round-trip latency in seconds.
    public private(set) var latency: TimeInterval?

    /// Total frames sent on this connection.
    public private(set) var framesSent: Int

    /// Total frames received on this connection.
    public private(set) var framesReceived: Int

    /// Total bytes sent on this connection.
    public private(set) var bytesSent: Int

    /// Total bytes received on this connection.
    public private(set) var bytesReceived: Int

    /// Pending ping timestamp for latency measurement.
    private var pendingPingTime: Date?

    /// Creates a new WebSocket connection.
    ///
    /// - Parameter connectionID: Unique connection identifier.
    public init(connectionID: String) {
        self.connectionID = connectionID
        self.state = .connected
        self.lastActivity = Date()
        self.framesSent = 0
        self.framesReceived = 0
        self.bytesSent = 0
        self.bytesReceived = 0
    }

    /// Binds a session to this connection.
    ///
    /// - Parameter sessionID: The session ID to bind.
    public func bindSession(_ sessionID: String) {
        self.sessionID = sessionID
        updateActivity()
    }

    /// Updates the last activity timestamp.
    public func updateActivity() {
        lastActivity = Date()
    }

    /// Records that a frame was sent.
    ///
    /// - Parameter size: Size of the frame in bytes.
    public func recordFrameSent(size: Int) {
        framesSent += 1
        bytesSent += size
        updateActivity()
    }

    /// Records that a frame was received.
    ///
    /// - Parameter size: Size of the frame in bytes.
    public func recordFrameReceived(size: Int) {
        framesReceived += 1
        bytesReceived += size
        updateActivity()
    }

    /// Records a ping being sent for latency measurement.
    public func recordPingSent() {
        pendingPingTime = Date()
    }

    /// Records a pong being received and calculates latency.
    public func recordPongReceived() {
        lastPongReceived = Date()
        if let pingTime = pendingPingTime {
            latency = Date().timeIntervalSince(pingTime)
            pendingPingTime = nil
        }
    }

    /// Checks if the connection is healthy based on timeout.
    ///
    /// - Parameter timeout: Maximum allowed inactivity in seconds.
    /// - Returns: True if the connection is still healthy.
    public func isHealthy(timeout: TimeInterval) -> Bool {
        guard state == .connected else { return false }
        return Date().timeIntervalSince(lastActivity) < timeout
    }

    /// Closes the connection.
    public func close() {
        state = .disconnected
        sessionID = nil
    }

    /// Gets connection info for monitoring.
    ///
    /// - Returns: Connection information struct.
    public func getInfo() -> ConnectionInfo {
        ConnectionInfo(
            connectionID: connectionID,
            sessionID: sessionID,
            state: state,
            lastActivity: lastActivity,
            latency: latency,
            framesSent: framesSent,
            framesReceived: framesReceived,
            bytesSent: bytesSent,
            bytesReceived: bytesReceived
        )
    }

    /// Connection information for monitoring.
    public struct ConnectionInfo: Sendable {
        public let connectionID: String
        public let sessionID: String?
        public let state: JPIPWebSocketConnectionState
        public let lastActivity: Date
        public let latency: TimeInterval?
        public let framesSent: Int
        public let framesReceived: Int
        public let bytesSent: Int
        public let bytesReceived: Int
    }
}

// MARK: - WebSocket Server Configuration

/// Configuration for the WebSocket JPIP server.
public struct JPIPWebSocketServerConfiguration: Sendable {
    /// Maximum concurrent WebSocket connections.
    public let maxConnections: Int

    /// Connection health check interval in seconds.
    public let healthCheckInterval: TimeInterval

    /// Connection timeout in seconds (no activity).
    public let connectionTimeout: TimeInterval

    /// Keepalive ping interval in seconds.
    public let keepaliveInterval: TimeInterval

    /// Whether to allow HTTP upgrade to WebSocket.
    public let allowUpgrade: Bool

    /// Maximum frame payload size in bytes.
    public let maxFrameSize: Int

    /// Whether to enable server push for data bins.
    public let enableServerPush: Bool

    /// Creates a new server configuration.
    ///
    /// - Parameters:
    ///   - maxConnections: Max WebSocket connections (default: 100).
    ///   - healthCheckInterval: Health check interval (default: 30).
    ///   - connectionTimeout: Connection timeout (default: 300).
    ///   - keepaliveInterval: Keepalive interval (default: 30).
    ///   - allowUpgrade: Allow HTTP to WebSocket upgrade (default: true).
    ///   - maxFrameSize: Max frame payload size (default: 16MB).
    ///   - enableServerPush: Enable server push (default: true).
    public init(
        maxConnections: Int = 100,
        healthCheckInterval: TimeInterval = 30.0,
        connectionTimeout: TimeInterval = 300.0,
        keepaliveInterval: TimeInterval = 30.0,
        allowUpgrade: Bool = true,
        maxFrameSize: Int = 16 * 1024 * 1024,
        enableServerPush: Bool = true
    ) {
        self.maxConnections = maxConnections
        self.healthCheckInterval = healthCheckInterval
        self.connectionTimeout = connectionTimeout
        self.keepaliveInterval = keepaliveInterval
        self.allowUpgrade = allowUpgrade
        self.maxFrameSize = maxFrameSize
        self.enableServerPush = enableServerPush
    }
}

// MARK: - WebSocket Server

/// A JPIP server supporting WebSocket transport.
///
/// Extends the base JPIP server with WebSocket capabilities including:
/// - HTTP to WebSocket upgrade handling
/// - Concurrent WebSocket session management
/// - Efficient binary frame serialization for data bins
/// - Connection health monitoring and keepalive
/// - Server-initiated push for data bins
///
/// Example usage:
/// ```swift
/// let server = JPIPWebSocketServer(port: 8080)
/// try await server.registerImage(name: "sample.jp2", at: imageURL)
/// try await server.start()
/// ```
public actor JPIPWebSocketServer {
    /// The port to listen on.
    nonisolated public let port: Int

    /// Server configuration.
    nonisolated public let configuration: JPIPWebSocketServerConfiguration

    /// Active WebSocket connections.
    private var connections: [String: JPIPWebSocketConnection]

    /// Session-to-connection mapping.
    private var sessionConnections: [String: String]

    /// The underlying JPIP server for request processing.
    private let jpipServer: JPIPServer

    /// Message encoder for frame serialization.
    private let encoder: JPIPWebSocketMessageEncoder

    /// Whether the server is running.
    private var isRunning: Bool

    /// Server statistics.
    public private(set) var statistics: Statistics

    /// Server statistics.
    public struct Statistics: Sendable {
        /// Total WebSocket connections accepted.
        public var totalConnections: Int = 0

        /// Currently active connections.
        public var activeConnections: Int = 0

        /// Total HTTP upgrade requests handled.
        public var upgradeRequests: Int = 0

        /// Successful upgrades.
        public var successfulUpgrades: Int = 0

        /// Failed upgrades.
        public var failedUpgrades: Int = 0

        /// Total frames sent to clients.
        public var framesSent: Int = 0

        /// Total frames received from clients.
        public var framesReceived: Int = 0

        /// Total data bins pushed to clients.
        public var dataBinsPushed: Int = 0

        /// Total keepalive pings sent.
        public var keepalivePingsSent: Int = 0

        /// Total connections closed due to timeout.
        public var timeoutDisconnections: Int = 0

        /// Total bytes sent.
        public var totalBytesSent: Int = 0

        /// Total bytes received.
        public var totalBytesReceived: Int = 0
    }

    /// Creates a new WebSocket JPIP server.
    ///
    /// - Parameters:
    ///   - port: The port to listen on (default: 8080).
    ///   - configuration: WebSocket server configuration.
    ///   - jpipConfiguration: Configuration for the underlying JPIP server.
    public init(
        port: Int = 8080,
        configuration: JPIPWebSocketServerConfiguration = .init(),
        jpipConfiguration: JPIPServer.Configuration = .init()
    ) {
        self.port = port
        self.configuration = configuration
        self.connections = [:]
        self.sessionConnections = [:]
        self.jpipServer = JPIPServer(
            port: port,
            configuration: jpipConfiguration
        )
        self.encoder = JPIPWebSocketMessageEncoder()
        self.isRunning = false
        self.statistics = Statistics()
    }

    /// Starts the WebSocket server.
    ///
    /// - Throws: ``J2KError`` if the server cannot start.
    public func start() async throws {
        guard !isRunning else {
            throw J2KError.invalidState("WebSocket server is already running")
        }

        try await jpipServer.start()
        isRunning = true
    }

    /// Stops the WebSocket server.
    ///
    /// Closes all active connections and the underlying JPIP server.
    ///
    /// - Throws: ``J2KError`` if stopping fails.
    public func stop() async throws {
        guard isRunning else {
            throw J2KError.invalidState("WebSocket server is not running")
        }

        // Close all WebSocket connections
        for (_, connection) in connections {
            await connection.close()
        }
        connections.removeAll()
        sessionConnections.removeAll()

        try await jpipServer.stop()
        isRunning = false
        statistics.activeConnections = 0
    }

    /// Registers an image for serving.
    ///
    /// - Parameters:
    ///   - name: The image name.
    ///   - url: The file URL of the image.
    /// - Throws: ``J2KError`` if the image cannot be accessed.
    public func registerImage(name: String, at url: URL) async throws {
        try await jpipServer.registerImage(name: name, at: url)
    }

    // MARK: - WebSocket Upgrade Handling

    /// Result of a WebSocket upgrade request.
    public struct UpgradeResult: Sendable {
        /// The connection ID if upgrade succeeded.
        public let connectionID: String?

        /// Error message if upgrade failed.
        public let error: String?

        /// Whether the upgrade succeeded.
        public var isSuccess: Bool { connectionID != nil }
    }

    /// Handles an HTTP upgrade request to WebSocket.
    ///
    /// Validates the upgrade request and creates a new WebSocket connection
    /// if the server can accept it.
    ///
    /// - Parameter headers: The HTTP request headers.
    /// - Returns: An upgrade result with connection ID on success or error message.
    public func handleUpgradeRequest(
        headers: [String: String]
    ) async -> UpgradeResult {
        statistics.upgradeRequests += 1

        guard isRunning else {
            statistics.failedUpgrades += 1
            return UpgradeResult(connectionID: nil, error: "Server is not running")
        }

        guard configuration.allowUpgrade else {
            statistics.failedUpgrades += 1
            return UpgradeResult(connectionID: nil, error: "WebSocket upgrade not allowed")
        }

        guard connections.count < configuration.maxConnections else {
            statistics.failedUpgrades += 1
            return UpgradeResult(connectionID: nil, error: "Maximum connections reached")
        }

        // Validate WebSocket upgrade headers
        guard let upgrade = headers["Upgrade"],
              upgrade.lowercased() == "websocket" else {
            statistics.failedUpgrades += 1
            return UpgradeResult(connectionID: nil, error: "Invalid upgrade header")
        }

        guard let connectionHeader = headers["Connection"],
              connectionHeader.lowercased().contains("upgrade") else {
            statistics.failedUpgrades += 1
            return UpgradeResult(connectionID: nil, error: "Invalid connection header")
        }

        // Check for JPIP subprotocol
        let subprotocol = headers["Sec-WebSocket-Protocol"] ?? ""
        let hasJPIPProtocol = subprotocol.lowercased().contains("jpip")

        // Create new connection
        let connectionID = UUID().uuidString
        let wsConnection = JPIPWebSocketConnection(connectionID: connectionID)

        connections[connectionID] = wsConnection
        statistics.totalConnections += 1
        statistics.activeConnections = connections.count
        statistics.successfulUpgrades += 1

        // Store subprotocol info in connection metadata if JPIP was negotiated
        if hasJPIPProtocol {
            await wsConnection.updateActivity()
        }

        return UpgradeResult(connectionID: connectionID, error: nil)
    }

    /// Builds WebSocket upgrade response headers.
    ///
    /// - Parameter acceptKey: The Sec-WebSocket-Accept key.
    /// - Returns: The response headers for the upgrade.
    public func buildUpgradeResponseHeaders(
        acceptKey: String
    ) -> [String: String] {
        var headers: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "Upgrade",
            "Sec-WebSocket-Accept": acceptKey
        ]
        headers["Sec-WebSocket-Protocol"] = "jpip"
        return headers
    }

    // MARK: - Frame Handling

    /// Handles a received WebSocket frame from a client connection.
    ///
    /// - Parameters:
    ///   - frame: The received frame.
    ///   - connectionID: The connection that sent the frame.
    /// - Returns: Optional response frame to send back.
    /// - Throws: ``J2KError`` if frame processing fails.
    public func handleFrame(
        _ frame: JPIPWebSocketFrame,
        from connectionID: String
    ) async throws -> JPIPWebSocketFrame? {
        guard isRunning else {
            throw J2KError.invalidState("Server is not running")
        }

        guard let connection = connections[connectionID] else {
            throw J2KError.invalidParameter(
                "Unknown connection: \(connectionID)"
            )
        }

        await connection.recordFrameReceived(size: frame.payload.count + 9)
        statistics.framesReceived += 1
        statistics.totalBytesReceived += frame.payload.count + 9

        switch frame.type {
        case .request:
            return try await handleRequestFrame(
                frame, connection: connection
            )
        case .ping:
            return handlePingFrame(frame)
        case .pong:
            await connection.recordPongReceived()
            return nil
        case .control:
            return try await handleControlFrame(
                frame, connection: connection
            )
        default:
            return nil
        }
    }

    /// Handles a request frame by forwarding to the JPIP server.
    private func handleRequestFrame(
        _ frame: JPIPWebSocketFrame,
        connection: JPIPWebSocketConnection
    ) async throws -> JPIPWebSocketFrame {
        guard let request = encoder.decodeRequest(from: frame) else {
            let errorPayload = Data("Invalid request format".utf8)
            return JPIPWebSocketFrame(
                type: .error,
                payload: errorPayload,
                requestID: frame.requestID
            )
        }

        // Process via underlying JPIP server
        let response = try await jpipServer.handleRequest(request)

        // If this creates a new session, bind it to the connection
        if request.cnew != nil, let channelID = response.channelID {
            await connection.bindSession(channelID)
            sessionConnections[channelID] = connection.connectionID
        }

        // Encode response as WebSocket frame
        let responseFrame = encoder.encodeResponse(
            response,
            requestID: frame.requestID ?? 0
        )

        let serialized = responseFrame.serialize()
        await connection.recordFrameSent(size: serialized.count)
        statistics.framesSent += 1
        statistics.totalBytesSent += serialized.count

        return responseFrame
    }

    /// Handles a ping frame by returning a pong.
    private func handlePingFrame(
        _ frame: JPIPWebSocketFrame
    ) -> JPIPWebSocketFrame {
        JPIPWebSocketFrame(
            type: .pong,
            payload: frame.payload,
            requestID: frame.requestID
        )
    }

    /// Handles a control frame (session management).
    private func handleControlFrame(
        _ frame: JPIPWebSocketFrame,
        connection: JPIPWebSocketConnection
    ) async throws -> JPIPWebSocketFrame? {
        guard let command = String(data: frame.payload, encoding: .utf8) else {
            return nil
        }

        if command.hasPrefix("close-session:") {
            let sessionID = String(command.dropFirst("close-session:".count))
            await jpipServer.closeSession(sessionID)
            sessionConnections.removeValue(forKey: sessionID)
            return JPIPWebSocketFrame(
                type: .control,
                payload: Data("session-closed:\(sessionID)".utf8),
                requestID: frame.requestID
            )
        }

        return nil
    }

    // MARK: - Server Push

    /// Pushes a data bin to a specific connection.
    ///
    /// Used for server-initiated delivery of data bins without client request.
    ///
    /// - Parameters:
    ///   - dataBin: The data bin to push.
    ///   - connectionID: The target connection.
    /// - Returns: The serialized frame data, or nil if connection not found.
    public func pushDataBin(
        _ dataBin: JPIPDataBin,
        to connectionID: String
    ) async -> Data? {
        guard configuration.enableServerPush else { return nil }
        guard let connection = connections[connectionID] else { return nil }

        let frame = encoder.encodeDataBin(dataBin)
        let serialized = frame.serialize()

        await connection.recordFrameSent(size: serialized.count)
        statistics.framesSent += 1
        statistics.dataBinsPushed += 1
        statistics.totalBytesSent += serialized.count

        return serialized
    }

    /// Pushes a data bin to all connections bound to a session.
    ///
    /// - Parameters:
    ///   - dataBin: The data bin to push.
    ///   - sessionID: The target session.
    /// - Returns: Number of connections the data bin was pushed to.
    public func pushDataBinToSession(
        _ dataBin: JPIPDataBin,
        sessionID: String
    ) async -> Int {
        guard configuration.enableServerPush else { return 0 }
        guard let connectionID = sessionConnections[sessionID] else { return 0 }

        if await pushDataBin(dataBin, to: connectionID) != nil {
            return 1
        }
        return 0
    }

    // MARK: - Connection Health

    /// Sends keepalive pings to all active connections.
    ///
    /// - Returns: Array of (connectionID, serialized ping frame) tuples.
    public func sendKeepalivePings() async -> [(String, Data)] {
        var pings: [(String, Data)] = []

        let pingFrame = JPIPWebSocketFrame(
            type: .ping,
            payload: Data("keepalive".utf8)
        )
        let serialized = pingFrame.serialize()

        for (connectionID, connection) in connections {
            guard await connection.state == .connected else { continue }
            await connection.recordPingSent()
            await connection.recordFrameSent(size: serialized.count)
            pings.append((connectionID, serialized))
            statistics.keepalivePingsSent += 1
        }

        return pings
    }

    /// Performs health check on all connections.
    ///
    /// Closes connections that have exceeded the timeout.
    ///
    /// - Returns: Array of connection IDs that were closed.
    public func performHealthCheck() async -> [String] {
        var closedIDs: [String] = []

        for (connectionID, connection) in connections {
            let healthy = await connection.isHealthy(
                timeout: configuration.connectionTimeout
            )
            if !healthy {
                await connection.close()
                connections.removeValue(forKey: connectionID)

                // Remove session mapping
                if let sessionID = await connection.sessionID {
                    sessionConnections.removeValue(forKey: sessionID)
                    await jpipServer.closeSession(sessionID)
                }

                closedIDs.append(connectionID)
                statistics.timeoutDisconnections += 1
            }
        }

        statistics.activeConnections = connections.count
        return closedIDs
    }

    /// Closes a specific WebSocket connection.
    ///
    /// - Parameter connectionID: The connection to close.
    public func closeConnection(_ connectionID: String) async {
        guard let connection = connections.removeValue(forKey: connectionID) else {
            return
        }

        if let sessionID = await connection.sessionID {
            sessionConnections.removeValue(forKey: sessionID)
            await jpipServer.closeSession(sessionID)
        }

        await connection.close()
        statistics.activeConnections = connections.count
    }

    // MARK: - Monitoring

    /// Gets the number of active connections.
    ///
    /// - Returns: Number of active WebSocket connections.
    public func getActiveConnectionCount() -> Int {
        connections.count
    }

    /// Gets information about all active connections.
    ///
    /// - Returns: Array of connection info structs.
    public func getConnectionInfos() async -> [JPIPWebSocketConnection.ConnectionInfo] {
        var infos: [JPIPWebSocketConnection.ConnectionInfo] = []
        for (_, connection) in connections {
            infos.append(await connection.getInfo())
        }
        return infos
    }

    /// Gets the underlying JPIP server statistics.
    ///
    /// - Returns: JPIP server statistics.
    public func getJPIPStatistics() async -> JPIPServer.Statistics {
        await jpipServer.getStatistics()
    }

    /// Gets the list of registered image names.
    ///
    /// - Returns: Array of registered image names.
    public func listRegisteredImages() async -> [String] {
        await jpipServer.listRegisteredImages()
    }
}
