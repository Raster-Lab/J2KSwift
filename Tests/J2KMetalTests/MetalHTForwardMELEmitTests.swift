// MetalHTForwardMELEmitTests.swift
//
// v7.1.0 I1.2c — bit-exact + microbenchmark validation of the MEL
// (forward-bit-stream) batched byte-write kernel.
//
// Mirrors the I1.2 / I1.2b MagSgn validation pattern but against
// `HTForwardBitEmitterConformant` (MSB-first, no rollback / FF-drop)
// rather than `HTMagSgnEncoderConformant` (LSB-first with both).
//
// Gates:
//   - Per-block bit-exactness across hand-picked edge cases:
//       * empty
//       * single-bit emit
//       * FF-stuff reserves next byte's high bit
//       * partial-byte terminate produces zero-padded final byte
//   - Randomised sweep: 3 seeds × N ∈ {1, 4, 32, 256} blocks; every
//     block byte-identical to the CPU reference.
//   - 4-byte-alignment regression guard (caught the I1.2b race;
//     the same constraint applies to MEL).
//   - Microbenchmark at N=2,300 blocks (DX 2x2 typical).

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MetalHTForwardMELEmitTests: XCTestCase {

    // MARK: - CPU reference

    private static func cpuEmit(_ items: [J2KMetalHTMELEmit.Item]) -> [UInt8] {
        var enc = HTForwardBitEmitterConformant()
        for item in items {
            enc.emit(bits: Int(item.value), count: Int(item.count))
        }
        return enc.finish()
    }

    private func runOneBlockAndCompare(_ items: [J2KMetalHTMELEmit.Item],
                                       file: StaticString = #filePath,
                                       line: UInt = #line) async throws {
        let cpu = Self.cpuEmit(items)
        let descriptors = [J2KMetalHTMELEmit.BlockDescriptor(
            itemStart: 0, itemCount: UInt32(items.count))]
        let budgets: [UInt32] = [UInt32(cpu.count)]
        let (offsets, capacity) = J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets: budgets)
        let result = try await J2KMetalHTMELEmit().emitBlocks(
            items: items, descriptors: descriptors,
            outputOffsets: offsets, outputCapacity: max(8, capacity))
        let gpuLen = Int(result.perBlockByteCount[0])
        let gpuStart = Int(offsets[0])
        let gpu = Array(result.bytes[gpuStart..<gpuStart + gpuLen])
        XCTAssertEqual(gpu, cpu,
                       "byte stream divergence (items.count=\(items.count), cpu len=\(cpu.count), gpu len=\(gpuLen))",
                       file: file, line: line)
    }

    // MARK: - Edge cases

    func testEmptyBatchReturnsEmpty() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        let result = try await J2KMetalHTMELEmit().emitBlocks(
            items: [], descriptors: [], outputOffsets: [], outputCapacity: 16)
        XCTAssertEqual(result.bytes, [])
        XCTAssertEqual(result.perBlockByteCount, [])
    }

    func testEmptyItemsInOneBlock_ProducesNoBytes() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        let descriptors = [J2KMetalHTMELEmit.BlockDescriptor(itemStart: 0, itemCount: 0)]
        let result = try await J2KMetalHTMELEmit().emitBlocks(
            items: [], descriptors: descriptors,
            outputOffsets: [0], outputCapacity: 16)
        XCTAssertEqual(Int(result.perBlockByteCount[0]), 0)
    }

    func testSingleBit_PaddedTerminate() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        // Emit one bit (1) → tmp=1, remainingBits=7. finish() shifts
        // tmp <<= 7 → byte = 0x80 (0b1000_0000). Tests the MSB-first
        // packing + LSB-side zero-pad on terminate.
        try await runOneBlockAndCompare([.init(value: 1, count: 1)])
    }

    /// Emit exactly 8 bits of 0xFF then 8 more bits — exercises the
    /// FF-stuff branch (next byte's high bit reserved as 0).
    func testFFStuffingReservesNextHighBit() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([
            .init(value: 0xFF, count: 8),
            .init(value: 0xFF, count: 8),
        ])
    }

    /// FF-stuff followed by terminate — finish() must emit the
    /// trailing partial byte (high bit reserved zero, low 7 bits
    /// zero-padded → byte = 0x00 even though no real data followed).
    func testTerminateAfterFF_AppendsStuffByte() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([.init(value: 0xFF, count: 8)])
    }

    /// Wide value emit, exercises the multi-bit-per-call inner loop.
    func testWideValueMSBFirst() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([.init(value: 0xDEAD_BEEF, count: 32)])
    }

    /// Mixed widths spanning the FF-stuff boundary multiple times.
    func testMixedWidthsAcrossFFRuns() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        try await runOneBlockAndCompare([
            .init(value: 0xFF, count: 8),
            .init(value: 0x7F, count: 7),
            .init(value: 0xFF, count: 8),
            .init(value: 0x55, count: 8),
            .init(value: 0xFF, count: 8),
            .init(value: 0x00, count: 3),
        ])
    }

    // MARK: - Random batched sweep

    func testRandomBatch_AllBlocksByteIdentical() async throws {
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        for seed in [0xA1B2_C3D4, 0xCAFE_F00D, 0xDEAD_BEEF] as [UInt64] {
            for blockCount in [1, 4, 32, 256] {
                var rng = SplitMix64(seed: seed &+ UInt64(blockCount))
                var items: [J2KMetalHTMELEmit.Item] = []
                var descriptors: [J2KMetalHTMELEmit.BlockDescriptor] = []
                var cpuBytes: [[UInt8]] = []
                for _ in 0..<blockCount {
                    let nItems = Int(rng.next() % 32) + 1   // 1..32
                    let start = UInt32(items.count)
                    var block: [J2KMetalHTMELEmit.Item] = []
                    block.reserveCapacity(nItems)
                    for _ in 0..<nItems {
                        let count = UInt32(rng.next() % 17) // 0..16 — MEL emits modest widths
                        let mask: UInt32 = count >= 32 ? 0xFFFF_FFFF
                                                       : (UInt32(1) &<< count) &- 1
                        let v = UInt32(rng.next() & 0xFFFF_FFFF) & mask
                        block.append(.init(value: v, count: count))
                    }
                    items.append(contentsOf: block)
                    descriptors.append(.init(itemStart: start, itemCount: UInt32(nItems)))
                    cpuBytes.append(Self.cpuEmit(block))
                }
                let budgets = cpuBytes.map { UInt32($0.count) }
                let (offsets, capacity) = J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets: budgets)
                let result = try await J2KMetalHTMELEmit().emitBlocks(
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
        try XCTSkipUnless(J2KMetalHTMELEmit.isAvailable, "Metal not available")
        let blockCount = 2300
        var rng = SplitMix64(seed: 0xA5A5_A5A5)
        var items: [J2KMetalHTMELEmit.Item] = []
        var descriptors: [J2KMetalHTMELEmit.BlockDescriptor] = []
        var cpuBytes: [[UInt8]] = []
        for _ in 0..<blockCount {
            let nItems = Int(rng.next() % 64) + 16   // 16..79
            let start = UInt32(items.count)
            var block: [J2KMetalHTMELEmit.Item] = []
            block.reserveCapacity(nItems)
            for _ in 0..<nItems {
                let count = UInt32(rng.next() % 9)   // 0..8
                let mask: UInt32 = count >= 32 ? 0xFFFF_FFFF
                                               : (UInt32(1) &<< count) &- 1
                let v = UInt32(rng.next() & 0xFFFF_FFFF) & mask
                block.append(.init(value: v, count: count))
            }
            items.append(contentsOf: block)
            descriptors.append(.init(itemStart: start, itemCount: UInt32(nItems)))
            cpuBytes.append(Self.cpuEmit(block))
        }
        let budgets = cpuBytes.map { UInt32($0.count) }
        let (offsets, capacity) = J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets: budgets)

        let emit = J2KMetalHTMELEmit()
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
            format: "I1.2c MEL-emit batched N=%d blocks (%d items): median=%.3f ms p10=%.3f ms p90=%.3f ms",
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
