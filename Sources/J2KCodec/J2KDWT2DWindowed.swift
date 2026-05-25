//
// J2KDWT2DWindowed.swift
// J2KSwift
//
// v10.15.0 (v10.24-research) — windowed multi-level inverse 5/3 DWT
// for ROI Stage 3 (single-tile / partially-touched-tile decode).
//
// The existing `J2KDWT2DOptimizer.inverseTransformMultiLevel53`
// processes the WHOLE tile across N decomposition levels — even when
// the caller only wants a small region. For ROI decode on single-tile
// codestreams (CT / DX / PX / MR), this is the dominant cost
// (57% of the remaining wall after v10.6.0 entropy-skip per
// V10_24_ROIStage3Profile).
//
// This file ships a parity-safe additive surface that walks levels
// deepest-first, extracts only the windowed sub-bands needed to
// produce the requested output region (with cumulative halo to
// compensate for the lift's symmetric-extension boundary cells),
// and trims halo cells after each level's lift. The existing
// `inverseTransformMultiLevel53` is NOT touched — it remains the
// path for full-tile decode and for the existing parity-sensitive
// cross-codec gates.
//
// Bit-exact equivalence guarantee:
//   inverseTransformWindowedMultiLevel53(ll, ..., outputRegion).data
//     ==
//   inverseTransformMultiLevel53(ll, ..., subbands).data cropped to outputRegion
//
// Validated by V10_24_WindowedIDWTParityTests across corner /
// centre / edge regions × multiple sizes × CT/DX/PX-sized tiles.

import Foundation
import J2KCore

extension J2KDWT2DOptimizer {

