// v8 Phase 6.2 — gated to macOS: invokes external CLIs via Process() (unavailable on iOS).
#if os(macOS)
//
// J2KCLITests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Raised when the `j2k` executable cannot be found, naming every path tried so the
/// failure reports what to fix rather than only that some file is missing.
enum CLILocationError: LocalizedError, CustomStringConvertible {
    case executableNotFound(attempted: [String])

    var description: String {
        switch self {
        case .executableNotFound(let attempted):
            let tried = attempted.map { "  - \($0)" }.joined(separator: "\n")
            return """
                Could not find the `j2k` executable. Build it with \
                `swift build --product j2k`, or set J2K_CLI_PATH to its location.
                Tried:
                \(tried)
                """
        }
    }

    var errorDescription: String? { description }
}

/// Basic integration tests for J2KCLI tool
final class J2KCLITests: XCTestCase {
    /// Path to the built CLI executable.
    ///
    /// The products directory is derived from this bundle's own location, so the lookup
    /// follows `--scratch-path`. The hardcoded `.build/...` paths below do not: a build
    /// into any other scratch path leaves `j2k` somewhere they never look, and every
    /// executable-based test here then fails on a missing file rather than on behaviour.
    var cliPath: String {
        get throws {
            // An explicit override wins and is taken as given: a caller who sets it has
            // said where the binary is.
            if let envPath = ProcessInfo.processInfo.environment["J2K_CLI_PATH"] {
                return envPath
            }

            let fileManager = FileManager.default
            var attempted: [String] = []

            // The directory this test bundle was built into, which is also where SwiftPM
            // puts `j2k`, whatever scratch path the build used.
            let productsDir = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()

            // Conventional locations, for a default-scratch-path build driven from the
            // package root or from a parent directory, as some CI layouts do.
            let currentDir = fileManager.currentDirectoryPath

            let possiblePaths = [
                productsDir.appendingPathComponent("j2k").path,
                "\(currentDir)/.build/debug/j2k",
                "\(currentDir)/.build/release/j2k",
                "\(currentDir)/J2KSwift/.build/debug/j2k",
                "\(currentDir)/J2KSwift/.build/release/j2k",
            ]

            for path in possiblePaths {
                attempted.append(path)
                if fileManager.fileExists(atPath: path) {
                    return path
                }
            }

            throw CLILocationError.executableNotFound(attempted: attempted)
        }
    }

    // MARK: - Executable-based tests

    func testCLIHelp() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
        process.executableURL = URL(fileURLWithPath: try cliPath)
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
// MARK: - v10.25 pipe-sentinel parser regression tests

final class CLIPipeSentinelParserTests: XCTestCase {
    /// `-i -` / `-o -` must bind the bare dash as the option's value
    /// (the stdin/stdout pipe sentinel) — the pre-v10.25 parser
    /// treated it as a flag terminator, so `-i -` parsed as
    /// `i = "true"` and the documented piping examples never worked.
    func testPipeSentinelBindsAsOptionValue() {
        let short = CLIArgumentParserTestHelper.parse(["-i", "-", "-o", "/tmp/x.j2k"])
        XCTAssertEqual(short["i"], "-")
        XCTAssertEqual(short["o"], "/tmp/x.j2k")

        let long = CLIArgumentParserTestHelper.parse(["--input", "-", "--output", "-"])
        XCTAssertEqual(long["input"], "-")
        XCTAssertEqual(long["output"], "-")
    }

    /// Tokens that look like flags must still NOT be consumed as values.
    func testFlagLikeTokensStillNotConsumed() {
        let parsed = CLIArgumentParserTestHelper.parse(["-i", "--verbose"])
        XCTAssertEqual(parsed["i"], "true")
        XCTAssertEqual(parsed["verbose"], "true")
    }
}

enum CLIArgumentParserTestHelper {
    /// v10.25: mirrors `J2KCLI.isOptionValue` — a bare `-` is the
    /// stdin/stdout pipe sentinel, not a flag.
    static func isOptionValue(_ token: String) -> Bool {
        token == "-" || !token.hasPrefix("-")
    }

    static func parse(_ args: [String]) -> [String: String] {
        var result: [String: String] = [:]
        var i = 0
        while i < args.count {
            let arg = args[i]
            if arg.hasPrefix("--") {
                let raw = String(arg.dropFirst(2))
                let key = normalise(raw)
                if i + 1 < args.count && isOptionValue(args[i + 1]) {
                    result[key] = args[i + 1]; i += 2
                } else {
                    result[key] = "true"; i += 1
                }
            } else if arg.hasPrefix("-") && arg.count == 2 {
                let key = String(arg.dropFirst())
                if i + 1 < args.count && isOptionValue(args[i + 1]) {
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

#endif // os(macOS)
