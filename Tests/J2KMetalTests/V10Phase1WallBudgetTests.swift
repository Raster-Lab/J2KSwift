// V10Phase1WallBudgetTests.swift
//
// v10.0-research Phase 1a/1b: produce the non-entropy wall budget that
// gates the Phase 2 C-target decision (see V10_0_RESEARCH_PLAN.md).
//
// Differences vs `EncodeStageProfileLosslessCorpusTests`:
//   1. Adds substage snapshots (J2KTier2Timings,
//      J2KCodestreamMarkerTimings, J2KPreprocessSubstageTimings).
//   2. Sweeps `config.maxThreads` ∈ {1, 4, 12} per fixture so
//      worker-contention effects are visible.
//   3. Output is markdown-formatted for direct copy into the
//      V10_0_PHASE1_WALL_BUDGET.md companion doc.
//
// Phase 1's gate: at least one non-entropy stage measures ≥10 % of
// wall on a representative corpus image. If nothing clears the bar,
// the plan calls for closing v10.0 as a research artefact.
//
// Run with:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test -c release --filter V10Phase1WallBudgetTests

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10Phase1WallBudgetTests: XCTestCase {

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
            if b == 0x23 {
                while i < raw.count, raw[i] != 0x0A { i += 1 }
                continue
            }
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
        CorpusFixture(label: "CT 512²",         filename: "ct_study_001_instance_000001.pgm"),
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
        let maxThreads: Int
        let totalMs: Double
        // Stage means (ms) from J2KEncodeTimings.
        let pre, colour, dwt, quant, entropy, rateCtrl, codestream: Double
        // Preprocess substage means (ms) from J2KPreprocessSubstageTimings.
        let preValidate, preExtract8, preExtract16, preDCShift: Double
        // Tier-2 substage means (ms) from J2KTier2Timings.
        let t2Total: Double
        // Codestream marker substage means (ms) from J2KCodestreamMarkerTimings.
        let csmTotal: Double
    }

    /// Phase 1b deliverable — full wall budget across {1, 4, 12} workers
    /// on the lossless HT-conformant 5/3 corpus.
    func testWallBudget_Lossless_WorkerSweep_M2() async throws {
        #if DEBUG
        print("⚠️  Phase 1b in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter V10Phase1WallBudgetTests")
        #endif

        let runsPerCell = 5
        let threadCounts = [1, 4, 12]
        var rows: [Row] = []

        for tc in threadCounts {
            let cfg = htLosslessConfig(maxThreads: tc)
            let encoder = J2KEncoder(encodingConfiguration: cfg)

            for fix in Self.corpus {
                guard let image = loadPGM16(fix.filename) else { continue }

                // Warm-up (excluded).
                _ = try await encoder.encode(image)

                var times: [TimeInterval] = []
                var sumPre: TimeInterval = 0, sumColor: TimeInterval = 0
                var sumDWT: TimeInterval = 0, sumQuant: TimeInterval = 0
                var sumEntropy: TimeInterval = 0, sumRate: TimeInterval = 0
                var sumCS: TimeInterval = 0
                var sumPreValidate: TimeInterval = 0
                var sumPreExtract8: TimeInterval = 0
                var sumPreExtract16: TimeInterval = 0
                var sumPreDCShift: TimeInterval = 0
                var sumT2: TimeInterval = 0
                var sumCSM: TimeInterval = 0

                for _ in 0..<runsPerCell {
                    J2KEncodeTimings.reset()
                    J2KPreprocessSubstageTimings.reset()
                    J2KTier2Timings.reset()
                    J2KCodestreamMarkerTimings.reset()

                    let t0 = Date()
                    _ = try await encoder.encode(image)
                    times.append(Date().timeIntervalSince(t0))

                    let s = J2KEncodeTimings.snapshot()
                    sumPre += s.preprocessing
                    sumColor += s.colorTransform
                    sumDWT += s.waveletTransform
                    sumQuant += s.quantization
                    sumEntropy += s.entropyCoding
                    sumRate += s.rateControl
                    sumCS += s.codestreamGeneration

                    let ps = J2KPreprocessSubstageTimings.snapshot()
                    sumPreValidate += ps.imageValidate
                    sumPreExtract8 += ps.extractComponentData8
                    sumPreExtract16 += ps.extractComponentData16
                    sumPreDCShift += ps.dcLevelShift

                    let ts = J2KTier2Timings.snapshot()
                    sumT2 += ts.total
                    let cms = J2KCodestreamMarkerTimings.snapshot()
                    sumCSM += cms.total
                }

                let median = times.sorted()[runsPerCell / 2] * 1000.0
                let scale = 1000.0 / Double(runsPerCell)
                rows.append(Row(
                    label: fix.label, pixels: image.width * image.height,
                    maxThreads: tc,
                    totalMs: median,
                    pre: sumPre * scale, colour: sumColor * scale,
                    dwt: sumDWT * scale, quant: sumQuant * scale,
                    entropy: sumEntropy * scale,
                    rateCtrl: sumRate * scale,
                    codestream: sumCS * scale,
                    preValidate: sumPreValidate * scale,
                    preExtract8: sumPreExtract8 * scale,
                    preExtract16: sumPreExtract16 * scale,
                    preDCShift: sumPreDCShift * scale,
                    t2Total: sumT2 * scale,
                    csmTotal: sumCSM * scale))
            }
        }

        XCTAssertFalse(rows.isEmpty, "No corpus fixtures resolved — fixture path layout changed?")

        // === Per-stage table (raw ms) ===
        print("=== v10.0 Phase 1b — lossless HT-conformant 5/3 wall budget (Apple M2, release, n=\(runsPerCell)) ===")
        print()
        print("## Per-stage breakdown (ms, mean over n=\(runsPerCell))")
        print()
        print("| Fixture | maxT | total | preproc | colour | DWT | quant | entropy | rateCtrl | codestream | sum |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let sum = r.pre + r.colour + r.dwt + r.quant + r.entropy + r.rateCtrl + r.codestream
            print(String(format: "| %@ | %d | %6.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f |",
                r.label, r.maxThreads, r.totalMs,
                r.pre, r.colour, r.dwt, r.quant, r.entropy, r.rateCtrl, r.codestream, sum))
        }

        // === Per-stage % of wall ===
        print()
        print("## Per-stage % of TOTAL encode wall (Phase 1 gate: any non-entropy stage ≥10 % on DX?)")
        print()
        print("| Fixture | maxT | preproc % | colour % | DWT % | quant % | entropy % | rateCtrl % | codestream % | accounted % |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let total = r.totalMs
            let pct = { (x: Double) in 100.0 * x / total }
            let sum = r.pre + r.colour + r.dwt + r.quant + r.entropy + r.rateCtrl + r.codestream
            print(String(format: "| %@ | %d | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f |",
                r.label, r.maxThreads,
                pct(r.pre), pct(r.colour), pct(r.dwt), pct(r.quant),
                pct(r.entropy), pct(r.rateCtrl), pct(r.codestream),
                pct(sum)))
        }

        // === Substage breakdowns ===
        print()
        print("## Preprocess substages (ms, mean over n=\(runsPerCell))")
        print()
        print("| Fixture | maxT | validate | extract8 | extract16 | dcShift | sum |")
        print("|---|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let sum = r.preValidate + r.preExtract8 + r.preExtract16 + r.preDCShift
            print(String(format: "| %@ | %d | %5.3f | %5.3f | %5.3f | %5.3f | %5.3f |",
                r.label, r.maxThreads,
                r.preValidate, r.preExtract8, r.preExtract16, r.preDCShift, sum))
        }

        print()
        print("## Tier-2 + codestream-marker substage totals (ms, mean over n=\(runsPerCell))")
        print()
        print("| Fixture | maxT | tier2 total | csmarker total |")
        print("|---|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %6.3f | %6.3f |",
                r.label, r.maxThreads, r.t2Total, r.csmTotal))
        }

        print()
        print("Reading the table:")
        print("  - Phase 1 gate: any NON-ENTROPY stage ≥10 % of DX wall?")
        print("    If yes → that's the Phase 2 C-target candidate.")
        print("    If no  → close v10.0 as research; entropy is the only live lever.")
        print("  - 'accounted %' < 100 % is overhead outside the timed regions:")
        print("    allocator, `withUnsafe...` wrappers, dispatch glue, tile assembly.")
        print("  - The maxThreads sweep exposes contention: a stage whose ms grows")
        print("    with thread count is hitting a serialisation point.")
    }
}
