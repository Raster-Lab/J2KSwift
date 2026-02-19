/// # J2KBoxes
///
/// Implementations of standard JP2 box types.
///
/// This module provides concrete implementations of the essential JP2 boxes
/// defined in ISO/IEC 15444-1.

import Foundation
import J2KCore
import J2KCodec

// MARK: - Signature Box

/// The JP2 signature box.
///
/// This box must be the first box in every JP2, JPX, and JPM file. It contains
/// a fixed signature that identifies the file as a JPEG 2000 file.
///
/// ## Box Structure
///
/// - Type: 'jP  ' (0x6A502020)
/// - Length: 12 bytes (fixed)
/// - Content: 0x0D0A870A (4 bytes)
///
/// Example:
/// ```swift
/// let box = J2KSignatureBox()
/// let data = try box.write()
/// // data contains: 0x0000000C 'jP  ' 0x0D0A870A
/// ```
public struct J2KSignatureBox: J2KBox {
    /// The signature content (always 0x0D0A870A).
    public static let signatureValue: UInt32 = 0x0D0A870A

    public var boxType: J2KBoxType {
        .jp
    }

    /// Creates a new signature box.
    public init() {}

    public func write() throws -> Data {
        var data = Data(capacity: 4)
        data.append(UInt8(0x0D))
        data.append(UInt8(0x0A))
        data.append(UInt8(0x87))
        data.append(UInt8(0x0A))
        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count == 4 else {
            throw J2KError.fileFormatError("Invalid signature box length: \(data.count), expected 4")
        }

        let signature = UInt32(data[0]) << 24 |
                       UInt32(data[1]) << 16 |
                       UInt32(data[2]) << 8 |
                       UInt32(data[3])

        guard signature == Self.signatureValue else {
            throw J2KError.fileFormatError(
                "Invalid JP2 signature: expected 0x\(String(Self.signatureValue, radix: 16, uppercase: true)), " +
                "got 0x\(String(signature, radix: 16, uppercase: true))"
            )
        }
    }
}

// MARK: - File Type Box

/// The file type box.
///
/// This box specifies the file type brand and compatibility information.
/// It must appear immediately after the signature box.
///
/// ## Box Structure
///
/// - Type: 'ftyp' (0x66747970)
/// - Length: Variable
/// - Content:
///   - Brand (4 bytes): Primary brand identifier (e.g., 'jp2 ', 'jpx ', 'jpm ')
///   - Minor version (4 bytes): Version number
///   - Compatible brands (4 × N bytes): List of compatible brands
///
/// Example:
/// ```swift
/// let box = J2KFileTypeBox(brand: .jp2, minorVersion: 0, compatibleBrands: [.jp2])
/// let data = try box.write()
/// ```
public struct J2KFileTypeBox: J2KBox {
    /// File type brands.
    public enum Brand: Equatable, Sendable {
        /// JP2 (JPEG 2000 Part 1)
        case jp2

        /// JPX (JPEG 2000 Part 2)
        case jpx

        /// JPM (JPEG 2000 Part 6)
        case jpm

        /// JPH (HTJ2K - JPEG 2000 Part 15)
        case jph

        /// Custom brand
        case custom(String)

        /// Returns the four-character brand identifier.
        public var identifier: String {
            switch self {
            case .jp2: return "jp2 "
            case .jpx: return "jpx "
            case .jpm: return "jpm "
            case .jph: return "jph "
            case .custom(let str): return str
            }
        }

        /// Creates a brand from a four-character identifier.
        public init(identifier: String) {
            switch identifier {
            case "jp2 ": self = .jp2
            case "jpx ": self = .jpx
            case "jpm ": self = .jpm
            case "jph ": self = .jph
            default: self = .custom(identifier)
            }
        }
    }

    public var boxType: J2KBoxType {
        .ftyp
    }

    /// The primary brand identifier.
    public var brand: Brand

    /// The minor version number.
    public var minorVersion: UInt32

    /// List of compatible brands.
    public var compatibleBrands: [Brand]

    /// Creates a new file type box.
    ///
    /// - Parameters:
    ///   - brand: The primary brand identifier.
    ///   - minorVersion: The minor version number (default: 0).
    ///   - compatibleBrands: List of compatible brands (default: empty).
    public init(brand: Brand, minorVersion: UInt32 = 0, compatibleBrands: [Brand] = []) {
        self.brand = brand
        self.minorVersion = minorVersion
        self.compatibleBrands = compatibleBrands
    }

    public func write() throws -> Data {
        var data = Data(capacity: 8 + compatibleBrands.count * 4)

        // Write brand
        let brandBytes = [UInt8](brand.identifier.utf8)
        guard brandBytes.count == 4 else {
            throw J2KError.invalidParameter("Brand identifier must be exactly 4 characters")
        }
        data.append(contentsOf: brandBytes)

        // Write minor version
        data.append(UInt8((minorVersion >> 24) & 0xFF))
        data.append(UInt8((minorVersion >> 16) & 0xFF))
        data.append(UInt8((minorVersion >> 8) & 0xFF))
        data.append(UInt8(minorVersion & 0xFF))

        // Write compatible brands
        for compatBrand in compatibleBrands {
            let compatBytes = [UInt8](compatBrand.identifier.utf8)
            guard compatBytes.count == 4 else {
                throw J2KError.invalidParameter("Compatible brand identifier must be exactly 4 characters")
            }
            data.append(contentsOf: compatBytes)
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 8 else {
            throw J2KError.fileFormatError("File type box too small: \(data.count) bytes, expected at least 8")
        }

        // Read brand
        let brandBytes = data[0..<4]
        guard let brandString = String(bytes: brandBytes, encoding: .ascii) else {
            throw J2KError.fileFormatError("Invalid brand identifier in file type box")
        }
        brand = Brand(identifier: brandString)

        // Read minor version
        minorVersion = UInt32(data[4]) << 24 |
                      UInt32(data[5]) << 16 |
                      UInt32(data[6]) << 8 |
                      UInt32(data[7])

        // Read compatible brands
        compatibleBrands = []
        let remainingBytes = data.count - 8
        guard remainingBytes % 4 == 0 else {
            throw J2KError.fileFormatError("Invalid compatible brands list length: \(remainingBytes)")
        }

        let numCompatBrands = remainingBytes / 4
        for i in 0..<numCompatBrands {
            let offset = 8 + i * 4
            let compatBytes = data[offset..<(offset + 4)]
            guard let compatString = String(bytes: compatBytes, encoding: .ascii) else {
                throw J2KError.fileFormatError("Invalid compatible brand identifier at index \(i)")
            }
            compatibleBrands.append(Brand(identifier: compatString))
        }
    }
}

// MARK: - JP2 Header Box

/// The JP2 header box.
///
/// This box is a superbox that contains other header boxes describing the
/// image properties. It must contain at least an image header box (ihdr).
///
/// ## Box Structure
///
/// - Type: 'jp2h' (0x6A703268)
/// - Length: Variable
/// - Content: Contains other boxes (ihdr, bpcc, colr, etc.)
///
/// Example:
/// ```swift
/// let ihdr = J2KImageHeaderBox(width: 512, height: 512, numComponents: 3, bitsPerComponent: 8)
/// let box = J2KHeaderBox(boxes: [ihdr])
/// let data = try box.write()
/// ```
public struct J2KHeaderBox: J2KBox {
    public var boxType: J2KBoxType {
        .jp2h
    }

    /// The child boxes contained in this header box.
    public var boxes: [any J2KBox]

    /// Creates a new JP2 header box.
    ///
    /// - Parameter boxes: The child boxes (default: empty).
    public init(boxes: [any J2KBox] = []) {
        self.boxes = boxes
    }

    public func write() throws -> Data {
        var writer = J2KBoxWriter()
        for box in boxes {
            try writer.writeBox(box)
        }
        return writer.data
    }

    public mutating func read(from data: Data) throws {
        // For now, we just store the raw data
        // A full implementation would parse all contained boxes
        boxes = []

        var reader = J2KBoxReader(data: data)
        while let boxInfo = try reader.readNextBox() {
            let content = reader.extractContent(from: boxInfo)

            // Parse known box types
            switch boxInfo.type {
            case .ihdr:
                var ihdr = J2KImageHeaderBox(width: 0, height: 0, numComponents: 0, bitsPerComponent: 0)
                try ihdr.read(from: content)
                boxes.append(ihdr)
            default:
                // Store as generic box for unknown types
                break
            }
        }
    }
}

// MARK: - Image Header Box

/// The image header box.
///
/// This box specifies the size of the image and the number of image components.
/// It must be the first box within the JP2 header box.
///
/// ## Box Structure
///
/// - Type: 'ihdr' (0x69686472)
/// - Length: 22 bytes (fixed)
/// - Content:
///   - Height (4 bytes): Image height in pixels
///   - Width (4 bytes): Image width in pixels
///   - Number of components (2 bytes): Number of image components
///   - Bits per component (1 byte): Bit depth (default value)
///   - Compression type (1 byte): Always 7 for JPEG 2000
///   - Color space unknown (1 byte): 0 or 1
///   - Intellectual property (1 byte): 0 or 1
///
/// Example:
/// ```swift
/// let box = J2KImageHeaderBox(
///     width: 1920,
///     height: 1080,
///     numComponents: 3,
///     bitsPerComponent: 8
/// )
/// let data = try box.write()
/// ```
public struct J2KImageHeaderBox: J2KBox {
    /// Compression type value for JPEG 2000.
    public static let compressionType: UInt8 = 7

    public var boxType: J2KBoxType {
        .ihdr
    }

    /// The image height in pixels.
    public var height: UInt32

    /// The image width in pixels.
    public var width: UInt32

    /// The number of image components.
    public var numComponents: UInt16

    /// The default bits per component (bit depth).
    ///
    /// This value is used when all components have the same bit depth.
    /// If components have different bit depths, a bits per component box (bpcc) must be used.
    public var bitsPerComponent: UInt8

    /// Compression type (always 7 for JPEG 2000).
    public var compressionType: UInt8

    /// Color space unknown flag.
    ///
    /// - `0`: Color space is known (specified in a color specification box)
    /// - `1`: Color space is unknown
    public var colorSpaceUnknown: UInt8

    /// Intellectual property flag.
    ///
    /// - `0`: No intellectual property rights information
    /// - `1`: Intellectual property rights information exists elsewhere in the file
    public var intellectualProperty: UInt8

    /// Creates a new image header box.
    ///
    /// - Parameters:
    ///   - width: The image width in pixels.
    ///   - height: The image height in pixels.
    ///   - numComponents: The number of image components.
    ///   - bitsPerComponent: The bits per component (1-38, actual value = bitsPerComponent - 1 + sign bit).
    ///   - compressionType: The compression type (default: 7 for JPEG 2000).
    ///   - colorSpaceUnknown: Whether the color space is unknown (default: 0).
    ///   - intellectualProperty: Whether IP information exists (default: 0).
    public init(
        width: UInt32,
        height: UInt32,
        numComponents: UInt16,
        bitsPerComponent: UInt8,
        compressionType: UInt8 = compressionType,
        colorSpaceUnknown: UInt8 = 0,
        intellectualProperty: UInt8 = 0
    ) {
        self.width = width
        self.height = height
        self.numComponents = numComponents
        self.bitsPerComponent = bitsPerComponent
        self.compressionType = compressionType
        self.colorSpaceUnknown = colorSpaceUnknown
        self.intellectualProperty = intellectualProperty
    }

