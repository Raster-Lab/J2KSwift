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
public struct J2KTileWorkObservation: Sendable {
    public let tileIndex: Int
    public let pixels: Int
    public let tileBytes: Int
    public let encodeMs: Double
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
            of: (Int, Data, Double).self
        ) { group in
            for k in 0..<n {
                let captureImage = image
                let captureLayout = layout
                let captureConfig = configuration
                group.addTask {
                    let subImage = try J2KTileImageSlicer.sliceTile(
                        from: captureImage,
                        layout: captureLayout,
                        tileIndex: k)
                    let encoder = J2KEncoder(encodingConfiguration: captureConfig)
                    let t0 = CFAbsoluteTimeGetCurrent()
                    // Route directly to the single-tile pipeline —
                    // bypassing the planner so we don't recurse.
                    let bytes = try await encoder._singleTileEncode(subImage)
                    let dt = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                    return (k, bytes, dt)
                }
            }
            for try await (k, bytes, dt) in group {
                perTileBytes[k] = bytes
                let r = layout.rect(forTile: k)
                observations[k] = J2KTileWorkObservation(
                    tileIndex: k,
                    pixels: r.w * r.h,
                    tileBytes: bytes.count,
                    encodeMs: dt)
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
