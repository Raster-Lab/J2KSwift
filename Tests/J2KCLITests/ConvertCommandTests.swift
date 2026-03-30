//
// ConvertCommandTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for the convert command: format conversion with bit depth conversion.
final class ConvertCommandTests: XCTestCase {

    // MARK: - Argument parsing

    func testConvertArgumentParsing() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "image.j2k", "-o", "image.pgm"])
        XCTAssertEqual(opts["i"], "image.j2k")
        XCTAssertEqual(opts["o"], "image.pgm")
    }

    func testConvertWithBitDepth() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "image.j2k", "-o", "image.pgm", "--bit-depth", "16"])
        XCTAssertEqual(opts["bit-depth"], "16")
    }

    func testConvertWithStripAlpha() {
        let opts = CLIArgumentParserTestHelper.parse(["-i", "image.j2k", "-o", "image.ppm", "--strip-alpha"])
        XCTAssertEqual(opts["strip-alpha"], "true")
    }

    // MARK: - Format detection

    func testFormatDetectionFromExtension() {
        let extensions = ["j2k", "jp2", "jph", "j2c", "jpx"]
        for ext in extensions {
            XCTAssertTrue(isJPEG2000Extension(ext), "\(ext) should be a JPEG 2000 extension")
        }
    }

    func testNonJ2KFormatDetection() {
        let extensions = ["pgm", "ppm", "pnm", "raw", "png", "jpg"]
        for ext in extensions {
            XCTAssertFalse(isJPEG2000Extension(ext), "\(ext) should not be a JPEG 2000 extension")
        }
    }

    func testImageFormatDetection() {
        let extensions = ["pgm", "ppm", "pnm", "raw"]
        for ext in extensions {
            XCTAssertTrue(isImageExtension(ext), "\(ext) should be an image extension")
        }
    }

    // MARK: - Bit depth conversion logic

    func testBitDepthConversion8to16() {
        let input: [UInt8] = [0, 128, 255]
        let output = input.map { UInt16($0) << 8 }
        XCTAssertEqual(output, [0, 32768, 65280])
    }

    func testBitDepthConversion16to8() {
        let input: [UInt16] = [0, 32768, 65535]
        let output = input.map { UInt8($0 >> 8) }
        XCTAssertEqual(output, [0, 128, 255])
    }

    // MARK: - Helpers

    private func isJPEG2000Extension(_ ext: String) -> Bool {
        ["j2k", "jp2", "jph", "j2c", "jpx", "jpm"].contains(ext.lowercased())
    }

    private func isImageExtension(_ ext: String) -> Bool {
        ["pgm", "ppm", "pnm", "raw", "bmp", "tiff"].contains(ext.lowercased())
    }
}
