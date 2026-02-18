import XCTest
@testable import J2KAccelerate

/// Tests for the SIMD-accelerated HT block coding operations.
///
/// Validates correctness of SIMD implementations by comparing against
/// scalar reference computations for all supported operations.
final class J2KHTSIMDTests: XCTestCase {

    let processor = HTSIMDProcessor()

    // MARK: - Capability Detection Tests

    func testCapabilityDetection() throws {
        let capability = HTSIMDCapability.detect()
        #if arch(arm64)
        XCTAssertEqual(capability.family, .neon)
        XCTAssertEqual(capability.vectorWidth, 4)
        XCTAssertTrue(capability.isAccelerated)
        #elseif arch(x86_64)
        XCTAssertEqual(capability.family, .sse42)
        XCTAssertEqual(capability.vectorWidth, 4)
        XCTAssertTrue(capability.isAccelerated)
        #else
        XCTAssertEqual(capability.family, .scalar)
        XCTAssertEqual(capability.vectorWidth, 1)
        XCTAssertFalse(capability.isAccelerated)
        #endif
    }

    func testCapabilityEquality() throws {
        let cap1 = HTSIMDCapability(family: .neon, vectorWidth: 4)
        let cap2 = HTSIMDCapability(family: .neon, vectorWidth: 4)
        let cap3 = HTSIMDCapability(family: .sse42, vectorWidth: 4)
        XCTAssertEqual(cap1, cap2)
        XCTAssertNotEqual(cap1, cap3)
    }

    func testScalarCapabilityNotAccelerated() throws {
        let scalar = HTSIMDCapability(family: .scalar, vectorWidth: 1)
        XCTAssertFalse(scalar.isAccelerated)
    }

    func testFamilyRawValues() throws {
        XCTAssertEqual(HTSIMDCapability.Family.neon.rawValue, "neon")
        XCTAssertEqual(HTSIMDCapability.Family.sse42.rawValue, "sse42")
        XCTAssertEqual(HTSIMDCapability.Family.avx2.rawValue, "avx2")
        XCTAssertEqual(HTSIMDCapability.Family.scalar.rawValue, "scalar")
    }

    // MARK: - Batch Significance Extraction Tests

    func testBatchSignificanceExtractionBasic() throws {
        // bitPlane=3 means we test bit 3 (value 8)
        let coefficients: [Int32] = [8, 7, 16, -9, 0, 4, -24, 15]
        let result = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 3
        )

