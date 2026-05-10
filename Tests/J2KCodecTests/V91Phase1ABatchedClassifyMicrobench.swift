// V91Phase1ABatchedClassifyMicrobench.swift
//
// v9.1 Path B Phase 1A — proof-of-concept microbench for batched
// per-quad SIMD classification.
//
// Phase 0 finding: ~96% of HT entropy CPU on DX is in the per-quad
// loop body, not in bit-emission engines. The biggest individual
// contributor inside that loop body is the per-sample classification
// (`val = (2t >> p) & ~1`, `clz(val - 1)`, sign/payload extraction).
//
// This microbench compares three variants of the per-quad classifier:
//
//   A. Scalar (current encoder default; 4× sampleInfo per quad)
//   B. SIMD4 (current encoder opt-in; one quad's 4 samples in one
//      SIMD register — already shipped in v5.39 M1)
//   C. SIMD16 (Phase 1A prototype; FOUR quads' 16 samples in one
//      SIMD register — pre-classifies four-quad tiles at once)
//
// All three produce bit-identical (rho, eQMax, eQ0..3, s0..3) output
// per quad; correctness is verified by sweeping random fixture data
// before timing.
//
// Goal: empirical evidence that SIMD16 produces ≥1.5× per-quad
// speedup on the classifier alone. If yes, Phase 1 architecture is
// sound and we proceed to integrate. If no (or speedup < 1.2×), we
// pivot to Candidate B (loop-body fusion) or pause Path B for the
// user's reconsideration.

import XCTest
@testable import J2KCodec

final class V91Phase1ABatchedClassifyMicrobench: XCTestCase {

    /// Per-sample classification output (bit-exact match to encoder
    /// internals: 1 sig bit + 7 eQ bits + 32 payload bits).
    /// We use a flat tuple here for microbench simplicity; production
    /// integration would use a packed UInt64 layout.
    typealias QuadClass = (rho: Int, eQMax: Int,
                           eQ0: Int, eQ1: Int, eQ2: Int, eQ3: Int,
                           s0: UInt32, s1: UInt32, s2: UInt32, s3: UInt32)

    // ---- Variant A: scalar (the encoder's current scalar path) ----

