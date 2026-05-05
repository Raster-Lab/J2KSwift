// HTInverseDWTParityAwarenessTests.swift
// v6-alpha3 step 6B slice 1 — focused unit tests for the
// parity-aware inverse 5/3 1D DWT primitive landed in
// `J2KDWT1DOptimized.inverseTransform53Optimized(...uOrigin:)`.
// Mirror of `HTDWTParityAwarenessTests` on the decode side.
//
// Anchors three invariants:
//
//   1. **Even-origin regression**: the parity-aware inverse, when
//      called with `uOrigin == 0` or any even value, produces
//      output bit-identical to the existing no-origin inverse
//      overload. Production single-tile and 32-aligned multi-tile
//      decode paths pay zero cost.
//
//   2. **Odd-origin reconstructibility**: forward (parity-aware)
//      then inverse (parity-aware) at the same odd origin recovers
//      the input bit-exactly. Pins the production inverse against
//      the test-reference inverse from
//      `HTDWT2DParityAwarenessTests` (which step 2's roundtrip
//      tests already validated).
//
//   3. **Cross-validation against the test reference**: for any
//      (n, u) combination the production inverse output equals
//      the test reference output byte-for-byte. The test reference
//      is the canonical spec implementation — agreement across all
//      probed cells gives the production inverse the same
//      correctness guarantee.
//
// SCOPE: 1D inverse only. The 2D inverse + multi-level recursion
// + decoder pipeline plumbing are slices 2 and 3 of step 6B.
// Production decoder code paths are unchanged by this commit
// — the new overload exists in source but isn't yet called from
// `J2KDecoderPipeline`.

import XCTest
@testable import J2KCodec

final class HTInverseDWTParityAwarenessTests: XCTestCase {

    // MARK: - Reference parity-aware inverse (canonical spec)

    /// Reference inverse 5/3 (1D), parity-aware. Identical
    /// algorithm to the reference in
    /// `HTDWT2DParityAwarenessTests.inverse53_1D` — duplicated
    /// here so this file is independent of test-suite ordering.
    /// The production inverse must agree with this reference
    /// byte-for-byte across every probed (n, u) cell.
    private static func referenceInverse53_1D(
        _ band: [Int32], count n: Int, uOrigin u: Int
    ) -> [Int32] {
        precondition(band.count == n)
        if n < 2 { return band }
        let oddOrigin = (u & 1) == 1
        let lowCount  = oddOrigin ? (n / 2) : ((n + 1) / 2)
        let highCount = n - lowCount
        var L = Array(band[0..<lowCount])
        var H = Array(band[lowCount..<n])

        if !oddOrigin {
            for i in 0..<lowCount {
                let left  = (i > 0) ? H[i - 1] : H[0]
                let right = (i < highCount) ? H[i] : H[highCount - 1]
                L[i] = L[i] &- ((left &+ right &+ 2) >> 2)
            }
        } else {
            for i in 0..<lowCount {
                let left  = H[i]
                let right = (i + 1 < highCount) ? H[i + 1] : H[highCount - 1]
                L[i] = L[i] &- ((left &+ right &+ 2) >> 2)
            }
        }

        if !oddOrigin {
            for i in 0..<highCount {
                let left  = L[i]
                let right = (i + 1 < lowCount) ? L[i + 1] : L[lowCount - 1]
                H[i] = H[i] &+ ((left &+ right) >> 1)
            }
        } else {
            if highCount > 0 { H[0] = H[0] &+ L[0] }
            let interiorEnd = min(highCount, lowCount)
            for i in 1..<interiorEnd {
                H[i] = H[i] &+ ((L[i - 1] &+ L[i]) >> 1)
            }
            if highCount > lowCount {
                H[lowCount] = H[lowCount] &+ L[lowCount - 1]
            }
        }

        var x = [Int32](repeating: 0, count: n)
        if !oddOrigin {
            for i in 0..<lowCount  { x[i * 2]     = L[i] }
            for i in 0..<highCount { x[i * 2 + 1] = H[i] }
        } else {
            for i in 0..<lowCount  { x[i * 2 + 1] = L[i] }
            for i in 0..<highCount { x[i * 2]     = H[i] }
        }
        return x
    }

    // MARK: - Helpers

    /// Run the parity-aware FORWARD 1D DWT (the production primitive
    /// from step 1) at the given origin. Returns `[L..., H...]`
    /// concatenated, the convention the inverse expects.
    private static func forward(input: [Int32], uOrigin: Int) -> [Int32] {
        let n = input.count
        let oddOrigin = (uOrigin & 1) == 1
        let lowCount  = oddOrigin ? (n / 2) : ((n + 1) / 2)
        let highCount = n - lowCount
        var output = [Int32](repeating: 0, count: n)
        let workspace = AcceleratedDWT2D.DWTWorkspace53(maxSignalLength: n)
        input.withUnsafeBufferPointer { inBuf in
            output.withUnsafeMutableBufferPointer { outBuf in
                AcceleratedDWT2D.forward53_1D(
                    inBuf.baseAddress!, outBuf.baseAddress!,
                    count: n, uOrigin: uOrigin, workspace: workspace)
            }
        }
        precondition(output.count == lowCount + highCount)
        return output
    }

    /// Split a `[L..., H...]` band into separate lowpass + highpass
    /// arrays sized for the given (n, uOrigin) — the input shape
    /// `inverseTransform53Optimized` expects.
    private static func splitBand(
        _ band: [Int32], n: Int, uOrigin: Int
    ) -> (lp: [Int32], hp: [Int32]) {
        let oddOrigin = (uOrigin & 1) == 1
        let lowCount  = oddOrigin ? (n / 2) : ((n + 1) / 2)
        return (
            lp: Array(band[0..<lowCount]),
            hp: Array(band[lowCount..<n])
        )
    }

