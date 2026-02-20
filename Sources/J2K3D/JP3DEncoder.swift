/// # JP3DEncoder
///
/// Core JP3D volumetric JPEG 2000 encoder.
///
/// Implements the complete JP3D encoding pipeline including 3D tiling,
/// wavelet transform, quantization, and codestream generation conforming
/// to ISO/IEC 15444-10.
///
/// ## Topics
///
/// ### Encoder Types
/// - ``JP3DEncoder``
/// - ``JP3DEncoderConfiguration``
/// - ``JP3DEncoderResult``

import Foundation
import J2KCore

/// Configuration for the JP3D encoder.
///
/// Specifies all parameters for volumetric encoding including compression
/// mode, tiling, wavelet transform, progression order, and quality layers.
///
/// ## Presets
///
/// ```swift
/// let lossless = JP3DEncoderConfiguration.lossless
/// let lossy = JP3DEncoderConfiguration.lossy()
/// ```
public struct JP3DEncoderConfiguration: Sendable, Equatable {
    /// Compression mode.
    public let compressionMode: JP3DCompressionMode

    /// Tiling configuration.
    public let tiling: JP3DTilingConfiguration

    /// Progression order.
    public let progressionOrder: JP3DProgressionOrder

    /// Number of quality layers.
    public let qualityLayers: Int

    /// Number of decomposition levels along X.
    public let levelsX: Int

    /// Number of decomposition levels along Y.
    public let levelsY: Int

    /// Number of decomposition levels along Z.
    public let levelsZ: Int

    /// Whether to enable parallel tile encoding.
    public let parallelEncoding: Bool

    /// Creates an encoder configuration.
    ///
    /// - Parameters:
    ///   - compressionMode: Compression mode (default: `.lossless`).
    ///   - tiling: Tiling configuration (default: `.default`).
    ///   - progressionOrder: Progression order (default: `.lrcps`).
    ///   - qualityLayers: Number of quality layers (default: 1).
    ///   - levelsX: Decomposition levels along X (default: 3).
    ///   - levelsY: Decomposition levels along Y (default: 3).
    ///   - levelsZ: Decomposition levels along Z (default: 1).
    ///   - parallelEncoding: Enable parallel tile encoding (default: true).
    public init(
        compressionMode: JP3DCompressionMode = .lossless,
        tiling: JP3DTilingConfiguration = .default,
        progressionOrder: JP3DProgressionOrder = .lrcps,
        qualityLayers: Int = 1,
        levelsX: Int = 3,
        levelsY: Int = 3,
        levelsZ: Int = 1,
        parallelEncoding: Bool = true
    ) {
        self.compressionMode = compressionMode
        self.tiling = tiling
        self.progressionOrder = progressionOrder
        self.qualityLayers = max(1, qualityLayers)
        self.levelsX = max(0, levelsX)
        self.levelsY = max(0, levelsY)
        self.levelsZ = max(0, levelsZ)
        self.parallelEncoding = parallelEncoding
    }

    // MARK: - Presets

    /// Lossless encoding configuration.
    ///
    /// Uses reversible 5/3 wavelet with no quantization for mathematically
    /// exact reconstruction.
    public static let lossless = JP3DEncoderConfiguration(
        compressionMode: .lossless,
        tiling: .default,
        progressionOrder: .lrcps,
        qualityLayers: 1,
        levelsX: 3,
        levelsY: 3,
        levelsZ: 1
    )

    /// Lossy encoding configuration with default PSNR target.
    ///
    /// - Parameter psnr: Target PSNR in dB. Defaults to 40.0.
    /// - Returns: A lossy encoder configuration.
    public static func lossy(psnr: Double = 40.0) -> JP3DEncoderConfiguration {
        JP3DEncoderConfiguration(
            compressionMode: .lossy(psnr: psnr),
            tiling: .default,
            progressionOrder: .lrcps,
            qualityLayers: 3,
            levelsX: 3,
            levelsY: 3,
            levelsZ: 1
        )
    }

    /// Visually lossless encoding configuration.
    public static let visuallyLossless = JP3DEncoderConfiguration(
        compressionMode: .visuallyLossless,
        tiling: .default,
        progressionOrder: .lrcps,
        qualityLayers: 3,
        levelsX: 3,
        levelsY: 3,
        levelsZ: 1
    )

    /// Streaming-optimized configuration.
    ///
    /// Uses smaller tiles for lower latency progressive delivery.
    public static let streaming = JP3DEncoderConfiguration(
        compressionMode: .lossless,
        tiling: .streaming,
        progressionOrder: .slrcp,
        qualityLayers: 1,
        levelsX: 2,
        levelsY: 2,
        levelsZ: 1
    )

