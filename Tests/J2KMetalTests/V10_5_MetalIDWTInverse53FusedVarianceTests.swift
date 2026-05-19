// V10_5_MetalIDWTInverse53FusedVarianceTests.swift
//
// v10.5-research — multi-trial variance bench for the fused H+V
// Metal IDWT kernel. Settles the "MG large flips sign run-to-run"
// question from the 2-run end-to-end A/B by sampling many more
// trials with interleaved (tiled, fused) calls so thermal /
// scheduler drift hits both paths symmetrically.
//
// Design:
//   - Per fixture, after a warm-up phase, run `nTrials` interleaved
//     samples: (tiled, fused, tiled, fused, ...). Each sample is one
//     full decode. Recording per-decode wall time gives 2 × nTrials
//     measurements per fixture.
//   - Stats reported: mean, median, min, max, std-dev for each path,
//     plus the per-trial (tiled - fused) delta distribution (mean,
//     median, std, fraction-positive).
//
// Decision rule (10-trial):
//   - "RELIABLE WIN" if median(Δ) ≥ 3 ms AND fraction-positive ≥ 0.7
//   - "RELIABLE WASH" if |median(Δ)| < 1 ms AND fraction-positive ∈
//     [0.4, 0.6]
//   - Anything else = "BORDERLINE — need more data or accept variance".
//
// Run with:
//   swift test -c release --filter V10_5_MetalIDWTInverse53FusedVarianceTests

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_5_MetalIDWTInverse53FusedVarianceTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    /// Focus on the fixtures where the 2-run A/B showed signal or
    /// variance: MG class (real win + variance) + one DX (regression
    /// check) + one PX (regression check).
    private static let corpus: [Fixture] = [
        Fixture(label: "MG small 3516×4784",  filename: "medical-real/mg_real_small_3516x4784.pgm"),
        Fixture(label: "MG mid 3518×4784",    filename: "medical-real/mg_real_mid_3518x4784.pgm"),
        Fixture(label: "MG large 3521×4784",  filename: "medical-real/mg_real_large_3521x4784.pgm"),
        Fixture(label: "DX large 2544×3056",  filename: "medical-real/dx_real_large_2544x3056.pgm"),
        Fixture(label: "PX large 2812×1316",  filename: "medical-real/px_real_large_2812x1316.pgm"),
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

    private struct Stats {
        let mean: Double
        let median: Double
        let min: Double
        let max: Double
        let std: Double
    }

    private static func summarize(_ xs: [Double]) -> Stats {
        let n = Double(xs.count)
        let mean = xs.reduce(0, +) / n
        let sorted = xs.sorted()
        let med = sorted[xs.count / 2]
        let lo = sorted.first ?? 0
        let hi = sorted.last ?? 0
        let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
        let std = variance.squareRoot()
        return Stats(mean: mean, median: med, min: lo, max: hi, std: std)
    }

    /// Decode `codestream` once with the given Metal IDWT path,
    /// returning the wall time in ms. Threshold is lowered to 0
    /// in `testFusedVariance_*` so the fused path runs at all
    /// sizes (otherwise production's 12 MP gate would re-route
    /// sub-MG fixtures through tiled).
    private func timedDecode(
        decoder: J2KDecoder, codestream: Data, fused: Bool
    ) async throws -> Double {
        J2KMetalDWT.inverse53IntTiledEnabled = !fused
        J2KMetalDWT.inverse53IntFusedEnabled = fused
        let t0 = Date()
        _ = try await decoder.decode(codestream)
        return Date().timeIntervalSince(t0) * 1000
    }

    func testFusedVariance_MGandRegressionCheck_10Trials() async throws {
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        let warmups = 3
        let nTrials = 10

        let prevThreshold = J2KMetalDWT.inverse53IntFusedPixelThreshold
        defer { J2KMetalDWT.inverse53IntFusedPixelThreshold = prevThreshold }
        // Lower threshold to 0 so the fused path runs at all sizes
        // — otherwise production's 12 MP gate would silently route
        // sub-MG fixtures (DX 7.7 MP, PX 3.7 MP) back through tiled
        // and the A/B would compare tiled-vs-tiled on those rows.
        J2KMetalDWT.inverse53IntFusedPixelThreshold = 0

        struct Row {
            let label: String
            let tiled: Stats
            let fused: Stats
            let deltas: [Double]
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }
            let codestream = try await encoder.encode(image)

            // Warm-up phase — fire both paths a few times to settle
            // thermal state and prime the buffer pool.
            for _ in 0..<warmups {
                _ = try await timedDecode(decoder: decoder,
                                          codestream: codestream,
                                          fused: false)
                _ = try await timedDecode(decoder: decoder,
                                          codestream: codestream,
                                          fused: true)
            }

            // Interleaved sampling: T F T F ... (nTrials of each).
            var tiledSamples: [Double] = []
            var fusedSamples: [Double] = []
            var deltas: [Double] = []
            tiledSamples.reserveCapacity(nTrials)
            fusedSamples.reserveCapacity(nTrials)
            for _ in 0..<nTrials {
                let tMs = try await timedDecode(decoder: decoder,
                                                codestream: codestream,
                                                fused: false)
                let fMs = try await timedDecode(decoder: decoder,
                                                codestream: codestream,
                                                fused: true)
                tiledSamples.append(tMs)
                fusedSamples.append(fMs)
                deltas.append(tMs - fMs) // positive = fused faster
            }

            rows.append(Row(label: fix.label,
                            tiled: Self.summarize(tiledSamples),
                            fused: Self.summarize(fusedSamples),
                            deltas: deltas))
        }

        // Restore tiled default-on.
        J2KMetalDWT.inverse53IntTiledEnabled = true
        J2KMetalDWT.inverse53IntFusedEnabled = false

        print("=== v10.5 fused IDWT variance bench (M2 release, 10 interleaved trials) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)")
        print("Warmups (each path): \(warmups)  Trials/path: \(nTrials)")
        if !skipped.isEmpty {
            print("Skipped: \(skipped.joined(separator: ", "))")
        }
        print("")
        print("Per-path stats (tiled / fused):")
        print("| Fixture | tiled mean | tiled med | tiled std | fused mean | fused med | fused std |")
        print("|---|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %6.2f | %6.2f | %5.2f | %6.2f | %6.2f | %5.2f |",
                         r.label,
                         r.tiled.mean, r.tiled.median, r.tiled.std,
                         r.fused.mean, r.fused.median, r.fused.std))
        }
        print("")
        print("Per-trial Δ = tiled − fused (positive = fused faster):")
        print("| Fixture | Δ mean | Δ med | Δ std | Δ min | Δ max | frac > 0 | verdict |")
        print("|---|---:|---:|---:|---:|---:|---:|---|")
        for r in rows {
            let ds = Self.summarize(r.deltas)
            let nPos = r.deltas.filter { $0 > 0 }.count
            let fracPos = Double(nPos) / Double(r.deltas.count)
            // Decision rule
            let verdict: String
            if ds.median >= 3.0 && fracPos >= 0.7 {
                verdict = "RELIABLE WIN"
            } else if ds.median <= -3.0 && fracPos <= 0.3 {
                verdict = "RELIABLE LOSS"
            } else if abs(ds.median) < 1.0 && fracPos >= 0.4 && fracPos <= 0.6 {
                verdict = "RELIABLE WASH"
            } else {
                verdict = "BORDERLINE"
            }
            print(String(format: "| %@ | %+5.2f | %+5.2f | %5.2f | %+5.2f | %+5.2f | %.0f%% | %@ |",
                         r.label,
                         ds.mean, ds.median, ds.std, ds.min, ds.max,
                         100 * fracPos, verdict))
        }
        print("")
        print("Decision rule (10-trial):")
        print("  - RELIABLE WIN  : median(Δ) ≥ 3 ms AND fraction-positive ≥ 70%")
        print("  - RELIABLE LOSS : median(Δ) ≤ −3 ms AND fraction-positive ≤ 30%")
        print("  - RELIABLE WASH : |median(Δ)| < 1 ms AND fraction-positive ∈ [40%, 60%]")
        print("  - BORDERLINE    : everything else — variance equals the lever")

        XCTAssertFalse(rows.isEmpty, "No fixtures benched")
    }
}
#endif
