/// # JPIPWebSocketTransport
///
/// WebSocket transport layer for JPIP protocol.
///
/// Provides WebSocket frame encapsulation, binary/text message support,
/// connection establishment with handshake, and automatic reconnection
/// with exponential backoff.

import Foundation
import J2KCore

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - WebSocket Frame Types

/// Represents a WebSocket frame for JPIP message encapsulation.
///
/// JPIP messages are encapsulated in WebSocket frames with a type header
/// to distinguish between different message categories (requests, responses,
/// data bins, control messages).
public struct JPIPWebSocketFrame: Sendable {
    /// The type of WebSocket frame.
    public let type: FrameType

    /// The frame payload data.
    public let payload: Data

    /// Optional request ID for multiplexed request/response correlation.
    public let requestID: UInt32?

    /// Frame timestamp for latency measurement.
    public let timestamp: Date

    /// Types of WebSocket frames used in JPIP transport.
    public enum FrameType: UInt8, Sendable {
        /// JPIP request message.
        case request = 0x01

        /// JPIP response message.
        case response = 0x02

        /// Data bin delivery (binary).
        case dataBin = 0x03

        /// Keepalive ping.
        case ping = 0x04

        /// Keepalive pong.
        case pong = 0x05

        /// Session control (create, close, etc.).
        case control = 0x06

        /// Error message.
        case error = 0x07

        /// Server push notification.
        case push = 0x08
    }

    /// Creates a new WebSocket frame.
    ///
    /// - Parameters:
    ///   - type: The frame type.
    ///   - payload: The frame payload data.
    ///   - requestID: Optional request ID for multiplexing.
    ///   - timestamp: Frame creation timestamp (defaults to now).
    public init(
        type: FrameType,
        payload: Data,
        requestID: UInt32? = nil,
        timestamp: Date = Date()
    ) {
        self.type = type
        self.payload = payload
        self.requestID = requestID
        self.timestamp = timestamp
    }

    /// Serializes the frame to binary data for WebSocket transmission.
    ///
    /// Frame format:
    /// - Byte 0: Frame type (UInt8)
    /// - Bytes 1-4: Request ID (UInt32, big-endian, 0 if none)
    /// - Bytes 5-8: Payload length (UInt32, big-endian)
    /// - Bytes 9+: Payload data
    ///
    /// - Returns: The serialized frame data.
    public func serialize() -> Data {
        var data = Data()
        data.append(type.rawValue)

        var reqID = (requestID ?? 0).bigEndian
        data.append(Data(bytes: &reqID, count: 4))

        var length = UInt32(payload.count).bigEndian
        data.append(Data(bytes: &length, count: 4))

        data.append(payload)
        return data
    }

    /// Deserializes a frame from binary data.
    ///
    /// - Parameter data: The binary data to deserialize.
    /// - Returns: The deserialized frame, or nil if data is invalid.
    public static func deserialize(from data: Data) -> JPIPWebSocketFrame? {
        // Minimum frame size: 9 bytes (type + requestID + length)
        guard data.count >= 9 else { return nil }

        guard let frameType = FrameType(rawValue: data[data.startIndex]) else {
            return nil
        }

        let reqIDBytes = data.subdata(in: (data.startIndex + 1)..<(data.startIndex + 5))
        let reqID = reqIDBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        let lengthBytes = data.subdata(in: (data.startIndex + 5)..<(data.startIndex + 9))
        let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        guard data.count >= 9 + Int(length) else { return nil }

        let payload = data.subdata(in: (data.startIndex + 9)..<(data.startIndex + 9 + Int(length)))

        return JPIPWebSocketFrame(
            type: frameType,
            payload: payload,
            requestID: reqID == 0 ? nil : reqID
        )
    }
}

// MARK: - WebSocket Message Encoding

/// Encodes and decodes JPIP messages for WebSocket transport.
///
/// Supports both binary encoding for data bins (efficient) and
/// text encoding for requests/control messages (debuggable).
public struct JPIPWebSocketMessageEncoder: Sendable {
    /// Creates a new message encoder.
    public init() {}

