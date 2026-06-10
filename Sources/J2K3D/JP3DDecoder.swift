//
// JP3DDecoder.swift
// J2KSwift
//
/// # JP3DDecoder
///
/// Core JP3D volumetric JPEG 2000 decoder.
///
/// Implements the complete JP3D decoding pipeline: codestream parsing,
/// tile data extraction, inverse quantization, 3D inverse wavelet transform,
/// and volume reconstruction. Conforms to ISO/IEC 15444-10.
///
/// ## Topics
///
/// ### Decoder Types
/// - ``JP3DDecoder``
/// - ``JP3DDecoderConfiguration``
/// - ``JP3DDecoderResult``

import Foundation
import J2KCore
import J2KCodec

/// Configuration for the JP3D decoder.
public struct JP3DDecoderConfiguration: Sendable {
    /// Maximum number of quality layers to decode (0 = all).
    public let maxQualityLayers: Int

    /// Resolution level to decode (0 = full, 1 = half, 2 = quarter, etc.).
    public let resolutionLevel: Int

    /// Whether to enable partial-result recovery on truncated/corrupted input.
    public let tolerateErrors: Bool

    /// Creates a decoder configuration.
    ///
    /// - Parameters:
    ///   - maxQualityLayers: Quality layers to decode. 0 means decode all (default: 0).
    ///   - resolutionLevel: Resolution reduction level (default: 0 = full resolution).
    ///   - tolerateErrors: Whether to continue decoding after recoverable errors (default: true).
    public init(
        maxQualityLayers: Int = 0,
        resolutionLevel: Int = 0,
        tolerateErrors: Bool = true
    ) {
        self.maxQualityLayers = max(0, maxQualityLayers)
        self.resolutionLevel = max(0, resolutionLevel)
        self.tolerateErrors = tolerateErrors
    }

    /// Full-resolution, all-layers decode.
    public static let `default` = JP3DDecoderConfiguration()

    /// Thumbnail decode at 1/4 resolution (2 levels up).
    public static let thumbnail = JP3DDecoderConfiguration(resolutionLevel: 2)
}

/// Result of a JP3D decode operation.
public struct JP3DDecoderResult: Sendable {
    /// The reconstructed volume.
    public let volume: J2KVolume

    /// Whether the result is a partial decode (truncated or corrupted input).
    public let isPartial: Bool

    /// Warnings encountered during decoding (e.g., skipped tiles).
    public let warnings: [String]

    /// Number of tiles successfully decoded.
    public let tilesDecoded: Int

    /// Total tiles expected.
    public let tilesTotal: Int
}

/// Progress update during decoding.
public struct JP3DDecoderProgress: Sendable {
    /// Current decoding stage.
    public let stage: JP3DDecodingStage

    /// Progress within the stage (0.0 to 1.0).
    public let stageProgress: Double

    /// Overall decode progress (0.0 to 1.0).
    public let overallProgress: Double

    /// Tiles decoded so far.
    public let tilesDecoded: Int

    /// Total tiles to decode.
    public let totalTiles: Int
}

/// Decoding pipeline stages.
public enum JP3DDecodingStage: String, Sendable {
    /// Parsing codestream marker segments.
    case parsing = "Parsing"
    /// Reconstructing tiles from quantized coefficients.
    case tileReconstruction = "Tile Reconstruction"
    /// Assembling tiles into the output volume.
    case volumeAssembly = "Volume Assembly"
}

