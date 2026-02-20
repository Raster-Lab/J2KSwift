// J2KQualityMetricsTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

// MARK: - Quality Metrics Random Number Generator

private struct QualityMetricsSeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class J2KQualityMetricsTests: XCTestCase {
    // MARK: - Helper Methods

    func createTestImage(
        width: Int,
        height: Int,
        componentCount: Int = 1,
        bitDepth: Int = 8,
        fillValue: Int32 = 128
    ) -> J2KImage {
        let sampleCount = width * height
        let samples = [Int32](repeating: fillValue, count: sampleCount)

        // Convert samples to Data
        var data = Data(count: sampleCount * MemoryLayout<Int32>.size)
        data.withUnsafeMutableBytes { buffer in
            let int32Ptr = buffer.bindMemory(to: Int32.self)
            for i in 0..<sampleCount {
                int32Ptr[i] = samples[i]
            }
        }

        let components = (0..<componentCount).map { index in
            J2KComponent(
                index: index,
                bitDepth: bitDepth,
                signed: false,
                width: width,
                height: height,
                data: data
            )
        }

        return J2KImage(
            width: width,
            height: height,
            components: components
        )
    }

    func createNoiseImage(
        width: Int,
        height: Int,
        componentCount: Int = 1,
        bitDepth: Int = 8,
        seed: UInt64 = 42
    ) -> J2KImage {
        var rng = QualityMetricsSeededRandom(seed: seed)
        let sampleCount = width * height
        let maxValue = (1 << bitDepth) - 1

        let components = (0..<componentCount).map { index in
            let samples = (0..<sampleCount).map { _ in
                Int32.random(in: 0...Int32(maxValue), using: &rng)
            }

            // Convert samples to Data
            var data = Data(count: sampleCount * MemoryLayout<Int32>.size)
            data.withUnsafeMutableBytes { buffer in
                let int32Ptr = buffer.bindMemory(to: Int32.self)
                for i in 0..<sampleCount {
                    int32Ptr[i] = samples[i]
                }
            }

            return J2KComponent(
                index: index,
                bitDepth: bitDepth,
                signed: false,
                width: width,
                height: height,
                data: data
            )
        }

        return J2KImage(
            width: width,
            height: height,
            components: components
        )
    }

    func addNoise(
        to image: J2KImage,
        noiseLevel: Int32,
        seed: UInt64 = 123
    ) -> J2KImage {
        var rng = QualityMetricsSeededRandom(seed: seed)

        let noisyComponents = image.components.map { comp in
            // Extract original samples
            var samples = [Int32](repeating: 0, count: comp.width * comp.height)
            comp.data.withUnsafeBytes { buffer in
                let int32Ptr = buffer.bindMemory(to: Int32.self)
                for i in 0..<samples.count {
                    samples[i] = int32Ptr[i]
                }
            }

            // Add noise
            let noisySamples = samples.map { sample in
                let noise = Int32.random(in: -noiseLevel...noiseLevel, using: &rng)
                let noisyValue = sample + noise
                let maxValue = Int32((1 << comp.bitDepth) - 1)
                return max(0, min(maxValue, noisyValue))
            }

            // Convert back to Data
            var data = Data(count: noisySamples.count * MemoryLayout<Int32>.size)
            data.withUnsafeMutableBytes { buffer in
                let int32Ptr = buffer.bindMemory(to: Int32.self)
                for i in 0..<noisySamples.count {
                    int32Ptr[i] = noisySamples[i]
                }
            }

            return J2KComponent(
                index: comp.index,
                bitDepth: comp.bitDepth,
                signed: comp.signed,
                width: comp.width,
                height: comp.height,
                data: data
            )
        }

        return J2KImage(
            width: image.width,
            height: image.height,
            components: noisyComponents,
            colorSpace: image.colorSpace
        )
    }

    // MARK: - PSNR Tests

    func testPSNRIdenticalImages() throws {
        let metrics = J2KQualityMetrics()
        let image = createTestImage(width: 64, height: 64)

        let result = try metrics.psnr(original: image, compressed: image)

        // Identical images should have infinite PSNR
        XCTAssertEqual(result.value, Double.infinity)
    }

