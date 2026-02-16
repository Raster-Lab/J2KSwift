/// # J2KCore
///
/// Core module for JPEG 2000 encoding and decoding functionality.
///
/// This module provides the foundational types, protocols, and utilities for JPEG 2000 image
/// processing. It defines the basic building blocks used by other modules in the J2KSwift framework.
///
/// ## Topics
///
/// ### Core Types
/// - ``J2KImage``
/// - ``J2KComponent``
/// - ``J2KTile``
/// - ``J2KTileComponent``
/// - ``J2KPrecinct``
/// - ``J2KCodeBlock``
///
/// ### Memory Management
/// - ``J2KBuffer``
/// - ``J2KImageBuffer``
/// - ``J2KMemoryPool``
/// - ``J2KMemoryTracker``
///
/// ### Enumerations
/// - ``J2KSubband``
/// - ``J2KColorSpace``
/// - ``J2KError``
///
/// ### Configuration
/// - ``J2KConfiguration``

import Foundation

/// Represents a JPEG 2000 image with metadata and pixel data.
///
/// A J2KImage contains all the necessary information to describe a JPEG 2000 image,
/// including dimensions, components, tiling information, and color space metadata.
public struct J2KImage: Sendable {
    /// The width of the image in pixels.
    public let width: Int
    
    /// The height of the image in pixels.
    public let height: Int
    
    /// The image components (color channels).
    public let components: [J2KComponent]
    
    /// The horizontal offset of the image reference grid origin.
    public let offsetX: Int
    
    /// The vertical offset of the image reference grid origin.
    public let offsetY: Int
    
    /// The width of a tile in pixels (0 means no tiling).
    public let tileWidth: Int
    
    /// The height of a tile in pixels (0 means no tiling).
    public let tileHeight: Int
    
    /// The horizontal offset of the first tile.
    public let tileOffsetX: Int
    
    /// The vertical offset of the first tile.
    public let tileOffsetY: Int
    
    /// The color space of the image.
    public let colorSpace: J2KColorSpace
    
    /// Creates a new J2KImage with the specified parameters.
    ///
    /// - Parameters:
    ///   - width: The width of the image in pixels.
    ///   - height: The height of the image in pixels.
    ///   - components: The image components (color channels).
    ///   - offsetX: The horizontal offset of the image reference grid origin (default: 0).
    ///   - offsetY: The vertical offset of the image reference grid origin (default: 0).
    ///   - tileWidth: The width of a tile in pixels, 0 for no tiling (default: 0).
    ///   - tileHeight: The height of a tile in pixels, 0 for no tiling (default: 0).
    ///   - tileOffsetX: The horizontal offset of the first tile (default: 0).
    ///   - tileOffsetY: The vertical offset of the first tile (default: 0).
    ///   - colorSpace: The color space of the image (default: .sRGB).
    public init(
        width: Int,
        height: Int,
        components: [J2KComponent],
        offsetX: Int = 0,
        offsetY: Int = 0,
        tileWidth: Int = 0,
        tileHeight: Int = 0,
        tileOffsetX: Int = 0,
        tileOffsetY: Int = 0,
        colorSpace: J2KColorSpace = .sRGB
    ) {
        self.width = width
        self.height = height
        self.components = components
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.tileOffsetX = tileOffsetX
        self.tileOffsetY = tileOffsetY
        self.colorSpace = colorSpace
    }
    
    /// Convenience initializer for simple images without tiling.
    ///
    /// - Parameters:
    ///   - width: The width of the image in pixels.
    ///   - height: The height of the image in pixels.
    ///   - components: The number of color components (e.g., 3 for RGB, 4 for RGBA).
    ///   - bitDepth: The bit depth per component (default: 8).
    ///   - signed: Whether the components are signed (default: false).
    public init(width: Int, height: Int, components: Int, bitDepth: Int = 8, signed: Bool = false) {
        // Validate and clamp inputs
        let validWidth = max(1, width) // At least 1 pixel wide
        let validHeight = max(1, height) // At least 1 pixel high
        let validComponents = max(1, components) // At least 1 component
        let validBitDepth = max(1, min(38, bitDepth)) // Between 1 and 38 bits
        
        let imageComponents = (0..<validComponents).map { index in
            J2KComponent(
                index: index,
                bitDepth: validBitDepth,
                signed: signed,
                width: validWidth,
                height: validHeight
            )
        }
        
        self.init(
            width: validWidth,
            height: validHeight,
            components: imageComponents
        )
    }
    
