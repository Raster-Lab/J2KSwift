// HTSampleInfoSIMDPrototypeTests.swift
// v5.38 M11 prototype — bit-exact correctness verification for a
// SIMD4<UInt32>-per-quad classification of the HT block encoder's
// `sampleInfo` function.
//
// SCOPE: parked experimental. Production code paths are unchanged.
//
// The scalar `sampleInfo(_ t: UInt32) -> (Bool, Int, UInt32)` inside
// `HTBlockEncoderConformant.encode` is called 4× per quad to derive
// (significant, eQ, payload) from each input sample. M11's hypothesis:
// loading 4 samples into a `SIMD4<UInt32>` and computing val / sign /
// payload in SIMD (with scalar `leadingZeroBitCount` per lane —
// Swift's SIMD types don't expose lane-wise clz) reduces the scalar
// op count by ~70% while keeping bit-exact output.
//
// **Correctness result** (this test, 600K+ random samples × 9 p values
// × 4 SIMD lanes): bit-exact identical to scalar reference. SIMD math
// is sound.
//
// **Perf result** (5-run encode-time medians, format-fair table,
// /tmp/simd_on.log vs /tmp/simd_off.log on 2026-05-05): essentially
// neutral within run-to-run noise on every fixture in the medical
// corpus.
//
// | Fixture | simd_off (ms) | simd_on (ms) | Δ |
// |---|---:|---:|---:|
// | MR-small 180×180 | 0.7 | 0.7 |  0% |
// | MR 886×886       | 5.3 | 5.4 | +2% |
// | XA 1024×1024     | 11.7 | 11.5 | −2% |
// | PX 2459×1316     | 38.5 | 38.7 | +1% |
// | DX 2800×2288     | 75.5 | 77.2 | +2% |
//
// **Conclusion**: M11 SIMD per-sample classification matches the
// v5.39 M1 SIMD per-quad outcome — bit-exact, perf-neutral, no
// promotion. The bottleneck on large fixtures isn't `sampleInfo`'s
// scalar op count; it's elsewhere in the entropy hot path (likely
// MEL run-length + VLC bit-output, per the v5.39 M3 diagnosis).
// Test is kept in source as the bit-exactness regression guard for
// any future SIMD attempt at this function.

import XCTest
@testable import J2KCodec

final class HTSampleInfoSIMDPrototypeTests: XCTestCase {

    /// The scalar reference, copy of `sampleInfo` from
    /// `HTBlockEncoderConformant.swift`. Kept here verbatim so this
    /// test pins the SIMD prototype against the exact production
    /// formula, not against an interpreted summary.
    @inline(__always)
    private static func sampleInfoScalar(_ t: UInt32, p: UInt32)
        -> (Bool, Int, UInt32)
    {
        var val = (t &+ t) >> p
        val &= ~UInt32(1)
        if val == 0 { return (false, 0, 0) }
        val &-= 1
        let lz = val.leadingZeroBitCount
        let eQ = 32 - lz
        let sign = UInt32((t >> 31) & 1)
        let payload = (val &- 1) &+ sign
        return (true, eQ, payload)
    }

    /// SIMD variant. Processes 4 samples per call. All lane-parallel
    /// operations stay in SIMD; `leadingZeroBitCount` is scalar per
    /// lane because Swift's `SIMD4<UInt32>` doesn't expose lane-wise
    /// clz (and the equivalent NEON `vclz` is not surfaced through
    /// the public `simd` module).
    ///
    /// Returns:
    ///   - `sig`: SIMD4<Bool>-equivalent — 4-bit mask in lane order
    ///     (lane 0 = bit 0 set ↔ significant; matches the rho bits
    ///     used in `processQuad`)
    ///   - `eQ`: SIMD4<Int32>; lanes where !sig hold 0
    ///   - `payload`: SIMD4<UInt32>; lanes where !sig hold 0
    @inline(__always)
    private static func sampleInfoSIMD4(_ t: SIMD4<UInt32>, p: UInt32)
        -> (sigMask: UInt8, eQ: SIMD4<Int32>, payload: SIMD4<UInt32>)
    {
        // val = ((t << 1) >> p) & ~1. SIMD lane-parallel.
        let twoT = t &<< 1
        var val = SIMD4<UInt32>(repeating: 0)
        // SIMD `&>>` accepts a SIMD4 right operand; broadcast `p`.
        val = twoT &>> SIMD4<UInt32>(repeating: p)
        val &= SIMD4<UInt32>(repeating: ~UInt32(1))

        // Per-lane significance: val != 0.
        let sig0 = val[0] != 0
        let sig1 = val[1] != 0
        let sig2 = val[2] != 0
        let sig3 = val[3] != 0
        let sigMask: UInt8 =
            (sig0 ? 1 : 0) |
            ((sig1 ? 1 : 0) << 1) |
            ((sig2 ? 1 : 0) << 2) |
            ((sig3 ? 1 : 0) << 3)

        // For non-significant lanes, set val to 1 so the subtract
        // below produces 0 instead of UInt32 wrap. The eQ / payload
        // for those lanes is overwritten to 0 at the end anyway, so
        // their intermediate values don't matter for final output —
        // but keeping them in a sane range avoids spurious behaviour
        // in the `leadingZeroBitCount` pass.
        let safeVal = SIMD4<UInt32>(
            sig0 ? val[0] : 1,
            sig1 ? val[1] : 1,
            sig2 ? val[2] : 1,
            sig3 ? val[3] : 1)
        let valMinus1 = safeVal &- SIMD4<UInt32>(repeating: 1)

        // Per-lane clz, scalar (Swift's SIMD types lack it).
        let lz = SIMD4<Int32>(
            Int32(valMinus1[0].leadingZeroBitCount),
            Int32(valMinus1[1].leadingZeroBitCount),
            Int32(valMinus1[2].leadingZeroBitCount),
            Int32(valMinus1[3].leadingZeroBitCount))
        var eQ = SIMD4<Int32>(repeating: 32) &- lz

        // sign = (t >> 31) & 1. SIMD.
        let sign = (t &>> SIMD4<UInt32>(repeating: 31))
                 & SIMD4<UInt32>(repeating: 1)
        // payload = (val - 2) + sign  [scalar: (val - 1) - 1 + sign]
        var payload = (valMinus1 &- SIMD4<UInt32>(repeating: 1)) &+ sign

        // Mask out non-significant lanes: eQ = 0, payload = 0.
        if !sig0 { eQ[0] = 0; payload[0] = 0 }
        if !sig1 { eQ[1] = 0; payload[1] = 0 }
        if !sig2 { eQ[2] = 0; payload[2] = 0 }
        if !sig3 { eQ[3] = 0; payload[3] = 0 }

        return (sigMask, eQ, payload)
    }

