// v8 Phase 6.2 — J2KCLI is a macOS-only executable target. Tests gated accordingly.
#if os(macOS)
//
// TranscodeBatchTests.swift
// J2KSwift
//
import XCTest
import Foundation
@testable import J2KCore

/// Tests for batch transcoding operations.
final class TranscodeBatchTests: XCTestCase {

    // MARK: - Batch transcode argument parsing

    func testBatchTranscodeArgs() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "j2k_dir/",
            "--output-dir", "/tmp/htj2k",
            "--codec", "htj2k-lossless",
            "--recursive",
            "--threads", "4",
            "--progress"
        ])
        XCTAssertEqual(opts["i"], "j2k_dir/")
        XCTAssertEqual(opts["output-dir"], "/tmp/htj2k")
        XCTAssertEqual(opts["codec"], "htj2k-lossless")
        XCTAssertEqual(opts["recursive"], "true")
        XCTAssertEqual(opts["threads"], "4")
        XCTAssertEqual(opts["progress"], "true")
    }

    func testBatchTranscodeWithVerify() {
        let opts = CLIArgumentParserTestHelper.parse([
            "-i", "j2k_dir/",
            "--output-dir", "/tmp/htj2k",
            "--codec", "htj2k-lossless",
            "--verify",
            "--verify-mode", "exact"
        ])
        XCTAssertEqual(opts["verify"], "true")
        XCTAssertEqual(opts["verify-mode"], "exact")
    }

    // MARK: - Output path resolution

    func testOutputPathGeneration() {
        // Given an input file and output dir, generate output path
        let inputPath = "/data/images/scan001.j2k"
        let outputDir = "/tmp/transcoded"
        let outputSuffix = ".jph"

        let filename = (inputPath as NSString).lastPathComponent
        let basename = (filename as NSString).deletingPathExtension
        let outputPath = "\(outputDir)/\(basename)\(outputSuffix)"

        XCTAssertEqual(outputPath, "/tmp/transcoded/scan001.jph")
    }

    func testOutputPathPreservesSubdirectory() {
        // With recursive processing, preserve directory structure
        let inputBase = "/data/images"
        let inputPath = "/data/images/subdir/scan001.j2k"
        let outputDir = "/tmp/transcoded"

        let relativePath = String(inputPath.dropFirst(inputBase.count + 1))
        let relativeDir = (relativePath as NSString).deletingLastPathComponent
        let filename = (relativePath as NSString).lastPathComponent
        let basename = (filename as NSString).deletingPathExtension

        let outputPath = "\(outputDir)/\(relativeDir)/\(basename).jph"
        XCTAssertEqual(outputPath, "/tmp/transcoded/subdir/scan001.jph")
    }

    // MARK: - File filtering

    func testFilterJ2KFiles() {
        let files = ["image1.j2k", "image2.jp2", "readme.txt", "image3.jph", "notes.md"]
        let j2kExtensions = Set(["j2k", "jp2", "j2c", "jpx", "jph"])
        let filtered = files.filter { file in
            let ext = (file as NSString).pathExtension.lowercased()
            return j2kExtensions.contains(ext)
        }
        XCTAssertEqual(filtered.count, 3)
        XCTAssertTrue(filtered.contains("image1.j2k"))
        XCTAssertTrue(filtered.contains("image2.jp2"))
        XCTAssertTrue(filtered.contains("image3.jph"))
    }

    // MARK: - Summary computation

    func testBatchSummary() {
        let startTime = Date()
        let results: [(file: String, success: Bool, inputSize: Int, outputSize: Int)] = [
            ("a.j2k", true, 1024, 512),
            ("b.j2k", true, 2048, 1024),
            ("c.j2k", false, 3072, 0),
        ]

        let successCount = results.filter(\.success).count
        let failureCount = results.filter { !$0.success }.count
        let totalInputSize = results.filter(\.success).map(\.inputSize).reduce(0, +)
        let totalOutputSize = results.filter(\.success).map(\.outputSize).reduce(0, +)

        XCTAssertEqual(successCount, 2)
        XCTAssertEqual(failureCount, 1)
        XCTAssertEqual(totalInputSize, 3072)
        XCTAssertEqual(totalOutputSize, 1536)

        let compressionRatio = Double(totalInputSize) / Double(totalOutputSize)
        XCTAssertEqual(compressionRatio, 2.0, accuracy: 0.01)
    }
}

#endif // os(macOS)
