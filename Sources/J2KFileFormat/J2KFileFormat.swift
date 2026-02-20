//
// J2KFileFormat.swift
// J2KSwift
//
/// # J2KFileFormat
///
/// File format support for JPEG 2000 and related formats.
///
/// This module handles reading and writing JPEG 2000 files in various formats,
/// including JP2, J2K, JPX, and related container formats.
///
/// ## Topics
///
/// ### File Reading
/// - ``J2KFileReader``
///
/// ### File Writing
/// - ``J2KFileWriter``
///
/// ### Format Detection
/// - ``J2KFormat``
/// - ``J2KFormatDetector``

import Foundation
import J2KCore
import J2KCodec

/// Supported JPEG 2000 file formats.
public enum J2KFormat: String, Sendable {
    /// JP2 format (JPEG 2000 Part 1)
    case jp2

    /// J2K codestream format
    case j2k

    /// JPX format (JPEG 2000 Part 2)
    case jpx

    /// JPM format (JPEG 2000 Part 6)
    case jpm

    /// JPH format (HTJ2K - JPEG 2000 Part 15)
    case jph

    /// Returns the typical file extension for this format.
    public var fileExtension: String {
        switch self {
        case .jp2: return "jp2"
        case .j2k: return "j2k"
        case .jpx: return "jpx"
        case .jpm: return "jpm"
        case .jph: return "jph"
        }
    }

    /// Returns the MIME type for this format.
    public var mimeType: String {
        switch self {
        case .jp2: return "image/jp2"
        case .j2k: return "image/j2k"
        case .jpx: return "image/jpx"
        case .jpm: return "image/jpm"
        case .jph: return "image/jph"
        }
    }
}

/// Detects JPEG 2000 file formats from file signatures.
///
/// `J2KFormatDetector` provides methods for detecting the format of JPEG 2000
/// files by examining their file signatures (magic numbers).
///
/// ## Signatures
///
/// - **JP2**: Starts with the JP2 signature box (0x0000000C 'jP  ' 0x0D0A870A)
/// - **J2K**: Starts directly with the SOC marker (0xFF4F)
/// - **JPX**: JP2 signature followed by 'ftyp' box with 'jpx ' brand
/// - **JPM**: JP2 signature followed by 'ftyp' box with 'jpm ' brand
/// - **JPH**: JP2 signature followed by 'ftyp' box with 'jph ' brand (HTJ2K)
///
/// Example:
/// ```swift
/// let detector = J2KFormatDetector()
/// let format = try detector.detect(data: fileData)
/// ```
public struct J2KFormatDetector: Sendable {
    // MARK: - Signature Constants

    /// JP2 signature box (first 12 bytes of a JP2/JPX/JPM file).
    /// Format: length (4) + type "jP  " (4) + content (4)
    private static let jp2SignatureLength: UInt32 = 0x0000000C
    private static let jp2SignatureType: [UInt8] = [0x6A, 0x50, 0x20, 0x20] // "jP  "
    private static let jp2SignatureContent: [UInt8] = [0x0D, 0x0A, 0x87, 0x0A]

    /// File type box type ("ftyp").
    private static let ftypType: [UInt8] = [0x66, 0x74, 0x79, 0x70] // "ftyp"

    /// JP2 brand in ftyp box.
    private static let jp2Brand: [UInt8] = [0x6A, 0x70, 0x32, 0x20] // "jp2 "

    /// JPX brand in ftyp box.
    private static let jpxBrand: [UInt8] = [0x6A, 0x70, 0x78, 0x20] // "jpx "

    /// JPM brand in ftyp box.
    private static let jpmBrand: [UInt8] = [0x6A, 0x70, 0x6D, 0x20] // "jpm "

    /// JPH brand in ftyp box (HTJ2K - Part 15).
    private static let jphBrand: [UInt8] = [0x6A, 0x70, 0x68, 0x20] // "jph "

    /// JPEG 2000 codestream SOC marker.
    private static let socMarker: [UInt8] = [0xFF, 0x4F]

    /// Creates a new format detector.
    public init() {}

