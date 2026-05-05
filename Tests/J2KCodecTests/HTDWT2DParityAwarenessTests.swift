// HTDWT2DParityAwarenessTests.swift
// v6-alpha3 step 2 — focused unit tests for the parity-aware 2D 5/3
// forward DWT and its multi-level decomposition recursion.
//
// Anchors three invariants:
//
//   1. **Even-origin regression**: the parity-aware overload, when
//      called with `tileOriginX == 0` and `tileOriginY == 0`, produces
//      output **bit-identical** to the existing no-origin overload.
//      This is the regression guard for the production single-tile
//      encode hot path. Even-aligned non-zero origins (e.g. (32, 32))
//      should also match the no-origin overload via the per-axis
//      parity-aware 1D filter's no-origin fast path.
//
//   2. **Odd-origin 2D roundtrip**: forward 2D DWT at any (uX, uY)
//      followed by the parity-aware reference inverse must recover
//      the input pixels exactly. Validated for both single-axis-odd
//      and double-axis-odd cases.
//
//   3. **Multi-level recursion at real-fixture origins**: 5-level
//      forward decomposition at origins drawn from the medical
//      corpus (MR 443, PX 1230×658, DX 1400×1144 / 700×572) followed
//      by reference inverse decomposition recovers the input
//      exactly. This is the structural correctness gate for the
//      pipeline change v6-alpha3 step 3+ will rely on.
//
// SCOPE: only the 2D forward DWT and multi-level recursion in
// isolation. Code-block grid origin, packet header generation, and
// native multi-tile codestream assembly are downstream v6-alpha3
// step 3+ work and are not covered here.

import XCTest
@testable import J2KCodec

final class HTDWT2DParityAwarenessTests: XCTestCase {

    // MARK: - Reference 1D inverse (parity-aware)

