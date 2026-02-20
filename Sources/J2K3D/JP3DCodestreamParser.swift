//
// JP3DCodestreamParser.swift
// J2KSwift
//
/// # JP3DCodestreamParser
///
/// Parser for JP3D volumetric JPEG 2000 codestreams.
///
/// Reads and validates marker segments (SOC, SIZ, COD, QCD, SOT, SOD, EOC)
/// from a JP3D codestream produced by `JP3DCodestreamBuilder`, extracting
/// volume metadata and per-tile encoded data.
///
/// ## Topics
///
/// ### Parser Types
/// - ``JP3DCodestreamParser``
/// - ``JP3DParsedCodestream``
/// - ``JP3DParsedTile``

import Foundation
import J2KCore

/// Metadata parsed from a JP3D SIZ marker segment.
public struct JP3DSIZInfo: Sendable {
    /// Volume width.
    public let width: Int
    /// Volume height.
    public let height: Int
    /// Volume depth.
    public let depth: Int
    /// Tile width.
    public let tileSizeX: Int
    /// Tile height.
    public let tileSizeY: Int
    /// Tile depth.
    public let tileSizeZ: Int
    /// Number of components.
    public let componentCount: Int
    /// Bit depth per component (1-based, as stored: Ssiz+1).
    public let bitDepth: Int
    /// Whether components are signed.
    public let signed: Bool
}

/// Coding parameters parsed from a JP3D COD marker segment.
public struct JP3DCODInfo: Sendable {
    /// Decomposition levels along X.
    public let levelsX: Int
    /// Decomposition levels along Y.
    public let levelsY: Int
    /// Decomposition levels along Z.
    public let levelsZ: Int
    /// Whether lossless encoding was used (filter byte = 1).
    public let isLossless: Bool
}

/// Encoded data for a single tile parsed from the codestream.
public struct JP3DParsedTile: Sendable {
    /// The tile index (as written in the SOT marker).
    public let tileIndex: Int
    /// Raw encoded data for this tile (after the SOD marker).
    public let data: Data
}

/// Complete parsed representation of a JP3D codestream.
public struct JP3DParsedCodestream: Sendable {
    /// Volume and tile geometry from the SIZ marker.
    public let siz: JP3DSIZInfo
    /// Coding parameters from the COD marker.
    public let cod: JP3DCODInfo
    /// Whether quantization is lossless (QCD style = 0).
    public let isLosslessQuantization: Bool
    /// Per-tile encoded data, ordered by tile index.
    public let tiles: [JP3DParsedTile]

    /// Compute the tile grid for this codestream.
    public var tileGrid: (tilesX: Int, tilesY: Int, tilesZ: Int) {
        let tx = max(1, (siz.width + siz.tileSizeX - 1) / siz.tileSizeX)
        let ty = max(1, (siz.height + siz.tileSizeY - 1) / siz.tileSizeY)
        let tz = max(1, (siz.depth + siz.tileSizeZ - 1) / siz.tileSizeZ)
        return (tx, ty, tz)
    }
}

/// Parses a JP3D codestream written by `JP3DCodestreamBuilder`.
///
/// `JP3DCodestreamParser` reads marker segments in the sequence produced
/// by the encoder and extracts all information needed for decoding.
///
/// Example:
/// ```swift
/// let parser = JP3DCodestreamParser()
/// let codestream = try parser.parse(data)
/// print("Volume: \(codestream.siz.width)×\(codestream.siz.height)×\(codestream.siz.depth)")
/// ```
public struct JP3DCodestreamParser: Sendable {
    /// Creates a new codestream parser.
    public init() {}

    // MARK: - Public API

