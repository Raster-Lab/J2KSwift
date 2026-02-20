//
// MJ2Configuration.swift
// J2KSwift
//
/// # MJ2Configuration
///
/// Configuration types for Motion JPEG 2000 file creation.
///
/// This module provides configuration options for creating Motion JPEG 2000 files,
/// including frame rate, timescale, quality, and profile settings.

import Foundation
import J2KCore
import J2KCodec

// MARK: - MJ2 Profile

/// Motion JPEG 2000 profiles.
///
/// Profiles define constraints and capabilities for MJ2 files to ensure
/// compatibility with different playback systems and applications.
public enum MJ2Profile: String, Sendable {
    /// Simple Profile - Basic MJ2 support
    ///
    /// Constraints:
    /// - Maximum resolution: 1920×1080
    /// - Maximum frame rate: 30 fps
    /// - Single video track
    case simple = "mj2s"

    /// General Profile - Full MJ2 support
    ///
    /// No specific constraints beyond JPEG 2000 Part 1 limitations.
    case general = "mjp2"

    /// Broadcast Profile - Professional broadcast applications
    ///
    /// Optimized for:
    /// - High bit rates
    /// - Low latency
    /// - Frame-accurate editing
    case broadcast = "broadcast"

    /// Cinema Profile - Digital cinema applications
    ///
    /// Optimized for:
    /// - High resolution (2K, 4K, 8K)
    /// - High quality
    /// - Color fidelity
    case cinema = "cinema"

    /// Returns the brand identifier for this profile.
    public var brandIdentifier: String {
        switch self {
        case .simple: return "mj2s"
        case .general: return "mjp2"
        case .broadcast: return "mjp2"
        case .cinema: return "mjp2"
        }
    }

    /// Returns whether this profile requires specific encoding constraints.
    public var hasConstraints: Bool {
        switch self {
        case .simple, .broadcast, .cinema: return true
        case .general: return false
        }
    }
}

// MARK: - MJ2 Timescale Configuration

/// Time scale configuration for MJ2 files.
///
/// The timescale defines the number of time units per second and is used
/// for all time-based calculations in the MJ2 file.
public struct MJ2TimescaleConfiguration: Sendable {
    /// Time units per second.
    public let timescale: UInt32

    /// Frame duration in time units.
    public let frameDuration: UInt32

    /// Creates a timescale configuration.
    ///
    /// - Parameters:
    ///   - timescale: Time units per second (e.g., 24000, 30000, 90000).
    ///   - frameDuration: Frame duration in time units.
    public init(timescale: UInt32, frameDuration: UInt32) {
        self.timescale = timescale
        self.frameDuration = frameDuration
    }

    /// Creates a timescale configuration from a frame rate.
    ///
    /// - Parameter frameRate: Frames per second (e.g., 24.0, 29.97, 30.0, 60.0).
    /// - Returns: A timescale configuration for the given frame rate.
    public static func from(frameRate: Double) -> MJ2TimescaleConfiguration {
        // Use common timescales
        let commonTimescales: [(rate: Double, timescale: UInt32, duration: UInt32)] = [
            (23.976, 24000, 1001),  // 23.976 fps (film)
            (24.0, 24000, 1000),     // 24 fps
            (25.0, 25000, 1000),     // 25 fps (PAL)
            (29.97, 30000, 1001),    // 29.97 fps (NTSC)
            (30.0, 30000, 1000),     // 30 fps
            (50.0, 50000, 1000),     // 50 fps
            (59.94, 60000, 1001),    // 59.94 fps
            (60.0, 60000, 1000),     // 60 fps
        ]

        // Find closest match
        let epsilon = 0.01
        if let match = commonTimescales.first(where: { abs($0.rate - frameRate) < epsilon }) {
            return MJ2TimescaleConfiguration(timescale: match.timescale, frameDuration: match.duration)
        }

        // Use generic timescale for non-standard frame rates
        let timescale: UInt32 = 90000 // Common for video
        let duration = UInt32(Double(timescale) / frameRate)
        return MJ2TimescaleConfiguration(timescale: timescale, frameDuration: duration)
    }

    /// Calculates the frame rate from this timescale configuration.
    public var frameRate: Double {
        guard frameDuration > 0 else { return 0.0 }
        return Double(timescale) / Double(frameDuration)
    }
}

// MARK: - MJ2 Metadata

/// Metadata for MJ2 files.
public struct MJ2Metadata: Sendable {
    /// Movie title.
    public var title: String?

    /// Movie author/creator.
    public var author: String?

    /// Copyright information.
    public var copyright: String?

    /// Movie description.
    public var description: String?

    /// Creation date.
    public var creationDate: Date?

    /// Modification date.
    public var modificationDate: Date?

