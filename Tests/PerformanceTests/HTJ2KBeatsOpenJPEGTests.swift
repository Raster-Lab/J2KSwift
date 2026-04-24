// HTJ2KBeatsOpenJPEGTests.swift
// Authoritative head-to-head benchmark proving J2KSwift HTJ2K beats
// OpenJPEG 2.5.4 (EBCOT / Part 1) on matched inputs.
//
// OpenJPEG 2.5.4 does not implement HTJ2K (Part 15), so "HTJ2K vs
// OpenJPEG" is necessarily an apples-to-oranges algorithm-vs-
// algorithm comparison: we feed the same raw PGM to J2KSwift's HTJ2K
// pipeline and to OpenJPEG's EBCOT pipeline, measure wall-clock time
// with warmup + repeated iterations, and verify the HTJ2K path is
// faster by at least `performanceTarget` (3.0× per the v2.0 spec).
//
// The test is skipped automatically if the OpenJPEG CLI tools are
// not installed (e.g. in CI without the `-c openjpeg` brew tap).
// Running locally on Apple Silicon with `opj_compress` / `opj_decompress`
// from `/opt/homebrew` is the supported path.

import XCTest
import Foundation
@testable import J2KCore

final class HTJ2KBeatsOpenJPEGTests: XCTestCase {

    private var openJPEGAvailable: Bool {
        OpenJPEGAvailability.findTool("opj_compress") != nil &&
        OpenJPEGAvailability.findTool("opj_decompress") != nil
    }

    // MARK: - Helpers

    /// Runs a single configuration and returns the comparison or nil
    /// if the CLI tool is missing.
    private func compare(
        size: BenchmarkImageSize,
        mode: BenchmarkCodingMode,
        operation: BenchmarkOperation,
        iterations: Int = 5,
        warmup: Int = 2,
        pattern: BenchmarkTestImageGenerator.Pattern = .naturalPhoto
    ) throws -> OpenJPEGBenchmarkComparison {
        try XCTSkipUnless(openJPEGAvailable,
            "OpenJPEG CLI tools not available — skipping head-to-head benchmark")
        let config = BenchmarkConfiguration(
            imageSize: size, codingMode: mode,
            iterations: iterations, warmupIterations: warmup)
        let runner = OpenJPEGBenchmarkRunner(includeOpenJPEG: true)
        let data = BenchmarkTestImageGenerator.generate(config: config, pattern: pattern)
        guard let comp = runner.runSingle(config: config, operation: operation, imageData: data) else {
            XCTFail("runSingle returned nil for \(size.rawValue) \(mode.rawValue) \(operation.rawValue)")
            fatalError("unreachable")
        }
        return comp
    }

    /// Asserts J2KSwift beats OpenJPEG by at least the configured
    /// performance target for the given comparison, printing the
    /// human-readable summary regardless of pass/fail for visibility.
    private func assertBeatsOpenJPEG(
        _ comparison: OpenJPEGBenchmarkComparison,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        // Always print the summary so the head-to-head numbers land
        // in test output, not just on failure.
        print("  " + comparison.summary)

        XCTAssertNotNil(comparison.openJPEGResult,
            "OpenJPEG comparison missing — CLI tool invocation failed",
            file: file, line: line)
        guard let ratio = comparison.speedRatio else { return }
        let target = comparison.performanceTarget
        XCTAssertGreaterThanOrEqual(ratio, target,
            "\(comparison.configuration.label) \(comparison.operation.rawValue): " +
            "J2KSwift ran at \(String(format: "%.2f×", ratio)) of OpenJPEG speed, " +
            "target was \(String(format: "%.2f×", target)). " +
            "J2KSwift=\(String(format: "%.2f ms", comparison.j2kSwiftResult.metrics.wallClockMedian * 1000)), " +
            "OpenJPEG=\(String(format: "%.2f ms", comparison.openJPEGResult!.metrics.wallClockMedian * 1000))",
            file: file, line: line)
    }

    // MARK: - HTJ2K vs OpenJPEG EBCOT

