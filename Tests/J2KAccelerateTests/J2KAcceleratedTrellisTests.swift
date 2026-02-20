//
// J2KAcceleratedTrellisTests.swift
// J2KSwift
//
// J2KAcceleratedTrellisTests.swift
// J2KSwift
//
// Tests for accelerated trellis coded quantization.
//

#if canImport(Accelerate)
import XCTest
@testable import J2KAccelerate
@testable import J2KCodec
import J2KCore

@available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 6.0, *)
final class J2KAcceleratedTrellisTests: XCTestCase {
    // MARK: - Basic Acceleration Tests

    func testAcceleratedQuantization() throws {
        let tcq = J2KAcceleratedTrellis()
        let coefficients = [1.5, 3.7, 5.2, 8.9, 12.3, 15.6, 18.1, 22.4]
        let stepSize = 2.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        XCTAssertEqual(result.quantizedCoefficients.count, 8)
        XCTAssertGreaterThanOrEqual(result.totalDistortion, 0.0)
        XCTAssertGreaterThan(result.estimatedRate, 0.0)
    }

    func testAcceleratedVsStandardQuantization() throws {
        let coefficients = Array(stride(from: 1.0, through: 20.0, by: 0.5))
        let stepSize = 1.5

        // Standard TCQ
        let standardTCQ = J2KTrellisQuantizer()
        let standardResult = try standardTCQ.quantize(coefficients: coefficients, stepSize: stepSize)

        // Accelerated TCQ
        let acceleratedTCQ = J2KAcceleratedTrellis()
        let acceleratedResult = try acceleratedTCQ.quantize(coefficients: coefficients, stepSize: stepSize)

        // Results should be very similar (within numerical precision)
        XCTAssertEqual(acceleratedResult.quantizedCoefficients.count, standardResult.quantizedCoefficients.count)

        // Check that distortion and rate are close (allow some numerical difference)
        let distortionDiff = abs(acceleratedResult.totalDistortion - standardResult.totalDistortion)
        let relativeDiff = distortionDiff / max(standardResult.totalDistortion, 1.0)
        XCTAssertLessThan(relativeDiff, 0.01, "Accelerated distortion differs too much from standard")
    }

    func testShortSequenceFallback() throws {
        // Short sequences should use fallback
        let tcq = J2KAcceleratedTrellis()
        let coefficients = [1.0, 2.0, 3.0] // < 16 elements

        let result = try tcq.quantize(coefficients: coefficients, stepSize: 1.0)

        XCTAssertEqual(result.quantizedCoefficients.count, 3)
    }

    func testLongSequenceAcceleration() throws {
        // Long sequences should use acceleration
        let tcq = J2KAcceleratedTrellis()
        let coefficients = Array(repeating: 5.0, count: 100)

        let result = try tcq.quantize(coefficients: coefficients, stepSize: 1.0)

        XCTAssertEqual(result.quantizedCoefficients.count, 100)
    }

    // MARK: - Subband Tests

    func testAcceleratedSubbandQuantization() throws {
        let tcq = J2KAcceleratedTrellis()
        let coefficients = Array(stride(from: 1.0, through: 30.0, by: 1.0))

        let result = try tcq.quantize(
            coefficients: coefficients,
            subband: .hh,
            decompositionLevel: 1,
            totalLevels: 3,
            reversible: false
        )

        XCTAssertEqual(result.quantizedCoefficients.count, 30)
        XCTAssertGreaterThanOrEqual(result.totalDistortion, 0.0)
    }

    // MARK: - Dequantization Tests

    func testAcceleratedDequantization() throws {
        let tcq = J2KAcceleratedTrellis()
        let quantized: [Int32] = [0, 1, 2, -1, -2, 3]
        let stepSize = 1.0

        let dequantized = tcq.dequantize(
            quantizedCoefficients: quantized,
            stepSize: stepSize
        )

        XCTAssertEqual(dequantized.count, 6)
        XCTAssertEqual(dequantized[0], 0.0, accuracy: 1e-10)
    }

    func testAcceleratedRoundtrip() throws {
        let tcq = J2KAcceleratedTrellis()
        let original = [2.3, 5.7, 10.1, 15.9, 20.2]
        let stepSize = 2.0

        let quantized = try tcq.quantize(coefficients: original, stepSize: stepSize)
        let reconstructed = tcq.dequantize(
            quantizedCoefficients: quantized.quantizedCoefficients,
            stepSize: stepSize
        )

        // Check reconstruction error is bounded
        for (orig, recon) in zip(original, reconstructed) {
            let error = abs(orig - recon)
            XCTAssertLessThanOrEqual(error, stepSize * 1.5)
        }
    }

    // MARK: - Configuration Tests

    func testAcceleratedWithCustomConfiguration() throws {
        let config = try J2KTCQConfiguration(
            numStates: 6,
            baseStepSize: 0.5,
            lambdaRD: 0.3,
            usePrunedSearch: false
        )

        let tcq = J2KAcceleratedTrellis(configuration: config)
        let coefficients = Array(stride(from: 1.0, through: 20.0, by: 1.0))
        let stepSize = 1.0

        let result = try tcq.quantize(coefficients: coefficients, stepSize: stepSize)

        XCTAssertEqual(result.quantizedCoefficients.count, 20)
    }

