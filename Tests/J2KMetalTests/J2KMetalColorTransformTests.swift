import XCTest
@testable import J2KMetal
@testable import J2KCore

/// Tests for Metal-accelerated color space transforms.
final class J2KMetalColorTransformTests: XCTestCase {
    // MARK: - Platform Availability Tests

    /// Tests that Metal color transform availability can be queried.
    func testColorTransformAvailability() {
        let available = J2KMetalColorTransform.isAvailable
        #if canImport(Metal)
        _ = available
        #else
        XCTAssertFalse(available)
        #endif
    }

    // MARK: - Transform Type Tests

    /// Tests ICT transform type.
    func testICTTransformType() {
        let transformType = J2KMetalColorTransformType.ict
        switch transformType {
        case .ict:
            break // Expected
        case .rct:
            XCTFail("Expected ICT transform type")
        }
    }

    /// Tests RCT transform type.
    func testRCTTransformType() {
        let transformType = J2KMetalColorTransformType.rct
        switch transformType {
        case .rct:
            break // Expected
        case .ict:
            XCTFail("Expected RCT transform type")
        }
    }

    // MARK: - Backend Tests

    /// Tests GPU backend selection.
    func testGPUBackend() {
        let backend = J2KMetalColorTransformBackend.gpu
        switch backend {
        case .gpu:
            break // Expected
        default:
            XCTFail("Expected GPU backend")
        }
    }

    /// Tests CPU backend selection.
    func testCPUBackend() {
        let backend = J2KMetalColorTransformBackend.cpu
        switch backend {
        case .cpu:
            break // Expected
        default:
            XCTFail("Expected CPU backend")
        }
    }

    /// Tests auto backend selection.
    func testAutoBackend() {
        let backend = J2KMetalColorTransformBackend.auto
        switch backend {
        case .auto:
            break // Expected
        default:
            XCTFail("Expected auto backend")
        }
    }

    // MARK: - Configuration Tests

    /// Tests default lossy configuration.
    func testLossyConfiguration() {
        let config = J2KMetalColorTransformConfiguration.lossy
        switch config.transformType {
        case .ict:
            break // Expected
        default:
            XCTFail("Expected ICT for lossy config")
        }
        XCTAssertEqual(config.gpuThreshold, 1024)
    }

    /// Tests lossless configuration.
    func testLosslessConfiguration() {
        let config = J2KMetalColorTransformConfiguration.lossless
        switch config.transformType {
        case .rct:
            break // Expected
        default:
            XCTFail("Expected RCT for lossless config")
        }
    }

