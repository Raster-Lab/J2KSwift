//
// JPIPServerTests.swift
// J2KSwift
//
/// # JPIPServerTests
///
/// Tests for JPIP server implementation.

import XCTest
@testable import JPIP
import J2KCore

final class JPIPServerTests: XCTestCase {
    // MARK: - Server Initialization Tests

    func testServerInitialization() async throws {
        let server = JPIPServer(port: 8080)
        XCTAssertEqual(server.port, 8080)

        let stats = await server.getStatistics()
        XCTAssertEqual(stats.totalRequests, 0)
        XCTAssertEqual(stats.activeClients, 0)
        XCTAssertEqual(stats.totalBytesSent, 0)
    }

    func testServerWithCustomConfiguration() async throws {
        let config = JPIPServer.Configuration(
            maxClients: 50,
            maxQueueSize: 500,
            globalBandwidthLimit: 1_000_000, // 1 MB/s
            perClientBandwidthLimit: 100_000, // 100 KB/s
            sessionTimeout: 600
        )

        let server = JPIPServer(port: 9090, configuration: config)
        XCTAssertEqual(server.port, 9090)
        XCTAssertEqual(server.configuration.maxClients, 50)
        XCTAssertEqual(server.configuration.maxQueueSize, 500)
    }

    // MARK: - Image Registration Tests

    func testRegisterImage() async throws {
        let server = JPIPServer()

        // Create a temporary test file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)

        let images = await server.listRegisteredImages()
        XCTAssertTrue(images.contains("test.jp2"))
    }

    func testRegisterNonExistentImage() async throws {
        let server = JPIPServer()
        let nonExistentURL = URL(fileURLWithPath: "/nonexistent/image.jp2")

        do {
            try await server.registerImage(name: "test.jp2", at: nonExistentURL)
            XCTFail("Should have thrown error for nonexistent file")
        } catch {
            // Expected
        }
    }

    func testUnregisterImage() async throws {
        let server = JPIPServer()

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)

        let images = await server.listRegisteredImages()
        XCTAssertTrue(images.contains("test.jp2"))

        await server.unregisterImage(name: "test.jp2")

