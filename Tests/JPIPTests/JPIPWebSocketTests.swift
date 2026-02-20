/// # JPIPWebSocketTests
///
/// Tests for JPIP WebSocket transport, client, and server implementations.

import XCTest
@testable import JPIP
@testable import J2KCore

// MARK: - WebSocket Frame Tests

final class JPIPWebSocketFrameTests: XCTestCase {
    // MARK: - Frame Serialization

    func testFrameSerializationRoundTrip() {
        let payload = Data("test payload".utf8)
        let frame = JPIPWebSocketFrame(
            type: .request,
            payload: payload,
            requestID: 42
        )

        let serialized = frame.serialize()
        let deserialized = JPIPWebSocketFrame.deserialize(from: serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.type, .request)
        XCTAssertEqual(deserialized?.payload, payload)
        XCTAssertEqual(deserialized?.requestID, 42)
    }

    func testFrameSerializationWithoutRequestID() {
        let payload = Data("no id".utf8)
        let frame = JPIPWebSocketFrame(
            type: .dataBin,
            payload: payload,
            requestID: nil
        )

        let serialized = frame.serialize()
        let deserialized = JPIPWebSocketFrame.deserialize(from: serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.type, .dataBin)
        XCTAssertEqual(deserialized?.payload, payload)
        XCTAssertNil(deserialized?.requestID)
    }

    func testFrameSerializationEmptyPayload() {
        let frame = JPIPWebSocketFrame(
            type: .ping,
            payload: Data()
        )

        let serialized = frame.serialize()
        XCTAssertEqual(serialized.count, 9) // header only
        let deserialized = JPIPWebSocketFrame.deserialize(from: serialized)
        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.type, .ping)
        XCTAssertTrue(deserialized?.payload.isEmpty ?? false)
    }

    func testFrameDeserializationInvalidData() {
        // Too short
        XCTAssertNil(JPIPWebSocketFrame.deserialize(from: Data([0x01])))
        XCTAssertNil(JPIPWebSocketFrame.deserialize(from: Data()))
    }

    func testFrameDeserializationInvalidType() {
        var data = Data()
        data.append(0xFF) // Invalid type
        data.append(contentsOf: [0, 0, 0, 0]) // requestID
        data.append(contentsOf: [0, 0, 0, 0]) // length
        XCTAssertNil(JPIPWebSocketFrame.deserialize(from: data))
    }

    func testAllFrameTypes() {
        let types: [JPIPWebSocketFrame.FrameType] = [
            .request, .response, .dataBin, .ping, .pong,
            .control, .error, .push
        ]

        for frameType in types {
            let frame = JPIPWebSocketFrame(
                type: frameType,
                payload: Data("test".utf8)
            )
            let serialized = frame.serialize()
            let deserialized = JPIPWebSocketFrame.deserialize(from: serialized)
            XCTAssertNotNil(deserialized, "Failed for type: \(frameType)")
            XCTAssertEqual(deserialized?.type, frameType)
        }
    }

    func testLargePayloadSerialization() {
        let payload = Data(repeating: 0xAB, count: 65536)
        let frame = JPIPWebSocketFrame(
            type: .dataBin,
            payload: payload,
            requestID: 1
        )

        let serialized = frame.serialize()
        let deserialized = JPIPWebSocketFrame.deserialize(from: serialized)

        XCTAssertNotNil(deserialized)
        XCTAssertEqual(deserialized?.payload.count, 65536)
        XCTAssertEqual(deserialized?.payload, payload)
    }
}

// MARK: - Message Encoder Tests

final class JPIPWebSocketMessageEncoderTests: XCTestCase {
    let encoder = JPIPWebSocketMessageEncoder()

    // MARK: - Request Encoding