    /// Creates metadata with optional fields.
    public init(
        title: String? = nil,
        author: String? = nil,
        copyright: String? = nil,
        description: String? = nil,
        creationDate: Date? = nil,
        modificationDate: Date? = nil
    ) {
        self.title = title
        self.author = author
        self.copyright = copyright
        self.description = description
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

// MARK: - MJ2 Audio Track Configuration

/// Audio track configuration (structure only, not implemented).
///
/// This structure defines the audio track parameters but audio encoding
/// and muxing is not yet implemented. Reserved for future expansion.
public struct MJ2AudioTrackConfiguration: Sendable {
    /// Sample rate in Hz (e.g., 44100, 48000).
    public let sampleRate: UInt32

    /// Number of audio channels (e.g., 1 for mono, 2 for stereo).
    public let channels: UInt16

    /// Bits per sample (e.g., 16, 24).
    public let bitsPerSample: UInt16

    /// Creates an audio track configuration.
    ///
    /// - Note: Audio encoding is not yet implemented. This is a placeholder.
    public init(sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitsPerSample = bitsPerSample
    }
}

// MARK: - MJ2 Creation Configuration

/// Configuration for creating Motion JPEG 2000 files.
///
/// Specifies all parameters needed to create an MJ2 file from an image sequence,
/// including frame rate, quality, profile, and metadata.
///
/// Example:
/// ```swift
/// let config = MJ2CreationConfiguration(
///     frameRate: 30.0,
///     profile: .simple,
///     encodingQuality: 0.95
/// )
/// ```
public struct MJ2CreationConfiguration: Sendable {
    /// MJ2 profile to use.
    public let profile: MJ2Profile

    /// Timescale configuration.
    public let timescale: MJ2TimescaleConfiguration

    /// JPEG 2000 encoding configuration.
    public let encodingConfiguration: J2KEncodingConfiguration

    /// Metadata to include in the file.
    public let metadata: MJ2Metadata

    /// Audio track configuration (if any).
    public let audioTrack: MJ2AudioTrackConfiguration?

    /// Whether to use 64-bit chunk offsets (required for files >4GB).
    public let use64BitOffsets: Bool

    /// Maximum number of frames to buffer in memory during encoding.
    public let maxFrameBufferCount: Int

    /// Whether to enable parallel frame encoding.
    public let enableParallelEncoding: Bool

    /// Number of frames to encode in parallel (0 = auto-detect).
    public let parallelEncodingCount: Int

    /// Creates a configuration with all parameters.
    ///
    /// - Parameters:
    ///   - profile: MJ2 profile (default: .general).
    ///   - timescale: Timescale configuration.
    ///   - encodingConfiguration: JPEG 2000 encoding configuration.
    ///   - metadata: File metadata (default: empty).
    ///   - audioTrack: Audio track configuration (default: nil).
    ///   - use64BitOffsets: Use 64-bit chunk offsets (default: false).
    ///   - maxFrameBufferCount: Maximum frames to buffer (default: 10).
    ///   - enableParallelEncoding: Enable parallel frame encoding (default: true).
    ///   - parallelEncodingCount: Parallel encoding count (default: 0 for auto).
    public init(
        profile: MJ2Profile = .general,
        timescale: MJ2TimescaleConfiguration,
        encodingConfiguration: J2KEncodingConfiguration,
        metadata: MJ2Metadata = MJ2Metadata(),
        audioTrack: MJ2AudioTrackConfiguration? = nil,
        use64BitOffsets: Bool = false,
        maxFrameBufferCount: Int = 10,
        enableParallelEncoding: Bool = true,
        parallelEncodingCount: Int = 0
    ) {
        self.profile = profile
        self.timescale = timescale
        self.encodingConfiguration = encodingConfiguration
        self.metadata = metadata
        self.audioTrack = audioTrack
        self.use64BitOffsets = use64BitOffsets
        self.maxFrameBufferCount = max(1, maxFrameBufferCount)
        self.enableParallelEncoding = enableParallelEncoding
        self.parallelEncodingCount = max(0, parallelEncodingCount)
    }

    /// Creates a configuration from a frame rate and quality.
    ///
    /// - Parameters:
    ///   - frameRate: Frames per second.
    ///   - profile: MJ2 profile (default: .general).
    ///   - quality: Encoding quality 0.0-1.0 (default: 0.95).
    ///   - lossless: Whether to use lossless encoding (default: false).
    /// - Returns: A configuration for the specified parameters.
    public static func from(
        frameRate: Double,
        profile: MJ2Profile = .general,
        quality: Double = 0.95,
        lossless: Bool = false
    ) -> MJ2CreationConfiguration {
        let timescale = MJ2TimescaleConfiguration.from(frameRate: frameRate)
        let encodingConfig = J2KEncodingConfiguration(quality: quality, lossless: lossless)

        return MJ2CreationConfiguration(
            profile: profile,
            timescale: timescale,
            encodingConfiguration: encodingConfig
        )
    }

    /// Validates the configuration for the given image dimensions.
    ///
    /// - Parameters:
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    /// - Throws: ``J2KError/invalidParameter(_:)`` if configuration violates profile constraints.
    public func validate(width: Int, height: Int) throws {
        // Check Simple Profile constraints
        if profile == .simple {
            if width > 1920 || height > 1080 {
                throw J2KError.invalidParameter(
                    "Simple Profile requires resolution ≤ 1920×1080, got \(width)×\(height)"
                )
            }

            if timescale.frameRate > 30.0 {
                throw J2KError.invalidParameter(
                    "Simple Profile requires frame rate ≤ 30 fps, got \(timescale.frameRate)"
                )
            }
        }

        // Validate timescale
        if timescale.timescale == 0 || timescale.frameDuration == 0 {
            throw J2KError.invalidParameter("Invalid timescale configuration")
        }

        // Validate frame buffer
        if maxFrameBufferCount < 1 {
            throw J2KError.invalidParameter("maxFrameBufferCount must be at least 1")
        }
    }
}
