// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// Decode3DTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCLI

/// Tests for 3D volumetric decoding via the decode3d CLI command.
final class Decode3DTests: XCTestCase {

    // MARK: - Argument parsing

    func testDecode3DBasicParsing() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "volume.j3d",
            "--output-dir", "/tmp/slices"
        ])
        XCTAssertEqual(opts["i"], "volume.j3d")
        XCTAssertEqual(opts["output-dir"], "/tmp/slices")
    }

    func testDecode3DWithSliceRange() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "volume.j3d",
            "--output-dir", "/tmp/slices",
            "--slice-range", "10-20"
        ])
        XCTAssertEqual(opts["slice-range"], "10-20")
    }

    func testDecode3DWithRawOutput() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "volume.j3d",
            "-o", "volume.raw",
            "--raw"
        ])
        XCTAssertEqual(opts["raw"], "true")
        XCTAssertEqual(opts["o"], "volume.raw")
    }

    func testDecode3DWithSlicePattern() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "volume.j3d",
            "--output-dir", "/tmp/slices",
            "--slice-pattern", "slice_%04d.pgm"
        ])
        XCTAssertEqual(opts["slice-pattern"], "slice_%04d.pgm")
    }

    // MARK: - Slice range parsing

    func testSliceRangeParsing() {
        let range = "10-20"
        let parts = range.split(separator: "-").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], 10)
        XCTAssertEqual(parts[1], 20)
    }

    func testSliceRangeSingle() {
        let range = "5-5"
        let parts = range.split(separator: "-").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], 5)
        XCTAssertEqual(parts[1], 5)
    }

    func testSliceRangeValidation() {
        let start = 10
        let end = 20
        XCTAssertLessThanOrEqual(start, end, "Start should be <= end")
        XCTAssertGreaterThanOrEqual(start, 0, "Start should be >= 0")
    }

    // MARK: - Output directory creation

    func testOutputDirectoryCreation() throws {
        let tmpDir = NSTemporaryDirectory() + "j2k_decode3d_test_\(UUID().uuidString)"
        let fm = FileManager.default

        XCTAssertFalse(fm.fileExists(atPath: tmpDir))
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        XCTAssertTrue(fm.fileExists(atPath: tmpDir))

        try fm.removeItem(atPath: tmpDir)
    }

    // MARK: - Slice naming

    func testSliceNamingPattern() {
        let pattern = "slice_%03d.pgm"
        for i in 0..<5 {
            let name = String(format: pattern, i)
            XCTAssertTrue(name.hasSuffix(".pgm"))
            XCTAssertTrue(name.hasPrefix("slice_"))
        }
        XCTAssertEqual(String(format: pattern, 0), "slice_000.pgm")
        XCTAssertEqual(String(format: pattern, 42), "slice_042.pgm")
        XCTAssertEqual(String(format: pattern, 999), "slice_999.pgm")
    }

    func testCustomSlicePattern() {
        let pattern = "ct_scan_%04d.ppm"
        XCTAssertEqual(String(format: pattern, 0), "ct_scan_0000.ppm")
        XCTAssertEqual(String(format: pattern, 123), "ct_scan_0123.ppm")
    }

    func testMakeSliceImagePreserves16BitStride() throws {
        let volume = J2KVolume(
            width: 2,
            height: 1,
            depth: 2,
            components: [
                J2KVolumeComponent(
                    index: 0,
                    bitDepth: 16,
                    signed: false,
                    width: 2,
                    height: 1,
                    depth: 2,
                    data: Data([0x00, 0x10, 0x00, 0x20, 0x00, 0x30, 0x00, 0x40])
                )
            ]
        )

        let slice0 = try J2KCLI.makeSliceImage(from: volume, atDepth: 0)
        let slice1 = try J2KCLI.makeSliceImage(from: volume, atDepth: 1)

        XCTAssertEqual(slice0.components[0].data, Data([0x00, 0x10, 0x00, 0x20]))
        XCTAssertEqual(slice1.components[0].data, Data([0x00, 0x30, 0x00, 0x40]))
        XCTAssertEqual(slice0.components[0].bitDepth, 16)
    }
}

#endif // os(macOS)
