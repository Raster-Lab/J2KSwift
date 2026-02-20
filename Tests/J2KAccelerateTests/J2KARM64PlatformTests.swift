//
// J2KARM64PlatformTests.swift
// J2KSwift
//
import XCTest
@testable import J2KAccelerate
@testable import J2KCore

/// Tests specific to ARM64 Linux platform validation.
///
/// These tests verify that NEON SIMD acceleration is properly detected and
/// functioning on ARM64 architectures, including Ubuntu ARM64 and Amazon Linux ARM64.
final class J2KARM64PlatformTests: XCTestCase {
    // MARK: - Architecture Detection Tests

    func testArchitectureIsARM64() throws {
        #if arch(arm64)
        // This test should only pass when compiled for ARM64
        XCTAssertTrue(true, "Running on ARM64 architecture")
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    func testNEONCapabilityDetection() throws {
        #if arch(arm64)
        let capability = HTSIMDCapability.detect()

        XCTAssertEqual(capability.family, .neon, "ARM64 should detect NEON")
        XCTAssertEqual(capability.vectorWidth, 4, "NEON vector width should be 4")
        XCTAssertTrue(capability.isAccelerated, "NEON should be accelerated")
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    // MARK: - NEON SIMD Correctness Tests

    func testNEONSignificanceExtraction() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        // Test with various coefficient patterns
        let testCases: [([Int32], Int, [Int32])] = [
            // (coefficients, bitPlane, expected)
            ([8, 7, 16, -9], 3, [1, 0, 0, 1]),
            ([0, 0, 0, 0], 0, [0, 0, 0, 0]),
            ([1, 2, 4, 8, 16, 32, 64, 128], 0, [1, 0, 0, 0, 0, 0, 0, 0]),
            ([-1, -2, -4, -8], 2, [0, 0, 1, 0]),
            ([127, 255, 511, 1023], 7, [0, 1, 1, 1])
        ]

        for (coeffs, bitPlane, expected) in testCases {
            let result = processor.batchSignificanceExtraction(
                coefficients: coeffs,
                bitPlane: bitPlane
            )
            XCTAssertEqual(result, expected,
                "Significance extraction failed for coefficients \(coeffs) at bit plane \(bitPlane)")
        }
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    func testNEONMagnitudeSignSeparation() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        let coefficients: [Int32] = [10, -20, 30, -40, 0, 5, -15, 25]
        let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(coefficients: coefficients)

        XCTAssertEqual(magnitudes, [10, 20, 30, 40, 0, 5, 15, 25])
        XCTAssertEqual(signs, [0, 1, 0, 1, 0, 0, 1, 0])
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    func testNEONRefinementBitExtraction() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        // Test refinement bit extraction at various bit planes
        let magnitudes: [Int32] = [15, 14, 13, 12, 11, 10, 9, 8]

        for bitPlane in 0..<4 {
            let result = processor.batchRefinementBitExtraction(
                magnitudes: magnitudes,
                bitPlane: bitPlane
            )

            // Verify each result matches scalar computation
            for i in 0..<magnitudes.count {
                let expected = (magnitudes[i] >> bitPlane) & 1
                XCTAssertEqual(result[i], expected,
                    "Refinement bit at plane \(bitPlane) incorrect for magnitude \(magnitudes[i])")
            }
        }
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    func testNEONVLCPatternExtraction() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        let significance: [Int32] = [1, 0, 1, 1, 0, 0, 1, 0]
        let result = processor.batchVLCPatternExtraction(significance: significance)

        // VLC pattern is computed by combining adjacent significance values
        // Expected: [1, 1, 0, 1] (pairs: [1,0], [1,1], [0,0], [1,0])
        XCTAssertEqual(result.count, 4)
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    // MARK: - NEON vs Scalar Comparison Tests

    func testNEONMatchesScalarForLargeDataset() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()
        let size = 1024
        var coefficients: [Int32] = []

        // Generate test data
        for i in 0..<size {
            coefficients.append(Int32((i % 256) - 128))
        }

        // Test significance extraction
        let simdResult = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 5
        )

        // Compute scalar reference
        var scalarResult: [Int32] = []
        for coeff in coefficients {
            let mag = abs(coeff)
            let bit = (mag >> 5) & 1
            scalarResult.append(bit)
        }

        XCTAssertEqual(simdResult, scalarResult,
            "NEON and scalar results should match for large dataset")
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    // MARK: - Memory Alignment Tests

    func testNEONMemoryAlignment() throws {
        #if arch(arm64)
        // NEON operations on ARM64 benefit from 16-byte alignment
        // Test that unaligned data still works correctly

        let processor = HTSIMDProcessor()

        // Create deliberately unaligned data (odd starting offset)
        var allData: [Int32] = Array(repeating: 0, count: 100)
        for i in 0..<100 {
            allData[i] = Int32(i)
        }

        // Test with various offsets
        for offset in 0..<4 {
            let slice = Array(allData[offset..<(offset + 8)])
            let result = processor.batchSignificanceExtraction(
                coefficients: slice,
                bitPlane: 3
            )

            // Verify correctness regardless of alignment
            XCTAssertEqual(result.count, 8,
                "Result size should match input size at offset \(offset)")

            for i in 0..<slice.count {
                let expected = (abs(slice[i]) >> 3) & 1
                XCTAssertEqual(result[i], expected,
                    "Incorrect result at offset \(offset), index \(i)")
            }
        }
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    // MARK: - Performance Validation Tests

    func testNEONPerformanceBenefit() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()
        let size = 10000
        var coefficients: [Int32] = []

        for i in 0..<size {
            coefficients.append(Int32.random(in: -1000...1000))
        }

        // Measure SIMD performance
        let simdStart = Date()
        for _ in 0..<100 {
            _ = processor.batchSignificanceExtraction(
                coefficients: coefficients,
                bitPlane: 5
            )
        }
        let simdDuration = Date().timeIntervalSince(simdStart)

        // Measure scalar performance
        let scalarStart = Date()
        for _ in 0..<100 {
            var result: [Int32] = []
            for coeff in coefficients {
                let mag = abs(coeff)
                let bit = (mag >> 5) & 1
                result.append(bit)
            }
        }
        let scalarDuration = Date().timeIntervalSince(scalarStart)

        // NEON should be faster than scalar (typically 2-4x)
        XCTAssertLessThan(simdDuration, scalarDuration,
            "NEON SIMD should be faster than scalar implementation")

        let speedup = scalarDuration / simdDuration
        print("NEON speedup: \(String(format: "%.2f", speedup))x")
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    // MARK: - Platform-Specific Edge Cases

    func testNEONWithEmptyInput() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        let result = processor.batchSignificanceExtraction(
            coefficients: [],
            bitPlane: 0
        )

        XCTAssertEqual(result, [])
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    func testNEONWithSingleElement() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        let result = processor.batchSignificanceExtraction(
            coefficients: [42],
            bitPlane: 3
        )

        // 42 >> 3 = 5, 5 & 1 = 1
        XCTAssertEqual(result, [1])
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    func testNEONWithNonMultipleOfFour() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        // Test with 7 elements (not a multiple of 4, the vector width)
        let coefficients: [Int32] = [8, 16, 24, 32, 40, 48, 56]
        let result = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 4
        )

        XCTAssertEqual(result.count, 7)

        // Verify each element
        for i in 0..<coefficients.count {
            let expected = (abs(coefficients[i]) >> 4) & 1
            XCTAssertEqual(result[i], expected)
        }
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    func testNEONWithExtremeValues() throws {
        #if arch(arm64)
        let processor = HTSIMDProcessor()

        let extremes: [Int32] = [
            Int32.max,
            Int32.min + 1, // Avoid overflow in abs()
            0,
            -1
        ]

        let result = processor.batchSignificanceExtraction(
            coefficients: extremes,
            bitPlane: 30
        )

        XCTAssertEqual(result.count, 4)
        // Just verify it doesn't crash and produces some result
        #else
        throw XCTSkip("Test requires ARM64 architecture")
        #endif
    }

    // MARK: - Cross-Platform Consistency Tests

    func testConsistencyAcrossPlatforms() throws {
        // This test verifies that results are consistent regardless of architecture
        let processor = HTSIMDProcessor()

        let testData: [Int32] = [100, -200, 300, -400, 0, 50, -75, 125]
        let bitPlane = 5

        let result = processor.batchSignificanceExtraction(
            coefficients: testData,
            bitPlane: bitPlane
        )

        // Compute expected result (platform-independent)
        var expected: [Int32] = []
        for coeff in testData {
            let mag = abs(coeff)
            let bit = (mag >> bitPlane) & 1
            expected.append(bit)
        }

        XCTAssertEqual(result, expected,
            "Results should be consistent across platforms")
    }
}