/// JP3D volumetric JPEG 2000 decoder.
///
/// `JP3DDecoder` implements the complete JP3D decoding pipeline for
/// volumetric data conforming to ISO/IEC 15444-10.
///
/// ## Usage
///
/// ```swift
/// let decoder = JP3DDecoder()
/// let result = try await decoder.decode(data)
/// print("Volume: \(result.volume.width)×\(result.volume.height)×\(result.volume.depth)")
/// ```
///
/// ## Pipeline
///
/// 1. **Parsing**: Parse marker segments to extract volume metadata
/// 2. **Tile Reconstruction**: Dequantize and apply inverse wavelet transform per tile
/// 3. **Volume Assembly**: Place reconstructed tiles into the output volume
public actor JP3DDecoder {
    // MARK: - State

    private let configuration: JP3DDecoderConfiguration
    private var progressCallback: (@Sendable (JP3DDecoderProgress) -> Void)?

    // MARK: - Init

    /// Creates a decoder with the given configuration.
    ///
    /// - Parameter configuration: Decoder configuration. Defaults to `.default`.
    public init(configuration: JP3DDecoderConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Pre-warm

    /// Warm the shared Metal session before the first JP3D decode in
    /// a process.
    ///
    /// JP3D decoding internally delegates each per-slice 2D codestream
    /// to `J2KDecoder` (which uses `J2KMetalSession.processShared`).
    /// The very first decode in a process pays the one-shot Metal
    /// init cost (driver init + shader library compile + buffer-pool
    /// first-fetch); subsequent decodes reuse the warm session.
    ///
    /// Call this once at app / SDK startup if your workflow is one-
    /// shot JP3D decodes (e.g., a DICOM viewer opening one study)
    /// to move the init cost off the critical path:
    ///
    /// ```swift
    /// // App / SDK startup
    /// await JP3DDecoder.preWarm()
    ///
    /// // Later, the first JP3D decode runs at warm-process speed
    /// let result = try await JP3DDecoder().decode(jp3dData)
    /// ```
    ///
    /// Cold-vs-warm A/B (M2 release, mr_3d_small 128×128×16): first
    /// decode in process 30.42 ms → 13.84 ms after `preWarm` = **−16.25 ms
    /// cold-start savings**. The savings are constant per process
    /// (one-shot init cost) so they're most visible on small-volume
    /// JP3D decodes where the decode wall itself is short.
    ///
    /// Idempotent: subsequent calls within the same process are
    /// near-instant. Safe to call from multiple SDK boundaries.
    /// Failures (e.g. Metal unavailable on Linux) are silently
    /// caught — the decoder falls back to CPU paths.
    ///
    /// Equivalent to calling `J2KDecoder.preWarm(includeWarmupDispatch:)`
    /// directly (JP3D shares the same process-wide Metal session). The
    /// JP3D wrapper exists to make the API discoverable from the JP3D
    /// surface for callers that only import `J2K3D`.
    ///
    /// - Parameter includeWarmupDispatch: when `true` (default
    ///   `false`), runs a tiny synthetic 2D decode to exercise the
    ///   buffer-pool first-fetch and Metal driver first-dispatch
    ///   fence. Costs ~5-10 ms extra during the preWarm call but
    ///   saves an additional 10-20 ms on the actual first user JP3D
    ///   decode. Recommended for batch / PACS workflows; skip for
    ///   one-off decoders that may never run a real decode.
    public static func preWarm(includeWarmupDispatch: Bool = false) async {
        await J2KDecoder.preWarm(includeWarmupDispatch: includeWarmupDispatch)
    }

    // MARK: - Public API

    /// Sets the progress reporting callback.
    ///
    /// - Parameter callback: Called during decoding with progress updates.
    public func setProgressCallback(
        _ callback: @escaping @Sendable (JP3DDecoderProgress) -> Void
    ) {
        self.progressCallback = callback
    }

    /// Decodes a JP3D codestream to a volume.
    ///
    /// - Parameter data: The JP3D codestream produced by `JP3DEncoder`.
    /// - Returns: The decoding result including the reconstructed volume.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is malformed
    ///           (and `tolerateErrors` is false).
    public func decode(_ data: Data) async throws -> JP3DDecoderResult {
        reportProgress(.parsing, stageProgress: 0.0, tilesDone: 0, tilesTotal: 1)

        // Stage 1: Parse codestream
        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)
        let siz = codestream.siz

        reportProgress(.parsing, stageProgress: 1.0, tilesDone: 0,
                       tilesTotal: codestream.tiles.count)

        // Stage 2: Reconstruct tiles
        let grid = codestream.tileGrid
        let tilesExpected = grid.tilesX * grid.tilesY * grid.tilesZ

        // v10.18-research — partial-resolution path. resolutionLevel = K:
        // K = 0   → full resolution (current behaviour, all branches
        //           below collapse to their original arithmetic).
        // K > 0   → in-plane (X, Y) dims halved K times; depth (Z) is
        //           per-slice and unaffected. Tile origins and per-tile
        //           dimensions scale the same way so the assembled
        //           volume has no gaps or overlaps.
        let K = max(0, configuration.resolutionLevel)
        let scale = 1 << K
        @inline(__always) func down(_ n: Int) -> Int {
            (n + scale - 1) / scale
        }
        let outW = down(siz.width)
        let outH = down(siz.height)
        let outD = siz.depth

        // Allocate output component buffers (Float per voxel) at the
        // downsampled volume size.
        let voxelCount = outW * outH * outD
        var componentBuffers = [[Float]](
            repeating: [Float](repeating: 0, count: voxelCount),
            count: siz.componentCount
        )

        var warnings: [String] = []
        var tilesDecoded = 0
        var isPartial = false

        for (tileIdx, parsedTile) in codestream.tiles.enumerated() {
            let index = parsedTile.tileIndex
            let iz = index / (grid.tilesX * grid.tilesY)
            let rem = index % (grid.tilesX * grid.tilesY)
            let iy = rem / grid.tilesX
            let ix = rem % grid.tilesX

            // Clamp tile boundaries to volume
            let x0 = ix * siz.tileSizeX
            let y0 = iy * siz.tileSizeY
            let z0 = iz * siz.tileSizeZ
            let x1 = min(x0 + siz.tileSizeX, siz.width)
            let y1 = min(y0 + siz.tileSizeY, siz.height)
            let z1 = min(z0 + siz.tileSizeZ, siz.depth)

            let tw = x1 - x0
            let th = y1 - y0
            let td = z1 - z0

            guard tw > 0 && th > 0 && td > 0 else {
                warnings.append("Tile \(index): empty region (\(tw)×\(th)×\(td)), skipped")
                continue
            }

            // v10.18 partial-res tile placement. JPEG 2000 spec rule
            // for downsampled coordinates: ⌈ref / 2^K⌉ for both origin
            // and origin+extent. For aligned tile grids this yields
            // adjacent downsampled tile placements without gaps —
            // the unit test in V10_18_TrueSelectiveParityTests
            // exercises corner + interior regions to catch any
            // off-by-one.
            let outX0 = down(x0)
            let outY0 = down(y0)
            let outZ0 = z0
            let outTW = down(x1) - outX0
            let outTH = down(y1) - outY0
            let outTD = td

            // M2: every tile written by the new encoder is a slice-stack
            // payload (J3DS magic). Older tile shapes (raw Int32 dump,
            // legacy JP3DHTJ2K) are no longer produced — they only ever
            // round-tripped via the same broken stub anyway.
            guard JP3DSliceStackCodec.hasMagic(parsedTile.data) else {
                let msg = "Tile \(index): not a JP3D slice-stack payload " +
                    "(missing 'J3DS' magic). " +
                    "This decoder requires JP3D codestreams produced by " +
                    "JP3DEncoder v5.2.0+ — older J2KSwift JP3D output is " +
                    "no longer supported."
                if configuration.tolerateErrors {
                    warnings.append(msg)
                    isPartial = true
                    continue
                }
                throw J2KError.decodingError(msg)
            }

            let perCompBuffers: [[Float]]
            do {
                perCompBuffers = try await JP3DSliceStackCodec().decode(
                    payload: parsedTile.data,
                    expectedTile: JP3DSliceStackCodec.ExpectedTile(
                        width: tw, height: th, depth: td,
                        componentCount: siz.componentCount
                    ),
                    resolutionLevel: K
                )
            } catch {
                if configuration.tolerateErrors {
                    warnings.append("Tile \(index) slice-stack decode failed: \(error)")
                    isPartial = true
                    continue
                }
                throw error
            }

            for comp in 0..<siz.componentCount {
                copyVoxelsToBuffer(
                    from: perCompBuffers[comp], to: &componentBuffers[comp],
                    tileDims: (outTW, outTH, outTD),
                    tileOrigin: (outX0, outY0, outZ0),
                    outWidth: outW, outHeight: outH
                )
            }

            tilesDecoded += 1
            let tileProgress = Double(tileIdx + 1) / Double(codestream.tiles.count)
            reportProgress(.tileReconstruction, stageProgress: tileProgress,
                           tilesDone: tilesDecoded, tilesTotal: tilesExpected)
        }

        reportProgress(.volumeAssembly, stageProgress: 0.0,
                       tilesDone: tilesDecoded, tilesTotal: tilesExpected)

        // Stage 3: Assemble output volume. For partial-res we hand
        // assembleVolumeComponents a SIZ-like descriptor that reflects
        // the downsampled dims so the per-component J2KVolumeComponent
        // metadata matches the buffer geometry.
        let outSIZ = JP3DSIZInfo(
            width: outW, height: outH, depth: outD,
            tileSizeX: siz.tileSizeX, tileSizeY: siz.tileSizeY,
            tileSizeZ: siz.tileSizeZ,
            componentCount: siz.componentCount,
            bitDepth: siz.bitDepth, signed: siz.signed)
        let volumeComponents = assembleVolumeComponents(
            from: componentBuffers, siz: outSIZ
        )

        let volume = J2KVolume(
            width: outW,
            height: outH,
            depth: outD,
            components: volumeComponents
        )

        reportProgress(.volumeAssembly, stageProgress: 1.0,
                       tilesDone: tilesDecoded, tilesTotal: tilesExpected)

        return JP3DDecoderResult(
            volume: volume,
            isPartial: isPartial,
            warnings: warnings,
            tilesDecoded: tilesDecoded,
            tilesTotal: tilesExpected
        )
    }

    /// Decodes only the volume dimensions and metadata without reconstructing voxel data.
    ///
    /// This is useful for determining volume properties before full decoding.
    ///
    /// - Parameter data: The JP3D codestream.
    /// - Returns: A `JP3DSIZInfo` with volume and tile geometry.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream cannot be parsed.
    public func peekMetadata(_ data: Data) throws -> JP3DSIZInfo {
        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)
        return codestream.siz
    }

    // MARK: - Private Helpers

    /// Clamps requested decomposition levels to the maximum meaningful for a dimension.
    private func clampLevels(_ requested: Int, for dimension: Int) -> Int {
        guard dimension > 1, requested > 0 else { return 0 }
        var maxL = 0
        var d = dimension
        while d > 1 { d = (d + 1) / 2; maxL += 1 }
        return min(requested, maxL)
    }

    /// Reports progress to the callback.
    private func reportProgress(
        _ stage: JP3DDecodingStage,
        stageProgress: Double,
        tilesDone: Int,
        tilesTotal: Int
    ) {
        let stageWeights: [JP3DDecodingStage: Double] = [
            .parsing: 0.10,
            .tileReconstruction: 0.75,
            .volumeAssembly: 0.15
        ]
        let stageOffset: [JP3DDecodingStage: Double] = [
            .parsing: 0.0,
            .tileReconstruction: 0.10,
            .volumeAssembly: 0.85
        ]
        let weight = stageWeights[stage] ?? 0.33
        let base = stageOffset[stage] ?? 0.0
        let overall = base + weight * stageProgress

        let update = JP3DDecoderProgress(
            stage: stage,
            stageProgress: stageProgress,
            overallProgress: min(1.0, overall),
            tilesDecoded: tilesDone,
            totalTiles: tilesTotal
        )
        progressCallback?(update)
    }

    private func assembleVolumeComponents(
        from componentBuffers: [[Float]],
        siz: JP3DSIZInfo
    ) -> [J2KVolumeComponent] {
        let voxelCount = siz.width * siz.height * siz.depth
        let bytesPerSample = (siz.bitDepth + 7) / 8
        var volumeComponents: [J2KVolumeComponent] = []

        for comp in 0..<siz.componentCount {
            let maxVal = Float((1 << siz.bitDepth) - 1)

            // v10.25: serialize via a contiguous [UInt8] instead of
            // per-byte mutable `Data` subscript writes — each of those
            // paid a CoW/representation check (~67M for a 33M-voxel
            // 16-bit volume). Byte order (little-endian sample
            // serialization) is unchanged.
            let buffer = componentBuffers[comp]
            let byteCount = voxelCount * bytesPerSample
            let bytes = [UInt8](unsafeUninitializedCapacity: byteCount) { dst, n in
                for i in 0..<voxelCount {
                    let clamped = max(0, min(maxVal, buffer[i]))
                    let intVal = Int(roundf(clamped))
                    for b in 0..<bytesPerSample {
                        dst[i * bytesPerSample + b] = UInt8(truncatingIfNeeded: intVal >> (b * 8))
                    }
                }
                n = byteCount
            }
            let rawData = Data(bytes)

            volumeComponents.append(J2KVolumeComponent(
                index: comp,
                bitDepth: siz.bitDepth,
                signed: siz.signed,
                width: siz.width,
                height: siz.height,
                depth: siz.depth,
                data: rawData
            ))
        }

        return volumeComponents
    }

    private func readLegacyCoefficients(
        from data: Data,
        compOffset: Int,
        expectedBytes: Int,
        into coefficients: inout [Float],
        isLossless: Bool
    ) {
        let available = max(0, min(expectedBytes, data.count - compOffset))
        let actualCount = available / 4

        for i in 0..<actualCount {
            let byteOffset = compOffset + i * 4
            let b0 = Int32(data[byteOffset])
            let b1 = Int32(data[byteOffset + 1])
            let b2 = Int32(data[byteOffset + 2])
            let b3 = Int32(data[byteOffset + 3])
            let raw: Int32 = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
            coefficients[i] = isLossless ? Float(raw) : Float(raw)
        }
    }

    private func inverseWaveletTransform(
        coefficients: [Float],
        cod: JP3DCODInfo,
        tw: Int, th: Int, td: Int,
        lx: Int, ly: Int, lz: Int
    ) async throws -> [Float] {
        let waveletConfig = JP3DTransformConfiguration(
            filter: cod.isLossless ? .reversible53 : .irreversible97,
            mode: .separable,
            boundary: .symmetric,
            levelsX: lx,
            levelsY: ly,
            levelsZ: lz
        )
        var coeffData = J2K3DCoefficients(
            width: tw, height: th, depth: td,
            decompositionLevels: max(lx, max(ly, lz))
        )
        coeffData.data = coefficients
        let decomp = JP3DSubbandDecomposition(
            width: tw, height: th, depth: td,
            levelsX: lx, levelsY: ly, levelsZ: lz,
            coefficients: coeffData,
            originalWidth: tw, originalHeight: th, originalDepth: td
        )
        let wavelet = JP3DWaveletTransform(configuration: waveletConfig)
        return try await wavelet.inverse(decomposition: decomp)
    }

    private func copyVoxelsToBuffer(
        from source: [Float],
        to destination: inout [Float],
        tileDims: (w: Int, h: Int, d: Int),
        tileOrigin: (x: Int, y: Int, z: Int),
        outWidth: Int, outHeight: Int
    ) {
        // v10.25: row-wise bulk copies instead of a per-voxel triple
        // loop with two bounds checks per element. Rows are contiguous
        // in both layouts; the per-row clamp preserves the original
        // per-voxel guard semantics exactly (it only ever truncated at
        // the end of a row when source/destination were undersized).
        let outSlice = outWidth * outHeight
        let voxelCount = destination.count
        let tileSlice = tileDims.w * tileDims.h
        destination.withUnsafeMutableBufferPointer { dst in
            source.withUnsafeBufferPointer { src in
                for z in 0..<tileDims.d {
                    for y in 0..<tileDims.h {
                        let srcRow = z * tileSlice + y * tileDims.w
                        let dstRow = (tileOrigin.z + z) * outSlice
                            + (tileOrigin.y + y) * outWidth + tileOrigin.x
                        let n = min(tileDims.w,
                                    max(0, src.count - srcRow),
                                    max(0, voxelCount - dstRow))
                        guard n > 0, srcRow >= 0, dstRow >= 0 else { continue }
                        dst.baseAddress!.advanced(by: dstRow).update(
                            from: src.baseAddress!.advanced(by: srcRow), count: n)
                    }
                }
            }
        }
    }
}

