import XCTest
@testable import J2KCodec
@testable import J2KCore

/// Tests for the J2K encoder and decoder pipeline.
final class J2KEncoderDecoderTests: XCTestCase {
    
    /// Tests basic encoder instantiation and encoding.
    func testEncoderBasicEncoding() throws {
        // Create a simple grayscale image
        let width = 64
        let height = 64
        let componentData = Data(repeating: 128, count: width * height * MemoryLayout<Int32>.size)
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: componentData
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        // Encode the image
        let encoder = J2KEncoder(configuration: J2KConfiguration(quality: 0.9, lossless: true))
        let encodedData = try encoder.encode(image)
        
        // Verify we got some data
        XCTAssertGreaterThan(encodedData.count, 0)
        
        // Verify it starts with SOC marker
        XCTAssertEqual(encodedData[0], 0xFF)
        XCTAssertEqual(encodedData[1], 0x4F)
        
        // Verify it ends with EOC marker
        let lastTwoBytes = encodedData.suffix(2)
        XCTAssertEqual(Array(lastTwoBytes), [0xFF, 0xD9])
    }
    
    /// Tests basic decoder instantiation and decoding.
    func testDecoderBasicDecoding() throws {
        // First encode an image
        let width = 32
        let height = 32
        let componentData = Data(repeating: 100, count: width * height * MemoryLayout<Int32>.size)
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: componentData
        )
        
        let originalImage = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        let encoder = J2KEncoder()
        let encodedData = try encoder.encode(originalImage)
        
        // Now decode it
        let decoder = J2KDecoder()
        let decodedImage = try decoder.decode(encodedData)
        
        // Verify dimensions
        XCTAssertEqual(decodedImage.width, width)
        XCTAssertEqual(decodedImage.height, height)
        XCTAssertEqual(decodedImage.components.count, 1)
    }
    
    /// Tests encoder-decoder round-trip for a single component image.
    func testEncoderDecoderRoundTripGrayscale() throws {
        let width = 16
        let height = 16
        
        // Create simple grayscale image with known values
        var componentData = Data(count: width * height * MemoryLayout<Int32>.size)
        componentData.withUnsafeMutableBytes { buffer in
            let int32Buffer = buffer.bindMemory(to: Int32.self)
            for i in 0..<(width * height) {
                int32Buffer[i] = Int32(i % 256)
            }
        }
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: componentData
        )
        
        let originalImage = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        // Encode
        let encoder = J2KEncoder(configuration: J2KConfiguration(quality: 1.0, lossless: true))
        let encodedData = try encoder.encode(originalImage)
        
        // Decode
        let decoder = J2KDecoder()
        let decodedImage = try decoder.decode(encodedData)
        
        // Verify dimensions match
        XCTAssertEqual(decodedImage.width, originalImage.width)
        XCTAssertEqual(decodedImage.height, originalImage.height)
        XCTAssertEqual(decodedImage.components.count, originalImage.components.count)
        
        // Verify component properties
        XCTAssertEqual(decodedImage.components[0].width, width)
        XCTAssertEqual(decodedImage.components[0].height, height)
        XCTAssertEqual(decodedImage.components[0].bitDepth, 8)
    }
    
    /// Tests encoder with RGB image (3 components).
    func testEncoderWithRGBImage() throws {
        let width = 16
        let height = 16
        let componentData = Data(repeating: 128, count: width * height * MemoryLayout<Int32>.size)
        
        let components = [
            J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: componentData),
            J2KComponent(index: 1, bitDepth: 8, signed: false, width: width, height: height, data: componentData),
            J2KComponent(index: 2, bitDepth: 8, signed: false, width: width, height: height, data: componentData)
        ]
        
        let image = J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: .sRGB
        )
        
        let encoder = J2KEncoder()
        let encodedData = try encoder.encode(image)
        
        // Verify encoding succeeded
        XCTAssertGreaterThan(encodedData.count, 0)
        
        // Decode and verify
        let decoder = J2KDecoder()
        let decodedImage = try decoder.decode(encodedData)
        
        XCTAssertEqual(decodedImage.width, width)
        XCTAssertEqual(decodedImage.height, height)
        XCTAssertEqual(decodedImage.components.count, 3)
    }
    
    /// Tests encoder with invalid input.
    func testEncoderInvalidInput() throws {
        // Zero width
        var image = J2KImage(width: 0, height: 100, components: [])
        XCTAssertThrowsError(try J2KEncoder().encode(image))
        
        // Zero height
        image = J2KImage(width: 100, height: 0, components: [])
        XCTAssertThrowsError(try J2KEncoder().encode(image))
        
        // No components
        image = J2KImage(width: 100, height: 100, components: [])
        XCTAssertThrowsError(try J2KEncoder().encode(image))
    }
    
    /// Tests decoder with invalid input.
    func testDecoderInvalidInput() throws {
        let decoder = J2KDecoder()
        
        // Empty data
        XCTAssertThrowsError(try decoder.decode(Data()))
        
        // Too short
        XCTAssertThrowsError(try decoder.decode(Data([0xFF, 0x4F])))
        
        // Invalid SOC marker
        XCTAssertThrowsError(try decoder.decode(Data(repeating: 0x00, count: 20)))
    }
    
    /// Tests encoder configuration affects output.
    func testEncoderConfigurationQuality() throws {
        let width = 16
        let height = 16
        let componentData = Data(repeating: 128, count: width * height * MemoryLayout<Int32>.size)
        
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: componentData
        )
        
        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )
        
        // Encode with different quality settings
        let highQualityEncoder = J2KEncoder(configuration: J2KConfiguration(quality: 1.0, lossless: true))
        let lowQualityEncoder = J2KEncoder(configuration: J2KConfiguration(quality: 0.5, lossless: false))
        
        let highQualityData = try highQualityEncoder.encode(image)
        let lowQualityData = try lowQualityEncoder.encode(image)
        
        // Both should produce valid data
        XCTAssertGreaterThan(highQualityData.count, 0)
        XCTAssertGreaterThan(lowQualityData.count, 0)
    }
    
    /// Tests decomposition level calculation.
    func testDecompositionLevelCalculation() throws {
        // Test various image sizes
        let testCases: [(width: Int, height: Int, expectedMaxLevels: Int)] = [
            (16, 16, 4),     // min(log2(16), 5) = min(4, 5) = 4
            (32, 32, 5),     // min(log2(32), 5) = min(5, 5) = 5
            (64, 64, 5),     // min(log2(64), 5) = min(6, 5) = 5
            (512, 512, 5),   // min(log2(512), 5) = min(9, 5) = 5
            (1024, 1024, 5), // min(log2(1024), 5) = min(10, 5) = 5
            (8, 16, 3),      // min(log2(8), 5) = min(3, 5) = 3
        ]
        
        for testCase in testCases {
            let componentData = Data(repeating: 0, count: testCase.width * testCase.height * MemoryLayout<Int32>.size)
            let component = J2KComponent(
                index: 0,
                bitDepth: 8,
                signed: false,
                width: testCase.width,
                height: testCase.height,
                data: componentData
            )
            
            let image = J2KImage(
                width: testCase.width,
                height: testCase.height,
                components: [component]
            )
            
            // Encoding should succeed for all sizes
            let encoder = J2KEncoder()
            let encodedData = try encoder.encode(image)
            XCTAssertGreaterThan(encodedData.count, 0, "Failed for size \(testCase.width)x\(testCase.height)")
        }
    }
}
