// HTParallelismProfileTests.swift
// v5.39 M2 — large-fixture HT parallelism feasibility study.
//
// Goal: profile J2KSwift's HT lossless encode parallelism on the
// large-fixture portion of the medical corpus (MR 886×886, XA, PX, DX)
// to determine whether more parallelism can narrow the Kakadu HT-fair
// gap, or whether per-CPU code speed is the bottleneck (in which case
// the gap is structural under the current SIMD primitive set).
//
// Measurement: thread-count sweep. For each fixture, encode at
// maxThreads ∈ {1, 2, 4, 8} and record wall time. Speedup =
// time(1) / time(N). On an 8-core M-series chip:
//   - speedup ≈ 7-8 at 8 threads → parallelism is essentially
//     perfect; remaining gap to Kakadu is per-core code speed and
//     no amount of "more parallelism" will help.
//   - speedup < 5 at 8 threads → there's parallel headroom (chunk
//     granularity issues, memory-bandwidth contention, etc.) that
//     could be addressed.
//
// SCOPE: lossless HT only; correctness gates already covered by
// `J2KLosslessMedicalGateTests`. This file only measures.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class HTParallelismProfileTests: XCTestCase {

    private func htConfig(maxThreads: Int) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0,
            lossless: true,
            decompositionLevels: 5,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            bitrateMode: .lossless,
            maxThreads: maxThreads,
            useHTJ2K: true,
            useReversibleFilter: true,
            enableParallelCodeBlocks: maxThreads != 1,
            htj2kBlockFormat: .conformant)
        return cfg
    }

    private static func median(_ samples: [Double]) -> Double {
        precondition(!samples.isEmpty)
        let sorted = samples.sorted()
        return sorted[sorted.count / 2]
    }

    /// For each large-fixture (≥ 886×886), sweep maxThreads ∈
    /// {1, 2, 4, 8} and report median-of-5 encode times. Print the
    /// speedup curve so we can read parallel efficiency directly.
    /// Also reports # of code blocks per fixture so the per-block
    /// granularity question is answerable from the same table.
    func testHTParallelismScalingOnLargeFixtures() async throws {
        struct Result {
            let modality: String
            let label: String
            let pixels: Int
            var times: [Int: Double]  // maxThreads → median ms
            var blockCount: Int
        }

        let largeFixtures = CrossCodecTooling.medicalCorpus.filter {
            switch $0.modality {
            case "MR", "XA", "PX", "DX": return true
            default: return false
            }
        }

        var results: [Result] = []
        let runs = 5
        let threadCounts = [1, 2, 4, 8]

        for fixture in largeFixtures {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }

            // Estimate block count once for reporting (encoder figures
            // it out internally; we recompute the rough count from
            // dimensions + decomposition for the report only).
            // For 64×64 code blocks, 5 decomp levels, 1 component:
            // blocks_per_band ≈ ceil(W/(64×2^(5-r))) × ceil(H/(64×2^(5-r)))
            // summed across (LL at r=0 + 3 detail bands at r=1..5).
            let cbW = 64, cbH = 64
            var blockCount = 0
            for r in 0...5 {
                let scale = 1 << (5 - r)
                let bandW = (img.width + scale - 1) / scale
                let bandH = (img.height + scale - 1) / scale
                let blocksX = (bandW + cbW - 1) / cbW
                let blocksY = (bandH + cbH - 1) / cbH
                let bands = (r == 0) ? 1 : 3
                blockCount += blocksX * blocksY * bands
            }

            var result = Result(
                modality: fixture.modality,
                label: fixture.labelHint,
                pixels: img.width * img.height,
                times: [:],
                blockCount: blockCount)

            for tc in threadCounts {
                let cfg = htConfig(maxThreads: tc)
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                // Warm-up.
                _ = try await encoder.encode(img)
                var samples: [Double] = []
                for _ in 0..<runs {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    _ = try await encoder.encode(img)
                    samples.append((CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
                }
                result.times[tc] = Self.median(samples)
            }

            results.append(result)
        }

        if results.isEmpty {
            throw XCTSkip("large-fixture corpus not present")
        }

        // Print thread-count sweep table.
        print("\n=== v5.39 M2 — HT parallelism scaling, median of \(runs) runs ===")
        print("|             |             |       |       |       | Speedup ×× |")
        print("| Modality    | Shape       | Blocks| 1 thr | 2 thr | 4 thr | 8 thr | 2/1 | 4/1 | 8/1 |")
        print("|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in results {
            let t1 = r.times[1] ?? 0
            let t2 = r.times[2] ?? 0
            let t4 = r.times[4] ?? 0
            let t8 = r.times[8] ?? 0
            print(String(format: "| %@ | %@ | %d | %.1f | %.1f | %.1f | %.1f | %.2f× | %.2f× | %.2f× |",
                r.modality, r.label,
                r.blockCount, t1, t2, t4, t8,
                t1 / max(t2, 0.001),
                t1 / max(t4, 0.001),
                t1 / max(t8, 0.001)))
        }

        // Print parallel-efficiency observations.
        print("\n=== v5.39 M2 — parallel efficiency at 8 threads ===")
        print("(efficiency = speedup_8 / 8; 1.0 = perfect; > 0.85 = strong; < 0.5 = poor)")
        print("| Modality | Shape | Speedup 8-thr | Efficiency | Verdict |")
        print("|---|---|---:|---:|:---|")
        for r in results {
            let t1 = r.times[1] ?? 0
            let t8 = r.times[8] ?? 0
            let s = t1 / max(t8, 0.001)
            let eff = s / 8.0
            let verdict: String
            if eff > 0.85 { verdict = "strong — per-CPU bound" }
            else if eff > 0.65 { verdict = "good — small parallel headroom" }
            else if eff > 0.45 { verdict = "moderate — parallel improvement possible" }
            else { verdict = "poor — large parallel headroom" }
            print(String(format: "| %@ | %@ | %.2f× | %.2f | %@ |",
                r.modality, r.label, s, eff, verdict))
        }
    }

    /// Per-stage 1-thread vs 8-thread breakdown, identifying which
    /// pipeline stage is the serial bottleneck.
    func testHTPerStageScalingOnLargeFixtures() async throws {
        struct StageTimes {
            let preprocess: Double
            let dwt: Double
            let entropy: Double
            let codestream: Double
            let total: Double
        }
        struct Row {
            let modality: String, label: String
            var t1: StageTimes
            var t8: StageTimes
        }

        let largeFixtures = CrossCodecTooling.medicalCorpus.filter {
            ["MR", "XA", "PX", "DX"].contains($0.modality)
        }
        var rows: [Row] = []
        let runs = 5

        for fixture in largeFixtures {
            guard let url = CrossCodecTooling.fixtureURL(fixture.path) else { continue }
            guard let img = try CrossCodecTooling.loadPGM16BE(url) else { continue }

            func measureStages(maxThreads: Int) async throws -> StageTimes {
                let cfg = htConfig(maxThreads: maxThreads)
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                _ = try await encoder.encode(img)  // warm-up
                var pre: [Double] = [], dwt: [Double] = [], ent: [Double] = []
                var code: [Double] = [], total: [Double] = []
                for _ in 0..<runs {
                    J2KEncodeTimings.reset()
                    let t0 = CFAbsoluteTimeGetCurrent()
                    _ = try await encoder.encode(img)
                    total.append((CFAbsoluteTimeGetCurrent() - t0) * 1000.0)
                    let snap = J2KEncodeTimings.snapshot()
                    pre.append(snap.preprocessing * 1000.0)
                    dwt.append(snap.waveletTransform * 1000.0)
                    ent.append(snap.entropyCoding * 1000.0)
                    code.append(snap.codestreamGeneration * 1000.0)
                }
                return StageTimes(
                    preprocess: Self.median(pre),
                    dwt: Self.median(dwt),
                    entropy: Self.median(ent),
                    codestream: Self.median(code),
                    total: Self.median(total))
            }

            let t1 = try await measureStages(maxThreads: 1)
            let t8 = try await measureStages(maxThreads: 8)
            rows.append(Row(
                modality: fixture.modality,
                label: fixture.labelHint,
                t1: t1, t8: t8))
        }

        if rows.isEmpty { throw XCTSkip("large-fixture corpus not present") }

        print("\n=== v5.39 M2 — per-stage 1-thread vs 8-thread (median of \(runs)) ===")
        print("| Modality | Shape | Stage | 1 thr ms | 8 thr ms | Speedup | Verdict |")
        print("|---|---|---|---:|---:|---:|:---|")
        for r in rows {
            let stages: [(String, Double, Double)] = [
                ("Preprocess", r.t1.preprocess, r.t8.preprocess),
                ("DWT",        r.t1.dwt,        r.t8.dwt),
                ("Entropy",    r.t1.entropy,    r.t8.entropy),
                ("Codestream", r.t1.codestream, r.t8.codestream),
                ("Total",      r.t1.total,     r.t8.total),
            ]
            for (name, single, multi) in stages {
                let s = single / max(multi, 0.001)
                let eff = s / 8.0
                let verdict: String
                if name == "Total" || single < 1.0 {
                    verdict = ""
                } else if eff > 0.85 { verdict = "near-perfect" }
                else if eff > 0.65 { verdict = "strong" }
                else if eff > 0.45 { verdict = "moderate" }
                else if eff > 0.20 { verdict = "weak" }
                else { verdict = "**SERIAL**" }
                print(String(format: "| %@ | %@ | %@ | %.1f | %.1f | %.2f× | %@ |",
                    r.modality, r.label, name, single, multi, s, verdict))
            }
        }
    }
}