    func testEncodeDecodeRequest() {
        var request = JPIPRequest(target: "image.jp2")
        request.cid = "channel-1"
        request.layers = 5

        let frame = encoder.encodeRequest(request, requestID: 10)
        XCTAssertEqual(frame.type, .request)
        XCTAssertEqual(frame.requestID, 10)

        let decoded = encoder.decodeRequest(from: frame)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.target, "image.jp2")
        XCTAssertEqual(decoded?.cid, "channel-1")
        XCTAssertEqual(decoded?.layers, 5)
    }

    func testEncodeDecodeRegionRequest() {
        let request = JPIPRequest.regionRequest(
            target: "test.jp2",
            x: 100,
            y: 200,
            width: 300,
            height: 400
        )

        let frame = encoder.encodeRequest(request, requestID: 1)
        let decoded = encoder.decodeRequest(from: frame)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.target, "test.jp2")
        XCTAssertEqual(decoded?.roff?.x, 100)
        XCTAssertEqual(decoded?.roff?.y, 200)
        XCTAssertEqual(decoded?.rsiz?.width, 300)
        XCTAssertEqual(decoded?.rsiz?.height, 400)
    }

    func testEncodeDecodeMetadataRequest() {
        let request = JPIPRequest.metadataRequest(target: "meta.jp2")

        let frame = encoder.encodeRequest(request, requestID: 2)
        let decoded = encoder.decodeRequest(from: frame)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.target, "meta.jp2")
        XCTAssertEqual(decoded?.metadata, true)
    }

    func testDecodeRequestFromWrongFrameType() {
        let frame = JPIPWebSocketFrame(
            type: .response,
            payload: Data()
        )
        XCTAssertNil(encoder.decodeRequest(from: frame))
    }

    // MARK: - Response Encoding

    func testEncodeDecodeResponse() {
        let response = JPIPResponse(
            channelID: "ch-1",
            data: Data("response data".utf8),
            statusCode: 200,
            headers: ["JPIP-cnew": "cid=ch-1,transport=ws"]
        )

        let frame = encoder.encodeResponse(response, requestID: 5)
        XCTAssertEqual(frame.type, .response)
        XCTAssertEqual(frame.requestID, 5)

        let decoded = encoder.decodeResponse(from: frame)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.statusCode, 200)
        XCTAssertEqual(decoded?.data, Data("response data".utf8))
    }

    func testDecodeResponseFromWrongFrameType() {
        let frame = JPIPWebSocketFrame(
            type: .request,
            payload: Data()
        )
        XCTAssertNil(encoder.decodeResponse(from: frame))
    }

    // MARK: - Data Bin Encoding

    func testEncodeDecodeDataBin() {
        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 42,
            data: Data(repeating: 0xAA, count: 1024),
            isComplete: true
        )

        let frame = encoder.encodeDataBin(dataBin, requestID: 7)
        XCTAssertEqual(frame.type, .dataBin)
        XCTAssertEqual(frame.requestID, 7)

        let decoded = encoder.decodeDataBin(from: frame)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.binClass, .precinct)
        XCTAssertEqual(decoded?.binID, 42)
        XCTAssertEqual(decoded?.data.count, 1024)
        XCTAssertEqual(decoded?.isComplete, true)
    }

    func testEncodeDecodeIncompleteDataBin() {
        let dataBin = JPIPDataBin(
            binClass: .tileHeader,
            binID: 3,
            data: Data([0x01, 0x02, 0x03]),
            isComplete: false
        )

        let frame = encoder.encodeDataBin(dataBin)
        let decoded = encoder.decodeDataBin(from: frame)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.binClass, .tileHeader)
        XCTAssertEqual(decoded?.isComplete, false)
    }

    func testAllDataBinClasses() {
        let classes: [JPIPDataBinClass] = [
            .mainHeader, .tileHeader, .precinct,
            .tile, .extendedPrecinct, .metadata
        ]

        for binClass in classes {
            let dataBin = JPIPDataBin(
                binClass: binClass,
                binID: 1,
                data: Data([0xFF]),
                isComplete: true
            )
            let frame = encoder.encodeDataBin(dataBin)
            let decoded = encoder.decodeDataBin(from: frame)
            XCTAssertNotNil(decoded, "Failed for binClass: \(binClass)")
            XCTAssertEqual(decoded?.binClass, binClass)
        }
    }

    func testDecodeDataBinFromWrongFrameType() {
        let frame = JPIPWebSocketFrame(
            type: .ping,
            payload: Data()
        )
        XCTAssertNil(encoder.decodeDataBin(from: frame))
    }
}

