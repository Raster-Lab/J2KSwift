// HTGPUForwardHTEntropyBatchBitExactTests.swift
//
// v6-alpha6 phase 1.2 — bit-exact validation of the batched
// `J2KGPUForwardHTEntropyBatch.encodeBlockBatch(...)` API.
//
// Phase 1.1 proved:
//   - GPU per-sample classifier == CPU `sampleInfo` (PR #302)
//   - Encoder consume path == CPU inline path on equal tuple inputs
//     (PR #303)
//
// Phase 1.2 ships the standalone batched API — concatenates many
// blocks into one GPU dispatch, walks the result per block on CPU.
// This test pins it: every block's output `(magsgn, mel, vlc)` byte
// tuple must equal what the CPU-only `HTBlockEncoderConformant.encode(...)`
// produces for the same block.
//
// What this test guarantees the eventual production wire-in (Phase
// 1.3) can assume:
//   1. GPU dispatch over `N` blocks gives the same per-block tuples
//      as `N` separate per-block dispatches (descriptor offset
//      arithmetic is correct).
//   2. The per-block emit step's tuple-slice extraction
//      (`UnsafeBufferPointer(start: ... + tupleStart, count: ...)`)
//      lands on the right tuples.
//   3. Mixed-shape, mixed-`p` batches encode each block correctly.
//
// Also exercises the telemetry counters end-to-end (one batch fire
// records `gpuFireCount += 1`, `gpuBlocksClassified += N`).
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class HTGPUForwardHTEntropyBatchBitExactTests: XCTestCase {

    /// CPU-only reference encode for one block. Returns the same
    /// `(magsgn, mel, vlc)` tuple shape the batched API returns per
    /// block. Builds fresh encoders per call (matches the simplest
    /// caller pattern; the batched API reuses encoders for perf, but
    /// the bytes are identical regardless).
    private func cpuEncode(coefficients: [UInt32], width: Int, height: Int,
                           missingMSBs: Int)
        -> (magsgn: [UInt8], mel: [UInt8], vlc: [UInt8])
    {
        var ms = HTMagSgnEncoderConformant()
        var ml = HTMELEncoderConformant()
        var vc = HTReverseBitEmitterConformant()
        return coefficients.withUnsafeBufferPointer { buf in
            HTBlockEncoderConformant.encode(
                coefficients: buf, width: width, height: height,
                missingMSBs: missingMSBs,
                magsgnEnc: &ms, melEnc: &ml, vlcEnc: &vc,
                useSIMDClassification: false)
        }
    }

    private func makeCoefficients(width: Int, height: Int, seed: UInt32)
        -> [UInt32]
    {
        var rng: UInt32 = seed
        var coeffs = [UInt32](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            rng = rng &* 1_103_515_245 &+ 12_345
            coeffs[i] = (rng & 0x8000_0000) | (rng & 0x3FFF_FFFF)
        }
        return coeffs
    }

    // MARK: - Tests

    /// Single-block batch — degenerate case, but exercises the
    /// descriptor-building path and confirms the API's contract for
    /// callers that always submit one block at a time.
    func testBatch_SingleBlock_BitExact() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        let coeffs = makeCoefficients(width: 64, height: 64, seed: 0xAAAA_BBBB)
        let pending = J2KGPUForwardHTEntropyBatch.PendingBlock(
            coefficients: coeffs, width: 64, height: 64, missingMSBs: 12)

        J2KGPUForwardHTEntropyTelemetry.reset()
        let encoded = try await J2KGPUForwardHTEntropyBatch.encodeBlockBatch([pending])
        let cpu = cpuEncode(coefficients: coeffs, width: 64, height: 64, missingMSBs: 12)

        XCTAssertEqual(encoded.count, 1)
        XCTAssertEqual(encoded[0].magsgn, cpu.magsgn, "MagSgn diverged")
        XCTAssertEqual(encoded[0].mel, cpu.mel, "MEL diverged")
        XCTAssertEqual(encoded[0].vlc, cpu.vlc, "VLC diverged")

        let snap = J2KGPUForwardHTEntropyTelemetry.snapshot()
        XCTAssertEqual(snap.gpuFireCount, 1)
        XCTAssertEqual(snap.gpuBlocksClassified, 1)
    }

    /// Mixed-shape, mixed-`missingMSBs` batch — the headline case.
    /// Models what production-wire-in's `applyEntropyCodingHTJ2KFused`
    /// will submit: 16+ blocks of varying sizes (one per tile-band cell)
    /// and varying `missingMSBs` (driven by per-band Kmsbs).
    func testBatch_MixedBatch_BitExact() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        let plan: [(w: Int, h: Int, missingMSBs: Int, seed: UInt32)] = [
            (64, 64, 12, 0x1010_2020),  // typical full block
            (64, 64, 18, 0x3030_4040),  // larger missingMSBs (deeper-band)
            (64, 32,  8, 0x5050_6060),  // half-height block
            (32, 32,  4, 0x7070_8080),  // quarter block
            (16, 16,  6, 0x9090_A0A0),  // tiny block (LL band edge)
            ( 8,  8,  2, 0xB0B0_C0C0),  // smaller tiny
            (40, 56, 14, 0xD0D0_E0E0),  // non-pow2 (interior partial cell)
            (24, 24,  9, 0xF0F0_1010),  // odd-mult-of-4 dims
            (64, 64,  3, 0x2222_3333),  // small missingMSBs (high-precision)
            (48, 16, 11, 0x4444_5555),  // wide-thin band edge
        ]

        var pendingBlocks: [J2KGPUForwardHTEntropyBatch.PendingBlock] = []
        var cpuExpected: [(magsgn: [UInt8], mel: [UInt8], vlc: [UInt8])] = []

        for entry in plan {
            let coeffs = makeCoefficients(width: entry.w, height: entry.h, seed: entry.seed)
            pendingBlocks.append(J2KGPUForwardHTEntropyBatch.PendingBlock(
                coefficients: coeffs,
                width: entry.w, height: entry.h,
                missingMSBs: entry.missingMSBs))
            cpuExpected.append(cpuEncode(
                coefficients: coeffs,
                width: entry.w, height: entry.h,
                missingMSBs: entry.missingMSBs))
        }

        J2KGPUForwardHTEntropyTelemetry.reset()
        let encoded = try await J2KGPUForwardHTEntropyBatch.encodeBlockBatch(pendingBlocks)
        XCTAssertEqual(encoded.count, plan.count)

        for (i, entry) in plan.enumerated() {
            let label = "block[\(i)] \(entry.w)×\(entry.h) m=\(entry.missingMSBs)"
            XCTAssertEqual(encoded[i].magsgn, cpuExpected[i].magsgn,
                "[\(label)] MagSgn diverged")
            XCTAssertEqual(encoded[i].mel, cpuExpected[i].mel,
                "[\(label)] MEL diverged")
            XCTAssertEqual(encoded[i].vlc, cpuExpected[i].vlc,
                "[\(label)] VLC diverged")
        }

        let snap = J2KGPUForwardHTEntropyTelemetry.snapshot()
        XCTAssertEqual(snap.gpuFireCount, 1, "expected one batched dispatch for the whole plan")
        XCTAssertEqual(snap.gpuBlocksClassified, plan.count,
            "telemetry blocks-classified should equal plan size")
        XCTAssertGreaterThan(snap.totalDispatchMs, 0, "non-zero dispatch ms")
        XCTAssertGreaterThan(snap.totalEmitMs, 0, "non-zero CPU emit ms")
    }

    /// 256-block batch — at-or-just-above the production
    /// `_gpuForwardHTEntropyBlockThreshold` default. Confirms the
    /// API behaves correctly at the threshold the gate uses, and
    /// gives an end-to-end wall-time data point for the design doc.
    func testBatch_AtBlockThreshold_256Blocks_BitExact() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        // 256 64×64 blocks — fills a 16×16 grid of codeblocks (≈ 1 MP
        // of total samples, similar shape to a full XA 1024² band).
        var blocks: [J2KGPUForwardHTEntropyBatch.PendingBlock] = []
        var cpuExpected: [(magsgn: [UInt8], mel: [UInt8], vlc: [UInt8])] = []
        for i in 0..<256 {
            let coeffs = makeCoefficients(width: 64, height: 64,
                                          seed: 0xC0FE_FACE &+ UInt32(i))
            let m = (i % 30)  // sweep missingMSBs across 0..29
            blocks.append(J2KGPUForwardHTEntropyBatch.PendingBlock(
                coefficients: coeffs, width: 64, height: 64,
                missingMSBs: m))
            cpuExpected.append(cpuEncode(coefficients: coeffs,
                                         width: 64, height: 64,
                                         missingMSBs: m))
        }

        J2KGPUForwardHTEntropyTelemetry.reset()
        let encoded = try await J2KGPUForwardHTEntropyBatch.encodeBlockBatch(blocks)
        XCTAssertEqual(encoded.count, 256)

        for i in 0..<256 {
            XCTAssertEqual(encoded[i].magsgn, cpuExpected[i].magsgn,
                "MagSgn diverged at block \(i)")
            XCTAssertEqual(encoded[i].mel, cpuExpected[i].mel,
                "MEL diverged at block \(i)")
            XCTAssertEqual(encoded[i].vlc, cpuExpected[i].vlc,
                "VLC diverged at block \(i)")
        }

        let snap = J2KGPUForwardHTEntropyTelemetry.snapshot()
        XCTAssertEqual(snap.gpuFireCount, 1)
        XCTAssertEqual(snap.gpuBlocksClassified, 256)
        // Diagnostic-only print: the pure-GPU dispatch + pure-CPU
        // emit ms, so future Phase 1.3 wire-in has a baseline to
        // compare against.
        print(String(format: "[batch 256 blocks] dispatch=%.2fms emit=%.2fms total=%.2fms",
            snap.totalDispatchMs, snap.totalEmitMs,
            snap.totalDispatchMs + snap.totalEmitMs))
    }

    /// Telemetry sanity — `reset()` clears every counter so back-to-
    /// back tests don't see each other's numbers.
    func testTelemetry_ResetClearsEverything() {
        J2KGPUForwardHTEntropyTelemetry.reset()
        let zero = J2KGPUForwardHTEntropyTelemetry.snapshot()
        XCTAssertEqual(zero.gpuFireCount, 0)
        XCTAssertEqual(zero.gpuBlocksClassified, 0)
        XCTAssertEqual(zero.totalCPUFireCount, 0)
        XCTAssertEqual(zero.totalDispatchMs, 0)
        XCTAssertEqual(zero.totalEmitMs, 0)
    }
}
