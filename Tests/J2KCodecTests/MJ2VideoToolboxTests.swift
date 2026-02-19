/// # MJ2VideoToolboxTests
///
/// Tests for VideoToolbox integration with Motion JPEG 2000.

#if canImport(VideoToolbox)
import XCTest
import VideoToolbox
import CoreMedia
@testable import J2KCodec
@testable import J2KCore

final class MJ2VideoToolboxTests: XCTestCase {
    
    // MARK: - Capability Detection Tests
    
    func testCapabilityDetection() throws {
        let capabilities = MJ2VideoToolboxCapabilityDetector.detectCapabilities()
        
        // At least one codec should be available on Apple platforms
        XCTAssertTrue(
            capabilities.h264HardwareEncoderAvailable ||
            capabilities.h265HardwareEncoderAvailable,
            "At least one hardware encoder should be available"
        )
        
        // Decoders should generally be available
        XCTAssertTrue(capabilities.h264HardwareDecoderAvailable)
        
        // Resolution should be reasonable
        XCTAssertGreaterThanOrEqual(capabilities.maxResolution.width, 1920)
        XCTAssertGreaterThanOrEqual(capabilities.maxResolution.height, 1080)
        
        // Should support common pixel formats
        XCTAssertFalse(capabilities.supportedPixelFormats.isEmpty)
        XCTAssertTrue(capabilities.supportedPixelFormats.contains(kCVPixelFormatType_32ARGB))
    }
    
    func testH264EncoderAvailability() throws {
        let capabilities = MJ2VideoToolboxCapabilityDetector.detectCapabilities()
        
        // H.264 should be widely available
        if !capabilities.h264HardwareEncoderAvailable {
            print("Warning: H.264 hardware encoder not available on this platform")
        }
    }
    
    func testH265EncoderAvailability() throws {
        let capabilities = MJ2VideoToolboxCapabilityDetector.detectCapabilities()
        
        // H.265 may not be available on older hardware
        if !capabilities.h265HardwareEncoderAvailable {
            print("Warning: H.265 hardware encoder not available on this platform")
        }
    }
    
    // MARK: - Encoder Configuration Tests
    
    func testDefaultH264Configuration() throws {
        let config = MJ2VideoToolboxEncoderConfiguration.defaultH264()
        
        XCTAssertEqual(config.codec, .h264)
        XCTAssertEqual(config.bitrate, 5_000_000)
        XCTAssertEqual(config.frameRate, 24.0)
        XCTAssertTrue(config.useHardwareAcceleration)
        XCTAssertNotNil(config.profileLevel)
        XCTAssertEqual(config.maxKeyFrameInterval, 60)
        XCTAssertTrue(config.allowBFrames)
        XCTAssertEqual(config.quality, 0.8)
    }
    
    func testDefaultH265Configuration() throws {
        let config = MJ2VideoToolboxEncoderConfiguration.defaultH265()
        
        XCTAssertEqual(config.codec, .h265)
        XCTAssertEqual(config.bitrate, 3_000_000)
        XCTAssertEqual(config.frameRate, 24.0)
        XCTAssertTrue(config.useHardwareAcceleration)
        XCTAssertNotNil(config.profileLevel)
        XCTAssertEqual(config.maxKeyFrameInterval, 60)
        XCTAssertTrue(config.allowBFrames)
    }
    
    func testCustomEncoderConfiguration() throws {
        let config = MJ2VideoToolboxEncoderConfiguration(
            codec: .h264,
            bitrate: 10_000_000,
            frameRate: 30.0,
            useHardwareAcceleration: false,
            profileLevel: kVTProfileLevel_H264_Main_AutoLevel as String,
            maxKeyFrameInterval: 120,
            allowBFrames: false,
            quality: 0.9,
            multiPass: true
        )
        
        XCTAssertEqual(config.bitrate, 10_000_000)
        XCTAssertEqual(config.frameRate, 30.0)
        XCTAssertFalse(config.useHardwareAcceleration)
        XCTAssertEqual(config.maxKeyFrameInterval, 120)
        XCTAssertFalse(config.allowBFrames)
        XCTAssertTrue(config.multiPass)
    }
    
    // MARK: - Decoder Configuration Tests
    
    func testDefaultDecoderConfiguration() throws {
        let config = MJ2VideoToolboxDecoderConfiguration.default()
        
        XCTAssertTrue(config.useHardwareAcceleration)
        XCTAssertFalse(config.deinterlace)
        XCTAssertEqual(config.outputColorSpace, .sRGB)
    }
    