    /// Local copy of the reference 1D inverse, used here as the
    /// kernel for the 2D inverse below. Identical to the version
    /// in `HTDWTParityAwarenessTests.swift`; duplicated so this file
    /// is independent of test-suite ordering.
    private static func inverse53_1D(
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

    // MARK: - Reference 2D inverse

    /// Reference 2D inverse 5/3 DWT, parity-aware. Takes the four
    /// bands (LL/HL/LH/HH) and reverses the forward 2D transform
    /// at the same (uX, uY) origin. Used here to verify that
    /// `AcceleratedDWT2D.forward2D_53(...tileOriginX:tileOriginY:)`
    /// produces a mathematically-reversible output.
    private static func inverse2D_53(
        ll: [Int32], hl: [Int32], lh: [Int32], hh: [Int32],
        rowLowW: Int, rowHighW: Int, colLowH: Int, colHighH: Int,
        uX: Int, uY: Int
    ) -> [Int32] {
        let width  = rowLowW  + rowHighW
        let height = colLowH  + colHighH

        // Step 1: re-assemble colResult by undoing the row pass.
        // For each row of colResult, we need to reverse the
        // forward53_1D(uOrigin: uX) that was applied during forward.
        // Forward writes [L, H] interleaved by band-count; the
        // inverse re-reads as a single [L_0..L_{rowLowW-1},
        // H_0..H_{rowHighW-1}] band and recovers the row.
        var colResult = [Int32](repeating: 0, count: width * height)

        // L-rows of colResult (row indices 0..<colLowH) come from
        // [LL, HL] interleaved as [LL_row, HL_row].
        for row in 0..<colLowH {
            var band = [Int32](repeating: 0, count: width)
            for c in 0..<rowLowW  { band[c] = ll[row * rowLowW  + c] }
            for c in 0..<rowHighW { band[rowLowW + c] = hl[row * rowHighW + c] }
            let rowOut = inverse53_1D(band, count: width, uOrigin: uX)
            for c in 0..<width { colResult[row * width + c] = rowOut[c] }
        }
        // H-rows of colResult (row indices colLowH..<height) come
        // from [LH, HH].
        for row in 0..<colHighH {
            var band = [Int32](repeating: 0, count: width)
            for c in 0..<rowLowW  { band[c] = lh[row * rowLowW  + c] }
            for c in 0..<rowHighW { band[rowLowW + c] = hh[row * rowHighW + c] }
            let rowOut = inverse53_1D(band, count: width, uOrigin: uX)
            let dstRow = colLowH + row
            for c in 0..<width { colResult[dstRow * width + c] = rowOut[c] }
        }

        // Step 2: reverse the column pass. For each column c in
        // [0, width), build a [L band, H band] from colResult and
        // apply the parity-aware inverse 1D with uOrigin = uY.
        var data = [Int32](repeating: 0, count: width * height)
        for c in 0..<width {
            var band = [Int32](repeating: 0, count: height)
            for row in 0..<colLowH  { band[row] = colResult[row * width + c] }
            for row in 0..<colHighH { band[colLowH + row] = colResult[(colLowH + row) * width + c] }
            let colOut = inverse53_1D(band, count: height, uOrigin: uY)
            for row in 0..<height { data[row * width + c] = colOut[row] }
        }
        return data
    }

    // MARK: - Reference multi-level inverse

    private static func inverseDecomposition53(
        decomposition: AcceleratedDWT2D.Int32DecompositionResult,
        startWidth: Int, startHeight: Int,
        tileOriginX: Int, tileOriginY: Int
    ) -> [Int32] {
        // Walk forward to record the (origin, dims) at every level.
        var levelOrigins: [(uX: Int, uY: Int, w: Int, h: Int)] = []
        var w = startWidth, h = startHeight
        var ox = tileOriginX, oy = tileOriginY
        for _ in 0..<decomposition.levels.count {
            levelOrigins.append((ox, oy, w, h))
            // After level k, LL band has dim that depends on parity.
            let lowW = ((ox & 1) == 0) ? (w + 1) / 2 : w / 2
            let lowH = ((oy & 1) == 0) ? (h + 1) / 2 : h / 2
            w = lowW; h = lowH
            ox >>= 1; oy >>= 1
        }
        // Now invert level by level, deepest first.
        var ll = decomposition.coarsestLL
        for (level, lr) in decomposition.levels.enumerated().reversed() {
            let (uX, uY, levelW, levelH) = levelOrigins[level]
            let rowLowW  = ((uX & 1) == 0) ? (levelW + 1) / 2 : levelW / 2
            let rowHighW = levelW - rowLowW
            let colLowH  = ((uY & 1) == 0) ? (levelH + 1) / 2 : levelH / 2
            let colHighH = levelH - colLowH
            ll = inverse2D_53(
                ll: ll, hl: lr.hl, lh: lr.lh, hh: lr.hh,
                rowLowW: rowLowW, rowHighW: rowHighW,
                colLowH: colLowH, colHighH: colHighH,
                uX: uX, uY: uY)
        }
        return ll
    }

    // MARK: - Test helpers

    private func makeRandom2D(width: Int, height: Int, seed: UInt64 = 0xc0fee) -> [Int32] {
        var rng = SplitMix64(seed: seed)
        return (0..<(width * height)).map { _ in
            Int32.random(in: -100_000...100_000, using: &rng)
        }
    }

    /// Deterministic seedable RNG so test output is reproducible.
    private struct SplitMix64: RandomNumberGenerator {
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

    // MARK: - Invariant 1: Even-origin regression (single-level)

    func testEvenOrigin2DByteIdenticalToNoOriginOverload() async {
        // For a sweep of small (width, height) with even-origin
        // (uX, uY) ∈ {0, 2, 32, 1024}², the parity-aware overload
        // must produce byte-identical output to the no-origin one.
        let sizes: [(w: Int, h: Int)] = [(8, 8), (16, 16), (17, 9), (32, 32),
                                         (64, 48), (33, 65)]
        let evenOrigins: [(Int, Int)] = [(0, 0), (2, 0), (0, 2), (2, 2),
                                         (32, 32), (1024, 1024)]
        for (w, h) in sizes {
            let data = makeRandom2D(width: w, height: h, seed: UInt64(w * 1000 + h))
            let baseline = await AcceleratedDWT2D.forward2D_53(
                data: data, width: w, height: h)
            for (uX, uY) in evenOrigins {
                let r = await AcceleratedDWT2D.forward2D_53(
                    data: data, width: w, height: h,
                    tileOriginX: uX, tileOriginY: uY)
                XCTAssertEqual(r.ll, baseline.ll, "size=\(w)x\(h) origin=\(uX),\(uY): LL must match no-origin")
                XCTAssertEqual(r.hl, baseline.hl, "size=\(w)x\(h) origin=\(uX),\(uY): HL must match no-origin")
                XCTAssertEqual(r.lh, baseline.lh, "size=\(w)x\(h) origin=\(uX),\(uY): LH must match no-origin")
                XCTAssertEqual(r.hh, baseline.hh, "size=\(w)x\(h) origin=\(uX),\(uY): HH must match no-origin")
            }
        }
    }

    // MARK: - Invariant 2: Odd-origin 2D forward+inverse roundtrip

    /// Forward at (uX, uY) followed by reference inverse must
    /// recover the input pixel-exact. Tests every parity combination
    /// (even/even, odd/even, even/odd, odd/odd).
    func testOdd2DForwardInverseRoundTrip() async {
        let sizes: [(w: Int, h: Int)] = [(8, 8), (15, 15), (16, 17), (17, 16),
                                         (33, 31), (64, 64)]
        let originPairs: [(Int, Int)] = [
            (0, 0), (1, 0), (0, 1), (1, 1),
            (3, 5), (5, 3), (33, 99), (99, 33),
            (1399, 887)
        ]
        for (w, h) in sizes {
            let data = makeRandom2D(width: w, height: h, seed: UInt64(w * 1000 + h))
            for (uX, uY) in originPairs {
                let r = await AcceleratedDWT2D.forward2D_53(
                    data: data, width: w, height: h,
                    tileOriginX: uX, tileOriginY: uY)
                let recovered = Self.inverse2D_53(
                    ll: r.ll, hl: r.hl, lh: r.lh, hh: r.hh,
                    rowLowW: r.lhW, rowHighW: r.hlW,
                    colLowH: r.llH, colHighH: r.lhH,
                    uX: uX, uY: uY)
                XCTAssertEqual(data, recovered,
                    "size=\(w)x\(h) origin=\(uX),\(uY): 2D forward+inverse must roundtrip")
            }
        }
    }

    // MARK: - Invariant 3: Multi-level recursion at real-fixture origins

    /// 5-level multi-level decomposition at MR 2x2 tile-1 origin
    /// (443, 0): MR 886×886 / 2x2 = tile 1 starts at (443, 0).
    /// Tile dim = 443×443 (MR top-right quadrant). Origin trajectory:
    ///   level 0: (443, 0)   — uX odd, uY even
    ///   level 1: (221, 0)   — uX odd, uY even
    ///   level 2: (110, 0)   — uX even, uY even
    ///   level 3: (55, 0)    — uX odd, uY even
    ///   level 4: (27, 0)    — uX odd, uY even
    /// Origin parity flips each level. Forward+inverse must
    /// roundtrip.
    func testMultiLevelMRTile1OriginRoundTrip() async {
        try? await runMultiLevelRoundTrip(width: 443, height: 443,
                                          uX: 443, uY: 0,
                                          levels: 5,
                                          label: "MR-2x2 tile1 (443, 0)")
    }

    /// 5-level multi-level at MR 2x2 tile-3 origin (443, 443).
    func testMultiLevelMRTile3OriginRoundTrip() async {
        try? await runMultiLevelRoundTrip(width: 443, height: 443,
                                          uX: 443, uY: 443,
                                          levels: 5,
                                          label: "MR-2x2 tile3 (443, 443)")
    }

    /// 5-level multi-level at PX 2x2 tile-1 origin (1230, 0).
    /// Tile dim = 1229×658 (PX 2459×1316 / 2x2 trailing tile).
    func testMultiLevelPXTile1OriginRoundTrip() async {
        try? await runMultiLevelRoundTrip(width: 1229, height: 658,
                                          uX: 1230, uY: 0,
                                          levels: 5,
                                          label: "PX-2x2 tile1 (1230, 0)")
    }

    /// 5-level multi-level at DX 2x2 tile-3 origin (1400, 1144).
    /// Tile dim = 1400×1144.
    func testMultiLevelDXTile3OriginRoundTrip() async {
        try? await runMultiLevelRoundTrip(width: 1400, height: 1144,
                                          uX: 1400, uY: 1144,
                                          levels: 5,
                                          label: "DX-2x2 tile3 (1400, 1144)")
    }

    /// 5-level multi-level at DX 4x4 tile origins (700, 572) — both
    /// even at level 0 but with parity flips at level 2+ (700/4=175
    /// odd; 572/4=143 odd).
    func testMultiLevelDX4x4OriginRoundTrip() async {
        try? await runMultiLevelRoundTrip(width: 700, height: 572,
                                          uX: 700, uY: 572,
                                          levels: 5,
                                          label: "DX-4x4 (700, 572)")
    }

    /// 5-level multi-level at origin (0, 0) must produce
    /// byte-identical output to the no-origin recursion.
    func testMultiLevelEvenOriginByteIdenticalToNoOriginRecursion() async {
        let sizes: [(w: Int, h: Int)] = [(64, 64), (128, 128), (250, 200)]
        for (w, h) in sizes {
            let data = makeRandom2D(width: w, height: h, seed: UInt64(w + h))
            let baseline = await AcceleratedDWT2D.forwardDecomposition53(
                data: data, width: w, height: h, levels: 5)
            let r = await AcceleratedDWT2D.forwardDecomposition53(
                data: data, width: w, height: h, levels: 5,
                tileOriginX: 0, tileOriginY: 0)
            XCTAssertEqual(r.coarsestLL, baseline.coarsestLL,
                "size=\(w)x\(h) origin (0,0): coarsest LL must match no-origin recursion")
            XCTAssertEqual(r.levels.count, baseline.levels.count,
                "size=\(w)x\(h) origin (0,0): level count must match")
            for (i, (a, b)) in zip(r.levels, baseline.levels).enumerated() {
                XCTAssertEqual(a.lh, b.lh, "size=\(w)x\(h) origin (0,0) level \(i): LH must match")
                XCTAssertEqual(a.hl, b.hl, "size=\(w)x\(h) origin (0,0) level \(i): HL must match")
                XCTAssertEqual(a.hh, b.hh, "size=\(w)x\(h) origin (0,0) level \(i): HH must match")
            }
        }
    }

    /// Helper: run multi-level forward+inverse at given (uX, uY) and
    /// assert pixel-exact roundtrip.
    private func runMultiLevelRoundTrip(
        width w: Int, height h: Int,
        uX: Int, uY: Int, levels: Int,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let data = makeRandom2D(width: w, height: h, seed: UInt64(w + h + uX + uY))
        let r = await AcceleratedDWT2D.forwardDecomposition53(
            data: data, width: w, height: h, levels: levels,
            tileOriginX: uX, tileOriginY: uY)
        let recovered = Self.inverseDecomposition53(
            decomposition: r,
            startWidth: w, startHeight: h,
            tileOriginX: uX, tileOriginY: uY)
        XCTAssertEqual(data, recovered,
            "\(label): \(levels)-level forward+inverse decomposition must roundtrip",
            file: file, line: line)
    }
}
