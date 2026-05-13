// V10Phase7FusionFeasibilityTests.swift
//
// v10.0-research Phase 7: cross-stage fusion (DWT + quantise +
// entropy single-pass) feasibility microbench.
//
// The v10.0 plan flagged cross-stage fusion as the v11.0 candidate.
// Multi-week scope, high risk, requires architectural rewrite of the
// encoder hot path. Before committing to that work, this phase
// produces a measurement-grade estimate of the upper bound on
// fusion savings.
//
// Approach: decompose the encode wall into (a) stage compute time,
// recorded by J2KEncodeTimings at stage boundaries, and (b) overhead
// = wall − sum(stage). The overhead is what fusion COULD remove —
// it's intermediate buffer allocation, materialisation between
// stages, inter-stage glue, and dispatcher cost. Fusion realistically
// eliminates 50-70 % of this overhead (the buffer allocs are gone
// entirely; some dispatcher and ordering cost remains for parallel
// fusion). Reporting "max fusion savings (100 %)" and "realistic
// fusion savings (50 %)" lets the v11.0 decision use this number
// as a scope estimate.
//
// Single-tile mode forced (envMode = .single) so wall ≈ sum(stages)
// is interpretable. Multi-tile mode would have stage CPU summed
// across workers and require deflation by an effective-worker count
// — that's Phase 1's caveat and isn't useful for fusion projection.
//
// Run with:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test -c release --filter V10Phase7FusionFeasibilityTests

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10Phase7FusionFeasibilityTests: XCTestCase {

    private func loadPGM16(_ filename: String) -> J2KImage? {
        let here = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/CrossCodec/\(filename)")
        guard FileManager.default.fileExists(atPath: here.path),
              let raw = try? Data(contentsOf: here) else { return nil }
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

    private struct CorpusFixture {
        let label: String
        let filename: String
    }

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "MR-small 180²",   filename: "mr_study_002_instance_000100.pgm"),
        CorpusFixture(label: "CT 512² (1)",     filename: "ct_study_001_instance_000001.pgm"),
        CorpusFixture(label: "CT 512² (2)",     filename: "ct_study_003_instance_000050.pgm"),
        CorpusFixture(label: "MR 886²",         filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",        filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316",    filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288",    filename: "dx_study_002_instance_000001.pgm"),
    ]

    private func htLosslessConfig(maxThreads: Int) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.maxThreads = maxThreads
        return cfg
    }

    private struct Row {
        let label: String
        let pixels: Int
        let totalMs: Double          // end-to-end encode wall (median)
        let preprocess: Double       // J2KEncodeTimings stage means (ms)
        let colour: Double
        let dwt: Double
        let quant: Double
        let entropy: Double
        let rateCtrl: Double
        let codestream: Double

        var stageSum: Double {
            preprocess + colour + dwt + quant + entropy + rateCtrl + codestream
        }
        /// "Overhead" = end-to-end wall − sum of stage walls.
        /// This is the time NOT spent in any timed stage — intermediate
        /// buffer allocation, materialisation, dispatcher glue.
        var overhead: Double { totalMs - stageSum }
        var overheadPct: Double { totalMs > 0 ? 100.0 * overhead / totalMs : 0 }
    }

    /// Phase 7 deliverable — per-fixture fusion-savings projection on
    /// the medical corpus, single-tile mode for interpretability.
    func testFusionFeasibilityProjection_SingleTile() async throws {
        #if DEBUG
        print("⚠️  Phase 7 in DEBUG mode; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter V10Phase7FusionFeasibilityTests")
        #endif

        // Force single-tile mode so wall ≈ sum(stages) — Phase 1's
        // multi-tile caveat doesn't apply.
        let savedTileMode = J2KEncodeTilePlanner.envMode
        defer { J2KEncodeTilePlanner.envMode = savedTileMode }
        J2KEncodeTilePlanner.envMode = .single

        let runs = 5
        let cfg = htLosslessConfig(maxThreads: 1)
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warmup (excluded).
            _ = try await encoder.encode(image)

            var times: [TimeInterval] = []
            var sumPre: TimeInterval = 0, sumCol: TimeInterval = 0
            var sumDWT: TimeInterval = 0, sumQuant: TimeInterval = 0
            var sumEnt: TimeInterval = 0, sumRate: TimeInterval = 0
            var sumCS: TimeInterval = 0

            for _ in 0..<runs {
                J2KEncodeTimings.reset()
                let t0 = Date()
                _ = try await encoder.encode(image)
                times.append(Date().timeIntervalSince(t0))
                let s = J2KEncodeTimings.snapshot()
                sumPre += s.preprocessing
                sumCol += s.colorTransform
                sumDWT += s.waveletTransform
                sumQuant += s.quantization
                sumEnt += s.entropyCoding
                sumRate += s.rateControl
                sumCS += s.codestreamGeneration
            }
            let median = times.sorted()[runs / 2] * 1000.0
            let scale = 1000.0 / Double(runs)
            rows.append(Row(
                label: fix.label, pixels: image.width * image.height,
                totalMs: median,
                preprocess: sumPre * scale,
                colour: sumCol * scale,
                dwt: sumDWT * scale,
                quant: sumQuant * scale,
                entropy: sumEnt * scale,
                rateCtrl: sumRate * scale,
                codestream: sumCS * scale))
        }

        XCTAssertFalse(rows.isEmpty, "No corpus fixtures resolved.")

        print()
        print("=== v10.0 Phase 7 — cross-stage fusion feasibility (single-tile, M2 release, n=\(runs)) ===")
        print()
        print("## Per-fixture stage breakdown + projected fusion savings")
        print()
        print("| Fixture | px | wall ms | preproc | colour | DWT | quant | entropy | rateCtrl | codestream | sum_stages | overhead | overhead % |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %6.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.1f%% |",
                r.label, r.pixels, r.totalMs,
                r.preprocess, r.colour, r.dwt, r.quant,
                r.entropy, r.rateCtrl, r.codestream,
                r.stageSum, r.overhead, r.overheadPct))
        }

        print()
        print("## Fusion savings projection")
        print()
        print("Assumptions:")
        print("  - max savings = overhead × 100% (theoretical ceiling if fusion")
        print("    eliminates ALL inter-stage allocation + materialisation)")
        print("  - realistic savings = overhead × 50% (cross-stage fusion typically")
        print("    removes about half the overhead; some dispatcher and ordering")
        print("    cost remains for the in-place pipeline)")
        print()
        print("| Fixture | wall ms | overhead ms | max fusion save | realistic fusion save | wall after realistic fusion |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            let maxSave = r.overhead
            let realSave = r.overhead * 0.5
            let afterReal = r.totalMs - realSave
            print(String(format: "| %@ | %6.2f | %5.2f | %5.2f ms (%.1f%%) | %5.2f ms (%.1f%%) | %6.2f ms |",
                r.label, r.totalMs, r.overhead,
                maxSave, (maxSave / r.totalMs) * 100,
                realSave, (realSave / r.totalMs) * 100,
                afterReal))
        }

        // Decision support — would v11 fusion clear the 3 ms acceptance bar
        // (v7.4 threshold for default-on perf changes)?
        print()
        print("## v11.0 decision support")
        print()
        let dx = rows.first { $0.label.starts(with: "DX") }
        let mg = rows.last
        if let dx = dx {
            let realSaveDX = dx.overhead * 0.5
            print(String(format: "  DX 2800×2288: realistic fusion save = %.2f ms (%.1f%% wall).", realSaveDX, (realSaveDX / dx.totalMs) * 100))
            print(String(format: "    %@ the v7.4 3-ms acceptance bar for default-on perf changes.",
                realSaveDX >= 3.0 ? "CLEARS" : "BELOW"))
        }
        if let mg = mg {
            let realSaveMG = mg.overhead * 0.5
            print(String(format: "  Largest fixture (%@): realistic fusion save = %.2f ms (%.1f%% wall).",
                mg.label, realSaveMG, (realSaveMG / mg.totalMs) * 100))
        }
        print()
        print("Phase 7 verdict template:")
        print("  - If DX realistic save ≥ 3 ms AND ≥ 5% of wall: fusion v11 is a real lever; recommend.")
        print("  - If DX realistic save < 3 ms OR < 5% wall: 11th lever-ceiling confirmation; close.")
    }
}
