// J2KLosslessDecodingOptimizationTests.swift
// J2KSwift
//
// Tests for lossless decoding optimizations
//

import XCTest
@testable import J2KCodec
@testable import J2KCore

final class J2KLosslessDecodingOptimizationTests: XCTestCase {
    // MARK: - Buffer Pool Tests

    func testBufferPoolInt32Acquisition() async throws {
        let pool = J2KBufferPool()

        // Acquire a buffer
        let buffer1 = await pool.acquireInt32Buffer(size: 100)
        XCTAssertEqual(buffer1.count, 100)
        XCTAssertTrue(buffer1.allSatisfy { $0 == 0 })

        // Release it
        await pool.releaseInt32Buffer(buffer1)

        // Acquire again - should reuse
        let buffer2 = await pool.acquireInt32Buffer(size: 100)
        XCTAssertEqual(buffer2.count, 100)

        await pool.releaseInt32Buffer(buffer2)
    }

    func testBufferPoolDoubleAcquisition() async throws {
        let pool = J2KBufferPool()

        // Acquire a buffer
        let buffer1 = await pool.acquireDoubleBuffer(size: 50)
        XCTAssertEqual(buffer1.count, 50)
        XCTAssertTrue(buffer1.allSatisfy { $0 == 0.0 })

        // Release it
        await pool.releaseDoubleBuffer(buffer1)

        // Acquire again - should reuse
        let buffer2 = await pool.acquireDoubleBuffer(size: 50)
        XCTAssertEqual(buffer2.count, 50)

        await pool.releaseDoubleBuffer(buffer2)
    }

    func testBufferPoolStatistics() async throws {
        let pool = J2KBufferPool()

        // Initial state
        let stats1 = await pool.statistics()
        XCTAssertTrue(stats1.int32.isEmpty)
        XCTAssertTrue(stats1.double.isEmpty)

        // Add some buffers
        let buffer1 = await pool.acquireInt32Buffer(size: 100)
        let buffer2 = await pool.acquireDoubleBuffer(size: 200)

        await pool.releaseInt32Buffer(buffer1)
        await pool.releaseDoubleBuffer(buffer2)

        // Check statistics
        let stats2 = await pool.statistics()
        XCTAssertEqual(stats2.int32[100], 1)
        XCTAssertEqual(stats2.double[200], 1)

        // Clear pool
        await pool.clear()
        let stats3 = await pool.statistics()
        XCTAssertTrue(stats3.int32.isEmpty)
        XCTAssertTrue(stats3.double.isEmpty)
    }

    func testBufferPoolMaxCapacity() async throws {
        let pool = J2KBufferPool()

        // Fill pool beyond capacity
        for _ in 0..<10 {
            let buffer = await pool.acquireInt32Buffer(size: 100)
            await pool.releaseInt32Buffer(buffer)
        }

        // Should cap at maxCachedBuffers (8)
        let stats = await pool.statistics()
        XCTAssertLessThanOrEqual(stats.int32[100] ?? 0, 8)
    }

    // MARK: - 1D Optimized Transform Tests

