// V720PhaseEThresholdSweepTests.swift
//
// v7.2.0 Phase E — empirical threshold sweep for the multi-tile
// per-tile GPU entropy and GPU IDWT pixel thresholds. v7.1.1 set
// both to 1 MP after measuring that DX 4x4 (16 × ~400 K/tile)
// regressed 2.14× when the GPU paths fired at smaller per-tile
// sizes. Phase E asks: with the current code state, where does
// the GPU-vs-CPU crossover actually live?
//
// Approach: encode DX as 4x4 multi-tile (the smallest per-tile
// size in the corpus that still has a real workload), then decode
// it with each threshold value in {256K, 512K, 1M, 2M, very-large}.
// Threshold values that put DX-4x4-per-tile (~400 K) ABOVE the
// gate route to GPU; values that put it BELOW route to CPU.
//
// We measure each (threshold-entropy, threshold-IDWT) cell as a
// median of 5 warm decodes. The output table tells us the
// optimal v7.2.0 threshold value to ship.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class V720PhaseEThresholdSweepTests: XCTestCase {

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

    private func htConfig() -> J2KEncodingConfiguration {
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: true,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .lossless
        return cfg
    }

    /// Build a DX 4x4 multi-tile codestream — the regression target
    /// from v7.1.1. Per-tile size ≈ 400 K, currently below both
    /// gates so the entire decode runs on CPU.
    private func makeDX4x4Codestream() async throws -> Data? {
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            return nil
        }
        let cfg = htConfig()
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: image.width, imageHeight: image.height,
            decompositionLevels: 5, mode: .tiles4x4)
        XCTAssertTrue(layout.isMultiTile, "DX 4x4 must produce multi-tile layout")
        let result = try await J2KMultiTileEncoder.encode(
            image: image, layout: layout, configuration: cfg)
        return result.codestream
    }

    private struct CellResult {
        let label: String
        let entropyThreshold: Int
        let idwtThreshold: Int
        let medianMs: Double
        let entropyOnGPU: Bool
        let idwtOnGPU: Bool
    }

    private func runDecodes(
        codestream: Data,
        entropyThreshold: Int,
        idwtThreshold: Int,
        runs: Int
    ) async throws -> Double {
        let prevEntropy = DecoderPipeline._gpuHTEntropyMultiTilePerTilePixelThreshold
        let prevIDWT = DecoderPipeline._gpuInverse53MultiTilePerTilePixelThreshold
        defer {
            DecoderPipeline._gpuHTEntropyMultiTilePerTilePixelThreshold = prevEntropy
            DecoderPipeline._gpuInverse53MultiTilePerTilePixelThreshold = prevIDWT
        }
        DecoderPipeline._gpuHTEntropyMultiTilePerTilePixelThreshold = entropyThreshold
        DecoderPipeline._gpuInverse53MultiTilePerTilePixelThreshold = idwtThreshold

        // Warm session + warm decode
        try await J2KMetalSession.processShared.preWarm()
        _ = try await J2KDecoder().decodeGPU(codestream)

        var samples: [Double] = []
        for _ in 0..<runs {
            let t0 = Date().timeIntervalSinceReferenceDate
            _ = try await J2KDecoder().decodeGPU(codestream)
            let t1 = Date().timeIntervalSinceReferenceDate
            samples.append((t1 - t0) * 1000.0)
        }
        samples.sort()
        return samples[runs / 2]
    }

    /// Sweep both thresholds across {256K, 512K, 1M (current), 2M,
    /// very-large}. Print median wall-time per cell. Bit-exactness is
    /// implicit since `decodeGPU` always produces the same J2KImage
    /// regardless of routing (the cross-codec gate guarantees that).
    func testPhaseEThresholdSweep_DX4x4() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        guard let codestream = try await makeDX4x4Codestream() else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }

        // DX 4x4 per-tile pixel count = 700 × 572 = 400 400.
        let dxPerTilePx = 700 * 572
        let veryLarge = 64_000_000
        let thresholds: [(label: String, value: Int)] = [
            ("256K",   256 * 1024),
            ("512K",   512 * 1024),
            ("1M",   1_048_576),
            ("2M",   2_097_152),
            ("∞",      veryLarge),
        ]
        let runs = Int(ProcessInfo.processInfo.environment["RUNS"] ?? "5") ?? 5

        print("=== v7.2.0 Phase E — DX 4x4 multi-tile per-tile decode threshold sweep ===")
        print("DX 4x4 per-tile pixels = \(dxPerTilePx)  (entropy/IDWT GPU paths fire when threshold ≤ \(dxPerTilePx))")
        print()

        // Single-axis sweeps + diagonal (both thresholds at the same value).
        var rows: [CellResult] = []
        for t in thresholds {
            let medianMs = try await runDecodes(
                codestream: codestream,
                entropyThreshold: t.value,
                idwtThreshold: t.value,
                runs: runs)
            rows.append(CellResult(
                label: t.label,
                entropyThreshold: t.value,
                idwtThreshold: t.value,
                medianMs: medianMs,
                entropyOnGPU: dxPerTilePx >= t.value,
                idwtOnGPU: dxPerTilePx >= t.value))
        }

        print("| threshold (entropy=IDWT) | DX 4x4 decode ms | entropy on GPU | IDWT on GPU |")
        print("|---|---:|:---:|:---:|")
        for r in rows {
            print(String(format: "| %@ | %.2f | %@ | %@ |",
                r.label, r.medianMs,
                r.entropyOnGPU ? "✓" : "✗",
                r.idwtOnGPU ? "✓" : "✗"))
        }

        // Single-axis: vary entropy threshold, hold IDWT at ∞ (CPU).
        // Isolates the entropy stage's GPU contribution.
        print()
        print("--- isolate entropy: vary entropy threshold, IDWT pinned to CPU ---")
        print("| entropy threshold | DX 4x4 decode ms | entropy on GPU |")
        print("|---|---:|:---:|")
        for t in thresholds {
            let medianMs = try await runDecodes(
                codestream: codestream,
                entropyThreshold: t.value,
                idwtThreshold: veryLarge,
                runs: runs)
            print(String(format: "| %@ | %.2f | %@ |",
                t.label, medianMs,
                dxPerTilePx >= t.value ? "✓" : "✗"))
        }

        // Single-axis: vary IDWT threshold, hold entropy at ∞ (CPU).
        print()
        print("--- isolate IDWT: vary IDWT threshold, entropy pinned to CPU ---")
        print("| IDWT threshold | DX 4x4 decode ms | IDWT on GPU |")
        print("|---|---:|:---:|")
        for t in thresholds {
            let medianMs = try await runDecodes(
                codestream: codestream,
                entropyThreshold: veryLarge,
                idwtThreshold: t.value,
                runs: runs)
            print(String(format: "| %@ | %.2f | %@ |",
                t.label, medianMs,
                dxPerTilePx >= t.value ? "✓" : "✗"))
        }
    }
}
