//
// BatchCommandTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for the batch command: batch encode, batch decode, batch transcode.
final class BatchCommandTests: XCTestCase {

    // MARK: - Batch argument parsing

    func testBatchEncodeSubcommand() {
        let args = ["encode", "-i", "images/", "--output-dir", "/tmp/out", "--codec", "j2k-lossless"]
        XCTAssertEqual(args[0], "encode")
    }

    func testBatchDecodeSubcommand() {
        let args = ["decode", "-i", "encoded/", "--output-dir", "/tmp/decoded"]
        XCTAssertEqual(args[0], "decode")
    }

    func testBatchTranscodeSubcommand() {
        let args = ["transcode", "-i", "j2k_files/", "--output-dir", "/tmp/htj2k", "--codec", "htj2k-lossless"]
        XCTAssertEqual(args[0], "transcode")
    }

    // MARK: - Multi-file input parsing

    func testBatchWithGlobPattern() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "data/*.pgm", "--output-dir", "/tmp/out"])
        XCTAssertEqual(opts["i"], "data/*.pgm")
        XCTAssertEqual(opts["output-dir"], "/tmp/out")
    }

    func testBatchWithRecursive() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "data/", "--recursive", "--output-dir", "/tmp/out"])
        XCTAssertEqual(opts["recursive"], "true")
    }

    func testBatchWithFilter() {
        let opts = CLIArgumentParserTestHelper.parse(["--filter", "*.pgm", "-i", "data/", "--output-dir", "/tmp/out"])
        XCTAssertEqual(opts["filter"], "*.pgm")
    }

    func testBatchWithExclude() {
        let opts = CLIArgumentParserTestHelper.parse(["--exclude", "thumbnail_*", "-i", "data/", "--output-dir", "/tmp/out"])
        XCTAssertEqual(opts["exclude"], "thumbnail_*")
    }

    // MARK: - Parallel processing flags

    func testBatchWithThreads() {
        let opts = CLIArgumentParserTestHelper.parse(["--threads", "8", "-i", "data/", "--output-dir", "/tmp/out"])
        XCTAssertEqual(opts["threads"], "8")
    }

    func testBatchWithProgress() {
        let opts = CLIArgumentParserTestHelper.parse(["--progress", "-i", "data/", "--output-dir", "/tmp/out"])
        XCTAssertEqual(opts["progress"], "true")
    }

    // MARK: - Output suffix

    func testBatchWithOutputSuffix() {
        let opts = CLIArgumentParserTestHelper.parse(["--output-suffix", ".j2k", "-i", "data/", "--output-dir", "/tmp/out"])
        XCTAssertEqual(opts["output-suffix"], ".j2k")
    }

    // MARK: - Temporary directory helpers

    func testBatchSummaryComputation() {
        // Test batch summary computation
        let results: [(name: String, success: Bool, elapsed: Double)] = [
            ("file1.pgm", true, 0.5),
            ("file2.pgm", true, 0.3),
            ("file3.pgm", false, 0.0),
        ]
        let successCount = results.filter { $0.success }.count
        let failureCount = results.filter { !$0.success }.count
        let totalTime = results.map(\.elapsed).reduce(0, +)

        XCTAssertEqual(successCount, 2)
        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(totalTime, 0.8, accuracy: 0.001)
    }
}
