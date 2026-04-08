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

        // Stage 6: Inverse colour transform
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 0.0)
        var rgbData = try applyInverseColorTransform(spatialData, metadata: metadata)
        reportProgress(progress, stage: .inverseColorTransform, stageProgress: 1.0)

        // DC level unshift: for unsigned components, add back 2^(bitDepth-1)
        // to reverse the ISO 15444-1 Annex F DC level shift applied during encoding.
        for (compIdx, compInfo) in metadata.components.enumerated() {
            guard compIdx < rgbData.count else { break }
            if !compInfo.signed {
                let dcOffset = Double(1 << (compInfo.bitDepth - 1))
                rgbData[compIdx] = rgbData[compIdx].map { $0 + dcOffset }
            }
        }

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
        var quantizationSteps: (steps: [String: Double], guardBits: Int, bandKb: [String: Int]) = ([:], 2, [:])
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
                let bitDepth = metadata?.components.first?.bitDepth ?? 8
                quantizationSteps = try parseQCDMarker(&reader, config: configuration, bitDepth: bitDepth)
            case J2KMarker.sot.rawValue:
                // Start of tile-part
                let (_, tilepartData) = try parseSOTMarker(&reader)
                tileData = tilepartData
                // Break after first tile for now

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
        meta.quantizationSteps = quantizationSteps.steps
        meta.quantizationGuardBits = quantizationSteps.guardBits
        meta.bandKbValues = quantizationSteps.bandKb

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
        // Bits 3-4: HT set extensions (ISO/IEC 15444-15)
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
                guard notEmpty else { continue }

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
    private func applyEntropyDecoding(
        _ blocks: [CodeBlockInfo],
        metadata: CodestreamMetadata
    ) throws -> [SubbandInfo] {
        let decoder = CodeBlockDecoder()
        let isIrreversible: Bool
        if case .irreversible97 = metadata.configuration.waveletFilter {
            isIrreversible = true
        } else {
            isIrreversible = false
        }
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
                bitDepth: block.bandKb > 0 ? block.bandKb : compInfo.bitDepth,
                irreversible: isIrreversible
            )

            let key = "\(block.componentIndex)_\(block.level)_\(block.subband.rawValue)"

            // Track maximum extent for subband dimensions
            let currentWidth = subbandDims[key]?.width ?? 0
            let currentHeight = subbandDims[key]?.height ?? 0
            subbandDims[key] = (
                width: max(currentWidth, block.x + block.width),
                height: max(currentHeight, block.y + block.height)
            )

            // Store decoded block with its position
            if subbandBlocks[key] == nil {
                subbandBlocks[key] = []
            }
            subbandBlocks[key]?.append(DecodedBlock(
                x: block.x, y: block.y,
                width: block.width, height: block.height,
                coefficients: coeffs
            ))
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
            for db in decodedBlocks {
                for row in 0..<db.height {
                    let srcStart = row * db.width
                    let dstStart = (db.y + row) * dims.width + db.x
                    for col in 0..<db.width {
                        if srcStart + col < db.coefficients.count {
                            subbandCoeffs[dstStart + col] = db.coefficients[srcStart + col]
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
                // EBCOT coefficients use bpno_plus_one scale (shifted left by 1)
                // to match OPJ's oneplushalf approach, so dequantization applies
                // ×0.5 to compensate. This ensures that the midpoint at bitPlane=0
                // (halfBitMask=1) correctly contributes +0.5 after dequantization.
                let halfStepSize = 0.5 * stepSize
                let dequantizedDouble = info.coefficients.map { coeff -> Double in
                    if coeff == 0 { return 0.0 }
                    let sign: Double = coeff > 0 ? 1.0 : -1.0
                    let magnitude = Double(abs(coeff))
                    return sign * magnitude * halfStepSize
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
                componentData.append(llSubband.coefficients.map { Double($0) })
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
                for row in 0..<copyH {
                    for col in 0..<copyW {
                        let idx = row * srcW + col
                        if idx < coeffs.count {
                            result[row][col] = coeffs[idx]
                        }
                    }
                }
                return result
            }

            func paddedDoubleFromInt(_ coeffs: [Int32], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Double]] {
                var result = [[Double]](repeating: [Double](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                for row in 0..<copyH {
                    for col in 0..<copyW {
                        let idx = row * srcW + col
                        if idx < coeffs.count {
                            result[row][col] = Double(coeffs[idx])
                        }
                    }
                }
                return result
            }

            func paddedDouble(_ coeffs: [Double], srcW: Int, srcH: Int, dstW: Int, dstH: Int) -> [[Double]] {
                var result = [[Double]](repeating: [Double](repeating: 0, count: dstW), count: dstH)
                let copyW = min(srcW, dstW)
                let copyH = min(srcH, dstH)
                for row in 0..<copyH {
                    for col in 0..<copyW {
                        let idx = row * srcW + col
                        if idx < coeffs.count {
                            result[row][col] = coeffs[idx]
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

                let flattened = currentLL.flatMap { $0.map { Double($0) } }
                componentData.append(flattened)
            }
        }

        return componentData
    }

    // MARK: - Stage 6: Inverse Colour Transform

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
                    y: components[0].map { Int32($0) },
                    cb: components[1].map { Int32($0) },
                    cr: components[2].map { Int32($0) }
                )

                var result: [[Double]] = [r.map { Double($0) }, g.map { Double($0) }, b.map { Double($0) }]
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
            var data = Data()
            if compInfo.bitDepth <= 8 {
                for value in compData {
                    let rounded = Int32(value.rounded())
                    if compInfo.signed {
                        data.append(UInt8(bitPattern: Int8(clamping: rounded)))
                    } else {
                        data.append(UInt8(clamping: max(0, rounded)))
                    }
                }
            } else {
                for value in compData {
                    let rounded = Int32(value.rounded())
                    let uint16Value: UInt16
                    if compInfo.signed {
                        uint16Value = UInt16(bitPattern: Int16(clamping: rounded))
                    } else {
                        uint16Value = UInt16(clamping: max(0, rounded))
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
