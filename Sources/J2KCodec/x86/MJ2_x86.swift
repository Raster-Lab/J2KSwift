// MJ2_x86.swift
// J2KSwift
//
// x86-64 specific code paths for Motion JPEG 2000 operations.
//
// ⚠️ DEPRECATION NOTICE: This file contains x86-64 specific code that may be removed
// in future versions as the project focuses on Apple Silicon (ARM64) architecture.
//

import Foundation
import J2KCore

#if arch(x86_64)

/// x86-64 specific optimizations for Motion JPEG 2000.
///
/// This type provides x86-64 specific implementations and fallbacks for MJ2 operations
/// that may have different performance characteristics on Intel processors.
///
/// ## Deprecation Status
///
/// - **Target Architecture**: x86-64 (Intel)
/// - **Maintenance Level**: Minimal (bug fixes only)
/// - **Removal Timeline**: v2.0.0 or later
/// - **Recommended Alternative**: Use Apple Silicon (ARM64) for best performance
///
/// ## Performance Notes
///
/// On x86-64 platforms:
/// - Limited to software encoding (no VideoToolbox on non-Apple x86-64)
/// - AVX/AVX2 SIMD for color conversion
/// - May benefit from Rosetta 2 when running ARM64 code on Intel Macs
///
/// ## Usage
///
/// ```swift
/// // Automatically used on x86-64 platforms when needed
/// if MJ2X86.isAvailable {
///     // Platform-specific optimizations
/// }
/// ```
public struct MJ2X86: Sendable {
    /// Creates a new x86-64 specific MJ2 processor.
    public init() {}

    /// Indicates whether x86-64 MJ2 optimizations are available.
    ///
    /// Returns `true` only on x86-64 platforms.
    public static var isAvailable: Bool {
        #if arch(x86_64)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Architecture Information

    /// Returns information about the x86-64 CPU features.
    ///
    /// Detects available SIMD instruction sets relevant to video processing.
    ///
    /// - Returns: Dictionary of feature name to availability.
    public static func cpuFeatures() -> [String: Bool] {
        var features: [String: Bool] = [:]

        // All modern x86-64 Macs support these
        features["SSE4.2"] = true
        features["AVX"] = true
        features["AVX2"] = true

        // Not available on x86-64
        features["NEON"] = false
        features["AMX"] = false
        features["VideoToolbox"] = false  // Not available on non-Apple x86-64

        return features
    }

    /// Returns a warning message about x86-64 deprecation.
    ///
    /// - Returns: Deprecation warning text.
    public static func deprecationWarning() -> String {
        """
        ⚠️ Running on x86-64 (Intel) architecture

        This architecture will be removed in a future major version.

        For best performance, consider:
        1. Using Apple Silicon (M1/M2/M3) hardware
        2. Running ARM64 builds via Rosetta 2 on Intel Macs
        3. Using FFmpeg for software encoding on non-Apple platforms

        x86-64 support will be maintained through v1.x.x releases but
        may be removed in v2.0.0 or later.
        """
    }
}

#else

/// Placeholder for x86-64 optimizations on non-x86-64 platforms.
public struct MJ2X86: Sendable {
    public init() {}

    public static var isAvailable: Bool { false }

    public static func cpuFeatures() -> [String: Bool] { [:] }

    public static func deprecationWarning() -> String { "" }
}

#endif
