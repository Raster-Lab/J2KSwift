// MetalHTForwardMagSgnEmitTests.swift
//
// v7.1.0 I1.2 — bit-exact + microbenchmark validation of the
// per-block serial MagSgn byte-write kernel that backs Pass 3 of
// approach C (MagSgn-only single-block spike).
//
// What this gates:
//   - Pass 3's output bytes must match `HTMagSgnEncoderConformant`
//     byte-for-byte across:
//       * hand-picked edge cases that exercise FF-stuffing, the
//         terminate rollback (maxBits == 7 with no further bits),
//         and the pad-drops-FF terminate rule
//       * a randomised sweep of (codeword, count) sequences with
//         deterministic seeds
//   - The per-block bit-write pattern works at all (this is the
//     highest-risk part of approach C per the I1.0 design — single
//     thread per block, 31 idle threads per warp).
//   - Round-trip via `HTMagSgnDecoderConformant` recovers the
//     original codewords, confirming the byte stream is decoder-
//     consumable as well as byte-identical.
//
// All correctness assertions are exact (XCTAssertEqual). The
// microbenchmark records dispatch+execution wall-time at a typical
// per-block item count and is observational, not gating.

import XCTest
@testable import J2KCore
@testable import J2KCodec
@testable import J2KMetal

final class MetalHTForwardMagSgnEmitTests: XCTestCase {

    // MARK: - CPU reference

    /// Run the production CPU encoder on the same items the kernel sees.
    private static func cpuEmit(_ items: [J2KMetalHTMagSgnEmit.Item]) -> [UInt8] {
        var enc = HTMagSgnEncoderConformant()
        for item in items {
            enc.encode(codeword: item.codeword, count: Int(item.count))
        }
        return enc.finish()
    }

    private func runAndCompare(_ items: [J2KMetalHTMagSgnEmit.Item],
                               file: StaticString = #filePath,
                               line: UInt = #line) async throws {
        let cpu = Self.cpuEmit(items)
        // Generous capacity: every byte may reserve a stuff-bit slot,
        // so each input bit costs at most 1/7 of a byte; pad slack.
        let totalBits = items.reduce(0) { $0 + Int($1.count) }
        let capacity = max(16, (totalBits / 7) + 16)
        let emit = J2KMetalHTMagSgnEmit()
        let gpu = try await emit.emitBlock(items: items, outputCapacity: capacity)
        XCTAssertEqual(gpu, cpu,
                       "byte stream divergence — items: \(items.count), cpu len: \(cpu.count), gpu len: \(gpu.count)",
                       file: file, line: line)
    }

    // MARK: - Edge cases

