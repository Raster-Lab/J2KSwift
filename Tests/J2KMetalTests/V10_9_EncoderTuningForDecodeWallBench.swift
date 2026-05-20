// V10_9_EncoderTuningForDecodeWallBench.swift
//
// v10.9-research Phase D — survey encoder-side parameter choices and
// their effect on decode wall. The current encoder default uses
// code-block 64×64 + 5 decomposition levels. If a different encoder
// configuration produces codestreams that decode faster on our
// decoder without significant size penalty, the encoder defaults
// could be tuned.
//
// **Caveat**: this only helps codestreams J2KSwift produces; consumers
// decoding third-party codestreams see no change.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_9_EncoderTuningForDecodeWallBench: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "PX 2459×1316", filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX large 2812×1316", filename: "medical-real/px_real_large_2812x1316.pgm"),
        Fixture(label: "DX 2800×2288", filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX large 2544×3056", filename: "medical-real/dx_real_large_2544x3056.pgm"),
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

    private func htLosslessConfig(cbW: Int, cbH: Int) -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5,
            codeBlockSize: (width: cbW, height: cbH),
            qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    func testEncoderCodeBlockSizeSweep_DXPX() async throws {
        let decoder = J2KDecoder()
        let warmups = 2
        let nTrials = 7

        let sizes: [(Int, Int, String)] = [
            (16, 16, "16×16"),
            (32, 32, "32×32 (preset 'fast')"),
            (64, 64, "64×64 (default)"),
        ]

        struct Row {
            let label: String, pixels: Int
            let walls: [String: Double]
            let bytes: [String: Int]
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }

            var walls: [String: Double] = [:]
            var bytes: [String: Int] = [:]
            for (cbW, cbH, label) in sizes {
                let cfg = htLosslessConfig(cbW: cbW, cbH: cbH)
                let encoder = J2KEncoder(encodingConfiguration: cfg)
                guard let codestream = try? await encoder.encode(image) else {
                    walls[label] = -1; bytes[label] = 0
                    continue
                }
                bytes[label] = codestream.count

                for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
                var times: [Double] = []
                for _ in 0..<nTrials {
                    let t0 = Date()
                    _ = try await decoder.decode(codestream)
                    times.append(Date().timeIntervalSince(t0) * 1000)
                }
                walls[label] = median(times)
            }
            rows.append(Row(label: fix.label, pixels: image.width * image.height,
                            walls: walls, bytes: bytes))
        }

        print("=== v10.9 Phase D — encoder code-block size A/B on DX/PX decode wall (M2 release) ===")
        print("Processor: \(processorBrandString())")
        if !skipped.isEmpty { print("Skipped: \(skipped.joined(separator: ", "))") }
        print("")
        print("Decode wall (ms) as function of encoder code-block size:")
        print("| Fixture | px | 16×16 | 32×32 | 64×64 (default) |")
        print("|---|---:|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %.2f | %.2f | %.2f |",
                         r.label, r.pixels,
                         r.walls["16×16"] ?? -1,
                         r.walls["32×32 (preset 'fast')"] ?? -1,
                         r.walls["64×64 (default)"] ?? -1))
        }
        print("")
        print("Codestream byte sizes:")
        print("| Fixture | 16×16 bytes | 32×32 bytes | 64×64 bytes |")
        print("|---|---:|---:|---:|")
        for r in rows {
            print(String(format: "| %@ | %d | %d | %d |",
                         r.label,
                         r.bytes["16×16"] ?? -1,
                         r.bytes["32×32 (preset 'fast')"] ?? -1,
                         r.bytes["64×64 (default)"] ?? -1))
        }
        print("")
        print("Interpretation:")
        print("  - If 16×16 or 32×32 decodes meaningfully faster than 64×64 with ≤5% byte penalty,")
        print("    the encoder default should be reconsidered. Most likely outcome: 64×64 default")
        print("    is empirically near-optimal (smaller blocks add per-block overhead).")

        XCTAssertFalse(rows.isEmpty)
    }
}
#endif
