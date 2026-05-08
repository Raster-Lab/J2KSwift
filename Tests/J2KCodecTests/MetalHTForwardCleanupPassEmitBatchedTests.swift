// MetalHTForwardCleanupPassEmitBatchedTests.swift
//
// v7.1.0 I1.3c — bit-exact validation of the **batched** unified
// Pass 3 cleanup-pass kernel against the CPU `preClassifiedTuples`
// path. Mirrors `MetalHTForwardCleanupPassEmitTests` (which uses
// the single-block convenience wrapper) but exercises the multi-
// block production-shape dispatch:
//
//   - Heterogeneous batches (different widths/heights/missingMSBs
//     per block in the same dispatch)
//   - Large batches (~256 blocks) to stress the GPU scheduler and
//     verify per-block region offsetting works at scale
//   - Microbenchmark at N=2,300 blocks (DX 2x2 per-tile typical)
//
// The single-block emit API is now a thin wrapper over emitBlocks;
// this test exists to cover the multi-block API directly.

import XCTest
@testable import J2KCodec
@testable import J2KMetal

final class MetalHTForwardCleanupPassEmitBatchedTests: XCTestCase {

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

    @inline(__always)
    private static func packTuple(sig: Bool, eQ: UInt32, payload: UInt32) -> UInt64 {
        var raw: UInt64 = 0
        if sig { raw |= UInt64(1) << 63 }
        raw |= UInt64(eQ & 0x7F) << 56
        raw |= UInt64(payload)
        return raw
    }

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

    /// Generate a deterministic pseudo-random codeblock with a
    /// configurable significant-density.
    private static func makeBlock(width: Int, height: Int, seed: UInt32,
                                  density: UInt32 = 32, magBits: UInt32 = 0x3F)
        -> (coefs: [UInt32], tuples: [UInt64])
    {
        var rng = seed
        var coefs = [UInt32](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            rng = rng &* 1_103_515_245 &+ 12_345
            if (rng & UInt32(0x3F)) < density {
                coefs[i] = (rng & 0x8000_0000) | UInt32(rng & magBits)
            }
        }
        let tuples = buildTuples(coefficients: coefs, width: width, height: height,
                                 missingMSBs: 0)
        return (coefs, tuples)
    }

    /// Run a batch through CPU + GPU; assert per-block byte-identical.
    private func runAndCompareBatch(blocks: [(coefs: [UInt32],
                                              width: Int, height: Int,
                                              missingMSBs: Int)],
                                    label: String,
                                    file: StaticString = #filePath,
                                    line: UInt = #line) async throws {
        // CPU expected, per block
        var cpuExpected: [(magsgn: [UInt8], mel: [UInt8], vlc: [UInt8])] = []
        cpuExpected.reserveCapacity(blocks.count)
        var batchInputs: [J2KGPUForwardHTCleanupPassEmit.BlockDescriptor] = []
        batchInputs.reserveCapacity(blocks.count)

        for b in blocks {
            let tuples = Self.buildTuples(
                coefficients: b.coefs, width: b.width, height: b.height,
                missingMSBs: b.missingMSBs)
            let (cpuMS, cpuMEL, cpuVLC) = tuples.withUnsafeBufferPointer { tupleBuf in
                b.coefs.withUnsafeBufferPointer { coefBuf in
                    var msEnc = HTMagSgnEncoderConformant()
                    var melEnc = HTMELEncoderConformant()
                    var vlcEnc = HTReverseBitEmitterConformant()
                    return HTBlockEncoderConformant.encode(
                        coefficients: coefBuf,
                        width: b.width, height: b.height, missingMSBs: b.missingMSBs,
                        magsgnEnc: &msEnc, melEnc: &melEnc, vlcEnc: &vlcEnc,
                        useSIMDClassification: false,
                        preClassifiedTuples: tupleBuf)
                }
            }
            cpuExpected.append((cpuMS, cpuMEL, cpuVLC))
            batchInputs.append(J2KGPUForwardHTCleanupPassEmit.BlockDescriptor(
                width: b.width, height: b.height,
                missingMSBs: b.missingMSBs, tuples: tuples))
        }

        let gpu = try await J2KGPUForwardHTCleanupPassEmit().emitBlocks(batchInputs)
        XCTAssertEqual(gpu.perBlockMagsgn.count, blocks.count, file: file, line: line)

        for i in 0..<blocks.count {
            XCTAssertEqual(gpu.perBlockMagsgn[i], cpuExpected[i].magsgn,
                "[\(label) block \(i)] MagSgn mismatch (cpu=\(cpuExpected[i].magsgn.count) gpu=\(gpu.perBlockMagsgn[i].count))",
                file: file, line: line)
            XCTAssertEqual(gpu.perBlockMel[i], cpuExpected[i].mel,
                "[\(label) block \(i)] MEL mismatch",
                file: file, line: line)
            XCTAssertEqual(gpu.perBlockVlc[i], cpuExpected[i].vlc,
                "[\(label) block \(i)] VLC mismatch",
                file: file, line: line)
        }
    }

    // MARK: - Empty / single