// MARK: - Reconnection Config Tests

final class JPIPWebSocketReconnectionTests: XCTestCase {
    func testDefaultConfiguration() {
        let config = JPIPWebSocketReconnectionConfig.default
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.initialDelay, 1.0)
        XCTAssertEqual(config.maxDelay, 60.0)
        XCTAssertEqual(config.backoffMultiplier, 2.0)
        XCTAssertEqual(config.maxAttempts, 10)
    }

    func testDisabledConfiguration() {
        let config = JPIPWebSocketReconnectionConfig.disabled
        XCTAssertFalse(config.enabled)
    }

    func testExponentialBackoffDelay() {
        let config = JPIPWebSocketReconnectionConfig(
            initialDelay: 1.0,
            maxDelay: 60.0,
            backoffMultiplier: 2.0,
            jitterFactor: 0.0 // No jitter for deterministic testing
        )

        // Base delays: 1, 2, 4, 8, 16, 32, 60 (capped)
        XCTAssertEqual(config.delay(forAttempt: 0), 1.0, accuracy: 0.01)
        XCTAssertEqual(config.delay(forAttempt: 1), 2.0, accuracy: 0.01)
        XCTAssertEqual(config.delay(forAttempt: 2), 4.0, accuracy: 0.01)
        XCTAssertEqual(config.delay(forAttempt: 3), 8.0, accuracy: 0.01)
        XCTAssertEqual(config.delay(forAttempt: 5), 32.0, accuracy: 0.01)
        XCTAssertEqual(config.delay(forAttempt: 6), 60.0, accuracy: 0.01) // capped
        XCTAssertEqual(config.delay(forAttempt: 10), 60.0, accuracy: 0.01) // capped
    }

    func testJitterKeepsDelayReasonable() {
        let config = JPIPWebSocketReconnectionConfig(
            initialDelay: 1.0,
            maxDelay: 60.0,
            backoffMultiplier: 2.0,
            jitterFactor: 0.5
        )

        // With jitter 0.5, delay for attempt 0 should be roughly 0.5-1.5
        for _ in 0..<20 {
            let delay = config.delay(forAttempt: 0)
            XCTAssertGreaterThanOrEqual(delay, 0.0)
            XCTAssertLessThanOrEqual(delay, 2.0)
        }
    }

    func testJitterFactorClamping() {
        let config = JPIPWebSocketReconnectionConfig(jitterFactor: 2.0)
        XCTAssertEqual(config.jitterFactor, 1.0) // Clamped to max 1.0

        let config2 = JPIPWebSocketReconnectionConfig(jitterFactor: -1.0)
        XCTAssertEqual(config2.jitterFactor, 0.0) // Clamped to min 0.0
    }
}

// MARK: - WebSocket Transport Tests

final class JPIPWebSocketTransportTests: XCTestCase {
    func testTransportInitialization() async {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)

        let state = await transport.connectionState
        XCTAssertEqual(state, .disconnected)

