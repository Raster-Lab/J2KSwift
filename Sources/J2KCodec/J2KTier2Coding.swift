//
// J2KTier2Coding.swift
// J2KSwift
//
/// # Tier-2 Coding
///
/// Implementation of JPEG 2000 Tier-2 coding (packet header encoding/decoding).
///
/// Tier-2 coding organizes the output of Tier-1 coding (code-block contributions)
/// into packets. Each packet contains data for one precinct in one quality layer.
/// The packet header describes which code-blocks contribute data and how many
/// coding passes are included from each code-block.
///
/// ## Topics
///
/// ### Progression Orders
/// - ``ProgressionOrder``
///
/// ### Packet Headers
/// - ``PacketHeader``
/// - ``PacketHeaderWriter``
/// - ``PacketHeaderReader``
///
/// ### Layer Formation
/// - ``QualityLayer``
/// - ``LayerFormation``

import Foundation
import J2KCore

// MARK: - Progression Order

/// Defines the order in which packets are written to the codestream.
///
/// JPEG 2000 supports five progression orders that determine how image data
/// is organised for transmission. Each order provides different benefits for
/// specific use cases.
public enum ProgressionOrder: UInt8, Sendable, CaseIterable {
    /// Layer-Resolution-Component-Position (LRCP).
    ///
    /// Packets are ordered by quality layer first, then resolution level,
    /// then component, and finally spatial position. This order is optimal
    /// for progressive quality refinement.
    case lrcp = 0

    /// Resolution-Layer-Component-Position (RLCP).
    ///
    /// Packets are ordered by resolution level first, then quality layer,
    /// then component, and finally spatial position. This order is optimal
    /// for progressive resolution refinement.
    case rlcp = 1

    /// Resolution-Position-Component-Layer (RPCL).
    ///
    /// Packets are ordered by resolution level, then spatial position,
    /// then component, and finally quality layer. This order allows for
    /// efficient spatial region-of-interest decoding.
    case rpcl = 2

    /// Position-Component-Resolution-Layer (PCRL).
    ///
    /// Packets are ordered by spatial position first, then component,
    /// then resolution level, and finally quality layer. This order is
    /// optimal for random access to spatial regions.
    case pcrl = 3

    /// Component-Position-Resolution-Layer (CPRL).
    ///
    /// Packets are ordered by component first, then spatial position,
    /// then resolution level, and finally quality layer. This order is
    /// useful for component-specific processing.
    case cprl = 4

    /// Returns a human-readable name for the progression order.
    public var name: String {
        switch self {
        case .lrcp: return "LRCP (Layer-Resolution-Component-Position)"
        case .rlcp: return "RLCP (Resolution-Layer-Component-Position)"
        case .rpcl: return "RPCL (Resolution-Position-Component-Layer)"
        case .pcrl: return "PCRL (Position-Component-Resolution-Layer)"
        case .cprl: return "CPRL (Component-Position-Resolution-Layer)"
        }
    }

    /// Returns a short acronym for the progression order.
    public var acronym: String {
        switch self {
        case .lrcp: return "LRCP"
        case .rlcp: return "RLCP"
        case .rpcl: return "RPCL"
        case .pcrl: return "PCRL"
        case .cprl: return "CPRL"
        }
    }
}

// MARK: - Quality Layer

/// Represents a quality layer in JPEG 2000 encoding.
///
/// Quality layers allow for progressive quality refinement. Each layer contains
/// additional coding passes from code-blocks, progressively improving image quality.
public struct QualityLayer: Sendable {
    /// The layer index (0-based).
    public let index: Int

    /// The target bit rate for this layer (bits per pixel), or nil for lossless.
    public let targetRate: Double?

    /// Code-block contributions for this layer.
    ///
    /// Maps code-block index to the number of coding passes included from that block.
    public var codeBlockContributions: [Int: Int]

    /// Creates a new quality layer.
    ///
    /// - Parameters:
    ///   - index: The layer index.
    ///   - targetRate: The target bit rate in bits per pixel (nil for lossless).
    ///   - codeBlockContributions: The code-block contributions.
    public init(
        index: Int,
        targetRate: Double? = nil,
        codeBlockContributions: [Int: Int] = [:]
    ) {
        self.index = index
        self.targetRate = targetRate
        self.codeBlockContributions = codeBlockContributions
    }
}

// MARK: - Packet Header

/// Represents the header of a packet in the JPEG 2000 codestream.
///
/// A packet header contains information about code-block contributions
/// to the current quality layer for a specific precinct.
public struct PacketHeader: Sendable {
    /// The layer index this packet belongs to.
    public let layerIndex: Int

