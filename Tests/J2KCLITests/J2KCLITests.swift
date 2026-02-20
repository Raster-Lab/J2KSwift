//
// J2KCLITests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Basic integration tests for J2KCLI tool
final class J2KCLITests: XCTestCase {
    /// Path to the built CLI executable
    var cliPath: String {
        // Try to get the path from environment variable first (most robust)
        if let envPath = ProcessInfo.processInfo.environment["J2K_CLI_PATH"] {
            return envPath
        }

        // Try to find the executable using FileManager by searching from current directory
        let fileManager = FileManager.default
        let currentDir = fileManager.currentDirectoryPath

        // Common build locations to check
        // Note: Some CI environments change directory structure, so we check both
        // the current directory and a potential subdirectory with the package name
        let possiblePaths = [
            "\(currentDir)/.build/debug/j2k",
            "\(currentDir)/.build/release/j2k",
            "\(currentDir)/J2KSwift/.build/debug/j2k",
            "\(currentDir)/J2KSwift/.build/release/j2k",
        ]

        // Return the first path that exists
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                return path
            }
        }

        // Fall back to standard debug path (will fail if not found, but gives clear error)
        return "\(currentDir)/.build/debug/j2k"
    }

    func testCLIHelp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["--help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("J2KSwift"))
        XCTAssertTrue(output.contains("COMMANDS"))
    }

    func testCLIVersion() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["version"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("J2KSwift version"))
    }
}