// MARK: - v10.16.0 — Discoverable partial-decode convenience overloads
//
// The JP3D partial-decode capabilities have existed since v10.18-research
// (partial-resolution via `JP3DDecoderConfiguration.resolutionLevel`,
// true-ROI via `JP3DROIDecoder`, K+ROI composition via v10.13.0) but the
// canonical `JP3DDecoder` exposed only a single `decode(_:)` entry point.
// Consumers had to know to:
//
//   * Construct a `JP3DDecoderConfiguration(resolutionLevel: K)` for
//     partial-res, OR
//   * Switch to `JP3DROIDecoder` for ROI, OR
//   * Combine both for K+ROI.
//
// The overloads below expose these as discoverable shortcuts on the
// canonical `JP3DDecoder` type. They are thin wrappers around the
// existing pipelines — no perf change on existing paths; the speedups
// they surface are those already shipped in v10.18-research / v10.13.0.

extension JP3DDecoder {
    /// v10.16.0 — convenience overload to decode at a reduced resolution level.
    ///
    /// At `level == 0` this is identical to ``decode(_:)``. At `level > 0` the output
    /// volume dimensions per spatial axis are `ceil(D / 2^level)` (Z is independently
    /// capped by the codestream's Z decomposition levels).
    ///
    /// Backed by the true-partial-resolution pipeline (v10.18-research) — the codec
    /// truncates each slice's iDWT chain rather than decoding then downsampling. On
    /// small-mid JP3D fixtures, level-1 decode measures **2.2-3.1× faster** than full
    /// decode (per v10.18-research bench).
    ///
    /// Equivalent to:
    /// ```swift
    /// let cfg = JP3DDecoderConfiguration(resolutionLevel: level, ...)
    /// try await JP3DDecoder(configuration: cfg).decode(data)
    /// ```
    /// but discoverable from the canonical JP3DDecoder API surface.
    ///
    /// - Parameters:
    ///   - data: The JP3D codestream produced by `JP3DEncoder`.
    ///   - level: The number of decomposition levels to drop. `0` ⇒ full resolution.
    ///            Negative values are clamped to `0`; values above the codestream's
    ///            decomposition depth are clamped by the underlying pipeline.
    /// - Returns: A `JP3DDecoderResult` whose `volume` carries the reduced-resolution
    ///            sub-volume.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is malformed.
    public func decode(_ data: Data, resolutionLevel level: Int) async throws -> JP3DDecoderResult {
        let clampedLevel = max(0, level)
        // Fast path: when the actor's own configuration already matches the
        // requested level, dispatch straight to the existing decode pipeline.
        if clampedLevel == self.configuration.resolutionLevel {
            return try await self.decode(data)
        }
        // Otherwise spin up a transient decoder with a tweaked configuration.
        // The bulk of the per-call cost is the codec itself; the actor +
        // configuration storage is essentially free.
        let cfg = JP3DDecoderConfiguration(
            maxQualityLayers: self.configuration.maxQualityLayers,
            resolutionLevel: clampedLevel,
            tolerateErrors: self.configuration.tolerateErrors)
        return try await JP3DDecoder(configuration: cfg).decode(data)
    }

