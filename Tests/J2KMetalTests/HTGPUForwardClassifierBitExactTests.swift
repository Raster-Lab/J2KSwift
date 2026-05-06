// HTGPUForwardClassifierBitExactTests.swift
//
// v6-alpha6 phase 1 (approach B) — bit-exact validation of the GPU
// per-sample classifier against the CPU `sampleInfo` reference.
//
// The classifier is the parallelizable half of HT-conformant forward
// entropy. Phase 1.1 will plug it into the encoder; this test is the
// bit-exactness gate that lets that integration assume the GPU
// tuples are trustworthy.
//
// What it asserts:
//
//   1. **Hand-picked edge cases** — same set the existing
//      `HTSampleInfoSIMDPrototypeTests` uses for the CPU SIMD prototype.
//      Covers zero, sign-only, magnitude-only, both, near-p
//      threshold, max value, varying p.
//
//   2. **Random-input sweep** — 64×64 codeblocks across a sweep of p
//      values (3, 5, 10, 15, 20, 25, 28, 29, 30) with deterministic
//      seeds. Per-sample tuples must match the CPU scalar reference
//      for every (sample, p) pair.
//
//   3. **Multi-block batch** — multiple codeblocks in one dispatch,
//      each with potentially different p. Confirms the per-block
//      descriptor threading is correct.
//
// All assertions are byte/bit-level; no tolerance.

import XCTest
@testable import J2KCore
@testable import J2KMetal

final class HTGPUForwardClassifierBitExactTests: XCTestCase {

    // MARK: - CPU reference (verbatim copy of the production formula)

    /// Scalar reference, copy of `sampleInfo` from
    /// `HTBlockEncoderConformant.swift`. Kept here verbatim so this
    /// test pins the GPU classifier against the exact production
    /// formula.
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

    // MARK: - Helpers

    /// Build a single-block descriptor + coefficients for `count`
    /// samples at bit-depth `p`, drawing from `seed`-deterministic LCG.
    private func makeSingleBlockBatch(count: Int, p: UInt32, seed: UInt32)
        -> (descs: [J2KMetalHTForwardClassifyDescriptor],
            coeffs: [UInt32], tupleCount: Int)
    {
        var rng: UInt32 = seed
        var coeffs = [UInt32](repeating: 0, count: count)
        for i in 0..<count {
            rng = rng &* 1_103_515_245 &+ 12_345
            // Sign + 30-bit magnitude span. p ∈ [3, 30] in tests, so
            // we want enough spread that lots of (sig, eQ, payload)
            // permutations get exercised.
            coeffs[i] = (rng & 0x8000_0000) | (rng & 0x3FFF_FFFF)
        }
        let desc = J2KMetalHTForwardClassifyDescriptor(
            coeffOffset: 0, tupleOffset: 0,
            sampleCount: UInt32(count), p: p)
        return (descs: [desc], coeffs: coeffs, tupleCount: count)
    }

    /// Run the GPU classifier and compare every output tuple against
    /// the CPU scalar reference, asserting bit-exactness.
    private func assertGPUMatchesCPU(
        descs: [J2KMetalHTForwardClassifyDescriptor],
        coeffs: [UInt32], tupleCount: Int,
        label: String
    ) async throws {
        let classifier = J2KMetalHTForwardClassifier()
        let gpuTuples = try await classifier.classify(
            descriptors: descs, coefficients: coeffs, tupleCount: tupleCount)
        XCTAssertEqual(gpuTuples.count, tupleCount,
            "[\(label)] GPU returned \(gpuTuples.count) tuples, expected \(tupleCount)")

        for desc in descs {
            for i in 0..<Int(desc.sampleCount) {
                let coeffIdx = Int(desc.coeffOffset) + i
                let tupleIdx = Int(desc.tupleOffset) + i
                let t = coeffs[coeffIdx]
                let cpu = Self.sampleInfoScalar(t, p: desc.p)
                let gpu = J2KMetalHTForwardClassifierTuple.unpack(gpuTuples[tupleIdx])
                if cpu.sig != gpu.sig
                    || cpu.eQ != gpu.eQ
                    || cpu.payload != gpu.payload
                {
                    XCTFail("[\(label)] mismatch at sample \(i) " +
                            "(t=0x\(String(t, radix: 16)) p=\(desc.p)): " +
                            "cpu=(sig=\(cpu.sig), eQ=\(cpu.eQ), payload=\(cpu.payload)) " +
                            "gpu=(sig=\(gpu.sig), eQ=\(gpu.eQ), payload=\(gpu.payload))")
                    return
                }
            }
        }
    }

