// J2KQuantizationTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-06.
//

import XCTest
@testable import J2KCodec
import J2KCore

/// Comprehensive tests for JPEG 2000 quantization.
final class J2KQuantizationTests: XCTestCase {
    // MARK: - Quantization Mode Tests

    func testQuantizationModeAllCases() throws {
        // Verify all quantization modes are available
        let allModes = J2KQuantizationMode.allCases
        XCTAssertEqual(allModes.count, 5)
        XCTAssertTrue(allModes.contains(.scalar))
        XCTAssertTrue(allModes.contains(.deadzone))
        XCTAssertTrue(allModes.contains(.expounded))
        XCTAssertTrue(allModes.contains(.noQuantization))
        XCTAssertTrue(allModes.contains(.trellis))
    }

    // MARK: - Guard Bits Tests

    func testGuardBitsValidRange() throws {
        for count in 0...7 {
            let guardBits = try J2KGuardBits(count: count)
            XCTAssertEqual(guardBits.count, count)
        }
    }

    func testGuardBitsInvalidRange() throws {
        XCTAssertThrowsError(try J2KGuardBits(count: -1))
        XCTAssertThrowsError(try J2KGuardBits(count: 8))
        XCTAssertThrowsError(try J2KGuardBits(count: 100))
    }

    func testGuardBitsDefault() throws {
        let defaultBits = J2KGuardBits.default
        XCTAssertEqual(defaultBits.count, 2)
    }

    // MARK: - Quantization Parameters Tests

    func testDefaultLossyParameters() throws {
        let params = J2KQuantizationParameters.lossy
        XCTAssertEqual(params.mode, .deadzone)
        XCTAssertEqual(params.baseStepSize, 1.0, accuracy: 1e-10)
        XCTAssertEqual(params.deadzoneWidth, 1.0, accuracy: 1e-10)
    }

    func testDefaultLosslessParameters() throws {
        let params = J2KQuantizationParameters.lossless
        XCTAssertEqual(params.mode, .noQuantization)
    }

    func testParametersFromQualityHigh() throws {
        let params = J2KQuantizationParameters.fromQuality(1.0)
        XCTAssertEqual(params.mode, .deadzone)
        // High quality should have small step size (near 0.1)
        XCTAssertLessThan(params.baseStepSize, 0.2)
        XCTAssertGreaterThan(params.baseStepSize, 0.05)
    }

    func testParametersFromQualityLow() throws {
        let params = J2KQuantizationParameters.fromQuality(0.0)
        XCTAssertEqual(params.mode, .deadzone)
        // Low quality should have large step size (near 16.0)
        XCTAssertGreaterThan(params.baseStepSize, 10.0)
        XCTAssertLessThan(params.baseStepSize, 20.0)
    }

    func testParametersFromQualityMedium() throws {
        let params = J2KQuantizationParameters.fromQuality(0.5)
        // Medium quality should have intermediate step size
        XCTAssertGreaterThan(params.baseStepSize, 0.5)
        XCTAssertLessThan(params.baseStepSize, 5.0)
    }

    func testParametersFromQualityClamping() throws {
        // Values outside [0, 1] should be clamped
        let paramsNegative = J2KQuantizationParameters.fromQuality(-0.5)
        let paramsZero = J2KQuantizationParameters.fromQuality(0.0)
        XCTAssertEqual(paramsNegative.baseStepSize, paramsZero.baseStepSize, accuracy: 1e-10)

        let paramsOver = J2KQuantizationParameters.fromQuality(1.5)
        let paramsOne = J2KQuantizationParameters.fromQuality(1.0)
        XCTAssertEqual(paramsOver.baseStepSize, paramsOne.baseStepSize, accuracy: 1e-10)
    }

    // MARK: - Subband Gain Tests

