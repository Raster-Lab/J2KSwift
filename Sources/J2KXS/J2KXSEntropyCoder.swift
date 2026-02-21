// J2KXSEntropyCoder.swift
// J2KSwift
//
// Entropy coding and packetisation scaffolds for JPEG XS (ISO/IEC 21122).
//
// JPEG XS uses MICT (Multi-component Inverse Colour Transform) for colour
// de-correlation and PREC (Prefix-code Entropy Coder) for lossless
// compression of quantised coefficients within each slice.  This file
// provides the type definitions and actor scaffolds for these stages.

import Foundation
import J2KCore

// MARK: - J2KXSEntropyMode

/// The entropy coding mode applied to quantised coefficients.
///
/// ISO/IEC 21122 allows the encoder to choose between a significance-range
/// and a variance-adaptive prefix-code mode per subband.
public enum J2KXSEntropyMode: Sendable, Equatable, CaseIterable {
    /// Significance-range mode — prefix codes based on coefficient magnitude
    /// ranges.  Preferred for sparse, high-energy subbands.
    case significanceRange

    /// Variance-adaptive mode — prefix codes adapted to the estimated
    /// variance of each subband.  Preferred for dense, low-energy detail
    /// subbands.
    case varianceAdaptive

    /// The identifier written into the JPEG XS packet header for this mode.
    public var packetHeaderID: UInt8 {
        switch self {
        case .significanceRange: return 0x00
        case .varianceAdaptive:  return 0x01
        }
    }
}

// MARK: - J2KXSEncodedSlice

/// A compressed slice of one JPEG XS image component.
///
/// A slice represents the entropy-coded data for a horizontal stripe of
/// `lineCount` image lines.  The `lineOffset` field records the first line
/// of the stripe within the full image.
public struct J2KXSEncodedSlice: Sendable, Equatable {
    /// The compressed byte payload for this slice.
    public let data: Data

    /// The first image line included in this slice (0-based).
    public let lineOffset: Int

    /// The number of image lines in this slice.
    public let lineCount: Int

    /// The component index this slice belongs to.
    public let componentIndex: Int

    /// Creates an encoded slice.
    ///
    /// - Parameters:
    ///   - data: Compressed bytes.
    ///   - lineOffset: First image line in this slice.
    ///   - lineCount: Number of lines (clamped to ≥ 1).
    ///   - componentIndex: Zero-based component index.
    public init(data: Data, lineOffset: Int, lineCount: Int, componentIndex: Int) {
        self.data = data
        self.lineOffset = max(0, lineOffset)
        self.lineCount = max(1, lineCount)
        self.componentIndex = max(0, componentIndex)
    }

    /// The number of compressed bytes in this slice.
    public var byteCount: Int { data.count }
}

// MARK: - J2KXSPacketHeader

/// The fixed-size header prepended to each JPEG XS slice packet.
///
/// The header carries the entropy mode, component index, line offset and
/// count so that a decoder can locate and process slices independently.
public struct J2KXSPacketHeader: Sendable, Equatable {
    /// Magic bytes identifying a JPEG XS packet.
    public static let magic: UInt16 = 0xFF10

    /// Entropy mode applied to this slice.
    public let entropyMode: J2KXSEntropyMode

    /// Zero-based component index.
    public let componentIndex: Int

    /// First image line in this slice.
    public let lineOffset: Int

    /// Number of lines in this slice.
    public let lineCount: Int

    /// Byte length of the slice payload (excluding this header).
    public let payloadLength: Int

    /// Creates a packet header.
    public init(
        entropyMode: J2KXSEntropyMode,
        componentIndex: Int,
        lineOffset: Int,
        lineCount: Int,
        payloadLength: Int
    ) {
        self.entropyMode = entropyMode
        self.componentIndex = componentIndex
        self.lineOffset = lineOffset
        self.lineCount = lineCount
        self.payloadLength = payloadLength
    }

    /// The serialised byte size of this header.
    public static let serialisedSize = 10
}

// MARK: - J2KXSPacketiser

