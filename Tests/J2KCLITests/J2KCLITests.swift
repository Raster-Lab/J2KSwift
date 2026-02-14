import XCTest
import Foundation
@testable import J2KCore

/// Basic integration tests for J2KCLI tool
final class J2KCLITests: XCTestCase {
    /// Path to the built CLI executable
    var cliPath: String {
        // Try to get the path from environment variable first (more robust)
        if let envPath = ProcessInfo.processInfo.environment["J2K_CLI_PATH"] {
            return envPath
        }
        
        // Fall back to relative path (assumes standard build directory)
        let buildDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/j2k")
        return buildDir.path
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
