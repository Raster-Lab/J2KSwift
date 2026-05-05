// J2KEncodeTilePlanner.swift
// v5.39 M4 / v6-alpha1 — multi-tile HT lossless architecture prototype.
//
// The single-tile encoder hits a structural ceiling on large fixtures
// (M3 diagnosis: DX 81 ms vs Kakadu 19 ms). The most-likely-to-clear-
// gate intervention identified in M3 was multi-tile encoding (each
// tile gets its own DWT + entropy + codestream segment, running in
// parallel). This module is the planner: it decides how many tiles
// to use based on image dimensions and the user-set environment flag.
//
// Production default is `single` — same code path as v5.38. Multi-
// tile modes are opt-in via `J2K_HT_TILE_MODE` env var:
//   - `single`   — 1×1, the current behaviour (default).
//   - `2x2`      — 2 columns × 2 rows = 4 tiles.
//   - `4x4`      — 4×4 = 16 tiles.
//   - `strips4`  — 1 column × 4 rows = 4 horizontal strips.
//   - `auto`     — pick 2x2 if pixels >= 3 M, else `single`.
//
// The planner refuses multi-tile when the resulting tile would be
// smaller than `2 ** decompositionLevels` in either dimension —
// without that floor the per-tile DWT can't run with the encoder's
// configured decomposition depth.

import Foundation

/// Selector for the multi-tile encode path. Read once at process
/// startup from `J2K_HT_TILE_MODE`; production default is `.single`.
public enum J2KHTTileMode: Sendable, CustomStringConvertible {
    case single
    case tiles2x2
    case tiles4x4
    case strips4
    case auto

    public var description: String {
        switch self {
        case .single:    return "single"
        case .tiles2x2:  return "2x2"
        case .tiles4x4:  return "4x4"
        case .strips4:   return "strips4"
        case .auto:      return "auto"
        }
    }

    public static func from(envValue: String?) -> J2KHTTileMode {
        guard let v = envValue?.lowercased() else { return .single }
        switch v {
        case "single", "1x1":          return .single
        case "2x2", "tiles2x2":        return .tiles2x2
        case "4x4", "tiles4x4":        return .tiles4x4
        case "strips4", "1x4":         return .strips4
        case "auto":                   return .auto
        default:                       return .single
        }
    }
}

/// Concrete tile grid produced by the planner — `cols × rows` tiles
/// each of fixed `tileWidth × tileHeight` (the trailing column / row
/// may be smaller if image dims aren't multiples). All tiles share
/// the same encoder configuration (same COD / QCD / decomp levels).
public struct J2KTileLayout: Sendable, CustomStringConvertible {
    public let cols: Int
    public let rows: Int
    public let tileWidth: Int
    public let tileHeight: Int
    public let imageWidth: Int
    public let imageHeight: Int

    public var tileCount: Int { cols * rows }
    public var isMultiTile: Bool { tileCount > 1 }

    /// Pixel-rect for tile k in row-major order (k = row * cols + col).
    /// Trailing tiles may have smaller width / height when image dims
    /// aren't exact multiples of `tileWidth` / `tileHeight`.
    public func rect(forTile k: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        precondition(k >= 0 && k < tileCount, "tile index out of range")
        let col = k % cols
        let row = k / cols
        let x = col * tileWidth
        let y = row * tileHeight
        let w = min(tileWidth, imageWidth - x)
        let h = min(tileHeight, imageHeight - y)
        return (x, y, w, h)
    }

    public var description: String {
        "\(cols)x\(rows) (\(tileWidth)×\(tileHeight))"
    }
}

/// Planner: picks the tile layout for a given image and environment-
/// requested mode. Refuses multi-tile when the resulting tile is too
/// small to support the encoder's decomposition depth.
public enum J2KEncodeTilePlanner {

    /// Cached env-var read at process startup. Only consulted when
    /// the encoder explicitly opts into the planner-driven path; the
    /// production default flow ignores it entirely.
    nonisolated(unsafe) public static let envMode: J2KHTTileMode = {
        J2KHTTileMode.from(envValue: ProcessInfo.processInfo.environment["J2K_HT_TILE_MODE"])
    }()

    /// Compute a tile layout for the given image. `decompositionLevels`
    /// is honoured as a sanity floor: each tile must be ≥ 2^N pixels
    /// in each dimension or the per-tile DWT fails.
    public static func plan(
        imageWidth: Int,
        imageHeight: Int,
        decompositionLevels: Int,
        mode: J2KHTTileMode
    ) -> J2KTileLayout {
        let pixels = imageWidth * imageHeight
        let chosen: J2KHTTileMode
        switch mode {
        case .auto:
            chosen = pixels >= 3_000_000 ? .tiles2x2 : .single
        default:
            chosen = mode
        }

        let (cols, rows): (Int, Int)
        switch chosen {
        case .single:    (cols, rows) = (1, 1)
        case .tiles2x2:  (cols, rows) = (2, 2)
        case .tiles4x4:  (cols, rows) = (4, 4)
        case .strips4:   (cols, rows) = (1, 4)
        case .auto:      (cols, rows) = (1, 1)  // resolved above
        }

        let tileW = (imageWidth  + cols - 1) / cols
        let tileH = (imageHeight + rows - 1) / rows

        // Sanity floor: each tile must be ≥ 2^decompositionLevels
        // along each axis or the per-tile DWT cannot run with that
        // depth. If we're below the floor, fall back to single-tile.
        let minDim = 1 << decompositionLevels
        if tileW < minDim || tileH < minDim {
            return J2KTileLayout(
                cols: 1, rows: 1,
                tileWidth: imageWidth, tileHeight: imageHeight,
                imageWidth: imageWidth, imageHeight: imageHeight)
        }

        return J2KTileLayout(
            cols: cols, rows: rows,
            tileWidth: tileW, tileHeight: tileH,
            imageWidth: imageWidth, imageHeight: imageHeight)
    }
}
