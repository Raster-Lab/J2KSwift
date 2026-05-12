// CodestreamMarkerSubstageProfileTests.swift
//
// v6.3.0 F1 — diagnostic that prints the per-marker breakdown of
// the codestream-generation stage's wall-time, using the new
// `J2KCodestreamMarkerTimings` accumulators. Mirror of
// `Tier2WritePacketSubstageProfileTests` (PR #308) for the
// non-`writePacket` portion of the codestream stage.
//
// Why this lands as a separate phase from any optimization
//
//   PR #308 measured `writePacket` at 2.5 % of DX wall — 0.22 ms
//   of "bit-write level work" inside writePacket, dominated by
//   `rawDataAppend` at 80 %. The codestream stage as a whole
//   (per the v6.2.0 measurement in `docs/V6_3_0_PLAN.md`) is
//   ~5.5 ms / 8 % of DX wall, so ~3.7 ms / 5.5 % is in the
//   non-`writePacket` markers (SOC / SIZ / CAP / CPF / COD / QCD
//   / COM / SOT / SOD / tile-data-append / EOC).
//
//   Before swinging at any of those markers, this PR gets *data*:
//   which marker actually owns the remaining codestream-stage wall?
//
//   The output of this test is the input to the next perf PR (or
//   the gate that says no further optimization in this stage is
//   warranted).

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class CodestreamMarkerSubstageProfileTests: XCTestCase {

    // v9.9 — these tests verify `J2KCodestreamMarkerTimings` fires
    // from the single-tile codestream-assembly path
    // (`generateCodestreamWithIndex`). v7.0.0 flipped the planner
    // default from `.single` to `.auto`, so MR 886² (the fixture
    // used here) now routes through `J2KMultiTileEncoder` which has
    // a separate codestream assembler that doesn't call
    // `J2KCodestreamMarkerTimings.recordEncodeCall()`. Pin to
    // `.single` to restore the assertion's pre-conditions.
    private var _savedEnvMode: J2KHTTileMode!

    override func setUp() {
        super.setUp()
        _savedEnvMode = J2KEncodeTilePlanner.envMode
        J2KEncodeTilePlanner.envMode = .single
    }

    override func tearDown() {
        J2KEncodeTilePlanner.envMode = _savedEnvMode
        super.tearDown()
    }

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

    private func htConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    /// Sanity test — `J2KCodestreamMarkerTimings` reset clears every
    /// counter so back-to-back tests don't see each other's data.
    func testCodestreamMarkerTimings_ResetClearsEverything() {
        J2KCodestreamMarkerTimings.reset()
        let zero = J2KCodestreamMarkerTimings.snapshot()
        XCTAssertEqual(zero.soc, 0)
        XCTAssertEqual(zero.siz, 0)
        XCTAssertEqual(zero.cap, 0)
        XCTAssertEqual(zero.cpf, 0)
        XCTAssertEqual(zero.cod, 0)
        XCTAssertEqual(zero.qcd, 0)
        XCTAssertEqual(zero.com, 0)
        XCTAssertEqual(zero.sot, 0)
        XCTAssertEqual(zero.sod, 0)
        XCTAssertEqual(zero.tileDataAppend, 0)
        XCTAssertEqual(zero.eoc, 0)
        XCTAssertEqual(zero.encodeCount, 0)
        XCTAssertEqual(zero.tileDataBytes, 0)
    }

    /// One encode of MR 886² populates the structural counters. The
    /// per-marker `TimeInterval` accumulators are intentionally NOT
    /// asserted > 0 here: in release mode, individual marker writes
    /// (SOC / SOD / EOC are 2 bytes; SIZ / COD / etc. are tens of
    /// bytes) routinely complete in under a microsecond, which is
    /// at or below `CFAbsoluteTimeGetCurrent()`'s practical
    /// resolution. They show as exactly `0.0` per single encode and
    /// only become measurable cumulatively across many encodes — see
    /// the corpus breakdown test below for the production timings.
    /// The structural counters (`encodeCount`, `tileDataBytes`) are
    /// the always-non-zero contract.
    func testCodestreamMarkerTimings_PopulatedAfterSingleEncode() async throws {
        guard let image = loadPGM16("mr_study_001_instance_000001.pgm") else {
            throw XCTSkip("MR 886² fixture not present")
        }
        J2KCodestreamMarkerTimings.reset()
        _ = try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)
        let snap = J2KCodestreamMarkerTimings.snapshot()

        XCTAssertEqual(snap.encodeCount, 1, "encodeCount should fire exactly once")
        XCTAssertGreaterThan(snap.tileDataBytes, 0,
            "tile data byte count should be non-zero on a real encode")
        // Per-marker timings: lower bound only (must not be negative
        // / NaN). The breakdown test below validates measurable
        // values on the larger fixtures.
        XCTAssertGreaterThanOrEqual(snap.soc, 0)
        XCTAssertGreaterThanOrEqual(snap.siz, 0)
        XCTAssertGreaterThanOrEqual(snap.cap, 0)
        XCTAssertGreaterThanOrEqual(snap.cpf, 0)
        XCTAssertGreaterThanOrEqual(snap.cod, 0)
        XCTAssertGreaterThanOrEqual(snap.qcd, 0)
        XCTAssertGreaterThanOrEqual(snap.com, 0)
        XCTAssertGreaterThanOrEqual(snap.sot, 0)
        XCTAssertGreaterThanOrEqual(snap.sod, 0)
        XCTAssertGreaterThanOrEqual(snap.tileDataAppend, 0)
        XCTAssertGreaterThanOrEqual(snap.eoc, 0)
    }

    /// Diagnostic — per-marker breakdown across the corpus. Median
    /// of 3 release-mode encodes per fixture. The output is the
    /// input to the next perf PR; the largest column tells us where
    /// to swing (or whether there's nothing left to swing at).
    func testCodestreamMarkers_SubstageBreakdown_AcrossCorpus() async throws {
        #if DEBUG
        print("⚠️  Sub-stage breakdown in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter CodestreamMarkerSubstageProfileTests/testCodestreamMarkers_SubstageBreakdown_AcrossCorpus")
        #endif

        print("=== v6.3.0 F1 — codestream marker breakdown ===")
        print("(All marker ms are CUMULATIVE across one full encode.")
        print(" 'total' is the sum of all markers + tile-data-append;")
        print(" subtract from 'encode ms' to get the non-codestream-stage")
        print(" wall time. 'tier-2 ms' is the writePacket sub-stage from")
        print(" PR #308 measured separately — it covers the per-packet")
        print(" tag-tree + length-signaling work that this PR does NOT")
        print(" double-count.)")
        print()
        print("| fixture | encode ms | soc | siz | cap | cpf | cod | qcd | com | sot | sod | tileData | eoc | total | tier-2 ms |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let encoder = J2KEncoder(encodingConfiguration: htConfig())

            // Warm-up.
            _ = try await encoder.encode(image)

            // Median of 3 — capture the timings on each run.
            var encodeMs: [Double] = []
            var snaps: [J2KCodestreamMarkerTimings.Snapshot] = []
            var tier2Snaps: [J2KTier2Timings.Snapshot] = []
            for _ in 0..<3 {
                J2KCodestreamMarkerTimings.reset()
                J2KTier2Timings.reset()
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encoder.encode(image)
                encodeMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                snaps.append(J2KCodestreamMarkerTimings.snapshot())
                tier2Snaps.append(J2KTier2Timings.snapshot())
            }

            // Pick the median run (middle index after sort by encode time).
            let sortedIdx = (0..<3).sorted { encodeMs[$0] < encodeMs[$1] }
            let med = sortedIdx[1]
            let s = snaps[med]
            let t2 = tier2Snaps[med]
            print(String(format: "| %@ | %6.2f | %5.3f | %5.3f | %5.3f | %5.3f | %5.3f | %5.3f | %5.3f | %5.3f | %5.3f | %6.3f | %5.3f | %5.3f | %5.3f |",
                fix.label,
                encodeMs[med],
                s.soc * 1000.0,
                s.siz * 1000.0,
                s.cap * 1000.0,
                s.cpf * 1000.0,
                s.cod * 1000.0,
                s.qcd * 1000.0,
                s.com * 1000.0,
                s.sot * 1000.0,
                s.sod * 1000.0,
                s.tileDataAppend * 1000.0,
                s.eoc * 1000.0,
                s.total * 1000.0,
                t2.total * 1000.0))
        }

        print()
        print("Reading the table:")
        print("  - `soc / sod / eoc`  — bare 2-byte marker writes (no segment)")
        print("  - `siz / cod / qcd / sot` — fixed-form segment writes (always present)")
        print("  - `cap / cpf / com`  — HTJ2K-only segments (Part 15)")
        print("  - `tileData`          — `writer.writeBytes(tileData)` of the")
        print("                          assembled tile bitstream payload")
        print("  - `total`             — sum of all marker / append accumulators")
        print("                          (codestream stage minus tier-2 packet writes)")
        print("  - `tier-2 ms`         — writePacket sum from PR #308 (separate;")
        print("                          NOT double-counted in `total`)")
        print()
        print("v6.2.0 baseline (per docs/V6_3_0_PLAN.md): codestream stage")
        print("was ~5.5 ms / 8 % of DX wall; tier-2 was 1.80 ms / 2.5 %.")
        print("This PR's `total + tier-2 ms` should match the ~5.5 ms total")
        print("on DX (within noise).")
        print()
        print("Decision rule: if `tileData` dominates `total` and total is")
        print("a small fraction of encode wall, no marker-write optimization")
        print("is worth pursuing — the bytes are already a memcpy.")
    }
}
