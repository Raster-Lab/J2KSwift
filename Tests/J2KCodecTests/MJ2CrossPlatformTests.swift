/// # MJ2CrossPlatformTests
///
/// Tests for cross-platform video encoder fallbacks and capabilities.

import XCTest
@testable import J2KCodec
import J2KCore

final class MJ2CrossPlatformTests: XCTestCase {
    
    // MARK: - Platform Detection Tests
    
    func testPlatformDetection() {
        // Verify platform is correctly detected
        let platform = MJ2PlatformCapabilities.currentPlatform
        
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        XCTAssertEqual(platform, .apple, "Should detect Apple platform")
        #elseif os(Linux)
        XCTAssertEqual(platform, .linux, "Should detect Linux platform")
        #elseif os(Windows)
        XCTAssertEqual(platform, .windows, "Should detect Windows platform")
        #endif
    }
    
    func testArchitectureDetection() {
        let architecture = MJ2PlatformCapabilities.architecture
        
        #if arch(arm64)
        XCTAssertEqual(architecture, "arm64", "Should detect ARM64 architecture")
        XCTAssertTrue(MJ2PlatformCapabilities.isARM64)
        XCTAssertFalse(MJ2PlatformCapabilities.isX86_64)
        #elseif arch(x86_64)
        XCTAssertEqual(architecture, "x86_64", "Should detect x86_64 architecture")
        XCTAssertTrue(MJ2PlatformCapabilities.isX86_64)
        XCTAssertFalse(MJ2PlatformCapabilities.isARM64)
        #endif
    }
    
    func testVideoToolboxAvailability() {
        #if canImport(VideoToolbox)
        XCTAssertTrue(MJ2PlatformCapabilities.hasVideoToolbox, "VideoToolbox should be available on Apple platforms")
        #else
        XCTAssertFalse(MJ2PlatformCapabilities.hasVideoToolbox, "VideoToolbox should not be available on non-Apple platforms")
        #endif
    }
    
    func testMetalAvailability() {
        #if canImport(Metal)
        XCTAssertTrue(MJ2PlatformCapabilities.hasMetal, "Metal should be available on platforms that support it")
        #else
        XCTAssertFalse(MJ2PlatformCapabilities.hasMetal, "Metal should not be available on unsupported platforms")
        #endif
    }
    
    // MARK: - Encoder Detection Tests
    
    func testEncoderDetection() {
        let encoders = MJ2EncoderFactory.detectAvailableEncoders()
        
        // Software fallback should always be available
        XCTAssertTrue(encoders.contains(.software), "Software encoder should always be available")
        
        #if canImport(VideoToolbox)
        // VideoToolbox should be available on Apple platforms
        XCTAssertTrue(encoders.contains(.videoToolbox), "VideoToolbox encoder should be available on Apple platforms")
        #endif
        
        // FFmpeg may or may not be installed
        if encoders.contains(.ffmpeg) {
            print("FFmpeg is available on this system")
        } else {
            print("FFmpeg is not available on this system")
        }
    }
    
    func testCapabilityDetection() {
        let capabilities = MJ2EncoderFactory.detectCapabilities()
        
        // Should have at least software encoder capabilities
        XCTAssertFalse(capabilities.isEmpty, "Should detect at least one encoder")
        
        // Verify software encoder capabilities
        if let softwareCap = capabilities[.software] {
            XCTAssertTrue(softwareCap.supportedCodecs.contains(.h264), "Software encoder should support H.264")
            XCTAssertFalse(softwareCap.supportsHardwareAcceleration, "Software encoder should not be hardware accelerated")
        }
        
        #if canImport(VideoToolbox)
        // Verify VideoToolbox capabilities
        if let vtCap = capabilities[.videoToolbox] {
            XCTAssertTrue(vtCap.supportedCodecs.contains(.h264), "VideoToolbox should support H.264")
            XCTAssertTrue(vtCap.supportedCodecs.contains(.h265), "VideoToolbox should support H.265")
            XCTAssertTrue(vtCap.supportsHardwareAcceleration, "VideoToolbox should be hardware accelerated")
        }
        #endif
    }
    
    func testCapabilityReportPrinting() {
        // This test just verifies the report can be generated without crashing
        MJ2EncoderFactory.printCapabilityReport()
    }
    
    // MARK: - Configuration Tests
    
