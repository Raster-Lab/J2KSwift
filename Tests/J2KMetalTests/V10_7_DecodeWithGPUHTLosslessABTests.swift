// V10_7_DecodeWithGPUHTLosslessABTests.swift
//
// v10.7-research Phase 2b — re-measure `decodeWithGPUHT` vs the
// production CPU path on the LOSSLESS HT-conformant 5/3 corpus
// (matches the warm cross-codec bench setup, so the numbers are
// directly comparable to the Kakadu gap report).
//
// Memory `project_v7_5_0_shipped.md` says GPU HT entropy was closed
// as wash in v7.5: "GPU is slower on every fixture (DX −22.4 ms /
// −44.6%); per-block GPU cost ~6.7× CPU on M2". The current
// `J2KMedicalCorpusPerformanceTests.testCorpusWarmSessionAcrossDecodeAPIs`
// shows on LOSSY 9/7 that the picture has shifted favorable —
// `decodeWithGPUHT` wins on PX (3.34×), XA (1.98×), MR-886 (1.68×).
// This test runs the same comparison on LOSSLESS HT to confirm
// the production routing (`.cpu` at ≥15 MP) is still correct.

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore
@testable import J2KMetal

final class V10_7_DecodeWithGPUHTLosslessABTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "MR-small 180²",       filename: "mr_study_002_instance_000100.pgm"),
        Fixture(label: "CT 512²",             filename: "ct_study_001_instance_000001.pgm"),
        Fixture(label: "MR 886²",             filename: "mr_study_001_instance_000001.pgm"),
        Fixture(label: "XA 1024²",            filename: "xa_study_001_instance_000001.pgm"),
        Fixture(label: "PX 2459×1316",        filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX mid 2793×1316",    filename: "medical-real/px_real_mid_2793x1316.pgm"),
        Fixture(label: "PX large 2812×1316",  filename: "medical-real/px_real_large_2812x1316.pgm"),
        Fixture(label: "DX 2800×2288",        filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX small 2224×2798",  filename: "medical-real/dx_real_small_2224x2798.pgm"),
        Fixture(label: "DX large 2544×3056",  filename: "medical-real/dx_real_large_2544x3056.pgm"),
        Fixture(label: "MG small 3516×4784",  filename: "medical-real/mg_real_small_3516x4784.pgm"),
        Fixture(label: "MG mid 3518×4784",    filename: "medical-real/mg_real_mid_3518x4784.pgm"),
        Fixture(label: "MG large 3521×4784",  filename: "medical-real/mg_real_large_3521x4784.pgm"),
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

    private func benchCPU(decoder: J2KDecoder, codestream: Data, n: Int, warmups: Int) async throws -> Double {
        for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
        var times: [Double] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try await decoder.decode(codestream)
            times.append(Date().timeIntervalSince(t0) * 1000)
        }
        return times.sorted()[n / 2]
    }

    private func benchGPUHT(decoder: J2KDecoder, session: J2KMetalSession, codestream: Data, n: Int, warmups: Int) async throws -> Double {
        for _ in 0..<warmups { _ = try await decoder.decodeWithGPUHT(codestream, session: session) }
        var times: [Double] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try await decoder.decodeWithGPUHT(codestream, session: session)
            times.append(Date().timeIntervalSince(t0) * 1000)
        }
        return times.sorted()[n / 2]
    }

    func testCPUvsGPUHT_LosslessCorpus() async throws {
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
            let cpuMs: Double
            let gpuHTMs: Double
        }

        var rows: [Row] = []
        var skipped: [String] = []
        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }
            let codestream = try await encoder.encode(image)
            let cpuMs = try await benchCPU(decoder: decoder, codestream: codestream, n: n, warmups: warmups)
            let gpuHTMs = try await benchGPUHT(decoder: decoder, session: session,
                                                codestream: codestream, n: n, warmups: warmups)
            rows.append(Row(label: fix.label,
                            pixels: image.width * image.height,
                            cpuMs: cpuMs, gpuHTMs: gpuHTMs))
        }

        print("=== v10.7 decodeWithGPUHT vs CPU (lossless HT corpus, M2 release) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Runs: \(n)")
        if !skipped.isEmpty {
            print("Skipped: \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | CPU ms | decodeWithGPUHT ms | Δ ms | speedup |")
        print("|---|---:|---:|---:|---:|---:|")
        for r in rows {
            let delta = r.cpuMs - r.gpuHTMs
            let speedup = r.cpuMs / r.gpuHTMs
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %+5.2f | %.2f× |",
                         r.label, r.pixels,
                         r.cpuMs, r.gpuHTMs, delta, speedup))
        }
        print("")
        print("Interpretation:")
        print("  - Positive Δ ms = decodeWithGPUHT wins. If ≥3 ms on MG/DX/PX,")
        print("    the production routing (`.cpu` at ≥15 MP) is wrong and we")
        print("    should flip the recommended API to decodeWithGPUHT.")

        XCTAssertFalse(rows.isEmpty, "No fixtures benched")
    }
}
#endif
