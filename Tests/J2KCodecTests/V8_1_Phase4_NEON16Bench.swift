// V8_1_Phase4_NEON16Bench.swift
//
// v8.1 Phase 4 — 16-byte NEON full-vector prefix-scan + 192-bit
// accumulator prototype. The "ambitious" path scoped down in
// Phase 1A. Pure measurement — the prototype lives inline here,
// no production code change.
//
// Per Phase 2's wash, the user explicitly authorised continuing
// to the 16-byte target documented as a future-investigator note.
// This bench produces the data that either justifies a Phase 5
// production integration OR closes the workstream definitively.
//
// Design:
//   - 192-bit accumulator (`tmp_lo: UInt64` + `tmp_mid: UInt64`
//     + `tmp_hi: UInt64`). 16-byte load can fill 128 bits per
//     fast-path iteration plus carry into mid/hi.
//   - SIMD16<UInt8> for the FF mask + per-byte u-state
//     computation (the compiler maps SIMD16 ops to NEON on ARM).
//   - Prefix-shift FF-mask by 1 lane to compute u_i = ff_{i-1}
//     (with carry from the prior batch's u-state).
//   - SIMD `vbslq`-style select for per-byte mask (0x7F vs 0xFF).
//   - Per-byte position offsets prefix-summed in scalar (since
//     dBits ∈ {7, 8} and 16 entries don't justify SIMD prefix-sum).
//   - 16 scalar OR-into-192-bit-accumulator operations.
//
// The bench compares:
//   1. Production v7.4 4-byte SWAR (existing default).
//   2. Production v8.1 8-byte SWAR (Phase 1B opt-in path).
//   3. v8.1 Phase 4 16-byte NEON prototype.
//
// Decision rule:
//   - If 16-byte beats 8-byte by ≥ 0.5 ns/call at corpus density
//     0.4 %, Phase 5 production-integrates the 16-byte path.
//   - Else, document the wash and close the v8.1 workstream
//     definitively.

import XCTest
@testable import J2KCodec

final class V8_1_Phase4_NEON16Bench: XCTestCase {

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

    // MARK: - Bench drivers