    /// The resolution level index.
    public let resolutionLevel: Int

    /// The component index.
    public let componentIndex: Int

    /// The precinct index.
    public let precinctIndex: Int

    /// Whether the packet is empty (no code-block data).
    public let isEmpty: Bool

    /// Code-block inclusion information.
    ///
    /// For each code-block in the precinct, indicates whether it has
    /// any contribution in this packet.
    public var codeBlockInclusions: [Bool]

    /// Number of coding passes for each included code-block.
    ///
    /// Only valid for code-blocks where `codeBlockInclusions` is true.
    public var codingPasses: [Int]

    /// Length of encoded data for each included code-block.
    ///
    /// Only valid for code-blocks where `codeBlockInclusions` is true.
    public var dataLengths: [Int]

    /// Number of zero bit-planes for each included code-block.
    ///
    /// Only used for the first inclusion of a code-block. Subsequent
    /// layers ignore this field.
    public var zeroBitPlanes: [Int]

    /// Creates a new packet header.
    ///
    /// - Parameters:
    ///   - layerIndex: The quality layer index.
    ///   - resolutionLevel: The resolution level.
    ///   - componentIndex: The component index.
    ///   - precinctIndex: The precinct index.
    ///   - isEmpty: Whether the packet is empty.
    ///   - codeBlockInclusions: Code-block inclusion flags.
    ///   - codingPasses: Number of coding passes per code-block.
    ///   - dataLengths: Data lengths per code-block.
    ///   - zeroBitPlanes: Zero bit-plane counts per code-block.
    public init(
        layerIndex: Int,
        resolutionLevel: Int,
        componentIndex: Int,
        precinctIndex: Int,
        isEmpty: Bool = false,
        codeBlockInclusions: [Bool] = [],
        codingPasses: [Int] = [],
        dataLengths: [Int] = [],
        zeroBitPlanes: [Int] = []
    ) {
        self.layerIndex = layerIndex
        self.resolutionLevel = resolutionLevel
        self.componentIndex = componentIndex
        self.precinctIndex = precinctIndex
        self.isEmpty = isEmpty
        self.codeBlockInclusions = codeBlockInclusions
        self.codingPasses = codingPasses
        self.dataLengths = dataLengths
        self.zeroBitPlanes = zeroBitPlanes
    }
}

// MARK: - Packet Header Writer

/// Writes packet headers to the JPEG 2000 codestream.
///
/// Encodes packet headers using the raw bitstream format defined in
/// ISO/IEC 15444-1 Annex B.10. Each packet header contains:
/// 1. Non-empty flag (1 bit)
/// 2. Code-block inclusion bits (1 bit per block; simplified tag-tree)
/// 3. Zero bit-plane information (for first inclusion only)
/// 4. Number of coding passes (Table B.4 prefix code)
/// 5. Data lengths (Lblock + length bits per Table B.5)
///
/// The writer tracks per-block state across layers so that subsequent
/// packets only encode incremental information.
public struct PacketHeaderWriter: Sendable {
    /// Per-block state tracking across layers.
    ///
    /// Tracks whether a block has been included before and the current
    /// Lblock value (initial length exponent) for length coding.
    private var blockIncluded: [Int: Bool]

    /// Current Lblock value per block (initial = 3).
    private var blockLblock: [Int: Int]

    /// Creates a new packet header writer.
    public init() {
        self.blockIncluded = [:]
        self.blockLblock = [:]
    }

    /// Resets per-block state for a new tile or codestream.
    public mutating func reset() {
        blockIncluded.removeAll()
        blockLblock.removeAll()
    }

