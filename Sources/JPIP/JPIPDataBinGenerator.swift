//
// JPIPDataBinGenerator.swift
// J2KSwift
//
/// # JPIPDataBinGenerator
///
/// Generates JPIP data bins from JPEG 2000 codestreams with HTJ2K support.
///
/// Extracts main headers, tile headers, and precinct data from JPEG 2000
/// codestreams (both legacy and HTJ2K) and packages them as JPIP data bins
/// for progressive streaming.

import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

/// Generates JPIP data bins from JPEG 2000 codestream data.
///
/// Parses codestream markers to extract structural components and packages
/// them into JPIP data bins suitable for progressive streaming. Supports
/// both legacy JPEG 2000 and HTJ2K codestreams.
///
/// Example:
/// ```swift
/// let generator = JPIPDataBinGenerator()
/// let bins = try generator.generateDataBins(from: codestreamData)
/// ```
public struct JPIPDataBinGenerator: Sendable {
    /// Creates a new data bin generator.
    public init() {}

    /// Generates JPIP data bins from a JPEG 2000 file.
    ///
    /// Reads the file, parses the codestream structure, and produces
    /// data bins for the main header, tile headers, and precinct data.
    ///
    /// - Parameter url: The file URL to read.
    /// - Returns: Array of generated data bins.
    /// - Throws: ``J2KError`` if the file cannot be read or parsed.
    public func generateDataBins(from url: URL) throws -> [JPIPDataBin] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try generateDataBins(from: data)
    }

    /// Generates JPIP data bins from codestream data.
    ///
    /// Parses the codestream structure and produces data bins for the
    /// main header, tile headers, and tile/precinct data.
    ///
    /// - Parameter data: The codestream data.
    /// - Returns: Array of generated data bins.
    /// - Throws: ``J2KError`` if the data cannot be parsed.
    public func generateDataBins(from data: Data) throws -> [JPIPDataBin] {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else {
            throw J2KError.invalidParameter("Data too small for JPEG 2000 codestream")
        }

        var bins: [JPIPDataBin] = []

        // Find the codestream start (skip JP2 file format boxes if present)
        let codestreamOffset = findCodestreamStart(in: bytes)
        let csBytes = Array(bytes[codestreamOffset...])

        // Extract main header
        let mainHeader = try extractMainHeader(from: csBytes)
        bins.append(JPIPDataBin(
            binClass: .mainHeader,
            binID: 0,
            data: Data(mainHeader),
            isComplete: true
        ))

        // Extract tile parts
        let tileParts = extractTileParts(from: csBytes, headerEnd: mainHeader.count)
        for (index, tilePart) in tileParts.enumerated() {
            // Tile header data bin
            bins.append(JPIPDataBin(
                binClass: .tileHeader,
                binID: index,
                data: Data(tilePart.header),
                isComplete: true
            ))

            // Tile data bin (bitstream data)
            bins.append(JPIPDataBin(
                binClass: .tile,
                binID: index,
                data: Data(tilePart.data),
                isComplete: true
            ))
        }

        // If no tile parts found, package remaining data as tile 0
        if tileParts.isEmpty && csBytes.count > mainHeader.count {
            let remainingData = Array(csBytes[mainHeader.count...])
            bins.append(JPIPDataBin(
                binClass: .tile,
                binID: 0,
                data: Data(remainingData),
                isComplete: true
            ))
        }

        return bins
    }

    /// Checks whether the given data is an HTJ2K codestream.
    ///
    /// - Parameter data: The codestream data to check.
    /// - Returns: `true` if the data contains HTJ2K markers.
    public func isHTJ2KCodestream(_ data: Data) -> Bool {
        let transcoder = J2KTranscoder()
        return (try? transcoder.isHTJ2K(data)) ?? false
    }

    // MARK: - Private Helpers

    /// Finds the start of the JPEG 2000 codestream within file data.
    ///
    /// For raw J2K codestreams, returns 0. For JP2/JPH file formats,
    /// finds the contiguous codestream box (jp2c) and returns its offset.
    ///
    /// - Parameter bytes: The file data bytes.
    /// - Returns: Offset to the codestream start.
    private func findCodestreamStart(in bytes: [UInt8]) -> Int {
        // Check for SOC marker at start (raw codestream)
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0x4F {
            return 0
        }

        // Look for JP2 signature box
        if bytes.count >= 12 {
            // JP2 signature: 0x0000000C 6A502020 0D0A870A
            let isJP2 = bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0x00 &&
                         bytes[3] == 0x0C && bytes[4] == 0x6A && bytes[5] == 0x50

            if isJP2 {
                // Search for jp2c box (contiguous codestream)
                var offset = 0
                while offset + 8 < bytes.count {
                    let boxLen = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 |
                                 Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                    let boxType = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)

                    if boxType == "jp2c" {
                        // Codestream starts after box header (8 bytes)
                        return offset + 8
                    }

                    if boxLen < 8 { break }
                    offset += boxLen
                }
            }
        }

        return 0
    }

    /// Extracts the main header from a codestream.
    ///
    /// The main header spans from SOC (0xFF4F) to the first SOT (0xFF90)
    /// marker, or to the end of data if no SOT is found.
    ///
    /// - Parameter bytes: The codestream bytes starting at SOC.
    /// - Returns: The main header bytes.
    /// - Throws: ``J2KError`` if the codestream is invalid.
    private func extractMainHeader(from bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0x4F else {
            throw J2KError.invalidParameter("Invalid codestream: missing SOC marker")
        }

        // Scan for SOT marker (0xFF90) which marks end of main header
        var offset = 2
        while offset + 1 < bytes.count {
            if bytes[offset] == 0xFF && bytes[offset + 1] == 0x90 {
                return Array(bytes[0..<offset])
            }

            // If it's a marker with a length field, skip it
            if bytes[offset] == 0xFF && bytes[offset + 1] != 0xFF {
                let marker = bytes[offset + 1]
                // SOC (0x4F), SOD (0x93), EOC (0xD9) have no length
                if marker == 0x4F || marker == 0x93 || marker == 0xD9 {
                    offset += 2
                } else if offset + 3 < bytes.count {
                    let length = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                    offset += 2 + length
                } else {
                    offset += 2
                }
            } else {
                offset += 1
            }
        }

        // No SOT found - entire data is the header
        return bytes
    }

    /// Represents a parsed tile part.
    struct TilePart {
        /// The tile header bytes (SOT marker segment).
        let header: [UInt8]

        /// The tile bitstream data (after SOD).
        let data: [UInt8]

        /// The tile index from the SOT marker.
        let tileIndex: Int
    }

    /// Extracts tile parts from a codestream.
    ///
    /// - Parameters:
    ///   - bytes: The codestream bytes starting at SOC.
    ///   - headerEnd: Offset past the main header.
    /// - Returns: Array of tile parts found.
    private func extractTileParts(from bytes: [UInt8], headerEnd: Int) -> [TilePart] {
        var tileParts: [TilePart] = []
        var offset = headerEnd

        while offset + 1 < bytes.count {
            // Look for SOT marker (0xFF90)
            if bytes[offset] == 0xFF && bytes[offset + 1] == 0x90 {
                guard offset + 11 < bytes.count else { break }

                // Parse SOT marker segment
                let sotLength = Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
                let tileIndex = Int(bytes[offset + 4]) << 8 | Int(bytes[offset + 5])
                let tilePartLength = Int(bytes[offset + 6]) << 24 | Int(bytes[offset + 7]) << 16 |
                                     Int(bytes[offset + 8]) << 8 | Int(bytes[offset + 9])

                // Tile header: SOT marker + its length field content
                let headerEndOffset = offset + 2 + sotLength

                // Find SOD marker (0xFF93) to separate header from data
                var sodOffset = headerEndOffset
                while sodOffset + 1 < bytes.count {
                    if bytes[sodOffset] == 0xFF && bytes[sodOffset + 1] == 0x93 {
                        break
                    }
                    // Skip marker segments within tile header
                    if bytes[sodOffset] == 0xFF && bytes[sodOffset + 1] != 0xFF {
                        let m = bytes[sodOffset + 1]
                        if m == 0x4F || m == 0x93 || m == 0xD9 {
                            break
                        } else if sodOffset + 3 < bytes.count {
                            let mLen = Int(bytes[sodOffset + 2]) << 8 | Int(bytes[sodOffset + 3])
                            sodOffset += 2 + mLen
                        } else {
                            sodOffset += 2
                        }
                    } else {
                        sodOffset += 1
                    }
                }

                let tileHeader = Array(bytes[offset..<min(sodOffset, bytes.count)])

                // Tile data starts after SOD marker
                let dataStart = min(sodOffset + 2, bytes.count)
                let dataEnd: Int
                if tilePartLength > 0 {
                    dataEnd = min(offset + tilePartLength, bytes.count)
                } else {
                    // Find next SOT or EOC
                    var nextOffset = dataStart
                    while nextOffset + 1 < bytes.count {
                        if bytes[nextOffset] == 0xFF &&
                           (bytes[nextOffset + 1] == 0x90 || bytes[nextOffset + 1] == 0xD9) {
                            break
                        }
                        nextOffset += 1
                    }
                    dataEnd = nextOffset
                }

                let tileData = dataStart < dataEnd ? Array(bytes[dataStart..<dataEnd]) : []

                tileParts.append(TilePart(
                    header: tileHeader,
                    data: tileData,
                    tileIndex: tileIndex
                ))

                offset = dataEnd
            } else if bytes[offset] == 0xFF && bytes[offset + 1] == 0xD9 {
                // EOC marker - end of codestream
                break
            } else {
                offset += 1
            }
        }

        return tileParts
    }
}
