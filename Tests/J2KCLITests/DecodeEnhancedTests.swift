// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// DecodeEnhancedTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for enhanced decode options: --header-only, --bit-depth,
/// --strip-alpha, --region, --scale, --output-format.
final class DecodeEnhancedTests: XCTestCase {

    // MARK: - Header-only

    func testHeaderOnlyFlagParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--header-only", "-i", "test.j2k"])
        XCTAssertEqual(opts["header-only"], "true")
    }

    // MARK: - Bit depth conversion

    func testBitDepthConversionFlag() {
        let opts = CLIArgumentParserTestHelper.parse(["--bit-depth", "16", "-i", "test.j2k", "-o", "out.pgm"])
        XCTAssertEqual(opts["bit-depth"], "16")
    }

    func testBitDepthConversion8() {
        let opts = CLIArgumentParserTestHelper.parse(["--bit-depth", "8"])
        XCTAssertEqual(opts["bit-depth"], "8")
    }

    // MARK: - Strip alpha

    func testStripAlphaFlag() {
        let opts = CLIArgumentParserTestHelper.parse(["--strip-alpha", "-i", "test.j2k", "-o", "out.ppm"])
        XCTAssertEqual(opts["strip-alpha"], "true")
    }

    // MARK: - Region decoding

    func testRegionDecodingFlag() {
        let opts = CLIArgumentParserTestHelper.parse(["--region", "0,0,256,256", "-i", "test.j2k", "-o", "out.pgm"])
        XCTAssertEqual(opts["region"], "0,0,256,256")
    }

    func testRegionParsing() {
        let region = "100,200,300,400"
        let parts = region.split(separator: ",").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0], 100) // x
        XCTAssertEqual(parts[1], 200) // y
        XCTAssertEqual(parts[2], 300) // width
        XCTAssertEqual(parts[3], 400) // height
    }

    // MARK: - Scale

    func testScaleFlag() {
        let opts = CLIArgumentParserTestHelper.parse(["--scale", "0.5", "-i", "test.j2k", "-o", "out.pgm"])
        XCTAssertEqual(opts["scale"], "0.5")
    }

    func testScaleValues() {
        // Valid scale values
        XCTAssertNotNil(Double("0.5"))
        XCTAssertNotNil(Double("0.25"))
        XCTAssertNotNil(Double("1.0"))
        XCTAssertNotNil(Double("2.0"))

        // Invalid scale
        XCTAssertNil(Double("abc"))
    }

    // MARK: - Output format

    func testOutputFormatParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["--output-format", "ppm", "-i", "test.j2k", "-o", "out"])
        XCTAssertEqual(opts["output-format"], "ppm")
    }

    func testOutputFormatPGM() {
        let opts = CLIArgumentParserTestHelper.parse(["--output-format", "pgm"])
        XCTAssertEqual(opts["output-format"], "pgm")
    }

    func testOutputFormatRAW() {
        let opts = CLIArgumentParserTestHelper.parse(["--output-format", "raw"])
        XCTAssertEqual(opts["output-format"], "raw")
    }

    // MARK: - Combined flags

    func testCombinedDecodeFlags() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--region", "0,0,512,512",
            "--bit-depth", "16",
            "--output-format", "pgm",
            "-i", "test.j2k",
            "-o", "out.pgm"
        ])
        XCTAssertEqual(opts["region"], "0,0,512,512")
        XCTAssertEqual(opts["bit-depth"], "16")
        XCTAssertEqual(opts["output-format"], "pgm")
        XCTAssertEqual(opts["i"], "test.j2k")
        XCTAssertEqual(opts["o"], "out.pgm")
    }
}

#endif // os(macOS)