    func testPSNRWithNoise() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 64, height: 64, fillValue: 128)
        let noisy = addNoise(to: original, noiseLevel: 10)

        let result = try metrics.psnr(original: original, compressed: noisy)

        // Should have finite PSNR
        XCTAssertFalse(result.value.isInfinite)
        XCTAssertGreaterThan(result.value, 0.0)

        // Small noise should give high PSNR
        XCTAssertGreaterThan(result.value, 20.0)  // Typically > 30dB for good quality
    }

    func testPSNRMultiComponent() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 64, height: 64, componentCount: 3)
        let noisy = addNoise(to: original, noiseLevel: 5)

        let result = try metrics.psnr(original: original, compressed: noisy)

        // Should have per-component values
        XCTAssertNotNil(result.componentValues)
        XCTAssertEqual(result.componentValues?.count, 3)

        // All component PSNRs should be valid
        for componentPSNR in result.componentValues! {
            XCTAssertGreaterThan(componentPSNR, 0.0)
        }
    }

    func testPSNRHigherWithLessNoise() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 64, height: 64)

        let lessNoisy = addNoise(to: original, noiseLevel: 5)
        let moreNoisy = addNoise(to: original, noiseLevel: 20)

        let resultLess = try metrics.psnr(original: original, compressed: lessNoisy)
        let resultMore = try metrics.psnr(original: original, compressed: moreNoisy)

        // Less noise should have higher PSNR
        XCTAssertGreaterThan(resultLess.value, resultMore.value)
    }

    func testPSNRDifferentSizesError() {
        let metrics = J2KQualityMetrics()
        let image1 = createTestImage(width: 64, height: 64)
        let image2 = createTestImage(width: 32, height: 32)

        XCTAssertThrowsError(try metrics.psnr(original: image1, compressed: image2))
    }

    // MARK: - SSIM Tests

    func testSSIMIdenticalImages() throws {
        let metrics = J2KQualityMetrics()
        let image = createTestImage(width: 64, height: 64)

        let result = try metrics.ssim(original: image, compressed: image)

        // Identical images should have SSIM = 1.0
        XCTAssertEqual(result.value, 1.0, accuracy: 0.001)
    }

    func testSSIMWithNoise() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 64, height: 64, fillValue: 128)
        let noisy = addNoise(to: original, noiseLevel: 10)

        let result = try metrics.ssim(original: original, compressed: noisy)

        // SSIM should be between 0 and 1
        XCTAssertGreaterThan(result.value, 0.0)
        XCTAssertLessThanOrEqual(result.value, 1.0)

        // Small noise should still give reasonable SSIM
        XCTAssertGreaterThan(result.value, 0.5)
    }

    func testSSIMMultiComponent() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 64, height: 64, componentCount: 3)
        let noisy = addNoise(to: original, noiseLevel: 5)

        let result = try metrics.ssim(original: original, compressed: noisy)

        // Should have per-component values
        XCTAssertNotNil(result.componentValues)
        XCTAssertEqual(result.componentValues?.count, 3)

        // All component SSIMs should be valid
        for componentSSIM in result.componentValues! {
            XCTAssertGreaterThan(componentSSIM, 0.0)
            XCTAssertLessThanOrEqual(componentSSIM, 1.0)
        }
    }

    func testSSIMHigherWithLessNoise() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 64, height: 64)

        let lessNoisy = addNoise(to: original, noiseLevel: 5)
        let moreNoisy = addNoise(to: original, noiseLevel: 20)

        let resultLess = try metrics.ssim(original: original, compressed: lessNoisy)
        let resultMore = try metrics.ssim(original: original, compressed: moreNoisy)

        // Less noise should have higher SSIM
        XCTAssertGreaterThan(resultLess.value, resultMore.value)
    }

    func testSSIMDifferentImages() throws {
        let metrics = J2KQualityMetrics()
        let image1 = createTestImage(width: 64, height: 64, fillValue: 50)
        let image2 = createTestImage(width: 64, height: 64, fillValue: 200)

        let result = try metrics.ssim(original: image1, compressed: image2)

        // Very different images should have low SSIM
        XCTAssertLessThan(result.value, 0.5)
    }

    // MARK: - MS-SSIM Tests

    func testMSSSIMIdenticalImages() throws {
        let metrics = J2KQualityMetrics()
        let image = createTestImage(width: 128, height: 128)

        let result = try metrics.msssim(original: image, compressed: image, scales: 3)

        // Identical images should have MS-SSIM = 1.0
        XCTAssertEqual(result.value, 1.0, accuracy: 0.001)
    }

    func testMSSSIMWithNoise() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 128, height: 128, fillValue: 128)
        let noisy = addNoise(to: original, noiseLevel: 10)

        let result = try metrics.msssim(original: original, compressed: noisy, scales: 3)

        // MS-SSIM should be between 0 and 1
        XCTAssertGreaterThan(result.value, 0.0)
        XCTAssertLessThanOrEqual(result.value, 1.0)
    }

    func testMSSSIMDifferentScales() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 128, height: 128)
        let noisy = addNoise(to: original, noiseLevel: 10)

        let result3 = try metrics.msssim(original: original, compressed: noisy, scales: 3)
        let result5 = try metrics.msssim(original: original, compressed: noisy, scales: 5)

        // Both should be valid (between 0 and 1)
        XCTAssertGreaterThanOrEqual(result3.value, 0.0)
        XCTAssertGreaterThanOrEqual(result5.value, 0.0)
        XCTAssertLessThanOrEqual(result3.value, 1.0)
        XCTAssertLessThanOrEqual(result5.value, 1.0)
    }

    func testMSSSIMInvalidScales() {
        let metrics = J2KQualityMetrics()
        let image = createTestImage(width: 128, height: 128)

        // Too few scales
        XCTAssertThrowsError(try metrics.msssim(original: image, compressed: image, scales: 0))

        // Too many scales
        XCTAssertThrowsError(try metrics.msssim(original: image, compressed: image, scales: 10))
    }

    func testMSSSIMImageTooSmall() {
        let metrics = J2KQualityMetrics()
        let image = createTestImage(width: 8, height: 8)

        // Image too small for 5 scales (would require 128x128 minimum)
        XCTAssertThrowsError(try metrics.msssim(original: image, compressed: image, scales: 5))
    }

    // MARK: - Comparison Tests

    func testPSNRvsSSIMCorrelation() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 64, height: 64)

        // Create images with different noise levels
        let noise1 = addNoise(to: original, noiseLevel: 5, seed: 1)
        let noise2 = addNoise(to: original, noiseLevel: 15, seed: 2)

        let psnr1 = try metrics.psnr(original: original, compressed: noise1)
        let psnr2 = try metrics.psnr(original: original, compressed: noise2)
        let ssim1 = try metrics.ssim(original: original, compressed: noise1)
        let ssim2 = try metrics.ssim(original: original, compressed: noise2)

        // Both metrics should rank images in the same order
        if psnr1.value > psnr2.value {
            XCTAssertGreaterThan(ssim1.value, ssim2.value)
        }
    }

    // MARK: - Result Description Tests

    func testResultDescription() {
        let result1 = J2KQualityMetricResult(value: 35.5)
        XCTAssertEqual(result1.description, "35.50")

        let result2 = J2KQualityMetricResult(value: Double.infinity)
        XCTAssertTrue(result2.description.contains("∞") || result2.description.contains("Perfect"))

        let result3 = J2KQualityMetricResult(
            value: 32.0,
            componentValues: [31.5, 32.0, 32.5]
        )
        XCTAssertTrue(result3.description.contains("32.00"))
        XCTAssertTrue(result3.description.contains("components"))
    }

    // MARK: - Edge Cases

    func testAllZeroImages() throws {
        let metrics = J2KQualityMetrics()
        let image = createTestImage(width: 64, height: 64, fillValue: 0)

        let psnrResult = try metrics.psnr(original: image, compressed: image)
        XCTAssertEqual(psnrResult.value, Double.infinity)

        let ssimResult = try metrics.ssim(original: image, compressed: image)
        XCTAssertEqual(ssimResult.value, 1.0, accuracy: 0.001)
    }

    func testAllMaxValueImages() throws {
        let metrics = J2KQualityMetrics()
        let maxValue: Int32 = 255
        let image = createTestImage(width: 64, height: 64, fillValue: maxValue)

        let psnrResult = try metrics.psnr(original: image, compressed: image)
        XCTAssertEqual(psnrResult.value, Double.infinity)

        let ssimResult = try metrics.ssim(original: image, compressed: image)
        XCTAssertEqual(ssimResult.value, 1.0, accuracy: 0.001)
    }

    func testSinglePixelDifference() throws {
        let metrics = J2KQualityMetrics()
        let original = createTestImage(width: 16, height: 16, fillValue: 128)

        // Create copy with one pixel different
        var modifiedSamples = [Int32](repeating: 128, count: 16 * 16)
        modifiedSamples[0] = 129

        // Convert to Data
        var data = Data(count: modifiedSamples.count * MemoryLayout<Int32>.size)
        data.withUnsafeMutableBytes { buffer in
            let int32Ptr = buffer.bindMemory(to: Int32.self)
            for i in 0..<modifiedSamples.count {
                int32Ptr[i] = modifiedSamples[i]
            }
        }

        let modified = J2KImage(
            width: 16,
            height: 16,
            components: [J2KComponent(
                index: 0,
                bitDepth: 8,
                signed: false,
                width: 16,
                height: 16,
                data: data
            )]
        )

        let psnrResult = try metrics.psnr(original: original, compressed: modified)
        XCTAssertFalse(psnrResult.value.isInfinite)
        XCTAssertGreaterThan(psnrResult.value, 40.0)  // Very high but not infinite

        let ssimResult = try metrics.ssim(original: original, compressed: modified)
        XCTAssertGreaterThan(ssimResult.value, 0.95)  // Very close to 1
    }

    // MARK: - Sendable Conformance Test

    func testSendableConformance() {
        let metrics = J2KQualityMetrics()
        let image = createTestImage(width: 64, height: 64)

        Task {
            let result = try? metrics.psnr(original: image, compressed: image)
            XCTAssertNotNil(result)
        }
    }
}