        // Reference: (abs(c) >> 3) & 1
        // abs(8)=8, 8>>3=1, &1=1
        // abs(7)=7, 7>>3=0, &1=0
        // abs(16)=16, 16>>3=2, &1=0
        // abs(-9)=9, 9>>3=1, &1=1
        // abs(0)=0, 0>>3=0, &1=0
        // abs(4)=4, 4>>3=0, &1=0
        // abs(-24)=24, 24>>3=3, &1=1
        // abs(15)=15, 15>>3=1, &1=1
        XCTAssertEqual(result, [1, 0, 0, 1, 0, 0, 1, 1])
    }

    func testBatchSignificanceExtractionEmpty() throws {
        let result = processor.batchSignificanceExtraction(
            coefficients: [],
            bitPlane: 0
        )
        XCTAssertEqual(result, [])
    }

    func testBatchSignificanceExtractionSingleElement() throws {
        let result = processor.batchSignificanceExtraction(
            coefficients: [5],
            bitPlane: 2
        )
        // abs(5) = 5, 5 >> 2 = 1, & 1 = 1
        XCTAssertEqual(result, [1])
    }

    func testBatchSignificanceExtractionAllZeros() throws {
        let coefficients: [Int32] = [0, 0, 0, 0, 0, 0, 0, 0]
        let result = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 0
        )
        XCTAssertEqual(result, [0, 0, 0, 0, 0, 0, 0, 0])
    }

    func testBatchSignificanceExtractionNegativeValues() throws {
        let coefficients: [Int32] = [-1, -2, -4, -8, -16, -32, -64, -128]
        let result = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 0
        )
        // All are significant at bitPlane 0
        XCTAssertEqual(result, [1, 0, 0, 0, 0, 0, 0, 0])
    }

    func testBatchSignificanceExtractionRemainder() throws {
        // 5 elements: 4 processed by SIMD + 1 scalar remainder
        let coefficients: [Int32] = [8, 7, 16, -9, -24]
        let result = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 3
        )
        XCTAssertEqual(result, [1, 0, 0, 1, 1])
    }

    func testBatchSignificanceExtractionLargeArray() throws {
        // Test with a larger array to exercise SIMD pipeline
        let count = 1024
        var coefficients = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            coefficients[i] = Int32(i) - 512
        }

        let result = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 5
        )

        // Verify against scalar reference
        for i in 0..<count {
            let expected = (abs(coefficients[i]) >> 5) & 1
            XCTAssertEqual(result[i], expected, "Mismatch at index \(i)")
        }
    }

    // MARK: - Batch Magnitude/Sign Separation Tests

    func testBatchMagnitudeSignSeparationBasic() throws {
        let coefficients: [Int32] = [10, -20, 0, 30, -5, 7, -1, 100]
        let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(
            coefficients: coefficients
        )

        XCTAssertEqual(magnitudes, [10, 20, 0, 30, 5, 7, 1, 100])
        XCTAssertEqual(signs, [0, 1, 0, 0, 1, 0, 1, 0])
    }

    func testBatchMagnitudeSignSeparationEmpty() throws {
        let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(
            coefficients: []
        )
        XCTAssertEqual(magnitudes, [])
        XCTAssertEqual(signs, [])
    }

    func testBatchMagnitudeSignSeparationSingleElement() throws {
        let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(
            coefficients: [-42]
        )
        XCTAssertEqual(magnitudes, [42])
        XCTAssertEqual(signs, [1])
    }

    func testBatchMagnitudeSignSeparationRemainder() throws {
        let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(
            coefficients: [1, -2, 3, 4, -5, 6]
        )
        XCTAssertEqual(magnitudes, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(signs, [0, 1, 0, 0, 1, 0])
    }

    func testBatchMagnitudeSignSeparationLargeArray() throws {
        let count = 1024
        var coefficients = [Int32](repeating: 0, count: count)
        for i in 0..<count {
            coefficients[i] = Int32(i) - 512
        }

        let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(
            coefficients: coefficients
        )

        for i in 0..<count {
            let c = coefficients[i]
            XCTAssertEqual(magnitudes[i], abs(c), "Magnitude mismatch at \(i)")
            XCTAssertEqual(signs[i], c < 0 ? 1 : 0, "Sign mismatch at \(i)")
        }
    }

    // MARK: - Batch Refinement Bit Extraction Tests

    func testBatchRefinementBitExtractionBasic() throws {
        let coefficients: [Int32] = [15, -12, 8, 3, 20, -7, 0, 16]
        let sigFlags: [Int32] = [1, 1, 0, 1, 1, 0, 1, 1]
        let result = processor.batchRefinementBitExtraction(
            coefficients: coefficients,
            significanceFlags: sigFlags,
            bitPlane: 2
        )

        // Reference: if sig, (abs(c) >> 2) & 1, else 0
        // sig=1: abs(15)=15, 15>>2=3, &1=1
        // sig=1: abs(-12)=12, 12>>2=3, &1=1
        // sig=0: 0
        // sig=1: abs(3)=3, 3>>2=0, &1=0
        // sig=1: abs(20)=20, 20>>2=5, &1=1
        // sig=0: 0
        // sig=1: abs(0)=0, 0>>2=0, &1=0
        // sig=1: abs(16)=16, 16>>2=4, &1=0
        XCTAssertEqual(result, [1, 1, 0, 0, 1, 0, 0, 0])
    }

    func testBatchRefinementBitExtractionEmpty() throws {
        let result = processor.batchRefinementBitExtraction(
            coefficients: [],
            significanceFlags: [],
            bitPlane: 0
        )
        XCTAssertEqual(result, [])
    }

    func testBatchRefinementBitExtractionAllSignificant() throws {
        let coefficients: [Int32] = [7, -7, 7, -7]
        let sigFlags: [Int32] = [1, 1, 1, 1]
        let result = processor.batchRefinementBitExtraction(
            coefficients: coefficients,
            significanceFlags: sigFlags,
            bitPlane: 1
        )
        // abs(7)=7, 7>>1=3, &1=1
        XCTAssertEqual(result, [1, 1, 1, 1])
    }

    func testBatchRefinementBitExtractionNoneSignificant() throws {
        let coefficients: [Int32] = [100, -200, 300, -400]
        let sigFlags: [Int32] = [0, 0, 0, 0]
        let result = processor.batchRefinementBitExtraction(
            coefficients: coefficients,
            significanceFlags: sigFlags,
            bitPlane: 3
        )
        XCTAssertEqual(result, [0, 0, 0, 0])
    }

    func testBatchRefinementBitExtractionMismatchedLengths() throws {
        let result = processor.batchRefinementBitExtraction(
            coefficients: [1, 2],
            significanceFlags: [1],
            bitPlane: 0
        )
        XCTAssertEqual(result, [])
    }

    // MARK: - Batch VLC Pattern Extraction Tests

    func testBatchVLCPatternExtractionBasic() throws {
        // Pairs: (8,-9), (0,16), (24,0), (15,8)
        let coefficients: [Int32] = [8, -9, 0, 16, 24, 0, 15, 8]
        let result = processor.batchVLCPatternExtraction(
            coefficients: coefficients,
            bitPlane: 3,
            pairCount: 4
        )

        // Reference: sig0 | (sig1 << 1)
        // pair 0: sig(8)=1, sig(-9)=1 → 1 | (1<<1) = 3
        // pair 1: sig(0)=0, sig(16)=0 → 0 | (0<<1) = 0
        // pair 2: sig(24)=1, sig(0)=0 → 1 | (0<<1) = 1
        // pair 3: sig(15)=1, sig(8)=1 → 1 | (1<<1) = 3
        XCTAssertEqual(result, [3, 0, 1, 3])
    }

    func testBatchVLCPatternExtractionEmpty() throws {
        let result = processor.batchVLCPatternExtraction(
            coefficients: [],
            bitPlane: 0,
            pairCount: 0
        )
        XCTAssertEqual(result, [])
    }

    func testBatchVLCPatternExtractionSinglePair() throws {
        let result = processor.batchVLCPatternExtraction(
            coefficients: [5, -3],
            bitPlane: 1,
            pairCount: 1
        )
        // abs(5)>>1 = 2, &1 = 0; abs(-3)>>1 = 1, &1 = 1 → 0 | (1<<1) = 2
        XCTAssertEqual(result, [2])
    }

    func testBatchVLCPatternExtractionOddPairCount() throws {
        // 3 pairs = 6 coefficients; 2 processed by SIMD + 1 scalar remainder
        let coefficients: [Int32] = [8, 8, 0, 0, 8, 0]
        let result = processor.batchVLCPatternExtraction(
            coefficients: coefficients,
            bitPlane: 3,
            pairCount: 3
        )
        // pair 0: both sig → 3
        // pair 1: neither sig → 0
        // pair 2: first sig → 1
        XCTAssertEqual(result, [3, 0, 1])
    }

    func testBatchVLCPatternExtractionInsufficientCoefficients() throws {
        let result = processor.batchVLCPatternExtraction(
            coefficients: [1, 2],
            bitPlane: 0,
            pairCount: 3  // needs 6 coefficients but only 2
        )
        XCTAssertEqual(result, [])
    }

    // MARK: - Batch Maximum Absolute Value Tests

    func testBatchMaxAbsValueBasic() throws {
        let coefficients: [Int32] = [10, -20, 15, -5, 8, -30, 25, 3]
        let result = processor.batchMaxAbsValue(coefficients: coefficients)
        XCTAssertEqual(result, 30)
    }

    func testBatchMaxAbsValueEmpty() throws {
        let result = processor.batchMaxAbsValue(coefficients: [])
        XCTAssertEqual(result, 0)
    }

    func testBatchMaxAbsValueSingleElement() throws {
        XCTAssertEqual(processor.batchMaxAbsValue(coefficients: [42]), 42)
        XCTAssertEqual(processor.batchMaxAbsValue(coefficients: [-42]), 42)
    }

    func testBatchMaxAbsValueAllNegative() throws {
        let coefficients: [Int32] = [-1, -5, -3, -7, -2, -10, -4, -6]
        let result = processor.batchMaxAbsValue(coefficients: coefficients)
        XCTAssertEqual(result, 10)
    }

    func testBatchMaxAbsValueWithRemainder() throws {
        // 5 elements: SIMD handles 4, scalar handles 1
        let coefficients: [Int32] = [1, 2, 3, 4, -100]
        let result = processor.batchMaxAbsValue(coefficients: coefficients)
        XCTAssertEqual(result, 100)
    }

    // MARK: - Batch Coefficient Reconstruction Tests

    func testBatchCoefficientReconstructionBasic() throws {
        let magnitudes: [Int32] = [10, 20, 0, 30, 5, 7, 1, 100]
        let signs: [Int32] = [0, 1, 0, 0, 1, 0, 1, 0]
        let result = processor.batchCoefficientReconstruction(
            magnitudes: magnitudes,
            signs: signs
        )
        XCTAssertEqual(result, [10, -20, 0, 30, -5, 7, -1, 100])
    }

    func testBatchCoefficientReconstructionEmpty() throws {
        let result = processor.batchCoefficientReconstruction(
            magnitudes: [],
            signs: []
        )
        XCTAssertEqual(result, [])
    }

    func testBatchCoefficientReconstructionRoundTrip() throws {
        let original: [Int32] = [42, -17, 0, 255, -128, 1, -1, 1000]
        let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(
            coefficients: original
        )
        let reconstructed = processor.batchCoefficientReconstruction(
            magnitudes: magnitudes,
            signs: signs
        )
        XCTAssertEqual(reconstructed, original)
    }

    func testBatchCoefficientReconstructionMismatchedLengths() throws {
        let result = processor.batchCoefficientReconstruction(
            magnitudes: [1, 2, 3],
            signs: [0, 1]
        )
        XCTAssertEqual(result, [])
    }

    // MARK: - Batch Significance Counting Tests

    func testBatchSignificanceCountBasic() throws {
        let coefficients: [Int32] = [8, 7, 16, -9, 0, 4, -24, 15]
        let count = processor.batchSignificanceCount(
            coefficients: coefficients,
            bitPlane: 3
        )
        // Significant at bitPlane 3: 8, -9, -24, 15 → 4
        XCTAssertEqual(count, 4)
    }

    func testBatchSignificanceCountEmpty() throws {
        let count = processor.batchSignificanceCount(
            coefficients: [],
            bitPlane: 0
        )
        XCTAssertEqual(count, 0)
    }

    func testBatchSignificanceCountAllSignificant() throws {
        let coefficients: [Int32] = [1, -1, 3, -3, 5, -5, 7, -7]
        let count = processor.batchSignificanceCount(
            coefficients: coefficients,
            bitPlane: 0
        )
        XCTAssertEqual(count, 8)
    }

    func testBatchSignificanceCountNoneSignificant() throws {
        let coefficients: [Int32] = [0, 0, 0, 0]
        let count = processor.batchSignificanceCount(
            coefficients: coefficients,
            bitPlane: 0
        )
        XCTAssertEqual(count, 0)
    }

    func testBatchSignificanceCountWithRemainder() throws {
        // 5 elements: 1 in remainder
        let coefficients: [Int32] = [8, 0, 0, 0, -8]
        let count = processor.batchSignificanceCount(
            coefficients: coefficients,
            bitPlane: 3
        )
        XCTAssertEqual(count, 2)
    }

    // MARK: - SIMD vs Scalar Consistency Tests

    func testSIMDScalarConsistencySignificanceExtraction() throws {
        // Test that SIMD and scalar paths produce identical results
        // across various array sizes that exercise both paths
        for size in [1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 100, 256] {
            var coefficients = [Int32](repeating: 0, count: size)
            for i in 0..<size {
                coefficients[i] = Int32(i * 7 - size * 3)
            }

            let simdResult = processor.batchSignificanceExtraction(
                coefficients: coefficients,
                bitPlane: 4
            )

            // Scalar reference
            let scalarResult = coefficients.map { (abs($0) >> 4) & 1 }

            XCTAssertEqual(
                simdResult, scalarResult,
                "Mismatch at size \(size)"
            )
        }
    }

    func testSIMDScalarConsistencyMagnitudeSign() throws {
        for size in [1, 3, 4, 5, 8, 16, 33, 100] {
            var coefficients = [Int32](repeating: 0, count: size)
            for i in 0..<size {
                coefficients[i] = Int32(i * 13 - size * 5)
            }

            let (magnitudes, signs) = processor.batchMagnitudeSignSeparation(
                coefficients: coefficients
            )

            for i in 0..<size {
                let c = coefficients[i]
                XCTAssertEqual(
                    magnitudes[i], abs(c),
                    "Magnitude mismatch at index \(i), size \(size)"
                )
                XCTAssertEqual(
                    signs[i], c < 0 ? 1 : 0,
                    "Sign mismatch at index \(i), size \(size)"
                )
            }
        }
    }

    func testSIMDScalarConsistencyMaxAbsValue() throws {
        for size in [1, 3, 4, 5, 8, 16, 33, 100, 1024] {
            var coefficients = [Int32](repeating: 0, count: size)
            for i in 0..<size {
                coefficients[i] = Int32(i * 17 - size * 8)
            }

            let simdMax = processor.batchMaxAbsValue(coefficients: coefficients)
            let scalarMax = coefficients.map { abs($0) }.max() ?? 0

            XCTAssertEqual(
                simdMax, scalarMax,
                "Max mismatch at size \(size)"
            )
        }
    }

    // MARK: - Performance Comparison Tests

    func testBenchmarkSignificanceExtraction() throws {
        let size = 4096
        var coefficients = [Int32](repeating: 0, count: size)
        for i in 0..<size {
            coefficients[i] = Int32.random(in: -1000...1000)
        }

        // Warm up
        _ = processor.batchSignificanceExtraction(
            coefficients: coefficients,
            bitPlane: 5
        )

        measure {
            for _ in 0..<100 {
                _ = processor.batchSignificanceExtraction(
                    coefficients: coefficients,
                    bitPlane: 5
                )
            }
        }
    }

    func testBenchmarkMagnitudeSignSeparation() throws {
        let size = 4096
        var coefficients = [Int32](repeating: 0, count: size)
        for i in 0..<size {
            coefficients[i] = Int32.random(in: -1000...1000)
        }

        // Warm up
        _ = processor.batchMagnitudeSignSeparation(coefficients: coefficients)

        measure {
            for _ in 0..<100 {
                _ = processor.batchMagnitudeSignSeparation(
                    coefficients: coefficients
                )
            }
        }
    }

    func testBenchmarkVLCPatternExtraction() throws {
        let pairCount = 2048
        var coefficients = [Int32](repeating: 0, count: pairCount * 2)
        for i in 0..<coefficients.count {
            coefficients[i] = Int32.random(in: -1000...1000)
        }

        // Warm up
        _ = processor.batchVLCPatternExtraction(
            coefficients: coefficients,
            bitPlane: 5,
            pairCount: pairCount
        )

        measure {
            for _ in 0..<100 {
                _ = processor.batchVLCPatternExtraction(
                    coefficients: coefficients,
                    bitPlane: 5,
                    pairCount: pairCount
                )
            }
        }
    }

    func testBenchmarkMaxAbsValue() throws {
        let size = 4096
        var coefficients = [Int32](repeating: 0, count: size)
        for i in 0..<size {
            coefficients[i] = Int32.random(in: -10000...10000)
        }

        // Warm up
        _ = processor.batchMaxAbsValue(coefficients: coefficients)

        measure {
            for _ in 0..<100 {
                _ = processor.batchMaxAbsValue(coefficients: coefficients)
            }
        }
    }
}
