// V10_8_DecodeVsDecodeGPUOnDXPXTests.swift
//
// v10.8-research Phase 2 — A/B test `decode()` vs `decodeGPU()` on
// DX/PX with lossless HT. Probes whether the
// `_gpuInverse53PixelThreshold = 4_000_000` is keeping PX
// (3.24-3.7 MP) on the CPU IDWT path when it would benefit from
// GPU IDWT.
//
// `decode()` has its own internal threshold (4 MP); below that, CPU
// IDWT is used. `decodeGPU()` always routes through GPU IDWT
// regardless of pixel count. The v9.6 `recommendedDecodeAPI` says
// 500K–15M pixels should use decodeGPU, contradicting decode()'s
// threshold.
//
// If decodeGPU wins on PX, the threshold is stale and should be
// lowered. Same pattern as the v10.3.0 `_gpuHTEntropyEnabled`
// regression discovery: previously-correct routing decisions can
// become regressions as the codec evolves.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_8_DecodeVsDecodeGPUOnDXPXTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    /// Focus on DX/PX/XA — single-tile fixtures where the
    /// `_gpuInverse53PixelThreshold = 4 MP` may be stale.
    private static let corpus: [Fixture] = [
        Fixture(label: "CT 512² (regression)", filename: "ct_study_001_instance_000001.pgm"),
        Fixture(label: "XA 1024² (regression)", filename: "xa_study_001_instance_000001.pgm"),
        Fixture(label: "PX 2459×1316 (3.24 MP — below threshold)",
                filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX mid 2793×1316 (3.68 MP — below threshold)",
                filename: "medical-real/px_real_mid_2793x1316.pgm"),
        Fixture(label: "PX large 2812×1316 (3.7 MP — below threshold)",
                filename: "medical-real/px_real_large_2812x1316.pgm"),
        Fixture(label: "DX small 2224×2798 (6.22 MP)",
                filename: "medical-real/dx_real_small_2224x2798.pgm"),
        Fixture(label: "DX 2800×2288 (6.4 MP)",
                filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX large 2544×3056 (7.77 MP)",
                filename: "medical-real/dx_real_large_2544x3056.pgm"),
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
        let median: Double, min: Double, max: Double, std: Double
    }

    private static func summarise(_ xs: [Double]) -> Stats {
        let sorted = xs.sorted()
        let mean = xs.reduce(0, +) / Double(xs.count)
        let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(xs.count)
        return Stats(median: sorted[xs.count / 2],
                     min: sorted.first!, max: sorted.last!,
                     std: variance.squareRoot())
    }

    func testDecode_vs_DecodeGPU_DXPX_10Trials() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()
        let session = J2KMetalSession()
        let warmups = 3
        let nTrials = 10

        struct Row {
            let label: String, pixels: Int
            let decodeStats: Stats, decodeGPUStats: Stats
            let deltas: [Double]
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }
            let codestream = try await encoder.encode(image)

            // Warm-up both paths.
            for _ in 0..<warmups {
                _ = try await decoder.decode(codestream)
                _ = try await decoder.decodeGPU(codestream, session: session)
            }

            // Interleaved sampling.
            var decTimes: [Double] = [], gpuTimes: [Double] = [], deltas: [Double] = []
            for _ in 0..<nTrials {
                let t0d = Date()
                _ = try await decoder.decode(codestream)
                let decMs = Date().timeIntervalSince(t0d) * 1000

                let t0g = Date()
                _ = try await decoder.decodeGPU(codestream, session: session)
                let gpuMs = Date().timeIntervalSince(t0g) * 1000

                decTimes.append(decMs)
                gpuTimes.append(gpuMs)
                deltas.append(decMs - gpuMs)  // positive = decodeGPU wins
            }

            rows.append(Row(label: fix.label, pixels: image.width * image.height,
                            decodeStats: Self.summarise(decTimes),
                            decodeGPUStats: Self.summarise(gpuTimes),
                            deltas: deltas))
        }

        print("=== v10.8 decode() vs decodeGPU() (lossless HT, M2 release, 10 trials) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Trials: \(nTrials)")
        if !skipped.isEmpty { print("Skipped: \(skipped.joined(separator: ", "))") }
        print("")
        print("| Fixture | px | decode() med | decodeGPU med | Δ med | Δ std | Δ min | Δ max | frac GPU wins |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let dStats = Self.summarise(r.deltas)
            let nPos = r.deltas.filter { $0 > 0 }.count
            let fracPos = Double(nPos) / Double(r.deltas.count)
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.2f | %4.2f | %+5.2f | %+5.2f | %.0f%% |",
                         r.label, r.pixels,
                         r.decodeStats.median, r.decodeGPUStats.median,
                         dStats.median, dStats.std, dStats.min, dStats.max,
                         100 * fracPos))
        }
        print("")
        print("Interpretation:")
        print("  - Δ = decode() − decodeGPU(). Positive = decodeGPU() wins.")
        print("  - PX (3.24-3.7 MP) is BELOW the 4 MP threshold in decode() and routes")
        print("    to CPU IDWT. If decodeGPU() wins ≥3 ms here, the threshold is stale.")
        print("  - DX (6.2-7.8 MP) is ABOVE threshold so both paths should use GPU IDWT;")
        print("    Δ ≈ 0 expected, divergence indicates code-path differences worth probing.")

        XCTAssertFalse(rows.isEmpty)
    }
}
#endif