    public func write() throws -> Data {
        guard compressionType == Self.compressionType else {
            throw J2KError.invalidParameter("Invalid compression type: \(compressionType), must be 7")
        }

        guard colorSpaceUnknown <= 1 else {
            throw J2KError.invalidParameter("Invalid color space unknown flag: \(colorSpaceUnknown), must be 0 or 1")
        }

        guard intellectualProperty <= 1 else {
            throw J2KError.invalidParameter("Invalid intellectual property flag: \(intellectualProperty), must be 0 or 1")
        }

        var data = Data(capacity: 14)

        // Height (4 bytes)
        data.append(UInt8((height >> 24) & 0xFF))
        data.append(UInt8((height >> 16) & 0xFF))
        data.append(UInt8((height >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))

        // Width (4 bytes)
        data.append(UInt8((width >> 24) & 0xFF))
        data.append(UInt8((width >> 16) & 0xFF))
        data.append(UInt8((width >> 8) & 0xFF))
        data.append(UInt8(width & 0xFF))

        // Number of components (2 bytes)
        data.append(UInt8((numComponents >> 8) & 0xFF))
        data.append(UInt8(numComponents & 0xFF))

        // Bits per component (1 byte)
        data.append(bitsPerComponent)

        // Compression type (1 byte)
        data.append(compressionType)

        // Color space unknown (1 byte)
        data.append(colorSpaceUnknown)

        // Intellectual property (1 byte)
        data.append(intellectualProperty)

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count == 14 else {
            throw J2KError.fileFormatError("Invalid image header box length: \(data.count), expected 14")
        }

        // Height (4 bytes)
        height = UInt32(data[0]) << 24 |
                UInt32(data[1]) << 16 |
                UInt32(data[2]) << 8 |
                UInt32(data[3])

        // Width (4 bytes)
        width = UInt32(data[4]) << 24 |
               UInt32(data[5]) << 16 |
               UInt32(data[6]) << 8 |
               UInt32(data[7])

        // Number of components (2 bytes)
        numComponents = UInt16(data[8]) << 8 |
                       UInt16(data[9])

        // Bits per component (1 byte)
        bitsPerComponent = data[10]

        // Compression type (1 byte)
        compressionType = data[11]
        guard compressionType == Self.compressionType else {
            throw J2KError.fileFormatError("Unsupported compression type: \(compressionType), expected 7")
        }

        // Color space unknown (1 byte)
        colorSpaceUnknown = data[12]
        guard colorSpaceUnknown <= 1 else {
            throw J2KError.fileFormatError("Invalid color space unknown flag: \(colorSpaceUnknown)")
        }

        // Intellectual property (1 byte)
        intellectualProperty = data[13]
        guard intellectualProperty <= 1 else {
            throw J2KError.fileFormatError("Invalid intellectual property flag: \(intellectualProperty)")
        }
    }
}

// MARK: - Bits Per Component Box

/// The bits per component box.
///
/// This box specifies the bit depth of each component when components have
/// different bit depths. If all components have the same bit depth, this box
/// is optional (the image header box suffices).
///
/// ## Box Structure
///
/// - Type: 'bpcc' (0x62706363)
/// - Length: Variable (8 + N bytes, where N = number of components)
/// - Content: Array of bytes, one per component
///
/// Each byte encodes:
/// - Bits 0-6: Bit depth minus 1 (0-127 represents 1-128 bits)
/// - Bit 7: Signed flag (0=unsigned, 1=signed)
///
/// ## Examples
///
/// ```swift
/// // 8-bit unsigned RGB
/// let box = J2KBitsPerComponentBox(bitDepths: [
///     .unsigned(8),
///     .unsigned(8),
///     .unsigned(8)
/// ])
///
/// // 16-bit signed grayscale
/// let box = J2KBitsPerComponentBox(bitDepths: [
///     .signed(16)
/// ])
///
/// // Mixed: 8-bit unsigned RGB + 16-bit unsigned alpha
/// let box = J2KBitsPerComponentBox(bitDepths: [
///     .unsigned(8),
///     .unsigned(8),
///     .unsigned(8),
///     .unsigned(16)
/// ])
/// ```
public struct J2KBitsPerComponentBox: J2KBox {
    /// Bit depth specification for a component.
    public enum BitDepth: Equatable, Sendable {
        /// Unsigned component with specified bit depth (1-128).
        case unsigned(UInt8)

        /// Signed component with specified bit depth (1-128).
        case signed(UInt8)

        /// Encodes the bit depth as a byte value.
        ///
        /// - Returns: Encoded byte value: (bits - 1) | (signed ? 0x80 : 0)
        public var encodedValue: UInt8 {
            switch self {
            case .unsigned(let bits):
                return bits - 1
            case .signed(let bits):
                return (bits - 1) | 0x80
            }
        }

        /// Decodes a byte value into a bit depth.
        ///
        /// - Parameter value: The encoded byte value.
        /// - Returns: The decoded bit depth.
        public static func decode(_ value: UInt8) -> BitDepth {
            let isSigned = (value & 0x80) != 0
            let bits = (value & 0x7F) + 1
            return isSigned ? .signed(bits) : .unsigned(bits)
        }

        /// Returns the actual bit depth value.
        public var bits: UInt8 {
            switch self {
            case .unsigned(let bits), .signed(let bits):
                return bits
            }
        }

        /// Returns whether the component is signed.
        public var isSigned: Bool {
            switch self {
            case .unsigned: return false
            case .signed: return true
            }
        }
    }

    public var boxType: J2KBoxType {
        .bpcc
    }

    /// The bit depth for each component.
    public var bitDepths: [BitDepth]

    /// Creates a new bits per component box.
    ///
    /// - Parameter bitDepths: The bit depth for each component.
    public init(bitDepths: [BitDepth]) {
        self.bitDepths = bitDepths
    }

    public func write() throws -> Data {
        guard !bitDepths.isEmpty else {
            throw J2KError.invalidParameter("Bits per component box must have at least one component")
        }

        guard bitDepths.count <= 16384 else {
            throw J2KError.invalidParameter("Too many components: \(bitDepths.count), maximum is 16384")
        }

        // Validate bit depths
        for (index, depth) in bitDepths.enumerated() {
            let bits = depth.bits
            guard bits >= 1 && bits <= 38 else {
                throw J2KError.invalidParameter(
                    "Invalid bit depth at component \(index): \(bits), must be 1-38"
                )
            }
        }

        var data = Data(capacity: bitDepths.count)
        for depth in bitDepths {
            data.append(depth.encodedValue)
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard !data.isEmpty else {
            throw J2KError.fileFormatError("Bits per component box is empty")
        }

        bitDepths = []
        for (index, byte) in data.enumerated() {
            let depth = BitDepth.decode(byte)
            let bits = depth.bits
            guard bits >= 1 && bits <= 38 else {
                throw J2KError.fileFormatError(
                    "Invalid bit depth at component \(index): \(bits), must be 1-38"
                )
            }
            bitDepths.append(depth)
        }
    }
}

// MARK: - Color Specification Box

/// The color specification box.
///
/// This box specifies the color space of the image. At least one color
/// specification box must be present in the JP2 header box.
///
/// ## Box Structure
///
/// - Type: 'colr' (0x636F6C72)
/// - Length: Variable
/// - Content:
///   - METH (1 byte): Specification method
///   - PREC (1 byte): Precedence
///   - APPROX (1 byte): Approximation
///   - EnumCS or ICC Profile data
///
/// ## Examples
///
/// ```swift
/// // sRGB color space
/// let box = J2KColorSpecificationBox(
///     method: .enumerated(.sRGB),
///     precedence: 0,
///     approximation: 0
/// )
///
/// // Grayscale
/// let box = J2KColorSpecificationBox(
///     method: .enumerated(.greyscale),
///     precedence: 0,
///     approximation: 0
/// )
///
/// // ICC profile
/// let iccData = Data(...)
/// let box = J2KColorSpecificationBox(
///     method: .restrictedICC(iccData),
///     precedence: 0,
///     approximation: 0
/// )
/// ```
public struct J2KColorSpecificationBox: J2KBox {
    /// Color specification method.
    public enum Method: Equatable, Sendable {
        /// Enumerated color space (method 1).
        case enumerated(EnumeratedColorSpace)

        /// Restricted ICC profile (method 2).
        case restrictedICC(Data)

        /// Any ICC profile (method 3).
        case anyICC(Data)

        /// Vendor-specific color space (method 4).
        case vendor(Data)

        /// Returns the method code.
        public var methodCode: UInt8 {
            switch self {
            case .enumerated: return 1
            case .restrictedICC: return 2
            case .anyICC: return 3
            case .vendor: return 4
            }
        }
    }

    /// Enumerated color space identifiers.
    public enum EnumeratedColorSpace: UInt32, Equatable, Sendable {
        /// sRGB color space (ITU-R BT.709).
        case sRGB = 16

        /// Greyscale (sGrey).
        case greyscale = 17

        /// YCbCr color space.
        case yCbCr = 18

        /// CMYK color space.
        case cmyk = 12

        /// e-sRGB color space.
        case esRGB = 20

        /// ROMM-RGB (ProPhoto RGB) color space.
        case rommRGB = 21
    }

    public var boxType: J2KBoxType {
        .colr
    }

    /// The color specification method.
    public var method: Method

    /// The precedence of this color specification (0-255).
    ///
    /// When multiple color specification boxes exist, the one with the
    /// lowest precedence value takes priority. Value 0 has highest priority.
    public var precedence: UInt8

    /// The approximation level (0=accurate, 1=approximate).
    public var approximation: UInt8

    /// Creates a new color specification box.
    ///
    /// - Parameters:
    ///   - method: The color specification method.
    ///   - precedence: The precedence (default: 0).
    ///   - approximation: The approximation level (default: 0).
    public init(method: Method, precedence: UInt8 = 0, approximation: UInt8 = 0) {
        self.method = method
        self.precedence = precedence
        self.approximation = approximation
    }

    public func write() throws -> Data {
        guard approximation <= 1 else {
            throw J2KError.invalidParameter("Invalid approximation value: \(approximation), must be 0 or 1")
        }

        var data = Data(capacity: 7)

        // METH (1 byte)
        data.append(method.methodCode)

        // PREC (1 byte)
        data.append(precedence)

        // APPROX (1 byte)
        data.append(approximation)

        // Method-specific data
        switch method {
        case .enumerated(let colorSpace):
            // EnumCS (4 bytes)
            let value = colorSpace.rawValue
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))

        case .restrictedICC(let profile), .anyICC(let profile), .vendor(let profile):
            guard !profile.isEmpty else {
                throw J2KError.invalidParameter("ICC profile data cannot be empty")
            }
            data.append(profile)
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 3 else {
            throw J2KError.fileFormatError("Color specification box too small: \(data.count) bytes, expected at least 3")
        }