    /// Detects the format of JPEG 2000 data.
    ///
    /// - Parameter data: The data to examine.
    /// - Returns: The detected format.
    /// - Throws: ``J2KError/fileFormatError(_:)`` if the format cannot be detected.
    public func detect(data: Data) throws -> J2KFormat {
        guard data.count >= 2 else {
            throw J2KError.fileFormatError("Data too small to detect format (need at least 2 bytes)")
        }

        // Check for raw codestream (J2K) - starts with SOC marker (0xFF4F)
        if data.count >= 2 && data[0] == Self.socMarker[0] && data[1] == Self.socMarker[1] {
            return .j2k
        }

        // Check for box-based format (JP2/JPX/JPM)
        guard data.count >= 12 else {
            throw J2KError.fileFormatError("Data too small for box-based format detection")
        }

        // Verify JP2 signature box
        if !hasJP2Signature(data) {
            throw J2KError.fileFormatError("Invalid or unrecognized JPEG 2000 file format")
        }

        // Look for ftyp box to determine specific format
        if let brand = extractFiletypeBrand(from: data) {
            if brand == Self.jpxBrand {
                return .jpx
            } else if brand == Self.jpmBrand {
                return .jpm
            } else if brand == Self.jphBrand {
                return .jph
            } else if brand == Self.jp2Brand {
                return .jp2
            }
        }

        // Default to JP2 if signature is valid but no ftyp found or recognized
        return .jp2
    }

    /// Detects the format of a file at the specified URL.
    ///
    /// - Parameter url: The URL of the file to examine.
    /// - Returns: The detected format.
    /// - Throws: ``J2KError`` if reading or detection fails.
    public func detect(at url: URL) throws -> J2KFormat {
        let data = try readHeader(from: url, maxBytes: 256)
        return try detect(data: data)
    }

    /// Validates that data appears to be a valid JPEG 2000 file.
    ///
    /// - Parameter data: The data to validate.
    /// - Returns: `true` if the data appears to be valid JPEG 2000.
    public func isValidJPEG2000(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }

        // Check for raw codestream
        if data[0] == Self.socMarker[0] && data[1] == Self.socMarker[1] {
            return true
        }

        // Check for box-based format
        return hasJP2Signature(data)
    }

    // MARK: - Private Methods

    /// Checks if data starts with the JP2 signature.
    private func hasJP2Signature(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }

        // Check length (first 4 bytes should be 0x0000000C)
        let length = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        guard length == Self.jp2SignatureLength else { return false }

        // Check type "jP  "
        guard data[4] == Self.jp2SignatureType[0] &&
              data[5] == Self.jp2SignatureType[1] &&
              data[6] == Self.jp2SignatureType[2] &&
              data[7] == Self.jp2SignatureType[3] else {
            return false
        }

        // Check content
        guard data[8] == Self.jp2SignatureContent[0] &&
              data[9] == Self.jp2SignatureContent[1] &&
              data[10] == Self.jp2SignatureContent[2] &&
              data[11] == Self.jp2SignatureContent[3] else {
            return false
        }

        return true
    }

    /// Extracts the brand from the ftyp box if present.
    private func extractFiletypeBrand(from data: Data) -> [UInt8]? {
        // After the signature box (12 bytes), look for ftyp box
        var offset = 12

        while offset + 8 <= data.count {
            // Read box length
            let length = Int(UInt32(data[offset]) << 24 |
                            UInt32(data[offset + 1]) << 16 |
                            UInt32(data[offset + 2]) << 8 |
                            UInt32(data[offset + 3]))

            // Check if this is an ftyp box
            if data[offset + 4] == Self.ftypType[0] &&
               data[offset + 5] == Self.ftypType[1] &&
               data[offset + 6] == Self.ftypType[2] &&
               data[offset + 7] == Self.ftypType[3] {
                // Brand is the next 4 bytes after the header
                guard offset + 12 <= data.count else { return nil }
                return [data[offset + 8], data[offset + 9], data[offset + 10], data[offset + 11]]
            }

            // Move to next box
            guard length > 0 else { break }
            offset += length
        }

        return nil
    }

    /// Reads the header bytes from a file.
    private func readHeader(from url: URL, maxBytes: Int) throws -> Data {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        guard let data = try fileHandle.read(upToCount: maxBytes) else {
            throw J2KError.ioError("Failed to read file header from \(url.path)")
        }

        return data
    }
}

