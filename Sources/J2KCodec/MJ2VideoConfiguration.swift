//
// MJ2VideoConfiguration.swift
// J2KSwift
//
/// # MJ2VideoConfiguration
///
/// Common configuration types for Motion JPEG 2000 video transcoding.
///
/// This module provides shared types and configurations used across different
/// video encoder and decoder implementations (VideoToolbox, FFmpeg, software, etc.).

import Foundation
import J2KCore

// MARK: - Video Codec Type

/// Supported video codec types for transcoding.
public enum MJ2VideoCodec: String, Sendable, Hashable, CaseIterable {
    /// H.264 (AVC) codec.
    case h264 = "H.264"

    /// H.265 (HEVC) codec.
    case h265 = "H.265"

    /// Motion JPEG 2000 codec.
    case mj2 = "MJ2"

    var description: String {
        switch self {
        case .h264:
            return "H.264 (AVC)"
        case .h265:
            return "H.265 (HEVC)"
        case .mj2:
            return "Motion JPEG 2000"
        }
    }
}

// MARK: - Quality Configuration

/// Quality configuration for transcoding operations.
public struct MJ2TranscodingQuality: Sendable {
    /// Quality mode.
    public enum Mode: Sendable {
        /// Bitrate-based encoding.
        case bitrate(Int)

        /// Quality-based encoding (0.0-1.0, higher is better).
        case quality(Double)

        /// Constant quantization parameter.
        case constantQP(Int)
    }

    /// Quality mode.
    public var mode: Mode

    /// Allow encoder to use multiple passes.
    public var allowMultiPass: Bool

    /// Creates a quality configuration.
    public init(mode: Mode, allowMultiPass: Bool = false) {
        self.mode = mode
        self.allowMultiPass = allowMultiPass
    }

    /// High quality preset (suitable for archival).
    public static let high = MJ2TranscodingQuality(mode: .quality(0.9), allowMultiPass: true)

    /// Medium quality preset (balanced).
    public static let medium = MJ2TranscodingQuality(mode: .quality(0.7), allowMultiPass: false)

    /// Low quality preset (suitable for previews).
    public static let low = MJ2TranscodingQuality(mode: .quality(0.5), allowMultiPass: false)

    /// Bitrate preset for 1080p video (5 Mbps).
    public static let bitrate1080p = MJ2TranscodingQuality(mode: .bitrate(5_000_000))

    /// Bitrate preset for 720p video (3 Mbps).
    public static let bitrate720p = MJ2TranscodingQuality(mode: .bitrate(3_000_000))
}

// MARK: - Performance Configuration

/// Performance trade-off configuration.
public struct MJ2PerformanceConfiguration: Sendable {
    /// Performance priority.
    public enum Priority: Sendable {
        /// Prioritize encoding speed (lower quality).
        case speed

        /// Balance speed and quality.
        case balanced

        /// Prioritize quality (slower encoding).
        case quality
    }

    /// Performance priority.
    public var priority: Priority

    /// Allow hardware acceleration if available.
    public var allowHardwareAcceleration: Bool

    /// Maximum number of threads to use (nil = automatic).
    public var maxThreads: Int?

    /// Creates a performance configuration.
    public init(
        priority: Priority = .balanced,
        allowHardwareAcceleration: Bool = true,
        maxThreads: Int? = nil
    ) {
        self.priority = priority
        self.allowHardwareAcceleration = allowHardwareAcceleration
        self.maxThreads = maxThreads
    }

    /// Real-time preset (prioritize speed).
    public static let realtime = MJ2PerformanceConfiguration(
        priority: .speed,
        allowHardwareAcceleration: true
    )

    /// Balanced preset.
    public static let balanced = MJ2PerformanceConfiguration(
        priority: .balanced,
        allowHardwareAcceleration: true
    )

    /// High quality preset (slow).
    public static let highQuality = MJ2PerformanceConfiguration(
        priority: .quality,
        allowHardwareAcceleration: true
    )
}

// MARK: - Platform Detection

/// Platform capability detection for video transcoding.
public struct MJ2PlatformCapabilities: Sendable {
    /// Platform type.
    public enum Platform: Sendable {
        /// Apple platform with VideoToolbox support.
        case apple

        /// Linux platform.
        case linux

        /// Windows platform.
        case windows

        /// Other Unix-like platform.
        case unix

        /// Unknown platform.
        case unknown
    }

    /// Current platform.
    public static var currentPlatform: Platform {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        return .apple
        #elseif os(Linux)
        return .linux
        #elseif os(Windows)
        return .windows
        #else
        return .unix
        #endif
    }

    /// Indicates whether VideoToolbox is available on this platform.
    public static var hasVideoToolbox: Bool {
        #if canImport(VideoToolbox)
        return true
        #else
        return false
        #endif
    }

    /// Indicates whether Metal is available on this platform.
    public static var hasMetal: Bool {
        #if canImport(Metal)
        return true
        #else
        return false
        #endif
    }

    /// Current CPU architecture.
    public static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #elseif arch(arm)
        return "arm"
        #else
        return "unknown"
        #endif
    }

    /// Indicates whether the current architecture is ARM64.
    public static var isARM64: Bool {
        architecture == "arm64"
    }

    /// Indicates whether the current architecture is x86_64.
    public static var isX86_64: Bool {
        architecture == "x86_64"
    }
}
