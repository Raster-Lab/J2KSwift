// MetalHTForwardCleanupPassEmitTests.swift
//
// v7.1.0 I1.3b — bit-exact validation of the unified Pass 3
// cleanup-pass kernel against the CPU `preClassifiedTuples` path.
//
// The kernel is a direct port of
// `HTBlockEncoderConformant.encode(preClassifiedTuples:)` to MSL.
// To validate, this test:
//
//   1. Generates coefficients for a hand-picked or seeded codeblock.
//   2. Runs the CPU classifier (`sampleInfoScalar`) per sample,
//      packing the (sig, eQ, payload) tuple into the same UInt64
//      format the GPU classifier emits (sig:1 | eQ:7 | payload:32,
//      bits 32-55 unused).
//   3. Calls `HTBlockEncoderConformant.encode(preClassifiedTuples:)`
//      with those tuples → expected (magsgn, mel, vlc) bytes.
//   4. Calls `J2KGPUForwardHTCleanupPassEmit.emitBlock(tuples:...)`
//      with the same tuples → GPU (magsgn, mel, vlc) bytes.
//   5. Asserts every stream is byte-identical.
//
// Edge cases: all-zero block, all-significant uniform block, single
// non-zero coefficient at various positions, hand-picked
// pattern from the existing CPU encoder tests, randomised sweeps.

import XCTest
@testable import J2KCodec
@testable import J2KMetal

final class MetalHTForwardCleanupPassEmitTests: XCTestCase {

    // MARK: - CPU sample classifier (mirror of HTBlockEncoderConformant.sampleInfo)

    @inline(__always)
    private static func sampleInfoScalar(_ t: UInt32, p: UInt32)
        -> (sig: Bool, eQ: UInt32, payload: UInt32)
    {
        var val = (t &+ t) >> p
        val &= ~UInt32(1)
        if val == 0 { return (false, 0, 0) }
        val &-= 1
        let lz = val.leadingZeroBitCount
        let eQ = UInt32(32 - lz)
        let sign = UInt32((t >> 31) & 1)
        let payload = (val &- 1) &+ sign
        return (true, eQ, payload)
    }

    /// Pack a (sig, eQ, payload) tuple into the UInt64 format both
    /// the GPU classifier emits and `processQuadFromTuples` consumes.
    @inline(__always)
    private static func packTuple(sig: Bool, eQ: UInt32, payload: UInt32) -> UInt64 {
        var raw: UInt64 = 0
        if sig { raw |= UInt64(1) << 63 }
        raw |= UInt64(eQ & 0x7F) << 56
        raw |= UInt64(payload)
        return raw
    }

