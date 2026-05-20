// V10_13_WindowedIDWTTests.swift
//
// v10.13-research — validation for ROI decode Stage 3 (windowed
// inverse DWT).
//
// v10.7.0 Stage 2 skipped off-region tiles wholesale, but the tile(s)
// a region *does* touch — and every single-tile fixture — still ran
// the inverse DWT full-tile. Stage 3 windows the inverse 5/3 DWT so it
// reconstructs only the region's rows/columns.
//
// The foundation is `inverseLift53InPlaceWindowed`: a windowed 1D
// inverse 5/3 lift that is exact by loop-restriction (not halo
// approximation) — the 5/3 inverse decomposes into Step 1 (evens from
// input high-pass only) then Step 2 (odds from Step-1 evens), a tight
// forward dependency. This file validates that primitive exhaustively
// against the full `inverseLift53InPlace`.
//
// Tests:
//   1. windowed lift == full lift on the windowed range, every window,
//      every dyadic even/odd count combination

#if canImport(Metal) && os(macOS)
import XCTest
import Foundation
@testable import J2KCodec

final class V10_13_WindowedIDWTTests: XCTestCase {

    /// `inverseLift53InPlaceWindowed` over `[pairFrom, pairTo)` must
    /// produce exactly the same even/odd samples as the full
    /// `inverseLift53InPlace` does in that range — for every window
    /// and every dyadic count pairing.
    func testWindowedLift_matchesFullLift_everyWindow() {
        // 5/3 dyadic invariant: evenCount ∈ {oddCount, oddCount+1}.
        let counts: [(Int, Int)] = [
            (1, 1), (2, 1), (2, 2), (3, 2), (3, 3), (4, 3), (4, 4),
            (5, 5), (6, 5), (8, 8), (9, 8), (16, 16), (17, 16), (33, 32),
        ]
        var rng = SystemRandomNumberGenerator()
        for (evenCount, oddCount) in counts {
            let n = evenCount + oddCount
            let input: [Int32] = (0..<n).map { _ in Int32.random(in: -50000...50000, using: &rng) }

            var ref = input
            ref.withUnsafeMutableBufferPointer { buf in
                J2KDWT2DOptimizer.inverseLift53InPlace(
                    buf.baseAddress!, evenCount: evenCount, oddCount: oddCount, stride: 1)
            }

            let maxPairs = max(evenCount, oddCount)
            for pf in 0...maxPairs {
                for pt in pf...maxPairs {
                    var buf = input
                    buf.withUnsafeMutableBufferPointer { b in
                        J2KDWT2DOptimizer.inverseLift53InPlaceWindowed(
                            b.baseAddress!, evenCount: evenCount, oddCount: oddCount,
                            stride: 1, pairFrom: pf, pairTo: pt)
                    }
                    for i in pf..<pt {
                        if i < evenCount {
                            XCTAssertEqual(buf[i * 2], ref[i * 2],
                                "even[\(i)] ec=\(evenCount) oc=\(oddCount) win=[\(pf),\(pt))")
                        }
                        if i < oddCount {
                            XCTAssertEqual(buf[i * 2 + 1], ref[i * 2 + 1],
                                "odd[\(i)] ec=\(evenCount) oc=\(oddCount) win=[\(pf),\(pt))")
                        }
                    }
                }
            }
        }
        print("V10_13 windowed lift: exact vs full lift across all windows × 14 count pairings ✓")
    }

    // MARK: - Multi-level windowed transform

    private typealias Level = (lh: [Int32], lhW: Int, lhH: Int,
                               hl: [Int32], hlW: Int, hlH: Int,
                               hh: [Int32], hhW: Int, hhH: Int)

    /// Builds a deepest-first subband set + deepest LL for a synthetic
    /// `fullW × fullH` tile with `n` decomposition levels, mirroring
    /// the decoder pipeline's `levelSizes` recursion.
    private func makeSubbands(fullW: Int, fullH: Int, n: Int,
                              rng: inout SystemRandomNumberGenerator)
        -> (ll: [Int32], llW: Int, llH: Int, subbands: [Level]) {
        var sizes: [(Int, Int)] = [(fullW, fullH)]
        for _ in 0..<n {
            let (w, h) = sizes.last!
            sizes.append(((w + 1) / 2, (h + 1) / 2))
        }
        func rand(_ count: Int) -> [Int32] {
            (0..<max(0, count)).map { _ in Int32.random(in: -8000...8000, using: &rng) }
        }
        var subbands: [Level] = []
        for level in stride(from: n, through: 1, by: -1) {
            let (pw, ph) = sizes[level - 1]
            let (cw, ch) = sizes[level]
            let llW = cw, llH = ch
            let hlW = pw - llW
            let lhH = ph - llH
            subbands.append((
                lh: rand(llW * lhH), lhW: llW, lhH: lhH,
                hl: rand(hlW * llH), hlW: hlW, hlH: llH,
                hh: rand(hlW * lhH), hhW: hlW, hhH: lhH))
        }
        let (dw, dh) = sizes[n]
        return (ll: rand(dw * dh), llW: dw, llH: dh, subbands: subbands)
    }

