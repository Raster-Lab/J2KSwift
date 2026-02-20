//
// J2KAPIErgonomicsTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

/// Tests for API ergonomics improvements in J2KCore.
final class J2KAPIErgonomicsTests: XCTestCase {
    // MARK: - J2KError Tests

    func testErrorDescriptions() {
        let errors: [J2KError] = [
            .invalidParameter("test"),
            .notImplemented("feature"),
            .internalError("crash"),
            .invalidDimensions("0x0"),
            .invalidBitDepth("42"),
            .invalidTileConfiguration("bad tiles"),
            .invalidComponentConfiguration("no components"),
            .invalidData("corrupted"),
            .fileFormatError("bad format"),
            .unsupportedFeature("not supported"),
            .decodingError("decode failed"),
            .encodingError("encode failed"),
            .ioError("read failed")
        ]

        for error in errors {
            let description = error.localizedDescription
            XCTAssertFalse(description.isEmpty, "Error description should not be empty")
            XCTAssertTrue(description.contains(":"), "Error description should contain error category")
        }
    }

    func testErrorStringConvertible() {
        let error = J2KError.invalidParameter("test parameter")
        let description = String(describing: error)
        XCTAssertTrue(description.contains("Invalid parameter"))
        XCTAssertTrue(description.contains("test parameter"))
    }

    // MARK: - J2KConfiguration Tests

    func testLosslessPreset() {
        let config = J2KConfiguration.lossless
        XCTAssertTrue(config.lossless)
        XCTAssertEqual(config.quality, 1.0)
    }

    func testHighQualityPreset() {
        let config = J2KConfiguration.highQuality
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.quality, 0.95)
    }

    func testBalancedPreset() {
        let config = J2KConfiguration.balanced
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.quality, 0.85)
    }

    func testFastPreset() {
        let config = J2KConfiguration.fast
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.quality, 0.70)
    }

    func testMaxCompressionPreset() {
        let config = J2KConfiguration.maxCompression
        XCTAssertFalse(config.lossless)
        XCTAssertEqual(config.quality, 0.50)
    }

    // MARK: - J2KImage Tests

    func testImageConvenienceProperties() {
        let image = J2KImage(width: 640, height: 480, components: 3)

        XCTAssertEqual(image.pixelCount, 640 * 480)
        XCTAssertEqual(image.componentCount, 3)
        XCTAssertFalse(image.isGrayscale)
        XCTAssertFalse(image.hasAlpha)
        XCTAssertFalse(image.isTiled)
        XCTAssertEqual(image.aspectRatio, 640.0 / 480.0, accuracy: 0.001)
    }

    func testGrayscaleImage() {
        let image = J2KImage(width: 100, height: 100, components: 1)

        XCTAssertTrue(image.isGrayscale)
        XCTAssertFalse(image.hasAlpha)
    }

    func testGrayscaleWithAlpha() {
        let comps = [
            J2KComponent(index: 0, bitDepth: 8, width: 100, height: 100),
            J2KComponent(index: 1, bitDepth: 8, width: 100, height: 100)
        ]
        let image = J2KImage(width: 100, height: 100, components: comps)

        XCTAssertFalse(image.isGrayscale)
        XCTAssertTrue(image.hasAlpha)
    }

    func testRGBWithAlpha() {
        let image = J2KImage(width: 100, height: 100, components: 4)

        XCTAssertFalse(image.isGrayscale)
        XCTAssertTrue(image.hasAlpha)
    }

    func testTiledImage() {
        let comps = [J2KComponent(index: 0, bitDepth: 8, width: 512, height: 512)]
        let image = J2KImage(
            width: 512,
            height: 512,
            components: comps,
            tileWidth: 256,
            tileHeight: 256
        )

        XCTAssertTrue(image.isTiled)
        XCTAssertEqual(image.tileCount, 4)
    }

    func testImageValidation() throws {
        let validImage = J2KImage(width: 100, height: 100, components: 3)
        XCTAssertNoThrow(try validImage.validate())
    }

    func testImageValidationInvalidDimensions() {
        let invalidComp = J2KComponent(index: 0, bitDepth: 8, width: 100, height: 100)
        // Use direct initializer with invalid dimensions (bypasses the convenience init clamping)
        let invalidImage = J2KImage(
            width: -1,
            height: 100,
            components: [invalidComp]
        )
        XCTAssertThrowsError(try invalidImage.validate()) { error in
            guard case J2KError.invalidDimensions = error else {
                XCTFail("Expected invalidDimensions error")
                return
            }
        }
    }

    func testImageValidationNoComponents() {
        let invalidImage = J2KImage(width: 100, height: 100, components: [])
        XCTAssertThrowsError(try invalidImage.validate()) { error in
            guard case J2KError.invalidComponentConfiguration = error else {
                XCTFail("Expected invalidComponentConfiguration error")
                return
            }
        }
    }

    func testImageValidationInvalidBitDepth() {
        let invalidComp = J2KComponent(index: 0, bitDepth: 39, width: 100, height: 100)
        let invalidImage = J2KImage(width: 100, height: 100, components: [invalidComp])
        XCTAssertThrowsError(try invalidImage.validate()) { error in
            guard case J2KError.invalidBitDepth = error else {
                XCTFail("Expected invalidBitDepth error")
                return
            }
        }
    }

    // MARK: - J2KComponent Tests

    func testComponentConvenienceProperties() {
        let component = J2KComponent(index: 0, bitDepth: 8, width: 100, height: 100)

        XCTAssertEqual(component.pixelCount, 10000)
        XCTAssertFalse(component.isSubsampled)
        XCTAssertEqual(component.maxValue, 255)
        XCTAssertEqual(component.minValue, 0)
    }

    func testComponentSubsampled() {
        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            width: 50,
            height: 50,
            subsamplingX: 2,
            subsamplingY: 2
        )

        XCTAssertTrue(component.isSubsampled)
    }

    func testComponentSigned() {
        let component = J2KComponent(index: 0, bitDepth: 8, signed: true, width: 100, height: 100)

        XCTAssertEqual(component.maxValue, 255)
        XCTAssertEqual(component.minValue, -128)
    }

    func testComponent16Bit() {
        let component = J2KComponent(index: 0, bitDepth: 16, width: 100, height: 100)

        XCTAssertEqual(component.maxValue, 65535)
        XCTAssertEqual(component.minValue, 0)
    }

    func testComponent12BitSigned() {
        let component = J2KComponent(index: 0, bitDepth: 12, signed: true, width: 100, height: 100)

        XCTAssertEqual(component.maxValue, 4095)
        XCTAssertEqual(component.minValue, -2048)
    }
}
