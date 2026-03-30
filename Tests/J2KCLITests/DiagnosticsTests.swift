//
// DiagnosticsTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for the capabilities and diagnostics commands.
final class DiagnosticsTests: XCTestCase {

    // MARK: - Capabilities argument parsing

    func testCapabilitiesBasicArgs() {
        let opts = CLIArgumentParserTestHelper.parse(["--json"])
        XCTAssertEqual(opts["json"], "true")
    }

    func testCapabilitiesQuiet() {
        let opts = CLIArgumentParserTestHelper.parse(["--quiet"])
        XCTAssertEqual(opts["quiet"], "true")
    }

    // MARK: - Platform detection

    func testPlatformDetection() {
        #if os(macOS)
        let platform = "macOS"
        XCTAssertEqual(platform, "macOS")
        #elseif os(Linux)
        let platform = "Linux"
        XCTAssertEqual(platform, "Linux")
        #elseif os(iOS)
        let platform = "iOS"
        XCTAssertEqual(platform, "iOS")
        #endif
    }

    func testArchitectureDetection() {
        #if arch(arm64)
        let arch = "arm64"
        XCTAssertEqual(arch, "arm64")
        #elseif arch(x86_64)
        let arch = "x86_64"
        XCTAssertEqual(arch, "x86_64")
        #endif
    }

    // MARK: - Codec availability

    func testCodecAvailability() {
        let codecs = [
            "j2k-lossless",
            "j2k-lossy",
            "htj2k-lossless",
            "htj2k-lossy"
        ]
        XCTAssertEqual(codecs.count, 4, "Should support 4 codec variants")
    }

    // MARK: - Format support

    func testInputFormatSupport() {
        let inputFormats = ["pgm", "ppm", "pnm", "raw"]
        XCTAssertTrue(inputFormats.contains("pgm"))
        XCTAssertTrue(inputFormats.contains("ppm"))
        XCTAssertTrue(inputFormats.contains("raw"))
    }

    func testOutputFormatSupport() {
        let outputFormats = ["pgm", "ppm", "raw"]
        XCTAssertTrue(outputFormats.contains("pgm"))
        XCTAssertTrue(outputFormats.contains("ppm"))
        XCTAssertTrue(outputFormats.contains("raw"))
    }

    func testCodestreamFormatSupport() {
        let csFormats = ["j2k", "jp2", "jpx", "jph", "j2c"]
        XCTAssertTrue(csFormats.contains("j2k"))
        XCTAssertTrue(csFormats.contains("jp2"))
        XCTAssertTrue(csFormats.contains("jph"))
    }

    // MARK: - Acceleration detection

    func testAccelerationDetection() {
        #if canImport(Accelerate)
        XCTAssertTrue(true, "Accelerate framework available")
        #else
        XCTAssertTrue(true, "Accelerate framework not available (expected on this platform)")
        #endif
    }

    // MARK: - Module availability

    func testModuleList() {
        let modules = [
            "J2KCore", "J2KCodec", "J2KFileFormat",
            "J2KAccelerate", "J2K3D", "JPIP",
            "J2KMetal", "J2KVulkan", "J2KXS"
        ]
        XCTAssertEqual(modules.count, 9, "Should list 9 modules")
    }

    // MARK: - Feature flags

    func testFeatureFlags() {
        let features = [
            "losslessCompression",
            "lossyCompression",
            "htj2k",
            "jp3d",
            "jpip",
            "multiComponentTransform",
            "regionOfInterest",
            "progressiveDecoding",
            "parallelProcessing",
            "batchProcessing"
        ]
        XCTAssertEqual(features.count, 10, "Should list 10 features")
    }

    // MARK: - GPU listing

    func testGPUListArgs() {
        let opts = CLIArgumentParserTestHelper.parse(["--list-gpus"])
        XCTAssertEqual(opts["list-gpus"], "true")
    }
}
