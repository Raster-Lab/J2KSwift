/// # MJ2VideoEncoderProtocol
///
/// Abstract protocol for video encoder implementations.
///
/// This protocol defines the interface for encoding Motion JPEG 2000 frames to modern video codecs.
/// Implementations can use hardware acceleration (VideoToolbox), software libraries (x264/x265),
/// or system tools (FFmpeg).

import Foundation
import J2KCore

// MARK: - Video Encoder Protocol

/// Protocol for video encoder implementations.
///
/// Implementations provide transcoding from Motion JPEG 2000 to H.264/H.265 or other codecs.
/// The protocol supports both hardware and software encoders with capability detection.
///
/// Example:
/// ```swift
/// let encoder: any MJ2VideoEncoderProtocol = MJ2VideoToolboxEncoder(configuration: config)
/// try await encoder.startEncoding()
/// let data = try await encoder.encode(frame)
/// try await encoder.finishEncoding()
/// ```
public protocol MJ2VideoEncoderProtocol: Sendable {
    /// Encoder type identifier.
    var encoderType: MJ2EncoderType { get }
    
    /// Indicates whether the encoder is hardware-accelerated.
    var isHardwareAccelerated: Bool { get }
    
    /// Encoder capabilities.
    var capabilities: MJ2EncoderCapabilities { get }
    
    /// Starts the encoding session.
    ///
    /// Prepares the encoder for frame encoding. Must be called before encoding frames.
    ///
    /// - Throws: ``MJ2VideoEncoderError/sessionCreationFailed(_:)`` if session setup fails.
    func startEncoding() async throws
    
    /// Encodes a single frame.
    ///
    /// - Parameter frame: The frame to encode.
    /// - Returns: Encoded frame data.
    /// - Throws: ``MJ2VideoEncoderError/encodingFailed(_:)`` if encoding fails.
    func encode(_ frame: J2KImage) async throws -> Data
    
    /// Finishes the encoding session and flushes any pending frames.
    ///
    /// - Returns: Any remaining encoded data.
    /// - Throws: ``MJ2VideoEncoderError/finalizationFailed(_:)`` if finalization fails.
    func finishEncoding() async throws -> Data
    
    /// Cancels the encoding session.
    func cancelEncoding() async
}

// MARK: - Video Decoder Protocol

/// Protocol for video decoder implementations.
///
/// Implementations provide transcoding from H.264/H.265 or other codecs to Motion JPEG 2000.
/// The protocol supports both hardware and software decoders with capability detection.
///
/// Example:
/// ```swift
/// let decoder: any MJ2VideoDecoderProtocol = MJ2VideoToolboxDecoder(configuration: config)
/// try await decoder.startDecoding()
/// let frame = try await decoder.decode(data)
/// ```
public protocol MJ2VideoDecoderProtocol: Sendable {
    /// Decoder type identifier.
    var decoderType: MJ2DecoderType { get }
    
    /// Indicates whether the decoder is hardware-accelerated.
    var isHardwareAccelerated: Bool { get }
    
    /// Decoder capabilities.
    var capabilities: MJ2DecoderCapabilities { get }
    
    /// Starts the decoding session.
    ///
    /// Prepares the decoder for frame decoding. Must be called before decoding frames.
    ///
    /// - Throws: ``MJ2VideoDecoderError/sessionCreationFailed(_:)`` if session setup fails.
    func startDecoding() async throws
    
    /// Decodes a single frame.
    ///
    /// - Parameter data: The encoded frame data.
    /// - Returns: Decoded frame as J2KImage.
    /// - Throws: ``MJ2VideoDecoderError/decodingFailed(_:)`` if decoding fails.
    func decode(_ data: Data) async throws -> J2KImage
    
    /// Finishes the decoding session.
    func finishDecoding() async
    
    /// Cancels the decoding session.
    func cancelDecoding() async
}

// MARK: - Encoder Type

/// Supported encoder implementation types.
public enum MJ2EncoderType: String, Sendable {
    /// Hardware encoder using VideoToolbox (Apple platforms).
    case videoToolbox = "VideoToolbox"
    
    /// Software encoder using x264 library.
    case x264 = "x264"
    
    /// Software encoder using x265 library.
    case x265 = "x265"
    
    /// System tool encoder using FFmpeg.
    case ffmpeg = "FFmpeg"
    
    /// Software fallback encoder (basic implementation).
    case software = "Software"
    
