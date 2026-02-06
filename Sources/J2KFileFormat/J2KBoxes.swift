/// # J2KBoxes
///
/// Implementations of standard JP2 box types.
///
/// This module provides concrete implementations of the essential JP2 boxes
/// defined in ISO/IEC 15444-1.

import Foundation
import J2KCore

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
        
        /// Custom brand
        case custom(String)
        
        /// Returns the four-character brand identifier.
        public var identifier: String {
            switch self {
            case .jp2: return "jp2 "
            case .jpx: return "jpx "
            case .jpm: return "jpm "
            case .custom(let str): return str
            }
        }
        
        /// Creates a brand from a four-character identifier.
        public init(identifier: String) {
            switch identifier {
            case "jp2 ": self = .jp2
            case "jpx ": self = .jpx
            case "jpm ": self = .jpm
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
