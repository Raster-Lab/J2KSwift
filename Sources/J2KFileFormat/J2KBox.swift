//
// J2KBox.swift
// J2KSwift
//
/// # J2KBox
///
/// JP2 box (atom) structure for JPEG 2000 file format.
///
/// This module provides the foundation for reading and writing JP2 boxes,
/// which are the basic building blocks of JP2, JPX, and JPM files.

import Foundation
import J2KCore

/// A JP2 box (also known as an atom in ISO base media file format).
///
/// Boxes are the fundamental structure of JP2 files. Each box has a type
/// (4-byte identifier) and contains either data or other boxes.
///
/// ## Box Structure
///
/// Standard box header (8 bytes):
/// ```
/// Length (4 bytes) - Total box length including header
/// Type   (4 bytes) - Four-character box type identifier
/// ```
///
/// Extended box header (16 bytes, when length = 1):
/// ```
/// Length    (4 bytes) - Set to 1 to indicate extended length
/// Type      (4 bytes) - Four-character box type identifier
/// XLength   (8 bytes) - Actual box length as 64-bit value
/// ```
///
/// Example:
/// ```swift
/// let box = J2KSignatureBox()
/// let data = try box.write()
/// ```
public protocol J2KBox: Sendable {
    /// The four-character box type identifier.
    var boxType: J2KBoxType { get }

    /// Writes the box to binary data.
    ///
    /// - Returns: The serialized box data including header.
    /// - Throws: ``J2KError`` if writing fails.
    func write() throws -> Data

    /// Reads the box content from data.
    ///
    /// - Parameter data: The box content (excluding the box header).
    /// - Throws: ``J2KError`` if parsing fails.
    mutating func read(from data: Data) throws
}

