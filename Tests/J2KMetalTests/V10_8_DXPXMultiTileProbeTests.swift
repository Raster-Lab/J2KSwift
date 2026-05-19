// V10_8_DXPXMultiTileProbeTests.swift
//
// v10.8-research Phase 3 — probe whether DX/PX decode benefits from
// being encoded with multi-tile (2x2) layout vs single-tile.
//
// The v9.6 release shipped an MG-only 2x2 tile override
// (`J2KEncodeTilePlanner.auto` gated on `pixels ≥ 12 MP AND
// min(w,h) ≥ 2400`). DX 2544×3056 has min(w,h) = 2544 ≥ 2400 but
// 7.77 MP < 12 MP, so it stays single-tile.
//
// On single-tile DX (6-8 MP) the decode wall is ~48-58 ms;
// Kakadu ~38-39 ms. Gap = 1.05-1.5×. Could 2x2 tiling close it?
//
// 2x2 tiling for DX puts each tile at ~2 MP, which:
//   - parallelises entropy decode 4-way (vs 1-way for single-tile)
//   - keeps each tile's IDWT working set L2-resident (~8 MB at L1)
//   - triggers the v8.2 routing fix: tilePixels < 3 MP → CPU IDWT
//
// This is a CODESTREAM CHANGE (MAJOR scope per RELEASING.md) so
// only relevant if the decode win is ≥3 ms.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_8_DXPXMultiTileProbeTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "PX 2459×1316", filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX large 2812×1316", filename: "medical-real/px_real_large_2812x1316.pgm"),
        Fixture(label: "DX 2800×2288", filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX large 2544×3056", filename: "medical-real/dx_real_large_2544x3056.pgm"),
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

    private func htLosslessConfig(tile2x2: Bool, image: J2KImage) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        if tile2x2 {
            // 2×2 layout: each tile ≈ ⌈W/2⌉ × ⌈H/2⌉.
            cfg.tileSize = (
                width: (image.width + 1) / 2,
                height: (image.height + 1) / 2)
        }
        return cfg
    }

    private func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    func testDXPX_SingleVsMultiTile_10Trials() async throws {
        let warmups = 3
        let nTrials = 10
        let decoder = J2KDecoder()

        struct Row {
            let label: String, pixels: Int
            let singleTileMs: Double
            let multiTileMs: Double
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }

            // Encode each fixture twice — single-tile + 2x2 tile.
            let cfgSingle = htLosslessConfig(tile2x2: false, image: image)
            let cfg2x2 = htLosslessConfig(tile2x2: true, image: image)
            let csSingle = try await J2KEncoder(encodingConfiguration: cfgSingle).encode(image)
            let cs2x2 = try await J2KEncoder(encodingConfiguration: cfg2x2).encode(image)

            // Warm-up both.
            for _ in 0..<warmups {
                _ = try await decoder.decode(csSingle)
                _ = try await decoder.decode(cs2x2)
            }

            // Interleaved sampling.
            var singleTimes: [Double] = [], multiTimes: [Double] = []
            for _ in 0..<nTrials {
                let t0a = Date()
                _ = try await decoder.decode(csSingle)
                singleTimes.append(Date().timeIntervalSince(t0a) * 1000)

                let t0b = Date()
                _ = try await decoder.decode(cs2x2)
                multiTimes.append(Date().timeIntervalSince(t0b) * 1000)
            }

            rows.append(Row(label: fix.label,
                            pixels: image.width * image.height,
                            singleTileMs: median(singleTimes),
                            multiTileMs: median(multiTimes)))
        }

        print("=== v10.8 DX/PX single-tile vs 2×2 multi-tile encode A/B (M2 release, 10 trials) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)")
        if !skipped.isEmpty { print("Skipped: \(skipped.joined(separator: ", "))") }
        print("")
        print("| Fixture | px | single-tile ms | 2×2 ms | Δ ms | speedup |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            let delta = r.singleTileMs - r.multiTileMs
            let speedup = r.singleTileMs / r.multiTileMs
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.2f | %.2f× |",
                         r.label, r.pixels,
                         r.singleTileMs, r.multiTileMs, delta, speedup))
        }
        print("")
        print("Interpretation:")
        print("  - Positive Δ = 2×2 multi-tile decodes faster. If ≥3 ms on DX class,")
        print("    encoder tile-planner could be widened to cover DX (currently MG-only).")
        print("  - Codestream bytes WILL change (codestream tile structure differs).")
        print("  - This is a CODESTREAM CHANGE — would be MAJOR per RELEASING.md.")

        XCTAssertFalse(rows.isEmpty)
    }
}
#endif