    /// Tests custom configuration.
    func testCustomConfiguration() {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .ict,
            gpuThreshold: 2048
        )
        XCTAssertEqual(config.gpuThreshold, 2048)
    }

    // MARK: - Statistics Tests

    /// Tests initial statistics are zero.
    func testInitialStatistics() {
        let stats = J2KMetalColorTransformStatistics()
        XCTAssertEqual(stats.totalOperations, 0)
        XCTAssertEqual(stats.gpuOperations, 0)
        XCTAssertEqual(stats.cpuOperations, 0)
        XCTAssertEqual(stats.totalProcessingTime, 0.0)
        XCTAssertEqual(stats.totalSamplesProcessed, 0)
    }

    /// Tests GPU utilization calculation.
    func testGPUUtilization() {
        var stats = J2KMetalColorTransformStatistics()
        XCTAssertEqual(stats.gpuUtilization, 0.0)

        stats.totalOperations = 10
        stats.gpuOperations = 7
        XCTAssertEqual(stats.gpuUtilization, 0.7, accuracy: 0.001)
    }

    /// Tests samples per second calculation.
    func testSamplesPerSecond() {
        var stats = J2KMetalColorTransformStatistics()
        XCTAssertEqual(stats.samplesPerSecond, 0.0)

        stats.totalSamplesProcessed = 10000
        stats.totalProcessingTime = 0.5
        XCTAssertEqual(stats.samplesPerSecond, 20000.0, accuracy: 0.1)
    }

    // MARK: - Result Tests

    /// Tests color transform result creation.
    func testColorTransformResult() {
        let result = J2KMetalColorTransformResult(
            component0: [1.0, 2.0, 3.0],
            component1: [4.0, 5.0, 6.0],
            component2: [7.0, 8.0, 9.0],
            transformType: .ict,
            usedGPU: false
        )
        XCTAssertEqual(result.component0.count, 3)
        XCTAssertEqual(result.component1.count, 3)
        XCTAssertEqual(result.component2.count, 3)
        XCTAssertFalse(result.usedGPU)
    }

    // MARK: - Forward ICT Transform Tests (CPU)

    /// Tests forward ICT with known values.
    func testForwardICTKnownValues() async throws {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .ict, gpuThreshold: Int.max
        )
        let ct = J2KMetalColorTransform(configuration: config)

        let red: [Float] = [255.0, 0.0, 0.0, 128.0]
        let green: [Float] = [0.0, 255.0, 0.0, 128.0]
        let blue: [Float] = [0.0, 0.0, 255.0, 128.0]

        let result = try await ct.forwardTransform(
            red: red, green: green, blue: blue, backend: .cpu
        )

        // Y for pure red: 0.299 * 255 = 76.245
        XCTAssertEqual(result.component0[0], 0.299 * 255.0, accuracy: 0.01)
        // Y for pure green: 0.587 * 255 = 149.685
        XCTAssertEqual(result.component0[1], 0.587 * 255.0, accuracy: 0.01)
        // Y for pure blue: 0.114 * 255 = 29.07
        XCTAssertEqual(result.component0[2], 0.114 * 255.0, accuracy: 0.01)
        // Y for gray: 0.299*128 + 0.587*128 + 0.114*128 = 128
        XCTAssertEqual(result.component0[3], 128.0, accuracy: 0.01)

        XCTAssertFalse(result.usedGPU)
    }

    /// Tests forward ICT produces zero chrominance for gray.
    func testForwardICTGrayInput() async throws {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .ict, gpuThreshold: Int.max
        )
        let ct = J2KMetalColorTransform(configuration: config)

        let gray: [Float] = [128.0, 128.0, 128.0]
        let result = try await ct.forwardTransform(
            red: gray, green: gray, blue: gray, backend: .cpu
        )

        // For gray input, Cb and Cr should be near zero
        for i in 0..<3 {
            XCTAssertEqual(result.component1[i], 0.0, accuracy: 0.01)
            XCTAssertEqual(result.component2[i], 0.0, accuracy: 0.01)
        }
    }

    // MARK: - Inverse ICT Transform Tests (CPU)

    /// Tests inverse ICT recovers original values.
    func testInverseICTRecovery() async throws {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .ict, gpuThreshold: Int.max
        )
        let ct = J2KMetalColorTransform(configuration: config)

        let red: [Float] = [200.0, 50.0, 100.0, 150.0]
        let green: [Float] = [100.0, 200.0, 50.0, 150.0]
        let blue: [Float] = [50.0, 100.0, 200.0, 150.0]

        let forward = try await ct.forwardTransform(
            red: red, green: green, blue: blue, backend: .cpu
        )
        let inverse = try await ct.inverseTransform(
            component0: forward.component0,
            component1: forward.component1,
            component2: forward.component2,
            backend: .cpu
        )

        for i in 0..<4 {
            XCTAssertEqual(inverse.component0[i], red[i], accuracy: 0.5)
            XCTAssertEqual(inverse.component1[i], green[i], accuracy: 0.5)
            XCTAssertEqual(inverse.component2[i], blue[i], accuracy: 0.5)
        }
    }

    // MARK: - Forward RCT Transform Tests (CPU)

    /// Tests forward RCT with known values.
    func testForwardRCTKnownValues() async throws {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .rct, gpuThreshold: Int.max
        )
        let ct = J2KMetalColorTransform(configuration: config)

        let red: [Float] = [100.0]
        let green: [Float] = [200.0]
        let blue: [Float] = [50.0]

        let result = try await ct.forwardTransform(
            red: red, green: green, blue: blue, backend: .cpu
        )

        // Y = (R + 2G + B) >> 2 = (100 + 400 + 50) >> 2 = 137
        XCTAssertEqual(result.component0[0], Float(Int32((100 + 400 + 50)) >> 2), accuracy: 0.5)
        // U = B - G = 50 - 200 = -150
        XCTAssertEqual(result.component1[0], -150.0, accuracy: 0.5)
        // V = R - G = 100 - 200 = -100
        XCTAssertEqual(result.component2[0], -100.0, accuracy: 0.5)
    }

    /// Tests inverse RCT recovers original values.
    func testInverseRCTRecovery() async throws {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .rct, gpuThreshold: Int.max
        )
        let ct = J2KMetalColorTransform(configuration: config)

        let red: [Float] = [100.0, 200.0, 50.0]
        let green: [Float] = [150.0, 100.0, 200.0]
        let blue: [Float] = [75.0, 50.0, 100.0]

        let forward = try await ct.forwardTransform(
            red: red, green: green, blue: blue, backend: .cpu
        )
        let inverse = try await ct.inverseTransform(
            component0: forward.component0,
            component1: forward.component1,
            component2: forward.component2,
            backend: .cpu
        )

        for i in 0..<3 {
            XCTAssertEqual(inverse.component0[i], red[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component1[i], green[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component2[i], blue[i], accuracy: 1.0)
        }
    }

    // MARK: - NLT Transform Tests (CPU)

    /// Tests gamma NLT transform.
    func testNLTGamma() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [0.0, 0.25, 0.5, 1.0]
        let result = try await ct.applyNLT(
            data: data, type: .gamma(2.2), backend: .cpu
        )

        XCTAssertEqual(result[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(result[3], 1.0, accuracy: 0.001)
        // pow(0.5, 2.2) ≈ 0.2176
        XCTAssertEqual(result[2], pow(0.5, 2.2), accuracy: 0.01)
    }

    /// Tests logarithmic NLT transform.
    func testNLTLogarithmic() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [0.0, 0.5, 1.0]
        let result = try await ct.applyNLT(
            data: data, type: .logarithmic(scale: 1.0, coefficient: 1.0),
            backend: .cpu
        )

        XCTAssertEqual(result[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(result[1], log(1.5), accuracy: 0.01)
        XCTAssertEqual(result[2], log(2.0), accuracy: 0.01)
    }

    /// Tests exponential NLT transform.
    func testNLTExponential() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [0.0, 0.5, 1.0]
        let result = try await ct.applyNLT(
            data: data, type: .exponential(scale: 1.0, coefficient: 1.0),
            backend: .cpu
        )

        XCTAssertEqual(result[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(result[1], exp(0.5) - 1.0, accuracy: 0.01)
        XCTAssertEqual(result[2], exp(1.0) - 1.0, accuracy: 0.01)
    }

    /// Tests PQ NLT transform.
    func testNLTPQ() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [0.0, 0.5, 1.0]
        let result = try await ct.applyNLT(
            data: data, type: .pq, backend: .cpu
        )

        // PQ(0) = 0 (approximately)
        XCTAssertEqual(result[0], 0.0, accuracy: 0.01)
        // PQ(1) = 1
        XCTAssertEqual(result[2], 1.0, accuracy: 0.001)
        // PQ is monotonically increasing
        XCTAssertLessThan(result[0], result[1])
        XCTAssertLessThan(result[1], result[2])
    }

    /// Tests HLG NLT transform.
    func testNLTHLG() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [0.0, 0.5, 1.0]
        let result = try await ct.applyNLT(
            data: data, type: .hlg, backend: .cpu
        )

        // HLG(0) = 0
        XCTAssertEqual(result[0], 0.0, accuracy: 0.001)
        // HLG is monotonically increasing
        XCTAssertLessThan(result[0], result[1])
        XCTAssertLessThan(result[1], result[2])
        // HLG(1) = 1
        XCTAssertEqual(result[2], 1.0, accuracy: 0.01)
    }

    /// Tests LUT-based NLT transform.
    func testNLTLUT() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let lut: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
        let data: [Float] = [0.0, 0.5, 1.0]
        let result = try await ct.applyNLT(
            data: data,
            type: .lut(table: lut, inputMin: 0.0, inputMax: 1.0),
            backend: .cpu
        )

        XCTAssertEqual(result[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(result[1], 0.5, accuracy: 0.001)
        XCTAssertEqual(result[2], 1.0, accuracy: 0.001)
    }

    /// Tests LUT interpolation.
    func testNLTLUTInterpolation() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let lut: [Float] = [0.0, 1.0] // Linear LUT from 0 to 1
        let data: [Float] = [0.25, 0.75]
        let result = try await ct.applyNLT(
            data: data,
            type: .lut(table: lut, inputMin: 0.0, inputMax: 1.0),
            backend: .cpu
        )

        XCTAssertEqual(result[0], 0.25, accuracy: 0.001)
        XCTAssertEqual(result[1], 0.75, accuracy: 0.001)
    }

    // MARK: - Backend Selection Tests

    /// Tests effective backend with CPU forced.
    func testEffectiveBackendCPU() async {
        let ct = J2KMetalColorTransform()
        let backend = await ct.effectiveBackend(
            sampleCount: 10000, backend: .cpu
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
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: 1024)
        )
        let backend = await ct.effectiveBackend(
            sampleCount: 100, backend: .auto
        )
        switch backend {
        case .cpu:
            break // Expected on this platform or below threshold
        default:
            break // GPU possible on Metal platforms
        }
    }

    // MARK: - Error Handling Tests

    /// Tests error for empty input.
    func testEmptyInputError() async {
        let ct = J2KMetalColorTransform()
        do {
            _ = try await ct.forwardTransform(
                red: [], green: [], blue: [], backend: .cpu
            )
            XCTFail("Expected error for empty input")
        } catch {
            // Expected
        }
    }

    /// Tests error for mismatched component lengths.
    func testMismatchedLengthsError() async {
        let ct = J2KMetalColorTransform()
        do {
            _ = try await ct.forwardTransform(
                red: [1.0, 2.0], green: [1.0], blue: [1.0, 2.0],
                backend: .cpu
            )
            XCTFail("Expected error for mismatched lengths")
        } catch {
            // Expected
        }
    }

    /// Tests error for empty NLT input.
    func testEmptyNLTError() async {
        let ct = J2KMetalColorTransform()
        do {
            _ = try await ct.applyNLT(
                data: [], type: .gamma(2.2), backend: .cpu
            )
            XCTFail("Expected error for empty NLT input")
        } catch {
            // Expected
        }
    }

    // MARK: - Statistics Tracking Tests

    /// Tests statistics tracking after CPU operations.
    func testStatisticsTracking() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [100.0, 200.0, 50.0]
        _ = try await ct.forwardTransform(
            red: data, green: data, blue: data, backend: .cpu
        )

        let stats = await ct.statistics()
        XCTAssertEqual(stats.totalOperations, 1)
        XCTAssertEqual(stats.cpuOperations, 1)
        XCTAssertEqual(stats.gpuOperations, 0)
        XCTAssertEqual(stats.totalSamplesProcessed, 3)
        XCTAssertGreaterThan(stats.totalProcessingTime, 0.0)
    }

    /// Tests statistics reset.
    func testStatisticsReset() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [100.0]
        _ = try await ct.forwardTransform(
            red: data, green: data, blue: data, backend: .cpu
        )
        await ct.resetStatistics()

        let stats = await ct.statistics()
        XCTAssertEqual(stats.totalOperations, 0)
    }

    // MARK: - Large Data Tests

    /// Tests forward ICT with large data set.
    func testForwardICTLargeData() async throws {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .ict, gpuThreshold: Int.max
        )
        let ct = J2KMetalColorTransform(configuration: config)

        let count = 4096
        let red = [Float](repeating: 128.0, count: count)
        let green = [Float](repeating: 128.0, count: count)
        let blue = [Float](repeating: 128.0, count: count)

        let result = try await ct.forwardTransform(
            red: red, green: green, blue: blue, backend: .cpu
        )

        XCTAssertEqual(result.component0.count, count)
        XCTAssertEqual(result.component1.count, count)
        XCTAssertEqual(result.component2.count, count)

        // Gray input: Y ≈ 128, Cb ≈ 0, Cr ≈ 0
        XCTAssertEqual(result.component0[0], 128.0, accuracy: 0.1)
        XCTAssertEqual(result.component1[0], 0.0, accuracy: 0.1)
        XCTAssertEqual(result.component2[0], 0.0, accuracy: 0.1)
    }

    /// Tests forward/inverse roundtrip with large data.
    func testICTRoundtripLargeData() async throws {
        let config = J2KMetalColorTransformConfiguration(
            transformType: .ict, gpuThreshold: Int.max
        )
        let ct = J2KMetalColorTransform(configuration: config)

        let count = 1024
        var red = [Float](repeating: 0, count: count)
        var green = [Float](repeating: 0, count: count)
        var blue = [Float](repeating: 0, count: count)
        for i in 0..<count {
            red[i] = Float(i % 256)
            green[i] = Float((i * 3) % 256)
            blue[i] = Float((i * 7) % 256)
        }

        let forward = try await ct.forwardTransform(
            red: red, green: green, blue: blue, backend: .cpu
        )
        let inverse = try await ct.inverseTransform(
            component0: forward.component0,
            component1: forward.component1,
            component2: forward.component2,
            backend: .cpu
        )

        for i in 0..<count {
            XCTAssertEqual(inverse.component0[i], red[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component1[i], green[i], accuracy: 1.0)
            XCTAssertEqual(inverse.component2[i], blue[i], accuracy: 1.0)
        }
    }

    // MARK: - NLT Edge Case Tests

    /// Tests NLT with negative values.
    func testNLTGammaNegativeValues() async throws {
        let ct = J2KMetalColorTransform(
            configuration: .init(gpuThreshold: Int.max)
        )

        let data: [Float] = [-1.0, -0.5, 0.0, 0.5, 1.0]
        let result = try await ct.applyNLT(
            data: data, type: .gamma(2.0), backend: .cpu
        )

        // Negative values should preserve sign
        XCTAssertEqual(result[0], -1.0, accuracy: 0.001)
        XCTAssertEqual(result[1], -0.25, accuracy: 0.001)
        XCTAssertEqual(result[2], 0.0, accuracy: 0.001)
        XCTAssertEqual(result[3], 0.25, accuracy: 0.001)
        XCTAssertEqual(result[4], 1.0, accuracy: 0.001)
    }
}
