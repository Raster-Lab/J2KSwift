// V91Phase0EncoderProfileTests.swift
//
// v9.1 Path B Phase 0 — encoder-side per-engine call breakdown probe.
//
// Runs a warm encode of each medical-corpus fixture, snapshots the
// `J2KHTEntropyEncoderProfile` counters, and prints a per-engine
// breakdown along with the per-block coarse wall slices (total /
// classify / finish).
//
// Combined with the per-engine microbench (`V91Phase0EncoderMicrobench`),
// the per-stage CPU contribution is `count × avg-cost-per-call`.
//
// Output answers: of the 57 % of encode CPU that v8.4 attributed to
// HT entropy on DX 2800×2288 (~353 ms accumulated), which sub-stage
// (processQuad classification, VLC tuple emit, UVLC emit, MEL emit,
// MagSgn emit, finish) takes the largest share? That sub-stage is
// the highest-leverage Phase 1 target.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V91Phase0EncoderProfileTests: XCTestCase {

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

    /// Per-fixture encoder engine breakdown for one encode (post-warmup).
    func testEntropyEncoderBreakdown_LosslessCorpus() async throws {
        let cfg = htConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        struct Row {
            let label: String
            let pixels: Int
            let blocks: UInt64
            let processQuad: UInt64
            let vlcTuple: UInt64       // total - UVLC = quad-tuple emits
            let vlcUVLC: UInt64
            let melEvents: UInt64
            let magsgnCalls: UInt64
            let avgMagsgnBits: Double
            let blockTotalMs: Double
            let classifyMs: Double
            let finishMs: Double
            let totalEncodeMs: Double
        }
        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warmup.
            _ = try await encoder.encode(image)

            // Measured encode.
            J2KHTEntropyEncoderProfile.reset()
            let t0 = Date().timeIntervalSinceReferenceDate
            _ = try await encoder.encode(image)
            let totalMs = (Date().timeIntervalSinceReferenceDate - t0) * 1000

            let s = J2KHTEntropyEncoderProfile.snapshot()
            let totalVlc = s.vlcEncodeCallCount
            let uvlc = s.vlcUVLCEncodeCallCount
            let tuple = totalVlc > uvlc ? totalVlc - uvlc : 0
            rows.append(Row(
                label: fix.label,
                pixels: image.width * image.height,
                blocks: s.blockCount,
                processQuad: s.processQuadCallCount,
                vlcTuple: tuple,
                vlcUVLC: uvlc,
                melEvents: s.melEncodeCallCount,
                magsgnCalls: s.magsgnEncodeCallCount,
                avgMagsgnBits: s.avgMagsgnBitsPerCall,
                blockTotalMs: s.blockTotalMs,
                classifyMs: s.blockClassifyMs,
                finishMs: s.blockFinishMs,
                totalEncodeMs: totalMs))
        }

        XCTAssertFalse(rows.isEmpty)
        print("=== v9.1 Path B Phase 0 — HT encoder per-engine call breakdown ===")
        print()
        print("| Fixture | px | blocks | processQuad | vlcTuple | vlcUVLC | mel | magsgn | avg-bits |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %llu | %llu | %llu | %llu | %llu | %llu | %.2f |",
                r.label, r.pixels, r.blocks,
                r.processQuad, r.vlcTuple, r.vlcUVLC,
                r.melEvents, r.magsgnCalls, r.avgMagsgnBits))
        }
        print()
        print("=== Per-block coarse wall slices (sum of clock_gettime_nsec_np pairs) ===")
        print()
        print("| Fixture | total ms | classify ms | finish ms | encode wall ms |")
        print("|---|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %.2f | %.2f | %.2f | %.2f |",
                r.label, r.blockTotalMs, r.classifyMs, r.finishMs, r.totalEncodeMs))
        }
        print()
        print("Notes:")
        print("  - `blockTotalMs` = sum across all blocks of wall time inside")
        print("    `HTBlockEncoderConformant.encode()`. This excludes upstream")
        print("    DWT, MCT, scratch alloc, codestream emitter assembly.")
        print("  - `classifyMs` = time inside the row-quad processing loop.")
        print("  - `finishMs` = time inside magsgn/mel/vlc.finish() (flush partial")
        print("    bytes + reverse VLC buffer).")
        print("  - `encode wall ms` = full pipeline encode wall (DWT + entropy + asm).")
        print("  - Combined with `V91Phase0EncoderMicrobench` (per-engine ns/call),")
        print("    we compute `per_stage_cpu = count × ns/call` to identify the")
        print("    highest-leverage sub-stage to redesign in Phase 1.")
    }
}
