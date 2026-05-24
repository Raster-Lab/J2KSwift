//
// J2KJP3DBridge.swift
// J2KSwift
//
// v10.20-research — JP3D batched GPU iDWT bridge SPI.
//
// JP3D's slice-stack codec decodes N slices' 2D codestreams one at
// a time today, with each slice paying its own GPU dispatch overhead
// when the 2D codec routes through GPU iDWT. For typical JP3D fixtures
// (256×256 / 512×512 per slice) the 2D codec's 4 MP threshold keeps
// every slice on CPU iDWT; even forcing GPU iDWT per-slice REGRESSES
// because per-slice dispatch overhead × N slices > CPU iDWT total
// (V10_19_JP3D_GPU_IDWT_CLOSED.md).
//
// The only path to a real GPU iDWT win for JP3D is BATCHED single-
// dispatch GPU iDWT — collect N slices' dequantized wavelet
// coefficients, submit ONE Metal dispatch that runs N parallel
// iDWTs (one threadgroup per slice along the Z grid axis), then
// scatter the results back per slice. Per-slice dispatch overhead
// amortises across the volume.
//
// This file ships the **bridge SPI** Phase 1 needs to make that
// possible: two methods on `J2KDecoder` that expose the pipeline
// split between dequantization and iDWT. Phase 2 will add the
// batched-dispatch GPU iDWT itself + the JP3DSliceStackCodec wiring
// that uses the bridge.
//
// **Bit-exact composition guarantee (Phase 1):**
//
//     decode(data) ≡ _jp3dIDWTAndFinalize(_jp3dDecodeToCoefficients(data))
//
// on every single-tile codestream — which is the wire format JP3D
// slices always use.
//
// Surface is `public func` (not `internal` / `@_spi`) because J2K3D
// depends on J2KCodec as a separate module; making the bridge SPI
// public lets J2K3D call it without an SPI-flag handshake. The leading
// underscore (`_jp3d...`) marks the methods as not-for-general-use:
// they're stable across patch versions but the intermediate
// `JP3DSliceCoefficients` type is opaque (no public fields) and
// consumers outside J2K3D should keep calling the normal
// `J2KDecoder.decode(_:)`.

import Foundation
import J2KCore

// MARK: - Internal payload

/// Opaque internal payload carried inside `JP3DSliceCoefficients`.
/// Not for consumption outside this module — accessed only by
/// `DecoderPipeline.iDWTAndFinalizeCoefficients`.
@usableFromInline
struct _JP3DSliceCoefficientsInternal: @unchecked Sendable {
    let metadata: CodestreamMetadata
    let dequantizedSubbands: [DecoderPipeline.SubbandInfo]
}

// MARK: - Public opaque coefficient bundle

/// Opaque dequantized-wavelet-coefficient bundle. Produced by
/// `J2KDecoder._jp3dDecodeToCoefficients(_:)`; consumed by
/// `J2KDecoder._jp3dIDWTAndFinalize(_:)`. Carrying this between the
/// two calls lets the JP3D slice-stack codec collect N slices'
/// coefficients before submitting one batched GPU iDWT dispatch
/// (Phase 2).
///
/// The contained payload is internal to J2KCodec; no public fields.
public struct JP3DSliceCoefficients: @unchecked Sendable {
    @usableFromInline
    let _internal: _JP3DSliceCoefficientsInternal

    @usableFromInline
    init(_internal: _JP3DSliceCoefficientsInternal) {
        self._internal = _internal
    }

    /// Pixel dimensions of the slice this coefficients bundle will
    /// produce after iDWT + reconstruction. Useful for the JP3D
    /// caller's output-buffer sizing before iDWT runs.
    public var width: Int  { _internal.metadata.width }
    public var height: Int { _internal.metadata.height }
}

// MARK: - J2KDecoder SPI

extension J2KDecoder {

