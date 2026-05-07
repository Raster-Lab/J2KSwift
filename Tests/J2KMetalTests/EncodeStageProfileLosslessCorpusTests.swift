// EncodeStageProfileLosslessCorpusTests.swift
//
// Per-stage encode breakdown for the lossless HT-conformant 5/3
// production path across the medical corpus. Mirrors the existing
// `J2KMedicalCorpusEncodePerformanceTests.testCorpusEncodeAcrossAPIs`
// stage table but runs in **lossless mode** (`useReversibleFilter:
// true`, `bitrateMode: .lossless`) — the path the v5.38+ work has
// shipped on top of, where the previous 9/7 lossy stage breakdown
// is misleading because PCRD-opt + quantization don't fire.
//
// Why this exists now
//
//   The recent perf arcs (v6-alpha6 entropy, v6-alpha7 tier-2)
//   produced four consecutive "wash" results. The PR #308 finding
//   showed tier-2 was 2.5 % of DX wall (not the cited 9 %), which
//   suggests other stage estimates may also be off. Before swinging
//   at any next stage we want **fresh, lossless-mode-specific stage
//   numbers**.
//
//   Existing data points (likely stale or off-mode):
//     - "entropy is 45 % of DX" (cited in v6-alpha6 plan, measured
//       in lossy 9/7 mode pre-v5.38)
//     - "tier-2 is 9 % of DX" (cited in #307; #308 measured 2.5 %)
//     - "DWT is 8 % of DX" (cited in v6-alpha6 plan)
//
//   This test produces the canonical lossless breakdown that future
//   perf-arc plans should cite.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class EncodeStageProfileLosslessCorpusTests: XCTestCase {

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

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Diagnostic — per-stage breakdown across the lossless corpus.
    /// Median of 5 release-mode encodes per fixture; stage means
    /// derived from `J2KEncodeTimings.snapshot()` accumulated across
    /// all 5 runs and divided.
    func testEncodeStageProfile_LosslessCorpus_M2Baseline() async throws {
        #if DEBUG
        print("⚠️  Stage breakdown in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter EncodeStageProfileLosslessCorpusTests")
        #endif

        let n = 5
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        struct Row {
            let label: String
            let pixels: Int
            let totalMs: Double
            let pre: Double
            let colour: Double
            let dwt: Double
            let quant: Double
            let entropy: Double
            let rateCtrl: Double
            let codestream: Double
        }

        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warm-up (excluded).
            _ = try await encoder.encode(image)

            var times: [TimeInterval] = []
            var sumPre: TimeInterval = 0, sumColor: TimeInterval = 0
            var sumDWT: TimeInterval = 0, sumQuant: TimeInterval = 0
            var sumEntropy: TimeInterval = 0, sumRate: TimeInterval = 0
            var sumCS: TimeInterval = 0
            for _ in 0..<n {
                J2KEncodeTimings.reset()
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
            }
            let median = times.sorted()[n / 2] * 1000.0
            let scale = 1000.0 / Double(n)
            rows.append(Row(
                label: fix.label, pixels: image.width * image.height,
                totalMs: median,
                pre: sumPre * scale, colour: sumColor * scale,
                dwt: sumDWT * scale, quant: sumQuant * scale,
                entropy: sumEntropy * scale,
                rateCtrl: sumRate * scale,
                codestream: sumCS * scale))
        }

        XCTAssertFalse(rows.isEmpty, "No corpus fixtures resolved — fixture path layout changed?")

        print("=== lossless 5/3 HT-conformant per-stage breakdown (Apple M2, release, median of \(n)) ===")
        print()
        print("| Fixture | px | total ms | preproc | colour | DWT | quant | entropy | rateCtrl | codestream | sum |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let sum = r.pre + r.colour + r.dwt + r.quant + r.entropy + r.rateCtrl + r.codestream
            print(String(format: "| %@ | %d | %6.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f |",
                r.label, r.pixels, r.totalMs,
                r.pre, r.colour, r.dwt, r.quant, r.entropy, r.rateCtrl, r.codestream, sum))
        }

        // Per-stage % of total wall on each fixture — what to read off
        // when picking the next perf-arc target.
        print()
        print("Per-stage % of TOTAL encode wall:")
        print("| Fixture | preproc % | colour % | DWT % | quant % | entropy % | rateCtrl % | codestream % | accounted % |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let total = r.totalMs
            let pct = { (x: Double) in 100.0 * x / total }
            let sum = r.pre + r.colour + r.dwt + r.quant + r.entropy + r.rateCtrl + r.codestream
            print(String(format: "| %@ | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f |",
                r.label, pct(r.pre), pct(r.colour), pct(r.dwt), pct(r.quant),
                pct(r.entropy), pct(r.rateCtrl), pct(r.codestream),
                pct(sum)))
        }

        print()
        print("Reading the table:")
        print("  - 'sum' is the sum of all 7 stage timings; 'accounted %' = sum / total.")
        print("  - 100 - accounted % is overhead OUTSIDE the timed regions: allocator,")
        print("    `withUnsafe...` wrappers, dispatch glue, codestream marker writes")
        print("    that aren't tracked by any of the 7 stage buckets, etc.")
        print("  - The largest 'X %' column on DX 2800×2288 is the next perf-arc target")
        print("    (assuming the gap is large enough to overcome the M2 noise band ±5 %).")
    }
}
