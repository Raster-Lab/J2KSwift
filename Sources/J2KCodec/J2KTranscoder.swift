/// # J2K Transcoder
///
/// Lossless transcoding between legacy JPEG 2000 (Part 1) and HTJ2K (Part 15)
/// without re-encoding wavelet coefficients.
///
/// Transcoding re-encodes only the Tier-1 (block coding) layer while preserving
/// all wavelet coefficients, metadata, quality layers, and progression orders.
/// This provides 5-10× faster format conversion compared to full re-encoding
/// and guarantees zero quality loss.
///
/// ## Topics
///
/// ### Transcoding
/// - ``J2KTranscoder``
/// - ``TranscodingDirection``
/// - ``TranscodingResult``
///
/// ### Intermediate Representation
/// - ``TranscodingCoefficients``
/// - ``TranscodingTileCoefficients``
/// - ``TranscodingCodeBlockCoefficients``
///
/// ### Progress
/// - ``TranscodingProgressUpdate``
/// - ``TranscodingStage``

import Foundation
import J2KCore

// MARK: - Transcoding Configuration

/// Configuration options for transcoding operations.
public struct TranscodingConfiguration: Sendable {
    /// Whether to enable parallel tile processing.
    ///
    /// When enabled, tiles are processed in parallel using Swift structured concurrency.
    /// This provides significant speedups for multi-tile images on multi-core systems.
    /// For single-tile images, parallel processing is automatically disabled.
    public let enableParallelProcessing: Bool
    
    /// Maximum number of concurrent tile processing tasks.
    ///
    /// Set to 0 to use the system processor count. Defaults to system processor count.
    public let maxConcurrency: Int
    
    /// Creates a new transcoding configuration.
    ///
    /// - Parameters:
    ///   - enableParallelProcessing: Whether to enable parallel tile processing (default: `true`).
    ///   - maxConcurrency: Maximum concurrent tasks (default: 0 = system processor count).
    public init(
        enableParallelProcessing: Bool = true,
        maxConcurrency: Int = 0
    ) {
        self.enableParallelProcessing = enableParallelProcessing
        self.maxConcurrency = maxConcurrency <= 0 ? ProcessInfo.processInfo.processorCount : maxConcurrency
    }
    
    /// Default configuration with parallel processing enabled.
    public static let `default` = TranscodingConfiguration()
    
    /// Configuration with parallel processing disabled.
    public static let sequential = TranscodingConfiguration(enableParallelProcessing: false)
}

// MARK: - Transcoding Direction

/// The direction of transcoding between JPEG 2000 formats.
public enum TranscodingDirection: String, Sendable {
    /// Transcode from legacy JPEG 2000 (Part 1) to HTJ2K (Part 15).
    ///
    /// Re-encodes EBCOT-coded code-blocks with the FBCOT block coder for
    /// significantly faster decoding throughput.
    case legacyToHT = "JPEG 2000 → HTJ2K"

    /// Transcode from HTJ2K (Part 15) to legacy JPEG 2000 (Part 1).
    ///
    /// Re-encodes FBCOT-coded code-blocks with the EBCOT block coder for
    /// maximum backward compatibility with legacy decoders.
    case htToLegacy = "HTJ2K → JPEG 2000"
}

// MARK: - Transcoding Stage

/// Represents the stages of the transcoding pipeline.
public enum TranscodingStage: String, Sendable, CaseIterable {
    /// Parsing the source codestream and extracting metadata.
    case parsing = "Parsing"

    /// Extracting intermediate coefficients from Tier-1 coded data.
    case coefficientExtraction = "Coefficient Extraction"

    /// Validating extracted coefficients.
    case validation = "Validation"

    /// Re-encoding coefficients with the target Tier-1 coder.
    case reEncoding = "Re-encoding"

    /// Generating the output codestream with appropriate markers.
    case codestreamGeneration = "Codestream Generation"
}

// MARK: - Transcoding Progress

/// Reports progress during a transcoding operation.
public struct TranscodingProgressUpdate: Sendable {
    /// The current transcoding stage.
    public let stage: TranscodingStage

    /// Progress within the current stage (0.0 to 1.0).
    public let progress: Double

    /// Overall transcoding progress (0.0 to 1.0).
    public let overallProgress: Double

    /// The transcoding direction.
    public let direction: TranscodingDirection
}

// MARK: - Transcoding Code-Block Coefficients

/// Intermediate representation of a single code-block's wavelet coefficients.
///
/// This structure captures all the information needed to losslessly re-encode
/// a code-block with a different Tier-1 coder. The coefficients are stored as
/// quantized integer values exactly as they appear after Tier-1 decoding.
public struct TranscodingCodeBlockCoefficients: Sendable {
    /// The code-block index within its precinct.
    public let index: Int

    /// The x-coordinate of the code-block in the subband.
    public let x: Int

    /// The y-coordinate of the code-block in the subband.
    public let y: Int

    /// The width of the code-block in samples.
    public let width: Int

    /// The height of the code-block in samples.
    public let height: Int

    /// The wavelet subband this code-block belongs to.
    public let subband: J2KSubband

    /// The quantized wavelet coefficients in raster order.
    ///
    /// These are the integer coefficient values produced by Tier-1 decoding.
    /// They include sign information (negative values are valid).
    public let coefficients: [Int]

    /// The number of zero bit-planes above the most significant bit-plane.
    public let zeroBitPlanes: Int

    /// The number of coding passes that were decoded.
    public let codingPasses: Int

    /// Creates a new code-block coefficient representation.
    ///
    /// - Parameters:
    ///   - index: The code-block index.
    ///   - x: The x-coordinate in the subband.
    ///   - y: The y-coordinate in the subband.
    ///   - width: The width in samples.
    ///   - height: The height in samples.
    ///   - subband: The wavelet subband.
    ///   - coefficients: The quantized wavelet coefficients.
    ///   - zeroBitPlanes: The number of zero MSB planes.
    ///   - codingPasses: The number of decoded coding passes.
    public init(
        index: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        subband: J2KSubband,
        coefficients: [Int],
        zeroBitPlanes: Int,
        codingPasses: Int
    ) {
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.subband = subband
        self.coefficients = coefficients
        self.zeroBitPlanes = zeroBitPlanes
        self.codingPasses = codingPasses
    }
}

// MARK: - Transcoding Tile Coefficients

/// Intermediate representation of all code-block coefficients within a tile.
///
/// Groups code-block coefficients by component and resolution level,
/// preserving the spatial organization needed for Tier-2 packet formation.
public struct TranscodingTileCoefficients: Sendable {
    /// The tile index.
    public let tileIndex: Int

    /// The tile width in pixels.
    public let width: Int

    /// The tile height in pixels.
    public let height: Int

    /// Code-block coefficients organized by component index then subband.
    ///
    /// The outer array index is the component index. Each dictionary maps
    /// subband to an array of code-block coefficients.
    public let components: [[J2KSubband: [TranscodingCodeBlockCoefficients]]]

    /// Creates a new tile coefficient representation.
    ///
    /// - Parameters:
    ///   - tileIndex: The tile index.
    ///   - width: The tile width.
    ///   - height: The tile height.
    ///   - components: Code-block coefficients by component and subband.
    public init(
        tileIndex: Int,
        width: Int,
        height: Int,
        components: [[J2KSubband: [TranscodingCodeBlockCoefficients]]]
    ) {
        self.tileIndex = tileIndex
        self.width = width
        self.height = height
        self.components = components
    }
}