/// Packs quantised JPEG XS slice data into a byte stream and unpacks it
/// on the decoder side.
///
/// The packetiser inserts a ``J2KXSPacketHeader`` before each slice payload
/// so that the decoder can random-access individual slices within the
/// codestream.
///
/// Example:
/// ```swift
/// let packetiser = J2KXSPacketiser()
/// let codestream = try await packetiser.pack(slices: encodedSlices, mode: .significanceRange)
/// let recovered = try await packetiser.unpack(codestream)
/// ```
public actor J2KXSPacketiser {
    /// Total slices packed.
    private(set) var packedSliceCount: Int = 0

    /// Total slices unpacked.
    private(set) var unpackedSliceCount: Int = 0

    /// Creates a new packetiser.
    public init() {}

    // MARK: Pack

    /// Serialises a collection of encoded slices into a JPEG XS codestream.
    ///
    /// - Parameters:
    ///   - slices: The slices to pack, in any order.
    ///   - mode: The entropy mode to record in each packet header.
    /// - Returns: A `Data` buffer containing the serialised packets.
    /// - Throws: ``J2KXSError/encodingFailed(_:)`` if no slices are provided.
    public func pack(slices: [J2KXSEncodedSlice], mode: J2KXSEntropyMode) async throws -> Data {
        guard !slices.isEmpty else {
            throw J2KXSError.encodingFailed("Cannot pack an empty slice list.")
        }

        var buffer = Data()
        for slice in slices {
            var header = Data(capacity: J2KXSPacketHeader.serialisedSize)
            // Magic (2 bytes)
            header.append(UInt8(J2KXSPacketHeader.magic >> 8))
            header.append(UInt8(J2KXSPacketHeader.magic & 0xFF))
            // Entropy mode (1 byte)
            header.append(mode.packetHeaderID)
            // Component index (1 byte)
            header.append(UInt8(slice.componentIndex & 0xFF))
            // Line offset (2 bytes, big-endian)
            header.append(UInt8((slice.lineOffset >> 8) & 0xFF))
            header.append(UInt8(slice.lineOffset & 0xFF))
            // Line count (2 bytes, big-endian)
            header.append(UInt8((slice.lineCount >> 8) & 0xFF))
            header.append(UInt8(slice.lineCount & 0xFF))
            // Payload length (2 bytes, big-endian)
            header.append(UInt8((slice.data.count >> 8) & 0xFF))
            header.append(UInt8(slice.data.count & 0xFF))

            buffer.append(header)
            buffer.append(slice.data)
        }

        packedSliceCount += slices.count
        return buffer
    }

    // MARK: Unpack

    /// Deserialises a JPEG XS codestream into individual encoded slices.
    ///
    /// - Parameter codestream: The byte buffer to unpack.
    /// - Returns: An array of ``J2KXSEncodedSlice`` values.
    /// - Throws: ``J2KXSError/decodingFailed(_:)`` if the stream is
    ///           truncated or contains invalid magic bytes.
    public func unpack(_ codestream: Data) async throws -> [J2KXSEncodedSlice] {
        var slices: [J2KXSEncodedSlice] = []
        var offset = 0
        let bytes = [UInt8](codestream)

        while offset < bytes.count {
            let remaining = bytes.count - offset

            guard remaining >= J2KXSPacketHeader.serialisedSize else {
                throw J2KXSError.decodingFailed(
                    "Truncated header at offset \(offset): need " +
                    "\(J2KXSPacketHeader.serialisedSize) bytes, only \(remaining) available."
                )
            }

            // Verify magic.
            let magic = UInt16(bytes[offset]) << 8 | UInt16(bytes[offset + 1])
            guard magic == J2KXSPacketHeader.magic else {
                throw J2KXSError.decodingFailed(
                    "Invalid magic 0x\(String(format: "%04X", magic)) at offset \(offset)."
                )
            }

            let componentIndex = Int(bytes[offset + 3])
            let lineOffset = Int(bytes[offset + 4]) << 8 | Int(bytes[offset + 5])
            let lineCount  = Int(bytes[offset + 6]) << 8 | Int(bytes[offset + 7])
            let payloadLen = Int(bytes[offset + 8]) << 8 | Int(bytes[offset + 9])

            offset += J2KXSPacketHeader.serialisedSize

            guard offset + payloadLen <= bytes.count else {
                throw J2KXSError.decodingFailed(
                    "Truncated payload at offset \(offset): need \(payloadLen) bytes."
                )
            }

            let payload = Data(bytes[offset..<(offset + payloadLen)])
            slices.append(J2KXSEncodedSlice(
                data: payload,
                lineOffset: lineOffset,
                lineCount: lineCount,
                componentIndex: componentIndex
            ))
            offset += payloadLen
        }

        unpackedSliceCount += slices.count
        return slices
    }

    // MARK: Diagnostics

    /// Resets the packed/unpacked slice counters.
    public func resetStatistics() {
        packedSliceCount = 0
        unpackedSliceCount = 0
    }
}