    /// v10.20-research JP3D bridge — Stage A: decode a single-tile
    /// 2D codestream THROUGH dequantization but BEFORE the inverse
    /// wavelet transform. Returns an opaque `JP3DSliceCoefficients`
    /// bundle the caller will later feed to `_jp3dIDWTAndFinalize`.
    ///
    /// **Bit-exact composition guarantee:**
    /// ```swift
    /// let direct  = try await decoder.decode(data)
    /// let coefs   = try await decoder._jp3dDecodeToCoefficients(data)
    /// let bridged = try await decoder._jp3dIDWTAndFinalize(coefs)
    /// // direct.components[i].data == bridged.components[i].data, byte-exact
    /// ```
    ///
    /// **Single-tile only.** JP3D's slice-stack codec only ever emits
    /// single-tile per-slice codestreams, so this restriction is
    /// invisible at the JP3D layer. A multi-tile codestream passed
    /// through this SPI throws `J2KError.notImplemented`.
    ///
    /// **Not for general use** — call the normal `decode(_:)` from
    /// outside the JP3D codec. The leading underscore marks this as
    /// a JP3D-specific bridge; the bundle's payload is opaque.
    public func _jp3dDecodeToCoefficients(
        _ data: Data
    ) async throws -> JP3DSliceCoefficients {
        var pipeline = DecoderPipeline()
        pipeline.metalSession = J2KMetalSession.processShared
        let inner = try await pipeline.decodeToCoefficients(data)
        return JP3DSliceCoefficients(_internal: inner)
    }

    /// v10.20-research JP3D bridge — Stage B+C: take a coefficient
    /// bundle produced by `_jp3dDecodeToCoefficients` and run iDWT +
    /// inverse colour transform + DC level unshift + image
    /// reconstruction, returning the final `J2KImage`.
    ///
    /// Equivalent to running the second half of `decode(_:)` on the
    /// stage-A output — but available as a separate call so the JP3D
    /// caller can collect N bundles and submit a single batched GPU
    /// iDWT dispatch between Stage A and Stage B (Phase 2).
    public func _jp3dIDWTAndFinalize(
        _ coefs: JP3DSliceCoefficients
    ) async throws -> J2KImage {
        var pipeline = DecoderPipeline()
        pipeline.metalSession = J2KMetalSession.processShared
        return try await pipeline.iDWTAndFinalizeCoefficients(coefs._internal)
    }

    /// v10.20-research Phase 3b — JP3D batched bridge SPI. Takes N
    /// coefficient bundles previously produced by
    /// `_jp3dDecodeToCoefficients` and runs ONE batched multi-level
    /// GPU iDWT dispatch across all N slices via
    /// `J2KMetalDWT.inverse2DInt32MultiLevelFusedBatched`, then
    /// finalises each slice into a `J2KImage`.
    ///
    /// For the JP3D-typical production shape (5/3 reversible, single-
    /// component slices, uniform dims across the batch, full
    /// resolution, no ROI), this delivers the per-slice GPU dispatch
    /// amortisation that Phase 3a measured at **2.4× on M2** for
    /// 16-slice 256×256×3-level batches.
    ///
    /// For any other shape (9/7 lossy, multi-component, non-uniform
    /// dims, partial-resolution, ROI) the bridge falls back to a
    /// per-slice serial loop via `_jp3dIDWTAndFinalize` — same
    /// output, no batched win. The fallback is invisible to callers
    /// and ensures the SPI never errors on a valid coefficient
    /// bundle.
    ///
    /// **Bit-exact composition guarantee**: for every slice `i` in
    /// the batch,
    /// ```
    /// batched[i].components[0].data ==
    ///     _jp3dIDWTAndFinalize(coefsBatch[i]).components[0].data
    /// ```
    /// — verified by `V10_20_BatchedBridgeParityTests`.
    public func _jp3dIDWTAndFinalizeBatched(
        _ coefsBatch: [JP3DSliceCoefficients]
    ) async throws -> [J2KImage] {
        var pipeline = DecoderPipeline()
        pipeline.metalSession = J2KMetalSession.processShared
        return try await pipeline.iDWTAndFinalizeCoefficientsBatched(
            coefsBatch.map { $0._internal })
    }
}
