// MetalHTForwardMagSgnEmitBatchedTests.swift
//
// v7.1.0 I1.2b — bit-exact + dispatch microbenchmark validation of
// the **batched** (multi-block) MagSgn byte-write kernel.
//
// I1.2 (#338) shipped the single-block per-block-serial bit-emit
// kernel and proved it byte-identical to `HTMagSgnEncoderConformant`.
// I1.2b dispatches that same logic as one threadgroup per block,
// which is the production shape of Pass 3: ~2,300 blocks per DX 2x2
// tile run concurrently. This test gates:
//
//   1. **Per-block bit-exactness** — every block in a multi-block
//      batch produces a stream byte-identical to running the CPU
//      `HTMagSgnEncoderConformant` on its items in isolation.
//
//   2. **Per-block byte-count exactness** — kernel-reported counts
//      match the CPU encoder's emitted byte count for each block.
//
//   3. **End-to-end Pass 2 → Pass 3 integration** — drive the
//      kernel with offsets produced by the I1.1 `J2KMetalPrefixSum`
//      kernel from per-block byte budgets. Catches contract drift
//      between Pass 2's exclusive-vs-inclusive scan semantics and
//      Pass 3's expected per-block start-offset.
//
//   4. **Dispatch microbenchmark** — measures realistic batched
//      execution time at N=2300 blocks (DX 2x2 per-tile typical),
//      not the misleading single-thread-per-block timing from I1.2.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MetalHTForwardMagSgnEmitBatchedTests: XCTestCase {

    // MARK: - CPU reference

    private static func cpuEmit(_ items: [J2KMetalHTMagSgnEmit.Item]) -> [UInt8] {
        var enc = HTMagSgnEncoderConformant()
        for item in items {
            enc.encode(codeword: item.codeword, count: Int(item.count))
        }
        return enc.finish()
    }

    /// Build a per-block dataset: returns the flat items array, per-
    /// block descriptors, and the per-block CPU reference bytes (which
    /// also act as the per-block byte budgets after CPU emit).
    private static func buildBlocks(seed: UInt64,
                                    blockCount: Int,
                                    itemsPerBlockRange: ClosedRange<Int>)
        -> (items: [J2KMetalHTMagSgnEmit.Item],
            descriptors: [J2KMetalHTMagSgnEmit.BlockDescriptor],
            cpuBytes: [[UInt8]])
    {
        var rng = SplitMix64(seed: seed)
        var items: [J2KMetalHTMagSgnEmit.Item] = []
        var descriptors: [J2KMetalHTMagSgnEmit.BlockDescriptor] = []
        var cpuBytes: [[UInt8]] = []
        for _ in 0..<blockCount {
            let nItems = Int(rng.next() % UInt64(itemsPerBlockRange.count))
                + itemsPerBlockRange.lowerBound
            let start = UInt32(items.count)
            var block: [J2KMetalHTMagSgnEmit.Item] = []
            block.reserveCapacity(nItems)
            for _ in 0..<nItems {
                let count = UInt32(rng.next() % 33)
                let mask: UInt32 = count >= 32 ? 0xFFFF_FFFF : (UInt32(1) &<< count) &- 1
                let cw = UInt32(rng.next() & 0xFFFF_FFFF) & mask
                block.append(.init(codeword: cw, count: count))
            }
            items.append(contentsOf: block)
            descriptors.append(.init(itemStart: start, itemCount: UInt32(nItems)))
            cpuBytes.append(cpuEmit(block))
        }
        return (items, descriptors, cpuBytes)
    }

    /// Convert per-block byte budgets to per-block start offsets via
    /// an *exclusive* prefix-sum (start of block i = sum of bytes for
    /// blocks 0..i-1). The kernel writes into the shared output buffer
    /// using these offsets; total capacity is the sum of all budgets.
    /// **Aligns each block to a 4-byte boundary** to avoid inter-
    /// threadgroup RMW races on Apple Silicon byte stores — see
    /// `J2KMetalHTMagSgnEmit.alignedOffsets`.
    private static func exclusiveAlignedScan(_ budgets: [UInt32]) -> (offsets: [UInt32], capacity: Int) {
        return J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets: budgets)
    }

    // MARK: - Empty / single-block / N=2

    func testEmptyBatchReturnsEmpty() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        let result = try await J2KMetalHTMagSgnEmit().emitBlocks(
            items: [], descriptors: [], outputOffsets: [], outputCapacity: 16)
        XCTAssertEqual(result.bytes, [])
        XCTAssertEqual(result.perBlockByteCount, [])
    }

    func testSingleBlockBatchMatchesSingleBlockKernel() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        let items: [J2KMetalHTMagSgnEmit.Item] = [
            .init(codeword: 0xFF, count: 8),
            .init(codeword: 0x55, count: 8),
        ]
        let cpu = Self.cpuEmit(items)
        let descriptors = [J2KMetalHTMagSgnEmit.BlockDescriptor(
            itemStart: 0, itemCount: UInt32(items.count))]
        let offsets: [UInt32] = [0]
        let capacity = max(16, cpu.count + 8)
        let result = try await J2KMetalHTMagSgnEmit().emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: capacity)
        XCTAssertEqual(Int(result.perBlockByteCount[0]), cpu.count)
        XCTAssertEqual(Array(result.bytes.prefix(cpu.count)), cpu)
    }

    func testTwoBlockBatch_SecondAtNonZeroOffset() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        let blockA: [J2KMetalHTMagSgnEmit.Item] = [.init(codeword: 0xA5, count: 8)]
        let blockB: [J2KMetalHTMagSgnEmit.Item] = [
            .init(codeword: 0xFF, count: 8),
            .init(codeword: 0x12, count: 8),
        ]
        let cpuA = Self.cpuEmit(blockA)
        let cpuB = Self.cpuEmit(blockB)
        let items = blockA + blockB
        let descriptors = [
            J2KMetalHTMagSgnEmit.BlockDescriptor(itemStart: 0, itemCount: UInt32(blockA.count)),
            J2KMetalHTMagSgnEmit.BlockDescriptor(itemStart: UInt32(blockA.count),
                                                 itemCount: UInt32(blockB.count)),
        ]
        let offsets: [UInt32] = [0, UInt32(cpuA.count)]
        let capacity = cpuA.count + cpuB.count + 8
        let result = try await J2KMetalHTMagSgnEmit().emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: capacity)
        XCTAssertEqual(Int(result.perBlockByteCount[0]), cpuA.count)
        XCTAssertEqual(Int(result.perBlockByteCount[1]), cpuB.count)
        XCTAssertEqual(Array(result.bytes[0..<cpuA.count]), cpuA)
        XCTAssertEqual(Array(result.bytes[cpuA.count..<(cpuA.count + cpuB.count)]), cpuB)
    }

    // MARK: - Random sweep

    func testRandomBatch_AllBlocksByteIdentical() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        for seed in [0xA1B2_C3D4, 0xCAFE_F00D, 0xDEAD_BEEF] as [UInt64] {
            for blockCount in [4, 32, 256] {
                let (items, descriptors, cpuBytes) = Self.buildBlocks(
                    seed: seed, blockCount: blockCount, itemsPerBlockRange: 1...64)
                let budgets = cpuBytes.map { UInt32($0.count) }
                let (offsets, capacity) = Self.exclusiveAlignedScan(budgets)
                let result = try await J2KMetalHTMagSgnEmit().emitBlocks(
                    items: items, descriptors: descriptors,
                    outputOffsets: offsets, outputCapacity: capacity)

                XCTAssertEqual(result.perBlockByteCount.count, blockCount,
                               "[seed=\(String(seed, radix: 16)) N=\(blockCount)] count vector length")

                for i in 0..<blockCount {
                    let cpu = cpuBytes[i]
                    let gpuLen = Int(result.perBlockByteCount[i])
                    let gpuStart = Int(offsets[i])
                    let gpuEnd = gpuStart + gpuLen
                    let gpu = Array(result.bytes[gpuStart..<gpuEnd])
                    XCTAssertEqual(gpuLen, cpu.count,
                        "[seed=\(String(seed, radix: 16)) N=\(blockCount) block \(i)] byte-count mismatch")
                    XCTAssertEqual(gpu, cpu,
                        "[seed=\(String(seed, radix: 16)) N=\(blockCount) block \(i)] byte mismatch")
                }
            }
        }
    }

    /// Regression — guards against re-introducing the I1.2b "unaligned
    /// offsets cause inter-threadgroup byte-store RMW races" bug.
    /// On an unaligned 4-byte boundary, two blocks RMW the same word
    /// and one wins. Block 23 of seed=0xA1B2C3D4 / N=32 hits offset
    /// 1214 (mod-4 = 2) without alignment; with alignment it lands at
    /// 1244 (mod-4 = 0) and bytes are bit-exact.
    func testRegressionGuard_AlignedOffsetsAvoidByteStoreRMWRace() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        let (items, descriptors, cpuBytes) = Self.buildBlocks(
            seed: 0xA1B2_C3D4, blockCount: 32, itemsPerBlockRange: 1...64)
        let bIdx = 23
        let desc = descriptors[bIdx]
        let blockItems = Array(items[Int(desc.itemStart)..<Int(desc.itemStart + desc.itemCount)])
        let cpuBlock = cpuBytes[bIdx]

        // Single-block kernel reference.
        let single = try await J2KMetalHTMagSgnEmit().emitBlock(
            items: blockItems, outputCapacity: cpuBlock.count + 8)

        // Batched, but with this block alone.
        let descriptorsOne = [J2KMetalHTMagSgnEmit.BlockDescriptor(
            itemStart: 0, itemCount: UInt32(blockItems.count))]
        let batchedOne = try await J2KMetalHTMagSgnEmit().emitBlocks(
            items: blockItems, descriptors: descriptorsOne,
            outputOffsets: [0], outputCapacity: cpuBlock.count + 8)
        let batchedOneBytes = Array(batchedOne.bytes.prefix(Int(batchedOne.perBlockByteCount[0])))

        // Full batched run.
        let budgets = cpuBytes.map { UInt32($0.count) }
        let (offsets, capacity) = Self.exclusiveAlignedScan(budgets)
        let result = try await J2KMetalHTMagSgnEmit().emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: capacity)
        let gpuLen = Int(result.perBlockByteCount[bIdx])
        let gpuStart = Int(offsets[bIdx])
        let gpuFull = Array(result.bytes[gpuStart..<gpuStart + gpuLen])

        print("=== block 23 debug ===")
        print("  itemStart=\(desc.itemStart) itemCount=\(desc.itemCount)")
        print("  outputOffset=\(offsets[bIdx]) cpuLen=\(cpuBlock.count) gpuLen=\(gpuLen)")
        print("  CPU       : \(Array(cpuBlock.prefix(8)))...")
        print("  GPU single: \(Array(single.prefix(8)))...")
        print("  GPU batch1: \(Array(batchedOneBytes.prefix(8)))...")
        print("  GPU batchN: \(Array(gpuFull.prefix(8)))...")

        XCTAssertEqual(single, cpuBlock, "single-block path failed for block 23 in isolation")
        XCTAssertEqual(batchedOneBytes, cpuBlock, "batched-1-block path failed for block 23 in isolation")
        XCTAssertEqual(gpuFull, cpuBlock, "batched-N path bytes (with aligned offsets)")
    }

    // MARK: - Pass 2 → Pass 3 integration

    /// Drive the emit kernel with offsets produced by the I1.1
    /// prefix-sum kernel — catches contract drift between Pass 2 and
    /// Pass 3.
    func testIntegrationWithPass2PrefixSum() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        try XCTSkipUnless(J2KMetalPrefixSum.isAvailable, "Metal not available")

        let (items, descriptors, cpuBytes) = Self.buildBlocks(
            seed: 0xB055_CAFE, blockCount: 64, itemsPerBlockRange: 4...32)
        let budgets = cpuBytes.map { UInt32($0.count) }

        // For batched dispatch, the Pass 2 prefix-sum input must be
        // **aligned-up per-block byte sizes** (multiple of 4) — see
        // `J2KMetalHTMagSgnEmit.alignedOffsets`. The kernel still
        // emits the unaligned byte count via `byteCountsOut`; the
        // alignment is purely about avoiding inter-threadgroup RMW
        // races on byte stores.
        let alignedSizes = budgets.map { ($0 &+ 3) & ~UInt32(3) }
        let pass2Inclusive = try await J2KMetalPrefixSum().inclusiveScan(alignedSizes)
        var offsets = [UInt32](repeating: 0, count: alignedSizes.count)
        for i in 1..<alignedSizes.count {
            offsets[i] = pass2Inclusive[i - 1]
        }
        let (refOffsets, capacity) = Self.exclusiveAlignedScan(budgets)
        XCTAssertEqual(offsets, refOffsets,
                       "Pass 2 inclusive scan over aligned sizes, shifted right, must equal CPU aligned exclusive scan")

        let result = try await J2KMetalHTMagSgnEmit().emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: capacity)

        for i in 0..<descriptors.count {
            let cpu = cpuBytes[i]
            let gpuLen = Int(result.perBlockByteCount[i])
            let gpuStart = Int(offsets[i])
            let gpuEnd = gpuStart + gpuLen
            let gpu = Array(result.bytes[gpuStart..<gpuEnd])
            XCTAssertEqual(gpu, cpu, "Pass2→Pass3 integration block \(i) bytes")
        }
    }

    // MARK: - Microbenchmark (observational, non-gating)

    /// Realistic batched dispatch wall-time at N=2,300 blocks (DX 2x2
    /// per-tile typical block count). The I1.2 microbenchmark
    /// reported 1.5 ms for ONE single-thread-per-block dispatch;
    /// this test reports the wall for the production-shape multi-
    /// block dispatch.
    func testMicrobenchmark_BatchedDispatchAtTilePerTileScale() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        let blockCount = 2300
        // Modest items-per-block — keeps total dataset workable for a
        // microbenchmark, mirrors the typical per-block sample density
        // for non-LL subbands of a 32×32 codeblock at moderate p.
        let (items, descriptors, cpuBytes) = Self.buildBlocks(
            seed: 0xA5A5_A5A5, blockCount: blockCount, itemsPerBlockRange: 32...96)
        let budgets = cpuBytes.map { UInt32($0.count) }
        let (offsets, capacity) = Self.exclusiveAlignedScan(budgets)

        let emit = J2KMetalHTMagSgnEmit()
        // Warm-up.
        _ = try await emit.emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: capacity)

        let trials = 10
        var samples: [Double] = []
        samples.reserveCapacity(trials)
        for _ in 0..<trials {
            let t0 = Date()
            _ = try await emit.emitBlocks(
                items: items, descriptors: descriptors,
                outputOffsets: offsets, outputCapacity: capacity)
            samples.append(Date().timeIntervalSince(t0) * 1000.0)
        }
        samples.sort()
        let median = samples[trials / 2]
        let p10 = samples[trials / 10]
        let p90 = samples[trials - trials / 10 - 1]
        let totalItems = items.count
        print(String(
            format: "I1.2b MagSgn-emit batched N=%d blocks (%d items): median=%.3f ms p10=%.3f ms p90=%.3f ms",
            blockCount, totalItems, median, p10, p90))
    }
}

// MARK: - Tiny deterministic RNG

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
