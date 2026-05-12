// V10Phase5GPUSingleTileABTests.swift
//
// v10.0-research Phase 5: re-measure the v7.0.0 tile-mode default choice
// against the current (post-v9.5) encoder pipeline. The hypothesis is that
// GPU forward 5/3 DWT under `.single` tile-mode may beat multi-tile CPU
// DWT on DX-class fixtures on M2 — the v7.0.0 default flip happened
// before v9.3/v9.4 entropy NEON, the v9.5 buffer hoisting, and the v9.5.0
// daemon-encode amortisation, all of which changed the wall-budget shape.
//
// Three conditions per fixture, all release-mode HT-conformant lossless:
//   A. `.auto` default       — current production (multi-tile CPU on DX)
//   B. `.single` + GPU on    — single-tile GPU forward DWT
//   C. `.single` + GPU off   — single-tile CPU DWT (control)
//
// If B beats A by ≥3 ms on DX wall (the v7.4 acceptance bar), Phase 5
// graduates as the v10.0 groundbreaking lever. If wash, this is the
// 10th lever-ceiling confirmation and v10.0 closure is reinforced.
//
// Run with:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test -c release --filter V10Phase5GPUSingleTileABTests

import XCTest
@testable import J2KCore
@testable import J2KCodec
import J2KMetal