/// Reads JPEG 2000 files from disk.
public struct J2KFileReader: Sendable {
    /// The format detector used for automatic format detection.
    private let detector: J2KFormatDetector

    /// Creates a new file reader.
    public init() {
        self.detector = J2KFormatDetector()
    }

    /// Reads a JPEG 2000 file from the specified URL.
    ///
    /// - Parameter url: The URL of the file to read.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if reading or decoding fails.
    public func read(from url: URL) throws -> J2KImage {
        // Detect the format first
        let format = try detectFormat(at: url)

        // Read the file data
        let data = try Data(contentsOf: url)

        // Parse based on format
        switch format {
        case .j2k:
            return try parseCodestream(data)
        case .jp2, .jpx, .jpm, .jph:
            return try parseBoxFormat(data, format: format)
        }
    }

    /// Detects the format of a JPEG 2000 file.
    ///
    /// - Parameter url: The URL of the file to examine.
    /// - Returns: The detected format.
    /// - Throws: ``J2KError`` if format detection fails.
    public func detectFormat(at url: URL) throws -> J2KFormat {
        try detector.detect(at: url)
    }

    /// Detects the format of JPEG 2000 data.
    ///
    /// - Parameter data: The data to examine.
    /// - Returns: The detected format.
    /// - Throws: ``J2KError`` if format detection fails.
    public func detectFormat(data: Data) throws -> J2KFormat {
        try detector.detect(data: data)
    }

