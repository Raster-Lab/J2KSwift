//
// MJ2VideoToolbox.swift
// J2KSwift
//
/// # MJ2VideoToolbox
///
/// VideoToolbox integration for hardware-accelerated transcoding between Motion JPEG 2000 and H.264/H.265.
///
/// This module provides hardware-accelerated encoding and decoding capabilities for Apple platforms,
/// enabling efficient conversion between MJ2 and modern video codecs (H.264/H.265).

#if canImport(VideoToolbox)
import Foundation
import VideoToolbox
import CoreVideo
import CoreMedia
import J2KCore

// MARK: - VideoToolbox Error

/// Errors that can occur during VideoToolbox operations.
public enum MJ2VideoToolboxError: Error, Sendable {
    /// VideoToolbox is not available on this platform.
    case notAvailable

    /// Hardware encoder/decoder is not available.
    case hardwareNotAvailable

    /// Failed to create compression session.
    case compressionSessionCreationFailed(OSStatus)

    /// Failed to create decompression session.
    case decompressionSessionCreationFailed(OSStatus)

    /// Encoding failed.
    case encodingFailed(OSStatus)

    /// Decoding failed.
    case decodingFailed(OSStatus)

    /// Invalid pixel buffer.
    case invalidPixelBuffer

    /// Invalid image dimensions.
    case invalidDimensions

    /// Unsupported color space.
    case unsupportedColorSpace

    /// Configuration error.
    case configurationError(String)
}

// MARK: - Video Codec Type

/// Supported video codec types for transcoding.
public enum MJ2VideoCodec: Sendable {
    /// H.264 (AVC) codec.
    case h264

    /// H.265 (HEVC) codec.
    case h265

    var codecType: CMVideoCodecType {
        switch self {
        case .h264:
            return kCMVideoCodecType_H264
        case .h265:
            return kCMVideoCodecType_HEVC
        }
    }

    var description: String {
        switch self {
        case .h264:
            return "H.264 (AVC)"
        case .h265:
            return "H.265 (HEVC)"
        }
    }
}

// MARK: - Encoder Configuration

/// Configuration for VideoToolbox encoding.
public struct MJ2VideoToolboxEncoderConfiguration: Sendable {
    /// Target codec.
    public var codec: MJ2VideoCodec

    /// Target bitrate in bits per second.
    public var bitrate: Int

    /// Frame rate (frames per second).
    public var frameRate: Double

    /// Enable hardware acceleration if available.
    public var useHardwareAcceleration: Bool

    /// Profile level (e.g., "High" for H.264).
    public var profileLevel: String?

    /// Maximum keyframe interval.
    public var maxKeyFrameInterval: Int

    /// Enable B-frames.
    public var allowBFrames: Bool

    /// Target quality (0.0 = low, 1.0 = high). Only used if bitrate is 0.
    public var quality: Double

    /// Enable multi-pass encoding.
    public var multiPass: Bool

    /// Creates default H.264 configuration.
    public static func defaultH264(bitrate: Int = 5_000_000, frameRate: Double = 24.0) -> Self {
        Self(
            codec: .h264,
            bitrate: bitrate,
            frameRate: frameRate,
            useHardwareAcceleration: true,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            maxKeyFrameInterval: 60,
            allowBFrames: true,
            quality: 0.8,
            multiPass: false
        )
    }

    /// Creates default H.265 configuration.
    public static func defaultH265(bitrate: Int = 3_000_000, frameRate: Double = 24.0) -> Self {
        Self(
            codec: .h265,
            bitrate: bitrate,
            frameRate: frameRate,
            useHardwareAcceleration: true,
            profileLevel: kVTProfileLevel_HEVC_Main_AutoLevel as String,
            maxKeyFrameInterval: 60,
            allowBFrames: true,
            quality: 0.8,
            multiPass: false
        )
    }
}

// MARK: - Decoder Configuration

/// Configuration for VideoToolbox decoding.
public struct MJ2VideoToolboxDecoderConfiguration: Sendable {
    /// Enable hardware acceleration if available.
    public var useHardwareAcceleration: Bool

    /// Enable deinterlacing.
    public var deinterlace: Bool

    /// Output color space.
    public var outputColorSpace: J2KColorSpace

    /// Creates default decoder configuration.
    public static func `default`() -> Self {
        Self(
            useHardwareAcceleration: true,
            deinterlace: false,
            outputColorSpace: .sRGB
        )
    }
}

// MARK: - Hardware Capabilities

/// Information about available hardware encoding/decoding capabilities.
public struct MJ2VideoToolboxCapabilities: Sendable {
    /// Hardware encoder is available for H.264.
    public let h264HardwareEncoderAvailable: Bool