    func testQualityPresets() {
        // High quality
        let high = MJ2TranscodingQuality.high
        if case .quality(let value) = high.mode {
            XCTAssertEqual(value, 0.9, accuracy: 0.01)
            XCTAssertTrue(high.allowMultiPass)
        } else {
            XCTFail("High quality should use quality mode")
        }
        
        // Medium quality
        let medium = MJ2TranscodingQuality.medium
        if case .quality(let value) = medium.mode {
            XCTAssertEqual(value, 0.7, accuracy: 0.01)
            XCTAssertFalse(medium.allowMultiPass)
        } else {
            XCTFail("Medium quality should use quality mode")
        }
        
        // Low quality
        let low = MJ2TranscodingQuality.low
        if case .quality(let value) = low.mode {
            XCTAssertEqual(value, 0.5, accuracy: 0.01)
            XCTAssertFalse(low.allowMultiPass)
        } else {
            XCTFail("Low quality should use quality mode")
        }
    }
    
    func testBitratePresets() {
        // 1080p
        let bitrate1080p = MJ2TranscodingQuality.bitrate1080p
        if case .bitrate(let value) = bitrate1080p.mode {
            XCTAssertEqual(value, 5_000_000)
        } else {
            XCTFail("Bitrate preset should use bitrate mode")
        }
        
        // 720p
        let bitrate720p = MJ2TranscodingQuality.bitrate720p
        if case .bitrate(let value) = bitrate720p.mode {
            XCTAssertEqual(value, 3_000_000)
        } else {
            XCTFail("Bitrate preset should use bitrate mode")
        }
    }
    
    func testPerformancePresets() {
        let realtime = MJ2PerformanceConfiguration.realtime
        XCTAssertEqual(realtime.priority, .speed)
        XCTAssertTrue(realtime.allowHardwareAcceleration)
        
        let balanced = MJ2PerformanceConfiguration.balanced
        XCTAssertEqual(balanced.priority, .balanced)
        XCTAssertTrue(balanced.allowHardwareAcceleration)
        
        let highQuality = MJ2PerformanceConfiguration.highQuality
        XCTAssertEqual(highQuality.priority, .quality)
        XCTAssertTrue(highQuality.allowHardwareAcceleration)
    }
    
    // MARK: - Software Encoder Tests
    
    func testSoftwareEncoderCreation() {
        let config = MJ2SoftwareEncoderConfiguration.h264Default
        let encoder = MJ2SoftwareEncoder(configuration: config)
        
        XCTAssertFalse(encoder.isHardwareAccelerated)
        
        // Encoder type depends on FFmpeg availability
        if MJ2SoftwareEncoder.isFFmpegAvailable() {
            XCTAssertEqual(encoder.encoderType, .ffmpeg)
        } else {
            XCTAssertEqual(encoder.encoderType, .software)
        }
    }
    
    func testSoftwareEncoderCapabilities() async {
        let config = MJ2SoftwareEncoderConfiguration.h264Default
        let encoder = MJ2SoftwareEncoder(configuration: config)
        
        let capabilities = encoder.capabilities
        XCTAssertFalse(capabilities.supportedCodecs.isEmpty)
        XCTAssertFalse(capabilities.supportsHardwareAcceleration)
    }
    
    func testSoftwareEncoderLifecycle() async throws {
        let config = MJ2SoftwareEncoderConfiguration.h264Default
        let encoder = MJ2SoftwareEncoder(configuration: config)
        
        // Start encoding
        try await encoder.startEncoding()
        
        // Cancel without encoding
        await encoder.cancelEncoding()
    }
    
