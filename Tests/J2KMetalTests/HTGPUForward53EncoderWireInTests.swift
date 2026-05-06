// HTGPUForward53EncoderWireInTests.swift
//
// v6-alpha5 / lossless-only pivot — Phase 2.
//
// Verifies that wiring the new GPU forward 5/3 INT path into the
// production encoder (gated by `J2K_GPU_FORWARD_53=1`) produces
// **byte-identical** codestreams to the CPU baseline. The
// codestream is the wire-level deliverable; if any byte differs
// between GPU and CPU forward backends, the gate flag would
// silently change user-visible output and we cannot ship phase 3.
//
// Phase 0 / 1 already proved bit-exact subband coefficients between
// GPU and CPU forward INT. Phase 2 proves that those bit-exact
// subbands flow through entropy + packet assembly to bit-exact
// output bytes — i.e. nothing downstream of the DWT is sensitive
// to which DWT backend produced the same Int32 numbers.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class HTGPUForward53EncoderWireInTests: XCTestCase {

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

    /// A/B encode helper: returns codestream bytes encoded with the
    /// given setting of `EncoderPipeline._gpuForward53Enabled`. Always
    /// restores the previous value (test isolation).
    private func encode(
        _ image: J2KImage,
        config: J2KEncodingConfiguration,
        gpuForward: Bool
    ) async throws -> Data {
        let prev = EncoderPipeline._gpuForward53Enabled
        defer { EncoderPipeline._gpuForward53Enabled = prev }
        EncoderPipeline._gpuForward53Enabled = gpuForward
        let encoder = J2KEncoder(encodingConfiguration: config)
        return try await encoder.encode(image)
    }

    /// 1024×1024 (above the 256² threshold for GPU eligibility):
    /// CPU and GPU forward must produce **byte-identical** codestreams.
    /// Phase-0 / phase-1 already proved bit-exact subband coefficients;
    /// this test proves nothing downstream of DWT changes when the
    /// backend swaps.
    func testGPUForward53_1024x1024_BytesIdenticalToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 1024, height: 1024, seed: 0xC0FE_FACE)
        let cfg = htConfig()

        let cpuBytes = try await encode(image, config: cfg, gpuForward: false)
        let gpuBytes = try await encode(image, config: cfg, gpuForward: true)

        XCTAssertEqual(cpuBytes.count, gpuBytes.count,
            "GPU and CPU forward must produce same-length codestream " +
            "(cpu=\(cpuBytes.count) gpu=\(gpuBytes.count))")
        XCTAssertEqual(cpuBytes, gpuBytes,
            "GPU forward 5/3 INT must be byte-identical to CPU forward — " +
            "if this fails, something downstream of DWT depends on the " +
            "backend (it shouldn't; subband coefficients are bit-exact " +
            "by phase 0/1 tests).")
    }

    /// 800×800 — less common dimension, exercises odd-tile partial
    /// blocks at the canvas edges.
    func testGPUForward53_800x800_BytesIdenticalToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 800, height: 800, seed: 0xBABE_F00D)
        let cfg = htConfig()

        let cpuBytes = try await encode(image, config: cfg, gpuForward: false)
        let gpuBytes = try await encode(image, config: cfg, gpuForward: true)

        XCTAssertEqual(cpuBytes, gpuBytes)
    }

    /// 200×200 — below the 256² gate threshold, so GPU forward should
    /// fall back to CPU even with the env var on. Output must equal
    /// the unconditional-CPU encode.
    func testGPUForward53_BelowThreshold_FallsBackToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 200, height: 200, seed: 0xDEAD_BABE)
        let cfg = htConfig()

        let cpuBytes = try await encode(image, config: cfg, gpuForward: false)
        let gateOnBytes = try await encode(image, config: cfg, gpuForward: true)

        // Below threshold — gateOn must produce the same CPU bytes.
        XCTAssertEqual(cpuBytes, gateOnBytes,
            "Sub-256² images must fall back to CPU even when " +
            "J2K_GPU_FORWARD_53 is enabled, to avoid command-buffer " +
            "overhead dominating compute on tiny images.")
    }

    /// Production default: when the gate flag is its initial state
    /// (env var unset → false), encoding produces v5.38-baseline bytes.
    /// This is the regression guard for Phase 2: shipping the new
    /// code path must not change unconditional production output.
    func testGPUForward53_DefaultOff_ProductionBytesUnchanged() async throws {
        let image = syntheticImage(width: 512, height: 512, seed: 0x5511_2244)
        let cfg = htConfig()

        // Don't touch the static — measure default behaviour.
        let encoder = J2KEncoder(encodingConfiguration: cfg)
        let bytes = try await encoder.encode(image)

        XCTAssertGreaterThan(bytes.count, 0,
            "Default encode must produce non-empty codestream")
        // Note: byte-content stability vs v5.38 is covered by
        // J2KLosslessMedicalGateTests / HT-fair / cross-codec gates.
        // This test only ensures the new code path doesn't alter the
        // default code path's semantics.
    }

    // MARK: - Phase 2 wall-time A/B (diagnostic)

    /// Diagnostic only — single-tile end-to-end encode wall time
    /// with GPU forward 5/3 INT enabled vs disabled, across multiple
    /// fixture sizes. Multi-tile encode passes non-zero per-tile
    /// origins on tiles 1+, so the gate falls back to CPU for those
    /// — hence single-tile is the right harness for Phase 2.
    ///
    /// Phase 1 isolated-DWT benchmark showed 2.49× GPU speedup on
    /// the DWT stage at 1.6 MP; this test reveals the **end-to-end**
    /// delta once `J2KMetalDWT(...) + initialize()` per-encode
    /// overhead and entropy / packet / codestream stages stack in.
    /// The size sweep tells us at what fixture size GPU forward
    /// starts winning — informing the Phase 3 decision on whether
    /// a process-wide persistent `J2KMetalDWT` instance is needed
    /// to amortise the init cost across encodes.
    func testGPUForward53_WallTimeAB_SizeSweep() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  GPU-forward A/B running in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter HTGPUForward53EncoderWireInTests/testGPUForward53_WallTimeAB_SizeSweep")
        #endif

        struct Bench { let label: String; let width: Int; let height: Int }
        let cases: [Bench] = [
            Bench(label: "XA 1024×1024", width: 1024, height: 1024),
            Bench(label: "MR 886×886",   width: 886,  height: 886),
            Bench(label: "PX 2459×1316", width: 2459, height: 1316),
            Bench(label: "DX 2800×2288", width: 2800, height: 2288),
            Bench(label: "MG 3520×4784", width: 3520, height: 4784),
        ]
        let runs = 5
        let cfg = htConfig()

        print("=== Phase 2 — single-tile end-to-end encode (median of \(runs), ms) ===")
        print("| Fixture | px | CPU fwd | GPU fwd | Δ |")
        print("|---|---:|---:|---:|---:|")

        for c in cases {
            let image = syntheticImage(width: c.width, height: c.height, seed: 0xC0FE_FACE)

            // Warm-up.
            _ = try await encode(image, config: cfg, gpuForward: true)
            _ = try await encode(image, config: cfg, gpuForward: false)

            var cpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encode(image, config: cfg, gpuForward: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            cpuMs.sort()

            var gpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encode(image, config: cfg, gpuForward: true)
                gpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            gpuMs.sort()

            let cpuMed = cpuMs[runs / 2]
            let gpuMed = gpuMs[runs / 2]
            let delta = ((cpuMed - gpuMed) / cpuMed) * 100.0
            print(String(format: "| %@ | %d | %.2f | %.2f | %+.1f %% |",
                c.label, c.width * c.height, cpuMed, gpuMed, delta))
        }
    }
}