    /// Hardware encoder is available for H.265.
    public let h265HardwareEncoderAvailable: Bool

    /// Hardware decoder is available for H.264.
    public let h264HardwareDecoderAvailable: Bool

    /// Hardware decoder is available for H.265.
    public let h265HardwareDecoderAvailable: Bool

    /// Maximum supported resolution (width x height).
    public let maxResolution: (width: Int, height: Int)

    /// Supported pixel formats.
    public let supportedPixelFormats: [OSType]
}

// MARK: - VideoToolbox Encoder

/// VideoToolbox-based encoder for converting J2KImage frames to H.264/H.265.
public actor MJ2VideoToolboxEncoder {
    private let configuration: MJ2VideoToolboxEncoderConfiguration
    private var compressionSession: VTCompressionSession?
    private var frameCount: Int = 0
    private var encodedFrames: [CMSampleBuffer] = []
    private var isConfigured: Bool = false

    /// Creates a new VideoToolbox encoder.
    ///
    /// - Parameter configuration: Encoder configuration.
    public init(configuration: MJ2VideoToolboxEncoderConfiguration) {
        self.configuration = configuration
    }

    /// Initializes the compression session.
    ///
    /// - Parameters:
    ///   - width: Frame width.
    ///   - height: Frame height.
    /// - Throws: `MJ2VideoToolboxError` if session creation fails.
    public func initialize(width: Int, height: Int) async throws {
        guard width > 0 && height > 0 else {
            throw MJ2VideoToolboxError.invalidDimensions
        }

        var session: VTCompressionSession?

        let sourceImageBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let encoderSpecification: [CFString: Any]? = configuration.useHardwareAcceleration ? [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
        ] : nil

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: configuration.codec.codecType,
            encoderSpecification: encoderSpecification as CFDictionary?,
            imageBufferAttributes: sourceImageBufferAttributes as CFDictionary?,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw MJ2VideoToolboxError.compressionSessionCreationFailed(status)
        }

        self.compressionSession = session

        // Configure session properties
        try await configureSession(session)

        // Prepare to encode
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else {
            throw MJ2VideoToolboxError.compressionSessionCreationFailed(prepareStatus)
        }

        isConfigured = true
    }

    private func configureSession(_ session: VTCompressionSession) async throws {
        // Set bitrate or quality
        if configuration.bitrate > 0 {
            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_AverageBitRate,
                value: configuration.bitrate as CFNumber
            )
        } else {
            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_Quality,
                value: configuration.quality as CFNumber
            )
        }

        // Set frame rate
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: configuration.frameRate as CFNumber
        )

        // Set max keyframe interval
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: configuration.maxKeyFrameInterval as CFNumber
        )

        // Set profile level if specified
        if let profileLevel = configuration.profileLevel {
            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_ProfileLevel,
                value: profileLevel as CFString
            )
        }

        // Enable B-frames if requested
        if configuration.allowBFrames {
            VTSessionSetProperty(
                session,
                key: kVTCompressionPropertyKey_AllowFrameReordering,
                value: kCFBooleanTrue
            )
        }

        // Enable real-time encoding
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )
    }

    /// Encodes a J2KImage frame.
    ///
    /// - Parameters:
    ///   - image: The image to encode.
    ///   - presentationTime: Presentation timestamp for the frame.
    ///   - duration: Duration of the frame.
    /// - Returns: Encoded CMSampleBuffer.
    /// - Throws: `MJ2VideoToolboxError` if encoding fails.
    public func encode(
        image: J2KImage,
        presentationTime: CMTime,
        duration: CMTime
    ) async throws -> CMSampleBuffer {
        guard isConfigured, let session = compressionSession else {
            throw MJ2VideoToolboxError.configurationError("Encoder not initialized")
        }

        // Convert J2KImage to CVPixelBuffer
        let pixelBuffer = try await convertToPixelBuffer(image)

        // Encode frame
        var encodedBuffer: CMSampleBuffer?
        let flags: VTEncodeInfoFlags = []

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )

        guard status == noErr else {
            throw MJ2VideoToolboxError.encodingFailed(status)
        }

        // For synchronous encoding, we need to flush
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: presentationTime)

        frameCount += 1

        // Note: In a real implementation, we would use an output callback to receive encoded frames.
        // For now, we create a placeholder sample buffer.
        // This would need to be updated with actual encoded data from the callback.
        guard let sampleBuffer = try await getEncodedFrame() else {
            throw MJ2VideoToolboxError.encodingFailed(status)
        }

        return sampleBuffer
    }

    private func convertToPixelBuffer(_ image: J2KImage) async throws -> CVPixelBuffer {
        // Create pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            image.width,
            image.height,
            kCVPixelFormatType_32ARGB,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw MJ2VideoToolboxError.invalidPixelBuffer
        }

        // Lock pixel buffer for writing
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw MJ2VideoToolboxError.invalidPixelBuffer
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let data = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Convert J2KImage components to ARGB pixel buffer
        try await fillPixelBuffer(data: data, bytesPerRow: bytesPerRow, image: image)

        return buffer
    }

    private func fillPixelBuffer(data: UnsafeMutablePointer<UInt8>, bytesPerRow: Int, image: J2KImage) async throws {
        // Get RGB components
        guard image.components.count >= 3 else {
            throw MJ2VideoToolboxError.unsupportedColorSpace
        }

        let rComp = image.components[0]
        let gComp = image.components[1]
        let bComp = image.components[2]

        // Convert component data to bytes
        for y in 0..<image.height {
            for x in 0..<image.width {
                let pixelIndex = y * image.width + x
                let bufferOffset = y * bytesPerRow + x * 4

                // Extract pixel values (assuming 8-bit depth for now)
                let r = rComp.data[pixelIndex]
                let g = gComp.data[pixelIndex]
                let b = bComp.data[pixelIndex]

                // Write ARGB (note: might need to adjust byte order depending on platform)
                data[bufferOffset + 0] = 255  // A
                data[bufferOffset + 1] = r    // R
                data[bufferOffset + 2] = g    // G
                data[bufferOffset + 3] = b    // B
            }
        }
    }

    private func getEncodedFrame() async throws -> CMSampleBuffer? {
        // This is a placeholder. In a real implementation, encoded frames would be
        // collected from the VTCompressionSession output callback.
        // For now, return nil to indicate that callback-based collection is needed.
        nil
    }

    /// Finishes encoding and flushes any pending frames.
    ///
    /// - Throws: `MJ2VideoToolboxError` if finishing fails.
    public func finish() async throws {
        guard let session = compressionSession else { return }

        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard status == noErr else {
            throw MJ2VideoToolboxError.encodingFailed(status)
        }

        VTCompressionSessionInvalidate(session)
        compressionSession = nil
        isConfigured = false
    }

    deinit {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
        }
    }
}

