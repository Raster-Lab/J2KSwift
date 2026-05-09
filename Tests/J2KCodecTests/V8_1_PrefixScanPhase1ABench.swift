// V8_1_PrefixScanPhase1ABench.swift
//
// v8.1 Phase 1A — prototype 8-byte SWAR refill with 128-bit
// accumulator. Pure measurement: the prototype lives inline as
// a private struct in this test file, NOT in production code.
// If the FF-density sweep shows a measurable win at corpus
// density (0.4 %) over the v7.4 4-byte SWAR baseline, Phase 1B
// will integrate the prototype into `HTMagSgnDecoderConformant`.
//
// The prototype:
//   - 128-bit accumulator (`tmp_lo: UInt64` + `tmp_hi: UInt64`)
//   - 8-byte unaligned `UInt64` load per iteration
//   - SWAR FF-detect on UInt64 (8-byte version of the v7.4 SWAR
//     4-byte detect) — `(inv &- 0x0101_0101_0101_0101) & ~inv &
//     0x8080_8080_8080_8080`
//   - Fast path (no FF in 8 bytes + no carried unstuff): one
//     128-bit OR, advance 64 bits
//   - Slow path: 8-iteration scalar fallback with 128-bit-aware
//     overflow handling
//
// The comparison is at the EXACT same `read(count:)` API surface
// as `HTMagSgnDecoderConformant`, so per-call costs are
// apples-to-apples.

import XCTest
@testable import J2KCodec

final class V8_1_PrefixScanPhase1ABench: XCTestCase {

