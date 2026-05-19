// V10_7_GPUHTEntropyEngagementCheck.swift
//
// v10.7-research Phase 2c — verify whether `J2KDecoder.decode()`
// actually engages GPU HT entropy on MG fixtures (default state of
// `_gpuHTEntropyEnabled = true`). Compares:
//
//   path A: decode() with _gpuHTEntropyEnabled = true (production default)
//   path B: decode() with _gpuHTEntropyEnabled = false (CPU HT entropy)
//   path C: decodeWithGPUHT() (explicit GPU HT entropy via dedicated entry)
//
// If A == B (within noise), then `_gpuHTEntropyEnabled` is NOT actually
// engaging GPU HT entropy through `decode()` for MG — i.e., the flag
// is ineffective in production. If A < B, GPU HT entropy IS engaged
// via `decode()`.
//
// If A < C, there's some additional efficiency in `decodeWithGPUHT()`
// beyond what `decode()` triggers via the flag.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_7_GPUHTEntropyEngagementCheck: XCTestCase {

    private static let corpus: [(String, String)] = [
        ("MG small 3516×4784",  "medical-real/mg_real_small_3516x4784.pgm"),
        ("MG mid 3518×4784",    "medical-real/mg_real_mid_3518x4784.pgm"),
        ("MG large 3521×4784",  "medical-real/mg_real_large_3521x4784.pgm"),
        ("DX 2800×2288",        "dx_study_002_instance_000001.pgm"),
        ("DX large 2544×3056",  "medical-real/dx_real_large_2544x3056.pgm"),
        ("PX large 2812×1316",  "medical-real/px_real_large_2812x1316.pgm"),
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

    private func htLosslessConfig() -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
    }

    private func median(_ xs: [Double]) -> Double { xs.sorted()[xs.count / 2] }

    func testGPUHTEntropyEngagement_MG_DX_PX() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")

        let n = 7
        let warmups = 2
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()
        let session = J2KMetalSession()

        struct Row {
            let label: String
            let pixels: Int
            let pathA: Double   // decode() with flag ON  (production default)
            let pathB: Double   // decode() with flag OFF (CPU HT entropy)
            let pathC: Double   // decodeWithGPUHT()
        }

        var rows: [Row] = []
        var skipped: [String] = []
        let savedFlag = DecoderPipeline._gpuHTEntropyEnabled
        defer { DecoderPipeline._gpuHTEntropyEnabled = savedFlag }

        for (label, filename) in Self.corpus {
            guard let image = try loadPGM16(filename) else {
                skipped.append(label); continue
            }
            let codestream = try await encoder.encode(image)

            // path A: decode() flag ON (production default)
            DecoderPipeline._gpuHTEntropyEnabled = true
            for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
            var aTimes: [Double] = []
            for _ in 0..<n {
                let t0 = Date()
                _ = try await decoder.decode(codestream)
                aTimes.append(Date().timeIntervalSince(t0) * 1000)
            }

            // path B: decode() flag OFF
            DecoderPipeline._gpuHTEntropyEnabled = false
            for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
            var bTimes: [Double] = []
            for _ in 0..<n {
                let t0 = Date()
                _ = try await decoder.decode(codestream)
                bTimes.append(Date().timeIntervalSince(t0) * 1000)
            }

            // path C: decodeWithGPUHT() — explicit entry
            DecoderPipeline._gpuHTEntropyEnabled = true
            for _ in 0..<warmups { _ = try await decoder.decodeWithGPUHT(codestream, session: session) }
            var cTimes: [Double] = []
            for _ in 0..<n {
                let t0 = Date()
                _ = try await decoder.decodeWithGPUHT(codestream, session: session)
                cTimes.append(Date().timeIntervalSince(t0) * 1000)
            }

            rows.append(Row(label: label, pixels: image.width * image.height,
                            pathA: median(aTimes),
                            pathB: median(bTimes),
                            pathC: median(cTimes)))
        }

        DecoderPipeline._gpuHTEntropyEnabled = savedFlag

        print("=== v10.7 GPU HT entropy engagement check (M2 release, lossless HT) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Runs: \(n)")
        if !skipped.isEmpty {
            print("Skipped: \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | A: decode flag-ON ms | B: decode flag-OFF ms | C: decodeWithGPUHT ms | A-B (flag impact) | A-C (entry impact) |")
        print("|---|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let aB = r.pathA - r.pathB
            let aC = r.pathA - r.pathC
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %6.2f | %+5.2f | %+5.2f |",
                         r.label, r.pixels,
                         r.pathA, r.pathB, r.pathC, aB, aC))
        }
        print("")
        print("Interpretation:")
        print("  - A − B (flag impact): if ≈ 0, the _gpuHTEntropyEnabled flag is INEFFECTIVE")
        print("    in decode() for this fixture (i.e., decode() doesn't actually engage GPU HT)")
        print("  - A − C (entry impact): if > 0, decodeWithGPUHT() is faster than decode()")
        print("    even when both should engage GPU HT. Indicates routing-level efficiency gap.")
        XCTAssertFalse(rows.isEmpty)
    }
}
#endif