    /// Returns the number of tiles in the horizontal direction.
    public var tilesX: Int {
        guard tileWidth > 0 else { return 1 }
        return (width + tileWidth - 1) / tileWidth
    }
    
    /// Returns the number of tiles in the vertical direction.
    public var tilesY: Int {
        guard tileHeight > 0 else { return 1 }
        return (height + tileHeight - 1) / tileHeight
    }
    
    /// Returns the total number of tiles in the image.
    public var tileCount: Int {
        return tilesX * tilesY
    }
    
    // MARK: - Convenience Properties
    
    /// Returns true if the image uses tiling.
    public var isTiled: Bool {
        return tileWidth > 0 && tileHeight > 0
    }
    
    /// Returns the total number of pixels in the image.
    public var pixelCount: Int {
        return width * height
    }
    
    /// Returns the number of components in the image.
    public var componentCount: Int {
        return components.count
    }
    
    /// Returns true if the image is grayscale (single component).
    public var isGrayscale: Bool {
        return components.count == 1
    }
    
    /// Returns true if the image has an alpha channel.
    ///
    /// An alpha channel is assumed to be present if there are 2 components (grayscale + alpha)
    /// or 4 components (RGB + alpha).
    public var hasAlpha: Bool {
        return components.count == 2 || components.count == 4
    }
    
    /// Returns the aspect ratio of the image (width / height).
    public var aspectRatio: Double {
        guard height > 0 else { return 0 }
        return Double(width) / Double(height)
    }
    
    // MARK: - Validation Methods
    
    /// Validates that the image has valid dimensions and components.
    ///
    /// - Throws: ``J2KError/invalidDimensions(_:)`` if dimensions are invalid.
    /// - Throws: ``J2KError/invalidComponentConfiguration(_:)`` if components are invalid.
    public func validate() throws {
        guard width > 0 && height > 0 else {
            throw J2KError.invalidDimensions("Image dimensions must be positive: \(width)x\(height)")
        }
        
        guard !components.isEmpty else {
            throw J2KError.invalidComponentConfiguration("Image must have at least one component")
        }
        
        for component in components {
            guard component.bitDepth >= 1 && component.bitDepth <= 38 else {
                throw J2KError.invalidBitDepth("Component \(component.index) has invalid bit depth: \(component.bitDepth)")
            }
        }
        
        if isTiled {
            guard tileWidth > 0 && tileHeight > 0 else {
                throw J2KError.invalidTileConfiguration("Tile dimensions must be positive if tiling is enabled")
            }
        }
    }
}

/// Represents a single component (color channel) of a JPEG 2000 image.
///
/// Each component has its own bit depth, sign, and dimensions. Components can be
/// subsampled relative to the full image resolution.
public struct J2KComponent: Sendable {
    /// The index of this component (0-based).
    public let index: Int
    
    /// The bit depth of this component (1-38 bits).
    public let bitDepth: Int
    
    /// Whether this component uses signed values.
    public let signed: Bool
    
    /// The width of this component in pixels.
    public let width: Int
    
    /// The height of this component in pixels.
    public let height: Int
    
    /// The horizontal subsampling factor relative to the reference grid.
    public let subsamplingX: Int
    
    /// The vertical subsampling factor relative to the reference grid.
    public let subsamplingY: Int
    
    /// The pixel data for this component.
    public var data: Data
    
    /// Creates a new component with the specified parameters.
    ///
    /// - Parameters:
    ///   - index: The index of this component (0-based).
    ///   - bitDepth: The bit depth (1-38 bits).
    ///   - signed: Whether this component uses signed values (default: false).
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    ///   - subsamplingX: The horizontal subsampling factor (default: 1).
    ///   - subsamplingY: The vertical subsampling factor (default: 1).
    ///   - data: The pixel data (default: empty).
    public init(
        index: Int,
        bitDepth: Int,
        signed: Bool = false,
        width: Int,
        height: Int,
        subsamplingX: Int = 1,
        subsamplingY: Int = 1,
        data: Data = Data()
    ) {
        self.index = index
        self.bitDepth = bitDepth
        self.signed = signed
        self.width = width
        self.height = height
        self.subsamplingX = subsamplingX
        self.subsamplingY = subsamplingY
        self.data = data
    }
    
    // MARK: - Convenience Properties
    
    /// Returns the total number of pixels in the component.
    public var pixelCount: Int {
        return width * height
    }
    
    /// Returns true if the component is subsampled.
    public var isSubsampled: Bool {
        return subsamplingX > 1 || subsamplingY > 1
    }
    