    /// Encodes a packet header.
    ///
    /// - Parameters:
    ///   - header: The packet header to encode.
    ///   - blockIndices: The code-block indices corresponding to each
    ///     position in `codeBlockInclusions`, used for state tracking.
    ///     When nil, sequential indices (0, 1, 2 ...) are assumed.
    /// - Returns: The encoded packet header data.
    /// - Throws: ``J2KError`` if encoding fails.
    public mutating func encode(
        _ header: PacketHeader,
        blockIndices: [Int]? = nil
    ) throws -> Data {
        var writer = J2KBitWriter()

        // 1. Non-empty flag (1 bit): 0 = empty, 1 = has data
        if header.isEmpty {
            writer.writeBit(false)
            writer.alignToByte()
            return writer.data
        }
        writer.writeBit(true)

        // Build sequential block indices if not provided
        let indices = blockIndices ?? Array(0..<header.codeBlockInclusions.count)

        // Track which blocks are first-included in THIS packet
        var blockFirstIncludedThisPacket = Set<Int>()

        // 2. Code-block inclusion bits
        //    First inclusion uses tag-tree coding (simplified to 1-bit here
        //    since we treat the whole precinct as a single leaf).
        //    Subsequent inclusions use 1 bit: 1 = included, 0 = not.
        for (i, included) in header.codeBlockInclusions.enumerated() {
            let blockIdx = i < indices.count ? indices[i] : i
            let firstTime = !(blockIncluded[blockIdx] ?? false)

            if firstTime {
                // Tag-tree coded first inclusion: write 1 if included, 0 if not.
                writer.writeBit(included)
                if included {
                    blockIncluded[blockIdx] = true
                    blockFirstIncludedThisPacket.insert(blockIdx)
                }
            } else {
                // Already included in a previous layer: 1-bit flag.
                writer.writeBit(included)
            }
        }

        // 3. For newly included blocks: encode the number of zero bit-planes
        //    using a simplified tag-tree (unary: emit P zeros then a one).
        var zbpIndex = 0
        for (i, included) in header.codeBlockInclusions.enumerated() {
            let blockIdx = i < indices.count ? indices[i] : i
            let wasFirstInclusion = included && blockFirstIncludedThisPacket.contains(blockIdx)
            if wasFirstInclusion {
                let P = zbpIndex < header.zeroBitPlanes.count
                    ? header.zeroBitPlanes[zbpIndex] : 0
                // Unary code: P zeros followed by a one
                for _ in 0..<P {
                    writer.writeBit(false)
                }
                writer.writeBit(true)
            }
            if included {
                zbpIndex += 1
            }
        }

        // 4. Number of coding passes (Table B.4):
        //    1        →  0
        //    2        →  10
        //    3-5      →  1100 + (n-3) in 2 bits
        //    6-36     →  1101 + (n-6) in 5 bits
        //    37-164   →  1110 + (n-37) in 7 bits
        //    We use a simpler compatible prefix code:
        //    1    → 0
        //    2    → 10
        //    3-5  → 1100 .. 1110 (2-bit suffix)
        //    ≥6   → 1111 + (n-6) in remaining bits
        var passIndex = 0
        for included in header.codeBlockInclusions where included {
            guard passIndex < header.codingPasses.count else {
                throw J2KError.invalidData("Missing coding pass count")
            }
            let nPasses = header.codingPasses[passIndex]
            try encodeCodingPasses(&writer, count: nPasses)
            passIndex += 1
        }

        // 5. Data length for each included code-block.
        //    Uses Lblock (initial = 3) with possible increment bits.
        //    Length is encoded in (Lblock + floor(log2(nPasses))) bits.
        var dataIndex = 0
        for (i, included) in header.codeBlockInclusions.enumerated() where included {
            guard dataIndex < header.dataLengths.count else {
                throw J2KError.invalidData("Missing data length")
            }
            let blockIdx = i < indices.count ? indices[i] : i
            let length = header.dataLengths[dataIndex]
            let nPasses = dataIndex < header.codingPasses.count
                ? header.codingPasses[dataIndex] : 1

            try encodeDataLength(&writer, length: length, nPasses: nPasses,
                                 blockIdx: blockIdx)
            dataIndex += 1
        }

        // Byte-align the header
        writer.alignToByte()

        return writer.data
    }

    /// Encodes multiple packet headers in sequence.
    ///
    /// - Parameters:
    ///   - headers: The packet headers to encode.
    ///   - blockIndices: Block indices (shared across all headers).
    /// - Returns: The encoded packet headers data.
    /// - Throws: ``J2KError`` if encoding fails.
    public mutating func encodeMultiple(
        _ headers: [PacketHeader],
        blockIndices: [Int]? = nil
    ) throws -> Data {
        var allData = Data()
        for header in headers {
            let headerData = try encode(header, blockIndices: blockIndices)
            allData.append(headerData)
        }
        return allData
    }

    // MARK: - Private Encoding Helpers