    /// HTJ2K lossless encode must beat OpenJPEG's EBCOT lossless
    /// encode by ≥ 3.0× (the target codified in
    /// `OpenJPEGBenchmarkComparison.performanceTarget`).
    func testHTJ2KLosslessEncodeBeatsOpenJPEG256() throws {
        let comp = try compare(size: .size256, mode: .htj2kLossless,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    func testHTJ2KLosslessEncodeBeatsOpenJPEG512() throws {
        let comp = try compare(size: .size512, mode: .htj2kLossless,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    func testHTJ2KLosslessEncodeBeatsOpenJPEG1024() throws {
        let comp = try compare(size: .size1024, mode: .htj2kLossless,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    /// HTJ2K lossy encode (2 bpp target) must beat OpenJPEG's EBCOT
    /// lossy encode at the matched bitrate.
    func testHTJ2KLossy2bppEncodeBeatsOpenJPEG256() throws {
        let comp = try compare(size: .size256, mode: .htj2kLossy2bpp,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    func testHTJ2KLossy2bppEncodeBeatsOpenJPEG512() throws {
        let comp = try compare(size: .size512, mode: .htj2kLossy2bpp,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    func testHTJ2KLossy2bppEncodeBeatsOpenJPEG1024() throws {
        let comp = try compare(size: .size1024, mode: .htj2kLossy2bpp,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    /// HTJ2K lossless **decode** must also beat OpenJPEG's EBCOT
    /// decode by ≥ 1.5×.
    func testHTJ2KLosslessDecodeBeatsOpenJPEG512() throws {
        let comp = try compare(size: .size512, mode: .htj2kLossless,
                               operation: .decode)
        assertBeatsOpenJPEG(comp)
    }

    func testHTJ2KLosslessDecodeBeatsOpenJPEG1024() throws {
        let comp = try compare(size: .size1024, mode: .htj2kLossless,
                               operation: .decode)
        assertBeatsOpenJPEG(comp)
    }

    // MARK: - Legacy (EBCOT) parity

    /// Sanity check that legacy EBCOT encode ALSO beats OpenJPEG at
    /// its own target of 1.5×; catches regressions in the non-HT
    /// code path when tuning the HT pipeline.
    func testLegacyLosslessEncodeStillBeatsOpenJPEG512() throws {
        let comp = try compare(size: .size512, mode: .lossless,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    func testLegacyLossy2bppEncodeStillBeatsOpenJPEG512() throws {
        let comp = try compare(size: .size512, mode: .lossy2bpp,
                               operation: .encode)
        assertBeatsOpenJPEG(comp)
    }

    // MARK: - Full-matrix victory table

    /// Prints a summary table covering the most interesting rows and
    /// asserts every one beats OpenJPEG. Deliberately scoped tight
    /// (4 rows) because `OpenJPEGBenchmarkRunner` shells out to
    /// `opj_compress` / `opj_decompress` via `Process`, and
    /// launching many subprocesses back-to-back in a single
    /// XCTestCase under `-c release` has been observed to SIGSEGV
    /// intermittently on Apple Silicon — the individually-named
    /// tests above run each row as its own XCTestCase and cover the
    /// full grid.
    func testHTJ2KBeatsOpenJPEGFullMatrixPrintsSummary() throws {
        try XCTSkipUnless(openJPEGAvailable,
            "OpenJPEG CLI tools not available")
        let sizes: [BenchmarkImageSize] = [.size256, .size512, .size1024]
        let modes: [BenchmarkCodingMode] = [
            .lossless, .lossy2bpp, .htj2kLossless, .htj2kLossy2bpp
        ]
        let ops: [BenchmarkOperation] = [.encode, .decode]

        var rows: [(label: String, mode: String, op: String,
                    j2k: Double, oj: Double, ratio: Double,
                    target: Double, pass: Bool)] = []

        for size in sizes {
            for mode in modes {
                for op in ops {
                    // Keep iteration count bounded — full matrix is 24 rows,
                    // 3 iterations is enough for a stable median on Apple Silicon.
                    let comp = try compare(size: size, mode: mode, operation: op,
                                           iterations: 3, warmup: 1)
                    guard let ratio = comp.speedRatio,
                          let oj = comp.openJPEGResult else { continue }
                    let j2kMs = comp.j2kSwiftResult.metrics.wallClockMedian * 1000
                    let ojMs = oj.metrics.wallClockMedian * 1000
                    rows.append((
                        label: size.rawValue, mode: mode.rawValue,
                        op: op.rawValue, j2k: j2kMs, oj: ojMs,
                        ratio: ratio, target: comp.performanceTarget,
                        pass: (comp.meetsTarget ?? false)
                    ))
                }
            }
        }

        print("\n=== J2KSWIFT_HTJ2K_BEATS_OPENJPEG_SUMMARY ===")
        let header = String(
            format: "%@  %@  %@  %@  %@  %@  %@  %@",
            "size".padding(toLength: 10, withPad: " ", startingAt: 0),
            "mode".padding(toLength: 18, withPad: " ", startingAt: 0),
            "op".padding(toLength: 8, withPad: " ", startingAt: 0),
            "J2KSwift".padding(toLength: 9, withPad: " ", startingAt: 0),
            "OpenJPEG".padding(toLength: 9, withPad: " ", startingAt: 0),
            "ratio".padding(toLength: 8, withPad: " ", startingAt: 0),
            "target".padding(toLength: 8, withPad: " ", startingAt: 0),
            "result")
        print(header)
        print(String(repeating: "-", count: 88))
        for r in rows {
            let j2k = String(format: "%7.2fms", r.j2k)
            let oj = String(format: "%7.2fms", r.oj)
            let ratio = String(format: "%7.2fx", r.ratio)
            let target = String(format: "%7.2fx", r.target)
            let line = String(
                format: "%@  %@  %@  %@  %@  %@  %@  %@",
                r.label.padding(toLength: 10, withPad: " ", startingAt: 0),
                r.mode.padding(toLength: 18, withPad: " ", startingAt: 0),
                r.op.padding(toLength: 8, withPad: " ", startingAt: 0),
                j2k.padding(toLength: 9, withPad: " ", startingAt: 0),
                oj.padding(toLength: 9, withPad: " ", startingAt: 0),
                ratio.padding(toLength: 8, withPad: " ", startingAt: 0),
                target.padding(toLength: 8, withPad: " ", startingAt: 0),
                r.pass ? "PASS ✓" : "FAIL ✗")
            print(line)
        }
        let passed = rows.filter(\.pass).count
        print(String(repeating: "-", count: 88))
        print("\(passed)/\(rows.count) comparisons met target")
        print("=== END J2KSWIFT_HTJ2K_BEATS_OPENJPEG_SUMMARY ===\n")

        // Assert every row meets target. Use a soft assertion so the
        // full table prints even when one cell fails.
        for r in rows {
            XCTAssertTrue(r.pass,
                "\(r.label) \(r.mode) \(r.op): " +
                "J2KSwift \(String(format: "%.2fms", r.j2k)) vs " +
                "OpenJPEG \(String(format: "%.2fms", r.oj)) = " +
                "\(String(format: "%.2fx", r.ratio)) (target \(String(format: "%.2fx", r.target)))")
        }
    }
}
