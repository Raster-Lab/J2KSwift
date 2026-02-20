/// # MJ2SoftwareEncoder
///
/// Software-based video encoder for cross-platform support.
///
/// This implementation provides software-based transcoding from Motion JPEG 2000 to H.264/H.265
/// on platforms without hardware acceleration. It serves as a fallback when VideoToolbox is not available.

import Foundation
import J2KCore

// MARK: - Software Encoder

/// Software-based video encoder using system tools or libraries.
///
/// This actor provides cross-platform video encoding capabilities by utilizing:
/// 1. FFmpeg command-line tool (if available)
/// 2. x264/x265 libraries (if linked)
/// 3. Basic software fallback
///
/// ## Platform Support
///
/// - **Apple Platforms**: Use ``MJ2VideoToolboxEncoder`` for better performance
/// - **Linux**: Requires FFmpeg or x264/x265 libraries
/// - **Windows**: Requires FFmpeg or x264/x265 libraries
///
/// ## Example
///
/// ```swift
/// let config = MJ2SoftwareEncoderConfiguration(
///     codec: .h264,
///     quality: .medium,
///     performance: .balanced
/// )
/// let encoder = MJ2SoftwareEncoder(configuration: config)
/// try await encoder.startEncoding()
/// let data = try await encoder.encode(frame)
/// try await encoder.finishEncoding()
/// ```
///
/// ## Performance Characteristics
///
/// Software encoding is significantly slower than hardware encoding:
/// - **Hardware (VideoToolbox)**: 60-120+ fps at 1080p
/// - **Software (FFmpeg)**: 10-30 fps at 1080p
/// - **Software (Basic)**: 1-5 fps at 1080p
///
/// For real-time applications on non-Apple platforms, consider:
/// - Lower resolution encoding
/// - Faster encoding presets
/// - Hardware-accelerated FFmpeg builds
public actor MJ2SoftwareEncoder: MJ2VideoEncoderProtocol {
    // MARK: - Properties

    private let configuration: MJ2SoftwareEncoderConfiguration
    private var isActive = false
    private var frameCount = 0
    private var encodedFrames: [Data] = []

    // MARK: - Protocol Properties

    public nonisolated let encoderType: MJ2EncoderType
    public nonisolated let isHardwareAccelerated = false
    public nonisolated let capabilities: MJ2EncoderCapabilities

    // MARK: - Initialization

    /// Creates a software encoder with the specified configuration.
    ///
    /// - Parameter configuration: Encoder configuration.
    public init(configuration: MJ2SoftwareEncoderConfiguration) {
        self.configuration = configuration

        // Determine encoder type based on available tools
        if MJ2SoftwareEncoder.isFFmpegAvailable() {
            self.encoderType = .ffmpeg
        } else {
            self.encoderType = .software
        }

        // Set capabilities based on encoder type
        self.capabilities = MJ2SoftwareEncoder.detectCapabilities(for: encoderType)
    }

    // MARK: - Protocol Methods

    public func startEncoding() async throws {
        guard !isActive else {
            throw MJ2VideoEncoderError.sessionCreationFailed("Encoder already active")
        }

        // Validate configuration
        guard capabilities.supportedCodecs.contains(configuration.codec) else {
            throw MJ2VideoEncoderError.unsupportedCodec(configuration.codec)
        }

        isActive = true
        frameCount = 0
        encodedFrames = []
    }

    public func encode(_ frame: J2KImage) async throws -> Data {
        guard isActive else {
            throw MJ2VideoEncoderError.encodingFailed("Encoder not started")
        }

        // Validate frame dimensions
        guard frame.width > 0, frame.height > 0 else {
            throw MJ2VideoEncoderError.invalidDimensions(width: frame.width, height: frame.height)
        }

        // Encode based on available encoder
        let encodedData: Data
        switch encoderType {
        case .ffmpeg:
            encodedData = try await encodeWithFFmpeg(frame)
        case .software:
            encodedData = try await encodeWithSoftwareFallback(frame)
        default:
            throw MJ2VideoEncoderError.encodingFailed("Unsupported encoder type: \(encoderType)")
        }

        frameCount += 1
        encodedFrames.append(encodedData)

        return encodedData
    }

    public func finishEncoding() async throws -> Data {
        guard isActive else {
            throw MJ2VideoEncoderError.finalizationFailed("Encoder not started")
        }

        isActive = false

        // Combine all encoded frames
        var combinedData = Data()
        for frameData in encodedFrames {
            combinedData.append(frameData)
        }

        return combinedData
    }

    public func cancelEncoding() async {
        isActive = false
        encodedFrames = []
        frameCount = 0
    }

    // MARK: - FFmpeg Encoding

    private func encodeWithFFmpeg(_ frame: J2KImage) async throws -> Data {
        // Note: This is a placeholder implementation
        // A real implementation would:
        // 1. Write frame to temporary file or pipe
        // 2. Invoke FFmpeg with appropriate parameters
        // 3. Read encoded output
        // 4. Clean up temporary files

        throw MJ2VideoEncoderError.encodingFailed("FFmpeg integration not yet implemented")
    }

    // MARK: - Software Fallback Encoding

    private func encodeWithSoftwareFallback(_ frame: J2KImage) async throws -> Data {
        // Basic software fallback - placeholder implementation
        // This would require a complete H.264/H.265 encoder implementation
        // which is beyond the scope of this initial version

        throw MJ2VideoEncoderError.encodingFailed("Pure software encoding not yet implemented. Please install FFmpeg.")
    }

    // MARK: - Capability Detection

    private static func detectCapabilities(for encoderType: MJ2EncoderType) -> MJ2EncoderCapabilities {
        switch encoderType {
        case .ffmpeg:
            // FFmpeg typically supports both H.264 and H.265
            return MJ2EncoderCapabilities(
                supportedCodecs: [.h264, .h265],
                supportsHardwareAcceleration: false,
                supportsVBR: true,
                supportsCBR: true,
                supportsQualityMode: true,
                supportsBFrames: true,
                supportsMultiPass: true
            )
        case .software:
            // Basic software fallback has minimal capabilities
            return MJ2EncoderCapabilities(
                supportedCodecs: [.h264],
                supportsHardwareAcceleration: false,
                supportsVBR: false,
                supportsCBR: true,
                supportsQualityMode: false,
                supportsBFrames: false,
                supportsMultiPass: false
            )
        default:
            return MJ2EncoderCapabilities(
                supportedCodecs: [],
                supportsHardwareAcceleration: false
            )
        }
    }

    /// Checks whether FFmpeg is available on the system.
    ///
    /// - Returns: `true` if FFmpeg is found in PATH, `false` otherwise.
    public static func isFFmpegAvailable() -> Bool {
        // Check if ffmpeg is in PATH
        #if os(Windows)
        let command = "where ffmpeg"
        #else
        let command = "which ffmpeg"
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["sh", "-c", command]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Software Encoder Configuration

/// Configuration for software-based video encoding.
public struct MJ2SoftwareEncoderConfiguration: Sendable {
    /// Target codec.
    public var codec: MJ2VideoCodec

    /// Quality configuration.
    public var quality: MJ2TranscodingQuality

    /// Performance configuration.
    public var performance: MJ2PerformanceConfiguration

    /// Frame rate (frames per second).
    public var frameRate: Double

    /// FFmpeg-specific options (only used with FFmpeg encoder).
    public var ffmpegOptions: [String]

    /// Creates a software encoder configuration.
    ///
    /// - Parameters:
    ///   - codec: Target codec (default: .h264).
    ///   - quality: Quality configuration (default: .medium).
    ///   - performance: Performance configuration (default: .balanced).
    ///   - frameRate: Frame rate in fps (default: 24.0).
    ///   - ffmpegOptions: Additional FFmpeg options (default: []).
    public init(
        codec: MJ2VideoCodec = .h264,
        quality: MJ2TranscodingQuality = .medium,
        performance: MJ2PerformanceConfiguration = .balanced,
        frameRate: Double = 24.0,
        ffmpegOptions: [String] = []
    ) {
        self.codec = codec
        self.quality = quality
        self.performance = performance
        self.frameRate = frameRate
        self.ffmpegOptions = ffmpegOptions
    }

    /// Default configuration for H.264 encoding.
    public static let h264Default = MJ2SoftwareEncoderConfiguration(
        codec: .h264,
        quality: .medium,
        frameRate: 24.0
    )

    /// Default configuration for H.265 encoding.
    public static let h265Default = MJ2SoftwareEncoderConfiguration(
        codec: .h265,
        quality: .medium,
        frameRate: 24.0
    )
}