    /// Encodes the number of coding passes using the Table B.4 prefix code.
    ///
    /// | Passes | Codeword          |
    /// |--------|-------------------|
    /// | 1      | 0                 |
    /// | 2      | 10                |
    /// | 3–5    | 1100 + (n-3) 2b   |
    /// | 6–36   | 1101 + (n-6) 5b   |
    /// | 37–164 | 1110 + (n-37) 7b  |
    private func encodeCodingPasses(
        _ writer: inout J2KBitWriter, count: Int
    ) throws {
        switch count {
        case 1:
            writer.writeBit(false) // 0
        case 2:
            writer.writeBit(true)  // 1
            writer.writeBit(false) // 0
        case 3...5:
            // 1100 prefix + 2-bit suffix
            writer.writeBit(true)
            writer.writeBit(true)
            writer.writeBit(false)
            writer.writeBit(false)
            try writer.writeBits(UInt32(count - 3), count: 2)
        case 6...36:
            // 1101 prefix + 5-bit suffix
            writer.writeBit(true)
            writer.writeBit(true)
            writer.writeBit(false)
            writer.writeBit(true)
            try writer.writeBits(UInt32(count - 6), count: 5)
        case 37...164:
            // 1110 prefix + 7-bit suffix
            writer.writeBit(true)
            writer.writeBit(true)
            writer.writeBit(true)
            writer.writeBit(false)
            try writer.writeBits(UInt32(count - 37), count: 7)
        default:
            throw J2KError.invalidParameter(
                "Unsupported coding pass count: \(count)")
        }
    }

    /// Encodes a data length using the Lblock mechanism (Annex B.10.5).
    ///
    /// Each block starts with Lblock = 3. The encoder writes increment bits
    /// (1 = increase Lblock by 1, 0 = stop) followed by the length value
    /// in (Lblock + floor(log2(nPasses))) bits.
    private mutating func encodeDataLength(
        _ writer: inout J2KBitWriter,
        length: Int,
        nPasses: Int,
        blockIdx: Int
    ) throws {
        let lblock = blockLblock[blockIdx] ?? 3
        let passLog = nPasses > 1 ? Int(log2(Double(nPasses))) : 0
        let totalBits = lblock + passLog

        // Check if length fits in current Lblock
        var neededBits = totalBits
        if length > 0 {
            let bitsRequired = Int(log2(Double(length))) + 1
            if bitsRequired > totalBits {
                neededBits = bitsRequired
            }
        }

        // Write increment bits if we need more than current Lblock allows
        let increments = max(0, neededBits - totalBits)
        for _ in 0..<increments {
            writer.writeBit(true) // increment Lblock
        }
        writer.writeBit(false) // stop incrementing

        let finalLblock = lblock + increments
        let finalBits = finalLblock + passLog
        blockLblock[blockIdx] = finalLblock

        // Write the length value
        if finalBits > 0 {
            try writer.writeBits(UInt32(length), count: finalBits)
        }
    }
}

// MARK: - Packet Header Reader

/// Reads packet headers from the JPEG 2000 codestream.
///
/// The packet header reader decodes packet information that was encoded
/// using tag trees and arithmetic coding.
///
/// ## Example
///
/// ```swift
/// let reader = PacketHeaderReader(data: codestreamData)
/// let header = try reader.decode(
///     layerIndex: 0,
///     resolutionLevel: 0,
///     componentIndex: 0,
///     precinctIndex: 0,
///     codeBlockCount: 16
/// )
/// ```
public struct PacketHeaderReader: Sendable {
    /// The codestream data.
    private let data: Data

    /// The current read position.
    private var position: Int

    /// Creates a new packet header reader.
    ///
    /// - Parameters:
    ///   - data: The codestream data.
    ///   - position: The initial read position (default: 0).
    public init(data: Data, position: Int = 0) {
        self.data = data
        self.position = position
    }