        // METH (1 byte)
        let methodCode = data[0]

        // PREC (1 byte)
        precedence = data[1]

        // APPROX (1 byte)
        approximation = data[2]
        guard approximation <= 1 else {
            throw J2KError.fileFormatError("Invalid approximation value: \(approximation)")
        }

        // Method-specific data
        switch methodCode {
        case 1:
            // Enumerated color space
            guard data.count == 7 else {
                throw J2KError.fileFormatError(
                    "Invalid enumerated color space box length: \(data.count), expected 7"
                )
            }

            let enumValue = UInt32(data[3]) << 24 |
                           UInt32(data[4]) << 16 |
                           UInt32(data[5]) << 8 |
                           UInt32(data[6])

            guard let colorSpace = EnumeratedColorSpace(rawValue: enumValue) else {
                throw J2KError.fileFormatError("Unknown enumerated color space: \(enumValue)")
            }

            method = .enumerated(colorSpace)

        case 2:
            // Restricted ICC profile
            guard data.count > 3 else {
                throw J2KError.fileFormatError("Restricted ICC profile data is empty")
            }
            let profile = data.subdata(in: 3..<data.count)
            method = .restrictedICC(profile)

        case 3:
            // Any ICC profile
            guard data.count > 3 else {
                throw J2KError.fileFormatError("ICC profile data is empty")
            }
            let profile = data.subdata(in: 3..<data.count)
            method = .anyICC(profile)

        case 4:
            // Vendor color space
            guard data.count > 3 else {
                throw J2KError.fileFormatError("Vendor color space data is empty")
            }
            let profile = data.subdata(in: 3..<data.count)
            method = .vendor(profile)

        default:
            throw J2KError.fileFormatError("Invalid color specification method: \(methodCode)")
        }
    }
}

// MARK: - Palette Box

/// The palette box.
///
/// This box defines a palette for indexed color images. It specifies the
/// number of entries, number of palette components, and bit depth of each
/// palette component.
///
/// ## Box Structure
///
/// - Type: 'pclr' (0x70636C72)
/// - Length: Variable
/// - Content:
///   - NE (2 bytes): Number of entries (1-1024)
///   - NPC (1 byte): Number of palette components (1-255)
///   - B[i] (1 byte each): Bit depth for each component
///   - C[i][j]: Palette data (NE × NPC values)
///
/// ## Example
///
/// ```swift
/// // 256-entry RGB palette with 8-bit components
/// let entries: [[UInt32]] = [
///     [255, 0, 0],      // Red
///     [0, 255, 0],      // Green
///     [0, 0, 255],      // Blue
///     // ... 253 more entries
/// ]
/// let box = J2KPaletteBox(
///     entries: entries,
///     componentBitDepths: [.unsigned(8), .unsigned(8), .unsigned(8)]
/// )
/// ```
public struct J2KPaletteBox: J2KBox {
    public var boxType: J2KBoxType {
        .pclr
    }

    /// Palette entries, where each entry is an array of component values.
    ///
    /// The outer array has NE elements (number of entries).
    /// Each inner array has NPC elements (number of components per entry).
    public var entries: [[UInt32]]

    /// Bit depth specification for each palette component.
    public var componentBitDepths: [J2KBitsPerComponentBox.BitDepth]

    /// Number of palette entries.
    public var numEntries: Int {
        entries.count
    }

    /// Number of components per palette entry.
    public var numComponents: Int {
        componentBitDepths.count
    }

    /// Creates a new palette box.
    ///
    /// - Parameters:
    ///   - entries: The palette entries (1-1024 entries).
    ///   - componentBitDepths: The bit depth for each component (1-255 components).
    /// - Throws: ``J2KError`` if validation fails.
    public init(entries: [[UInt32]], componentBitDepths: [J2KBitsPerComponentBox.BitDepth]) {
        self.entries = entries
        self.componentBitDepths = componentBitDepths
    }

    public func write() throws -> Data {
        // Validate number of entries
        guard numEntries >= 1 && numEntries <= 1024 else {
            throw J2KError.invalidParameter(
                "Invalid number of palette entries: \(numEntries), must be 1-1024"
            )
        }

        // Validate number of components
        guard numComponents >= 1 && numComponents <= 255 else {
            throw J2KError.invalidParameter(
                "Invalid number of palette components: \(numComponents), must be 1-255"
            )
        }

        // Validate component bit depths
        for (i, depth) in componentBitDepths.enumerated() {
            let bits = depth.bits
            guard bits >= 1 && bits <= 38 else {
                throw J2KError.invalidParameter(
                    "Invalid bit depth for component \(i): \(bits), must be 1-38"
                )
            }
        }

        // Validate all entries have correct number of components
        for (i, entry) in entries.enumerated() {
            guard entry.count == numComponents else {
                throw J2KError.invalidParameter(
                    "Entry \(i) has \(entry.count) components, expected \(numComponents)"
                )
            }
        }

        var data = Data()

        // NE (2 bytes)
        data.append(UInt8((numEntries >> 8) & 0xFF))
        data.append(UInt8(numEntries & 0xFF))

        // NPC (1 byte)
        data.append(UInt8(numComponents))

        // B[i] - bit depths
        for depth in componentBitDepths {
            data.append(depth.encodedValue)
        }

        // C[i][j] - palette data
        for entry in entries {
            for (componentIndex, value) in entry.enumerated() {
                let bits = componentBitDepths[componentIndex].bits
                let numBytes = (Int(bits) + 7) / 8

                // Validate value fits in specified bit depth
                let maxValue = (UInt32(1) << bits) - 1
                guard value <= maxValue else {
                    throw J2KError.invalidParameter(
                        "Palette value \(value) exceeds maximum for \(bits)-bit component: \(maxValue)"
                    )
                }

                // Write value as big-endian
                for byteIndex in (0..<numBytes).reversed() {
                    let byte = UInt8((value >> (byteIndex * 8)) & 0xFF)
                    data.append(byte)
                }
            }
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 3 else {
            throw J2KError.fileFormatError("Palette box too small: \(data.count) bytes, expected at least 3")
        }

        // NE (2 bytes)
        let ne = Int(data[0]) << 8 | Int(data[1])
        guard ne >= 1 && ne <= 1024 else {
            throw J2KError.fileFormatError("Invalid number of palette entries: \(ne), must be 1-1024")
        }

        // NPC (1 byte)
        let npc = Int(data[2])
        guard npc >= 1 && npc <= 255 else {
            throw J2KError.fileFormatError("Invalid number of palette components: \(npc), must be 1-255")
        }

        // B[i] - bit depths
        guard data.count >= 3 + npc else {
            throw J2KError.fileFormatError("Palette box too small for bit depth array")
        }

        componentBitDepths = []
        var totalBytesPerEntry = 0

        for i in 0..<npc {
            let byte = data[3 + i]
            let depth = J2KBitsPerComponentBox.BitDepth.decode(byte)
            let bits = depth.bits

            guard bits >= 1 && bits <= 38 else {
                throw J2KError.fileFormatError(
                    "Invalid bit depth for component \(i): \(bits), must be 1-38"
                )
            }

            componentBitDepths.append(depth)
            totalBytesPerEntry += (Int(bits) + 7) / 8
        }

        // C[i][j] - palette data
        let headerSize = 3 + npc
        let expectedDataSize = headerSize + ne * totalBytesPerEntry

        guard data.count == expectedDataSize else {
            throw J2KError.fileFormatError(
                "Invalid palette data size: \(data.count) bytes, expected \(expectedDataSize)"
            )
        }

        entries = []
        var offset = headerSize

        for _ in 0..<ne {
            var entry: [UInt32] = []

            for depth in componentBitDepths {
                let bits = depth.bits
                let numBytes = (Int(bits) + 7) / 8

                var value: UInt32 = 0
                for byteIndex in 0..<numBytes {
                    value = (value << 8) | UInt32(data[offset + byteIndex])
                }

                entry.append(value)
                offset += numBytes
            }

            entries.append(entry)
        }
    }
}

// MARK: - Component Mapping Box

/// The component mapping box.
///
/// This box specifies the mapping between components in the codestream and
/// channels in the image. It is required when using a palette or when the
/// component ordering needs to be specified.
///
/// ## Box Structure
///
/// - Type: 'cmap' (0x636D6170)
/// - Length: Variable (8 + N × 4 bytes, where N = number of components)
/// - Content: Array of 4-byte mapping entries
///
/// Each mapping entry contains:
/// - CMP (2 bytes): Component index in codestream (0-65535)
/// - MTYP (1 byte): Mapping type (0=direct, 1=palette)
/// - PCOL (1 byte): Palette column (0-255, only valid when MTYP=1)
///
/// ## Examples
///
/// ```swift
/// // Direct mapping (RGB components map directly)
/// let box = J2KComponentMappingBox(mappings: [
///     .direct(component: 0),
///     .direct(component: 1),
///     .direct(component: 2)
/// ])
///
/// // Palette mapping (indexed color)
/// let box = J2KComponentMappingBox(mappings: [
///     .palette(component: 0, paletteColumn: 0),
///     .palette(component: 0, paletteColumn: 1),
///     .palette(component: 0, paletteColumn: 2)
/// ])
/// ```
public struct J2KComponentMappingBox: J2KBox {
    /// Component mapping entry.
    public enum Mapping: Equatable, Sendable {
        /// Direct mapping to a codestream component.
        case direct(component: UInt16)

        /// Palette mapping to a component and palette column.
        case palette(component: UInt16, paletteColumn: UInt8)

        /// Returns the component index.
        public var component: UInt16 {
            switch self {
            case .direct(let comp), .palette(let comp, _):
                return comp
            }
        }

        /// Returns the mapping type (0=direct, 1=palette).
        public var mappingType: UInt8 {
            switch self {
            case .direct: return 0
            case .palette: return 1
            }
        }

        /// Returns the palette column (0 for direct mapping).
        public var paletteColumn: UInt8 {
            switch self {
            case .direct: return 0
            case .palette(_, let col): return col
            }
        }
    }

    public var boxType: J2KBoxType {
        .cmap
    }

    /// The component mappings.
    public var mappings: [Mapping]

    /// Creates a new component mapping box.
    ///
    /// - Parameter mappings: The component mappings.
    public init(mappings: [Mapping]) {
        self.mappings = mappings
    }

