// J2KDecoderPipeline.swift
// J2KSwift
//
// Decoder pipeline implementation for JPEG 2000 decoding.
//

import Foundation
import J2KCore

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
    
    /// Inverse color space transformation.
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
    
    /// Whether to use reversible color transform.
    var useReversibleTransform: Bool = true
    
    /// Number of quality layers (from COD marker).
    var qualityLayers: Int = 1
    
    /// Progression order (from COD marker).
    var progressionOrder: J2KProgressionOrder = .lrcp
    
    /// Wavelet filter type (from COD marker).
    var waveletFilter: J2KDWT1D.Filter = .reversible53
    
    /// Whether HTJ2K block coding is used (from COD marker bit 6).
    var useHTJ2K: Bool = false
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
    
    /// Configuration from COD marker.
    var configuration: DecoderConfiguration
    
    /// Quantization step sizes from QCD marker.
    var quantizationSteps: [String: Double]
    
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
/// 6. Inverse Color Transform — YCbCr → RGB conversion
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
        let (metadata, tileData) = try parseCodestream(data)
        reportProgress(progress, stage: .codestreamParsing, stageProgress: 1.0)
        
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
        
        // Stage 6: Inverse color transform
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        let rgbData = try applyInverseColorTransform(spatialData, metadata: metadata)
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 1.0)
        
        // Stage 7: Image reconstruction
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 0.0)
        let image = try reconstructImage(rgbData, metadata: metadata)
        reportProgress(progress, stage: .imageReconstruction, stageProgress: 1.0)
        
        return image
    }
    
    // MARK: - Stage 1: Codestream Parsing
    
    /// Parses the JPEG 2000 codestream and extracts metadata and tile data.
    private func parseCodestream(_ data: Data) throws -> (CodestreamMetadata, Data) {
        var reader = J2KBitReader(data: data)
        
        // Verify SOC marker
        guard try reader.readMarker() == J2KMarker.soc.rawValue else {
            throw J2KError.decodingError("Invalid codestream: missing SOC marker")
        }
        
        var metadata: CodestreamMetadata?
        var configuration = DecoderConfiguration()
        var quantizationSteps: [String: Double] = [:]
        var tileData: Data?
        
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
                quantizationSteps = try parseQCDMarker(&reader, config: configuration)
                
            case J2KMarker.sot.rawValue:
                // Start of tile-part
                let (_, tilepartData) = try parseSOTMarker(&reader)
                tileData = tilepartData
                // Break after first tile for now
                break
                
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
            
            if tileData != nil {
                break
            }
        }
        
        guard var meta = metadata else {
            throw J2KError.decodingError("Missing SIZ marker in codestream")
        }
        
        meta.configuration = configuration
        meta.quantizationSteps = quantizationSteps
        
        return (meta, tileData ?? Data())
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
        _ = try reader.readUInt32() // XOsiz
        _ = try reader.readUInt32() // YOsiz
        
        // Tile dimensions
        let tileWidth = Int(try reader.readUInt32())
        let tileHeight = Int(try reader.readUInt32())
        
        // Tile offset
        _ = try reader.readUInt32() // XTOsiz
        _ = try reader.readUInt32() // YTOsiz
        
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
            configuration: DecoderConfiguration(),
            quantizationSteps: [:]
        )
    }
    
    /// Parses the COD marker segment.
    private func parseCODMarker(_ reader: inout J2KBitReader) throws -> DecoderConfiguration {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position
        
        var config = DecoderConfiguration()
        
        // Scod — Coding style flags
        _ = try reader.readUInt8()
        
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
        config: DecoderConfiguration
    ) throws -> [String: Double] {
        let length = Int(try reader.readUInt16())
        let startPos = reader.position
        
        var stepSizes: [String: Double] = [:]
        
        // Sqcd — Quantization style
        let sqcd = try reader.readUInt8()
        let quantStyle = sqcd & 0x1F
        
        if quantStyle == 0 {
            // No quantization (reversible)
            // Read exponent values
            let llExp = try reader.readUInt8() >> 3
            stepSizes["LL_0"] = pow(2.0, Double(llExp))
            
            if config.decompositionLevels > 0 {
                for level in 1...config.decompositionLevels {
                    for subband in ["HL", "LH", "HH"] {
                        let exp = try reader.readUInt8() >> 3
                        stepSizes["\(subband)_\(level)"] = pow(2.0, Double(exp))
                    }
                }
            }
        } else if quantStyle == 2 {
            // Scalar expounded quantization
            // Read step size values (2 bytes each)
            func decodeStepSize(_ value: UInt16) -> Double {
                let exp = Int((value >> 11) & 0x1F)
                let mant = Double(value & 0x7FF)
                return pow(2.0, Double(exp) - 11.0) * (1.0 + mant / 2048.0)
            }
            
            let llValue = try reader.readUInt16()
            stepSizes["LL_0"] = decodeStepSize(llValue)
            
            if config.decompositionLevels > 0 {
                for level in 1...config.decompositionLevels {
                    for subband in ["HL", "LH", "HH"] {
                        let value = try reader.readUInt16()
                        stepSizes["\(subband)_\(level)"] = decodeStepSize(value)
                    }
                }
            }
        }
        
        // Verify we read the expected amount
        let bytesRead = reader.position - startPos
        if bytesRead < length - 2 {
            try reader.skip(length - 2 - bytesRead)
        }
        
        return stepSizes
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
    }
    
    /// Extracts code blocks from tile data with multi-level support.
    private func extractTileData(
        _ tileData: Data,
        metadata: CodestreamMetadata
    ) throws -> [CodeBlockInfo] {
        var blocks: [CodeBlockInfo] = []
        
        let cbWidth = metadata.configuration.codeBlockSize.width
        let cbHeight = metadata.configuration.codeBlockSize.height
        let levels = metadata.configuration.decompositionLevels
        
        // Calculate tile dimensions at full resolution
        let tileWidth = metadata.tileSize.width
        let tileHeight = metadata.tileSize.height
        
        // Simple packet parsing for LRCP progression order
        // Process each quality layer, resolution level, component, and precinct
        var reader = PacketHeaderReader(data: tileData)
        var dataOffset = 0
        
        // For now, support single component, single layer
        let componentIndex = 0
        let layerIndex = 0
        
        // Process all resolution levels (from coarsest to finest)
        for resLevel in 0...levels {
            // Calculate dimensions at this resolution level
            let levelScale = 1 << (levels - resLevel)
            let levelWidth = (tileWidth + levelScale - 1) / levelScale
            let levelHeight = (tileHeight + levelScale - 1) / levelScale
            
            // Determine which subbands to process at this level
            let subbands: [J2KSubband]
            if resLevel == 0 {
                // Coarsest level: only LL subband
                subbands = [.ll]
            } else {
                // Other levels: HL, LH, HH subbands (LL comes from previous level)
                subbands = [.hl, .lh, .hh]
            }
            
            for subband in subbands {
                // Calculate subband dimensions (approximately half of level dimensions)
                let subbandWidth = (levelWidth + 1) / 2
                let subbandHeight = (levelHeight + 1) / 2
                
                // Calculate number of code blocks in this subband
                let blocksX = (subbandWidth + cbWidth - 1) / cbWidth
                let blocksY = (subbandHeight + cbHeight - 1) / cbHeight
                let codeBlockCount = blocksX * blocksY
                
                // Try to parse packet header for this subband
                // Note: This is a simplified approach - real packet parsing is complex
                do {
                    let header = try reader.decode(
                        layerIndex: layerIndex,
                        resolutionLevel: resLevel,
                        componentIndex: componentIndex,
                        precinctIndex: 0,
                        codeBlockCount: codeBlockCount
                    )
                    
                    guard !header.isEmpty else {
                        continue
                    }
                    
                    // Extract code block data for this subband
                    let inclusions = header.codeBlockInclusions
                    let passes = header.codingPasses
                    let lengths = header.dataLengths
                    
                    // Track which entry in lengths/passes we're reading
                    var dataIndex = 0
                    
                    for (idx, included) in inclusions.enumerated() {
                        guard included else { continue }
                        
                        guard dataIndex < lengths.count else { break }
                        
                        let dataLength = lengths[dataIndex]
                        let passCount = dataIndex < passes.count ? passes[dataIndex] : 0
                        dataIndex += 1  // Move to next data entry
                        
                        // Extract data
                        guard dataOffset + dataLength <= tileData.count else {
                            // Not enough data - skip remaining blocks
                            break
                        }
                        
                        let blockData = tileData.subdata(in: dataOffset..<dataOffset + dataLength)
                        dataOffset += dataLength
                        
                        // Calculate code block position within subband
                        let blockX = (idx % blocksX) * cbWidth
                        let blockY = (idx / blocksX) * cbHeight
                        
                        // Calculate actual block dimensions (may be smaller at edges)
                        let actualWidth = min(cbWidth, subbandWidth - blockX)
                        let actualHeight = min(cbHeight, subbandHeight - blockY)
                        
                        blocks.append(CodeBlockInfo(
                            componentIndex: componentIndex,
                            level: resLevel,
                            subband: subband,
                            x: blockX,
                            y: blockY,
                            width: actualWidth,
                            height: actualHeight,
                            data: blockData,
                            passCount: passCount,
                            zeroBitPlanes: 0
                        ))
                    }
                } catch {
                    // Packet parsing failed - this is expected for simplified implementation
                    // Fall back to simplified single-level extraction
                    break
                }
            }
        }
        
        // If multi-level extraction failed, fall back to simplified single-level approach
        if blocks.isEmpty {
            // Reset and try simplified extraction
            reader = PacketHeaderReader(data: tileData)
            dataOffset = 0
            
            let header = try reader.decode(
                layerIndex: 0,
                resolutionLevel: 0,
                componentIndex: 0,
                precinctIndex: 0,
                codeBlockCount: 16
            )
            
            guard !header.isEmpty else {
                return []
            }
            
            let inclusions = header.codeBlockInclusions
            let passes = header.codingPasses
            let lengths = header.dataLengths
            
            // Track which entry in lengths/passes we're reading
            // The lengths/passes arrays contain data only for included blocks
            var dataIndex = 0
            
            for (idx, included) in inclusions.enumerated() {
                guard included else { continue }
                
                guard dataIndex < lengths.count else { break }
                
                let dataLength = lengths[dataIndex]
                let passCount = dataIndex < passes.count ? passes[dataIndex] : 0
                dataIndex += 1  // Move to next data entry
                
                guard dataOffset + dataLength <= tileData.count else {
                    throw J2KError.decodingError("Insufficient data for code block \(idx)")
                }
                
                let blockData = tileData.subdata(in: dataOffset..<dataOffset + dataLength)
                dataOffset += dataLength
                
                blocks.append(CodeBlockInfo(
                    componentIndex: 0,
                    level: 0,
                    subband: .ll,
                    x: (idx % 8) * cbWidth,
                    y: (idx / 8) * cbHeight,
                    width: cbWidth,
                    height: cbHeight,
                    data: blockData,
                    passCount: passCount,
                    zeroBitPlanes: 0
                ))
            }
        }
        
        return blocks
    }
    
    // MARK: - Stage 3: Entropy Decoding
    
    /// Decoded subband information.
    struct SubbandInfo: Sendable {
        let componentIndex: Int
        let level: Int
        let subband: J2KSubband
        let coefficients: [Int32]
        let width: Int
        let height: Int
    }
    
    /// Applies entropy decoding to code blocks.
    private func applyEntropyDecoding(
        _ blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata
    ) throws -> [SubbandInfo] {
        let decoder = CodeBlockDecoder()
        var subbandData: [String: [Int32]] = [:]
        var subbandDims: [String: (width: Int, height: Int)] = [:]
        
        // Decode each code block
        for block in blocks {
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
            
            let compInfo = metadata.components[block.componentIndex]
            let coeffs = try decoder.decode(
                codeBlock: codeBlock,
                bitDepth: compInfo.bitDepth
            )
            
            // Accumulate coefficients for subband
            let key = "\(block.componentIndex)_\(block.level)_\(block.subband.rawValue)"
            if subbandData[key] == nil {
                subbandData[key] = []
                subbandDims[key] = (width: 0, height: 0)
            }
            
            subbandData[key]?.append(contentsOf: coeffs)
            
            // Update dimensions
            let currentWidth = subbandDims[key]?.width ?? 0
            let currentHeight = subbandDims[key]?.height ?? 0
            subbandDims[key] = (
                width: max(currentWidth, block.x + block.width),
                height: max(currentHeight, block.y + block.height)
            )
        }
        
        // Convert to SubbandInfo array
        var subbands: [SubbandInfo] = []
        for (key, coeffs) in subbandData {
            let parts = key.split(separator: "_")
            guard parts.count == 3,
                  let compIdx = Int(parts[0]),
                  let level = Int(parts[1]),
                  let dims = subbandDims[key] else { continue }
            
            let subbandType = J2KSubband(rawValue: String(parts[2])) ?? .ll
            
            subbands.append(SubbandInfo(
                componentIndex: compIdx,
                level: level,
                subband: subbandType,
                coefficients: coeffs,
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
        
        for info in subbands {
            let key = "\(info.subband.rawValue)_\(info.level)"
            let stepSize = metadata.quantizationSteps[key] ?? 1.0
            
            // Dequantize coefficients
            let dequantized = info.coefficients.map { coeff in
                Int32(Double(coeff) * stepSize)
            }
            
            result.append(SubbandInfo(
                componentIndex: info.componentIndex,
                level: info.level,
                subband: info.subband,
                coefficients: dequantized,
                width: info.width,
                height: info.height
            ))
        }
        
        return result
    }
    
    // MARK: - Stage 5: Inverse Wavelet Transform
    
    /// Applies inverse wavelet transform to reconstruct spatial domain.
    private func applyInverseWaveletTransform(
        _ subbands: [SubbandInfo],
        metadata: CodestreamMetadata
    ) throws -> [[Int32]] {
        let filter = metadata.configuration.waveletFilter
        let levels = metadata.configuration.decompositionLevels
        var componentData: [[Int32]] = []
        
        // Group subbands by component
        let maxComponent = subbands.map { $0.componentIndex }.max() ?? 0
        
        for compIdx in 0...maxComponent {
            let compSubbands = subbands.filter { $0.componentIndex == compIdx }
            
            if compSubbands.isEmpty {
                // Empty component
                componentData.append([])
                continue
            }
            
            // Find LL subband
            guard let llSubband = compSubbands.first(where: { $0.subband == .ll }) else {
                throw J2KError.decodingError("Missing LL subband for component \(compIdx)")
            }
            
            let width = llSubband.width
            let height = llSubband.height
            
            // For now, if no decomposition levels, just return LL subband
            if levels == 0 {
                componentData.append(llSubband.coefficients)
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
            
            // Check if we have all subbands for multi-level reconstruction
            let hasAllSubbands = (1...levels).allSatisfy { level in
                compSubbands.contains(where: { $0.level == level && $0.subband == .lh }) &&
                compSubbands.contains(where: { $0.level == level && $0.subband == .hl }) &&
                compSubbands.contains(where: { $0.level == level && $0.subband == .hh })
            }
            
            if hasAllSubbands {
                // Full multi-level IDWT reconstruction
                // Start with coarsest LL subband and reconstruct level by level
                var currentLL = to2D(llSubband.coefficients, width: width, height: height)
                
                // Reconstruct from coarsest to finest level
                for level in (1...levels).reversed() {
                    guard let lhInfo = compSubbands.first(where: { $0.level == level && $0.subband == .lh }),
                          let hlInfo = compSubbands.first(where: { $0.level == level && $0.subband == .hl }),
                          let hhInfo = compSubbands.first(where: { $0.level == level && $0.subband == .hh }) else {
                        throw J2KError.decodingError("Missing subbands for level \(level)")
                    }
                    
                    let lh2D = to2D(lhInfo.coefficients, width: lhInfo.width, height: lhInfo.height)
                    let hl2D = to2D(hlInfo.coefficients, width: hlInfo.width, height: hlInfo.height)
                    let hh2D = to2D(hhInfo.coefficients, width: hhInfo.width, height: hhInfo.height)
                    
                    // Apply single-level inverse transform
                    // Use optimized path for lossless (reversible 5/3 filter)
                    if case .reversible53 = filter {
                        let optimizer = J2KDWT2DOptimizer()
                        currentLL = try optimizer.inverseTransform2DOptimized(
                            ll: currentLL,
                            lh: lh2D,
                            hl: hl2D,
                            hh: hh2D,
                            boundaryExtension: .symmetric
                        )
                    } else {
                        // Use standard transform for lossy modes
                        currentLL = try J2KDWT2D.inverseTransform(
                            ll: currentLL,
                            lh: lh2D,
                            hl: hl2D,
                            hh: hh2D,
                            filter: filter
                        )
                    }
                }
                
                // Flatten final reconstructed image to 1D array
                let flattened = currentLL.flatMap { $0 }
                componentData.append(flattened)
            } else {
                // Simplified path: Only LL subband available (current decoder limitation)
                // This is the current implementation - just return LL subband
                let image2D = to2D(llSubband.coefficients, width: width, height: height)
                let flattened = image2D.flatMap { $0 }
                componentData.append(flattened)
            }
        }
        
        return componentData
    }
    
    // MARK: - Stage 6: Inverse Color Transform
    
    /// Applies inverse color transform.
    private func applyInverseColorTransform(
        _ components: [[Int32]],
        metadata: CodestreamMetadata
    ) throws -> [[Int32]] {
        // Only apply if 3+ components
        guard components.count >= 3 else { return components }
        
        // Apply inverse RCT/ICT based on configuration
        if metadata.configuration.useReversibleTransform {
            let transform = J2KColorTransform(configuration: J2KColorTransformConfiguration(mode: .reversible))
            let (r, g, b) = try transform.inverseRCT(
                y: components[0],
                cb: components[1],
                cr: components[2]
            )
            
            var result = [r, g, b]
            if components.count > 3 {
                result.append(contentsOf: components[3...])
            }
            return result
        } else {
            // ICT not yet implemented in pipeline
            return components
        }
    }
    
    // MARK: - Stage 7: Image Reconstruction
    
    /// Reconstructs the final J2KImage from component data.
    private func reconstructImage(
        _ components: [[Int32]],
        metadata: CodestreamMetadata
    ) throws -> J2KImage {
        var imageComponents: [J2KComponent] = []
        
        for (idx, compData) in components.enumerated() {
            guard idx < metadata.components.count else { break }
            
            let compInfo = metadata.components[idx]
            let width = metadata.width / compInfo.subsamplingX
            let height = metadata.height / compInfo.subsamplingY
            
            // Convert Int32 array to Data
            var data = Data()
            if compInfo.bitDepth <= 8 {
                for value in compData {
                    if compInfo.signed {
                        data.append(UInt8(bitPattern: Int8(clamping: value)))
                    } else {
                        data.append(UInt8(clamping: max(0, value)))
                    }
                }
            } else {
                for value in compData {
                    let uint16Value: UInt16
                    if compInfo.signed {
                        uint16Value = UInt16(bitPattern: Int16(clamping: value))
                    } else {
                        uint16Value = UInt16(clamping: max(0, value))
                    }
                    data.append(UInt8(uint16Value >> 8))
                    data.append(UInt8(uint16Value & 0xFF))
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