    /// Decodes a packet header.
    ///
    /// - Parameters:
    ///   - layerIndex: The expected layer index.
    ///   - resolutionLevel: The expected resolution level.
    ///   - componentIndex: The expected component index.
    ///   - precinctIndex: The expected precinct index.
    ///   - codeBlockCount: The number of code-blocks in the precinct.
    /// - Returns: The decoded packet header.
    /// - Throws: ``J2KError`` if decoding fails.
    public mutating func decode(
        layerIndex: Int,
        resolutionLevel: Int,
        componentIndex: Int,
        precinctIndex: Int,
        codeBlockCount: Int
    ) throws -> PacketHeader {
        var reader = J2KBitReader(data: data)
        try reader.seek(to: position)

        // Read empty packet flag
        let notEmpty = try reader.readBit()
        if !notEmpty {
            position = reader.position
            return PacketHeader(
                layerIndex: layerIndex,
                resolutionLevel: resolutionLevel,
                componentIndex: componentIndex,
                precinctIndex: precinctIndex,
                isEmpty: true
            )
        }

        // Initialise MQ decoder
        let mqData = data.suffix(from: reader.position)
        var decoder = MQDecoder(data: mqData)
        var context = MQContext()

        // Decode code-block inclusions
        var inclusions = [Bool]()
        for _ in 0..<codeBlockCount {
            let included = decoder.decode(context: &context)
            inclusions.append(included)
        }

        // Decode coding passes for included code-blocks
        var codingPasses = [Int]()
        for included in inclusions where included {
            // Decode number of passes
            let firstBit = decoder.decode(context: &context)
            if firstBit {
                // Single pass
                codingPasses.append(1)
            } else {
                let secondBit = decoder.decode(context: &context)
                if secondBit {
                    // 2 or 3 passes
                    let thirdBit = decoder.decode(context: &context)
                    codingPasses.append(thirdBit ? 3 : 2)
                } else {
                    // More than 3 passes
                    var passes = 4
                    var bit = decoder.decode(context: &context)
                    var shift = 0
                    while bit {
                        passes += (1 << shift)
                        shift += 1
                        bit = decoder.decode(context: &context)
                    }
                    codingPasses.append(passes)
                }
            }
        }

        // Decode data lengths for included code-blocks
        var dataLengths = [Int]()
        for included in inclusions where included {
            var length = 0
            var shift = 0
            var bit = decoder.decode(context: &context)
            while bit {
                length += (1 << shift)
                shift += 1
                bit = decoder.decode(context: &context)
            }
            dataLengths.append(length)
        }

        // Update position (approximate - we advance by the data we've processed)
        // In practice, packet headers are followed by packet body, so position
        // management is handled by the higher-level packet parser
        position = reader.position

        return PacketHeader(
            layerIndex: layerIndex,
            resolutionLevel: resolutionLevel,
            componentIndex: componentIndex,
            precinctIndex: precinctIndex,
            isEmpty: false,
            codeBlockInclusions: inclusions,
            codingPasses: codingPasses,
            dataLengths: dataLengths
        )
    }
}

// MARK: - Layer Formation

/// Manages the formation of quality layers from code-block contributions.
///
/// The layer formation algorithm determines which coding passes from each
/// code-block should be included in each quality layer to achieve target
/// bit rates while maximising image quality.
public struct LayerFormation: Sendable {
    /// The target bit rates for each layer (bits per pixel).
    public let targetRates: [Double]

    /// Whether to use rate-distortion optimisation.
    public let useRDOptimization: Bool

    /// Creates a new layer formation configuration.
    ///
    /// - Parameters:
    ///   - targetRates: Target bit rates for each layer in bits per pixel.
    ///   - useRDOptimization: Whether to use rate-distortion optimisation (default: false).
    public init(targetRates: [Double], useRDOptimization: Bool = false) {
        self.targetRates = targetRates
        self.useRDOptimization = useRDOptimization
    }

    /// Forms quality layers from code-block data.
    ///
    /// - Parameters:
    ///   - codeBlocks: The code-blocks to organize into layers.
    ///   - totalPixels: The total number of pixels in the image.
    /// - Returns: An array of quality layers.
    /// - Throws: ``J2KError`` if layer formation fails.
    public func formLayers(
        codeBlocks: [J2KCodeBlock],
        totalPixels: Int
    ) throws -> [QualityLayer] {
        // Use rate-distortion optimisation if enabled
        if useRDOptimization {
            let rateControl = J2KRateControl(targetRates: targetRates)
            return try rateControl.optimizeLayers(
                codeBlocks: codeBlocks,
                totalPixels: totalPixels
            )
        }

        // Otherwise use simple proportional allocation
        var layers = [QualityLayer]()

        for (index, targetRate) in targetRates.enumerated() {
            var contributions = [Int: Int]()

            // Calculate target bytes for this layer
            let targetBytes = Int(targetRate * Double(totalPixels) / 8.0)
            var currentBytes = 0

            // Distribute coding passes to code-blocks
            for codeBlock in codeBlocks {
                // Simple strategy: include passes proportionally
                let maxPasses = min(codeBlock.passeCount, 3 * (index + 1))

                if maxPasses > 0 && currentBytes < targetBytes {
                    contributions[codeBlock.index] = maxPasses
                    currentBytes += codeBlock.data.count
                }
            }

            layers.append(QualityLayer(
                index: index,
                targetRate: targetRate,
                codeBlockContributions: contributions
            ))
        }

        return layers
    }

    /// Forms layers with lossless encoding (all passes in final layer).
    ///
    /// - Parameter codeBlocks: The code-blocks to organize.
    /// - Returns: A single quality layer containing all code-block data.
    public func formLosslessLayer(codeBlocks: [J2KCodeBlock]) -> QualityLayer {
        var contributions = [Int: Int]()

        for codeBlock in codeBlocks where codeBlock.passeCount > 0 {
            contributions[codeBlock.index] = codeBlock.passeCount
        }

        return QualityLayer(
            index: 0,
            targetRate: nil,
            codeBlockContributions: contributions
        )
    }
}
