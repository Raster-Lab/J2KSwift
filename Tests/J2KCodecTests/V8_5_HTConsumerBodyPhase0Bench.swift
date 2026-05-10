// V8_5_HTConsumerBodyPhase0Bench.swift
//
// v8.5 Phase 0 — definitive cost measurement of the HT-conformant
// block decoder's per-quad read pattern. Asks one question: is
// batching 4× `magsgnDec.read(count: m_i)` calls into ONE wider
// read worth the implementation work?
//
// The "consumer body" — `readQuadSamples` in
// `J2KHTConformantBlockDecoder.swift` — issues up to 4 sequential
// `read(count:)` calls per quad (gated by `rho` bits). Each call
// pays its own refill check + bit-buffer shift + mask + decrement.
// Algorithmic-redesign hypothesis: collapse the 4 reads into ONE
// `read(count: m0+m1+m2+m3)` and split the result manually via
// shifts + masks. Saves 3× per-call overhead.
//
// This phase measures the per-call overhead at the
// `HTMagSgnDecoderConformant.read` API surface — the exact code
// the consumer body invokes — so we can project upper-bound DX
// wall savings BEFORE building Phase 1A's prototype.
//
// Decision rule:
//   - If "4 reads − 1 batched read" delta is ≥ 10 ns/quad
//     (projects to ≥ 3 ms DX wall after parallelism), proceed
//     to Phase 1A.
//   - If < 10 ns/quad, document as projected wash and close.

#if os(macOS)

import XCTest
@testable import J2KCodec

final class V8_5_HTConsumerBodyPhase0Bench: XCTestCase {

    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func makeMagSgnBytes(byteCount: Int, seed: UInt64) -> [UInt8] {
        var rng = SplitMix64(seed: seed)
        var out = [UInt8]()
        out.reserveCapacity(byteCount)
        var lastWasFF = false
        for _ in 0..<byteCount {
            var b = UInt8(truncatingIfNeeded: rng.next() & 0xFF)
            if lastWasFF { b &= 0x7F }
            out.append(b)
            lastWasFF = (b == 0xFF)
        }
        return out
    }

    /// Bench `runs * 4` reads — the current consumer-body shape.
    /// Each iteration runs 4 sequential `read(count:)` calls with
    /// varying widths (mimicking the `m0..m3` per-quad m values).
    private func bench4Reads(
        bytes: [UInt8], widths: [Int],
        iterations: Int
    ) -> Double {
        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        let bytesNeeded = widths.reduce(0, +) / 8 + 4
        let resetEvery = max(1, bytes.count / bytesNeeded / 2)
        var sink: UInt64 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            let p0 = dec.read(count: widths[0])
            let p1 = dec.read(count: widths[1])
            let p2 = dec.read(count: widths[2])
            let p3 = dec.read(count: widths[3])
            sink &+= UInt64(p0) &+ UInt64(p1) &+ UInt64(p2) &+ UInt64(p3)
            i &+= 1
            if i % resetEvery == 0 {
                dec = HTMagSgnDecoderConformant(bytes: bytes)
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt64.max - 1)
        // Return ns per quad (= 4 reads).
        return Double(dt) / Double(iterations)
    }

    /// Bench batched: ONE `read(count: total)` followed by manual
    /// shift+mask split into 4 payloads. Same total bits consumed
    /// per iteration as `bench4Reads`, just fewer API calls.
    /// Splits via UInt64 because total can exceed 32 bits.
    private func benchBatched(
        bytes: [UInt8], widths: [Int],
        iterations: Int
    ) -> Double {
        var dec = HTMagSgnDecoderConformant(bytes: bytes)
        let bytesNeeded = widths.reduce(0, +) / 8 + 4
        let resetEvery = max(1, bytes.count / bytesNeeded / 2)
        let total = widths.reduce(0, +)
        // Workaround: read(count:) caps at 32. For widths summing
        // > 32, do two reads. (Production prototype would use a
        // new `read64` variant; this bench approximates with two
        // 32-bit reads + shift-merge.)
        var sink: UInt64 = 0
        let t0 = DispatchTime.now()
        var i = 0
        while i < iterations {
            let combined: UInt64
            if total <= 32 {
                combined = UInt64(dec.read(count: total))
            } else {
                let lo = UInt64(dec.read(count: 32))
                let hi = UInt64(dec.read(count: total - 32))
                combined = lo | (hi << 32)
            }
            // Split into 4 payloads.
            var c = combined
            let m0 = widths[0], m1 = widths[1]
            let m2 = widths[2], m3 = widths[3]
            let p0 = c & ((UInt64(1) << m0) - 1); c >>= m0
            let p1 = c & ((UInt64(1) << m1) - 1); c >>= m1
            let p2 = c & ((UInt64(1) << m2) - 1); c >>= m2
            let p3 = c & ((UInt64(1) << m3) - 1)
            sink &+= p0 &+ p1 &+ p2 &+ p3
            i &+= 1
            if i % resetEvery == 0 {
                dec = HTMagSgnDecoderConformant(bytes: bytes)
            }
        }
        let dt = DispatchTime.now().uptimeNanoseconds &- t0.uptimeNanoseconds
        XCTAssertNotEqual(sink, UInt64.max - 1)
        return Double(dt) / Double(iterations)
    }