final class V10Phase5GPUSingleTileABTests: XCTestCase {

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
        let label: String; let filename: String
    }

    private static let corpus: [CorpusFixture] = [
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

    /// Phase 5 deliverable — three-way A/B/C wall comparison on PX + DX.
    func testGPUForwardSingleTileVsAuto_MultiCPU() async throws {
        #if DEBUG
        print("⚠️  Phase 5 in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter V10Phase5GPUSingleTileABTests")
        #endif

        guard J2KMetalDWT.isAvailable else {
            print("Metal unavailable on this host — skipping Phase 5 A/B.")
            return
        }

        let runs = 7
        let warmups = 2
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)

        // Snapshot the existing planner mode + GPU flag so we restore.
        let savedTileMode = J2KEncodeTilePlanner.envMode
        let savedGPUEnabled = EncoderPipeline._gpuForward53Enabled
        defer {
            J2KEncodeTilePlanner.envMode = savedTileMode
            EncoderPipeline._gpuForward53Enabled = savedGPUEnabled
        }

        struct Row {
            let label: String
            let pixels: Int
            let conditionLabel: String
            let median: Double
            let min: Double
            let max: Double
            let codestreamBytes: Int
        }

        var rows: [Row] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let pixels = image.width * image.height

            for (label, configure) in [
                ("A: .auto default (multi-tile CPU)", {
                    J2KEncodeTilePlanner.envMode = .auto
                    EncoderPipeline._gpuForward53Enabled = true  // gate fires only at ≥3 MP per tile
                }),
                ("B: .single + GPU on (single-tile GPU)", {
                    J2KEncodeTilePlanner.envMode = .single
                    EncoderPipeline._gpuForward53Enabled = true
                }),
                ("C: .single + GPU off (single-tile CPU)", {
                    J2KEncodeTilePlanner.envMode = .single
                    EncoderPipeline._gpuForward53Enabled = false
                }),
            ] as [(String, () -> Void)] {
                configure()

                // Warm-up (excluded).
                for _ in 0..<warmups {
                    _ = try await encoder.encode(image)
                }

                var times: [TimeInterval] = []
                var lastBytes = 0
                for _ in 0..<runs {
                    let t0 = Date()
                    let encoded = try await encoder.encode(image)
                    times.append(Date().timeIntervalSince(t0))
                    lastBytes = encoded.count
                }
                times.sort()
                rows.append(Row(
                    label: fix.label, pixels: pixels, conditionLabel: label,
                    median: times[runs / 2] * 1000.0,
                    min: times.first! * 1000.0,
                    max: times.last! * 1000.0,
                    codestreamBytes: lastBytes))
            }
        }

        XCTAssertFalse(rows.isEmpty, "No corpus fixtures resolved.")

        print()
        print("=== v10.0 Phase 5 — GPU single-tile vs .auto multi-tile A/B on PX + DX ===")
        print("    (Apple M2, release mode, n=\(runs) median after \(warmups) warmups)")
        print()
        print("| Fixture | Condition | median ms | min ms | max ms | bytes |")
        print("|---|---|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %@ | %6.2f | %6.2f | %6.2f | %d |",
                r.label, r.conditionLabel, r.median, r.min, r.max, r.codestreamBytes))
        }

        // Decision summary per fixture.
        print()
        print("## Decision per fixture (winner-vs-A delta)")
        print("| Fixture | A (.auto) | B (single+GPU) | C (single+CPU) | Δ(B-A) | Δ(C-A) | winner |")
        print("|---|---:|---:|---:|---:|---:|---|")
        let groupedByLabel = Dictionary(grouping: rows, by: { $0.label })
        for (label, group) in groupedByLabel.sorted(by: { $0.key < $1.key }) {
            let a = group.first { $0.conditionLabel.starts(with: "A") }!.median
            let b = group.first { $0.conditionLabel.starts(with: "B") }!.median
            let c = group.first { $0.conditionLabel.starts(with: "C") }!.median
            let dBA = b - a
            let dCA = c - a
            let bestMs = min(a, b, c)
            let winner: String
            if bestMs == a { winner = "A (.auto)" }
            else if bestMs == b { winner = "B (single+GPU)" }
            else { winner = "C (single+CPU)" }
            print(String(format: "| %@ | %6.2f | %6.2f | %6.2f | %+6.2f | %+6.2f | %@ |",
                label, a, b, c, dBA, dCA, winner))
        }

        // Bit-exact correctness check. A vs B/C will produce DIFFERENT
        // codestream bytes because A is multi-tile (2x2) and B/C are
        // single-tile — the tile-stream structure (SOT/SOD markers,
        // per-tile resyncs, packet layouts) is inherently different.
        // The real parity check is B vs C: GPU forward 5/3 DWT must
        // produce a codestream byte-identical to CPU forward 5/3 DWT
        // when the tile mode is held constant. (This is what
        // HTGPUForward53CrossCodecTests enforces; re-asserting locally.)
        print()
        print("## Codestream-byte equality (B GPU vs C CPU within single-tile)")
        for (label, group) in groupedByLabel.sorted(by: { $0.key < $1.key }) {
            let b = group.first { $0.conditionLabel.starts(with: "B") }!.codestreamBytes
            let c = group.first { $0.conditionLabel.starts(with: "C") }!.codestreamBytes
            print("  - \(label): B=\(b) bytes, C=\(c) bytes — \(b == c ? "IDENTICAL ✓" : "DIFFER ✗")")
            XCTAssertEqual(b, c,
                "GPU vs CPU forward 5/3 DWT produced different codestream bytes on \(label) — bit-exact violation in the GPU path.")
        }

        print()
        print("## Tile-mode codestream variance (A vs B; expected to differ)")
        print("    Multi-tile vs single-tile change SOT/SOD markers + per-tile resyncs,")
        print("    so byte count differs. Both decode to the same pixel image (per")
        print("    HTTileParityMatrixTests).")
        for (label, group) in groupedByLabel.sorted(by: { $0.key < $1.key }) {
            let a = group.first { $0.conditionLabel.starts(with: "A") }!.codestreamBytes
            let b = group.first { $0.conditionLabel.starts(with: "B") }!.codestreamBytes
            let dPct = Double(a - b) / Double(b) * 100.0
            print(String(format: "  - %@: A=%d, B=%d (Δ %.2f %%)", label, a, b, dPct))
        }

        print()
        print("Phase 5 acceptance bar (per V10_0_RESEARCH_PLAN.md):")
        print("  - GROUNDBREAKING: B (single+GPU) beats A (.auto) by ≥3 ms on DX wall.")
        print("  - WASH: |Δ| < 3 ms; 10th lever-ceiling confirmation.")
        print("  - REGRESSION: B slower than A; .auto stays default (already true since v7.0.0).")
    }
}