    /// Validates that a file appears to be a valid JPEG 2000 file.
    ///
    /// - Parameter url: The URL of the file to validate.
    /// - Returns: `true` if the file appears valid.
    public func isValid(at url: URL) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: url),
              let headerData = try? fileHandle.read(upToCount: 64) else {
            return false
        }
        try? fileHandle.close()
        return detector.isValidJPEG2000(headerData)
    }

    // MARK: - Private Methods

    /// Parses a raw JPEG 2000 codestream.
    private func parseCodestream(_ data: Data) throws -> J2KImage {
        // Validate the codestream starts with SOC marker
        guard data.count >= 4 else {
            throw J2KError.invalidData("Codestream too small")
        }

        // Parse marker segments to extract image info
        let parser = J2KMarkerParser(data: data)
        guard parser.validateBasicStructure() else {
            throw J2KError.invalidData("Invalid codestream structure")
        }

        let segments = try parser.parseMainHeader()

        // Find and parse SIZ marker to get image dimensions
        guard let sizSegment = segments.first(where: { $0.marker == .siz }) else {
            throw J2KError.invalidData("Missing required SIZ marker segment")
        }

        return try parseSIZMarker(sizSegment.data)
    }

    /// Parses a box-based format (JP2, JPX, JPM).
    private func parseBoxFormat(_ data: Data, format: J2KFormat) throws -> J2KImage {
        // For now, we need to find the codestream within the boxes
        // The codestream is contained in a 'jp2c' box
        let codestreamData = try extractCodestream(from: data)
        return try parseCodestream(codestreamData)
    }

    /// Extracts the codestream from a box-based format.
    private func extractCodestream(from data: Data) throws -> Data {
        var offset = 0

        while offset + 8 <= data.count {
            // Read box header
            let length = Int(UInt32(data[offset]) << 24 |
                            UInt32(data[offset + 1]) << 16 |
                            UInt32(data[offset + 2]) << 8 |
                            UInt32(data[offset + 3]))

            let boxType = [data[offset + 4], data[offset + 5], data[offset + 6], data[offset + 7]]

            // Check for jp2c box (Contiguous Codestream)
            // 'jp2c' = [0x6A, 0x70, 0x32, 0x63]
            if boxType == [0x6A, 0x70, 0x32, 0x63] {
                let headerSize = 8
                let contentStart = offset + headerSize
                let contentLength = length == 0 ? data.count - contentStart : length - headerSize

                guard contentStart + contentLength <= data.count else {
                    throw J2KError.invalidData("Codestream box extends beyond file")
                }

                return data.subdata(in: contentStart..<(contentStart + contentLength))
            }

            // Handle extended length boxes (length == 1)
            var boxLength = length
            if length == 1 && offset + 16 <= data.count {
                // Extended length is the next 8 bytes
                var extLen: UInt64 = 0
                extLen |= UInt64(data[offset + 8]) << 56
                extLen |= UInt64(data[offset + 9]) << 48
                extLen |= UInt64(data[offset + 10]) << 40
                extLen |= UInt64(data[offset + 11]) << 32
                extLen |= UInt64(data[offset + 12]) << 24
                extLen |= UInt64(data[offset + 13]) << 16
                extLen |= UInt64(data[offset + 14]) << 8
                extLen |= UInt64(data[offset + 15])
                boxLength = Int(extLen)
            } else if length == 0 {
                // Box extends to end of file
                boxLength = data.count - offset
            }

            guard boxLength > 0 else {
                throw J2KError.invalidData("Invalid box length at offset \(offset)")
            }

            offset += boxLength
        }

        throw J2KError.invalidData("No codestream found in file")
    }

    /// Parses SIZ marker segment data to extract image information.
    private func parseSIZMarker(_ data: Data) throws -> J2KImage {
        var reader = J2KBitReader(data: data)

        // SIZ marker segment structure:
        // Rsiz (2 bytes) - Capabilities
        // Xsiz (4 bytes) - Image width
        // Ysiz (4 bytes) - Image height
        // XOsiz (4 bytes) - Image X offset
        // YOsiz (4 bytes) - Image Y offset
        // XTsiz (4 bytes) - Tile width
        // YTsiz (4 bytes) - Tile height
        // XTOsiz (4 bytes) - Tile X offset
        // YTOsiz (4 bytes) - Tile Y offset
        // Csiz (2 bytes) - Number of components
        // For each component:
        //   Ssiz (1 byte) - Bit depth and sign
        //   XRsiz (1 byte) - Horizontal subsampling
        //   YRsiz (1 byte) - Vertical subsampling

        guard data.count >= 38 else {
            throw J2KError.invalidData("SIZ marker segment too small")
        }

        _ = try reader.readUInt16() // Rsiz (capabilities)
        let width = Int(try reader.readUInt32())
        let height = Int(try reader.readUInt32())
        let offsetX = Int(try reader.readUInt32())
        let offsetY = Int(try reader.readUInt32())
        let tileWidth = Int(try reader.readUInt32())
        let tileHeight = Int(try reader.readUInt32())
        let tileOffsetX = Int(try reader.readUInt32())
        let tileOffsetY = Int(try reader.readUInt32())
        let numComponents = Int(try reader.readUInt16())

        guard numComponents >= 1 && numComponents <= 16384 else {
            throw J2KError.invalidData("Invalid number of components: \(numComponents)")
        }

        guard data.count >= 38 + (numComponents * 3) else {
            throw J2KError.invalidData("SIZ marker segment missing component data")
        }

        var components: [J2KComponent] = []
        for i in 0..<numComponents {
            let ssiz = try reader.readUInt8()
            let xrSiz = Int(try reader.readUInt8())
            let yrSiz = Int(try reader.readUInt8())

            let signed = (ssiz & 0x80) != 0
            let bitDepth = Int(ssiz & 0x7F) + 1

            // Component dimensions are scaled by subsampling
            let compWidth = (width + xrSiz - 1) / xrSiz
            let compHeight = (height + yrSiz - 1) / yrSiz

            components.append(J2KComponent(
                index: i,
                bitDepth: bitDepth,
                signed: signed,
                width: compWidth,
                height: compHeight,
                subsamplingX: xrSiz,
                subsamplingY: yrSiz
            ))
        }

        return J2KImage(
            width: width,
            height: height,
            components: components,
            offsetX: offsetX,
            offsetY: offsetY,
            tileWidth: tileWidth,
            tileHeight: tileHeight,
            tileOffsetX: tileOffsetX,
            tileOffsetY: tileOffsetY
        )
    }
}

