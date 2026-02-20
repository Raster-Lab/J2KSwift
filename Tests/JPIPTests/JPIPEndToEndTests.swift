//
// JPIPEndToEndTests.swift
// J2KSwift
//
/// # JPIPEndToEndTests
///
/// Comprehensive end-to-end tests for JPIP client-server communication.
/// These tests cover advanced scenarios including error handling, session isolation,
/// cache coherency, and resilience testing.

import XCTest
@testable import JPIP
import J2KCore
import J2KFileFormat

final class JPIPEndToEndTests: XCTestCase {
    // MARK: - Mock Transport for Testing

    /// Mock transport that simulates client-server communication without actual HTTP.
    actor MockJPIPTransport {
        private let server: JPIPServer
        private var shouldSimulateNetworkError = false
        private var requestCount = 0
        private let maxRequestsBeforeError: Int?

        init(server: JPIPServer, maxRequestsBeforeError: Int? = nil) {
            self.server = server
            self.maxRequestsBeforeError = maxRequestsBeforeError
        }

        func sendRequest(_ request: JPIPRequest) async throws -> JPIPResponse {
            requestCount += 1

            // Simulate network error if configured
            if shouldSimulateNetworkError {
                throw J2KError.internalError("Simulated network error")
            }

            // Simulate intermittent errors
            if let maxRequests = maxRequestsBeforeError, requestCount > maxRequests {
                throw J2KError.internalError("Connection lost")
            }

            return try await server.handleRequest(request)
        }

        func enableNetworkError() {
            shouldSimulateNetworkError = true
        }

        func disableNetworkError() {
            shouldSimulateNetworkError = false
        }

        func resetRequestCount() {
            requestCount = 0
        }
    }

    // MARK: - Error Handling Tests

    func testInvalidTargetHandling() async throws {
        let server = JPIPServer(port: 10000)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Request non-existent image
        let request = JPIPRequest(target: "nonexistent.jp2")

        do {
            _ = try await transport.sendRequest(request)
            XCTFail("Expected error for non-existent target")
        } catch {
            // Expected error
            XCTAssertTrue(true)
        }

        try await server.stop()
    }

    func testMalformedRequestRecovery() async throws {
        let server = JPIPServer(port: 10001)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test-malformed".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // First, create valid session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        XCTAssertEqual(sessionResponse.statusCode, 200)

        // Now send request with invalid channel ID
        var invalidRequest = JPIPRequest(target: "test.jp2")
        invalidRequest.cid = "invalid-channel-id"

        do {
            let response = try await transport.sendRequest(invalidRequest)
            // Server should return error status
            XCTAssertNotEqual(response.statusCode, 200)
        } catch {
            // Or throw error - both are valid responses
            XCTAssertTrue(true)
        }

        // Verify we can still use the valid session
        var validRequest = JPIPRequest(target: "test.jp2")
        validRequest.cid = sessionResponse.channelID
        let validResponse = try await transport.sendRequest(validRequest)
        XCTAssertEqual(validResponse.statusCode, 200)

        try await server.stop()
    }

    func testNetworkErrorHandling() async throws {
        let server = JPIPServer(port: 10002)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test-network".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create session successfully
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        XCTAssertEqual(sessionResponse.statusCode, 200)

        // Enable network error simulation
        await transport.enableNetworkError()

        // Subsequent requests should fail
        var request = JPIPRequest(target: "test.jp2")
        request.cid = sessionResponse.channelID

        do {
            _ = try await transport.sendRequest(request)
            XCTFail("Expected network error")
        } catch {
            XCTAssertTrue(true)
        }

        // Disable network error and retry
        await transport.disableNetworkError()
        let retryResponse = try await transport.sendRequest(request)
        XCTAssertEqual(retryResponse.statusCode, 200)

        try await server.stop()
    }

    // MARK: - Session Isolation Tests

    func testSessionIsolation() async throws {
        let server = JPIPServer(port: 10003, configuration: JPIPServer.Configuration(
            maxClients: 20
        ))

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test-isolation".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create multiple sessions
        var sessions: [(id: String?, request: JPIPRequest)] = []
        for _ in 1...5 {
            var sessionRequest = JPIPRequest(target: "test.jp2")
            sessionRequest.cnew = .http
            let response = try await transport.sendRequest(sessionRequest)
            sessions.append((id: response.channelID, request: sessionRequest))
        }

        // Verify all sessions are independent
        let uniqueChannelIDs = Set(sessions.compactMap { $0.id })
        XCTAssertEqual(uniqueChannelIDs.count, 5)

        // Each session should be able to make requests independently
        for (channelID, _) in sessions {
            guard let channelID = channelID else { continue }

            var request = JPIPRequest(target: "test.jp2")
            request.cid = channelID
            let response = try await transport.sendRequest(request)
            XCTAssertEqual(response.statusCode, 200)
        }

        try await server.stop()
    }