    func testSubbandGainReversible() throws {
        // 5/3 filter gains
        XCTAssertEqual(J2KSubbandGain.gain(for: .ll, reversible: true), 1.0, accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.gain(for: .lh, reversible: true), sqrt(2), accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.gain(for: .hl, reversible: true), sqrt(2), accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.gain(for: .hh, reversible: true), 2.0, accuracy: 1e-10)
    }

    func testSubbandGainIrreversible() throws {
        // 9/7 filter gains
        XCTAssertEqual(J2KSubbandGain.gain(for: .ll, reversible: false), 1.0, accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.gain(for: .lh, reversible: false), 2.0, accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.gain(for: .hl, reversible: false), 2.0, accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.gain(for: .hh, reversible: false), 4.0, accuracy: 1e-10)
    }

    func testLog2GainReversible() throws {
        XCTAssertEqual(J2KSubbandGain.log2Gain(for: .ll, reversible: true), 0.0, accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.log2Gain(for: .lh, reversible: true), 0.5, accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.log2Gain(for: .hl, reversible: true), 0.5, accuracy: 1e-10)
        XCTAssertEqual(J2KSubbandGain.log2Gain(for: .hh, reversible: true), 1.0, accuracy: 1e-10)
    }

    // MARK: - Step Size Calculator Tests

    func testStepSizeCalculationBasic() throws {
        let baseStep = 1.0

        // Level 0 (finest), LL subband
        let stepLL0 = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: baseStep,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 3,
            reversible: true
        )
        XCTAssertEqual(stepLL0, 1.0, accuracy: 1e-10)

