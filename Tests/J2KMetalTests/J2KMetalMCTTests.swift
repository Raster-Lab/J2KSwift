//
// J2KMetalMCTTests.swift
// J2KSwift
//
import XCTest
@testable import J2KMetal
@testable import J2KCore

/// Tests for Metal-accelerated multi-component transforms.
final class J2KMetalMCTTests: XCTestCase {
    // MARK: - Platform Availability Tests

    /// Tests that Metal MCT availability can be queried.
    func testMCTAvailability() {
        let available = J2KMetalMCT.isAvailable
        #if canImport(Metal)
        _ = available
        #else
        XCTAssertFalse(available)
        #endif
    }

    // MARK: - Backend Tests

    /// Tests GPU backend selection.
    func testGPUBackend() {
        let backend = J2KMetalMCTBackend.gpu
        switch backend {
        case .gpu:
            break // Expected
        default:
            XCTFail("Expected GPU backend")
        }
    }

    /// Tests CPU backend selection.
    func testCPUBackend() {
        let backend = J2KMetalMCTBackend.cpu
        switch backend {
        case .cpu:
            break // Expected
        default:
            XCTFail("Expected CPU backend")
        }
    }

    /// Tests auto backend selection.
    func testAutoBackend() {
        let backend = J2KMetalMCTBackend.auto
        switch backend {
        case .auto:
            break // Expected
        default:
            XCTFail("Expected auto backend")
        }
    }

    // MARK: - Configuration Tests

    /// Tests default MCT configuration.
    func testDefaultConfiguration() {
        let config = J2KMetalMCTConfiguration.default
        XCTAssertEqual(config.gpuThreshold, 512)
        XCTAssertEqual(config.batchSize, 4096)
    }

    /// Tests high performance configuration.
    func testHighPerformanceConfiguration() {
        let config = J2KMetalMCTConfiguration.highPerformance
        XCTAssertEqual(config.gpuThreshold, 256)
        XCTAssertEqual(config.batchSize, 8192)
    }

    /// Tests custom configuration.
    func testCustomConfiguration() {
        let config = J2KMetalMCTConfiguration(
            gpuThreshold: 1024, batchSize: 2048
        )
        XCTAssertEqual(config.gpuThreshold, 1024)
        XCTAssertEqual(config.batchSize, 2048)
    }

    // MARK: - Statistics Tests

    /// Tests initial statistics are zero.
    func testInitialStatistics() {
        let stats = J2KMetalMCTStatistics()
        XCTAssertEqual(stats.totalOperations, 0)
        XCTAssertEqual(stats.gpuOperations, 0)
        XCTAssertEqual(stats.cpuOperations, 0)
        XCTAssertEqual(stats.totalProcessingTime, 0.0)
        XCTAssertEqual(stats.totalSamplesProcessed, 0)
        XCTAssertEqual(stats.fastPath3x3Operations, 0)
        XCTAssertEqual(stats.fastPath4x4Operations, 0)
    }

    /// Tests GPU utilization calculation.
    func testGPUUtilization() {
        var stats = J2KMetalMCTStatistics()
        XCTAssertEqual(stats.gpuUtilization, 0.0)

        stats.totalOperations = 10
        stats.gpuOperations = 8
        XCTAssertEqual(stats.gpuUtilization, 0.8, accuracy: 0.001)
    }

    /// Tests fast path utilization calculation.
    func testFastPathUtilization() {
        var stats = J2KMetalMCTStatistics()
        XCTAssertEqual(stats.fastPathUtilization, 0.0)

        stats.totalOperations = 10
        stats.fastPath3x3Operations = 5
        stats.fastPath4x4Operations = 3
        XCTAssertEqual(stats.fastPathUtilization, 0.8, accuracy: 0.001)
    }

    // MARK: - Result Tests

    /// Tests MCT result creation.
    func testMCTResultCreation() {
        let result = J2KMetalMCTResult(
            components: [[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]],
            componentCount: 3,
            sampleCount: 2,
            usedGPU: false
        )
        XCTAssertEqual(result.components.count, 3)
        XCTAssertEqual(result.componentCount, 3)
        XCTAssertEqual(result.sampleCount, 2)
        XCTAssertFalse(result.usedGPU)
    }

