//
// J2KQualityMetricsTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore

final class J2KQualityMetricsTests: XCTestCase {

    // MARK: - Helpers

    /// Build a single-component greyscale test image filled with a constant value.
    private func makeGreyscaleImage(width: Int, height: Int, value: UInt8) -> J2KImage {
        let data = Data(repeating: value, count: width * height)
        let comp = J2KComponent(index: 0, bitDepth: 8, width: width, height: height, data: data)
        return J2KImage(width: width, height: height, components: [comp], colorSpace: .grayscale)
    }

    /// Build a single-component greyscale image from an array of pixel values.
    private func makeGreyscaleImage(width: Int, height: Int, pixels: [UInt8]) -> J2KImage {
        let data = Data(pixels)
        let comp = J2KComponent(index: 0, bitDepth: 8, width: width, height: height, data: data)
        return J2KImage(width: width, height: height, components: [comp], colorSpace: .grayscale)
    }

    /// Build a 3-component RGB test image with constant channel values.
    private func makeRGBImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> J2KImage {
        let count = width * height
        let rData = Data(repeating: r, count: count)
        let gData = Data(repeating: g, count: count)
        let bData = Data(repeating: b, count: count)
        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: width, height: height, data: rData),
            J2KComponent(index: 1, bitDepth: 8, width: width, height: height, data: gData),
            J2KComponent(index: 2, bitDepth: 8, width: width, height: height, data: bData),
        ]
        return J2KImage(width: width, height: height, components: components, colorSpace: .sRGB)
    }

    // MARK: - Identical Images (Lossless)

    func testIdenticalGreyscaleImagesAreBitExact() throws {
        // Arrange
        let img = makeGreyscaleImage(width: 16, height: 16, value: 128)

        // Act
        let report = try J2KQualityMetricsEngine.computeReport(
            original: img, compared: img,
            originalLabel: "original", comparedLabel: "compared",
            originalFileSize: 256, comparedFileSize: 256)

        // Assert
        XCTAssertTrue(report.bitExact)
        XCTAssertTrue(report.globalPSNR.isInfinite)
        XCTAssertEqual(report.globalMSE, 0.0, accuracy: 1e-10)
        XCTAssertEqual(report.globalMAE, 0.0, accuracy: 1e-10)
        XCTAssertEqual(report.globalMaxAbsoluteError, 0)
        XCTAssertEqual(report.globalSSIM, 1.0, accuracy: 1e-6)
    }

    func testIdenticalRGBImagesAreBitExact() throws {
        // Arrange
        let img = makeRGBImage(width: 16, height: 16, r: 100, g: 150, b: 200)

        // Act
        let report = try J2KQualityMetricsEngine.computeReport(
            original: img, compared: img,
            originalLabel: "original", comparedLabel: "compared",
            originalFileSize: 768, comparedFileSize: 768)

        // Assert
        XCTAssertTrue(report.bitExact)
        XCTAssertTrue(report.globalPSNR.isInfinite)
        XCTAssertEqual(report.globalSSIM, 1.0, accuracy: 1e-6)
        XCTAssertEqual(report.perComponent.count, 3)
        for cm in report.perComponent {
            XCTAssertTrue(cm.bitExact)
            XCTAssertTrue(cm.psnr.isInfinite)
        }
    }

    // MARK: - Known Differences

    func testKnownConstantDifference() throws {
        // Arrange: original=100, compared=102 everywhere → diff=2
        let original = makeGreyscaleImage(width: 8, height: 8, value: 100)
        let compared = makeGreyscaleImage(width: 8, height: 8, value: 102)

        // Act
        let report = try J2KQualityMetricsEngine.computeReport(
            original: original, compared: compared,
            originalLabel: "orig", comparedLabel: "comp",
            originalFileSize: 64, comparedFileSize: 64)

        // Assert
        XCTAssertFalse(report.bitExact)
        XCTAssertEqual(report.globalMSE, 4.0, accuracy: 1e-10)  // (100-102)^2 = 4
        XCTAssertEqual(report.globalMAE, 2.0, accuracy: 1e-10)
        XCTAssertEqual(report.globalMaxAbsoluteError, 2)

        // PSNR = 10*log10(255^2 / 4) ≈ 42.11 dB
        let expectedPSNR = 10.0 * log10(255.0 * 255.0 / 4.0)
        XCTAssertEqual(report.globalPSNR, expectedPSNR, accuracy: 0.01)
    }

    func testSinglePixelDifference() throws {
        // Arrange: all pixels match except index 5 (diff=10)
        var origPixels = [UInt8](repeating: 50, count: 64)
        var compPixels = [UInt8](repeating: 50, count: 64)
        compPixels[5] = 60

        let original = makeGreyscaleImage(width: 8, height: 8, pixels: origPixels)
        let compared = makeGreyscaleImage(width: 8, height: 8, pixels: compPixels)

        // Act
        let report = try J2KQualityMetricsEngine.computeReport(
            original: original, compared: compared,
            originalLabel: "orig", comparedLabel: "comp",
            originalFileSize: 64, comparedFileSize: 64)

        // Assert
        XCTAssertFalse(report.bitExact)
        XCTAssertEqual(report.globalMaxAbsoluteError, 10)
        XCTAssertEqual(report.globalMSE, 100.0 / 64.0, accuracy: 1e-10)
        XCTAssertEqual(report.globalMAE, 10.0 / 64.0, accuracy: 1e-10)

        // Worst error at pixel index 5 → (5, 0) for 8-wide image
        XCTAssertEqual(report.worstErrorLocation.x, 5)
        XCTAssertEqual(report.worstErrorLocation.y, 0)
    }

    // MARK: - SSIM

    func testSSIMIdentical() throws {
        // Arrange: 16×16 gradient so SSIM has variance to work with
        var pixels = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 { pixels[i] = UInt8(i) }
        let img = makeGreyscaleImage(width: 16, height: 16, pixels: pixels)

        // Act
        let report = try J2KQualityMetricsEngine.computeReport(
            original: img, compared: img,
            originalLabel: "orig", comparedLabel: "comp",
            originalFileSize: 256, comparedFileSize: 256)

        // Assert
        XCTAssertEqual(report.globalSSIM, 1.0, accuracy: 1e-6)
    }

    func testSSIMDegraded() throws {
        // Arrange: gradient original, add noise to compared
        var origPixels = [UInt8](repeating: 0, count: 256)
        var compPixels = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            origPixels[i] = UInt8(i)
            // Deterministic "noise": every 3rd pixel offset by 20
            compPixels[i] = i.isMultiple(of: 3)
                ? UInt8(clamping: i + 20)
                : UInt8(i)
        }
        let original = makeGreyscaleImage(width: 16, height: 16, pixels: origPixels)
        let compared = makeGreyscaleImage(width: 16, height: 16, pixels: compPixels)

        // Act
        let report = try J2KQualityMetricsEngine.computeReport(
            original: original, compared: compared,
            originalLabel: "orig", comparedLabel: "comp",
            originalFileSize: 256, comparedFileSize: 256)

        // Assert: SSIM should be less than 1 but still high (small perturbation)
        XCTAssertLessThan(report.globalSSIM, 1.0)
        XCTAssertGreaterThan(report.globalSSIM, 0.8)
    }

    // MARK: - Dimension Mismatch

    func testMismatchedDimensionsThrows() throws {
        let a = makeGreyscaleImage(width: 8, height: 8, value: 100)
        let b = makeGreyscaleImage(width: 16, height: 8, value: 100)

        XCTAssertThrowsError(try J2KQualityMetricsEngine.computeReport(
            original: a, compared: b,
            originalLabel: "a", comparedLabel: "b",
            originalFileSize: 64, comparedFileSize: 128))
    }

    func testMismatchedComponentCountThrows() throws {
        let grey = makeGreyscaleImage(width: 8, height: 8, value: 100)
        let rgb = makeRGBImage(width: 8, height: 8, r: 100, g: 100, b: 100)

        XCTAssertThrowsError(try J2KQualityMetricsEngine.computeReport(
            original: grey, compared: rgb,
            originalLabel: "grey", comparedLabel: "rgb",
            originalFileSize: 64, comparedFileSize: 192))
    }

    // MARK: - Pixel Differences

    func testPixelDifferencesComputedCorrectly() throws {
        let origPixels: [UInt8] = [10, 20, 30, 40]
        let compPixels: [UInt8] = [12, 18, 30, 45]

        let origComp = J2KComponent(index: 0, bitDepth: 8, width: 2, height: 2, data: Data(origPixels))
        let compComp = J2KComponent(index: 0, bitDepth: 8, width: 2, height: 2, data: Data(compPixels))

        let diffs = J2KQualityMetricsEngine.pixelDifferences(original: origComp, compared: compComp)
        XCTAssertEqual(diffs, [-2, 2, 0, -5])
    }

    // MARK: - Compression Ratio

    func testCompressionRatioComputed() throws {
        let img = makeGreyscaleImage(width: 100, height: 100, value: 128)

        let report = try J2KQualityMetricsEngine.computeReport(
            original: img, compared: img,
            originalLabel: "orig", comparedLabel: "comp",
            originalFileSize: 10000, comparedFileSize: 2000)

        // Raw size = 100*100*1 = 10000; compressed = 2000; ratio = 5.0
        XCTAssertEqual(report.compressionRatio, 5.0, accuracy: 0.01)
    }

    // MARK: - Determinism

    func testResultsAreDeterministic() throws {
        var origPixels = [UInt8](repeating: 0, count: 256)
        var compPixels = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            origPixels[i] = UInt8(i)
            compPixels[i] = UInt8(clamping: i + (i.isMultiple(of: 7) ? 5 : 0))
        }
        let original = makeGreyscaleImage(width: 16, height: 16, pixels: origPixels)
        let compared = makeGreyscaleImage(width: 16, height: 16, pixels: compPixels)

        let report1 = try J2KQualityMetricsEngine.computeReport(
            original: original, compared: compared,
            originalLabel: "orig", comparedLabel: "comp",
            originalFileSize: 256, comparedFileSize: 256)

        let report2 = try J2KQualityMetricsEngine.computeReport(
            original: original, compared: compared,
            originalLabel: "orig", comparedLabel: "comp",
            originalFileSize: 256, comparedFileSize: 256)

        XCTAssertEqual(report1.globalPSNR, report2.globalPSNR)
        XCTAssertEqual(report1.globalSSIM, report2.globalSSIM)
        XCTAssertEqual(report1.globalMSE, report2.globalMSE)
        XCTAssertEqual(report1.globalMAE, report2.globalMAE)
        XCTAssertEqual(report1.globalMaxAbsoluteError, report2.globalMaxAbsoluteError)
    }
}