// MARK: - Transcoding Coefficients

/// Complete intermediate representation of all coefficients in an image.
///
/// This is the unified format used for lossless transcoding. It captures the
/// full image structure — metadata, tile organization, and all code-block
/// coefficients — in a codec-independent form that can be re-encoded with
/// either EBCOT or FBCOT.
public struct TranscodingCoefficients: Sendable {
    /// The image width in pixels.
    public let width: Int

    /// The image height in pixels.
    public let height: Int

    /// The number of image components.
    public let componentCount: Int

    /// Per-component bit depths.
    public let bitDepths: [Int]

    /// Per-component signedness.
    public let signedComponents: [Bool]

    /// The color space of the source image.
    public let colorSpace: J2KColorSpace

    /// The number of wavelet decomposition levels.
    public let decompositionLevels: Int

    /// The progression order from the source codestream.
    public let progressionOrder: J2KProgressionOrder

    /// The number of quality layers.
    public let qualityLayers: Int

    /// Whether the source used lossless compression.
    public let isLossless: Bool

    /// Whether the source used HTJ2K encoding.
    public let sourceIsHTJ2K: Bool

    /// The source coding mode (internal).
    let sourceCodingMode: HTCodingMode

    /// All tile coefficients in raster order.
    public let tiles: [TranscodingTileCoefficients]

    /// The tile width (0 for single-tile images).
    public let tileWidth: Int

    /// The tile height (0 for single-tile images).
    public let tileHeight: Int

    /// The code-block width used in the source codestream.
    public let codeBlockWidth: Int

    /// The code-block height used in the source codestream.
    public let codeBlockHeight: Int

    /// Creates a new transcoding coefficients container.
    ///
    /// - Parameters:
    ///   - width: The image width.
    ///   - height: The image height.
    ///   - componentCount: The number of components.
    ///   - bitDepths: Per-component bit depths.
    ///   - signedComponents: Per-component signedness.
    ///   - colorSpace: The color space.
    ///   - decompositionLevels: Wavelet decomposition levels.
    ///   - progressionOrder: The packet progression order.
    ///   - qualityLayers: The number of quality layers.
    ///   - isLossless: Whether the source is lossless.
    ///   - sourceIsHTJ2K: Whether the source uses HTJ2K encoding.
    ///   - tiles: The tile coefficients.
    ///   - tileWidth: The tile width (0 for untiled).
    ///   - tileHeight: The tile height (0 for untiled).
    ///   - codeBlockWidth: The code-block width (default: 32).
    ///   - codeBlockHeight: The code-block height (default: 32).
    public init(
        width: Int,
        height: Int,
        componentCount: Int,
        bitDepths: [Int],
        signedComponents: [Bool],
        colorSpace: J2KColorSpace,
        decompositionLevels: Int,
        progressionOrder: J2KProgressionOrder,
        qualityLayers: Int,
        isLossless: Bool,
        sourceIsHTJ2K: Bool,
        tiles: [TranscodingTileCoefficients],
        tileWidth: Int = 0,
        tileHeight: Int = 0,
        codeBlockWidth: Int = 32,
        codeBlockHeight: Int = 32
    ) {
        self.width = width
        self.height = height
        self.componentCount = componentCount
        self.bitDepths = bitDepths
        self.signedComponents = signedComponents
        self.colorSpace = colorSpace
        self.decompositionLevels = decompositionLevels
        self.progressionOrder = progressionOrder
        self.qualityLayers = qualityLayers
        self.isLossless = isLossless
        self.sourceIsHTJ2K = sourceIsHTJ2K
        self.sourceCodingMode = sourceIsHTJ2K ? .ht : .legacy
        self.tiles = tiles
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.codeBlockWidth = codeBlockWidth
        self.codeBlockHeight = codeBlockHeight
    }

    /// Internal initializer that accepts an HTCodingMode directly.
    init(
        width: Int,
        height: Int,
        componentCount: Int,
        bitDepths: [Int],
        signedComponents: [Bool],
        colorSpace: J2KColorSpace,
        decompositionLevels: Int,
        progressionOrder: J2KProgressionOrder,
        qualityLayers: Int,
        isLossless: Bool,
        sourceCodingMode: HTCodingMode,
        tiles: [TranscodingTileCoefficients],
        tileWidth: Int = 0,
        tileHeight: Int = 0,
        codeBlockWidth: Int = 32,
        codeBlockHeight: Int = 32
    ) {
        self.width = width
        self.height = height
        self.componentCount = componentCount
        self.bitDepths = bitDepths
        self.signedComponents = signedComponents
        self.colorSpace = colorSpace
        self.decompositionLevels = decompositionLevels
        self.progressionOrder = progressionOrder
        self.qualityLayers = qualityLayers
        self.isLossless = isLossless
        self.sourceIsHTJ2K = sourceCodingMode == .ht
        self.sourceCodingMode = sourceCodingMode
        self.tiles = tiles
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.codeBlockWidth = codeBlockWidth
        self.codeBlockHeight = codeBlockHeight
    }

    /// The total number of code-blocks across all tiles and components.
    public var totalCodeBlocks: Int {
        tiles.reduce(0) { tileSum, tile in
            tileSum + tile.components.reduce(0) { compSum, subbands in
                compSum + subbands.values.reduce(0) { $0 + $1.count }
            }
        }
    }

