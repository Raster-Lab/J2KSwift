// J2KDWT1DTests.swift
// J2KSwift
//
// Created by J2KSwift on 2026-02-05.
//

import XCTest
@testable import J2KCodec
import J2KCore

final class J2KDWT1DTests: XCTestCase {
    // MARK: - Basic Functionality Tests

    func testForwardTransform53Simple() throws {
        // Test with simple signal
        let signal: [Int32] = [1, 2, 3, 4, 5, 6, 7, 8]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        // Verify output sizes
        XCTAssertEqual(lowpass.count, 4, "Lowpass should have 4 elements")
        XCTAssertEqual(highpass.count, 4, "Highpass should have 4 elements")

        // Verify outputs are not all zeros
        XCTAssertTrue(lowpass.contains { $0 != 0 }, "Lowpass should contain non-zero elements")
    }

    func testInverseTransform53Simple() throws {
        // Test perfect reconstruction with simple signal
        let original: [Int32] = [1, 2, 3, 4, 5, 6, 7, 8]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: original,
            filter: .reversible53
        )

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53
        )

        // Verify perfect reconstruction
        XCTAssertEqual(reconstructed.count, original.count)
        XCTAssertEqual(reconstructed, original, "5/3 filter should achieve perfect reconstruction")
    }

    func testPerfectReconstruction53WithVariousLengths() throws {
        // Test perfect reconstruction with different signal lengths
        let testLengths = [2, 3, 4, 5, 8, 10, 16, 32, 64, 100, 127, 128, 129, 256]

        for length in testLengths {
            let signal = (0..<length).map { Int32($0 + 1) }

            let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
                signal: signal,
                filter: .reversible53
            )

            let reconstructed = try J2KDWT1D.inverseTransform(
                lowpass: lowpass,
                highpass: highpass,
                filter: .reversible53
            )

            XCTAssertEqual(
                reconstructed, signal,
                "Failed perfect reconstruction for length \(length)"
            )
        }
    }

    func testPerfectReconstruction53WithRandomData() throws {
        // Test with random data
        var rng = SeededRandomNumberGenerator(seed: 12345)

        for _ in 0..<10 {
            let length = Int.random(in: 10...200, using: &rng)
            let signal = (0..<length).map { _ in Int32.random(in: -1000...1000, using: &rng) }

            let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
                signal: signal,
                filter: .reversible53
            )

            let reconstructed = try J2KDWT1D.inverseTransform(
                lowpass: lowpass,
                highpass: highpass,
                filter: .reversible53
            )

            XCTAssertEqual(reconstructed, signal, "Failed reconstruction for random signal")
        }
    }

    // MARK: - 9/7 Filter Tests

    func testForwardTransform97Simple() throws {
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: signal)

        XCTAssertEqual(lowpass.count, 4)
        XCTAssertEqual(highpass.count, 4)
        XCTAssertTrue(lowpass.contains { $0 != 0 })
    }

    func testInverseTransform97Simple() throws {
        let original: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: original)
        let reconstructed = try J2KDWT1D.inverseTransform97(
            lowpass: lowpass,
            highpass: highpass
        )

        XCTAssertEqual(reconstructed.count, original.count)

        // Verify near-perfect reconstruction (within floating-point precision)
        for i in 0..<original.count {
            XCTAssertEqual(
                reconstructed[i], original[i],
                accuracy: 1e-6,
                "Failed reconstruction at index \(i)"
            )
        }
    }

    func testNearPerfectReconstruction97WithVariousLengths() throws {
        let testLengths = [2, 3, 4, 8, 16, 32, 64, 128]

        for length in testLengths {
            let signal = (0..<length).map { Double($0 + 1) }

            let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: signal)
            let reconstructed = try J2KDWT1D.inverseTransform97(
                lowpass: lowpass,
                highpass: highpass
            )

            for i in 0..<signal.count {
                XCTAssertEqual(
                    reconstructed[i], signal[i],
                    accuracy: 1e-6,
                    "Failed reconstruction for length \(length) at index \(i)"
                )
            }
        }
    }

    func testNearPerfectReconstruction97WithRandomData() throws {
        var rng = SeededRandomNumberGenerator(seed: 54321)

        for _ in 0..<10 {
            let length = Int.random(in: 10...200, using: &rng)
            let signal = (0..<length).map { _ in Double.random(in: -1000...1000, using: &rng) }

            let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: signal)
            let reconstructed = try J2KDWT1D.inverseTransform97(
                lowpass: lowpass,
                highpass: highpass
            )

            for i in 0..<signal.count {
                XCTAssertEqual(
                    reconstructed[i], signal[i],
                    accuracy: 1e-5,
                    "Failed reconstruction at index \(i)"
                )
            }
        }
    }

    // MARK: - Boundary Extension Tests

    func testSymmetricBoundaryExtension53() throws {
        let signal: [Int32] = [1, 2, 3, 4]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testPeriodicBoundaryExtension53() throws {
        let signal: [Int32] = [1, 2, 3, 4, 5, 6]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53,
            boundaryExtension: .periodic
        )

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53,
            boundaryExtension: .periodic
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testZeroPaddingBoundaryExtension53() throws {
        let signal: [Int32] = [1, 2, 3, 4, 5, 6, 7, 8]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53,
            boundaryExtension: .zeroPadding
        )

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53,
            boundaryExtension: .zeroPadding
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testAllBoundaryExtensionsMatch97() throws {
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
        let extensions: [J2KDWT1D.BoundaryExtension] = [.symmetric, .periodic, .zeroPadding]

        for ext in extensions {
            let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(
                signal: signal,
                boundaryExtension: ext
            )

            let reconstructed = try J2KDWT1D.inverseTransform97(
                lowpass: lowpass,
                highpass: highpass,
                boundaryExtension: ext
            )

            for i in 0..<signal.count {
                XCTAssertEqual(
                    reconstructed[i], signal[i],
                    accuracy: 1e-6,
                    "Failed for boundary extension \(ext) at index \(i)"
                )
            }
        }
    }

    // MARK: - Edge Cases

    func testMinimumSignalLength53() throws {
        // Test with minimum valid length (2 elements)
        let signal: [Int32] = [1, 2]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        XCTAssertEqual(lowpass.count, 1)
        XCTAssertEqual(highpass.count, 1)

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testMinimumSignalLength97() throws {
        let signal: [Double] = [1.0, 2.0]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: signal)

        XCTAssertEqual(lowpass.count, 1)
        XCTAssertEqual(highpass.count, 1)

        let reconstructed = try J2KDWT1D.inverseTransform97(
            lowpass: lowpass,
            highpass: highpass
        )

        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 1e-6)
        }
    }

    func testOddLength53() throws {
        // Test with odd-length signal
        let signal: [Int32] = [1, 2, 3, 4, 5]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        // For odd length n, lowpass has (n+1)/2 = 3, highpass has n/2 = 2
        XCTAssertEqual(lowpass.count, 3)
        XCTAssertEqual(highpass.count, 2)

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testEvenLength53() throws {
        // Test with even-length signal
        let signal: [Int32] = [1, 2, 3, 4, 5, 6]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        // For even length n, both have n/2 = 3
        XCTAssertEqual(lowpass.count, 3)
        XCTAssertEqual(highpass.count, 3)

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testConstantSignal53() throws {
        // Test with constant signal - highpass should be nearly zero
        let signal: [Int32] = Array(repeating: 42, count: 16)

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        // For constant signal, highpass (detail) should be very small
        let maxHighpass = highpass.map { abs($0) }.max() ?? 0
        XCTAssertLessThanOrEqual(maxHighpass, 1, "Highpass should be nearly zero for constant signal")

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testConstantSignal97() throws {
        let signal: [Double] = Array(repeating: 42.0, count: 16)

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: signal)

        // For constant signal, highpass should be very small
        let maxHighpass = highpass.map { abs($0) }.max() ?? 0
        XCTAssertLessThan(maxHighpass, 0.1, "Highpass should be nearly zero for constant signal")

        let reconstructed = try J2KDWT1D.inverseTransform97(
            lowpass: lowpass,
            highpass: highpass
        )

        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 1e-6)
        }
    }

    func testAllZeros53() throws {
        let signal: [Int32] = Array(repeating: 0, count: 16)

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        XCTAssertTrue(lowpass.allSatisfy { $0 == 0 })
        XCTAssertTrue(highpass.allSatisfy { $0 == 0 })

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, signal)
    }

    func testAllZeros97() throws {
        let signal: [Double] = Array(repeating: 0.0, count: 16)

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: signal)

        XCTAssertTrue(lowpass.allSatisfy { abs($0) < 1e-10 })
        XCTAssertTrue(highpass.allSatisfy { abs($0) < 1e-10 })
    }

    func testAlternatingSignal53() throws {
        // Alternating pattern should produce strong highpass response
        let signal: [Int32] = [1, -1, 1, -1, 1, -1, 1, -1]

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        // Highpass should capture the alternation
        XCTAssertTrue(highpass.contains { abs($0) > 1 })

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53
        )

        XCTAssertEqual(reconstructed, signal)
    }

    // MARK: - Error Handling Tests

    func testEmptySignalError() {
        let signal: [Int32] = []

        XCTAssertThrowsError(
            try J2KDWT1D.forwardTransform(signal: signal, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    func testSingleElementSignalError() {
        let signal: [Int32] = [42]

        XCTAssertThrowsError(
            try J2KDWT1D.forwardTransform(signal: signal, filter: .reversible53)
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    func testEmptySubbandsError() {
        let lowpass: [Int32] = []
        let highpass: [Int32] = [1, 2, 3]

        XCTAssertThrowsError(
            try J2KDWT1D.inverseTransform(
                lowpass: lowpass,
                highpass: highpass,
                filter: .reversible53
            )
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    func testIncompatibleSubbandSizesError() {
        let lowpass: [Int32] = [1, 2, 3]
        let highpass: [Int32] = [4, 5, 6, 7, 8, 9] // Too many elements

        XCTAssertThrowsError(
            try J2KDWT1D.inverseTransform(
                lowpass: lowpass,
                highpass: highpass,
                filter: .reversible53
            )
        ) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }
    }

    // MARK: - Numerical Properties Tests

    func testLowpassContainsApproximation53() throws {
        // Smooth signal should have most energy in lowpass
        let signal: [Int32] = (0..<32).map { Int32($0) }

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        let lowpassEnergy = lowpass.map { Int64($0) * Int64($0) }.reduce(0, +)
        let highpassEnergy = highpass.map { Int64($0) * Int64($0) }.reduce(0, +)

        // Lowpass should contain more energy for smooth signal
        XCTAssertGreaterThan(lowpassEnergy, highpassEnergy)
    }

    func testHighpassContainsDetails53() throws {
        // High-frequency signal should have significant energy in highpass
        let signal: [Int32] = (0..<32).map { Int32($0.isMultiple(of: 2) ? 10 : -10) }

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        let lowpassEnergy = lowpass.map { Int64($0) * Int64($0) }.reduce(0, +)
        let highpassEnergy = highpass.map { Int64($0) * Int64($0) }.reduce(0, +)

        // Highpass should contain significant energy for high-frequency signal
        XCTAssertGreaterThan(highpassEnergy, lowpassEnergy / 10)
    }

    func testEnergyConservation97() throws {
        // The 9/7 filter modifies energy due to scaling, but reconstruction should be accurate
        // This test verifies that the transform is working correctly even though energy changes
        let signal: [Double] = (0..<32).map { Double($0 + 1) }

        let originalEnergy = signal.map { $0 * $0 }.reduce(0, +)

        let (lowpass, highpass) = try J2KDWT1D.forwardTransform97(signal: signal)

        let transformedEnergy = lowpass.map { $0 * $0 }.reduce(0, +) +
                               highpass.map { $0 * $0 }.reduce(0, +)

        // 9/7 filter changes energy due to scaling (K = 1.149604398)
        // The energy should be within a reasonable range (5-20% difference is expected)
        XCTAssertGreaterThan(transformedEnergy, originalEnergy * 0.8)
        XCTAssertLessThan(transformedEnergy, originalEnergy * 1.2)

        // But reconstruction should still be accurate
        let reconstructed = try J2KDWT1D.inverseTransform97(
            lowpass: lowpass,
            highpass: highpass
        )

        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 1e-6)
        }
    }

    // MARK: - Performance Tests

    func testPerformanceForward53() {
        let signal: [Int32] = (0..<1024).map { Int32($0) }

        measure {
            for _ in 0..<100 {
                _ = try? J2KDWT1D.forwardTransform(signal: signal, filter: .reversible53)
            }
        }
    }

    func testPerformanceInverse53() {
        let signal: [Int32] = (0..<1024).map { Int32($0) }
        let (lowpass, highpass) = try! J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        measure {
            for _ in 0..<100 {
                _ = try? J2KDWT1D.inverseTransform(
                    lowpass: lowpass,
                    highpass: highpass,
                    filter: .reversible53
                )
            }
        }
    }

    func testPerformanceRoundTrip53() {
        let signal: [Int32] = (0..<1024).map { Int32($0) }

        measure {
            for _ in 0..<100 {
                let (low, high) = try! J2KDWT1D.forwardTransform(
                    signal: signal,
                    filter: .reversible53
                )
                _ = try! J2KDWT1D.inverseTransform(
                    lowpass: low,
                    highpass: high,
                    filter: .reversible53
                )
            }
        }
    }

    func testPerformanceForward97() {
        let signal: [Double] = (0..<1024).map { Double($0) }

        measure {
            for _ in 0..<100 {
                _ = try? J2KDWT1D.forwardTransform97(signal: signal)
            }
        }
    }

    func testPerformanceRoundTrip97() {
        let signal: [Double] = (0..<1024).map { Double($0) }

        measure {
            for _ in 0..<100 {
                let (low, high) = try! J2KDWT1D.forwardTransform97(signal: signal)
                _ = try! J2KDWT1D.inverseTransform97(lowpass: low, highpass: high)
            }
        }
    }

    // MARK: - Custom Filter Tests

    func testCustomFilterCDF97Equivalent() throws {
        // Test that custom CDF 9/7 filter produces same results as built-in 9/7
        let signal: [Int32] = Array(1...32)

        let result97 = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .irreversible97
        )

        let resultCustom = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .custom(.cdf97)
        )

        // Should produce nearly identical results (within floating-point precision after rounding)
        XCTAssertEqual(result97.lowpass.count, resultCustom.lowpass.count)
        XCTAssertEqual(result97.highpass.count, resultCustom.highpass.count)

        for i in 0..<result97.lowpass.count {
            let diff = abs(result97.lowpass[i] - resultCustom.lowpass[i])
            XCTAssertLessThanOrEqual(diff, 1, "Lowpass should match within 1 at index \(i)")
        }

        for i in 0..<result97.highpass.count {
            let diff = abs(result97.highpass[i] - resultCustom.highpass[i])
            XCTAssertLessThanOrEqual(diff, 1, "Highpass should match within 1 at index \(i)")
        }
    }

    func testCustomFilterLeGall53Equivalent() throws {
        // Test that custom Le Gall 5/3 filter produces similar results
        let signal: [Int32] = Array(1...32)

        let result53 = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .reversible53
        )

        let resultCustom = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .custom(.leGall53)
        )

        // Should produce nearly identical results (custom uses floating-point)
        XCTAssertEqual(result53.lowpass.count, resultCustom.lowpass.count)
        XCTAssertEqual(result53.highpass.count, resultCustom.highpass.count)

        for i in 0..<result53.lowpass.count {
            let diff = abs(result53.lowpass[i] - resultCustom.lowpass[i])
            XCTAssertLessThanOrEqual(diff, 1, "Lowpass should match within 1 at index \(i)")
        }

        for i in 0..<result53.highpass.count {
            let diff = abs(result53.highpass[i] - resultCustom.highpass[i])
            XCTAssertLessThanOrEqual(diff, 1, "Highpass should match within 1 at index \(i)")
        }
    }

    func testCustomFilterReconstruction() throws {
        // Test that custom filter has good reconstruction
        let signal: [Int32] = Array(1...64)

        let (low, high) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .custom(.cdf97)
        )

        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: low,
            highpass: high,
            filter: .custom(.cdf97)
        )

        // Allow small error for floating-point custom filter
        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            let diff = abs(reconstructed[i] - signal[i])
            XCTAssertLessThanOrEqual(diff, 2, "Reconstruction error should be <= 2 at index \(i)")
        }
    }

    func testCustomFilterWithSimpleCoefficients() throws {
        // Test custom filter with simple coefficients
        let customFilter = J2KDWT1D.CustomFilter(
            steps: [
                J2KDWT1D.LiftingStep(coefficients: [-0.5], isPredict: true),
                J2KDWT1D.LiftingStep(coefficients: [0.25], isPredict: false),
            ],
            lowpassScale: 1.0,
            highpassScale: 1.0,
            isReversible: false
        )

        let signal: [Int32] = [1, 2, 3, 4, 5, 6, 7, 8]

        let (low, high) = try J2KDWT1D.forwardTransform(
            signal: signal,
            filter: .custom(customFilter)
        )

        // Should produce subbands
        XCTAssertEqual(low.count, 4)
        XCTAssertEqual(high.count, 4)

        // Test reconstruction
        let reconstructed = try J2KDWT1D.inverseTransform(
            lowpass: low,
            highpass: high,
            filter: .custom(customFilter)
        )

        XCTAssertEqual(reconstructed.count, signal.count)
    }

    func testCustomFilterEquality() {
        // Test Equatable conformance for CustomFilter
        let filter1 = J2KDWT1D.CustomFilter.cdf97
        let filter2 = J2KDWT1D.CustomFilter.cdf97
        let filter3 = J2KDWT1D.CustomFilter.leGall53

        XCTAssertEqual(filter1, filter2)
        XCTAssertNotEqual(filter1, filter3)
    }

    func testLiftingStepEquality() {
        // Test Equatable conformance for LiftingStep
        let step1 = J2KDWT1D.LiftingStep(coefficients: [-0.5], isPredict: true)
        let step2 = J2KDWT1D.LiftingStep(coefficients: [-0.5], isPredict: true)
        let step3 = J2KDWT1D.LiftingStep(coefficients: [0.25], isPredict: false)

        XCTAssertEqual(step1, step2)
        XCTAssertNotEqual(step1, step3)
    }
}

// MARK: - Helper: Seeded Random Number Generator

struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
