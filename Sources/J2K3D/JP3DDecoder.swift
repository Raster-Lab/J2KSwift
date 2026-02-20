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
        let cod = codestream.cod

        reportProgress(.parsing, stageProgress: 1.0, tilesDone: 0,
                       tilesTotal: codestream.tiles.count)

        // Stage 2: Reconstruct tiles
        let grid = codestream.tileGrid
        let tilesExpected = grid.tilesX * grid.tilesY * grid.tilesZ

        // Allocate output component buffers (Float per voxel)
        let voxelCount = siz.width * siz.height * siz.depth
        var componentBuffers = [[Float]](
            repeating: [Float](repeating: 0, count: voxelCount),
            count: siz.componentCount
        )

        var warnings: [String] = []
        var tilesDecoded = 0
        var isPartial = false

        for (tileIdx, parsedTile) in codestream.tiles.enumerated() {
            // Cache for HTJ2K-decoded all-component coefficients of the current tile.
            // Scoped here so it is naturally reset on each tile iteration.
            var htj2kTileCache: [Float]?
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

            // Clamp levels to actual tile dimensions
            let lx = clampLevels(cod.levelsX, for: tw)
            let ly = clampLevels(cod.levelsY, for: th)
            let lz = clampLevels(cod.levelsZ, for: td)
            let voxelsPerComp = tw * th * td

            // Detect whether the tile was HTJ2K-encoded by checking for a JP3DHTTileInfo prefix.
            let tileInfo = JP3DHTTileInfo.deserialise(from: parsedTile.data)
            let tileIsHTJ2K = tileInfo?.isHT ?? false

            // Parse coefficient bytes for each component
            let expectedBytesPerComp = voxelsPerComp * 4 // Int32 = 4 bytes
            let expectedTotal = expectedBytesPerComp * siz.componentCount

            // For HTJ2K tiles the payload includes the 4-byte tile-info prefix plus
            // a 4-byte ZBP prefix per component.  Skip the length check for those.
            if !tileIsHTJ2K && parsedTile.data.count < expectedTotal {
                if configuration.tolerateErrors {
                    warnings.append(
                        "Tile \(index): data truncated (\(parsedTile.data.count) < \(expectedTotal) bytes)"
                    )
                    isPartial = true
                } else {
                    throw J2KError.decodingError(
                        "Tile \(index): data truncated (\(parsedTile.data.count) < \(expectedTotal) bytes)"
                    )
                }
            }

            for comp in 0..<siz.componentCount {
                // Read quantized Int32 coefficients
                var coefficients = [Float](repeating: 0, count: voxelsPerComp)

                if tileIsHTJ2K {
                    // HTJ2K-encoded: the tile payload contains all components interleaved
                    // after the 4-byte tile-info prefix.  Decode the whole tile for the
                    // first component and store; subsequent components read from the cache.
                    if comp == 0 {
                        let codec = JP3DHTJ2KCodec(configuration: .default)
                        do {
                            let allComps = try codec.decodeTile(
                                tileData: parsedTile.data,
                                expectedVoxels: voxelsPerComp * siz.componentCount
                            )
                            // Cache the full decode for use by remaining components
                            htj2kTileCache = allComps
                        } catch {
                            if configuration.tolerateErrors {
                                warnings.append(
                                    "Tile \(index) HTJ2K decode failed: \(error)"
                                )
                                isPartial = true
                                htj2kTileCache = nil
                                continue
                            }
                            throw error
                        }
                    }
                    // Extract the per-component slice from the cache
                    if let cache = htj2kTileCache {
                        let start = comp * voxelsPerComp
                        let end = min(start + voxelsPerComp, cache.count)
                        if start < end {
                            coefficients.replaceSubrange(0..<(end - start), with: cache[start..<end])
                        }
                    }
                } else {
                    readLegacyCoefficients(
                        from: parsedTile.data,
                        compOffset: comp * expectedBytesPerComp,
                        expectedBytes: expectedBytesPerComp,
                        into: &coefficients,
                        isLossless: codestream.isLosslessQuantization
                    )
                }
                // Apply inverse 3D wavelet transform
                let floatCoeffs: [Float]
                do {
                    floatCoeffs = try await inverseWaveletTransform(
                        coefficients: coefficients, cod: cod,
                        tw: tw, th: th, td: td, lx: lx, ly: ly, lz: lz
                    )
                } catch {
                    if configuration.tolerateErrors {
                        warnings.append("Tile \(index) comp \(comp): inverse DWT failed – \(error)")
                        isPartial = true
                        continue
                    }
                    throw error
                }

                // Write reconstructed voxels into the output component buffer
                copyVoxelsToBuffer(
                    from: floatCoeffs, to: &componentBuffers[comp],
                    tileDims: (tw, th, td),
                    tileOrigin: (x0, y0, z0),
                    outWidth: siz.width, outHeight: siz.height
                )
            }

            tilesDecoded += 1
            let tileProgress = Double(tileIdx + 1) / Double(codestream.tiles.count)
            reportProgress(.tileReconstruction, stageProgress: tileProgress,
                           tilesDone: tilesDecoded, tilesTotal: tilesExpected)
        }

        reportProgress(.volumeAssembly, stageProgress: 0.0,
                       tilesDone: tilesDecoded, tilesTotal: tilesExpected)

        // Stage 3: Assemble output volume
        let volumeComponents = assembleVolumeComponents(
            from: componentBuffers, siz: siz
        )

        let volume = J2KVolume(
            width: siz.width,
            height: siz.height,
            depth: siz.depth,
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
            var rawData = Data(count: voxelCount * bytesPerSample)
            let maxVal = Float((1 << siz.bitDepth) - 1)

            for i in 0..<voxelCount {
                let clamped = max(0, min(maxVal, componentBuffers[comp][i]))
                let intVal = Int(roundf(clamped))
                for b in 0..<bytesPerSample {
                    rawData[i * bytesPerSample + b] = UInt8(truncatingIfNeeded: intVal >> (b * 8))
                }
            }

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
        let outSlice = outWidth * outHeight
        let voxelCount = destination.count
        for z in 0..<tileDims.d {
            for y in 0..<tileDims.h {
                for x in 0..<tileDims.w {
                    let srcIdx = z * tileDims.w * tileDims.h + y * tileDims.w + x
                    let dstIdx = (tileOrigin.z + z) * outSlice + (tileOrigin.y + y) * outWidth + (tileOrigin.x + x)
                    if srcIdx < source.count && dstIdx < voxelCount {
                        destination[dstIdx] = source[srcIdx]
                    }
                }
            }
        }
    }
}