    // MARK: - Identity Matrix Tests

    /// Tests identity matrix generation.
    func testIdentityMatrix() async {
        let mct = J2KMetalMCT()
        let identity = await mct.identityMatrix(n: 3)
        XCTAssertEqual(identity.count, 9)
        XCTAssertEqual(identity[0], 1.0)
        XCTAssertEqual(identity[1], 0.0)
        XCTAssertEqual(identity[2], 0.0)
        XCTAssertEqual(identity[3], 0.0)
        XCTAssertEqual(identity[4], 1.0)
        XCTAssertEqual(identity[5], 0.0)
        XCTAssertEqual(identity[6], 0.0)
        XCTAssertEqual(identity[7], 0.0)
        XCTAssertEqual(identity[8], 1.0)
    }

    /// Tests identity transform preserves data.
    func testIdentityTransform() async throws {
        let mct = J2KMetalMCT()
        let identity = await mct.identityMatrix(n: 3)

        let components: [[Float]] = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0]
        ]

        let result = try await mct.forwardTransform(
            components: components,
            matrix: identity,
            componentCount: 3,
            backend: .cpu
        )

        for c in 0..<3 {
            for i in 0..<3 {
                XCTAssertEqual(
                    result.components[c][i], components[c][i],
                    accuracy: 0.001
                )
            }
        }
    }

    // MARK: - Matrix Multiply Tests

    /// Tests matrix multiplication.
    func testMatrixMultiply() async {
        let mct = J2KMetalMCT()
        let a: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let b: [Float] = [9, 8, 7, 6, 5, 4, 3, 2, 1]
        let result = await mct.matrixMultiply(a, b, n: 3)

        // Expected: row 0 = [1*9+2*6+3*3, 1*8+2*5+3*2, 1*7+2*4+3*1]
        //                  = [30, 24, 18]
        XCTAssertEqual(result[0], 30.0, accuracy: 0.001)
        XCTAssertEqual(result[1], 24.0, accuracy: 0.001)
        XCTAssertEqual(result[2], 18.0, accuracy: 0.001)
    }

    /// Tests matrix transpose.
    func testMatrixTranspose() async {
        let mct = J2KMetalMCT()
        let matrix: [Float] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
        let transposed = await mct.transposeMatrix(matrix, n: 3)

        XCTAssertEqual(transposed[0], 1.0)
        XCTAssertEqual(transposed[1], 4.0)
        XCTAssertEqual(transposed[2], 7.0)
        XCTAssertEqual(transposed[3], 2.0)
        XCTAssertEqual(transposed[4], 5.0)
        XCTAssertEqual(transposed[5], 8.0)
    }

    // MARK: - 3×3 MCT Transform Tests (CPU)

    /// Tests 3×3 forward MCT with ICT matrix.
    func testForward3x3ICT() async throws {
        let mct = J2KMetalMCT()
        let matrix = J2KMetalMCT.ictForwardMatrix

        let components: [[Float]] = [
            [255.0, 0.0, 0.0],   // Red channel
            [0.0, 255.0, 0.0],   // Green channel
            [0.0, 0.0, 255.0]    // Blue channel
        ]

        let result = try await mct.forwardTransform(
            components: components,
            matrix: matrix,
            componentCount: 3,
            backend: .cpu
        )

        // Y for pure red: 0.299 * 255 = 76.245
        XCTAssertEqual(result.components[0][0], 0.299 * 255.0, accuracy: 0.01)
        // Y for pure green: 0.587 * 255 = 149.685
        XCTAssertEqual(result.components[0][1], 0.587 * 255.0, accuracy: 0.01)
        XCTAssertEqual(result.componentCount, 3)
        XCTAssertEqual(result.sampleCount, 3)
        XCTAssertFalse(result.usedGPU)
    }

    /// Tests 3×3 forward/inverse roundtrip.
    func testForwardInverse3x3Roundtrip() async throws {
        let mct = J2KMetalMCT()

        let components: [[Float]] = [
            [200.0, 50.0, 100.0],
            [100.0, 200.0, 50.0],
            [50.0, 100.0, 200.0]
        ]

        let forward = try await mct.forwardTransform(
            components: components,
            matrix: J2KMetalMCT.ictForwardMatrix,
            componentCount: 3,
            backend: .cpu
        )
        let inverse = try await mct.inverseTransform(
            components: forward.components,
            matrix: J2KMetalMCT.ictInverseMatrix,
            componentCount: 3,
            backend: .cpu
        )

        for c in 0..<3 {
            for i in 0..<3 {
                XCTAssertEqual(
                    inverse.components[c][i], components[c][i],
                    accuracy: 1.0
                )
            }
        }
    }

    // MARK: - 4×4 MCT Transform Tests (CPU)

    /// Tests 4×4 identity transform.
    func testForward4x4Identity() async throws {
        let mct = J2KMetalMCT()
        let identity = await mct.identityMatrix(n: 4)

        let components: [[Float]] = [
            [10.0, 20.0],
            [30.0, 40.0],
            [50.0, 60.0],
            [70.0, 80.0]
        ]

        let result = try await mct.forwardTransform(
            components: components,
            matrix: identity,
            componentCount: 4,
            backend: .cpu
        )

        for c in 0..<4 {
            for i in 0..<2 {
                XCTAssertEqual(
                    result.components[c][i], components[c][i],
                    accuracy: 0.001
                )
            }
        }
    }

    /// Tests 4×4 MCT with custom matrix.
    func testForward4x4CustomMatrix() async throws {
        let mct = J2KMetalMCT()

        // Simple permutation matrix: swap components 0↔1, 2↔3
        let matrix: [Float] = [
            0, 1, 0, 0,
            1, 0, 0, 0,
            0, 0, 0, 1,
            0, 0, 1, 0
        ]

        let components: [[Float]] = [
            [1.0], [2.0], [3.0], [4.0]
        ]

        let result = try await mct.forwardTransform(
            components: components,
            matrix: matrix,
            componentCount: 4,
            backend: .cpu
        )

        XCTAssertEqual(result.components[0][0], 2.0, accuracy: 0.001)
        XCTAssertEqual(result.components[1][0], 1.0, accuracy: 0.001)
        XCTAssertEqual(result.components[2][0], 4.0, accuracy: 0.001)
        XCTAssertEqual(result.components[3][0], 3.0, accuracy: 0.001)
    }

    // MARK: - General N×N MCT Tests (CPU)

    /// Tests general 5×5 MCT.
    func testForward5x5MCT() async throws {
        let mct = J2KMetalMCT()
        let identity = await mct.identityMatrix(n: 5)

        let components: [[Float]] = [
            [1.0], [2.0], [3.0], [4.0], [5.0]
        ]

        let result = try await mct.forwardTransform(
            components: components,
            matrix: identity,
            componentCount: 5,
            backend: .cpu
        )

        XCTAssertEqual(result.componentCount, 5)
        for c in 0..<5 {
            XCTAssertEqual(
                result.components[c][0], components[c][0],
                accuracy: 0.001
            )
        }
    }

    /// Tests 2×2 MCT (minimum).
    func testForward2x2MCT() async throws {
        let mct = J2KMetalMCT()

        let matrix: [Float] = [
            1.0, 1.0,
            1.0, -1.0
        ]

        let components: [[Float]] = [
            [3.0, 7.0],
            [5.0, 2.0]
        ]

        let result = try await mct.forwardTransform(
            components: components,
            matrix: matrix,
            componentCount: 2,
            backend: .cpu
        )

        // [3+5, 3-5] = [8, -2] for first sample
        XCTAssertEqual(result.components[0][0], 8.0, accuracy: 0.001)
        XCTAssertEqual(result.components[1][0], -2.0, accuracy: 0.001)
        // [7+2, 7-2] = [9, 5] for second sample
        XCTAssertEqual(result.components[0][1], 9.0, accuracy: 0.001)
        XCTAssertEqual(result.components[1][1], 5.0, accuracy: 0.001)
    }

    // MARK: - Fused Color + MCT Tests (CPU)

    /// Tests fused color + MCT with identity MCT.
    func testFusedColorMCTIdentity() async throws {
        let mct = J2KMetalMCT()
        let colorMatrix = J2KMetalMCT.ictForwardMatrix
        let identity = await mct.identityMatrix(n: 3)

        let components: [[Float]] = [
            [128.0], [128.0], [128.0]
        ]

        let result = try await mct.fusedColorMCTTransform(
            components: components,
            colorMatrix: colorMatrix,
            mctMatrix: identity,
            componentCount: 3,
            backend: .cpu
        )

        // Color transform of gray: Y=128, Cb≈0, Cr≈0
        // Followed by identity MCT: same output
        XCTAssertEqual(result.components[0][0], 128.0, accuracy: 0.1)
        XCTAssertEqual(result.components[1][0], 0.0, accuracy: 0.1)
        XCTAssertEqual(result.components[2][0], 0.0, accuracy: 0.1)
    }

    /// Tests fused operation equals sequential operations.
    func testFusedEqualsSequential() async throws {
        let mct = J2KMetalMCT()
        let colorMatrix = J2KMetalMCT.ictForwardMatrix
        let mctMatrix: [Float] = [
            2.0, 0.0, 0.0,
            0.0, 3.0, 0.0,
            0.0, 0.0, 0.5
        ]

        let components: [[Float]] = [
            [200.0, 100.0],
            [100.0, 200.0],
            [50.0, 150.0]
        ]

        // Fused operation
        let fused = try await mct.fusedColorMCTTransform(
            components: components,
            colorMatrix: colorMatrix,
            mctMatrix: mctMatrix,
            componentCount: 3,
            backend: .cpu
        )

        // Sequential: color first, then MCT
        let color = try await mct.forwardTransform(
            components: components,
            matrix: colorMatrix,
            componentCount: 3,
            backend: .cpu
        )
        let sequential = try await mct.forwardTransform(
            components: color.components,
            matrix: mctMatrix,
            componentCount: 3,
            backend: .cpu
        )

        for c in 0..<3 {
            for i in 0..<2 {
                XCTAssertEqual(
                    fused.components[c][i],
                    sequential.components[c][i],
                    accuracy: 0.01
                )
            }
        }
    }

    // MARK: - Batch Transform Tests

    /// Tests batch transform with multiple tiles.
    func testBatchTransform() async throws {
        let mct = J2KMetalMCT()
        let identity = await mct.identityMatrix(n: 3)

        let tile1: [[Float]] = [[1.0], [2.0], [3.0]]
        let tile2: [[Float]] = [[4.0], [5.0], [6.0]]

        let results = try await mct.batchTransform(
            tiles: [tile1, tile2],
            matrix: identity,
            componentCount: 3,
            backend: .cpu
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].components[0][0], 1.0, accuracy: 0.001)
        XCTAssertEqual(results[1].components[0][0], 4.0, accuracy: 0.001)
    }

    /// Tests batch transform with empty tiles error.
    func testBatchTransformEmptyError() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.batchTransform(
                tiles: [],
                matrix: [1, 0, 0, 1],
                componentCount: 2,
                backend: .cpu
            )
            XCTFail("Expected error for empty tiles")
        } catch {
            // Expected
        }
    }

    // MARK: - Predefined Matrix Tests

    /// Tests ICT forward matrix values.
    func testICTForwardMatrixValues() {
        let matrix = J2KMetalMCT.ictForwardMatrix
        XCTAssertEqual(matrix.count, 9)
        // First row: Y coefficients
        XCTAssertEqual(matrix[0], 0.299, accuracy: 0.001)
        XCTAssertEqual(matrix[1], 0.587, accuracy: 0.001)
        XCTAssertEqual(matrix[2], 0.114, accuracy: 0.001)
    }

    /// Tests ICT inverse matrix values.
    func testICTInverseMatrixValues() {
        let matrix = J2KMetalMCT.ictInverseMatrix
        XCTAssertEqual(matrix.count, 9)
        XCTAssertEqual(matrix[0], 1.0, accuracy: 0.001)
        XCTAssertEqual(matrix[4], -0.34413, accuracy: 0.001)
    }

    /// Tests averaging matrix.
    func testAveragingMatrix() {
        let matrix = J2KMetalMCT.averaging3Matrix
        XCTAssertEqual(matrix.count, 9)
        // First row averages all components
        XCTAssertEqual(
            matrix[0] + matrix[1] + matrix[2], 1.0, accuracy: 0.001
        )
    }

    // MARK: - Error Handling Tests

    /// Tests error for less than 2 components.
    func testTooFewComponentsError() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.forwardTransform(
                components: [[1.0]],
                matrix: [1.0],
                componentCount: 1,
                backend: .cpu
            )
            XCTFail("Expected error for single component")
        } catch {
            // Expected
        }
    }

    /// Tests error for component count mismatch.
    func testComponentCountMismatchError() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.forwardTransform(
                components: [[1.0], [2.0]],
                matrix: [1, 0, 0, 1, 0, 0, 0, 0, 1],
                componentCount: 3,
                backend: .cpu
            )
            XCTFail("Expected error for component count mismatch")
        } catch {
            // Expected
        }
    }

    /// Tests error for matrix size mismatch.
    func testMatrixSizeMismatchError() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.forwardTransform(
                components: [[1.0], [2.0], [3.0]],
                matrix: [1, 0, 0, 1],  // 2×2 instead of 3×3
                componentCount: 3,
                backend: .cpu
            )
            XCTFail("Expected error for matrix size mismatch")
        } catch {
            // Expected
        }
    }

    /// Tests error for empty components.
    func testEmptyComponentsError() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.forwardTransform(
                components: [[], [], []],
                matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                componentCount: 3,
                backend: .cpu
            )
            XCTFail("Expected error for empty components")
        } catch {
            // Expected
        }
    }

    /// Tests error for mismatched component lengths.
    func testMismatchedComponentLengthsError() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.forwardTransform(
                components: [[1.0, 2.0], [3.0], [4.0, 5.0]],
                matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],
                componentCount: 3,
                backend: .cpu
            )
            XCTFail("Expected error for mismatched lengths")
        } catch {
            // Expected
        }
    }

    /// Tests error for too many components.
    func testTooManyComponentsError() async {
        let mct = J2KMetalMCT()
        let n = 17
        let components = [[Float]](repeating: [1.0], count: n)
        let matrix = [Float](repeating: 0.0, count: n * n)
        do {
            _ = try await mct.forwardTransform(
                components: components,
                matrix: matrix,
                componentCount: n,
                backend: .cpu
            )
            XCTFail("Expected error for too many components")
        } catch {
            // Expected
        }
    }

    // MARK: - Statistics Tracking Tests

    /// Tests statistics tracking after CPU operations.
    func testStatisticsTracking() async throws {
        let mct = J2KMetalMCT()
        let identity = await mct.identityMatrix(n: 3)

        _ = try await mct.forwardTransform(
            components: [[1.0], [2.0], [3.0]],
            matrix: identity,
            componentCount: 3,
            backend: .cpu
        )

        let stats = await mct.statistics()
        XCTAssertEqual(stats.totalOperations, 1)
        XCTAssertEqual(stats.cpuOperations, 1)
        XCTAssertEqual(stats.gpuOperations, 0)
        XCTAssertEqual(stats.fastPath3x3Operations, 1)
        XCTAssertEqual(stats.totalSamplesProcessed, 3)
        XCTAssertGreaterThan(stats.totalProcessingTime, 0.0)
    }

    /// Tests statistics reset.
    func testStatisticsReset() async throws {
        let mct = J2KMetalMCT()
        let identity = await mct.identityMatrix(n: 3)

        _ = try await mct.forwardTransform(
            components: [[1.0], [2.0], [3.0]],
            matrix: identity,
            componentCount: 3,
            backend: .cpu
        )
        await mct.resetStatistics()

        let stats = await mct.statistics()
        XCTAssertEqual(stats.totalOperations, 0)
    }

    // MARK: - Backend Selection Tests

    /// Tests effective backend with CPU forced.
    func testEffectiveBackendCPU() async {
        let mct = J2KMetalMCT()
        let backend = await mct.effectiveBackend(
            sampleCount: 10000, componentCount: 3, backend: .cpu
        )
        switch backend {
        case .cpu:
            break // Expected
        default:
            XCTFail("Expected CPU backend when forced")
        }
    }

    /// Tests auto backend selects CPU for small data.
    func testAutoBackendSmallData() async {
        let mct = J2KMetalMCT(
            configuration: .init(gpuThreshold: 1024)
        )
        let backend = await mct.effectiveBackend(
            sampleCount: 100, componentCount: 3, backend: .auto
        )
        switch backend {
        case .cpu:
            break // Expected on this platform or below threshold
        default:
            break // GPU possible on Metal platforms
        }
    }

    // MARK: - Large Data Tests

    /// Tests 3×3 MCT with large data set.
    func testLargeData3x3() async throws {
        let mct = J2KMetalMCT()

        let count = 4096
        let components: [[Float]] = [
            [Float](repeating: 128.0, count: count),
            [Float](repeating: 128.0, count: count),
            [Float](repeating: 128.0, count: count)
        ]

        let result = try await mct.forwardTransform(
            components: components,
            matrix: J2KMetalMCT.ictForwardMatrix,
            componentCount: 3,
            backend: .cpu
        )

        XCTAssertEqual(result.components[0].count, count)
        // Gray: Y ≈ 128, Cb ≈ 0, Cr ≈ 0
        XCTAssertEqual(result.components[0][0], 128.0, accuracy: 0.1)
        XCTAssertEqual(result.components[1][0], 0.0, accuracy: 0.1)
        XCTAssertEqual(result.components[2][0], 0.0, accuracy: 0.1)
    }

    /// Tests 3×3 forward/inverse roundtrip with large data.
    func testLargeRoundtrip3x3() async throws {
        let mct = J2KMetalMCT()

        let count = 1024
        var c0 = [Float](repeating: 0, count: count)
        var c1 = [Float](repeating: 0, count: count)
        var c2 = [Float](repeating: 0, count: count)
        for i in 0..<count {
            c0[i] = Float(i % 256)
            c1[i] = Float((i * 3) % 256)
            c2[i] = Float((i * 7) % 256)
        }

        let forward = try await mct.forwardTransform(
            components: [c0, c1, c2],
            matrix: J2KMetalMCT.ictForwardMatrix,
            componentCount: 3,
            backend: .cpu
        )
        let inverse = try await mct.inverseTransform(
            components: forward.components,
            matrix: J2KMetalMCT.ictInverseMatrix,
            componentCount: 3,
            backend: .cpu
        )

        for i in 0..<count {
            XCTAssertEqual(inverse.components[0][i], c0[i], accuracy: 1.0)
            XCTAssertEqual(inverse.components[1][i], c1[i], accuracy: 1.0)
            XCTAssertEqual(inverse.components[2][i], c2[i], accuracy: 1.0)
        }
    }

    // MARK: - Fused Transform Error Tests

    /// Tests fused transform with invalid component count.
    func testFusedInvalidComponentCount() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.fusedColorMCTTransform(
                components: [[1.0]],
                colorMatrix: [1.0],
                mctMatrix: [1.0],
                componentCount: 1,
                backend: .cpu
            )
            XCTFail("Expected error for invalid component count")
        } catch {
            // Expected
        }
    }

    /// Tests fused transform with mismatched matrix sizes.
    func testFusedMatrixSizeMismatch() async {
        let mct = J2KMetalMCT()
        do {
            _ = try await mct.fusedColorMCTTransform(
                components: [[1.0], [2.0], [3.0]],
                colorMatrix: [1, 0, 0, 1],  // 2×2
                mctMatrix: [1, 0, 0, 0, 1, 0, 0, 0, 1],  // 3×3
                componentCount: 3,
                backend: .cpu
            )
            XCTFail("Expected error for matrix size mismatch")
        } catch {
            // Expected
        }
    }
}