    /// Returns the maximum value for this component's bit depth.
    public var maxValue: Int {
        return (1 << bitDepth) - 1
    }
    
    /// Returns the minimum value for this component (0 for unsigned, negative for signed).
    public var minValue: Int {
        return signed ? -(1 << (bitDepth - 1)) : 0
    }
}

/// Represents a tile in a JPEG 2000 image.
///
/// Tiles are rectangular regions that can be encoded and decoded independently.
/// They enable parallel processing and memory-efficient streaming.
public struct J2KTile: Sendable {
    /// The index of this tile.
    public let index: Int
    
    /// The x-coordinate of the tile in the tile grid.
    public let x: Int
    
    /// The y-coordinate of the tile in the tile grid.
    public let y: Int
    
    /// The width of this tile in pixels.
    public let width: Int
    
    /// The height of this tile in pixels.
    public let height: Int
    
    /// The x-offset of this tile in the reference grid.
    public let offsetX: Int
    
    /// The y-offset of this tile in the reference grid.
    public let offsetY: Int
    
    /// The tile-components (one per image component).
    public var components: [J2KTileComponent]
    
    /// Creates a new tile with the specified parameters.
    ///
    /// - Parameters:
    ///   - index: The tile index.
    ///   - x: The x-coordinate in the tile grid.
    ///   - y: The y-coordinate in the tile grid.
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    ///   - offsetX: The x-offset in the reference grid.
    ///   - offsetY: The y-offset in the reference grid.
    ///   - components: The tile-components.
    public init(
        index: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        offsetX: Int,
        offsetY: Int,
        components: [J2KTileComponent] = []
    ) {
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.components = components
    }
}

/// Represents a component within a tile.
public struct J2KTileComponent: Sendable {
    /// The component index.
    public let componentIndex: Int
    
    /// The width of this tile-component in pixels.
    public let width: Int
    
    /// The height of this tile-component in pixels.
    public let height: Int
    
    /// The precincts in this tile-component (organized by resolution level).
    public var precincts: [[J2KPrecinct]]
    
    /// Creates a new tile-component.
    ///
    /// - Parameters:
    ///   - componentIndex: The component index.
    ///   - width: The width in pixels.
    ///   - height: The height in pixels.
    ///   - precincts: The precincts organized by resolution level.
    public init(
        componentIndex: Int,
        width: Int,
        height: Int,
        precincts: [[J2KPrecinct]] = []
    ) {
        self.componentIndex = componentIndex
        self.width = width
        self.height = height
        self.precincts = precincts
    }
}

/// Represents a precinct in the wavelet decomposition.
///
/// A precinct is a spatial region within a resolution level that groups code-blocks
/// for efficient organization and streaming.
public struct J2KPrecinct: Sendable {
    /// The precinct index within its resolution level.
    public let index: Int
    
    /// The x-coordinate of the precinct.
    public let x: Int
    
    /// The y-coordinate of the precinct.
    public let y: Int
    
    /// The width of this precinct in the subband coordinate system.
    public let width: Int
    
    /// The height of this precinct in the subband coordinate system.
    public let height: Int
    
    /// The resolution level this precinct belongs to.
    public let resolutionLevel: Int
    
    /// The code-blocks in this precinct organized by subband (LL, HL, LH, HH).
    public var codeBlocks: [J2KSubband: [J2KCodeBlock]]
    
    /// Creates a new precinct.
    ///
    /// - Parameters:
    ///   - index: The precinct index.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - width: The width.
    ///   - height: The height.
    ///   - resolutionLevel: The resolution level.
    ///   - codeBlocks: The code-blocks organized by subband.
    public init(
        index: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        resolutionLevel: Int,
        codeBlocks: [J2KSubband: [J2KCodeBlock]] = [:]
    ) {
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.resolutionLevel = resolutionLevel
        self.codeBlocks = codeBlocks
    }
}

/// Represents a code-block, the fundamental unit for entropy coding.
///
/// Code-blocks are small rectangular regions (typically 32×32 or 64×64 samples)
/// that are independently coded using the EBCOT algorithm.
public struct J2KCodeBlock: Sendable {
    /// The code-block index within its precinct and subband.
    public let index: Int
    
    /// The x-coordinate of the code-block.
    public let x: Int
    
    /// The y-coordinate of the code-block.
    public let y: Int
    
    /// The width of this code-block in samples.
    public let width: Int
    
