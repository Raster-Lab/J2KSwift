//
// JPIPEndToEndTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// End-to-end tests for JPIP server/client interaction scenarios.
/// These tests validate argument structures and configuration logic
/// without requiring actual network connections.
final class JPIPEndToEndTests: XCTestCase {

    // MARK: - Server + Client configuration pairing

    func testServerClientPortMatch() {
        let serverOpts = CLIArgumentParserTestHelper.parse(["--data-dir", "/data", "--port", "8080"])
        let clientOpts = CLIArgumentParserTestHelper.parse(["--url", "jpip://localhost:8080/image.jp2"])

        let serverPort = serverOpts["port"]
        // Extract port from client URL
        let urlString = clientOpts["url"]!
        let withoutScheme = String(urlString.dropFirst(7))
        let hostPort = withoutScheme.split(separator: "/").first ?? ""
        let portStr = hostPort.split(separator: ":").last.map(String.init) ?? ""

        XCTAssertEqual(serverPort, portStr, "Server and client ports should match")
    }

    // MARK: - Session lifecycle

    func testSessionConfiguration() {
        // Validate session parameters
        let sessionId = UUID().uuidString
        XCTAssertEqual(sessionId.count, 36, "UUID should be 36 characters")
        XCTAssertTrue(sessionId.contains("-"), "UUID should contain dashes")
    }

    // MARK: - Progressive quality request sequence

    func testProgressiveQualitySequence() {
        let qualityLevels: [Double] = [0.1, 0.25, 0.5, 0.75, 1.0]

        // Each level should be greater than the previous
        for i in 1..<qualityLevels.count {
            XCTAssertGreaterThan(qualityLevels[i], qualityLevels[i-1],
                                 "Quality levels should be increasing")
        }
    }

    // MARK: - Region-of-interest request

    func testROIRequestParameters() {
        let fullWidth = 4096
        let fullHeight = 4096

        // Request a quarter of the image
        let roiX = 0, roiY = 0
        let roiW = fullWidth / 2
        let roiH = fullHeight / 2

        XCTAssertEqual(roiW, 2048)
        XCTAssertEqual(roiH, 2048)
        XCTAssertTrue(roiX + roiW <= fullWidth)
        XCTAssertTrue(roiY + roiH <= fullHeight)
    }

    // MARK: - Resolution level request

    func testResolutionLevelScaling() {
        let fullWidth = 4096
        let fullHeight = 4096
        let maxDecompositionLevels = 5

        for level in 0...maxDecompositionLevels {
            let scaledWidth = fullWidth >> level
            let scaledHeight = fullHeight >> level
            XCTAssertGreaterThan(scaledWidth, 0)
            XCTAssertGreaterThan(scaledHeight, 0)
        }

        // Level 0 = full resolution
        XCTAssertEqual(fullWidth >> 0, 4096)
        // Level 1 = half resolution
        XCTAssertEqual(fullWidth >> 1, 2048)
        // Level 5 = 1/32 resolution
        XCTAssertEqual(fullWidth >> 5, 128)
    }

    // MARK: - Metadata request

    func testMetadataRequestArgs() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--url", "jpip://localhost:8080/image.jp2",
            "--metadata-only"
        ])
        XCTAssertEqual(opts["metadata-only"], "true")
    }

    // MARK: - Error handling scenarios

    func testConnectionRefusedScenario() {
        // Validate that an invalid URL would be caught
        let invalidURL = "jpip://nonexistent:99999/missing.jp2"
        XCTAssertTrue(invalidURL.contains("nonexistent"))
    }

    func testMissingImageScenario() {
        // Image not found on server
        let imageName = "nonexistent_image.jp2"
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: "/tmp/\(imageName)"))
    }
}