    public func write() throws -> Data {
        guard !mappings.isEmpty else {
            throw J2KError.invalidParameter("Component mapping box must have at least one mapping")
        }

        var data = Data(capacity: mappings.count * 4)

        for mapping in mappings {
            let comp = mapping.component
            let mtyp = mapping.mappingType
            let pcol = mapping.paletteColumn

            // CMP (2 bytes)
            data.append(UInt8((comp >> 8) & 0xFF))
            data.append(UInt8(comp & 0xFF))

            // MTYP (1 byte)
            data.append(mtyp)

            // PCOL (1 byte)
            data.append(pcol)
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 4 else {
            throw J2KError.fileFormatError("Component mapping box too small: \(data.count) bytes, expected at least 4")
        }

        guard data.count % 4 == 0 else {
            throw J2KError.fileFormatError("Invalid component mapping box size: \(data.count), must be multiple of 4")
        }

        let numMappings = data.count / 4
        mappings = []

        for i in 0..<numMappings {
            let offset = i * 4

            // CMP (2 bytes)
            let comp = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])

            // MTYP (1 byte)
            let mtyp = data[offset + 2]

            // PCOL (1 byte)
            let pcol = data[offset + 3]

            let mapping: Mapping
            switch mtyp {
            case 0:
                mapping = .direct(component: comp)
            case 1:
                mapping = .palette(component: comp, paletteColumn: pcol)
            default:
                throw J2KError.fileFormatError("Invalid mapping type at index \(i): \(mtyp), must be 0 or 1")
            }

            mappings.append(mapping)
        }
    }
}

// MARK: - Channel Definition Box

/// The channel definition box.
///
/// This box specifies the type and association of each channel in the image.
/// It is optional but recommended for images with specific channel types
/// (e.g., color with alpha, premultiplied alpha).
///
/// ## Box Structure
///
/// - Type: 'cdef' (0x63646566)
/// - Length: Variable (8 + 2 + N × 6 bytes, where N = number of channels)
/// - Content:
///   - N (2 bytes): Number of channel descriptions
///   - For each channel:
///     - Cn (2 bytes): Channel index (0-65535)
///     - Typ (2 bytes): Channel type
///     - Asoc (2 bytes): Associated channel
///
/// ## Channel Types
///
/// - 0: Color channel
/// - 1: Opacity (alpha) channel
/// - 2: Premultiplied opacity channel
/// - 65535: Unspecified channel type
///
/// ## Association Values
///
/// - 0: Associated with whole image
/// - 1-65534: Associated with specific color channel
/// - 65535: Unassociated
///
/// ## Examples
///
/// ```swift
/// // RGB with alpha
/// let box = J2KChannelDefinitionBox(channels: [
///     .color(index: 0, association: 1),   // Red
///     .color(index: 1, association: 2),   // Green
///     .color(index: 2, association: 3),   // Blue
///     .opacity(index: 3, association: 0)  // Alpha (whole image)
/// ])
///
/// // Grayscale with alpha
/// let box = J2KChannelDefinitionBox(channels: [
///     .color(index: 0, association: 1),   // Luminance
///     .opacity(index: 1, association: 0)  // Alpha
/// ])
/// ```
public struct J2KChannelDefinitionBox: J2KBox {
    /// Channel definition.
    public struct Channel: Equatable, Sendable {
        /// The channel index in the codestream (0-65535).
        public let index: UInt16

        /// The channel type.
        public let type: ChannelType

        /// The associated channel or image (0-65535).
        ///
        /// - 0: Associated with whole image
        /// - 1-65534: Associated with specific color channel
        /// - 65535: Unassociated
        public let association: UInt16

        /// Creates a new channel definition.
        ///
        /// - Parameters:
        ///   - index: The channel index.
        ///   - type: The channel type.
        ///   - association: The association.
        public init(index: UInt16, type: ChannelType, association: UInt16) {
            self.index = index
            self.type = type
            self.association = association
        }

        /// Creates a color channel definition.
        ///
        /// - Parameters:
        ///   - index: The channel index.
        ///   - association: The associated color channel (default: 0 for whole image).
        /// - Returns: A color channel definition.
        public static func color(index: UInt16, association: UInt16 = 0) -> Channel {
            Channel(index: index, type: .color, association: association)
        }

        /// Creates an opacity (alpha) channel definition.
        ///
        /// - Parameters:
        ///   - index: The channel index.
        ///   - association: The associated image/channel (default: 0 for whole image).
        /// - Returns: An opacity channel definition.
        public static func opacity(index: UInt16, association: UInt16 = 0) -> Channel {
            Channel(index: index, type: .opacity, association: association)
        }

        /// Creates a premultiplied opacity channel definition.
        ///
        /// - Parameters:
        ///   - index: The channel index.
        ///   - association: The associated image/channel (default: 0 for whole image).
        /// - Returns: A premultiplied opacity channel definition.
        public static func premultipliedOpacity(index: UInt16, association: UInt16 = 0) -> Channel {
            Channel(index: index, type: .premultipliedOpacity, association: association)
        }

        /// Creates an unspecified channel definition.
        ///
        /// - Parameters:
        ///   - index: The channel index.
        ///   - association: The association (default: 65535 for unassociated).
        /// - Returns: An unspecified channel definition.
        public static func unspecified(index: UInt16, association: UInt16 = 65535) -> Channel {
            Channel(index: index, type: .unspecified, association: association)
        }
    }

    /// Channel type identifiers.
    public enum ChannelType: UInt16, Equatable, Sendable {
        /// Color channel.
        case color = 0

        /// Opacity (alpha) channel.
        case opacity = 1

        /// Premultiplied opacity channel.
        case premultipliedOpacity = 2

        /// Unspecified channel type.
        case unspecified = 65535
    }

    public var boxType: J2KBoxType {
        .cdef
    }

    /// The channel definitions.
    public var channels: [Channel]

    /// Creates a new channel definition box.
    ///
    /// - Parameter channels: The channel definitions.
    public init(channels: [Channel]) {
        self.channels = channels
    }

    public func write() throws -> Data {
        guard !channels.isEmpty else {
            throw J2KError.invalidParameter("Channel definition box must have at least one channel")
        }

        guard channels.count <= 65535 else {
            throw J2KError.invalidParameter("Too many channels: \(channels.count), maximum is 65535")
        }

        var data = Data(capacity: 2 + channels.count * 6)

        // N (2 bytes)
        let n = UInt16(channels.count)
        data.append(UInt8((n >> 8) & 0xFF))
        data.append(UInt8(n & 0xFF))

        // Channel definitions
        for channel in channels {
            // Cn (2 bytes)
            data.append(UInt8((channel.index >> 8) & 0xFF))
            data.append(UInt8(channel.index & 0xFF))

            // Typ (2 bytes)
            let typ = channel.type.rawValue
            data.append(UInt8((typ >> 8) & 0xFF))
            data.append(UInt8(typ & 0xFF))

            // Asoc (2 bytes)
            data.append(UInt8((channel.association >> 8) & 0xFF))
            data.append(UInt8(channel.association & 0xFF))
        }

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 2 else {
            throw J2KError.fileFormatError("Channel definition box too small: \(data.count) bytes, expected at least 2")
        }

        // N (2 bytes)
        let n = Int(data[0]) << 8 | Int(data[1])

        let expectedSize = 2 + n * 6
        guard data.count == expectedSize else {
            throw J2KError.fileFormatError(
                "Invalid channel definition box size: \(data.count) bytes, expected \(expectedSize)"
            )
        }

        channels = []

        for i in 0..<n {
            let offset = 2 + i * 6

            // Cn (2 bytes)
            let index = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])

            // Typ (2 bytes)
            let typValue = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
            guard let type = ChannelType(rawValue: typValue) else {
                throw J2KError.fileFormatError("Invalid channel type at index \(i): \(typValue)")
            }

            // Asoc (2 bytes)
            let association = UInt16(data[offset + 4]) << 8 | UInt16(data[offset + 5])

            channels.append(Channel(index: index, type: type, association: association))
        }
    }
}

// MARK: - Resolution Boxes

/// Resolution box.
///
/// The resolution box ('res ') is a superbox that contains resolution information
/// for the image. It contains one or both of the Capture Resolution Box ('resc')
/// and the Display Resolution Box ('resd').
///
/// ## Box Structure
///
/// - Type: 'res ' (0x72657320)
/// - Length: Variable (superbox container)
/// - Content: Contains 'resc' and/or 'resd' boxes
///
/// Example:
/// ```swift
/// let captureRes = J2KCaptureResolutionBox(
///     horizontalResolution: (72, 1, 0),
///     verticalResolution: (72, 1, 0),
///     unit: .inch
/// )
/// let displayRes = J2KDisplayResolutionBox(
///     horizontalResolution: (72, 1, 0),
///     verticalResolution: (72, 1, 0),
///     unit: .inch
/// )
/// let resBox = J2KResolutionBox(
///     captureResolution: captureRes,
///     displayResolution: displayRes
/// )
/// ```
public struct J2KResolutionBox: J2KBox {
    /// The capture resolution box (optional).
    public var captureResolution: J2KCaptureResolutionBox?

    /// The display resolution box (optional).
    public var displayResolution: J2KDisplayResolutionBox?

    public var boxType: J2KBoxType {
        .res
    }

    /// Creates a new resolution box.
    ///
    /// - Parameters:
    ///   - captureResolution: The capture resolution box (optional).
    ///   - displayResolution: The display resolution box (optional).
    public init(
        captureResolution: J2KCaptureResolutionBox? = nil,
        displayResolution: J2KDisplayResolutionBox? = nil
    ) {
        self.captureResolution = captureResolution
        self.displayResolution = displayResolution
    }

    public func write() throws -> Data {
        var writer = J2KBoxWriter()

        // Write capture resolution box if present
        if let captureRes = captureResolution {
            try writer.writeBox(captureRes)
        }

        // Write display resolution box if present
        if let displayRes = displayResolution {
            try writer.writeBox(displayRes)
        }

        return writer.data
    }

    public mutating func read(from data: Data) throws {
        var reader = J2KBoxReader(data: data)

        while let boxInfo = try reader.readNextBox() {
            let content = reader.extractContent(from: boxInfo)

            switch boxInfo.type {
            case .resc:
                var captureRes = J2KCaptureResolutionBox(
                    horizontalResolution: (1, 1, 0),
                    verticalResolution: (1, 1, 0),
                    unit: .unknown
                )
                try captureRes.read(from: content)
                self.captureResolution = captureRes

            case .resd:
                var displayRes = J2KDisplayResolutionBox(
                    horizontalResolution: (1, 1, 0),
                    verticalResolution: (1, 1, 0),
                    unit: .unknown
                )
                try displayRes.read(from: content)
                self.displayResolution = displayRes

            default:
                // Ignore unknown boxes
                break
            }
        }
    }
}

/// Capture resolution box.
///
/// The capture resolution box ('resc') specifies the resolution at which
/// the image was originally captured or created.
///
/// ## Box Structure
///
/// - Type: 'resc' (0x72657363)
/// - Length: 27 bytes (fixed)
/// - Content:
///   - HRcN (4 bytes): Horizontal resolution numerator
///   - HRcD (4 bytes): Horizontal resolution denominator
///   - HRcE (1 byte): Horizontal resolution exponent (signed)
///   - VRcN (4 bytes): Vertical resolution numerator
///   - VRcD (4 bytes): Vertical resolution denominator
///   - VRcE (1 byte): Vertical resolution exponent (signed)
///   - Unit (1 byte): Resolution unit
///
/// The resolution is calculated as: (numerator / denominator) × 10^exponent
///
/// Example:
/// ```swift
/// // 72 DPI (dots per inch)
/// let box = J2KCaptureResolutionBox(
///     horizontalResolution: (72, 1, 0),
///     verticalResolution: (72, 1, 0),
///     unit: .inch
/// )
///
/// // 300 DPI
/// let box2 = J2KCaptureResolutionBox(
///     horizontalResolution: (300, 1, 0),
///     verticalResolution: (300, 1, 0),
///     unit: .inch
/// )
/// ```
public struct J2KCaptureResolutionBox: J2KBox {
    /// Resolution units.
    public enum Unit: UInt8, Sendable {
        /// Unknown or unspecified units
        case unknown = 0

