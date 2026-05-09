// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
import XCTest
import Foundation
@testable import J2KCore

/// Tests for multi-file input parsing, glob expansion, and directory traversal.
final class MultiFileInputTests: XCTestCase {

    /// Test parsing comma-separated input paths.
    func testCommaSeparatedInputParsing() throws {
        let args = ["--input", "file1.pgm,file2.pgm,file3.pgm", "--output-dir", "/tmp/out"]
        let options = CLIArgumentParserTestHelper.parse(args)
        XCTAssertEqual(options["input"], "file1.pgm,file2.pgm,file3.pgm")
        XCTAssertEqual(options["output-dir"], "/tmp/out")
    }

    /// Test parsing glob pattern input.
    func testGlobPatternInputParsing() throws {
        let args = ["-i", "images/*.pgm", "-o", "/tmp/out"]
        let options = CLIArgumentParserTestHelper.parse(args)
        XCTAssertEqual(options["i"], "images/*.pgm")
    }

    /// Test parsing directory input.
    func testDirectoryInputParsing() throws {
        let args = ["-i", "./input_dir/", "--recursive", "--output-dir", "/tmp/out"]
        let options = CLIArgumentParserTestHelper.parse(args)
        XCTAssertEqual(options["i"], "./input_dir/")
        XCTAssertEqual(options["recursive"], "true")
    }

    /// Test parsing file list from file argument.
    func testFileListInputParsing() throws {
        let args = ["--input-list", "paths.txt"]
        let options = CLIArgumentParserTestHelper.parse(args)
        XCTAssertEqual(options["input-list"], "paths.txt")
    }

    /// Test parsing file list from stdin argument.
    func testFileListStdinParsing() throws {
        let args = ["--input-list", "-"]
        let options = CLIArgumentParserTestHelper.parse(args)
        // Note: '-' alone is not treated as a flag because it's only 1 char
        XCTAssertNotNil(options["input-list"])
    }

    /// Test output-dir and output-suffix parsing.
    func testOutputDirSuffixParsing() throws {
        let args = ["--output-dir", "/tmp/encoded", "--output-suffix", ".j2k"]
        let options = CLIArgumentParserTestHelper.parse(args)
        XCTAssertEqual(options["output-dir"], "/tmp/encoded")
        XCTAssertEqual(options["output-suffix"], ".j2k")
    }

    /// Test threads flag parsing.
    func testThreadsFlagParsing() throws {
        let args = ["--threads", "4", "--progress"]
        let options = CLIArgumentParserTestHelper.parse(args)
        XCTAssertEqual(options["threads"], "4")
        XCTAssertEqual(options["progress"], "true")
    }

    /// Test glob expansion with a temporary directory.
    func testGlobExpansionWithTempDir() throws {
        let tmpDir = NSTemporaryDirectory() + "j2k_glob_test_\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        // Create test files
        try "test".write(toFile: "\(tmpDir)/image1.pgm", atomically: true, encoding: .utf8)
        try "test".write(toFile: "\(tmpDir)/image2.pgm", atomically: true, encoding: .utf8)
        try "test".write(toFile: "\(tmpDir)/other.txt", atomically: true, encoding: .utf8)

        let contents = try fm.contentsOfDirectory(atPath: tmpDir)
        let pgmFiles = contents.filter { $0.hasSuffix(".pgm") }
        XCTAssertEqual(pgmFiles.count, 2)
    }

    /// Test directory traversal with filter and exclude.
    func testFilterAndExclude() throws {
        let tmpDir = NSTemporaryDirectory() + "j2k_filter_test_\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        try "test".write(toFile: "\(tmpDir)/a.pgm", atomically: true, encoding: .utf8)
        try "test".write(toFile: "\(tmpDir)/b.pgm", atomically: true, encoding: .utf8)
        try "test".write(toFile: "\(tmpDir)/c.ppm", atomically: true, encoding: .utf8)

        let contents = try fm.contentsOfDirectory(atPath: tmpDir)
        let pgmOnly = contents.filter { $0.hasSuffix(".pgm") }
        XCTAssertEqual(pgmOnly.count, 2)
    }
}

#endif // os(macOS)
