// HTInverseDWT2DParityAwarenessTests.swift
// v6-alpha3 step 6B slice 2 — focused unit tests for the
// parity-aware 2D + multi-level inverse 5/3 DWT primitives landed
// in `J2KDWT2DOptimizer`:
//
//   - inverseTransform2DOptimized(...uX:uY:)
//   - inverseTransformMultiLevel53(...tileOriginX:tileOriginY:)
//
// Mirror of `HTDWT2DParityAwarenessTests` on the decode side. The
// HTDWT2DParityAwarenessTests suite uses a hand-written REFERENCE
// inverse to validate the parity-aware FORWARD; this suite uses
// the parity-aware FORWARD (already validated) to validate the
// production INVERSE.
//
// Anchors:
//
//   1. **Even-origin regression (single-level)**: `(uX, uY)` both
//      even routes to the existing non-parity-aware fast path —
//      output byte-identical to the no-origin overload.
//
//   2. **Odd-origin 2D roundtrip**: forward(parity-aware) →
//      inverse(parity-aware production) recovers input bit-exactly
//      across every parity combination (e/e, o/e, e/o, o/o).
//
//   3. **Multi-level roundtrip at real-fixture origins** (MR /
//      PX / DX 2x2 / DX 4x4) — the same parity trajectory the
//      step-2 multi-level forward tests pin against the test
//      reference, here pinned against the production inverse.
//
//   4. **Multi-level even-origin regression**: starting origin
//      (0, 0) → every level routes to the existing fast path,
//      multi-level output byte-identical.
//
// SCOPE: 2D inverse + multi-level inverse only. The decoder
// pipeline plumbing (slice 3) is the next step — without it the
// production decoder still applies the legacy even-origin inverse
// to multi-tile codestreams.

import XCTest
@testable import J2KCodec

final class HTInverseDWT2DParityAwarenessTests: XCTestCase {

    private static func makeRandom2D(width: Int, height: Int, seed: UInt64 = 0xC0FEE) -> [Int32] {
        var rng = SplitMix64(seed: seed)
        return (0..<(width * height)).map { _ in
            Int32.random(in: -100_000...100_000, using: &rng)
        }
    }

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

    /// Convert a flat row-major `[Int32]` into a jagged `[[Int32]]`.
    private static func toJagged(_ flat: [Int32], w: Int, h: Int) -> [[Int32]] {
        guard h > 0 && w > 0 else { return [] }
        return (0..<h).map { r in Array(flat[(r * w)..<(r * w + w)]) }
    }

    /// Flatten a jagged `[[Int32]]` into row-major `[Int32]`.
    private static func toFlat(_ jagged: [[Int32]]) -> [Int32] {
        let h = jagged.count
        let w = h > 0 ? jagged[0].count : 0
        var out = [Int32](repeating: 0, count: w * h)
        for (r, row) in jagged.enumerated() {
            for (c, v) in row.enumerated() where c < w {
                out[r * w + c] = v
            }
        }
        return out
    }

    // MARK: - Invariant 1: Even-origin 2D inverse regression

    /// Single-level 2D inverse with even origins must equal the
    /// no-origin overload's output byte-for-byte. The production
    /// path uses `J2KDWT2DOptimizer.inverseTransform2DOptimized`
    /// which routes through the existing optimised flat-buffer
    /// lifting; the new parity-aware overload should not perturb
    /// this for even origins.
    func testEven2DInverseByteIdenticalToNoOriginOverload() async throws {
        let optimizer = J2KDWT2DOptimizer()
        let sizes: [(w: Int, h: Int)] = [(8, 8), (16, 16), (17, 9),
                                         (32, 32), (64, 48), (33, 65)]
        let evenOrigins: [(Int, Int)] = [(0, 0), (2, 0), (0, 2),
                                         (2, 2), (32, 32), (1024, 1024)]
        for (w, h) in sizes {
            let data = Self.makeRandom2D(width: w, height: h, seed: UInt64(w * 1000 + h))
            // Forward to get bands.
            let f = await AcceleratedDWT2D.forward2D_53(
                data: data, width: w, height: h)
            let ll2D = Self.toJagged(f.ll, w: f.llW, h: f.llH)
            let lh2D = Self.toJagged(f.lh, w: f.lhW, h: f.lhH)
            let hl2D = Self.toJagged(f.hl, w: f.hlW, h: f.hlH)
            let hh2D = Self.toJagged(f.hh, w: f.hhW, h: f.hhH)
            let baseline = try await optimizer.inverseTransform2DOptimized(
                ll: ll2D, lh: lh2D, hl: hl2D, hh: hh2D,
                boundaryExtension: .symmetric)
            for (uX, uY) in evenOrigins {
                let recovered = try await optimizer.inverseTransform2DOptimized(
                    ll: ll2D, lh: lh2D, hl: hl2D, hh: hh2D,
                    boundaryExtension: .symmetric, uX: uX, uY: uY)
                XCTAssertEqual(recovered, baseline,
                    "size=\(w)x\(h) origin=(\(uX),\(uY)): even-origin " +
                    "2D inverse must be byte-identical to no-origin overload")
            }
        }
    }