        /// Pixels per metre
        case metre = 1

        /// Pixels per inch
        case inch = 2
    }

    /// Horizontal resolution (numerator, denominator, exponent).
    public var horizontalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8)

    /// Vertical resolution (numerator, denominator, exponent).
    public var verticalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8)

    /// Resolution unit.
    public var unit: Unit

    public var boxType: J2KBoxType {
        .resc
    }

    /// Creates a new capture resolution box.
    ///
    /// - Parameters:
    ///   - horizontalResolution: The horizontal resolution as (numerator, denominator, exponent).
    ///   - verticalResolution: The vertical resolution as (numerator, denominator, exponent).
    ///   - unit: The resolution unit.
    public init(
        horizontalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8),
        verticalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8),
        unit: Unit
    ) {
        self.horizontalResolution = horizontalResolution
        self.verticalResolution = verticalResolution
        self.unit = unit
    }

    public func write() throws -> Data {
        var data = Data(capacity: 19)

        // HRcN (4 bytes)
        data.append(UInt8((horizontalResolution.numerator >> 24) & 0xFF))
        data.append(UInt8((horizontalResolution.numerator >> 16) & 0xFF))
        data.append(UInt8((horizontalResolution.numerator >> 8) & 0xFF))
        data.append(UInt8(horizontalResolution.numerator & 0xFF))

        // HRcD (4 bytes)
        data.append(UInt8((horizontalResolution.denominator >> 24) & 0xFF))
        data.append(UInt8((horizontalResolution.denominator >> 16) & 0xFF))
        data.append(UInt8((horizontalResolution.denominator >> 8) & 0xFF))
        data.append(UInt8(horizontalResolution.denominator & 0xFF))

        // HRcE (1 byte)
        data.append(UInt8(bitPattern: horizontalResolution.exponent))

        // VRcN (4 bytes)
        data.append(UInt8((verticalResolution.numerator >> 24) & 0xFF))
        data.append(UInt8((verticalResolution.numerator >> 16) & 0xFF))
        data.append(UInt8((verticalResolution.numerator >> 8) & 0xFF))
        data.append(UInt8(verticalResolution.numerator & 0xFF))

        // VRcD (4 bytes)
        data.append(UInt8((verticalResolution.denominator >> 24) & 0xFF))
        data.append(UInt8((verticalResolution.denominator >> 16) & 0xFF))
        data.append(UInt8((verticalResolution.denominator >> 8) & 0xFF))
        data.append(UInt8(verticalResolution.denominator & 0xFF))

        // VRcE (1 byte)
        data.append(UInt8(bitPattern: verticalResolution.exponent))

        // Unit (1 byte)
        data.append(unit.rawValue)

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count == 19 else {
            throw J2KError.fileFormatError("Invalid capture resolution box length: \(data.count), expected 19")
        }

        // HRcN (4 bytes)
        let hrcn = UInt32(data[0]) << 24 |
                   UInt32(data[1]) << 16 |
                   UInt32(data[2]) << 8 |
                   UInt32(data[3])

        // HRcD (4 bytes)
        let hrcd = UInt32(data[4]) << 24 |
                   UInt32(data[5]) << 16 |
                   UInt32(data[6]) << 8 |
                   UInt32(data[7])

        // HRcE (1 byte, signed)
        let hrce = Int8(bitPattern: data[8])

        // VRcN (4 bytes)
        let vrcn = UInt32(data[9]) << 24 |
                   UInt32(data[10]) << 16 |
                   UInt32(data[11]) << 8 |
                   UInt32(data[12])

        // VRcD (4 bytes)
        let vrcd = UInt32(data[13]) << 24 |
                   UInt32(data[14]) << 16 |
                   UInt32(data[15]) << 8 |
                   UInt32(data[16])

        // VRcE (1 byte, signed)
        let vrce = Int8(bitPattern: data[17])

        // Unit (1 byte)
        guard let unitValue = Unit(rawValue: data[18]) else {
            throw J2KError.fileFormatError("Invalid resolution unit: \(data[18])")
        }

        self.horizontalResolution = (hrcn, hrcd, hrce)
        self.verticalResolution = (vrcn, vrcd, vrce)
        self.unit = unitValue
    }
}

/// Display resolution box.
///
/// The display resolution box ('resd') specifies the recommended resolution
/// at which the image should be displayed.
///
/// ## Box Structure
///
/// - Type: 'resd' (0x72657364)
/// - Length: 27 bytes (fixed)
/// - Content: Same structure as Capture Resolution Box
///
/// Example:
/// ```swift
/// let box = J2KDisplayResolutionBox(
///     horizontalResolution: (72, 1, 0),
///     verticalResolution: (72, 1, 0),
///     unit: .inch
/// )
/// ```
public struct J2KDisplayResolutionBox: J2KBox {
    /// Resolution units (same as Capture Resolution Box).
    public typealias Unit = J2KCaptureResolutionBox.Unit

    /// Horizontal resolution (numerator, denominator, exponent).
    public var horizontalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8)

    /// Vertical resolution (numerator, denominator, exponent).
    public var verticalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8)

    /// Resolution unit.
    public var unit: Unit

    public var boxType: J2KBoxType {
        .resd
    }

    /// Creates a new display resolution box.
    ///
    /// - Parameters:
    ///   - horizontalResolution: The horizontal resolution as (numerator, denominator, exponent).
    ///   - verticalResolution: The vertical resolution as (numerator, denominator, exponent).
    ///   - unit: The resolution unit.
    public init(
        horizontalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8),
        verticalResolution: (numerator: UInt32, denominator: UInt32, exponent: Int8),
        unit: Unit
    ) {
        self.horizontalResolution = horizontalResolution
        self.verticalResolution = verticalResolution
        self.unit = unit
    }

    public func write() throws -> Data {
        var data = Data(capacity: 19)

        // HRdN (4 bytes)
        data.append(UInt8((horizontalResolution.numerator >> 24) & 0xFF))
        data.append(UInt8((horizontalResolution.numerator >> 16) & 0xFF))
        data.append(UInt8((horizontalResolution.numerator >> 8) & 0xFF))
        data.append(UInt8(horizontalResolution.numerator & 0xFF))

        // HRdD (4 bytes)
        data.append(UInt8((horizontalResolution.denominator >> 24) & 0xFF))
        data.append(UInt8((horizontalResolution.denominator >> 16) & 0xFF))
        data.append(UInt8((horizontalResolution.denominator >> 8) & 0xFF))
        data.append(UInt8(horizontalResolution.denominator & 0xFF))

        // HRdE (1 byte)
        data.append(UInt8(bitPattern: horizontalResolution.exponent))

        // VRdN (4 bytes)
        data.append(UInt8((verticalResolution.numerator >> 24) & 0xFF))
        data.append(UInt8((verticalResolution.numerator >> 16) & 0xFF))
        data.append(UInt8((verticalResolution.numerator >> 8) & 0xFF))
        data.append(UInt8(verticalResolution.numerator & 0xFF))

        // VRdD (4 bytes)
        data.append(UInt8((verticalResolution.denominator >> 24) & 0xFF))
        data.append(UInt8((verticalResolution.denominator >> 16) & 0xFF))
        data.append(UInt8((verticalResolution.denominator >> 8) & 0xFF))
        data.append(UInt8(verticalResolution.denominator & 0xFF))

        // VRdE (1 byte)
        data.append(UInt8(bitPattern: verticalResolution.exponent))

        // Unit (1 byte)
        data.append(unit.rawValue)

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count == 19 else {
            throw J2KError.fileFormatError("Invalid display resolution box length: \(data.count), expected 19")
        }

        // HRdN (4 bytes)
        let hrdn = UInt32(data[0]) << 24 |
                   UInt32(data[1]) << 16 |
                   UInt32(data[2]) << 8 |
                   UInt32(data[3])

        // HRdD (4 bytes)
        let hrdd = UInt32(data[4]) << 24 |
                   UInt32(data[5]) << 16 |
                   UInt32(data[6]) << 8 |
                   UInt32(data[7])

        // HRdE (1 byte, signed)
        let hrde = Int8(bitPattern: data[8])

        // VRdN (4 bytes)
        let vrdn = UInt32(data[9]) << 24 |
                   UInt32(data[10]) << 16 |
                   UInt32(data[11]) << 8 |
                   UInt32(data[12])

        // VRdD (4 bytes)
        let vrdd = UInt32(data[13]) << 24 |
                   UInt32(data[14]) << 16 |
                   UInt32(data[15]) << 8 |
                   UInt32(data[16])

        // VRdE (1 byte, signed)
        let vrde = Int8(bitPattern: data[17])

        // Unit (1 byte)
        guard let unitValue = Unit(rawValue: data[18]) else {
            throw J2KError.fileFormatError("Invalid resolution unit: \(data[18])")
        }

        self.horizontalResolution = (hrdn, hrdd, hrde)
        self.verticalResolution = (vrdn, vrdd, vrde)
        self.unit = unitValue
    }
}

// MARK: - UUID Box

/// UUID box.
///
/// The UUID box ('uuid') allows for vendor-specific or application-specific
/// extensions to the JP2 format. The box is identified by a 16-byte UUID
/// (Universally Unique Identifier) that uniquely identifies the type of data.
///
/// ## Box Structure
///
/// - Type: 'uuid' (0x75756964)
/// - Length: Variable
/// - Content:
///   - UUID (16 bytes): Unique identifier
///   - Data (N bytes): Application-specific data
///
/// Example:
/// ```swift
/// import Foundation
///
/// let uuid = UUID()
/// let customData = "Custom metadata".data(using: .utf8)!
/// let box = J2KUUIDBox(uuid: uuid, data: customData)
/// ```
public struct J2KUUIDBox: J2KBox {
    /// The 16-byte UUID identifying this box's content type.
    public var uuid: UUID

    /// The application-specific data.
    public var data: Data

    public var boxType: J2KBoxType {
        .uuid
    }

    /// Creates a new UUID box.
    ///
    /// - Parameters:
    ///   - uuid: The UUID identifying the content type.
    ///   - data: The application-specific data.
    public init(uuid: UUID, data: Data) {
        self.uuid = uuid
        self.data = data
    }

    public func write() throws -> Data {
        var output = Data(capacity: 16 + data.count)

        // Write UUID (16 bytes)
        var uuidBytes = uuid.uuid
        withUnsafeBytes(of: &uuidBytes) { bytes in
            output.append(contentsOf: bytes)
        }

        // Write data
        output.append(data)

        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 16 else {
            throw J2KError.fileFormatError("Invalid UUID box length: \(data.count), expected at least 16")
        }

        // Read UUID (16 bytes)
        let uuidBytes = data.prefix(16)
        var uuidTuple: uuid_t = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        _ = withUnsafeMutableBytes(of: &uuidTuple) { buffer in
            uuidBytes.copyBytes(to: buffer)
        }
        self.uuid = UUID(uuid: uuidTuple)

        // Read remaining data
        self.data = data.suffix(from: 16)
    }
}