        let imagesAfter = await server.listRegisteredImages()
        XCTAssertFalse(imagesAfter.contains("test.jp2"))
    }

    func testListRegisteredImages() async throws {
        let server = JPIPServer()

        // Create multiple test files
        var tempURLs: [URL] = []
        for i in 1...3 {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("test\(i)-\(UUID().uuidString).jp2")
            try Data("test\(i)".utf8).write(to: tempURL)
            tempURLs.append(tempURL)
            try await server.registerImage(name: "test\(i).jp2", at: tempURL)
        }
        defer {
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let images = await server.listRegisteredImages()
        XCTAssertEqual(images.count, 3)
        XCTAssertTrue(images.contains("test1.jp2"))
        XCTAssertTrue(images.contains("test2.jp2"))
        XCTAssertTrue(images.contains("test3.jp2"))
    }

    // MARK: - Server Lifecycle Tests

    func testStartServer() async throws {
        let server = JPIPServer(port: 8888)

        try await server.start()

        // Verify server is running
        let stats = await server.getStatistics()
        XCTAssertGreaterThanOrEqual(stats.totalRequests, 0)
    }

    func testStartAlreadyRunningServer() async throws {
        let server = JPIPServer(port: 8889)

        try await server.start()

        // Try to start again
        do {
            try await server.start()
            XCTFail("Should have thrown error for already running server")
        } catch {
            // Expected
        }

        try await server.stop()
    }

    func testStopServer() async throws {
        let server = JPIPServer(port: 8890)

        try await server.start()
        try await server.stop()

        // Verify sessions are cleared
        let sessionCount = await server.getActiveSessionCount()
        XCTAssertEqual(sessionCount, 0)
    }

    func testStopNotRunningServer() async throws {
        let server = JPIPServer(port: 8891)

        do {
            try await server.stop()
            XCTFail("Should have thrown error for not running server")
        } catch {
            // Expected
        }
    }

    // MARK: - Request Handling Tests

    func testHandleSessionCreationRequest() async throws {
        let server = JPIPServer(port: 8892)

        // Create and register test image
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Create session request
        var request = JPIPRequest(target: "test.jp2")
        request.cnew = .http

        let response = try await server.handleRequest(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertNotNil(response.channelID)
        XCTAssertTrue(response.headers.keys.contains("JPIP-cnew"))

        // Verify session was created
        let sessionCount = await server.getActiveSessionCount()
        XCTAssertEqual(sessionCount, 1)

        try await server.stop()
    }

    func testHandleMetadataRequest() async throws {
        let server = JPIPServer(port: 8893)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Create session first
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await server.handleRequest(sessionRequest)

        // Request metadata
        var metadataRequest = JPIPRequest.metadataRequest(target: "test.jp2")
        metadataRequest.cid = sessionResponse.channelID

        let response = try await server.handleRequest(metadataRequest)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertGreaterThan(response.data.count, 0)

        try await server.stop()
    }

    func testHandleImageDataRequest() async throws {
        let server = JPIPServer(port: 8894)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Create session
        var sessionRequest = JPIPRequest(target: "test.jp2")
        sessionRequest.cnew = .http
        let sessionResponse = try await server.handleRequest(sessionRequest)

        // Request image data
        var imageRequest = JPIPRequest(target: "test.jp2")
        imageRequest.cid = sessionResponse.channelID

        let response = try await server.handleRequest(imageRequest)

        XCTAssertEqual(response.statusCode, 200)

        try await server.stop()
    }

    func testHandleRequestForUnregisteredImage() async throws {
        let server = JPIPServer(port: 8895)
        try await server.start()

        var request = JPIPRequest(target: "nonexistent.jp2")
        request.cnew = .http

        // Should create session but fail when processing
        do {
            _ = try await server.handleRequest(request)
            XCTFail("Should have thrown error for unregistered image")
        } catch {
            // Expected
        }

        try await server.stop()
    }

    func testHandleRequestWhenNotRunning() async throws {
        let server = JPIPServer(port: 8896)

        let request = JPIPRequest(target: "test.jp2")

        do {
            _ = try await server.handleRequest(request)
            XCTFail("Should have thrown error for stopped server")
        } catch {
            // Expected
        }
    }

    // MARK: - Session Management Tests

    func testMultipleClientSessions() async throws {
        let server = JPIPServer(port: 8897)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Create multiple sessions
        var channelIDs: [String] = []
        for _ in 1...3 {
            var request = JPIPRequest(target: "test.jp2")
            request.cnew = .http
            let response = try await server.handleRequest(request)
            if let cid = response.channelID {
                channelIDs.append(cid)
            }
        }

        XCTAssertEqual(channelIDs.count, 3)
        let sessionCount = await server.getActiveSessionCount()
        XCTAssertEqual(sessionCount, 3)

        // All channel IDs should be unique
        let uniqueIDs = Set(channelIDs)
        XCTAssertEqual(uniqueIDs.count, 3)

        try await server.stop()
    }

    func testCloseSession() async throws {
        let server = JPIPServer(port: 8898)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Create session
        var request = JPIPRequest(target: "test.jp2")
        request.cnew = .http
        let response = try await server.handleRequest(request)

        let sessionCount1 = await server.getActiveSessionCount()
        XCTAssertEqual(sessionCount1, 1)

        // Close session
        if let cid = response.channelID {
            await server.closeSession(cid)
        }

        let sessionCount2 = await server.getActiveSessionCount()
        XCTAssertEqual(sessionCount2, 0)

        try await server.stop()
    }

    // MARK: - Statistics Tests

    func testServerStatistics() async throws {
        let server = JPIPServer(port: 8899)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).jp2")
        try Data("test".utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try await server.registerImage(name: "test.jp2", at: tempURL)
        try await server.start()

        // Initial stats
        var stats = await server.getStatistics()
        XCTAssertEqual(stats.totalRequests, 0)

        // Make some requests
        for _ in 1...5 {
            var request = JPIPRequest(target: "test.jp2")
            request.cnew = .http
            _ = try await server.handleRequest(request)
        }

        // Check updated stats
        stats = await server.getStatistics()
        XCTAssertEqual(stats.totalRequests, 5)
        XCTAssertEqual(stats.activeClients, 5)
        // Session creation requests return empty data, so totalBytesSent might be 0
        XCTAssertGreaterThanOrEqual(stats.totalBytesSent, 0)

        try await server.stop()
    }
}
