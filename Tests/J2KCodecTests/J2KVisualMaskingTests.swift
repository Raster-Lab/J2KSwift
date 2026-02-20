// J2KVisualMaskingTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-19.
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KVisualMaskingTests: XCTestCase {
    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let config = J2KVisualMaskingConfiguration.default

        XCTAssertTrue(config.enableLuminanceMasking)
        XCTAssertTrue(config.enableTextureMasking)
        XCTAssertFalse(config.enableMotionMasking)
        XCTAssertEqual(config.luminanceStrength, 0.5)
        XCTAssertEqual(config.textureStrength, 0.7)
        XCTAssertEqual(config.motionStrength, 0.6)
        XCTAssertEqual(config.minimumFactor, 0.5)
        XCTAssertEqual(config.maximumFactor, 3.0)
    }

    func testAggressiveConfiguration() {
        let config = J2KVisualMaskingConfiguration.aggressive

        XCTAssertEqual(config.luminanceStrength, 0.8)
        XCTAssertEqual(config.textureStrength, 0.9)
        XCTAssertEqual(config.minimumFactor, 0.3)
        XCTAssertEqual(config.maximumFactor, 4.0)
    }

    func testConservativeConfiguration() {
        let config = J2KVisualMaskingConfiguration.conservative

        XCTAssertEqual(config.luminanceStrength, 0.3)
        XCTAssertEqual(config.textureStrength, 0.5)
        XCTAssertEqual(config.minimumFactor, 0.7)
        XCTAssertEqual(config.maximumFactor, 2.0)
    }

    func testCustomConfiguration() {
        let config = J2KVisualMaskingConfiguration(
            enableLuminanceMasking: false,
            enableTextureMasking: true,
            enableMotionMasking: true,
            luminanceStrength: 0.6,
            textureStrength: 0.8,
            motionStrength: 0.7,
            minimumFactor: 0.4,
            maximumFactor: 3.5
        )

        XCTAssertFalse(config.enableLuminanceMasking)
        XCTAssertTrue(config.enableTextureMasking)
        XCTAssertTrue(config.enableMotionMasking)
        XCTAssertEqual(config.luminanceStrength, 0.6)
        XCTAssertEqual(config.textureStrength, 0.8)
        XCTAssertEqual(config.motionStrength, 0.7)
        XCTAssertEqual(config.minimumFactor, 0.4)
        XCTAssertEqual(config.maximumFactor, 3.5)
    }

    // MARK: - Motion Vector Tests

    func testMotionVectorCreation() {
        let mv = J2KMotionVector(dx: 3.0, dy: 4.0)

        XCTAssertEqual(mv.dx, 3.0)
        XCTAssertEqual(mv.dy, 4.0)
        XCTAssertEqual(mv.magnitude, 5.0, accuracy: 0.001)
    }

    func testZeroMotionVector() {
        let mv = J2KMotionVector.zero

        XCTAssertEqual(mv.dx, 0.0)
        XCTAssertEqual(mv.dy, 0.0)
        XCTAssertEqual(mv.magnitude, 0.0)
    }

    func testMotionVectorMagnitude() {
        let mv1 = J2KMotionVector(dx: 1.0, dy: 0.0)
        XCTAssertEqual(mv1.magnitude, 1.0)

        let mv2 = J2KMotionVector(dx: 0.0, dy: 1.0)
        XCTAssertEqual(mv2.magnitude, 1.0)

        let mv3 = J2KMotionVector(dx: 3.0, dy: 4.0)
        XCTAssertEqual(mv3.magnitude, 5.0, accuracy: 0.001)

        let mv4 = J2KMotionVector(dx: -3.0, dy: -4.0)
        XCTAssertEqual(mv4.magnitude, 5.0, accuracy: 0.001)
    }

    // MARK: - Luminance Masking Tests

    func testLuminanceMaskingMidGray() {
        let masking = J2KVisualMasking()

        // Mid-gray (127.5) should have minimum masking
        let factor = masking.luminanceMaskingFactor(luminance: 127.5)

        // Should be close to 1.0 (minimal masking at mid-gray)
        XCTAssertGreaterThanOrEqual(factor, 1.0)
        XCTAssertLessThan(factor, 1.1)
    }

    func testLuminanceMaskingBlack() {
        let masking = J2KVisualMasking()

        // Black (0) should have high masking
        let factor = masking.luminanceMaskingFactor(luminance: 0.0)

        // Should be significantly greater than 1.0
        XCTAssertGreaterThan(factor, 1.4)
    }

    func testLuminanceMaskingWhite() {
        let masking = J2KVisualMasking()

        // White (255) should have high masking
        let factor = masking.luminanceMaskingFactor(luminance: 255.0)

        // Should be significantly greater than 1.0
        XCTAssertGreaterThan(factor, 1.4)
    }

    func testLuminanceMaskingSymmetry() {
        let masking = J2KVisualMasking()

        // Masking should be symmetric around mid-gray
        let darkFactor = masking.luminanceMaskingFactor(luminance: 50.0)
        let brightFactor = masking.luminanceMaskingFactor(luminance: 205.0)  // 255 - 50

        // Should be approximately equal
        XCTAssertEqual(darkFactor, brightFactor, accuracy: 0.01)
    }

    // MARK: - Texture Masking Tests

    func testTextureMaskingZeroVariance() {
        let masking = J2KVisualMasking()

        // Zero variance (flat region) should have minimal masking
        let factor = masking.textureMaskingFactor(variance: 0.0)

        // Should be close to 1.0
        XCTAssertGreaterThanOrEqual(factor, 1.0)
        XCTAssertLessThan(factor, 1.1)
    }

    func testTextureMaskingHighVariance() {
        let masking = J2KVisualMasking()

        // High variance (textured region) should have high masking
        let factor = masking.textureMaskingFactor(variance: 5000.0)

        // Should be significantly greater than 1.0
        XCTAssertGreaterThan(factor, 2.0)
    }

    func testTextureMaskingIncreases() {
        let masking = J2KVisualMasking()

        // Masking should increase with variance
        let factor1 = masking.textureMaskingFactor(variance: 100.0)
        let factor2 = masking.textureMaskingFactor(variance: 500.0)
        let factor3 = masking.textureMaskingFactor(variance: 2000.0)

        XCTAssertLessThan(factor1, factor2)
        XCTAssertLessThan(factor2, factor3)
    }

    // MARK: - Motion Masking Tests

    func testMotionMaskingZeroMotion() {
        let masking = J2KVisualMasking()

        // Zero motion should have minimal masking
        let factor = masking.motionMaskingFactor(motionVector: .zero)

        // Should be close to 1.0
        XCTAssertGreaterThanOrEqual(factor, 1.0)
        XCTAssertLessThan(factor, 1.1)
    }

    func testMotionMaskingHighMotion() {
        let masking = J2KVisualMasking()

        // High motion should have high masking
        let mv = J2KMotionVector(dx: 15.0, dy: 20.0)
        let factor = masking.motionMaskingFactor(motionVector: mv)

        // Should be significantly greater than 1.0
        XCTAssertGreaterThan(factor, 1.5)
    }

    func testMotionMaskingIncreases() {
        let masking = J2KVisualMasking()

        // Masking should increase with motion magnitude
        let mv1 = J2KMotionVector(dx: 2.0, dy: 0.0)
        let mv2 = J2KMotionVector(dx: 5.0, dy: 0.0)
        let mv3 = J2KMotionVector(dx: 15.0, dy: 0.0)

        let factor1 = masking.motionMaskingFactor(motionVector: mv1)
        let factor2 = masking.motionMaskingFactor(motionVector: mv2)
        let factor3 = masking.motionMaskingFactor(motionVector: mv3)

        XCTAssertLessThan(factor1, factor2)
        XCTAssertLessThan(factor2, factor3)
    }

    // MARK: - Combined Masking Tests

    func testCombinedMaskingBasic() {
        let masking = J2KVisualMasking()

        // Test combined masking with typical values
        let factor = masking.calculateMaskingFactor(
            luminance: 128.0,
            localVariance: 100.0,
            motionVector: nil
        )

        // Should be within valid range
        XCTAssertGreaterThanOrEqual(factor, 0.5)
        XCTAssertLessThanOrEqual(factor, 3.0)
    }

    func testCombinedMaskingWithMotion() {
        let config = J2KVisualMaskingConfiguration(enableMotionMasking: true)
        let masking = J2KVisualMasking(configuration: config)

        let mv = J2KMotionVector(dx: 5.0, dy: 5.0)
        let factor = masking.calculateMaskingFactor(
            luminance: 128.0,
            localVariance: 100.0,
            motionVector: mv
        )

        // Should be within valid range
        XCTAssertGreaterThanOrEqual(factor, 0.5)
        XCTAssertLessThanOrEqual(factor, 3.0)
    }

    func testCombinedMaskingBounds() {
        let masking = J2KVisualMasking()

        // Test with extreme values to verify clamping
        let factor1 = masking.calculateMaskingFactor(
            luminance: 0.0,
            localVariance: 10000.0,
            motionVector: nil
        )

        // Should be clamped to maximum
        XCTAssertLessThanOrEqual(factor1, 3.0)

        let factor2 = masking.calculateMaskingFactor(
            luminance: 127.5,
            localVariance: 0.0,
            motionVector: nil
        )

        // Should be clamped to minimum
        XCTAssertGreaterThanOrEqual(factor2, 0.5)
    }

    func testLuminanceMaskingDisabled() {
        let config = J2KVisualMaskingConfiguration(enableLuminanceMasking: false)
        let masking = J2KVisualMasking(configuration: config)

        // Luminance should not affect masking
        let factor1 = masking.calculateMaskingFactor(
            luminance: 0.0,
            localVariance: 100.0,
            motionVector: nil
        )

        let factor2 = masking.calculateMaskingFactor(
            luminance: 255.0,
            localVariance: 100.0,
            motionVector: nil
        )

        // Should be approximately equal (small differences due to texture masking)
        XCTAssertEqual(factor1, factor2, accuracy: 0.1)
    }

    // MARK: - Region Masking Tests

    func testRegionMaskingUniformImage() {
        let masking = J2KVisualMasking()

        // Create uniform image (all same value)
        let width = 32
        let height = 32
        let samples = [Int32](repeating: 128, count: width * height)

        let factors = masking.calculateRegionMaskingFactors(
            samples: samples,
            width: width,
            height: height,
            bitDepth: 8,
            motionField: nil
        )

        XCTAssertEqual(factors.count, width * height)

        // All factors should be similar for uniform image
        let avgFactor = factors.reduce(0.0, +) / Double(factors.count)
        for factor in factors {
            XCTAssertEqual(factor, avgFactor, accuracy: 0.2)
        }
    }

    func testRegionMaskingTexturedImage() {
        let masking = J2KVisualMasking()

        // Create textured image with varying values
        let width = 32
        let height = 32
        var samples = [Int32]()
        for y in 0..<height {
            for x in 0..<width {
                // Checkerboard pattern creates high variance
                let value: Int32 = ((x + y) % 2 == 0) ? 50 : 200
                samples.append(value)
            }
        }

        let factors = masking.calculateRegionMaskingFactors(
            samples: samples,
            width: width,
            height: height,
            bitDepth: 8,
            motionField: nil
        )

        XCTAssertEqual(factors.count, width * height)

        // Should have valid factors
        for factor in factors {
            XCTAssertGreaterThanOrEqual(factor, 0.5)
            XCTAssertLessThanOrEqual(factor, 3.0)
        }
    }

    func testRegionMaskingWithMotionField() {
        let config = J2KVisualMaskingConfiguration(enableMotionMasking: true)
        let masking = J2KVisualMasking(configuration: config)

        let width = 16
        let height = 16
        let samples = [Int32](repeating: 128, count: width * height)

        // Create motion field with varying motion
        var motionField = [[J2KMotionVector]]()
        for _ in 0..<height {
            var row = [J2KMotionVector]()
            for x in 0..<width {
                // More motion on the right side
                let dx = Double(x) / 2.0
                row.append(J2KMotionVector(dx: dx, dy: 0.0))
            }
            motionField.append(row)
        }

        let factors = masking.calculateRegionMaskingFactors(
            samples: samples,
            width: width,
            height: height,
            bitDepth: 8,
            motionField: motionField
        )

        XCTAssertEqual(factors.count, width * height)

        // Factors on the right should be higher due to motion
        let leftFactor = factors[0]  // (0, 0)
        let rightFactor = factors[width - 1]  // (width-1, 0)
        XCTAssertLessThan(leftFactor, rightFactor)
    }

    func testRegionMaskingInvalidSize() {
        let masking = J2KVisualMasking()

        // Mismatched size should return default factors
        let samples = [Int32](repeating: 128, count: 10)
        let factors = masking.calculateRegionMaskingFactors(
            samples: samples,
            width: 8,
            height: 8,
            bitDepth: 8,
            motionField: nil
        )

        // Should still return correct count
        XCTAssertEqual(factors.count, 64)

        // Should all be 1.0 (default)
        for factor in factors {
            XCTAssertEqual(factor, 1.0)
        }
    }

    // MARK: - JND Model Tests

    func testJNDThresholdBasic() {
        let jnd = J2KJNDModel()

        let threshold = jnd.jndThreshold(
            luminance: 128.0,
            localVariance: 100.0,
            viewingDistance: 60.0
        )

        // Should be positive
        XCTAssertGreaterThan(threshold, 0.0)
    }

    func testJNDThresholdIncreasesWithVariance() {
        let jnd = J2KJNDModel()

        let threshold1 = jnd.jndThreshold(luminance: 128.0, localVariance: 10.0)
        let threshold2 = jnd.jndThreshold(luminance: 128.0, localVariance: 100.0)
        let threshold3 = jnd.jndThreshold(luminance: 128.0, localVariance: 1000.0)

        // JND should increase with variance (more texture masking)
        XCTAssertLessThan(threshold1, threshold2)
        XCTAssertLessThan(threshold2, threshold3)
    }

    func testJNDThresholdViewingDistance() {
        let jnd = J2KJNDModel()

        // Closer viewing should have lower threshold (more visible distortion)
        let thresholdClose = jnd.jndThreshold(
            luminance: 128.0,
            localVariance: 100.0,
            viewingDistance: 30.0
        )

        let thresholdFar = jnd.jndThreshold(
            luminance: 128.0,
            localVariance: 100.0,
            viewingDistance: 120.0
        )

        XCTAssertLessThan(thresholdClose, thresholdFar)
    }

    // MARK: - Perceptual Step Size Tests

    func testPerceptualStepSize() {
        let masking = J2KVisualMasking()
        let baseStepSize = 1.0

        let perceptualSize = masking.perceptualStepSize(
            baseStepSize: baseStepSize,
            luminance: 128.0,
            localVariance: 100.0,
            motionVector: nil
        )

        // Should be different from base
        XCTAssertNotEqual(perceptualSize, baseStepSize)
        XCTAssertGreaterThan(perceptualSize, 0.0)
    }

    func testPerceptualStepSizeHighTexture() {
        let masking = J2KVisualMasking()
        let baseStepSize = 1.0

        // High texture should allow larger step size
        let sizeHighTexture = masking.perceptualStepSize(
            baseStepSize: baseStepSize,
            luminance: 128.0,
            localVariance: 2000.0,
            motionVector: nil
        )

        // Low texture should use smaller step size
        let sizeLowTexture = masking.perceptualStepSize(
            baseStepSize: baseStepSize,
            luminance: 128.0,
            localVariance: 10.0,
            motionVector: nil
        )

        XCTAssertGreaterThan(sizeHighTexture, sizeLowTexture)
    }

    func testPerceptualStepSizeWithMotion() {
        let config = J2KVisualMaskingConfiguration(enableMotionMasking: true)
        let masking = J2KVisualMasking(configuration: config)
        let baseStepSize = 1.0

        // Motion should allow larger step size
        let sizeWithMotion = masking.perceptualStepSize(
            baseStepSize: baseStepSize,
            luminance: 128.0,
            localVariance: 100.0,
            motionVector: J2KMotionVector(dx: 10.0, dy: 10.0)
        )

        let sizeNoMotion = masking.perceptualStepSize(
            baseStepSize: baseStepSize,
            luminance: 128.0,
            localVariance: 100.0,
            motionVector: .zero
        )

        XCTAssertGreaterThan(sizeWithMotion, sizeNoMotion)
    }

    // MARK: - Sendable Conformance Tests

    func testSendableConformance() {
        let config = J2KVisualMaskingConfiguration.default
        let masking = J2KVisualMasking(configuration: config)
        let mv = J2KMotionVector(dx: 1.0, dy: 1.0)

        Task {
            let factor = masking.calculateMaskingFactor(
                luminance: 128.0,
                localVariance: 100.0,
                motionVector: mv
            )
            XCTAssertGreaterThan(factor, 0.0)
        }
    }

    // MARK: - Configuration Strength Tests

    func testConfigurationStrengthAffectsMasking() {
        let weakConfig = J2KVisualMaskingConfiguration(
            luminanceStrength: 0.1,
            textureStrength: 0.1
        )
        let strongConfig = J2KVisualMaskingConfiguration(
            luminanceStrength: 0.9,
            textureStrength: 0.9
        )

        let weakMasking = J2KVisualMasking(configuration: weakConfig)
        let strongMasking = J2KVisualMasking(configuration: strongConfig)

        // Test with extreme values
        let weakFactor = weakMasking.calculateMaskingFactor(
            luminance: 0.0,
            localVariance: 5000.0,
            motionVector: nil
        )

        let strongFactor = strongMasking.calculateMaskingFactor(
            luminance: 0.0,
            localVariance: 5000.0,
            motionVector: nil
        )

        // Strong configuration should produce more extreme masking
        XCTAssertGreaterThan(strongFactor, weakFactor)
    }
}
