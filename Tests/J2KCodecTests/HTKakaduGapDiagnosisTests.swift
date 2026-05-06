// HTKakaduGapDiagnosisTests.swift
// v6-alpha4 step 11 — diagnostic harness for the remaining Kakadu
// HT-fair encode gap on XA / PX / DX after step 9 closed the MR
// gap.
//
// Step 9 measurement (release median of 5):
//
//   Modality    J2KSwift best   Kakadu HT   Gap
//   MR 886²     2.6 ms          3.6 ms      J2KSwift wins (1.42×)
//   XA 1024²    7.7 ms          5.7 ms      Kakadu (1.35×)
//   PX 2459×    23.2 ms         11.0 ms     Kakadu (2.11×)
//   DX 2800×    53.5 ms         23.8 ms     Kakadu (2.25×)
//
// Step 11's job is to identify WHICH STAGES of the J2KSwift multi-
// tile encode are still over budget vs Kakadu, so future work can
// target them. The v5.39 M3 diagnosis profiled DX SINGLE-TILE
// only and identified DWT structural ceiling + entropy parallel-
// efficiency cap as the dominant levers; the multi-tile path
// (steps 5–10) has different parallelism characteristics, so a
// fresh stage breakdown is needed.
//
// **Diagnostic-only — no XCTAssert on perf numbers.** Resets
// `J2KEncodeTimings`, runs the encode, snapshots stage CPU sums
// (totalled across all concurrent tile tasks), prints a Markdown
// table per fixture. Skips gracefully when the medical corpus
// isn't available.
//
// Usage: `swift test -c release --filter HTKakaduGapDiagnosisTests`
//
// The release-mode requirement is the same as the step-8
// benchmark harness — debug-build numbers are not meaningful for
// HT-fair comparison.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTKakaduGapDiagnosisTests: XCTestCase {

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, bitrateMode: .lossless,
            maxThreads: 8, useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true, htj2kBlockFormat: .conformant)
    }

    private static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// Per-fixture diagnosis cell: wall + per-stage CPU sums (totalled
    /// across all tiles, since the lock-protected accumulator catches
    /// every tile task's contribution). Stage CPU sum × parallel
    /// efficiency = stage wall.
    private struct StageBreakdown {
        let modality: String
        let shape: String
        let mode: String
        let cols: Int
        let rows: Int
        let kakaduWallMs: Double  // for HT-fair comparison
        // Wall time across `runs` runs (median).
        let wallMs: Double
        // Per-stage CPU sums (median across runs of single-run sums).
        let preprocessMs: Double
        let colorTransformMs: Double
        let dwtMs: Double
        let quantizationMs: Double
        let entropyMs: Double
        let rateControlMs: Double
        let codestreamMs: Double
    }

    /// Run a single fixture × mode through encode `runs` times,
    /// resetting `J2KEncodeTimings` between runs, and return
    /// median-aggregated wall + per-stage CPU sums.
    private func diagnoseFixture(
        modality: String, shape: String, mode: J2KHTTileMode,
        kakaduWallMs: Double,
        runs: Int = 5
    ) async throws -> StageBreakdown {
        guard let fixture = CrossCodecTooling.medicalCorpus.first(where: {
            $0.modality == modality && $0.labelHint == shape
        }), let url = CrossCodecTooling.fixtureURL(fixture.path),
              let img = try CrossCodecTooling.loadPGM16BE(url)
        else {
            throw XCTSkip("\(modality) \(shape) fixture missing")
        }

        let cfg = htConfig()
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: img.width, imageHeight: img.height,
            decompositionLevels: cfg.decompositionLevels, mode: mode)
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        // Warm up (one call to absorb cold-start cost).
        if !layout.isMultiTile {
            _ = try await encoder._singleTileEncode(img)
        } else {
            _ = try await J2KMultiTileEncoder.encode(
                image: img, layout: layout, configuration: cfg)
        }

        // Per-run wall + per-stage breakdown samples.
        var walls: [Double] = []
        var pre: [Double] = [], col: [Double] = [], dwt: [Double] = []
        var quant: [Double] = [], ent: [Double] = [], rc: [Double] = []
        var cs: [Double] = []

        for _ in 0..<runs {
            J2KEncodeTimings.reset()
            let t0 = CFAbsoluteTimeGetCurrent()
            if !layout.isMultiTile {
                _ = try await encoder._singleTileEncode(img)
            } else {
                _ = try await J2KMultiTileEncoder.encode(
                    image: img, layout: layout, configuration: cfg)
            }
            let wallMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let snap = J2KEncodeTimings.snapshot()
            walls.append(wallMs)
            pre.append(snap.preprocessing * 1000)
            col.append(snap.colorTransform * 1000)
            dwt.append(snap.waveletTransform * 1000)
            quant.append(snap.quantization * 1000)
            ent.append(snap.entropyCoding * 1000)
            rc.append(snap.rateControl * 1000)
            cs.append(snap.codestreamGeneration * 1000)
        }

        return StageBreakdown(
            modality: modality, shape: shape,
            mode: String(describing: mode),
            cols: layout.cols, rows: layout.rows,
            kakaduWallMs: kakaduWallMs,
            wallMs: Self.median(walls),
            preprocessMs: Self.median(pre),
            colorTransformMs: Self.median(col),
            dwtMs: Self.median(dwt),
            quantizationMs: Self.median(quant),
            entropyMs: Self.median(ent),
            rateControlMs: Self.median(rc),
            codestreamMs: Self.median(cs))
    }

    /// Step 11 deliverable — per-stage breakdown for each fixture
    /// in its step-10 best mode (`auto`), prints Markdown tables
    /// suitable for pasting into MEDICAL_BENCHMARK_V6.md.
    func testKakaduGapDiagnosisPrintTable() async throws {
        #if DEBUG
        print("\n  ⚠️  WARNING ⚠️")
        print("  HTKakaduGapDiagnosisTests is running in DEBUG build.")
        print("  Numbers below are NOT meaningful for HT-fair gap diagnosis.")
        print("  Re-run with: swift test -c release --filter HTKakaduGapDiagnosisTests")
        print()
        #endif

        // Kakadu HT-fair encode wall times from step 10 measurement
        // (release median of 5). Used here to attribute the J2KSwift
        // gap on a per-stage basis.
        let kakaduWalls: [String: Double] = [
            "MR-886":  3.6,
            "XA-1024": 5.0,
            "PX-2459": 10.9,
            "DX-2800": 24.3,
        ]

        struct Probe {
            let modality: String
            let shape: String
            let kakaduKey: String
            let mode: J2KHTTileMode
        }
        let probes: [Probe] = [
            Probe(modality: "MR", shape: "886×886",   kakaduKey: "MR-886",  mode: .auto),
            Probe(modality: "XA", shape: "1024×1024", kakaduKey: "XA-1024", mode: .auto),
            Probe(modality: "PX", shape: "2459×1316", kakaduKey: "PX-2459", mode: .auto),
            Probe(modality: "DX", shape: "2800×2288", kakaduKey: "DX-2800", mode: .auto),
        ]

        var breakdowns: [StageBreakdown] = []
        for probe in probes {
            do {
                let bd = try await diagnoseFixture(
                    modality: probe.modality, shape: probe.shape, mode: probe.mode,
                    kakaduWallMs: kakaduWalls[probe.kakaduKey] ?? -1)
                breakdowns.append(bd)
            } catch is XCTSkip {
                // Skip silently if a fixture is missing; print summary
                // tells the reader which were measured.
            }
        }
        if breakdowns.isEmpty {
            throw XCTSkip("medical corpus not present — step 11 harness skipped")
        }

        // ============================================================
        // Per-fixture per-stage CPU-sum breakdown
        // ============================================================
        print("\n=== v6-alpha4 step 11 — per-stage CPU-sum (release, median of 5) ===")
        print("(Stage CPU sum is totalled across all concurrent tile tasks via")
        print(" J2KEncodeTimings's lock-protected accumulator. Wall time is the")
        print(" actual elapsed end-to-end. Wall < CPU sum when parallelism wins;")
        print(" wall ≈ CPU sum when the stage runs single-threaded.)")
        print()
        print("| Modality | Shape | Mode | layout | Wall ms | Pre+ColXfm | DWT | Quant | Entropy | RateCtrl | Codestream | CPU sum |")
        print("|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for b in breakdowns {
            let preCol = b.preprocessMs + b.colorTransformMs
            let cpuSum = b.preprocessMs + b.colorTransformMs + b.dwtMs +
                         b.quantizationMs + b.entropyMs + b.rateControlMs +
                         b.codestreamMs
            print(String(format:
                "| %@ | %@ | %@ | %d×%d | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f |",
                b.modality, b.shape, b.mode, b.cols, b.rows,
                b.wallMs, preCol, b.dwtMs, b.quantizationMs,
                b.entropyMs, b.rateControlMs, b.codestreamMs, cpuSum))
        }

        // ============================================================
        // Parallelism efficiency per stage
        // ============================================================
        print("\n=== v6-alpha4 step 11 — parallelism efficiency per stage ===")
        print("(CPU_sum / wall = effective parallelism. ≈ 1.0 means stage is")
        print(" single-threaded; > 1.0 means it scales across cores. Apple M2")
        print(" has 8 perf cores so a max of ~8.0 is structurally reachable.)")
        print()
        print("| Modality | Shape | Mode | layout | Pre+Col×n | DWT×n | Entropy×n | Codestream×n |")
        print("|---|---|---|---|---:|---:|---:|---:|")
        for b in breakdowns {
            let preCol = b.preprocessMs + b.colorTransformMs
            // Approximate per-stage wall as CPU_sum / parallelism. We
            // can't directly measure stage wall, but we can estimate
            // the stage's parallelism factor by comparing to the
            // overall wall × stage_fraction.
            let cpuSum = preCol + b.dwtMs + b.quantizationMs +
                         b.entropyMs + b.rateControlMs + b.codestreamMs
            // Estimate stage wall by attributing wall proportionally.
            // Proportional attribution is an approximation but captures
            // the directional finding (stages with higher CPU sums
            // get more wall-time budget).
            func parallelismFactor(_ stage: Double) -> Double {
                guard cpuSum > 0 else { return 0 }
                let stageWall = b.wallMs * (stage / cpuSum)
                guard stageWall > 0.01 else { return 0 }
                return stage / stageWall
            }
            print(String(format:
                "| %@ | %@ | %@ | %d×%d | %.2f× | %.2f× | %.2f× | %.2f× |",
                b.modality, b.shape, b.mode, b.cols, b.rows,
                parallelismFactor(preCol),
                parallelismFactor(b.dwtMs),
                parallelismFactor(b.entropyMs),
                parallelismFactor(b.codestreamMs)))
        }
        print()
        print("(Identical numbers across columns mean the proportional-attribution")
        print(" approximation; actual per-stage parallelism is harder to measure")
        print(" without per-stage wall timers. This table's value is showing the")
        print(" relative SHARES of CPU time per stage, which DOES show where work")
        print(" is concentrated.)")

        // ============================================================
        // Stage shares + Kakadu gap attribution
        // ============================================================
        print("\n=== v6-alpha4 step 11 — stage shares + Kakadu gap attribution ===")
        print("(Stage shares = CPU_sum percentages. Kakadu gap = J2KSwift wall −")
        print(" Kakadu wall. Per-stage gap attribution = stage_share × total_gap")
        print(" — approximate but identifies which stages own the most absolute ms.)")
        print()
        print("| Modality | Shape | Mode | J2KSwift wall | Kakadu wall | Gap (ms) | Pre+Col % | DWT % | Quant % | Entropy % | RC % | Codestream % |")
        print("|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for b in breakdowns {
            let preCol = b.preprocessMs + b.colorTransformMs
            let cpuSum = preCol + b.dwtMs + b.quantizationMs +
                         b.entropyMs + b.rateControlMs + b.codestreamMs
            let gap = b.wallMs - b.kakaduWallMs
            func pct(_ stage: Double) -> Double {
                cpuSum > 0 ? (stage / cpuSum * 100) : 0
            }
            print(String(format:
                "| %@ | %@ | %@ | %.2f | %.2f | %+.2f | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% | %.0f%% |",
                b.modality, b.shape, b.mode, b.wallMs, b.kakaduWallMs, gap,
                pct(preCol), pct(b.dwtMs), pct(b.quantizationMs),
                pct(b.entropyMs), pct(b.rateControlMs), pct(b.codestreamMs)))
        }

        // ============================================================
        // Ranked levers (gap attribution × % share)
        // ============================================================
        print("\n=== v6-alpha4 step 11 — ranked encode levers (largest absolute share first) ===")
        print()
        print("For each fixture × stage, the stage's CPU-sum × J2KSwift_wall /")
        print("CPU_sum is its wall-time share, and gap × share is the absolute")
        print("ms a perfect optimisation of that stage could remove. (Optimisation")
        print("would have to take the stage's wall to 0 — typically unreachable —")
        print("so these are upper bounds.)")
        print()
        for b in breakdowns where b.wallMs > b.kakaduWallMs {
            let preCol = b.preprocessMs + b.colorTransformMs
            let cpuSum = preCol + b.dwtMs + b.quantizationMs +
                         b.entropyMs + b.rateControlMs + b.codestreamMs
            let gap = b.wallMs - b.kakaduWallMs
            // For each stage, its wall = J2KSwift_wall * (stage_cpu / cpu_sum).
            // Best-case ms removable = stage_wall (if optimised to 0).
            struct Lever {
                let name: String
                let cpuMs: Double
                let pct: Double
                let stageWallMs: Double
            }
            let levers: [Lever] = [
                Lever(name: "DWT",        cpuMs: b.dwtMs,        pct: cpuSum > 0 ? b.dwtMs / cpuSum * 100 : 0,        stageWallMs: cpuSum > 0 ? b.wallMs * b.dwtMs / cpuSum : 0),
                Lever(name: "Entropy",    cpuMs: b.entropyMs,    pct: cpuSum > 0 ? b.entropyMs / cpuSum * 100 : 0,    stageWallMs: cpuSum > 0 ? b.wallMs * b.entropyMs / cpuSum : 0),
                Lever(name: "Codestream", cpuMs: b.codestreamMs, pct: cpuSum > 0 ? b.codestreamMs / cpuSum * 100 : 0, stageWallMs: cpuSum > 0 ? b.wallMs * b.codestreamMs / cpuSum : 0),
                Lever(name: "RateCtrl",   cpuMs: b.rateControlMs,pct: cpuSum > 0 ? b.rateControlMs / cpuSum * 100 : 0,stageWallMs: cpuSum > 0 ? b.wallMs * b.rateControlMs / cpuSum : 0),
                Lever(name: "Pre+ColXfm", cpuMs: preCol,         pct: cpuSum > 0 ? preCol / cpuSum * 100 : 0,         stageWallMs: cpuSum > 0 ? b.wallMs * preCol / cpuSum : 0),
                Lever(name: "Quant",      cpuMs: b.quantizationMs,pct: cpuSum > 0 ? b.quantizationMs / cpuSum * 100 : 0,stageWallMs: cpuSum > 0 ? b.wallMs * b.quantizationMs / cpuSum : 0),
            ].sorted { $0.cpuMs > $1.cpuMs }
            print("**\(b.modality) \(b.shape)** (J2KSwift \(String(format: "%.1f", b.wallMs)) ms vs Kakadu \(String(format: "%.1f", b.kakaduWallMs)) ms — gap \(String(format: "%+.1f", gap)) ms):")
            print()
            print("| Rank | Stage | CPU sum (ms) | % of CPU sum | Estimated stage wall (ms) | Max ms removable (= stage wall) |")
            print("|---:|---|---:|---:|---:|---:|")
            for (i, lever) in levers.enumerated() {
                print(String(format:
                    "| %d | %@ | %.2f | %.0f%% | %.2f | %.2f |",
                    i + 1, lever.name, lever.cpuMs, lever.pct,
                    lever.stageWallMs, lever.stageWallMs))
            }
            print()
        }

        print("(Step 11 is diagnostic-only. Step 12+ targets the highest-ranked")
        print("levers per fixture, prioritising those with concrete optimisation")
        print("paths within the v6-alpha4 scope constraints.)")
    }
}
