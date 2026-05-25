//
// V10_24_WindowedIDWTParityTests.swift
// J2KSwift
//
// v10.15.0 (v10.24-research) Phase 2 — parity oracle for the
// windowed multi-level inverse 5/3 DWT.
//
// Specification: for any `outputRegion` fully contained within the
// tile dims, and any `(ll, subbands)` decoded from a real
// codestream,
//   inverseTransformWindowedMultiLevel53(ll, ..., outputRegion).data
//     ==
//   inverseTransformMultiLevel53(ll, ..., subbands).data
//     cropped to outputRegion (column-major flattened)
// bit-exact across the 5/3 reversible path.

import XCTest
@testable import J2KCore
@testable import J2KCodec

final class V10_24_WindowedIDWTParityTests: XCTestCase {

    /// Construct a synthetic `(ll, subbands)` tuple of the shape
    /// inverseTransformMultiLevel53 expects: LL at the deepest level
    /// + N levels of LH/HL/HH bands. Dimensions follow the standard
    /// 5/3 partition: each band's width = ceil(parent / 2), etc.
    private func synthesizeBands(
        tileW: Int, tileH: Int, levels: Int, seed: UInt64
    ) -> (ll: [Int32], llW: Int, llH: Int,
          subbands: [(lh: [Int32], lhW: Int, lhH: Int,
                       hl: [Int32], hlW: Int, hlH: Int,
                       hh: [Int32], hhW: Int, hhH: Int)]) {
        // Compute per-level dims: depth 0 = (tileW, tileH), depth d = halve.
        var dims: [(w: Int, h: Int)] = [(tileW, tileH)]
        for _ in 0..<levels {
            let (pw, ph) = dims.last!
            dims.append(((pw + 1) / 2, (ph + 1) / 2))
        }
        // LL at deepest level d = levels.
        let llW = dims[levels].w  /// LL is depth-`levels`
        let llH = dims[levels].h
        let llCount = llW * llH

        func lcgFill(count: Int, seed: UInt64) -> [Int32] {
            var s = seed &* 6364136223846793005 &+ 1442695040888963407
            var out = [Int32](repeating: 0, count: count)
            for i in 0..<count {
                s = s &* 6364136223846793005 &+ 1442695040888963407
                // 16-bit signed range — typical for medical lossless coefficients
                out[i] = Int32(Int16(truncatingIfNeeded: Int((s >> 32) & 0xFFFF)))
            }
            return out
        }

        let ll = lcgFill(count: llCount, seed: seed)

        // Build subbands deepest-first. subbands[0] is for the deepest
        // lift step (inputs deepest LL + deepest LH/HL/HH).
        var subbands: [(lh: [Int32], lhW: Int, lhH: Int,
                         hl: [Int32], hlW: Int, hlH: Int,
                         hh: [Int32], hhW: Int, hhH: Int)] = []
        for d in (1...levels).reversed() {
            let parentW = dims[d - 1].w
            let parentH = dims[d - 1].h
            let llWd = dims[d].w
            let llHd = dims[d].h
            let hlWd = parentW - llWd
            let lhHd = parentH - llHd
            // Each band has its own w × h.
            let lh = lcgFill(count: llWd * lhHd, seed: seed &+ UInt64(d) &* 7)
            let hl = lcgFill(count: hlWd * llHd, seed: seed &+ UInt64(d) &* 11)
            let hh = lcgFill(count: hlWd * lhHd, seed: seed &+ UInt64(d) &* 13)
            subbands.append((lh: lh, lhW: llWd, lhH: lhHd,
                             hl: hl, hlW: hlWd, hlH: llHd,
                             hh: hh, hhW: hlWd, hhH: lhHd))
        }
        return (ll, llW, llH, subbands)
    }

    /// Crop a flat row-major Int32 buffer to a region (test-side oracle).
    private func cropRegion(_ data: [Int32], srcW: Int, srcH: Int,
                            region: J2KRegion) -> [Int32] {
        var out = [Int32](repeating: 0, count: region.width * region.height)
        for y in 0..<region.height {
            let srcOff = (region.y + y) * srcW + region.x
            let dstOff = y * region.width
            for x in 0..<region.width {
                out[dstOff + x] = data[srcOff + x]
            }
        }
        return out
    }