    /// v10.15.0 — windowed multi-level inverse 5/3.
    ///
    /// Computes ONLY the samples of the output covering `outputRegion`
    /// (in level-0 = full-resolution image coords). Walks deepest-first
    /// to compute per-level input regions with cumulative halo, then
    /// forward to lift each level on a windowed workspace.
    ///
    /// - Parameters:
    ///   - ll: LL subband coefficients (flat, row-major) — the deepest
    ///     LL band. Same as `inverseTransformMultiLevel53`'s `ll`.
    ///   - llW: Width of the LL subband (deepest).
    ///   - llH: Height of the LL subband (deepest).
    ///   - subbands: Per-level subbands ordered deepest-first
    ///     (smallest → largest). Each element carries
    ///     `(lh, lhW, lhH, hl, hlW, hlH, hh, hhW, hhH)`. Same shape as
    ///     `inverseTransformMultiLevel53`.
    ///   - outputRegion: The region of the level-0 output to produce.
    ///     `(0, 0, W, H)` reduces to a full-tile decode + crop (use
    ///     `inverseTransformMultiLevel53` directly for that case).
    /// - Returns: Flat row-major `[Int32]` of size
    ///   `outputRegion.width × outputRegion.height`.
    public func inverseTransformWindowedMultiLevel53(
        ll: [Int32], llW: Int, llH: Int,
        subbands: [(lh: [Int32], lhW: Int, lhH: Int,
                     hl: [Int32], hlW: Int, hlH: Int,
                     hh: [Int32], hhW: Int, hhH: Int)],
        outputRegion: J2KRegion
    ) async -> (data: [Int32], width: Int, height: Int) {
        let N = subbands.count
        guard N > 0 else {
            // No iDWT levels — just crop the LL.
            return Self.cropFlat(
                src: ll, srcW: llW, srcH: llH, region: outputRegion)
        }

        // HALO per side per axis per level. The lift's symmetric-
        // extension boundary reaches 2 cells in from the workspace
        // edge per pass (predict + update both touch ±1, the
        // first-cell special case touches up to ±2). Two passes (row +
        // column) accumulate orthogonally on different axes, so HALO=4
        // is safe per axis per level (with a small over-decode margin
        // versus the strict minimum of 2). Per-level cumulative halo
        // walks deepest-first.
        let HALO = 4

        // ---- Pass 1: Compute per-level input regions (walking
        // shallowest → deepest, but in subbands' lift-order — i.e.,
        // reverse iteration over subbands).
        //
        // perLevelInput[i] is the input band region for the lift step
        // that processes subbands[i] (i=0 deepest, i=N-1 shallowest).
        // The level i lift PRODUCES output at level (N-i-1) coords;
        // the INPUT is at level (N-i) coords.
        //
        // We start with the requested output region at level 0 (image
        // coords) and walk inward by halving + halo per level.
        var perLevelInput = [(xLo: Int, yLo: Int, w: Int, h: Int)](
            repeating: (0, 0, 0, 0), count: N)
        // currentOutput tracks "what region must this level produce"
        // — starts as outputRegion at level 0 coords.
        var currentOutput = (
            xLo: outputRegion.x, yLo: outputRegion.y,
            w: outputRegion.width, h: outputRegion.height)
        // Walk from shallowest lift (i = N-1) to deepest (i = 0).
        for i in (0..<N).reversed() {
            // Input band dimensions at this level: LL at this level
            // matches LH's width and HL's height (both are at the
            // input depth).
            let inputBandW: Int
            let inputBandH: Int
            if i == 0 {
                inputBandW = llW
                inputBandH = llH
            } else {
                inputBandW = subbands[i].lhW
                inputBandH = subbands[i].hlH
            }
            let halfXLo = currentOutput.xLo / 2
            let halfYLo = currentOutput.yLo / 2
            let halfXHi = (currentOutput.xLo + currentOutput.w + 1) / 2
            let halfYHi = (currentOutput.yLo + currentOutput.h + 1) / 2
            let inXLo = max(0, halfXLo - HALO)
            let inYLo = max(0, halfYLo - HALO)
            let inXHi = min(inputBandW, halfXHi + HALO)
            let inYHi = min(inputBandH, halfYHi + HALO)
            let inputRegion = (xLo: inXLo, yLo: inYLo,
                               w: inXHi - inXLo, h: inYHi - inYLo)
            perLevelInput[i] = inputRegion
            currentOutput = inputRegion  // next deeper level produces THIS region
        }

        // ---- Pass 2: Walk forward (deepest → shallowest) and lift.
        //
        // At each level i, we have:
        //   • Input LL = `currentLL` buffer covering perLevelInput[i] region
        //     (in level-(N-i) coords). currentLL dims = (inputRegion.w, inputRegion.h).
        //   • Input LH/HL/HH = extracted sub-arrays from subbands[i] at
        //     the same region in level-(N-i) coords.
        //   • Lift produces 2× output: size (2*inputRegion.w, 2*inputRegion.h).
        //     The output is in level-(N-i-1) coords; the workspace
        //     "covers" region (2*inputRegion.xLo .. 2*inputRegion.xHi).
        //   • For the next level, the relevant slice of the workspace
        //     is the inner core: indices that correspond to
        //     perLevelInput[i-1] (if i > 0) or outputRegion (if i == 0).

        // Extract the windowed initial LL from `ll`.
        let deepestInput = perLevelInput[0]
        var currentLL = Self.extractFlat(
            src: ll, srcW: llW, srcH: llH,
            xLo: deepestInput.xLo, yLo: deepestInput.yLo,
            w: deepestInput.w, h: deepestInput.h)
        var currentLLW = deepestInput.w
        var currentLLH = deepestInput.h
        var currentLLXLo = deepestInput.xLo
        var currentLLYLo = deepestInput.yLo

        for i in 0..<N {
            let inputRegion = perLevelInput[i]
            // The current LL we hold corresponds to perLevelInput[i] in
            // band coords. Sanity:
            precondition(currentLLW == inputRegion.w &&
                         currentLLH == inputRegion.h &&
                         currentLLXLo == inputRegion.xLo &&
                         currentLLYLo == inputRegion.yLo,
                "Windowed iDWT: current LL doesn't match expected input region")

            // Extract windowed LH/HL/HH from subbands[i] at inputRegion,
            // constrained to each band's actual dims. At tile edges the
            // detail bands can be 1 cell shorter than the LL in either
            // axis (standard 5/3 partition: parent = LL + detail per
            // axis; when parent is odd-sized, LL gets the ceil and
            // detail gets the floor → detail dim = LL dim − 1 at the
            // edge that touches the odd-sized tile boundary). The lift
            // needs the ACTUAL windowed dims (not the LL inputRegion
            // dims) for its workspace sizing to match the full path.
            let lhBW = subbands[i].lhW; let lhBH = subbands[i].lhH
            let hlBW = subbands[i].hlW; let hlBH = subbands[i].hlH
            let hhBW = subbands[i].hhW; let hhBH = subbands[i].hhH
            // Windowed dims per band: clamp the requested region to the
            // band's own bounds. The dim is the COUNT of valid samples
            // in [inputRegion.xLo, inputRegion.xLo + inputRegion.w) ∩ [0, bandDim).
            let lhWinW = max(0, min(inputRegion.w, lhBW - inputRegion.xLo))
            let lhWinH = max(0, min(inputRegion.h, lhBH - inputRegion.yLo))
            let hlWinW = max(0, min(inputRegion.w, hlBW - inputRegion.xLo))
            let hlWinH = max(0, min(inputRegion.h, hlBH - inputRegion.yLo))
            let hhWinW = max(0, min(inputRegion.w, hhBW - inputRegion.xLo))
            let hhWinH = max(0, min(inputRegion.h, hhBH - inputRegion.yLo))
            let lhWindowed = Self.extractFlat(
                src: subbands[i].lh, srcW: lhBW, srcH: lhBH,
                xLo: inputRegion.xLo, yLo: inputRegion.yLo,
                w: lhWinW, h: lhWinH)
            let hlWindowed = Self.extractFlat(
                src: subbands[i].hl, srcW: hlBW, srcH: hlBH,
                xLo: inputRegion.xLo, yLo: inputRegion.yLo,
                w: hlWinW, h: hlWinH)
            let hhWindowed = Self.extractFlat(
                src: subbands[i].hh, srcW: hhBW, srcH: hhBH,
                xLo: inputRegion.xLo, yLo: inputRegion.yLo,
                w: hhWinW, h: hhWinH)

            // Run one level's lift on the windowed workspace. Workspace
            // dims = (LL_w + HL_w, LL_h + LH_h) — exact same formula
            // the full-tile path uses. The lift's symmetric-extension
            // boundary at the workspace's left/top is wrong (in the
            // middle of the tile) → halo cells absorb it and get
            // trimmed by the next-level input-region extraction. At
            // the right/bottom where the windowed region touches the
            // tile edge, the boundary IS at the band edge and the
            // extension is correct.
            let oneLevelSubbands: [(lh: [Int32], lhW: Int, lhH: Int,
                                     hl: [Int32], hlW: Int, hlH: Int,
                                     hh: [Int32], hhW: Int, hhH: Int)] = [
                (lh: lhWindowed, lhW: lhWinW, lhH: lhWinH,
                 hl: hlWindowed, hlW: hlWinW, hlH: hlWinH,
                 hh: hhWindowed, hhW: hhWinW, hhH: hhWinH)
            ]
            // Note: The single-level lift expects LH/HL/HH dims that
            // combine with LL dims to produce a 2x output. For our
            // windowed case where LL is w×h, LH is also w×h (matching
            // the inputRegion in its own band coords).
            let oneLevel = await inverseTransformMultiLevel53(
                ll: currentLL, llW: currentLLW, llH: currentLLH,
                subbands: oneLevelSubbands)
            // oneLevel.data is the workspace output at this level's
            // OUTPUT coord space, dims = (2*inputRegion.w, 2*inputRegion.h).
            // The output's region in level-(N-i-1) coords spans:
            //   xLo = 2 * inputRegion.xLo .. xLo + 2*inputRegion.w
            //   yLo = 2 * inputRegion.yLo .. yLo + 2*inputRegion.h
            let workspaceXLo = 2 * inputRegion.xLo
            let workspaceYLo = 2 * inputRegion.yLo
            let workspaceW = oneLevel.width
            let workspaceH = oneLevel.height

            if i == N - 1 {
                // This is the shallowest level — output is at level 0
                // coords. Extract the requested outputRegion from the
                // workspace.
                let cropped = Self.extractFlat(
                    src: oneLevel.data, srcW: workspaceW, srcH: workspaceH,
                    xLo: outputRegion.x - workspaceXLo,
                    yLo: outputRegion.y - workspaceYLo,
                    w: outputRegion.width, h: outputRegion.height)
                return (data: cropped, width: outputRegion.width, height: outputRegion.height)
            }

            // For the next (shallower) level, the input region is
            // perLevelInput[i+1] in level-(N-i-1) coords. Extract the
            // corresponding sub-array of the workspace.
            let nextInputRegion = perLevelInput[i + 1]
            let nextLL = Self.extractFlat(
                src: oneLevel.data, srcW: workspaceW, srcH: workspaceH,
                xLo: nextInputRegion.xLo - workspaceXLo,
                yLo: nextInputRegion.yLo - workspaceYLo,
                w: nextInputRegion.w, h: nextInputRegion.h)
            currentLL = nextLL
            currentLLW = nextInputRegion.w
            currentLLH = nextInputRegion.h
            currentLLXLo = nextInputRegion.xLo
            currentLLYLo = nextInputRegion.yLo
        }

        // Unreachable — loop returns at i == N - 1.
        return (data: currentLL, width: currentLLW, height: currentLLH)
    }