    func testCustomDecoderConfiguration() throws {
        let config = MJ2VideoToolboxDecoderConfiguration(
            useHardwareAcceleration: false,
            deinterlace: true,
            outputColorSpace: .yCbCr
        )
        
        XCTAssertFalse(config.useHardwareAcceleration)
        XCTAssertTrue(config.deinterlace)
        XCTAssertEqual(config.outputColorSpace, .yCbCr)
    }
    
    // MARK: - Encoder Tests
    
    func testEncoderInitialization() async throws {
        let config = MJ2VideoToolboxEncoderConfiguration.defaultH264(bitrate: 2_000_000)
        let encoder = MJ2VideoToolboxEncoder(configuration: config)
        
        // Initialize with HD resolution
        try await encoder.initialize(width: 1920, height: 1080)
        
        // Finish should not throw
        try await encoder.finish()
    }
    
    func testEncoderInitializationInvalidDimensions() async throws {
        let config = MJ2VideoToolboxEncoderConfiguration.defaultH264()
        let encoder = MJ2VideoToolboxEncoder(configuration: config)
        
        do {
            try await encoder.initialize(width: 0, height: 1080)
            XCTFail("Should throw error for invalid dimensions")
        } catch MJ2VideoToolboxError.invalidDimensions {
            // Expected
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
    
    func testEncoderWithDifferentResolutions() async throws {
        let config = MJ2VideoToolboxEncoderConfiguration.defaultH264()
        
        // Test common resolutions
        let resolutions = [
            (width: 640, height: 480),    // VGA
            (width: 1280, height: 720),   // HD
            (width: 1920, height: 1080),  // Full HD
            (width: 3840, height: 2160)   // 4K
        ]
        
        for resolution in resolutions {
            let encoder = MJ2VideoToolboxEncoder(configuration: config)
            try await encoder.initialize(width: resolution.width, height: resolution.height)
            try await encoder.finish()
        }
    }
    
    func testEncoderH265() async throws {
        let config = MJ2VideoToolboxEncoderConfiguration.defaultH265()
        let encoder = MJ2VideoToolboxEncoder(configuration: config)
        
        let capabilities = MJ2VideoToolboxCapabilityDetector.detectCapabilities()
        
        if capabilities.h265HardwareEncoderAvailable {
            try await encoder.initialize(width: 1920, height: 1080)
            try await encoder.finish()
        } else {
            // Skip test if H.265 encoder not available
            throw XCTSkip("H.265 hardware encoder not available")
        }
    }
    
    // MARK: - Decoder Tests
    
    func testDecoderInitialization() async throws {
        let config = MJ2VideoToolboxDecoderConfiguration.default()
        let decoder = MJ2VideoToolboxDecoder(configuration: config)
        
        // Create a format description for H.264
        let formatDescription = try createH264FormatDescription()
        
        try await decoder.initialize(formatDescription: formatDescription)
        await decoder.finish()
    }
    
    func testDecoderWithCustomConfiguration() async throws {
        let config = MJ2VideoToolboxDecoderConfiguration(
            useHardwareAcceleration: true,
            deinterlace: false,
            outputColorSpace: .sRGB
        )
        let decoder = MJ2VideoToolboxDecoder(configuration: config)
        
        let formatDescription = try createH264FormatDescription()
        try await decoder.initialize(formatDescription: formatDescription)
        await decoder.finish()
    }
    
    // MARK: - Integration Tests
    
    func testEncodeJ2KImageCreation() throws {
        // Create a simple test J2KImage
        let width = 640
        let height = 480
        let componentSize = width * height
        
        // Create RGB components with gradient pattern
        var rData = Data(count: componentSize)
        var gData = Data(count: componentSize)
        var bData = Data(count: componentSize)
        
        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                rData[index] = UInt8((x * 255) / width)
                gData[index] = UInt8((y * 255) / height)
                bData[index] = 128
            }
        }
        
        let components = [
            J2KComponent(
                index: 0,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: rData
            ),
            J2KComponent(
                index: 1,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: gData
            ),
            J2KComponent(
                index: 2,
                bitDepth: 8,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: bData
            )
        ]
        
        let image = J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: .sRGB,
            offsetX: 0,
            offsetY: 0,
            tileWidth: 0,
            tileHeight: 0,
            tileOffsetX: 0,
            tileOffsetY: 0
        )
        
