// V10_10_StageB1EntropyFilterBench.swift
//
// v10.10-research Phase 2 Stage B.1 — quantify the entropy-stage
// savings from the code-block filter in `extractTileData`.
//
// Before B.1 (v10.4.0 Phase 1): `decodeResolution(level: r)` runs the
// full decode pipeline + downsamples. Thumbnail (level 0) still pays
// full-decode time (~85 ms on MG).
//
// After B.1 (v10.5.0): code-blocks at decomposition levels above the
// kept range are dropped during extract; entropy decode operates on
// the reduced set. iDWT still runs all levels (zeroed for filtered
// bands) and downsample remains at the end. Projected ~50-70% of
// the full Phase 2 speedup.
//
// Stage B.2 (future): iDWT truncation completes the ~13× thumbnail
// win by skipping the iDWT for higher resolution levels and removing
// the downsample step.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_10_StageB1EntropyFilterBench: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "CT 512²",          filename: "ct_study_001_instance_000001.pgm"),
        Fixture(label: "PX 2459×1316",     filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "DX 2800×2288",     filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "MG mid 3518×4784", filename: "medical-real/mg_real_mid_3518x4784.pgm"),
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

    private func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    func testStageB1_EntropyFilter_WallByLevel() async throws {
        let decoder = J2KDecoder()
        let warmups = 2
        let nTrials = 7
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        struct Row {
            let label: String
            let pixels: Int
            let fullMs: Double
            let l4: Double
            let l3: Double
            let l2: Double
            let l1: Double
            let l0: Double
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }
            let codestream = try await encoder.encode(image)

            // Warm-up full-decode path.
            for _ in 0..<warmups {
                _ = try await decoder.decode(codestream)
                _ = try await decoder.decodeResolution(
                    codestream, options: J2KResolutionDecodingOptions(level: 0))
            }

            func bench(level: Int?) async throws -> Double {
                var times: [Double] = []
                for _ in 0..<nTrials {
                    let t0 = Date()
                    if let lv = level {
                        _ = try await decoder.decodeResolution(
                            codestream, options: J2KResolutionDecodingOptions(level: lv))
                    } else {
                        _ = try await decoder.decode(codestream)
                    }
                    times.append(Date().timeIntervalSince(t0) * 1000)
                }
                return median(times)
            }

            let full = try await bench(level: nil)
            let l4 = try await bench(level: 4)
            let l3 = try await bench(level: 3)
            let l2 = try await bench(level: 2)
            let l1 = try await bench(level: 1)
            let l0 = try await bench(level: 0)

            rows.append(Row(label: fix.label, pixels: image.width * image.height,
                            fullMs: full, l4: l4, l3: l3, l2: l2, l1: l1, l0: l0))
        }

        print("=== v10.10 Stage B.1 — decodeResolution wall by level (M2 release, 7 trials) ===")
        print("Processor: \(processorBrandString())")
        if !skipped.isEmpty { print("Skipped: \(skipped.joined(separator: ", "))") }
        print("")
        print("Decode wall (ms) by partial-resolution level:")
        print("| Fixture | px | decode() ms (full) | L4 ms | L3 ms | L2 ms | L1 ms | L0 (thumb) ms | L0 speedup |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let speedup = r.fullMs / max(r.l0, 0.001)
            print(String(format: "| %@ | %d | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f× |",
                         r.label, r.pixels,
                         r.fullMs, r.l4, r.l3, r.l2, r.l1, r.l0, speedup))
        }
        print("")
        print("Interpretation:")
        print("  - decode() is the v10.3.0 production full-decode wall.")
        print("  - L0 (thumbnail) is the bottom of the partial-resolution range.")
        print("  - Stage B.1 win is bounded by the entropy-stage savings; iDWT")
        print("    still runs full + downsample. Stage B.2 will add iDWT truncation.")
        XCTAssertFalse(rows.isEmpty)
    }
}
#endif