    func testSoftwareEncoderInvalidFrame() async throws {
        let config = MJ2SoftwareEncoderConfiguration.h264Default
        let encoder = MJ2SoftwareEncoder(configuration: config)
        
        try await encoder.startEncoding()
        
        // Create invalid frame (zero dimensions)
        let invalidFrame = J2KImage(width: 0, height: 0, components: 3, bitDepth: 8)
        
        do {
            _ = try await encoder.encode(invalidFrame)
            XCTFail("Should throw error for invalid frame")
        } catch MJ2VideoEncoderError.invalidDimensions {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        await encoder.cancelEncoding()
    }
    
    // MARK: - x86-64 Tests
    
    func testX86Availability() {
        #if arch(x86_64)
        XCTAssertTrue(MJ2X86.isAvailable, "MJ2X86 should be available on x86_64")
        
        let features = MJ2X86.cpuFeatures()
        XCTAssertTrue(features["SSE4.2"] ?? false)
        XCTAssertTrue(features["AVX"] ?? false)
        XCTAssertTrue(features["AVX2"] ?? false)
        XCTAssertFalse(features["NEON"] ?? true)
        XCTAssertFalse(features["AMX"] ?? true)
        
        let warning = MJ2X86.deprecationWarning()
        XCTAssertFalse(warning.isEmpty, "Should have deprecation warning")
        XCTAssertTrue(warning.contains("x86-64"))
        
        #else
        XCTAssertFalse(MJ2X86.isAvailable, "MJ2X86 should not be available on non-x86_64")
        #endif
    }
    
    // MARK: - Codec Tests
    
    func testVideoCodecCases() {
        XCTAssertEqual(MJ2VideoCodec.h264.rawValue, "H.264")
        XCTAssertEqual(MJ2VideoCodec.h265.rawValue, "H.265")
        XCTAssertEqual(MJ2VideoCodec.mj2.rawValue, "MJ2")
        
        XCTAssertEqual(MJ2VideoCodec.h264.description, "H.264 (AVC)")
        XCTAssertEqual(MJ2VideoCodec.h265.description, "H.265 (HEVC)")
        XCTAssertEqual(MJ2VideoCodec.mj2.description, "Motion JPEG 2000")
    }
    
    func testVideoCodecHashable() {
        let codecs: Set<MJ2VideoCodec> = [.h264, .h265, .mj2]
        XCTAssertEqual(codecs.count, 3)
        
        XCTAssertTrue(codecs.contains(.h264))
        XCTAssertTrue(codecs.contains(.h265))
        XCTAssertTrue(codecs.contains(.mj2))
    }
    
    func testVideoCodecCaseIterable() {
        let allCodecs = MJ2VideoCodec.allCases
        XCTAssertEqual(allCodecs.count, 3)
        XCTAssertTrue(allCodecs.contains(.h264))
        XCTAssertTrue(allCodecs.contains(.h265))
        XCTAssertTrue(allCodecs.contains(.mj2))
    }
    
    // MARK: - Protocol Tests
    
    func testEncoderTypeRawValues() {
        XCTAssertEqual(MJ2EncoderType.videoToolbox.rawValue, "VideoToolbox")
        XCTAssertEqual(MJ2EncoderType.x264.rawValue, "x264")
        XCTAssertEqual(MJ2EncoderType.x265.rawValue, "x265")
        XCTAssertEqual(MJ2EncoderType.ffmpeg.rawValue, "FFmpeg")
        XCTAssertEqual(MJ2EncoderType.software.rawValue, "Software")
        XCTAssertEqual(MJ2EncoderType.custom.rawValue, "Custom")
    }
    
    func testDecoderTypeRawValues() {
        XCTAssertEqual(MJ2DecoderType.videoToolbox.rawValue, "VideoToolbox")
        XCTAssertEqual(MJ2DecoderType.ffmpeg.rawValue, "FFmpeg")
        XCTAssertEqual(MJ2DecoderType.software.rawValue, "Software")
        XCTAssertEqual(MJ2DecoderType.custom.rawValue, "Custom")
    }
    
    // MARK: - Error Tests
    
    func testEncoderErrors() {
        let notAvailable = MJ2VideoEncoderError.notAvailable
        XCTAssertNotNil(notAvailable)
        
        let hardwareNotAvailable = MJ2VideoEncoderError.hardwareNotAvailable
        XCTAssertNotNil(hardwareNotAvailable)
        
        let sessionFailed = MJ2VideoEncoderError.sessionCreationFailed("test")
        XCTAssertNotNil(sessionFailed)
        
        let encodingFailed = MJ2VideoEncoderError.encodingFailed("test")
        XCTAssertNotNil(encodingFailed)
        
        let unsupportedCodec = MJ2VideoEncoderError.unsupportedCodec(.h265)
        XCTAssertNotNil(unsupportedCodec)
        
        let invalidDims = MJ2VideoEncoderError.invalidDimensions(width: 0, height: 0)
        XCTAssertNotNil(invalidDims)
    }
    
    func testDecoderErrors() {
        let notAvailable = MJ2VideoDecoderError.notAvailable
        XCTAssertNotNil(notAvailable)
        
        let hardwareNotAvailable = MJ2VideoDecoderError.hardwareNotAvailable
        XCTAssertNotNil(hardwareNotAvailable)
        
        let sessionFailed = MJ2VideoDecoderError.sessionCreationFailed("test")
        XCTAssertNotNil(sessionFailed)
        
        let decodingFailed = MJ2VideoDecoderError.decodingFailed("test")
        XCTAssertNotNil(decodingFailed)
        
        let invalidFormat = MJ2VideoDecoderError.invalidDataFormat
        XCTAssertNotNil(invalidFormat)
    }
}