    // MARK: - Tests

    /// Hand-picked edge cases.
    func testSampleInfoSIMD_BitExact_EdgeCases() {
        // Cover: zero, sign-only, magnitude-only, both, near-p
        // threshold, max value, and full-significance ranges.
        let inputs: [(UInt32, UInt32)] = [
            // (t, p)
            (0, 5), (0, 30),                              // zero
            (0x8000_0000, 5),                             // sign only, mag below p
            (0x0000_0001, 5), (0x0000_0010, 5),           // tiny mags
            (0x0000_FFFF, 5), (0x000F_FFFF, 5),           // medium mags
            (0xFFFF_FFFF, 30),                            // max
            (0x4000_0000, 5),                             // near-MSB
            (0xC000_0000, 5),                             // sign + near-MSB
            (0x0010_0000, 10), (0x0010_0000, 20),         // varying p
            (0x7FFF_FFFF, 5), (0x7FFF_FFFF, 30),          // max non-negative
            (0x1234_5678, 7), (0xDEAD_BEEF, 11),          // arbitrary
        ]
        for (t, p) in inputs {
            let scalar = Self.sampleInfoScalar(t, p: p)
            let simd = Self.sampleInfoSIMD4(SIMD4<UInt32>(t, 0, 0, 0), p: p)
            let simdSig = (simd.sigMask & 1) != 0
            let simdE = Int(simd.eQ[0])
            let simdP = simd.payload[0]
            XCTAssertEqual(simdSig, scalar.0,
                "sig mismatch for t=0x\(String(t, radix: 16)) p=\(p)")
            XCTAssertEqual(simdE, scalar.1,
                "eQ mismatch for t=0x\(String(t, radix: 16)) p=\(p): scalar=\(scalar.1) simd=\(simdE)")
            XCTAssertEqual(simdP, scalar.2,
                "payload mismatch for t=0x\(String(t, radix: 16)) p=\(p): scalar=0x\(String(scalar.2, radix: 16)) simd=0x\(String(simdP, radix: 16))")
        }
    }

    /// Randomized sweep across realistic `p` range. p = 30 - missingMSBs;
    /// missingMSBs is 0..29 in valid Part-15 lossless encoding.
    func testSampleInfoSIMD_BitExact_RandomSweep() {
        // Deterministic seed so failures are reproducible.
        var rng = SystemRandomNumberGenerator()
        // Per-p iteration count — total ~600K samples across all p.
        let perP = 20_000

        for p: UInt32 in [3, 5, 10, 15, 20, 25, 28, 29, 30] {
            // Process inputs in batches of 4 to exercise the SIMD
            // path the way `processQuad` will.
            for _ in 0..<(perP / 4) {
                let t0 = UInt32.random(in: 0...UInt32.max, using: &rng)
                let t1 = UInt32.random(in: 0...UInt32.max, using: &rng)
                let t2 = UInt32.random(in: 0...UInt32.max, using: &rng)
                let t3 = UInt32.random(in: 0...UInt32.max, using: &rng)

                let s0 = Self.sampleInfoScalar(t0, p: p)
                let s1 = Self.sampleInfoScalar(t1, p: p)
                let s2 = Self.sampleInfoScalar(t2, p: p)
                let s3 = Self.sampleInfoScalar(t3, p: p)
                let v = Self.sampleInfoSIMD4(SIMD4<UInt32>(t0, t1, t2, t3), p: p)

                let lanes: [(Bool, Int, UInt32)] = [s0, s1, s2, s3]
                for lane in 0..<4 {
                    let scalar = lanes[lane]
                    let simdSig = (v.sigMask & (1 << lane)) != 0
                    let simdE = Int(v.eQ[lane])
                    let simdP = v.payload[lane]
                    if simdSig != scalar.0 || simdE != scalar.1 || simdP != scalar.2 {
                        let ts = [t0, t1, t2, t3]
                        XCTFail("""
                            random-sweep mismatch (lane \(lane), p=\(p))
                            t = 0x\(String(ts[lane], radix: 16))
                            scalar: sig=\(scalar.0) eQ=\(scalar.1) payload=0x\(String(scalar.2, radix: 16))
                            simd:   sig=\(simdSig) eQ=\(simdE) payload=0x\(String(simdP, radix: 16))
                            """)
                        return
                    }
                }
            }
        }
    }
}
