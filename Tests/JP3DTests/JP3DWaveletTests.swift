/// Tests for JP3D 3D wavelet transform (Week 214-217).
///
/// Validates forward/inverse round-trips, boundary modes, edge dimensions,
/// multi-level decomposition, filter types, non-power-of-2 inputs, and errors.

import XCTest
@testable import J2KCore
@testable import J2K3D

final class JP3DWaveletTests: XCTestCase {

    // MARK: - Helpers

    /// Generates a deterministic test volume with a simple spatial gradient.
    private func makeTestData(width: Int, height: Int, depth: Int) -> [Float] {
        var data = [Float](repeating: 0, count: width * height * depth)
        for z in 0..<depth {
            for y in 0..<height {
                for x in 0..<width {
                    let idx = z * width * height + y * width + x
                    data[idx] = Float(x + y * 2 + z * 3) * 0.5 + 1.0
                }
            }
        }
        return data
    }

    /// Returns the maximum absolute difference between two equal-length arrays.
    private func maxError(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return Float.infinity }
        return zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }

    // MARK: - 1. Basic Forward/Inverse Round-Trip (Reversible 5/3)

    func testRoundTrip4x4x1Lossless() async throws {
        // Arrange
        let data = makeTestData(width: 4, height: 4, depth: 1)
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act
        let decomp = try await transform.forward(data: data, width: 4, height: 4, depth: 1)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testRoundTrip8x8x4Lossless() async throws {
        // Arrange
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testRoundTrip16x16x8TwoLevels() async throws {
        // Arrange
        let data = makeTestData(width: 16, height: 16, depth: 8)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 16, height: 16, depth: 8)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    // MARK: - 2. Separable vs Full 3D Equivalence

    func testSeparableAndFull3DRoundTripEquivalence() async throws {
        // Arrange
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let sepConfig = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let fullConfig = JP3DTransformConfiguration(
            filter: .reversible53, mode: .full3D, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 1)

        let sepTransform = JP3DWaveletTransform(configuration: sepConfig)
        let fullTransform = JP3DWaveletTransform(configuration: fullConfig)

        // Act
        let sepDecomp = try await sepTransform.forward(data: data, width: 8, height: 8, depth: 4)
        let sepResult = try await sepTransform.inverse(decomposition: sepDecomp)

        let fullDecomp = try await fullTransform.forward(data: data, width: 8, height: 8, depth: 4)
        let fullResult = try await fullTransform.inverse(decomposition: fullDecomp)

        // Assert: both modes reconstruct correctly
        XCTAssertLessThan(maxError(data, sepResult), 1e-4)
        XCTAssertLessThan(maxError(data, fullResult), 1e-4)
    }

    func testFull3DRoundTrip8x8x4() async throws {
        // Arrange
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .full3D, boundary: .symmetric,
            levelsX: 1, levelsY: 1, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    // MARK: - 3. Boundary Extension Tests

    func testSymmetricBoundaryNonPowerOf2() async throws {
        // Arrange – 5×3×2 (non-power-of-2 in every axis)
        let data = makeTestData(width: 5, height: 3, depth: 2)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 1, levelsY: 1, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 5, height: 3, depth: 2)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testPeriodicBoundaryRoundTrip() async throws {
        // Arrange
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .periodic,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testZeroPaddingBoundaryRoundTrip() async throws {
        // Arrange
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .zeroPadding,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    // MARK: - 4. Edge Dimension Tests

    func testDepth1NoZTransform() async throws {
        // Arrange – depth=1: no Z-axis transform should be applied
        let data = makeTestData(width: 8, height: 8, depth: 1)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 1)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testWidth1NoXTransform() async throws {
        // Arrange – width=1: no X-axis transform should be applied
        let data = makeTestData(width: 1, height: 8, depth: 4)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 1, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 1, height: 8, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testHeight1NoYTransform() async throws {
        // Arrange – height=1: no Y-axis transform should be applied
        let data = makeTestData(width: 8, height: 1, depth: 4)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 1, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 1, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testSingleVoxel1x1x1() async throws {
        // Arrange – trivial single-voxel volume
        let data: [Float] = [42.0]
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act
        let decomp = try await transform.forward(data: data, width: 1, height: 1, depth: 1)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, 1)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testZOnlyVolume1x1x16() async throws {
        // Arrange – only the Z axis has extent > 1
        let data = makeTestData(width: 1, height: 1, depth: 16)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 0, levelsY: 0, levelsZ: 2)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 1, height: 1, depth: 16)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    // MARK: - 5. Multi-Level Decomposition Validation

    func testMultiLevel2x2xy1z() async throws {
        // Arrange – 2 XY levels, 1 Z level on 8×8×4
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(decomp.levelsX, 2)
        XCTAssertEqual(decomp.levelsY, 2)
        XCTAssertEqual(decomp.levelsZ, 1)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testMultiLevel3x3xy2z_32x32x8() async throws {
        // Arrange – 3 XY levels, 2 Z levels on a larger volume
        let data = makeTestData(width: 32, height: 32, depth: 8)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 3, levelsY: 3, levelsZ: 2)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 32, height: 32, depth: 8)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    // MARK: - 6. 9/7 Irreversible Filter

    func testIrreversible97DefaultLossyRoundTrip() async throws {
        // Arrange
        let data = makeTestData(width: 8, height: 8, depth: 4)
        let transform = JP3DWaveletTransform(configuration: .defaultLossy)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert – lossy filter has relaxed tolerance
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-3)
    }

    func testIrreversible97CustomConfig16x16x4() async throws {
        // Arrange
        let data = makeTestData(width: 16, height: 16, depth: 4)
        let config = JP3DTransformConfiguration(
            filter: .irreversible97, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 16, height: 16, depth: 4)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-3)
    }

    // MARK: - 7. Non-Power-of-2 Dimensions

    func testNonPow2_7x5x3_oneLevel() async throws {
        // Arrange
        let data = makeTestData(width: 7, height: 5, depth: 3)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 1, levelsY: 1, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 7, height: 5, depth: 3)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testNonPow2_13x11x5() async throws {
        // Arrange
        let data = makeTestData(width: 13, height: 11, depth: 5)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 13, height: 11, depth: 5)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    // MARK: - 8. Asymmetric / Thin Volumes

    func testThinVolume64x64x1() async throws {
        // Arrange – effectively a 2D image
        let data = makeTestData(width: 64, height: 64, depth: 1)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 3, levelsY: 3, levelsZ: 0)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 64, height: 64, depth: 1)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    func testDeepVolume8x8x32() async throws {
        // Arrange – deep in Z dimension
        let data = makeTestData(width: 8, height: 8, depth: 32)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 2, levelsY: 2, levelsZ: 3)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 8, height: 8, depth: 32)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-4)
    }

    // MARK: - 9. Error Cases

    func testEmptyDataThrowsInvalidParameter() async throws {
        // Arrange
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act & Assert
        do {
            _ = try await transform.forward(data: [], width: 0, height: 0, depth: 0)
            XCTFail("Expected invalidParameter error for empty data")
        } catch J2KError.invalidParameter {
            // expected
        }
    }

    func testZeroWidthThrowsInvalidParameter() async throws {
        // Arrange
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act & Assert
        do {
            _ = try await transform.forward(
                data: [1.0, 2.0, 3.0, 4.0], width: 0, height: 4, depth: 1)
            XCTFail("Expected invalidParameter error for width=0")
        } catch J2KError.invalidParameter {
            // expected
        }
    }

    func testZeroHeightThrowsInvalidParameter() async throws {
        // Arrange
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act & Assert
        do {
            _ = try await transform.forward(
                data: [1.0, 2.0, 3.0, 4.0], width: 4, height: 0, depth: 1)
            XCTFail("Expected invalidParameter error for height=0")
        } catch J2KError.invalidParameter {
            // expected
        }
    }

    func testZeroDepthThrowsInvalidParameter() async throws {
        // Arrange
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act & Assert
        do {
            _ = try await transform.forward(
                data: [1.0, 2.0, 3.0, 4.0], width: 4, height: 1, depth: 0)
            XCTFail("Expected invalidParameter error for depth=0")
        } catch J2KError.invalidParameter {
            // expected
        }
    }

    // MARK: - 10. Coefficient Storage Validation

    func testCoefficientStorageSizeAfterForward() async throws {
        // Arrange
        let width = 8, height = 8, depth = 4
        let data = makeTestData(width: width, height: height, depth: depth)
        let transform = JP3DWaveletTransform(configuration: .defaultLossless)

        // Act
        let decomp = try await transform.forward(data: data, width: width, height: height, depth: depth)

        // Assert
        XCTAssertEqual(decomp.coefficients.data.count,
                       decomp.coefficients.width * decomp.coefficients.height * decomp.coefficients.depth)
        XCTAssertGreaterThan(decomp.coefficients.data.count, 0)
    }

    func testOriginalDimensionsStoredInDecomposition() async throws {
        // Arrange
        let width = 13, height = 7, depth = 5
        let data = makeTestData(width: width, height: height, depth: depth)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 1, levelsY: 1, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: width, height: height, depth: depth)

        // Assert
        XCTAssertEqual(decomp.originalWidth, width)
        XCTAssertEqual(decomp.originalHeight, height)
        XCTAssertEqual(decomp.originalDepth, depth)
    }

    func testDecompositionLevelsStoredCorrectly() async throws {
        // Arrange
        let data = makeTestData(width: 16, height: 16, depth: 8)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 3, levelsY: 2, levelsZ: 1)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 16, height: 16, depth: 8)

        // Assert
        XCTAssertEqual(decomp.levelsX, 3)
        XCTAssertEqual(decomp.levelsY, 2)
        XCTAssertEqual(decomp.levelsZ, 1)
    }

    // MARK: - Bonus: Zero-Level (Identity) Transform

    func testZeroLevelsIsIdentity() async throws {
        // Arrange – no transform levels means forward is a no-op
        let data = makeTestData(width: 4, height: 4, depth: 2)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 0, levelsY: 0, levelsZ: 0)
        let transform = JP3DWaveletTransform(configuration: config)

        // Act
        let decomp = try await transform.forward(data: data, width: 4, height: 4, depth: 2)
        let reconstructed = try await transform.inverse(decomposition: decomp)

        // Assert – reconstructed data must equal original exactly (no transform applied)
        XCTAssertEqual(reconstructed.count, data.count)
        XCTAssertLessThan(maxError(data, reconstructed), 1e-6)
    }

    // MARK: - Performance

    func testPerformance32x32x16() {
        // Synchronously run a forward+inverse cycle to benchmark
        let data = makeTestData(width: 32, height: 32, depth: 16)
        let config = JP3DTransformConfiguration(
            filter: .reversible53, mode: .separable, boundary: .symmetric,
            levelsX: 3, levelsY: 3, levelsZ: 2)

        measure {
            let result: Void = {
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    let transform = JP3DWaveletTransform(configuration: config)
                    let decomp = try await transform.forward(
                        data: data, width: 32, height: 32, depth: 16)
                    _ = try await transform.inverse(decomposition: decomp)
                    semaphore.signal()
                }
                semaphore.wait()
            }()
            _ = result
        }
    }
}