    /// Unknown or custom encoder.
    case custom = "Custom"
}

// MARK: - Decoder Type

/// Supported decoder implementation types.
public enum MJ2DecoderType: String, Sendable {
    /// Hardware decoder using VideoToolbox (Apple platforms).
    case videoToolbox = "VideoToolbox"
    
    /// Software decoder using FFmpeg.
    case ffmpeg = "FFmpeg"
    
    /// Software fallback decoder (basic implementation).
    case software = "Software"
    
    /// Unknown or custom decoder.
    case custom = "Custom"
}

// MARK: - Encoder Capabilities

/// Capabilities of a video encoder.
public struct MJ2EncoderCapabilities: Sendable {
    /// Supported codecs.
    public var supportedCodecs: Set<MJ2VideoCodec>
    
    /// Supports hardware acceleration.
    public var supportsHardwareAcceleration: Bool
    
    /// Supports variable bitrate (VBR).
    public var supportsVBR: Bool
    
    /// Supports constant bitrate (CBR).
    public var supportsCBR: Bool
    
    /// Supports quality-based encoding.
    public var supportsQualityMode: Bool
    
    /// Supports B-frames.
    public var supportsBFrames: Bool
    
    /// Supports multi-pass encoding.
    public var supportsMultiPass: Bool
    
    /// Maximum supported resolution (width × height).
    public var maxResolution: (width: Int, height: Int)?
    
    /// Creates encoder capabilities.
    public init(
        supportedCodecs: Set<MJ2VideoCodec>,
        supportsHardwareAcceleration: Bool = false,
        supportsVBR: Bool = true,
        supportsCBR: Bool = true,
        supportsQualityMode: Bool = false,
        supportsBFrames: Bool = false,
        supportsMultiPass: Bool = false,
        maxResolution: (width: Int, height: Int)? = nil
    ) {
        self.supportedCodecs = supportedCodecs
        self.supportsHardwareAcceleration = supportsHardwareAcceleration
        self.supportsVBR = supportsVBR
        self.supportsCBR = supportsCBR
        self.supportsQualityMode = supportsQualityMode
        self.supportsBFrames = supportsBFrames
        self.supportsMultiPass = supportsMultiPass
        self.maxResolution = maxResolution
    }
}

// MARK: - Decoder Capabilities

/// Capabilities of a video decoder.
public struct MJ2DecoderCapabilities: Sendable {
    /// Supported codecs.
    public var supportedCodecs: Set<MJ2VideoCodec>
    
    /// Supports hardware acceleration.
    public var supportsHardwareAcceleration: Bool
    
    /// Maximum supported resolution (width × height).
    public var maxResolution: (width: Int, height: Int)?
    
    /// Creates decoder capabilities.
    public init(
        supportedCodecs: Set<MJ2VideoCodec>,
        supportsHardwareAcceleration: Bool = false,
        maxResolution: (width: Int, height: Int)? = nil
    ) {
        self.supportedCodecs = supportedCodecs
        self.supportsHardwareAcceleration = supportsHardwareAcceleration
        self.maxResolution = maxResolution
    }
}

// MARK: - Encoder Error

/// Errors that can occur during video encoding.
public enum MJ2VideoEncoderError: Error, Sendable {
    /// Encoder is not available on this platform.
    case notAvailable
    
    /// Hardware encoder is not available.
    case hardwareNotAvailable
    
    /// Session creation failed.
    case sessionCreationFailed(String)
    
    /// Encoding failed.
    case encodingFailed(String)
    
    /// Finalization failed.
    case finalizationFailed(String)
    
    /// Configuration error.
    case configurationError(String)
    
    /// Unsupported codec.
    case unsupportedCodec(MJ2VideoCodec)
    
    /// Invalid frame dimensions.
    case invalidDimensions(width: Int, height: Int)
}

// MARK: - Decoder Error

/// Errors that can occur during video decoding.
public enum MJ2VideoDecoderError: Error, Sendable {
    /// Decoder is not available on this platform.
    case notAvailable
    
    /// Hardware decoder is not available.
    case hardwareNotAvailable
    
    /// Session creation failed.
    case sessionCreationFailed(String)
    
    /// Decoding failed.
    case decodingFailed(String)
    
    /// Configuration error.
    case configurationError(String)
    
    /// Unsupported codec.
    case unsupportedCodec(MJ2VideoCodec)
    
    /// Invalid data format.
    case invalidDataFormat
}