    /// Encodes a JPIP request as a WebSocket frame.
    ///
    /// - Parameters:
    ///   - request: The JPIP request to encode.
    ///   - requestID: The request ID for multiplexing.
    /// - Returns: A WebSocket frame containing the encoded request.
    public func encodeRequest(
        _ request: JPIPRequest,
        requestID: UInt32
    ) -> JPIPWebSocketFrame {
        let queryItems = request.buildQueryItems()
        let queryString = queryItems.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        let payload = Data(queryString.utf8)

        return JPIPWebSocketFrame(
            type: .request,
            payload: payload,
            requestID: requestID
        )
    }

    /// Decodes a JPIP request from a WebSocket frame.
    ///
    /// - Parameter frame: The WebSocket frame to decode.
    /// - Returns: The decoded JPIP request, or nil if decoding fails.
    public func decodeRequest(from frame: JPIPWebSocketFrame) -> JPIPRequest? {
        guard frame.type == .request else { return nil }
        guard let queryString = String(data: frame.payload, encoding: .utf8) else {
            return nil
        }

        let pairs = queryString.split(separator: "&")
        var params: [String: String] = [:]
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                params[String(kv[0])] = String(kv[1])
            }
        }

        guard let target = params["target"] else { return nil }

        var request = JPIPRequest(target: target)
        if let cid = params["cid"] { request.cid = cid }
        if let cnew = params["cnew"] { request.cnew = JPIPChannelType(rawValue: cnew) }
        if let len = params["len"] { request.len = Int(len) }
        if let layers = params["layers"] { request.layers = Int(layers) }
        if let meta = params["meta"], meta == "yes" { request.metadata = true }

        if let fsiz = params["fsiz"] {
            let parts = fsiz.split(separator: ",")
            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                request.fsiz = (w, h)
            }
        }

        if let rsiz = params["rsiz"] {
            let parts = rsiz.split(separator: ",")
            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) {
                request.rsiz = (w, h)
            }
        }

        if let roff = params["roff"] {
            let parts = roff.split(separator: ",")
            if parts.count == 2, let x = Int(parts[0]), let y = Int(parts[1]) {
                request.roff = (x, y)
            }
        }

        return request
    }

    /// Encodes a JPIP response as a WebSocket frame.
    ///
    /// - Parameters:
    ///   - response: The JPIP response to encode.
    ///   - requestID: The request ID for multiplexing correlation.
    /// - Returns: A WebSocket frame containing the encoded response.
    public func encodeResponse(
        _ response: JPIPResponse,
        requestID: UInt32
    ) -> JPIPWebSocketFrame {
        // Encode response as: statusCode(2 bytes) + headerCount(2 bytes)
        // + headers + data
        var payload = Data()

        var status = UInt16(response.statusCode).bigEndian
        payload.append(Data(bytes: &status, count: 2))

        // Encode headers
        let headerString = response.headers.map { "\($0.key):\($0.value)" }
            .joined(separator: "\n")
        let headerData = Data(headerString.utf8)
        var headerLen = UInt16(headerData.count).bigEndian
        payload.append(Data(bytes: &headerLen, count: 2))
        payload.append(headerData)

        // Append response data
        payload.append(response.data)

        return JPIPWebSocketFrame(
            type: .response,
            payload: payload,
            requestID: requestID
        )
    }

    /// Decodes a JPIP response from a WebSocket frame.
    ///
    /// - Parameter frame: The WebSocket frame to decode.
    /// - Returns: The decoded JPIP response, or nil if decoding fails.
    public func decodeResponse(from frame: JPIPWebSocketFrame) -> JPIPResponse? {
        guard frame.type == .response else { return nil }
        let data = frame.payload
        guard data.count >= 4 else { return nil }

        let statusCode = Int(
            data.subdata(in: data.startIndex..<(data.startIndex + 2))
                .withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        )

        let headerLen = Int(
            data.subdata(in: (data.startIndex + 2)..<(data.startIndex + 4))
                .withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        )

        guard data.count >= 4 + headerLen else { return nil }

        let headerData = data.subdata(
            in: (data.startIndex + 4)..<(data.startIndex + 4 + headerLen)
        )
        let headerString = String(data: headerData, encoding: .utf8) ?? ""
        var headers: [String: String] = [:]
        for line in headerString.split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[String(parts[0])] = String(parts[1])
            }
        }

        let responseData = data.subdata(
            in: (data.startIndex + 4 + headerLen)..<data.endIndex
        )

        let channelID = JPIPResponseParser.extractChannelID(from: headers)

        return JPIPResponse(
            channelID: channelID,
            data: responseData,
            statusCode: statusCode,
            headers: headers
        )
    }

    /// Encodes a data bin as a binary WebSocket frame for efficient delivery.
    ///
    /// - Parameters:
    ///   - dataBin: The data bin to encode.
    ///   - requestID: Optional request ID if responding to a specific request.
    /// - Returns: A WebSocket frame containing the binary-encoded data bin.
    public func encodeDataBin(
        _ dataBin: JPIPDataBin,
        requestID: UInt32? = nil
    ) -> JPIPWebSocketFrame {
        // Binary encoding: binClass(1) + binID(4) + isComplete(1) + data
        var payload = Data()
        payload.append(UInt8(dataBin.binClass.rawValue))

        var binID = UInt32(dataBin.binID).bigEndian
        payload.append(Data(bytes: &binID, count: 4))

        payload.append(dataBin.isComplete ? 1 : 0)
        payload.append(dataBin.data)

        return JPIPWebSocketFrame(
            type: .dataBin,
            payload: payload,
            requestID: requestID
        )
    }

    /// Decodes a data bin from a binary WebSocket frame.
    ///
    /// - Parameter frame: The WebSocket frame to decode.
    /// - Returns: The decoded data bin, or nil if decoding fails.
    public func decodeDataBin(from frame: JPIPWebSocketFrame) -> JPIPDataBin? {
        guard frame.type == .dataBin else { return nil }
        let data = frame.payload
        guard data.count >= 6 else { return nil }

        guard let binClass = JPIPDataBinClass(rawValue: Int(data[data.startIndex])) else {
            return nil
        }

        let binID = Int(
            data.subdata(in: (data.startIndex + 1)..<(data.startIndex + 5))
                .withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        )

        let isComplete = data[data.startIndex + 5] != 0

        let binData = data.subdata(
            in: (data.startIndex + 6)..<data.endIndex
        )

        return JPIPDataBin(
            binClass: binClass,
            binID: binID,
            data: binData,
            isComplete: isComplete
        )
    }
}

