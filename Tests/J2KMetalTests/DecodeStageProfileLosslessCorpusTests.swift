// DecodeStageProfileLosslessCorpusTests.swift
//
// v6.2.0 work item B2 (per docs/V6_2_0_PLAN.md) — decoder-side
// stage profile gap-fill. Mirrors `EncodeStageProfileLosslessCorpusTests`
// (PR #309) for the decode path: runs the lossless 5/3 HT-conformant
// corpus through `J2KDecoder.decode`, captures `J2KDecodeTimings`
// snapshots per run, prints the canonical per-stage breakdown.
//
// Why this lands first in the v6.2.0 trajectory
//
//   The encode-side profile from #309 gave us the data that
//   identified DWT as the v6.1.0 lever. The decode-side has had
//   `J2KDecodeTimings` infrastructure since v5.24.0 but no
//   canonical corpus breakdown — every recent decoder-side work
//   would have to start by writing this test first. Doing it now
//   gap-fills the baseline so future decoder perf arcs (whenever
//   they come) start from data, not estimates.
//
// Sub-stages tracked (per `J2KDecodeTimings`):
//
//   extractTileData          — codestream + packet header parse
//   entropyDecoding          — total entropy stage (CPU + GPU)
//     gpuHTDispatch          — sub-stage of entropy: GPU HT decode only
//     entropyRegroup         — entropy − gpuHTDispatch (CPU regroup)
//   dequantization           — identity for lossless reversible
//   inverseWaveletTransform  — inverse 5/3 (CPU or GPU IDWT)
//   inverseColorTransform    — RCT/ICT (zero for grayscale corpus)
//   dcLevelUnshift           — re-add the DC bias
//   reconstructImage         — compose final J2KImage
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class DecodeStageProfileLosslessCorpusTests: XCTestCase {

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

    /// Diagnostic — per-stage breakdown of `J2KDecoder.decode` across
    /// the lossless corpus. Median of 5 release-mode runs per fixture;
    /// stage means derived from `J2KDecodeTimings.snapshot()`
    /// accumulated across all 5 runs and divided.
    ///
    /// Encodes are done up-front per fixture (warm encoder, NOT
    /// timed) so the test isolates the decode path.
    func testDecodeStageProfile_LosslessCorpus_M2Baseline() async throws {
        #if DEBUG
        print("⚠️  Decode stage breakdown in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter DecodeStageProfileLosslessCorpusTests")
        #endif

        let n = 5
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        struct Row {
            let label: String
            let pixels: Int
            let codestreamBytes: Int
            let totalMs: Double
            let extract: Double
            let entropy: Double
            let gpuHT: Double
            let regroup: Double
            let dequant: Double
            let idwt: Double
            let colour: Double
            let dcShift: Double
            let reconstruct: Double
        }

        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Encode once (NOT timed) — codestream feeds the decode benchmark.
            let codestream = try await encoder.encode(image)

            // Warm decoder.
            _ = try await decoder.decode(codestream)

            var times: [TimeInterval] = []
            var sumExtract: TimeInterval = 0, sumEntropy: TimeInterval = 0
            var sumGPUHT: TimeInterval = 0, sumDequant: TimeInterval = 0
            var sumIDWT: TimeInterval = 0, sumColor: TimeInterval = 0
            var sumDcShift: TimeInterval = 0, sumReconstruct: TimeInterval = 0
            for _ in 0..<n {
                J2KDecodeTimings.reset()
                let t0 = Date()
                _ = try await decoder.decode(codestream)
                times.append(Date().timeIntervalSince(t0))
                let s = J2KDecodeTimings.snapshot()
                sumExtract += s.extractTileData
                sumEntropy += s.entropyDecoding
                sumGPUHT += s.gpuHTDispatch
                sumDequant += s.dequantization
                sumIDWT += s.inverseWaveletTransform
                sumColor += s.inverseColorTransform
                sumDcShift += s.dcLevelUnshift
                sumReconstruct += s.reconstructImage
            }
            let median = times.sorted()[n / 2] * 1000.0
            let scale = 1000.0 / Double(n)
            rows.append(Row(
                label: fix.label, pixels: image.width * image.height,
                codestreamBytes: codestream.count,
                totalMs: median,
                extract: sumExtract * scale,
                entropy: sumEntropy * scale,
                gpuHT: sumGPUHT * scale,
                regroup: max(0, (sumEntropy - sumGPUHT) * scale),
                dequant: sumDequant * scale,
                idwt: sumIDWT * scale,
                colour: sumColor * scale,
                dcShift: sumDcShift * scale,
                reconstruct: sumReconstruct * scale))
        }

        XCTAssertFalse(rows.isEmpty, "No corpus fixtures resolved — fixture path layout changed?")

        print("=== lossless 5/3 HT-conformant DECODE per-stage breakdown (Apple M2, release, median of \(n)) ===")
        print()
        print("| Fixture | px | bytes | total ms | extract | entropy | (gpuHT) | (regroup) | dequant | iDWT | colour | dcShift | reconstruct | sum |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let sum = r.extract + r.entropy + r.dequant + r.idwt + r.colour + r.dcShift + r.reconstruct
            print(String(format: "| %@ | %d | %d | %6.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f |",
                r.label, r.pixels, r.codestreamBytes, r.totalMs,
                r.extract, r.entropy, r.gpuHT, r.regroup,
                r.dequant, r.idwt, r.colour, r.dcShift, r.reconstruct,
                sum))
        }

        print()
        print("Per-stage % of TOTAL decode wall:")
        print("| Fixture | extract % | entropy % | (gpuHT %) | dequant % | iDWT % | colour % | dcShift % | reconstruct % | accounted % |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let total = r.totalMs
            let pct = { (x: Double) in 100.0 * x / total }
            let sum = r.extract + r.entropy + r.dequant + r.idwt + r.colour + r.dcShift + r.reconstruct
            print(String(format: "| %@ | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f |",
                r.label, pct(r.extract), pct(r.entropy), pct(r.gpuHT),
                pct(r.dequant), pct(r.idwt), pct(r.colour),
                pct(r.dcShift), pct(r.reconstruct),
                pct(sum)))
        }

        print()
        print("Reading the table:")
        print("  - 'sum' is the sum of the 7 top-level stage timings; 'gpuHT' is a SUB-stage")
        print("    of 'entropy' (entropy = gpuHT + regroup) so it's NOT summed twice.")
        print("  - 'accounted %' = sum / total. Like the encode profile, this can exceed 100%")
        print("    on small fixtures because of `withThrowingTaskGroup` parallelism — stages")
        print("    can record concurrent wall time.")
        print("  - The largest stage on DX 2800×2288 is the next decoder-side perf-arc target")
        print("    (assuming the gap is large enough to overcome the M2 noise band ±5%).")
        print("  - dequant = 0 expected for lossless reversible (identity quantization).")
        print("  - colour = 0 expected for grayscale medical corpus (no MCT).")
    }
}
