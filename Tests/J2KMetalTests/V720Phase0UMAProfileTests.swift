// V720Phase0UMAProfileTests.swift
//
// v7.2.0 Phase 0 — UMA boundary baseline. Snapshots
// `J2KMetalUMACounters` pre/post each medical-corpus encode and decode
// to surface:
//
//   - memcpyCount  — readback boundaries crossed per encode/decode
//   - bufferContentsAccessCount — `MTLBuffer.contents()` reads (the
//                                same boundaries; included for
//                                cross-check)
//   - makeBufferCount — `MTLDevice.makeBuffer` allocations not served
//                       by the v5.11 MTLHeap pool (warm pool target: 0)
//
// Output is a markdown table the v7.2 plan can use to (a) confirm
// the UMA wedge magnitude, and (b) measure each subsequent Phase A
// sub-PR's success criterion ("memcpyCount == 0 for the boundary
// just eliminated").
//
// Per-decode "memcpy bytes" estimate is computed at the test level
// from the per-boundary stride/sample-count info embedded in the
// existing increment call sites. We don't have a global byte-counter
// today; if Phase A needs precise byte attribution we'll add one.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V720Phase0UMAProfileTests: XCTestCase {

    private struct CorpusFixture {
        let label: String
        let filename: String
    }

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "MR-small 180²",  filename: "mr_study_002_instance_000100.pgm"),
        CorpusFixture(label: "CT 512²",        filename: "ct_study_001_instance_000001.pgm"),
        CorpusFixture(label: "MR 886²",        filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",       filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316",   filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288",   filename: "dx_study_002_instance_000001.pgm"),
    ]

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
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Per-fixture UMA counter capture across one warm encode and one
    /// warm decode. Does not assert specific counts — purpose is to
    /// emit a table the v7.2 plan can quote.
    func testUMABaseline_LosslessCorpus_v720Phase0() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        // Pre-warm so the first-decode allocation pulse doesn't get
        // attributed to fixture #1's totals.
        try await J2KMetalSession.processShared.preWarm()

        let cfg = htConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        struct Row {
            let label: String
            let pixels: Int
            let codestreamBytes: Int
            let encMemcpy: Int
            let encContents: Int
            let encMakeBuffer: Int
            let decMemcpy: Int
            let decContents: Int
            let decMakeBuffer: Int
        }
        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }

            // Warmup: one encode + one decode, counters reset.
            let warmCs = try await encoder.encode(image)
            _ = try await decoder.decode(warmCs)

            // Encode counters (single warm run).
            J2KMetalUMACounters.reset()
            let codestream = try await encoder.encode(image)
            let encSnap = J2KMetalUMACounters.snapshot()

            // Decode counters (single warm run).
            J2KMetalUMACounters.reset()
            _ = try await decoder.decode(codestream)
            let decSnap = J2KMetalUMACounters.snapshot()

            rows.append(Row(
                label: fix.label,
                pixels: image.width * image.height,
                codestreamBytes: codestream.count,
                encMemcpy: encSnap.memcpyCount,
                encContents: encSnap.bufferContentsAccessCount,
                encMakeBuffer: encSnap.makeBufferCount,
                decMemcpy: decSnap.memcpyCount,
                decContents: decSnap.bufferContentsAccessCount,
                decMakeBuffer: decSnap.makeBufferCount))
        }

        XCTAssertFalse(rows.isEmpty, "No corpus fixtures resolved — fixture path layout changed?")

        print("=== v7.2.0 Phase 0 — UMA counter baseline (warm session, single-run per fixture) ===")
        print()
        print("| Fixture | px | bytes | enc memcpy | enc contents | enc makeBuf | dec memcpy | dec contents | dec makeBuf |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %d | %d | %d | %d | %d | %d | %d |",
                r.label, r.pixels, r.codestreamBytes,
                r.encMemcpy, r.encContents, r.encMakeBuffer,
                r.decMemcpy, r.decContents, r.decMakeBuffer))
        }

        print()
        print("Reading the table:")
        print("  - memcpy + contents are paired at every readback site (HTMagSgn,")
        print("    HTCleanup×2, DWT). Identical counts → instrumentation consistent.")
        print("  - makeBuf > 0 on a warm session means the MTLHeap pool didn't have")
        print("    a bucket for that allocation. v5.11's expectation is single-digit;")
        print("    v7.2 Phase B target: 0.")
        print("  - Each `dec memcpy` boundary on DX 6.41 MP corresponds to a buffer")
        print("    of up to (samples × 4 B) per readback. For 4x4 multi-tile DX")
        print("    (16 tiles × ~400 K px/tile × 4 B), the entire decode could memcpy")
        print("    25-100 MB of data that UMA elimination would save.")
    }
}