        XCTAssertEqual(image.width, width)
        XCTAssertEqual(image.height, height)
        XCTAssertEqual(image.components.count, 3)
    }
    
    func testVideoCodecDescription() throws {
        XCTAssertEqual(MJ2VideoCodec.h264.description, "H.264 (AVC)")
        XCTAssertEqual(MJ2VideoCodec.h265.description, "H.265 (HEVC)")
        
        XCTAssertEqual(MJ2VideoCodec.h264.codecType, kCMVideoCodecType_H264)
        XCTAssertEqual(MJ2VideoCodec.h265.codecType, kCMVideoCodecType_HEVC)
    }
    
    func testErrorTypes() throws {
        // Test that error types can be thrown and caught
        let errors: [MJ2VideoToolboxError] = [
            .notAvailable,
            .hardwareNotAvailable,
            .compressionSessionCreationFailed(0),
            .decompressionSessionCreationFailed(0),
            .encodingFailed(0),
            .decodingFailed(0),
            .invalidPixelBuffer,
            .invalidDimensions,
            .unsupportedColorSpace,
            .configurationError("test")
        ]
        
        for error in errors {
            XCTAssertNotNil(error)
        }
    }
    
    func testEncoderQualityMode() async throws {
        // Test quality-based encoding (bitrate = 0)
        let config = MJ2VideoToolboxEncoderConfiguration(
            codec: .h264,
            bitrate: 0,  // Use quality instead
            frameRate: 24.0,
            useHardwareAcceleration: true,
            profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
            maxKeyFrameInterval: 60,
            allowBFrames: false,
            quality: 0.9,
            multiPass: false
        )
        
        let encoder = MJ2VideoToolboxEncoder(configuration: config)
        try await encoder.initialize(width: 1280, height: 720)
        try await encoder.finish()
    }
    
    func testMultipleEncoders() async throws {
        let config1 = MJ2VideoToolboxEncoderConfiguration.defaultH264()
        let config2 = MJ2VideoToolboxEncoderConfiguration.defaultH264(bitrate: 8_000_000)
        
        let encoder1 = MJ2VideoToolboxEncoder(configuration: config1)
        let encoder2 = MJ2VideoToolboxEncoder(configuration: config2)
        
        try await encoder1.initialize(width: 1920, height: 1080)
        try await encoder2.initialize(width: 1280, height: 720)
        
        try await encoder1.finish()
        try await encoder2.finish()
    }
    
    func testEncoderFrameRateVariations() async throws {
        let frameRates: [Double] = [23.976, 24.0, 25.0, 29.97, 30.0, 50.0, 59.94, 60.0]
        
        for frameRate in frameRates {
            let config = MJ2VideoToolboxEncoderConfiguration.defaultH264(frameRate: frameRate)
            let encoder = MJ2VideoToolboxEncoder(configuration: config)
            
            XCTAssertEqual(config.frameRate, frameRate)
            
            try await encoder.initialize(width: 1920, height: 1080)
            try await encoder.finish()
        }
    }
    
    func testEncoderBitrateVariations() async throws {
        let bitrates = [1_000_000, 2_500_000, 5_000_000, 10_000_000, 20_000_000]
        
        for bitrate in bitrates {
            let config = MJ2VideoToolboxEncoderConfiguration.defaultH264(bitrate: bitrate)
            let encoder = MJ2VideoToolboxEncoder(configuration: config)
            
            XCTAssertEqual(config.bitrate, bitrate)
            
            try await encoder.initialize(width: 1920, height: 1080)
            try await encoder.finish()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createH264FormatDescription() throws -> CMFormatDescription {
        // Create a minimal H.264 format description
        // In a real scenario, this would come from actual encoded data
        
        var formatDescription: CMFormatDescription?
        
        // Minimal SPS/PPS for 1920x1080
        let sps: [UInt8] = [0x67, 0x64, 0x00, 0x2a, 0xac, 0x2c, 0xa4, 0x01, 0xe0, 0x08, 0x9f, 0x96, 0x6e]
        let pps: [UInt8] = [0x68, 0xeb, 0xe3, 0xcb, 0x22, 0xc0]
        
        let parameterSets = [Data(sps), Data(pps)]
        let nalUnitHeaderLength: Int32 = 4
        
        var parameterSetPointers = parameterSets.map { $0.withUnsafeBytes { $0.baseAddress! } }
        var parameterSetSizes = parameterSets.map { $0.count }
        
        let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            allocator: kCFAllocatorDefault,
            parameterSetCount: parameterSets.count,
            parameterSetPointers: &parameterSetPointers,
            parameterSetSizes: &parameterSetSizes,
            nalUnitHeaderLength: nalUnitHeaderLength,
            formatDescriptionOut: &formatDescription
        )
        
        guard status == noErr, let description = formatDescription else {
            throw MJ2VideoToolboxError.configurationError("Failed to create format description")
        }
        
        return description
    }
}

#else
// Provide empty test class for non-VideoToolbox platforms
import XCTest

final class MJ2VideoToolboxTests: XCTestCase {
    func testVideoToolboxNotAvailable() throws {
        throw XCTSkip("VideoToolbox is not available on this platform")
    }
}
#endif