// MARK: - XML Box

/// XML box.
///
/// The XML box ('xml ') embeds XML-formatted metadata within the JP2 file.
/// The content must be valid, well-formed XML encoded as UTF-8.
///
/// ## Box Structure
///
/// - Type: 'xml ' (0x786D6C20)
/// - Length: Variable
/// - Content: UTF-8 encoded XML data
///
/// Example:
/// ```swift
/// let xmlString = """
/// <?xml version="1.0" encoding="UTF-8"?>
/// <metadata>
///     <title>Sample Image</title>
///     <author>John Doe</author>
///     <date>2024-01-01</date>
/// </metadata>
/// """
/// let box = try J2KXMLBox(xmlString: xmlString)
/// ```
public struct J2KXMLBox: J2KBox {
    /// The XML content as a string.
    public var xmlString: String

    public var boxType: J2KBoxType {
        .xml
    }

    /// Creates a new XML box.
    ///
    /// - Parameter xmlString: The XML content as a string.
    /// - Throws: ``J2KError/fileFormatError(_:)`` if the string cannot be encoded as UTF-8.
    public init(xmlString: String) throws {
        // Validate that the string can be encoded as UTF-8
        guard xmlString.data(using: .utf8) != nil else {
            throw J2KError.fileFormatError("XML string cannot be encoded as UTF-8")
        }
        self.xmlString = xmlString
    }

    /// Creates a new XML box from raw data.
    ///
    /// - Parameter data: The XML content as UTF-8 encoded data.
    /// - Throws: ``J2KError/fileFormatError(_:)`` if the data is not valid UTF-8.
    public init(data: Data) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw J2KError.fileFormatError("XML box data is not valid UTF-8")
        }
        self.xmlString = string
    }

    public func write() throws -> Data {
        guard let data = xmlString.data(using: .utf8) else {
            throw J2KError.fileFormatError("Failed to encode XML as UTF-8")
        }
        return data
    }

    public mutating func read(from data: Data) throws {
        guard let string = String(data: data, encoding: .utf8) else {
            throw J2KError.fileFormatError("XML box data is not valid UTF-8")
        }
        self.xmlString = string
    }
}

// MARK: - Fragment Table Box (JPX)

/// Fragment table box.
///
/// The fragment table box ('ftbl') is a superbox that contains a fragment list box.
/// It enables fragmented codestreams where the image data is distributed across
/// multiple non-contiguous fragments in the file. This is useful for:
/// - Progressive image streaming
/// - Efficient partial updates
/// - Complex multi-layer compositions
///
/// ## Box Structure
///
/// - Type: 'ftbl' (0x6674626C)
/// - Length: Variable
/// - Content: Contains one 'flst' box
///
/// Example:
/// ```swift
/// let fragments = [
///     J2KFragment(offset: 1000, length: 5000),
///     J2KFragment(offset: 8000, length: 3000)
/// ]
/// let fragmentList = J2KFragmentListBox(fragments: fragments)
/// let fragmentTable = J2KFragmentTableBox(fragmentList: fragmentList)
/// ```
public struct J2KFragmentTableBox: J2KBox {
    /// The fragment list contained in this table.
    public var fragmentList: J2KFragmentListBox

    public var boxType: J2KBoxType {
        .ftbl
    }

    /// Creates a new fragment table box.
    ///
    /// - Parameter fragmentList: The fragment list for this table.
    public init(fragmentList: J2KFragmentListBox) {
        self.fragmentList = fragmentList
    }

    public func write() throws -> Data {
        var writer = J2KBoxWriter()
        try writer.writeBox(fragmentList)
        return writer.data
    }

    public mutating func read(from data: Data) throws {
        var reader = J2KBoxReader(data: data)

        // Read the fragment list box
        guard let boxInfo = try reader.readNextBox() else {
            throw J2KError.fileFormatError("Fragment table box is empty")
        }

        guard boxInfo.type == .flst else {
            throw J2KError.fileFormatError(
                "Expected fragment list box ('flst'), found '\(boxInfo.type.stringValue)'"
            )
        }

        let content = reader.extractContent(from: boxInfo)
        var flst = J2KFragmentListBox(fragments: [])
        try flst.read(from: content)
        self.fragmentList = flst
    }
}

// MARK: - Fragment List Box (JPX)

/// A single fragment in a codestream.
///
/// Represents a contiguous segment of codestream data at a specific location in the file.
public struct J2KFragment: Sendable, Equatable {
    /// The byte offset of this fragment from the start of the file.
    public var offset: UInt64

    /// The length of this fragment in bytes.
    public var length: UInt32

    /// Creates a new fragment.
    ///
    /// - Parameters:
    ///   - offset: The byte offset from the start of the file.
    ///   - length: The length in bytes.
    public init(offset: UInt64, length: UInt32) {
        self.offset = offset
        self.length = length
    }
}

/// Fragment list box.
///
/// The fragment list box ('flst') contains an ordered list of fragments that
/// together make up a complete codestream. The fragments are concatenated in
/// the order they appear in this list to reconstruct the full codestream.
///
/// ## Box Structure
///
/// - Type: 'flst' (0x666C7374)
/// - Length: Variable
/// - Content:
///   - Fragment count (2 bytes): Number of fragments (NF)
///   - Fragment data size (2 bytes): Size of fragment data field (DR)
///   - For each fragment:
///     - Offset (DR bytes): Byte offset from file start
///     - Length (4 bytes): Fragment length
///
/// Example:
/// ```swift
/// let fragments = [
///     J2KFragment(offset: 1000, length: 5000),
///     J2KFragment(offset: 8000, length: 3000),
///     J2KFragment(offset: 12000, length: 2000)
/// ]
/// let box = J2KFragmentListBox(fragments: fragments)
/// ```
public struct J2KFragmentListBox: J2KBox {
    /// The list of fragments making up the codestream.
    public var fragments: [J2KFragment]

    public var boxType: J2KBoxType {
        .flst
    }

    /// Creates a new fragment list box.
    ///
    /// - Parameter fragments: The list of fragments.
    public init(fragments: [J2KFragment]) {
        self.fragments = fragments
    }

    public func write() throws -> Data {
        guard fragments.count <= UInt16.max else {
            throw J2KError.fileFormatError("Too many fragments: \(fragments.count), maximum is \(UInt16.max)")
        }

        // Determine the minimum DR (fragment data size) needed
        // DR can be 4 or 8 bytes depending on the maximum offset
        let maxOffset = fragments.map { $0.offset }.max() ?? 0
        let dr: UInt16 = maxOffset > UInt32.max ? 8 : 4

        var output = Data()
        output.reserveCapacity(4 + fragments.count * (Int(dr) + 4))

        // Fragment count (2 bytes)
        let nf = UInt16(fragments.count)
        output.append(UInt8((nf >> 8) & 0xFF))
        output.append(UInt8(nf & 0xFF))

        // Fragment data size (2 bytes)
        output.append(UInt8((dr >> 8) & 0xFF))
        output.append(UInt8(dr & 0xFF))

        // Write each fragment
        for fragment in fragments {
            if dr == 8 {
                // Write 8-byte offset
                output.append(UInt8((fragment.offset >> 56) & 0xFF))
                output.append(UInt8((fragment.offset >> 48) & 0xFF))
                output.append(UInt8((fragment.offset >> 40) & 0xFF))
                output.append(UInt8((fragment.offset >> 32) & 0xFF))
                output.append(UInt8((fragment.offset >> 24) & 0xFF))
                output.append(UInt8((fragment.offset >> 16) & 0xFF))
                output.append(UInt8((fragment.offset >> 8) & 0xFF))
                output.append(UInt8(fragment.offset & 0xFF))
            } else {
                // Write 4-byte offset
                let offset32 = UInt32(fragment.offset)
                output.append(UInt8((offset32 >> 24) & 0xFF))
                output.append(UInt8((offset32 >> 16) & 0xFF))
                output.append(UInt8((offset32 >> 8) & 0xFF))
                output.append(UInt8(offset32 & 0xFF))
            }

            // Write length (4 bytes)
            output.append(UInt8((fragment.length >> 24) & 0xFF))
            output.append(UInt8((fragment.length >> 16) & 0xFF))
            output.append(UInt8((fragment.length >> 8) & 0xFF))
            output.append(UInt8(fragment.length & 0xFF))
        }

        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 4 else {
            throw J2KError.fileFormatError("Invalid fragment list box length: \(data.count), expected at least 4")
        }

        // Fragment count (2 bytes)
        let nf = UInt16(data[0]) << 8 | UInt16(data[1])

        // Fragment data size (2 bytes)
        let dr = UInt16(data[2]) << 8 | UInt16(data[3])

        guard dr == 4 || dr == 8 else {
            throw J2KError.fileFormatError("Invalid fragment data size: \(dr), expected 4 or 8")
        }

        // Calculate expected size
        let expectedSize = 4 + Int(nf) * (Int(dr) + 4)
        guard data.count >= expectedSize else {
            throw J2KError.fileFormatError(
                "Invalid fragment list box length: \(data.count), expected at least \(expectedSize)"
            )
        }

        // Read fragments
        var offset = 4
        var result: [J2KFragment] = []
        result.reserveCapacity(Int(nf))

        for _ in 0..<nf {
            // Read offset (dr bytes)
            let fragmentOffset: UInt64
            if dr == 8 {
                fragmentOffset = UInt64(data[offset]) << 56 |
                               UInt64(data[offset + 1]) << 48 |
                               UInt64(data[offset + 2]) << 40 |
                               UInt64(data[offset + 3]) << 32 |
                               UInt64(data[offset + 4]) << 24 |
                               UInt64(data[offset + 5]) << 16 |
                               UInt64(data[offset + 6]) << 8 |
                               UInt64(data[offset + 7])
                offset += 8
            } else {
                let offset32 = UInt32(data[offset]) << 24 |
                             UInt32(data[offset + 1]) << 16 |
                             UInt32(data[offset + 2]) << 8 |
                             UInt32(data[offset + 3])
                fragmentOffset = UInt64(offset32)
                offset += 4
            }

            // Read length (4 bytes)
            let fragmentLength = UInt32(data[offset]) << 24 |
                               UInt32(data[offset + 1]) << 16 |
                               UInt32(data[offset + 2]) << 8 |
                               UInt32(data[offset + 3])
            offset += 4

            result.append(J2KFragment(offset: fragmentOffset, length: fragmentLength))
        }

        self.fragments = result
    }
}

// MARK: - Composition Box (JPX)

/// Composition instruction.
///
/// Defines how to compose a single layer in the final image, including its
/// position, size, and compositing options.
public struct J2KCompositionInstruction: Sendable, Equatable {
    /// The width of the composition layer in pixels.
    public var width: UInt32

    /// The height of the composition layer in pixels.
    public var height: UInt32

    /// The horizontal offset of the layer from the origin.
    public var horizontalOffset: UInt32

    /// The vertical offset of the layer from the origin.
    public var verticalOffset: UInt32

