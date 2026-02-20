import XCTest
@testable import J2KAccelerate
@testable import J2KCore

/// Tests for vImage integration.
final class J2KVImageIntegrationTests: XCTestCase {
    let vimage = J2KVImageIntegration()

    // MARK: - Availability Tests

    /// Tests that vImage availability can be checked.
    func testVImageAvailability() throws {
        #if canImport(Accelerate)
        XCTAssertTrue(J2KVImageIntegration.isAvailable)
        #else
        XCTAssertFalse(J2KVImageIntegration.isAvailable)
        #endif
    }

    // MARK: - Format Conversion Tests

    #if canImport(Accelerate)

    /// Tests YCbCr to RGB conversion.
    func testYCbCrToRGBConversion() throws {
        let width = 4
        let height = 4
        let pixelCount = width * height

        // Create simple test data
        let y = [UInt8](repeating: 128, count: pixelCount)
        let cb = [UInt8](repeating: 128, count: pixelCount)
        let cr = [UInt8](repeating: 128, count: pixelCount)

        let rgb = try vimage.convertYCbCrToRGB(
            y: y,
            cb: cb,
            cr: cr,
            width: width,
            height: height
        )

        // Should produce RGBA output
        XCTAssertEqual(rgb.count, pixelCount * 4)

        // All values should be valid
        XCTAssertTrue(rgb.allSatisfy { $0 <= 255 })
    }

    /// Tests YCbCr to RGB with invalid dimensions.
    func testYCbCrToRGBInvalidDimensions() throws {
        let y = [UInt8](repeating: 0, count: 10)
        let cb = [UInt8](repeating: 0, count: 10)
        let cr = [UInt8](repeating: 0, count: 10)

        // Size doesn't match width × height
        XCTAssertThrowsError(try vimage.convertYCbCrToRGB(
            y: y,
            cb: cb,
            cr: cr,
            width: 4,
            height: 4
        ))
    }

    /// Tests RGB to YCbCr conversion.
    func testRGBToYCbCrConversion() throws {
        let width = 4
        let height = 4
        let pixelCount = width * height

        // Create simple RGBA test data (gray)
        var rgb = [UInt8](repeating: 128, count: pixelCount * 4)

        // Set alpha to 255
        for i in 0..<pixelCount {
            rgb[i * 4 + 3] = 255
        }

        let (y, cb, cr) = try vimage.convertRGBToYCbCr(
            rgb: rgb,
            width: width,
            height: height
        )

        // Check output dimensions
        XCTAssertEqual(y.count, pixelCount)
        XCTAssertEqual(cb.count, pixelCount)
        XCTAssertEqual(cr.count, pixelCount)

        // All values should be valid
        XCTAssertTrue(y.allSatisfy { $0 <= 255 })
        XCTAssertTrue(cb.allSatisfy { $0 <= 255 })
        XCTAssertTrue(cr.allSatisfy { $0 <= 255 })
    }

    /// Tests round-trip conversion (RGB → YCbCr → RGB).
    func testRoundTripConversion() throws {
        let width = 4
        let height = 4
        let pixelCount = width * height

        // Create test RGB data
        var originalRGB = [UInt8](repeating: 0, count: pixelCount * 4)
        for i in 0..<pixelCount {
            originalRGB[i * 4] = UInt8(i * 16)     // R
            originalRGB[i * 4 + 1] = UInt8(i * 8)  // G
            originalRGB[i * 4 + 2] = UInt8(i * 4)  // B
            originalRGB[i * 4 + 3] = 255           // A
        }

        // Convert to YCbCr
        let (y, cb, cr) = try vimage.convertRGBToYCbCr(
            rgb: originalRGB,
            width: width,
            height: height
        )

        // Convert back to RGB
        let reconstructedRGB = try vimage.convertYCbCrToRGB(
            y: y,
            cb: cb,
            cr: cr,
            width: width,
            height: height
        )

        XCTAssertEqual(reconstructedRGB.count, originalRGB.count)

        // Check that values are reasonably close (some loss expected)
        for i in 0..<pixelCount {
            let rDiff = abs(Int(originalRGB[i * 4]) - Int(reconstructedRGB[i * 4]))
            let gDiff = abs(Int(originalRGB[i * 4 + 1]) - Int(reconstructedRGB[i * 4 + 1]))
            let bDiff = abs(Int(originalRGB[i * 4 + 2]) - Int(reconstructedRGB[i * 4 + 2]))

            // Allow some tolerance for color space conversion
            XCTAssertLessThanOrEqual(rDiff, 5, "Red component differs too much at pixel \(i)")
            XCTAssertLessThanOrEqual(gDiff, 5, "Green component differs too much at pixel \(i)")
            XCTAssertLessThanOrEqual(bDiff, 5, "Blue component differs too much at pixel \(i)")
        }
    }

    // MARK: - Resampling Tests

    /// Tests downsampling.
    func testResampleDownscale() throws {
        let srcWidth = 8
        let srcHeight = 8
        let srcData = [UInt8](repeating: 128, count: srcWidth * srcHeight)

        let dstWidth = 4
        let dstHeight = 4

        let result = try vimage.resample(
            data: srcData,
            fromSize: (width: srcWidth, height: srcHeight),
            toSize: (width: dstWidth, height: dstHeight),
            channels: 1
        )

        XCTAssertEqual(result.count, dstWidth * dstHeight)
        XCTAssertTrue(result.allSatisfy { $0 <= 255 })
    }