        let stats = await transport.statistics
        XCTAssertEqual(stats.framesSent, 0)
        XCTAssertEqual(stats.framesReceived, 0)
    }

    func testConnectAndDisconnect() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)

        try await transport.connect()
        var state = await transport.connectionState
        XCTAssertEqual(state, .connected)

        await transport.disconnect()
        state = await transport.connectionState
        XCTAssertEqual(state, .disconnected)
    }

    func testDoubleConnectFails() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)

        try await transport.connect()

        do {
            try await transport.connect()
            XCTFail("Expected error for double connect")
        } catch {
            // Expected
        }

        await transport.disconnect()
    }

    func testSendRequestRequiresConnection() async {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)
        let request = JPIPRequest(target: "test.jp2")

        do {
            _ = try await transport.sendRequest(request)
            XCTFail("Expected error when not connected")
        } catch {
            // Expected
        }
    }

    func testSendRequestWhenConnected() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)

        try await transport.connect()
        let request = JPIPRequest(target: "test.jp2")
        let response = try await transport.sendRequest(request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.headers["X-JPIP-Transport"], "websocket")

        await transport.disconnect()
    }

    func testSendPing() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)

        try await transport.connect()
        try await transport.sendPing()

        let stats = await transport.statistics
        XCTAssertEqual(stats.keepalivePingsSent, 1)

        await transport.disconnect()
    }

    func testHandleReceivedDataBin() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)
        let encoder = JPIPWebSocketMessageEncoder()

        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 5,
            data: Data([0x01, 0x02]),
            isComplete: true
        )
        let frame = encoder.encodeDataBin(dataBin)

        await transport.handleReceivedFrame(frame)

        let bins = await transport.drainReceivedDataBins()
        XCTAssertEqual(bins.count, 1)
        XCTAssertEqual(bins.first?.binClass, .precinct)
        XCTAssertEqual(bins.first?.binID, 5)

        let stats = await transport.statistics
        XCTAssertEqual(stats.dataBinsPushed, 1)
    }

    func testDrainClearsDataBins() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)
        let encoder = JPIPWebSocketMessageEncoder()

        let dataBin = JPIPDataBin(
            binClass: .tile,
            binID: 1,
            data: Data([0xFF]),
            isComplete: false
        )
        let frame = encoder.encodeDataBin(dataBin)

        await transport.handleReceivedFrame(frame)
        let bins1 = await transport.drainReceivedDataBins()
        XCTAssertEqual(bins1.count, 1)

        // Second drain should be empty
        let bins2 = await transport.drainReceivedDataBins()
        XCTAssertEqual(bins2.count, 0)
    }

    func testReconnectionAttemptTracking() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let config = JPIPWebSocketReconnectionConfig(
            enabled: true,
            initialDelay: 0.01, // Very short for testing
            maxAttempts: 3,
            jitterFactor: 0.0
        )
        let transport = JPIPWebSocketTransport(
            url: url,
            reconnectionConfig: config
        )

        try await transport.attemptReconnection()
        var attempts = await transport.currentReconnectionAttempts
        // After successful reconnection, attempts are reset to 0
        XCTAssertEqual(attempts, 0)

        let stats = await transport.statistics
        XCTAssertEqual(stats.reconnectionAttempts, 1)
        XCTAssertEqual(stats.successfulReconnections, 1)

        await transport.resetReconnectionAttempts()
        attempts = await transport.currentReconnectionAttempts
        XCTAssertEqual(attempts, 0)
    }

    func testReconnectionDisabledFails() async {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let config = JPIPWebSocketReconnectionConfig.disabled
        let transport = JPIPWebSocketTransport(
            url: url,
            reconnectionConfig: config
        )

        do {
            try await transport.attemptReconnection()
            XCTFail("Expected error when reconnection is disabled")
        } catch {
            // Expected
        }
    }

    func testHandlePongMeasuresLatency() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let transport = JPIPWebSocketTransport(url: url)

        try await transport.connect()
        try await transport.sendPing()

        // Simulate pong response
        let pongFrame = JPIPWebSocketFrame(
            type: .pong,
            payload: Data("pong".utf8)
        )
        await transport.handlePong(pongFrame)

        let latency = await transport.measuredLatency
        XCTAssertNotNil(latency)
        XCTAssertGreaterThanOrEqual(latency ?? -1, 0.0)

        await transport.disconnect()
    }
}

// MARK: - WebSocket Client Tests

