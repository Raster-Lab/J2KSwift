//
// JP3DROIDecoder.swift
// J2KSwift
//
/// # JP3DROIDecoder
///
/// Region-of-Interest (ROI) decoding for JP3D volumetric JPEG 2000.
///
/// Provides efficient spatial sub-region decoding by skipping tiles that
/// do not intersect the requested region, significantly reducing I/O and
/// computation for large volumes when only a spatial subset is needed.
///
/// ## Topics
///
/// ### ROI Types
/// - ``JP3DROIDecoder``
/// - ``JP3DROIDecoderResult``

import Foundation
import J2KCore

/// Result of a JP3D ROI decode operation.
public struct JP3DROIDecoderResult: Sendable {
    /// The decoded sub-volume for the requested (clamped) region.
    public let volume: J2KVolume

    /// The actual decoded region (may be smaller than requested if clamped to volume bounds).
    public let decodedRegion: JP3DRegion

    /// Whether the decoded region equals the entire volume (ROI == full volume).
    public let isFullVolume: Bool

    /// Tiles skipped because they did not intersect the ROI.
    public let tilesSkipped: Int

    /// Tiles decoded.
    public let tilesDecoded: Int

    /// Any warnings encountered during decoding.
    public let warnings: [String]
}

/// Decodes a specific 3D region from a JP3D codestream.
///
/// `JP3DROIDecoder` only processes tiles that intersect the requested region,
/// providing significant performance gains over full-volume decoding when only
/// a spatial subset is required.
///
/// ## Usage
///
/// ```swift
/// let roi = JP3DRegion(x: 0..<64, y: 0..<64, z: 0..<32)
/// let decoder = JP3DROIDecoder()
/// let result = try await decoder.decode(data, region: roi)
/// ```
///
/// ## Edge Cases
///
/// - If the requested region exceeds the volume bounds, it is clamped to the
///   intersection with the volume.
/// - If the clamped region has zero area, an empty volume with valid metadata is returned.
/// - If the ROI equals the entire volume, the decoder follows the full-volume path.
public actor JP3DROIDecoder {
    // MARK: - State

    private let configuration: JP3DDecoderConfiguration
    private var progressCallback: (@Sendable (JP3DDecoderProgress) -> Void)?

    // MARK: - Init

    /// Creates an ROI decoder with the given configuration.
    ///
    /// - Parameter configuration: Decoder configuration. Defaults to `.default`.
    public init(configuration: JP3DDecoderConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - Pre-warm

    /// Warm the shared Metal session before the first JP3D ROI decode
    /// in a process.
    ///
    /// Equivalent to ``JP3DDecoder/preWarm(includeWarmupDispatch:)``
    /// — both ROI and full-volume JP3D decoders share the same
    /// process-wide Metal session via the per-slice 2D `J2KDecoder`
    /// delegation. Provided here as a discoverable convenience so
    /// callers using `JP3DROIDecoder` directly don't have to import
    /// `J2KCodec` separately.
    ///
    /// Cold-vs-warm A/B savings are the same as `JP3DDecoder.preWarm()`
    /// — see that method's docs.
    ///
    /// - Parameter includeWarmupDispatch: when `true`, runs a tiny
    ///   synthetic 2D decode for an extra ~10 ms savings on the
    ///   first user JP3D ROI decode. Default `false`.
    public static func preWarm(includeWarmupDispatch: Bool = false) async {
        await JP3DDecoder.preWarm(includeWarmupDispatch: includeWarmupDispatch)
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

    /// Decodes a specific 3D region from a JP3D codestream.
    ///
    /// - Parameters:
    ///   - data: The JP3D codestream produced by `JP3DEncoder`.
    ///   - region: The 3D region to decode.
    /// - Returns: The decoded sub-volume and metadata about the ROI decode.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is malformed.
    public func decode(_ data: Data, region requestedRegion: JP3DRegion) async throws -> JP3DROIDecoderResult {
        // Parse metadata first
        let parser = JP3DCodestreamParser()
        let codestream = try parser.parse(data)
        let siz = codestream.siz

        // v10.22-research — resolutionLevel + sub-region composition
        // is now supported via the batched bridge. JP3DSliceStackCodec
        // (Phase 5 wiring) routes K>0 + ROI through the v10.21
        // bridge SPI's K+ROI-aware orchestrator, which truncates the
        // iDWT chain AND crops the per-slice output to the
        // downsampled-coord ROI. The v10.18 fail-loud throw is gone;
        // the per-tile coord translation runs below.

        // Clamp the requested region to valid volume bounds
        let clampedXLower = max(0, requestedRegion.x.lowerBound)
        let clampedXUpper = min(siz.width, requestedRegion.x.upperBound)
        let clampedYLower = max(0, requestedRegion.y.lowerBound)
        let clampedYUpper = min(siz.height, requestedRegion.y.upperBound)
        let clampedZLower = max(0, requestedRegion.z.lowerBound)
        let clampedZUpper = min(siz.depth, requestedRegion.z.upperBound)

        // Handle empty intersection
        if clampedXLower >= clampedXUpper || clampedYLower >= clampedYUpper || clampedZLower >= clampedZUpper {
            let emptyVolume = J2KVolume(
                width: siz.width, height: siz.height, depth: siz.depth,
                componentCount: siz.componentCount, bitDepth: siz.bitDepth
            )
            let emptyRegion = JP3DRegion(x: 0..<0, y: 0..<0, z: 0..<0)
            return JP3DROIDecoderResult(
                volume: emptyVolume,
                decodedRegion: emptyRegion,
                isFullVolume: false,
                tilesSkipped: codestream.tiles.count,
                tilesDecoded: 0,
                warnings: ["Requested region does not intersect the volume"]
            )
        }

        let clampedX = clampedXLower..<clampedXUpper
        let clampedY = clampedYLower..<clampedYUpper
        let clampedZ = clampedZLower..<clampedZUpper

        let roiRegion = JP3DRegion(x: clampedX, y: clampedY, z: clampedZ)
        let roiW = clampedX.count
        let roiH = clampedY.count
        let roiD = clampedZ.count

        // Check if ROI == entire volume
        let isFullVol = (roiW == siz.width && roiH == siz.height && roiD == siz.depth)
        if isFullVol {
            // Delegate to full decoder
            let decoder = JP3DDecoder(configuration: configuration)
            let result = try await decoder.decode(data)
            return JP3DROIDecoderResult(
                volume: result.volume,
                decodedRegion: roiRegion,
                isFullVolume: true,
                tilesSkipped: 0,
                tilesDecoded: result.tilesDecoded,
                warnings: result.warnings
            )
        }

        // Determine which tiles intersect the ROI
        let tiling = JP3DTilingConfiguration(
            tileSizeX: siz.tileSizeX, tileSizeY: siz.tileSizeY, tileSizeZ: siz.tileSizeZ
        )
        let intersectingTiles = tiling.tilesIntersecting(
            region: roiRegion,
            volumeWidth: siz.width,
            volumeHeight: siz.height,
            volumeDepth: siz.depth
        )

        // Build a quick lookup: tile linear index → JP3DTile
        let grid = codestream.tileGrid
        var tilesByIndex: [Int: JP3DTile] = [:]
        for tile in intersectingTiles {
            let linearIndex = tile.indexZ * grid.tilesX * grid.tilesY
                + tile.indexY * grid.tilesX + tile.indexX
            tilesByIndex[linearIndex] = tile
        }

        // v10.22 — when configuration.resolutionLevel > 0 the output
        // sub-volume's XY dims are downsampled by 2^K relative to the
        // user-passed ROI (Z is per-slice, not affected). The output
        // buffer sizing + per-tile composite below switch to
        // downsampled coords accordingly. Z stays full because JP3D's
        // K is a 2D-only halving (Z residual chain is per-slice).
        let K = configuration.resolutionLevel
        let f = K > 0 ? (1 << K) : 1
        let roiW_out = K > 0 ? (roiW + f - 1) / f : roiW
        let roiH_out = K > 0 ? (roiH + f - 1) / f : roiH
        let roiD_out = roiD

        // Allocate output ROI buffers
        let roiVoxels = roiW_out * roiH_out * roiD_out
        var roiBuffers = [[Float]](
            repeating: [Float](repeating: 0, count: roiVoxels),
            count: siz.componentCount
        )

        var warnings: [String] = []
        var tilesDecoded = 0
        var tilesSkipped = 0

        for parsedTile in codestream.tiles {
            let idx = parsedTile.tileIndex
            guard let tileInfo = tilesByIndex[idx] else {
                tilesSkipped += 1
                continue
            }

            let x0 = tileInfo.region.x.lowerBound
            let y0 = tileInfo.region.y.lowerBound
            let z0 = tileInfo.region.z.lowerBound
            let tw = tileInfo.width
            let th = tileInfo.height
            let td = tileInfo.depth

            // v10.18 Phase 3 — compute the in-tile XY sub-region in
            // tile-local coords. JP3DSliceStackCodec routes the per-
            // slice 2D decode through `decoder.decodeRegion(.direct)`
            // (v10.6.0 footprint-skip: code-blocks whose synthesis
            // cone-of-influence misses the region skip entropy decode
            // entirely) and returns Float buffers sized exactly for
            // the region rather than the whole tile. The intersection-
            // crop loop below collapses to a region-local copy with
            // Z-axis filtering.
            //
            // Z stays per-slice because slice-stack residual coding
            // chains through every slice — we still decode all slices
            // in the tile to keep Z-delta correct, then only copy the
            // in-Z-range ones into the ROI buffer.
            let inTileXLower = max(0, clampedX.lowerBound - x0)
            let inTileXUpper = min(tw, clampedX.upperBound - x0)
            let inTileYLower = max(0, clampedY.lowerBound - y0)
            let inTileYUpper = min(th, clampedY.upperBound - y0)
            let inTileZLower = max(0, clampedZ.lowerBound - z0)
            let inTileZUpper = min(td, clampedZ.upperBound - z0)

            // Tile is in tilesByIndex but its intersection is empty:
            // shouldn't happen (tilesIntersecting filters this), but
            // defensively skip.
            guard inTileXLower < inTileXUpper,
                  inTileYLower < inTileYUpper,
                  inTileZLower < inTileZUpper else {
                tilesSkipped += 1
                continue
            }

            guard JP3DSliceStackCodec.hasMagic(parsedTile.data) else {
                if configuration.tolerateErrors {
                    warnings.append("Tile \(idx): not a JP3D slice-stack payload (missing 'J3DS' magic)")
                    continue
                }
                throw J2KError.decodingError(
                    "Tile \(idx): not a JP3D slice-stack payload (missing 'J3DS' magic)"
                )
            }

            // v10.22 — JP3DSliceStackCodec now treats `regionOfInterest`
            // in FULL tile-local coords (post-K mapping happens inside
            // the bridge SPI). No translation needed here.
            let inTileXRange = inTileXLower..<inTileXUpper
            let inTileYRange = inTileYLower..<inTileYUpper
            // regionW_full / regionH_full track the FULL-coords in-tile
            // region (what we pass to JP3DSliceStackCodec); regionW /
            // regionH track the DOWNSAMPLED per-slice buffer shape
            // (what the slice-stack actually returns when K>0).
            let regionW_full = inTileXRange.count
            let regionH_full = inTileYRange.count
            let regionW = K > 0 ? (regionW_full + f - 1) / f : regionW_full
            let regionH = K > 0 ? (regionH_full + f - 1) / f : regionH_full

            // Phase 3 fast path only fires when the in-tile region is
            // strictly smaller than the tile (full coords). When K>0
            // the slice-stack will still downsample internally.
            let useRegionPath = (regionW_full < tw || regionH_full < th)

            // v10.18-research Phase 5 — wire JP3DDecoderConfiguration.
            // resolutionLevel through to the slice-stack codec. When
            // resolutionLevel > 0 AND a region is being decoded, the
            // slice-stack codec throws the "combination is the Phase 5
            // wiring future-work" error LOUDLY rather than silently
            // ignoring resolutionLevel (which is what JP3DROIDecoder
            // did pre-Phase-3).
            //
            // v10.18-research Phase 6 — Z-narrow ROI skip. Pass the
            // per-tile Z range to the slice-stack codec so that for
            // tiles where the ROI Z-range starts deep into the tile,
            // the codec scans forward from the latest non-residual
            // slice ≤ zLower (rather than decoding slice 0..zLower
            // verbatim purely to keep the Z-delta chain alive).
            let K = max(0, configuration.resolutionLevel)
            let inTileZRange = inTileZLower..<inTileZUpper
            // The codec returns buffers sized for the tile-local
            // Z range, not the full tile depth.
            let returnedSliceCount = inTileZRange.count
            let perCompBuffers: [[Float]]
            do {
                if useRegionPath {
                    perCompBuffers = try await JP3DSliceStackCodec().decode(
                        payload: parsedTile.data,
                        expectedTile: JP3DSliceStackCodec.ExpectedTile(
                            width: tw, height: th, depth: td,
                            componentCount: siz.componentCount
                        ),
                        resolutionLevel: K,
                        regionOfInterest: (inTileXRange, inTileYRange),
                        zRange: inTileZRange
                    )
                } else {
                    perCompBuffers = try await JP3DSliceStackCodec().decode(
                        payload: parsedTile.data,
                        expectedTile: JP3DSliceStackCodec.ExpectedTile(
                            width: tw, height: th, depth: td,
                            componentCount: siz.componentCount
                        ),
                        resolutionLevel: K,
                        zRange: inTileZRange
                    )
                }
            } catch {
                if configuration.tolerateErrors {
                    warnings.append("Tile \(idx): slice-stack decode failed – \(error)")
                    continue
                }
                throw error
            }

            // Place into the output ROI buffer. v10.18 Phase 6 — the
            // codec now returns buffers sized `returnedSliceCount` deep
            // (= inTileZRange.count) rather than `td` deep. The source
            // Z index `srcZ` is now offset from `inTileZLower` instead
            // of `z0` (volume coords) → tile-local `srcZ = z - z0 -
            // inTileZLower` for any volume Z in `[z0 + inTileZLower,
            // z0 + inTileZUpper)`.
            //
            // When useRegionPath: perCompBuffers is
            //   regionW * regionH * returnedSliceCount (per component).
            // When !useRegionPath: perCompBuffers is
            //   tw * th * returnedSliceCount (per component).
            for comp in 0..<siz.componentCount {
                let floatCoeffs = perCompBuffers[comp]
                let intZ0 = max(z0 + inTileZLower, clampedZ.lowerBound)
                let intZ1 = min(z0 + inTileZUpper, clampedZ.upperBound)
                _ = returnedSliceCount  // bounded by the loop below

                if useRegionPath {
                    // v10.22 — composite at DOWNSAMPLED XY coords when
                    // K>0. The slice-stack returns the per-slice buffer
                    // sized for the downsampled-in-tile region, so
                    // src strides and dst offsets are both at the
                    // reduced scale. Z stays full (per-slice).
                    let srcSliceVoxels = regionW * regionH
                    // In-tile lower bound in downsampled coords; the
                    // dst-base accounts for the clampedX/Y lower bound
                    // also being downsampled (since roiBuffers is
                    // downsampled-sized).
                    let inTileXLowerDown = K > 0
                        ? inTileXRange.lowerBound / f
                        : inTileXRange.lowerBound
                    let inTileYLowerDown = K > 0
                        ? inTileYRange.lowerBound / f
                        : inTileYRange.lowerBound
                    let x0Down = K > 0 ? x0 / f : x0
                    let y0Down = K > 0 ? y0 / f : y0
                    let clampedXLowerDown = K > 0
                        ? clampedX.lowerBound / f
                        : clampedX.lowerBound
                    let clampedYLowerDown = K > 0
                        ? clampedY.lowerBound / f
                        : clampedY.lowerBound
                    for z in intZ0..<intZ1 {
                        let srcZ = (z - z0) - inTileZLower
                        let dstZ = z - clampedZ.lowerBound
                        let srcRowOffset = srcZ * srcSliceVoxels
                        for ry in 0..<regionH {
                            let dstY = (y0Down + inTileYLowerDown + ry) - clampedYLowerDown
                            let srcRow = srcRowOffset + ry * regionW
                            let dstRow = dstZ * roiW_out * roiH_out + dstY * roiW_out
                            for rx in 0..<regionW {
                                let dstX = (x0Down + inTileXLowerDown + rx) - clampedXLowerDown
                                let dstIdx = dstRow + dstX
                                let srcIdx = srcRow + rx
                                if srcIdx < floatCoeffs.count && dstIdx < roiVoxels {
                                    roiBuffers[comp][dstIdx] = floatCoeffs[srcIdx]
                                }
                            }
                        }
                    }
                } else {
                    // Whole-tile XY decode + intersection-crop (tile
                    // is entirely inside ROI in XY). Z range is the
                    // narrowed one. v10.22 — also K-aware: the slice-
                    // stack returned a downsampled-tile buffer when K>0,
                    // so iterate at downsampled stride.
                    let twDown = K > 0 ? (tw + f - 1) / f : tw
                    let thDown = K > 0 ? (th + f - 1) / f : th
                    let intX0 = max(x0, clampedX.lowerBound)
                    let intY0 = max(y0, clampedY.lowerBound)
                    let intX1 = min(x0 + tw, clampedX.upperBound)
                    let intY1 = min(y0 + th, clampedY.upperBound)
                    let intX0Down = K > 0 ? intX0 / f : intX0
                    let intY0Down = K > 0 ? intY0 / f : intY0
                    let intX1Down = K > 0 ? (intX1 + f - 1) / f : intX1
                    let intY1Down = K > 0 ? (intY1 + f - 1) / f : intY1
                    let x0Down = K > 0 ? x0 / f : x0
                    let y0Down = K > 0 ? y0 / f : y0
                    let clampedXLowerDown = K > 0 ? clampedX.lowerBound / f : clampedX.lowerBound
                    let clampedYLowerDown = K > 0 ? clampedY.lowerBound / f : clampedY.lowerBound
                    for z in intZ0..<intZ1 {
                        let srcZ = (z - z0) - inTileZLower
                        for y in intY0Down..<intY1Down {
                            for x in intX0Down..<intX1Down {
                                let srcX = x - x0Down
                                let srcY = y - y0Down
                                let srcIdx = srcZ * twDown * thDown + srcY * twDown + srcX
                                let dstX = x - clampedXLowerDown
                                let dstY = y - clampedYLowerDown
                                let dstZ = z - clampedZ.lowerBound
                                let dstIdx = dstZ * roiW_out * roiH_out + dstY * roiW_out + dstX
                                if srcIdx < floatCoeffs.count && dstIdx < roiVoxels {
                                    roiBuffers[comp][dstIdx] = floatCoeffs[srcIdx]
                                }
                            }
                        }
                    }
                }
            }

            tilesDecoded += 1
        }

        // v10.22 — output volume uses downsampled XY dims when K>0.
        let volumeComponents = assembleROIComponents(
            from: roiBuffers, siz: siz,
            roiW: roiW_out, roiH: roiH_out, roiD: roiD_out
        )

        let volume = J2KVolume(width: roiW_out, height: roiH_out, depth: roiD_out, components: volumeComponents)

        return JP3DROIDecoderResult(
            volume: volume,
            decodedRegion: roiRegion,
            isFullVolume: false,
            tilesSkipped: tilesSkipped,
            tilesDecoded: tilesDecoded,
            warnings: warnings
        )
    }

    // MARK: - Private Helpers

    private func clampLevels(_ requested: Int, for dimension: Int) -> Int {
        guard dimension > 1, requested > 0 else { return 0 }
        var maxL = 0
        var d = dimension
        while d > 1 { d = (d + 1) / 2; maxL += 1 }
        return min(requested, maxL)
    }

    private func readLegacyCoefficients(
        from data: Data,
        compOffset: Int,
        expectedBytes: Int,
        into coefficients: inout [Float]
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
            coefficients[i] = Float(raw)
        }
    }

    private func assembleROIComponents(
        from roiBuffers: [[Float]],
        siz: JP3DSIZInfo,
        roiW: Int,
        roiH: Int,
        roiD: Int
    ) -> [J2KVolumeComponent] {
        let roiVoxels = roiW * roiH * roiD
        let bytesPerSample = (siz.bitDepth + 7) / 8
        let maxVal = Float((1 << siz.bitDepth) - 1)
        var volumeComponents: [J2KVolumeComponent] = []

        for comp in 0..<siz.componentCount {
            var rawData = Data(count: roiVoxels * bytesPerSample)
            for i in 0..<roiVoxels {
                let clamped = max(0, min(maxVal, roiBuffers[comp][i]))
                let intVal = Int(roundf(clamped))
                for b in 0..<bytesPerSample {
                    rawData[i * bytesPerSample + b] = UInt8(truncatingIfNeeded: intVal >> (b * 8))
                }
            }
            volumeComponents.append(J2KVolumeComponent(
                index: comp,
                bitDepth: siz.bitDepth,
                signed: siz.signed,
                width: roiW,
                height: roiH,
                depth: roiD,
                data: rawData
            ))
        }

        return volumeComponents
    }

    private func inverseWaveletTransform(
        coefficients: [Float],
        cod: JP3DCODInfo,
        tw: Int, th: Int, td: Int,
        lx: Int, ly: Int, lz: Int
    ) async throws -> [Float] {
        let waveletConfig = JP3DTransformConfiguration(
            filter: cod.isLossless ? .reversible53 : .irreversible97,
            mode: .separable, boundary: .symmetric,
            levelsX: lx, levelsY: ly, levelsZ: lz
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
}