    /// High-throughput lossless configuration using HTJ2K.
    ///
    /// Uses the FBCOT block coder for significantly faster encoding and decoding
    /// while maintaining bit-exact reconstruction.
    public static let htj2kLossless = JP3DEncoderConfiguration(
        compressionMode: .losslessHTJ2K,
        tiling: .default,
        progressionOrder: .lrcps,
        qualityLayers: 1,
        levelsX: 3,
        levelsY: 3,
        levelsZ: 1
    )

    /// High-throughput lossy configuration using HTJ2K.
    ///
    /// - Parameter psnr: Target PSNR in dB. Defaults to 40.0.
    /// - Returns: An HTJ2K lossy encoder configuration.
    public static func htj2kLossy(psnr: Double = 40.0) -> JP3DEncoderConfiguration {
        JP3DEncoderConfiguration(
            compressionMode: .lossyHTJ2K(psnr: psnr),
            tiling: .default,
            progressionOrder: .lrcps,
            qualityLayers: 3,
            levelsX: 3,
            levelsY: 3,
            levelsZ: 1
        )
    }
}

/// Result of a JP3D encoding operation.
public struct JP3DEncoderResult: Sendable {
    /// The encoded JP3D codestream.
    public let data: Data

    /// Volume width.
    public let width: Int

    /// Volume height.
    public let height: Int

    /// Volume depth.
    public let depth: Int

    /// Number of components.
    public let componentCount: Int

    /// Whether lossless encoding was used.
    public let isLossless: Bool

    /// Number of tiles encoded.
    public let tileCount: Int

    /// Compression ratio (original size / compressed size).
    public var compressionRatio: Double {
        guard !data.isEmpty else { return 0 }
        let originalSize = width * height * depth * componentCount * 4 // Float = 4 bytes
        return Double(originalSize) / Double(data.count)
    }
}

/// Progress update during encoding.
public struct JP3DEncoderProgress: Sendable {
    /// The encoding stage.
    public let stage: JP3DEncodingStage

    /// Progress within the current stage (0.0 to 1.0).
    public let stageProgress: Double

    /// Overall encoding progress (0.0 to 1.0).
    public let overallProgress: Double

    /// Current tile being encoded.
    public let currentTile: Int

    /// Total number of tiles.
    public let totalTiles: Int
}

/// Encoding pipeline stages.
public enum JP3DEncodingStage: String, Sendable {
    /// Validating input and preparing tiles.
    case preparation = "Preparation"
    /// Applying 3D wavelet transform.
    case waveletTransform = "Wavelet Transform"
    /// Quantizing wavelet coefficients.
    case quantization = "Quantization"
    /// Forming packets and codestream.
    case codestreamGeneration = "Codestream Generation"
}