    /// v10.16.0 — convenience overload to decode a spatial region of interest.
    ///
    /// Backed by the v10.13.0 tile-granular ROI pipeline: tiles outside the requested
    /// region are skipped entirely (no entropy / iDWT / colour-transform cost).
    /// Measured **3.4-4.1× faster** than full decode for ~1/4-extent regions on small
    /// JP3D fixtures (per v10.18-research bench).
    ///
    /// Equivalent to `JP3DROIDecoder(configuration: self.configuration).decode(data, region: region)`,
    /// but discoverable from the canonical JP3DDecoder type. The actor's own
    /// configuration is forwarded so e.g. `tolerateErrors` and `maxQualityLayers`
    /// propagate.
    ///
    /// - Parameters:
    ///   - data: The JP3D codestream produced by `JP3DEncoder`.
    ///   - region: The spatial region (in full-image voxel coordinates) to decode.
    /// - Returns: A `JP3DROIDecoderResult` carrying the sub-volume plus
    ///            ROI-specific metadata (`decodedRegion`, `isFullVolume`,
    ///            `tilesSkipped`, `tilesDecoded`).
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is malformed.
    public func decode(_ data: Data, region: JP3DRegion) async throws -> JP3DROIDecoderResult {
        let roi = JP3DROIDecoder(configuration: self.configuration)
        return try await roi.decode(data, region: region)
    }