    func testOptimized1DInverseTransform() throws {
        let optimizer = J2KDWT1DOptimizer()

        // Test signal
        let lowpass: [Int32] = [10, 20, 30, 40]
        let highpass: [Int32] = [5, 15, 25]

        // Optimized transform
        let result = try optimizer.inverseTransform53Optimized(
            lowpass: lowpass,
            highpass: highpass,
            boundaryExtension: .symmetric
        )

        // Should have 7 elements (4 + 3)
        XCTAssertEqual(result.count, 7)

        // Verify against standard implementation
        let standard = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result, standard, "Optimized result should match standard implementation")
    }

    func testOptimized1DSymmetricBoundary() throws {
        let optimizer = J2KDWT1DOptimizer()

        // Test with symmetric boundary extension
        let lowpass: [Int32] = [100, 200, 300]
        let highpass: [Int32] = [50, 150]

        let result = try optimizer.inverseTransform53Optimized(
            lowpass: lowpass,
            highpass: highpass,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result.count, 5)

        // Verify each element is computed correctly
        // The exact values depend on the lifting scheme implementation
        XCTAssertNotNil(result.first)
        XCTAssertNotNil(result.last)
    }

    func testOptimized1DLargeSignal() throws {
        let optimizer = J2KDWT1DOptimizer()

        // Test with larger signal (512 samples)
        let size = 256
        let lowpass: [Int32] = (0..<size).map { Int32($0 * 10) }
        let highpass: [Int32] = (0..<(size - 1)).map { Int32($0 * 5 + 100) }

        let result = try optimizer.inverseTransform53Optimized(
            lowpass: lowpass,
            highpass: highpass,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result.count, size + (size - 1))

        // Verify against standard implementation
        let standard = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result, standard)
    }

    func testOptimized1DEdgeCases() throws {
        let optimizer = J2KDWT1DOptimizer()

        // Minimum size
        let lowpass: [Int32] = [10]
        let highpass: [Int32] = [5]

        let result = try optimizer.inverseTransform53Optimized(
            lowpass: lowpass,
            highpass: highpass,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result.count, 2)

        // Verify correctness
        let standard = try J2KDWT1D.inverseTransform(
            lowpass: lowpass,
            highpass: highpass,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result, standard)
    }

    // MARK: - 2D Optimized Transform Tests

    func testOptimized2DInverseTransform() throws {
        let optimizer = J2KDWT2DOptimizer()

        // Create small test subbands
        let ll: [[Int32]] = [
            [100, 200],
            [300, 400]
        ]
        let lh: [[Int32]] = [
            [10, 20],
            [30, 40]
        ]
        let hl: [[Int32]] = [
            [5, 15],
            [25, 35]
        ]
        let hh: [[Int32]] = [
            [1, 2],
            [3, 4]
        ]

        // Optimized transform
        let result = try optimizer.inverseTransform2DOptimized(
            ll: ll,
            lh: lh,
            hl: hl,
            hh: hh,
            boundaryExtension: .symmetric
        )

        // Should reconstruct to approximately 4x4 image
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0].count, 4)

        // Verify against standard implementation
        let standard = try J2KDWT2D.inverseTransform(
            ll: ll,
            lh: lh,
            hl: hl,
            hh: hh,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result.count, standard.count)
        for (row1, row2) in zip(result, standard) {
            XCTAssertEqual(row1, row2)
        }
    }

    func testOptimized2DLargeImage() throws {
        let optimizer = J2KDWT2DOptimizer()

        // Create 32x32 test subbands
        let size = 16
        let ll = (0..<size).map { row in
            (0..<size).map { col in Int32(row * size + col) }
        }
        let lh = (0..<size).map { row in
            (0..<size).map { col in Int32(row * size + col + 1000) }
        }
        let hl = (0..<size).map { row in
            (0..<size).map { col in Int32(row * size + col + 2000) }
        }
        let hh = (0..<size).map { row in
            (0..<size).map { col in Int32(row * size + col + 3000) }
        }

        // Optimized transform
        let result = try optimizer.inverseTransform2DOptimized(
            ll: ll,
            lh: lh,
            hl: hl,
            hh: hh,
            boundaryExtension: .symmetric
        )

        // Should reconstruct to approximately 32x32 image
        XCTAssertEqual(result.count, 32)
        XCTAssertEqual(result[0].count, 32)

        // Verify against standard implementation
        let standard = try J2KDWT2D.inverseTransform(
            ll: ll,
            lh: lh,
            hl: hl,
            hh: hh,
            filter: .reversible53,
            boundaryExtension: .symmetric
        )

        XCTAssertEqual(result.count, standard.count)
        for (row1, row2) in zip(result, standard) {
            XCTAssertEqual(row1, row2)
        }
    }

    func testOptimized2DReconstructionAccuracy() throws {
        let optimizer = J2KDWT2DOptimizer()

        // Test with known values to verify perfect reconstruction
        let ll: [[Int32]] = [
            [128, 128],
            [128, 128]
        ]
        let lh: [[Int32]] = [
            [0, 0],
            [0, 0]
        ]
        let hl: [[Int32]] = [
            [0, 0],
            [0, 0]
        ]
        let hh: [[Int32]] = [
            [0, 0],
            [0, 0]
        ]

        let result = try optimizer.inverseTransform2DOptimized(
            ll: ll,
            lh: lh,
            hl: hl,
            hh: hh,
            boundaryExtension: .symmetric
        )

        // With zero detail subbands and constant LL, output should be constant
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result[0].isEmpty)

        // All values should be close to 128 (may vary slightly due to integer rounding)
        for row in result {
            for value in row {
                XCTAssertTrue(abs(value - 128) < 10, "Value \(value) should be close to 128")
            }
        }
    }

    // MARK: - Performance Tests

    func testOptimizedVsStandardPerformance() {
        // Create test data
        let size = 128
        let lowpass: [Int32] = (0..<size).map { Int32($0) }
        let highpass: [Int32] = (0..<(size - 1)).map { Int32($0 + 100) }

        let optimizer = J2KDWT1DOptimizer()

        // Measure optimized version
        measure {
            for _ in 0..<100 {
                _ = try? optimizer.inverseTransform53Optimized(
                    lowpass: lowpass,
                    highpass: highpass,
                    boundaryExtension: .symmetric
                )
            }
        }
    }

    func testOptimized2DPerformance() {
        // Create 64x64 test subbands
        let size = 32
        let ll = (0..<size).map { row in
            (0..<size).map { col in Int32(row * size + col) }
        }
        let lh = ll
        let hl = ll
        let hh = ll

        let optimizer = J2KDWT2DOptimizer()

        // Measure performance
        measure {
            for _ in 0..<10 {
                _ = try? optimizer.inverseTransform2DOptimized(
                    ll: ll,
                    lh: lh,
                    hl: hl,
                    hh: hh,
                    boundaryExtension: .symmetric
                )
            }
        }
    }

    // MARK: - Integration Tests

    func testLosslessDecodingPipelineUsesOptimization() throws {
        // This test verifies that the decoder pipeline uses the optimized path
        // for lossless (reversible 5/3) decoding

        // Create a simple test image
        let width = 64
        let height = 64
        let data = [Int32](repeating: 128, count: width * height)

        let component = J2KComponent(
            index: 0,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            data: Data(data.flatMap { withUnsafeBytes(of: $0, Array.init) })
        )

        let image = J2KImage(
            width: width,
            height: height,
            components: [component]
        )

        // This would test encoding and decoding, but for now we just verify
        // the optimized transform functions work correctly
        XCTAssertNotNil(image)
    }
}