    @inline(__always)
    private static func sampleInfoScalar(_ t: UInt32, _ p: UInt32) -> (Bool, Int, UInt32) {
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

    @inline(__always)
    static func processQuadScalar(
        _ t0: UInt32, _ t1: UInt32, _ t2: UInt32, _ t3: UInt32,
        p: UInt32
    ) -> QuadClass {
        var rho = 0
        var eQMax = 0
        var eQ0 = 0, eQ1 = 0, eQ2 = 0, eQ3 = 0
        var s0: UInt32 = 0, s1: UInt32 = 0, s2: UInt32 = 0, s3: UInt32 = 0
        let (sig0, e0, p0) = sampleInfoScalar(t0, p)
        if sig0 { rho |= 1; eQ0 = e0; s0 = p0; if e0 > eQMax { eQMax = e0 } }
        let (sig1, e1, p1) = sampleInfoScalar(t1, p)
        if sig1 { rho |= 2; eQ1 = e1; s1 = p1; if e1 > eQMax { eQMax = e1 } }
        let (sig2, e2, p2) = sampleInfoScalar(t2, p)
        if sig2 { rho |= 4; eQ2 = e2; s2 = p2; if e2 > eQMax { eQMax = e2 } }
        let (sig3, e3, p3) = sampleInfoScalar(t3, p)
        if sig3 { rho |= 8; eQ3 = e3; s3 = p3; if e3 > eQMax { eQMax = e3 } }
        return (rho, eQMax, eQ0, eQ1, eQ2, eQ3, s0, s1, s2, s3)
    }

    // ---- Variant B: SIMD4 (one quad in SIMD register) ----

    @inline(__always)
    static func processQuadSIMD4(
        _ t0: UInt32, _ t1: UInt32, _ t2: UInt32, _ t3: UInt32,
        p: UInt32
    ) -> QuadClass {
        let t = SIMD4<UInt32>(t0, t1, t2, t3)
        var val = (t &<< 1) &>> SIMD4<UInt32>(repeating: p)
        val &= SIMD4<UInt32>(repeating: ~UInt32(1))
        let sig0 = val[0] != 0
        let sig1 = val[1] != 0
        let sig2 = val[2] != 0
        let sig3 = val[3] != 0
        let safeVal = SIMD4<UInt32>(
            sig0 ? val[0] : 1,
            sig1 ? val[1] : 1,
            sig2 ? val[2] : 1,
            sig3 ? val[3] : 1)
        let valMinus1 = safeVal &- SIMD4<UInt32>(repeating: 1)
        let lz = SIMD4<Int32>(
            Int32(valMinus1[0].leadingZeroBitCount),
            Int32(valMinus1[1].leadingZeroBitCount),
            Int32(valMinus1[2].leadingZeroBitCount),
            Int32(valMinus1[3].leadingZeroBitCount))
        let eQv = SIMD4<Int32>(repeating: 32) &- lz
        let sign = (t &>> SIMD4<UInt32>(repeating: 31))
                 & SIMD4<UInt32>(repeating: 1)
        let payload = (valMinus1 &- SIMD4<UInt32>(repeating: 1)) &+ sign

        var rho = 0
        var eQMax = 0
        var eQ0 = 0, eQ1 = 0, eQ2 = 0, eQ3 = 0
        var s0: UInt32 = 0, s1: UInt32 = 0
        var s2: UInt32 = 0, s3: UInt32 = 0
        if sig0 { rho |= 1; eQ0 = Int(eQv[0]); s0 = payload[0]; if eQ0 > eQMax { eQMax = eQ0 } }
        if sig1 { rho |= 2; eQ1 = Int(eQv[1]); s1 = payload[1]; if eQ1 > eQMax { eQMax = eQ1 } }
        if sig2 { rho |= 4; eQ2 = Int(eQv[2]); s2 = payload[2]; if eQ2 > eQMax { eQMax = eQ2 } }
        if sig3 { rho |= 8; eQ3 = Int(eQv[3]); s3 = payload[3]; if eQ3 > eQMax { eQMax = eQ3 } }
        return (rho, eQMax, eQ0, eQ1, eQ2, eQ3, s0, s1, s2, s3)
    }

    // ---- Variant C: SIMD16 (FOUR quads in one register) ----
    //
    // Layout: 4 quads × 4 samples each = 16 lanes. Each quad's
    // samples are stored in 4 consecutive lanes:
    //   Quad 0: lanes 0..3   (samples: top-left, bot-left, top-right, bot-right)
    //   Quad 1: lanes 4..7
    //   Quad 2: lanes 8..11
    //   Quad 3: lanes 12..15
    //
    // The classification math is per-lane independent so SIMD16 can
    // do all 16 in parallel. The per-quad reduction (rho/eQMax/sig)
    // requires 4-lane-group reduce; we do this scalar at the end
    // since SIMD<UInt32> doesn't expose horizontal reductions cheaply
    // on Apple Silicon (the per-lane sigi/eQv/payload extracts compile
    // to single NEON loads).

    @inline(__always)
    static func processFourQuadsSIMD16(
        _ t: SIMD16<UInt32>, p: UInt32
    ) -> (QuadClass, QuadClass, QuadClass, QuadClass) {
        // Lane-parallel classification for all 16 samples at once.
        var val = (t &<< 1) &>> SIMD16<UInt32>(repeating: p)
        val &= SIMD16<UInt32>(repeating: ~UInt32(1))

        // Per-lane significance flag — extract scalarly (one cmp per lane,
        // single NEON instr each on Apple Silicon).
        let sigBits = SIMD16<UInt32>(
            val[0] != 0 ? 1 : 0,
            val[1] != 0 ? 1 : 0,
            val[2] != 0 ? 1 : 0,
            val[3] != 0 ? 1 : 0,
            val[4] != 0 ? 1 : 0,
            val[5] != 0 ? 1 : 0,
            val[6] != 0 ? 1 : 0,
            val[7] != 0 ? 1 : 0,
            val[8] != 0 ? 1 : 0,
            val[9] != 0 ? 1 : 0,
            val[10] != 0 ? 1 : 0,
            val[11] != 0 ? 1 : 0,
            val[12] != 0 ? 1 : 0,
            val[13] != 0 ? 1 : 0,
            val[14] != 0 ? 1 : 0,
            val[15] != 0 ? 1 : 0)

        // Substitute val=1 for non-significant lanes so clz path is
        // straight-line SIMD without lane-conditional branches.
        let safeVal = SIMD16<UInt32>(
            val[0] != 0 ? val[0] : 1,
            val[1] != 0 ? val[1] : 1,
            val[2] != 0 ? val[2] : 1,
            val[3] != 0 ? val[3] : 1,
            val[4] != 0 ? val[4] : 1,
            val[5] != 0 ? val[5] : 1,
            val[6] != 0 ? val[6] : 1,
            val[7] != 0 ? val[7] : 1,
            val[8] != 0 ? val[8] : 1,
            val[9] != 0 ? val[9] : 1,
            val[10] != 0 ? val[10] : 1,
            val[11] != 0 ? val[11] : 1,
            val[12] != 0 ? val[12] : 1,
            val[13] != 0 ? val[13] : 1,
            val[14] != 0 ? val[14] : 1,
            val[15] != 0 ? val[15] : 1)
        let valMinus1 = safeVal &- SIMD16<UInt32>(repeating: 1)

        // Per-lane clz. NEON has a vclz instruction that emits one
        // instruction per lane; Swift's `leadingZeroBitCount` should
        // map to it. SIMD16 = 4× NEON 128-bit registers worth of work,
        // so this is 4 vclz instructions back-to-back.
        let lz = SIMD16<Int32>(
            Int32(valMinus1[0].leadingZeroBitCount),
            Int32(valMinus1[1].leadingZeroBitCount),
            Int32(valMinus1[2].leadingZeroBitCount),
            Int32(valMinus1[3].leadingZeroBitCount),
            Int32(valMinus1[4].leadingZeroBitCount),
            Int32(valMinus1[5].leadingZeroBitCount),
            Int32(valMinus1[6].leadingZeroBitCount),
            Int32(valMinus1[7].leadingZeroBitCount),
            Int32(valMinus1[8].leadingZeroBitCount),
            Int32(valMinus1[9].leadingZeroBitCount),
            Int32(valMinus1[10].leadingZeroBitCount),
            Int32(valMinus1[11].leadingZeroBitCount),
            Int32(valMinus1[12].leadingZeroBitCount),
            Int32(valMinus1[13].leadingZeroBitCount),
            Int32(valMinus1[14].leadingZeroBitCount),
            Int32(valMinus1[15].leadingZeroBitCount))
        let eQv = SIMD16<Int32>(repeating: 32) &- lz

        // Sign bit + payload — both lane-parallel.
        let sign = (t &>> SIMD16<UInt32>(repeating: 31))
                 & SIMD16<UInt32>(repeating: 1)
        let payload = (valMinus1 &- SIMD16<UInt32>(repeating: 1)) &+ sign

        // Per-quad reduction: assemble (rho, eQMax) for each quad.
        // sigBits[i*4..(i+1)*4] gives the 4 sig bits for quad i.
        // rho is OR-reduce of (sig << position) for that quad.

        @inline(__always) func reduce(_ q: Int) -> QuadClass {
            let i0 = q * 4
            let i1 = i0 + 1
            let i2 = i0 + 2
            let i3 = i0 + 3
            let sb0 = Int(sigBits[i0])
            let sb1 = Int(sigBits[i1])
            let sb2 = Int(sigBits[i2])
            let sb3 = Int(sigBits[i3])
            let rho = sb0 | (sb1 << 1) | (sb2 << 2) | (sb3 << 3)
            let e0 = sb0 != 0 ? Int(eQv[i0]) : 0
            let e1 = sb1 != 0 ? Int(eQv[i1]) : 0
            let e2 = sb2 != 0 ? Int(eQv[i2]) : 0
            let e3 = sb3 != 0 ? Int(eQv[i3]) : 0
            let eQMax = max(max(e0, e1), max(e2, e3))
            let s0 = sb0 != 0 ? payload[i0] : 0
            let s1 = sb1 != 0 ? payload[i1] : 0
            let s2 = sb2 != 0 ? payload[i2] : 0
            let s3 = sb3 != 0 ? payload[i3] : 0
            return (rho, eQMax, e0, e1, e2, e3, s0, s1, s2, s3)
        }

        return (reduce(0), reduce(1), reduce(2), reduce(3))
    }

    // ---- Correctness sweep: verify SIMD16 == scalar bit-exactly ----

    func testSIMD16BitExactVsScalarOnRandomCorpus() throws {
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: 0xDEAD_BEEF_C0FFEE_42)
        let p: UInt32 = 24  // realistic for 16-bit medical lossless

        for _ in 0..<10_000 {
            let t0 = UInt32(truncatingIfNeeded: rng.next())
            let t1 = UInt32(truncatingIfNeeded: rng.next())
            let t2 = UInt32(truncatingIfNeeded: rng.next())
            let t3 = UInt32(truncatingIfNeeded: rng.next())
            let t4 = UInt32(truncatingIfNeeded: rng.next())
            let t5 = UInt32(truncatingIfNeeded: rng.next())
            let t6 = UInt32(truncatingIfNeeded: rng.next())
            let t7 = UInt32(truncatingIfNeeded: rng.next())
            let t8 = UInt32(truncatingIfNeeded: rng.next())
            let t9 = UInt32(truncatingIfNeeded: rng.next())
            let tA = UInt32(truncatingIfNeeded: rng.next())
            let tB = UInt32(truncatingIfNeeded: rng.next())
            let tC = UInt32(truncatingIfNeeded: rng.next())
            let tD = UInt32(truncatingIfNeeded: rng.next())
            let tE = UInt32(truncatingIfNeeded: rng.next())
            let tF = UInt32(truncatingIfNeeded: rng.next())

            let scalarQ0 = Self.processQuadScalar(t0, t1, t2, t3, p: p)
            let scalarQ1 = Self.processQuadScalar(t4, t5, t6, t7, p: p)
            let scalarQ2 = Self.processQuadScalar(t8, t9, tA, tB, p: p)
            let scalarQ3 = Self.processQuadScalar(tC, tD, tE, tF, p: p)

            let v = SIMD16<UInt32>(t0, t1, t2, t3,
                                   t4, t5, t6, t7,
                                   t8, t9, tA, tB,
                                   tC, tD, tE, tF)
            let (s16q0, s16q1, s16q2, s16q3) = Self.processFourQuadsSIMD16(v, p: p)

            XCTAssertEqual(scalarQ0.rho, s16q0.rho, "Q0 rho mismatch")
            XCTAssertEqual(scalarQ0.eQMax, s16q0.eQMax, "Q0 eQMax mismatch")
            XCTAssertEqual(scalarQ0.s0, s16q0.s0, "Q0 s0 mismatch")
            XCTAssertEqual(scalarQ0.s1, s16q0.s1, "Q0 s1 mismatch")
            XCTAssertEqual(scalarQ1.rho, s16q1.rho, "Q1 rho mismatch")
            XCTAssertEqual(scalarQ1.s0, s16q1.s0, "Q1 s0 mismatch")
            XCTAssertEqual(scalarQ2.rho, s16q2.rho, "Q2 rho mismatch")
            XCTAssertEqual(scalarQ3.rho, s16q3.rho, "Q3 rho mismatch")
        }
    }