        // Level 1, HH subband (gain 2)
        let stepHH1 = J2KStepSizeCalculator.calculateStepSize(
            baseStepSize: baseStep,
            subband: .hh,
            decompositionLevel: 1,
            totalLevels: 3,
            reversible: true
        )
        // step = baseStep * 2^level / gain = 1.0 * 2 / 2 = 1.0
        XCTAssertEqual(stepHH1, 1.0, accuracy: 1e-10)
    }

    func testStepSizeCalculationAllSubbands() throws {
        let allSteps = J2KStepSizeCalculator.calculateAllStepSizes(
            baseStepSize: 1.0,
            totalLevels: 3,
            reversible: true
        )

        // Should have step sizes for all subbands
        XCTAssertNotNil(allSteps["LH1"])
        XCTAssertNotNil(allSteps["HL1"])
        XCTAssertNotNil(allSteps["HH1"])
        XCTAssertNotNil(allSteps["LH2"])
        XCTAssertNotNil(allSteps["HL2"])
        XCTAssertNotNil(allSteps["HH2"])
        XCTAssertNotNil(allSteps["LH3"])
        XCTAssertNotNil(allSteps["HL3"])
        XCTAssertNotNil(allSteps["HH3"])
        XCTAssertNotNil(allSteps["LL3"])
    }

    func testStepSizeEncodeDecodeRoundtrip() throws {
        let testStepSizes = [0.1, 0.5, 1.0, 2.0, 4.0, 8.0, 0.125, 0.0625]

        for originalStep in testStepSizes {
            let (exponent, mantissa) = J2KStepSizeCalculator.encodeStepSize(originalStep)
            let decoded = J2KStepSizeCalculator.decodeStepSize(exponent: exponent, mantissa: mantissa)

            // Allow for quantization error in encoding (about 0.1% precision)
            XCTAssertEqual(decoded, originalStep, accuracy: originalStep * 0.01,
                          "Roundtrip failed for step size \(originalStep)")
        }
    }

    func testStepSizeEncodeZero() throws {
        let (exponent, mantissa) = J2KStepSizeCalculator.encodeStepSize(0.0)
        XCTAssertEqual(exponent, 0)
        XCTAssertEqual(mantissa, 0)
    }

    // MARK: - Dynamic Range Tests

    func testDynamicRangeScalingFactor() throws {
        // 8-bit unsigned
        let scale8 = J2KDynamicRange.scalingFactor(bitDepth: 8, signed: false)
        XCTAssertEqual(scale8, 1.0 / 255.0, accuracy: 1e-10)

        // 16-bit unsigned
        let scale16 = J2KDynamicRange.scalingFactor(bitDepth: 16, signed: false)
        XCTAssertEqual(scale16, 1.0 / 65535.0, accuracy: 1e-10)
    }

    func testDynamicRangeMaxMagnitude() throws {
        // 8-bit unsigned
        XCTAssertEqual(J2KDynamicRange.maxMagnitude(bitDepth: 8, signed: false), 255)
        // 8-bit signed
        XCTAssertEqual(J2KDynamicRange.maxMagnitude(bitDepth: 8, signed: true), 127)
        // 16-bit unsigned
        XCTAssertEqual(J2KDynamicRange.maxMagnitude(bitDepth: 16, signed: false), 65535)
        // 16-bit signed
        XCTAssertEqual(J2KDynamicRange.maxMagnitude(bitDepth: 16, signed: true), 32767)
    }

    func testDynamicRangeStepSizeAdjustment() throws {
        let baseStep = 1.0

        // 8-bit reference should not change
        let adjusted8 = J2KDynamicRange.adjustStepSize(baseStep, forBitDepth: 8, referenceBitDepth: 8)
        XCTAssertEqual(adjusted8, baseStep, accuracy: 1e-10)

        // 16-bit should scale by 256x
        let adjusted16 = J2KDynamicRange.adjustStepSize(baseStep, forBitDepth: 16, referenceBitDepth: 8)
        XCTAssertEqual(adjusted16, 256.0, accuracy: 1e-10)
    }

    // MARK: - Scalar Quantization Tests

    func testScalarQuantizationBasic() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 2.0)
        let quantizer = J2KQuantizer(parameters: params)

        // Test positive values
        XCTAssertEqual(quantizer.quantizeCoefficient(0.0, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(1.9, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(2.0, stepSize: 2.0), 1)
        XCTAssertEqual(quantizer.quantizeCoefficient(3.9, stepSize: 2.0), 1)
        XCTAssertEqual(quantizer.quantizeCoefficient(4.0, stepSize: 2.0), 2)

        // Test negative values
        XCTAssertEqual(quantizer.quantizeCoefficient(-1.9, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(-2.0, stepSize: 2.0), -1)
        XCTAssertEqual(quantizer.quantizeCoefficient(-3.9, stepSize: 2.0), -1)
        XCTAssertEqual(quantizer.quantizeCoefficient(-4.0, stepSize: 2.0), -2)
    }

    func testScalarDequantizationBasic() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 2.0)
        let quantizer = J2KQuantizer(parameters: params)

        // Dequantization should reconstruct to bin center
        XCTAssertEqual(quantizer.dequantizeIndex(0, stepSize: 2.0), 0.0, accuracy: 1e-10)
        XCTAssertEqual(quantizer.dequantizeIndex(1, stepSize: 2.0), 3.0, accuracy: 1e-10) // (1 + 0.5) * 2
        XCTAssertEqual(quantizer.dequantizeIndex(2, stepSize: 2.0), 5.0, accuracy: 1e-10) // (2 + 0.5) * 2
        XCTAssertEqual(quantizer.dequantizeIndex(-1, stepSize: 2.0), -3.0, accuracy: 1e-10)
        XCTAssertEqual(quantizer.dequantizeIndex(-2, stepSize: 2.0), -5.0, accuracy: 1e-10)
    }

    func testScalarQuantizationArray() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 4.0)
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        let coefficients: [Double] = [0.0, 2.0, 4.0, 8.0, -4.0, -8.0, 3.9, -3.9]
        let quantized = try quantizer.quantize(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )

        // With step size 4.0 for LL at level 0
        // The actual step size depends on the gain calculation
        XCTAssertEqual(quantized.count, coefficients.count)
    }

    // MARK: - Deadzone Quantization Tests

    func testDeadzoneQuantizationBasic() throws {
        let params = J2KQuantizationParameters(mode: .deadzone, baseStepSize: 2.0, deadzoneWidth: 1.0)
        let quantizer = J2KQuantizer(parameters: params)

        // With step=2.0 and deadzoneWidth=1.0, threshold = 2.0 * 1.0 * 0.5 = 1.0
        // Values in [-1.0, 1.0] map to 0
        XCTAssertEqual(quantizer.quantizeCoefficient(0.0, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(0.5, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(1.0, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(1.01, stepSize: 2.0), 1)
        XCTAssertEqual(quantizer.quantizeCoefficient(-1.0, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(-1.01, stepSize: 2.0), -1)
    }

    func testDeadzoneQuantizationWideDeadzone() throws {
        let params = J2KQuantizationParameters(mode: .deadzone, baseStepSize: 2.0, deadzoneWidth: 2.0)
        let quantizer = J2KQuantizer(parameters: params)

        // With step=2.0 and deadzoneWidth=2.0, threshold = 2.0 * 2.0 * 0.5 = 2.0
        XCTAssertEqual(quantizer.quantizeCoefficient(1.9, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(2.0, stepSize: 2.0), 0)
        XCTAssertEqual(quantizer.quantizeCoefficient(2.01, stepSize: 2.0), 1)
    }

    func testDeadzoneDequantizationBasic() throws {
        let params = J2KQuantizationParameters(mode: .deadzone, baseStepSize: 2.0, deadzoneWidth: 1.0)
        let quantizer = J2KQuantizer(parameters: params)

        // Index 0 always dequantizes to 0
        XCTAssertEqual(quantizer.dequantizeIndex(0, stepSize: 2.0), 0.0, accuracy: 1e-10)

        // Non-zero indices reconstruct considering threshold
        let reconstructed1 = quantizer.dequantizeIndex(1, stepSize: 2.0)
        XCTAssertGreaterThan(reconstructed1, 0)
    }

    // MARK: - No Quantization Mode Tests

    func testNoQuantizationPassthrough() throws {
        let params = J2KQuantizationParameters.lossless
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        // No quantization should round to nearest integer
        XCTAssertEqual(quantizer.quantizeCoefficient(5.4, stepSize: 1.0), 5)
        XCTAssertEqual(quantizer.quantizeCoefficient(5.5, stepSize: 1.0), 6)
        XCTAssertEqual(quantizer.quantizeCoefficient(5.6, stepSize: 1.0), 6)
        XCTAssertEqual(quantizer.quantizeCoefficient(-5.4, stepSize: 1.0), -5)
        XCTAssertEqual(quantizer.quantizeCoefficient(-5.5, stepSize: 1.0), -6)
    }

    func testNoQuantizationRoundtrip() throws {
        let params = J2KQuantizationParameters.lossless
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        // Integer values should survive roundtrip exactly
        let intCoeffs: [Double] = [0, 1, -1, 100, -100, 255, -255]
        for coeff in intCoeffs {
            let quantized = quantizer.quantizeCoefficient(coeff, stepSize: 1.0)
            let reconstructed = quantizer.dequantizeIndex(quantized, stepSize: 1.0)
            XCTAssertEqual(reconstructed, coeff, accuracy: 1e-10)
        }
    }

    // MARK: - Expounded Mode Tests

    func testExpoundedModeWithExplicitStepSizes() throws {
        let explicitSteps: [String: Double] = [
            "LL1": 1.0,
            "LH1": 2.0,
            "HL1": 2.0,
            "HH1": 4.0
        ]

        let params = J2KQuantizationParameters(
            mode: .expounded,
            baseStepSize: 1.0,
            implicitStepSizes: false,
            explicitStepSizes: explicitSteps
        )

        let quantizer = J2KQuantizer(parameters: params)

        // Verify step sizes are retrieved correctly
        XCTAssertEqual(quantizer.getStepSize(for: .ll, decompositionLevel: 0, totalLevels: 1), 1.0, accuracy: 1e-10)
        XCTAssertEqual(quantizer.getStepSize(for: .lh, decompositionLevel: 0, totalLevels: 1), 2.0, accuracy: 1e-10)
        XCTAssertEqual(quantizer.getStepSize(for: .hh, decompositionLevel: 0, totalLevels: 1), 4.0, accuracy: 1e-10)
    }

    // MARK: - 2D Quantization Tests

    func testQuantize2DBasic() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 2.0)
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        let coefficients: [[Double]] = [
            [0.0, 2.0, 4.0],
            [6.0, 8.0, 10.0]
        ]

        let quantized = try quantizer.quantize2D(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )

        XCTAssertEqual(quantized.count, 2)
        XCTAssertEqual(quantized[0].count, 3)
        XCTAssertEqual(quantized[1].count, 3)
    }

    func testQuantize2DInt32() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 2.0)
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        let coefficients: [[Int32]] = [
            [0, 2, 4],
            [6, 8, 10]
        ]

        let quantized = try quantizer.quantize2D(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )

        XCTAssertEqual(quantized.count, 2)
        XCTAssertEqual(quantized[0].count, 3)
    }

    func testDequantize2DBasic() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 2.0)
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        let indices: [[Int32]] = [
            [0, 1, 2],
            [3, -1, -2]
        ]

        let dequantized = try quantizer.dequantize2D(
            indices: indices,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )

        XCTAssertEqual(dequantized.count, 2)
        XCTAssertEqual(dequantized[0].count, 3)
        XCTAssertEqual(dequantized[0][0], 0.0, accuracy: 1e-10) // Index 0 -> 0
    }

    func testDequantize2DToIntLossless() throws {
        let params = J2KQuantizationParameters.lossless
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        let indices: [[Int32]] = [
            [0, 1, 2],
            [3, -1, -2]
        ]

        let dequantized = try quantizer.dequantize2DToInt(
            indices: indices,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )

        // Lossless mode should return indices unchanged
        XCTAssertEqual(dequantized, indices)
    }

    // MARK: - Complete Decomposition Tests

    func testQuantizeDecomposition() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 1.0)
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        let ll: [[Int32]] = [[100, 200], [150, 250]]
        let lh: [[Int32]] = [[10, -10], [5, -5]]
        let hl: [[Int32]] = [[20, -20], [15, -15]]
        let hh: [[Int32]] = [[2, -2], [1, -1]]

        let result = try quantizer.quantizeDecomposition(
            ll: ll, lh: lh, hl: hl, hh: hh,
            decompositionLevel: 0,
            totalLevels: 1
        )

        // Verify all subbands are quantized
        XCTAssertEqual(result.ll.count, 2)
        XCTAssertEqual(result.lh.count, 2)
        XCTAssertEqual(result.hl.count, 2)
        XCTAssertEqual(result.hh.count, 2)
    }

    func testQuantizeDequantizeRoundtrip() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 1.0)
        let quantizer = J2KQuantizer(parameters: params, reversible: true)

        let original: [[Int32]] = [
            [100, 200, 300],
            [150, 250, 350],
            [175, 275, 375]
        ]

        let quantized = try quantizer.quantize2D(
            coefficients: original,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )

        let dequantized = try quantizer.dequantize2DToInt(
            indices: quantized,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        )

        // With scalar quantization, there will be some loss
        // but values should be close
        for i in 0..<original.count {
            for j in 0..<original[i].count {
                let diff = abs(Int(dequantized[i][j]) - Int(original[i][j]))
                // Error should be bounded by step size
                XCTAssertLessThanOrEqual(diff, 2, "Large difference at [\(i)][\(j)]")
            }
        }
    }

    // MARK: - Edge Case Tests

    func testQuantizationZeroCoefficients() throws {
        let params = J2KQuantizationParameters(mode: .deadzone, baseStepSize: 2.0)
        let quantizer = J2KQuantizer(parameters: params)

        // Zero should always quantize to zero
        XCTAssertEqual(quantizer.quantizeCoefficient(0.0, stepSize: 2.0), 0)

        // And dequantize back to zero
        XCTAssertEqual(quantizer.dequantizeIndex(0, stepSize: 2.0), 0.0, accuracy: 1e-10)
    }

    func testQuantizationExtremeValues() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 1.0)
        let quantizer = J2KQuantizer(parameters: params)

        // Large positive value
        let largePositive = quantizer.quantizeCoefficient(10000.0, stepSize: 1.0)
        XCTAssertEqual(largePositive, 10000)

        // Large negative value
        let largeNegative = quantizer.quantizeCoefficient(-10000.0, stepSize: 1.0)
        XCTAssertEqual(largeNegative, -10000)
    }

    func testQuantizationVerySmallStepSize() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 0.001)
        let quantizer = J2KQuantizer(parameters: params)

        let quantized = quantizer.quantizeCoefficient(1.0, stepSize: 0.001)
        XCTAssertEqual(quantized, 1000)
    }

    func testQuantizationVeryLargeStepSize() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 100.0)
        let quantizer = J2KQuantizer(parameters: params)

        let quantized = quantizer.quantizeCoefficient(150.0, stepSize: 100.0)
        XCTAssertEqual(quantized, 1)
    }

    func testQuantizationInvalidStepSize() throws {
        let params = J2KQuantizationParameters(mode: .scalar, baseStepSize: 0.0)
        let quantizer = J2KQuantizer(parameters: params)

        // Should throw error for zero step size
        XCTAssertThrowsError(try quantizer.quantize(
            coefficients: [1.0, 2.0],
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 1
        ))
    }

    // MARK: - Integration Tests

    func testIntegrationWithTypicalImageValues() throws {
        // Simulate typical 8-bit image values after DC level shift (-128)
        let params = J2KQuantizationParameters.fromQuality(0.8)
        let quantizer = J2KQuantizer(parameters: params, reversible: false)

        // Typical DWT coefficient range after transform
        var coefficients: [[Int32]] = []
        for i in 0..<8 {
            var row: [Int32] = []
            for j in 0..<8 {
                // Simulated coefficients (LL subband would have larger values)
                row.append(Int32((i + j) * 10 - 50))
            }
            coefficients.append(row)
        }

        let quantized = try quantizer.quantize2D(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 3
        )

        let dequantized = try quantizer.dequantize2DToInt(
            indices: quantized,
            subband: .ll,
            decompositionLevel: 0,
            totalLevels: 3
        )

        // Verify dimensions preserved
        XCTAssertEqual(quantized.count, coefficients.count)
        XCTAssertEqual(dequantized.count, coefficients.count)
    }

    // MARK: - Sendable Conformance Tests

    func testQuantizerIsSendable() throws {
        let params = J2KQuantizationParameters.lossy
        let quantizer = J2KQuantizer(parameters: params)

        // Test that quantizer can be used across threads
        let expectation = XCTestExpectation(description: "Quantizer is Sendable")

        Task {
            // Using quantizer in an async context proves Sendable conformance
            _ = quantizer.quantizeCoefficient(5.0, stepSize: 1.0)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Parameters Equality Tests

    func testQuantizationParametersEquality() throws {
        let params1 = J2KQuantizationParameters(mode: .scalar, baseStepSize: 1.0)
        let params2 = J2KQuantizationParameters(mode: .scalar, baseStepSize: 1.0)
        let params3 = J2KQuantizationParameters(mode: .deadzone, baseStepSize: 1.0)

        XCTAssertEqual(params1, params2)
        XCTAssertNotEqual(params1, params3)
    }

    func testQuantizationModeEquality() throws {
        XCTAssertEqual(J2KQuantizationMode.scalar, J2KQuantizationMode.scalar)
        XCTAssertNotEqual(J2KQuantizationMode.scalar, J2KQuantizationMode.deadzone)
    }
}
