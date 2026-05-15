// V10_5_IDWTColBlockVsGPUTests.swift
//
// v10.5-research Phase 4b — does the v10.5 CPU column-block IDWT
// path beat the production GPU IDWT for MG / DX / PX?
//
// The default `decoder.decode()` router sends every ≥4 MP fixture
// to the GPU IDWT path (v6.2.0 default-on). That's why the Phase 4
// A/B with the column-block flag toggled showed near-zero end-to-
// end delta on MG/DX/PX — the column-block code never runs for
// those fixtures unless we force the CPU path.
//
// Three measurements per fixture:
//   1. GPU IDWT (default-on, `_gpuInverse53Enabled = true`).
//   2. CPU IDWT — canonical transpose path
//      (`columnBlockLiftEnabled = false`).
//   3. CPU IDWT — column-block path
//      (`columnBlockLiftEnabled = true`, v10.5 default).
//
// Acceptance gate (v7.4 discipline): if (3) beats (1) by ≥3 ms on
// any MG/DX/PX fixture, we have a router-flip recommendation —
// flip `_gpuInverse53Enabled` off (or raise the pixel threshold)
// for that fixture class. If (3) only beats (2) but loses to (1),
// the lever is real on the CPU path but the router stays as-is
// and the win is unreachable from `.decode()`.
//
// Run with:
//   swift test -c release --filter V10_5_IDWTColBlockVsGPUTests

import XCTest
import Foundation
@testable import J2KCodec
@testable import J2KCore

final class V10_5_IDWTColBlockVsGPUTests: XCTestCase {

    private struct Fixture {
        let label: String
        let filename: String
    }

    private static let corpus: [Fixture] = [
        Fixture(label: "MG small 3516×4784",  filename: "medical-real/mg_real_small_3516x4784.pgm"),
        Fixture(label: "MG mid 3518×4784",    filename: "medical-real/mg_real_mid_3518x4784.pgm"),
        Fixture(label: "MG large 3521×4784",  filename: "medical-real/mg_real_large_3521x4784.pgm"),
        Fixture(label: "DX 2800×2288",        filename: "dx_study_002_instance_000001.pgm"),
        Fixture(label: "DX small 2224×2798",  filename: "medical-real/dx_real_small_2224x2798.pgm"),
        Fixture(label: "DX large 2544×3056",  filename: "medical-real/dx_real_large_2544x3056.pgm"),
        Fixture(label: "PX 2459×1316",        filename: "px_study_001_instance_000001.pgm"),
        Fixture(label: "PX mid 2793×1316",    filename: "medical-real/px_real_mid_2793x1316.pgm"),
        Fixture(label: "PX large 2812×1316",  filename: "medical-real/px_real_large_2812x1316.pgm"),
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

    private func bench(
        decoder: J2KDecoder, codestream: Data, n: Int, warmups: Int
    ) async throws -> Double {
        for _ in 0..<warmups { _ = try await decoder.decode(codestream) }
        var times: [Double] = []
        for _ in 0..<n {
            let t0 = Date()
            _ = try await decoder.decode(codestream)
            times.append(Date().timeIntervalSince(t0) * 1000)
        }
        return times.sorted()[n / 2]
    }

    func testGPUvsCPU_ColBlockVsCanonical_MedicalCorpus() async throws {
        let n = 7
        let warmups = 2
        let cfg = htLosslessConfig()
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let decoder = J2KDecoder()

        struct Row {
            let label: String
            let pixels: Int
            let gpuMs: Double
            let cpuCanonicalMs: Double
            let cpuColBlockMs: Double
        }

        var rows: [Row] = []
        var skipped: [String] = []

        for fix in Self.corpus {
            guard let image = try loadPGM16(fix.filename) else {
                skipped.append(fix.label); continue
            }
            let codestream = try await encoder.encode(image)

            // 1) Production routing — GPU IDWT.
            DecoderPipeline._gpuInverse53Enabled = true
            J2KDWT2DOptimizer.columnBlockLiftEnabled = true   // irrelevant on GPU
            let gpuMs = try await bench(
                decoder: decoder, codestream: codestream,
                n: n, warmups: warmups)

            // 2) Force CPU + canonical column-pass (transpose round-trip).
            DecoderPipeline._gpuInverse53Enabled = false
            J2KDWT2DOptimizer.columnBlockLiftEnabled = false
            let cpuCanonicalMs = try await bench(
                decoder: decoder, codestream: codestream,
                n: n, warmups: warmups)

            // 3) Force CPU + column-block (v10.5 default).
            DecoderPipeline._gpuInverse53Enabled = false
            J2KDWT2DOptimizer.columnBlockLiftEnabled = true
            let cpuColBlockMs = try await bench(
                decoder: decoder, codestream: codestream,
                n: n, warmups: warmups)

            rows.append(Row(
                label: fix.label,
                pixels: image.width * image.height,
                gpuMs: gpuMs,
                cpuCanonicalMs: cpuCanonicalMs,
                cpuColBlockMs: cpuColBlockMs))
        }

        // Restore production defaults.
        DecoderPipeline._gpuInverse53Enabled = true
        J2KDWT2DOptimizer.columnBlockLiftEnabled = true

        print("=== v10.5 GPU iDWT vs CPU iDWT (canonical / column-block) — end-to-end (M2 release) ===")
        print("Processor: \(processorBrandString())")
        print("Cores: \(ProcessInfo.processInfo.processorCount)  Warmups: \(warmups)  Runs: \(n)")
        if !skipped.isEmpty {
            print("Skipped: \(skipped.joined(separator: ", "))")
        }
        print("")
        print("| Fixture | px | GPU ms (prod) | CPU canon ms | CPU col-block ms | ΔcpuCol−GPU | ΔcpuCol−cpuCanon |")
        print("|---|---:|---:|---:|---:|---:|---:|")
        for r in rows {
            let dCpuColVsGPU = r.cpuColBlockMs - r.gpuMs
            let dCpuColVsCanon = r.cpuColBlockMs - r.cpuCanonicalMs
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %6.2f | %+5.2f | %+5.2f |",
                         r.label, r.pixels,
                         r.gpuMs, r.cpuCanonicalMs, r.cpuColBlockMs,
                         dCpuColVsGPU, dCpuColVsCanon))
        }
        print("")
        print("Reading:")
        print("  - Negative ΔcpuCol−GPU = CPU column-block faster than GPU IDWT")
        print("    → router-flip recommendation for that fixture class.")
        print("  - Negative ΔcpuCol−cpuCanon = column-block faster than canonical CPU")
        print("    → confirms the CPU bandwidth lever is real end-to-end (not just microbench).")

        XCTAssertFalse(rows.isEmpty, "No fixtures benched")
    }
}