    /// The row-windowed multi-level transform must produce, for the
    /// windowed rows, bit-identical output to the full
    /// `inverseTransformMultiLevel53` — across odd dimensions, several
    /// level counts, and a spread of row windows (including the full
    /// height, corners, thin strips, and an empty window).
    func testWindowedTransform_matchesFullTransform() async throws {
        let optimizer = J2KDWT2DOptimizer()
        var rng = SystemRandomNumberGenerator()
        let cases: [(Int, Int, Int)] = [
            (64, 64, 3), (63, 65, 4), (100, 80, 5),
            (127, 129, 5), (40, 200, 4), (200, 40, 4), (33, 33, 5),
            (2800, 2288, 5), (512, 512, 5),
        ]
        for (fullW, fullH, n) in cases {
            let s = makeSubbands(fullW: fullW, fullH: fullH, n: n, rng: &rng)
            let ref = await optimizer.inverseTransformMultiLevel53(
                ll: s.ll, llW: s.llW, llH: s.llH, subbands: s.subbands)
            XCTAssertEqual(ref.width, fullW)
            XCTAssertEqual(ref.height, fullH)

            var windows: [(Int, Int)] = [
                (0, fullH), (0, 0), (0, min(8, fullH)),
                (max(0, fullH - 8), fullH), (fullH / 3, fullH / 3 + 1),
            ]
            if fullH >= 4 { windows.append((fullH / 2 - 2, fullH / 2 + 2)) }
            for (lo, hi) in windows {
                let win = optimizer.inverseTransformMultiLevel53RowWindowed(
                    ll: s.ll, llW: s.llW, llH: s.llH, subbands: s.subbands,
                    outRowLo: lo, outRowHi: hi)
                XCTAssertEqual(win.width, fullW, "[\(fullW)×\(fullH) n=\(n)] width")
                XCTAssertEqual(win.height, fullH, "[\(fullW)×\(fullH) n=\(n)] height")
                for r in lo..<hi {
                    for c in 0..<fullW {
                        XCTAssertEqual(win.data[r * fullW + c], ref.data[r * fullW + c],
                            "[\(fullW)×\(fullH) n=\(n)] win=[\(lo),\(hi)) mismatch at (\(r),\(c))")
                    }
                }
            }
        }
        print("V10_13 windowed transform: exact vs full transform across 7 shapes × 6 windows ✓")
    }

    /// A windowed lift over a strided buffer (mimicking the column
    /// pass, which lifts columns of a row-major buffer) must also
    /// match the full strided lift on the windowed range.
    func testWindowedLift_strided_matchesFullLift() {
        let evenCount = 20, oddCount = 19, stride = 7
        let pairs = max(evenCount, oddCount)
        let n = (evenCount + oddCount) * stride
        var rng = SystemRandomNumberGenerator()
        let input: [Int32] = (0..<n).map { _ in Int32.random(in: -50000...50000, using: &rng) }

        var ref = input
        ref.withUnsafeMutableBufferPointer { buf in
            J2KDWT2DOptimizer.inverseLift53InPlace(
                buf.baseAddress!, evenCount: evenCount, oddCount: oddCount, stride: stride)
        }
        for pf in [0, 1, 5, 9] {
            for pt in [pf + 1, pf + 3, pairs] where pt <= pairs {
                var buf = input
                buf.withUnsafeMutableBufferPointer { b in
                    J2KDWT2DOptimizer.inverseLift53InPlaceWindowed(
                        b.baseAddress!, evenCount: evenCount, oddCount: oddCount,
                        stride: stride, pairFrom: pf, pairTo: pt)
                }
                for i in pf..<pt {
                    if i < evenCount {
                        XCTAssertEqual(buf[i * 2 * stride], ref[i * 2 * stride],
                            "even[\(i)] strided win=[\(pf),\(pt))")
                    }
                    if i < oddCount {
                        XCTAssertEqual(buf[(i * 2 + 1) * stride], ref[(i * 2 + 1) * stride],
                            "odd[\(i)] strided win=[\(pf),\(pt))")
                    }
                }
            }
        }
        print("V10_13 windowed lift: exact vs full strided lift ✓")
    }
}
#endif
