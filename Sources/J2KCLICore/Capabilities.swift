//
// Capabilities.swift
// J2KSwift
//
/// Capabilities and diagnostics command — display library capabilities,
/// GPU information, and platform details.

import Foundation
import J2KCore

extension J2KCLI {

    /// Display library capabilities and platform information.
    static func capabilitiesCommand(_ args: [String]) async throws {
        let options = parseArguments(args)
        let jsonOutput = options["json"] != nil
        let quiet = options["quiet"] != nil

        // Build capabilities information
        var caps: [String: Any] = [:]

        // Library version
        caps["version"] = getVersion()

        // Platform information
        #if os(macOS)
        let platform = "macOS"
        #elseif os(Linux)
        let platform = "Linux"
        #elseif os(iOS)
        let platform = "iOS"
        #elseif os(tvOS)
        let platform = "tvOS"
        #elseif os(watchOS)
        let platform = "watchOS"
        #elseif os(visionOS)
        let platform = "visionOS"
        #else
        let platform = "Unknown"
        #endif
        caps["platform"] = platform

        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        caps["architecture"] = architecture

        // Swift version
        #if swift(>=6.2)
        let swiftVersion = "6.2+"
        #elseif swift(>=6.0)
        let swiftVersion = "6.0+"
        #elseif swift(>=5.9)
        let swiftVersion = "5.9+"
        #else
        let swiftVersion = "5.x"
        #endif
        caps["swiftVersion"] = swiftVersion

        // Supported codecs
        caps["codecs"] = [
            "j2k-lossless": true,
            "j2k-lossy": true,
            "htj2k-lossless": true,
            "htj2k-lossy": true
        ]

        // Supported formats
        caps["formats"] = [
            "input": ["pgm", "ppm", "pnm", "raw"],
            "output": ["pgm", "ppm", "raw"],
            "codestream": ["j2k", "jp2", "jpx", "jph", "j2c"]
        ]

        // Acceleration backends
        var acceleration: [String: Any] = [:]

        #if canImport(Accelerate)
        acceleration["accelerate"] = true
        #else
        acceleration["accelerate"] = false
        #endif

        #if canImport(Metal)
        acceleration["metal"] = true
        #else
        acceleration["metal"] = false
        #endif

        // SIMD support
        #if arch(arm64)
        acceleration["simd"] = "NEON"
        #elseif arch(x86_64)
        acceleration["simd"] = "SSE/AVX"
        #else
        acceleration["simd"] = "none"
        #endif

        caps["acceleration"] = acceleration

        // Modules
        caps["modules"] = [
            "J2KCore": true,
            "J2KCodec": true,
            "J2KFileFormat": true,
            "J2KAccelerate": true,
            "J2K3D": true,
            "JPIP": true,
            "J2KMetal": true,
            "J2KVulkan": true,
            "J2KXS": true
        ]

        // Features
        caps["features"] = [
            "losslessCompression": true,
            "lossyCompression": true,
            "htj2k": true,
            "jp3d": true,
            "jpip": true,
            "multiComponentTransform": true,
            "regionOfInterest": true,
            "progressiveDecoding": true,
            "parallelProcessing": true,
            "batchProcessing": true
        ]

        // Output
        if jsonOutput {
            printJSON(caps)
        } else if !quiet {
            print("J2KSwift Library Capabilities")
            print("═════════════════════════════")
            print("")
            print("Version:        \(caps["version"] ?? "unknown")")
            print("Platform:       \(platform)")
            print("Architecture:   \(architecture)")
            print("Swift Version:  \(swiftVersion)")
            print("")
            print("Codecs:")
            print("  ✓ JPEG 2000 Part 1 Lossless (5/3 DWT)")
            print("  ✓ JPEG 2000 Part 1 Lossy (9/7 DWT)")
            print("  ✓ HTJ2K Part 15 Lossless")
            print("  ✓ HTJ2K Part 15 Lossy")
            print("")
            print("File Formats:")
            print("  Input:  PGM, PPM, PNM, RAW")
            print("  Output: PGM, PPM, RAW")
            print("  JPEG 2000: J2K, JP2, JPX, JPH, J2C")
            print("")
            print("Acceleration:")
            #if canImport(Accelerate)
            print("  ✓ Apple Accelerate framework")
            #else
            print("  ✗ Apple Accelerate framework (not available)")
            #endif
            #if canImport(Metal)
            print("  ✓ Metal GPU compute")
            #else
            print("  ✗ Metal GPU compute (not available)")
            #endif
            #if arch(arm64)
            print("  ✓ NEON SIMD")
            #elseif arch(x86_64)
            print("  ✓ SSE/AVX SIMD")
            #endif
            print("")
            print("Modules:")
            print("  ✓ J2KCore        — Core types and utilities")
            print("  ✓ J2KCodec       — Encoding/decoding")
            print("  ✓ J2KFileFormat  — File format support")
            print("  ✓ J2KAccelerate  — Hardware acceleration")
            print("  ✓ J2K3D          — 3D volumetric (JP3D)")
            print("  ✓ JPIP           — Network streaming")
            print("  ✓ J2KMetal       — Metal GPU compute")
            print("  ✓ J2KVulkan      — Vulkan GPU compute")
            print("  ✓ J2KXS          — JPEG XS support")
            print("")
            print("Features:")
            print("  ✓ Multi-file batch processing")
            print("  ✓ Parallel execution")
            print("  ✓ Region-of-interest encoding/decoding")
            print("  ✓ Progressive quality layers")
            print("  ✓ Multi-component transform")
            print("  ✓ Image comparison metrics (PSNR, MSE, MAE)")
            print("  ✓ Lossless transcoding (J2K ↔ HTJ2K)")
            print("  ✓ 3D volumetric compression (JP3D)")
            print("  ✓ JPIP network streaming")
        }
    }

    /// List available GPU devices.
    static func listGPUs() {
        #if canImport(Metal)
        print("GPU Devices (Metal):")
        print("  Note: Use --gpu flag to enable Metal acceleration")
        // Metal device enumeration would go here
        print("  (Metal device enumeration requires Metal framework import)")
        #else
        print("GPU: No GPU acceleration available on this platform")
        #endif
    }
}