    /// Parity check: the batched-and-split version produces the
    /// same 4 payloads as the 4-reads version on the same input
    /// bytes + widths.
    func testParity_4Reads_vs_Batched() {
        let bytes = makeMagSgnBytes(byteCount: 4 * 1024, seed: 0x1234)
        let widthSets: [[Int]] = [
            [3, 3, 3, 3],     // total 12
            [7, 5, 3, 1],     // total 16
            [10, 10, 10, 10], // total 40 — needs 2 reads
            [14, 14, 14, 14], // total 56
            [16, 8, 16, 8],   // total 48
            [4, 0, 0, 0],     // total 4 (only one significant)
        ]
        for widths in widthSets {
            // Path 1: 4 sequential reads.
            var d1 = HTMagSgnDecoderConformant(bytes: bytes)
            let p0a = d1.read(count: widths[0])
            let p1a = d1.read(count: widths[1])
            let p2a = d1.read(count: widths[2])
            let p3a = d1.read(count: widths[3])
            // Path 2: batched + split.
            var d2 = HTMagSgnDecoderConformant(bytes: bytes)
            let total = widths.reduce(0, +)
            let combined: UInt64
            if total <= 32 {
                combined = UInt64(d2.read(count: total))
            } else {
                let lo = UInt64(d2.read(count: 32))
                let hi = UInt64(d2.read(count: total - 32))
                combined = lo | (hi << 32)
            }
            var c = combined
            let m0 = widths[0], m1 = widths[1], m2 = widths[2], m3 = widths[3]
            let p0b = UInt32(c & ((UInt64(1) << m0) - 1)); c >>= m0
            let p1b = UInt32(c & ((UInt64(1) << m1) - 1)); c >>= m1
            let p2b = UInt32(c & ((UInt64(1) << m2) - 1)); c >>= m2
            let p3b = UInt32(c & ((UInt64(1) << m3) - 1))
            // Special-case widths[i]=0: read(count:0) returns 0,
            // batched split also returns 0 — both paths consistent.
            XCTAssertEqual(p0a, p0b, "widths=\(widths) p0 mismatch")
            XCTAssertEqual(p1a, p1b, "widths=\(widths) p1 mismatch")
            XCTAssertEqual(p2a, p2b, "widths=\(widths) p2 mismatch")
            XCTAssertEqual(p3a, p3b, "widths=\(widths) p3 mismatch")
        }
    }

    /// Headline measurement (simplified inline): per-quad cost.
    /// Apple Silicon M2 release-mode.
    func testBench_4Reads_vs_Batched_Simple() {
        let bytes = makeMagSgnBytes(byteCount: 64 * 1024, seed: 0xC0FFEE)
        let iterations = 10_000

        // 4-reads (typical 4×7 = 28-bit/quad shape).
        var dec1 = HTMagSgnDecoderConformant(bytes: bytes)
        var sink1: UInt64 = 0
        let t1 = DispatchTime.now()
        var i = 0
        while i < iterations {
            sink1 &+= UInt64(dec1.read(count: 7))
            sink1 &+= UInt64(dec1.read(count: 7))
            sink1 &+= UInt64(dec1.read(count: 7))
            sink1 &+= UInt64(dec1.read(count: 7))
            i &+= 1
        }
        let dt1 = Double(DispatchTime.now().uptimeNanoseconds &- t1.uptimeNanoseconds) / Double(iterations)

        // Batched (one 28-bit read + manual split).
        var dec2 = HTMagSgnDecoderConformant(bytes: bytes)
        var sink2: UInt64 = 0
        let t2 = DispatchTime.now()
        var j = 0
        while j < iterations {
            let combined = UInt64(dec2.read(count: 28))
            let p0 = combined & 0x7F
            let p1 = (combined >> 7) & 0x7F
            let p2 = (combined >> 14) & 0x7F
            let p3 = (combined >> 21) & 0x7F
            sink2 &+= p0 &+ p1 &+ p2 &+ p3
            j &+= 1
        }
        let dt2 = Double(DispatchTime.now().uptimeNanoseconds &- t2.uptimeNanoseconds) / Double(iterations)

        XCTAssertNotEqual(sink1, UInt64.max - 1)
        XCTAssertNotEqual(sink2, UInt64.max - 1)

        let delta = dt1 - dt2
        let savedAccUs = delta * 800_000.0 / 1000.0
        let savedWallMs = savedAccUs / 1000.0 / 5.0

        print()
        print("=== v8.5 Phase 0 — per-quad cost (simple, 4×7-bit shape) ===")
        print(String(format: "  4-reads:     %.2f ns/quad", dt1))
        print(String(format: "  batched:     %.2f ns/quad", dt2))
        print(String(format: "  Δ:           %+.2f ns/quad", delta))
        print()
        print("Projection to DX 2800×2288 wall (~800 K quads at ~50 % rho):")
        print(String(format: "  Accumulated CPU savings: ~%.0f µs", savedAccUs))
        print(String(format: "  Wall savings (÷5 parallelism per v8.4): ~%.2f ms", savedWallMs))
        print()
        if savedWallMs >= 3.0 {
            print("  ⇒ ≥ 3 ms threshold MET. Phase 1A justified.")
        } else {
            print("  ⇒ ≥ 3 ms threshold NOT MET. Close v8.5 with projected wash.")
        }
    }
}

#endif
