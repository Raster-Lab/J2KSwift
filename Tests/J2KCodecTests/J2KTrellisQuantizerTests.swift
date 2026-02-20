// J2KTrellisQuantizerTests.swift
// J2KSwift
//
// Tests for Trellis Coded Quantization (TCQ).
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KTrellisQuantizerTests: XCTestCase {
    // MARK: - Configuration Tests

    func testDefaultConfiguration() throws {
        let config = J2KTCQConfiguration.default
        XCTAssertEqual(config.numStates, 4)
        XCTAssertEqual(config.baseStepSize, 1.0, accuracy: 1e-10)
        XCTAssertEqual(config.lambdaRD, 0.5, accuracy: 1e-10)
        XCTAssertTrue(config.usePrunedSearch)
        XCTAssertEqual(config.pruningThreshold, 2.0, accuracy: 1e-10)
        XCTAssertFalse(config.useContextAdaptation)
    }

    func testHighQualityConfiguration() throws {
        let config = J2KTCQConfiguration.highQuality
        XCTAssertEqual(config.numStates, 8)
        XCTAssertEqual(config.baseStepSize, 0.5, accuracy: 1e-10)
        XCTAssertEqual(config.lambdaRD, 0.2, accuracy: 1e-10)
        XCTAssertFalse(config.usePrunedSearch)
        XCTAssertTrue(config.useContextAdaptation)
    }

    func testFastConfiguration() throws {
        let config = J2KTCQConfiguration.fast
        XCTAssertEqual(config.numStates, 2)
        XCTAssertEqual(config.lambdaRD, 0.8, accuracy: 1e-10)
        XCTAssertTrue(config.usePrunedSearch)
        XCTAssertEqual(config.pruningThreshold, 1.5, accuracy: 1e-10)
    }

    func testCustomConfiguration() throws {
        let config = try J2KTCQConfiguration(
            numStates: 6,
            baseStepSize: 2.0,
            lambdaRD: 1.0,
            usePrunedSearch: false,
            pruningThreshold: 3.0,
            useContextAdaptation: true
        )

        XCTAssertEqual(config.numStates, 6)
        XCTAssertEqual(config.baseStepSize, 2.0, accuracy: 1e-10)
        XCTAssertEqual(config.lambdaRD, 1.0, accuracy: 1e-10)
        XCTAssertFalse(config.usePrunedSearch)
        XCTAssertEqual(config.pruningThreshold, 3.0, accuracy: 1e-10)
        XCTAssertTrue(config.useContextAdaptation)
    }

    func testConfigurationValidation() throws {
        // Invalid number of states
        XCTAssertThrowsError(try J2KTCQConfiguration(numStates: 1))
        XCTAssertThrowsError(try J2KTCQConfiguration(numStates: 9))
        XCTAssertThrowsError(try J2KTCQConfiguration(numStates: 0))

        // Invalid step size
        XCTAssertThrowsError(try J2KTCQConfiguration(baseStepSize: 0.0))
        XCTAssertThrowsError(try J2KTCQConfiguration(baseStepSize: -1.0))

        // Invalid lambda
        XCTAssertThrowsError(try J2KTCQConfiguration(lambdaRD: 0.0))
        XCTAssertThrowsError(try J2KTCQConfiguration(lambdaRD: -0.5))

        // Invalid pruning threshold
        XCTAssertThrowsError(try J2KTCQConfiguration(pruningThreshold: 0.5))
    }

    // MARK: - Basic Quantization Tests

    func testQuantizeEmptyArray() throws {
        let tcq = J2KTrellisQuantizer()

        XCTAssertThrowsError(try tcq.quantize(coefficients: [], stepSize: 1.0))
    }

    func testQuantizeInvalidStepSize() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [1.0, 2.0, 3.0]

        XCTAssertThrowsError(try tcq.quantize(coefficients: coefficients, stepSize: 0.0))
        XCTAssertThrowsError(try tcq.quantize(coefficients: coefficients, stepSize: -1.0))
    }

    func testQuantizeSingleCoefficient() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [5.0]
        let stepSize = 1.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        XCTAssertEqual(result.quantizedCoefficients.count, 1)
        XCTAssertGreaterThanOrEqual(result.totalDistortion, 0.0)
        XCTAssertGreaterThan(result.estimatedRate, 0.0)
    }

    func testQuantizeUniformCoefficients() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [10.0, 10.0, 10.0, 10.0]
        let stepSize = 2.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        XCTAssertEqual(result.quantizedCoefficients.count, 4)
        // All coefficients similar, should get similar quantization levels
        let uniqueLevels = Set(result.quantizedCoefficients)
        XCTAssertLessThanOrEqual(uniqueLevels.count, 2) // Should be mostly uniform
    }

    func testQuantizeZeroCoefficients() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [0.0, 0.0, 0.0, 0.0]
        let stepSize = 1.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        // Zero coefficients should mostly quantize to zero
        let nonZeroCount = result.quantizedCoefficients.filter { $0 != 0 }.count
        XCTAssertLessThanOrEqual(nonZeroCount, 2) // Allow some state transitions
    }

    func testQuantizeMixedCoefficients() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [0.5, 1.5, 2.5, 3.5, 4.5]
        let stepSize = 1.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        XCTAssertEqual(result.quantizedCoefficients.count, 5)
        // Verify quantized levels increase with input magnitude
        for i in 1..<result.quantizedCoefficients.count {
            XCTAssertGreaterThanOrEqual(
                abs(result.quantizedCoefficients[i]),
                abs(result.quantizedCoefficients[i - 1]) - 1 // Allow some flexibility
            )
        }
    }

    func testQuantizeNegativeCoefficients() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0]
        let stepSize = 1.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        XCTAssertEqual(result.quantizedCoefficients.count, 6)

        // Verify sign preservation
        for (coeff, quantized) in zip(coefficients, result.quantizedCoefficients) {
            if abs(coeff) > stepSize / 2 {
                XCTAssertEqual(
                    coeff >= 0,
                    quantized >= 0,
                    "Sign should be preserved for coefficient \(coeff)"
                )
            }
        }
    }

    // MARK: - Subband Quantization Tests

    func testQuantizeForSubband() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [1.3, 2.7, 3.1, 4.8, 5.4] // Non-integer values to ensure distortion

        let result = try tcq.quantize(
            coefficients: coefficients,
            subband: .hh,
            decompositionLevel: 0,
            totalLevels: 3,
            reversible: false
        )

        XCTAssertEqual(result.quantizedCoefficients.count, 5)
        XCTAssertGreaterThanOrEqual(result.totalDistortion, 0.0)
        XCTAssertGreaterThan(result.estimatedRate, 0.0)
    }

    func testQuantizeDifferentSubbands() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [10.0, 20.0, 30.0]

        // Quantize for different subbands
        let llResult = try tcq.quantize(
            coefficients: coefficients,
            subband: .ll,
            decompositionLevel: 2,
            totalLevels: 3
        )

        let hhResult = try tcq.quantize(
            coefficients: coefficients,
            subband: .hh,
            decompositionLevel: 0,
            totalLevels: 3
        )

        // HH subband (high freq) typically has smaller step size, more detail
        // LL subband (low freq) typically has larger step size
        XCTAssertNotEqual(llResult.quantizedCoefficients, hhResult.quantizedCoefficients)
    }

    // MARK: - Dequantization Tests

    func testDequantizeSimple() throws {
        let tcq = J2KTrellisQuantizer()
        let quantized: [Int32] = [0, 1, 2, 3, -1, -2]
        let stepSize = 1.0

        let dequantized = tcq.dequantize(
            quantizedCoefficients: quantized,
            stepSize: stepSize
        )

        XCTAssertEqual(dequantized.count, 6)

        // Verify reconstruction values
        XCTAssertEqual(dequantized[0], 0.0, accuracy: 1e-10)
        XCTAssertEqual(dequantized[1], 1.5, accuracy: 1e-10) // 1 + 0.5
        XCTAssertEqual(dequantized[2], 2.5, accuracy: 1e-10) // 2 + 0.5
        XCTAssertEqual(dequantized[4], -1.5, accuracy: 1e-10) // -1 - 0.5
    }

    func testDequantizeForSubband() throws {
        let tcq = J2KTrellisQuantizer()
        let quantized: [Int32] = [1, 2, 3]

        let dequantized = tcq.dequantize(
            quantizedCoefficients: quantized,
            subband: .hl,
            decompositionLevel: 1,
            totalLevels: 3,
            reversible: false
        )

        XCTAssertEqual(dequantized.count, 3)
        XCTAssertGreaterThan(dequantized[0], 0.0)
    }

    func testQuantizeDequantizeRoundtrip() throws {
        let tcq = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(baseStepSize: 1.0)
        )
        let original = [1.0, 5.0, 10.0, 15.0, 20.0]
        let stepSize = 2.0

        // Quantize
        let quantized = try tcq.quantize(coefficients: original, stepSize: stepSize)

        // Dequantize
        let reconstructed = tcq.dequantize(
            quantizedCoefficients: quantized.quantizedCoefficients,
            stepSize: stepSize
        )

        // Verify reconstruction error is bounded
        for (orig, recon) in zip(original, reconstructed) {
            let error = abs(orig - recon)
            XCTAssertLessThanOrEqual(error, stepSize * 1.5, "Reconstruction error too large")
        }
    }

    // MARK: - Rate-Distortion Tests

    func testRateDistortionTradeoff() throws {
        let coefficients = Array(repeating: 10.0, count: 20)

        // Low lambda (favor quality)
        let tcqLow = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(lambdaRD: 0.1)
        )
        let resultLow = try tcqLow.quantize(coefficients: coefficients, stepSize: 1.0)

        // High lambda (favor compression)
        let tcqHigh = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(lambdaRD: 2.0)
        )
        let resultHigh = try tcqHigh.quantize(coefficients: coefficients, stepSize: 1.0)

        // Low lambda should have lower distortion (better quality)
        XCTAssertLessThanOrEqual(resultLow.totalDistortion, resultHigh.totalDistortion)

        // High lambda should have lower rate (better compression)
        XCTAssertLessThanOrEqual(resultHigh.estimatedRate, resultLow.estimatedRate)
    }

    func testDifferentStepSizes() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [5.0, 10.0, 15.0, 20.0]

        // Small step size (high quality)
        let resultSmall = try tcq.quantize(coefficients: coefficients, stepSize: 0.5)

        // Large step size (high compression)
        let resultLarge = try tcq.quantize(coefficients: coefficients, stepSize: 2.0)

        // Small step size should have lower distortion
        XCTAssertLessThan(resultSmall.totalDistortion, resultLarge.totalDistortion)

        // Small step size should have higher rate
        XCTAssertGreaterThan(resultSmall.estimatedRate, resultLarge.estimatedRate)
    }

    // MARK: - State Machine Tests

    func testStateSequence() throws {
        let tcq = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(numStates: 4)
        )
        let coefficients = [1.0, 2.0, 3.0, 4.0, 5.0]

        let result = try tcq.quantize(coefficients: coefficients, stepSize: 1.0)

        // Verify state sequence has correct length
        XCTAssertEqual(result.stateSequence.count, coefficients.count)

        // All states should be valid (0 to numStates-1)
        for state in result.stateSequence {
            XCTAssertGreaterThanOrEqual(state, 0)
            XCTAssertLessThan(state, 4)
        }
    }

    func testDifferentNumberOfStates() throws {
        let coefficients = [5.0, 10.0, 15.0, 20.0]

        // 2 states (simple)
        let tcq2 = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(numStates: 2)
        )
        let result2 = try tcq2.quantize(coefficients: coefficients, stepSize: 1.0)

        // 8 states (complex)
        let tcq8 = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(numStates: 8)
        )
        let result8 = try tcq8.quantize(coefficients: coefficients, stepSize: 1.0)

        // More states should provide better or equal rate-distortion
        XCTAssertLessThanOrEqual(result8.rdCost, result2.rdCost * 1.1) // Allow 10% tolerance
    }

    // MARK: - Pruned Search Tests

    func testPrunedVsFullSearch() throws {
        let coefficients = Array(stride(from: 0.0, through: 20.0, by: 1.0))

        // Full search
        let tcqFull = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(
                numStates: 4,
                usePrunedSearch: false
            )
        )
        let resultFull = try tcqFull.quantize(coefficients: coefficients, stepSize: 1.0)

        // Pruned search
        let tcqPruned = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(
                numStates: 4,
                usePrunedSearch: true,
                pruningThreshold: 2.0
            )
        )
        let resultPruned = try tcqPruned.quantize(coefficients: coefficients, stepSize: 1.0)

        // Pruned search should be close to full search (within 5%)
        let costDiff = abs(resultPruned.rdCost - resultFull.rdCost)
        let relativeDiff = costDiff / resultFull.rdCost
        XCTAssertLessThan(relativeDiff, 0.05, "Pruned search differs too much from full search")
    }

    // MARK: - Performance Comparison Tests

    func testTCQVsScalarQuantization() throws {
        // Test that TCQ provides benefit over scalar quantization
        let coefficients = [1.5, 3.7, 5.2, 8.9, 12.3, 15.6, 18.1, 22.4]
        let stepSize = 2.0

        // TCQ quantization
        let tcq = J2KTrellisQuantizer(
            configuration: try J2KTCQConfiguration(lambdaRD: 0.5)
        )
        let tcqResult = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        // Simple scalar quantization (for comparison)
        let scalarQuantized = coefficients.map { coeff -> Int32 in
            Int32(round(coeff / stepSize))
        }

        // Compute scalar distortion
        var scalarDistortion = 0.0
        for (coeff, quantLevel) in zip(coefficients, scalarQuantized) {
            let reconstructed = Double(quantLevel) * stepSize
            scalarDistortion += pow(coeff - reconstructed, 2)
        }

        // TCQ should have lower or similar distortion with similar rate
        // (TCQ optimization finds better quantization levels)
        XCTAssertLessThanOrEqual(
            tcqResult.totalDistortion,
            scalarDistortion * 1.05 // Allow 5% tolerance
        )
    }

    // MARK: - Integration Tests

    func testIntegrationWithQuantizationParameters() throws {
        // Test that TCQ works with J2KQuantizationParameters
        let tcqConfig = try J2KTCQConfiguration(
            numStates: 4,
            baseStepSize: 1.0,
            lambdaRD: 0.5
        )

        let params = J2KQuantizationParameters(
            mode: .trellis,
            baseStepSize: 1.0,
            tcqConfiguration: tcqConfig
        )

        XCTAssertEqual(params.mode, .trellis)
        XCTAssertNotNil(params.tcqConfiguration)
        XCTAssertEqual(params.tcqConfiguration?.numStates, 4)
    }

    func testQuantizationModeIncludesTrellis() throws {
        let allModes = J2KQuantizationMode.allCases
        XCTAssertTrue(allModes.contains(.trellis))
    }

    func testTrellisQuantizationParameters() throws {
        let params = J2KQuantizationParameters.trellis
        XCTAssertEqual(params.mode, .trellis)
        XCTAssertNotNil(params.tcqConfiguration)
    }

    // MARK: - Edge Cases

    func testLargeCoefficients() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [103.7, 207.2, 315.1, 423.8, 508.3] // Non-multiples of step size
        let stepSize = 10.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        XCTAssertEqual(result.quantizedCoefficients.count, 5)
        XCTAssertGreaterThanOrEqual(result.totalDistortion, 0.0)
    }

    func testSmallStepSize() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = [1.0, 2.0, 3.0]
        let stepSize = 0.1

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        // Small step size should give low distortion
        XCTAssertLessThan(result.totalDistortion, 1.0)
    }

    func testLongSequence() throws {
        let tcq = J2KTrellisQuantizer()
        let coefficients = Array(repeating: 5.0, count: 100)

        let result = try tcq.quantize(coefficients: coefficients, stepSize: 1.0)

        XCTAssertEqual(result.quantizedCoefficients.count, 100)
        XCTAssertEqual(result.stateSequence.count, 100)
    }
}
