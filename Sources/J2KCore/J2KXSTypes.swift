// J2KXSTypes.swift
// J2KSwift
//
// JPEG XS (ISO/IEC 21122) exploration types.
//
// JPEG XS (ISO/IEC 21122) is a lightweight, visually lossless codec. This file
// provides exploratory type definitions as part of Phase 19's JPEG XS investigation.

import Foundation

// MARK: - J2KXSProfile

/// JPEG XS profile, controlling the number of components that may be encoded.
///
/// Profiles correspond to increasing complexity and component capacity as
/// defined in ISO/IEC 21122.
public enum J2KXSProfile: Sendable, Equatable, CaseIterable {
    /// Light profile — single-component images only.
    case light
    /// Main profile — up to 4 components (e.g. RGBA).
    case main
    /// High profile — up to 16 components (e.g. hyperspectral).
    case high

    /// The maximum number of components supported by this profile.
    public var maxComponents: Int {
        switch self {
        case .light: return 1
        case .main:  return 4
        case .high:  return 16
        }
    }
}

// MARK: - J2KXSLevel

/// JPEG XS level, specifying the maximum pixel throughput rate.
public enum J2KXSLevel: Sendable, Equatable, CaseIterable {
    /// Sub-level 0 — up to 1 Gpixel/s.
    case sublevel0
    /// Sub-level 1 — up to 2 Gpixel/s.
    case sublevel1
    /// Sub-level 2 — up to 4 Gpixel/s.
    case sublevel2
    /// Sub-level 3 — up to 8 Gpixel/s.
    case sublevel3

    /// The maximum pixel throughput rate in giga-pixels per second.
    public var pixelRateGigaPixelsPerSecond: Double {
        switch self {
        case .sublevel0: return 1.0
        case .sublevel1: return 2.0
        case .sublevel2: return 4.0
        case .sublevel3: return 8.0
        }
    }
}

// MARK: - J2KXSSliceHeight

/// JPEG XS slice height, determining the vertical granularity of independent
/// coding units within a frame.
public enum J2KXSSliceHeight: Sendable, Equatable, CaseIterable {
    /// 16-line slices.
    case height16
    /// 32-line slices.
    case height32
    /// 64-line slices.
    case height64

    /// The slice height in pixels.
    public var pixels: Int {
        switch self {
        case .height16: return 16
        case .height32: return 32
        case .height64: return 64
        }
    }
}

// MARK: - J2KXSConfiguration

/// Configuration for a JPEG XS codec instance.
///
/// Combines a profile, level, slice height, and target bit-rate into a
/// single configuration value. Use the static presets for common scenarios.
///
/// Example:
/// ```swift
/// let config = J2KXSConfiguration.preview
/// print(config.targetBitsPerPixel) // 3.0
/// ```
public struct J2KXSConfiguration: Sendable, Equatable {
    /// The JPEG XS profile.
    public var profile: J2KXSProfile

    /// The JPEG XS level.
    public var level: J2KXSLevel

    /// The vertical slice height.
    public var sliceHeight: J2KXSSliceHeight

    /// The target compressed bit rate in bits per pixel.
    public var targetBitsPerPixel: Double

    /// Creates a JPEG XS configuration.
    ///
    /// - Parameters:
    ///   - profile: The profile.
    ///   - level: The level.
    ///   - sliceHeight: The slice height.
    ///   - targetBitsPerPixel: Target bits per pixel (clamped to > 0).
    public init(
        profile: J2KXSProfile,
        level: J2KXSLevel,
        sliceHeight: J2KXSSliceHeight,
        targetBitsPerPixel: Double
    ) {
        self.profile = profile
        self.level = level
        self.sliceHeight = sliceHeight
        self.targetBitsPerPixel = max(0.01, targetBitsPerPixel)
    }

    /// Preview preset — Main profile, Sub-level 1, 32-line slices, 3.0 bpp.
    ///
    /// Suitable for preview monitoring and editorial workflows where a low bit
    /// rate with acceptable visual quality is required.
    public static let preview = J2KXSConfiguration(
        profile: .main,
        level: .sublevel1,
        sliceHeight: .height32,
        targetBitsPerPixel: 3.0
    )

    /// Production preset — High profile, Sub-level 2, 32-line slices, 6.0 bpp.
    ///
    /// Suitable for high-fidelity post-production workflows with up to
    /// 16 components and 4 Gpixel/s throughput.
    public static let production = J2KXSConfiguration(
        profile: .high,
        level: .sublevel2,
        sliceHeight: .height32,
        targetBitsPerPixel: 6.0
    )
}

// MARK: - J2KXSCapabilities

/// Describes the JPEG XS capabilities of the current runtime environment.
///
/// During Phase 19 this is an **exploration** type only; `isAvailable` is
/// always `false` because a full JPEG XS implementation has not yet been
/// completed. The capabilities object documents which profiles are planned.
///
/// Example:
/// ```swift
/// let caps = J2KXSCapabilities.current
/// print(caps.isAvailable)   // false
/// print(caps.version)       // "exploration-2.2.0"
/// ```
public struct J2KXSCapabilities: Sendable {
    /// Whether a JPEG XS codec is available in this build.
    ///
    /// Always `false` during the exploration phase.
    public let isAvailable: Bool

    /// The profiles supported (or planned) by this build.
    public let supportedProfiles: [J2KXSProfile]

    /// A human-readable version or status string for the JPEG XS module.
    public let version: String

    /// Creates a capabilities descriptor.
    ///
    /// - Parameters:
    ///   - isAvailable: Whether the codec is available.
    ///   - supportedProfiles: Supported or planned profiles.
    ///   - version: Version/status string.
    public init(isAvailable: Bool, supportedProfiles: [J2KXSProfile], version: String) {
        self.isAvailable = isAvailable
        self.supportedProfiles = supportedProfiles
        self.version = version
    }

    /// Capabilities for the current build.
    ///
    /// From Phase 20 onwards the codec is available for all three profiles.
    public static let current = J2KXSCapabilities(
        isAvailable: true,
        supportedProfiles: [.light, .main, .high],
        version: "2.3.0"
    )
}