/// Writes JPEG 2000 files to disk.
public struct J2KFileWriter: Sendable {
    /// The format to use for writing.
    public let format: J2KFormat

    /// Creates a new file writer with the specified format.
    ///
    /// - Parameter format: The format to use (default: .jp2).
    public init(format: J2KFormat = .jp2) {
        self.format = format
    }

    /// Writes an image to a JPEG 2000 file.
    ///
    /// This method encodes the image using the specified configuration and writes it
    /// to the specified file format. Supports JP2 (with metadata) and J2K (codestream only) formats.
    ///
    /// - Parameters:
    ///   - image: The image to write. Must have valid dimensions and at least one component.
    ///   - url: The destination URL where the file will be written.
    ///   - configuration: The encoding configuration (quality, compression settings, etc.).
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the image is invalid.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    /// - Throws: ``J2KError/ioError(_:)`` if file writing fails.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let writer = J2KFileWriter(format: .jp2)
    /// let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
    /// // ... fill image data ...
    /// try writer.write(image, to: fileURL, configuration: .init(quality: 0.95))
    /// ```
    public func write(_ image: J2KImage, to url: URL, configuration: J2KConfiguration = J2KConfiguration()) throws {
        // Validate the image
        guard image.width > 0, image.height > 0 else {
            throw J2KError.invalidParameter("Image must have positive dimensions (got \(image.width)x\(image.height))")
        }

        guard !image.components.isEmpty else {
            throw J2KError.invalidParameter("Image must have at least one component")
        }

        // Encode the image to a codestream
        let encoder = J2KEncoder(configuration: configuration)
        let codestreamData = try encoder.encode(image)

        // Generate the file data based on format
        let fileData: Data
        switch format {
        case .j2k:
            // J2K format is just the codestream
            fileData = codestreamData

        case .jp2:
            // JP2 format requires box structure
            fileData = try buildJP2File(image: image, codestream: codestreamData)

        case .jph:
            // JPH format (HTJ2K) uses JP2 structure with different brand
            fileData = try buildJPHFile(image: image, codestream: codestreamData)

        case .jpx:
            // JPX format uses extended boxes
            fileData = try buildJPXFile(image: image, codestream: codestreamData)

        case .jpm:
            // JPM format supports multi-page
            fileData = try buildJPMFile(image: image, codestream: codestreamData)
        }

        // Write to file
        do {
            try fileData.write(to: url, options: .atomic)
        } catch {
            throw J2KError.ioError("Failed to write file to \(url.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    /// Builds a JP2 file with proper box structure.
    private func buildJP2File(image: J2KImage, codestream: Data) throws -> Data {
        var writer = J2KBoxWriter()

        // 1. Signature box (jP\x20\x20\x0D\x0A\x87\x0A)
        let signatureBox = J2KSignatureBox()
        try writer.writeBox(signatureBox)

        // 2. File Type box
        let fileTypeBox = J2KFileTypeBox(
            brand: .jp2,
            minorVersion: 0
        )
        try writer.writeBox(fileTypeBox)

        // 3. JP2 Header box (jp2h) - contains image metadata
        try writeJP2HeaderBox(image: image, writer: &writer)

        // 4. Contiguous Codestream box (jp2c)
        try writer.writeRawBox(type: .jp2c, content: codestream)

        return writer.data
    }

    /// Builds a JPH file (HTJ2K format) with proper box structure.
    ///
    /// JPH files use the same box structure as JP2, but with the 'jph ' brand
    /// in the file type box to indicate HTJ2K (Part 15) support.
    private func buildJPHFile(image: J2KImage, codestream: Data) throws -> Data {
        var writer = J2KBoxWriter()

        // 1. Signature box (jP\x20\x20\x0D\x0A\x87\x0A)
        let signatureBox = J2KSignatureBox()
        try writer.writeBox(signatureBox)

        // 2. File Type box with 'jph ' brand for HTJ2K
        let fileTypeBox = J2KFileTypeBox(
            brand: .jph,
            minorVersion: 0,
            compatibleBrands: [.jph, .jp2]  // Compatible with both HTJ2K and JP2 readers
        )
        try writer.writeBox(fileTypeBox)

        // 3. JP2 Header box (jp2h) - contains image metadata
        try writeJP2HeaderBox(image: image, writer: &writer)

        // 4. Contiguous Codestream box (jp2c)
        try writer.writeRawBox(type: .jp2c, content: codestream)

        return writer.data
    }

    /// Writes the JP2 header box containing image metadata.
    private func writeJP2HeaderBox(image: J2KImage, writer: inout J2KBoxWriter) throws {
        var headerWriter = J2KBoxWriter()

        // Image Header box (ihdr)
        let ihdrBox = J2KImageHeaderBox(
            width: UInt32(image.width),
            height: UInt32(image.height),
            numComponents: UInt16(image.components.count),
            bitsPerComponent: UInt8(image.components[0].bitDepth),
            compressionType: J2KImageHeaderBox.compressionType,
            colorSpaceUnknown: 0, // Color space is known
            intellectualProperty: 0 // No intellectual property info
        )
        try headerWriter.writeBox(ihdrBox)

        // Bits Per Component box (bpcc) - optional, for variable bit depths
        let allSameBitDepth = image.components.allSatisfy { $0.bitDepth == image.components[0].bitDepth }
        if !allSameBitDepth {
            var bitDepths: [J2KBitsPerComponentBox.BitDepth] = []
            for component in image.components {
                let depth = component.signed ?
                    J2KBitsPerComponentBox.BitDepth.signed(UInt8(component.bitDepth)) :
                    J2KBitsPerComponentBox.BitDepth.unsigned(UInt8(component.bitDepth))
                bitDepths.append(depth)
            }
            let bpccBox = J2KBitsPerComponentBox(bitDepths: bitDepths)
            try headerWriter.writeBox(bpccBox)
        }

        // Color Specification box (colr)
        let colrBox = try buildColorSpecificationBox(image: image)
        try headerWriter.writeBox(colrBox)

        // Write the jp2h box containing all header boxes
        try writer.writeRawBox(type: .jp2h, content: headerWriter.data)
    }

    /// Builds a color specification box based on image components.
    ///
    /// - Note: This implementation makes basic assumptions about color space:
    ///   - 1 component: Greyscale
    ///   - 3 components: sRGB
    ///   - 4+ components: sRGB (assumes RGBA; CMYK and other color spaces not yet supported)
    /// Future versions should implement proper color space detection based on component metadata.
    private func buildColorSpecificationBox(image: J2KImage) throws -> J2KColorSpecificationBox {
        // Determine color space based on number of components
        let colorSpace: J2KColorSpecificationBox.EnumeratedColorSpace
        switch image.components.count {
        case 1:
            colorSpace = .greyscale
        case 3:
            colorSpace = .sRGB
        case 4:
            // Assume RGBA (sRGB with alpha)
            // Note: CMYK and other 4-component color spaces are not yet supported
            colorSpace = .sRGB
        default:
            // Default fallback for unusual component counts
            colorSpace = .sRGB
        }

        return J2KColorSpecificationBox(
            method: .enumerated(colorSpace),
            precedence: 0,
            approximation: 0
        )
    }

    /// Builds a JPX file (extended format).
    private func buildJPXFile(image: J2KImage, codestream: Data) throws -> Data {
        // JPX is an extended format, for now use JP2 structure
        // Full JPX support would include reader requirements box, etc.
        try buildJP2File(image: image, codestream: codestream)
    }

    /// Builds a JPM file (multi-page format).
    private func buildJPMFile(image: J2KImage, codestream: Data) throws -> Data {
        // JPM is for multi-page documents, for now use JP2 structure
        // Full JPM support would include page boxes, layout, etc.
        try buildJP2File(image: image, codestream: codestream)
    }
}
