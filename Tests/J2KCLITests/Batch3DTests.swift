// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// Batch3DTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for batch 3D encoding/decoding operations.
final class Batch3DTests: XCTestCase {

    // MARK: - Batch 3D argument parsing

    func testBatch3DEncodeArgs() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "/data/volumes/",
            "--output-dir", "/tmp/encoded3d",
            "--codec", "htj2k-lossless",
            "--recursive"
        ])
        XCTAssertEqual(opts["i"], "/data/volumes/")
        XCTAssertEqual(opts["output-dir"], "/tmp/encoded3d")
        XCTAssertEqual(opts["codec"], "htj2k-lossless")
        XCTAssertEqual(opts["recursive"], "true")
    }

    func testBatch3DDecodeArgs() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "/data/encoded3d/",
            "--output-dir", "/tmp/decoded3d",
            "--raw"
        ])
        XCTAssertEqual(opts["raw"], "true")
    }

    // MARK: - Volume directory detection

    func testVolumeDirectoryStructure() throws {
        let tmpDir = NSTemporaryDirectory() + "j2k_batch3d_test_\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: "\(tmpDir)/vol1", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: "\(tmpDir)/vol2", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: tmpDir) }

        // Create slice files in each volume dir
        for vol in ["vol1", "vol2"] {
            for i in 0..<3 {
                let name = String(format: "slice_%03d.pgm", i)
                try "P5\n2 2\n255\n\0\0\0\0".write(
                    toFile: "\(tmpDir)/\(vol)/\(name)", atomically: true, encoding: .utf8
                )
            }
        }

        let volumes = try fm.contentsOfDirectory(atPath: tmpDir)
        XCTAssertEqual(volumes.count, 2)

        for vol in volumes {
            let slices = try fm.contentsOfDirectory(atPath: "\(tmpDir)/\(vol)")
                .filter { $0.hasSuffix(".pgm") }
            XCTAssertEqual(slices.count, 3)
        }
    }

    // MARK: - Batch processing summary

    func testBatch3DSummary() {
        struct VolumeResult {
            let name: String
            let success: Bool
            let sliceCount: Int
            let outputSize: Int
        }

        let results: [VolumeResult] = [
            VolumeResult(name: "vol1", success: true, sliceCount: 64, outputSize: 1_048_576),
            VolumeResult(name: "vol2", success: true, sliceCount: 128, outputSize: 2_097_152),
            VolumeResult(name: "vol3", success: false, sliceCount: 0, outputSize: 0),
        ]

        let successCount = results.filter(\.success).count
        let totalSlices = results.filter(\.success).map(\.sliceCount).reduce(0, +)
        let totalSize = results.filter(\.success).map(\.outputSize).reduce(0, +)

        XCTAssertEqual(successCount, 2)
        XCTAssertEqual(totalSlices, 192)
        XCTAssertEqual(totalSize, 3_145_728)
    }

    // MARK: - Slice range across volumes

    func testSliceRangePerVolume() {
        let sliceRange = "0-63"
        let parts = sliceRange.split(separator: "-").compactMap { Int($0) }
        XCTAssertEqual(parts.count, 2)

        let start = parts[0]
        let end = parts[1]
        let sliceCount = end - start + 1
        XCTAssertEqual(sliceCount, 64)
    }
}

#endif // os(macOS)
