// V10Phase9TunableSweepTests.swift
//
// v10.0-research Phase 9: encoder tunable sweep — find pareto-optimal
// (encode wall, output bytes) configurations on the medical corpus.
//
// Default config (since v6.x) is: decompositionLevels=5, codeBlockSize=
// 64×64, LRCP progression, 1 quality layer (lossless). Phase 9 asks:
// are there non-default values that produce smaller bytes WITHOUT
// sacrificing wall, OR accelerate wall WITHOUT growing bytes?
//
// Sweep dimensions:
//   - decompositionLevels ∈ {3, 4, 5, 6}
//   - codeBlockSize ∈ {(32,32), (64,64)}
//
// That's 4 × 2 = 8 combos × 7 medical fixtures = 56 cells, each with
// wall + bytes measured. Pareto front identifies which combos are
// non-dominated (no other combo is faster AND smaller for that
// fixture).
//
// Run with:
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
//     swift test -c release --filter V10Phase9TunableSweepTests

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10Phase9TunableSweepTests: XCTestCase {

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
        let label: String
        let filename: String
    }

    private static let corpus: [CorpusFixture] = [
        CorpusFixture(label: "MR-small 180²",   filename: "mr_study_002_instance_000100.pgm"),
        CorpusFixture(label: "CT 512² (1)",     filename: "ct_study_001_instance_000001.pgm"),
        CorpusFixture(label: "MR 886²",         filename: "mr_study_001_instance_000001.pgm"),
        CorpusFixture(label: "XA 1024²",        filename: "xa_study_001_instance_000001.pgm"),
        CorpusFixture(label: "PX 2459×1316",    filename: "px_study_001_instance_000001.pgm"),
        CorpusFixture(label: "DX 2800×2288",    filename: "dx_study_002_instance_000001.pgm"),
    ]

    private struct Cell {
        let fixture: String
        let levels: Int
        let blockSize: (Int, Int)
        let wallMs: Double
        let bytes: Int
        var bpp: Double { Double(bytes * 8) }  // caller divides by pixels
    }

    private func config(levels: Int, blockSize: (Int, Int)) -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: levels,
            qualityLayers: 1,
            progressionOrder: .lrcp,
            useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.codeBlockSize = blockSize
        return cfg
    }

    /// Phase 9 deliverable — tunable sweep, pareto front per fixture.
    func testTunableSweep_Pareto_M2() async throws {
        #if DEBUG
        print("⚠️  Phase 9 in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter V10Phase9TunableSweepTests")
        #endif

        let levels = [3, 4, 5, 6]
        let blocks: [(Int, Int)] = [(32, 32), (64, 64)]
        let runs = 5
        var cells: [Cell] = []

        for fix in Self.corpus {
            guard let image = loadPGM16(fix.filename) else { continue }
            let pixels = image.width * image.height
            print("[\(fix.label)] pixels=\(pixels)")

            for level in levels {
                for blk in blocks {
                    let cfg = config(levels: level, blockSize: blk)
                    let encoder = J2KEncoder(encodingConfiguration: cfg)
                    // Warm-up
                    let warmBytes: Int
                    do {
                        let d = try await encoder.encode(image)
                        warmBytes = d.count
                    } catch {
                        print("  (skip levels=\(level) block=\(blk.0)×\(blk.1) — \(error))")
                        continue
                    }
                    var times: [TimeInterval] = []
                    var bytes = warmBytes
                    for _ in 0..<runs {
                        let t0 = Date()
                        let d = try await encoder.encode(image)
                        times.append(Date().timeIntervalSince(t0))
                        bytes = d.count
                    }
                    let median = times.sorted()[runs / 2] * 1000.0
                    cells.append(Cell(
                        fixture: fix.label, levels: level, blockSize: blk,
                        wallMs: median, bytes: bytes))
                    let bpp = Double(bytes * 8) / Double(pixels)
                    print(String(format: "  levels=%d block=%d×%d  wall=%7.2f ms  bytes=%9d  bpp=%5.2f",
                        level, blk.0, blk.1, median, bytes, bpp))
                }
            }
        }

        XCTAssertFalse(cells.isEmpty)

        print()
        print("=== v10.0 Phase 9 — encoder tunable sweep, pareto front (M2 release, n=\(runs)) ===")
        print()

        // Per-fixture full table + identify pareto front
        let byFixture = Dictionary(grouping: cells, by: \.fixture)
        for fix in Self.corpus {
            guard let group = byFixture[fix.label] else { continue }
            print("## \(fix.label)")
            print()
            print("| levels | blocksize | wall ms | bytes | bpp | dominated by default? |")
            print("|---:|---|---:|---:|---:|---|")
            // Default = levels=5, block=64×64
            let def = group.first { $0.levels == 5 && $0.blockSize == (64, 64) }
            for c in group.sorted(by: { ($0.levels, $0.blockSize.0) < ($1.levels, $1.blockSize.0) }) {
                let bpp = (def.map { _ in
                    // Need the pixel count to compute bpp; load again
                    let img = loadPGM16(fix.filename)
                    return Double(c.bytes * 8) / Double(img!.width * img!.height)
                }) ?? 0
                let dominated: String = {
                    guard let d = def else { return "-" }
                    if c.levels == 5 && c.blockSize == (64, 64) { return "(default)" }
                    if c.wallMs >= d.wallMs && c.bytes >= d.bytes {
                        return "yes — default is faster + smaller"
                    }
                    if c.wallMs < d.wallMs && c.bytes < d.bytes {
                        return "**DOMINATES default** (faster + smaller)"
                    }
                    if c.wallMs < d.wallMs {
                        return "faster but larger"
                    }
                    return "smaller but slower"
                }()
                print(String(format: "| %d | %d×%d | %6.2f | %d | %.2f | %@ |",
                    c.levels, c.blockSize.0, c.blockSize.1,
                    c.wallMs, c.bytes, bpp, dominated))
            }
            print()
        }

        // Cross-fixture: does any non-default combo CONSISTENTLY dominate?
        print("## Cross-fixture: combos that DOMINATE default on each fixture")
        print()
        var combosDominateCount: [String: Int] = [:]
        for fix in Self.corpus {
            guard let group = byFixture[fix.label] else { continue }
            let def = group.first { $0.levels == 5 && $0.blockSize == (64, 64) }
            guard let d = def else { continue }
            for c in group {
                if c.levels == 5 && c.blockSize == (64, 64) { continue }
                let key = "levels=\(c.levels) block=\(c.blockSize.0)×\(c.blockSize.1)"
                if c.wallMs < d.wallMs && c.bytes < d.bytes {
                    combosDominateCount[key, default: 0] += 1
                }
            }
        }
        let totalFixtures = byFixture.count
        if combosDominateCount.isEmpty {
            print("  → NO non-default combo dominates the default on any fixture.")
            print("  → The (levels=5, block=64×64) default is pareto-optimal across the medical corpus.")
        } else {
            for (key, count) in combosDominateCount.sorted(by: { $0.value > $1.value }) {
                let pct = 100.0 * Double(count) / Double(totalFixtures)
                print(String(format: "  %@: dominates default on %d/%d fixtures (%.0f%%)",
                    key, count, totalFixtures, pct))
            }
        }
    }
}