    // MARK: - Tests

    /// Hand-picked edge cases — same set as `HTSampleInfoSIMDPrototypeTests`.
    func testForwardClassifier_BitExact_EdgeCases() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        let inputs: [(t: UInt32, p: UInt32)] = [
            (0,            5),
            (0,            30),
            (0x8000_0000,  5),    // sign only, mag below p
            (0x0000_0001,  5),
            (0x0000_0010,  5),
            (0x0000_FFFF,  5),
            (0x000F_FFFF,  5),
            (0xFFFF_FFFF, 30),
            (0x4000_0000,  5),    // near-MSB
            (0xC000_0000,  5),    // sign + near-MSB
            (0x0010_0000, 10),
            (0x0010_0000, 20),
            (0x7FFF_FFFF,  5),
            (0x7FFF_FFFF, 30),
            (0x1234_5678,  7),
            (0xDEAD_BEEF, 11),
        ]

        // Group by p so each block is mono-p (the kernel descriptor
        // carries one p per block).
        var byP: [UInt32: [UInt32]] = [:]
        for (t, p) in inputs { byP[p, default: []].append(t) }

        for (p, ts) in byP {
            var descs: [J2KMetalHTForwardClassifyDescriptor] = []
            var coeffs: [UInt32] = []
            var tupleOffset: UInt32 = 0
            for t in ts {
                descs.append(J2KMetalHTForwardClassifyDescriptor(
                    coeffOffset: UInt32(coeffs.count),
                    tupleOffset: tupleOffset,
                    sampleCount: 1, p: p))
                coeffs.append(t)
                tupleOffset += 1
            }
            try await assertGPUMatchesCPU(
                descs: descs, coeffs: coeffs, tupleCount: Int(tupleOffset),
                label: "edge p=\(p)")
        }
    }

    /// Random-input sweep — 64×64 codeblock per p value across the p
    /// range tested by the existing CPU SIMD prototype.
    func testForwardClassifier_BitExact_RandomCodeblockSweep() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        let pValues: [UInt32] = [3, 5, 10, 15, 20, 25, 28, 29, 30]
        for p in pValues {
            // Two seeds per p for some breadth; each is 64×64 = 4096
            // samples, so 8192 (sample, p) pairs per p.
            for seed: UInt32 in [0xDEAD_BEEF, 0xC0FE_FACE] {
                let (descs, coeffs, tupleCount) =
                    makeSingleBlockBatch(count: 64 * 64, p: p, seed: seed)
                try await assertGPUMatchesCPU(
                    descs: descs, coeffs: coeffs, tupleCount: tupleCount,
                    label: "p=\(p) seed=0x\(String(seed, radix: 16))")
            }
        }
    }

    /// Multi-block batch — confirms per-block descriptor offset
    /// threading is correct when several blocks fire in one dispatch
    /// at potentially different p values.
    func testForwardClassifier_BitExact_MultiBlockBatch() async throws {
        try XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, "Metal not available")

        // 5 blocks: 32×32 / 16×16 / 64×64 / 8×8 / 64×64, p varying.
        let plan: [(w: Int, h: Int, p: UInt32, seed: UInt32)] = [
            (32, 32,  5, 0x1111_2222),
            (16, 16, 10, 0x3333_4444),
            (64, 64, 15, 0x5555_6666),
            ( 8,  8, 20, 0x7777_8888),
            (64, 64, 25, 0x9999_AAAA),
        ]

        var descs: [J2KMetalHTForwardClassifyDescriptor] = []
        var coeffs: [UInt32] = []
        var tupleOffset: UInt32 = 0
        for entry in plan {
            let n = entry.w * entry.h
            var rng = entry.seed
            for _ in 0..<n {
                rng = rng &* 1_103_515_245 &+ 12_345
                coeffs.append((rng & 0x8000_0000) | (rng & 0x3FFF_FFFF))
            }
            descs.append(J2KMetalHTForwardClassifyDescriptor(
                coeffOffset: UInt32(coeffs.count - n),
                tupleOffset: tupleOffset,
                sampleCount: UInt32(n), p: entry.p))
            tupleOffset += UInt32(n)
        }

        try await assertGPUMatchesCPU(
            descs: descs, coeffs: coeffs, tupleCount: Int(tupleOffset),
            label: "multi-block 5-cell")
    }
}