final class JPIPWebSocketClientTests: XCTestCase {
    func testClientInitialization() async {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let client = JPIPWebSocketClient(serverURL: url)

        let fallback = await client.isUsingHTTPFallback
        XCTAssertFalse(fallback)

        let stats = await client.statistics
        XCTAssertEqual(stats.webSocketRequests, 0)
        XCTAssertEqual(stats.httpFallbackRequests, 0)
    }

    func testClientConnects() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let client = JPIPWebSocketClient(serverURL: url)

        try await client.connect()
        let state = await client.getConnectionState()
        XCTAssertEqual(state, .connected)

        try await client.close()
    }

    func testClientSendRequest() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let client = JPIPWebSocketClient(serverURL: url)

        try await client.connect()
        let request = JPIPRequest(target: "test.jp2")
        let response = try await client.sendRequest(request)
        XCTAssertEqual(response.statusCode, 200)

        let stats = await client.statistics
        XCTAssertEqual(stats.webSocketRequests, 1)

        try await client.close()
    }

    func testClientHTTPFallbackConfiguration() async {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let config = JPIPWebSocketClientConfiguration(
            enableHTTPFallback: true,
            maxConcurrentRequests: 8
        )
        let client = JPIPWebSocketClient(
            serverURL: url,
            configuration: config
        )

        let fallback = await client.isUsingHTTPFallback
        XCTAssertFalse(fallback)
    }

    func testClientDrainPushedDataBins() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let client = JPIPWebSocketClient(serverURL: url)

        try await client.connect()
        let bins = await client.drainPushedDataBins()
        XCTAssertEqual(bins.count, 0) // No pushed bins yet

        try await client.close()
    }

    func testClientSendPing() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let client = JPIPWebSocketClient(serverURL: url)

        try await client.connect()
        try await client.sendPing()
        // No error means success

        try await client.close()
    }

    func testClientGetSession() async throws {
        let url = URL(string: "ws://localhost:8080/jpip")!
        let client = JPIPWebSocketClient(serverURL: url)

        try await client.connect()
        let session = await client.getSession()
        XCTAssertNil(session) // No session created yet

        try await client.close()
    }
}

// MARK: - WebSocket Server Tests

final class JPIPWebSocketServerTests: XCTestCase {
    func testServerInitialization() async {
        let server = JPIPWebSocketServer(port: 9090)
        let count = await server.getActiveConnectionCount()
        XCTAssertEqual(count, 0)

        let stats = await server.statistics
        XCTAssertEqual(stats.totalConnections, 0)
        XCTAssertEqual(stats.activeConnections, 0)
    }

    func testServerStartStop() async throws {
        let server = JPIPWebSocketServer(port: 9091)
        try await server.start()
        try await server.stop()
    }

    func testServerDoubleStartFails() async throws {
        let server = JPIPWebSocketServer(port: 9092)
        try await server.start()

        do {
            try await server.start()
            XCTFail("Expected error for double start")
        } catch {
            // Expected
        }

        try await server.stop()
    }

    func testServerDoubleStopFails() async throws {
        let server = JPIPWebSocketServer(port: 9093)

        do {
            try await server.stop()
            XCTFail("Expected error for stopping non-running server")
        } catch {
            // Expected
        }
    }

    func testUpgradeRequestValidation() async throws {
        let server = JPIPWebSocketServer(port: 9094)
        try await server.start()

        // Valid upgrade request
        let validHeaders: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "Upgrade",
            "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
            "Sec-WebSocket-Protocol": "jpip"
        ]

        let result = await server.handleUpgradeRequest(headers: validHeaders)
        XCTAssertTrue(result.isSuccess)
        XCTAssertNotNil(result.connectionID)
        XCTAssertNil(result.error)

        let stats = await server.statistics
        XCTAssertEqual(stats.successfulUpgrades, 1)
        XCTAssertEqual(stats.activeConnections, 1)