    /// v10.16.0 — convenience overload combining resolution reduction and ROI.
    ///
    /// Returns the in-region sub-volume at `2^level`-down dimensions per spatial axis.
    /// The region coordinates are in full-image voxel space (matches the
    /// `J2KDecoder.decodeRegion(.direct)` convention from v10.6/v10.8). The bridge
    /// maps them to the reduced grid for crop. Closes the v10.13.0 {K, ROI}
    /// composition matrix behind a single discoverable API.
    ///
    /// Equivalent to:
    /// ```swift
    /// let cfg = JP3DDecoderConfiguration(resolutionLevel: level, ...)
    /// try await JP3DROIDecoder(configuration: cfg).decode(data, region: region)
    /// ```
    ///
    /// - Parameters:
    ///   - data: The JP3D codestream produced by `JP3DEncoder`.
    ///   - region: The spatial region (in full-image voxel coordinates).
    ///   - level: The number of decomposition levels to drop. `0` ⇒ full resolution
    ///            within the region (equivalent to ``decode(_:region:)``).
    /// - Returns: A `JP3DROIDecoderResult`.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is malformed.
    public func decode(
        _ data: Data,
        region: JP3DRegion,
        resolutionLevel level: Int
    ) async throws -> JP3DROIDecoderResult {
        let clampedLevel = max(0, level)
        if clampedLevel == self.configuration.resolutionLevel {
            return try await self.decode(data, region: region)
        }
        let cfg = JP3DDecoderConfiguration(
            maxQualityLayers: self.configuration.maxQualityLayers,
            resolutionLevel: clampedLevel,
            tolerateErrors: self.configuration.tolerateErrors)
        let roi = JP3DROIDecoder(configuration: cfg)
        return try await roi.decode(data, region: region)
    }
}
