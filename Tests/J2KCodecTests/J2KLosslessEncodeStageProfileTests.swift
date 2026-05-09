// v8 Phase 6.2 — gated to macOS: depends on CrossCodecTooling (uses Process(), unavailable on iOS).
#if os(macOS)
// J2KLosslessEncodeStageProfileTests.swift
// v5.38 M3 — per-stage profile of the lossless encode pipeline on
// the medical corpus. Pure measurement; no code changes here.
//
// SCOPE: lossless-only. Drives `J2KEncoder(.lossless).encode` while
// resetting `J2KEncodeTimings` per pass and snapshotting after, so
// the table identifies the dominant stage per fixture (preprocess /
// colorXform / dwt / quantize / entropy / rateCtrl / codestream).
//
// Pass gate: every fixture's lossless roundtrip remains bit-exact
// (re-asserted as a smoke check). The numbers are diagnostic, not
// gating — but XCTAttachments in CI would let us regression-track
// stage shifts over time.

import XCTest
import Foundation
@testable import J2KCore
@testable import J2KCodec

final class J2KLosslessEncodeStageProfileTests: XCTestCase {

    private func losslessConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    /// Per-fixture stage breakdown of the lossless encode pipeline.
    /// Runs `nRuns` measurement passes per fixture (after a discarded
    /// warm-up). For each run: reset the global timings → encode →
    /// snapshot → accumulate. Reports median per-stage ms and
    /// percentage of total.
    func testLosslessEncodeStageProfileAcrossMedicalCorpus() async throws {
        let nRuns = 5
        struct StageMs { let preprocess: Double; let colorXform: Double; let dwt: Double; let quant: Double; let entropy: Double; let rateCtrl: Double; let codestream: Double; let total: Double }
        struct Row { let modality: String; let label: String; let pixels: Int; let median: StageMs }
        var rows: [Row] = []
        var ranAtLeastOne = false

        for fixture in CrossCodecTooling.medicalCorpus {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }
            ranAtLeastOne = true

            let cfg = losslessConfig()
            let encoder = J2KEncoder(encodingConfiguration: cfg)
            let decoder = J2KDecoder()

            // Discarded warm-up pass.
            _ = try await encoder.encode(img)

            // Bit-exact smoke check (gate-grade); the M1 test is the
            // primary correctness gate, but we add it here so this
            // file is also a guard against regressions.
            let warmEncoded = try await encoder.encode(img)
            let warmDecoded = try await decoder.decode(warmEncoded)
            XCTAssertTrue(CrossCodecTooling.bitExactPixelMatch(img, warmDecoded),
                "lossless self-roundtrip not bit-exact: \(fixture.modality) \(fixture.labelHint)")

            // Measurement passes.
            var samples: [StageMs] = []
            for _ in 0..<nRuns {
                J2KEncodeTimings.reset()
                _ = try await encoder.encode(img)
                let snap = J2KEncodeTimings.snapshot()
                samples.append(StageMs(
                    preprocess: snap.preprocessing * 1000,
                    colorXform: snap.colorTransform * 1000,
                    dwt: snap.waveletTransform * 1000,
                    quant: snap.quantization * 1000,
                    entropy: snap.entropyCoding * 1000,
                    rateCtrl: snap.rateControl * 1000,
                    codestream: snap.codestreamGeneration * 1000,
                    total: snap.total * 1000))
            }

            // Median per stage to absorb outliers from the first
            // post-warm-up pass and the GC/page-fault tail of the last.
            func median(_ values: [Double]) -> Double {
                let sorted = values.sorted()
                return sorted[sorted.count / 2]
            }
            let med = StageMs(
                preprocess:  median(samples.map(\.preprocess)),
                colorXform:  median(samples.map(\.colorXform)),
                dwt:         median(samples.map(\.dwt)),
                quant:       median(samples.map(\.quant)),
                entropy:     median(samples.map(\.entropy)),
                rateCtrl:    median(samples.map(\.rateCtrl)),
                codestream:  median(samples.map(\.codestream)),
                total:       median(samples.map(\.total)))

            rows.append(Row(
                modality: fixture.modality,
                label: fixture.labelHint.isEmpty ? "\(img.width)×\(img.height)" : fixture.labelHint,
                pixels: img.width * img.height,
                median: med))
        }

        if !ranAtLeastOne { throw XCTSkip("medical corpus fixtures not present") }

        // ---- Stage breakdown table (ms) ----
        print("\n=== v5.38 M3 — Lossless encode stage profile (median of \(nRuns) runs, ms) ===")
        print("| Modality | Shape | Total | Pre | Colour | DWT | Quant | Entropy | RateCtrl | Codestream |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %@ | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |",
                r.modality, r.label, r.median.total,
                r.median.preprocess, r.median.colorXform, r.median.dwt,
                r.median.quant, r.median.entropy, r.median.rateCtrl,
                r.median.codestream))
        }

        // ---- Stage breakdown table (% of total) ----
        print("\n=== v5.38 M3 — Lossless encode stage profile (% of total) ===")
        print("| Modality | Shape | Pre% | Colour% | DWT% | Quant% | Entropy% | RateCtrl% | Codestream% |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let t = max(r.median.total, 0.001)
            let pct = { (x: Double) in (x / t) * 100.0 }
            print(String(format: "| %@ | %@ | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% |",
                r.modality, r.label,
                pct(r.median.preprocess), pct(r.median.colorXform),
                pct(r.median.dwt), pct(r.median.quant),
                pct(r.median.entropy), pct(r.median.rateCtrl),
                pct(r.median.codestream)))
        }

        // ---- Identify the dominant stage per fixture ----
        print("\n=== v5.38 M3 — Dominant stage per fixture ===")
        for r in rows {
            let stages: [(String, Double)] = [
                ("preprocess", r.median.preprocess),
                ("colorXform", r.median.colorXform),
                ("dwt", r.median.dwt),
                ("quant", r.median.quant),
                ("entropy", r.median.entropy),
                ("rateCtrl", r.median.rateCtrl),
                ("codestream", r.median.codestream),
            ]
            let dom = stages.max(by: { $0.1 < $1.1 })!
            let pct = (dom.1 / max(r.median.total, 0.001)) * 100.0
            print(String(format: "  %@ %@ → %@ (%.1f ms, %.0f%% of total)",
                r.modality, r.label, dom.0, dom.1, pct))
        }
    }
}

#endif // os(macOS)