    // MARK: - Invariant 2: Odd-origin 2D forward+inverse roundtrip

    /// For each (size, origin) cell — every parity combination,
    /// real-fixture origins included — forward(parity-aware) then
    /// inverse(parity-aware production) recovers the input pixel-
    /// exact.
    func testOdd2DForwardInverseRoundTripViaProductionPath() async throws {
        let optimizer = J2KDWT2DOptimizer()
        let sizes: [(w: Int, h: Int)] = [(8, 8), (15, 15), (16, 17),
                                         (17, 16), (33, 31), (64, 64)]
        let originPairs: [(Int, Int)] = [
            (0, 0), (1, 0), (0, 1), (1, 1),
            (3, 5), (5, 3), (33, 99), (99, 33),
            (1399, 887)
        ]
        for (w, h) in sizes {
            let data = Self.makeRandom2D(width: w, height: h, seed: UInt64(w * 1000 + h))
            for (uX, uY) in originPairs {
                let f = await AcceleratedDWT2D.forward2D_53(
                    data: data, width: w, height: h,
                    tileOriginX: uX, tileOriginY: uY)
                let ll2D = Self.toJagged(f.ll, w: f.llW, h: f.llH)
                let lh2D = Self.toJagged(f.lh, w: f.lhW, h: f.lhH)
                let hl2D = Self.toJagged(f.hl, w: f.hlW, h: f.hlH)
                let hh2D = Self.toJagged(f.hh, w: f.hhW, h: f.hhH)
                let recovered2D = try await optimizer.inverseTransform2DOptimized(
                    ll: ll2D, lh: lh2D, hl: hl2D, hh: hh2D,
                    boundaryExtension: .symmetric, uX: uX, uY: uY)
                let recovered = Self.toFlat(recovered2D)
                XCTAssertEqual(recovered, data,
                    "size=\(w)x\(h) origin=(\(uX),\(uY)): 2D forward+" +
                    "inverse via production path must roundtrip")
            }
        }
    }

    // MARK: - Invariant 3: Multi-level roundtrip at real fixtures

    /// Helper: run `levels`-level forward+inverse via production
    /// paths and assert bit-exact roundtrip.
    private func assertMultiLevelRoundTripsViaProduction(
        width w: Int, height h: Int,
        uX: Int, uY: Int,
        levels: Int,
        label: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let optimizer = J2KDWT2DOptimizer()
        let data = Self.makeRandom2D(width: w, height: h, seed: UInt64(w + h + uX + uY))
        let decomposition = await AcceleratedDWT2D.forwardDecomposition53(
            data: data, width: w, height: h, levels: levels,
            tileOriginX: uX, tileOriginY: uY)

        // Build the deepest-first subbands array the production
        // multi-level inverse expects.
        let subbands: [(lh: [Int32], lhW: Int, lhH: Int,
                        hl: [Int32], hlW: Int, hlH: Int,
                        hh: [Int32], hhW: Int, hhH: Int)] =
            decomposition.levels.reversed().map { lr in
                (lh: lr.lh, lhW: lr.lhW, lhH: lr.lhH,
                 hl: lr.hl, hlW: lr.hlW, hlH: lr.hlH,
                 hh: lr.hh, hhW: lr.hhW, hhH: lr.hhH)
            }

        let result = try await optimizer.inverseTransformMultiLevel53(
            ll: decomposition.coarsestLL,
            llW: decomposition.llW, llH: decomposition.llH,
            subbands: subbands,
            tileOriginX: uX, tileOriginY: uY)

        XCTAssertEqual(result.width, w,
            "\(label): recovered width \(result.width) != input \(w)",
            file: file, line: line)
        XCTAssertEqual(result.height, h,
            "\(label): recovered height \(result.height) != input \(h)",
            file: file, line: line)
        XCTAssertEqual(result.data, data,
            "\(label): \(levels)-level forward+inverse via production " +
            "must roundtrip bit-exactly",
            file: file, line: line)
    }