    // MARK: - Internal helpers

    /// Crops a sub-rectangle from a flat row-major Int32 buffer into
    /// a new flat Int32 array.
    @usableFromInline
    static func cropFlat(
        src: [Int32], srcW: Int, srcH: Int, region: J2KRegion
    ) -> (data: [Int32], width: Int, height: Int) {
        var dst = [Int32](repeating: 0, count: region.width * region.height)
        let copyW = min(region.width, srcW - region.x)
        let copyH = min(region.height, srcH - region.y)
        for y in 0..<copyH {
            let srcOff = (region.y + y) * srcW + region.x
            let dstOff = y * region.width
            for x in 0..<copyW {
                dst[dstOff + x] = src[srcOff + x]
            }
        }
        return (data: dst, width: region.width, height: region.height)
    }

    /// Extracts a sub-rectangle from a flat row-major buffer at
    /// `(xLo, yLo, w, h)` into a fresh `[Int32]`. No clamping / padding;
    /// assumes the region is fully in-bounds.
    @usableFromInline
    static func extractFlat(
        src: [Int32], srcW: Int, srcH: Int,
        xLo: Int, yLo: Int, w: Int, h: Int
    ) -> [Int32] {
        var dst = [Int32](repeating: 0, count: w * h)
        for y in 0..<h {
            let srcOff = (yLo + y) * srcW + xLo
            let dstOff = y * w
            for x in 0..<w {
                dst[dstOff + x] = src[srcOff + x]
            }
        }
        return dst
    }

    /// Extracts a sub-rectangle from a flat row-major buffer at
    /// `(xLo, yLo, w, h)` into a fresh `[Int32]`, zero-padding cells
    /// that fall outside `(0..copyW × 0..copyH)`.
    @usableFromInline
    static func extractFlatPadded(
        src: [Int32], srcW: Int, srcH: Int,
        xLo: Int, yLo: Int, w: Int, h: Int,
        copyW: Int, copyH: Int
    ) -> [Int32] {
        var dst = [Int32](repeating: 0, count: w * h)
        for y in 0..<copyH {
            let srcRow = yLo + y
            guard srcRow >= 0, srcRow < srcH else { continue }
            let srcOff = srcRow * srcW + xLo
            let dstOff = y * w
            for x in 0..<copyW {
                let srcCol = xLo + x
                guard srcCol >= 0, srcCol < srcW else { continue }
                dst[dstOff + x] = src[srcOff + x]
            }
        }
        return dst
    }
}
