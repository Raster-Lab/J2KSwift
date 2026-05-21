// PreprocessSubstageProfileTests.swift
//
// v6.3.0 F3 — diagnostic that prints the per-sub-stage breakdown
// of the encoder preprocessing stage's wall-time, using the new
// `J2KPreprocessSubstageTimings` accumulators. Mirror of F1's
// `CodestreamMarkerSubstageProfileTests` (PR #324) for the
// preprocess stage.
//
// Why this lands as a separate phase from any optimization
//
//   docs/V6_3_0_PLAN.md F3 cited preprocess as ~4.8 % of DX
//   encode wall (2.91 ms in v6.1.0, 2.44 ms in v6.2.0). v5.38 M7
//   already specialised the 16-bit loop into 4 branchless bodies
//   to let LLVM auto-vectorise. The plan's question is: does
//   explicit vDSP / NEON intrinsics help, or has LLVM already
//   captured the win?
//
//   Before swinging, F3 gets *data*: which sub-stage actually
//   owns the preprocess wall? `imageValidate`, `extractComponentData`,
//   or `dcLevelShift`?
//
//   The output of this test is the input to the F3 decision: ship
//   a Phase 1 optimization or close the arc with no further work.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class PreprocessSubstageProfileTests: XCTestCase {

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

    /// Sanity test — `J2KPreprocessSubstageTimings` reset clears every
    /// counter so back-to-back tests don't see each other's data.
    func testPreprocessTimings_ResetClearsEverything() {
        J2KPreprocessSubstageTimings.reset()
        let zero = J2KPreprocessSubstageTimings.snapshot()
        XCTAssertEqual(zero.imageValidate, 0)
        XCTAssertEqual(zero.extractComponentData8, 0)
        XCTAssertEqual(zero.extractComponentData16, 0)
        XCTAssertEqual(zero.dcLevelShift, 0)
        XCTAssertEqual(zero.encodeCount, 0)
        XCTAssertEqual(zero.pixelsProcessed, 0)
    }

    /// Diagnostic — per-sub-stage breakdown across the corpus.
    /// Median of 5 release-mode encodes per fixture. The output is
    /// the input to the F3 decision (ship Phase 1 or close arc).
    func testPreprocess_SubstageBreakdown_AcrossCorpus() async throws {
        #if DEBUG
        print("⚠️  Sub-stage breakdown in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter PreprocessSubstageProfileTests/testPreprocess_SubstageBreakdown_AcrossCorpus")
        #endif

        print("=== v6.3.0 F3 — preprocess sub-stage breakdown ===")
        print("(All sub-stage ms are CUMULATIVE across one full encode.")
        print(" `total` is the sum of all sub-stages; subtract from")
        print(" `encode ms` to get the non-preprocess wall time.)")
        print()
        print("| fixture | encode ms | validate | extract8 | extract16 | dcShift | total | total% wall | px |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|---:|")

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let encoder = J2KEncoder(encodingConfiguration: htConfig())

            // Warm-up.
            _ = try await encoder.encode(image)

            // Median of 5 — capture the timings on each run.
            let n = 5
            var encodeMs: [Double] = []
            var snaps: [J2KPreprocessSubstageTimings.Snapshot] = []
            for _ in 0..<n {
                J2KPreprocessSubstageTimings.reset()
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encoder.encode(image)
                encodeMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                snaps.append(J2KPreprocessSubstageTimings.snapshot())
            }

            // Pick the median run by encode time.
            let sortedIdx = (0..<n).sorted { encodeMs[$0] < encodeMs[$1] }
            let med = sortedIdx[n / 2]
            let s = snaps[med]
            let totalPct = encodeMs[med] > 0 ? (s.total * 1000.0 / encodeMs[med]) * 100.0 : 0
            print(String(format: "| %@ | %6.2f | %6.4f | %6.4f | %6.4f | %6.4f | %6.4f | %5.2f%% | %d |",
                fix.label,
                encodeMs[med],
                s.imageValidate * 1000.0,
                s.extractComponentData8 * 1000.0,
                s.extractComponentData16 * 1000.0,
                s.dcLevelShift * 1000.0,
                s.total * 1000.0,
                totalPct,
                s.pixelsProcessed))
        }

        print()
        print("Reading the table:")
        print("  - `validate`     — `image.validate()` cost (config + dimensions check)")
        print("  - `extract8`     — extractComponentData 8-bit branch (sign-cast loop)")
        print("  - `extract16`    — extractComponentData 16-bit branch (4 specialised")
        print("                     UInt16 → Int32 loops, branchless after v5.38 M7)")
        print("  - `dcShift`      — per-component `&-= dcOffset` in-place loop")
        print("  - `total`        — sum (approximates preprocess wall within ~1-2%)")
        print("  - `total% wall`  — total preprocess as % of encode wall")
        print()
        print("Decision rule: if `extract16` is the dominant sub-stage and `total`")
        print("is > 5 % of encode wall on DX, an explicit vDSP / NEON-intrinsics")
        print("rewrite of the 16-bit branch is warranted. Otherwise, LLVM has")
        print("already captured the win and the F3 arc can close.")
    }
}