        try await server.stop()
    }

    func testUpgradeRequestMissingHeaders() async throws {
        let server = JPIPWebSocketServer(port: 9095)
        try await server.start()

        // Missing Upgrade header
        let headers: [String: String] = [
            "Connection": "Upgrade"
        ]

        let result = await server.handleUpgradeRequest(headers: headers)
        XCTAssertFalse(result.isSuccess)
        XCTAssertNotNil(result.error)

        let stats = await server.statistics
        XCTAssertEqual(stats.failedUpgrades, 1)

        try await server.stop()
    }

    func testUpgradeRequestInvalidConnection() async throws {
        let server = JPIPWebSocketServer(port: 9096)
        try await server.start()

        let headers: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "keep-alive" // Wrong
        ]

        let result = await server.handleUpgradeRequest(headers: headers)
        XCTAssertFalse(result.isSuccess)

        try await server.stop()
    }

    func testUpgradeWhenNotRunning() async {
        let server = JPIPWebSocketServer(port: 9097)

        let result = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        XCTAssertFalse(result.isSuccess)
    }

    func testMaxConnectionsLimit() async throws {
        let config = JPIPWebSocketServerConfiguration(maxConnections: 2)
        let server = JPIPWebSocketServer(port: 9098, configuration: config)
        try await server.start()

        let headers: [String: String] = [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ]

        // First two should succeed
        let result1 = await server.handleUpgradeRequest(headers: headers)
        XCTAssertTrue(result1.isSuccess)

        let result2 = await server.handleUpgradeRequest(headers: headers)
        XCTAssertTrue(result2.isSuccess)

        // Third should fail
        let result3 = await server.handleUpgradeRequest(headers: headers)
        XCTAssertFalse(result3.isSuccess)

        try await server.stop()
    }

    func testUpgradeResponseHeaders() async {
        let server = JPIPWebSocketServer(port: 9099)
        let headers = await server.buildUpgradeResponseHeaders(
            acceptKey: "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )

        XCTAssertEqual(headers["Upgrade"], "websocket")
        XCTAssertEqual(headers["Connection"], "Upgrade")
        XCTAssertEqual(
            headers["Sec-WebSocket-Accept"],
            "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="
        )
        XCTAssertEqual(headers["Sec-WebSocket-Protocol"], "jpip")
    }

    func testHandleRequestFrame() async throws {
        let config = JPIPWebSocketServerConfiguration()
        let server = JPIPWebSocketServer(port: 9100, configuration: config)

        // Create a temp file for the image
        let tempDir = FileManager.default.temporaryDirectory
        let imageURL = tempDir.appendingPathComponent("\(UUID().uuidString).jp2")
        try Data("fake-image-data".utf8).write(to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }

        try await server.registerImage(name: "test.jp2", at: imageURL)
        try await server.start()

        // Establish a connection
        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        guard let connectionID = upgradeResult.connectionID else {
            XCTFail("Failed to establish connection")
            return
        }

        // Send a session creation request
        let encoder = JPIPWebSocketMessageEncoder()
        var request = JPIPRequest(target: "test.jp2")
        request.cnew = .http
        let requestFrame = encoder.encodeRequest(request, requestID: 1)

        let responseFrame = try await server.handleFrame(
            requestFrame,
            from: connectionID
        )

        XCTAssertNotNil(responseFrame)
        XCTAssertEqual(responseFrame?.type, .response)

        let stats = await server.statistics
        XCTAssertEqual(stats.framesReceived, 1)
        XCTAssertEqual(stats.framesSent, 1)

        try await server.stop()
    }

    func testHandlePingFrame() async throws {
        let server = JPIPWebSocketServer(port: 9101)
        try await server.start()

        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        guard let connectionID = upgradeResult.connectionID else {
            XCTFail("Failed to establish connection")
            return
        }

        let pingFrame = JPIPWebSocketFrame(
            type: .ping,
            payload: Data("keepalive".utf8)
        )

        let responseFrame = try await server.handleFrame(
            pingFrame,
            from: connectionID
        )

        XCTAssertNotNil(responseFrame)
        XCTAssertEqual(responseFrame?.type, .pong)
        XCTAssertEqual(responseFrame?.payload, Data("keepalive".utf8))

        try await server.stop()
    }

    func testPushDataBin() async throws {
        let server = JPIPWebSocketServer(port: 9102)
        try await server.start()

        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        guard let connectionID = upgradeResult.connectionID else {
            XCTFail("Failed to establish connection")
            return
        }

        let dataBin = JPIPDataBin(
            binClass: .precinct,
            binID: 10,
            data: Data(repeating: 0xBB, count: 512),
            isComplete: true
        )

        let result = await server.pushDataBin(dataBin, to: connectionID)
        XCTAssertNotNil(result)

        let stats = await server.statistics
        XCTAssertEqual(stats.dataBinsPushed, 1)

        try await server.stop()
    }

    func testPushDataBinDisabled() async throws {
        let config = JPIPWebSocketServerConfiguration(enableServerPush: false)
        let server = JPIPWebSocketServer(port: 9103, configuration: config)
        try await server.start()

        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        guard upgradeResult.isSuccess else {
            XCTFail("Failed to establish connection")
            return
        }

        let dataBin = JPIPDataBin(
            binClass: .tile,
            binID: 1,
            data: Data([0x01]),
            isComplete: true
        )

        let result = await server.pushDataBin(
            dataBin,
            to: upgradeResult.connectionID!
        )
        XCTAssertNil(result)

        try await server.stop()
    }

    func testSendKeepalivePings() async throws {
        let server = JPIPWebSocketServer(port: 9104)
        try await server.start()

        // Add a connection
        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        XCTAssertTrue(upgradeResult.isSuccess)

        let pings = await server.sendKeepalivePings()
        XCTAssertEqual(pings.count, 1)

        let stats = await server.statistics
        XCTAssertEqual(stats.keepalivePingsSent, 1)

        try await server.stop()
    }

    func testHealthCheckClosesTimedOutConnections() async throws {
        let config = JPIPWebSocketServerConfiguration(
            connectionTimeout: 0.0 // Immediate timeout for testing
        )
        let server = JPIPWebSocketServer(port: 9105, configuration: config)
        try await server.start()

        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        XCTAssertTrue(upgradeResult.isSuccess)

        // Wait a tiny bit for the timeout
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        let closedIDs = await server.performHealthCheck()
        XCTAssertEqual(closedIDs.count, 1)

        let count = await server.getActiveConnectionCount()
        XCTAssertEqual(count, 0)

        let stats = await server.statistics
        XCTAssertEqual(stats.timeoutDisconnections, 1)

        try await server.stop()
    }

    func testCloseConnection() async throws {
        let server = JPIPWebSocketServer(port: 9106)
        try await server.start()

        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        guard let connectionID = upgradeResult.connectionID else {
            XCTFail("Failed to establish connection")
            return
        }

        var count = await server.getActiveConnectionCount()
        XCTAssertEqual(count, 1)

        await server.closeConnection(connectionID)

        count = await server.getActiveConnectionCount()
        XCTAssertEqual(count, 0)

        try await server.stop()
    }

    func testConnectionInfos() async throws {
        let server = JPIPWebSocketServer(port: 9107)
        try await server.start()

        let upgradeResult = await server.handleUpgradeRequest(headers: [
            "Upgrade": "websocket",
            "Connection": "Upgrade"
        ])
        XCTAssertTrue(upgradeResult.isSuccess)

        let infos = await server.getConnectionInfos()
        XCTAssertEqual(infos.count, 1)
        XCTAssertEqual(infos.first?.state, .connected)

        try await server.stop()
    }
}

