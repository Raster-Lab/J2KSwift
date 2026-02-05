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
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(_ image: J2KImage) throws -> Data {
        fatalError("Not implemented")
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
    /// - Throws: ``J2KError`` if decoding fails.
    public func decode(_ data: Data) throws -> J2KImage {
        fatalError("Not implemented")
    }
}
