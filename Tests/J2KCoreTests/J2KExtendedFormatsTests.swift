import XCTest
@testable import J2KCore

/// Tests for extended format support (16-bit, HDR, extended precision, alpha channels).
///
/// This test suite validates the implementation of Week 90-92: Extended Formats milestone,
/// covering support for various bit depths, HDR images, extended precision modes, and
/// alpha channel handling.
final class J2KExtendedFormatsTests: XCTestCase {
    
    // MARK: - 16-bit Image Support Tests
    
    /// Tests creating a 16-bit grayscale image.
    func test16BitGrayscaleImage() throws {
        let image = J2KImage(width: 512, height: 512, components: 1, bitDepth: 16, signed: false)
        
        XCTAssertEqual(image.components.count, 1)
        XCTAssertEqual(image.components[0].bitDepth, 16)
        XCTAssertFalse(image.components[0].signed)
        XCTAssertEqual(image.width, 512)
        XCTAssertEqual(image.height, 512)
    }
    
    /// Tests creating a 16-bit RGB image.
    func test16BitRGBImage() throws {
        let image = J2KImage(width: 1024, height: 768, components: 3, bitDepth: 16, signed: false)
        
        XCTAssertEqual(image.components.count, 3)
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 16)
            XCTAssertFalse(component.signed)
        }
    }
    
    /// Tests creating a 16-bit signed image.
    func test16BitSignedImage() throws {
        let image = J2KImage(width: 256, height: 256, components: 1, bitDepth: 16, signed: true)
        
        XCTAssertTrue(image.components[0].signed)
        XCTAssertEqual(image.components[0].bitDepth, 16)
    }
    
    /// Tests 16-bit image buffer storage and retrieval.
    func test16BitImageBufferRoundTrip() throws {
        let buffer = J2KImageBuffer(width: 10, height: 10, bitDepth: 16)
        var mutableBuffer = buffer
        
        // Test values across the 16-bit range
        let testValues = [0, 255, 256, 1000, 32768, 65535]
        for (index, value) in testValues.enumerated() {
            mutableBuffer.setPixel(at: index, value: value)
        }
        
        for (index, expectedValue) in testValues.enumerated() {
            let actualValue = mutableBuffer.getPixel(at: index)
            XCTAssertEqual(actualValue, expectedValue, "16-bit value at index \(index) should match")
        }
    }
    
    /// Tests 16-bit image buffer with maximum value.
    func test16BitMaxValue() throws {
        let buffer = J2KImageBuffer(width: 1, height: 1, bitDepth: 16)
        var mutableBuffer = buffer
        
        let maxValue = 65535
        mutableBuffer.setPixel(at: 0, value: maxValue)
        
        let retrieved = mutableBuffer.getPixel(at: 0)
        XCTAssertEqual(retrieved, maxValue, "Should handle 16-bit maximum value")
    }
    
    // MARK: - Extended Precision Tests
    
    /// Tests 10-bit image support.
    func test10BitPrecision() throws {
        let image = J2KImage(width: 640, height: 480, components: 3, bitDepth: 10, signed: false)
        
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 10)
        }
        
        // Verify 10-bit range (0-1023)
        let buffer = J2KImageBuffer(width: 5, height: 1, bitDepth: 10)
        var mutableBuffer = buffer
        
        let testValues = [0, 256, 512, 768, 1023]
        for (index, value) in testValues.enumerated() {
            mutableBuffer.setPixel(at: index, value: value)
            let retrieved = mutableBuffer.getPixel(at: index)
            XCTAssertEqual(retrieved, value, "10-bit value should be preserved")
        }
    }
    
    /// Tests 12-bit image support.
    func test12BitPrecision() throws {
        let image = J2KImage(width: 800, height: 600, components: 3, bitDepth: 12, signed: false)
        
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 12)
        }
        
        // Verify 12-bit range (0-4095)
        let buffer = J2KImageBuffer(width: 5, height: 1, bitDepth: 12)
        var mutableBuffer = buffer
        
        let testValues = [0, 1024, 2048, 3072, 4095]
        for (index, value) in testValues.enumerated() {
            mutableBuffer.setPixel(at: index, value: value)
            let retrieved = mutableBuffer.getPixel(at: index)
            XCTAssertEqual(retrieved, value, "12-bit value should be preserved")
        }
    }
    
    /// Tests 14-bit image support.
    func test14BitPrecision() throws {
        let image = J2KImage(width: 1920, height: 1080, components: 3, bitDepth: 14, signed: false)
        
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 14)
        }
        
        // Verify 14-bit range (0-16383)
        let buffer = J2KImageBuffer(width: 5, height: 1, bitDepth: 14)
        var mutableBuffer = buffer
        
        let testValues = [0, 4096, 8192, 12288, 16383]
        for (index, value) in testValues.enumerated() {
            mutableBuffer.setPixel(at: index, value: value)
            let retrieved = mutableBuffer.getPixel(at: index)
            XCTAssertEqual(retrieved, value, "14-bit value should be preserved")
        }
    }
    
    // MARK: - Various Bit Depth Tests
    
    /// Tests 1-bit (binary) images.
    func test1BitImage() throws {
        let image = J2KImage(width: 100, height: 100, components: 1, bitDepth: 1, signed: false)
        
        XCTAssertEqual(image.components[0].bitDepth, 1)
        
        let buffer = J2KImageBuffer(width: 8, height: 1, bitDepth: 1)
        var mutableBuffer = buffer
        
        // Test binary values
        for index in 0..<8 {
            let value = index % 2
            mutableBuffer.setPixel(at: index, value: value)
            XCTAssertEqual(mutableBuffer.getPixel(at: index), value)
        }
    }
    
    /// Tests 4-bit images.
    func test4BitImage() throws {
        let image = J2KImage(width: 256, height: 256, components: 1, bitDepth: 4, signed: false)
        
        XCTAssertEqual(image.components[0].bitDepth, 4)
        
        // Test 4-bit range (0-15)
        let buffer = J2KImageBuffer(width: 16, height: 1, bitDepth: 4)
        var mutableBuffer = buffer
        
        for value in 0..<16 {
            mutableBuffer.setPixel(at: value, value: value)
            XCTAssertEqual(mutableBuffer.getPixel(at: value), value)
        }
    }
    
    /// Tests unusual bit depths (e.g., 3, 5, 7, 9, 11, 13, 15).
    func testUnusualBitDepths() throws {
        let unusualDepths = [3, 5, 7, 9, 11, 13, 15]
        
        for bitDepth in unusualDepths {
            let image = J2KImage(width: 64, height: 64, components: 1, bitDepth: bitDepth, signed: false)
            XCTAssertEqual(image.components[0].bitDepth, bitDepth, "Should support \(bitDepth)-bit images")
            
            // Test buffer with this bit depth
            let buffer = J2KImageBuffer(width: 4, height: 1, bitDepth: bitDepth)
            var mutableBuffer = buffer
            
            let maxValue = (1 << bitDepth) - 1
            let testValues = [0, maxValue / 4, maxValue / 2, maxValue]
            
            for (index, value) in testValues.enumerated() {
                mutableBuffer.setPixel(at: index, value: value)
                let retrieved = mutableBuffer.getPixel(at: index)
                XCTAssertEqual(retrieved, value, "\(bitDepth)-bit value should be preserved")
            }
        }
    }
    
    /// Tests the maximum supported bit depth (38 bits according to JPEG 2000 spec).
    func testMaximumBitDepth() throws {
        // JPEG 2000 Part 1 supports up to 38 bits per component
        let image = J2KImage(width: 16, height: 16, components: 1, bitDepth: 38, signed: false)
        XCTAssertEqual(image.components[0].bitDepth, 38)
    }
    
    // MARK: - Alpha Channel Tests
    
    /// Tests creating an RGBA image with 8-bit components.
    func testRGBAImage8Bit() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: 512, height: 512), // R
            J2KComponent(index: 1, bitDepth: 8, width: 512, height: 512), // G
            J2KComponent(index: 2, bitDepth: 8, width: 512, height: 512), // B
            J2KComponent(index: 3, bitDepth: 8, width: 512, height: 512)  // A
        ]
        
        let image = J2KImage(
            width: 512,
            height: 512,
            components: components,
            colorSpace: .sRGB
        )
        
        XCTAssertEqual(image.components.count, 4)
        XCTAssertEqual(image.components[3].bitDepth, 8, "Alpha channel should be 8-bit")
    }
    
    /// Tests creating an RGBA image with 16-bit components.
    func testRGBAImage16Bit() throws {
        let image = J2KImage(width: 1024, height: 768, components: 4, bitDepth: 16, signed: false)
        
        XCTAssertEqual(image.components.count, 4)
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 16)
        }
    }
    
    /// Tests grayscale with alpha (GA).
    func testGrayscaleAlphaImage() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: 640, height: 480), // Gray
            J2KComponent(index: 1, bitDepth: 8, width: 640, height: 480)  // Alpha
        ]
        
        let image = J2KImage(
            width: 640,
            height: 480,
            components: components,
            colorSpace: .grayscale
        )
        
        XCTAssertEqual(image.components.count, 2)
    }
    
    /// Tests alpha channel with different bit depth than color channels.
    func testMixedBitDepthWithAlpha() throws {
        // RGB at 8-bit, Alpha at 16-bit (uncommon but valid)
        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: 256, height: 256),  // R
            J2KComponent(index: 1, bitDepth: 8, width: 256, height: 256),  // G
            J2KComponent(index: 2, bitDepth: 8, width: 256, height: 256),  // B
            J2KComponent(index: 3, bitDepth: 16, width: 256, height: 256)  // A (higher precision)
        ]
        
        let image = J2KImage(
            width: 256,
            height: 256,
            components: components
        )
        
        XCTAssertEqual(image.components.count, 4)
        XCTAssertEqual(image.components[0].bitDepth, 8)
        XCTAssertEqual(image.components[3].bitDepth, 16)
    }
    
    // MARK: - HDR Image Support Tests
    
    /// Tests creating an HDR image with 10-bit components.
    func testHDR10BitImage() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 10, width: 1920, height: 1080),
            J2KComponent(index: 1, bitDepth: 10, width: 1920, height: 1080),
            J2KComponent(index: 2, bitDepth: 10, width: 1920, height: 1080)
        ]
        
        let image = J2KImage(
            width: 1920,
            height: 1080,
            components: components,
            colorSpace: .hdr
        )
        
        XCTAssertEqual(image.colorSpace, .hdr)
        XCTAssertEqual(image.components.count, 3)
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 10, "HDR10 uses 10-bit components")
        }
    }
    
    /// Tests creating an HDR image with 12-bit components.
    func testHDR12BitImage() throws {
        let image = J2KImage(
            width: 3840,
            height: 2160,
            components: 3,
            bitDepth: 12,
            signed: false
        )
        
        let hdrImage = J2KImage(
            width: image.width,
            height: image.height,
            components: image.components,
            colorSpace: .hdr
        )
        
        XCTAssertEqual(hdrImage.colorSpace, .hdr)
        for component in hdrImage.components {
            XCTAssertEqual(component.bitDepth, 12)
        }
    }
    
    /// Tests creating an HDR image with 16-bit components.
    func testHDR16BitImage() throws {
        let image = J2KImage(
            width: 4096,
            height: 2160,
            components: 3,
            bitDepth: 16,
            signed: false
        )
        
        let hdrImage = J2KImage(
            width: image.width,
            height: image.height,
            components: image.components,
            colorSpace: .hdr
        )
        
        XCTAssertEqual(hdrImage.colorSpace, .hdr)
        for component in hdrImage.components {
            XCTAssertEqual(component.bitDepth, 16, "HDR can use 16-bit for maximum precision")
        }
    }
    
    /// Tests HDR linear color space.
    func testHDRLinearColorSpace() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 16, width: 1920, height: 1080),
            J2KComponent(index: 1, bitDepth: 16, width: 1920, height: 1080),
            J2KComponent(index: 2, bitDepth: 16, width: 1920, height: 1080)
        ]
        
        let image = J2KImage(
            width: 1920,
            height: 1080,
            components: components,
            colorSpace: .hdrLinear
        )
        
        XCTAssertEqual(image.colorSpace, .hdrLinear)
        XCTAssertEqual(image.components.count, 3)
    }
    
    /// Tests HDR grayscale image.
    func testHDRGrayscaleImage() throws {
        let component = J2KComponent(index: 0, bitDepth: 16, width: 2048, height: 2048)
        
        let image = J2KImage(
            width: 2048,
            height: 2048,
            components: [component],
            colorSpace: .hdr
        )
        
        XCTAssertEqual(image.colorSpace, .hdr)
        XCTAssertEqual(image.components.count, 1)
        XCTAssertEqual(image.components[0].bitDepth, 16)
    }
    
    /// Tests HDR image with alpha channel (RGBA HDR).
    func testHDRWithAlpha() throws {
        let components = [
            J2KComponent(index: 0, bitDepth: 10, width: 1920, height: 1080),  // R
            J2KComponent(index: 1, bitDepth: 10, width: 1920, height: 1080),  // G
            J2KComponent(index: 2, bitDepth: 10, width: 1920, height: 1080),  // B
            J2KComponent(index: 3, bitDepth: 10, width: 1920, height: 1080)   // A
        ]
        
        let image = J2KImage(
            width: 1920,
            height: 1080,
            components: components,
            colorSpace: .hdr
        )
        
        XCTAssertEqual(image.colorSpace, .hdr)
        XCTAssertEqual(image.components.count, 4, "HDR can include alpha channel")
        for component in image.components {
            XCTAssertEqual(component.bitDepth, 10)
        }
    }
    
    /// Tests that HDR buffer can store extended range values.
    func testHDRBufferExtendedRange() throws {
        // HDR images can represent values beyond typical 8-bit range
        let buffer = J2KImageBuffer(width: 10, height: 1, bitDepth: 16)
        var mutableBuffer = buffer
        
        // Test values across extended dynamic range
        let testValues = [
            0,      // Black
            1024,   // Lower mid-tone
            4096,   // Mid-tone
            16384,  // Upper mid-tone
            32768,  // Bright
            65535   // Peak white
        ]
        
        for (index, value) in testValues.enumerated() {
            mutableBuffer.setPixel(at: index, value: value)
            let retrieved = mutableBuffer.getPixel(at: index)
            XCTAssertEqual(retrieved, value, "HDR value should be preserved across full range")
        }
    }
    
    // MARK: - Signed Image Tests
    
    /// Tests signed 8-bit images.
    func testSigned8BitImage() throws {
        let image = J2KImage(width: 128, height: 128, components: 1, bitDepth: 8, signed: true)
        
        XCTAssertTrue(image.components[0].signed)
        XCTAssertEqual(image.components[0].bitDepth, 8)
    }
    
    /// Tests signed 16-bit images.
    func testSigned16BitImage() throws {
        let image = J2KImage(width: 256, height: 256, components: 3, bitDepth: 16, signed: true)
        
        for component in image.components {
            XCTAssertTrue(component.signed)
            XCTAssertEqual(component.bitDepth, 16)
        }
    }
    
    // MARK: - Buffer Size Tests
    
    /// Tests that buffer sizes are calculated correctly for different bit depths.
    func testBufferSizeCalculation() throws {
        let widths = [100, 512, 1024]
        let heights = [100, 512, 1024]
        let bitDepths = [1, 8, 10, 12, 14, 16]
        
        for width in widths {
            for height in heights {
                for bitDepth in bitDepths {
                    let buffer = J2KImageBuffer(width: width, height: height, bitDepth: bitDepth)
                    
                    let expectedPixelCount = width * height
                    let expectedBytesPerPixel = (bitDepth + 7) / 8
                    let expectedSizeInBytes = expectedPixelCount * expectedBytesPerPixel
                    
                    XCTAssertEqual(buffer.count, expectedPixelCount)
                    XCTAssertEqual(buffer.sizeInBytes, expectedSizeInBytes,
                                   "Size mismatch for \(width)x\(height) at \(bitDepth)-bit")
                }
            }
        }
    }
    
    // MARK: - Integration Tests
    
    /// Tests creating a complex multi-component image with mixed properties.
    func testComplexMultiComponentImage() throws {
        // Simulate a complex image: RGB at 10-bit + Alpha at 8-bit + Depth at 16-bit
        let components = [
            J2KComponent(index: 0, bitDepth: 10, width: 1920, height: 1080),  // R
            J2KComponent(index: 1, bitDepth: 10, width: 1920, height: 1080),  // G
            J2KComponent(index: 2, bitDepth: 10, width: 1920, height: 1080),  // B
            J2KComponent(index: 3, bitDepth: 8, width: 1920, height: 1080),   // A
            J2KComponent(index: 4, bitDepth: 16, width: 1920, height: 1080)   // Depth
        ]
        
        let image = J2KImage(
            width: 1920,
            height: 1080,
            components: components
        )
        
        XCTAssertEqual(image.components.count, 5)
        XCTAssertEqual(image.components[0].bitDepth, 10)
        XCTAssertEqual(image.components[1].bitDepth, 10)
        XCTAssertEqual(image.components[2].bitDepth, 10)
        XCTAssertEqual(image.components[3].bitDepth, 8)
        XCTAssertEqual(image.components[4].bitDepth, 16)
    }
    
    /// Tests that images with various bit depths maintain their metadata correctly.
    func testMetadataPreservation() throws {
        let testCases: [(width: Int, height: Int, components: Int, bitDepth: Int, signed: Bool)] = [
            (512, 512, 1, 8, false),
            (1024, 768, 3, 10, false),
            (640, 480, 4, 12, false),
            (256, 256, 1, 16, true),
            (1920, 1080, 3, 16, false)
        ]
        
        for testCase in testCases {
            let image = J2KImage(
                width: testCase.width,
                height: testCase.height,
                components: testCase.components,
                bitDepth: testCase.bitDepth,
                signed: testCase.signed
            )
            
            XCTAssertEqual(image.width, testCase.width)
            XCTAssertEqual(image.height, testCase.height)
            XCTAssertEqual(image.components.count, testCase.components)
            
            for component in image.components {
                XCTAssertEqual(component.bitDepth, testCase.bitDepth)
                XCTAssertEqual(component.signed, testCase.signed)
            }
        }
    }
}
