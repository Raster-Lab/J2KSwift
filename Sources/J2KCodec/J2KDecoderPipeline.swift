//
// J2KDecoderPipeline.swift
// J2KSwift
//
// J2KDecoderPipeline.swift
// J2KSwift
//
// Decoder pipeline implementation for JPEG 2000 decoding.
//

import Foundation
import J2KCore
import J2KMetal

#if canImport(Accelerate)
import Accelerate
#endif

// MARK: - Decoding Stage

/// Represents the stages of the JPEG 2000 decoding pipeline.
public enum DecodingStage: String, Sendable, CaseIterable {
    /// Codestream parsing and marker validation.
    case codestreamParsing = "Codestream Parsing"

    /// Tile data extraction from packets.
    case tileExtraction = "Tile Extraction"

    /// Entropy decoding (EBCOT bit-plane decoding).
    case entropyDecoding = "Entropy Decoding"

    /// Dequantization of wavelet coefficients.
    case dequantization = "Dequantization"

    /// Inverse wavelet transform.
    case inverseWaveletTransform = "Inverse Wavelet Transform"

    /// Inverse colour space transformation.
    case inverseColorTransform = "Inverse Color Transform"

    /// Image reconstruction.
    case imageReconstruction = "Image Reconstruction"
}

// MARK: - Progress Update

/// Reports progress during decoding.
public struct DecoderProgressUpdate: Sendable {
    /// The current decoding stage.
    public let stage: DecodingStage

    /// Progress within the current stage (0.0 to 1.0).
    public let progress: Double

    /// Overall decoding progress (0.0 to 1.0).
    public let overallProgress: Double
}

// MARK: - Decoder Configuration

/// Configuration for the decoder pipeline.
struct DecoderConfiguration: Sendable {
    /// Number of decomposition levels (from COD marker).
    var decompositionLevels: Int = 5

    /// Code block size (from COD marker).
    var codeBlockSize: (width: Int, height: Int) = (32, 32)

    /// Whether to use reversible colour transform.
    var useReversibleTransform: Bool = true

    /// Number of quality layers (from COD marker).
    var qualityLayers: Int = 1

    /// Progression order (from COD marker).
    var progressionOrder: J2KProgressionOrder = .lrcp

    /// Wavelet filter type (from COD marker).
    var waveletFilter: J2KDWT1D.Filter = .reversible53

    /// Whether HTJ2K block coding is used (from COD marker bit 6).
    var useHTJ2K: Bool = false

    /// Per-component DC offset values from DCO marker segment (Part 2).
    ///
    /// When non-nil, the decoder applies these offsets after inverse wavelet
    /// transform to restore original component values.
    var dcOffsets: [J2KDCOffsetValue]?

    /// Extended precision configuration (Part 2).
    ///
    /// Controls guard bit count and rounding mode for coefficient processing.
    var extendedPrecision: J2KExtendedPrecisionConfiguration = .default

    /// Wavelet kernel configuration (Part 2).
    ///
    /// Specifies which wavelet kernels to use per tile-component.
    /// When nil, uses the waveletFilter property for all components.
    var waveletKernelConfiguration: J2KWaveletKernelConfiguration?
}

// MARK: - Codestream Metadata

/// Metadata extracted from codestream markers.
struct CodestreamMetadata: Sendable {
    /// Image width.
    var width: Int

    /// Image height.
    var height: Int

    /// Number of components.
    var componentCount: Int

    /// Component information.
    var components: [ComponentInfo]

    /// Tile size.
    var tileSize: (width: Int, height: Int)

    /// Image offset (XOsiz, YOsiz).
    var imageOffset: (x: Int, y: Int) = (0, 0)

    /// Tile offset (XTOsiz, YTOsiz).
    var tileOffset: (x: Int, y: Int) = (0, 0)

    /// Configuration from COD marker.
    var configuration: DecoderConfiguration

    /// Quantization step sizes from QCD marker.
    var quantizationSteps: [String: Double]

    /// Guard bits from QCD marker Sqcd byte.
    var quantizationGuardBits: Int

    /// Band-level Kb values (number of magnitude bit-planes) per subband.
    /// Keyed by "{subband}_{level}" matching quantizationSteps keys.
    var bandKbValues: [String: Int]

    /// DCO marker segment from codestream (Part 2).
    ///
    /// Present when the codestream contains a DCO marker segment (0xFF5C)
    /// signaling per-component DC offset values.
    var dcoMarkerSegment: J2KDCOMarkerSegment?

    /// Number of tiles in X direction.
    var numTilesX: Int { max(1, (width + tileSize.width - 1) / tileSize.width) }

    /// Number of tiles in Y direction.
    var numTilesY: Int { max(1, (height + tileSize.height - 1) / tileSize.height) }

    /// Total number of tiles.
    var totalTiles: Int { numTilesX * numTilesY }

    /// Whether this is a multi-tile codestream.
    var isMultiTile: Bool { totalTiles > 1 }

    /// Returns the actual dimensions for a given tile index, accounting for edge tiles.
    func tileDimensions(tileIndex: Int) -> (x: Int, y: Int, width: Int, height: Int) {
        let col = tileIndex % numTilesX
        let row = tileIndex / numTilesX
        let x0 = col * tileSize.width
        let y0 = row * tileSize.height
        let w = min(tileSize.width, width - x0)
        let h = min(tileSize.height, height - y0)
        return (x0, y0, w, h)
    }

    struct ComponentInfo: Sendable {
        var bitDepth: Int
        var signed: Bool
        var subsamplingX: Int
        var subsamplingY: Int
    }
}

// MARK: - Decoder Pipeline