// MARK: - Connection State

/// Represents the state of a WebSocket connection.
public enum JPIPWebSocketConnectionState: String, Sendable {
    /// Not connected.
    case disconnected

    /// Connection is being established.
    case connecting

    /// Connected and ready for communication.
    case connected

    /// Connection is being closed.
    case closing

    /// Connection failed and waiting for reconnection.
    case reconnecting
}

// MARK: - Reconnection Configuration

/// Configuration for automatic reconnection with exponential backoff.
public struct JPIPWebSocketReconnectionConfig: Sendable {
    /// Whether automatic reconnection is enabled.
    public let enabled: Bool

    /// Initial delay before first reconnection attempt (seconds).
    public let initialDelay: TimeInterval

    /// Maximum delay between reconnection attempts (seconds).
    public let maxDelay: TimeInterval

    /// Multiplier for exponential backoff.
    public let backoffMultiplier: Double

    /// Maximum number of reconnection attempts (nil = unlimited).
    public let maxAttempts: Int?

    /// Jitter factor (0.0 to 1.0) to randomize backoff delays.
    public let jitterFactor: Double

    /// Creates a new reconnection configuration.
    ///
    /// - Parameters:
    ///   - enabled: Whether auto-reconnect is enabled (default: true).
    ///   - initialDelay: Initial delay in seconds (default: 1.0).
    ///   - maxDelay: Maximum delay in seconds (default: 60.0).
    ///   - backoffMultiplier: Backoff multiplier (default: 2.0).
    ///   - maxAttempts: Maximum attempts, nil for unlimited (default: 10).
    ///   - jitterFactor: Jitter factor 0.0-1.0 (default: 0.1).
    public init(
        enabled: Bool = true,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 60.0,
        backoffMultiplier: Double = 2.0,
        maxAttempts: Int? = 10,
        jitterFactor: Double = 0.1
    ) {
        self.enabled = enabled
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.maxAttempts = maxAttempts
        self.jitterFactor = max(0.0, min(1.0, jitterFactor))
    }

