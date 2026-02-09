/// # J2KCodec
///
/// Codec module for JPEG 2000 encoding and decoding.
///
/// This module provides the core encoding and decoding functionality for JPEG 2000 images,
/// including support for various compression modes and quality settings.
///
/// ## Topics
///
/// ### Encoding
/// - ``J2KEncoder``
///
/// ### Decoding
/// - ``J2KDecoder``

import Foundation
import J2KCore

/// Encodes images to JPEG 2000 format.
public struct J2KEncoder: Sendable {
    /// The configuration to use for encoding.
    public let configuration: J2KConfiguration
    
    /// Creates a new encoder with the specified configuration.
    ///
    /// - Parameter configuration: The encoding configuration.
    public init(configuration: J2KConfiguration = J2KConfiguration()) {
        self.configuration = configuration
    }
    
    /// Encodes an image to JPEG 2000 format.
    ///
    /// - Parameter image: The image to encode.
    /// - Returns: The encoded image data.
    /// - Throws: ``J2KError/notImplemented(_:)`` - This API is not yet implemented in v1.0.
    ///
    /// - Note: This high-level API is not yet implemented in v1.0. Use component-level
    ///   APIs (wavelet transform, quantization, entropy coding) directly for now.
    ///   Full implementation planned for v1.1. See ROADMAP_v1.1.md for details.
    ///
    /// Example of component-level usage:
    /// ```swift
    /// // Component-level encoding (v1.0 approach)
    /// let dwt = J2KDWT2D()
    /// let quantizer = J2KQuantizer()
    /// let bitPlaneCoder = BitPlaneCoder(...)
    /// // ... assemble manually
    /// ```
    public func encode(_ image: J2KImage) throws -> Data {
        throw J2KError.notImplemented(
            "J2KEncoder.encode() is not implemented in v1.0. This is a high-level integration API planned for v1.1. Use component-level APIs directly for now. See ROADMAP_v1.1.md and GETTING_STARTED.md for examples."
        )
    }
}

/// Decodes JPEG 2000 images.
public struct J2KDecoder: Sendable {
    /// Creates a new decoder.
    public init() {}
    
    /// Decodes JPEG 2000 data into an image.
    ///
    /// - Parameter data: The JPEG 2000 data to decode.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError/notImplemented(_:)`` - This API is not yet implemented in v1.0.
    ///
    /// - Note: This high-level API is not yet implemented in v1.0. Use component-level
    ///   APIs (entropy decoding, dequantization, inverse wavelet transform) directly for now.
    ///   Full implementation planned for v1.1. See ROADMAP_v1.1.md for details.
    ///
    /// Example of component-level usage:
    /// ```swift
    /// // Component-level decoding (v1.0 approach)
    /// let bitPlaneDecoder = BitPlaneDecoder(...)
    /// let quantizer = J2KQuantizer()
    /// let idwt = J2KDWT2D()
    /// // ... assemble manually
    /// ```
    public func decode(_ data: Data) throws -> J2KImage {
        throw J2KError.notImplemented(
            "J2KDecoder.decode() is not implemented in v1.0. This is a high-level integration API planned for v1.1. Use component-level APIs directly for now. See ROADMAP_v1.1.md and GETTING_STARTED.md for examples."
        )
    }
}
