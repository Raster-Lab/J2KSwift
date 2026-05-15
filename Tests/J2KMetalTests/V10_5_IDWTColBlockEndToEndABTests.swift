// V10_5_IDWTColBlockEndToEndABTests.swift
//
// v10.5-research Phase 4 — end-to-end warm A/B bench. Decodes the
// real MG / DX / PX medical-real corpus through the lossless 5/3
// HT-conformant path with `columnBlockLiftEnabled` toggled OFF then
// ON. Median of 7 timed runs + 2 warmups per (fixture × path).
//
// Acceptance gate (v7.4 discipline): default-on requires ≥3 ms
// wall improvement on at least one MG/DX/PX fixture AND no
// ≥3 ms regression on any fixture (small or large).
//
// Run with:
//   swift test -c release --filter V10_5_IDWTColBlockEndToEndABTests

import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_5_IDWTColBlockEndToEndABTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    /// Real medical corpus across decode-time tiers: largest first
    /// (MG ~16.8 MP) so any A/B noise hits the most-saturated
    /// fixtures before the small ones.
    private static let corpus: [Fixture] = [
        Fixture(label: "MG small 3516×4784",  filename: "medical-real/mg_real_small_3516x4784.pgm"),
        Fixture(label: "MG mid 3518×4784",    filename: "medical-real/mg_real_mid_3518x4784.pgm"),
        Fixture(label: "MG large 3521×4784",  filename: "medical-real/mg_real_large_3521x4784.pgm"),
        Fixture(label: "DX 2800×2288",        filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX small 2224×2798",  filename: "medical-real/dx_real_small_2224x2798.pgm"),
        Fixture(label: "DX large 2544×3056",  filename: "medical-real/dx_real_large_2544x3056.pgm"),
        Fixture(label: "PX 2459×1316",        filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX mid 2793×1316",    filename: "medical-real/px_real_mid_2793x1316.pgm"),
        Fixture(label: "PX large 2812×1316",  filename: "medical-real/px_real_large_2812x1316.pgm"),
        // Small-fixture regression check — make sure the new path
        // doesn't pay an overhead penalty on sub-32×32 paths or
        // the small-image branch.
        Fixture(label: "XA 1024²",            filename: "xa_study_001_instance_000001.pgm"),
        Fixture(label: "CT 512²",             filename: "ct_study_001_instance_000001.pgm"),
        Fixture(label: "MR-small 180²",       filename: "mr_study_002_instance_000100.pgm"),
    ]

    private func loadPGM16(_ filename: String) throws -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path) else { return nil }
        let raw = try Data(contentsOf: here)
        var i = 2
        var fields: [Int] = []
        while i < raw.count, fields.count < 3 {
            let b = raw[i]
            if b == 0x23 { while i < raw.count, raw[i] != 0x0A { i += 1 }; continue }
            if [0x20, 0x09, 0x0A, 0x0D].contains(b) { i += 1; continue }
            var num = 0
            while i < raw.count {
                let c = raw[i]
                if [0x20, 0x09, 0x0A, 0x0D].contains(c) { break }
                num = num * 10 + Int(c - 0x30); i += 1
            }
            fields.append(num)
        }
        if i < raw.count, [0x20, 0x09, 0x0A, 0x0D].contains(raw[i]) { i += 1 }
        return J2KImage(
            width: fields[0], height: fields[1],
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: fields[0], height: fields[1],
                data: raw.subdata(in: i..<raw.count),
                sampleByteOrder: .bigEndian)])
    }

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func bench(
        decoder: J2KDecoder, codestream: Data, n: Int, warmups: Int
    ) async throws -> Double {
        for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
        var times: [Double] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try await decoder.decode(codestream)
            times.append(Date().timeIntervalSince(t0) * 1000)
        }
        return times.sorted()[n / 2]
    }

    func testColumnBlockEndToEndAB_MedicalCorpus() async throws {
        let n = 7
        let warmups = 2
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        struct Row {
            let label: String
            let pixels: Int
            let canonicalMs: Double
            let probeMs: Double
            let delta: Double
            let pct: Double
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }
            let codestream = try await encoder.encode(image)

            // Canonical first — transpose + lift + untranspose path.
            J2KDWT2DOptimizer.columnBlockLiftEnabled = false
            let canonicalMs = try await bench(
                decoder: decoder, codestream: codestream,
                n: n, warmups: warmups)

            // Probe — row-major column-block lift.
            J2KDWT2DOptimizer.columnBlockLiftEnabled = true
            let probeMs = try await bench(
                decoder: decoder, codestream: codestream,
                n: n, warmups: warmups)

            let delta = canonicalMs - probeMs
            let pct = 100 * delta / canonicalMs
            rows.append(Row(
                label: fix.label, pixels: image.width * image.height,
                canonicalMs: canonicalMs, probeMs: probeMs,
                delta: delta, pct: pct))
        }

        // Restore default-on.
        J2KDWT2DOptimizer.columnBlockLiftEnabled = true

        print("=== v10.5 column-block IDWT end-to-end A/B (M2 release, in-proc) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Runs: \(n)")
        if !skipped.isEmpty {
            print("Skipped (fixture missing): \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | canonical ms | column-block ms | Δ ms | Δ % |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.2f | %+5.1f%% |",
                         r.label, r.pixels,
                         r.canonicalMs, r.probeMs, r.delta, r.pct))
        }
        print("")
        print("Reading: positive Δ ms = column-block faster (probe wins).")
        print("Acceptance gate (v7.4): ≥3 ms wall lift on at least one MG/DX/PX,")
        print("                        AND no fixture regresses by ≥3 ms.")

        XCTAssertFalse(rows.isEmpty, "No fixtures benched — corpus layout changed?")
    }
}