    private static func makeRandom(_ n: Int, seed: UInt64) -> [Int32] {
        var state: UInt64 = seed
        return (0..<n).map { _ -> Int32 in
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return Int32(truncatingIfNeeded: z & 0xFFFF_FFFF) % 100_000
        }
    }

    // MARK: - Invariant 1: Even-origin regression

    /// For every n in 2…32 and every even u in {0, 2, 4, 100, 1024},
    /// the parity-aware overload's output equals the no-origin
    /// overload's output byte-for-byte. This is the production
    /// regression guard — `inverseTransform53Optimized` is on every
    /// single-tile decode hot path; we cannot pay any cost here.
    func testEvenOriginInverseIsByteIdenticalToNoOriginOverload() throws {
        let optimizer = J2KDWT1DOptimizer()
        let evens: [Int] = [0, 2, 4, 100, 1024]
        for n in 2...32 {
            let input = Self.makeRandom(n, seed: UInt64(0xBEEF + n))
            // Forward at even origin gives the [L..., H...] band.
            let band = Self.forward(input: input, uOrigin: 0)
            let (lp, hp) = Self.splitBand(band, n: n, uOrigin: 0)
            let baseline = try optimizer.inverseTransform53Optimized(
                lowpass: lp, highpass: hp, boundaryExtension: .symmetric)
            for u in evens {
                let withOrigin = try optimizer.inverseTransform53Optimized(
                    lowpass: lp, highpass: hp,
                    boundaryExtension: .symmetric, uOrigin: u)
                XCTAssertEqual(withOrigin, baseline,
                    "n=\(n) u=\(u): even-origin inverse must be " +
                    "byte-identical to no-origin overload")
            }
        }
    }

    // MARK: - Invariant 2: Odd-origin forward+inverse roundtrip

    /// For every n in 2…32 and every odd u in {1, 3, 5, 33, 99,
    /// 1399}, forward(input, u) followed by parity-aware inverse
    /// at the same u must recover input bit-exactly. This is the
    /// math correctness check — no production code path on the
    /// decode side has invoked the new overload yet, so this test
    /// is the only thing pinning its arithmetic.
    func testOddOriginInverseRoundTripIsBitExact() throws {
        let optimizer = J2KDWT1DOptimizer()
        let odds: [Int] = [1, 3, 5, 33, 99, 1399]
        for n in 2...32 {
            for u in odds {
                let input = Self.makeRandom(n, seed: UInt64(0xC0DE + n + u))
                let band = Self.forward(input: input, uOrigin: u)
                let (lp, hp) = Self.splitBand(band, n: n, uOrigin: u)
                let recovered = try optimizer.inverseTransform53Optimized(
                    lowpass: lp, highpass: hp,
                    boundaryExtension: .symmetric, uOrigin: u)
                XCTAssertEqual(recovered, input,
                    "n=\(n) u=\(u): forward+inverse at odd origin must " +
                    "roundtrip bit-exactly (recovered=\(recovered) " +
                    "input=\(input))")
            }
        }
    }

    // MARK: - Invariant 3: Production matches reference byte-for-byte

    /// For every (n, u) cell in the test matrix, the production
    /// inverse output equals the reference inverse output. The
    /// reference is the canonical parity-aware inverse from
    /// `HTDWT2DParityAwarenessTests`, which step 2's multi-level
    /// roundtrip tests pin against the parity-aware forward.
    /// Agreement here means the production inverse can substitute
    /// for the reference anywhere the reference is used.
    func testInverseMatchesReferenceAcrossOriginsAndSizes() throws {
        let optimizer = J2KDWT1DOptimizer()
        let origins: [Int] = [0, 1, 2, 3, 5, 33, 99, 100, 1024, 1399]
        for n in 2...32 {
            for u in origins {
                let input = Self.makeRandom(n, seed: UInt64(0xFADE + n + u))
                let band = Self.forward(input: input, uOrigin: u)
                let (lp, hp) = Self.splitBand(band, n: n, uOrigin: u)
                let production = try optimizer.inverseTransform53Optimized(
                    lowpass: lp, highpass: hp,
                    boundaryExtension: .symmetric, uOrigin: u)
                let reference = Self.referenceInverse53_1D(
                    band, count: n, uOrigin: u)
                XCTAssertEqual(production, reference,
                    "n=\(n) u=\(u): production inverse must match " +
                    "reference (prod=\(production) ref=\(reference))")
            }
        }
    }

    // MARK: - Invariant 4: Edge cases

    /// `n < 2` is a no-op (forward returns input as-is, inverse
    /// must return the single sample unchanged). `n = 0` is
    /// rejected by the precondition; `n = 1` returns the lowpass
    /// untouched (highpass is empty). Verify both even and odd
    /// origin fall through cleanly.
    func testInverseHandlesSingleSampleEdge() throws {
        let optimizer = J2KDWT1DOptimizer()
        let single: [Int32] = [42]
        for u in [0, 1, 2, 3] {
            let result = try optimizer.inverseTransform53Optimized(
                lowpass: single, highpass: [],
                boundaryExtension: .symmetric, uOrigin: u)
            XCTAssertEqual(result, single,
                "n=1 u=\(u): single-sample inverse must return lowpass unchanged")
        }
    }
}