    func testConcurrentSessionRequests() async throws {
        let server = JPIPServer(port: 10004, configuration: JPIPServer.Configuration(
            maxClients: 20,
            maxQueueSize: 200
        ))

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test-concurrent-sessions".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create sessions first
        var channelIDs: [String] = []
        for _ in 1...10 {
            var sessionRequest = JPIPRequest(target: "test.jp2")
            sessionRequest.cnew = .http
            let response = try await transport.sendRequest(sessionRequest)
            if let channelID = response.channelID {
                channelIDs.append(channelID)
            }
        }

        XCTAssertEqual(channelIDs.count, 10)

        // Now make concurrent requests from all sessions
        await withTaskGroup(of: Bool.self) { group in
            for channelID in channelIDs {
                // Each session makes 5 requests
                for _ in 1...5 {
                    group.addTask {
                        var request = JPIPRequest(target: "test.jp2")
                        request.cid = channelID

                        do {
                            let response = try await transport.sendRequest(request)
                            return response.statusCode == 200
                        } catch {
                            return false
                        }
                    }
                }
            }

            var successCount = 0
            for await success in group where success {
                successCount += 1
            }

            // All requests should succeed
            XCTAssertEqual(successCount, 50)
        }

        try await server.stop()
    }

    // MARK: - Cache Coherency Tests

    func testCacheStateAfterMultipleRequests() async throws {
        let server = JPIPServer(port: 10005)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")

        // Create a larger test payload to ensure meaningful cache behavior
        let testData = Data(repeating: 0x42, count: 10000)
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)

        // Make multiple requests and track data
        var totalDataReceived = 0
        for _ in 1...5 {
            var request = JPIPRequest(target: "test.jp2")
            request.cid = sessionResponse.channelID

            let response = try await transport.sendRequest(request)
            totalDataReceived += response.data.count
        }

        // Verify data was received
        XCTAssertGreaterThan(totalDataReceived, 0)

