// V10Phase8DecodeWallBudgetTests.swift
//
// v10.0-research Phase 8: decode wall budget on Apple M2.
// Symmetric to Phase 1 (encode wall budget) but for the decode side.
//
// Per `project_v8_4_lever_ceiling.md`, DX decode wall was estimated as
// entropy 57 % + iDWT 39 % = 96 % on the v8.4 measurement. Phase 8
// re-measures on the v9.4-era v10.0-research binary with fresh M2
// numbers and the canonical `recommendedDecodeAPI` routing (CPU /
// decodeGPU / decodeWithGPUHT per pixel-count threshold).
//
// Phase 8 gate: does any non-entropy stage clear ≥10 % of wall on DX
// with ns/sample > 20 ceiling threshold? If yes, that stage is a v11
// decoder-side candidate. If no, 12th lever-ceiling confirmation.
//
// Decode paths exercised:
//   - CPU `decode`           (pixels < 256² per recommendedDecodeAPI)
//   - GPU `decodeGPU`        (256² ≤ pixels < 3 MP)
//   - GPU `decodeWithGPUHT`  (pixels ≥ 3 MP)
//
// Run with:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test -c release --filter V10Phase8DecodeWallBudgetTests

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10Phase8DecodeWallBudgetTests: XCTestCase {

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

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private struct Row {
        let label: String
        let pixels: Int
        let totalMs: Double             // end-to-end decode wall (median)
        let apiUsed: String             // CPU / decodeGPU / decodeWithGPUHT
        // Stage walls from J2KDecodeTimings (ms, mean over n runs)
        let extract: Double
        let entropy: Double
        let gpuDispatch: Double
        let dequant: Double
        let idwt: Double
        let invColour: Double
        let dcUnshift: Double
        let reconstruct: Double

        var stageSum: Double {
            extract + entropy + gpuDispatch + dequant + idwt + invColour + dcUnshift + reconstruct
        }
        var pct: (Double) -> Double {
            { val in self.totalMs > 0 ? 100.0 * val / self.totalMs : 0 }
        }
    }

    /// Phase 8 deliverable — per-fixture decode wall budget across the
    /// medical corpus on M2, using the recommended decode API per
    /// pixel-count threshold (so each fixture exercises its production
    /// hot path).
    func testDecodeWallBudget_Corpus_M2() async throws {
        #if DEBUG
        print("⚠️  Phase 8 in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter V10Phase8DecodeWallBudgetTests")
        #endif

        // Pre-warm Metal session so first decode doesn't pay cold-start.
        await J2KDecoder.preWarm(includeWarmupDispatch: true)

        let runs = 7
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()
        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let codestream = try await encoder.encode(image)
            let recommendation = J2KDecoder.recommendedDecodeAPI(
                width: image.width, height: image.height)
            let apiUsed = "\(recommendation)"

            // Warm-up (excluded).
            _ = try await decoder.decode(codestream)

            var times: [TimeInterval] = []
            var sumExtract: TimeInterval = 0, sumEntropy: TimeInterval = 0
            var sumGPU: TimeInterval = 0, sumDeq: TimeInterval = 0
            var sumIDWT: TimeInterval = 0, sumInvCol: TimeInterval = 0
            var sumDCU: TimeInterval = 0, sumRecon: TimeInterval = 0

            for _ in 0..<runs {
                J2KDecodeTimings.reset()
                let t0 = Date()
                // Route to the recommended decode API for the fixture
                let _ = switch recommendation {
                case .cpu:                try await decoder.decode(codestream)
                case .decodeGPU:          try await decoder.decodeGPU(codestream)
                case .decodeWithGPUHT:    try await decoder.decodeWithGPUHT(codestream)
                }
                times.append(Date().timeIntervalSince(t0))
                let s = J2KDecodeTimings.snapshot()
                sumExtract += s.extractTileData
                sumEntropy += s.entropyDecoding
                sumGPU += s.gpuHTDispatch
                sumDeq += s.dequantization
                sumIDWT += s.inverseWaveletTransform
                sumInvCol += s.inverseColorTransform
                sumDCU += s.dcLevelUnshift
                sumRecon += s.reconstructImage
            }
            let median = times.sorted()[runs / 2] * 1000.0
            let scale = 1000.0 / Double(runs)
            rows.append(Row(
                label: fix.label, pixels: image.width * image.height,
                totalMs: median, apiUsed: apiUsed,
                extract: sumExtract * scale, entropy: sumEntropy * scale,
                gpuDispatch: sumGPU * scale, dequant: sumDeq * scale,
                idwt: sumIDWT * scale, invColour: sumInvCol * scale,
                dcUnshift: sumDCU * scale, reconstruct: sumRecon * scale))
        }

        XCTAssertFalse(rows.isEmpty, "No corpus fixtures resolved.")

        print()
        print("=== v10.0 Phase 8 — decode wall budget on M2 (warm, n=\(runs), routed via recommendedDecodeAPI) ===")
        print()
        print("## Per-fixture stage breakdown (ms)")
        print()
        print("| Fixture | px | API | wall ms | extract | entropy | gpuDisp | dequant | iDWT | invColour | dcUnshift | reconstr | sum |")
        print("|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %@ | %6.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f |",
                r.label, r.pixels, r.apiUsed, r.totalMs,
                r.extract, r.entropy, r.gpuDispatch, r.dequant,
                r.idwt, r.invColour, r.dcUnshift, r.reconstruct, r.stageSum))
        }

        print()
        print("## Per-stage % of decode wall (Phase 8 gate: any non-entropy stage ≥10 % on DX?)")
        print()
        print("| Fixture | extract % | entropy % | gpuDisp % | dequant % | iDWT % | invColour % | dcUnshift % | reconstr % | accounted % |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let p = r.pct
            print(String(format: "| %@ | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f | %5.1f |",
                r.label,
                p(r.extract), p(r.entropy), p(r.gpuDispatch), p(r.dequant),
                p(r.idwt), p(r.invColour), p(r.dcUnshift), p(r.reconstruct),
                p(r.stageSum)))
        }

        // DX-specific decision support
        print()
        print("## DX decision support — is any non-entropy stage a v11 decoder-side candidate?")
        if let dx = rows.first(where: { $0.label.starts(with: "DX") }) {
            let p = dx.pct
            print(String(format: "  DX wall: %.2f ms", dx.totalMs))
            print(String(format: "  - entropy:    %5.2f ms (%5.1f %% wall) [excluded from non-entropy gate]", dx.entropy, p(dx.entropy)))
            print(String(format: "  - extract:    %5.2f ms (%5.1f %%)", dx.extract, p(dx.extract)))
            print(String(format: "  - gpuDisp:    %5.2f ms (%5.1f %%)", dx.gpuDispatch, p(dx.gpuDispatch)))
            print(String(format: "  - dequant:    %5.2f ms (%5.1f %%)", dx.dequant, p(dx.dequant)))
            print(String(format: "  - iDWT:       %5.2f ms (%5.1f %%)", dx.idwt, p(dx.idwt)))
            print(String(format: "  - invColour:  %5.2f ms (%5.1f %%)", dx.invColour, p(dx.invColour)))
            print(String(format: "  - dcUnshift:  %5.2f ms (%5.1f %%)", dx.dcUnshift, p(dx.dcUnshift)))
            print(String(format: "  - reconstr:   %5.2f ms (%5.1f %%)", dx.reconstruct, p(dx.reconstruct)))
            print()
            print("  Phase 8 gate threshold: ≥10 % of wall AND ns/sample > 20.")
            let nonEntropy = [
                ("extract", dx.extract), ("gpuDispatch", dx.gpuDispatch),
                ("dequant", dx.dequant), ("iDWT", dx.idwt),
                ("invColour", dx.invColour), ("dcUnshift", dx.dcUnshift),
                ("reconstruct", dx.reconstruct),
            ]
            let candidates = nonEntropy.filter { p($0.1) >= 10.0 }
            if candidates.isEmpty {
                print("  → No non-entropy stage clears the 10 % threshold on DX.")
                print("  → 12th lever-ceiling confirmation; close v10 Phase 8 as research.")
            } else {
                print("  → Candidate stages clearing 10 % wall:")
                for (name, ms) in candidates {
                    print(String(format: "      %@: %5.2f ms (%5.1f %% wall) — needs ns/sample check", name, ms, p(ms)))
                }
            }
        }
    }
}
