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
        for path in possiblePaths where fileManager.fileExists(atPath: path) {
            return path
        }

        // Fall back to standard debug path (will fail if not found, but gives clear error)
        return "\(currentDir)/.build/debug/j2k"
    }

    // MARK: - Executable-based tests

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

    func testCLIVersionFlag() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("J2KSwift version"))
    }

    func testCLIInfoHelp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["info", "--help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("info"))
    }

    func testCLITranscodeHelp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["transcode", "--help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("transcode"))
    }

    func testCLIValidateHelp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["validate", "--help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("validate"))
    }

    func testCLIBenchmarkHelp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["benchmark", "--help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("benchmark"))
    }

    func testCLIHelpShowsNewCommands() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["help"]

        let pipe = Pipe()
        process.standardOutput = pipe

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(output.contains("info"),       "help should mention 'info' command")
        XCTAssertTrue(output.contains("transcode"),  "help should mention 'transcode' command")
        XCTAssertTrue(output.contains("validate"),   "help should mention 'validate' command")
        XCTAssertTrue(output.contains("benchmark"),  "help should mention 'benchmark' command")
    }

    // MARK: - Argument parsing unit tests (logic only, no binary required)

    func testArgumentParsing() {
        // Basic flag parsing
        let opts = CLIArgumentParserTestHelper.parse(["--lossless", "--quality", "0.9", "-i", "input.pgm"])
        XCTAssertEqual(opts["lossless"], "true")
        XCTAssertEqual(opts["quality"],  "0.9")
        XCTAssertEqual(opts["i"],        "input.pgm")
    }

    func testCLIDualSpelling() {
        // British spelling should map to American spelling
        let opts1 = CLIArgumentParserTestHelper.parse(["--colour-space", "sRGB"])
        let opts2 = CLIArgumentParserTestHelper.parse(["--color-space",  "sRGB"])
        XCTAssertEqual(opts1["color-space"], "sRGB", "--colour-space should map to color-space")
        XCTAssertEqual(opts2["color-space"], "sRGB", "--color-space should be stored as color-space")

        let opts3 = CLIArgumentParserTestHelper.parse(["--colour"])
        let opts4 = CLIArgumentParserTestHelper.parse(["--color"])
        XCTAssertEqual(opts3["color"], "true", "--colour should map to color")
        XCTAssertEqual(opts4["color"], "true", "--color should be stored as color")

        let opts5 = CLIArgumentParserTestHelper.parse(["--optimise"])
        let opts6 = CLIArgumentParserTestHelper.parse(["--optimize"])
        XCTAssertEqual(opts5["optimize"], "true", "--optimise should map to optimize")
        XCTAssertEqual(opts6["optimize"], "true", "--optimize should be stored as optimize")
    }

    func testArgumentParsingPositional() {
        let opts = CLIArgumentParserTestHelper.parse(["image.jp2", "--json"])
        XCTAssertEqual(opts["_positional"], "image.jp2")
        XCTAssertEqual(opts["json"], "true")
    }

    func testArgumentParsingShortFlags() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "input.j2k", "-o", "output.ppm", "-r", "5"])
        XCTAssertEqual(opts["i"], "input.j2k")
        XCTAssertEqual(opts["o"], "output.ppm")
        XCTAssertEqual(opts["r"], "5")
    }
}

// MARK: - Lightweight argument parser for unit testing

/// A standalone argument parser that mirrors J2KCLI.parseArguments / normaliseKey
/// but is accessible without importing the executable module.
enum CLIArgumentParserTestHelper {
    static func parse(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--") {
                let raw = String(arg.dropFirst(2))
                let key = normalise(raw)
                if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    result[key] = args[i + 1]; i += 2
                } else {
                    result[key] = "true"; i += 1
                }
            } else if arg.hasPrefix("-") && arg.count == 2 {
                let key = String(arg.dropFirst())
                if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    result[key] = args[i + 1]; i += 2
                } else {
                    result[key] = "true"; i += 1
                }
            } else {
                result["_positional"] = arg; i += 1
            }
        }
        return result
    }

    static func normalise(_ key: String) -> String {
        switch key {
        case "colour":               return "color"
        case "colour-space":         return "color-space"
        case "optimise":             return "optimize"
        case "optimise-progressive": return "optimize-progressive"
        default:                     return key
        }
    }
}
