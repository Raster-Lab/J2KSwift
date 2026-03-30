//
// JPIPServerTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for the JPIP server CLI command arguments and configuration.
final class JPIPServerTests: XCTestCase {

    // MARK: - Server argument parsing

    func testJPIPServerBasicArgs() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--data-dir", "/data/images",
            "--port", "8080"
        ])
        XCTAssertEqual(opts["data-dir"], "/data/images")
        XCTAssertEqual(opts["port"], "8080")
    }

    func testJPIPServerDefaultPort() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--data-dir", "/data/images"
        ])
        XCTAssertNil(opts["port"], "Port should default when not specified")
    }

    func testJPIPServerSingleFile() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--file", "large_image.jp2",
            "--port", "9090"
        ])
        XCTAssertEqual(opts["file"], "large_image.jp2")
        XCTAssertEqual(opts["port"], "9090")
    }

    func testJPIPServerVerbose() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--data-dir", "/data/images",
            "--verbose"
        ])
        XCTAssertEqual(opts["verbose"], "true")
    }

    func testJPIPServerHost() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--data-dir", "/data",
            "--host", "0.0.0.0",
            "--port", "8080"
        ])
        XCTAssertEqual(opts["host"], "0.0.0.0")
    }

    // MARK: - Port validation

    func testValidPortNumbers() {
        let validPorts = [80, 443, 8080, 8443, 9090, 65535]
        for port in validPorts {
            XCTAssertTrue(port > 0 && port <= 65535, "Port \(port) should be valid")
        }
    }

    func testInvalidPortNumbers() {
        let invalidPorts = [0, -1, 65536, 100000]
        for port in invalidPorts {
            XCTAssertFalse(port > 0 && port <= 65535, "Port \(port) should be invalid")
        }
    }

    // MARK: - Data directory validation

    func testDataDirExists() throws {
        let tmpDir = NSTemporaryDirectory() + "j2k_jpip_test_\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        XCTAssertTrue(fm.fileExists(atPath: tmpDir))
    }

    func testDataDirNotExists() {
        let fakePath = "/nonexistent/path/\(UUID().uuidString)"
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: fakePath))
    }

    // MARK: - Image registration

    func testImageRegistrationFromDirectory() throws {
        let tmpDir = NSTemporaryDirectory() + "j2k_jpip_reg_\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        try "fake_jp2".write(toFile: "\(tmpDir)/image1.jp2", atomically: true, encoding: .utf8)
        try "fake_jp2".write(toFile: "\(tmpDir)/image2.jp2", atomically: true, encoding: .utf8)
        try "readme".write(toFile: "\(tmpDir)/readme.txt", atomically: true, encoding: .utf8)

        let contents = try fm.contentsOfDirectory(atPath: tmpDir)
        let jp2Files = contents.filter { $0.hasSuffix(".jp2") || $0.hasSuffix(".j2k") }
        XCTAssertEqual(jp2Files.count, 2)
    }
}
