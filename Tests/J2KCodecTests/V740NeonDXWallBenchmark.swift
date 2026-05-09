// V740NeonDXWallBenchmark.swift
//
// v7.4 NEON reconstruction — end-to-end DX 2800×2288 in-process
// wall-time A/B (scalar vs NEON). The acceptance criterion for v7.4
// is "DX in-process decode improves by at least 3 ms" before enabling
// the NEON path by default.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V740NeonDXWallBenchmark: XCTestCase {

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

    private func medianMs(
        _ runs: Int, _ body: () async throws -> Void
    ) async throws -> Double {
        var samples: [Double] = []
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            try await body()
            let t1 = Date().timeIntervalSinceReferenceDate
            samples.append((t1 - t0) * 1000.0)
        }
        samples.sort()
        return samples[runs / 2]
    }

    /// DX 2800×2288 in-process decode — measure scalar vs NEON
    /// reconstruction at the full-pipeline wall-time level. This is
    /// the test that gates "default NEON ON" per the v7.4 acceptance
    /// criterion (DX wall must improve by ≥ 3 ms; otherwise NEON
    /// stays behind a flag).
    func testDXInProcessWall_ScalarVsNEON() async throws {
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            throw XCTSkip("DX fixture not present")
        }
        let cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        let codestream = try await J2KEncoder(encodingConfiguration: cfg)
            .encode(image)

        let runs = 5
        let prev = HTBlockDecoderConformant.neonReconstructionEnabled
        defer { HTBlockDecoderConformant.neonReconstructionEnabled = prev }

        // Warmup — first decode pays the GPU session warmup which we
        // don't want polluting the measurement.
        _ = try await J2KDecoder().decode(codestream)
        _ = try await J2KDecoder().decode(codestream)

        HTBlockDecoderConformant.neonReconstructionEnabled = false
        let scalar = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(codestream)
        }

        HTBlockDecoderConformant.neonReconstructionEnabled = true
        let neon = try await medianMs(runs) {
            _ = try await J2KDecoder().decode(codestream)
        }

        let delta = scalar - neon
        let pct = delta / scalar * 100.0

        print("=== v7.4 DX in-process decode A/B (median of \(runs)) ===")
        print(String(format: "  Scalar reconstruction: %.2f ms", scalar))
        print(String(format: "  NEON   reconstruction: %.2f ms", neon))
        print(String(format: "  Δ:                     %.2f ms (%+.1f %%)", delta, pct))
        print()
        if delta >= 3.0 {
            print("  ✓ ≥ 3 ms threshold met — NEON should remain default ON.")
        } else if delta >= 0 {
            print("  ⚠ < 3 ms threshold — per v7.4 acceptance criterion,")
            print("    keep NEON behind a flag (default OFF) until either")
            print("    further reconstruction work yields ≥ 3 ms or the")
            print("    flag is removed as not-load-bearing.")
        } else {
            print("  ✗ NEON SLOWER than scalar — must default OFF.")
        }
    }
}