    /// Parses a JP3D codestream from raw data.
    ///
    /// - Parameter data: The codestream `Data` produced by `JP3DCodestreamBuilder`.
    /// - Returns: A `JP3DParsedCodestream` with all marker segments decoded.
    /// - Throws: ``J2KError/decodingError(_:)`` if the codestream is malformed or truncated.
    public func parse(_ data: Data) throws -> JP3DParsedCodestream {
        var offset = 0

        // --- SOC ---
        let socMarker = try readUInt16BE(data, at: &offset)
        guard socMarker == 0xFF4F else {
            throw J2KError.decodingError(
                "Missing SOC marker at start of codestream (got 0x\(String(socMarker, radix: 16)))"
            )
        }

        // --- SIZ ---
        var sizInfo: JP3DSIZInfo?
        var codInfo: JP3DCODInfo?
        var isLosslessQuan = true
        var parsedTiles: [JP3DParsedTile] = []
        var foundEOC = false

        while offset < data.count {
            guard offset + 2 <= data.count else { break }
            let marker = try readUInt16BE(data, at: &offset)

            switch marker {
            case 0xFF51: // SIZ
                sizInfo = try parseSIZ(data, at: &offset)
            case 0xFF52: // COD
                codInfo = try parseCOD(data, at: &offset)
            case 0xFF5C: // QCD
                isLosslessQuan = try parseQCD(data, at: &offset)
            case 0xFF64: // COM – skip
                let len = Int(try readUInt16BE(data, at: &offset))
                guard len >= 2 else {
                    throw J2KError.decodingError("COM marker has invalid length \(len)")
                }
                offset += len - 2
            case 0xFF90: // SOT
                let tile = try parseSOTAndData(data, at: &offset)
                parsedTiles.append(tile)
            case 0xFFD9: // EOC
                foundEOC = true
            default:
                // Unknown marker: try to skip using length field if present
                if marker >= 0xFF00 {
                    if offset + 2 <= data.count {
                        let len = Int(try readUInt16BE(data, at: &offset))
                        if len >= 2 {
                            offset += len - 2
                            continue
                        }
                    }
                }
                // If we can't skip, treat as truncated
            }

            if foundEOC { break }
        }

        guard let siz = sizInfo else {
            throw J2KError.decodingError("Codestream missing SIZ marker")
        }
        guard let cod = codInfo else {
            throw J2KError.decodingError("Codestream missing COD marker")
        }
        if parsedTiles.isEmpty {
            throw J2KError.decodingError("Codestream contains no tile data")
        }

        return JP3DParsedCodestream(
            siz: siz,
            cod: cod,
            isLosslessQuantization: isLosslessQuan,
            tiles: parsedTiles.sorted { $0.tileIndex < $1.tileIndex }
        )
    }

    // MARK: - Private Marker Parsers

    /// Parses the SIZ marker segment.
    private func parseSIZ(_ data: Data, at offset: inout Int) throws -> JP3DSIZInfo {
        // Length field (includes itself = 2 bytes)
        let len = Int(try readUInt16BE(data, at: &offset))
        guard len >= 38 else {
            throw J2KError.decodingError("SIZ segment length \(len) too small (min 38)")
        }
        let segEnd = offset + len - 2 // position after all segment bytes

        // Profile (2 bytes) – ignored
        offset += 2
        // Image width + height (4 + 4 bytes)
        let width  = Int(try readUInt32BE(data, at: &offset))
        let height = Int(try readUInt32BE(data, at: &offset))
        // Image offset (4 + 4 bytes) – ignored
        offset += 8
        // Tile width + height
        let tileW = Int(try readUInt32BE(data, at: &offset))
        let tileH = Int(try readUInt32BE(data, at: &offset))
        // Tile offset (4 + 4 bytes) – ignored
        offset += 8
        // Number of components
        let numComponents = Int(try readUInt16BE(data, at: &offset))
        guard numComponents > 0 else {
            throw J2KError.decodingError("SIZ: zero component count")
        }

        // Per-component fields (3 bytes each)
        var bitDepth = 8
        var isSigned = false
        for _ in 0..<numComponents {
            guard offset + 3 <= data.count else {
                throw J2KError.decodingError("SIZ: truncated component info")
            }
            let ssiz = data[offset]
            offset += 3
            isSigned = (ssiz & 0x80) != 0
            bitDepth = Int(ssiz & 0x7F) + 1
        }

        // JP3D extensions: depth (4 bytes), tileSizeZ (4 bytes)
        var depth = 1
        var tileSizeZ = 1
        if offset + 4 <= segEnd {
            depth = Int(try readUInt32BE(data, at: &offset))
        }
        if offset + 4 <= segEnd {
            tileSizeZ = Int(try readUInt32BE(data, at: &offset))
        }
        // Skip any remaining bytes in the segment
        if offset < segEnd { offset = segEnd }

        // Clamp tile sizes: if the stored tile size equals the volume (legacy single-tile),
        // use the volume dimensions as tile sizes
        let effectiveTileW = tileW > 0 ? tileW : width
        let effectiveTileH = tileH > 0 ? tileH : height
        let effectiveTileZ = tileSizeZ > 0 ? tileSizeZ : depth

        return JP3DSIZInfo(
            width: max(1, width),
            height: max(1, height),
            depth: max(1, depth),
            tileSizeX: max(1, effectiveTileW),
            tileSizeY: max(1, effectiveTileH),
            tileSizeZ: max(1, effectiveTileZ),
            componentCount: numComponents,
            bitDepth: max(1, bitDepth),
            signed: isSigned
        )
    }

