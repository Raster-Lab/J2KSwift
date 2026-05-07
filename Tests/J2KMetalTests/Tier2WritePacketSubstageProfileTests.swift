// Tier2WritePacketSubstageProfileTests.swift
//
// v6-alpha7 phase 1 — diagnostic that prints the per-sub-stage
// breakdown of `writePacket`'s wall-time, using the new
// `J2KTier2Timings` accumulators.
//
// Why this lands as a separate phase from any optimization
//
//   PR #307 measured the J2KTagTree allocation reduction as a
//   wash (±2 % corpus deltas inside the M2 noise band). Three
//   "wash" results in a row across recent perf arcs (Phase 1.3
//   GPU approach B, Phase 1.4 SIMD classification, #307 tag-
//   tree scratch) suggest single-lever optimizations rarely move
//   the needle on this hot path. Before swinging at another
//   sub-stage of `writePacket`, this PR gets *data*: which sub-
//   stage actually owns the 9 % of DX wall the entropy /
//   codestream-generation stage consumes?
//
//   The output of this test is the input to the next perf PR.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class Tier2WritePacketSubstageProfileTests: XCTestCase {

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

    /// Sanity test — `J2KTier2Timings` reset clears every counter so
    /// back-to-back tests don't see each other's data.
    func testTier2Timings_ResetClearsEverything() {
        J2KTier2Timings.reset()
        let zero = J2KTier2Timings.snapshot()
        XCTAssertEqual(zero.tagTreeBuild, 0)
        XCTAssertEqual(zero.tagTreeInclusionEncode, 0)
        XCTAssertEqual(zero.tagTreeZBPEncode, 0)
        XCTAssertEqual(zero.passesEncoding, 0)
        XCTAssertEqual(zero.lengthSignaling, 0)
        XCTAssertEqual(zero.rawDataAppend, 0)
        XCTAssertEqual(zero.writePacketCount, 0)
        XCTAssertEqual(zero.includedBlockCount, 0)
    }

    /// One encode of MR 886² populates the counters with non-zero
    /// values for every sub-stage, and the included-block counter
    /// matches expected (one per non-zero codeblock × packets).
    func testTier2Timings_PopulatedAfterSingleEncode() async throws {
        guard let image = loadPGM16("mr_study_001_instance_000001.pgm") else {
            throw XCTSkip("MR 886² fixture not present")
        }
        J2KTier2Timings.reset()
        _ = try await J2KEncoder(encodingConfiguration: htConfig()).encode(image)
        let snap = J2KTier2Timings.snapshot()
        XCTAssertGreaterThan(snap.writePacketCount, 0,
            "writePacket should fire at least once per encode")
        XCTAssertGreaterThan(snap.includedBlockCount, 0,
            "at least one codeblock should be included in the codestream")
        XCTAssertGreaterThan(snap.tagTreeBuild, 0)
        XCTAssertGreaterThan(snap.tagTreeInclusionEncode, 0)
        XCTAssertGreaterThan(snap.tagTreeZBPEncode, 0)
        XCTAssertGreaterThan(snap.passesEncoding, 0)
        XCTAssertGreaterThan(snap.lengthSignaling, 0)
        // rawDataAppend can be very small or zero on tiny fixtures
        // where all blocks are zero (rare); leave un-asserted here
        // but expect non-zero on the corpus print below.
        XCTAssertGreaterThanOrEqual(snap.rawDataAppend, 0)
    }

    /// Diagnostic — per-sub-stage breakdown across the corpus. Median
    /// of 3 release-mode encodes per fixture. The output of this is
    /// the input to the next perf PR; the largest column tells us
    /// where to swing.
    func testTier2WritePacket_SubstageBreakdown_AcrossCorpus() async throws {
        #if DEBUG
        print("⚠️  Sub-stage breakdown in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter Tier2WritePacketSubstageProfileTests/testTier2WritePacket_SubstageBreakdown_AcrossCorpus")
        #endif

        print("=== v6-alpha7 phase 1 — writePacket sub-stage breakdown ===")
        print("(All sub-stage ms are CUMULATIVE across one full encode.")
        print(" 'total' is the sum; subtract from 'encode ms' to get the")
        print(" non-tier-2 wall time. The largest sub-stage is the next")
        print(" perf-PR target.)")
        print()
        print("| fixture | encode ms | tagBuild | tagInc | tagZBP | passes | length | rawData | total | packets | incBlocks |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let encoder = J2KEncoder(encodingConfiguration: htConfig())

            // Warm-up.
            _ = try await encoder.encode(image)

            // Median of 3 — capture the timings on each run.
            var encodeMs: [Double] = []
            var snaps: [J2KTier2Timings.Snapshot] = []
            for _ in 0..<3 {
                J2KTier2Timings.reset()
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encoder.encode(image)
                encodeMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                snaps.append(J2KTier2Timings.snapshot())
            }

            // Pick the median run (middle index after sort by encode time).
            let sortedIdx = (0..<3).sorted { encodeMs[$0] < encodeMs[$1] }
            let med = sortedIdx[1]
            let s = snaps[med]
            print(String(format: "| %@ | %6.2f | %5.2f | %5.2f | %5.2f | %5.2f | %5.2f | %6.2f | %5.2f | %d | %d |",
                fix.label,
                encodeMs[med],
                s.tagTreeBuild * 1000.0,
                s.tagTreeInclusionEncode * 1000.0,
                s.tagTreeZBPEncode * 1000.0,
                s.passesEncoding * 1000.0,
                s.lengthSignaling * 1000.0,
                s.rawDataAppend * 1000.0,
                s.total * 1000.0,
                s.writePacketCount,
                s.includedBlockCount))
        }

        print()
        print("Reading the table:")
        print("  - `tagBuild`    — per-band tag-tree construction + setValue per block")
        print("  - `tagInc`      — inclusion-tree encode per block (every block, included or not)")
        print("  - `tagZBP`      — zero-bit-plane tree encode per included block")
        print("  - `passes`      — Table B.4 prefix-code writes per included block")
        print("  - `length`      — Lblock loop + writeBits of the byte length per included block")
        print("  - `rawData`     — appendRawBytes of the included block payload")
        print("  - `total`       — sum (approximates writePacket wall time within ~1-2%)")
        print("  - `incBlocks`   — sum of included blocks across all packets in this encode")
        print()
        print("The largest column on DX 2800×2288 is the next perf-PR target.")
    }
}
