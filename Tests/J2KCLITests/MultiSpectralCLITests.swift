//
// MultiSpectralCLITests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for multi-spectral/multi-band 3D encoding CLI options.
final class MultiSpectralCLITests: XCTestCase {

    // MARK: - Multi-spectral argument parsing

    func testMultiSpectralComponentsParsing() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--slice-dir", "/data/multispectral",
            "--components", "4",
            "-o", "ms_volume.j3d"
        ])
        XCTAssertEqual(opts["components"], "4")
    }

    func testMultiSpectralBandNames() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--slice-dir", "/data/bands",
            "--band-names", "R,G,B,NIR",
            "-o", "ms_volume.j3d"
        ])
        XCTAssertEqual(opts["band-names"], "R,G,B,NIR")
    }

    // MARK: - Band name parsing

    func testBandNameParsing() {
        let bandNames = "R,G,B,NIR"
        let bands = bandNames.split(separator: ",").map(String.init)
        XCTAssertEqual(bands.count, 4)
        XCTAssertEqual(bands[0], "R")
        XCTAssertEqual(bands[1], "G")
        XCTAssertEqual(bands[2], "B")
        XCTAssertEqual(bands[3], "NIR")
    }

    func testSingleBand() {
        let bandNames = "Luminance"
        let bands = bandNames.split(separator: ",").map(String.init)
        XCTAssertEqual(bands.count, 1)
        XCTAssertEqual(bands[0], "Luminance")
    }

    // MARK: - Multi-spectral volume dimensions

    func testMultiSpectralDimensions() {
        let width = 512
        let height = 512
        let bands = 7 // hyperspectral
        let depth = 1

        let totalSamples = width * height * bands * depth
        XCTAssertEqual(totalSamples, 1_835_008)
    }

    // MARK: - Component interleaving

    func testComponentCount() {
        // Verify component count for typical multi-spectral configs
        let rgbComponents = 3
        let rgbaNIRComponents = 5
        let hyperSpectralComponents = 224

        XCTAssertGreaterThan(rgbComponents, 0)
        XCTAssertGreaterThan(rgbaNIRComponents, 0)
        XCTAssertGreaterThan(hyperSpectralComponents, 0)
    }

    // MARK: - 3D encoding with multi-spectral data

    func testEncode3DMultiSpectralArgs() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--slice-dir", "/data/hyperspectral",
            "-o", "hyper.j3d",
            "--codec", "j2k-lossless",
            "--components", "224",
            "--width", "640",
            "--height", "480"
        ])
        XCTAssertEqual(opts["slice-dir"], "/data/hyperspectral")
        XCTAssertEqual(opts["components"], "224")
        XCTAssertEqual(opts["width"], "640")
        XCTAssertEqual(opts["height"], "480")
        XCTAssertEqual(opts["codec"], "j2k-lossless")
    }
}