    /// Tests upsampling.
    func testResampleUpscale() throws {
        let srcWidth = 4
        let srcHeight = 4
        let srcData = [UInt8](repeating: 128, count: srcWidth * srcHeight)

        let dstWidth = 8
        let dstHeight = 8

        let result = try vimage.resample(
            data: srcData,
            fromSize: (width: srcWidth, height: srcHeight),
            toSize: (width: dstWidth, height: dstHeight),
            channels: 1
        )

        XCTAssertEqual(result.count, dstWidth * dstHeight)
        XCTAssertTrue(result.allSatisfy { $0 <= 255 })
    }

    /// Tests resampling with RGBA data.
    func testResampleRGBA() throws {
        let srcWidth = 4
        let srcHeight = 4
        let srcData = [UInt8](repeating: 128, count: srcWidth * srcHeight * 4)

        let dstWidth = 2
        let dstHeight = 2

        let result = try vimage.resample(
            data: srcData,
            fromSize: (width: srcWidth, height: srcHeight),
            toSize: (width: dstWidth, height: dstHeight),
            channels: 4
        )

        XCTAssertEqual(result.count, dstWidth * dstHeight * 4)
    }

    /// Tests resampling with invalid dimensions.
    func testResampleInvalidDimensions() throws {
        let data = [UInt8](repeating: 0, count: 10)

        XCTAssertThrowsError(try vimage.resample(
            data: data,
            fromSize: (width: 4, height: 4),
            toSize: (width: 2, height: 2),
            channels: 1
        ))
    }

    // MARK: - Geometric Transform Tests

    /// Tests 90-degree rotation.
    func testRotate90() throws {
        let width = 4
        let height = 2
        let data = [UInt8](repeating: 128, count: width * height)

        let (rotated, newWidth, newHeight) = try vimage.rotate(
            data: data,
            width: width,
            height: height,
            degrees: 90,
            channels: 1
        )

        // 90-degree rotation swaps dimensions
        XCTAssertEqual(newWidth, height)
        XCTAssertEqual(newHeight, width)
        XCTAssertEqual(rotated.count, width * height)
    }

    /// Tests 180-degree rotation.
    func testRotate180() throws {
        let width = 4
        let height = 4
        let data = [UInt8](repeating: 128, count: width * height)

        let (rotated, newWidth, newHeight) = try vimage.rotate(
            data: data,
            width: width,
            height: height,
            degrees: 180,
            channels: 1
        )

        // 180-degree rotation keeps dimensions
        XCTAssertEqual(newWidth, width)
        XCTAssertEqual(newHeight, height)
        XCTAssertEqual(rotated.count, width * height)
    }

    /// Tests 270-degree rotation.
    func testRotate270() throws {
        let width = 4
        let height = 2
        let data = [UInt8](repeating: 128, count: width * height)

        let (rotated, newWidth, newHeight) = try vimage.rotate(
            data: data,
            width: width,
            height: height,
            degrees: 270,
            channels: 1
        )

        // 270-degree rotation swaps dimensions
        XCTAssertEqual(newWidth, height)
        XCTAssertEqual(newHeight, width)
        XCTAssertEqual(rotated.count, width * height)
    }

    /// Tests rotation with invalid angle.
    func testRotateInvalidAngle() throws {
        let data = [UInt8](repeating: 0, count: 16)

        XCTAssertThrowsError(try vimage.rotate(
            data: data,
            width: 4,
            height: 4,
            degrees: 45, // Not supported
            channels: 1
        ))
    }

    // MARK: - Alpha Blending Tests

    /// Tests alpha blending of two images.
    func testAlphaBlend() throws {
        let width = 4
        let height = 4
        let pixelCount = width * height

        // Create foreground (opaque red)
        var foreground = [UInt8](repeating: 0, count: pixelCount * 4)
        for i in 0..<pixelCount {
            foreground[i * 4] = 255     // A
            foreground[i * 4 + 1] = 255 // R
            foreground[i * 4 + 2] = 0   // G
            foreground[i * 4 + 3] = 0   // B
        }

        // Create background (opaque blue)
        var background = [UInt8](repeating: 0, count: pixelCount * 4)
        for i in 0..<pixelCount {
            background[i * 4] = 255     // A
            background[i * 4 + 1] = 0   // R
            background[i * 4 + 2] = 0   // G
            background[i * 4 + 3] = 255 // B
        }

        let result = try vimage.alphaBlend(
            foreground: foreground,
            background: background,
            width: width,
            height: height
        )

        XCTAssertEqual(result.count, pixelCount * 4)
        XCTAssertTrue(result.allSatisfy { $0 <= 255 })
    }

    /// Tests alpha blending with invalid dimensions.
    func testAlphaBlendInvalidDimensions() throws {
        let foreground = [UInt8](repeating: 0, count: 10)
        let background = [UInt8](repeating: 0, count: 16)

        XCTAssertThrowsError(try vimage.alphaBlend(
            foreground: foreground,
            background: background,
            width: 4,
            height: 4
        ))
    }

    #endif
}