    private func benchProduction(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int,
        useSwar8: Bool
    ) -> Double {
        let prevSwar8 = HTMagSgnDecoderConformant.swarRefill8Enabled
        defer { HTMagSgnDecoderConformant.swarRefill8Enabled = prevSwar8 }
        HTMagSgnDecoderConformant.swarRefill8Enabled = useSwar8

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

    private func benchPrototype16(
        bytes: [UInt8],
        bitsPerCall: Int,
        iterations: Int
    ) -> Double {
        let bytesNeeded = max(1, (bitsPerCall + 7) / 8)
        let resetEvery = max(1, bytes.count / bytesNeeded / 2)
        var dec = NEON16Prototype(bytes: bytes)
        var sink: UInt64 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            sink &+= UInt64(dec.read(count: bitsPerCall))
            i &+= 1
            if i % resetEvery == 0 {
                dec = NEON16Prototype(bytes: bytes)
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt64.max - 1)
        return Double(dt) / Double(iterations)
    }

    // MARK: - Parity (mandatory before reporting bench numbers)

    func testParity_Prototype16VsProduction() {
        let widths = [3, 7, 14, 32]
        let densities: [Double] = [0.0, 0.004, 0.05, 0.10, 0.25]
        let seeds: [UInt64] = [0x1, 0xC0FFEE, 0xDEADBEEF]

        for density in densities {
            for seed in seeds {
                let bytes = makeBytes(byteCount: 4096, ffProbability: density, seed: seed)
                for w in widths {
                    var prod = HTMagSgnDecoderConformant(bytes: bytes)
                    var proto = NEON16Prototype(bytes: bytes)
                    for step in 0..<200 {
                        let pv = prod.read(count: w)
                        let qv = proto.read(count: w)
                        XCTAssertEqual(pv, qv,
                            "mismatch density=\(density) seed=\(String(seed, radix: 16)) w=\(w) step=\(step)")
                    }
                }
            }
        }
    }

    func testParity_StreamExhaustionPadding() {
        for size in [0, 1, 2, 7, 8, 15, 16, 17, 31, 32, 33] {
            let bytes = (0..<size).map { UInt8($0 & 0x7F) }
            for w in [3, 7, 14, 32] {
                var prod = HTMagSgnDecoderConformant(bytes: bytes)
                var proto = NEON16Prototype(bytes: bytes)
                for _ in 0..<10 {
                    let pv = prod.read(count: w)
                    let qv = proto.read(count: w)
                    XCTAssertEqual(pv, qv,
                        "exhaust mismatch size=\(size) w=\(w)")
                }
            }
        }
    }

    func testParity_HeavyFFEdgeCases() {
        let cases: [[UInt8]] = [
            // FF at every byte (with stuff bit constraint)
            [0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F,
             0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F,
             0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F,
             0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F, 0xFF, 0x7F],
            // FF at 16-byte batch boundary
            [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF,
             0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            // FF at start
            [0xFF, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
             0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            // Multiple FFs scattered
            [0x55, 0xFF, 0x33, 0x44, 0xFF, 0x10, 0x77, 0x88,
             0xAA, 0xBB, 0xFF, 0x42, 0xDD, 0xEE, 0x12, 0x34,
             0x56, 0x78, 0xFF, 0x05, 0xBC, 0xDE, 0xFF, 0x33,
             0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xFF, 0x44],
        ]
        for (idx, bytes) in cases.enumerated() {
            for w in [3, 7, 14, 32] {
                var prod = HTMagSgnDecoderConformant(bytes: bytes)
                var proto = NEON16Prototype(bytes: bytes)
                for step in 0..<8 {
                    let pv = prod.read(count: w)
                    let qv = proto.read(count: w)
                    XCTAssertEqual(pv, qv,
                        "edge mismatch idx=\(idx) w=\(w) step=\(step)")
                }
            }
        }
    }

    // MARK: - Bench: 3-way FF-density sweep

    func testBench_v74_v8_8byte_v8_16byte_FFDensitySweep_14bit() {
        let runs = 5
        let iterations = 200_000
        let byteCount = 4 * 1024 * 1024
        let densities: [Double] = [0.0, 0.004, 0.01, 0.05, 0.10, 0.25]

        print("=== v8.1 Phase 4 — 3-way refill A/B (median of \(runs)) ===")
        print("Buffer: \(byteCount) bytes; iterations: \(iterations) per cell; 14-bit reads")
        print()
        print("| target FF % | v7.4 4B | v8.1 8B | v8.1 16B (proto) | 16B vs 8B speedup | 16B vs v7.4 speedup |")
        print("|---|---:|---:|---:|---:|---:|")

        for density in densities {
            let bytes = makeBytes(
                byteCount: byteCount, ffProbability: density, seed: 0xC0FFEE_C0FFEE)

            var s4: [Double] = []
            for _ in 0..<runs {
                s4.append(benchProduction(bytes: bytes, bitsPerCall: 14,
                    iterations: iterations, useSwar8: false))
            }
            s4.sort()
            let v74 = s4[runs / 2]

            var s8: [Double] = []
            for _ in 0..<runs {
                s8.append(benchProduction(bytes: bytes, bitsPerCall: 14,
                    iterations: iterations, useSwar8: true))
            }
            s8.sort()
            let v81_8b = s8[runs / 2]

            var s16: [Double] = []
            for _ in 0..<runs {
                s16.append(benchPrototype16(bytes: bytes, bitsPerCall: 14,
                    iterations: iterations))
            }
            s16.sort()
            let v81_16b = s16[runs / 2]

            let speedup_16_vs_8 = v81_8b / v81_16b
            let speedup_16_vs_v74 = v74 / v81_16b
            print(String(format: "| %.1f | %.2f | %.2f | %.2f | %.2fx | %.2fx |",
                density * 100.0, v74, v81_8b, v81_16b,
                speedup_16_vs_8, speedup_16_vs_v74))
        }
    }
}

// MARK: - Phase 4 prototype: 16-byte NEON refill with 192-bit accumulator
//
// Uses `SIMD16<UInt8>` for the per-byte FF detect, u-state, mask
// computation. The compiler maps these SIMD16 ops to NEON on ARM.
// Scalar accumulator-OR is the residual sequential cost — 16
// shifted-ORs into a 3-limb 192-bit accumulator.

private struct NEON16Prototype {
    private let bytes: ArraySlice<UInt8>
    private var readIndex: Int
    private var tmp: UInt64 = 0
    private var tmpMid: UInt64 = 0
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
        // 192-bit right shift by `count` (count ∈ [1, 32]).
        // (64 - count) ∈ [32, 63] — well-defined Swift shift.
        tmp = (tmp >> count) | (tmpMid << (64 - count))
        tmpMid = (tmpMid >> count) | (tmpHi << (64 - count))
        tmpHi = tmpHi >> count
        bits -= count
        return v
    }

    @inline(__always)
    mutating func refill() {
        var rIdx = readIndex
        var t = tmp
        var tm = tmpMid
        var th = tmpHi
        var b = bits
        var u = unstuff

        bytes.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                let count = ptr.count

                // 16-byte NEON-prefix-scan fast/slow path.
                // b ∈ [0, 32] on entry; one batch can add up to
                // 8 × 16 = 128 bits, so b ≤ 160 after batch — fits
                // in 192-bit accumulator.
                while b <= 32 && rIdx + 16 <= count {
                    // Load 16 bytes into a SIMD16<UInt8>. The
                    // compiler maps this to a single `vld1q_u8`
                    // on ARM.
                    var v = SIMD16<UInt8>()
                    for i in 0..<16 {
                        v[i] = base[rIdx + i]
                    }

                    // FF detect: lane mask, 0xFF ⇒ true.
                    let ffMask = v .== SIMD16<UInt8>(repeating: 0xFF)

                    // Quick fast-path: no FFs and no carried
                    // unstuff. Fold the entire 16 bytes into the
                    // 192-bit accumulator at offset b.
                    if !any(ffMask) && !u {
                        // Reinterpret the 16 bytes as 2× UInt64 for
                        // direct accumulator OR. v[0..7] is lo, v[8..15] is hi.
                        let lo64 = UnsafeRawPointer(base.advanced(by: rIdx))
                            .loadUnaligned(as: UInt64.self)
                        let hi64 = UnsafeRawPointer(base.advanced(by: rIdx + 8))
                            .loadUnaligned(as: UInt64.self)
                        // 128-bit value at offset b in 192-bit acc.
                        if b == 0 {
                            t |= lo64
                            tm |= hi64
                        } else {
                            t |= lo64 << b
                            tm |= (hi64 << b) | (lo64 >> (64 - b))
                            th |= hi64 >> (64 - b)
                        }
                        b += 128
                        rIdx += 16
                        // u stays false
                        continue
                    }

                    // Slow path — at least one FF in the 16-byte
                    // batch or carried unstuff. SIMD-compute the
                    // per-byte u-state, mask, dBits; then scalar-
                    // reduce 16 contributions into the 192-bit
                    // accumulator.

                    // Per-byte u-state: u_i = (i == 0) ? carriedU : ff_{i-1}
                    // i.e., u-mask = ffMask shifted-left-by-1-lane,
                    // with carriedU at lane 0.
                    var uVec = SIMD16<UInt8>()
                    uVec[0] = u ? 1 : 0
                    for i in 1..<16 {
                        uVec[i] = ffMask[i - 1] ? 1 : 0
                    }

                    // dBits[i] = 8 - uVec[i] (∈ {7, 8})
                    // mask[i] = 0xFF >> uVec[i] (∈ {0xFF, 0x7F})
                    // masked[i] = v[i] & mask[i]

                    // Scalar reduction into 192-bit accumulator.
                    var pos = b
                    for i in 0..<16 {
                        let uHere = uVec[i]
                        let dBits = 8 - Int(uHere)
                        let m: UInt8 = (uHere != 0) ? 0x7F : 0xFF
                        let val = UInt64(v[i] & m)
                        // Place `val` (≤ 8 bits wide) at bit
                        // offset `pos` in the 192-bit accumulator.
                        if pos < 64 {
                            t |= val << pos
                            if pos + 8 > 64 {
                                tm |= val >> (64 - pos)
                            }
                        } else if pos < 128 {
                            let p = pos - 64
                            tm |= val << p
                            if p + 8 > 64 {
                                th |= val >> (64 - p)
                            }
                        } else {
                            th |= val << (pos - 128)
                        }
                        pos += dBits
                        if pos > 32 + 128 { break }   // safety
                    }
                    b = pos
                    rIdx += 16
                    u = ffMask[15]
                }

                // Tail: byte-at-a-time for remaining stream
                // (with 192-bit overflow handling).
                while b <= 32 && rIdx < count {
                    let byte = base[rIdx]
                    rIdx += 1
                    let dBits = 8 - (u ? 1 : 0)
                    let mask: UInt8 = UInt8(0xFF) >> (u ? 1 : 0)
                    let val = UInt64(byte & mask)
                    if b < 64 {
                        t |= val << b
                        if b + 8 > 64 {
                            tm |= val >> (64 - b)
                        }
                    } else if b < 128 {
                        let p = b - 64
                        tm |= val << p
                        if p + 8 > 64 {
                            th |= val >> (64 - p)
                        }
                    } else {
                        th |= val << (b - 128)
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
                        tm |= val >> (64 - b)
                    }
                } else if b < 128 {
                    let p = b - 64
                    tm |= val << p
                    if p + 8 > 64 {
                        th |= val >> (64 - p)
                    }
                } else {
                    th |= val << (b - 128)
                }
                b += dBits
                u = (byte == 0xFF)
            }
        }

        readIndex = rIdx
        tmp = t
        tmpMid = tm
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