// MARK: - VideoToolbox Decoder

/// VideoToolbox-based decoder for converting H.264/H.265 to J2KImage frames.
public actor MJ2VideoToolboxDecoder {
    private let configuration: MJ2VideoToolboxDecoderConfiguration
    private var decompressionSession: VTDecompressionSession?
    private var isConfigured: Bool = false

    /// Creates a new VideoToolbox decoder.
    ///
    /// - Parameter configuration: Decoder configuration.
    public init(configuration: MJ2VideoToolboxDecoderConfiguration) {
        self.configuration = configuration
    }

    /// Initializes the decompression session.
    ///
    /// - Parameters:
    ///   - formatDescription: Format description for the encoded video.
    /// - Throws: `MJ2VideoToolboxError` if session creation fails.
    public func initialize(formatDescription: CMFormatDescription) async throws {
        var session: VTDecompressionSession?

        let destinationPixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32ARGB,
            kCVPixelBufferMetalCompatibilityKey: true
        ]

        let decoderSpecification: [CFString: Any]? = configuration.useHardwareAcceleration ? [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: true
        ] : nil

        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification as CFDictionary?,
            imageBufferAttributes: destinationPixelBufferAttributes as CFDictionary?,
            outputCallback: nil,
            decompressionSessionOut: &session
        )

        guard status == noErr, let session = session else {
            throw MJ2VideoToolboxError.decompressionSessionCreationFailed(status)
        }

        self.decompressionSession = session
        isConfigured = true
    }

    /// Decodes a CMSampleBuffer to J2KImage.
    ///
    /// - Parameter sampleBuffer: The sample buffer to decode.
    /// - Returns: Decoded J2KImage.
    /// - Throws: `MJ2VideoToolboxError` if decoding fails.
    public func decode(sampleBuffer: CMSampleBuffer) async throws -> J2KImage {
        guard isConfigured, let session = decompressionSession else {
            throw MJ2VideoToolboxError.configurationError("Decoder not initialized")
        }

        var decodedBuffer: CVImageBuffer?
        let flags: VTDecodeFrameFlags = []

        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: flags,
            frameRefcon: nil,
            infoFlagsOut: nil
        )

        guard status == noErr else {
            throw MJ2VideoToolboxError.decodingFailed(status)
        }

        // Wait for decoding to complete
        VTDecompressionSessionWaitForAsynchronousFrames(session)

        // In a real implementation, decoded frames would be received via output callback
        // For now, this is a placeholder that would need callback integration
        guard let pixelBuffer = try await getDecodedFrame() else {
            throw MJ2VideoToolboxError.decodingFailed(status)
        }

        // Convert CVPixelBuffer to J2KImage
        return try await convertToJ2KImage(pixelBuffer)
    }

    private func getDecodedFrame() async throws -> CVPixelBuffer? {
        // Placeholder for callback-based frame retrieval
        nil
    }

    private func convertToJ2KImage(_ pixelBuffer: CVPixelBuffer) async throws -> J2KImage {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MJ2VideoToolboxError.invalidPixelBuffer
        }

        let data = baseAddress.assumingMemoryBound(to: UInt8.self)

        // Extract RGB components
        var rData = Data(count: width * height)
        var gData = Data(count: width * height)
        var bData = Data(count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let bufferOffset = y * bytesPerRow + x * 4
                let pixelIndex = y * width + x

                // Read ARGB
                rData[pixelIndex] = data[bufferOffset + 1]
                gData[pixelIndex] = data[bufferOffset + 2]
                bData[pixelIndex] = data[bufferOffset + 3]
            }
        }

        // Create J2KComponents
        let rComponent = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: rData
        )

        let gComponent = J2KComponent(
            index: 1,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: gData
        )

        let bComponent = J2KComponent(
            index: 2,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: bData
        )

        return J2KImage(
            width: width,
            height: height,
            components: [rComponent, gComponent, bComponent],
            colorSpace: configuration.outputColorSpace,
            offsetX: 0,
            offsetY: 0,
            tileWidth: 0,
            tileHeight: 0,
            tileOffsetX: 0,
            tileOffsetY: 0
        )
    }

    /// Finishes decoding and cleans up resources.
    public func finish() async {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
            decompressionSession = nil
        }
        isConfigured = false
    }

    deinit {
        if let session = decompressionSession {
            VTDecompressionSessionInvalidate(session)
        }
    }
}

