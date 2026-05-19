// V10_7_GPUHTEntropyFlagFlipVarianceTests.swift
//
// v10.7-research — 10-trial interleaved variance bench confirming
// the engagement-check finding: `_gpuHTEntropyEnabled = true`
// (current production default) regresses MG-class decode by 13-21 ms
// on M2.
//
// Per-trial interleave (flag-OFF, flag-ON) so thermal/scheduler
// drift hits both paths symmetrically. Reports mean / median / std
// for each path plus the per-trial Δ distribution.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_7_GPUHTEntropyFlagFlipVarianceTests: XCTestCase {

    private static let corpus: [(String, String)] = [
        ("MG small 3516×4784",   "medical-real/mg_real_small_3516x4784.pgm"),
        ("MG mid 3518×4784",     "medical-real/mg_real_mid_3518x4784.pgm"),
        ("MG large 3521×4784",   "medical-real/mg_real_large_3521x4784.pgm"),
        ("DX large 2544×3056",   "medical-real/dx_real_large_2544x3056.pgm"),
        ("PX large 2812×1316",   "medical-real/px_real_large_2812x1316.pgm"),
        ("XA 1024² (regression check)", "xa_study_001_instance_000001.pgm"),
        ("CT 512² (regression check)",  "ct_study_001_instance_000001.pgm"),
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
        let mean: Double, median: Double, min: Double, max: Double, std: Double
    }

    private static func summarise(_ xs: [Double]) -> Stats {
        let n = Double(xs.count)
        let mean = xs.reduce(0, +) / n
        let sorted = xs.sorted()
        let variance = xs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
        return Stats(mean: mean, median: sorted[xs.count / 2],
                     min: sorted.first!, max: sorted.last!,
                     std: variance.squareRoot())
    }

    private func timedDecode(decoder: J2KDecoder, codestream: Data, flagOn: Bool) async throws -> Double {
        DecoderPipeline._gpuHTEntropyEnabled = flagOn
        let t0 = Date()
        _ = try await decoder.decode(codestream)
        return Date().timeIntervalSince(t0) * 1000
    }

    func testFlagFlipVariance_10Trials() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        let warmups = 3
        let nTrials = 10

        let saved = DecoderPipeline._gpuHTEntropyEnabled
        defer { DecoderPipeline._gpuHTEntropyEnabled = saved }

        struct Row {
            let label: String, pixels: Int
            let onStats: Stats, offStats: Stats
            let deltas: [Double]
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for (label, filename) in Self.corpus {
            guard let image = try loadPGM16(filename) else {
                skipped.append(label); continue
            }
            let codestream = try await encoder.encode(image)

            // Warm-up both paths.
            for _ in 0..<warmups {
                _ = try await timedDecode(decoder: decoder, codestream: codestream, flagOn: true)
                _ = try await timedDecode(decoder: decoder, codestream: codestream, flagOn: false)
            }

            // Interleaved sampling.
            var onTimes: [Double] = [], offTimes: [Double] = [], deltas: [Double] = []
            for _ in 0..<nTrials {
                let onMs = try await timedDecode(decoder: decoder, codestream: codestream, flagOn: true)
                let offMs = try await timedDecode(decoder: decoder, codestream: codestream, flagOn: false)
                onTimes.append(onMs); offTimes.append(offMs)
                deltas.append(onMs - offMs)  // positive = flag-OFF is faster
            }

            rows.append(Row(label: label, pixels: image.width * image.height,
                            onStats: Self.summarise(onTimes),
                            offStats: Self.summarise(offTimes),
                            deltas: deltas))
        }

        DecoderPipeline._gpuHTEntropyEnabled = saved

        print("=== v10.7 _gpuHTEntropyEnabled flag-flip variance bench (M2 release, 10 interleaved trials) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Trials/path: \(nTrials)")
        if !skipped.isEmpty { print("Skipped: \(skipped.joined(separator: ", "))") }
        print("")
        print("| Fixture | ON med | ON std | OFF med | OFF std | Δ mean | Δ med | Δ std | Δ min | Δ max | frac OFF wins |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let dStats = Self.summarise(r.deltas)
            let nPos = r.deltas.filter { $0 > 0 }.count
            let fracPos = Double(nPos) / Double(r.deltas.count)
            print(String(format: "| %@ | %6.2f | %4.2f | %6.2f | %4.2f | %+5.2f | %+5.2f | %4.2f | %+5.2f | %+5.2f | %.0f%% |",
                         r.label,
                         r.onStats.median, r.onStats.std,
                         r.offStats.median, r.offStats.std,
                         dStats.mean, dStats.median, dStats.std,
                         dStats.min, dStats.max, 100 * fracPos))
        }
        print("")
        print("Decision rule:")
        print("  - 'Δ' = decode(flag-ON) − decode(flag-OFF). Positive = flag-OFF wins.")
        print("  - RELIABLE WIN for flag flip: median Δ ≥ 3 ms AND fraction OFF wins ≥ 70%")
        print("  - RELIABLE WASH: |median Δ| < 1 ms AND fraction in [40%, 60%]")
        XCTAssertFalse(rows.isEmpty)
    }
}
#endif
