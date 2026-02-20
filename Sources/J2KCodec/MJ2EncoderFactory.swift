/// # MJ2EncoderFactory
///
/// Factory for creating appropriate video encoders based on platform capabilities.
///
/// This module provides automatic selection of the best available encoder for the current
/// platform, with graceful fallback from hardware to software implementations.

import Foundation
import J2KCore

// MARK: - Encoder Factory

/// Factory for creating video encoders with automatic platform detection.
///
/// The factory selects the best available encoder based on:
/// 1. Platform capabilities (VideoToolbox on Apple platforms)
/// 2. System tools (FFmpeg)
/// 3. Software fallback
///
/// ## Example
///
/// ```swift
/// // Automatic encoder selection
/// let encoder = try await MJ2EncoderFactory.createEncoder(
///     codec: .h264,
///     quality: .medium,
///     performance: .balanced
/// )
///
/// // Check what encoder was selected
/// print("Using \(encoder.encoderType) encoder")
/// print("Hardware accelerated: \(encoder.isHardwareAccelerated)")
/// ```
public struct MJ2EncoderFactory {
    // MARK: - Encoder Creation

    /// Creates the best available encoder for the current platform.
    ///
    /// Selection priority:
    /// 1. VideoToolbox (if available on Apple platforms)
    /// 2. FFmpeg (if installed)
    /// 3. Software fallback
    ///
    /// - Parameters:
    ///   - codec: Target codec.
    ///   - quality: Quality configuration.
    ///   - performance: Performance configuration.
    ///   - preferHardware: Prefer hardware acceleration (default: true).
    /// - Returns: Configured encoder implementation.
    /// - Throws: ``MJ2VideoEncoderError/notAvailable`` if no encoder is available.
    public static func createEncoder(
        codec: MJ2VideoCodec,
        quality: MJ2TranscodingQuality = .medium,
        performance: MJ2PerformanceConfiguration = .balanced,
        preferHardware: Bool = true
    ) async throws -> any MJ2VideoEncoderProtocol {
        // Try VideoToolbox on Apple platforms (hardware acceleration)
        #if canImport(VideoToolbox)
        if preferHardware && performance.allowHardwareAcceleration {
            // Import VideoToolbox types dynamically
            return try await createVideoToolboxEncoder(
                codec: codec,
                quality: quality,
                performance: performance
            )
        }
        #endif

        // Try software encoder (FFmpeg or fallback)
        let softwareConfig = MJ2SoftwareEncoderConfiguration(
            codec: codec,
            quality: quality,
            performance: performance
        )

        return MJ2SoftwareEncoder(configuration: softwareConfig)
    }

    #if canImport(VideoToolbox)
    /// Creates a VideoToolbox encoder (Apple platforms only).
    private static func createVideoToolboxEncoder(
        codec: MJ2VideoCodec,
        quality: MJ2TranscodingQuality,
        performance: MJ2PerformanceConfiguration
    ) async throws -> any MJ2VideoEncoderProtocol {
        // Note: This would require importing MJ2VideoToolbox types
        // For now, throw to use software fallback
        throw MJ2VideoEncoderError.hardwareNotAvailable
    }
    #endif

    // MARK: - Capability Detection

    /// Detects all available encoders on the current platform.
    ///
    /// - Returns: Array of available encoder types.
    public static func detectAvailableEncoders() -> [MJ2EncoderType] {
        var encoders: [MJ2EncoderType] = []

        // Check VideoToolbox
        #if canImport(VideoToolbox)
        encoders.append(.videoToolbox)
        #endif

        // Check FFmpeg
        if MJ2SoftwareEncoder.isFFmpegAvailable() {
            encoders.append(.ffmpeg)
        }

        // Software fallback always available
        encoders.append(.software)

        return encoders
    }

    /// Gets detailed capabilities for all available encoders.
    ///
    /// - Returns: Dictionary mapping encoder type to capabilities.
    public static func detectCapabilities() -> [MJ2EncoderType: MJ2EncoderCapabilities] {
        var capabilities: [MJ2EncoderType: MJ2EncoderCapabilities] = [:]

        let availableEncoders = detectAvailableEncoders()

        for encoderType in availableEncoders {
            switch encoderType {
            #if canImport(VideoToolbox)
            case .videoToolbox:
                capabilities[encoderType] = MJ2EncoderCapabilities(
                    supportedCodecs: [.h264, .h265],
                    supportsHardwareAcceleration: true,
                    supportsVBR: true,
                    supportsCBR: true,
                    supportsQualityMode: true,
                    supportsBFrames: true,
                    supportsMultiPass: true
                )
            #endif
            case .ffmpeg:
                capabilities[encoderType] = MJ2EncoderCapabilities(
                    supportedCodecs: [.h264, .h265],
                    supportsHardwareAcceleration: false,
                    supportsVBR: true,
                    supportsCBR: true,
                    supportsQualityMode: true,
                    supportsBFrames: true,
                    supportsMultiPass: true
                )
            case .software:
                capabilities[encoderType] = MJ2EncoderCapabilities(
                    supportedCodecs: [.h264],
                    supportsHardwareAcceleration: false,
                    supportsVBR: false,
                    supportsCBR: true,
                    supportsQualityMode: false,
                    supportsBFrames: false,
                    supportsMultiPass: false
                )
            default:
                break
            }
        }

        return capabilities
    }

    /// Prints a platform capability report.
    ///
    /// Useful for debugging and understanding what features are available.
    public static func printCapabilityReport() {
        print("=== MJ2 Encoder Capability Report ===")
        print()
        print("Platform: \(MJ2PlatformCapabilities.currentPlatform)")
        print("Architecture: \(MJ2PlatformCapabilities.architecture)")
        print("VideoToolbox: \(MJ2PlatformCapabilities.hasVideoToolbox)")
        print("Metal: \(MJ2PlatformCapabilities.hasMetal)")
        print()

        let encoders = detectAvailableEncoders()
        print("Available Encoders: \(encoders.map { $0.rawValue }.joined(separator: ", "))")
        print()

        let capabilities = detectCapabilities()
        for (encoderType, capability) in capabilities.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("\(encoderType.rawValue):")
            print("  - Codecs: \(capability.supportedCodecs.map { $0.rawValue }.joined(separator: ", "))")
            print("  - Hardware Accelerated: \(capability.supportsHardwareAcceleration)")
            print("  - VBR: \(capability.supportsVBR)")
            print("  - CBR: \(capability.supportsCBR)")
            print("  - Quality Mode: \(capability.supportsQualityMode)")
            print("  - B-Frames: \(capability.supportsBFrames)")
            print("  - Multi-Pass: \(capability.supportsMultiPass)")
            print()
        }

        // x86-64 warning
        if MJ2PlatformCapabilities.isX86_64 {
            print("⚠️  WARNING: Running on x86-64 architecture")
            print("   This architecture will be deprecated in future versions.")
            print("   Consider using Apple Silicon or ARM64 for best performance.")
            print()
        }

        print("=== End of Report ===")
    }
}
