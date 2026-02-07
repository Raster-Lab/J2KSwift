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
    ///   - passeCount: The number of coding passes (default: 0).
    ///   - zeroBitPlanes: The number of missing MSB planes (default: 0).
    public init(
        index: Int,
        x: Int,
        y: Int,
        width: Int,
        height: Int,
        subband: J2KSubband,
        data: Data = Data(),
        passeCount: Int = 0,
        zeroBitPlanes: Int = 0
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
}

/// Returns the version of the J2KSwift framework.
///
/// - Returns: A string representing the current version.
public func getVersion() -> String {
    return "0.1.0-dev"
}