    private func makeBytes(
        byteCount: Int,
        ffProbability: Double,
        seed: UInt64
    ) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        var out = [UInt8]()
        out.reserveCapacity(byteCount)
        let threshold = UInt64(Double(UInt64.max) * ffProbability)
        var lastWasFF = false
        for _ in 0..<byteCount {
            var b: UInt8
            if lastWasFF {
                b = UInt8(truncatingIfNeeded: rng.next() & 0x7F)
                lastWasFF = false
            } else if rng.next() < threshold {
                b = 0xFF
                lastWasFF = true
            } else {
                b = UInt8(truncatingIfNeeded: rng.next() & 0xFF)
                if b == 0xFF { b = 0xFE }
                lastWasFF = false
            }
            out.append(b)
        }
        return out
    }

    // ── Bench drivers ────────────────────────────────────────

    private func benchProduction(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
        let bytesNeeded = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, bytes.count / bytesNeeded / 2)
        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        var sink: UInt64 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            sink &+= UInt64(dec.read(count: bitsPerCall))
            i &+= 1
            if i % resetEvery == 0 {
                dec = HTMagSgnDecoderConformant(bytes: bytes)
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt64.max - 1)
        return Double(dt) / Double(iterations)
    }

    private func benchPrototype(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
        let bytesNeeded = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, bytes.count / bytesNeeded / 2)
        var dec = Refill8Prototype(bytes: bytes)
        var sink: UInt64 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            sink &+= UInt64(dec.read(count: bitsPerCall))
            i &+= 1
            if i % resetEvery == 0 {
                dec = Refill8Prototype(bytes: bytes)
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt64.max - 1)
        return Double(dt) / Double(iterations)
    }

    // ── Parity (mandatory before reporting bench numbers) ─────

    func testParity_ProductionVsPrototype_AcrossDensities() {
        let widths = [3, 7, 14, 32]
        let densities: [Double] = [0.0, 0.004, 0.05, 0.10, 0.25]
        let seeds: [UInt64] = [0x1, 0xC0FFEE, 0xDEADBEEF, 0x123_456_789]

        for density in densities {
            for seed in seeds {
                let bytes = makeBytes(byteCount: 4096, ffProbability: density, seed: seed)
                for w in widths {
                    var prod = HTMagSgnDecoderConformant(bytes: bytes)
                    var proto = Refill8Prototype(bytes: bytes)
                    var step = 0
                    while step < 200 {
                        let pv = prod.read(count: w)
                        let qv = proto.read(count: w)
                        XCTAssertEqual(pv, qv,
                            "parity mismatch at density=\(density) seed=\(String(seed, radix: 16)) w=\(w) step=\(step) prod=\(pv) proto=\(qv)")
                        step += 1
                    }
                }
            }
        }
    }

    func testParity_StreamExhaustionPadding() {
        // Tiny streams exhaust into 0xFF padding. Prototype must
        // produce the same padded reads as production.
        for size in [0, 1, 2, 3, 7, 8, 15, 16, 17] {
            let bytes = (0..<size).map { UInt8($0 & 0x7F) }
            for w in [3, 7, 14, 32] {
                var prod = HTMagSgnDecoderConformant(bytes: bytes)
                var proto = Refill8Prototype(bytes: bytes)
                for _ in 0..<10 {
                    let pv = prod.read(count: w)
                    let qv = proto.read(count: w)
                    XCTAssertEqual(pv, qv,
                        "exhaustion-padding mismatch size=\(size) w=\(w)")
                }
            }
        }
    }

    func testParity_HeavyFFEdgeCases() {
        // 0xFF at every position, 0xFF at every other, etc.
        let cases: [[UInt8]] = [
            [0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00,
             0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00],
            [0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F,
             0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F],
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF],
            [0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            // 0xFF at first 8-byte batch boundary edge
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF,
             0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        ]
        for (idx, bytes) in cases.enumerated() {
            for w in [3, 7, 14, 32] {
                var prod = HTMagSgnDecoderConformant(bytes: bytes)
                var proto = Refill8Prototype(bytes: bytes)
                for step in 0..<8 {
                    let pv = prod.read(count: w)
                    let qv = proto.read(count: w)
                    XCTAssertEqual(pv, qv,
                        "edge-case mismatch idx=\(idx) w=\(w) step=\(step)")
                }
            }
        }
    }

    // ── Bench: FF-density sweep, prototype vs v7.4 production ──

    func testBench_PrototypeVsProduction_FFDensitySweep_14bit() {
        let runs = 5
        let iterations = 200_000
        let byteCount = 4 * 1024 * 1024
        let densities: [Double] = [0.0, 0.004, 0.01, 0.05, 0.10, 0.25]

        print("=== v8.1 Phase 1A — prototype-vs-production FF-density sweep (median of \(runs)) ===")
        print("Buffer: \(byteCount) bytes; iterations: \(iterations) per cell; 14-bit reads")
        print()
        print("| target FF % | v7.4 ns/call | proto ns/call | proto Δ | proto speedup vs v7.4 |")
        print("|---|---:|---:|---:|---:|")

        for density in densities {
            let bytes = makeBytes(
                byteCount: byteCount, ffProbability: density, seed: 0xC0FFEE_C0FFEE)

            var prodSamples: [Double] = []
            for _ in 0..<runs {
                prodSamples.append(
                    benchProduction(bytes: bytes, bitsPerCall: 14, iterations: iterations))
            }
            prodSamples.sort()
            let prod = prodSamples[runs / 2]

            var protoSamples: [Double] = []
            for _ in 0..<runs {
                protoSamples.append(
                    benchPrototype(bytes: bytes, bitsPerCall: 14, iterations: iterations))
            }
            protoSamples.sort()
            let proto = protoSamples[runs / 2]

            let delta = (proto - prod) / prod * 100.0
            let speedup = prod / proto
            print(String(format: "| %.1f | %.2f | %.2f | %+.1f %% | %.2fx |",
                density * 100.0, prod, proto, delta, speedup))
        }
    }
}

// MARK: - Phase 1A prototype: 8-byte SWAR refill with 128-bit accumulator
//
// API-compatible mirror of `HTMagSgnDecoderConformant`. Internal
// fields are renamed (`tmpHi`) to make the 128-bit shape explicit.
//
// `read(count:)` does an UNCONDITIONAL 128-bit right shift —
// (`tmp_lo` + `tmp_hi` -> shift down by `count`). The cost of
// the carry-shift is in the prototype's per-call cost, so the
// bench fairly attributes it to Phase 1A's design.

private struct Refill8Prototype {
    private let bytes: ArraySlice<UInt8>
    private var readIndex: Int
    private var tmp: UInt64 = 0
    private var tmpHi: UInt64 = 0
    private var bits: Int = 0
    private var unstuff: Bool = false