    /// MR 2x2 tile-1 origin (443, 0), tile dim 443×443 — odd uX,
    /// even uY at top level; parity flips at every level.
    func testMultiLevelMRTile1OriginRoundTripViaProduction() async throws {
        try await assertMultiLevelRoundTripsViaProduction(
            width: 443, height: 443, uX: 443, uY: 0, levels: 5,
            label: "MR-2x2 tile1 (443, 0)")
    }

    /// MR 2x2 tile-3 origin (443, 443) — both odd, both flip every level.
    func testMultiLevelMRTile3OriginRoundTripViaProduction() async throws {
        try await assertMultiLevelRoundTripsViaProduction(
            width: 443, height: 443, uX: 443, uY: 443, levels: 5,
            label: "MR-2x2 tile3 (443, 443)")
    }

    /// PX 2x2 trailing tile origin (1230, 0) on 1229×658 trailing
    /// dimensions — even uX, even uY at top level but parity flips
    /// at deeper levels (1230 / 4 = 307 odd; etc.).
    func testMultiLevelPXTile1OriginRoundTripViaProduction() async throws {
        try await assertMultiLevelRoundTripsViaProduction(
            width: 1229, height: 658, uX: 1230, uY: 0, levels: 5,
            label: "PX-2x2 tile1 (1230, 0)")
    }

    /// DX 2x2 tile-3 origin (1400, 1144) — both even at level 0,
    /// both flip parity at deeper DWT levels.
    func testMultiLevelDXTile3OriginRoundTripViaProduction() async throws {
        try await assertMultiLevelRoundTripsViaProduction(
            width: 1400, height: 1144, uX: 1400, uY: 1144, levels: 5,
            label: "DX-2x2 tile3 (1400, 1144)")
    }

    /// DX 4x4 representative tile origin (700, 572) — both even
    /// at level 0; parity flips at level 2+ (700/4 = 175 odd;
    /// 572/4 = 143 odd).
    func testMultiLevelDX4x4OriginRoundTripViaProduction() async throws {
        try await assertMultiLevelRoundTripsViaProduction(
            width: 700, height: 572, uX: 700, uY: 572, levels: 5,
            label: "DX-4x4 (700, 572)")
    }

    // MARK: - Invariant 4: Multi-level even-origin byte-identity

    /// Multi-level inverse with starting origin (0, 0) must
    /// produce output byte-identical to the no-origin overload's
    /// recursion. Pins the regression guard for the production
    /// single-tile decode path.
    func testMultiLevelEvenOriginByteIdenticalToNoOriginRecursion() async throws {
        let optimizer = J2KDWT2DOptimizer()
        let sizes: [(w: Int, h: Int)] = [(64, 64), (128, 128), (250, 200)]
        for (w, h) in sizes {
            let data = Self.makeRandom2D(width: w, height: h, seed: UInt64(w + h))
            let decomposition = await AcceleratedDWT2D.forwardDecomposition53(
                data: data, width: w, height: h, levels: 5)
            let subbands: [(lh: [Int32], lhW: Int, lhH: Int,
                            hl: [Int32], hlW: Int, hlH: Int,
                            hh: [Int32], hhW: Int, hhH: Int)] =
                decomposition.levels.reversed().map { lr in
                    (lh: lr.lh, lhW: lr.lhW, lhH: lr.lhH,
                     hl: lr.hl, hlW: lr.hlW, hlH: lr.hlH,
                     hh: lr.hh, hhW: lr.hhW, hhH: lr.hhH)
                }
            let baseline = await optimizer.inverseTransformMultiLevel53(
                ll: decomposition.coarsestLL,
                llW: decomposition.llW, llH: decomposition.llH,
                subbands: subbands)
            let result = try await optimizer.inverseTransformMultiLevel53(
                ll: decomposition.coarsestLL,
                llW: decomposition.llW, llH: decomposition.llH,
                subbands: subbands,
                tileOriginX: 0, tileOriginY: 0)
            XCTAssertEqual(result.data, baseline.data,
                "size=\(w)x\(h) origin (0,0): multi-level inverse must " +
                "be byte-identical to no-origin recursion")
            XCTAssertEqual(result.width, baseline.width,
                "size=\(w)x\(h) origin (0,0): width must match baseline")
            XCTAssertEqual(result.height, baseline.height,
                "size=\(w)x\(h) origin (0,0): height must match baseline")
        }
    }
}