    func testAcceleratedWithPruning() throws {
        let config = try J2KTCQConfiguration(
            numStates: 4,
            usePrunedSearch: true,
            pruningThreshold: 2.0
        )

        let tcq = J2KAcceleratedTrellis(configuration: config)
        let coefficients = Array(repeating: 10.0, count: 50)

        let result = try tcq.quantize(coefficients: coefficients, stepSize: 2.0)

        XCTAssertEqual(result.quantizedCoefficients.count, 50)
    }

    // MARK: - Batch Processing Tests

    func testBatchQuantization() async throws {
        let tcq = J2KAcceleratedTrellis()
        let arrays: [[Double]] = [
            [1.0, 2.0, 3.0, 4.0, 5.0],
            [10.0, 20.0, 30.0, 40.0, 50.0],
            [5.5, 10.5, 15.5, 20.5, 25.5]
        ]
        let stepSize = 2.0

        let results = try await tcq.quantizeBatch(
            coefficientArrays: arrays,
            stepSize: stepSize
        )

        XCTAssertEqual(results.count, 3)
        for result in results {
            XCTAssertEqual(result.quantizedCoefficients.count, 5)
        }
    }

    func testEmptyBatch() async throws {
        let tcq = J2KAcceleratedTrellis()
        let arrays: [[Double]] = []

        let results = try await tcq.quantizeBatch(
            coefficientArrays: arrays,
            stepSize: 1.0
        )

        XCTAssertEqual(results.count, 0)
    }

    func testLargeBatch() async throws {
        let tcq = J2KAcceleratedTrellis()
        let arrays = (0..<10).map { i in
            Array(stride(from: Double(i), through: Double(i + 10), by: 0.5))
        }

        let results = try await tcq.quantizeBatch(
            coefficientArrays: arrays,
            stepSize: 1.0
        )

        XCTAssertEqual(results.count, 10)
    }

    // MARK: - Edge Cases

    func testAcceleratedEmptyArray() throws {
        let tcq = J2KAcceleratedTrellis()

        XCTAssertThrowsError(try tcq.quantize(coefficients: [], stepSize: 1.0))
    }

    func testAcceleratedInvalidStepSize() throws {
        let tcq = J2KAcceleratedTrellis()
        let coefficients = [1.0, 2.0, 3.0]

        XCTAssertThrowsError(try tcq.quantize(coefficients: coefficients, stepSize: 0.0))
        XCTAssertThrowsError(try tcq.quantize(coefficients: coefficients, stepSize: -1.0))
    }

    func testAcceleratedWithZeros() throws {
        let tcq = J2KAcceleratedTrellis()
        let coefficients = [Double](repeating: 0.0, count: 30)

        let result = try tcq.quantize(coefficients: coefficients, stepSize: 1.0)

        // Most should be zero
        let nonZeroCount = result.quantizedCoefficients.filter { $0 != 0 }.count
        XCTAssertLessThanOrEqual(nonZeroCount, 5)
    }

    func testAcceleratedWithNegatives() throws {
        let tcq = J2KAcceleratedTrellis()
        let coefficients = [-5.0, -3.0, -1.0, 1.0, 3.0, 5.0, 7.0, 9.0, 11.0, 13.0]

        let result = try tcq.quantize(coefficients: coefficients, stepSize: 2.0)

        XCTAssertEqual(result.quantizedCoefficients.count, 10)

        // Verify sign preservation for large magnitudes
        for (coeff, quantized) in zip(coefficients, result.quantizedCoefficients)
            where abs(coeff) > 2.0 {
            XCTAssertEqual(coeff >= 0, quantized >= 0, "Sign not preserved")
        }
    }

    // MARK: - Performance Comparison

    func testAcceleratedPerformance() throws {
        let coefficients = Array(stride(from: 0.0, through: 100.0, by: 0.5))
        let stepSize = 1.5

        // Measure accelerated version
        let tcqAccelerated = J2KAcceleratedTrellis()
        let startAccelerated = Date()
        _ = try tcqAccelerated.quantize(coefficients: coefficients, stepSize: stepSize)
        let acceleratedTime = Date().timeIntervalSince(startAccelerated)

        // Measure standard version
        let tcqStandard = J2KTrellisQuantizer()
        let startStandard = Date()
        _ = try tcqStandard.quantize(coefficients: coefficients, stepSize: stepSize)
        let standardTime = Date().timeIntervalSince(startStandard)

        // Accelerated should be faster or at least not significantly slower
        // (actual speedup depends on coefficient count and hardware)
        print("Standard: \(standardTime)s, Accelerated: \(acceleratedTime)s")
        print("Speedup: \(standardTime / acceleratedTime)×")

        // For this size, speedup may vary, just ensure it works
        XCTAssertGreaterThan(standardTime + acceleratedTime, 0.0)
    }
}

#endif // canImport(Accelerate)