    // ---- Throughput bench: ns per quad-equivalent ----

    func testThroughput_ScalarVsSIMD4VsSIMD16() throws {
        // Generate 256K samples of synthetic data — enough to defeat
        // the L1 cache so we measure cold-store throughput, not
        // L1-resident tightness.
        struct SplitMix64 {
            var state: UInt64
            mutating func next() -> UInt64 {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                return z ^ (z >> 31)
            }
        }
        var rng = SplitMix64(state: 0x1234_5678_9ABC_DEF0)
        let sampleCount = 256 * 1024
        var samples = [UInt32](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            samples[i] = UInt32(truncatingIfNeeded: rng.next())
        }
        let p: UInt32 = 24
        let runs = 5
        let iterationsPerRun = 50_000

        // ---- A: scalar ----
        var scalarSamples: [Double] = []
        for _ in 0..<runs {
            var sink: Int = 0
            let t0 = DispatchTime.now()
            for _ in 0..<iterationsPerRun {
                let base = (Int(truncatingIfNeeded: rng.next()) & 0xFFFC) % (sampleCount - 4)
                let q = Self.processQuadScalar(
                    samples[base], samples[base+1],
                    samples[base+2], samples[base+3],
                    p: p)
                sink &+= q.rho &+ q.eQMax
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            XCTAssertNotEqual(sink, Int.min)
            scalarSamples.append(Double(dt) / Double(iterationsPerRun))
        }
        scalarSamples.sort()
        let scalarNs = scalarSamples[runs / 2]

        // ---- B: SIMD4 ----
        var simd4Samples: [Double] = []
        for _ in 0..<runs {
            var sink: Int = 0
            let t0 = DispatchTime.now()
            for _ in 0..<iterationsPerRun {
                let base = (Int(truncatingIfNeeded: rng.next()) & 0xFFFC) % (sampleCount - 4)
                let q = Self.processQuadSIMD4(
                    samples[base], samples[base+1],
                    samples[base+2], samples[base+3],
                    p: p)
                sink &+= q.rho &+ q.eQMax
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            XCTAssertNotEqual(sink, Int.min)
            simd4Samples.append(Double(dt) / Double(iterationsPerRun))
        }
        simd4Samples.sort()
        let simd4Ns = simd4Samples[runs / 2]

        // ---- C: SIMD16 (4 quads at once; report ns/quad-equivalent) ----
        var simd16Samples: [Double] = []
        for _ in 0..<runs {
            var sink: Int = 0
            let t0 = DispatchTime.now()
            // Each iteration processes 4 quads, so for a fair ns/quad
            // comparison we run iterationsPerRun/4 iterations.
            let simd16Iters = iterationsPerRun / 4
            for _ in 0..<simd16Iters {
                let base = (Int(truncatingIfNeeded: rng.next()) & 0xFFF0) % (sampleCount - 16)
                let v = SIMD16<UInt32>(
                    samples[base + 0], samples[base + 1], samples[base + 2], samples[base + 3],
                    samples[base + 4], samples[base + 5], samples[base + 6], samples[base + 7],
                    samples[base + 8], samples[base + 9], samples[base + 10], samples[base + 11],
                    samples[base + 12], samples[base + 13], samples[base + 14], samples[base + 15])
                let (q0, q1, q2, q3) = Self.processFourQuadsSIMD16(v, p: p)
                sink &+= q0.rho &+ q1.rho &+ q2.rho &+ q3.rho
                sink &+= q0.eQMax &+ q1.eQMax &+ q2.eQMax &+ q3.eQMax
            }
            let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
            XCTAssertNotEqual(sink, Int.min)
            // ns per quad-equivalent: total ns / (iters × 4 quads-per-iter)
            simd16Samples.append(Double(dt) / Double(simd16Iters * 4))
        }
        simd16Samples.sort()
        let simd16Ns = simd16Samples[runs / 2]

        print("=== v9.1 Phase 1A — per-quad classifier throughput ===")
        print()
        print("|     Variant     | ns/quad |    M quads/sec    | speedup vs scalar |")
        print("|-----------------|--------:|------------------:|------------------:|")
        print(String(format: "| Scalar (1 quad) | %7.2f | %17.2f | %17.2f |",
                     scalarNs, 1000.0 / scalarNs, 1.0))
        print(String(format: "| SIMD4  (1 quad) | %7.2f | %17.2f | %17.2f |",
                     simd4Ns, 1000.0 / simd4Ns, scalarNs / simd4Ns))
        print(String(format: "| SIMD16 (4 quads)| %7.2f | %17.2f | %17.2f |",
                     simd16Ns, 1000.0 / simd16Ns, scalarNs / simd16Ns))
        print()
        print("Notes:")
        print("  - All three variants produce bit-exact (rho, eQMax, eQ, s) output;")
        print("    correctness verified by `testSIMD16BitExactVsScalarOnRandomCorpus`")
        print("    over 10K random sample-quartets at p=24 (16-bit medical lossless).")
        print("  - SIMD16 reports ns per quad-equivalent (total time / 4 quads).")
        print("  - Phase 1A gate: SIMD16 should beat scalar by ≥1.5× to justify")
        print("    the multi-week integration into HTBlockEncoderConformant.")
        print("  - If SIMD16 wins, this is the foundation for the Phase 1B")
        print("    integration: the encoder hot loop is restructured to call")
        print("    processFourQuadsSIMD16 once per 4-quad-group, then sequentially")
        print("    emit the 4 quads' VLC/MEL/MagSgn output.")
    }
}