// MARK: - Capability Detection

/// Detects available VideoToolbox hardware capabilities.
public struct MJ2VideoToolboxCapabilityDetector {
    /// Queries hardware capabilities.
    ///
    /// - Returns: Available hardware capabilities.
    public static func detectCapabilities() -> MJ2VideoToolboxCapabilities {
        // Query hardware encoder availability
        let h264HWEnc = isHardwareEncoderAvailable(codec: .h264)
        let h265HWEnc = isHardwareEncoderAvailable(codec: .h265)

        // Query hardware decoder availability
        let h264HWDec = isHardwareDecoderAvailable(codec: .h264)
        let h265HWDec = isHardwareDecoderAvailable(codec: .h265)

        // Detect maximum resolution (typically 4K on most modern hardware)
        let maxResolution = detectMaxResolution()

        // Query supported pixel formats
        let pixelFormats = detectSupportedPixelFormats()

        return MJ2VideoToolboxCapabilities(
            h264HardwareEncoderAvailable: h264HWEnc,
            h265HardwareEncoderAvailable: h265HWEnc,
            h264HardwareDecoderAvailable: h264HWDec,
            h265HardwareDecoderAvailable: h265HWDec,
            maxResolution: maxResolution,
            supportedPixelFormats: pixelFormats
        )
    }

    private static func isHardwareEncoderAvailable(codec: MJ2VideoCodec) -> Bool {
        // Try to create a session with hardware acceleration requirement
        var session: VTCompressionSession?
        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
        ]

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 1920,
            height: 1080,
            codecType: codec.codecType,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )

        if let session = session {
            VTCompressionSessionInvalidate(session)
        }

        return status == noErr
    }

    private static func isHardwareDecoderAvailable(codec: MJ2VideoCodec) -> Bool {
        // Hardware decoders are generally available on all modern Apple platforms
        // More detailed detection would require actual format descriptions
        true
    }

    private static func detectMaxResolution() -> (width: Int, height: Int) {
        // Most modern Apple hardware supports 4K (3840x2160)
        // Some support 8K (7680x4320)
        // For now, return conservative 4K limit
        (width: 3840, height: 2160)
    }

    private static func detectSupportedPixelFormats() -> [OSType] {
        // Common pixel formats supported by VideoToolbox
        [
            kCVPixelFormatType_32ARGB,
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelFormatType_422YpCbCr8,
            kCVPixelFormatType_444YpCbCr8
        ]
    }
}

#endif // canImport(VideoToolbox)