    /// The index of the codestream to use for this layer (0-based).
    public var codestreamIndex: UInt16

    /// Compositing mode for blending layers.
    public enum CompositingMode: UInt8, Sendable {
        /// Replace mode - layer replaces background
        case replace = 0

        /// Alpha blending mode
        case alphaBlend = 1

        /// Pre-multiplied alpha blending
        case preMulAlphaBlend = 2
    }

    /// The compositing mode for this layer.
    public var compositingMode: CompositingMode

    /// Creates a new composition instruction.
    ///
    /// - Parameters:
    ///   - width: Layer width in pixels.
    ///   - height: Layer height in pixels.
    ///   - horizontalOffset: Horizontal position offset.
    ///   - verticalOffset: Vertical position offset.
    ///   - codestreamIndex: Index of the codestream to use.
    ///   - compositingMode: How to blend this layer (default: replace).
    public init(
        width: UInt32,
        height: UInt32,
        horizontalOffset: UInt32 = 0,
        verticalOffset: UInt32 = 0,
        codestreamIndex: UInt16,
        compositingMode: CompositingMode = .replace
    ) {
        self.width = width
        self.height = height
        self.horizontalOffset = horizontalOffset
        self.verticalOffset = verticalOffset
        self.codestreamIndex = codestreamIndex
        self.compositingMode = compositingMode
    }
}

/// Composition box.
///
/// The composition box ('comp') defines how multiple codestreams are composed
/// into a final rendered image. It can specify layering, positioning, cropping,
/// and blending operations. For animation, multiple composition instructions
/// can define a sequence of frames.
///
/// ## Box Structure
///
/// - Type: 'comp' (0x636F6D70)
/// - Length: Variable
/// - Content:
///   - Width (4 bytes): Composition canvas width
///   - Height (4 bytes): Composition canvas height
///   - Loop count (2 bytes): For animation (0 = infinite, 1+ = repeat count)
///   - Instruction count (2 bytes): Number of composition instructions
///   - Instructions: Array of composition instruction structures
///
/// Each instruction (19 bytes minimum):
/// - Layer width (4 bytes)
/// - Layer height (4 bytes)
/// - Horizontal offset (4 bytes)
/// - Vertical offset (4 bytes)
/// - Codestream index (2 bytes)
/// - Compositing mode (1 byte)
///
/// Example:
/// ```swift
/// // Single layer composition
/// let instruction = J2KCompositionInstruction(
///     width: 1024,
///     height: 768,
///     codestreamIndex: 0
/// )
/// let box = J2KCompositionBox(
///     width: 1024,
///     height: 768,
///     instructions: [instruction]
/// )
///
/// // Multi-layer composition with animation
/// let frame1 = J2KCompositionInstruction(width: 800, height: 600, codestreamIndex: 0)
/// let frame2 = J2KCompositionInstruction(width: 800, height: 600, codestreamIndex: 1)
/// let animation = J2KCompositionBox(
///     width: 800,
///     height: 600,
///     instructions: [frame1, frame2],
///     loopCount: 0  // Infinite loop
/// )
/// ```
public struct J2KCompositionBox: J2KBox {
    /// The width of the composition canvas in pixels.
    public var width: UInt32

    /// The height of the composition canvas in pixels.
    public var height: UInt32

    /// The number of times to loop through the composition sequence.
    /// - 0: Loop infinitely (for animations)
    /// - 1: Play once (single image or single animation playthrough)
    /// - N: Play N times
    public var loopCount: UInt16

    /// The list of composition instructions.
    /// For animations, each instruction represents a frame.
    public var instructions: [J2KCompositionInstruction]

    public var boxType: J2KBoxType {
        .comp
    }

    /// Creates a new composition box.
    ///
    /// - Parameters:
    ///   - width: Composition canvas width.
    ///   - height: Composition canvas height.
    ///   - instructions: List of composition instructions.
    ///   - loopCount: Loop count for animations (default: 1).
    public init(
        width: UInt32,
        height: UInt32,
        instructions: [J2KCompositionInstruction],
        loopCount: UInt16 = 1
    ) {
        self.width = width
        self.height = height
        self.loopCount = loopCount
        self.instructions = instructions
    }

    public func write() throws -> Data {
        guard instructions.count <= UInt16.max else {
            throw J2KError.fileFormatError(
                "Too many composition instructions: \(instructions.count), maximum is \(UInt16.max)"
            )
        }

        var output = Data()
        output.reserveCapacity(8 + instructions.count * 19)

        // Width (4 bytes)
        output.append(UInt8((width >> 24) & 0xFF))
        output.append(UInt8((width >> 16) & 0xFF))
        output.append(UInt8((width >> 8) & 0xFF))
        output.append(UInt8(width & 0xFF))

        // Height (4 bytes)
        output.append(UInt8((height >> 24) & 0xFF))
        output.append(UInt8((height >> 16) & 0xFF))
        output.append(UInt8((height >> 8) & 0xFF))
        output.append(UInt8(height & 0xFF))

        // Loop count (2 bytes)
        output.append(UInt8((loopCount >> 8) & 0xFF))
        output.append(UInt8(loopCount & 0xFF))

        // Instruction count (2 bytes)
        let count = UInt16(instructions.count)
        output.append(UInt8((count >> 8) & 0xFF))
        output.append(UInt8(count & 0xFF))

        // Write each instruction
        for instruction in instructions {
            // Layer width (4 bytes)
            output.append(UInt8((instruction.width >> 24) & 0xFF))
            output.append(UInt8((instruction.width >> 16) & 0xFF))
            output.append(UInt8((instruction.width >> 8) & 0xFF))
            output.append(UInt8(instruction.width & 0xFF))

            // Layer height (4 bytes)
            output.append(UInt8((instruction.height >> 24) & 0xFF))
            output.append(UInt8((instruction.height >> 16) & 0xFF))
            output.append(UInt8((instruction.height >> 8) & 0xFF))
            output.append(UInt8(instruction.height & 0xFF))

            // Horizontal offset (4 bytes)
            output.append(UInt8((instruction.horizontalOffset >> 24) & 0xFF))
            output.append(UInt8((instruction.horizontalOffset >> 16) & 0xFF))
            output.append(UInt8((instruction.horizontalOffset >> 8) & 0xFF))
            output.append(UInt8(instruction.horizontalOffset & 0xFF))

            // Vertical offset (4 bytes)
            output.append(UInt8((instruction.verticalOffset >> 24) & 0xFF))
            output.append(UInt8((instruction.verticalOffset >> 16) & 0xFF))
            output.append(UInt8((instruction.verticalOffset >> 8) & 0xFF))
            output.append(UInt8(instruction.verticalOffset & 0xFF))

            // Codestream index (2 bytes)
            output.append(UInt8((instruction.codestreamIndex >> 8) & 0xFF))
            output.append(UInt8(instruction.codestreamIndex & 0xFF))

            // Compositing mode (1 byte)
            output.append(instruction.compositingMode.rawValue)
        }

        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 12 else {
            throw J2KError.fileFormatError(
                "Invalid composition box length: \(data.count), expected at least 12"
            )
        }

        // Width (4 bytes)
        self.width = UInt32(data[0]) << 24 |
                    UInt32(data[1]) << 16 |
                    UInt32(data[2]) << 8 |
                    UInt32(data[3])

        // Height (4 bytes)
        self.height = UInt32(data[4]) << 24 |
                     UInt32(data[5]) << 16 |
                     UInt32(data[6]) << 8 |
                     UInt32(data[7])

        // Loop count (2 bytes)
        self.loopCount = UInt16(data[8]) << 8 | UInt16(data[9])

        // Instruction count (2 bytes)
        let count = UInt16(data[10]) << 8 | UInt16(data[11])

        // Calculate expected size
        let expectedSize = 12 + Int(count) * 19
        guard data.count >= expectedSize else {
            throw J2KError.fileFormatError(
                "Invalid composition box length: \(data.count), expected at least \(expectedSize)"
            )
        }

        // Read instructions
        var offset = 12
        var result: [J2KCompositionInstruction] = []
        result.reserveCapacity(Int(count))

        for _ in 0..<count {
            // Layer width (4 bytes)
            let layerWidth = UInt32(data[offset]) << 24 |
                           UInt32(data[offset + 1]) << 16 |
                           UInt32(data[offset + 2]) << 8 |
                           UInt32(data[offset + 3])
            offset += 4

            // Layer height (4 bytes)
            let layerHeight = UInt32(data[offset]) << 24 |
                            UInt32(data[offset + 1]) << 16 |
                            UInt32(data[offset + 2]) << 8 |
                            UInt32(data[offset + 3])
            offset += 4

            // Horizontal offset (4 bytes)
            let hOffset = UInt32(data[offset]) << 24 |
                        UInt32(data[offset + 1]) << 16 |
                        UInt32(data[offset + 2]) << 8 |
                        UInt32(data[offset + 3])
            offset += 4

            // Vertical offset (4 bytes)
            let vOffset = UInt32(data[offset]) << 24 |
                        UInt32(data[offset + 1]) << 16 |
                        UInt32(data[offset + 2]) << 8 |
                        UInt32(data[offset + 3])
            offset += 4

            // Codestream index (2 bytes)
            let csIndex = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            offset += 2

            // Compositing mode (1 byte)
            guard let mode = J2KCompositionInstruction.CompositingMode(rawValue: data[offset]) else {
                throw J2KError.fileFormatError("Invalid compositing mode: \(data[offset])")
            }
            offset += 1

            let instruction = J2KCompositionInstruction(
                width: layerWidth,
                height: layerHeight,
                horizontalOffset: hOffset,
                verticalOffset: vOffset,
                codestreamIndex: csIndex,
                compositingMode: mode
            )
            result.append(instruction)
        }

        self.instructions = result
    }
}

// MARK: - Page Collection Box (JPM)

/// Page collection box.
///
/// The page collection box ('pcol') is a superbox that contains multiple page boxes,
/// enabling multi-page document support in JPM format. This is essential for
/// document imaging applications like digital faxes, scanned documents, and PDFs.
///
/// ## Box Structure
///
/// - Type: 'pcol' (0x70636F6C)
/// - Length: Variable
/// - Content: Contains one or more 'page' boxes
///
/// Example:
/// ```swift
/// let page1 = J2KPageBox(pageNumber: 0, width: 2480, height: 3508)
/// let page2 = J2KPageBox(pageNumber: 1, width: 2480, height: 3508)
/// let collection = J2KPageCollectionBox(pages: [page1, page2])
/// ```
public struct J2KPageCollectionBox: J2KBox {
    /// The pages in this collection.
    public var pages: [J2KPageBox]

    public var boxType: J2KBoxType {
        .pcol
    }

    /// Creates a new page collection box.
    ///
    /// - Parameter pages: The list of pages.
    public init(pages: [J2KPageBox]) {
        self.pages = pages
    }

    public func write() throws -> Data {
        var writer = J2KBoxWriter()
        for page in pages {
            try writer.writeBox(page)
        }
        return writer.data
    }

