// J2KMultiTileEncoder.swift
// v5.39 M4 / v6-alpha1 — multi-tile HT lossless prototype: scheduler
// + outer encode wrapper.
//
// Per-tile encode is currently the existing `J2KEncoder.encode(_:)`
// pipeline applied to a sub-image (so M5/M7/M8/M9 wins persist
// unchanged inside each tile). The scheduler runs N tile encodes
// in parallel via `withTaskGroup`, captures per-tile wall time and
// output bytes, and returns results in deterministic tile-index
// order.
//
// Production code path is unchanged: this module is only invoked
// when the planner returns a multi-tile layout. Single-tile
// callers go straight to the existing pipeline.
//
// Determinism note: parallel encode is deterministic in the bytes
// each tile produces (each tile's encode is fully deterministic
// per the existing pipeline). The order of completion may vary;
// we collect with explicit indices and sort, so the stitched
// output is byte-identical across runs at the same tile mode.

import Foundation
@preconcurrency import J2KCore

/// Per-tile observation captured by the work scheduler — used by
/// the M4 benchmark to print the load-balance table and is part
/// of the diagnostic surface, not the production return.
///
/// v6-alpha3 step 3 added `originX` / `originY` so tests can probe
/// that the multi-tile dispatcher actually threaded the per-tile
/// image-coordinate origin into the encoder pipeline (rather than
/// silently encoding every tile at (0, 0) as the wrap-and-stitch
/// prototype did).
public struct J2KTileWorkObservation: Sendable {
    public let tileIndex: Int
    public let pixels: Int
    public let tileBytes: Int
    public let encodeMs: Double
    public let originX: Int
    public let originY: Int
}

/// Aggregated result of a multi-tile encode — both the assembled
/// codestream and the per-tile observations used for diagnostics.
public struct J2KMultiTileEncodeResult: Sendable {
    public let codestream: Data
    public let layout: J2KTileLayout
    public let observations: [J2KTileWorkObservation]
}

enum J2KMultiTileEncoder {

    /// Run `N` per-tile encodes in parallel via `withTaskGroup`. Each
    /// task slices its tile from the parent image, builds a fresh
    /// `J2KEncoder` with the same configuration, and runs the
    /// existing `encode(_:)` pipeline. The encoder's planner is NOT
    /// re-consulted inside the per-tile encode (we route directly to
    /// the single-tile pipeline via a config flag).
    static func encode(
        image: J2KImage,
        layout: J2KTileLayout,
        configuration: J2KEncodingConfiguration
    ) async throws -> J2KMultiTileEncodeResult {

        let n = layout.tileCount
        precondition(n >= 1, "tile count must be ≥ 1")

        // Per-tile encode tasks. Each task captures its tile index
        // so we can sort results back into deterministic order.
        var perTileBytes = [Data?](repeating: nil, count: n)
        var observations = [J2KTileWorkObservation?](repeating: nil, count: n)

        try await withThrowingTaskGroup(
            of: (Int, Data, Double, Int, Int).self
        ) { group in
            for k in 0..<n {
                let captureImage = image
                let captureLayout = layout
                let captureConfig = configuration
                group.addTask {
                    // v6-alpha3 step 3: compute the tile's actual
                    // image-coordinate origin and thread it into the
                    // per-tile encode. The slicer carves the
                    // sub-image's pixel data; the origin is the rect
                    // returned by the layout (matches what the
                    // multi-tile decoder will use to place tile k's
                    // pixels back into the image grid).
                    let r = captureLayout.rect(forTile: k)
                    let subImage = try J2KTileImageSlicer.sliceTile(
                        from: captureImage,
                        layout: captureLayout,
                        tileIndex: k)
                    let encoder = J2KEncoder(encodingConfiguration: captureConfig)
                    let t0 = CFAbsoluteTimeGetCurrent()
                    // Route directly to the single-tile pipeline,
                    // origin-aware overload. Bypassing the planner so
                    // we don't recurse.
                    let bytes = try await encoder._singleTileEncode(
                        subImage,
                        tileOriginX: r.x,
                        tileOriginY: r.y)
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                    return (k, bytes, dt, r.x, r.y)
                }
            }
            for try await (k, bytes, dt, ox, oy) in group {
                perTileBytes[k] = bytes
                let r = layout.rect(forTile: k)
                observations[k] = J2KTileWorkObservation(
                    tileIndex: k,
                    pixels: r.w * r.h,
                    tileBytes: bytes.count,
                    encodeMs: dt,
                    originX: ox,
                    originY: oy)
            }
        }

        // Assemble in deterministic tile-index order.
        let orderedTileBytes = perTileBytes.compactMap { $0 }
        precondition(orderedTileBytes.count == n,
                     "missing per-tile codestream after parallel encode")

        let stitched = try J2KMultiTileAssembler.stitch(
            perTile: orderedTileBytes,
            imageWidth: image.width,
            imageHeight: image.height)

        return J2KMultiTileEncodeResult(
            codestream: stitched,
            layout: layout,
            observations: observations.compactMap { $0 })
    }
}
