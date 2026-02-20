//
// J2KMetalQuantizerTests.swift
// J2KSwift
//
import XCTest
@testable import J2KMetal
@testable import J2KCore

/// Tests for Metal-accelerated quantization and dequantization operations.
final class J2KMetalQuantizerTests: XCTestCase {
    // MARK: - Configuration Tests

    /// Tests default quantization configuration.
    func testDefaultQuantizationConfiguration() {
        let config = J2KMetalQuantizationConfiguration()
        XCTAssertEqual(config.stepSize, 0.1, accuracy: 0.001)
        XCTAssertEqual(config.deadzoneWidth, 1.5, accuracy: 0.001)
        XCTAssertEqual(config.gpuThreshold, 1024)
    }

    /// Tests lossy configuration preset.
    func testLossyConfiguration() {
        let config = J2KMetalQuantizationConfiguration.lossy
        XCTAssertEqual(config.stepSize, 0.1, accuracy: 0.001)
    }

    /// Tests high quality configuration preset.
    func testHighQualityConfiguration() {
        let config = J2KMetalQuantizationConfiguration.highQuality
        XCTAssertEqual(config.stepSize, 0.05, accuracy: 0.001)
    }

    /// Tests custom configuration.
    func testCustomConfiguration() {
        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.2,
            deadzoneWidth: 2.0,
            gpuThreshold: 2048,
            backend: .gpu
        )
        XCTAssertEqual(config.stepSize, 0.2, accuracy: 0.001)
        XCTAssertEqual(config.deadzoneWidth, 2.0, accuracy: 0.001)
        XCTAssertEqual(config.gpuThreshold, 2048)
    }

    // MARK: - Statistics Tests

    /// Tests initial statistics are zero.
    func testInitialStatistics() {
        let stats = J2KMetalQuantizationStatistics()
        XCTAssertEqual(stats.totalQuantizations, 0)
        XCTAssertEqual(stats.totalDequantizations, 0)
        XCTAssertEqual(stats.gpuQuantizations, 0)
        XCTAssertEqual(stats.gpuDequantizations, 0)
        XCTAssertEqual(stats.cpuQuantizations, 0)
        XCTAssertEqual(stats.cpuDequantizations, 0)
        XCTAssertEqual(stats.totalProcessingTime, 0.0, accuracy: 0.001)
        XCTAssertEqual(stats.totalCoefficientsProcessed, 0)
    }

    /// Tests GPU utilization calculation.
    func testGPUUtilizationCalculation() {
        var stats = J2KMetalQuantizationStatistics()

        // Initially zero
        XCTAssertEqual(stats.gpuUtilization, 0.0, accuracy: 0.001)

        // After mixed operations
        stats.totalQuantizations = 6
        stats.totalDequantizations = 4
        stats.gpuQuantizations = 5
        stats.gpuDequantizations = 3
        stats.cpuQuantizations = 1
        stats.cpuDequantizations = 1

        // (5 + 3) / (6 + 4) = 0.8
        XCTAssertEqual(stats.gpuUtilization, 0.8, accuracy: 0.001)
    }

    /// Tests coefficients per second calculation.
    func testCoefficientsPerSecondCalculation() {
        var stats = J2KMetalQuantizationStatistics()

        // Initially zero
        XCTAssertEqual(stats.coefficientsPerSecond, 0.0, accuracy: 0.001)

        // After processing
        stats.totalCoefficientsProcessed = 1_000_000
        stats.totalProcessingTime = 0.1
        XCTAssertEqual(stats.coefficientsPerSecond, 10_000_000.0, accuracy: 0.1)
    }

    #if canImport(Metal)

    // MARK: - Device Initialization Tests

    /// Tests quantizer initialization.
    func testQuantizerInitialization() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let stats = await quantizer.getStatistics()
        XCTAssertEqual(stats.totalQuantizations, 0)
    }

    // MARK: - Scalar Quantization Tests

    /// Tests scalar quantization (CPU).
    func testScalarQuantizationCPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, -1.0, -2.0]
        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .cpu
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        // q = sign(c) × floor(|c| / Δ)
        XCTAssertEqual(result.indices[0], 0)   // floor(0.0 / 0.5) = 0
        XCTAssertEqual(result.indices[1], 1)   // floor(0.5 / 0.5) = 1
        XCTAssertEqual(result.indices[2], 2)   // floor(1.0 / 0.5) = 2
        XCTAssertEqual(result.indices[3], 3)   // floor(1.5 / 0.5) = 3
        XCTAssertEqual(result.indices[4], 4)   // floor(2.0 / 0.5) = 4
        XCTAssertEqual(result.indices[5], 5)   // floor(2.5 / 0.5) = 5
        XCTAssertEqual(result.indices[6], -2)  // -floor(1.0 / 0.5) = -2
        XCTAssertEqual(result.indices[7], -4)  // -floor(2.0 / 0.5) = -4

        XCTAssertFalse(result.usedGPU)
    }

    /// Tests scalar quantization with small values.
    func testScalarQuantizationSmallValues() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [0.01, 0.05, 0.09, 0.1, 0.15]
        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.1,
            backend: .cpu
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        XCTAssertEqual(result.indices[0], 0)  // floor(0.01 / 0.1) = 0
        XCTAssertEqual(result.indices[1], 0)  // floor(0.05 / 0.1) = 0
        XCTAssertEqual(result.indices[2], 0)  // floor(0.09 / 0.1) = 0
        XCTAssertEqual(result.indices[3], 1)  // floor(0.1 / 0.1) = 1
        XCTAssertEqual(result.indices[4], 1)  // floor(0.15 / 0.1) = 1
    }

    // MARK: - Dead-Zone Quantization Tests

    /// Tests dead-zone quantization (CPU).
    func testDeadzoneQuantizationCPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [0.0, 0.05, 0.1, 0.2, 0.3, 1.0, -0.1, -0.5]
        let config = J2KMetalQuantizationConfiguration(
            mode: .deadzone,
            stepSize: 0.1,
            deadzoneWidth: 1.5,  // threshold = 0.075
            backend: .cpu
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        // threshold = 0.1 * 1.5 * 0.5 = 0.075
        XCTAssertEqual(result.indices[0], 0)  // 0.0 <= 0.075
        XCTAssertEqual(result.indices[1], 0)  // 0.05 <= 0.075
        XCTAssertEqual(result.indices[2], 1)  // 0.1 > 0.075: floor((0.1 - 0.075) / 0.1) + 1 = 1
        XCTAssertEqual(result.indices[3], 2)  // floor((0.2 - 0.075) / 0.1) + 1 = 2
        XCTAssertEqual(result.indices[6], -1) // -0.1 < -0.075

        XCTAssertFalse(result.usedGPU)
    }

    /// Tests dead-zone with wide threshold.
    func testDeadzoneWithWideThreshold() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [0.1, 0.2, 0.3, 0.4, 0.5]
        let config = J2KMetalQuantizationConfiguration(
            mode: .deadzone,
            stepSize: 0.1,
            deadzoneWidth: 3.0,  // threshold = 0.15
            backend: .cpu
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        // threshold = 0.1 * 3.0 * 0.5 = 0.15
        XCTAssertEqual(result.indices[0], 0)  // 0.1 <= 0.15
        XCTAssertEqual(result.indices[1], 1)  // 0.2 > 0.15
        XCTAssertEqual(result.indices[2], 2)  // 0.3 > 0.15
        XCTAssertEqual(result.indices[3], 3)  // 0.4 > 0.15
        XCTAssertEqual(result.indices[4], 4)  // 0.5 > 0.15
    }

    // MARK: - Dequantization Tests

    /// Tests scalar dequantization (CPU).
    func testScalarDequantizationCPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let indices: [Int32] = [0, 1, 2, 3, -1, -2]
        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .cpu
        )

        let result = try await quantizer.dequantize(
            indices: indices,
            configuration: config
        )

        // c' = (q + 0.5 × sign(q)) × Δ (midpoint reconstruction)
        XCTAssertEqual(result.coefficients[0], 0.0, accuracy: 0.001)     // 0
        XCTAssertEqual(result.coefficients[1], 0.75, accuracy: 0.001)    // (1 + 0.5) * 0.5
        XCTAssertEqual(result.coefficients[2], 1.25, accuracy: 0.001)    // (2 + 0.5) * 0.5
        XCTAssertEqual(result.coefficients[3], 1.75, accuracy: 0.001)    // (3 + 0.5) * 0.5
        XCTAssertEqual(result.coefficients[4], -0.75, accuracy: 0.001)   // -(1 + 0.5) * 0.5
        XCTAssertEqual(result.coefficients[5], -1.25, accuracy: 0.001)   // -(2 + 0.5) * 0.5

        XCTAssertFalse(result.usedGPU)
    }

    /// Tests dead-zone dequantization (CPU).
    func testDeadzoneDequantizationCPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let indices: [Int32] = [0, 1, 2, 3, -1]
        let config = J2KMetalQuantizationConfiguration(
            mode: .deadzone,
            stepSize: 0.1,
            deadzoneWidth: 1.5,  // threshold = 0.075
            backend: .cpu
        )

        let result = try await quantizer.dequantize(
            indices: indices,
            configuration: config
        )

        // c' = sign(q) × ((|q| - 0.5) × Δ + threshold)
        let threshold: Float = 0.075
        XCTAssertEqual(result.coefficients[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(result.coefficients[1], (0.5 * 0.1 + threshold), accuracy: 0.001)
        XCTAssertEqual(result.coefficients[2], (1.5 * 0.1 + threshold), accuracy: 0.001)
        XCTAssertEqual(result.coefficients[3], (2.5 * 0.1 + threshold), accuracy: 0.001)
        XCTAssertEqual(result.coefficients[4], -(0.5 * 0.1 + threshold), accuracy: 0.001)
    }

    // MARK: - Round-Trip Tests

    /// Tests scalar quantization round-trip.
    func testScalarRoundTrip() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [0.0, 1.0, 2.5, -1.5, 3.7]
        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .cpu
        )

        // Quantize
        let quantized = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        // Dequantize
        let dequantized = try await quantizer.dequantize(
            indices: quantized.indices,
            configuration: config
        )

        // Check that values are reconstructed reasonably
        // (within one step size of original)
        for i in 0..<coeffs.count {
            let error = abs(dequantized.coefficients[i] - coeffs[i])
            XCTAssertLessThan(error, 0.6, "Reconstruction error too large at index \(i)")
        }
    }

    /// Tests dead-zone quantization round-trip.
    func testDeadzoneRoundTrip() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [0.0, 0.5, 1.0, 1.5, -1.0]
        let config = J2KMetalQuantizationConfiguration.lossy

        let quantized = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        let dequantized = try await quantizer.dequantize(
            indices: quantized.indices,
            configuration: config
        )

        // Small values should be quantized to zero
        XCTAssertEqual(quantized.indices[0], 0)
        XCTAssertEqual(dequantized.coefficients[0], 0.0, accuracy: 0.001)
    }

    // MARK: - 2D Array Tests

    /// Tests 2D quantization.
    func testQuantize2D() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [[Float]] = [
            [0.0, 0.5, 1.0],
            [1.5, 2.0, 2.5],
            [3.0, 3.5, 4.0]
        ]

        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .cpu
        )

        let result = try await quantizer.quantize2D(
            coefficients: coeffs,
            configuration: config
        )

        // Check dimensions
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].count, 3)

        // Check some values
        XCTAssertEqual(result[0][0], 0)
        XCTAssertEqual(result[0][2], 2)
        XCTAssertEqual(result[2][2], 8)
    }

    /// Tests 2D dequantization.
    func testDequantize2D() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let indices: [[Int32]] = [
            [0, 1, 2],
            [3, 4, 5]
        ]

        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .cpu
        )

        let result = try await quantizer.dequantize2D(
            indices: indices,
            configuration: config
        )

        // Check dimensions
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].count, 3)

        // Check values
        XCTAssertEqual(result[0][0], 0.0, accuracy: 0.001)
        XCTAssertEqual(result[0][1], 0.75, accuracy: 0.001)
        XCTAssertEqual(result[1][2], 2.75, accuracy: 0.001)
    }

    // MARK: - GPU Tests

    /// Tests quantization on GPU.
    func testQuantizationGPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        // Create large array for GPU
        var coeffs = [Float]()
        for i in 0..<2048 {
            coeffs.append(Float(i) * 0.1)
        }

        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .gpu
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        XCTAssertTrue(result.usedGPU)
        XCTAssertEqual(result.indices.count, 2048)

        // Spot check some values
        XCTAssertEqual(result.indices[0], 0)    // floor(0.0 / 0.5) = 0
        XCTAssertEqual(result.indices[10], 2)   // floor(1.0 / 0.5) = 2
        XCTAssertEqual(result.indices[100], 20) // floor(10.0 / 0.5) = 20
    }

    /// Tests dequantization on GPU.
    func testDequantizationGPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        // Create large array for GPU
        var indices = [Int32]()
        for i in 0..<2048 {
            indices.append(Int32(i))
        }

        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .gpu
        )

        let result = try await quantizer.dequantize(
            indices: indices,
            configuration: config
        )

        XCTAssertTrue(result.usedGPU)
        XCTAssertEqual(result.coefficients.count, 2048)

        // Spot check some values
        XCTAssertEqual(result.coefficients[0], 0.0, accuracy: 0.001)
        XCTAssertEqual(result.coefficients[10], 5.25, accuracy: 0.001) // (10 + 0.5) * 0.5
    }

    /// Tests GPU vs CPU consistency for scalar quantization.
    func testGPUCPUConsistencyScalar() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        // Test data
        var coeffs = [Float]()
        for i in 0..<2048 {
            coeffs.append(Float(i) * 0.01)
        }

        let baseConfig = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.1
        )

        // CPU version
        var cpuConfig = baseConfig
        cpuConfig.backend = .cpu
        let cpuResult = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: cpuConfig
        )

        // GPU version
        var gpuConfig = baseConfig
        gpuConfig.backend = .gpu
        let gpuResult = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: gpuConfig
        )

        // Results should match
        XCTAssertFalse(cpuResult.usedGPU)
        XCTAssertTrue(gpuResult.usedGPU)
        XCTAssertEqual(cpuResult.indices.count, gpuResult.indices.count)

        for i in 0..<coeffs.count {
            XCTAssertEqual(cpuResult.indices[i], gpuResult.indices[i],
                          "Mismatch at index \(i)")
        }
    }

    /// Tests GPU vs CPU consistency for dead-zone quantization.
    func testGPUCPUConsistencyDeadzone() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        // Test data
        var coeffs = [Float]()
        for i in 0..<2048 {
            coeffs.append(Float(i) * 0.01)
        }

        let baseConfig = J2KMetalQuantizationConfiguration(
            mode: .deadzone,
            stepSize: 0.1,
            deadzoneWidth: 1.5
        )

        // CPU version
        var cpuConfig = baseConfig
        cpuConfig.backend = .cpu
        let cpuResult = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: cpuConfig
        )

        // GPU version
        var gpuConfig = baseConfig
        gpuConfig.backend = .gpu
        let gpuResult = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: gpuConfig
        )

        // Results should match
        for i in 0..<coeffs.count {
            XCTAssertEqual(cpuResult.indices[i], gpuResult.indices[i],
                          "Mismatch at index \(i)")
        }
    }

    // MARK: - Backend Selection Tests

    /// Tests auto backend selection (small -> CPU).
    func testAutoBackendSelectionSmall() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs = [Float](repeating: 1.0, count: 100)
        let config = J2KMetalQuantizationConfiguration(
            gpuThreshold: 1000,
            backend: .auto
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        XCTAssertFalse(result.usedGPU)

        let stats = await quantizer.getStatistics()
        XCTAssertEqual(stats.cpuQuantizations, 1)
        XCTAssertEqual(stats.gpuQuantizations, 0)
    }

    /// Tests auto backend selection (large -> GPU).
    func testAutoBackendSelectionLarge() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs = [Float](repeating: 1.0, count: 5000)
        let config = J2KMetalQuantizationConfiguration(
            gpuThreshold: 1000,
            backend: .auto
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        XCTAssertTrue(result.usedGPU)

        let stats = await quantizer.getStatistics()
        XCTAssertEqual(stats.gpuQuantizations, 1)
        XCTAssertEqual(stats.cpuQuantizations, 0)
    }

    // MARK: - Statistics Tracking Tests

    /// Tests statistics reset.
    func testStatisticsReset() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        // Perform operations
        let coeffs = [Float](repeating: 1.0, count: 100)
        let config = J2KMetalQuantizationConfiguration(backend: .cpu)

        _ = try await quantizer.quantize(coefficients: coeffs, configuration: config)

        var stats = await quantizer.getStatistics()
        XCTAssertGreaterThan(stats.totalQuantizations, 0)

        // Reset
        await quantizer.resetStatistics()
        stats = await quantizer.getStatistics()
        XCTAssertEqual(stats.totalQuantizations, 0)
    }

    /// Tests statistics accumulation.
    func testStatisticsAccumulation() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs = [Float](repeating: 1.0, count: 100)
        let config = J2KMetalQuantizationConfiguration(backend: .cpu)

        // Multiple quantizations
        for _ in 0..<3 {
            _ = try await quantizer.quantize(coefficients: coeffs, configuration: config)
        }

        // Multiple dequantizations
        let indices = [Int32](repeating: 1, count: 100)
        for _ in 0..<2 {
            _ = try await quantizer.dequantize(indices: indices, configuration: config)
        }

        let stats = await quantizer.getStatistics()
        XCTAssertEqual(stats.totalQuantizations, 3)
        XCTAssertEqual(stats.totalDequantizations, 2)
        XCTAssertEqual(stats.cpuQuantizations, 3)
        XCTAssertEqual(stats.cpuDequantizations, 2)
        XCTAssertEqual(stats.totalCoefficientsProcessed, 500) // 5 × 100
    }

    // MARK: - Edge Case Tests

    /// Tests quantization of all zeros.
    func testQuantizationAllZeros() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs = [Float](repeating: 0.0, count: 100)
        let config = J2KMetalQuantizationConfiguration(backend: .cpu)

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        // All should be zero
        for index in result.indices {
            XCTAssertEqual(index, 0)
        }
    }

    /// Tests quantization of very large values.
    func testQuantizationLargeValues() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [1000.0, -1000.0, 5000.0]
        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 10.0,
            backend: .cpu
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        XCTAssertEqual(result.indices[0], 100)   // floor(1000 / 10)
        XCTAssertEqual(result.indices[1], -100)  // -floor(1000 / 10)
        XCTAssertEqual(result.indices[2], 500)   // floor(5000 / 10)
    }

    /// Tests single value quantization.
    func testSingleValueQuantization() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = [1.5]
        let config = J2KMetalQuantizationConfiguration(
            mode: .scalar,
            stepSize: 0.5,
            backend: .cpu
        )

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        XCTAssertEqual(result.indices.count, 1)
        XCTAssertEqual(result.indices[0], 3) // floor(1.5 / 0.5) = 3
    }

    /// Tests empty array handling.
    func testEmptyArrayQuantization() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary()
        let quantizer = try await J2KMetalQuantizer(
            device: device,
            shaderLibrary: shaderLibrary
        )

        let coeffs: [Float] = []
        let config = J2KMetalQuantizationConfiguration(backend: .cpu)

        let result = try await quantizer.quantize(
            coefficients: coeffs,
            configuration: config
        )

        XCTAssertEqual(result.indices.count, 0)
    }

    #endif // canImport(Metal)
}