/// JP3D volumetric JPEG 2000 encoder.
///
/// `JP3DEncoder` implements the complete JP3D encoding pipeline for
/// volumetric data conforming to ISO/IEC 15444-10.
///
/// ## Usage
///
/// ```swift
/// let encoder = JP3DEncoder()
/// let result = try await encoder.encode(volume)
/// print("Compressed: \(result.data.count) bytes")
/// print("Ratio: \(result.compressionRatio)x")
/// ```
///
/// ## Pipeline
///
/// 1. **Preparation**: Validate input, decompose volume into tiles
/// 2. **Wavelet Transform**: Apply 3D DWT to each tile
/// 3. **Quantization**: Quantize wavelet coefficients
/// 4. **Codestream Generation**: Form packets and assemble codestream
public actor JP3DEncoder {
    // MARK: - State

    private let configuration: JP3DEncoderConfiguration
    private var progressCallback: (@Sendable (JP3DEncoderProgress) -> Void)?

    // MARK: - Init

    /// Creates an encoder with the given configuration.
    ///
    /// - Parameter configuration: Encoder configuration. Defaults to `.lossless`.
    public init(configuration: JP3DEncoderConfiguration = .lossless) {
        self.configuration = configuration
    }

    // MARK: - Public API

    /// Sets the progress reporting callback.
    ///
    /// - Parameter callback: Called during encoding with progress updates.
    public func setProgressCallback(
        _ callback: @escaping @Sendable (JP3DEncoderProgress) -> Void
    ) {
        self.progressCallback = callback
    }

    /// Encodes a volume to a JP3D codestream.
    ///
    /// This method performs the complete encoding pipeline: tile decomposition,
    /// 3D wavelet transform, quantization, and codestream generation.
    ///
    /// - Parameter volume: The volume to encode. Must have valid dimensions and components.
    /// - Returns: The encoding result containing the JP3D codestream.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the volume is invalid.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    public func encode(_ volume: J2KVolume) async throws -> JP3DEncoderResult {
        // Stage 1: Preparation
        try validateVolume(volume)
        let decomposer = JP3DTileDecomposer(configuration: configuration.tiling)
        let tiles = decomposer.decompose(volume: volume)

        guard !tiles.isEmpty else {
            throw J2KError.encodingError("No tiles generated for volume \(volume.width)×\(volume.height)×\(volume.depth)")
        }

        reportProgress(.preparation, stageProgress: 1.0, tile: 0, total: tiles.count)

        // Stage 2 & 3: Wavelet Transform + Quantization per tile
        let transformConfig = makeTransformConfiguration()
        let rateController = JP3DRateController(
            mode: configuration.compressionMode,
            qualityLayers: configuration.qualityLayers
        )

        var encodedTileData: [Data] = []
        encodedTileData.reserveCapacity(tiles.count)
        // Track actual clamped decomposition levels (populated from first tile's decomposition)
        var actualLevelsX = configuration.levelsX
        var actualLevelsY = configuration.levelsY
        var actualLevelsZ = configuration.levelsZ

        for (tileIdx, tile) in tiles.enumerated() {
            var tileBytes = Data()

            for comp in 0..<volume.components.count {
                // Extract tile data
                let tileData = try decomposer.extractTileData(
                    from: volume, tile: tile, componentIndex: comp
                )

                // Apply wavelet transform
                let wavelet = JP3DWaveletTransform(configuration: transformConfig)
                let decomposition = try await wavelet.forward(
                    data: tileData.data,
                    width: tileData.width,
                    height: tileData.height,
                    depth: tileData.depth
                )

                // Capture clamped levels from the first component of the first tile
                if tileIdx == 0 && comp == 0 {
                    actualLevelsX = decomposition.levelsX
                    actualLevelsY = decomposition.levelsY
                    actualLevelsZ = decomposition.levelsZ
                }

                reportProgress(
                    .waveletTransform,
                    stageProgress: Double(tileIdx * volume.components.count + comp + 1) /
                        Double(tiles.count * volume.components.count),
                    tile: tileIdx,
                    total: tiles.count
                )

                // Quantize
                let quantized = rateController.quantize(
                    coefficients: decomposition.coefficients.data,
                    tile: tile,
                    componentIndex: comp,
                    bitDepth: volume.components[comp].bitDepth,
                    decompositionLevels: max(
                        decomposition.levelsX,
                        max(decomposition.levelsY, decomposition.levelsZ)
                    )
                )

                reportProgress(
                    .quantization,
                    stageProgress: Double(tileIdx * volume.components.count + comp + 1) /
                        Double(tiles.count * volume.components.count),
                    tile: tileIdx,
                    total: tiles.count
                )

                // Encode quantized coefficients
                if configuration.compressionMode.isHTJ2K {
                    // HTJ2K tile encoding: prepend JP3DHTTileInfo prefix
                    let htConfig = JP3DHTJ2KConfiguration(
                        blockMode: .ht,
                        passCount: 1,
                        cleanupPassEnabled: true,
                        allowMixedTiles: false
                    )
                    let codec = JP3DHTJ2KCodec(configuration: htConfig)
                    tileBytes.append(codec.encodeTile(
                        coefficients: quantized.coefficients,
                        voxelCount: quantized.coefficients.count,
                        tileIndex: tileIdx
                    ))
                } else {
                    for coeff in quantized.coefficients {
                        var value = coeff.bigEndian
                        tileBytes.append(contentsOf: withUnsafeBytes(of: &value) { Array($0) })
                    }
                }
            }

            encodedTileData.append(tileBytes)
        }

        // Stage 4: Codestream Generation
        let builder = JP3DCodestreamBuilder()
        let effectiveTiling = decomposer.clampedConfiguration(for: volume)
        let htj2kConfig: JP3DHTJ2KConfiguration? = configuration.compressionMode.isHTJ2K
            ? .default : nil
        let codestream = builder.build(
            tileData: encodedTileData,
            width: volume.width,
            height: volume.height,
            depth: volume.depth,
            components: volume.components.count,
            bitDepth: volume.components[0].bitDepth,
            levelsX: actualLevelsX,
            levelsY: actualLevelsY,
            levelsZ: actualLevelsZ,
            tileSizeX: effectiveTiling.tileSizeX,
            tileSizeY: effectiveTiling.tileSizeY,
            tileSizeZ: effectiveTiling.tileSizeZ,
            isLossless: configuration.compressionMode.isLossless,
            htj2kConfiguration: htj2kConfig
        )

        reportProgress(.codestreamGeneration, stageProgress: 1.0,
                       tile: tiles.count, total: tiles.count)

        return JP3DEncoderResult(
            data: codestream,
            width: volume.width,
            height: volume.height,
            depth: volume.depth,
            componentCount: volume.components.count,
            isLossless: configuration.compressionMode.isLossless,
            tileCount: tiles.count
        )
    }

    /// Encodes raw voxel data without a `J2KVolume` wrapper.
    ///
    /// This is a convenience method for encoding raw float data directly.
    ///
    /// - Parameters:
    ///   - data: Voxel data as Float values in row-major order.
    ///   - width: Volume width.
    ///   - height: Volume height.
    ///   - depth: Volume depth.
    ///   - componentCount: Number of components (default: 1).
    ///   - bitDepth: Bit depth per component (default: 8).
    /// - Returns: The encoding result.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if dimensions are invalid.
    public func encode(
        data: [Float],
        width: Int,
        height: Int,
        depth: Int,
        componentCount: Int = 1,
        bitDepth: Int = 8
    ) async throws -> JP3DEncoderResult {
        guard width > 0, height > 0, depth > 0 else {
            throw J2KError.invalidParameter(
                "Dimensions must be positive: \(width)×\(height)×\(depth)"
            )
        }

        let expectedCount = width * height * depth * componentCount
        guard data.count == expectedCount else {
            throw J2KError.invalidParameter(
                "Data count \(data.count) does not match \(width)×\(height)×\(depth)×\(componentCount) = \(expectedCount)"
            )
        }

        // Build volume from raw data
        let voxelsPerComponent = width * height * depth
        let bytesPerSample = (bitDepth + 7) / 8
        var components: [J2KVolumeComponent] = []
        for c in 0..<componentCount {
            let start = c * voxelsPerComponent
            var componentBytes = Data(count: voxelsPerComponent * bytesPerSample)
            for i in 0..<voxelsPerComponent {
                let value = Int(roundf(data[start + i]))
                for b in 0..<bytesPerSample {
                    componentBytes[i * bytesPerSample + b] = UInt8(truncatingIfNeeded: value >> (b * 8))
                }
            }
            let component = J2KVolumeComponent(
                index: c,
                bitDepth: bitDepth,
                signed: false,
                width: width,
                height: height,
                depth: depth,
                data: componentBytes
            )
            components.append(component)
        }

        let volume = J2KVolume(width: width, height: height, depth: depth, components: components)
        return try await encode(volume)
    }

    // MARK: - Private Helpers

    /// Validates the input volume.
    private func validateVolume(_ volume: J2KVolume) throws {
        guard volume.width > 0, volume.height > 0, volume.depth > 0 else {
            throw J2KError.invalidParameter(
                "Volume dimensions must be positive: \(volume.width)×\(volume.height)×\(volume.depth)"
            )
        }

        guard !volume.components.isEmpty else {
            throw J2KError.invalidParameter("Volume must have at least one component")
        }

        for component in volume.components {
            guard component.bitDepth >= 1, component.bitDepth <= 38 else {
                throw J2KError.invalidBitDepth(
                    "Component bit depth \(component.bitDepth) out of range [1, 38]"
                )
            }
        }
    }

    /// Creates a wavelet transform configuration from encoder settings.
    private func makeTransformConfiguration() -> JP3DTransformConfiguration {
        let filter: JP3DWaveletFilter
        switch configuration.compressionMode {
        case .lossless, .losslessHTJ2K:
            filter = .reversible53
        default:
            filter = .irreversible97
        }

        return JP3DTransformConfiguration(
            filter: filter,
            mode: .separable,
            boundary: .symmetric,
            levelsX: configuration.levelsX,
            levelsY: configuration.levelsY,
            levelsZ: configuration.levelsZ
        )
    }

    /// Reports progress to the callback.
    private func reportProgress(
        _ stage: JP3DEncodingStage,
        stageProgress: Double,
        tile: Int,
        total: Int
    ) {
        let stageWeights: [JP3DEncodingStage: Double] = [
            .preparation: 0.05,
            .waveletTransform: 0.40,
            .quantization: 0.35,
            .codestreamGeneration: 0.20
        ]

        let stageOffset: [JP3DEncodingStage: Double] = [
            .preparation: 0.0,
            .waveletTransform: 0.05,
            .quantization: 0.45,
            .codestreamGeneration: 0.80
        ]

        let weight = stageWeights[stage] ?? 0.25
        let offset = stageOffset[stage] ?? 0.0
        let overall = offset + weight * stageProgress

        let update = JP3DEncoderProgress(
            stage: stage,
            stageProgress: stageProgress,
            overallProgress: min(1.0, overall),
            currentTile: tile,
            totalTiles: total
        )
        progressCallback?(update)
    }
}