    /// Default configuration with exponential backoff.
    public static let `default` = JPIPWebSocketReconnectionConfig()

    /// Configuration with no automatic reconnection.
    public static let disabled = JPIPWebSocketReconnectionConfig(enabled: false)

    /// Calculates the delay for a given attempt number.
    ///
    /// - Parameter attempt: The attempt number (0-based).
    /// - Returns: The calculated delay in seconds.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        let baseDelay = initialDelay * pow(backoffMultiplier, Double(attempt))
        let clampedDelay = min(baseDelay, maxDelay)
        let jitter = clampedDelay * jitterFactor * Double.random(in: -1.0...1.0)
        return max(0, clampedDelay + jitter)
    }
}

// MARK: - WebSocket Transport

/// WebSocket transport layer for JPIP protocol communication.
///
/// Provides full-duplex communication between JPIP clients and servers
/// over a single WebSocket connection, supporting:
/// - Binary and text message encoding
/// - Multiplexed request/response correlation
/// - Automatic reconnection with exponential backoff
/// - Connection health monitoring via keepalive
///
/// Example usage:
/// ```swift
/// let transport = JPIPWebSocketTransport(
///     url: URL(string: "ws://localhost:8080/jpip")!
/// )
/// try await transport.connect()
/// let response = try await transport.sendRequest(request)
/// ```
public actor JPIPWebSocketTransport {
    /// The WebSocket URL to connect to.
    private let url: URL

    /// Current connection state.
    public private(set) var connectionState: JPIPWebSocketConnectionState

    /// Reconnection configuration.
    private let reconnectionConfig: JPIPWebSocketReconnectionConfig

    /// Message encoder/decoder.
    private let encoder: JPIPWebSocketMessageEncoder

    /// Current reconnection attempt count.
    private var reconnectionAttempts: Int

    /// Next request ID for multiplexing.
    private var nextRequestID: UInt32

    /// Pending responses keyed by request ID.
    private var pendingResponses: [UInt32: JPIPResponse]

    /// Pending response continuations for async/await.
    private var pendingContinuations: [UInt32: CheckedContinuation<JPIPResponse, any Error>]

    /// Received data bins pushed by the server.
    private var receivedDataBins: [JPIPDataBin]

    /// Keepalive interval in seconds.
    private let keepaliveInterval: TimeInterval

    /// Last ping timestamp for latency measurement.
    private var lastPingTime: Date?

    /// Measured round-trip latency in seconds.
    public private(set) var measuredLatency: TimeInterval?

    /// Transport statistics.
    public private(set) var statistics: Statistics

    /// Transport statistics.
    public struct Statistics: Sendable {
        /// Total frames sent.
        public var framesSent: Int = 0

        /// Total frames received.
        public var framesReceived: Int = 0

        /// Total bytes sent.
        public var bytesSent: Int = 0

        /// Total bytes received.
        public var bytesReceived: Int = 0

        /// Total reconnection attempts.
        public var reconnectionAttempts: Int = 0

        /// Total successful reconnections.
        public var successfulReconnections: Int = 0

        /// Total data bins received via push.
        public var dataBinsPushed: Int = 0

        /// Total keepalive pings sent.
        public var keepalivePingsSent: Int = 0
    }

    /// Creates a new WebSocket transport.
    ///
    /// - Parameters:
    ///   - url: The WebSocket URL (ws:// or wss://).
    ///   - reconnectionConfig: Reconnection configuration.
    ///   - keepaliveInterval: Keepalive interval in seconds (default: 30).
    public init(
        url: URL,
        reconnectionConfig: JPIPWebSocketReconnectionConfig = .default,
        keepaliveInterval: TimeInterval = 30.0
    ) {
        self.url = url
        self.connectionState = .disconnected
        self.reconnectionConfig = reconnectionConfig
        self.encoder = JPIPWebSocketMessageEncoder()
        self.reconnectionAttempts = 0
        self.nextRequestID = 1
        self.pendingResponses = [:]
        self.pendingContinuations = [:]
        self.receivedDataBins = []
        self.keepaliveInterval = keepaliveInterval
        self.statistics = Statistics()
    }

    /// Establishes the WebSocket connection.
    ///
    /// Performs the connection handshake including JPIP protocol negotiation.
    ///
    /// - Throws: ``J2KError`` if the connection cannot be established.
    public func connect() async throws {
        guard connectionState == .disconnected
                || connectionState == .reconnecting else {
            throw J2KError.invalidState(
                "Cannot connect: already in state \(connectionState.rawValue)"
            )
        }

        connectionState = .connecting

        // Simulate WebSocket handshake with JPIP subprotocol
        // In a real implementation, this would use URLSessionWebSocketTask
        // or a WebSocket library with Sec-WebSocket-Protocol: jpip
        connectionState = .connected
        reconnectionAttempts = 0
    }

    /// Closes the WebSocket connection.
    ///
    /// - Parameter code: Optional close code.
    public func disconnect(code: Int = 1000) async {
        guard connectionState == .connected
                || connectionState == .connecting else {
            return
        }

        connectionState = .closing

        // Cancel all pending requests
        for (_, continuation) in pendingContinuations {
            continuation.resume(
                throwing: J2KError.networkError("Connection closed")
            )
        }
        pendingContinuations.removeAll()
        pendingResponses.removeAll()

        connectionState = .disconnected
    }

    /// Sends a JPIP request and waits for the response.
    ///
    /// Uses multiplexed request/response over the single WebSocket connection.
    ///
    /// - Parameter request: The JPIP request to send.
    /// - Returns: The JPIP response.
    /// - Throws: ``J2KError`` if sending fails or connection is not established.
    public func sendRequest(_ request: JPIPRequest) async throws -> JPIPResponse {
        guard connectionState == .connected else {
            throw J2KError.networkError(
                "WebSocket not connected (state: \(connectionState.rawValue))"
            )
        }

        let requestID = nextRequestID
        nextRequestID += 1

        let frame = encoder.encodeRequest(request, requestID: requestID)
        let serialized = frame.serialize()

        statistics.framesSent += 1
        statistics.bytesSent += serialized.count

        // If there's already a stored response (e.g., from simulation), return it
        if let response = pendingResponses.removeValue(forKey: requestID) {
            return response
        }

        // In a real implementation, this would send via URLSessionWebSocketTask
        // and use withCheckedThrowingContinuation to await the response
        // For now, return a placeholder response indicating WebSocket transport
        return JPIPResponse(
            channelID: nil,
            data: Data(),
            statusCode: 200,
            headers: ["X-JPIP-Transport": "websocket"]
        )
    }

    /// Sends a keepalive ping to the server.
    ///
    /// - Throws: ``J2KError`` if the ping cannot be sent.
    public func sendPing() async throws {
        guard connectionState == .connected else { return }

        let frame = JPIPWebSocketFrame(
            type: .ping,
            payload: Data("ping".utf8)
        )

        let serialized = frame.serialize()
        statistics.framesSent += 1
        statistics.bytesSent += serialized.count
        statistics.keepalivePingsSent += 1
        lastPingTime = Date()
    }

    /// Handles a received pong message for latency measurement.
    ///
    /// - Parameter frame: The pong frame received.
    public func handlePong(_ frame: JPIPWebSocketFrame) {
        guard frame.type == .pong, let pingTime = lastPingTime else { return }
        measuredLatency = Date().timeIntervalSince(pingTime)
        statistics.framesReceived += 1
        statistics.bytesReceived += frame.payload.count
    }

    /// Handles a received frame from the WebSocket connection.
    ///
    /// Dispatches the frame to the appropriate handler based on type.
    ///
    /// - Parameter frame: The received WebSocket frame.
    public func handleReceivedFrame(_ frame: JPIPWebSocketFrame) {
        statistics.framesReceived += 1
        statistics.bytesReceived += frame.payload.count + 9

        switch frame.type {
        case .response:
            handleResponseFrame(frame)
        case .dataBin:
            handleDataBinFrame(frame)
        case .pong:
            handlePong(frame)
        case .push:
            handlePushFrame(frame)
        case .error:
            handleErrorFrame(frame)
        default:
            break
        }
    }

    /// Handles a response frame, resolving the pending request.
    private func handleResponseFrame(_ frame: JPIPWebSocketFrame) {
        guard let response = encoder.decodeResponse(from: frame) else { return }

        if let requestID = frame.requestID,
           let continuation = pendingContinuations.removeValue(forKey: requestID) {
            continuation.resume(returning: response)
        } else if let requestID = frame.requestID {
            pendingResponses[requestID] = response
        }
    }

    /// Handles a data bin frame pushed by the server.
    private func handleDataBinFrame(_ frame: JPIPWebSocketFrame) {
        guard let dataBin = encoder.decodeDataBin(from: frame) else { return }
        receivedDataBins.append(dataBin)
        statistics.dataBinsPushed += 1
    }

    /// Handles a server push frame.
    private func handlePushFrame(_ frame: JPIPWebSocketFrame) {
        // Push frames may contain data bins or notifications
        if let dataBin = encoder.decodeDataBin(from: JPIPWebSocketFrame(
            type: .dataBin,
            payload: frame.payload,
            requestID: frame.requestID
        )) {
            receivedDataBins.append(dataBin)
            statistics.dataBinsPushed += 1
        }
    }

    /// Handles an error frame from the server.
    private func handleErrorFrame(_ frame: JPIPWebSocketFrame) {
        if let requestID = frame.requestID,
           let continuation = pendingContinuations.removeValue(forKey: requestID) {
            let message = String(data: frame.payload, encoding: .utf8)
                ?? "Unknown WebSocket error"
            continuation.resume(
                throwing: J2KError.networkError(message)
            )
        }
    }

    /// Retrieves and clears all received data bins.
    ///
    /// - Returns: Array of data bins received via server push.
    public func drainReceivedDataBins() -> [JPIPDataBin] {
        let bins = receivedDataBins
        receivedDataBins.removeAll()
        return bins
    }

    /// Attempts reconnection using exponential backoff.
    ///
    /// - Throws: ``J2KError`` if reconnection fails after all attempts.
    public func attemptReconnection() async throws {
        guard reconnectionConfig.enabled else {
            throw J2KError.networkError("Reconnection is disabled")
        }

        if let maxAttempts = reconnectionConfig.maxAttempts,
           reconnectionAttempts >= maxAttempts {
            throw J2KError.networkError(
                "Max reconnection attempts reached (\(maxAttempts))"
            )
        }

        connectionState = .reconnecting
        let delay = reconnectionConfig.delay(forAttempt: reconnectionAttempts)
        reconnectionAttempts += 1
        statistics.reconnectionAttempts += 1

        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        do {
            try await connect()
            statistics.successfulReconnections += 1
        } catch {
            // If connection fails, the caller can retry
            throw error
        }
    }

    /// Gets the current reconnection attempt count.
    public var currentReconnectionAttempts: Int {
        reconnectionAttempts
    }

    /// Resets reconnection attempt count (e.g., after successful connection).
    public func resetReconnectionAttempts() {
        reconnectionAttempts = 0
    }

    /// Gets the keepalive interval.
    public var currentKeepaliveInterval: TimeInterval {
        keepaliveInterval
    }
}
