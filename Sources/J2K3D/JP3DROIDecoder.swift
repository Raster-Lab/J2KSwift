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
        let cod = codestream.cod

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

        // Allocate output ROI buffers
        let roiVoxels = roiW * roiH * roiD
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

            let lx = clampLevels(cod.levelsX, for: tw)
            let ly = clampLevels(cod.levelsY, for: th)
            let lz = clampLevels(cod.levelsZ, for: td)
            let voxelsPerComp = tw * th * td
            let expectedBytesPerComp = voxelsPerComp * 4

            for comp in 0..<siz.componentCount {
                let compOffset = comp * expectedBytesPerComp
                let available = max(0, min(expectedBytesPerComp, parsedTile.data.count - compOffset))
                let actualCount = available / 4

                var coefficients = [Float](repeating: 0, count: voxelsPerComp)
                for i in 0..<actualCount {
                    let byteOffset = compOffset + i * 4
                    let b0 = Int32(parsedTile.data[byteOffset])
                    let b1 = Int32(parsedTile.data[byteOffset + 1])
                    let b2 = Int32(parsedTile.data[byteOffset + 2])
                    let b3 = Int32(parsedTile.data[byteOffset + 3])
                    let raw: Int32 = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
                    coefficients[i] = Float(raw)
                }

                // Inverse wavelet
                let floatCoeffs: [Float]
                do {
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
                    floatCoeffs = try await wavelet.inverse(decomposition: decomp)
                } catch {
                    if configuration.tolerateErrors {
                        warnings.append("Tile \(idx) comp \(comp): \(error)")
                        continue
                    }
                    throw error
                }

                // Copy the intersecting sub-region into ROI buffer
                let intX0 = max(x0, clampedX.lowerBound)
                let intY0 = max(y0, clampedY.lowerBound)
                let intZ0 = max(z0, clampedZ.lowerBound)
                let intX1 = min(x0 + tw, clampedX.upperBound)
                let intY1 = min(y0 + th, clampedY.upperBound)
                let intZ1 = min(z0 + td, clampedZ.upperBound)

                for z in intZ0..<intZ1 {
                    for y in intY0..<intY1 {
                        for x in intX0..<intX1 {
                            let srcX = x - x0
                            let srcY = y - y0
                            let srcZ = z - z0
                            let srcIdx = srcZ * tw * th + srcY * tw + srcX
                            let dstX = x - clampedX.lowerBound
                            let dstY = y - clampedY.lowerBound
                            let dstZ = z - clampedZ.lowerBound
                            let dstIdx = dstZ * roiW * roiH + dstY * roiW + dstX
                            if srcIdx < floatCoeffs.count && dstIdx < roiVoxels {
                                roiBuffers[comp][dstIdx] = floatCoeffs[srcIdx]
                            }
                        }
                    }
                }
            }

            tilesDecoded += 1
        }

        // Assemble ROI sub-volume
        let bytesPerSample = (siz.bitDepth + 7) / 8
        var volumeComponents: [J2KVolumeComponent] = []
        let maxVal = Float((1 << siz.bitDepth) - 1)

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

        let volume = J2KVolume(width: roiW, height: roiH, depth: roiD, components: volumeComponents)

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
}
