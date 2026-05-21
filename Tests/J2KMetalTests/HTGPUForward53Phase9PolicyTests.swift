// HTGPUForward53Phase9PolicyTests.swift
//
// v6-alpha5 Phase 9 — production-policy tests for the GPU forward
// 5/3 INT path.
//
// Phase 8 closed correctness; Phase 9 closes **routing**. The
// gate has three orthogonal predicates:
//
//   - `_gpuForward53Enabled` (env-var or programmatic flag)
//   - `J2KMetalDWT.isAvailable` (platform predicate)
//   - `width * height >= _gpuForward53PixelThreshold`
//
// Production users observe the gate via the codestream bytes
// (byte-identical regardless of which path fires) but the
// **routing** itself is invisible without the
// `J2KGPUForward53Telemetry` counters added in this phase. These
// tests assert that, for each combination of inputs, the right
// path fires — a stronger statement than "the bytes match"
// because byte-equality could be vacuously true if the GPU path
// silently fell back without firing.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class HTGPUForward53Phase9PolicyTests: XCTestCase {

    // MARK: - Fixtures

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

    /// Restore the gate flag and threshold to phase-3-default after
    /// every test, so tests stay isolated even if a previous test
    /// crashed mid-way.
    override func tearDown() {
        EncoderPipeline._gpuForward53Enabled = false
        EncoderPipeline._gpuForward53PixelThreshold = 4_000_000
        super.tearDown()
    }

    // MARK: - Policy: env-var unset → CPU path

    /// With the gate off, every encode must route to CPU.
    /// Production-default behaviour: users who don't opt in get
    /// the v6-alpha4 CPU encode path verbatim.
    func testGate_EnvDisabled_AlwaysRoutesToCPU() async throws {
        EncoderPipeline._gpuForward53Enabled = false
        EncoderPipeline._gpuForward53PixelThreshold = 1  // Even if threshold lowered to 1.

        let image = syntheticImage(width: 1024, height: 1024, seed: 0xC0FE_FACE)
        let cfg = htConfig()
        J2KGPUForward53Telemetry.reset()

        _ = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let s = J2KGPUForward53Telemetry.snapshot()
        XCTAssertEqual(s.gpuFireCount, 0,
            "GPU must NOT fire when _gpuForward53Enabled is false")
        XCTAssertGreaterThan(s.cpuFireByReason[.envDisabled] ?? 0, 0,
            "Skip reason must be env-disabled when the flag is off")
    }

    // MARK: - Policy: env-var set + below threshold → CPU path

    /// 1024×1024 (1.05 MP) is below the production 4 MP threshold.
    /// With the gate on but threshold at production default, the
    /// encoder must still route to CPU. This is the safety net
    /// users opting in get: small fixtures don't accidentally
    /// hit the GPU regression zone.
    func testGate_EnabledButBelowThreshold_RoutesToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        EncoderPipeline._gpuForward53Enabled = true
        EncoderPipeline._gpuForward53PixelThreshold = 4_000_000  // production default

        let image = syntheticImage(width: 1024, height: 1024, seed: 0xC0FE_FACE)
        let cfg = htConfig()
        J2KGPUForward53Telemetry.reset()

        _ = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        let s = J2KGPUForward53Telemetry.snapshot()
        XCTAssertEqual(s.gpuFireCount, 0,
            "GPU must NOT fire when pixel count < threshold")
        XCTAssertGreaterThan(s.cpuFireByReason[.belowThreshold] ?? 0, 0,
            "Skip reason must be below-threshold")
    }

    // MARK: - Policy: multi-tile path → CPU path (per-tile dim < 4 MP)

    /// Multi-tile encode with the gate on. Each tile's per-tile
    /// pixel count is below 4 MP for the production `.auto`
    /// layouts, so the threshold gates GPU out on every tile —
    /// CPU keeps the multi-tile fast path it owns. Phase 5
    /// measured 33–43 % GPU regression for multi-tile per-tile
    /// dispatches; the threshold protects against that.
    func testGate_MultiTilePath_RoutesPerTileToCPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        EncoderPipeline._gpuForward53Enabled = true
        EncoderPipeline._gpuForward53PixelThreshold = 4_000_000  // production default

        // DX 2800×2288 — 4×4 multi-tile = 700×572 per tile = 0.4 MP,
        // well below 4 MP. Production `.auto` would pick this.
        let image = syntheticImage(width: 2800, height: 2288, seed: 0xDEAD_BABE)
        let cfg = htConfig()
        let pipeline = EncoderPipeline(config: cfg)
        let layout = J2KTileLayout(
            cols: 4, rows: 4,
            tileWidth: (2800 + 3) / 4, tileHeight: (2288 + 3) / 4,
            imageWidth: 2800, imageHeight: 2288)

        J2KGPUForward53Telemetry.reset()
        _ = try await pipeline.encodeNativeMultiTile(image, layout: layout)

        let s = J2KGPUForward53Telemetry.snapshot()
        XCTAssertEqual(s.gpuFireCount, 0,
            "GPU must NOT fire on any multi-tile per-tile dispatch " +
            "when per-tile dim < 4 MP threshold (DX 4×4 per-tile = 0.4 MP)")
        // 16 tiles × 1 component → 16 CPU fires expected, all
        // tagged below-threshold.
        XCTAssertEqual(s.cpuFireByReason[.belowThreshold] ?? 0, 16,
            "Expected 16 below-threshold CPU fires for DX 4×4 (got " +
            "\(s.cpuFireByReason[.belowThreshold] ?? 0))")
    }

    /// Same multi-tile encode but with the threshold lowered to 1
    /// — every per-tile dispatch should THEN fire GPU. This proves
    /// the gate's threshold predicate is the load-bearing signal
    /// (the multi-tile branch isn't structurally CPU-only; it's
    /// gated by pixel count).
    func testGate_MultiTileWithLoweredThreshold_RoutesPerTileToGPU() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        EncoderPipeline._gpuForward53Enabled = true
        EncoderPipeline._gpuForward53PixelThreshold = 1  // forces GPU on every tile

        let image = syntheticImage(width: 2800, height: 2288, seed: 0xDEAD_BABE)
        let cfg = htConfig()
        let pipeline = EncoderPipeline(config: cfg)
        let layout = J2KTileLayout(
            cols: 4, rows: 4,
            tileWidth: (2800 + 3) / 4, tileHeight: (2288 + 3) / 4,
            imageWidth: 2800, imageHeight: 2288)

        J2KGPUForward53Telemetry.reset()
        _ = try await pipeline.encodeNativeMultiTile(image, layout: layout)

        let s = J2KGPUForward53Telemetry.snapshot()
        XCTAssertEqual(s.gpuFireCount, 16,
            "Expected 16 GPU fires when threshold is forced to 1 " +
            "(got \(s.gpuFireCount))")
        XCTAssertEqual(s.cpuFireByReason[.belowThreshold] ?? 0, 0,
            "No below-threshold skip when threshold = 1")
    }

    // MARK: - Policy: byte-identical when GPU disabled vs enabled

    /// CPU bytes (gate off) must be byte-identical to GPU bytes
    /// (gate on). The Phase 8 cross-codec validation already
    /// proved external decoders agree; this test is the in-process
    /// equivalent — same encoder, same config, two backends, same
    /// bytes.
    func testGate_BytesIdenticalAcrossBackends_2048x2048() async throws {
        try XCTSkipUnless(J2KMetalDWT.isAvailable, "Metal not available")

        let image = syntheticImage(width: 2048, height: 2048, seed: 0x5511_2244)
        let cfg = htConfig()

        EncoderPipeline._gpuForward53Enabled = false
        EncoderPipeline._gpuForward53PixelThreshold = 4_000_000
        let cpuBytes = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        EncoderPipeline._gpuForward53Enabled = true
        EncoderPipeline._gpuForward53PixelThreshold = 1  // force GPU
        let gpuBytes = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

        XCTAssertEqual(cpuBytes, gpuBytes,
            "CPU bytes (gate off) must equal GPU bytes (gate on, threshold=1) " +
            "for the same image + config — phase-2/4 byte-identical guarantee.")
    }

    // MARK: - Telemetry sanity: counters reset cleanly

    /// Reset must zero every counter so back-to-back tests don't
    /// see each other's counts.
    func testTelemetry_ResetClearsEverything() {
        J2KGPUForward53Telemetry.reset()
        let zero = J2KGPUForward53Telemetry.snapshot()
        XCTAssertEqual(zero.gpuFireCount, 0)
        XCTAssertEqual(zero.totalCPUFireCount, 0)
        XCTAssertEqual(zero.totalSetupMs, 0)
        XCTAssertEqual(zero.totalDispatchMs, 0)
    }
}
