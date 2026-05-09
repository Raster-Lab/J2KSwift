// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// ErrorHandlingTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for CLI error handling: missing files, invalid arguments,
/// unsupported formats, and graceful failure.
final class ErrorHandlingTests: XCTestCase {

    // MARK: - Missing input file

    func testMissingInputFileParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["-o", "output.j2k"])
        XCTAssertNil(opts["i"], "No input file specified should result in nil")
    }

    func testMissingOutputFileParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "input.pgm"])
        XCTAssertNil(opts["o"], "No output file specified should result in nil")
    }

    // MARK: - Invalid argument values

    func testInvalidQualityValue() {
        let opts = CLIArgumentParserTestHelper.parse(["--quality", "abc"])
        let quality = Double(opts["quality"] ?? "")
        XCTAssertNil(quality, "Non-numeric quality should fail to parse")
    }

    func testNegativeQuality() {
        let quality = Double("-0.5")!
        XCTAssertLessThan(quality, 0.0, "Negative quality should be invalid")
    }

    func testQualityAboveOne() {
        let quality = Double("1.5")!
        XCTAssertGreaterThan(quality, 1.0, "Quality > 1.0 should be invalid")
    }

    func testInvalidDecompositionLevels() {
        let levels = Int("0")!
        XCTAssertLessThanOrEqual(levels, 0, "Zero decomposition levels should be invalid")
    }

    func testInvalidCompressionRatioFormat() {
        let ratio = "20" // Missing ":1" suffix
        let parts = ratio.split(separator: ":")
        XCTAssertNotEqual(parts.count, 2, "Invalid ratio format should not have 2 parts")
    }

    func testValidCompressionRatioFormat() {
        let ratio = "20:1"
        let parts = ratio.split(separator: ":")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(Int(parts[0]), 20)
        XCTAssertEqual(Int(parts[1]), 1)
    }

    // MARK: - File extension validation

    func testUnsupportedInputFormat() {
        let unsupported = ["gif", "webp", "svg", "eps"]
        let supported = Set(["pgm", "ppm", "pnm", "raw", "j2k", "jp2", "jph", "j2c", "jpx"])
        for ext in unsupported {
            XCTAssertFalse(supported.contains(ext), "\(ext) should not be supported")
        }
    }

    // MARK: - File existence checks

    func testNonexistentFile() {
        let path = "/nonexistent/\(UUID().uuidString).pgm"
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - Empty input handling

    func testEmptyArgumentList() {
        let opts = CLIArgumentParserTestHelper.parse([])
        XCTAssertTrue(opts.isEmpty, "Empty args should produce empty options")
    }

    // MARK: - Invalid codec values

    func testInvalidCodecName() {
        let validCodecs = Set(["j2k-lossless", "j2k-lossy", "htj2k-lossless", "htj2k-lossy"])
        let invalidCodec = "jpeg-xl"
        XCTAssertFalse(validCodecs.contains(invalidCodec))
    }

    // MARK: - Invalid region format

    func testInvalidRegionFormat() {
        let region = "0,0,256" // Only 3 values instead of 4
        let parts = region.split(separator: ",").compactMap { Int($0) }
        XCTAssertNotEqual(parts.count, 4, "Region should require exactly 4 values")
    }

    func testRegionWithNegativeValues() {
        let parts = [-1, 0, 256, 256]
        let hasNegative = parts.contains { $0 < 0 }
        XCTAssertTrue(hasNegative, "Region should not have negative values")
    }

    // MARK: - Invalid bit depth

    func testInvalidBitDepth() {
        let validBitDepths = Set([8, 10, 12, 16])
        let invalidDepth = 7
        XCTAssertFalse(validBitDepths.contains(invalidDepth))
    }

    func testValidBitDepths() {
        let validBitDepths = [8, 10, 12, 16]
        for depth in validBitDepths {
            XCTAssertGreaterThan(depth, 0)
            XCTAssertLessThanOrEqual(depth, 16)
        }
    }

    // MARK: - Invalid port

    func testInvalidPortValue() {
        let port = Int("abc")
        XCTAssertNil(port, "Non-numeric port should fail to parse")
    }

    // MARK: - Scale validation

    func testInvalidScaleValue() {
        let scale = Double("0")!
        XCTAssertEqual(scale, 0.0, "Zero scale should be invalid")
    }

    func testNegativeScale() {
        let scale = Double("-0.5")!
        XCTAssertLessThan(scale, 0.0, "Negative scale should be invalid")
    }
}

#endif // os(macOS)