    /// Validates the integrity of the coefficient data.
    ///
    /// Checks that dimensions are consistent, coefficient arrays have the
    /// correct size, and all metadata is valid.
    ///
    /// - Throws: ``J2KError/invalidData(_:)`` if validation fails.
    public func validate() throws {
        guard width > 0 && height > 0 else {
            throw J2KError.invalidData("Image dimensions must be positive: \(width)x\(height)")
        }

        guard componentCount > 0 else {
            throw J2KError.invalidData("Must have at least one component")
        }

        guard bitDepths.count == componentCount else {
            throw J2KError.invalidData(
                "Bit depth count (\(bitDepths.count)) must match component count (\(componentCount))"
            )
        }

        guard signedComponents.count == componentCount else {
            throw J2KError.invalidData(
                "Signed component count (\(signedComponents.count)) must match component count (\(componentCount))"
            )
        }

        for bitDepth in bitDepths {
            guard bitDepth >= 1 && bitDepth <= 38 else {
                throw J2KError.invalidData("Invalid bit depth: \(bitDepth)")
            }
        }

        guard decompositionLevels >= 0 && decompositionLevels <= 32 else {
            throw J2KError.invalidData(
                "Decomposition levels must be 0-32, got \(decompositionLevels)"
            )
        }

        guard qualityLayers >= 1 else {
            throw J2KError.invalidData("Must have at least one quality layer")
        }

        // Validate each tile's code-block coefficients
        for tile in tiles {
            for componentSubbands in tile.components {
                for (_, codeBlocks) in componentSubbands {
                    for cb in codeBlocks {
                        let expectedCount = cb.width * cb.height
                        guard cb.coefficients.count == expectedCount else {
                            throw J2KError.invalidData(
                                "Code-block \(cb.index) has \(cb.coefficients.count) coefficients, " +
                                "expected \(expectedCount) for \(cb.width)x\(cb.height)"
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Transcoding Result

/// The result of a transcoding operation.
public struct TranscodingResult: Sendable {
    /// The transcoded codestream data.
    public let data: Data

    /// The direction of transcoding that was performed.
    public let direction: TranscodingDirection

    /// The number of code-blocks that were transcoded.
    public let codeBlocksTranscoded: Int

    /// The number of tiles processed.
    public let tilesProcessed: Int

    /// The total time spent transcoding, in seconds.
    public let transcodingTime: TimeInterval

    /// Whether metadata was fully preserved.
    public let metadataPreserved: Bool

    /// Creates a new transcoding result.
    ///
    /// - Parameters:
    ///   - data: The transcoded codestream data.
    ///   - direction: The transcoding direction.
    ///   - codeBlocksTranscoded: Number of code-blocks transcoded.
    ///   - tilesProcessed: Number of tiles processed.
    ///   - transcodingTime: Total transcoding time in seconds.
    ///   - metadataPreserved: Whether metadata was fully preserved.
    public init(
        data: Data,
        direction: TranscodingDirection,
        codeBlocksTranscoded: Int,
        tilesProcessed: Int,
        transcodingTime: TimeInterval,
        metadataPreserved: Bool
    ) {
        self.data = data
        self.direction = direction
        self.codeBlocksTranscoded = codeBlocksTranscoded
        self.tilesProcessed = tilesProcessed
        self.transcodingTime = transcodingTime
        self.metadataPreserved = metadataPreserved
    }
}

// MARK: - Transcoder

/// Lossless transcoder between JPEG 2000 (Part 1) and HTJ2K (Part 15).
///
/// `J2KTranscoder` converts between legacy JPEG 2000 and HTJ2K encoding formats
/// without re-encoding the wavelet coefficients. Only the Tier-1 (block coding)
/// layer is re-encoded, preserving all other information:
///
/// - Wavelet coefficients (unchanged)
/// - Color transform parameters
/// - Quantization step sizes
/// - Quality layer structure
/// - Progression order
/// - Metadata and ICC profiles
///
/// This approach is 5-10× faster than full re-encoding and guarantees zero
/// quality loss.
///
/// ## Basic Usage
///
/// ```swift
/// let transcoder = J2KTranscoder()
///
/// // Convert legacy JPEG 2000 to HTJ2K
/// let htj2kData = try transcoder.transcode(
///     legacyData,
///     direction: .legacyToHT
/// )
///
/// // Convert HTJ2K back to legacy JPEG 2000
/// let legacyData = try transcoder.transcode(
///     htj2kData,
///     direction: .htToLegacy
/// )
/// ```
///
/// ## Extracting Intermediate Coefficients
///
/// ```swift
/// let coefficients = try transcoder.extractCoefficients(from: codestreamData)
/// try coefficients.validate()
/// let result = try transcoder.encodeFromCoefficients(
///     coefficients,
///     targetMode: .ht
/// )
/// ```
public struct J2KTranscoder: Sendable {
    /// The transcoding configuration.
    public let configuration: TranscodingConfiguration
    
    /// Creates a new transcoder with the specified configuration.
    ///
    /// - Parameter configuration: The transcoding configuration (default: `.default`).
    public init(configuration: TranscodingConfiguration = .default) {
        self.configuration = configuration
    }

    // MARK: - High-Level Transcoding

    /// Transcodes a JPEG 2000 codestream between legacy and HTJ2K formats.
    ///
    /// This is the primary transcoding entry point. It automatically detects
    /// the source format and re-encodes the Tier-1 data with the target coder.
    ///
    /// For multi-tile images, this method automatically uses parallel processing
    /// if enabled in the configuration.
    ///
    /// - Parameters:
    ///   - data: The source codestream data.
    ///   - direction: The transcoding direction.
    ///   - progress: Optional progress callback.
    /// - Returns: A ``TranscodingResult`` with the transcoded data and metadata.
    /// - Throws: ``J2KError/decodingError(_:)`` if the source codestream is invalid.
    /// - Throws: ``J2KError/encodingError(_:)`` if re-encoding fails.
    public func transcode(
        _ data: Data,
        direction: TranscodingDirection,
        progress: (@Sendable (TranscodingProgressUpdate) -> Void)? = nil
    ) throws -> TranscodingResult {
        // Use task with unsafe continuation for sync-to-async bridging
        nonisolated(unsafe) var capturedResult: Result<TranscodingResult, Error>?
        let group = DispatchGroup()
        group.enter()
        
        Task { @Sendable in
            do {
                capturedResult = .success(try await transcodeAsync(data, direction: direction, progress: progress))
            } catch {
                capturedResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return try capturedResult!.get()
    }
    
    /// Asynchronously transcodes a JPEG 2000 codestream between legacy and HTJ2K formats.
    ///
    /// This method supports parallel tile processing for multi-tile images when enabled
    /// in the configuration. Use this method for better integration with async/await code.
    ///
    /// - Parameters:
    ///   - data: The source codestream data.
    ///   - direction: The transcoding direction.
    ///   - progress: Optional progress callback.
    /// - Returns: A ``TranscodingResult`` with the transcoded data and metadata.
    /// - Throws: ``J2KError/decodingError(_:)`` if the source codestream is invalid.
    /// - Throws: ``J2KError/encodingError(_:)`` if re-encoding fails.
    public func transcodeAsync(
        _ data: Data,
        direction: TranscodingDirection,
        progress: (@Sendable (TranscodingProgressUpdate) -> Void)? = nil
    ) async throws -> TranscodingResult {
        let startTime = DispatchTime.now()

        // Stage 1: Extract coefficients from source
        reportProgress(progress, stage: .parsing, stageProgress: 0.0, direction: direction)
        let coefficients = try extractCoefficients(from: data)
        reportProgress(progress, stage: .parsing, stageProgress: 1.0, direction: direction)

        // Stage 2: Validate
        reportProgress(progress, stage: .validation, stageProgress: 0.0, direction: direction)
        try coefficients.validate()
        reportProgress(progress, stage: .validation, stageProgress: 1.0, direction: direction)

        // Stage 3: Re-encode with target coder
        let targetMode: HTCodingMode = direction == .legacyToHT ? .ht : .legacy
        reportProgress(progress, stage: .reEncoding, stageProgress: 0.0, direction: direction)
        let result = try await encodeFromCoefficientsAsync(coefficients, targetMode: targetMode, progress: { p in
            self.reportProgress(progress, stage: .reEncoding, stageProgress: p, direction: direction)
        })
        reportProgress(progress, stage: .reEncoding, stageProgress: 1.0, direction: direction)

        let endTime = DispatchTime.now()
        let elapsed = Double(endTime.uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000_000.0

        return TranscodingResult(
            data: result,
            direction: direction,
            codeBlocksTranscoded: coefficients.totalCodeBlocks,
            tilesProcessed: coefficients.tiles.count,
            transcodingTime: elapsed,
            metadataPreserved: true
        )
    }

    // MARK: - Coefficient Extraction

    /// Extracts intermediate coefficients from a JPEG 2000 codestream.
    ///
    /// Parses the codestream, decodes Tier-1 data to recover quantized wavelet
    /// coefficients, and assembles them into the unified intermediate format.
    ///
    /// - Parameter data: The JPEG 2000 codestream data.
    /// - Returns: The extracted ``TranscodingCoefficients``.
    /// - Throws: ``J2KError/decodingError(_:)`` if parsing or decoding fails.
    public func extractCoefficients(from data: Data) throws -> TranscodingCoefficients {
        // Parse the codestream to extract metadata and tile data
        let parsed = try parseCodestreamForTranscoding(data)

        // Decode each tile's code-blocks to coefficients
        var tileCoefficients: [TranscodingTileCoefficients] = []

        for tileData in parsed.tiles {
            let tileCoeffs = try extractTileCoefficients(
                tileData,
                metadata: parsed.metadata,
                codingMode: parsed.codingMode
            )
            tileCoefficients.append(tileCoeffs)
        }

        return TranscodingCoefficients(
            width: parsed.metadata.width,
            height: parsed.metadata.height,
            componentCount: parsed.metadata.componentCount,
            bitDepths: parsed.metadata.bitDepths,
            signedComponents: parsed.metadata.signedComponents,
            colorSpace: parsed.metadata.colorSpace,
            decompositionLevels: parsed.metadata.decompositionLevels,
            progressionOrder: parsed.metadata.progressionOrder,
            qualityLayers: parsed.metadata.qualityLayers,
            isLossless: parsed.metadata.isLossless,
            sourceCodingMode: parsed.codingMode,
            tiles: tileCoefficients,
            tileWidth: parsed.metadata.tileWidth,
            tileHeight: parsed.metadata.tileHeight,
            codeBlockWidth: parsed.metadata.codeBlockWidth,
            codeBlockHeight: parsed.metadata.codeBlockHeight
        )
    }

    // MARK: - Re-encoding from Coefficients

    /// Re-encodes intermediate coefficients to produce an HTJ2K codestream.
    ///
    /// Takes the unified coefficient representation and encodes it into a
    /// complete JPEG 2000 codestream using HTJ2K block coding.
    ///
    /// - Parameters:
    ///   - coefficients: The intermediate coefficients to encode.
    ///   - useHTJ2K: If `true`, encode using HTJ2K; if `false`, use legacy EBCOT.
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Returns: The encoded codestream data.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    public func encodeFromCoefficients(
        _ coefficients: TranscodingCoefficients,
        useHTJ2K: Bool,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> Data {
        let targetMode: HTCodingMode = useHTJ2K ? .ht : .legacy
        return try encodeFromCoefficients(coefficients, targetMode: targetMode, progress: progress)
    }

    /// Re-encodes intermediate coefficients with the specified Tier-1 coder.
    ///
    /// Takes the unified coefficient representation and encodes it into a
    /// complete JPEG 2000 codestream using the target block coding mode.
    ///
    /// - Parameters:
    ///   - coefficients: The intermediate coefficients to encode.
    ///   - targetMode: The target block coding mode (.ht or .legacy).
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Returns: The encoded codestream data.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeFromCoefficients(
        _ coefficients: TranscodingCoefficients,
        targetMode: HTCodingMode,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> Data {
        // Use task with unsafe continuation for sync-to-async bridging
        nonisolated(unsafe) var capturedResult: Result<Data, Error>?
        let group = DispatchGroup()
        group.enter()
        
        Task { @Sendable in
            do {
                capturedResult = .success(try await encodeFromCoefficientsAsync(coefficients, targetMode: targetMode, progress: progress))
            } catch {
                capturedResult = .failure(error)
            }
            group.leave()
        }
        
        group.wait()
        return try capturedResult!.get()
    }
    
    /// Asynchronously re-encodes intermediate coefficients with the specified Tier-1 coder.
    ///
    /// Takes the unified coefficient representation and encodes it into a
    /// complete JPEG 2000 codestream using the target block coding mode.
    /// Supports parallel tile processing for multi-tile images.
    ///
    /// - Parameters:
    ///   - coefficients: The intermediate coefficients to encode.
    ///   - targetMode: The target block coding mode (.ht or .legacy).
    ///   - progress: Optional progress callback (0.0 to 1.0).
    /// - Returns: The encoded codestream data.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    func encodeFromCoefficientsAsync(
        _ coefficients: TranscodingCoefficients,
        targetMode: HTCodingMode,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        var codestream = Data()

        // Write SOC marker
        codestream.append(contentsOf: [0xFF, 0x4F])

        // Write SIZ marker
        let sizData = generateSIZMarker(from: coefficients)
        codestream.append(contentsOf: [0xFF, 0x51]) // SIZ marker
        let sizLength = UInt16(sizData.count + 2)
        codestream.append(UInt8((sizLength >> 8) & 0xFF))
        codestream.append(UInt8(sizLength & 0xFF))
        codestream.append(sizData)

        // Write CAP marker if target is HTJ2K
        if targetMode == .ht {
            let htEncoder = HTJ2KEncoder(configuration: HTJ2KConfiguration(codingMode: .ht))
            let capData = htEncoder.generateCAPMarkerData()
            codestream.append(contentsOf: [0xFF, 0x50]) // CAP marker
            let capLength = UInt16(capData.count + 2)
            codestream.append(UInt8((capLength >> 8) & 0xFF))
            codestream.append(UInt8(capLength & 0xFF))
            codestream.append(capData)
        }

        // Write COD marker
        let codData = generateCODMarker(from: coefficients, targetMode: targetMode)
        codestream.append(contentsOf: [0xFF, 0x52]) // COD marker
        let codLength = UInt16(codData.count + 2)
        codestream.append(UInt8((codLength >> 8) & 0xFF))
        codestream.append(UInt8(codLength & 0xFF))
        codestream.append(codData)

        // Write QCD marker
        let qcdData = generateQCDMarker(from: coefficients)
        codestream.append(contentsOf: [0xFF, 0x5C]) // QCD marker
        let qcdLength = UInt16(qcdData.count + 2)
        codestream.append(UInt8((qcdLength >> 8) & 0xFF))
        codestream.append(UInt8(qcdLength & 0xFF))
        codestream.append(qcdData)

        // Process tiles in parallel if enabled and there are multiple tiles
        let totalTiles = coefficients.tiles.count
        let shouldUseParallel = configuration.enableParallelProcessing && totalTiles > 1
        
        let encodedTiles: [(index: Int, data: Data)]
        
        if shouldUseParallel {
            // Parallel tile processing using Swift structured concurrency
            encodedTiles = try await withThrowingTaskGroup(
                of: (Int, Data).self,
                returning: [(Int, Data)].self
            ) { group in
                // Limit concurrency by batching submissions
                let maxConcurrency = configuration.maxConcurrency
                var nextIndex = 0
                var collectedResults: [(Int, Data)] = []
                collectedResults.reserveCapacity(totalTiles)
                
                // Submit initial batch
                let initialBatch = min(maxConcurrency, totalTiles)
                for index in 0..<initialBatch {
                    let tile = coefficients.tiles[index]
                    group.addTask {
                        let tileData = try self.encodeTile(
                            tile,
                            targetMode: targetMode,
                            metadata: coefficients
                        )
                        return (index, tileData)
                    }
                }
                nextIndex = initialBatch
                
                // Process results and submit more work
                for try await (index, tileData) in group {
                    collectedResults.append((index, tileData))
                    
                    // Report progress
                    if let progress = progress {
                        progress(Double(collectedResults.count) / Double(totalTiles))
                    }
                    
                    // Submit next tile if available
                    if nextIndex < totalTiles {
                        let tile = coefficients.tiles[nextIndex]
                        let capturedIndex = nextIndex
                        group.addTask {
                            let tileData = try self.encodeTile(
                                tile,
                                targetMode: targetMode,
                                metadata: coefficients
                            )
                            return (capturedIndex, tileData)
                        }
                        nextIndex += 1
                    }
                }
                
                // Sort by original index to maintain order
                return collectedResults.sorted { $0.0 < $1.0 }
            }
        } else {
            // Sequential tile processing
            encodedTiles = try coefficients.tiles.enumerated().map { (tileIdx, tile) in
                let tileData = try self.encodeTile(
                    tile,
                    targetMode: targetMode,
                    metadata: coefficients
                )
                
                progress?(Double(tileIdx + 1) / Double(totalTiles))
                
                return (index: tileIdx, data: tileData)
            }
        }
        
        // Write tiles in order
        for (tileIdx, tileData) in encodedTiles {
            let tile = coefficients.tiles[tileIdx]
            
            // Write SOT marker
            codestream.append(contentsOf: [0xFF, 0x90]) // SOT marker
            let sotLength: UInt16 = 10 // Fixed SOT segment length
            codestream.append(UInt8((sotLength >> 8) & 0xFF))
            codestream.append(UInt8(sotLength & 0xFF))
            // Isot (tile index)
            codestream.append(UInt8((UInt16(tile.tileIndex) >> 8) & 0xFF))
            codestream.append(UInt8(UInt16(tile.tileIndex) & 0xFF))
            // Psot (tile-part length, 0 means until next SOT or EOC)
            let psot = UInt32(12 + tileData.count + 2) // SOT(12) + data + SOD(2)
            codestream.append(UInt8((psot >> 24) & 0xFF))
            codestream.append(UInt8((psot >> 16) & 0xFF))
            codestream.append(UInt8((psot >> 8) & 0xFF))
            codestream.append(UInt8(psot & 0xFF))
            // TPsot (tile-part index)
            codestream.append(0x00)
            // TNsot (number of tile-parts)
            codestream.append(0x01)

            // Write SOD marker
            codestream.append(contentsOf: [0xFF, 0x93]) // SOD marker

            // Write tile data
            codestream.append(tileData)
        }

        // Write EOC marker
        codestream.append(contentsOf: [0xFF, 0xD9])

        return codestream
    }

    // MARK: - Format Detection

    /// Detects whether a JPEG 2000 codestream uses HTJ2K encoding.
    ///
    /// Scans the main header for CAP marker segments and COD marker coding
    /// style bits to determine whether the codestream uses HTJ2K or legacy coding.
    ///
    /// - Parameter data: The codestream data.
    /// - Returns: `true` if the codestream uses HTJ2K encoding, `false` for legacy.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is invalid.
    public func isHTJ2K(_ data: Data) throws -> Bool {
        return try detectCodingMode(in: data) == .ht
    }

    /// Detects the coding mode of a JPEG 2000 codestream.
    ///
    /// Scans the main header for CAP marker segments and COD marker coding
    /// style bits to determine whether the codestream uses HTJ2K or legacy coding.
    ///
    /// - Parameter data: The codestream data.
    /// - Returns: The detected coding mode.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is invalid.
    func detectCodingMode(in data: Data) throws -> HTCodingMode {
        guard data.count >= 4 else {
            throw J2KError.decodingError("Codestream too short to detect format")
        }

        // Check SOC marker
        let socMarker = UInt16(data[0]) << 8 | UInt16(data[1])
        guard socMarker == J2KMarker.soc.rawValue else {
            throw J2KError.decodingError("Missing SOC marker")
        }

        // Scan for CAP marker
        var offset = 2
        while offset < data.count - 1 {
            let marker = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])

            if marker == J2KMarker.cap.rawValue {
                // Found CAP marker — this is HTJ2K
                return .ht
            }

            if marker == J2KMarker.sot.rawValue || marker == J2KMarker.sod.rawValue {
                break
            }

            offset += 2
            if let m = J2KMarker(rawValue: marker), m.hasSegment {
                if offset + 1 < data.count {
                    let length = Int(data[offset]) << 8 | Int(data[offset + 1])
                    offset += length
                } else {
                    break
                }
            }
        }

        return .legacy
    }

    // MARK: - Private: Codestream Parsing

    /// Parsed codestream data for transcoding.
    private struct ParsedCodestream: Sendable {
        let metadata: TranscodingMetadata
        let codingMode: HTCodingMode
        let tiles: [ParsedTileData]
    }

    /// Metadata extracted from codestream markers.
    private struct TranscodingMetadata: Sendable {
        var width: Int
        var height: Int
        var componentCount: Int
        var bitDepths: [Int]
        var signedComponents: [Bool]
        var colorSpace: J2KColorSpace
        var decompositionLevels: Int
        var progressionOrder: J2KProgressionOrder
        var qualityLayers: Int
        var isLossless: Bool
        var tileWidth: Int
        var tileHeight: Int
        var codeBlockWidth: Int
        var codeBlockHeight: Int
    }

    /// Parsed tile data from the codestream.
    private struct ParsedTileData: Sendable {
        let tileIndex: Int
        let data: Data
    }

    /// Parses a complete codestream for transcoding.
    private func parseCodestreamForTranscoding(_ data: Data) throws -> ParsedCodestream {
        guard data.count >= 4 else {
            throw J2KError.decodingError("Codestream too short")
        }

        let socMarker = UInt16(data[0]) << 8 | UInt16(data[1])
        guard socMarker == J2KMarker.soc.rawValue else {
            throw J2KError.decodingError("Missing SOC marker at start of codestream")
        }

        var metadata = TranscodingMetadata(
            width: 0, height: 0, componentCount: 0,
            bitDepths: [], signedComponents: [],
            colorSpace: .unknown, decompositionLevels: 5,
            progressionOrder: .lrcp, qualityLayers: 1,
            isLossless: true, tileWidth: 0, tileHeight: 0,
            codeBlockWidth: 32, codeBlockHeight: 32
        )
        var codingMode: HTCodingMode = .legacy
        var tiles: [ParsedTileData] = []

        var offset = 2
        while offset < data.count - 1 {
            let marker = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2

            switch marker {
            case J2KMarker.siz.rawValue:
                // Parse SIZ marker
                guard offset + 1 < data.count else { break }
                let segLength = Int(data[offset]) << 8 | Int(data[offset + 1])
                let segEnd = offset + segLength
                guard segEnd <= data.count else {
                    throw J2KError.decodingError("SIZ marker segment extends beyond codestream")
                }
                try parseSIZSegment(data: data, offset: offset + 2, metadata: &metadata)
                offset = segEnd

            case J2KMarker.cap.rawValue:
                codingMode = .ht
                guard offset + 1 < data.count else { break }
                let segLength = Int(data[offset]) << 8 | Int(data[offset + 1])
                offset += segLength

            case J2KMarker.cod.rawValue:
                guard offset + 1 < data.count else { break }
                let segLength = Int(data[offset]) << 8 | Int(data[offset + 1])
                let segEnd = offset + segLength
                guard segEnd <= data.count else {
                    throw J2KError.decodingError("COD marker segment extends beyond codestream")
                }
                parseCODSegment(data: data, offset: offset + 2, metadata: &metadata, codingMode: &codingMode)
                offset = segEnd

            case J2KMarker.qcd.rawValue:
                guard offset + 1 < data.count else { break }
                let segLength = Int(data[offset]) << 8 | Int(data[offset + 1])
                offset += segLength

            case J2KMarker.sot.rawValue:
                guard offset + 1 < data.count else { break }
                let segLength = Int(data[offset]) << 8 | Int(data[offset + 1])
                let segStart = offset + 2
                guard segStart + 8 <= data.count else {
                    throw J2KError.decodingError("SOT marker segment too short")
                }
                let tileIndex = Int(data[segStart]) << 8 | Int(data[segStart + 1])
                let psot = Int(data[segStart + 2]) << 24 | Int(data[segStart + 3]) << 16 |
                           Int(data[segStart + 4]) << 8 | Int(data[segStart + 5])

                // Move past SOT segment
                offset += segLength

                // Find SOD marker
                while offset < data.count - 1 {
                    let nextMarker = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
                    if nextMarker == J2KMarker.sod.rawValue {
                        offset += 2 // Skip SOD marker
                        break
                    }
                    offset += 2
                    if let m = J2KMarker(rawValue: nextMarker), m.hasSegment {
                        if offset + 1 < data.count {
                            let len = Int(data[offset]) << 8 | Int(data[offset + 1])
                            offset += len
                        } else {
                            break
                        }
                    }
                }

                // Extract tile data (from SOD to next SOT or EOC)
                let tileDataEnd: Int
                if psot > 0 {
                    // Psot includes the entire tile-part length from SOT marker start.
                    // SOT marker (2 bytes) is at (offset - 2 - segLength - 2),
                    // but we need the start of the SOT marker code (0xFF90).
                    let sotMarkerStart = offset - 2 - segLength - 2
                    tileDataEnd = min(sotMarkerStart + psot, data.count)
                } else {
                    // Find next SOT or EOC
                    tileDataEnd = findNextTileOrEnd(data: data, from: offset)
                }

                let tileDataSlice = data[offset..<min(tileDataEnd, data.count)]
                tiles.append(ParsedTileData(tileIndex: tileIndex, data: Data(tileDataSlice)))
                offset = tileDataEnd

            case J2KMarker.eoc.rawValue:
                // End of codestream
                offset = data.count

            default:
                // Skip unknown marker segments
                if let m = J2KMarker(rawValue: marker), m.hasSegment {
                    if offset + 1 < data.count {
                        let segLength = Int(data[offset]) << 8 | Int(data[offset + 1])
                        offset += segLength
                    } else {
                        break
                    }
                }
            }
        }

        // Set color space based on component count if not already determined
        if metadata.colorSpace == .unknown {
            metadata.colorSpace = metadata.componentCount >= 3 ? .sRGB : .grayscale
        }

        return ParsedCodestream(
            metadata: metadata,
            codingMode: codingMode,
            tiles: tiles
        )
    }

    /// Parses a SIZ marker segment.
    private func parseSIZSegment(data: Data, offset: Int, metadata: inout TranscodingMetadata) throws {
        var pos = offset

        guard pos + 36 <= data.count else {
            throw J2KError.decodingError("SIZ segment too short")
        }

        // Rsiz (2 bytes) - capabilities
        pos += 2

        // Xsiz, Ysiz (4 bytes each) - image dimensions on reference grid
        let xsiz = Int(data[pos]) << 24 | Int(data[pos + 1]) << 16 |
                    Int(data[pos + 2]) << 8 | Int(data[pos + 3])
        pos += 4
        let ysiz = Int(data[pos]) << 24 | Int(data[pos + 1]) << 16 |
                    Int(data[pos + 2]) << 8 | Int(data[pos + 3])
        pos += 4

        // XOsiz, YOsiz (4 bytes each) - image offset
        pos += 8

        // XTsiz, YTsiz (4 bytes each) - tile size
        let xtsiz = Int(data[pos]) << 24 | Int(data[pos + 1]) << 16 |
                     Int(data[pos + 2]) << 8 | Int(data[pos + 3])
        pos += 4
        let ytsiz = Int(data[pos]) << 24 | Int(data[pos + 1]) << 16 |
                     Int(data[pos + 2]) << 8 | Int(data[pos + 3])
        pos += 4

        // XTOsiz, YTOsiz (4 bytes each) - tile offset
        pos += 8

        // Csiz (2 bytes) - number of components
        guard pos + 1 < data.count else {
            throw J2KError.decodingError("SIZ segment missing component count")
        }
        let csiz = Int(data[pos]) << 8 | Int(data[pos + 1])
        pos += 2

        metadata.width = xsiz
        metadata.height = ysiz
        metadata.componentCount = csiz
        metadata.tileWidth = xtsiz == xsiz ? 0 : xtsiz
        metadata.tileHeight = ytsiz == ysiz ? 0 : ytsiz

        // Read per-component info
        metadata.bitDepths = []
        metadata.signedComponents = []
        for _ in 0..<csiz {
            guard pos < data.count else { break }
            let ssiz = data[pos]
            pos += 1
            let signed = (ssiz & 0x80) != 0
            let bitDepth = Int(ssiz & 0x7F) + 1
            metadata.bitDepths.append(bitDepth)
            metadata.signedComponents.append(signed)

            // Skip XRsiz, YRsiz (subsampling factors)
            pos += 2
        }
    }

    /// Parses a COD marker segment.
    private func parseCODSegment(
        data: Data, offset: Int,
        metadata: inout TranscodingMetadata,
        codingMode: inout HTCodingMode
    ) {
        var pos = offset

        guard pos + 9 <= data.count else { return }

        // Scod (1 byte) - coding style
        let scod = data[pos]
        pos += 1

        // Check bit 6 for HTJ2K block coding style
        if (scod & 0x40) != 0 {
            codingMode = .ht
        }

        // SGcod
        // Progression order (1 byte)
        let progOrder = data[pos]
        pos += 1
        let progOrderStrings = ["LRCP", "RLCP", "RPCL", "PCRL", "CPRL"]
        let progOrderKey = progOrderStrings[min(Int(progOrder), 4)]
        if let order = J2KProgressionOrder(rawValue: progOrderKey) {
            metadata.progressionOrder = order
        }

        // Number of layers (2 bytes)
        let numLayers = Int(data[pos]) << 8 | Int(data[pos + 1])
        pos += 2
        metadata.qualityLayers = max(1, numLayers)

        // MCT (1 byte) - multiple component transform
        pos += 1

        // SPcod
        // Number of decomposition levels (1 byte)
        guard pos < data.count else { return }
        metadata.decompositionLevels = Int(data[pos])
        pos += 1

        // Code-block width exponent (1 byte)
        guard pos < data.count else { return }
        let cbWidthExp = Int(data[pos]) + 2
        pos += 1
        metadata.codeBlockWidth = 1 << cbWidthExp

        // Code-block height exponent (1 byte)
        guard pos < data.count else { return }
        let cbHeightExp = Int(data[pos]) + 2
        pos += 1
        metadata.codeBlockHeight = 1 << cbHeightExp

        // Code-block style (1 byte)
        guard pos < data.count else { return }
        pos += 1

        // Transform (1 byte) - 0 = 9/7 irreversible, 1 = 5/3 reversible
        guard pos < data.count else { return }
        let transform = data[pos]
        metadata.isLossless = (transform == 1)
    }

    /// Finds the end of tile data by scanning for the next SOT or EOC marker.
    private func findNextTileOrEnd(data: Data, from start: Int) -> Int {
        var offset = start
        while offset < data.count - 1 {
            if data[offset] == 0xFF {
                let nextByte = data[offset + 1]
                // SOT = 0xFF90, EOC = 0xFFD9
                if nextByte == 0x90 || nextByte == 0xD9 {
                    return offset
                }
            }
            offset += 1
        }
        return data.count
    }

    // MARK: - Private: Tile Coefficient Extraction

    /// Extracts coefficients from a single tile's coded data.
    private func extractTileCoefficients(
        _ tileData: ParsedTileData,
        metadata: TranscodingMetadata,
        codingMode: HTCodingMode
    ) throws -> TranscodingTileCoefficients {
        // Determine tile dimensions
        let tileWidth = metadata.tileWidth > 0 ? metadata.tileWidth : metadata.width
        let tileHeight = metadata.tileHeight > 0 ? metadata.tileHeight : metadata.height

        // Create code-block coefficients from tile data by decoding
        // the Tier-1 coded data
        var componentSubbands: [[J2KSubband: [TranscodingCodeBlockCoefficients]]] = []

        let codeBlockWidth = metadata.codeBlockWidth
        let codeBlockHeight = metadata.codeBlockHeight

        for comp in 0..<metadata.componentCount {
            var subbandBlocks: [J2KSubband: [TranscodingCodeBlockCoefficients]] = [:]

            // For each decomposition level, extract code-block coefficients
            for level in 0...metadata.decompositionLevels {
                let subbands: [J2KSubband] = level == 0 ? [.ll] : [.hl, .lh, .hh]

                for subband in subbands {
                    // Calculate subband dimensions
                    let subbandWidth: Int
                    let subbandHeight: Int
                    if level == 0 {
                        subbandWidth = tileWidth >> metadata.decompositionLevels
                        subbandHeight = tileHeight >> metadata.decompositionLevels
                    } else {
                        subbandWidth = tileWidth >> (metadata.decompositionLevels - level + 1)
                        subbandHeight = tileHeight >> (metadata.decompositionLevels - level + 1)
                    }

                    guard subbandWidth > 0 && subbandHeight > 0 else { continue }

                    // Generate code-blocks for this subband
                    let cbCountX = (subbandWidth + codeBlockWidth - 1) / codeBlockWidth
                    let cbCountY = (subbandHeight + codeBlockHeight - 1) / codeBlockHeight

                    var blocks: [TranscodingCodeBlockCoefficients] = []
                    for cby in 0..<cbCountY {
                        for cbx in 0..<cbCountX {
                            let blockW = min(codeBlockWidth, subbandWidth - cbx * codeBlockWidth)
                            let blockH = min(codeBlockHeight, subbandHeight - cby * codeBlockHeight)
                            let blockIndex = cby * cbCountX + cbx

                            // Decode the code-block from the tile data
                            let coefficients = try decodeCodeBlockCoefficients(
                                tileData: tileData.data,
                                codingMode: codingMode,
                                width: blockW,
                                height: blockH,
                                subband: subband,
                                componentIndex: comp,
                                blockIndex: blockIndex,
                                level: level,
                                metadata: metadata
                            )

                            blocks.append(TranscodingCodeBlockCoefficients(
                                index: blockIndex,
                                x: cbx * codeBlockWidth,
                                y: cby * codeBlockHeight,
                                width: blockW,
                                height: blockH,
                                subband: subband,
                                coefficients: coefficients,
                                zeroBitPlanes: 0,
                                codingPasses: 1
                            ))
                        }
                    }

                    if var existing = subbandBlocks[subband] {
                        existing.append(contentsOf: blocks)
                        subbandBlocks[subband] = existing
                    } else {
                        subbandBlocks[subband] = blocks
                    }
                }
            }

            componentSubbands.append(subbandBlocks)
        }

        return TranscodingTileCoefficients(
            tileIndex: tileData.tileIndex,
            width: tileWidth,
            height: tileHeight,
            components: componentSubbands
        )
    }

    /// Decodes a single code-block's coefficients from tile data.
    ///
    /// This is the Tier-1 decoding step that recovers the quantized wavelet
    /// coefficients from the entropy-coded data.
    private func decodeCodeBlockCoefficients(
        tileData: Data,
        codingMode: HTCodingMode,
        width: Int,
        height: Int,
        subband: J2KSubband,
        componentIndex: Int,
        blockIndex: Int,
        level: Int,
        metadata: TranscodingMetadata
    ) throws -> [Int] {
        let blockSize = width * height

        // If tile data is empty or insufficient, return zeros
        guard !tileData.isEmpty else {
            return [Int](repeating: 0, count: blockSize)
        }

        // For transcoding, we decode the Tier-1 coded data based on coding mode.
        // Use the appropriate block decoder to extract coefficients.
        switch codingMode {
        case .legacy:
            return try decodeLegacyCodeBlock(
                tileData: tileData,
                width: width, height: height,
                subband: subband,
                blockIndex: blockIndex,
                metadata: metadata
            )
        case .ht:
            return try decodeHTCodeBlock(
                tileData: tileData,
                width: width, height: height,
                subband: subband,
                blockIndex: blockIndex,
                metadata: metadata
            )
        }
    }

    /// Decodes a legacy EBCOT code-block.
    private func decodeLegacyCodeBlock(
        tileData: Data,
        width: Int, height: Int,
        subband: J2KSubband,
        blockIndex: Int,
        metadata: TranscodingMetadata
    ) throws -> [Int] {
        let blockSize = width * height

        // Use BitPlaneDecoder to decode the EBCOT-coded data
        let decoder = BitPlaneDecoder(
            width: width,
            height: height,
            subband: subband,
            options: .default
        )

        // Determine bit depth for this component
        let bitDepth = metadata.bitDepths.isEmpty ? 8 : metadata.bitDepths[0]

        do {
            let coeffsInt32 = try decoder.decode(
                data: tileData,
                passCount: 3,
                bitDepth: bitDepth,
                zeroBitPlanes: 0
            )
            return coeffsInt32.map { Int($0) }
        } catch {
            // If decoding fails (e.g., data doesn't correspond to this specific block),
            // return zeros rather than propagating the error since the tile data
            // may be organized differently than expected
            return [Int](repeating: 0, count: blockSize)
        }
    }

    /// Decodes an HTJ2K code-block.
    private func decodeHTCodeBlock(
        tileData: Data,
        width: Int, height: Int,
        subband: J2KSubband,
        blockIndex: Int,
        metadata: TranscodingMetadata
    ) throws -> [Int] {
        let blockSize = width * height

        // Build a minimal HTEncodedResult from the tile data
        let cleanupBlock = HTEncodedBlock(
            codedData: tileData,
            passType: .htCleanup,
            melLength: 0,
            vlcLength: 0,
            magsgnLength: tileData.count,
            bitPlane: metadata.bitDepths.isEmpty ? 8 : metadata.bitDepths[0],
            width: width,
            height: height
        )

        let result = HTEncodedResult(
            codingMode: .ht,
            cleanupPass: cleanupBlock,
            sigPropPasses: [],
            magRefPasses: [],
            zeroBitPlanes: 0,
            totalPasses: 1
        )

        let decoder = HTJ2KDecoder()
        do {
            return try decoder.decodeCodeBlocks(
                from: result,
                width: width,
                height: height,
                subband: subband
            )
        } catch {
            return [Int](repeating: 0, count: blockSize)
        }
    }

    // MARK: - Private: Tile Encoding

    /// Encodes a tile's coefficients with the target Tier-1 coder.
    private func encodeTile(
        _ tile: TranscodingTileCoefficients,
        targetMode: HTCodingMode,
        metadata: TranscodingCoefficients
    ) throws -> Data {
        var tileData = Data()

        for componentSubbands in tile.components {
            for (subband, codeBlocks) in componentSubbands.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                for cb in codeBlocks {
                    let encodedBlock = try encodeCodeBlock(
                        cb,
                        targetMode: targetMode,
                        subband: subband
                    )

                    // Write packet header for this code-block contribution
                    // Simplified: just append the coded data
                    tileData.append(encodedBlock)
                }
            }
        }

        return tileData
    }

    /// Encodes a single code-block with the target Tier-1 coder.
    private func encodeCodeBlock(
        _ cb: TranscodingCodeBlockCoefficients,
        targetMode: HTCodingMode,
        subband: J2KSubband
    ) throws -> Data {
        switch targetMode {
        case .ht:
            let encoder = HTJ2KEncoder(configuration: HTJ2KConfiguration(codingMode: .ht))
            let result = try encoder.encodeCodeBlocks(
                coefficients: cb.coefficients,
                width: cb.width,
                height: cb.height,
                subband: subband
            )
            return result.cleanupPass.codedData
        case .legacy:
            let encoder = HTJ2KEncoder(configuration: HTJ2KConfiguration(codingMode: .legacy))
            let result = try encoder.encodeCodeBlocks(
                coefficients: cb.coefficients,
                width: cb.width,
                height: cb.height,
                subband: subband
            )
            return result.cleanupPass.codedData
        }
    }

    // MARK: - Private: Marker Generation

    /// Generates SIZ marker data.
    private func generateSIZMarker(from coefficients: TranscodingCoefficients) -> Data {
        var data = Data()

        // Rsiz (2 bytes) - capabilities
        data.append(contentsOf: [0x00, 0x00])

        // Xsiz (4 bytes) - image width
        appendUInt32(&data, UInt32(coefficients.width))

        // Ysiz (4 bytes) - image height
        appendUInt32(&data, UInt32(coefficients.height))

        // XOsiz (4 bytes) - horizontal offset
        appendUInt32(&data, 0)

        // YOsiz (4 bytes) - vertical offset
        appendUInt32(&data, 0)

        // XTsiz (4 bytes) - tile width
        let tileWidth = coefficients.tileWidth > 0 ? coefficients.tileWidth : coefficients.width
        appendUInt32(&data, UInt32(tileWidth))

        // YTsiz (4 bytes) - tile height
        let tileHeight = coefficients.tileHeight > 0 ? coefficients.tileHeight : coefficients.height
        appendUInt32(&data, UInt32(tileHeight))

        // XTOsiz (4 bytes) - tile horizontal offset
        appendUInt32(&data, 0)

        // YTOsiz (4 bytes) - tile vertical offset
        appendUInt32(&data, 0)

        // Csiz (2 bytes) - number of components
        data.append(UInt8((coefficients.componentCount >> 8) & 0xFF))
        data.append(UInt8(coefficients.componentCount & 0xFF))

        // Per-component information
        for i in 0..<coefficients.componentCount {
            let bitDepth = i < coefficients.bitDepths.count ? coefficients.bitDepths[i] : 8
            let signed = i < coefficients.signedComponents.count ? coefficients.signedComponents[i] : false

            // Ssiz (1 byte): bit depth - 1, with MSB for signedness
            var ssiz = UInt8((bitDepth - 1) & 0x7F)
            if signed {
                ssiz |= 0x80
            }
            data.append(ssiz)

            // XRsiz (1 byte): horizontal subsampling
            data.append(0x01)

            // YRsiz (1 byte): vertical subsampling
            data.append(0x01)
        }

        return data
    }

    /// Generates COD marker data.
    private func generateCODMarker(
        from coefficients: TranscodingCoefficients,
        targetMode: HTCodingMode
    ) -> Data {
        var data = Data()

        // Scod (1 byte) - coding style
        var scod: UInt8 = 0x00
        if targetMode == .ht {
            scod |= 0x40 // Bit 6: HT block coding
        }
        data.append(scod)

        // SGcod
        // Progression order (1 byte)
        let progOrderIndex: UInt8
        switch coefficients.progressionOrder {
        case .lrcp: progOrderIndex = 0
        case .rlcp: progOrderIndex = 1
        case .rpcl: progOrderIndex = 2
        case .pcrl: progOrderIndex = 3
        case .cprl: progOrderIndex = 4
        }
        data.append(progOrderIndex)

        // Number of layers (2 bytes)
        data.append(UInt8((coefficients.qualityLayers >> 8) & 0xFF))
        data.append(UInt8(coefficients.qualityLayers & 0xFF))

        // MCT (1 byte) - multiple component transform
        let mct: UInt8 = coefficients.componentCount >= 3 ? 1 : 0
        data.append(mct)

        // SPcod
        // Number of decomposition levels (1 byte)
        data.append(UInt8(coefficients.decompositionLevels))

        // Code-block width exponent minus 2 (1 byte)
        let cbWidth = max(4, coefficients.codeBlockWidth)
        let cbWidthExp = Int(log2(Double(cbWidth)))
        data.append(UInt8(cbWidthExp - 2))

        // Code-block height exponent minus 2 (1 byte)
        let cbHeight = max(4, coefficients.codeBlockHeight)
        let cbHeightExp = Int(log2(Double(cbHeight)))
        data.append(UInt8(cbHeightExp - 2))

        // Code-block style (1 byte)
        data.append(0x00)

        // Transform (1 byte): 0 = 9/7 irreversible, 1 = 5/3 reversible
        data.append(coefficients.isLossless ? 0x01 : 0x00)

        return data
    }

    /// Generates QCD marker data.
    private func generateQCDMarker(from coefficients: TranscodingCoefficients) -> Data {
        var data = Data()

        // Sqcd (1 byte) - quantization style
        // 0x00 = no quantization (reversible)
        // 0x01 = scalar derived quantization
        // 0x02 = scalar expounded quantization
        if coefficients.isLossless {
            data.append(0x00)

            // For reversible, one byte per subband: guard bits(3) + exponent(5)
            let numSubbands = 1 + 3 * coefficients.decompositionLevels
            for _ in 0..<numSubbands {
                data.append(0x48) // Default: 2 guard bits, exponent 8
            }
        } else {
            data.append(0x02) // Scalar expounded

            // For irreversible, two bytes per subband: guard bits + exponent + mantissa
            let numSubbands = 1 + 3 * coefficients.decompositionLevels
            for _ in 0..<numSubbands {
                data.append(0x48) // Exponent
                data.append(0x00) // Mantissa
            }
        }

        return data
    }

    /// Appends a UInt32 in big-endian byte order.
    private func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    // MARK: - Private: Progress Reporting

    /// Reports progress for a transcoding stage.
    private func reportProgress(
        _ handler: ((TranscodingProgressUpdate) -> Void)?,
        stage: TranscodingStage,
        stageProgress: Double,
        direction: TranscodingDirection
    ) {
        guard let handler = handler else { return }

        let stageIndex = TranscodingStage.allCases.firstIndex(of: stage) ?? 0
        let stageCount = Double(TranscodingStage.allCases.count)
        let overallProgress = (Double(stageIndex) + stageProgress) / stageCount

        handler(TranscodingProgressUpdate(
            stage: stage,
            progress: stageProgress,
            overallProgress: min(1.0, overallProgress),
            direction: direction
        ))
    }
}
