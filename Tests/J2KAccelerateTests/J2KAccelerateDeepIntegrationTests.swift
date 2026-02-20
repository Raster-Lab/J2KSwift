//
// J2KAccelerateDeepIntegrationTests.swift
// J2KSwift
//
import XCTest
@testable import J2KAccelerate
@testable import J2KCore

/// Tests for deep Accelerate framework integration (Week 244-246).
final class J2KAccelerateDeepIntegrationTests: XCTestCase {
    let tolerance = 1e-6

    // MARK: - vDSP Deep Integration Availability

    /// Tests that vDSP deep integration availability can be checked.
    func testVDSPAvailability() throws {
        #if canImport(Accelerate)
        XCTAssertTrue(J2KvDSPDeepIntegration.isAvailable)
        #else
        XCTAssertFalse(J2KvDSPDeepIntegration.isAvailable)
        #endif
    }

    // MARK: - Vectorised Quantisation Tests

    #if canImport(Accelerate)

    /// Tests basic quantisation with a step size.
    func testQuantiseBasic() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let coefficients: [Double] = [10.0, 25.0, 37.0, 50.0, -15.0]

        let quantised = try vdsp.quantise(coefficients: coefficients, stepSize: 10.0)

        XCTAssertEqual(quantised.count, coefficients.count)
        XCTAssertEqual(quantised[0], 1.0, accuracy: tolerance) // 10 / 10 = 1
        XCTAssertEqual(quantised[1], 2.0, accuracy: tolerance) // 25 / 10 = 2.5 → floor = 2
        XCTAssertEqual(quantised[2], 3.0, accuracy: tolerance) // 37 / 10 = 3.7 → floor = 3
        XCTAssertEqual(quantised[3], 5.0, accuracy: tolerance) // 50 / 10 = 5
        XCTAssertEqual(quantised[4], -2.0, accuracy: tolerance) // -15 / 10 = -1.5 → floor = -2
    }

    /// Tests quantisation with invalid step size.
    func testQuantiseInvalidStepSize() throws {
        let vdsp = J2KvDSPDeepIntegration()

        XCTAssertThrowsError(try vdsp.quantise(coefficients: [1.0], stepSize: 0.0)) { error in
            guard case J2KError.invalidParameter = error else {
                XCTFail("Expected invalidParameter error")
                return
            }
        }

        XCTAssertThrowsError(try vdsp.quantise(coefficients: [1.0], stepSize: -1.0))
    }

    /// Tests quantisation with empty input.
    func testQuantiseEmpty() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let result = try vdsp.quantise(coefficients: [], stepSize: 1.0)
        XCTAssertTrue(result.isEmpty)
    }

    /// Tests dequantisation.
    func testDequantise() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let quantised: [Double] = [1.0, 2.0, 3.0, 5.0, -2.0]

        let dequantised = try vdsp.dequantise(quantised: quantised, stepSize: 10.0)

        XCTAssertEqual(dequantised[0], 10.0, accuracy: tolerance)
        XCTAssertEqual(dequantised[1], 20.0, accuracy: tolerance)
        XCTAssertEqual(dequantised[2], 30.0, accuracy: tolerance)
        XCTAssertEqual(dequantised[3], 50.0, accuracy: tolerance)
        XCTAssertEqual(dequantised[4], -20.0, accuracy: tolerance)
    }

    /// Tests dead-zone quantisation.
    func testDeadZoneQuantise() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let coefficients: [Double] = [0.5, 1.5, -0.5, -1.5, 3.0, -3.0, 0.0]

        let quantised = try vdsp.deadZoneQuantise(coefficients: coefficients, stepSize: 1.0)

        XCTAssertEqual(quantised.count, coefficients.count)
        XCTAssertEqual(quantised[0], 0.0, accuracy: tolerance) // |0.5| / 1 → floor(0.5) = 0
        XCTAssertEqual(quantised[1], 1.0, accuracy: tolerance) // |1.5| / 1 → floor(1.5) = 1, positive
        XCTAssertEqual(quantised[2], 0.0, accuracy: tolerance) // |-0.5| / 1 → floor(0.5) = 0
        XCTAssertEqual(quantised[3], -1.0, accuracy: tolerance) // |-1.5| / 1 → floor(1.5) = 1, negative
        XCTAssertEqual(quantised[4], 3.0, accuracy: tolerance)
        XCTAssertEqual(quantised[5], -3.0, accuracy: tolerance)
        XCTAssertEqual(quantised[6], 0.0, accuracy: tolerance) // 0 / 1 = 0
    }

    // MARK: - DFT Tests

    /// Tests DFT with non-power-of-2 length.
    func testDFTNonPowerOf2() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let signal: [Double] = [1.0, 2.0, 3.0] // Length 3

        let spectrum = try vdsp.dft(signal: signal)

        // DFT of 3-point signal produces 3 complex values = 6 doubles
        XCTAssertEqual(spectrum.count, 6)

        // DC component (k=0): sum of all inputs = 6
        XCTAssertEqual(spectrum[0], 6.0, accuracy: tolerance) // Real part of X[0]
        XCTAssertEqual(spectrum[1], 0.0, accuracy: tolerance) // Imag part of X[0]
    }

    /// Tests DFT/IDFT round-trip for non-power-of-2.
    func testDFTIDFTRoundTrip() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0, 5.0]

        let spectrum = try vdsp.dft(signal: signal)
        let reconstructed = try vdsp.idft(spectrum: spectrum)

        XCTAssertEqual(reconstructed.count, signal.count)
        for i in 0..<signal.count {
            XCTAssertEqual(reconstructed[i], signal[i], accuracy: 1e-10)
        }
    }

    /// Tests DFT with empty input.
    func testDFTEmpty() throws {
        let vdsp = J2KvDSPDeepIntegration()
        XCTAssertThrowsError(try vdsp.dft(signal: []))
    }

    /// Tests IDFT with odd-length spectrum.
    func testIDFTInvalidSpectrum() throws {
        let vdsp = J2KvDSPDeepIntegration()
        XCTAssertThrowsError(try vdsp.idft(spectrum: [1.0, 2.0, 3.0])) // Odd length
    }

    // MARK: - In-Place Operation Tests

    /// Tests in-place scalar multiplication.
    func testScalarMultiplyInPlace() throws {
        let vdsp = J2KvDSPDeepIntegration()
        var data: [Double] = [1.0, 2.0, 3.0, 4.0]

        vdsp.scalarMultiplyInPlace(&data, scalar: 2.5)

        XCTAssertEqual(data[0], 2.5, accuracy: tolerance)
        XCTAssertEqual(data[1], 5.0, accuracy: tolerance)
        XCTAssertEqual(data[2], 7.5, accuracy: tolerance)
        XCTAssertEqual(data[3], 10.0, accuracy: tolerance)
    }

    /// Tests in-place scalar division.
    func testScalarDivideInPlace() throws {
        let vdsp = J2KvDSPDeepIntegration()
        var data: [Double] = [10.0, 20.0, 30.0, 40.0]

        try vdsp.scalarDivideInPlace(&data, scalar: 5.0)

        XCTAssertEqual(data[0], 2.0, accuracy: tolerance)
        XCTAssertEqual(data[1], 4.0, accuracy: tolerance)
        XCTAssertEqual(data[2], 6.0, accuracy: tolerance)
        XCTAssertEqual(data[3], 8.0, accuracy: tolerance)
    }

    /// Tests in-place scalar division by zero.
    func testScalarDivideByZero() throws {
        let vdsp = J2KvDSPDeepIntegration()
        var data: [Double] = [1.0, 2.0]

        XCTAssertThrowsError(try vdsp.scalarDivideInPlace(&data, scalar: 0.0))
    }

    /// Tests in-place vector addition.
    func testVectorAddInPlace() throws {
        let vdsp = J2KvDSPDeepIntegration()
        var data: [Double] = [1.0, 2.0, 3.0]
        let addend: [Double] = [10.0, 20.0, 30.0]

        try vdsp.vectorAddInPlace(&data, addend: addend)

        XCTAssertEqual(data[0], 11.0, accuracy: tolerance)
        XCTAssertEqual(data[1], 22.0, accuracy: tolerance)
        XCTAssertEqual(data[2], 33.0, accuracy: tolerance)
    }

    /// Tests in-place vector addition with mismatched lengths.
    func testVectorAddInPlaceMismatch() throws {
        let vdsp = J2KvDSPDeepIntegration()
        var data: [Double] = [1.0, 2.0]
        let addend: [Double] = [10.0]

        XCTAssertThrowsError(try vdsp.vectorAddInPlace(&data, addend: addend))
    }

    // MARK: - Wavelet Convolution Tests

    /// Tests wavelet convolution with full mode.
    func testWaveletConvolveFull() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0]
        let kernel: [Double] = [0.5, 1.0, 0.5]

        let result = try vdsp.waveletConvolve(signal: signal, kernel: kernel, mode: .full)

        XCTAssertEqual(result.count, signal.count + kernel.count - 1)
        XCTAssertFalse(result.allSatisfy { $0 == 0.0 })
    }

    /// Tests wavelet convolution with same mode.
    func testWaveletConvolveSame() throws {
        let vdsp = J2KvDSPDeepIntegration()
        let signal: [Double] = [1.0, 2.0, 3.0, 4.0]
        let kernel: [Double] = [0.5, 1.0, 0.5]

        let result = try vdsp.waveletConvolve(signal: signal, kernel: kernel, mode: .same)

        XCTAssertEqual(result.count, signal.count)
    }

    /// Tests wavelet convolution with empty inputs.
    func testWaveletConvolveEmpty() throws {
        let vdsp = J2KvDSPDeepIntegration()
        XCTAssertThrowsError(try vdsp.waveletConvolve(signal: [], kernel: [1.0]))
        XCTAssertThrowsError(try vdsp.waveletConvolve(signal: [1.0], kernel: []))
    }

    // MARK: - vImage Deep Integration Tests

    /// Tests vImage deep integration availability.
    func testVImageDeepAvailability() throws {
        #if canImport(Accelerate)
        XCTAssertTrue(J2KvImageDeepIntegration.isAvailable)
        #else
        XCTAssertFalse(J2KvImageDeepIntegration.isAvailable)
        #endif
    }

    /// Tests 16-bit to float conversion.
    func testConvert16BitToFloat() throws {
        let vimage = J2KvImageDeepIntegration()
        let data: [UInt16] = [0, 32767, 65535, 16384]

        let floatData = try vimage.convert16BitToFloat(data: data, width: 2, height: 2)

        XCTAssertEqual(floatData.count, 4)
        XCTAssertEqual(floatData[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(floatData[1], 0.5, accuracy: 0.001) // 32767/65535 ≈ 0.4999
        XCTAssertEqual(floatData[2], 1.0, accuracy: 0.001)
        XCTAssertEqual(floatData[3], 0.25, accuracy: 0.001) // 16384/65535 ≈ 0.25
    }

    /// Tests float to 16-bit conversion.
    func testConvertFloatTo16Bit() throws {
        let vimage = J2KvImageDeepIntegration()
        let data: [Float] = [0.0, 0.5, 1.0, 0.25]

        let uint16Data = try vimage.convertFloatTo16Bit(data: data, width: 2, height: 2)

        XCTAssertEqual(uint16Data.count, 4)
        XCTAssertEqual(uint16Data[0], 0)
        XCTAssertEqual(Int(uint16Data[1]), 32767, accuracy: 1) // 0.5 * 65535 ≈ 32767
        XCTAssertEqual(uint16Data[2], 65535)
        XCTAssertEqual(Int(uint16Data[3]), 16383, accuracy: 1) // 0.25 * 65535 ≈ 16383
    }

    /// Tests 16-bit round-trip conversion.
    func testConvert16BitRoundTrip() throws {
        let vimage = J2KvImageDeepIntegration()
        let original: [UInt16] = [0, 100, 1000, 10000, 32768, 65535]

        let floatData = try vimage.convert16BitToFloat(data: original, width: 6, height: 1)
        let reconstructed = try vimage.convertFloatTo16Bit(data: floatData, width: 6, height: 1)

        for i in 0..<original.count {
            XCTAssertEqual(
                Int(reconstructed[i]),
                Int(original[i]),
                accuracy: 1,
                "Mismatch at index \(i): \(reconstructed[i]) vs \(original[i])"
            )
        }
    }

    /// Tests 16-bit conversion with invalid dimensions.
    func testConvert16BitInvalidDimensions() throws {
        let vimage = J2KvImageDeepIntegration()
        let data: [UInt16] = [0, 1, 2]

        XCTAssertThrowsError(try vimage.convert16BitToFloat(data: data, width: 2, height: 2))
    }

    // MARK: - Tiled Processing Tests

    /// Tests splitting an image into tiles.
    func testSplitIntoTiles() throws {
        let vimage = J2KvImageDeepIntegration()
        let width = 8
        let height = 8
        let data = [UInt8](repeating: 128, count: width * height)

        let tiles = try vimage.splitIntoTiles(data: data, width: width, height: height, tileSize: 4)

        XCTAssertEqual(tiles.count, 4) // 2×2 tiles
        for tile in tiles {
            XCTAssertEqual(tile.width, 4)
            XCTAssertEqual(tile.height, 4)
            XCTAssertEqual(tile.data.count, 16)
        }
    }

    /// Tests splitting with non-even tile boundaries.
    func testSplitIntoTilesNonEven() throws {
        let vimage = J2KvImageDeepIntegration()
        let width = 5
        let height = 5
        let data = [UInt8](repeating: 128, count: width * height)

        let tiles = try vimage.splitIntoTiles(data: data, width: width, height: height, tileSize: 3)

        // 5/3 = 2 tiles per dimension
        XCTAssertEqual(tiles.count, 4)

        // First tile should be 3×3
        XCTAssertEqual(tiles[0].width, 3)
        XCTAssertEqual(tiles[0].height, 3)

        // Edge tiles should be 2×3 or 3×2 or 2×2
        XCTAssertEqual(tiles[1].width, 2) // Right edge
        XCTAssertEqual(tiles[1].height, 3)
    }

    /// Tests tile split and reassemble round-trip.
    func testTileSplitAssembleRoundTrip() throws {
        let vimage = J2KvImageDeepIntegration()
        let width = 6
        let height = 6
        var data = [UInt8](repeating: 0, count: width * height)

        // Fill with distinct values
        for i in 0..<data.count {
            data[i] = UInt8(i % 256)
        }

        let tiles = try vimage.splitIntoTiles(data: data, width: width, height: height, tileSize: 4)
        let reassembled = try vimage.assembleTiles(tiles: tiles, width: width, height: height)

        XCTAssertEqual(reassembled, data)
    }

    /// Tests tile split with invalid parameters.
    func testSplitIntoTilesInvalid() throws {
        let vimage = J2KvImageDeepIntegration()

        XCTAssertThrowsError(try vimage.splitIntoTiles(
            data: [0], width: 1, height: 1, tileSize: 0
        ))
        XCTAssertThrowsError(try vimage.splitIntoTiles(
            data: [0, 1], width: 2, height: 2, tileSize: 1
        ))
    }

    // MARK: - BLAS/LAPACK Deep Integration Tests

    /// Tests BLAS/LAPACK deep integration availability.
    func testBLASAvailability() throws {
        #if canImport(Accelerate)
        XCTAssertTrue(J2KBLASDeepIntegration.isAvailable)
        #else
        XCTAssertFalse(J2KBLASDeepIntegration.isAvailable)
        #endif
    }

    /// Tests eigenvalue decomposition of a diagonal matrix.
    func testEigenDecompositionDiagonal() throws {
        let blas = J2KBLASDeepIntegration()

        // Diagonal matrix: eigenvalues are the diagonal elements
        let matrix: [Double] = [
            3.0, 0.0, 0.0,
            0.0, 1.0, 0.0,
            0.0, 0.0, 2.0
        ]

        let (eigenvalues, eigenvectors) = try blas.eigenDecomposition(matrix: matrix, n: 3)

        XCTAssertEqual(eigenvalues.count, 3)
        XCTAssertEqual(eigenvectors.count, 9)

        // Eigenvalues should be sorted ascending: 1, 2, 3
        XCTAssertEqual(eigenvalues[0], 1.0, accuracy: tolerance)
        XCTAssertEqual(eigenvalues[1], 2.0, accuracy: tolerance)
        XCTAssertEqual(eigenvalues[2], 3.0, accuracy: tolerance)
    }

    /// Tests eigenvalue decomposition of a symmetric matrix.
    func testEigenDecompositionSymmetric() throws {
        let blas = J2KBLASDeepIntegration()

        // Symmetric 2×2 matrix
        let matrix: [Double] = [
            2.0, 1.0,
            1.0, 2.0
        ]

        let (eigenvalues, _) = try blas.eigenDecomposition(matrix: matrix, n: 2)

        // Eigenvalues of [[2,1],[1,2]] are 1 and 3
        XCTAssertEqual(eigenvalues[0], 1.0, accuracy: tolerance)
        XCTAssertEqual(eigenvalues[1], 3.0, accuracy: tolerance)
    }

    /// Tests eigenvalue decomposition with invalid dimensions.
    func testEigenDecompositionInvalid() throws {
        let blas = J2KBLASDeepIntegration()

        XCTAssertThrowsError(try blas.eigenDecomposition(matrix: [1.0, 2.0, 3.0], n: 2))
        XCTAssertThrowsError(try blas.eigenDecomposition(matrix: [], n: 0))
    }

    // MARK: - Batch Matrix Operations Tests

    /// Tests batch matrix multiplication.
    func testBatchMatrixMultiply() throws {
        let blas = J2KBLASDeepIntegration()

        let matrices: [[Double]] = [
            [1.0, 0.0, 0.0, 1.0], // Identity
            [2.0, 0.0, 0.0, 2.0], // Scale by 2
        ]

        let transform: [Double] = [3.0, 0.0, 0.0, 3.0] // Scale by 3

        let results = try blas.batchMatrixMultiply(
            matrices: matrices, transform: transform, m: 2, n: 2, k: 2
        )

        XCTAssertEqual(results.count, 2)

        // Identity × Scale3 = Scale3
        XCTAssertEqual(results[0][0], 3.0, accuracy: tolerance)
        XCTAssertEqual(results[0][3], 3.0, accuracy: tolerance)

        // Scale2 × Scale3 = Scale6
        XCTAssertEqual(results[1][0], 6.0, accuracy: tolerance)
        XCTAssertEqual(results[1][3], 6.0, accuracy: tolerance)
    }

    /// Tests batch matrix multiply with empty input.
    func testBatchMatrixMultiplyEmpty() throws {
        let blas = J2KBLASDeepIntegration()
        let results = try blas.batchMatrixMultiply(
            matrices: [], transform: [1.0], m: 1, n: 1, k: 1
        )
        XCTAssertTrue(results.isEmpty)
    }

    /// Tests batch matrix multiply with invalid dimensions.
    func testBatchMatrixMultiplyInvalid() throws {
        let blas = J2KBLASDeepIntegration()

        XCTAssertThrowsError(try blas.batchMatrixMultiply(
            matrices: [[1.0, 2.0]], transform: [1.0], m: 2, n: 1, k: 1
        ))
    }

    // MARK: - Covariance Matrix Tests

    /// Tests covariance matrix computation.
    func testCovarianceMatrix() throws {
        let blas = J2KBLASDeepIntegration()

        // Two perfectly correlated components
        let components: [[Double]] = [
            [1.0, 2.0, 3.0, 4.0, 5.0],
            [2.0, 4.0, 6.0, 8.0, 10.0]
        ]

        let cov = try blas.covarianceMatrix(components: components)

        XCTAssertEqual(cov.count, 4) // 2×2

        // Variance of [1,2,3,4,5] = 2.5
        XCTAssertEqual(cov[0], 2.5, accuracy: tolerance)

        // Variance of [2,4,6,8,10] = 10.0
        XCTAssertEqual(cov[3], 10.0, accuracy: tolerance)

        // Covariance should be positive (perfectly correlated)
        XCTAssertEqual(cov[1], 5.0, accuracy: tolerance) // cov(x, 2x) = 2*var(x) = 5
        XCTAssertEqual(cov[2], 5.0, accuracy: tolerance) // Symmetric
    }

    /// Tests covariance matrix with invalid inputs.
    func testCovarianceMatrixInvalid() throws {
        let blas = J2KBLASDeepIntegration()

        XCTAssertThrowsError(try blas.covarianceMatrix(components: []))
        XCTAssertThrowsError(try blas.covarianceMatrix(components: [[1.0]])) // Need 2+ samples
    }

    // MARK: - Memory Optimisation Tests

    /// Tests cache-aligned allocation.
    func testAllocateAligned() throws {
        let mem = J2KMemoryOptimisation()
        let buffer = try mem.allocateAligned(count: 1024, alignment: 128)

        XCTAssertEqual(buffer.count, 1024)
        XCTAssertTrue(buffer.allSatisfy { $0 == 0.0 })
    }

    /// Tests aligned allocation with invalid parameters.
    func testAllocateAlignedInvalid() throws {
        let mem = J2KMemoryOptimisation()

        XCTAssertThrowsError(try mem.allocateAligned(count: 0))
        XCTAssertThrowsError(try mem.allocateAligned(count: 1, alignment: 3)) // Not power of 2
    }

    /// Tests M-series cache line size constant.
    func testMSeriesCacheLineSize() throws {
        XCTAssertEqual(J2KMemoryOptimisation.mSeriesCacheLineSize, 128)
    }

    // MARK: - Copy-on-Write Buffer Tests

    /// Tests COW buffer creation and read access.
    func testCOWBufferCreation() throws {
        let buffer = J2KCOWBuffer(data: [1.0, 2.0, 3.0])

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer[0], 1.0)
        XCTAssertEqual(buffer[1], 2.0)
        XCTAssertEqual(buffer[2], 3.0)
        XCTAssertEqual(buffer.data, [1.0, 2.0, 3.0])
    }

    /// Tests COW buffer copy-on-write semantics.
    func testCOWBufferCopyOnWrite() throws {
        var original = J2KCOWBuffer(data: [1.0, 2.0, 3.0])
        var copy = original

        // Modify copy - should trigger copy
        copy.modify { $0[0] = 99.0 }

        // Original should be unchanged
        XCTAssertEqual(original[0], 1.0)
        // Copy should be modified
        XCTAssertEqual(copy[0], 99.0)

        // Modify original
        original.modify { $0[2] = 42.0 }
        XCTAssertEqual(original[2], 42.0)
        XCTAssertEqual(copy[2], 3.0)
    }

    /// Tests COW buffer unique reference modification (no copy needed).
    func testCOWBufferUniqueModification() throws {
        var buffer = J2KCOWBuffer(data: [1.0, 2.0, 3.0])

        // Modify unique buffer - should not trigger copy
        buffer.modify { $0[0] = 99.0 }

        XCTAssertEqual(buffer[0], 99.0)
        XCTAssertEqual(buffer.count, 3)
    }

    #endif

    // MARK: - 16-Bit Scaling Tests

    #if canImport(Accelerate)

    /// Tests 16-bit image scaling.
    func testScale16Bit() throws {
        let vimage = J2KvImageDeepIntegration()
        let width = 4
        let height = 4
        let data = [UInt16](repeating: 32768, count: width * height)

        let scaled = try vimage.scale16Bit(
            data: data,
            fromSize: (width: width, height: height),
            toSize: (width: 2, height: 2)
        )

        XCTAssertEqual(scaled.count, 4)
        // Uniform input should produce uniform output
        for value in scaled {
            XCTAssertEqual(Int(value), 32768, accuracy: 2)
        }
    }

    /// Tests 16-bit scaling with invalid dimensions.
    func testScale16BitInvalid() throws {
        let vimage = J2KvImageDeepIntegration()

        XCTAssertThrowsError(try vimage.scale16Bit(
            data: [0, 1, 2],
            fromSize: (width: 2, height: 2),
            toSize: (width: 1, height: 1)
        ))
    }

    #endif
}
