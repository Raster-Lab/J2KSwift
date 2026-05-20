// V10_9_PartialResolutionPotentialBench.swift
//
// v10.9-research Phase C — quantify the UPPER-BOUND wall reduction
// available from a TRUE partial-resolution decode implementation,
// using a simulation: encode the same source image with
// `decompositionLevels = 1, 2, 3, 4, 5` and decode each. Decode
// wall at lower decomposition counts approximates what a TRUE
// partial-decode would achieve at corresponding resolution levels.
//
// J2KSwift currently has stub implementations of `decodePartial`,
// `decodeResolution`, `decodeQuality` (all throw `notImplemented`).
// Only `decodeRegion` with `.fullImageExtraction` works (decode then
// crop — does NOT save time).
//
// Memory `project_jp3d_beat_openjpeg.md` flags this as a known gap:
// "ROI decoder decodes-then-crops (no true per-resolution selective
// decode)".
//
// If decoding at level 2 is dramatically faster than level 5, the
// gap is worth closing (multi-week feature). If marginal, the
// existing stubs can stay and v10.9 closes as informational.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_9_PartialResolutionPotentialBench: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "PX 2459×1316", filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "DX 2800×2288", filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "MG mid 3518×4784", filename: "medical-real/mg_real_mid_3518x4784.pgm"),
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

    private func htLosslessConfig(levels: Int) -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: levels, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    func testPartialResolutionPotential_MGDXPX() async throws {
        let decoder = J2KDecoder()
        let warmups = 2
        let nTrials = 7

        struct Row {
            let label: String
            let pixels: Int
            let timesByLevel: [Int: Double]  // levels=1..5
            let csBytesByLevel: [Int: Int]
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }

            var timesByLevel: [Int: Double] = [:]
            var bytesByLevel: [Int: Int] = [:]
            for levels in [1, 2, 3, 4, 5] {
                let cfg = htLosslessConfig(levels: levels)
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                let codestream = try await encoder.encode(image)
                bytesByLevel[levels] = codestream.count

                // Warm-up + sample.
                for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
                var times: [Double] = []
                for _ in 0..<nTrials {
                    let t0 = Date()
                    _ = try await decoder.decode(codestream)
                    times.append(Date().timeIntervalSince(t0) * 1000)
                }
                timesByLevel[levels] = median(times)
            }

            rows.append(Row(label: fix.label,
                            pixels: image.width * image.height,
                            timesByLevel: timesByLevel,
                            csBytesByLevel: bytesByLevel))
        }

        print("=== v10.9 partial-resolution potential bench (M2 release, lossless HT, 7 trials each) ===")
        print("Processor: \(processorBrandString())")
        if !skipped.isEmpty { print("Skipped: \(skipped.joined(separator: ", "))") }
        print("")
        print("Decode wall (ms) as a function of `decompositionLevels`:")
        print("| Fixture | px | L=1 | L=2 | L=3 | L=4 | L=5 (default) | L=1 speedup |")
        print("|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let l1 = r.timesByLevel[1] ?? 0
            let l5 = r.timesByLevel[5] ?? 0
            let l1Speed = l5 / max(l1, 0.001)
            print(String(format: "| %@ | %d | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f× |",
                         r.label, r.pixels,
                         r.timesByLevel[1] ?? -1,
                         r.timesByLevel[2] ?? -1,
                         r.timesByLevel[3] ?? -1,
                         r.timesByLevel[4] ?? -1,
                         r.timesByLevel[5] ?? -1,
                         l1Speed))
        }
        print("")
        print("Codestream byte sizes as a function of `decompositionLevels`:")
        print("| Fixture | L=1 bytes | L=2 bytes | L=3 bytes | L=4 bytes | L=5 bytes |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %d | %d | %d | %d |",
                         r.label,
                         r.csBytesByLevel[1] ?? -1,
                         r.csBytesByLevel[2] ?? -1,
                         r.csBytesByLevel[3] ?? -1,
                         r.csBytesByLevel[4] ?? -1,
                         r.csBytesByLevel[5] ?? -1))
        }
        print("")
        print("Interpretation:")
        print("  - The L=1 column is the upper-bound wall achievable from a TRUE partial-")
        print("    resolution decode at coarsest level (thumbnail). The L=2/3/4 columns")
        print("    approximate intermediate-resolution decode walls.")
        print("  - This is a SIMULATION using separate codestreams. The actual partial-decode")
        print("    feature would decode at lower resolution from the SAME codestream (5 levels),")
        print("    which is similar but not identical to encoding at fewer levels.")
        print("  - Real win on the 'beat Kakadu' framing: not directly (cross-codec bench is")
        print("    full-decode apples-to-apples). But for DICOM thumbnail / viewport workflows,")
        print("    this is the biggest single user-perceived speedup the codec can offer.")
        XCTAssertFalse(rows.isEmpty)
    }
}
#endif