/// Box type identifiers for JP2 format.
///
/// These are the standard box types defined in ISO/IEC 15444-1 (JPEG 2000 Part 1).
public struct J2KBoxType: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    /// Creates a box type from a four-character string.
    ///
    /// - Parameter string: The four-character box type identifier.
    public init(string: String) {
        precondition(string.count == 4, "Box type must be exactly 4 characters")
        let bytes = [UInt8](string.utf8)
        self.rawValue = UInt32(bytes[0]) << 24 |
                       UInt32(bytes[1]) << 16 |
                       UInt32(bytes[2]) << 8 |
                       UInt32(bytes[3])
    }

    /// Returns the box type as a four-character string.
    public var stringValue: String {
        let bytes: [UInt8] = [
            UInt8((rawValue >> 24) & 0xFF),
            UInt8((rawValue >> 16) & 0xFF),
            UInt8((rawValue >> 8) & 0xFF),
            UInt8(rawValue & 0xFF)
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    // MARK: - Standard Box Types

    /// Signature box ('jP  ') - JP2 file signature
    public static let jp = J2KBoxType(string: "jP  ")

    /// File type box ('ftyp') - File type and compatibility
    public static let ftyp = J2KBoxType(string: "ftyp")

    /// JP2 header box ('jp2h') - Container for header boxes
    public static let jp2h = J2KBoxType(string: "jp2h")

    /// Image header box ('ihdr') - Image dimensions and properties
    public static let ihdr = J2KBoxType(string: "ihdr")

    /// Bits per component box ('bpcc') - Bit depth per component
    public static let bpcc = J2KBoxType(string: "bpcc")

    /// Color specification box ('colr') - Color space information
    public static let colr = J2KBoxType(string: "colr")

    /// Palette box ('pclr') - Palette data for indexed color
    public static let pclr = J2KBoxType(string: "pclr")

    /// Component mapping box ('cmap') - Maps palette indices to components
    public static let cmap = J2KBoxType(string: "cmap")

    /// Channel definition box ('cdef') - Channel/component definitions
    public static let cdef = J2KBoxType(string: "cdef")

    /// Resolution box ('res ') - Container for resolution boxes
    public static let res = J2KBoxType(string: "res ")

    /// Capture resolution box ('resc') - Original capture resolution
    public static let resc = J2KBoxType(string: "resc")

    /// Display resolution box ('resd') - Recommended display resolution
    public static let resd = J2KBoxType(string: "resd")

    /// Contiguous codestream box ('jp2c') - JPEG 2000 codestream
    public static let jp2c = J2KBoxType(string: "jp2c")

    /// UUID box ('uuid') - Vendor-specific extensions
    public static let uuid = J2KBoxType(string: "uuid")

    /// UUID info box ('uinf') - UUID list and URL
    public static let uinf = J2KBoxType(string: "uinf")

    /// UUID list box ('ulst') - List of UUIDs
    public static let ulst = J2KBoxType(string: "ulst")

    /// XML box ('xml ') - XML metadata
    public static let xml = J2KBoxType(string: "xml ")

    // MARK: - JPX Box Types (ISO/IEC 15444-2)

    /// Reader requirements box ('rreq') - Requirements for reading the file
    public static let rreq = J2KBoxType(string: "rreq")

    /// Fragment table box ('ftbl') - Container for fragment list
    public static let ftbl = J2KBoxType(string: "ftbl")

    /// Fragment list box ('flst') - List of codestream fragments
    public static let flst = J2KBoxType(string: "flst")

    /// Composition box ('comp') - Instructions for composing layers
    public static let comp = J2KBoxType(string: "comp")

    /// Compositing layer header box ('cgrp') - Grouping of composition layers
    public static let cgrp = J2KBoxType(string: "cgrp")

    /// DC offset feature box ('dcof') - Part 2 DC offset capabilities
    public static let dcof = J2KBoxType(string: "dcof")

    // MARK: - JPM Box Types (ISO/IEC 15444-6)

    /// Page collection box ('pcol') - Container for pages
    public static let pcol = J2KBoxType(string: "pcol")

    /// Page box ('page') - Single page in a multi-page document
    public static let page = J2KBoxType(string: "page")

    /// Layout box ('lobj') - Layout information for objects
    public static let lobj = J2KBoxType(string: "lobj")
}

/// Reader for parsing JP2 boxes from binary data.
///
/// `J2KBoxReader` provides efficient parsing of box structures from JP2 files.
/// It handles standard and extended length boxes, and provides box-by-box iteration.
///
/// Example:
/// ```swift
/// let reader = J2KBoxReader(data: fileData)
/// while let box = try reader.readNextBox() {
///     print("Found box: \(box.type.stringValue)")
/// }
/// ```
public struct J2KBoxReader: Sendable {
    /// Information about a box found in the data.
    public struct BoxInfo: Sendable {
        /// The box type.
        public let type: J2KBoxType

        /// The offset of the box header in the data.
        public let headerOffset: Int

        /// The size of the box header (8 for standard, 16 for extended).
        public let headerSize: Int

        /// The total length of the box including header.
        public let totalLength: Int

        /// The offset of the box content (after the header).
        public var contentOffset: Int {
            headerOffset + headerSize
        }

        /// The length of the box content (excluding the header).
        public var contentLength: Int {
            totalLength - headerSize
        }
    }

    /// The data being read.
    private let data: Data

    /// The current read position.
    private var position: Int

    /// Creates a new box reader.
    ///
    /// - Parameter data: The data to read boxes from.
    public init(data: Data) {
        self.data = data
        self.position = 0
    }

    /// The current read position in the data.
    public var currentPosition: Int {
        position
    }

    /// Returns `true` if there are no more boxes to read.
    public var isAtEnd: Bool {
        position >= data.count
    }

    /// Reads the next box header without advancing the position.
    ///
    /// - Returns: Information about the next box, or `nil` if at end.
    /// - Throws: ``J2KError`` if the box header is invalid.
    public func peekNextBox() throws -> BoxInfo? {
        guard position < data.count else { return nil }

        guard position + 8 <= data.count else {
            throw J2KError.fileFormatError("Incomplete box header at offset \(position)")
        }

        // Read standard header
        let length = readUInt32(at: position)
        let type = J2KBoxType(rawValue: readUInt32(at: position + 4))

        // Determine actual length and header size
        var actualLength: Int
        var headerSize: Int

        if length == 0 {
            // Box extends to end of file
            actualLength = data.count - position
            headerSize = 8
        } else if length == 1 {
            // Extended length box
            guard position + 16 <= data.count else {
                throw J2KError.fileFormatError("Incomplete extended box header at offset \(position)")
            }
            let extendedLength = readUInt64(at: position + 8)
            guard extendedLength <= Int.max else {
                throw J2KError.fileFormatError("Box length exceeds maximum supported size")
            }
            actualLength = Int(extendedLength)
            headerSize = 16
        } else if length >= 8 {
            // Standard length
            actualLength = Int(length)
            headerSize = 8
        } else {
            throw J2KError.fileFormatError("Invalid box length \(length) at offset \(position)")
        }

        // Validate that box doesn't extend beyond data
        guard position + actualLength <= data.count else {
            throw J2KError.fileFormatError("Box extends beyond end of data at offset \(position)")
        }

        return BoxInfo(
            type: type,
            headerOffset: position,
            headerSize: headerSize,
            totalLength: actualLength
        )
    }

    /// Reads and returns the next box header, advancing the position.
    ///
    /// - Returns: Information about the next box, or `nil` if at end.
    /// - Throws: ``J2KError`` if the box header is invalid.
    public mutating func readNextBox() throws -> BoxInfo? {
        guard let info = try peekNextBox() else {
            return nil
        }
        position = info.headerOffset + info.totalLength
        return info
    }

    /// Extracts the content of a box.
    ///
    /// - Parameter info: The box information.
    /// - Returns: The box content data (excluding the header).
    public func extractContent(from info: BoxInfo) -> Data {
        let start = info.contentOffset
        let end = start + info.contentLength
        return data.subdata(in: start..<end)
    }

    /// Skips the current box and moves to the next one.
    ///
    /// - Throws: ``J2KError`` if skipping fails.
    public mutating func skipBox() throws {
        _ = try readNextBox()
    }

    /// Seeks to a specific position in the data.
    ///
    /// - Parameter offset: The offset to seek to.
    /// - Throws: ``J2KError`` if the offset is invalid.
    public mutating func seek(to offset: Int) throws {
        guard offset >= 0 && offset <= data.count else {
            throw J2KError.invalidParameter("Invalid seek offset: \(offset)")
        }
        position = offset
    }

    /// Reads all boxes from the current position to the end.
    ///
    /// - Returns: An array of box information structures.
    /// - Throws: ``J2KError`` if parsing fails.
    public mutating func readAllBoxes() throws -> [BoxInfo] {
        var boxes: [BoxInfo] = []
        while let box = try readNextBox() {
            boxes.append(box)
        }
        return boxes
    }

    // MARK: - Private Helpers

    private func readUInt32(at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24 |
        UInt32(data[offset + 1]) << 16 |
        UInt32(data[offset + 2]) << 8 |
        UInt32(data[offset + 3])
    }

    private func readUInt64(at offset: Int) -> UInt64 {
        UInt64(data[offset]) << 56 |
        UInt64(data[offset + 1]) << 48 |
        UInt64(data[offset + 2]) << 40 |
        UInt64(data[offset + 3]) << 32 |
        UInt64(data[offset + 4]) << 24 |
        UInt64(data[offset + 5]) << 16 |
        UInt64(data[offset + 6]) << 8 |
        UInt64(data[offset + 7])
    }
}

/// Writer for serializing JP2 boxes to binary data.
///
/// `J2KBoxWriter` provides efficient serialization of box structures to create JP2 files.
/// It automatically handles standard and extended length boxes.
///
/// Example:
/// ```swift
/// var writer = J2KBoxWriter()
/// try writer.writeBox(signatureBox)
/// try writer.writeBox(fileTypeBox)
/// let data = writer.data
/// ```
public struct J2KBoxWriter: Sendable {
    /// The buffer containing written data.
    private var buffer: Data

    /// Creates a new box writer.
    ///
    /// - Parameter capacity: The initial capacity in bytes (default: 4096).
    public init(capacity: Int = 4096) {
        self.buffer = Data()
        self.buffer.reserveCapacity(capacity)
    }

    /// The data written so far.
    public var data: Data {
        buffer
    }

    /// The number of bytes written.
    public var count: Int {
        buffer.count
    }

    /// Writes a box to the buffer.
    ///
    /// - Parameter box: The box to write.
    /// - Throws: ``J2KError`` if writing fails.
    public mutating func writeBox(_ box: some J2KBox) throws {
        let content = try box.write()
        try writeRawBox(type: box.boxType, content: content)
    }

    /// Writes a raw box with the given type and content.
    ///
    /// - Parameters:
    ///   - type: The box type.
    ///   - content: The box content (excluding header).
    /// - Throws: ``J2KError`` if writing fails.
    public mutating func writeRawBox(type: J2KBoxType, content: Data) throws {
        let headerSize = 8
        let totalLength = headerSize + content.count

        // Determine if we need extended length
        if totalLength > UInt32.max {
            // Use extended length format
            buffer.append(contentsOf: [0x00, 0x00, 0x00, 0x01]) // Length = 1
            writeUInt32(type.rawValue)
            writeUInt64(UInt64(totalLength + 8)) // Extended length includes the XLength field
            buffer.append(content)
        } else {
            // Use standard length format
            writeUInt32(UInt32(totalLength))
            writeUInt32(type.rawValue)
            buffer.append(content)
        }
    }

    /// Writes raw bytes to the buffer.
    ///
    /// - Parameter data: The data to write.
    public mutating func writeData(_ data: Data) {
        buffer.append(data)
    }

    // MARK: - Private Helpers

    private mutating func writeUInt32(_ value: UInt32) {
        buffer.append(UInt8((value >> 24) & 0xFF))
        buffer.append(UInt8((value >> 16) & 0xFF))
        buffer.append(UInt8((value >> 8) & 0xFF))
        buffer.append(UInt8(value & 0xFF))
    }

    private mutating func writeUInt64(_ value: UInt64) {
        buffer.append(UInt8((value >> 56) & 0xFF))
        buffer.append(UInt8((value >> 48) & 0xFF))
        buffer.append(UInt8((value >> 40) & 0xFF))
        buffer.append(UInt8((value >> 32) & 0xFF))
        buffer.append(UInt8((value >> 24) & 0xFF))
        buffer.append(UInt8((value >> 16) & 0xFF))
        buffer.append(UInt8((value >> 8) & 0xFF))
        buffer.append(UInt8(value & 0xFF))
    }
}