    private func runParity(
        label: String,
        tileW: Int, tileH: Int, levels: Int,
        regions: [J2KRegion]
    ) async {
        let bands = synthesizeBands(tileW: tileW, tileH: tileH,
                                    levels: levels, seed: 0xC0FFEE)
        let optimizer = J2KDWT2DOptimizer()
        let fullResult = await optimizer.inverseTransformMultiLevel53(
            ll: bands.ll, llW: bands.llW, llH: bands.llH,
            subbands: bands.subbands)
        XCTAssertEqual(fullResult.width, tileW, "[\(label)] full output width")
        XCTAssertEqual(fullResult.height, tileH, "[\(label)] full output height")

        for region in regions {
            let oracle = cropRegion(fullResult.data,
                                    srcW: fullResult.width,
                                    srcH: fullResult.height,
                                    region: region)
            let windowed = await optimizer.inverseTransformWindowedMultiLevel53(
                ll: bands.ll, llW: bands.llW, llH: bands.llH,
                subbands: bands.subbands,
                outputRegion: region)
            XCTAssertEqual(windowed.width, region.width,
                           "[\(label)] region (\(region.x),\(region.y),\(region.width)×\(region.height)) windowed width")
            XCTAssertEqual(windowed.height, region.height,
                           "[\(label)] region windowed height")
            // First-divergent diagnostic
            if windowed.data != oracle {
                var firstDiff = -1
                for i in 0..<min(windowed.data.count, oracle.count) {
                    if windowed.data[i] != oracle[i] { firstDiff = i; break }
                }
                XCTFail("""
                [\(label)] region (\(region.x),\(region.y),\(region.width)×\(region.height)) windowed ≠ oracle.
                First mismatch at flat-index \(firstDiff) of \(oracle.count):
                  oracle = \(firstDiff >= 0 ? String(describing: oracle[firstDiff]) : "n/a")
                  windowed = \(firstDiff >= 0 ? String(describing: windowed.data[firstDiff]) : "n/a")
                """)
                return
            }
        }
    }

    func testWindowedParity_DX2800x2288_5levels() async {
        let W = 2800, H = 2288
        await runParity(label: "DX 2800×2288", tileW: W, tileH: H, levels: 5,
            regions: [
                J2KRegion(x: W/2 - 128, y: H/2 - 128, width: 256, height: 256),
                J2KRegion(x: 0, y: 0, width: 256, height: 256),
                J2KRegion(x: W - 256, y: H - 256, width: 256, height: 256),
                J2KRegion(x: W/4, y: H/4, width: 512, height: 512),
                J2KRegion(x: 100, y: 100, width: 64, height: 64),
            ])
    }

    func testWindowedParity_CT512_5levels() async {
        let W = 512, H = 512
        await runParity(label: "CT 512²", tileW: W, tileH: H, levels: 5,
            regions: [
                J2KRegion(x: W/2 - 64, y: H/2 - 64, width: 128, height: 128),
                J2KRegion(x: 0, y: 0, width: 128, height: 128),
                J2KRegion(x: W - 128, y: H - 128, width: 128, height: 128),
                J2KRegion(x: W/4, y: H/4, width: 256, height: 256),
                J2KRegion(x: 32, y: 32, width: 32, height: 32),
            ])
    }

    func testWindowedParity_PX2459x1316_5levels() async {
        let W = 2459, H = 1316
        await runParity(label: "PX 2459×1316", tileW: W, tileH: H, levels: 5,
            regions: [
                J2KRegion(x: W/2 - 128, y: H/2 - 128, width: 256, height: 256),
                J2KRegion(x: 0, y: 0, width: 256, height: 256),
                J2KRegion(x: W - 256, y: H - 256, width: 256, height: 256),
                J2KRegion(x: W/4, y: H/4, width: 256, height: 128),  // wide+short
            ])
    }

    /// A very small region (64×64) that exercises the deepest-level
    /// halo edge cases.
    func testWindowedParity_TinyRegion() async {
        let W = 1024, H = 1024
        await runParity(label: "1024² tiny", tileW: W, tileH: H, levels: 5,
            regions: [
                J2KRegion(x: 256, y: 256, width: 64, height: 64),
                J2KRegion(x: 256, y: 256, width: 32, height: 32),
                J2KRegion(x: 0, y: 0, width: 64, height: 64),  // top-left
                J2KRegion(x: W - 32, y: H - 32, width: 32, height: 32), // br
            ])
    }

    /// Fewer-levels case (3 levels).
    func testWindowedParity_3Levels() async {
        let W = 1024, H = 1024
        await runParity(label: "1024² 3-level", tileW: W, tileH: H, levels: 3,
            regions: [
                J2KRegion(x: 256, y: 256, width: 256, height: 256),
                J2KRegion(x: 0, y: 0, width: 128, height: 128),
            ])
    }
}
