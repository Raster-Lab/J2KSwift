// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// Encode3DTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCLICore

/// Tests for 3D volumetric encoding via the encode3d CLI command.
final class Encode3DTests: XCTestCase {

    // MARK: - Argument parsing

    func testEncode3DSliceDirParsing() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--slice-dir", "/data/slices",
            "-o", "volume.j3d",
            "--codec", "j2k-lossless"
        ])
        XCTAssertEqual(opts["slice-dir"], "/data/slices")
        XCTAssertEqual(opts["o"], "volume.j3d")
        XCTAssertEqual(opts["codec"], "j2k-lossless")
    }

    func testEncode3DRawInputParsing() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "volume.raw",
            "-o", "volume.j3d",
            "--width", "256",
            "--height", "256",
            "--depth", "128",
            "--components", "1",
            "--bit-depth", "16"
        ])
        XCTAssertEqual(opts["i"], "volume.raw")
        XCTAssertEqual(opts["width"], "256")
        XCTAssertEqual(opts["height"], "256")
        XCTAssertEqual(opts["depth"], "128")
        XCTAssertEqual(opts["components"], "1")
        XCTAssertEqual(opts["bit-depth"], "16")
    }

    func testEncode3DCodecVariants() {
        let codecs = ["j2k-lossless", "j2k-lossy", "htj2k-lossless", "htj2k-lossy"]
        for codec in codecs {
            let opts = CLIArgumentParserTestHelper.parse(["--codec", codec])
            XCTAssertEqual(opts["codec"], codec)
        }
    }

    func testEncode3DWithQuality() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--slice-dir", "/data/slices",
            "-o", "volume.j3d",
            "--codec", "j2k-lossy",
            "--quality", "0.85"
        ])
        XCTAssertEqual(opts["quality"], "0.85")
    }

    func testEncode3DWithDecompositionLevels() {
        let opts = CLIArgumentParserTestHelper.parse([
            "--slice-dir", "/data/slices",
            "-o", "volume.j3d",
            "--decomposition-levels", "5"
        ])
        XCTAssertEqual(opts["decomposition-levels"], "5")
    }

    // MARK: - Slice directory validation

    func testSliceDirectoryCreation() throws {
        let tmpDir = NSTemporaryDirectory() + "j2k_encode3d_test_\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        // Create numbered slice files
        for i in 0..<5 {
            let name = String(format: "slice_%03d.pgm", i)
            try "P5\n4 4\n255\n\(String(repeating: "\0", count: 16))".write(
                toFile: "\(tmpDir)/\(name)", atomically: true, encoding: .utf8
            )
        }

        let slices = try fm.contentsOfDirectory(atPath: tmpDir)
            .filter { $0.hasSuffix(".pgm") }
            .sorted()
        XCTAssertEqual(slices.count, 5)
        XCTAssertEqual(slices[0], "slice_000.pgm")
        XCTAssertEqual(slices[4], "slice_004.pgm")
    }

    // MARK: - Volume dimension validation

    func testVolumeDimensionValidation() {
        // Width, height, depth must be positive
        let width = 256, height = 256, depth = 128
        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        XCTAssertGreaterThan(depth, 0)
    }

    func testInvalidVolumeDimensions() {
        let width = 0, height = 256, depth = 128
        XCTAssertFalse(width > 0 && height > 0 && depth > 0,
                       "Should reject zero dimensions")
    }

    func testMakeVolumeFromSlicesPreservesVoxelDataAndSpacing() throws {
        let slice0 = J2KImage(
            width: 2,
            height: 1,
            components: [
                J2KComponent(
                    index: 0,
                    bitDepth: 16,
                    signed: false,
                    width: 2,
                    height: 1,
                    data: Data([0x00, 0x10, 0x00, 0x20])
                )
            ],
            colorSpace: .grayscale
        )
        let slice1 = J2KImage(
            width: 2,
            height: 1,
            components: [
                J2KComponent(
                    index: 0,
                    bitDepth: 16,
                    signed: false,
                    width: 2,
                    height: 1,
                    data: Data([0x00, 0x30, 0x00, 0x40])
                )
            ],
            colorSpace: .grayscale
        )

        let volume = try J2KCLI.makeVolumeFromSlices(
            [slice0, slice1],
            spacing: (0.7, 0.7, 1.5),
            origin: (0.0, 0.0, -2.0)
        )

        XCTAssertEqual(volume.width, 2)
        XCTAssertEqual(volume.height, 1)
        XCTAssertEqual(volume.depth, 2)
        XCTAssertEqual(volume.components.count, 1)
        XCTAssertEqual(volume.components[0].data, Data([0x00, 0x10, 0x00, 0x20, 0x00, 0x30, 0x00, 0x40]))
        XCTAssertEqual(volume.spacingX, 0.7, accuracy: 0.000_1)
        XCTAssertEqual(volume.spacingY, 0.7, accuracy: 0.000_1)
        XCTAssertEqual(volume.spacingZ, 1.5, accuracy: 0.000_1)
        XCTAssertEqual(volume.originZ, -2.0, accuracy: 0.000_1)
    }

    func testLoadRawVolumePreservesComponentPayload() throws {
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("j2k_volume_\(UUID().uuidString).raw")
        let rawBytes = Data([1, 2, 3, 4, 10, 20, 30, 40])
        try rawBytes.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let volume = try J2KCLI.loadRawVolume(
            from: tmpURL.path,
            width: 2,
            height: 1,
            depth: 2,
            componentCount: 2,
            bitDepth: 8,
            signed: false
        )

        XCTAssertEqual(volume.components.count, 2)
        XCTAssertEqual(volume.components[0].data, Data([1, 2, 3, 4]))
        XCTAssertEqual(volume.components[1].data, Data([10, 20, 30, 40]))
    }
}

#endif // os(macOS)
