// HTGPUForward53Phase9ThresholdBoundaryTests.swift
//
// v6-alpha5 Phase 9 — empirical re-validation of the 4 MP gate
// threshold via finer-grained pixel-count sweep.
//
// Phase 5 swept the 7 medical-corpus fixtures and concluded the
// production threshold should sit at 4 MP. Phase 9 zooms in
// around that boundary with synthetic fixtures at exactly 1, 2,
// 3, 4, 6, 12, 16 MP — the granularity needed to confirm:
//
//   1. **GPU loses or is noise below 4 MP** (1, 2, 3 MP cells).
//   2. **GPU wins consistently at or above 4 MP** (4, 6, 12, 16 MP).
//   3. **No jitter causes threshold instability** — three-run
//      median means a small loss at 4 MP shouldn't tip the
//      threshold one MP either way.
//   4. **DX / MG (the medical fixtures the production threshold
//      was set for) remain wins** — the corpus-fixture sweep
//      from Phase 5/6/8 still holds.
//
// Diagnostic-only — does not assert routing or wall time. The
// numbers it prints are the input to the cross-device tuning
// table in `MEDICAL_BENCHMARK_V6.md` (Phase 9 section).
//
// Skipped automatically in DEBUG (numbers would be 50–100×
// slower) or when Metal is unavailable.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class HTGPUForward53Phase9ThresholdBoundaryTests: XCTestCase {

    private func htConfig(decompositionLevels: Int = 5) -> J2KEncodingConfiguration {
        J2KEncodingConfiguration(
            quality: 1.0, lossless: true,
            decompositionLevels: decompositionLevels,
            qualityLayers: 1, progressionOrder: .lrcp,
            bitrateMode: .lossless, maxThreads: 8,
            useHTJ2K: true, useReversibleFilter: true,
            enableParallelCodeBlocks: true,
            htj2kBlockFormat: .conformant)
    }

    private func syntheticImage(width: Int, height: Int, seed: UInt64) -> J2KImage {
        var data = Data(count: width * height * 2)
        var rng: UInt64 = seed
        for i in 0..<(width * height) {
            rng &+= 0x9E37_79B9_7F4A_7C15
            let v = UInt16(truncatingIfNeeded: rng)
            data[2 * i]     = UInt8(v >> 8)
            data[2 * i + 1] = UInt8(v & 0xFF)
        }
        let comp = J2KComponent(
            index: 0, bitDepth: 16, signed: false,
            width: width, height: height,
            subsamplingX: 1, subsamplingY: 1,
            data: data, sampleByteOrder: .bigEndian)
        return J2KImage(width: width, height: height, components: [comp])
    }

    /// A/B encode helper — forces threshold to 1 so even sub-4 MP
    /// fixtures exercise the GPU path; restores both flags
    /// after every call.
    private func encode(_ image: J2KImage,
                        config: J2KEncodingConfiguration,
                        gpuForward: Bool) async throws -> Data {
        let prevEnabled = EncoderPipeline._gpuForward53Enabled
        let prevThreshold = EncoderPipeline._gpuForward53PixelThreshold
        defer {
            EncoderPipeline._gpuForward53Enabled = prevEnabled
            EncoderPipeline._gpuForward53PixelThreshold = prevThreshold
        }
        EncoderPipeline._gpuForward53Enabled = gpuForward
        EncoderPipeline._gpuForward53PixelThreshold = 1
        let encoder = J2KEncoder(encodingConfiguration: config)
        return try await encoder.encode(image)
    }

    /// Phase 9 boundary sweep — single-tile lossless encode wall
    /// time at the 7 sizes the user requested (1/2/3/4/6/12/16 MP)
    /// + the existing corpus DX 6.41 MP and MG 16.84 MP for
    /// continuity with the Phase 5/6/8 measurements.
    ///
    /// Median of 3 runs (release mode). Each row: CPU wall, GPU
    /// wall, GPU/CPU ratio, byte-identical assertion, GPU
    /// setup-ms (warm-session expectation: < 1 ms after first
    /// fire), GPU dispatch-ms.
    func testGPUForward53_Phase9_ThresholdBoundarySweep() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  Phase 9 boundary sweep running in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter HTGPUForward53Phase9ThresholdBoundaryTests")
        #endif

        struct Bench {
            let label: String
            let width: Int
            let height: Int
            let approxMP: Double
        }
        // Sizes chosen so width * height lands at exactly the
        // requested megapixel target (within 1%).
        let cases: [Bench] = [
            Bench(label: "  1 MP (1024×1024)",  width: 1024, height: 1024, approxMP:  1.05),
            Bench(label: "  2 MP (1448×1448)",  width: 1448, height: 1448, approxMP:  2.10),
            Bench(label: "  3 MP (1732×1732)",  width: 1732, height: 1732, approxMP:  3.00),
            Bench(label: "  4 MP (2000×2000)",  width: 2000, height: 2000, approxMP:  4.00),
            Bench(label: "  6 MP (2449×2449)",  width: 2449, height: 2449, approxMP:  6.00),
            Bench(label: " 12 MP (3464×3464)",  width: 3464, height: 3464, approxMP: 12.00),
            Bench(label: " 16 MP (4000×4000)",  width: 4000, height: 4000, approxMP: 16.00),
        ]
        let runs = 3
        let cfg = htConfig()

        print("=== Phase 9 — threshold-boundary sweep (release, Apple M2, median of \(runs)) ===")
        print("(Threshold forced to 1 so every fixture exercises the GPU code path.")
        print(" The 4 MP threshold's empirical break-even is the production policy.)")
        print()
        print("| Fixture                | px       | CPU ms | GPU ms | GPU/CPU× | Δ        | bytes match | GPU setup | GPU dispatch |")
        print("|---|---:|---:|---:|---:|---:|:---:|---:|---:|")

        for c in cases {
            let image = syntheticImage(width: c.width, height: c.height, seed: 0xC0FE_FACE)

            // Warm-up.
            _ = try await encode(image, config: cfg, gpuForward: true)
            _ = try await encode(image, config: cfg, gpuForward: false)

            // CPU runs.
            var cpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encode(image, config: cfg, gpuForward: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            cpuMs.sort()

            // GPU runs — also collect setup + dispatch ms via telemetry.
            var gpuMs: [Double] = []
            var setupMsList: [Double] = []
            var dispatchMsList: [Double] = []
            var gpuBytes: Data?
            for _ in 0..<runs {
                J2KGPUForward53Telemetry.reset()
                let t0 = Date().timeIntervalSinceReferenceDate
                let bytes = try await encode(image, config: cfg, gpuForward: true)
                gpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
                let s = J2KGPUForward53Telemetry.snapshot()
                if s.gpuFireCount > 0 {
                    setupMsList.append(s.totalSetupMs / Double(s.gpuFireCount))
                    dispatchMsList.append(s.totalDispatchMs / Double(s.gpuFireCount))
                }
                gpuBytes = bytes
            }
            gpuMs.sort()
            setupMsList.sort()
            dispatchMsList.sort()

            // Byte-identical check (one-shot, since runs are
            // deterministic — Phase 4 proved this).
            let cpuBytes = try await encode(image, config: cfg, gpuForward: false)
            let bytesMatch = (gpuBytes == cpuBytes)

            let cpuMed = cpuMs[runs / 2]
            let gpuMed = gpuMs[runs / 2]
            let setupMed = setupMsList.isEmpty ? 0 : setupMsList[setupMsList.count / 2]
            let dispatchMed = dispatchMsList.isEmpty ? 0 : dispatchMsList[dispatchMsList.count / 2]
            let ratio = gpuMed / cpuMed
            let delta = ((cpuMed - gpuMed) / cpuMed) * 100.0
            print(String(format: "| %@ | %d | %6.2f | %6.2f | %5.2f×   | %+5.1f %% | %@         | %5.2f ms | %5.2f ms     |",
                c.label, c.width * c.height,
                cpuMed, gpuMed, ratio, delta,
                bytesMatch ? "✓" : "✗",
                setupMed, dispatchMed))
        }

        print()
        print("Phase 9 readout:")
        print("  - GPU setup time should be ≪ 1 ms after the first fixture warms")
        print("    `J2KMetalSession.processShared`. If higher, the session isn't")
        print("    being shared (Phase 3 regression).")
        print("  - GPU/CPU ratio < 1.0 = GPU wins. The 4 MP threshold should be")
        print("    the largest fixture where GPU still loses by more than measurement")
        print("    noise (±5 % run-to-run on M2).")
        print("  - bytes-match column is the byte-identical guarantee (Phase 4 / 8).")
    }
}