/// Internal decoding pipeline that connects all JPEG 2000 decoding components.
///
/// The pipeline processes a codestream through these stages:
/// 1. Codestream Parsing — parse markers and extract metadata
/// 2. Tile Extraction — extract tile data from packets
/// 3. Entropy Decoding — EBCOT bit-plane decoding per code block
/// 4. Dequantization — convert integer indices to coefficients
/// 5. Inverse Wavelet Transform — multi-level 2D IDWT reconstruction
/// 6. Inverse Colour Transform — YCbCr → RGB conversion
/// 7. Image Reconstruction — assemble final image
struct DecoderPipeline: Sendable {
    /// Decodes a JPEG 2000 codestream through the full pipeline.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data.
    ///   - progress: Optional progress callback.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    func decode(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)? = nil
    ) throws -> J2KImage {
        // Stage 1: Parse codestream and extract metadata
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 0.0)
        let (metadata, tiles) = try parseCodestream(data)
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 1.0)

        if metadata.isMultiTile {
            return try decodeMultiTile(metadata: metadata, tiles: tiles, progress: progress)
        } else {
            let tileData = tiles.first?.tileData ?? Data()
            return try decodeSingleTile(metadata: metadata, tileData: tileData, progress: progress)
        }
    }

    // MARK: - GPU-Accelerated Decode

    /// Decodes a JPEG 2000 codestream using GPU-accelerated inverse DWT.
    ///
    /// Uses Metal GPU for the inverse wavelet transform and colour transform
    /// stages when available. Falls back to CPU implementations when Metal is
    /// unavailable (e.g. Linux, CI servers without GPU).
    ///
    /// HTJ2K block decoding (when signaled via COD marker bit 6) always runs
    /// on CPU using the FBCOT algorithm.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data.
    ///   - progress: Optional progress callback.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    func decodeGPU(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)? = nil
    ) async throws -> J2KImage {
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 0.0)
        let (metadata, tiles) = try parseCodestream(data)
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 1.0)

        if metadata.isMultiTile {
            return try await decodeMultiTileGPU(metadata: metadata, tiles: tiles, progress: progress)
        } else {
            let tileData = tiles.first?.tileData ?? Data()
            return try await decodeSingleTileGPU(metadata: metadata, tileData: tileData, progress: progress)
        }
    }

    /// GPU-accelerated single-tile decode.
    private func decodeSingleTileGPU(
        metadata: CodestreamMetadata,
        tileData: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        // Stages 2-4: same as CPU path
        reportProgress(progress, stage: .tileExtraction, stageProgress: 0.0)
        let codeBlocks = try extractTileData(tileData, metadata: metadata)
        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        reportProgress(progress, stage: .entropyDecoding, stageProgress: 0.0)
        let decodedBlocks = try applyEntropyDecoding(codeBlocks, metadata: metadata)
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 1.0)

        reportProgress(progress, stage: .dequantization, stageProgress: 0.0)
        let dequantizedSubbands = try applyDequantization(decodedBlocks, metadata: metadata)
        reportProgress(progress, stage: .dequantization, stageProgress: 1.0)

        // Stage 5: GPU inverse wavelet transform
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 0.0)
        let spatialData = try await applyInverseWaveletTransformGPU(dequantizedSubbands, metadata: metadata)
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 1.0)

        // Stages 6-7: GPU inverse colour transform
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        var rgbData = try await applyInverseColorTransformGPU(spatialData, metadata: metadata)
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 1.0)

        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < rgbData.count else { break }
            if !compInfo.signed {
                let dcOffset = Double(1 << (compInfo.bitDepth - 1))
                rgbData[compIdx] = rgbData[compIdx].map { $0 + dcOffset }
            }
        }

        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        let image = try reconstructImage(rgbData, metadata: metadata)
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)
        return image
    }

    /// GPU-accelerated multi-tile decode.
    private func decodeMultiTileGPU(
        metadata: CodestreamMetadata,
        tiles: [(tileIndex: Int, tileData: Data)],
        progress: ((DecoderProgressUpdate) -> Void)?
    ) async throws -> J2KImage {
        let numComponents = metadata.componentCount
        var fullComponents: [[Double]] = (0..<numComponents).map { compIdx in
            let compInfo = metadata.components[compIdx]
            let w = metadata.width / compInfo.subsamplingX
            let h = metadata.height / compInfo.subsamplingY
            return [Double](repeating: 0.0, count: w * h)
        }

        for (tileIdx, tile) in tiles.enumerated() {
            let tileProgress = Double(tileIdx) / Double(tiles.count)
            reportProgress(progress, stage: .tileExtraction, stageProgress: tileProgress)

            let (tileX, tileY, tileW, tileH) = metadata.tileDimensions(tileIndex: tile.tileIndex)

            var tileMeta = metadata
            tileMeta.width = tileW
            tileMeta.height = tileH
            tileMeta.tileSize = (width: tileW, height: tileH)

            let codeBlocks = try extractTileData(tile.tileData, metadata: tileMeta)
            let decodedBlocks = try applyEntropyDecoding(codeBlocks, metadata: tileMeta)
            let dequantizedSubbands = try applyDequantization(decodedBlocks, metadata: tileMeta)

            // GPU inverse wavelet transform for this tile
            let spatialData = try await applyInverseWaveletTransformGPU(dequantizedSubbands, metadata: tileMeta)
            var tileRGB = try await applyInverseColorTransformGPU(spatialData, metadata: tileMeta)

            for (compIdx, compInfo) in metadata.components.enumerated() {
                guard compIdx < tileRGB.count else { break }
                if !compInfo.signed {
                    let dcOffset = Double(1 << (compInfo.bitDepth - 1))
                    tileRGB[compIdx] = tileRGB[compIdx].map { $0 + dcOffset }
                }
            }

            for compIdx in 0..<min(numComponents, tileRGB.count) {
                let compInfo = metadata.components[compIdx]
                let fullW = metadata.width / compInfo.subsamplingX
                let compTileX = tileX / compInfo.subsamplingX
                let compTileY = tileY / compInfo.subsamplingY
                let compTileW = tileW / compInfo.subsamplingX
                let compTileH = tileH / compInfo.subsamplingY

                let tileCompData = tileRGB[compIdx]
                for row in 0..<compTileH {
                    let dstOffset = (compTileY + row) * fullW + compTileX
                    let srcOffset = row * compTileW
                    for col in 0..<compTileW {
                        if srcOffset + col < tileCompData.count {
                            fullComponents[compIdx][dstOffset + col] = tileCompData[srcOffset + col]
                        }
                    }
                }
            }
        }

        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        let image = try reconstructImage(fullComponents, metadata: metadata)
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)
        return image
    }

    /// Decodes a single-tile codestream (original path).
    private func decodeSingleTile(
        metadata: CodestreamMetadata,
        tileData: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) throws -> J2KImage {
        // Stage 2: Extract tile data
        reportProgress(progress, stage: .tileExtraction, stageProgress: 0.0)
        let codeBlocks = try extractTileData(tileData, metadata: metadata)
        reportProgress(progress, stage: .tileExtraction, stageProgress: 1.0)

        // Stage 3: Entropy decoding
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 0.0)
        let decodedBlocks = try applyEntropyDecoding(codeBlocks, metadata: metadata)
        reportProgress(progress, stage: .entropyDecoding, stageProgress: 1.0)

        // Stage 4: Dequantization
        reportProgress(progress, stage: .dequantization, stageProgress: 0.0)
        let dequantizedSubbands = try applyDequantization(decodedBlocks, metadata: metadata)
        reportProgress(progress, stage: .dequantization, stageProgress: 1.0)

        // Stage 5: Inverse wavelet transform
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 0.0)
        let spatialData = try applyInverseWaveletTransform(dequantizedSubbands, metadata: metadata)
        reportProgress(progress, stage: .inverseWaveletTransform, stageProgress: 1.0)

        // Stage 6: Inverse colour transform
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        var rgbData = try applyInverseColorTransform(spatialData, metadata: metadata)
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 1.0)

        // DC level unshift: for unsigned components, add back 2^(bitDepth-1)
        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < rgbData.count else { break }
            if !compInfo.signed {
                let dcOffset = Double(1 << (compInfo.bitDepth - 1))
                rgbData[compIdx].withUnsafeMutableBufferPointer { buf in
                    for i in 0..<buf.count {
                        buf[i] += dcOffset
                    }
                }
            }
        }

        // Stage 7: Image reconstruction
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        let image = try reconstructImage(rgbData, metadata: metadata)
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)

        return image
    }

    /// Decodes a multi-tile codestream by processing each tile independently
    /// and assembling the results into the full image.
    private func decodeMultiTile(
        metadata: CodestreamMetadata,
        tiles: [(tileIndex: Int, tileData: Data)],
        progress: ((DecoderProgressUpdate) -> Void)?
    ) throws -> J2KImage {
        let numComponents = metadata.componentCount

        // Prepare full-image component buffers
        var fullComponents: [[Double]] = (0..<numComponents).map { compIdx in
            let compInfo = metadata.components[compIdx]
            let w = metadata.width / compInfo.subsamplingX
            let h = metadata.height / compInfo.subsamplingY
            return [Double](repeating: 0.0, count: w * h)
        }

        // Process each tile
        for (tileIdx, tile) in tiles.enumerated() {
            let tileProgress = Double(tileIdx) / Double(tiles.count)
            reportProgress(progress, stage: .tileExtraction, stageProgress: tileProgress)

            let (tileX, tileY, tileW, tileH) = metadata.tileDimensions(tileIndex: tile.tileIndex)

            // Create tile-specific metadata with tile dimensions as the "image" dimensions
            var tileMeta = metadata
            tileMeta.width = tileW
            tileMeta.height = tileH
            // For tile processing, tileSize should be the actual tile dimensions
            tileMeta.tileSize = (width: tileW, height: tileH)

            // Stage 2-4: Extract, entropy decode, dequantize for this tile
            let codeBlocks = try extractTileData(tile.tileData, metadata: tileMeta)
            let decodedBlocks = try applyEntropyDecoding(codeBlocks, metadata: tileMeta)
            let dequantizedSubbands = try applyDequantization(decodedBlocks, metadata: tileMeta)

            // Stage 5: Inverse wavelet transform for this tile
            let spatialData = try applyInverseWaveletTransform(dequantizedSubbands, metadata: tileMeta)

            // Stage 6: Inverse colour transform for this tile
            var tileRGB = try applyInverseColorTransform(spatialData, metadata: tileMeta)

            // DC level unshift for this tile
            for (compIdx, compInfo) in metadata.components.enumerated() {
                guard compIdx < tileRGB.count else { break }
                if !compInfo.signed {
                    let dcOffset = Double(1 << (compInfo.bitDepth - 1))
                    tileRGB[compIdx] = tileRGB[compIdx].map { $0 + dcOffset }
                }
            }

            // Place tile data into full image buffers
            for compIdx in 0..<min(numComponents, tileRGB.count) {
                let compInfo = metadata.components[compIdx]
                let fullW = metadata.width / compInfo.subsamplingX
                let compTileX = tileX / compInfo.subsamplingX
                let compTileY = tileY / compInfo.subsamplingY
                let compTileW = tileW / compInfo.subsamplingX
                let compTileH = tileH / compInfo.subsamplingY

                let tileCompData = tileRGB[compIdx]
                for row in 0..<compTileH {
                    let dstOffset = (compTileY + row) * fullW + compTileX
                    let srcOffset = row * compTileW
                    for col in 0..<compTileW {
                        if srcOffset + col < tileCompData.count {
                            fullComponents[compIdx][dstOffset + col] = tileCompData[srcOffset + col]
                        }
                    }
                }
            }
        }

        // Stage 7: Reconstruct final image
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        let image = try reconstructImage(fullComponents, metadata: metadata)
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)

        return image
    }

    // MARK: - Stage 1: Codestream Parsing

    /// Parses the JPEG 2000 codestream and extracts metadata and tile data.
    private func parseCodestream(_ data: Data) throws -> (CodestreamMetadata, [(tileIndex: Int, tileData: Data)]) {
        var reader = J2KBitReader(data: data)

        // Verify SOC marker
        guard try reader.readMarker() == J2KMarker.soc.rawValue else {
            throw J2KError.decodingError("Invalid codestream: missing SOC marker")
        }

        var metadata: CodestreamMetadata?
        var configuration = DecoderConfiguration()
        var quantizationSteps: (steps: [String: Double], guardBits: Int, bandKb: [String: Int]) = ([:], 2, [:])
        var tiles: [(tileIndex: Int, tileData: Data)] = []

        // Parse main header markers
        while reader.position < data.count {
            let marker = try reader.readMarker()

            switch marker {
            case J2KMarker.siz.rawValue:
                // Parse SIZ marker
                metadata = try parseSIZMarker(&reader)

            case J2KMarker.cod.rawValue:
                // Parse COD marker
                configuration = try parseCODMarker(&reader)

            case J2KMarker.qcd.rawValue:
                // Parse QCD marker
                let bitDepth = metadata?.components.first?.bitDepth ?? 8
                quantizationSteps = try parseQCDMarker(&reader, config: configuration, bitDepth: bitDepth)
            case J2KMarker.sot.rawValue:
                // Start of tile-part — collect all tiles
                let (tileIndex, tilepartData) = try parseSOTMarker(&reader)
                tiles.append((tileIndex: tileIndex, tileData: tilepartData))

            case J2KMarker.eoc.rawValue:
                // End of codestream
                break

            default:
                // Skip unknown marker segment
                if marker >= 0xFF30 {
                    let length = Int(try reader.readUInt16())
                    if length > 2 {
                        try reader.skip(length - 2)
                    }
                }
            }

            if marker == J2KMarker.eoc.rawValue {
                break
            }
        }

        guard var meta = metadata else {
            throw J2KError.decodingError("Missing SIZ marker in codestream")
        }

        meta.configuration = configuration
        meta.quantizationSteps = quantizationSteps.steps
        meta.quantizationGuardBits = quantizationSteps.guardBits
        meta.bandKbValues = quantizationSteps.bandKb

        // If no tiles were found via SOT, but we have remaining data,
        // treat everything after the main header as a single tile
        if tiles.isEmpty {
            // Calculate remaining data after main header
            let remaining = data.subdata(in: reader.position..<data.count)
            if !remaining.isEmpty {
                tiles.append((tileIndex: 0, tileData: remaining))
            }
        }

        return (meta, tiles)
    }

    /// Parses the SIZ marker segment.
    private func parseSIZMarker(_ reader: inout J2KBitReader) throws -> CodestreamMetadata {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        // Rsiz — Capabilities
        _ = try reader.readUInt16()

        // Image dimensions
        let width = Int(try reader.readUInt32())
        let height = Int(try reader.readUInt32())

        // Image offset
        let xOsiz = Int(try reader.readUInt32())
        let yOsiz = Int(try reader.readUInt32())

        // Tile dimensions
        let tileWidth = Int(try reader.readUInt32())
        let tileHeight = Int(try reader.readUInt32())

        // Tile offset
        let xtOsiz = Int(try reader.readUInt32())
        let ytOsiz = Int(try reader.readUInt32())

        // Number of components
        let componentCount = Int(try reader.readUInt16())

        // Parse component information
        var components: [CodestreamMetadata.ComponentInfo] = []
        for _ in 0..<componentCount {
            let ssiz = try reader.readUInt8()
            let signed = (ssiz & 0x80) != 0
            let bitDepth = Int((ssiz & 0x7F)) + 1
            let subsamplingX = Int(try reader.readUInt8())
            let subsamplingY = Int(try reader.readUInt8())

            components.append(CodestreamMetadata.ComponentInfo(
                bitDepth: bitDepth,
                signed: signed,
                subsamplingX: subsamplingX,
                subsamplingY: subsamplingY
            ))
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return CodestreamMetadata(
            width: width,
            height: height,
            componentCount: componentCount,
            components: components,
            tileSize: (width: tileWidth, height: tileHeight),
            imageOffset: (x: xOsiz, y: yOsiz),
            tileOffset: (x: xtOsiz, y: ytOsiz),
            configuration: DecoderConfiguration(),
            quantizationSteps: [:],
            quantizationGuardBits: 2,
            bandKbValues: [:]
        )
    }

    /// Parses the COD marker segment.
    private func parseCODMarker(_ reader: inout J2KBitReader) throws -> DecoderConfiguration {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        var config = DecoderConfiguration()

        // Scod — Coding style flags
        let scod = try reader.readUInt8()
        // Bits 3-4: HT set extensions (legacy non-standard; current encoder
        // no longer sets these, but decode them for backward compatibility).
        let htSetBits = (scod >> 3) & 0x03
        let hasHTSets = htSetBits != 0

        // Progression order
        let progOrder = try reader.readUInt8()
        switch progOrder {
        case 0: config.progressionOrder = .lrcp
        case 1: config.progressionOrder = .rlcp
        case 2: config.progressionOrder = .rpcl
        case 3: config.progressionOrder = .pcrl
        case 4: config.progressionOrder = .cprl
        default: config.progressionOrder = .lrcp
        }

        // Number of layers
        config.qualityLayers = Int(try reader.readUInt16())

        // Multiple component transform
        let mct = try reader.readUInt8()
        config.useReversibleTransform = (mct == 1)

        // Number of decomposition levels
        config.decompositionLevels = Int(try reader.readUInt8())

        // Code-block dimensions
        let cbWidthExp = Int(try reader.readUInt8()) + 2
        let cbHeightExp = Int(try reader.readUInt8()) + 2
        config.codeBlockSize = (width: 1 << cbWidthExp, height: 1 << cbHeightExp)

        // Code-block style
        // Bit 6: HT block coding (1 = HTJ2K, 0 = legacy EBCOT)
        let codeBlockStyle = try reader.readUInt8()
        config.useHTJ2K = (codeBlockStyle & 0x40) != 0

        // Wavelet transform type
        let transformType = try reader.readUInt8()
        config.waveletFilter = (transformType == 1) ? .reversible53 : .irreversible97

        // HT set parameters (ISO/IEC 15444-15) — only when bits 3-4 of Scod are non-zero
        // If HT sets are signaled, the configuration byte must be read regardless of useHTJ2K flag
        if hasHTSets {
            // Read HT set configuration byte
            _ = try reader.readUInt8()
            // We read and ignore for now - parameters are advisory
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return config
    }

    /// Parses the COC marker segment (Coding Style Component).
    ///
    /// The COC marker provides per-component coding parameters that override
    /// the default COD parameters for a specific component.
    ///
    /// - Parameters:
    ///   - reader: The bit reader to read from.
    ///   - componentCount: Total number of components in the image.
    ///   - baseConfig: The base configuration from COD marker.
    /// - Returns: A tuple of (component index, component-specific configuration).
    private func parseCOCMarker(
        _ reader: inout J2KBitReader,
        componentCount: Int,
        baseConfig: DecoderConfiguration
    ) throws -> (componentIndex: Int, config: DecoderConfiguration) {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        // Start with base configuration
        var config = baseConfig

        // Ccoc — Component index
        let componentIndex: Int
        if componentCount < 257 {
            // 1 byte for component index
            componentIndex = Int(try reader.readUInt8())
        } else {
            // 2 bytes for component index
            componentIndex = Int(try reader.readUInt16())
        }

        // Scoc — Coding style for this component

        // Number of decomposition levels
        config.decompositionLevels = Int(try reader.readUInt8())

        // Code-block dimensions
        let cbWidthExp = Int(try reader.readUInt8()) + 2
        let cbHeightExp = Int(try reader.readUInt8()) + 2
        config.codeBlockSize = (width: 1 << cbWidthExp, height: 1 << cbHeightExp)

        // Code-block style
        // Bit 6: HT block coding (1 = HTJ2K, 0 = legacy EBCOT)
        let codeBlockStyle = try reader.readUInt8()
        config.useHTJ2K = (codeBlockStyle & 0x40) != 0

        // Wavelet transform type
        let transformType = try reader.readUInt8()
        config.waveletFilter = (transformType == 1) ? .reversible53 : .irreversible97

        // HT set parameters (ISO/IEC 15444-15) — only when HTJ2K is enabled
        // Note: COC doesn't have its own Scod, so we check if HTJ2K mode is set
        if config.useHTJ2K {
            // Check if there's enough data left to read HT set configuration byte
            let currentBytesRead = reader.position - startPos
            if currentBytesRead < length - 2 {
                // Read HT set configuration byte
                _ = try reader.readUInt8()
                // We read and ignore for now - parameters are advisory
            }
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return (componentIndex, config)
    }

    /// Parses the QCD marker segment.
    private func parseQCDMarker(
        _ reader: inout J2KBitReader,
        config: DecoderConfiguration,
        bitDepth: Int = 8
    ) throws -> (steps: [String: Double], guardBits: Int, bandKb: [String: Int]) {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position

        var stepSizes: [String: Double] = [:]
        var bandKb: [String: Int] = [:]

        // Sqcd — Quantization style
        let sqcd = try reader.readUInt8()
        let quantStyle = sqcd & 0x1F
        let guardBits = Int((sqcd >> 5) & 0x07)

        if quantStyle == 0 {
            // No quantization (reversible) — step size is 1.0
            // Read exponent values (used only for Kb computation)
            let llExp = Int(try reader.readUInt8() >> 3)
            stepSizes["LL_0"] = 1.0
            bandKb["LL_0"] = llExp + guardBits - 1  // Kb = εb + Gb - 1

            if config.decompositionLevels > 0 {
                for level in 1...config.decompositionLevels {
                    for subband in ["HL", "LH", "HH"] {
                        let exp = Int(try reader.readUInt8() >> 3)
                        stepSizes["\(subband)_\(level)"] = 1.0
                        bandKb["\(subband)_\(level)"] = exp + guardBits - 1  // Kb = εb + Gb - 1
                    }
                }
            }
        } else if quantStyle == 2 {
            // Scalar expounded quantization
            // Per ISO 15444-1 Eq. E.3:
            //   Δ_b = 2^(R_b - ε_b) × (1 + μ_b / 2^11)
            // where R_b = bitDepth + subbandGain (Eq. E.4)
            // Guard bits are NOT part of R_b — they only affect M_b (Eq. E.2)
            let baseRangeBits = bitDepth

            func decodeStepSize(_ value: UInt16, subbandGain: Int) -> Double {
                let exp = Int((value >> 11) & 0x1F)
                let mant = Double(value & 0x7FF)
                let rangeBits = baseRangeBits + subbandGain
                return pow(2.0, Double(rangeBits - exp)) * (1.0 + mant / 2048.0)
            }

            // LL subband (gain = 0)
            let llValue = try reader.readUInt16()
            let llExp = Int((llValue >> 11) & 0x1F)
            stepSizes["LL_0"] = decodeStepSize(llValue, subbandGain: 0)
            bandKb["LL_0"] = llExp + guardBits - 1  // Kb = εb + Gb - 1

            if config.decompositionLevels > 0 {
                for level in 1...config.decompositionLevels {
                    for subband in ["HL", "LH", "HH"] {
                        let value = try reader.readUInt16()
                        let exp = Int((value >> 11) & 0x1F)
                        // Use standard subband gains for Rb (ISO 15444-1 Eq. E.4).
                        // This is correct for our inverse DWT which uses standard invK.
                        // (OPJ uses gain=0 here but compensates with two_invK in its IDWT.)
                        let gain: Int = (subband == "HH") ? 2 : 1
                        stepSizes["\(subband)_\(level)"] = decodeStepSize(value, subbandGain: gain)
                        bandKb["\(subband)_\(level)"] = exp + guardBits - 1  // Kb = εb + Gb - 1
                    }
                }
            }
        }

        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }

        return (steps: stepSizes, guardBits: guardBits, bandKb: bandKb)
    }

    /// Parses the SOT marker segment and extracts tile data.
    private func parseSOTMarker(_ reader: inout J2KBitReader) throws -> (Int, Data) {
        _ = Int(try reader.readUInt16())

        // Isot — Tile index
        let tileIndex = Int(try reader.readUInt16())

        // Psot — Tile-part length
        let tilepartLength = Int(try reader.readUInt32())

        // TPsot — Tile-part index
        _ = try reader.readUInt8()

        // TNsot — Number of tile-parts
        _ = try reader.readUInt8()

        // Find SOD marker
        guard try reader.readMarker() == J2KMarker.sod.rawValue else {
            throw J2KError.decodingError("Missing SOD marker after SOT")
        }

        // Calculate data length
        // tilepartLength includes SOT marker (2) + length (2) + segment (8) + SOD marker (2)
        let dataLength = tilepartLength - 14

        // Extract tile data
        let tileData = try reader.readBytes(dataLength)

        return (tileIndex, tileData)
    }

    // MARK: - Stage 2: Tile Extraction

    /// Information about a code block extracted from tile data.
    struct CodeBlockInfo: Sendable {
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let data: Data
        let passCount: Int
        let zeroBitPlanes: Int
        let bandKb: Int
    }

    /// Extracts code blocks from tile data using ISO/IEC 15444-1 packet format.
    ///
    /// Parses packet headers using tag trees for code-block inclusion and
    /// zero bit-planes, Table B.4 for coding passes, and Lblock for data lengths.
    private func extractTileData(
        _ tileData: Data,
        metadata: CodestreamMetadata
    ) throws -> [CodeBlockInfo] {
        var blocks: [CodeBlockInfo] = []

        let cbWidth = metadata.configuration.codeBlockSize.width
        let cbHeight = metadata.configuration.codeBlockSize.height
        let levels = metadata.configuration.decompositionLevels
        let tileWidth = metadata.tileSize.width
        let tileHeight = metadata.tileSize.height
        let numComponents = metadata.components.count
        var reader = J2KBitReader(data: tileData)
        // Enable JPEG 2000 byte stuffing for packet headers (ISO 15444-1 B.10.1)
        reader.setByteStuffing(true)

        // LRCP progression: Layer → Resolution → Component → Position
        // Single layer for now
        for resLevel in 0...levels {
            for compIdx in 0..<numComponents {
                // Read non-empty packet flag
                guard reader.bytesRemaining > 0 || reader.bitOffset > 0 else { break }
                let notEmpty = try reader.readBit()
                guard notEmpty else {
                    // Empty packet: align to byte boundary per ISO 15444-1 B.10.
                    // Each packet starts on a byte boundary. The encoder writes the
                    // empty flag bit and then pads to the next byte boundary.
                    try reader.alignToByte()
                    continue
                }

                let subbands: [J2KSubband] = resLevel == 0 ? [.ll] : [.hl, .lh, .hh]

                // Track included blocks for data extraction after header
                struct PendingBlock {
                    let componentIndex: Int
                    let decomLevel: Int
                    let subband: J2KSubband
                    let x, y, width, height: Int
                    let passCount: Int
                    let zeroBitPlanes: Int
                    let bandKb: Int
                    let dataLength: Int
                }
                var pendingBlocks: [PendingBlock] = []

                for subband in subbands {
                    // Compute subband dimensions
                    let (sbWidth, sbHeight) = Self.subbandDimensions(
                        tileWidth: tileWidth, tileHeight: tileHeight,
                        levels: levels, resLevel: resLevel, subband: subband
                    )
                    guard sbWidth > 0 && sbHeight > 0 else { continue }

                    let blocksX = (sbWidth + cbWidth - 1) / cbWidth
                    let blocksY = (sbHeight + cbHeight - 1) / cbHeight
                    let blockCount = blocksX * blocksY

                    // Look up band Kb from QCD metadata
                    let bandKey: String
                    if subband == .ll {
                        bandKey = "LL_0"
                    } else {
                        bandKey = "\(subband.rawValue)_\(resLevel)"
                    }
                    let kb = metadata.bandKbValues[bandKey] ?? (metadata.components[compIdx].bitDepth + metadata.quantizationGuardBits)

                    // Convert resolution level to decomposition level
                    let decomLevel = resLevel == 0 ? 0 : (levels - resLevel + 1)

                    // Create tag trees for this band
                    var inclusionTree = J2KTagTree(width: blocksX, height: blocksY)
                    var zbpTree = J2KTagTree(width: blocksX, height: blocksY)

                    for leafIdx in 0..<blockCount {
                        // Decode inclusion via tag tree (threshold=1 for layer 0)
                        let included = try inclusionTree.decode(
                            reader: &reader, leafIndex: leafIdx, threshold: 1
                        )
                        guard included else { continue }

                        // Decode zero bit-planes via tag tree
                        var zbp: Int32 = 0
                        while !(try zbpTree.decode(reader: &reader, leafIndex: leafIdx, threshold: zbp + 1)) {
                            zbp += 1
                            if zbp > 100 { break }
                        }

                        // Decode coding passes (ISO Table B.4)
                        let passes = try Self.decodeCodingPasses(&reader)

                        // Decode data length (Lblock + floor(log2(numpasses)))
                        let length = try Self.decodeDataLength(&reader, numPasses: passes)

                        let blockX = (leafIdx % blocksX) * cbWidth
                        let blockY = (leafIdx / blocksX) * cbHeight
                        let actualW = min(cbWidth, sbWidth - blockX)
                        let actualH = min(cbHeight, sbHeight - blockY)

                        pendingBlocks.append(PendingBlock(
                            componentIndex: compIdx,
                            decomLevel: decomLevel,
                            subband: subband,
                            x: blockX, y: blockY,
                            width: actualW, height: actualH,
                            passCount: passes,
                            zeroBitPlanes: Int(zbp),
                            bandKb: kb,
                            dataLength: length
                        ))
                    }
                }

                // Byte-align after packet header
                try reader.alignToByte()
                // Disable byte stuffing for raw code-block data
                reader.setByteStuffing(false)

                // Read code-block data in band order
                for pb in pendingBlocks {
                    let blockData = try reader.readBytes(pb.dataLength)
                    blocks.append(CodeBlockInfo(
                        componentIndex: pb.componentIndex,
                        level: pb.decomLevel,
                        subband: pb.subband,
                        x: pb.x, y: pb.y,
                        width: pb.width, height: pb.height,
                        data: blockData,
                        passCount: pb.passCount,
                        zeroBitPlanes: pb.zeroBitPlanes,
                        bandKb: pb.bandKb
                    ))
                }
                // Re-enable byte stuffing for next packet header
                reader.setByteStuffing(true)
            }
        }

        return blocks
    }

    /// Computes subband dimensions for a given resolution level and subband type.
    private static func subbandDimensions(
        tileWidth: Int, tileHeight: Int,
        levels: Int, resLevel: Int, subband: J2KSubband
    ) -> (width: Int, height: Int) {
        if resLevel == 0 {
            // LL at deepest decomposition level
            var w = tileWidth, h = tileHeight
            for _ in 0..<levels {
                w = (w + 1) / 2
                h = (h + 1) / 2
            }
            return (w, h)
        } else {
            // Detail subband at decomposition level d = levels - resLevel + 1
            // Parent LL is at decomposition level (d - 1)
            let d = levels - resLevel + 1
            var w = tileWidth, h = tileHeight
            for _ in 0..<(d - 1) {
                w = (w + 1) / 2
                h = (h + 1) / 2
            }
            // Parent dimensions are (w, h). DWT splits into:
            switch subband {
            case .ll: return ((w + 1) / 2, (h + 1) / 2)
            case .hl: return (w / 2, (h + 1) / 2)
            case .lh: return ((w + 1) / 2, h / 2)
            case .hh: return (w / 2, h / 2)
            }
        }
    }

    /// Decodes the number of coding passes per ISO/IEC 15444-1 Table B.4.
    private static func decodeCodingPasses(_ reader: inout J2KBitReader) throws -> Int {
        if !(try reader.readBit()) { return 1 }   // 0 → 1 pass
        if !(try reader.readBit()) { return 2 }   // 10 → 2 passes
        // 11...
        let b3 = try reader.readBit()
        let b4 = try reader.readBit()
        if !(b3 && b4) {
            return 3 + (b3 ? 2 : 0) + (b4 ? 1 : 0) // 1100→3, 1101→4, 1110→5
        }
        // 1111 → read 5-bit value per ISO 15444-1 Table B.4
        let value5 = Int(try reader.readBits(5))
        if value5 < 31 {
            return 6 + value5                         // 1111 XXXXX → 6-36
        }
        return 37 + Int(try reader.readBits(7))      // 1111 11111 XXXXXXX → 37-164
    }

    /// Decodes data length using the Lblock mechanism per ISO 15444-1 B.10.7.
    /// Total bits = Lblock + floor(log2(numpasses)).
    private static func decodeDataLength(_ reader: inout J2KBitReader, numPasses: Int) throws -> Int {
        var lblock = 3
        while try reader.readBit() { lblock += 1 }
        let passLog = numPasses > 1 ? Int(log2(Double(numPasses))) : 0
        let totalBits = lblock + passLog
        return Int(try reader.readBits(totalBits))
    }

    // MARK: - Stage 3: Entropy Decoding

    /// Decoded subband information.
    struct SubbandInfo: Sendable {
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let coefficients: [Int32]
        /// Double-precision dequantized coefficients for the irreversible 9/7 path.
        /// When populated, the inverse DWT uses these directly to avoid
        /// precision loss from Int32 rounding of fractional dequantized values.
        let doubleCoefficients: [Double]?
        let width: Int
        let height: Int
    }

    /// Applies entropy decoding to code blocks.
    ///
    /// When `metadata.configuration.useHTJ2K` is true, uses HTJ2K FBCOT block
    /// decoding (ISO/IEC 15444-15). Otherwise uses legacy EBCOT bit-plane
    /// decoding (ISO/IEC 15444-1).
    private func applyEntropyDecoding(
        _ blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata
    ) throws -> [SubbandInfo] {
        let isIrreversible: Bool
        if case .irreversible97 = metadata.configuration.waveletFilter {
            isIrreversible = true
        } else {
            isIrreversible = false
        }
        let useHT = metadata.configuration.useHTJ2K

        // Track subband dimensions and use 2D placement for code blocks
        var subbandDims: [String: (width: Int, height: Int)] = [:]
        // Store decoded code blocks with their positions for proper 2D placement
        struct DecodedBlock {
            let x: Int
            let y: Int
            let width: Int
            let height: Int
            let coefficients: [Int32]
        }
        var subbandBlocks: [String: [DecodedBlock]] = [:]

        let blockCount = blocks.count

        if blockCount >= 4 {
            // === Parallel code block decoding ===
            // Each code block is independent (own MQ state + context models for EBCOT,
            // own MEL/VLC/MagSgn state for HTJ2K).
            // Use DispatchQueue.concurrentPerform for cross-platform parallelism
            // (macOS Intel/ARM, Linux).
            let componentBitDepths = metadata.components.map { $0.bitDepth }

            // Thread-safe result storage: each thread writes to its unique index
            let resultsPtr = UnsafeMutablePointer<[Int32]>.allocate(capacity: blockCount)
            for idx in 0..<blockCount {
                resultsPtr.advanced(by: idx).initialize(to: [])
            }
            defer {
                resultsPtr.deinitialize(count: blockCount)
                resultsPtr.deallocate()
            }

            DispatchQueue.concurrentPerform(iterations: blockCount) { i in
                let block = blocks[i]
                let bitDepth = block.bandKb > 0 ? block.bandKb : componentBitDepths[block.componentIndex]

                if useHT {
                    // HTJ2K path: use FBCOT block decoding
                    let htDecoder = HTBlockDecoder(
                        width: block.width,
                        height: block.height,
                        subband: block.subband
                    )
                    if let coeffs = try? htDecoder.decodeFromCodestream(
                        data: block.data,
                        passCount: block.passCount,
                        bitDepth: bitDepth,
                        zeroBitPlanes: block.zeroBitPlanes
                    ) {
                        resultsPtr[i] = coeffs
                    }
                } else {
                    // Legacy path: use EBCOT bit-plane decoding
                    let blockDecoder = CodeBlockDecoder()
                    let codeBlock = J2KCodeBlock(
                        index: 0,
                        x: block.x,
                        y: block.y,
                        width: block.width,
                        height: block.height,
                        subband: block.subband,
                        data: block.data,
                        passeCount: block.passCount,
                        zeroBitPlanes: block.zeroBitPlanes
                    )
                    if let coeffs = try? blockDecoder.decode(
                        codeBlock: codeBlock,
                        bitDepth: bitDepth,
                        irreversible: isIrreversible
                    ) {
                        resultsPtr[i] = coeffs
                    }
                }
            }

            // Collect results sequentially
            for i in 0..<blockCount {
                let block = blocks[i]
                var coeffs = resultsPtr[i]
                if coeffs.isEmpty {
                    coeffs = [Int32](repeating: 0, count: block.width * block.height)
                }

                let key = "\(block.componentIndex)_\(block.level)_\(block.subband.rawValue)"

                let currentWidth = subbandDims[key]?.width ?? 0
                let currentHeight = subbandDims[key]?.height ?? 0
                subbandDims[key] = (
                    width: max(currentWidth, block.x + block.width),
                    height: max(currentHeight, block.y + block.height)
                )

                if subbandBlocks[key] == nil {
                    subbandBlocks[key] = []
                }
                subbandBlocks[key]?.append(DecodedBlock(
                    x: block.x, y: block.y,
                    width: block.width, height: block.height,
                    coefficients: coeffs
                ))
            }
        } else {
            // Sequential path for small block counts
            for block in blocks {
                let compInfo = metadata.components[block.componentIndex]
                let bitDepth = block.bandKb > 0 ? block.bandKb : compInfo.bitDepth
                let coeffs: [Int32]

                if useHT {
                    // HTJ2K path: use FBCOT block decoding
                    let htDecoder = HTBlockDecoder(
                        width: block.width,
                        height: block.height,
                        subband: block.subband
                    )
                    coeffs = try htDecoder.decodeFromCodestream(
                        data: block.data,
                        passCount: block.passCount,
                        bitDepth: bitDepth,
                        zeroBitPlanes: block.zeroBitPlanes
                    )
                } else {
                    // Legacy path: use EBCOT bit-plane decoding
                    let decoder = CodeBlockDecoder()
                    let codeBlock = J2KCodeBlock(
                        index: 0,
                        x: block.x,
                        y: block.y,
                        width: block.width,
                        height: block.height,
                        subband: block.subband,
                        data: block.data,
                        passeCount: block.passCount,
                        zeroBitPlanes: block.zeroBitPlanes
                    )
                    coeffs = try decoder.decode(
                        codeBlock: codeBlock,
                        bitDepth: bitDepth,
                        irreversible: isIrreversible
                    )
                }

                let key = "\(block.componentIndex)_\(block.level)_\(block.subband.rawValue)"

                let currentWidth = subbandDims[key]?.width ?? 0
                let currentHeight = subbandDims[key]?.height ?? 0
                subbandDims[key] = (
                    width: max(currentWidth, block.x + block.width),
                    height: max(currentHeight, block.y + block.height)
                )

                if subbandBlocks[key] == nil {
                    subbandBlocks[key] = []
                }
                subbandBlocks[key]?.append(DecodedBlock(
                    x: block.x, y: block.y,
                    width: block.width, height: block.height,
                    coefficients: coeffs
                ))
            }
        }

        // Scatter code block coefficients into proper 2D subband positions
        var subbands: [SubbandInfo] = []
        for (key, decodedBlocks) in subbandBlocks {
            let parts = key.split(separator: "_")
            guard parts.count == 3,
                  let compIdx = Int(parts[0]),
                  let level = Int(parts[1]),
                  let dims = subbandDims[key] else { continue }

            let subbandType = J2KSubband(rawValue: String(parts[2])) ?? .ll

            // Create subband buffer and place each code block at its correct position
            var subbandCoeffs = [Int32](repeating: 0, count: dims.width * dims.height)
            subbandCoeffs.withUnsafeMutableBufferPointer { dstBuf in
                for db in decodedBlocks {
                    db.coefficients.withUnsafeBufferPointer { srcBuf in
                        for row in 0..<db.height {
                            let srcStart = row * db.width
                            let dstStart = (db.y + row) * dims.width + db.x
                            let copyCount = min(db.width, srcBuf.count - srcStart)
                            guard copyCount > 0, dstStart + copyCount <= dstBuf.count else { continue }
                            dstBuf.baseAddress!.advanced(by: dstStart)
                                .update(from: srcBuf.baseAddress!.advanced(by: srcStart), count: copyCount)
                        }
                    }
                }
            }

            subbands.append(SubbandInfo(
                componentIndex: compIdx,
                level: level,
                subband: subbandType,
                coefficients: subbandCoeffs,
                doubleCoefficients: nil,
                width: dims.width,
                height: dims.height
            ))
        }

        return subbands
    }

    // MARK: - Stage 4: Dequantization

    /// Applies dequantization to decoded subbands.
    private func applyDequantization(
        _ subbands: [SubbandInfo],
        metadata: CodestreamMetadata
    ) throws -> [SubbandInfo] {
        var result: [SubbandInfo] = []
        let levels = metadata.configuration.decompositionLevels

        // Determine if we're using irreversible (9/7) transform
        let isIrreversible: Bool
        if case .irreversible97 = metadata.configuration.waveletFilter {
            isIrreversible = true
        } else {
            isIrreversible = false
        }

        // HTJ2K (FBCOT) outputs coefficients at natural scale, while standard
        // EBCOT uses bpno_plus_one (shifted left by 1) for irreversible 9/7.
        // The dequantization scale factor must account for this difference.
        let useHTJ2K = metadata.configuration.useHTJ2K

        for info in subbands {
            // QCD keys use resolution-level numbering (1=coarsest, NL=finest),
            // but SubbandInfo.level uses decomposition-level numbering (NL=coarsest, 1=finest).
            // Convert: resLevel = NL - decomLevel + 1
            let key: String
            if info.subband == .ll {
                key = "LL_0"
            } else {
                let resLevel = levels - info.level + 1
                key = "\(info.subband.rawValue)_\(resLevel)"
            }
            let stepSize = metadata.quantizationSteps[key] ?? 1.0

            if isIrreversible {
                // For irreversible 9/7, dequantize to Double to preserve fractional
                // precision through the inverse DWT. Rounding to Int32 here would
                // destroy sub-integer information (e.g. step=0.02, q=10 → 0.2 → 0).
                //
                // Standard EBCOT coefficients use bpno_plus_one scale (shifted left
                // by 1) to match OPJ's oneplushalf approach, so dequantization
                // applies ×0.5 to compensate. The EBCOT halfBit adds 1 at bit 0,
                // giving effective dequantization of (2q + 1) × stepSize/2 =
                // (q + 0.5) × stepSize — the midpoint of the quantization bin.
                //
                // HTJ2K (FBCOT) outputs coefficients at natural scale (no shift).
                // Apply explicit midpoint reconstruction: (q + 0.5) × stepSize,
                // which centers the value in the quantization bin and minimizes
                // the expected quantization error (MSE).
                let effectiveStepSize = useHTJ2K ? stepSize : (0.5 * stepSize)
                let midpointOffset = useHTJ2K ? (0.5 * stepSize) : 0.0
                let dequantizedDouble = info.coefficients.map { coeff -> Double in
                    if coeff == 0 { return 0.0 }
                    let sign: Double = coeff > 0 ? 1.0 : -1.0
                    let magnitude = Double(abs(coeff))
                    return sign * (magnitude * effectiveStepSize + midpointOffset)
                }

                result.append(SubbandInfo(
                    componentIndex: info.componentIndex,
                    level: info.level,
                    subband: info.subband,
                    coefficients: info.coefficients,
                    doubleCoefficients: dequantizedDouble,
                    width: info.width,
                    height: info.height
                ))
            } else {
                // For reversible 5/3, step size is always 1 (no quantization).
                // Coefficients are exact integers.
                result.append(SubbandInfo(
                    componentIndex: info.componentIndex,
                    level: info.level,
                    subband: info.subband,
                    coefficients: info.coefficients,
                    doubleCoefficients: nil,
                    width: info.width,
                    height: info.height
                ))
            }
        }

        return result
    }

    // MARK: - Stage 5: Inverse Wavelet Transform

    /// Applies inverse wavelet transform to reconstruct spatial domain.
    private func applyInverseWaveletTransform(
        _ subbands: [SubbandInfo],
        metadata: CodestreamMetadata
    ) throws -> [[Double]] {
        let filter = metadata.configuration.waveletFilter
        let levels = metadata.configuration.decompositionLevels
        var componentData: [[Double]] = []

        // Use the component count from the SIZ marker, not from the data.
        // Some components may have all-empty packets (e.g., aggressive rate
        // control). They should still produce zero-filled output.
        let maxComponent = max(
            metadata.componentCount - 1,
            subbands.map { $0.componentIndex }.max() ?? 0
        )

        for compIdx in 0...maxComponent {
            // Select filter for this component
            let componentFilter: J2KDWT1D.Filter
            if let kernelConfig = metadata.configuration.waveletKernelConfiguration {
                // Use arbitrary wavelet kernel if configured
                if let kernel = kernelConfig.kernel(
                    forTile: 0, component: compIdx,
                    lossless: metadata.configuration.useReversibleTransform
                ) {
                    componentFilter = kernel.toDWTFilter()
                } else {
                    componentFilter = filter
                }
            } else {
                componentFilter = filter
            }

            let compSubbands = subbands.filter { $0.componentIndex == compIdx }

            if compSubbands.isEmpty {
                // Component has no data (e.g., all code blocks were zeroed by
                // rate control). Fill with neutral values so downstream stages
                // (color transform, reconstruction) have the expected shape.
                componentData.append([Double](repeating: 0.0, count: metadata.width * metadata.height))
                continue
            }

            // Find LL subband.  When rate control truncates aggressively the
            // LL code blocks may all be empty, so synthesise a zero-filled
            // subband with the standard dimensions for the deepest level.
            let llSubband: SubbandInfo
            let width: Int
            let height: Int
            if let found = compSubbands.first(where: { $0.subband == .ll }) {
                llSubband = found
                width = found.width
                height = found.height
            } else {
                let cW = metadata.width / metadata.components[compIdx].subsamplingX
                let cH = metadata.height / metadata.components[compIdx].subsamplingY
                var w = cW; var h = cH
                for _ in 0..<levels { w = (w + 1) / 2; h = (h + 1) / 2 }
                llSubband = SubbandInfo(
                    componentIndex: compIdx,
                    level: levels,
                    subband: .ll,
                    coefficients: [Int32](repeating: 0, count: w * h),
                    doubleCoefficients: nil,
                    width: w,
                    height: h
                )
                width = w
                height = h
            }

            // For now, if no decomposition levels, just return LL subband
            if levels == 0 {
                componentData.append(vDSPConvert.int32sToDoubles(llSubband.coefficients))
                continue
            }

            // Convert 1D coefficient arrays to 2D arrays for each subband
            func to2D(_ coeffs: [Int32], width: Int, height: Int) -> [[Int32]] {
                var result = [[Int32]](
                    repeating: [Int32](repeating: 0, count: width),
                    count: height
                )
                for row in 0..<height {
                    for col in 0..<width {
                        let idx = row * width + col
                        if idx < coeffs.count {
                            result[row][col] = coeffs[idx]
                        }
                    }
                }
                return result
            }

            func to2DDouble(_ coeffs: [Int32], width: Int, height: Int) -> [[Double]] {
                var result = [[Double]](
                    repeating: [Double](repeating: 0, count: width),
                    count: height
                )
                for row in 0..<height {
                    for col in 0..<width {
                        let idx = row * width + col
                        if idx < coeffs.count {
                            result[row][col] = Double(coeffs[idx])
                        }
                    }
                }
                return result
            }

            func to2DDoubleFromDoubles(_ coeffs: [Double], width: Int, height: Int) -> [[Double]] {
                var result = [[Double]](
                    repeating: [Double](repeating: 0, count: width),
                    count: height
                )
                for row in 0..<height {
                    for col in 0..<width {
                        let idx = row * width + col
                        if idx < coeffs.count {
                            result[row][col] = coeffs[idx]
                        }
                    }
                }
                return result
            }

            // Compute expected subband dimensions at each decomposition level
            let compW = metadata.width / metadata.components[compIdx].subsamplingX
            let compH = metadata.height / metadata.components[compIdx].subsamplingY
            var levelSizes: [(width: Int, height: Int)] = [(compW, compH)]
            for _ in 0..<levels {
                let (pw, ph) = levelSizes.last!
                levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))
            }

            // Helper: convert 1D Int32 array to 2D padded to standard dimensions.
            // When rate control truncates code blocks, the actual subband data may
            // be smaller than the standard dimension. Zero-pad to the expected size.
            func paddedInt(_ coeffs: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Int32]] {
                var result = [[Int32]](repeating: [Int32](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    for row in 0..<copyH {
                        let srcOffset = row * srcW
                        guard srcOffset + copyW <= srcBuf.count else { return }
                        result[row].withUnsafeMutableBufferPointer { dstBuf in
                            dstBuf.baseAddress!.update(from: srcBuf.baseAddress! + srcOffset, count: copyW)
                        }
                    }
                }
                return result
            }

            func paddedDoubleFromInt(_ coeffs: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Double]] {
                var result = [[Double]](repeating: [Double](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    for row in 0..<copyH {
                        let srcOffset = row * srcW
                        guard srcOffset + copyW <= srcBuf.count else { return }
                        result[row].withUnsafeMutableBufferPointer { dstBuf in
                            for col in 0..<copyW {
                                dstBuf[col] = Double(srcBuf[srcOffset + col])
                            }
                        }
                    }
                }
                return result
            }

            func paddedDouble(_ coeffs: [Double], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Double]] {
                var result = [[Double]](repeating: [Double](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                coeffs.withUnsafeBufferPointer { srcBuf in
                    for row in 0..<copyH {
                        let srcOffset = row * srcW
                        guard srcOffset + copyW <= srcBuf.count else { return }
                        result[row].withUnsafeMutableBufferPointer { dstBuf in
                            dstBuf.baseAddress!.update(from: srcBuf.baseAddress! + srcOffset, count: copyW)
                        }
                    }
                }
                return result
            }

            // Full multi-level IDWT reconstruction
            // For 9/7 irreversible, use Double precision throughout all levels to
            // avoid accumulated rounding error from Int32 truncation at each level.
            let useDoublePrecision: Bool
            if case .irreversible97 = componentFilter {
                useDoublePrecision = true
            } else {
                useDoublePrecision = false
            }

            if useDoublePrecision {
                // Double-precision path for 9/7 irreversible wavelet.
                // Use doubleCoefficients (from dequantization) to preserve
                // fractional precision that would be lost by Int32 rounding.
                let expectedLLW = levelSizes[levels].width
                let expectedLLH = levelSizes[levels].height
                var currentLLDouble: [[Double]]
                if let dc = llSubband.doubleCoefficients {
                    currentLLDouble = paddedDouble(dc, srcW: width, srcH: height, dstW: expectedLLW, dstH: expectedLLH)
                } else {
                    currentLLDouble = paddedDoubleFromInt(llSubband.coefficients, srcW: width, srcH: height, dstW: expectedLLW, dstH: expectedLLH)
                }

                for level in (1...levels).reversed() {
                    let parentW = levelSizes[level - 1].width
                    let parentH = levelSizes[level - 1].height
                    let llW = levelSizes[level].width
                    let llH = levelSizes[level].height
                    // Standard JPEG 2000 subband dimensions:
                    // HL: floor(parentW/2) x ceil(parentH/2)
                    // LH: ceil(parentW/2) x floor(parentH/2)
                    // HH: floor(parentW/2) x floor(parentH/2)
                    let hlW = parentW - llW  // = floor(parentW/2)
                    let lhH = parentH - llH  // = floor(parentH/2)

                    let hlSub = compSubbands.first(where: { $0.level == level && $0.subband == .hl })
                    let hl2D: [[Double]]
                    if let hs = hlSub, let dc = hs.doubleCoefficients {
                        hl2D = paddedDouble(dc, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: llH)
                    } else if let hs = hlSub {
                        hl2D = paddedDoubleFromInt(hs.coefficients, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: llH)
                    } else {
                        hl2D = [[Double]](repeating: [Double](repeating: 0, count: hlW), count: llH)
                    }

                    let lhSub = compSubbands.first(where: { $0.level == level && $0.subband == .lh })
                    let lh2D: [[Double]]
                    if let ls = lhSub, let dc = ls.doubleCoefficients {
                        lh2D = paddedDouble(dc, srcW: ls.width, srcH: ls.height, dstW: llW, dstH: lhH)
                    } else if let ls = lhSub {
                        lh2D = paddedDoubleFromInt(ls.coefficients, srcW: ls.width, srcH: ls.height, dstW: llW, dstH: lhH)
                    } else {
                        lh2D = [[Double]](repeating: [Double](repeating: 0, count: llW), count: lhH)
                    }

                    let hhSub = compSubbands.first(where: { $0.level == level && $0.subband == .hh })
                    let hh2D: [[Double]]
                    if let hs = hhSub, let dc = hs.doubleCoefficients {
                        hh2D = paddedDouble(dc, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: lhH)
                    } else if let hs = hhSub {
                        hh2D = paddedDoubleFromInt(hs.coefficients, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: lhH)
                    } else {
                        hh2D = [[Double]](repeating: [Double](repeating: 0, count: hlW), count: lhH)
                    }

                    currentLLDouble = try J2KDWT2D.inverseTransform97(
                        ll: currentLLDouble,
                        lh: lh2D,
                        hl: hl2D,
                        hh: hh2D,
                        boundaryExtension: .symmetric
                    )
                }

                // Keep Double precision through ICT and DC shift — round only at final pixel output
                let flattened = currentLLDouble.flatMap { $0 }
                componentData.append(flattened)
            } else {
                // Int32 path for 5/3 reversible wavelet (exact integer arithmetic)
                let expectedLLW = levelSizes[levels].width
                let expectedLLH = levelSizes[levels].height
                var currentLL = paddedInt(llSubband.coefficients, srcW: width, srcH: height, dstW: expectedLLW, dstH: expectedLLH)

                for level in (1...levels).reversed() {
                    let parentW = levelSizes[level - 1].width
                    let parentH = levelSizes[level - 1].height
                    let llW = levelSizes[level].width
                    let llH = levelSizes[level].height
                    let hlW = parentW - llW
                    let lhH = parentH - llH

                    let hl2D: [[Int32]]
                    if let hs = compSubbands.first(where: { $0.level == level && $0.subband == .hl }) {
                        hl2D = paddedInt(hs.coefficients, srcW: hs.width, srcH: hs.height, dstW: hlW, dstH: llH)
                    } else {
                        hl2D = [[Int32]](repeating: [Int32](repeating: 0, count: hlW), count: llH)
                    }
                    let lh2D: [[Int32]]
                    if let ls = compSubbands.first(where: { $0.level == level && $0.subband == .lh }) {
                        lh2D = paddedInt(ls.coefficients, srcW: ls.width, srcH: ls.height, dstW: llW, dstH: lhH)
                    } else {
                        lh2D = [[Int32]](repeating: [Int32](repeating: 0, count: llW), count: lhH)
                    }
                    let hh2D: [[Int32]]
                    if let hhs = compSubbands.first(where: { $0.level == level && $0.subband == .hh }) {
                        hh2D = paddedInt(hhs.coefficients, srcW: hhs.width, srcH: hhs.height, dstW: hlW, dstH: lhH)
                    } else {
                        hh2D = [[Int32]](repeating: [Int32](repeating: 0, count: hlW), count: lhH)
                    }

                    let optimizer = J2KDWT2DOptimizer()
                    currentLL = try optimizer.inverseTransform2DOptimized(
                        ll: currentLL,
                        lh: lh2D,
                        hl: hl2D,
                        hh: hh2D,
                        boundaryExtension: .symmetric
                    )
                }

                let rowCount = currentLL.count
                let colCount = rowCount > 0 ? currentLL[0].count : 0
                var flattened = [Double](repeating: 0.0, count: rowCount * colCount)
                flattened.withUnsafeMutableBufferPointer { dst in
                    for r in 0..<rowCount {
                        let row = currentLL[r]
                        let offset = r * colCount
                        for c in 0..<min(colCount, row.count) {
                            dst[offset + c] = Double(row[c])
                        }
                    }
                }
                componentData.append(flattened)
            }
        }

        return componentData
    }

    // MARK: - GPU Inverse Wavelet Transform

    /// GPU-accelerated inverse wavelet transform using Metal.
    ///
    /// Uses Metal GPU for CDF 9/7 irreversible and Le Gall 5/3 reversible inverse DWT.
    /// Falls back to CPU when Metal is unavailable or for custom filters.
    private func applyInverseWaveletTransformGPU(
        _ subbands: [SubbandInfo],
        metadata: CodestreamMetadata
    ) async throws -> [[Double]] {
        // Fall back to CPU for custom wavelet kernels only
        if metadata.configuration.waveletKernelConfiguration != nil {
            return try applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        let levels = metadata.configuration.decompositionLevels
        guard levels >= 1 else {
            return try applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        // Fall back to CPU when Metal GPU is not available (e.g. Linux, CI servers)
        guard J2KMetalDWT.isAvailable else {
            return try applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        // Fall back to CPU for small images where GPU dispatch overhead exceeds compute benefit.
        let pixelCount = metadata.width * metadata.height
        guard pixelCount >= 256 * 256 else {
            return try applyInverseWaveletTransform(subbands, metadata: metadata)
        }

        // Select filter based on configuration
        let metalFilter: J2KMetalDWTFilter
        if case .irreversible97 = metadata.configuration.waveletFilter {
            metalFilter = .irreversible97
        } else {
            metalFilter = .reversible53
        }

        let metalDWT = J2KMetalDWT(configuration: J2KMetalDWTConfiguration(
            filter: metalFilter, decompositionLevels: levels
        ))
        try await metalDWT.initialize()

        var componentData: [[Double]] = []
        let maxComponent = max(
            metadata.componentCount - 1,
            subbands.map { $0.componentIndex }.max() ?? 0
        )

        for compIdx in 0...maxComponent {
            let compSubbands = subbands.filter { $0.componentIndex == compIdx }

            if compSubbands.isEmpty {
                componentData.append([Double](repeating: 0.0, count: metadata.width * metadata.height))
                continue
            }

            // Compute expected subband dimensions at each level
            let compW = metadata.width / metadata.components[compIdx].subsamplingX
            let compH = metadata.height / metadata.components[compIdx].subsamplingY
            var levelSizes: [(width: Int, height: Int)] = [(compW, compH)]
            for _ in 0..<levels {
                let (pw, ph) = levelSizes.last!
                levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))
            }

            // Get initial LL subband as Float
            let llSubband = compSubbands.first(where: { $0.subband == .ll })
            let expectedLLW = levelSizes[levels].width
            let expectedLLH = levelSizes[levels].height

            var currentLL: [Float]
            if let ll = llSubband {
                if let dc = ll.doubleCoefficients {
                    currentLL = padFlatFloat(vDSPConvert.doublesToFloats(dc), srcW: ll.width, srcH: ll.height,
                                              dstW: expectedLLW, dstH: expectedLLH)
                } else {
                    currentLL = padFlatFloat(vDSPConvert.int32sToFloats(ll.coefficients), srcW: ll.width, srcH: ll.height,
                                              dstW: expectedLLW, dstH: expectedLLH)
                }
            } else {
                currentLL = [Float](repeating: 0, count: expectedLLW * expectedLLH)
            }

            // Inverse DWT from coarsest to finest using Metal GPU
            for level in (1...levels).reversed() {
                let parentW = levelSizes[level - 1].width
                let parentH = levelSizes[level - 1].height
                let llW = levelSizes[level].width
                let llH = levelSizes[level].height
                let hlW = parentW - llW
                let lhH = parentH - llH

                let hlFloat = getSubbandAsFloat(compSubbands, level: level, subband: .hl,
                                                 dstW: hlW, dstH: llH)
                let lhFloat = getSubbandAsFloat(compSubbands, level: level, subband: .lh,
                                                 dstW: llW, dstH: lhH)
                let hhFloat = getSubbandAsFloat(compSubbands, level: level, subband: .hh,
                                                 dstW: hlW, dstH: lhH)

                let subbandData = J2KMetalDWTSubbands(
                    ll: currentLL, lh: lhFloat, hl: hlFloat, hh: hhFloat,
                    llWidth: llW, llHeight: llH,
                    originalWidth: parentW, originalHeight: parentH
                )

                currentLL = try await metalDWT.inverse2D(subbands: subbandData, backend: .auto)
            }

            componentData.append(vDSPConvert.floatsToDoubles(currentLL))
        }

        return componentData
    }

    /// Extracts a subband as a Float array with zero-padding to expected dimensions.
    private func getSubbandAsFloat(_ subbands: [SubbandInfo], level: Int, subband: J2KSubband,
                                    dstW: Int, dstH: Int) -> [Float] {
        if let sb = subbands.first(where: { $0.level == level && $0.subband == subband }) {
            let srcData: [Float]
            if let dc = sb.doubleCoefficients {
                srcData = vDSPConvert.doublesToFloats(dc)
            } else {
                srcData = vDSPConvert.int32sToFloats(sb.coefficients)
            }
            return padFlatFloat(srcData, srcW: sb.width, srcH: sb.height, dstW: dstW, dstH: dstH)
        }
        return [Float](repeating: 0, count: dstW * dstH)
    }

    /// Zero-pads a flat Float array from source to destination dimensions.
    private func padFlatFloat(_ data: [Float], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [Float] {
        if srcW == dstW && srcH == dstH && data.count == dstW * dstH { return data }
        var result = [Float](repeating: 0, count: dstW * dstH)
        let copyW = min(srcW, dstW)
        let copyH = min(srcH, dstH)
        for row in 0..<copyH {
            let srcOffset = row * srcW
            let dstOffset = row * dstW
            guard srcOffset + copyW <= data.count else { break }
            for col in 0..<copyW {
                result[dstOffset + col] = data[srcOffset + col]
            }
        }
        return result
    }

    // MARK: - Stage 6: Inverse Colour Transform

    /// GPU-accelerated inverse colour transform using Metal.
    ///
    /// Uses Metal GPU for inverse ICT/RCT colour transforms on 3+ component images.
    /// Falls back to CPU when Metal is unavailable.
    private func applyInverseColorTransformGPU(
        _ components: [[Double]],
        metadata: CodestreamMetadata
    ) async throws -> [[Double]] {
        guard components.count >= 3 else { return components }
        // useReversibleTransform indicates MCT is enabled; when false, no color transform
        guard metadata.configuration.useReversibleTransform else { return components }

        // Check if Metal is available
        guard J2KMetalColorTransform.isAvailable else {
            return try applyInverseColorTransform(components, metadata: metadata)
        }

        let transformType: J2KMetalColorTransformType
        if case .reversible53 = metadata.configuration.waveletFilter {
            transformType = .rct
        } else {
            transformType = .ict
        }

        let metalConfig = J2KMetalColorTransformConfiguration(transformType: transformType)
        let metalCT = J2KMetalColorTransform(configuration: metalConfig)
        try await metalCT.initialize()

        // Convert Double to Float for Metal
        let comp0 = vDSPConvert.doublesToFloats(components[0])
        let comp1 = vDSPConvert.doublesToFloats(components[1])
        let comp2 = vDSPConvert.doublesToFloats(components[2])

        let result = try await metalCT.inverseTransform(
            component0: comp0, component1: comp1, component2: comp2, backend: .auto
        )

        // Convert back to Double
        var output: [[Double]] = [
            vDSPConvert.floatsToDoubles(result.component0),
            vDSPConvert.floatsToDoubles(result.component1),
            vDSPConvert.floatsToDoubles(result.component2)
        ]
        if components.count > 3 {
            output.append(contentsOf: components[3...])
        }
        return output
    }

    /// Applies inverse colour transform.
    private func applyInverseColorTransform(
        _ components: [[Double]],
        metadata: CodestreamMetadata
    ) throws -> [[Double]] {
        // Only apply if 3+ components
        guard components.count >= 3 else { return components }

        // Apply inverse RCT/ICT based on configuration
        // useReversibleTransform indicates MCT is enabled; waveletFilter determines RCT vs ICT
        if metadata.configuration.useReversibleTransform {
            if case .reversible53 = metadata.configuration.waveletFilter {
                // Inverse RCT (lossless) — needs Int32 for exact integer arithmetic
                let transform = J2KColorTransform(configuration: J2KColorTransformConfiguration(mode: .reversible))
                let (r, g, b) = try transform.inverseRCT(
                    y: vDSPConvert.doublesToInt32s(components[0]),
                    cb: vDSPConvert.doublesToInt32s(components[1]),
                    cr: vDSPConvert.doublesToInt32s(components[2])
                )

                var result: [[Double]] = [vDSPConvert.int32sToDoubles(r), vDSPConvert.int32sToDoubles(g), vDSPConvert.int32sToDoubles(b)]
                if components.count > 3 {
                    result.append(contentsOf: components[3...])
                }
                return result
            } else {
                // Inverse ICT (lossy) — stays in Double precision throughout
                let transform = J2KColorTransform(configuration: J2KColorTransformConfiguration(mode: .irreversible))
                let (red, green, blue) = try transform.inverseICT(y: components[0], cb: components[1], cr: components[2])

                var result: [[Double]] = [red, green, blue]
                if components.count > 3 {
                    result.append(contentsOf: components[3...])
                }
                return result
            }
        } else {
            // No MCT
            return components
        }
    }

    // MARK: - Stage 7: Image Reconstruction

    /// Reconstructs the final J2KImage from component data.
    private func reconstructImage(
        _ components: [[Double]],
        metadata: CodestreamMetadata
    ) throws -> J2KImage {
        var imageComponents: [J2KComponent] = []

        for (idx, compData) in components.enumerated() {
            guard idx < metadata.components.count else { break }

            let compInfo = metadata.components[idx]
            let width = metadata.width / compInfo.subsamplingX
            let height = metadata.height / compInfo.subsamplingY

            // Convert Double array to Data with final rounding and clamping
            // Pre-allocate the exact size needed
            let bytesPerPixel = compInfo.bitDepth <= 8 ? 1 : 2
            let pixelCount = compData.count
            var data = Data(count: pixelCount * bytesPerPixel)

            data.withUnsafeMutableBytes { rawBuf in
                let ptr = rawBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                if compInfo.bitDepth <= 8 {
                    if compInfo.signed {
                        for i in 0..<pixelCount {
                            let rounded = Int32(compData[i].rounded())
                            ptr[i] = UInt8(bitPattern: Int8(clamping: rounded))
                        }
                    } else {
                        for i in 0..<pixelCount {
                            let rounded = Int32(compData[i].rounded())
                            ptr[i] = UInt8(clamping: max(0, rounded))
                        }
                    }
                } else {
                    if compInfo.signed {
                        for i in 0..<pixelCount {
                            let rounded = Int32(compData[i].rounded())
                            let v = UInt16(bitPattern: Int16(clamping: rounded))
                            ptr[i * 2] = UInt8(v >> 8)
                            ptr[i * 2 + 1] = UInt8(v & 0xFF)
                        }
                    } else {
                        for i in 0..<pixelCount {
                            let rounded = Int32(compData[i].rounded())
                            let v = UInt16(clamping: max(0, rounded))
                            ptr[i * 2] = UInt8(v >> 8)
                            ptr[i * 2 + 1] = UInt8(v & 0xFF)
                        }
                    }
                }
            }

            let component = J2KComponent(
                index: idx,
                bitDepth: compInfo.bitDepth,
                signed: compInfo.signed,
                width: width,
                height: height,
                subsamplingX: compInfo.subsamplingX,
                subsamplingY: compInfo.subsamplingY,
                data: data
            )

            imageComponents.append(component)
        }

        return J2KImage(
            width: metadata.width,
            height: metadata.height,
            components: imageComponents
        )
    }

    // MARK: - Progress Reporting

    private func reportProgress(
        _ callback: ((DecoderProgressUpdate) -> Void)?,
        stage: DecodingStage,
        stageProgress: Double
    ) {
        guard let callback = callback else { return }
        let stages = DecodingStage.allCases
        guard let stageIndex = stages.firstIndex(of: stage) else { return }
        let stageWeight = 1.0 / Double(stages.count)
        let overall = Double(stageIndex) * stageWeight + stageProgress * stageWeight
        callback(DecoderProgressUpdate(
            stage: stage,
            progress: stageProgress,
            overallProgress: min(overall, 1.0)
        ))
    }
}
