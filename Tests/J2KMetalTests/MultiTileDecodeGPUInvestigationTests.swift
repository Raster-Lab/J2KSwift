// MultiTileDecodeGPUInvestigationTests.swift
//
// v6.3.0 work item E1.0 (per docs/V6_3_0_PLAN.md) — multi-tile
// decode bug investigation. v6.2.0's release-candidate validation
// caught `J2KError.malformedBlock` from `applyEntropyDecoding` when
// multi-tile codestreams routed through the GPU pipeline. v6.2.0
// narrowed the routing to single-tile only via `!metadata.isMultiTile`
// in `decode()`.
//
// This test reproduces the failing path the v6.2.0 rc validation
// caught — uses `J2KMultiTileEncoder` to match `HTTileParityMatrixTests`'s
// codestream shape — and triangulates which (fixture, mode) combinations
// actually fail and on which decode entry point.
//
// Three decode entry points × full HTTileParityMatrixTests matrix:
//
//   (A) `J2KDecoder().decode()` with both gates ON
//       — !isMultiTile guard routes to CPU regardless of flags;
//       expected ✅ on every cell (production-default after v6.2.0)
//   (B) `J2KDecoder().decodeWithGPUHT()`
//       — pre-D-series GPU path; sets useGPUHT=true on instance var,
//       calls decodeGPU which dispatches multi-tile to decodeMultiTileGPU
//       UNCONDITIONALLY. If THIS fails on a cell, the bug is in the
//       multi-tile GPU pipeline (older than D-series).
//   (C) `J2KDecoder().decodeGPU()` (no useGPUHT)
//       — GPU IDWT only, CPU entropy. If (B) fails but (C) passes
//       on the same cell, the bug is in GPU HT entropy multi-tile
//       dispatch specifically.
//
// Findings drive the E1.1 fix scope.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MultiTileDecodeGPUInvestigationTests: XCTestCase {

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
        let modality: String
        let filename: String
    }

    // Same modalities + fixtures HTTileParityMatrixTests uses.
    private static let fixtures: [CorpusFixture] = [
        CorpusFixture(label: "MR 886²",      modality: "MR", filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",     modality: "XA", filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316", modality: "PX", filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288", modality: "DX", filename: "dx_study_002_instance_000001.pgm"),
    ]

    private func htConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    private struct CellResult: Sendable {
        let fixture: String
        let mode: String
        let cols: Int
        let rows: Int
        let bytesEncoded: Int
        let resultA: String  // ✅ / ❌ + error
        let resultB: String
        let resultC: String
    }

    private func tryDecode(_ op: () async throws -> J2KImage) async -> String {
        do {
            _ = try await op()
            return "✅"
        } catch {
            return "❌ \(error)"
        }
    }

    /// Triangulation matrix: 4 fixtures × 3 multi-tile modes via
    /// `J2KMultiTileEncoder` (matching `HTTileParityMatrixTests`'s
    /// codestream shape), each decoded via 3 entry points. Diagnostic
    /// — does not assert; the print is the input to the E1.1 fix scope.
    func testMultiTileGPUDecode_TriangulationMatrix_FullCorpus() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let modes: [(label: String, mode: J2KHTTileMode)] = [
            ("2x2",     .tiles2x2),
            ("4x4",     .tiles4x4),
            ("strips4", .strips4),
        ]

        var results: [CellResult] = []

        for fix in Self.fixtures {
            guard let img = loadPGM16(fix.filename) else {
                print("[skip] \(fix.label) — fixture not present")
                continue
            }
            let cfg = htConfig()

            for (modeLabel, mode) in modes {
                let layout = J2KEncodeTilePlanner.plan(
                    imageWidth: img.width, imageHeight: img.height,
                    decompositionLevels: 5, mode: mode)
                guard layout.isMultiTile else { continue }

                // Match HTTileParityMatrixTests's encode path.
                let result: J2KMultiTileEncodeResult
                do {
                    result = try await J2KMultiTileEncoder.encode(
                        image: img, layout: layout, configuration: cfg)
                } catch {
                    results.append(CellResult(
                        fixture: fix.label, mode: modeLabel,
                        cols: layout.cols, rows: layout.rows,
                        bytesEncoded: 0,
                        resultA: "encode ❌ \(error)",
                        resultB: "—", resultC: "—"))
                    continue
                }
                let codestream = result.codestream

                // Save + restore both gate flags.
                let prevInv = DecoderPipeline._gpuInverse53Enabled
                let prevHT = DecoderPipeline._gpuHTEntropyEnabled
                defer {
                    DecoderPipeline._gpuInverse53Enabled = prevInv
                    DecoderPipeline._gpuHTEntropyEnabled = prevHT
                }

                // (A) decode() with both static flags ON.
                DecoderPipeline._gpuInverse53Enabled = true
                DecoderPipeline._gpuHTEntropyEnabled = true
                let resultA = await tryDecode {
                    try await J2KDecoder().decode(codestream)
                }

                // (B) decodeWithGPUHT() — useGPUHT instance var path.
                DecoderPipeline._gpuInverse53Enabled = false
                DecoderPipeline._gpuHTEntropyEnabled = false
                let resultB = await tryDecode {
                    try await J2KDecoder().decodeWithGPUHT(codestream)
                }

                // (C) decodeGPU() — GPU IDWT only.
                // v6.3.0 E1.1 re-enabled: the pre-existing process
                // crash was a downstream effect of the corrupt
                // codeblock layout in decodeTilePayloadGPU (now fixed
                // by passing tileOriginX/Y to extractTileData).
                let resultC = await tryDecode {
                    try await J2KDecoder().decodeGPU(codestream)
                }

                results.append(CellResult(
                    fixture: fix.label, mode: modeLabel,
                    cols: layout.cols, rows: layout.rows,
                    bytesEncoded: codestream.count,
                    resultA: resultA, resultB: resultB, resultC: resultC))
            }
        }

        print("=== v6.3.0 E1.0 — multi-tile decode triangulation matrix ===")
        print("(Encoder: J2KMultiTileEncoder — matches HTTileParityMatrixTests's codestream shape)")
        print()
        print("Entry points:")
        print("  (A) decode() with _gpuInverse53Enabled=true, _gpuHTEntropyEnabled=true")
        print("  (B) decodeWithGPUHT() — sets useGPUHT instance var")
        print("  (C) decodeGPU() — GPU IDWT only (no HT entropy GPU)")
        print()
        print("| fixture | mode | grid | bytes | (A) | (B) | (C) |")
        print("|---|---|---|---:|:---|:---|:---|")
        for r in results {
            print("| \(r.fixture) | \(r.mode) | \(r.cols)×\(r.rows) | \(r.bytesEncoded) | \(r.resultA) | \(r.resultB) | \(r.resultC) |")
        }
        print()
        let aFails = results.filter { $0.resultA.starts(with: "❌") }.count
        let bFails = results.filter { $0.resultB.starts(with: "❌") }.count
        let cFails = results.filter { $0.resultC.starts(with: "❌") }.count
        print("Summary: (A) \(aFails) failures · (B) \(bFails) failures · (C) \(cFails) failures of \(results.count) cells")
        print()
        print("Triangulation logic per cell:")
        print("  (A) ✅ + (B) ❌ + (C) ✅ → bug in GPU HT entropy multi-tile dispatch")
        print("  (A) ✅ + (B) ❌ + (C) ❌ → bug in GPU IDWT multi-tile path AND HT entropy")
        print("  (A) ✅ + (B) ✅ + (C) ✅ → no bug for this cell (v6.2.0 narrow over-cautious)")
        print("  (A) ❌                    → bug surfaces even on the v6.2.0 production-default path")
    }
}
