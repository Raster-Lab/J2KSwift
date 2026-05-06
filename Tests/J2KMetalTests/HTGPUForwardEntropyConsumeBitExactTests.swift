// HTGPUForwardEntropyConsumeBitExactTests.swift
//
// v6-alpha6 phase 1.1 — bit-exact validation of the encoder's
// pre-classified-tuple consume path.
//
// Two orthogonal correctness gates land here:
//
//   1. **CPU-only A/B**: encode-with-CPU-classification vs
//      encode-with-pre-classified-tuples (where tuples come from the
//      same CPU `sampleInfo` formula, hand-rolled in this test).
//      Proves the consume path doesn't drift from the inline path.
//      This isolates the encoder change from the GPU classifier;
//      if this fails, the bug is in `processQuadFromTuples` /
//      `sampleInfoFromTuple`, not in the GPU kernel.
//
//   2. **End-to-end**: encode-with-CPU-inline vs encode-with-
//      GPU-classified-tuples. Proves the full Phase 1.1 pipeline
//      (GPU classifier → CPU emit-from-tuples) is byte-identical to
//      the existing scalar path on every fixture / parameter
//      combination.
//
// Codestream bytes are part of the lossless contract. Any drift here
// means cross-codec validation would fail downstream — so this test
// is the gate that lets Phase 1.2 (production wire-in behind a
// gate flag) assume safety.
//

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class HTGPUForwardEntropyConsumeBitExactTests: XCTestCase {

    // MARK: - CPU classifier (verbatim copy of the production formula)

    /// Scalar reference, copy of `sampleInfo` from
    /// `HTBlockEncoderConformant.swift`. Verbatim so this test pins
    /// the consume path against the exact production formula.
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

    /// Pack `(sig, eQ, payload)` into the kernel's tuple format —
    /// `sig:1 | reserved:24 | eQ:7 | payload:32`. Mirrors what the
    /// GPU kernel emits.
    @inline(__always)
    private static func packTuple(sig: Bool, eQ: UInt32, payload: UInt32) -> UInt64 {
        guard sig else { return 0 }
        return (1 << 63)
             | ((UInt64(eQ) & 0x7F) << 56)
             | UInt64(payload)
    }

    /// Compute per-sample tuples for a codeblock using the CPU
    /// reference (hand-rolled here so the test doesn't depend on
    /// implementation details of the production encoder's nested
    /// `sampleInfo`).
    private func cpuClassify(coefficients: [UInt32], width: Int, height: Int,
                             p: UInt32) -> [UInt64] {
        var tuples = [UInt64](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            let info = Self.sampleInfoScalar(coefficients[i], p: p)
            tuples[i] = Self.packTuple(sig: info.sig, eQ: info.eQ, payload: info.payload)
        }
        return tuples
    }

    // MARK: - Helpers

    /// Generate a deterministic codeblock of `width × height` samples
    /// with a sign bit + 30-bit magnitude — typical post-DWT shape
    /// for medical inputs.
    private func makeCoefficients(width: Int, height: Int, seed: UInt32) -> [UInt32] {
        var rng: UInt32 = seed
        var coeffs = [UInt32](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            rng = rng &* 1_103_515_245 &+ 12_345
            coeffs[i] = (rng & 0x8000_0000) | (rng & 0x3FFF_FFFF)
        }
        return coeffs
    }

    /// Run both encode paths and return their byte-tuples.
    private func encodeBoth(coefficients: [UInt32],
                            width: Int, height: Int,
                            missingMSBs: Int,
                            preClassifiedTuples: [UInt64])
        -> (inline: (magsgn: [UInt8], mel: [UInt8], vlc: [UInt8]),
            consume: (magsgn: [UInt8], mel: [UInt8], vlc: [UInt8]))
    {
        // Inline path (production scalar `sampleInfo`).
        var magInline = HTMagSgnEncoderConformant()
        var melInline = HTMELEncoderConformant()
        var vlcInline = HTReverseBitEmitterConformant()
        let inline = coefficients.withUnsafeBufferPointer { coeffs in
            HTBlockEncoderConformant.encode(
                coefficients: coeffs, width: width, height: height,
                missingMSBs: missingMSBs,
                magsgnEnc: &magInline, melEnc: &melInline, vlcEnc: &vlcInline,
                useSIMDClassification: false)
        }

        // Consume path (reads pre-classified tuples).
        var magConsume = HTMagSgnEncoderConformant()
        var melConsume = HTMELEncoderConformant()
        var vlcConsume = HTReverseBitEmitterConformant()
        let consume = coefficients.withUnsafeBufferPointer { coeffs in
            preClassifiedTuples.withUnsafeBufferPointer { tuples in
                HTBlockEncoderConformant.encode(
                    coefficients: coeffs, width: width, height: height,
                    missingMSBs: missingMSBs,
                    magsgnEnc: &magConsume, melEnc: &melConsume, vlcEnc: &vlcConsume,
                    useSIMDClassification: false,
                    preClassifiedTuples: tuples)
            }
        }
        return (inline, consume)
    }

    private func assertBytesEqual(
        _ inline: (magsgn: [UInt8], mel: [UInt8], vlc: [UInt8]),
        _ consume: (magsgn: [UInt8], mel: [UInt8], vlc: [UInt8]),
        label: String
    ) {
        XCTAssertEqual(inline.magsgn, consume.magsgn,
            "[\(label)] MagSgn bytes diverged")
        XCTAssertEqual(inline.mel, consume.mel,
            "[\(label)] MEL bytes diverged")
        XCTAssertEqual(inline.vlc, consume.vlc,
            "[\(label)] VLC bytes diverged")
    }

    // MARK: - Test 1: CPU-only A/B (consume path correctness)

    /// Encode-with-CPU-classification vs encode-with-CPU-pre-classified-
    /// tuples. Both use the same `sampleInfo` formula; only the call
    /// path differs. Proves the encoder's `processQuadFromTuples` path
    /// produces byte-identical output to `processQuad`.
    func testConsumePath_CPU_AB_BitExactBytes() {
        let cases: [(width: Int, height: Int, missingMSBs: Int, seed: UInt32, label: String)] = [
            (16, 16, 4,  0x1111_2222, "16×16 m=4"),
            (32, 32, 8,  0x3333_4444, "32×32 m=8"),
            (64, 64, 12, 0x5555_6666, "64×64 m=12"),
            (64, 64, 18, 0x7777_8888, "64×64 m=18"),
            ( 8,  4, 2,  0x9999_AAAA, "8×4 m=2 (small/odd shape)"),
            (24, 32, 6,  0xBBBB_CCCC, "24×32 m=6 (non-pow2 width)"),
        ]

        for c in cases {
            let coeffs = makeCoefficients(width: c.width, height: c.height, seed: c.seed)
            let p = UInt32(30 - c.missingMSBs)
            let tuples = cpuClassify(coefficients: coeffs,
                                     width: c.width, height: c.height, p: p)
            let result = encodeBoth(coefficients: coeffs,
                                    width: c.width, height: c.height,
                                    missingMSBs: c.missingMSBs,
                                    preClassifiedTuples: tuples)
            assertBytesEqual(result.inline, result.consume, label: c.label)
        }
    }

    // MARK: - Test 2: End-to-end (GPU classifier + consume)

    /// GPU classifier produces the tuple stream + encoder consumes it
    /// → bytes must match the CPU-only inline encode for the same
    /// codeblock.
    func testConsumePath_GPUClassify_BitExactVsCPUInline() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        let cases: [(width: Int, height: Int, missingMSBs: Int, seed: UInt32, label: String)] = [
            (32, 32, 8,  0xAAAA_BBBB, "32×32 m=8 (single-block)"),
            (64, 64, 12, 0xCCCC_DDDD, "64×64 m=12 (single-block)"),
        ]

        let classifier = J2KMetalHTForwardClassifier()

        for c in cases {
            let coeffs = makeCoefficients(width: c.width, height: c.height, seed: c.seed)
            let p = UInt32(30 - c.missingMSBs)
            let descriptor = J2KMetalHTForwardClassifyDescriptor(
                coeffOffset: 0, tupleOffset: 0,
                sampleCount: UInt32(c.width * c.height),
                p: p)
            let gpuTuples = try await classifier.classify(
                descriptors: [descriptor],
                coefficients: coeffs,
                tupleCount: c.width * c.height)

            let result = encodeBoth(coefficients: coeffs,
                                    width: c.width, height: c.height,
                                    missingMSBs: c.missingMSBs,
                                    preClassifiedTuples: gpuTuples)
            assertBytesEqual(result.inline, result.consume, label: c.label)
        }
    }

    // MARK: - Test 3: Multi-block batch (GPU dispatches all blocks at
    //                                   once, encoder consumes per-block slices)

    /// Multi-block: classify several codeblocks in a single GPU
    /// dispatch, then encode each block from its slice of the tuple
    /// stream. Proves the per-block tuple-offset threading is correct
    /// when the consume path operates on a sub-range of a shared
    /// tuple buffer.
    func testConsumePath_GPUClassify_MultiBlockBatch_BitExact() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        let plan: [(w: Int, h: Int, missingMSBs: Int, seed: UInt32)] = [
            (32, 32,  8, 0x1010_2020),
            (16, 16,  4, 0x3030_4040),
            (64, 64, 12, 0x5050_6060),
            ( 8,  8,  6, 0x7070_8080),
        ]

        // Build descriptor batch + concatenated coefficient pool.
        var descs: [J2KMetalHTForwardClassifyDescriptor] = []
        var coeffs: [UInt32] = []
        var coeffOff: UInt32 = 0
        var tupleOff: UInt32 = 0
        for entry in plan {
            let blockCoeffs = makeCoefficients(width: entry.w, height: entry.h, seed: entry.seed)
            coeffs.append(contentsOf: blockCoeffs)
            descs.append(J2KMetalHTForwardClassifyDescriptor(
                coeffOffset: coeffOff,
                tupleOffset: tupleOff,
                sampleCount: UInt32(entry.w * entry.h),
                p: UInt32(30 - entry.missingMSBs)))
            coeffOff += UInt32(entry.w * entry.h)
            tupleOff += UInt32(entry.w * entry.h)
        }

        let classifier = J2KMetalHTForwardClassifier()
        let gpuTuples = try await classifier.classify(
            descriptors: descs,
            coefficients: coeffs,
            tupleCount: Int(tupleOff))

        // Per-block A/B: extract this block's coeffs + tuples, encode
        // both ways, assert bytes equal.
        for (i, entry) in plan.enumerated() {
            let n = entry.w * entry.h
            let coeffStart = Int(descs[i].coeffOffset)
            let tupleStart = Int(descs[i].tupleOffset)
            let blockCoeffs = Array(coeffs[coeffStart..<(coeffStart + n)])
            let blockTuples = Array(gpuTuples[tupleStart..<(tupleStart + n)])
            let result = encodeBoth(coefficients: blockCoeffs,
                                    width: entry.w, height: entry.h,
                                    missingMSBs: entry.missingMSBs,
                                    preClassifiedTuples: blockTuples)
            assertBytesEqual(result.inline, result.consume,
                             label: "block[\(i)] \(entry.w)×\(entry.h) m=\(entry.missingMSBs)")
        }
    }
}
