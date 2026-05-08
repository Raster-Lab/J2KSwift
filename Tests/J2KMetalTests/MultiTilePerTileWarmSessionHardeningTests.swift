// MultiTilePerTileWarmSessionHardeningTests.swift
//
// v7.1.0 K1 — multi-tile per-tile warm-session hardening.
//
// The infrastructure for warm-session reuse across tiles in a multi-
// tile per-tile decode already exists: `J2KDecoder.decode(_:)` /
// `decodeGPU(_:)` set `pipeline.metalSession = J2KMetalSession.processShared`
// before invoking `decodeMultiTileGPU`, which spawns per-tile work
// inside `withThrowingTaskGroup` — every per-tile task captures the
// pipeline (and thus the session) by reference. `decodeTilePayloadGPU`
// hands the shared session's `device`, `bufferPool`, and
// `shaderLibrary` into every `J2KMetalDWT` it constructs.
//
// **What's missing — and what K1 closes — is the regression-guard
// contract that all of the above is in fact happening.** Future
// changes (e.g. adding a new GPU stage to `decodeTilePayloadGPU`)
// could silently introduce per-tile session / device / library /
// pool reconstruction; the cold-start cost is ~25-30 ms per Metal
// init (per `project_gpu97_warm_session_ceiling.md`). For a DX 4x4
// multi-tile decode with 16 tiles, that's a hidden ~480 ms regression.
//
// This test class pins three explicit invariants:
//
//   1. **Singleton stability** — `J2KMetalSession.processShared`'s
//      `device`, `shaderLibrary`, and `bufferPool` must be stable
//      object identities before vs after a multi-tile decode.
//      Trivially holds for the singleton design but catches
//      future drift if the singleton is ever replaced or wrapped.
//
//   2. **Repeated-decode buffer-pool amortisation** — running the
//      same multi-tile decode three times in a row must NOT triple
//      the `J2KMetalUMACounters.makeBufferCount` total. Once the
//      pool is warmed by the first decode, subsequent decodes
//      should reuse pooled buffers; runs 2 + 3 should add only a
//      small overhead. Catches the case where someone adds a new
//      GPU stage that bypasses the pool and pays per-decode
//      `makeBuffer` calls.
//
//   3. **Cross-tile buffer-pool amortisation** — within a single
//      multi-tile decode, makeBuffer count must NOT scale linearly
//      with tile count. Catches per-tile session / device / pool
//      reconstruction (the "K1 hardening" target).

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MultiTilePerTileWarmSessionHardeningTests: XCTestCase {

    // MARK: - Fixture loading

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

    /// Build a multi-tile codestream from `dx_study_002_instance_000001.pgm`
    /// at the given tile mode. Used for the corpus-shape regression
    /// gate — the DX fixture is the headline production case (6.4 MP,
    /// 16-bit, 4–16 tiles) where a per-tile warm-session miss would
    /// cost the most.
    private func makeMultiTileCodestream(
        mode: J2KHTTileMode
    ) async throws -> Data? {
        guard let image = loadPGM16("dx_study_002_instance_000001.pgm") else {
            return nil
        }
        let cfg = htConfig()
        let layout = J2KEncodeTilePlanner.plan(
            imageWidth: image.width, imageHeight: image.height,
            decompositionLevels: 5, mode: mode)
        XCTAssertTrue(layout.isMultiTile, "DX fixture must produce multi-tile layout for \(mode)")
        let result = try await J2KMultiTileEncoder.encode(
            image: image, layout: layout, configuration: cfg)
        return result.codestream
    }

    // MARK: - Invariant 1: singleton stability

    /// `J2KMetalSession.processShared` exposes the same `device`,
    /// `shaderLibrary`, and `bufferPool` instances before and after
    /// a multi-tile decode. Trivial for the singleton; the test
    /// exists so a future refactor that breaks the singleton has to
    /// explicitly update this assertion.
    func testProcessShared_DeviceLibraryPool_StableAcrossMultiTileDecode() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        guard let codestream = try await makeMultiTileCodestream(mode: .tiles2x2) else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }

        try await J2KMetalSession.processShared.preWarm()
        let session = J2KMetalSession.processShared
        let beforeDevice = session.device
        let beforeLibrary = session.shaderLibrary
        let beforePool = session.bufferPool

        _ = try await J2KDecoder().decodeGPU(codestream)

        XCTAssertTrue(session.device === beforeDevice,
            "processShared.device must remain the same instance across multi-tile decode")
        XCTAssertTrue(session.shaderLibrary === beforeLibrary,
            "processShared.shaderLibrary must remain the same instance")
        XCTAssertTrue(session.bufferPool === beforePool,
            "processShared.bufferPool must remain the same instance")
    }

    // MARK: - Invariant 2: repeated-decode buffer-pool amortisation

    /// Three back-to-back multi-tile decodes of the same DX 2x2 (4
    /// tiles) codestream must NOT make a large number of new buffers.
    ///
    /// In steady state the buffer pool serves all per-tile working
    /// buffers from cached entries → makeBuffer count stays at or
    /// near zero. A regression that introduces per-tile session /
    /// pool reconstruction would call `MTLDevice.makeBuffer` on
    /// every tile of every decode (12 tile-decodes × per-tile-init
    /// budget ≈ 60-240 buffers), crossing the absolute cap.
    ///
    /// Cap: 32 makeBuffer calls across 3 decodes of 4 tiles each
    /// = 12 tile-decodes. ~3 buffers per tile-decode worst-case.
    func testRepeatedMultiTileDecode_PoolAmortises() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        guard let codestream = try await makeMultiTileCodestream(mode: .tiles2x2) else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }

        // Warm the session + run one warmup decode so the pool's
        // first-decode allocation cost isn't part of the measurement.
        try await J2KMetalSession.processShared.preWarm()
        _ = try await J2KDecoder().decodeGPU(codestream)

        J2KMetalUMACounters.reset()
        _ = try await J2KDecoder().decodeGPU(codestream)
        _ = try await J2KDecoder().decodeGPU(codestream)
        _ = try await J2KDecoder().decodeGPU(codestream)
        let totalNewBuffers = J2KMetalUMACounters.snapshot().makeBufferCount

        // Absolute cap rather than a ratio — steady-state reuse
        // typically yields 0 new makeBuffer calls; a regression that
        // bypasses the pool per tile would scale linearly with
        // tile-decodes × per-tile budget and cross 32.
        XCTAssertLessThan(totalNewBuffers, 32,
            "Multi-tile per-tile warm-session reuse regression: " +
            "3 × 4-tile decodes made \(totalNewBuffers) new MTLBuffers " +
            "(steady-state expectation: 0). A pool / session " +
            "reconstruction in the per-tile decode chain would scale " +
            "with tile-decodes × per-tile init budget.")

        print("[K1] DX 2x2 × 3 decodes makeBuffer total = \(totalNewBuffers) (cap 32, ideal 0)")
    }

    // MARK: - Invariant 3: cross-tile buffer-pool amortisation

    /// Within a single multi-tile decode, the makeBuffer count must
    /// NOT scale linearly with tile count. DX at `2x2` (4 tiles) and
    /// DX at `4x4` (16 tiles) decode the same total pixel area, so
    /// per-tile session / pool reconstruction would multiply 4x4's
    /// makeBuffer count by ~4× vs 2x2's.
    ///
    /// Asserts an **absolute cap** rather than a ratio because the
    /// expected steady-state value is 0 (full pool reuse). Cap = 32
    /// even on the 16-tile case is well below the linear-scaling
    /// regression signature (16 × per-tile-init budget ≈ 80-320).
    func testCrossTile_BufferPool_AmortisesAcrossTilesInOneDecode() async throws {
        try XCTSkipUnless(J2KMetalSession.isAvailable, "Metal not available")
        guard let cs2x2 = try await makeMultiTileCodestream(mode: .tiles2x2),
              let cs4x4 = try await makeMultiTileCodestream(mode: .tiles4x4)
        else {
            throw XCTSkip("DX 2800×2288 fixture not present")
        }

        // Warm session + pool to steady state with one decode of each.
        try await J2KMetalSession.processShared.preWarm()
        _ = try await J2KDecoder().decodeGPU(cs2x2)
        _ = try await J2KDecoder().decodeGPU(cs4x4)

        // 2x2 measurement (4 tiles).
        J2KMetalUMACounters.reset()
        _ = try await J2KDecoder().decodeGPU(cs2x2)
        let count2x2 = J2KMetalUMACounters.snapshot().makeBufferCount

        // 4x4 measurement (16 tiles).
        J2KMetalUMACounters.reset()
        _ = try await J2KDecoder().decodeGPU(cs4x4)
        let count4x4 = J2KMetalUMACounters.snapshot().makeBufferCount

        XCTAssertLessThan(count2x2, 32,
            "DX 2x2 (4 tiles) made \(count2x2) new MTLBuffers in one " +
            "warm-session decode (cap 32, ideal 0).")
        XCTAssertLessThan(count4x4, 32,
            "DX 4x4 (16 tiles) made \(count4x4) new MTLBuffers in one " +
            "warm-session decode (cap 32, ideal 0). Linear-scaling regression " +
            "would yield ≈ 4× the 2x2 count of \(count2x2).")

        print("[K1] DX 2x2 (4 tiles) makeBuffer = \(count2x2); " +
              "DX 4x4 (16 tiles) makeBuffer = \(count4x4) (cap 32 each)")
    }
}