    /// Build the per-sample tuple stream from coefficients + p.
    private static func buildTuples(
        coefficients: [UInt32], width: Int, height: Int, missingMSBs: Int
    ) -> [UInt64] {
        let p = UInt32(30 - missingMSBs)
        var tuples = [UInt64](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let t = coefficients[y * width + x]
                let info = sampleInfoScalar(t, p: p)
                tuples[y * width + x] = packTuple(
                    sig: info.sig, eQ: info.eQ, payload: info.payload)
            }
        }
        return tuples
    }

    // MARK: - Helpers

    private func runAndCompare(coefficients: [UInt32],
                               width: Int, height: Int, missingMSBs: Int,
                               label: String,
                               file: StaticString = #filePath,
                               line: UInt = #line) async throws {
        let tuples = Self.buildTuples(
            coefficients: coefficients, width: width, height: height,
            missingMSBs: missingMSBs)

        // CPU expected output
        let (cpuMS, cpuMEL, cpuVLC) = tuples.withUnsafeBufferPointer { tupleBuf in
            coefficients.withUnsafeBufferPointer { coefBuf in
                var msEnc = HTMagSgnEncoderConformant()
                var melEnc = HTMELEncoderConformant()
                var vlcEnc = HTReverseBitEmitterConformant()
                return HTBlockEncoderConformant.encode(
                    coefficients: coefBuf,
                    width: width, height: height, missingMSBs: missingMSBs,
                    magsgnEnc: &msEnc, melEnc: &melEnc, vlcEnc: &vlcEnc,
                    useSIMDClassification: false,
                    preClassifiedTuples: tupleBuf)
            }
        }

        // GPU output
        let gpu = try await J2KGPUForwardHTCleanupPassEmit().emitBlock(
            tuples: tuples, width: width, height: height, missingMSBs: missingMSBs)

        XCTAssertEqual(gpu.magsgn, cpuMS,
            "[\(label)] MagSgn divergence (cpu=\(cpuMS.count) gpu=\(gpu.magsgn.count))",
            file: file, line: line)
        XCTAssertEqual(gpu.mel, cpuMEL,
            "[\(label)] MEL divergence (cpu=\(cpuMEL.count) gpu=\(gpu.mel.count))",
            file: file, line: line)
        XCTAssertEqual(gpu.vlc, cpuVLC,
            "[\(label)] VLC divergence (cpu=\(cpuVLC.count) gpu=\(gpu.vlc.count))",
            file: file, line: line)
    }

    // MARK: - Edge cases

    func testAllZero4x4Block() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        try await runAndCompare(
            coefficients: [UInt32](repeating: 0, count: 16),
            width: 4, height: 4, missingMSBs: 0,
            label: "all-zero 4x4")
    }

    func testHandPicked4x4Block_FewSignificant() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        var coefs = [UInt32](repeating: 0, count: 16)
        coefs[0] = 0x0000_0004        // +4
        coefs[5] = 0x0000_0002        // +2
        coefs[10] = 0x8000_0008       // -8
        try await runAndCompare(
            coefficients: coefs, width: 4, height: 4, missingMSBs: 0,
            label: "hand-picked 4x4")
    }

    func testUniformHighMagnitude4x4() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        try await runAndCompare(
            coefficients: [UInt32](repeating: 0x0000_0010, count: 16),
            width: 4, height: 4, missingMSBs: 0,
            label: "uniform 0x10 4x4")
    }

    func testSingleSignificantCornerSample() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        // (3,3) — far corner of a 4x4 block.
        var coefs = [UInt32](repeating: 0, count: 16)
        coefs[15] = 0x0000_0040
        try await runAndCompare(
            coefficients: coefs, width: 4, height: 4, missingMSBs: 0,
            label: "single corner sample 4x4")
    }

    // MARK: - Various block sizes (smoke + dimension coverage)

    func testDimensionSweep() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        for (w, h) in [(4, 4), (8, 8), (16, 16), (32, 32), (4, 8), (8, 4),
                       (16, 32), (1, 1), (2, 2), (1, 4), (4, 1)] {
            // Mix of zero + significant; uses an LCG-derived pattern
            // so the test is deterministic but exercises non-trivial
            // bit patterns at every dimension.
            var rng: UInt32 = 0xA5A5_A5A5
            var coefs = [UInt32](repeating: 0, count: w * h)
            for i in 0..<(w * h) {
                rng = rng &* 1_103_515_245 &+ 12_345
                // Sparse: ~25 % of samples significant, magnitudes < 0x100
                if (rng & 0xFF) < 64 {
                    coefs[i] = (rng & 0x8000_0000) | UInt32(rng & 0xFF)
                }
            }
            try await runAndCompare(
                coefficients: coefs, width: w, height: h, missingMSBs: 0,
                label: "\(w)x\(h) sparse")
        }
    }

    // MARK: - Random sweep on 32×32 blocks (typical HT codeblock size)

    func testRandomized32x32Blocks_Seeded() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        for seed in [UInt32(0xA1B2_C3D4),
                     UInt32(0xCAFE_F00D),
                     UInt32(0xDEAD_BEEF)] {
            var rng = seed
            var coefs = [UInt32](repeating: 0, count: 32 * 32)
            for i in 0..<(32 * 32) {
                rng = rng &* 1_103_515_245 &+ 12_345
                // Mix of magnitudes including some near-zero and
                // some that exercise high-magnitude code paths.
                if (rng & 0x3F) < 32 {
                    coefs[i] = (rng & 0x8000_0000) | UInt32(rng & 0x3FFF_FFFF)
                }
            }
            try await runAndCompare(
                coefficients: coefs, width: 32, height: 32, missingMSBs: 0,
                label: "random 32x32 seed=\(String(seed, radix: 16))")
        }
    }

    // MARK: - Max-size stress (64×64 — J2K HT codeblock max)

    func testRandomized64x64Block_MaxBlockSize() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        var rng: UInt32 = 0xBADC_0DE0
        var coefs = [UInt32](repeating: 0, count: 64 * 64)
        for i in 0..<(64 * 64) {
            rng = rng &* 1_103_515_245 &+ 12_345
            if (rng & 0x3F) < 32 {
                coefs[i] = (rng & 0x8000_0000) | UInt32(rng & 0x3FFF_FFFF)
            }
        }
        try await runAndCompare(
            coefficients: coefs, width: 64, height: 64, missingMSBs: 0,
            label: "max-size 64x64 random")
    }

    // MARK: - missingMSBs sweep — exercises p ∈ {25..30}

    func testMissingMSBsSweep_4x4() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        let coefs: [UInt32] = [
            0x0000_1234, 0x0000_5678, 0x0000_9ABC, 0x0000_DEF0,
            0x8000_1111, 0x0000_2222, 0x8000_3333, 0x0000_4444,
            0x0000_5555, 0x8000_6666, 0x0000_7777, 0x0000_8888,
            0x8000_9999, 0x0000_AAAA, 0x0000_BBBB, 0x0000_CCCC,
        ]
        for missingMSBs in [0, 5, 10, 15, 20] {
            try await runAndCompare(
                coefficients: coefs, width: 4, height: 4,
                missingMSBs: missingMSBs,
                label: "missingMSBs=\(missingMSBs)")
        }
    }
}