// MARK: - WebSocket Connection Tests

final class JPIPWebSocketConnectionTests: XCTestCase {
    func testConnectionInitialization() async {
        let conn = JPIPWebSocketConnection(connectionID: "test-conn")
        let state = await conn.state
        XCTAssertEqual(state, .connected)
        let sessionID = await conn.sessionID
        XCTAssertNil(sessionID)
        let framesSent = await conn.framesSent
        XCTAssertEqual(framesSent, 0)
        let framesReceived = await conn.framesReceived
        XCTAssertEqual(framesReceived, 0)
    }

    func testBindSession() async {
        let conn = JPIPWebSocketConnection(connectionID: "test-conn")
        await conn.bindSession("session-1")
        let sessionID = await conn.sessionID
        XCTAssertEqual(sessionID, "session-1")
    }

    func testRecordFrameStats() async {
        let conn = JPIPWebSocketConnection(connectionID: "test-conn")
        await conn.recordFrameSent(size: 100)
        await conn.recordFrameReceived(size: 200)

        let framesSent = await conn.framesSent
        XCTAssertEqual(framesSent, 1)
        let framesReceived = await conn.framesReceived
        XCTAssertEqual(framesReceived, 1)
        let bytesSent = await conn.bytesSent
        XCTAssertEqual(bytesSent, 100)
        let bytesReceived = await conn.bytesReceived
        XCTAssertEqual(bytesReceived, 200)
    }