    init(bytes: [UInt8]) {
        self.init(bytes: bytes[...])
    }

    init(bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        self.readIndex = 0
    }

    @inline(__always)
    mutating func read(count: Int) -> UInt32 {
        if bits < count { refill() }
        if count == 0 { return 0 }
        let mask: UInt64 = (UInt64(1) << count) - 1
        let v = UInt32(tmp & mask)
        // 128-bit right shift by `count` (count ∈ [1, 32]).
        // (64 - count) ∈ [32, 63] — well-defined Swift shift.
        tmp = (tmp >> count) | (tmpHi << (64 - count))
        tmpHi = tmpHi >> count
        bits -= count
        return v
    }

    @inline(__always)
    mutating func refill() {
        var rIdx = readIndex
        var t = tmp
        var th = tmpHi
        var b = bits
        var u = unstuff

        bytes.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                let count = ptr.count

                // 8-byte batched fast path. b ∈ [0, 32] on entry;
                // adding 64 bits gives b ≤ 96, fits in 128-bit
                // accumulator (lo + hi).
                while b <= 32 && rIdx + 8 <= count {
                    let p64 = UnsafeRawPointer(base.advanced(by: rIdx))
                        .loadUnaligned(as: UInt64.self)
                    // SWAR zero-byte detect on (p64 ^ 0xFFFF…).
                    // A byte equals 0xFF iff the corresponding lane
                    // in `inv` is zero.
                    let inv = p64 ^ 0xFFFF_FFFF_FFFF_FFFF
                    let hasZero =
                        (inv &- 0x0101_0101_0101_0101) & ~inv & 0x8080_8080_8080_8080
                    let anyFF = hasZero != 0

                    if !anyFF && !u {
                        // Fast path — fold all 8 bytes into the
                        // 128-bit accumulator at offset b.
                        if b == 0 {
                            t |= p64
                        } else {
                            t |= p64 << b
                            // For b ∈ [1, 32], (64 - b) ∈ [32, 63] —
                            // well-defined.
                            th |= p64 >> (64 - b)
                        }
                        b += 64
                        rIdx += 8
                    } else {
                        // Slow path — byte-by-byte for these 8
                        // bytes, with 128-bit-aware overflow.
                        var k = 0
                        while k < 8 {
                            let byte = base[rIdx]
                            rIdx += 1
                            let dBits = 8 - (u ? 1 : 0)
                            let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                            let val = UInt64(byte & mask)
                            // Place `val` (≤ 8 bits wide) at bit
                            // offset b in the 128-bit accumulator.
                            if b < 64 {
                                t |= val << b
                                if b + 8 > 64 {
                                    // Carry the high bits of val
                                    // into tmpHi.
                                    th |= val >> (64 - b)
                                }
                            } else {
                                th |= val << (b - 64)
                            }
                            b += dBits
                            u = (byte == 0xFF)
                            k += 1
                            if b > 32 { break }
                        }
                    }
                }

                // Tail: byte-at-a-time for remaining stream
                // (with 128-bit overflow handling).
                while b <= 32 && rIdx < count {
                    let byte = base[rIdx]
                    rIdx += 1
                    let dBits = 8 - (u ? 1 : 0)
                    let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                    let val = UInt64(byte & mask)
                    if b < 64 {
                        t |= val << b
                        if b + 8 > 64 {
                            th |= val >> (64 - b)
                        }
                    } else {
                        th |= val << (b - 64)
                    }
                    b += dBits
                    u = (byte == 0xFF)
                }
            }
            // End-of-stream 0xFF padding.
            while b <= 32 {
                let byte: UInt8 = 0xFF
                let dBits = 8 - (u ? 1 : 0)
                let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                let val = UInt64(byte & mask)
                if b < 64 {
                    t |= val << b
                    if b + 8 > 64 {
                        th |= val >> (64 - b)
                    }
                } else {
                    th |= val << (b - 64)
                }
                b += dBits
                u = (byte == 0xFF)
            }
        }

        readIndex = rIdx
        tmp = t
        tmpHi = th
        bits = b
        unstuff = u
    }
}

private struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