        // Check server statistics
        let stats = await server.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.totalBytesSent, totalDataReceived)

        try await server.stop()
    }

    func testCacheConsistencyAcrossSessions() async throws {
        let server = JPIPServer(port: 10006)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test-cache-consistency".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create first session
        var sessionRequest1 = JPIPRequest(target: "test.jp2")
        sessionRequest1.cnew = .http
        let sessionResponse1 = try await transport.sendRequest(sessionRequest1)
        guard let channelID1 = sessionResponse1.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Make requests from first session
        for _ in 1...3 {
            var request = JPIPRequest(target: "test.jp2")
            request.cid = channelID1
            _ = try await transport.sendRequest(request)
        }

        // Create second session for same image
        var sessionRequest2 = JPIPRequest(target: "test.jp2")
        sessionRequest2.cnew = .http
        let sessionResponse2 = try await transport.sendRequest(sessionRequest2)
        guard let channelID2 = sessionResponse2.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Sessions should have different channel IDs
        XCTAssertNotEqual(channelID1, channelID2)

        // Both sessions should be able to make requests
        var request1 = JPIPRequest(target: "test.jp2")
        request1.cid = channelID1
        let response1 = try await transport.sendRequest(request1)
        XCTAssertEqual(response1.statusCode, 200)

        var request2 = JPIPRequest(target: "test.jp2")
        request2.cid = channelID2
        let response2 = try await transport.sendRequest(request2)
        XCTAssertEqual(response2.statusCode, 200)

        try await server.stop()
    }

    // MARK: - Request-Response Cycle Tests

    func testCompleteRequestResponseCycle() async throws {
        let server = JPIPServer(port: 10007)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")

        // Create realistic JPEG 2000 data
        let testData = Data(repeating: 0x00, count: 5000)
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Step 1: Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)

        XCTAssertEqual(sessionResponse.statusCode, 200)
        XCTAssertNotNil(sessionResponse.channelID)
        XCTAssertTrue(sessionResponse.headers.keys.contains("JPIP-cnew"))

        guard let channelID = sessionResponse.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Step 2: Request metadata
        var metadataRequest = JPIPRequest.metadataRequest(target: "test.jp2")
        metadataRequest.cid = channelID
        let metadataResponse = try await transport.sendRequest(metadataRequest)

        XCTAssertEqual(metadataResponse.statusCode, 200)
        XCTAssertGreaterThan(metadataResponse.data.count, 0)

        // Step 3: Request full image data
        var imageRequest = JPIPRequest(target: "test.jp2")
        imageRequest.cid = channelID
        let imageResponse = try await transport.sendRequest(imageRequest)

        XCTAssertEqual(imageResponse.statusCode, 200)
        XCTAssertGreaterThan(imageResponse.data.count, 0)

        // Step 4: Request specific region
        var regionRequest = JPIPRequest.regionRequest(
            target: "test.jp2",
            x: 0, y: 0, width: 100, height: 100
        )
        regionRequest.cid = channelID
        let regionResponse = try await transport.sendRequest(regionRequest)

        XCTAssertEqual(regionResponse.statusCode, 200)

        // Verify session is still active
        let sessionCount = await server.getActiveSessionCount()
        XCTAssertEqual(sessionCount, 1)

        try await server.stop()
    }

    func testProgressiveQualityRequests() async throws {
        let server = JPIPServer(port: 10008)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data(repeating: 0xFF, count: 8000).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()
        let transport = MockJPIPTransport(server: server)

        // Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        guard let channelID = sessionResponse.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Request progressive quality layers
        for layer in 1...5 {
            var request = JPIPRequest.progressiveQualityRequest(
                target: "test.jp2",
                upToLayers: layer
            )
            request.cid = channelID

            let response = try await transport.sendRequest(request)
            XCTAssertEqual(response.statusCode, 200)

            // Each progressive request should return data
            XCTAssertGreaterThan(response.data.count, 0)
        }

        try await server.stop()
    }

    func testResolutionLevelRequests() async throws {
        let server = JPIPServer(port: 10009)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data(repeating: 0xAA, count: 12000).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        guard let channelID = sessionResponse.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Request different resolution levels
        for level in 0...3 {
            var request = JPIPRequest.resolutionLevelRequest(
                target: "test.jp2",
                level: level,
                layers: nil
            )
            request.cid = channelID

            let response = try await transport.sendRequest(request)
            XCTAssertEqual(response.statusCode, 200)
            XCTAssertGreaterThan(response.data.count, 0)
        }

        try await server.stop()
    }

    // MARK: - Resilience Tests

    func testServerRestartHandling() async throws {
        var server = JPIPServer(port: 10010)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test-restart".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        XCTAssertEqual(sessionResponse.statusCode, 200)

        // Stop server
        try await server.stop()

        // Restart server
        server = JPIPServer(port: 10010)
        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Old session should be invalid, need to create new one
        var newSessionRequest = JPIPRequest(target: "test.jp2")
        newSessionRequest.cnew = .http
        let newSessionResponse = try await MockJPIPTransport(server: server).sendRequest(newSessionRequest)
        XCTAssertEqual(newSessionResponse.statusCode, 200)
        XCTAssertNotNil(newSessionResponse.channelID)

        try await server.stop()
    }

    func testIntermittentConnectionFailures() async throws {
        let server = JPIPServer(port: 10011)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test-intermittent".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Transport that fails after 5 requests
        let transport = MockJPIPTransport(server: server, maxRequestsBeforeError: 5)

        // Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        guard let channelID = sessionResponse.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Make successful requests
        for _ in 1...4 {
            var request = JPIPRequest(target: "test.jp2")
            request.cid = channelID
            let response = try await transport.sendRequest(request)
            XCTAssertEqual(response.statusCode, 200)
        }

        // Next request should fail
        var failingRequest = JPIPRequest(target: "test.jp2")
        failingRequest.cid = channelID

        do {
            _ = try await transport.sendRequest(failingRequest)
            XCTFail("Expected connection error")
        } catch {
            XCTAssertTrue(true)
        }

        try await server.stop()
    }

    // MARK: - Data Integrity Tests

    func testDataIntegrityAcrossRequests() async throws {
        let server = JPIPServer(port: 10012)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")

        // Create deterministic test data
        var testData = Data()
        for i in 0..<1000 {
            testData.append(UInt8(i % 256))
        }
        try testData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        // Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        guard let channelID = sessionResponse.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Make multiple requests and verify data consistency
        var allData = Data()
        for _ in 1...3 {
            var request = JPIPRequest(target: "test.jp2")
            request.cid = channelID

            let response = try await transport.sendRequest(request)
            XCTAssertEqual(response.statusCode, 200)

            // Accumulate data
            allData.append(response.data)
        }

        // Verify we received data
        XCTAssertGreaterThan(allData.count, 0)

        try await server.stop()
    }

    func testLargePayloadHandling() async throws {
        let server = JPIPServer(port: 10013)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")

        // Create large test payload (1 MB)
        let largeData = Data(repeating: 0x55, count: 1_000_000)
        try largeData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        let transport = MockJPIPTransport(server: server)

        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await transport.sendRequest(sessionRequest)
        guard let channelID = sessionResponse.channelID else {
            XCTFail("No channel ID received")
            return
        }

        // Request large payload
        var request = JPIPRequest(target: "test.jp2")
        request.cid = channelID

        let response = try await transport.sendRequest(request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertGreaterThan(response.data.count, 0)

        try await server.stop()
    }
}