    /// The height of this code-block in samples.
    public let height: Int
    
    /// The subband this code-block belongs to.
    public let subband: J2KSubband
    
    /// The encoded data for this code-block.
    public var data: Data
    
    /// The number of coding passes applied to this code-block.
    public var passeCount: Int
    
    /// The number of missing most significant bit-planes.
    public var zeroBitPlanes: Int
    
    /// The byte lengths of each coding pass segment.
    ///
    /// When predictable termination is used, the encoder resets after each
    /// coding pass, producing separate data segments. This array stores
    /// the byte length of each segment so the decoder can reset at the
    /// correct boundaries.
    ///
    /// When empty, the data is treated as a single contiguous segment
    /// (default/non-predictable termination mode).
    public var passSegmentLengths: [Int]
    
    /// Creates a new code-block.
    ///
    /// - Parameters:
    ///   - index: The code-block index.
    ///   - x: The x-coordinate.
    ///   - y: The y-coordinate.
    ///   - width: The width.
    ///   - height: The height.
    ///   - subband: The subband.
    ///   - data: The encoded data.
    ///   - passeCount: The number of coding passes (default: 0). (Note: historical spelling preserved for API compatibility.)
    ///   - zeroBitPlanes: The number of missing MSB planes (default: 0).
    ///   - passSegmentLengths: Byte lengths per pass segment (default: empty).
    public init(
        index: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        subband: J2KSubband,
        data: Data = Data(),
        passeCount: Int = 0,
        zeroBitPlanes: Int = 0,
        passSegmentLengths: [Int] = []
    ) {
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.subband = subband
        self.data = data
        self.passeCount = passeCount
        self.zeroBitPlanes = zeroBitPlanes
        self.passSegmentLengths = passSegmentLengths
    }
}

/// Represents a subband in the wavelet decomposition.
public enum J2KSubband: String, Sendable, Hashable {
    /// Low-low subband (approximation).
    case ll = "LL"
    
    /// High-low subband (horizontal detail).
    case hl = "HL"
    
    /// Low-high subband (vertical detail).
    case lh = "LH"
    
    /// High-high subband (diagonal detail).
    case hh = "HH"
}

/// Represents the color space of a JPEG 2000 image.
public enum J2KColorSpace: Sendable, Equatable {
    /// sRGB color space (standard dynamic range).
    case sRGB
    
    /// Grayscale (single component).
    case grayscale
    
    /// YCbCr color space.
    case yCbCr
    
    /// HDR color space with extended dynamic range (e.g., Rec. 2020, Rec. 2100).
    ///
    /// HDR images typically use higher bit depths (10, 12, or 16 bits) and represent
    /// luminance values that exceed the standard 0-1 range of SDR content.
    ///
    /// Common HDR standards:
    /// - Rec. 2020: Wide color gamut for UHDTV
    /// - Rec. 2100 (HLG/PQ): HDR transfer functions
    /// - SMPTE ST 2084 (PQ): Perceptual quantization
    /// - ARIB STD-B67 (HLG): Hybrid log-gamma
    case hdr
    
    /// HDR color space with linear light encoding.
    ///
    /// Linear HDR represents light intensity directly without gamma correction,
    /// suitable for physically-based rendering and compositing operations.
    case hdrLinear
    
    /// ICC profile-based color space.
    case iccProfile(Data)
    
    /// Unknown or unspecified color space.
    case unknown
    
    /// Equatable conformance for J2KColorSpace.
    public static func == (lhs: J2KColorSpace, rhs: J2KColorSpace) -> Bool {
        switch (lhs, rhs) {
        case (.sRGB, .sRGB),
             (.grayscale, .grayscale),
             (.yCbCr, .yCbCr),
             (.hdr, .hdr),
             (.hdrLinear, .hdrLinear),
             (.unknown, .unknown):
            return true
        case let (.iccProfile(lhsData), .iccProfile(rhsData)):
            return lhsData == rhsData
        default:
            return false
        }
    }
}

/// Errors that can occur during JPEG 2000 operations.
public enum J2KError: Error, Sendable {
    /// An invalid parameter was provided.
    case invalidParameter(String)
    
    /// The operation is not yet implemented.
    case notImplemented(String)
    
    /// An internal error occurred.
    case internalError(String)
    
    /// Invalid image dimensions.
    case invalidDimensions(String)
    
    /// Invalid bit depth.
    case invalidBitDepth(String)
    
    /// Invalid tile configuration.
    case invalidTileConfiguration(String)
    
