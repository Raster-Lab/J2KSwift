// MetalHTForwardVLCEmitTests.swift
//
// v7.1.0 I1.2d — bit-exact + microbenchmark validation of the VLC
// (reverse-bit-stream) batched byte-write kernel.
//
// VLC is the trickiest of the three Pass 3 emit kernels — bytes are
// packed LSB-first within each byte, but the byte SEQUENCE is built
// in REVERSE then flipped at terminate. There's also a
// `lastGreaterThan8F` deferred-stuff state machine. This test gates
// the whole thing against `HTReverseBitEmitterConformant`.
//
// Coverage:
//   - Hand-picked edge cases that exercise the deferred-stuff release
//     branch, the `> 0x8F` stuff trigger, the implicit 0xFF sentinel
//     at the end of the on-wire stream, and the partial-byte
//     terminate flush.
//   - Randomised batched sweep at multiple seeds × N up to 256.
//   - Microbenchmark at N=2,300 blocks (DX 2x2 typical).

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MetalHTForwardVLCEmitTests: XCTestCase {

    // MARK: - CPU reference

    private static func cpuEmit(_ items: [J2KMetalHTVLCEmit.Item]) -> [UInt8] {
        var enc = HTReverseBitEmitterConformant()
        for item in items {
            enc.encode(codeword: Int(item.codeword), count: Int(item.count))
        }
        return enc.finish()
    }

    private func runOneBlockAndCompare(_ items: [J2KMetalHTVLCEmit.Item],
                                       file: StaticString = #filePath,
                                       line: UInt = #line) async throws {
        let cpu = Self.cpuEmit(items)
        let descriptors = [J2KMetalHTVLCEmit.BlockDescriptor(
            itemStart: 0, itemCount: UInt32(items.count))]
        let budgets: [UInt32] = [UInt32(cpu.count)]
        let (offsets, capacity) = J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets: budgets)
        let result = try await J2KMetalHTVLCEmit().emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: max(8, capacity))
        let gpuLen = Int(result.perBlockByteCount[0])
        let gpuStart = Int(offsets[0])
        let gpu = Array(result.bytes[gpuStart..<gpuStart + gpuLen])
        XCTAssertEqual(gpu, cpu,
                       "byte stream divergence (items=\(items.count), cpu len=\(cpu.count), gpu len=\(gpuLen))",
                       file: file, line: line)
    }

    // MARK: - Edge cases

    func testEmptyBatchReturnsEmpty() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        let result = try await J2KMetalHTVLCEmit().emitBlocks(
            items: [], descriptors: [], outputOffsets: [], outputCapacity: 16)
        XCTAssertEqual(result.bytes, [])
        XCTAssertEqual(result.perBlockByteCount, [])
    }

    /// Empty items in a single block — should still produce the
    /// 0xFF sentinel at on-wire byte 0 (and possibly the partial-byte
    /// flush of the initial `tmp = 0x0F, usedBits = 4` state).
    func testEmptyItemsInOneBlock_StillEmitsSentinel() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([])
    }

    /// Single small codeword — no stuff bytes triggered.
    func testSingleSmallCodeword() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([.init(codeword: 0x5, count: 4)])
    }

    /// Codeword wide enough to fill multiple bytes — exercises the
    /// inner-loop multi-byte emission path.
    func testWideCodeword_TriggersMultipleEmits() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([.init(codeword: 0xDEAD_BEEF, count: 32)])
    }

    /// All-ones across many bits — guarantees `> 0x8F` bytes get
    /// emitted, exercising the reverse-stuff trigger.
    func testAllOnes_TriggersGreaterThan8FStuff() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([
            .init(codeword: 0xFFFF_FFFF, count: 32),
            .init(codeword: 0xFFFF_FFFF, count: 32),
        ])
    }

    /// Varied widths and codewords — covers the deferred-stuff release
    /// branch (`lastGreaterThan8F && tmp != 0x7F`) by varying the
    /// pattern of "would-be" stuff bytes.
    func testMixedPatternsCoverDeferredStuffRelease() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([
            .init(codeword: 0xFF, count: 8),
            .init(codeword: 0x55, count: 6),
            .init(codeword: 0x7F, count: 7),
            .init(codeword: 0xFF, count: 8),
            .init(codeword: 0xAA, count: 5),
            .init(codeword: 0x12, count: 4),
            .init(codeword: 0x9F, count: 8),
        ])
    }

    // MARK: - Random batched sweep

    func testRandomBatch_AllBlocksByteIdentical() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        for seed in [0xA1B2_C3D4, 0xCAFE_F00D, 0xDEAD_BEEF] as [UInt64] {
            for blockCount in [1, 4, 32, 256] {
                var rng = SplitMix64(seed: seed &+ UInt64(blockCount))
                var items: [J2KMetalHTVLCEmit.Item] = []
                var descriptors: [J2KMetalHTVLCEmit.BlockDescriptor] = []
                var cpuBytes: [[UInt8]] = []
                for _ in 0..<blockCount {
                    let nItems = Int(rng.next() % 32) + 1   // 1..32
                    let start = UInt32(items.count)
                    var block: [J2KMetalHTVLCEmit.Item] = []
                    block.reserveCapacity(nItems)
                    for _ in 0..<nItems {
                        // VLC widths up to 16; broad enough to exercise
                        // the multi-byte inner loop and the > 0x8F stuff
                        // condition.
                        let count = UInt32(rng.next() % 17)
                        let mask: UInt32 = count >= 32 ? 0xFFFF_FFFF
                                                       : (UInt32(1) &<< count) &- 1
                        let cw = UInt32(rng.next() & 0xFFFF_FFFF) & mask
                        block.append(.init(codeword: cw, count: count))
                    }
                    items.append(contentsOf: block)
                    descriptors.append(.init(itemStart: start, itemCount: UInt32(nItems)))
                    cpuBytes.append(Self.cpuEmit(block))
                }
                let budgets = cpuBytes.map { UInt32($0.count) }
                let (offsets, capacity) = J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets: budgets)
                let result = try await J2KMetalHTVLCEmit().emitBlocks(
                    items: items, descriptors: descriptors,
                    outputOffsets: offsets, outputCapacity: max(8, capacity))
                XCTAssertEqual(result.perBlockByteCount.count, blockCount)
                for i in 0..<blockCount {
                    let cpu = cpuBytes[i]
                    let gpuLen = Int(result.perBlockByteCount[i])
                    let gpuStart = Int(offsets[i])
                    let gpu = Array(result.bytes[gpuStart..<gpuStart + gpuLen])
                    XCTAssertEqual(gpu, cpu,
                        "[seed=\(String(seed, radix: 16)) N=\(blockCount) block \(i)] byte mismatch")
                }
            }
        }
    }

    // MARK: - Microbenchmark (observational)

    func testMicrobenchmark_BatchedDispatchAtTilePerTileScale() async throws {
        try XCTSkipUnless(J2KMetalHTVLCEmit.isAvailable, "Metal not available")
        let blockCount = 2300
        var rng = SplitMix64(seed: 0xA5A5_A5A5)
        var items: [J2KMetalHTVLCEmit.Item] = []
        var descriptors: [J2KMetalHTVLCEmit.BlockDescriptor] = []
        var cpuBytes: [[UInt8]] = []
        for _ in 0..<blockCount {
            let nItems = Int(rng.next() % 64) + 16
            let start = UInt32(items.count)
            var block: [J2KMetalHTVLCEmit.Item] = []
            block.reserveCapacity(nItems)
            for _ in 0..<nItems {
                let count = UInt32(rng.next() % 13) + 2  // 2..14 — typical VLC widths
                let mask: UInt32 = count >= 32 ? 0xFFFF_FFFF
                                               : (UInt32(1) &<< count) &- 1
                let cw = UInt32(rng.next() & 0xFFFF_FFFF) & mask
                block.append(.init(codeword: cw, count: count))
            }
            items.append(contentsOf: block)
            descriptors.append(.init(itemStart: start, itemCount: UInt32(nItems)))
            cpuBytes.append(Self.cpuEmit(block))
        }
        let budgets = cpuBytes.map { UInt32($0.count) }
        let (offsets, capacity) = J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets: budgets)

        let emit = J2KMetalHTVLCEmit()
        _ = try await emit.emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: max(8, capacity))

        let trials = 10
        var samples: [Double] = []
        samples.reserveCapacity(trials)
        for _ in 0..<trials {
            let t0 = Date()
            _ = try await emit.emitBlocks(
                items: items, descriptors: descriptors,
                outputOffsets: offsets, outputCapacity: max(8, capacity))
            samples.append(Date().timeIntervalSince(t0) * 1000.0)
        }
        samples.sort()
        let median = samples[trials / 2]
        let p10 = samples[trials / 10]
        let p90 = samples[trials - trials / 10 - 1]
        print(String(
            format: "I1.2d VLC-emit batched N=%d blocks (%d items): median=%.3f ms p10=%.3f ms p90=%.3f ms",
            blockCount, items.count, median, p10, p90))
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
