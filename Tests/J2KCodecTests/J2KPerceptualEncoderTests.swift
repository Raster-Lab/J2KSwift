//
// J2KPerceptualEncoderTests.swift
// J2KSwift
//
// J2KPerceptualEncoderTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-19.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KPerceptualEncoderTests: XCTestCase {
    // MARK: - Quality Target Tests

    func testQualityTargetPSNR() {
        let target = J2KQualityTarget.psnr(40.0)

        if case .psnr(let value) = target {
            XCTAssertEqual(value, 40.0)
        } else {
            XCTFail("Expected PSNR target")
        }
    }

    func testQualityTargetSSIM() {
        let target = J2KQualityTarget.ssim(0.95)

        if case .ssim(let value) = target {
            XCTAssertEqual(value, 0.95)
        } else {
            XCTFail("Expected SSIM target")
        }
    }

    func testQualityTargetMSSSIM() {
        let target = J2KQualityTarget.msssim(0.98)

        if case .msssim(let value) = target {
            XCTAssertEqual(value, 0.98)
        } else {
            XCTFail("Expected MS-SSIM target")
        }
    }

    func testQualityTargetBitrate() {
        let target = J2KQualityTarget.bitrate(2.0)

        if case .bitrate(let value) = target {
            XCTAssertEqual(value, 2.0)
        } else {
            XCTFail("Expected bitrate target")
        }
    }

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = J2KPerceptualEncodingConfiguration.default

        if case .ssim(let value) = config.targetQuality {
            XCTAssertEqual(value, 0.95)
        } else {
            XCTFail("Expected SSIM target")
        }

        XCTAssertTrue(config.enableVisualMasking)
        XCTAssertTrue(config.enableFrequencyWeighting)
        XCTAssertEqual(config.maxIterations, 3)
        XCTAssertEqual(config.qualityTolerance, 0.01)
    }

    func testHighQualityConfiguration() {
        let config = J2KPerceptualEncodingConfiguration.highQuality

        if case .ssim(let value) = config.targetQuality {
            XCTAssertEqual(value, 0.98)
        } else {
            XCTFail("Expected SSIM target")
        }
    }

    func testBalancedConfiguration() {
        let config = J2KPerceptualEncodingConfiguration.balanced

        if case .msssim(let value) = config.targetQuality {
            XCTAssertEqual(value, 0.95)
        } else {
            XCTFail("Expected MS-SSIM target")
        }
    }

    func testHighCompressionConfiguration() {
        let config = J2KPerceptualEncodingConfiguration.highCompression

        if case .ssim(let value) = config.targetQuality {
            XCTAssertEqual(value, 0.90)
        } else {
            XCTFail("Expected SSIM target")
        }
    }

    func testCustomConfiguration() {
        let config = J2KPerceptualEncodingConfiguration(
            targetQuality: .psnr(45.0),
            enableVisualMasking: false,
            enableFrequencyWeighting: true,
            maxIterations: 5,
            qualityTolerance: 0.005
        )

        if case .psnr(let value) = config.targetQuality {
            XCTAssertEqual(value, 45.0)
        } else {
            XCTFail("Expected PSNR target")
        }

        XCTAssertFalse(config.enableVisualMasking)
        XCTAssertTrue(config.enableFrequencyWeighting)
        XCTAssertEqual(config.maxIterations, 5)
        XCTAssertEqual(config.qualityTolerance, 0.005)
    }

    // MARK: - Encoder Creation Tests

    func testEncoderCreation() {
        let encoder = J2KPerceptualEncoder()

        if case .ssim(let value) = encoder.configuration.targetQuality {
            XCTAssertEqual(value, 0.95)
        } else {
            XCTFail("Expected SSIM target")
        }
    }

    func testEncoderWithCustomConfiguration() {
        let config = J2KPerceptualEncodingConfiguration.highQuality
        let encoder = J2KPerceptualEncoder(configuration: config)

        if case .ssim(let value) = encoder.configuration.targetQuality {
            XCTAssertEqual(value, 0.98)
        } else {
            XCTFail("Expected SSIM target")
        }
    }

    // MARK: - Quantization Step Calculation Tests

    func testPerceptualQuantizationSteps() {
        let encoder = J2KPerceptualEncoder()
        let image = createTestImage(width: 512, height: 512)

        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.1,
            image: image,
            decompositionLevels: 3
        )

        // Should have steps for each level
        XCTAssertEqual(steps.count, 3)

        // Check that steps are valid
        for levelSteps in steps {
            for stepSize in levelSteps.values {
                XCTAssertGreaterThan(stepSize, 0.0)
            }
        }
    }

    func testQuantizationWithOnlyFrequencyWeighting() {
        let config = J2KPerceptualEncodingConfiguration(
            targetQuality: .ssim(0.95),
            enableVisualMasking: false,
            enableFrequencyWeighting: true
        )
        let encoder = J2KPerceptualEncoder(configuration: config)
        let image = createTestImage(width: 512, height: 512)

        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.1,
            image: image,
            decompositionLevels: 3
        )

        XCTAssertEqual(steps.count, 3)

        // Steps should vary by frequency (different for different subbands)
        let firstLevel = steps[0]
        let lhStep = firstLevel[.lh] ?? 0.0
        let hhStep = firstLevel[.hh] ?? 0.0

        // Steps should be different for different subbands
        XCTAssertNotEqual(lhStep, hhStep)
    }

    func testQuantizationWithOnlyMasking() {
        let config = J2KPerceptualEncodingConfiguration(
            targetQuality: .ssim(0.95),
            enableVisualMasking: true,
            enableFrequencyWeighting: false
        )
        let encoder = J2KPerceptualEncoder(configuration: config)
        let image = createTestImage(width: 512, height: 512)

        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: 0.1,
            image: image,
            decompositionLevels: 3
        )

        XCTAssertEqual(steps.count, 3)

        // All steps should be valid
        for levelSteps in steps {
            for stepSize in levelSteps.values {
                XCTAssertGreaterThan(stepSize, 0.0)
            }
        }
    }

    func testQuantizationWithoutPerceptualFeatures() {
        let config = J2KPerceptualEncodingConfiguration(
            targetQuality: .ssim(0.95),
            enableVisualMasking: false,
            enableFrequencyWeighting: false
        )
        let encoder = J2KPerceptualEncoder(configuration: config)
        let image = createTestImage(width: 512, height: 512)
        let baseQuant = 0.1

        let steps = encoder.calculatePerceptualQuantizationSteps(
            baseQuantization: baseQuant,
            image: image,
            decompositionLevels: 3
        )

        // Without perceptual features, all steps should be equal to base
        for levelSteps in steps {
            for stepSize in levelSteps.values {
                XCTAssertEqual(stepSize, baseQuant, accuracy: 0.0001)
            }
        }
    }

    // MARK: - Spatially-Varying Quantization Tests

    func testSpatiallyVaryingQuantization() {
        let encoder = J2KPerceptualEncoder()

        let width = 32
        let height = 32
        let samples = [Int32](repeating: 128, count: width * height)

        let steps = encoder.calculateSpatiallyVaryingQuantization(
            samples: samples,
            width: width,
            height: height,
            bitDepth: 8,
            baseQuantization: 0.1,
            subband: .hh,
            decompositionLevel: 1,
            totalLevels: 3
        )

        XCTAssertEqual(steps.count, width * height)

        // All steps should be positive
        for step in steps {
            XCTAssertGreaterThan(step, 0.0)
        }
    }

    func testSpatiallyVaryingQuantizationTexturedRegion() {
        let encoder = J2KPerceptualEncoder()

        let width = 32
        let height = 32

        // Create textured samples (checkerboard pattern)
        var samples = [Int32]()
        for y in 0..<height {
            for x in 0..<width {
                let value: Int32 = ((x + y).isMultiple(of: 2)) ? 50 : 200
                samples.append(value)
            }
        }

        let steps = encoder.calculateSpatiallyVaryingQuantization(
            samples: samples,
            width: width,
            height: height,
            bitDepth: 8,
            baseQuantization: 0.1,
            subband: .hh,
            decompositionLevel: 1,
            totalLevels: 3
        )

        XCTAssertEqual(steps.count, width * height)

        // Steps should vary due to texture masking
        let uniqueSteps = Set(steps)
        XCTAssertGreaterThan(uniqueSteps.count, 1)
    }

    // MARK: - Base Quantization Estimation Tests

    func testEstimateBaseQuantizationHighBitrate() {
        let encoder = J2KPerceptualEncoder()

        let baseQuant = encoder.estimateBaseQuantization(
            targetBitrate: 4.0,
            imageSize: 512 * 512
        )

        // High bitrate should produce low quantization
        XCTAssertLessThan(baseQuant, 0.05)
    }

    func testEstimateBaseQuantizationMediumBitrate() {
        let encoder = J2KPerceptualEncoder()

        let baseQuant = encoder.estimateBaseQuantization(
            targetBitrate: 1.0,
            imageSize: 512 * 512
        )

        // Medium bitrate should produce medium quantization
        XCTAssertGreaterThan(baseQuant, 0.05)
        XCTAssertLessThan(baseQuant, 0.3)
    }

    func testEstimateBaseQuantizationLowBitrate() {
        let encoder = J2KPerceptualEncoder()

        let baseQuant = encoder.estimateBaseQuantization(
            targetBitrate: 0.25,
            imageSize: 512 * 512
        )

        // Low bitrate should produce high quantization
        XCTAssertGreaterThan(baseQuant, 0.3)
    }

    func testEstimateBaseQuantizationOrdering() {
        let encoder = J2KPerceptualEncoder()

        let quant1 = encoder.estimateBaseQuantization(targetBitrate: 4.0, imageSize: 1000)
        let quant2 = encoder.estimateBaseQuantization(targetBitrate: 2.0, imageSize: 1000)
        let quant3 = encoder.estimateBaseQuantization(targetBitrate: 0.5, imageSize: 1000)

        // Higher bitrate should produce lower quantization
        XCTAssertLessThan(quant1, quant2)
        XCTAssertLessThan(quant2, quant3)
    }

    // MARK: - Quantization Adjustment Tests

    func testAdjustQuantizationQualityTooLow() {
        let encoder = J2KPerceptualEncoder()

        let adjusted = encoder.adjustQuantization(
            currentQuantization: 0.1,
            targetQuality: 0.95,
            achievedQuality: 0.90
        )

        // Quality too low, should decrease quantization
        XCTAssertLessThan(adjusted, 0.1)
    }

    func testAdjustQuantizationQualityTooHigh() {
        let encoder = J2KPerceptualEncoder()

        let adjusted = encoder.adjustQuantization(
            currentQuantization: 0.1,
            targetQuality: 0.95,
            achievedQuality: 0.98
        )

        // Quality too high, should increase quantization
        XCTAssertGreaterThan(adjusted, 0.1)
    }

    func testAdjustQuantizationQualityPerfect() {
        let encoder = J2KPerceptualEncoder()

        let adjusted = encoder.adjustQuantization(
            currentQuantization: 0.1,
            targetQuality: 0.95,
            achievedQuality: 0.95
        )

        // Quality perfect, should stay close to current
        XCTAssertEqual(adjusted, 0.1, accuracy: 0.01)
    }

    func testAdjustQuantizationClamping() {
        let encoder = J2KPerceptualEncoder()

        // Test lower bound clamping
        let adjustedLow = encoder.adjustQuantization(
            currentQuantization: 0.001,
            targetQuality: 0.95,
            achievedQuality: 0.80
        )
        XCTAssertGreaterThanOrEqual(adjustedLow, 0.001)

        // Test upper bound clamping
        let adjustedHigh = encoder.adjustQuantization(
            currentQuantization: 0.9,
            targetQuality: 0.95,
            achievedQuality: 0.99
        )
        XCTAssertLessThanOrEqual(adjustedHigh, 1.0)
    }

    // MARK: - Quality Evaluation Tests

    func testEvaluateQualityPSNR() throws {
        let config = J2KPerceptualEncodingConfiguration(targetQuality: .psnr(40.0))
        let encoder = J2KPerceptualEncoder(configuration: config)

        let original = createTestImage(width: 64, height: 64)
        let encoded = createTestImage(width: 64, height: 64)  // Same for now

        let result = try encoder.evaluateQuality(original: original, encoded: encoded)

        // Should return a PSNR result
        XCTAssertGreaterThan(result.value, 0.0)
    }

    func testEvaluateQualitySSIM() throws {
        let config = J2KPerceptualEncodingConfiguration(targetQuality: .ssim(0.95))
        let encoder = J2KPerceptualEncoder(configuration: config)

        let original = createTestImage(width: 64, height: 64)
        let encoded = createTestImage(width: 64, height: 64)

        let result = try encoder.evaluateQuality(original: original, encoded: encoded)

        // Should return an SSIM result
        XCTAssertGreaterThanOrEqual(result.value, 0.0)
        XCTAssertLessThanOrEqual(result.value, 1.0)
    }

    func testCalculateAllQualityMetrics() throws {
        let encoder = J2KPerceptualEncoder()

        let original = createTestImage(width: 64, height: 64)
        let encoded = createTestImage(width: 64, height: 64)

        let results = try encoder.calculateAllQualityMetrics(
            original: original,
            encoded: encoded
        )

        XCTAssertNotNil(results["PSNR"])
        XCTAssertNotNil(results["SSIM"])
        XCTAssertNotNil(results["MS-SSIM"])

        XCTAssertEqual(results.count, 3)
    }

    // MARK: - Result Tests

    func testEncodingResultCreation() {
        let data = Data([0x00, 0x01, 0x02])
        let quality = J2KQualityMetricResult(value: 0.95)

        let result = J2KPerceptualEncodingResult(
            data: data,
            achievedQuality: quality,
            iterations: 2,
            bitrate: 1.5
        )

        XCTAssertEqual(result.data, data)
        XCTAssertEqual(result.achievedQuality.value, 0.95)
        XCTAssertEqual(result.iterations, 2)
        XCTAssertEqual(result.bitrate, 1.5)
    }

    // MARK: - Sendable Conformance Tests

    func testSendableConformance() {
        let encoder = J2KPerceptualEncoder()
        let image = createTestImage(width: 64, height: 64)

        Task {
            let steps = encoder.calculatePerceptualQuantizationSteps(
                baseQuantization: 0.1,
                image: image,
                decompositionLevels: 3
            )
            XCTAssertGreaterThan(steps.count, 0)
        }
    }

    // MARK: - Helper Methods

    private func createTestImage(width: Int, height: Int) -> J2KImage {
        let componentSize = width * height
        var data = Data(count: componentSize * 4)  // Int32 per pixel

        data.withUnsafeMutableBytes { buffer in
            let int32Buffer = buffer.bindMemory(to: Int32.self)
            for i in 0..<componentSize {
                int32Buffer[i] = 128  // Mid-gray
            }
        }

        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: data
        )

        return J2KImage(
            width: width,
            height: height,
            components: [component],
            colorSpace: .grayscale
        )
    }
}
