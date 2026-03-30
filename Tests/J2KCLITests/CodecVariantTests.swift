//
// CodecVariantTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for codec variant selection (--codec flag) in encode/transcode commands.
final class CodecVariantTests: XCTestCase {

    // MARK: - Argument parsing for --codec

    func testCodecFlagJ2KLossless() {
        let opts = CLIArgumentParserTestHelper.parse(["--codec", "j2k-lossless", "-i", "input.pgm", "-o", "output.j2k"])
        XCTAssertEqual(opts["codec"], "j2k-lossless")
    }

    func testCodecFlagJ2KLossy() {
        let opts = CLIArgumentParserTestHelper.parse(["--codec", "j2k-lossy", "-i", "input.pgm", "-o", "output.j2k"])
        XCTAssertEqual(opts["codec"], "j2k-lossy")
    }

    func testCodecFlagHTJ2KLossless() {
        let opts = CLIArgumentParserTestHelper.parse(["--codec", "htj2k-lossless", "-i", "input.pgm", "-o", "output.jph"])
        XCTAssertEqual(opts["codec"], "htj2k-lossless")
    }

    func testCodecFlagHTJ2KLossy() {
        let opts = CLIArgumentParserTestHelper.parse(["--codec", "htj2k-lossy", "-i", "input.pgm", "-o", "output.jph"])
        XCTAssertEqual(opts["codec"], "htj2k-lossy")
    }

    func testDefaultCodecIsNil() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "input.pgm", "-o", "output.j2k"])
        XCTAssertNil(opts["codec"])
    }

    // MARK: - Compression options

    func testCompressionRatioParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--compression-ratio", "20:1"])
        XCTAssertEqual(opts["compression-ratio"], "20:1")
    }

    func testCompressionPercentParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--compression-percent", "95"])
        XCTAssertEqual(opts["compression-percent"], "95")
    }

    func testTargetSizeParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--target-size", "1048576"])
        XCTAssertEqual(opts["target-size"], "1048576")
    }

    // MARK: - Codec combined with quality

    func testCodecWithQuality() {
        let opts = CLIArgumentParserTestHelper.parse(["--codec", "j2k-lossy", "--quality", "0.85"])
        XCTAssertEqual(opts["codec"], "j2k-lossy")
        XCTAssertEqual(opts["quality"], "0.85")
    }

    func testCodecWithLossless() {
        let opts = CLIArgumentParserTestHelper.parse(["--codec", "j2k-lossless", "--lossless"])
        XCTAssertEqual(opts["codec"], "j2k-lossless")
        XCTAssertEqual(opts["lossless"], "true")
    }

    // MARK: - Transcode codec options

    func testTranscodeCodecFlags() {
        let opts = CLIArgumentParserTestHelper.parse(["--codec", "htj2k-lossless", "-i", "input.j2k", "-o", "output.jph", "--verify"])
        XCTAssertEqual(opts["codec"], "htj2k-lossless")
        XCTAssertEqual(opts["verify"], "true")
    }

    func testTranscodeVerifyMode() {
        let opts = CLIArgumentParserTestHelper.parse(["--verify", "--verify-mode", "statistical"])
        XCTAssertEqual(opts["verify"], "true")
        XCTAssertEqual(opts["verify-mode"], "statistical")
    }

    func testTranscodeVerifyModeExact() {
        let opts = CLIArgumentParserTestHelper.parse(["--verify", "--verify-mode", "exact"])
        XCTAssertEqual(opts["verify-mode"], "exact")
    }
}