    func testLatencyMeasurement() async {
        let conn = JPIPWebSocketConnection(connectionID: "test-conn")
        await conn.recordPingSent()
        await conn.recordPongReceived()

        let latency = await conn.latency
        XCTAssertNotNil(latency)
        XCTAssertGreaterThanOrEqual(latency ?? -1, 0.0)
    }

    func testHealthCheck() async {
        let conn = JPIPWebSocketConnection(connectionID: "test-conn")

        // Should be healthy with any reasonable timeout
        let healthy = await conn.isHealthy(timeout: 60.0)
        XCTAssertTrue(healthy)

        // Should be unhealthy with 0 timeout
        try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        let unhealthy = await conn.isHealthy(timeout: 0.0)
        XCTAssertFalse(unhealthy)
    }

    func testClose() async {
        let conn = JPIPWebSocketConnection(connectionID: "test-conn")
        await conn.bindSession("session-1")

        await conn.close()
        let state = await conn.state
        XCTAssertEqual(state, .disconnected)
        let sessionID = await conn.sessionID
        XCTAssertNil(sessionID)
    }

    func testGetInfo() async {
        let conn = JPIPWebSocketConnection(connectionID: "test-conn")
        await conn.bindSession("session-1")
        await conn.recordFrameSent(size: 50)

        let info = await conn.getInfo()
        XCTAssertEqual(info.connectionID, "test-conn")
        XCTAssertEqual(info.sessionID, "session-1")
        XCTAssertEqual(info.state, .connected)
        XCTAssertEqual(info.framesSent, 1)
        XCTAssertEqual(info.bytesSent, 50)
    }
}

// MARK: - Channel Type Extension Tests

final class JPIPChannelTypeWebSocketTests: XCTestCase {
    func testWebSocketChannelType() {
        XCTAssertEqual(JPIPChannelType.webSocket.rawValue, "ws")
    }

    func testChannelTypeFromRawValue() {
        let wsType = JPIPChannelType(rawValue: "ws")
        XCTAssertNotNil(wsType)
        XCTAssertEqual(wsType, .webSocket)
    }
}

// MARK: - Connection State Tests

final class JPIPWebSocketConnectionStateTests: XCTestCase {
    func testAllStates() {
        let states: [JPIPWebSocketConnectionState] = [
            .disconnected, .connecting, .connected,
            .closing, .reconnecting
        ]

        XCTAssertEqual(states.count, 5)
        XCTAssertEqual(
            JPIPWebSocketConnectionState.disconnected.rawValue,
            "disconnected"
        )
        XCTAssertEqual(
            JPIPWebSocketConnectionState.connected.rawValue,
            "connected"
        )
        XCTAssertEqual(
            JPIPWebSocketConnectionState.reconnecting.rawValue,
            "reconnecting"
        )
    }
}