    /// Parses the COD marker segment.
    private func parseCOD(_ data: Data, at offset: inout Int) throws -> JP3DCODInfo {
        let len = Int(try readUInt16BE(data, at: &offset))
        guard len >= 12 else {
            throw J2KError.decodingError("COD segment length \(len) too small (min 12)")
        }
        let segEnd = offset + len - 2

        // Coding style (1 byte) – ignored
        offset += 1
        // Progression order (1 byte) – ignored
        offset += 1
        // Quality layers (2 bytes) – ignored
        offset += 2
        // MCT (1 byte) – ignored
        offset += 1

        // Decomposition levels:
        // Extended JP3D COD (length 14): levelsX (1 byte), levelsY (1 byte), levelsZ (1 byte)
        // Legacy COD (length 12): single decomposition levels byte
        var levelsX = 1
        var levelsY = 1
        var levelsZ = 1

        guard offset < data.count else {
            throw J2KError.decodingError("COD: truncated levels field")
        }
        levelsX = Int(data[offset]); offset += 1

        if len >= 14 {
            // Extended JP3D format with separate Y and Z levels
            guard offset + 1 < data.count else {
                throw J2KError.decodingError("COD: truncated JP3D levels field")
            }
            levelsY = Int(data[offset]); offset += 1
            levelsZ = Int(data[offset]); offset += 1
        } else {
            levelsY = levelsX
            levelsZ = levelsX
        }

        // cbw, cbh, code-block style (3 bytes) – skip
        offset = min(segEnd - 1, offset + 3)

        // Wavelet filter: 1 = lossless (5/3), 0 = lossy (9/7)
        var isLossless = true
        if offset < segEnd {
            isLossless = data[min(offset, data.count - 1)] == 1
            offset += 1
        }

        // Skip any remaining bytes
        if offset < segEnd { offset = segEnd }

        return JP3DCODInfo(
            levelsX: max(0, levelsX),
            levelsY: max(0, levelsY),
            levelsZ: max(0, levelsZ),
            isLossless: isLossless
        )
    }

    /// Parses the QCD marker segment. Returns true if lossless quantization.
    private func parseQCD(_ data: Data, at offset: inout Int) throws -> Bool {
        let len = Int(try readUInt16BE(data, at: &offset))
        guard len >= 3 else {
            throw J2KError.decodingError("QCD segment length \(len) too small (min 3)")
        }
        let segEnd = offset + len - 2
        guard offset < data.count else {
            throw J2KError.decodingError("QCD: truncated")
        }
        let style = data[offset]
        // Skip the rest
        offset = segEnd
        // style 0 = no quantization (lossless); style 2 = scalar expounded (lossy)
        return style == 0
    }

    /// Parses an SOT marker segment and reads the following SOD + tile data.
    private func parseSOTAndData(_ data: Data, at offset: inout Int) throws -> JP3DParsedTile {
        let len = Int(try readUInt16BE(data, at: &offset))
        guard len >= 10 else {
            throw J2KError.decodingError("SOT segment length \(len) too small (min 10)")
        }
        // Tile index
        let tileIndex = Int(try readUInt16BE(data, at: &offset))
        // Tile-part length (includes SOT + SOD markers)
        let tilePartLength = Int(try readUInt32BE(data, at: &offset))
        // Tile-part index + num tile-parts (2 bytes)
        offset += 2
        // Skip any extra SOT bytes
        let sotConsumed = 10 // len(2) + tileIndex(2) + tpLen(4) + tpIdx(1) + numTp(1)
        if len > sotConsumed {
            offset += len - sotConsumed
        }

        // Expect SOD marker
        guard offset + 2 <= data.count else {
            throw J2KError.decodingError("SOT[\(tileIndex)]: truncated before SOD")
        }
        let sodMarker = try readUInt16BE(data, at: &offset)
        guard sodMarker == 0xFF93 else {
            throw J2KError.decodingError(
                "SOT[\(tileIndex)]: expected SOD (0xFF93) got 0x\(String(sodMarker, radix: 16))"
            )
        }

        // Tile data length: tilePartLength includes SOT (12 bytes) + SOD (2 bytes)
        let dataLength: Int
        if tilePartLength > 14 {
            dataLength = tilePartLength - 14 // SOT(12) + SOD(2)
        } else {
            // Fallback: read until next marker (0xFF??) or EOC
            dataLength = nextMarkerOffset(in: data, from: offset) - offset
        }

        guard offset + dataLength <= data.count else {
            throw J2KError.decodingError(
                "SOT[\(tileIndex)]: declared data length \(dataLength) exceeds available bytes"
            )
        }

        let tileData = data.subdata(in: offset..<(offset + dataLength))
        offset += dataLength

        return JP3DParsedTile(tileIndex: tileIndex, data: tileData)
    }

    /// Returns the offset of the next 0xFF marker byte (or `data.count` if none found).
    private func nextMarkerOffset(in data: Data, from start: Int) -> Int {
        var i = start
        while i < data.count - 1 {
            if data[i] == 0xFF && data[i + 1] != 0xFF {
                return i
            }
            i += 1
        }
        return data.count
    }

    // MARK: - Byte Reading Helpers

    private func readUInt16BE(_ data: Data, at offset: inout Int) throws -> UInt16 {
        guard offset + 2 <= data.count else {
            throw J2KError.decodingError("Codestream truncated reading UInt16 at offset \(offset)")
        }
        let hi = UInt16(data[offset])
        let lo = UInt16(data[offset + 1])
        offset += 2
        return (hi << 8) | lo
    }

    private func readUInt32BE(_ data: Data, at offset: inout Int) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw J2KError.decodingError("Codestream truncated reading UInt32 at offset \(offset)")
        }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        offset += 4
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
    }
}