    /// Invalid component configuration.
    case invalidComponentConfiguration(String)
    
    /// Corrupted or invalid data.
    case invalidData(String)
    
    /// File format error.
    case fileFormatError(String)
    
    /// Unsupported feature.
    case unsupportedFeature(String)
    
    /// Decoding error.
    case decodingError(String)
    
    /// Encoding error.
    case encodingError(String)
    
    /// I/O error.
    case ioError(String)
}

// MARK: - J2KError Extensions

extension J2KError: LocalizedError {
    /// A localized description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidParameter(let message):
            return "Invalid parameter: \(message)"
        case .notImplemented(let message):
            return "Not implemented: \(message)"
        case .internalError(let message):
            return "Internal error: \(message)"
        case .invalidDimensions(let message):
            return "Invalid dimensions: \(message)"
        case .invalidBitDepth(let message):
            return "Invalid bit depth: \(message)"
        case .invalidTileConfiguration(let message):
            return "Invalid tile configuration: \(message)"
        case .invalidComponentConfiguration(let message):
            return "Invalid component configuration: \(message)"
        case .invalidData(let message):
            return "Invalid data: \(message)"
        case .fileFormatError(let message):
            return "File format error: \(message)"
        case .unsupportedFeature(let message):
            return "Unsupported feature: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .ioError(let message):
            return "I/O error: \(message)"
        }
    }
}

extension J2KError: CustomStringConvertible {
    /// A textual representation of the error.
    public var description: String {
        return errorDescription ?? "Unknown J2K error"
    }
}

/// Configuration options for JPEG 2000 operations.
public struct J2KConfiguration: Sendable {
    /// The quality factor for encoding (0.0 to 1.0).
    public let quality: Double
    
    /// Whether to use lossless compression.
    public let lossless: Bool
    
    /// Creates a new configuration with the specified options.
    ///
    /// - Parameters:
    ///   - quality: The quality factor (default: 0.9).
    ///   - lossless: Whether to use lossless compression (default: false).
    public init(quality: Double = 0.9, lossless: Bool = false) {
        self.quality = quality
        self.lossless = lossless
    }
    
    // MARK: - Convenience Factory Methods
    
    /// Creates a configuration for lossless compression.
    ///
    /// Use this preset when you need perfect reconstruction of the original image
    /// without any quality loss. Results in larger file sizes but maintains all
    /// original image data.
    ///
    /// - Returns: A configuration for lossless compression.
    public static var lossless: J2KConfiguration {
        return J2KConfiguration(quality: 1.0, lossless: true)
    }
    
    /// Creates a configuration for high-quality lossy compression.
    ///
    /// Use this preset when you want excellent visual quality with moderate compression.
    /// Suitable for archival purposes and professional photography.
    ///
    /// - Returns: A configuration for high-quality compression (quality: 0.95).
    public static var highQuality: J2KConfiguration {
        return J2KConfiguration(quality: 0.95, lossless: false)
    }
    
    /// Creates a configuration for balanced compression.
    ///
    /// Use this preset for a good balance between file size and visual quality.
    /// This is the recommended default for most use cases.
    ///
    /// - Returns: A configuration for balanced compression (quality: 0.85).
    public static var balanced: J2KConfiguration {
        return J2KConfiguration(quality: 0.85, lossless: false)
    }
    
    /// Creates a configuration for fast compression with smaller file sizes.
    ///
    /// Use this preset when file size is more important than visual quality,
    /// such as for web delivery or bandwidth-constrained scenarios.
    ///
    /// - Returns: A configuration for fast compression (quality: 0.70).
    public static var fast: J2KConfiguration {
        return J2KConfiguration(quality: 0.70, lossless: false)
    }
    
    /// Creates a configuration for maximum compression.
    ///
    /// Use this preset when you need the smallest possible file size and can
    /// tolerate visible compression artifacts.
    ///
    /// - Returns: A configuration for maximum compression (quality: 0.50).
    public static var maxCompression: J2KConfiguration {
        return J2KConfiguration(quality: 0.50, lossless: false)
    }
}

/// Returns the version of the J2KSwift framework.
///
/// This function returns the semantic version string for the current release of J2KSwift.
/// The version follows semantic versioning (semver) format: MAJOR.MINOR.PATCH.
///
/// Example:
/// ```swift
/// let version = getVersion()
/// print("J2KSwift version: \(version)")
/// ```
///
/// - Returns: A string representing the current version in semver format.
public func getVersion() -> String {
    return "1.2.0"
}
