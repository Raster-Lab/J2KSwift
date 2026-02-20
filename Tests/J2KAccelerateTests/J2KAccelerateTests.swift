//
// J2KAccelerateTests.swift
// J2KSwift
//
import XCTest
@testable import J2KAccelerate
@testable import J2KCore

/// Tests for the J2KAccelerate module - Hardware-Accelerated Wavelet Transforms.
final class J2KAccelerateTests: XCTestCase {
    let dwt = J2KDWTAccelerated()
    let tolerance = 1e-6

    // MARK: - Basic Tests

    /// Tests that the module compiles and links correctly.
    func testModuleCompilationAndLinkage() throws {
        let dwt = J2KDWTAccelerated()
        XCTAssertNotNil(dwt)
    }

    /// Tests that hardware acceleration availability can be checked.
    func testAccelerationAvailability() throws {
        // Should be true on macOS/iOS, false on Linux
        #if canImport(Accelerate)
        XCTAssertTrue(J2KDWTAccelerated.isAvailable)
        #else
        XCTAssertFalse(J2KDWTAccelerated.isAvailable)
        #endif
    }

    // MARK: - 1D Forward Transform Tests (9/7 Filter)

    /// Tests 1D forward transform with 9/7 filter on a simple signal.
    func testForwardTransform97Simple() throws {
        #if canImport(Accelerate)
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

        let (low, high) = try dwt.forwardTransform97(signal: signal)

        // Check output sizes
        XCTAssertEqual(low.count, 4) // (8 + 1) / 2 = 4
        XCTAssertEqual(high.count, 4) // 8 / 2 = 4

        // The lowpass should contain approximation (lower frequencies)
        // and highpass should contain details (higher frequencies)
        XCTAssertNotEqual(low, [0, 0, 0, 0])
        XCTAssertNotEqual(high, [0, 0, 0, 0])
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0, 3.0, 4.0]))
        #endif
    }

    /// Tests 1D forward transform with symmetric boundary extension.
    func testForwardTransform97SymmetricBoundary() throws {
        #if canImport(Accelerate)
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0]

        let (low, high) = try dwt.forwardTransform97(
            signal: signal,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(low.count, 2)
        XCTAssertEqual(high.count, 2)
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0, 3.0, 4.0]))
        #endif
    }

    /// Tests 1D forward transform with periodic boundary extension.
    func testForwardTransform97PeriodicBoundary() throws {
        #if canImport(Accelerate)
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0]

        let (low, high) = try dwt.forwardTransform97(
            signal: signal,
            boundaryExtension: .periodic
        )

        XCTAssertEqual(low.count, 2)
        XCTAssertEqual(high.count, 2)
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0, 3.0, 4.0]))
        #endif
    }

    /// Tests 1D forward transform with zero padding boundary extension.
    func testForwardTransform97ZeroPaddingBoundary() throws {
        #if canImport(Accelerate)
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0]

        let (low, high) = try dwt.forwardTransform97(
            signal: signal,
            boundaryExtension: .zeroPadding
        )

        XCTAssertEqual(low.count, 2)
        XCTAssertEqual(high.count, 2)
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0, 3.0, 4.0]))
        #endif
    }

    /// Tests forward transform with odd-length signal.
    func testForwardTransform97OddLength() throws {
        #if canImport(Accelerate)
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]

        let (low, high) = try dwt.forwardTransform97(signal: signal)

        XCTAssertEqual(low.count, 3) // (5 + 1) / 2 = 3
        XCTAssertEqual(high.count, 2) // 5 / 2 = 2
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0, 3.0]))
        #endif
    }

    /// Tests forward transform with minimum size signal (2 elements).
    func testForwardTransform97MinimumSize() throws {
        #if canImport(Accelerate)
        let signal: [Double] = [1.0, 2.0]

        let (low, high) = try dwt.forwardTransform97(signal: signal)

        XCTAssertEqual(low.count, 1)
        XCTAssertEqual(high.count, 1)
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0]))
        #endif
    }

    /// Tests that forward transform rejects invalid input.
    func testForwardTransform97InvalidInput() throws {
        #if canImport(Accelerate)
        // Too short
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0]))
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: []))
        #else
        // Should throw unsupported feature error
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0]))
        #endif
    }

    // MARK: - 1D Inverse Transform Tests (9/7 Filter)

    /// Tests 1D inverse transform with 9/7 filter.
    func testInverseTransform97Simple() throws {
        #if canImport(Accelerate)
        let low: [Double] = [1.0, 2.0, 3.0, 4.0]
        let high: [Double] = [0.5, 0.5, 0.5, 0.5]

        let reconstructed = try dwt.inverseTransform97(lowpass: low, highpass: high)

        XCTAssertEqual(reconstructed.count, 8) // 4 + 4 = 8
        #else
        XCTAssertThrowsError(try dwt.inverseTransform97(lowpass: [1.0], highpass: [1.0]))
        #endif
    }

    /// Tests that inverse transform rejects invalid input.
    func testInverseTransform97InvalidInput() throws {
        #if canImport(Accelerate)
        // Empty subbands
        XCTAssertThrowsError(try dwt.inverseTransform97(lowpass: [], highpass: [1.0]))
        XCTAssertThrowsError(try dwt.inverseTransform97(lowpass: [1.0], highpass: []))

        // Incompatible sizes (differ by more than 1)
        XCTAssertThrowsError(try dwt.inverseTransform97(lowpass: [1.0, 2.0, 3.0], highpass: [1.0]))
        #else
        XCTAssertThrowsError(try dwt.inverseTransform97(lowpass: [1.0], highpass: [1.0]))
        #endif
    }

    // MARK: - Perfect Reconstruction Tests

    /// Tests perfect reconstruction (forward then inverse).
    func testPerfectReconstruction97() throws {
        #if canImport(Accelerate)
        let original: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

        // Forward transform
        let (low, high) = try dwt.forwardTransform97(signal: original)

        // Inverse transform
        let reconstructed = try dwt.inverseTransform97(lowpass: low, highpass: high)

        // Check that reconstruction is close to original (9/7 is not perfectly reversible)
        XCTAssertEqual(reconstructed.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(reconstructed[i], original[i], accuracy: tolerance,
                          "Reconstruction error at index \(i)")
        }
        #else
        // Test that proper error is thrown on unsupported platforms
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0]))
        #endif
    }

    /// Tests perfect reconstruction with odd-length signal.
    func testPerfectReconstruction97OddLength() throws {
        #if canImport(Accelerate)
        let original: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0]

        let (low, high) = try dwt.forwardTransform97(signal: original)
        let reconstructed = try dwt.inverseTransform97(lowpass: low, highpass: high)

        XCTAssertEqual(reconstructed.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(reconstructed[i], original[i], accuracy: tolerance)
        }
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0, 3.0]))
        #endif
    }

    /// Tests perfect reconstruction with different boundary modes.
    func testPerfectReconstructionBoundaryModes() throws {
        #if canImport(Accelerate)
        let original: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]

        for boundary in [BoundaryExtension.symmetric, .periodic, .zeroPadding] {
            let (low, high) = try dwt.forwardTransform97(
                signal: original,
                boundaryExtension: boundary
            )
            let reconstructed = try dwt.inverseTransform97(
                lowpass: low,
                highpass: high,
                boundaryExtension: boundary
            )

            XCTAssertEqual(reconstructed.count, original.count)
            for i in 0..<original.count {
                XCTAssertEqual(reconstructed[i], original[i], accuracy: tolerance,
                              "Failed with boundary mode \(boundary) at index \(i)")
            }
        }
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0]))
        #endif
    }

    /// Tests perfect reconstruction with a large signal.
    func testPerfectReconstruction97LargeSignal() throws {
        #if canImport(Accelerate)
        let size = 1024
        let original = (0..<size).map { Double($0) }

        let (low, high) = try dwt.forwardTransform97(signal: original)
        let reconstructed = try dwt.inverseTransform97(lowpass: low, highpass: high)

        XCTAssertEqual(reconstructed.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(reconstructed[i], original[i], accuracy: tolerance)
        }
        #else
        XCTAssertThrowsError(try dwt.forwardTransform97(signal: [1.0, 2.0]))
        #endif
    }

    // MARK: - 2D Transform Tests

    /// Tests 2D forward transform on a simple image.
    func testForwardTransform2DSimple() throws {
        #if canImport(Accelerate)
        let width = 8
        let height = 8
        let data = (0..<(width * height)).map { Double($0) }

        let decompositions = try dwt.forwardTransform2D(
            data: data,
            width: width,
            height: height,
            levels: 1
        )

        XCTAssertEqual(decompositions.count, 1)

        let level = decompositions[0]
        XCTAssertEqual(level.llWidth, 4) // (8 + 1) / 2 = 4
        XCTAssertEqual(level.llHeight, 4)
        XCTAssertEqual(level.ll.count, 16) // 4 * 4
        XCTAssertEqual(level.lh.count, 16) // 4 * 4
        XCTAssertEqual(level.hl.count, 16) // 4 * 4
        XCTAssertEqual(level.hh.count, 16) // 4 * 4
        #else
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0], width: 1, height: 1))
        #endif
    }

    /// Tests 2D forward transform with multiple levels.
    func testForwardTransform2DMultiLevel() throws {
        #if canImport(Accelerate)
        let width = 16
        let height = 16
        let data = (0..<(width * height)).map { Double($0) }

        let decompositions = try dwt.forwardTransform2D(
            data: data,
            width: width,
            height: height,
            levels: 3
        )

        XCTAssertEqual(decompositions.count, 3)

        // Check first level
        XCTAssertEqual(decompositions[0].llWidth, 8)
        XCTAssertEqual(decompositions[0].llHeight, 8)

        // Check second level
        XCTAssertEqual(decompositions[1].llWidth, 4)
        XCTAssertEqual(decompositions[1].llHeight, 4)

        // Check third level
        XCTAssertEqual(decompositions[2].llWidth, 2)
        XCTAssertEqual(decompositions[2].llHeight, 2)
        #else
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0], width: 1, height: 1))
        #endif
    }

    /// Tests 2D perfect reconstruction.
    func testPerfectReconstruction2D() throws {
        #if canImport(Accelerate)
        let width = 8
        let height = 8
        let original = (0..<(width * height)).map { Double($0) }

        let decompositions = try dwt.forwardTransform2D(
            data: original,
            width: width,
            height: height,
            levels: 1
        )

        let reconstructed = try dwt.inverseTransform2D(
            decompositions: decompositions,
            width: width,
            height: height
        )

        XCTAssertEqual(reconstructed.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(reconstructed[i], original[i], accuracy: tolerance,
                          "Reconstruction error at index \(i)")
        }
        #else
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0], width: 1, height: 1))
        #endif
    }

    /// Tests 2D perfect reconstruction with multiple levels.
    func testPerfectReconstruction2DMultiLevel() throws {
        #if canImport(Accelerate)
        let width = 16
        let height = 16
        let original = (0..<(width * height)).map { Double($0) }

        let decompositions = try dwt.forwardTransform2D(
            data: original,
            width: width,
            height: height,
            levels: 3
        )

        let reconstructed = try dwt.inverseTransform2D(
            decompositions: decompositions,
            width: width,
            height: height
        )

        XCTAssertEqual(reconstructed.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(reconstructed[i], original[i], accuracy: tolerance)
        }
        #else
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0], width: 1, height: 1))
        #endif
    }

    /// Tests that 2D transform rejects invalid dimensions.
    func testForwardTransform2DInvalidDimensions() throws {
        #if canImport(Accelerate)
        // Too small
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0], width: 1, height: 1))

        // Mismatched size
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0, 2.0], width: 2, height: 2))

        // Invalid levels
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0, 2.0, 3.0, 4.0], width: 2, height: 2, levels: 0))
        #else
        XCTAssertThrowsError(try dwt.forwardTransform2D(data: [1.0], width: 1, height: 1))
        #endif
    }

    // MARK: - Performance Tests

    /// Tests performance of 1D transform on a large signal.
    func testPerformance1DTransform() throws {
        #if canImport(Accelerate)
        let size = 8192
        let signal = (0..<size).map { Double($0) }

        measure {
            do {
                let (low, high) = try dwt.forwardTransform97(signal: signal)
                _ = try dwt.inverseTransform97(lowpass: low, highpass: high)
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        // Skip on unsupported platforms
        #endif
    }

    /// Tests performance of 2D transform on a large image.
    func testPerformance2DTransform() throws {
        #if canImport(Accelerate)
        let width = 512
        let height = 512
        let data = (0..<(width * height)).map { Double($0) }

        measure {
            do {
                let decompositions = try dwt.forwardTransform2D(
                    data: data,
                    width: width,
                    height: height,
                    levels: 3
                )
                _ = try dwt.inverseTransform2D(
                    decompositions: decompositions,
                    width: width,
                    height: height
                )
            } catch {
                XCTFail("Transform failed: \(error)")
            }
        }
        #else
        // Skip on unsupported platforms
        #endif
    }

    // MARK: - Parallel Processing Tests

    func testForwardTransform2DParallel() async throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 64
        let height = 64
        var data = [Double](repeating: 0, count: width * height)

        // Create test pattern
        for y in 0..<height {
            for x in 0..<width {
                data[y * width + x] = Double(x + y)
            }
        }

        let decompositions = try await dwt.forwardTransform2DParallel(
            data: data,
            width: width,
            height: height,
            levels: 2
        )

        XCTAssertEqual(decompositions.count, 2, "Should have 2 levels")
        XCTAssertFalse(decompositions[0].ll.isEmpty, "LL subband should not be empty")
        #else
        // Skip on unsupported platforms
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testParallelVsSequentialConsistency() async throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 32
        let height = 32
        var data = [Double](repeating: 0, count: width * height)

        // Create test pattern
        for i in 0..<data.count {
            data[i] = Double(i % 256)
        }

        // Sequential transform
        let sequentialResult = try dwt.forwardTransform2D(
            data: data,
            width: width,
            height: height,
            levels: 3
        )

        // Parallel transform
        let parallelResult = try await dwt.forwardTransform2DParallel(
            data: data,
            width: width,
            height: height,
            levels: 3
        )

        // Results should be identical
        XCTAssertEqual(sequentialResult.count, parallelResult.count, "Level counts should match")

        for level in 0..<sequentialResult.count {
            let seqLevel = sequentialResult[level]
            let parLevel = parallelResult[level]

            XCTAssertEqual(seqLevel.ll.count, parLevel.ll.count, "LL sizes should match at level \(level)")
            XCTAssertEqual(seqLevel.lh.count, parLevel.lh.count, "LH sizes should match at level \(level)")
            XCTAssertEqual(seqLevel.hl.count, parLevel.hl.count, "HL sizes should match at level \(level)")
            XCTAssertEqual(seqLevel.hh.count, parLevel.hh.count, "HH sizes should match at level \(level)")

            // Check that values are close (within floating point precision)
            for i in 0..<seqLevel.ll.count {
                XCTAssertEqual(seqLevel.ll[i], parLevel.ll[i], accuracy: 1e-10,
                             "LL values should match at level \(level), index \(i)")
            }
        }
        #else
        // Skip on unsupported platforms
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testParallelWithDifferentConcurrencyLimits() async throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 32
        let height = 32
        var data = [Double](repeating: 0, count: width * height)

        for i in 0..<data.count {
            data[i] = Double(i % 100)
        }

        // Test with different concurrency limits
        let result1 = try await dwt.forwardTransform2DParallel(
            data: data,
            width: width,
            height: height,
            maxConcurrentTasks: 2
        )

        let result2 = try await dwt.forwardTransform2DParallel(
            data: data,
            width: width,
            height: height,
            maxConcurrentTasks: 16
        )

        // Results should be identical regardless of concurrency limit
        XCTAssertEqual(result1.count, result2.count)
        XCTAssertEqual(result1[0].ll.count, result2[0].ll.count)

        for i in 0..<result1[0].ll.count {
            XCTAssertEqual(result1[0].ll[i], result2[0].ll[i], accuracy: 1e-10)
        }
        #else
        // Skip on unsupported platforms
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    // MARK: - Cache Optimization Tests

    func testCacheOptimizedTransform() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 64
        let height = 64
        var data = [Double](repeating: 0, count: width * height)

        // Create test pattern
        for y in 0..<height {
            for x in 0..<width {
                data[y * width + x] = Double(x * y % 256)
            }
        }

        let result = try dwt.forwardTransform2DCacheOptimized(
            data: data,
            width: width,
            height: height,
            levels: 3
        )

        XCTAssertEqual(result.count, 3, "Should have 3 levels")
        XCTAssertFalse(result[0].ll.isEmpty, "LL subband should not be empty")
        #else
        // Skip on unsupported platforms
        throw XCTSkip("Accelerate framework not available")
        #endif
    }

    func testCacheOptimizedVsStandardConsistency() throws {
        #if canImport(Accelerate)
        let dwt = J2KDWTAccelerated()
        let width = 32
        let height = 32
        var data = [Double](repeating: 0, count: width * height)

        // Create test pattern
        for i in 0..<data.count {
            data[i] = Double(i % 128)
        }

        // Standard transform
        let standardResult = try dwt.forwardTransform2D(
            data: data,
            width: width,
            height: height,
            levels: 2
        )

        // Cache-optimized transform
        let optimizedResult = try dwt.forwardTransform2DCacheOptimized(
            data: data,
            width: width,
            height: height,
            levels: 2
        )

        // Results should be identical (within floating point precision)
        XCTAssertEqual(standardResult.count, optimizedResult.count, "Level counts should match")

        for level in 0..<standardResult.count {
            let stdLevel = standardResult[level]
            let optLevel = optimizedResult[level]

            XCTAssertEqual(stdLevel.ll.count, optLevel.ll.count, "LL sizes should match at level \(level)")

            // Check that values are close
            for i in 0..<stdLevel.ll.count {
                XCTAssertEqual(stdLevel.ll[i], optLevel.ll[i], accuracy: 1e-10,
                             "LL values should match at level \(level), index \(i)")
            }

            for i in 0..<stdLevel.lh.count {
                XCTAssertEqual(stdLevel.lh[i], optLevel.lh[i], accuracy: 1e-10,
                             "LH values should match at level \(level), index \(i)")
            }
        }
        #else
        // Skip on unsupported platforms
        throw XCTSkip("Accelerate framework not available")
        #endif
    }
}