    public mutating func read(from data: Data) throws {
        var reader = J2KBoxReader(data: data)
        var result: [J2KPageBox] = []

        // Read all page boxes
        while let boxInfo = try reader.readNextBox() {
            guard boxInfo.type == .page else {
                throw J2KError.fileFormatError(
                    "Expected page box ('page'), found '\(boxInfo.type.stringValue)'"
                )
            }

            let content = reader.extractContent(from: boxInfo)
            var page = J2KPageBox(pageNumber: 0, width: 0, height: 0)
            try page.read(from: content)
            result.append(page)
        }

        self.pages = result
    }
}

// MARK: - Page Box (JPM)

/// Page box.
///
/// The page box ('page') represents a single page in a multi-page JPM document.
/// Each page has its own dimensions and can reference one or more codestreams
/// for different layers (e.g., background, foreground, text masks in Mixed
/// Raster Content documents).
///
/// ## Box Structure
///
/// - Type: 'page' (0x70616765)
/// - Length: Variable
/// - Content:
///   - Page number (2 bytes): Zero-based page index
///   - Width (4 bytes): Page width in pixels
///   - Height (4 bytes): Page height in pixels
///   - Optional: Layout boxes and codestream references
///
/// Example:
/// ```swift
/// // Simple page
/// let page = J2KPageBox(pageNumber: 0, width: 2480, height: 3508)
///
/// // A4 page at 300 DPI
/// let a4Page = J2KPageBox(pageNumber: 0, width: 2480, height: 3508)
/// ```
public struct J2KPageBox: J2KBox {
    /// The page number (0-based index).
    public var pageNumber: UInt16

    /// The width of the page in pixels.
    public var width: UInt32

    /// The height of the page in pixels.
    public var height: UInt32

    /// Optional layout information for objects on this page.
    public var layouts: [J2KLayoutBox]

    public var boxType: J2KBoxType {
        .page
    }

    /// Creates a new page box.
    ///
    /// - Parameters:
    ///   - pageNumber: The page number (0-based).
    ///   - width: Page width in pixels.
    ///   - height: Page height in pixels.
    ///   - layouts: Optional layout boxes (default: empty).
    public init(
        pageNumber: UInt16,
        width: UInt32,
        height: UInt32,
        layouts: [J2KLayoutBox] = []
    ) {
        self.pageNumber = pageNumber
        self.width = width
        self.height = height
        self.layouts = layouts
    }

    public func write() throws -> Data {
        var output = Data()
        output.reserveCapacity(10)

        // Page number (2 bytes)
        output.append(UInt8((pageNumber >> 8) & 0xFF))
        output.append(UInt8(pageNumber & 0xFF))

        // Width (4 bytes)
        output.append(UInt8((width >> 24) & 0xFF))
        output.append(UInt8((width >> 16) & 0xFF))
        output.append(UInt8((width >> 8) & 0xFF))
        output.append(UInt8(width & 0xFF))

        // Height (4 bytes)
        output.append(UInt8((height >> 24) & 0xFF))
        output.append(UInt8((height >> 16) & 0xFF))
        output.append(UInt8((height >> 8) & 0xFF))
        output.append(UInt8(height & 0xFF))

        // Write layout boxes if any
        if !layouts.isEmpty {
            var writer = J2KBoxWriter()
            for layout in layouts {
                try writer.writeBox(layout)
            }
            output.append(writer.data)
        }

        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 10 else {
            throw J2KError.fileFormatError(
                "Invalid page box length: \(data.count), expected at least 10"
            )
        }

        // Page number (2 bytes)
        self.pageNumber = UInt16(data[0]) << 8 | UInt16(data[1])

        // Width (4 bytes)
        self.width = UInt32(data[2]) << 24 |
                    UInt32(data[3]) << 16 |
                    UInt32(data[4]) << 8 |
                    UInt32(data[5])

        // Height (4 bytes)
        self.height = UInt32(data[6]) << 24 |
                     UInt32(data[7]) << 16 |
                     UInt32(data[8]) << 8 |
                     UInt32(data[9])

        // Read layout boxes if present
        if data.count > 10 {
            let layoutData = Data(data.suffix(from: 10))  // Create a new Data to avoid slice issues
            var reader = J2KBoxReader(data: layoutData)
            var result: [J2KLayoutBox] = []

            while let boxInfo = try reader.readNextBox() {
                if boxInfo.type == .lobj {
                    let content = reader.extractContent(from: boxInfo)
                    var layout = J2KLayoutBox(objectID: 0, x: 0, y: 0, width: 0, height: 0)
                    try layout.read(from: content)
                    result.append(layout)
                }
            }

            self.layouts = result
        } else {
            self.layouts = []
        }
    }
}

// MARK: - Layout Box (JPM)

/// Layout box.
///
/// The layout box ('lobj') defines the position and size of an object within
/// a page. In JPM, objects can be images, text masks, or other graphical elements
/// that need to be positioned on the page.
///
/// ## Box Structure
///
/// - Type: 'lobj' (0x6C6F626A)
/// - Length: Variable (minimum 18 bytes)
/// - Content:
///   - Object ID (2 bytes): Unique identifier for this object
///   - X position (4 bytes): Horizontal position on page
///   - Y position (4 bytes): Vertical position on page
///   - Width (4 bytes): Object width
///   - Height (4 bytes): Object height
///
/// Example:
/// ```swift
/// // Position an image at (100, 200) with size 800x600
/// let layout = J2KLayoutBox(
///     objectID: 0,
///     x: 100,
///     y: 200,
///     width: 800,
///     height: 600
/// )
/// ```
public struct J2KLayoutBox: J2KBox {
    /// The unique identifier for this object.
    public var objectID: UInt16

    /// The horizontal position on the page in pixels.
    public var x: UInt32

    /// The vertical position on the page in pixels.
    public var y: UInt32

    /// The width of the object in pixels.
    public var width: UInt32

    /// The height of the object in pixels.
    public var height: UInt32

    public var boxType: J2KBoxType {
        .lobj
    }

    /// Creates a new layout box.
    ///
    /// - Parameters:
    ///   - objectID: Unique object identifier.
    ///   - x: Horizontal position.
    ///   - y: Vertical position.
    ///   - width: Object width.
    ///   - height: Object height.
    public init(
        objectID: UInt16,
        x: UInt32,
        y: UInt32,
        width: UInt32,
        height: UInt32
    ) {
        self.objectID = objectID
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func write() throws -> Data {
        var output = Data(capacity: 18)

        // Object ID (2 bytes)
        output.append(UInt8((objectID >> 8) & 0xFF))
        output.append(UInt8(objectID & 0xFF))

        // X position (4 bytes)
        output.append(UInt8((x >> 24) & 0xFF))
        output.append(UInt8((x >> 16) & 0xFF))
        output.append(UInt8((x >> 8) & 0xFF))
        output.append(UInt8(x & 0xFF))

        // Y position (4 bytes)
        output.append(UInt8((y >> 24) & 0xFF))
        output.append(UInt8((y >> 16) & 0xFF))
        output.append(UInt8((y >> 8) & 0xFF))
        output.append(UInt8(y & 0xFF))

        // Width (4 bytes)
        output.append(UInt8((width >> 24) & 0xFF))
        output.append(UInt8((width >> 16) & 0xFF))
        output.append(UInt8((width >> 8) & 0xFF))
        output.append(UInt8(width & 0xFF))

        // Height (4 bytes)
        output.append(UInt8((height >> 24) & 0xFF))
        output.append(UInt8((height >> 16) & 0xFF))
        output.append(UInt8((height >> 8) & 0xFF))
        output.append(UInt8(height & 0xFF))

        return output
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 18 else {
            throw J2KError.fileFormatError(
                "Invalid layout box length: \(data.count), expected at least 18"
            )
        }

        // Object ID (2 bytes)
        self.objectID = UInt16(data[0]) << 8 | UInt16(data[1])

        // X position (4 bytes)
        self.x = UInt32(data[2]) << 24 |
                UInt32(data[3]) << 16 |
                UInt32(data[4]) << 8 |
                UInt32(data[5])

        // Y position (4 bytes)
        self.y = UInt32(data[6]) << 24 |
                UInt32(data[7]) << 16 |
                UInt32(data[8]) << 8 |
                UInt32(data[9])

        // Width (4 bytes)
        self.width = UInt32(data[10]) << 24 |
                    UInt32(data[11]) << 16 |
                    UInt32(data[12]) << 8 |
                    UInt32(data[13])

        // Height (4 bytes)
        self.height = UInt32(data[14]) << 24 |
                     UInt32(data[15]) << 16 |
                     UInt32(data[16]) << 8 |
                     UInt32(data[17])
    }
}

// MARK: - JPX DC Offset Extension Box (Part 2)

/// JPX extension box for signaling DC offset capabilities.
///
/// This box is placed in the JP2 header (jp2h) superbox to indicate
/// that the codestream uses Part 2 DC offset features. It stores
/// the DC offset configuration and per-component offset type.
///
/// ## Box Structure
///
/// - Type: 'dcof' (DC Offset Feature)
/// - Content:
///   - Offset type (1 byte): 0 = integer, 1 = floating-point
///   - Component count (2 bytes): Number of components with DC offset
///   - Flags (1 byte): Configuration flags
///
/// ## Usage
///
/// ```swift
/// let box = J2KDCOffsetExtensionBox(
///     offsetType: .integer,
///     componentCount: 3,
///     enabled: true
/// )
/// let data = try box.write()
/// ```
public struct J2KDCOffsetExtensionBox: J2KBox {
    public var boxType: J2KBoxType {
        .dcof
    }

    /// The type of DC offset encoding used.
    public var offsetType: J2KDCOOffsetType

    /// Number of components that use DC offset.
    public var componentCount: UInt16

    /// Whether DC offset is enabled.
    public var enabled: Bool

    /// Creates a new DC offset extension box.
    ///
    /// - Parameters:
    ///   - offsetType: The type of offset encoding (default: .integer).
    ///   - componentCount: Number of components with DC offset (default: 0).
    ///   - enabled: Whether DC offset is enabled (default: true).
    public init(
        offsetType: J2KDCOOffsetType = .integer,
        componentCount: UInt16 = 0,
        enabled: Bool = true
    ) {
        self.offsetType = offsetType
        self.componentCount = componentCount
        self.enabled = enabled
    }

    public func write() throws -> Data {
        var data = Data(capacity: 4)

        // Offset type (1 byte)
        data.append(offsetType.rawValue)

        // Component count (2 bytes)
        data.append(UInt8((componentCount >> 8) & 0xFF))
        data.append(UInt8(componentCount & 0xFF))

        // Flags (1 byte): bit 0 = enabled
        data.append(enabled ? 0x01 : 0x00)

        return data
    }

    public mutating func read(from data: Data) throws {
        guard data.count >= 4 else {
            throw J2KError.fileFormatError(
                "DC offset extension box too short: \(data.count), expected at least 4"
            )
        }

        guard let ot = J2KDCOOffsetType(rawValue: data[0]) else {
            throw J2KError.fileFormatError(
                "Invalid DC offset type: \(data[0])"
            )
        }
        self.offsetType = ot

        self.componentCount = UInt16(data[1]) << 8 | UInt16(data[2])

        self.enabled = (data[3] & 0x01) != 0
    }
}
