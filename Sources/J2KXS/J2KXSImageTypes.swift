// J2KXSImageTypes.swift
// J2KSwift
//
// JPEG XS (ISO/IEC 21122) image types, codec API surface, and error definitions.

import Foundation
import J2KCore

// MARK: - J2KXSPixelFormat

/// The pixel layout of a JPEG XS image.
///
/// Determines how component planes are arranged, mirroring the colour-space
/// and sub-sampling conventions defined in ISO/IEC 21122.
public enum J2KXSPixelFormat: Sendable, Equatable, CaseIterable {
    /// Planar YCbCr 4:2:0 — three planes, Cb/Cr at half width and height.
    case yuv420
    /// Planar YCbCr 4:2:2 — three planes, Cb/Cr at half width.
    case yuv422
    /// Planar YCbCr 4:4:4 — three full-resolution planes.
    case yuv444
    /// Planar RGB — three full-resolution planes.
    case rgb
    /// Planar RGBA — four full-resolution planes.
    case rgba

    /// The number of component planes for this pixel format.
    public var planeCount: Int {
        switch self {
        case .yuv420, .yuv422, .yuv444, .rgb: return 3
        case .rgba: return 4
        }
    }
}

// MARK: - J2KXSImage

/// A planar image suitable for JPEG XS encoding.
///
/// Each plane holds raw sample data in row-major order.  For `yuv420` and
/// `yuv422` formats the chroma planes are automatically sub-sampled by the
/// ``J2KXSEncoder`` prior to encoding.
///
/// Example:
/// ```swift
/// let image = J2KXSImage(
///     width: 1920, height: 1080,
///     pixelFormat: .yuv422,
///     planes: [lumaPlane, cbPlane, crPlane]
/// )
/// ```
public struct J2KXSImage: Sendable, Equatable {
    /// The image width in pixels.
    public var width: Int

    /// The image height in pixels.
    public var height: Int

    /// The pixel format (colour space and component layout).
    public var pixelFormat: J2KXSPixelFormat

    /// Raw component planes.  The number of planes must equal
    /// `pixelFormat.planeCount`.
    public var planes: [Data]

    /// Creates a JPEG XS image.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels (clamped to ≥ 1).
    ///   - height: Image height in pixels (clamped to ≥ 1).
    ///   - pixelFormat: Component layout.
    ///   - planes: Raw plane data.  Must contain `pixelFormat.planeCount`
    ///             elements.
    public init(width: Int, height: Int, pixelFormat: J2KXSPixelFormat, planes: [Data]) {
        self.width = max(1, width)
        self.height = max(1, height)
        self.pixelFormat = pixelFormat
        self.planes = planes
    }

    /// The total number of pixels (width × height).
    public var pixelCount: Int { width * height }
}

// MARK: - J2KXSError

/// Errors thrown by the JPEG XS codec.
public enum J2KXSError: Error, Sendable, Equatable {
    /// The configuration is not valid (e.g. a dimension is zero).
    case invalidConfiguration(String)

    /// The encoder failed to produce a valid codestream.
    case encodingFailed(String)

    /// The decoder failed to interpret the codestream.
    case decodingFailed(String)

    /// The requested profile is not supported by this build.
    case unsupportedProfile(J2KXSProfile)

    /// The number of planes in the image does not match the pixel format.
    case planeMismatch(expected: Int, got: Int)
}

// MARK: - J2KXSEncodeResult

/// The result of a JPEG XS encode operation.
///
/// Contains the compressed codestream together with metadata that describes
/// how the image was encoded.
public struct J2KXSEncodeResult: Sendable {
    /// The compressed JPEG XS codestream.
    public let encodedData: Data

    /// The profile used for encoding.
    public let profile: J2KXSProfile

    /// The level used for encoding.
    public let level: J2KXSLevel

    /// The number of independent slices the image was divided into.
    public let sliceCount: Int

    /// The wall-clock encoding time in milliseconds.
    public let encodingTimeMs: Double

    /// Creates an encode result.
    ///
    /// - Parameters:
    ///   - encodedData: The compressed codestream.
    ///   - profile: The profile used.
    ///   - level: The level used.
    ///   - sliceCount: Number of slices.
    ///   - encodingTimeMs: Encoding duration in ms.
    public init(
        encodedData: Data,
        profile: J2KXSProfile,
        level: J2KXSLevel,
        sliceCount: Int,
        encodingTimeMs: Double
    ) {
        self.encodedData = encodedData
        self.profile = profile
        self.level = level
        self.sliceCount = max(1, sliceCount)
        self.encodingTimeMs = max(0, encodingTimeMs)
    }

    /// The size of the encoded codestream in bytes.
    public var encodedBytes: Int { encodedData.count }
}

// MARK: - J2KXSDecodeResult

/// The result of a JPEG XS decode operation.
///
/// Wraps the reconstructed image and the profile/level read from the
/// codestream header.
public struct J2KXSDecodeResult: Sendable {
    /// The reconstructed image.
    public let image: J2KXSImage

    /// The profile declared in the codestream.
    public let profile: J2KXSProfile

    /// The level declared in the codestream.
    public let level: J2KXSLevel

    /// The wall-clock decoding time in milliseconds.
    public let decodingTimeMs: Double

    /// Creates a decode result.
    ///
    /// - Parameters:
    ///   - image: The reconstructed image.
    ///   - profile: Profile from the codestream header.
    ///   - level: Level from the codestream header.
    ///   - decodingTimeMs: Decoding duration in ms.
    public init(
        image: J2KXSImage,
        profile: J2KXSProfile,
        level: J2KXSLevel,
        decodingTimeMs: Double
    ) {
        self.image = image
        self.profile = profile
        self.level = level
        self.decodingTimeMs = max(0, decodingTimeMs)
    }
}
