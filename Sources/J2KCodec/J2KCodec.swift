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
///
/// `J2KEncoder` provides a high-level API for encoding images to JPEG 2000 codestreams.
/// It connects all encoding components — color transform, wavelet transform, quantization,
/// entropy coding, and rate control — into a complete encoding pipeline.
///
/// ## Basic Usage
///
/// ```swift
/// let encoder = J2KEncoder()
/// let image = J2KImage(width: 256, height: 256, components: 3, bitDepth: 8)
/// let data = try encoder.encode(image)
/// ```
///
/// ## Custom Configuration
///
/// ```swift
/// let config = J2KEncodingPreset.quality.configuration(quality: 0.95)
/// let encoder = J2KEncoder(encodingConfiguration: config)
/// let data = try encoder.encode(image)
/// ```
///
/// ## Progress Reporting
///
/// ```swift
/// let data = try encoder.encode(image) { update in
///     print("\(update.stage): \(Int(update.overallProgress * 100))%")
/// }
/// ```
public struct J2KEncoder: Sendable {
    /// The configuration to use for encoding.
    public let configuration: J2KConfiguration

    /// The detailed encoding configuration.
    public let encodingConfiguration: J2KEncodingConfiguration

    /// Creates a new encoder with the specified configuration.
    ///
    /// - Parameter configuration: The encoding configuration.
    public init(configuration: J2KConfiguration = J2KConfiguration()) {
        self.configuration = configuration
        self.encodingConfiguration = J2KEncodingConfiguration(
            quality: configuration.quality,
            lossless: configuration.lossless
        )
    }

    /// Creates a new encoder with a detailed encoding configuration.
    ///
    /// - Parameter encodingConfiguration: The detailed encoding configuration.
    public init(encodingConfiguration: J2KEncodingConfiguration) {
        self.configuration = J2KConfiguration(
            quality: encodingConfiguration.quality,
            lossless: encodingConfiguration.lossless
        )
        self.encodingConfiguration = encodingConfiguration
    }

    /// Encodes an image to JPEG 2000 format.
    ///
    /// This method processes the image through the complete JPEG 2000 encoding pipeline:
    /// 1. Preprocessing and input validation
    /// 2. Color transform (RCT for lossless, ICT for lossy)
    /// 3. Multi-level wavelet transform
    /// 4. Quantization
    /// 5. EBCOT entropy coding
    /// 6. Rate control and layer formation
    /// 7. Codestream generation
    ///
    /// - Parameter image: The image to encode. Must have valid dimensions and components.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the image is invalid.
    /// - Throws: ``J2KError/encodingError(_:)`` if encoding fails.
    public func encode(_ image: J2KImage) throws -> Data {
        let pipeline = EncoderPipeline(config: encodingConfiguration)
        return try pipeline.encode(image)
    }

    /// Encodes an image to JPEG 2000 format with progress reporting.
    ///
    /// - Parameters:
    ///   - image: The image to encode.
    ///   - progress: A callback invoked with progress updates during encoding.
    /// - Returns: The encoded JPEG 2000 codestream data.
    /// - Throws: ``J2KError`` if encoding fails.
    public func encode(
        _ image: J2KImage,
        progress: ((EncoderProgressUpdate) -> Void)?
    ) throws -> Data {
        let pipeline = EncoderPipeline(config: encodingConfiguration)
        return try pipeline.encode(image, progress: progress)
    }
}

/// Decodes JPEG 2000 images.
///
/// `J2KDecoder` provides a high-level API for decoding JPEG 2000 codestreams to images.
/// It connects all decoding components — codestream parsing, entropy decoding, dequantization,
/// inverse wavelet transform, and inverse color transform — into a complete decoding pipeline.
///
/// ## Basic Usage
///
/// ```swift
/// let decoder = J2KDecoder()
/// let codestreamData = // ... load from file
/// let image = try decoder.decode(codestreamData)
/// ```
///
/// ## Progress Reporting
///
/// ```swift
/// let image = try decoder.decode(data) { update in
///     print("\(update.stage): \(Int(update.overallProgress * 100))%")
/// }
/// ```
public struct J2KDecoder: Sendable {
    /// Creates a new decoder.
    public init() {}

    /// Decodes JPEG 2000 data into an image.
    ///
    /// This method processes the codestream through the complete JPEG 2000 decoding pipeline:
    /// 1. Codestream parsing and marker validation
    /// 2. Tile data extraction from packets
    /// 3. EBCOT entropy decoding
    /// 4. Dequantization
    /// 5. Inverse wavelet transform
    /// 6. Inverse color transform (YCbCr → RGB)
    /// 7. Image reconstruction
    ///
    /// - Parameter data: The JPEG 2000 codestream data to decode.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError/decodingError(_:)`` if decoding fails.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if the codestream is malformed.
    public func decode(_ data: Data) throws -> J2KImage {
        let pipeline = DecoderPipeline()
        return try pipeline.decode(data)
    }

    /// Decodes JPEG 2000 data into an image with progress reporting.
    ///
    /// - Parameters:
    ///   - data: The JPEG 2000 codestream data to decode.
    ///   - progress: A callback invoked with progress updates during decoding.
    /// - Returns: The decoded image.
    /// - Throws: ``J2KError`` if decoding fails.
    public func decode(
        _ data: Data,
        progress: ((DecoderProgressUpdate) -> Void)?
    ) throws -> J2KImage {
        let pipeline = DecoderPipeline()
        return try pipeline.decode(data, progress: progress)
    }
}
