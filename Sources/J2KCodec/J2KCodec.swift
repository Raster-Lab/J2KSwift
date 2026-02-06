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
    /// This method performs the complete JPEG 2000 encoding pipeline:
    /// 1. Input validation
    /// 2. Color space transformation (RGB → YCbCr if applicable)
    /// 3. Discrete wavelet transform (DWT)
    /// 4. Quantization
    /// 5. Entropy coding (EBCOT)
    /// 6. Rate control and layer formation
    /// 7. Codestream assembly
    ///
    /// - Parameter image: The image to encode. Must have valid dimensions and at least one component.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the image is invalid.
    /// - Throws: ``J2KError/internalError(_:)`` if encoding fails.
    ///
    /// Example:
    /// ```swift
    /// let image = J2KImage(width: 512, height: 512, components: 3)
    /// let encoder = J2KEncoder(configuration: J2KConfiguration(quality: 0.9))
    /// let encodedData = try encoder.encode(image)
    /// ```
    ///
    /// - Note: This is a simplified initial implementation. Full JPEG 2000 encoding with all
    ///   codec components (DWT, quantization, entropy coding, etc.) will be completed in Phase 7.
    public func encode(_ image: J2KImage) throws -> Data {
        let pipeline = J2KEncoderPipeline(configuration: configuration)
        return try pipeline.encode(image)
    }
}

/// Decodes JPEG 2000 images.
public struct J2KDecoder: Sendable {
    /// Creates a new decoder.
    public init() {}
    
    /// Decodes JPEG 2000 data into an image.
    ///
    /// This method performs the complete JPEG 2000 decoding pipeline:
    /// 1. Parse codestream headers
    /// 2. Entropy decoding
    /// 3. Dequantization
    /// 4. Inverse wavelet transform
    /// 5. Inverse color transform
    /// 6. Image reconstruction
    ///
    /// - Parameter data: The JPEG 2000 codestream data to decode.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the data is invalid.
    /// - Throws: ``J2KError/internalError(_:)`` if decoding fails.
    ///
    /// Example:
    /// ```swift
    /// let decoder = J2KDecoder()
    /// let image = try decoder.decode(encodedData)
    /// print("Decoded: \(image.width)x\(image.height)")
    /// ```
    ///
    /// - Note: This is a simplified initial implementation. Full JPEG 2000 decoding with all
    ///   codec components (entropy decoding, dequantization, IDWT, etc.) will be completed in Phase 7.
    public func decode(_ data: Data) throws -> J2KImage {
        let pipeline = J2KDecoderPipeline()
        return try pipeline.decode(data)
    }
}