    func testEmptyItemsReturnsEmpty() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        let emit = J2KMetalHTMagSgnEmit()
        let gpu = try await emit.emitBlock(items: [], outputCapacity: 16)
        XCTAssertEqual(gpu, [])
    }

    /// Single full byte — no FF-stuffing, no terminate rollback path.
    func testSingleByteValue() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        try await runAndCompare([.init(codeword: 0xA5, count: 8)])
    }

    /// Emits exactly `0xFF` then a follow-up byte — exercises the
    /// stuff-bit-reservation branch (the next byte's high bit must
    /// stay clear).
    func testFFStuffingReservesHighBit() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        // First write all 8 bits of 0xFF; then emit 8 more bits — the
        // CPU encoder will use only 7 of those before flushing.
        try await runAndCompare([
            .init(codeword: 0xFF, count: 8),
            .init(codeword: 0x55, count: 8),
        ])
    }

    /// Multi-FF run — back-to-back stuff bits.
    func testRepeatedFFRuns() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        try await runAndCompare([
            .init(codeword: 0xFF, count: 8),
            .init(codeword: 0x7F, count: 7),  // packs into the next byte's low 7 bits
            .init(codeword: 0xFF, count: 8),
            .init(codeword: 0x7F, count: 7),
            .init(codeword: 0x12, count: 8),
        ])
    }

    /// Pad-drops-FF — terminate flushes a partial byte that, after
    /// 1-bit padding, equals 0xFF; CPU drops it. GPU must too.
    func testTerminateDropsFFPaddedByte() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        // 1 bit set, 7 pad bits all 1 → 0xFE | 0x80 ... actually we
        // just need usedBits != 0 and tmp + pad bits = 0xFF. Pad bits
        // are always 1, so any tmp with the LSBs forming the matching
        // bits will produce 0xFF when padded. Easiest: set 0 bits used,
        // covered separately. Here: 1 bit "1" used → padded byte =
        // 0b1111_1111 = 0xFF → dropped.
        try await runAndCompare([.init(codeword: 1, count: 1)])
    }

    /// Terminate rollback — after a 0xFF byte, the next byte slot is
    /// reserved as a stuff-bit; if no more bits follow, the encoder
    /// rolls back the over-committed byte.
    func testTerminateRollbackAfterFF() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        // emit exactly 8 bits of 0xFF then nothing — finish() should
        // run the `maxBits == 7` rollback branch.
        try await runAndCompare([.init(codeword: 0xFF, count: 8)])
    }

    /// Wide codeword (32 bits) — exercises the `take >= 32` mask path.
    func testWide32BitCodeword() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        try await runAndCompare([.init(codeword: 0xDEAD_BEEF, count: 32)])
    }

    // MARK: - Random sweep

    /// Random sequences of (codeword, count) pairs. Deterministic seeds
    /// so failures are reproducible.
    func testRandomSweep_ByteIdentical() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        for seed in [0xA1B2_C3D4, 0xDEAD_BEEF, 0x0123_4567] as [UInt64] {
            for nItems in [1, 4, 16, 64, 256, 1024] {
                var rng = SplitMix64(seed: seed &+ UInt64(nItems))
                var items: [J2KMetalHTMagSgnEmit.Item] = []
                items.reserveCapacity(nItems)
                for _ in 0..<nItems {
                    let count = UInt32(rng.next() % 33)  // 0…32
                    let mask: UInt32 = count >= 32 ? 0xFFFF_FFFF
                                                   : (UInt32(1) &<< count) &- 1
                    let cw = UInt32(rng.next() & 0xFFFF_FFFF) & mask
                    items.append(.init(codeword: cw, count: count))
                }
                try await runAndCompare(items)
            }
        }
    }

    // MARK: - Round-trip via decoder

    func testRoundTripViaCPUDecoder() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        // Mix of 1, 7, 8, 13, 32-bit widths.
        let widths: [Int] = [1, 7, 8, 13, 32, 8, 8, 4, 16, 5, 8, 8]
        var rng = SplitMix64(seed: 0xCAFE_F00D)
        var items: [J2KMetalHTMagSgnEmit.Item] = []
        var expected: [UInt32] = []
        for w in widths {
            let mask: UInt32 = w >= 32 ? 0xFFFF_FFFF : (UInt32(1) &<< UInt32(w)) &- 1
            let cw = UInt32(rng.next() & 0xFFFF_FFFF) & mask
            items.append(.init(codeword: cw, count: UInt32(w)))
            expected.append(cw)
        }

        let totalBits = widths.reduce(0, +)
        let capacity = max(32, (totalBits / 7) + 16)
        let bytes = try await J2KMetalHTMagSgnEmit().emitBlock(items: items, outputCapacity: capacity)

        var decoder = HTMagSgnDecoderConformant(bytes: bytes)
        for (i, w) in widths.enumerated() {
            XCTAssertEqual(decoder.read(count: w), expected[i],
                           "round-trip mismatch at item \(i), width \(w)")
        }
    }

    // MARK: - Microbenchmark (observational, non-gating)

    /// Reports MagSgn emit dispatch+execution wall-time at a per-block
    /// item count typical of HT cleanup-pass output (~1024 samples per
    /// 32×32 codeblock, each emitting up to a couple of bit-fields).
    func testMicrobenchmark_DispatchTimeAtBlockSize() async throws {
        try XCTSkipUnless(J2KMetalHTMagSgnEmit.isAvailable, "Metal not available")
        let nItems = 1024
        var rng = SplitMix64(seed: 0xA5A5_A5A5)
        var items: [J2KMetalHTMagSgnEmit.Item] = []
        items.reserveCapacity(nItems)
        for _ in 0..<nItems {
            let count = UInt32(rng.next() % 33)
            let mask: UInt32 = count >= 32 ? 0xFFFF_FFFF : (UInt32(1) &<< count) &- 1
            let cw = UInt32(rng.next() & 0xFFFF_FFFF) & mask
            items.append(.init(codeword: cw, count: count))
        }
        let totalBits = items.reduce(0) { $0 + Int($1.count) }
        let capacity = max(64, (totalBits / 7) + 32)

        let emit = J2KMetalHTMagSgnEmit()
        // Warm-up — first dispatch pays pipeline-state cost.
        _ = try await emit.emitBlock(items: items, outputCapacity: capacity)

        let trials = 20
        var samples: [Double] = []
        samples.reserveCapacity(trials)
        for _ in 0..<trials {
            let t0 = Date()
            _ = try await emit.emitBlock(items: items, outputCapacity: capacity)
            samples.append(Date().timeIntervalSince(t0) * 1000.0)
        }
        samples.sort()
        let median = samples[trials / 2]
        let p10 = samples[trials / 10]
        let p90 = samples[trials - trials / 10 - 1]
        print(String(
            format: "I1.2 MagSgn-emit single-block N=%d items: median=%.3f ms p10=%.3f ms p90=%.3f ms",
            nItems, median, p10, p90))
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