    func testEmptyBatchReturnsEmpty() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        let result = try await J2KGPUForwardHTCleanupPassEmit().emitBlocks([])
        XCTAssertEqual(result.perBlockMagsgn, [])
        XCTAssertEqual(result.perBlockMel, [])
        XCTAssertEqual(result.perBlockVlc, [])
    }

    // MARK: - Heterogeneous batches

    /// 4 blocks with different sizes (4×4, 8×8, 16×16, 32×32) in one
    /// dispatch — tests per-block descriptor indexing.
    func testHeterogeneousSizes_4Blocks() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        let sizes = [(4, 4), (8, 8), (16, 16), (32, 32)]
        var blocks: [(coefs: [UInt32], width: Int, height: Int, missingMSBs: Int)] = []
        for (i, (w, h)) in sizes.enumerated() {
            let (coefs, _) = Self.makeBlock(width: w, height: h, seed: 0xCAFE0000 + UInt32(i))
            blocks.append((coefs, w, h, 0))
        }
        try await runAndCompareBatch(blocks: blocks, label: "heterogeneous-sizes")
    }

    /// Same dimensions but different missingMSBs per block.
    func testHeterogeneousMissingMSBs() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        var blocks: [(coefs: [UInt32], width: Int, height: Int, missingMSBs: Int)] = []
        for (i, missingMSBs) in [0, 5, 10, 15].enumerated() {
            let (coefs, _) = Self.makeBlock(width: 16, height: 16,
                                            seed: 0xDEAD0000 + UInt32(i))
            blocks.append((coefs, 16, 16, missingMSBs))
        }
        try await runAndCompareBatch(blocks: blocks, label: "heterogeneous-missingMSBs")
    }

    /// 16-block uniform 32×32 batch — most common production case.
    func testUniform16Blocks_32x32() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        var blocks: [(coefs: [UInt32], width: Int, height: Int, missingMSBs: Int)] = []
        for i in 0..<16 {
            let (coefs, _) = Self.makeBlock(width: 32, height: 32,
                                            seed: 0xA1B2_C3D0 + UInt32(i))
            blocks.append((coefs, 32, 32, 0))
        }
        try await runAndCompareBatch(blocks: blocks, label: "16x32x32")
    }

    /// 64-block 32×32 batch with varying significance density.
    func testLargeBatch_64Blocks_VaryingDensity() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        var blocks: [(coefs: [UInt32], width: Int, height: Int, missingMSBs: Int)] = []
        for i in 0..<64 {
            // Density 4 (sparse) ↔ 60 (dense) in 4-step increments.
            let density = UInt32(4 + (i % 14) * 4)
            let (coefs, _) = Self.makeBlock(width: 32, height: 32,
                                            seed: 0xCAFE_F000 + UInt32(i),
                                            density: density)
            blocks.append((coefs, 32, 32, 0))
        }
        try await runAndCompareBatch(blocks: blocks, label: "64x32x32 varying density")
    }

    /// Mix of zero and non-zero blocks — edges of the per-block emit
    /// path (zero blocks emit only signalling bits; non-zero blocks
    /// emit full data). Verifies the kernel correctly resets state
    /// per block (since they share the kernel pipeline).
    func testZeroAndNonZeroBlocksMixed() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        var blocks: [(coefs: [UInt32], width: Int, height: Int, missingMSBs: Int)] = []
        for i in 0..<8 {
            let (coefs, _): ([UInt32], [UInt64])
            if i % 2 == 0 {
                coefs = [UInt32](repeating: 0, count: 32 * 32)
            } else {
                let r = Self.makeBlock(width: 32, height: 32,
                                       seed: 0xFEED_F00D + UInt32(i))
                coefs = r.coefs
            }
            blocks.append((coefs, 32, 32, 0))
        }
        try await runAndCompareBatch(blocks: blocks, label: "zero + non-zero mixed")
    }

    // MARK: - Microbenchmark (observational)

    /// 2,300-block dispatch wall-time at DX 2x2 per-tile scale.
    /// Single-block dispatch in I1.3b was ~0.05 ms per block; the
    /// batched dispatch should be much less per-block due to GPU
    /// parallelism (Apple M2 ~320 simultaneous threadgroups).
    func testMicrobenchmark_TilePerTileScale() async throws {
        try XCTSkipUnless(J2KGPUForwardHTCleanupPassEmit.isAvailable, "Metal not available")
        let blockCount = 2300
        var blocks: [J2KGPUForwardHTCleanupPassEmit.BlockDescriptor] = []
        blocks.reserveCapacity(blockCount)
        for i in 0..<blockCount {
            let (coefs, _) = Self.makeBlock(width: 32, height: 32,
                                            seed: 0xA5A5_0000 + UInt32(i))
            let tuples = Self.buildTuples(coefficients: coefs,
                                          width: 32, height: 32, missingMSBs: 0)
            blocks.append(.init(width: 32, height: 32, missingMSBs: 0, tuples: tuples))
        }
        let emit = J2KGPUForwardHTCleanupPassEmit()
        // Warm-up
        _ = try await emit.emitBlocks(blocks)

        let trials = 10
        var samples: [Double] = []
        samples.reserveCapacity(trials)
        for _ in 0..<trials {
            let t0 = Date()
            _ = try await emit.emitBlocks(blocks)
            samples.append(Date().timeIntervalSince(t0) * 1000.0)
        }
        samples.sort()
        let median = samples[trials / 2]
        let p10 = samples[trials / 10]
        let p90 = samples[trials - trials / 10 - 1]
        print(String(
            format: "I1.3c batched cleanup-pass N=%d × 32×32 blocks: median=%.3f ms p10=%.3f ms p90=%.3f ms",
            blockCount, median, p10, p90))
    }
}
