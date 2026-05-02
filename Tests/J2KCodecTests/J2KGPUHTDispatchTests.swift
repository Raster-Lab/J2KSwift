// J2KGPUHTDispatchTests.swift
//
// Bit-exact validation that J2KGPUHTDispatch.decodeBatch produces
// the same Int32 integer-magnitude coefficients as the CPU
// HTBlockDecoder.decodeCleanupConformant path, on a synthetic
// multi-block batch. This is the M2-prime correctness gate at the
// integration shim level — the kernel itself is already covered by
// J2KMetalHTCleanupTests; this test covers the descriptor/pool
// building, the dequant conversion, and the eligibility filter.

import XCTest
import J2KCore
@testable import J2KCodec

final class J2KGPUHTDispatchTests: XCTestCase {

    /// Same deterministic coefficient generator as the kernel test
    /// (J2KMetalHTCleanupTests.makeCoefficients). Returns sign-
    /// magnitude UInt32 (sign in bit 31, magnitude in low bits).
    private func makeCoefficients(
        width: Int, height: Int, seed: UInt64, p: Int
    ) -> [UInt32] {
        var rng = seed | 1
        var out = [UInt32](repeating: 0, count: width * height)
        let minMag = UInt32(1) << p
        let extraBits = min(3, 30 - p)
        let extraMask: UInt32 = extraBits >= 31 ? 0 : ((UInt32(1) << extraBits) - 1)
        for i in 0..<out.count {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let gate = UInt8((rng >> 56) & 0xFF)
            if gate < 100 { out[i] = 0; continue }
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            let extra = UInt32((rng >> 32) & UInt64(extraMask))
            let sign = UInt32((rng >> 1) & 1) << 31
            out[i] = sign | (minMag &+ extra)
        }
        return out
    }

    /// Build a batch of N codeblocks with varying sizes + missingMSBs,
    /// run them through the dispatcher, and assert each block's
    /// dispatcher output equals the CPU `decodeCleanupConformant`
    /// output for the same raw bytes. Also checks that the
    /// eligibility filter passes empty/malformed blocks to fallback.
    func testBatchMatchesCPUPath() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")

        // Mix of sizes so the descriptor pool handling is exercised.
        let cases: [(w: Int, h: Int, missingMSBs: Int, seed: UInt64)] = [
            (16, 16, 5, 0x1234),
            (32, 32, 4, 0x5678),
            (64, 64, 3, 0x9ABC),
            (16, 32, 5, 0xDEF0),
        ]

        // Build encoded blocks + sample-aligned input data.
        var inputBlocks: [GPUHTBlock] = []
        var rawBlockBytes: [[UInt8]] = []
        var widths: [Int] = []
        var heights: [Int] = []
        var missingMSBsList: [Int] = []
        for c in cases {
            let p = 30 - c.missingMSBs
            let coefs = makeCoefficients(width: c.w, height: c.h, seed: c.seed, p: p)
            let (magsgn, mel, vlc) = HTBlockEncoderConformant.encode(
                coefficients: coefs,
                width: c.w, height: c.h,
                missingMSBs: c.missingMSBs)
            let block = try HTBlockLayoutConformant.assemble(
                magsgn: magsgn, mel: mel, vlc: vlc)
            inputBlocks.append(GPUHTBlock(
                width: c.w, height: c.h,
                data: block,
                missingMSBs: c.missingMSBs))
            rawBlockBytes.append(block)
            widths.append(c.w); heights.append(c.h); missingMSBsList.append(c.missingMSBs)
        }

        // Insert one empty block in the middle to exercise the
        // fallback path. The dispatcher should report it in
        // cpuFallbackIndices, not silently drop it.
        let emptyIdx = 2
        inputBlocks.insert(
            GPUHTBlock(width: 16, height: 16, data: [], missingMSBs: 4),
            at: emptyIdx)

        // Dispatch GPU batch.
        let result = try await J2KGPUHTDispatch.decodeBatch(blocks: inputBlocks)

        // The empty block must be in fallback, every other block
        // must be in decoded.
        XCTAssertEqual(result.cpuFallbackIndices, [emptyIdx],
                       "empty block must fall back to CPU")
        XCTAssertEqual(
            result.decodedBlockIndices,
            (0..<inputBlocks.count).filter { $0 != emptyIdx },
            "non-empty blocks must be decoded")
        XCTAssertEqual(result.results.count, result.decodedBlockIndices.count)

        // CPU reference path: per-block decodeCleanupConformant via
        // HTBlockDecoder, which produces the same Int32 integer-
        // magnitude convention the dispatcher returns.
        for (i, blockIdx) in result.decodedBlockIndices.enumerated() {
            // Map blockIdx in inputBlocks back to the original test
            // case (compensating for the inserted empty block).
            let origIdx = blockIdx < emptyIdx ? blockIdx : blockIdx - 1
            let w = widths[origIdx]
            let h = heights[origIdx]
            let mmsb = missingMSBsList[origIdx]
            let cpuDecoder = HTBlockDecoder(width: w, height: h, subband: .ll)
            let cpuCoeffs = try cpuDecoder.decodeCleanupConformant(
                rawBytes: rawBlockBytes[origIdx],
                missingMSBs: mmsb)
            XCTAssertEqual(
                result.results[i].coefficients, cpuCoeffs,
                "block #\(blockIdx) (\(w)×\(h), mmsb=\(mmsb)) must match CPU path"
            )
        }
    }

    /// Empty input must produce empty output without dispatching.
    func testEmptyBatch() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")
        let result = try await J2KGPUHTDispatch.decodeBatch(blocks: [])
        XCTAssertEqual(result.decodedBlockIndices, [])
        XCTAssertEqual(result.results.count, 0)
        XCTAssertEqual(result.cpuFallbackIndices, [])
    }

    /// All-empty batch must produce all-fallback, no GPU dispatch.
    func testAllEmptyFallsBack() async throws {
        try XCTSkipUnless(J2KGPUHTDispatch.isAvailable, "Metal not available")
        let blocks = (0..<3).map { _ in
            GPUHTBlock(width: 16, height: 16, data: [], missingMSBs: 4)
        }
        let result = try await J2KGPUHTDispatch.decodeBatch(blocks: blocks)
        XCTAssertEqual(result.decodedBlockIndices, [])
        XCTAssertEqual(result.cpuFallbackIndices, [0, 1, 2])
    }
}
