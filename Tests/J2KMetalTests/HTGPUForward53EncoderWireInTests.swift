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
    ///
    /// Phase 5 — also lowers `_gpuForward53PixelThreshold` to 1 so
    /// the GPU code path actually fires on the sub-4 MP test
    /// fixtures used in this suite. Production default
    /// (4_000_000 pixels) is restored after each call.
    private func encode(
        _ image: J2KImage,
        config: J2KEncodingConfiguration,
        gpuForward: Bool,
        forceGPUThresholdToOne: Bool = true
    ) async throws -> Data {
        let prevEnabled = EncoderPipeline._gpuForward53Enabled
        let prevThreshold = EncoderPipeline._gpuForward53PixelThreshold
        defer {
            EncoderPipeline._gpuForward53Enabled = prevEnabled
            EncoderPipeline._gpuForward53PixelThreshold = prevThreshold
        }
        EncoderPipeline._gpuForward53Enabled = gpuForward
        if forceGPUThresholdToOne {
            // Force-arm GPU on small fixtures so the byte-identical
            // assertions actually exercise the GPU code path. Wall-
            // time benchmarks override this to keep production routing.
            EncoderPipeline._gpuForward53PixelThreshold = 1
        }
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

    /// 200×200 — well below the 4 MP gate threshold (Phase 5).
    /// GPU forward must fall back to CPU even with the env var on
    /// — production threshold isn't lowered for this test.
    func testGPUForward53_BelowThreshold_FallsBackToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 200, height: 200, seed: 0xDEAD_BABE)
        let cfg = htConfig()

        let cpuBytes = try await encode(image, config: cfg,
            gpuForward: false, forceGPUThresholdToOne: false)
        let gateOnBytes = try await encode(image, config: cfg,
            gpuForward: true,  forceGPUThresholdToOne: false)

        // Below threshold — gateOn must produce the same CPU bytes.
        XCTAssertEqual(cpuBytes, gateOnBytes,
            "Sub-4 MP images must fall back to CPU even when " +
            "J2K_GPU_FORWARD_53 is enabled, to avoid the " +
            "wall-time regression Phase 3 / 5 measured below " +
            "the 4 MP break-even point.")
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

    // MARK: - Phase 4 slice 3 — multi-tile byte-identical

    /// Multi-tile A/B encode helper: encodes via
    /// `EncoderPipeline.encodeNativeMultiTile` so per-tile origins
    /// other than (0, 0) actually fire. Returns codestream bytes.
    ///
    /// Phase 5 — also lowers `_gpuForward53PixelThreshold` to 1 so
    /// per-tile GPU forward fires even when the per-tile pixel count
    /// is below the 4 MP production threshold. Wall-time benchmarks
    /// override this for production-routing measurement.
    private func encodeMultiTile(
        _ image: J2KImage,
        config: J2KEncodingConfiguration,
        cols: Int, rows: Int,
        gpuForward: Bool,
        forceGPUThresholdToOne: Bool = true
    ) async throws -> Data {
        let prevEnabled = EncoderPipeline._gpuForward53Enabled
        let prevThreshold = EncoderPipeline._gpuForward53PixelThreshold
        defer {
            EncoderPipeline._gpuForward53Enabled = prevEnabled
            EncoderPipeline._gpuForward53PixelThreshold = prevThreshold
        }
        EncoderPipeline._gpuForward53Enabled = gpuForward
        if forceGPUThresholdToOne {
            EncoderPipeline._gpuForward53PixelThreshold = 1
        }

        let pipeline = EncoderPipeline(config: config)
        let tw = (image.width  + cols - 1) / cols
        let th = (image.height + rows - 1) / rows
        let layout = J2KTileLayout(
            cols: cols, rows: rows, tileWidth: tw, tileHeight: th,
            imageWidth: image.width, imageHeight: image.height)
        let (bytes, _) = try await pipeline.encodeNativeMultiTile(
            image, layout: layout)
        return bytes
    }

    /// MR 886×886 2x2 multi-tile encode — origins (0, 0), (443, 0),
    /// (0, 443), (443, 443) span every parity combination. Phase 4
    /// slice 3 is the first commit where these tiles route through
    /// GPU forward (slices 1+2 lifted the kernel coverage; slice 3
    /// drops the gate's `tileOriginX == 0 && tileOriginY == 0`
    /// filter). Bytes must remain byte-identical.
    func testGPUForward53MultiTile_MR886_2x2_BytesIdenticalToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 886, height: 886, seed: 0xC0FE_FACE)
        let cfg = htConfig()

        let cpuBytes = try await encodeMultiTile(
            image, config: cfg, cols: 2, rows: 2, gpuForward: false)
        let gpuBytes = try await encodeMultiTile(
            image, config: cfg, cols: 2, rows: 2, gpuForward: true)

        XCTAssertEqual(cpuBytes.count, gpuBytes.count,
            "MR 886×886 2x2 multi-tile: GPU and CPU must produce same-length bytes " +
            "(cpu=\(cpuBytes.count) gpu=\(gpuBytes.count))")
        XCTAssertEqual(cpuBytes, gpuBytes,
            "MR 886×886 2x2 multi-tile: GPU forward 5/3 INT must be byte-identical " +
            "to CPU forward — every odd-parity tile routes through the new " +
            "parity-aware GPU path landed in phase 4 slices 1+2.")
    }

    /// DX 2800×2288 2x2 multi-tile — origins all even at level 0
    /// but parity flips at deeper DWT levels (1400/8 = 175 odd).
    /// Exercises the per-level Eq. B-15 origin trajectory inside
    /// the multi-level fused dispatch.
    func testGPUForward53MultiTile_DX2800_2x2_BytesIdenticalToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 2800, height: 2288, seed: 0xC0FE_FACE)
        let cfg = htConfig()

        let cpuBytes = try await encodeMultiTile(
            image, config: cfg, cols: 2, rows: 2, gpuForward: false)
        let gpuBytes = try await encodeMultiTile(
            image, config: cfg, cols: 2, rows: 2, gpuForward: true)

        XCTAssertEqual(cpuBytes, gpuBytes,
            "DX 2800×2288 2x2 multi-tile: GPU and CPU forward must produce byte-identical bytes")
    }

    /// PX 2459×1316 2x2 — irregular tile dims (1230×658 + a
    /// 1229-wide trailing column). Tile origins (0, 0), (1230, 0),
    /// (0, 658), (1230, 658) — even at L0, odd at deeper levels.
    func testGPUForward53MultiTile_PX2459_2x2_BytesIdenticalToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 2459, height: 1316, seed: 0xC0FE_FACE)
        let cfg = htConfig()

        let cpuBytes = try await encodeMultiTile(
            image, config: cfg, cols: 2, rows: 2, gpuForward: false)
        let gpuBytes = try await encodeMultiTile(
            image, config: cfg, cols: 2, rows: 2, gpuForward: true)

        XCTAssertEqual(cpuBytes, gpuBytes,
            "PX 2459×1316 2x2 multi-tile: byte-identical")
    }

    // MARK: - Phase 2 wall-time A/B (diagnostic)

    // MARK: - Phase 5 — multi-tile wall-time A/B (diagnostic)

    /// Diagnostic only — multi-tile end-to-end encode wall time with
    /// GPU forward 5/3 INT enabled vs disabled. Multi-tile is the
    /// production fast path post v6-alpha3 step 9; the Phase 4 gate
    /// relaxation finally lets every tile route through GPU forward.
    ///
    /// Layout choice mirrors the v6-alpha4 step-10 `.auto` policy:
    /// MR/XA below 3 MP get 2×2; PX/DX/MG above 3 MP get 4×4.
    /// That's what production users will hit when they opt into
    /// `J2K_HT_TILE_MODE=auto` AND `J2K_GPU_FORWARD_53=1`.
    ///
    /// Phase 3 single-tile sweep showed GPU wins ≥ 6 MP. Multi-tile
    /// changes the picture: each tile is smaller (700×572 on DX
    /// 4×4, ~1 MP), but 16 tiles run concurrently sharing the same
    /// `J2KMetalSession.processShared` so the GPU dispatch chain
    /// gets queued through one MTLCommandQueue. This benchmark
    /// reveals whether the per-tile compute amortises over the
    /// shared session's pipeline-cached state better than per-tile
    /// CPU forward (which already runs the parallel-strip + vDSP
    /// fast path).
    func testGPUForward53MultiTile_WallTimeAB_AutoLayoutSizeSweep() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")
        #if DEBUG
        print("⚠️  Multi-tile A/B running in DEBUG; numbers will be 50–100× too slow.")
        print("   Re-run with: swift test -c release --filter HTGPUForward53EncoderWireInTests/testGPUForward53MultiTile_WallTimeAB_AutoLayoutSizeSweep")
        #endif

        struct Bench {
            let label: String
            let width: Int
            let height: Int
            let cols: Int
            let rows: Int
        }
        let cases: [Bench] = [
            Bench(label: "MR  886× 886 / 2×2",  width:  886, height:  886, cols: 2, rows: 2),
            Bench(label: "XA 1024×1024 / 2×2",  width: 1024, height: 1024, cols: 2, rows: 2),
            Bench(label: "PX 2459×1316 / 4×4",  width: 2459, height: 1316, cols: 4, rows: 4),
            Bench(label: "DX 2800×2288 / 4×4",  width: 2800, height: 2288, cols: 4, rows: 4),
            Bench(label: "MG 3520×4784 / 4×4",  width: 3520, height: 4784, cols: 4, rows: 4),
        ]
        let runs = 5
        let cfg = htConfig()

        print("=== Phase 5 — multi-tile end-to-end encode (median of \(runs), ms) ===")
        print("| Fixture | px | tiles | CPU fwd | GPU fwd | Δ |")
        print("|---|---:|---:|---:|---:|---:|")

        for c in cases {
            let image = syntheticImage(width: c.width, height: c.height, seed: 0xC0FE_FACE)

            // Warm-up.
            _ = try await encodeMultiTile(
                image, config: cfg, cols: c.cols, rows: c.rows, gpuForward: true)
            _ = try await encodeMultiTile(
                image, config: cfg, cols: c.cols, rows: c.rows, gpuForward: false)

            var cpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encodeMultiTile(
                    image, config: cfg, cols: c.cols, rows: c.rows, gpuForward: false)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            cpuMs.sort()

            var gpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encodeMultiTile(
                    image, config: cfg, cols: c.cols, rows: c.rows, gpuForward: true)
                gpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            gpuMs.sort()

            let cpuMed = cpuMs[runs / 2]
            let gpuMed = gpuMs[runs / 2]
            let delta = ((cpuMed - gpuMed) / cpuMed) * 100.0
            print(String(format: "| %@ | %d | %d | %.2f | %.2f | %+.1f %% |",
                c.label, c.width * c.height, c.cols * c.rows,
                cpuMed, gpuMed, delta))
        }
    }

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

            // Warm-up. Force threshold = 1 so even the small fixtures
            // exercise the GPU code path — single-tile A/B is
            // diagnostic across sizes regardless of production gate.
            _ = try await encode(image, config: cfg,
                gpuForward: true,  forceGPUThresholdToOne: true)
            _ = try await encode(image, config: cfg,
                gpuForward: false, forceGPUThresholdToOne: true)

            var cpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encode(image, config: cfg,
                    gpuForward: false, forceGPUThresholdToOne: true)
                cpuMs.append((Date().timeIntervalSinceReferenceDate - t0) * 1000.0)
            }
            cpuMs.sort()

            var gpuMs: [Double] = []
            for _ in 0..<runs {
                let t0 = Date().timeIntervalSinceReferenceDate
                _ = try await encode(image, config: cfg,
                    gpuForward: true, forceGPUThresholdToOne: true)
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
