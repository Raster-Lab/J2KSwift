// V730Phase0EntropyProbe.swift
//
// v7.3.0 Phase 0 — HT entropy decoder engine breakdown probe.
//
// Runs a warm decode of each medical-corpus fixture, snapshots the
// `J2KHTEntropyProfile` counters, and prints a per-engine call-count
// breakdown. Combined with a separate micro-benchmark of cost-per-
// call for each engine (TBD in a follow-up), the per-engine
// contribution to decode wall-time is `(count × avg-cost-per-call)`.
//
// Output answers: which engine (MEL, VLC lookup, UVLC, MagSgn read,
// readQuadSamples) is invoked the most, and is therefore the
// highest-leverage SIMD target for v7.3?

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V730Phase0EntropyProbe: XCTestCase {

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

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "MR-small 180²", filename: "mr_study_002_instance_000100.pgm"),
        Fixture(label: "CT 512²",       filename: "ct_study_001_instance_000001.pgm"),
        Fixture(label: "MR 886²",       filename: "mr_study_001_instance_000001.pgm"),
        Fixture(label: "XA 1024²",      filename: "xa_study_001_instance_000001.pgm"),
        Fixture(label: "PX 2459×1316",  filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "DX 2800×2288",  filename: "dx_study_002_instance_000001.pgm"),
    ]

    /// Per-fixture engine call breakdown for one decode (post-warmup).
    /// Run with `_multiTileBatchedEntropyEnabled = false` to ensure
    /// the CPU entropy path fires (the v7.2.0 batched-entropy path
    /// routes to GPU when per-tile pixels ≥ 1 MP, bypassing the CPU
    /// inner loops we want to measure).
    func testEntropyEngineBreakdown_LosslessCorpus() async throws {
        // Force CPU entropy so the inner loops get exercised.
        let prevBatched = DecoderPipeline._multiTileBatchedEntropyEnabled
        let prevHT = DecoderPipeline._gpuHTEntropyEnabled
        let prevInv = DecoderPipeline._gpuInverse53Enabled
        defer {
            DecoderPipeline._multiTileBatchedEntropyEnabled = prevBatched
            DecoderPipeline._gpuHTEntropyEnabled = prevHT
            DecoderPipeline._gpuInverse53Enabled = prevInv
        }
        DecoderPipeline._multiTileBatchedEntropyEnabled = false
        DecoderPipeline._gpuHTEntropyEnabled = false
        DecoderPipeline._gpuInverse53Enabled = false

        let cfg = htConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        struct Row {
            let label: String
            let pixels: Int
            let mel: UInt64
            let vlcLookup: UInt64
            let uvlc: UInt64
            let magsgn: UInt64
            let avgMagsgnBits: Double
            let quadSamples: UInt64
            let rowTotalMs: Double
            let totalDecodeMs: Double
        }
        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let codestream = try await encoder.encode(image)

            // Warmup.
            _ = try await decoder.decode(codestream)

            // Measured decode.
            J2KHTEntropyProfile.reset()
            let t0 = Date().timeIntervalSinceReferenceDate
            _ = try await decoder.decode(codestream)
            let totalMs = (Date().timeIntervalSinceReferenceDate - t0) * 1000

            let s = J2KHTEntropyProfile.snapshot()
            rows.append(Row(
                label: fix.label,
                pixels: image.width * image.height,
                mel: s.melCallCount,
                vlcLookup: s.vlcLookupCount,
                uvlc: s.uvlcCount,
                magsgn: s.magsgnReadBitsCount,
                avgMagsgnBits: s.avgMagsgnBitsPerCall,
                quadSamples: s.quadSamplesCallCount,
                rowTotalMs: s.rowDecodeTotalMs,
                totalDecodeMs: totalMs))
        }

        XCTAssertFalse(rows.isEmpty)
        print("=== v7.3.0 Phase 0 — HT entropy engine call breakdown ===")
        print()
        print("| Fixture | px | total ms | row ms | mel calls | vlcLookup | uvlc | magsgn read | avg-bits | readQuadSamples |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %.2f | %.2f | %llu | %llu | %llu | %llu | %.2f | %llu |",
                r.label, r.pixels,
                r.totalDecodeMs, r.rowTotalMs,
                r.mel, r.vlcLookup, r.uvlc, r.magsgn, r.avgMagsgnBits, r.quadSamples))
        }
        print()
        print("Read: per-engine call counts. The DX row drives v7.3 SIMD targeting —")
        print("the engine with the highest count is the highest-leverage hot loop.")
        print("`row ms` is the wall-time inside `decodeInitialRow` + `decodeSubsequentRow`")
        print("summed across all tiles; `total ms` is the full pipeline wall.")
        print("`avg-bits` is the average per-MagSgn-read width; if it's ~3, MagSgn reads")
        print("are short variable-length operations (NEON-hostile); if ~10+, they're")
        print("longer reads that vectorise more easily.")
    }
}
