import XCTest
@testable import J2KMetal
@testable import J2KCore

/// Tests for Metal-accelerated Region of Interest (ROI) operations.
final class J2KMetalROITests: XCTestCase {
    // MARK: - Configuration Tests

    /// Tests default ROI configuration.
    func testDefaultROIConfiguration() {
        let config = J2KMetalROIConfiguration.default
        XCTAssertEqual(config.gpuThreshold, 4096)
        XCTAssertEqual(config.featherWidth, 8.0, accuracy: 0.001)
    }

    /// Tests custom ROI configuration.
    func testCustomROIConfiguration() {
        let config = J2KMetalROIConfiguration(
            gpuThreshold: 8192,
            featherWidth: 16.0,
            backend: .gpu
        )
        XCTAssertEqual(config.gpuThreshold, 8192)
        XCTAssertEqual(config.featherWidth, 16.0, accuracy: 0.001)
    }

    // MARK: - Statistics Tests

    /// Tests initial statistics are zero.
    func testInitialStatistics() {
        let stats = J2KMetalROIStatistics()
        XCTAssertEqual(stats.totalOperations, 0)
        XCTAssertEqual(stats.gpuOperations, 0)
        XCTAssertEqual(stats.cpuOperations, 0)
        XCTAssertEqual(stats.totalProcessingTime, 0.0, accuracy: 0.001)
        XCTAssertEqual(stats.totalPixelsProcessed, 0)
    }

    /// Tests GPU utilization calculation.
    func testGPUUtilizationCalculation() {
        var stats = J2KMetalROIStatistics()

        // Initially zero operations
        XCTAssertEqual(stats.gpuUtilization, 0.0, accuracy: 0.001)

        // After some operations
        stats.totalOperations = 10
        stats.gpuOperations = 7
        stats.cpuOperations = 3
        XCTAssertEqual(stats.gpuUtilization, 0.7, accuracy: 0.001)
    }

    /// Tests pixels per second calculation.
    func testPixelsPerSecondCalculation() {
        var stats = J2KMetalROIStatistics()

        // Initially zero
        XCTAssertEqual(stats.pixelsPerSecond, 0.0, accuracy: 0.001)

        // After processing
        stats.totalPixelsProcessed = 1_000_000
        stats.totalProcessingTime = 0.5
        XCTAssertEqual(stats.pixelsPerSecond, 2_000_000.0, accuracy: 0.1)
    }

    #if canImport(Metal)

    // MARK: - Device Initialization Tests

    /// Tests ROI processor initialization.
    func testROIProcessorInitialization() async throws {
        // Skip test if Metal not available
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        let stats = await roi.getStatistics()
        XCTAssertEqual(stats.totalOperations, 0)
    }

    // MARK: - Mask Generation Tests

    /// Tests rectangular ROI mask generation (CPU fallback).
    func testRectangularMaskGenerationCPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Small image - should use CPU
        let config = J2KMetalROIConfiguration(
            gpuThreshold: 10000,
            backend: .cpu
        )

        let mask = try await roi.generateMask(
            width: 8,
            height: 8,
            x: 2,
            y: 2,
            roiWidth: 4,
            roiHeight: 4,
            configuration: config
        )

        // Verify dimensions
        XCTAssertEqual(mask.count, 8)
        XCTAssertEqual(mask[0].count, 8)

        // Check ROI region is true
        for y in 2..<6 {
            for x in 2..<6 {
                XCTAssertTrue(mask[y][x], "Pixel at (\(x), \(y)) should be in ROI")
            }
        }

        // Check outside region is false
        XCTAssertFalse(mask[0][0])
        XCTAssertFalse(mask[7][7])
        XCTAssertFalse(mask[0][7])
        XCTAssertFalse(mask[7][0])
    }

    /// Tests rectangular ROI mask generation (GPU).
    func testRectangularMaskGenerationGPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Force GPU
        let config = J2KMetalROIConfiguration(backend: .gpu)

        let mask = try await roi.generateMask(
            width: 64,
            height: 64,
            x: 16,
            y: 16,
            roiWidth: 32,
            roiHeight: 32,
            configuration: config
        )

        // Verify dimensions
        XCTAssertEqual(mask.count, 64)
        XCTAssertEqual(mask[0].count, 64)

        // Check ROI region
        for y in 16..<48 {
            for x in 16..<48 {
                XCTAssertTrue(mask[y][x], "Pixel at (\(x), \(y)) should be in ROI")
            }
        }

        // Check corners are false
        XCTAssertFalse(mask[0][0])
        XCTAssertFalse(mask[63][63])
    }

    /// Tests full-image ROI mask.
    func testFullImageROIMask() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        let mask = try await roi.generateMask(
            width: 32,
            height: 32,
            x: 0,
            y: 0,
            roiWidth: 32,
            roiHeight: 32,
            configuration: .default
        )

        // All pixels should be in ROI
        for y in 0..<32 {
            for x in 0..<32 {
                XCTAssertTrue(mask[y][x])
            }
        }
    }

    /// Tests empty ROI mask.
    func testEmptyROIMask() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // ROI outside image bounds
        let mask = try await roi.generateMask(
            width: 32,
            height: 32,
            x: 100,
            y: 100,
            roiWidth: 10,
            roiHeight: 10,
            configuration: .default
        )

        // All pixels should be false
        for y in 0..<32 {
            for x in 0..<32 {
                XCTAssertFalse(mask[y][x])
            }
        }
    }

    // MARK: - MaxShift Scaling Tests

    /// Tests MaxShift coefficient scaling (CPU).
    func testMaxShiftScalingCPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Create test coefficients
        let coeffs: [[Int32]] = [
            [10, 20, 30, 40],
            [50, 60, 70, 80],
            [90, 100, 110, 120],
            [130, 140, 150, 160]
        ]

        // Create ROI mask (center 2×2)
        let mask: [[Bool]] = [
            [false, false, false, false],
            [false, true, true, false],
            [false, true, true, false],
            [false, false, false, false]
        ]

        let config = J2KMetalROIConfiguration(backend: .cpu)
        let shift: UInt32 = 5  // Multiply by 32

        let scaled = try await roi.applyMaxShift(
            coefficients: coeffs,
            mask: mask,
            shift: shift,
            width: 4,
            height: 4,
            configuration: config
        )

        // Check non-ROI values unchanged
        XCTAssertEqual(scaled[0][0], 10)
        XCTAssertEqual(scaled[0][3], 40)
        XCTAssertEqual(scaled[3][0], 130)

        // Check ROI values scaled
        XCTAssertEqual(scaled[1][1], 60 << 5)  // 60 * 32 = 1920
        XCTAssertEqual(scaled[1][2], 70 << 5)  // 70 * 32 = 2240
        XCTAssertEqual(scaled[2][1], 100 << 5) // 100 * 32 = 3200
        XCTAssertEqual(scaled[2][2], 110 << 5) // 110 * 32 = 3520
    }

    /// Tests MaxShift with negative coefficients.
    func testMaxShiftWithNegativeCoefficients() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Mixed positive and negative coefficients
        let coeffs: [[Int32]] = [
            [10, -20],
            [-30, 40]
        ]

        let mask: [[Bool]] = [
            [true, true],
            [true, true]
        ]

        let config = J2KMetalROIConfiguration(backend: .cpu)
        let shift: UInt32 = 3  // Multiply by 8

        let scaled = try await roi.applyMaxShift(
            coefficients: coeffs,
            mask: mask,
            shift: shift,
            width: 2,
            height: 2,
            configuration: config
        )

        // Check sign preservation
        XCTAssertEqual(scaled[0][0], 80)   // 10 * 8 = 80
        XCTAssertEqual(scaled[0][1], -160) // -20 * 8 = -160
        XCTAssertEqual(scaled[1][0], -240) // -30 * 8 = -240
        XCTAssertEqual(scaled[1][1], 320)  // 40 * 8 = 320
    }

    /// Tests MaxShift scaling (GPU).
    func testMaxShiftScalingGPU() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Larger array for GPU
        let size = 64
        var coeffs = Array(repeating: Array(repeating: Int32(0), count: size), count: size)
        var mask = Array(repeating: Array(repeating: false, count: size), count: size)

        // Fill with test values
        for y in 0..<size {
            for x in 0..<size {
                coeffs[y][x] = Int32(y * size + x + 1)
                // Center ROI
                if x >= 16 && x < 48 && y >= 16 && y < 48 {
                    mask[y][x] = true
                }
            }
        }

        let config = J2KMetalROIConfiguration(backend: .gpu)
        let shift: UInt32 = 5

        let scaled = try await roi.applyMaxShift(
            coefficients: coeffs,
            mask: mask,
            shift: shift,
            width: size,
            height: size,
            configuration: config
        )

        // Check non-ROI unchanged
        XCTAssertEqual(scaled[0][0], 1)
        XCTAssertEqual(scaled[0][15], 16)

        // Check ROI scaled
        let roiValue = Int32(16 * size + 16 + 1) // Value at (16, 16)
        XCTAssertEqual(scaled[16][16], roiValue << 5)
    }

    /// Tests MaxShift with zero coefficients.
    func testMaxShiftWithZeroCoefficients() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        let coeffs: [[Int32]] = [
            [0, 0, 10],
            [0, 20, 0],
            [30, 0, 0]
        ]

        let mask: [[Bool]] = [
            [true, true, true],
            [true, true, true],
            [true, true, true]
        ]

        let config = J2KMetalROIConfiguration(backend: .cpu)
        let shift: UInt32 = 4

        let scaled = try await roi.applyMaxShift(
            coefficients: coeffs,
            mask: mask,
            shift: shift,
            width: 3,
            height: 3,
            configuration: config
        )

        // Zero should remain zero
        XCTAssertEqual(scaled[0][0], 0)
        XCTAssertEqual(scaled[0][1], 0)
        XCTAssertEqual(scaled[1][0], 0)

        // Non-zero should be scaled
        XCTAssertEqual(scaled[0][2], 10 << 4)
        XCTAssertEqual(scaled[1][1], 20 << 4)
        XCTAssertEqual(scaled[2][0], 30 << 4)
    }

    // MARK: - Backend Selection Tests

    /// Tests auto backend selection (small -> CPU).
    func testAutoBackendSelectionSmall() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Small image with auto backend
        let config = J2KMetalROIConfiguration(
            gpuThreshold: 10000,
            backend: .auto
        )

        _ = try await roi.generateMask(
            width: 10,
            height: 10,
            x: 0,
            y: 0,
            roiWidth: 5,
            roiHeight: 5,
            configuration: config
        )

        let stats = await roi.getStatistics()
        XCTAssertEqual(stats.totalOperations, 1)
        XCTAssertEqual(stats.cpuOperations, 1)
        XCTAssertEqual(stats.gpuOperations, 0)
    }

    /// Tests auto backend selection (large -> GPU).
    func testAutoBackendSelectionLarge() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Large image with auto backend
        let config = J2KMetalROIConfiguration(
            gpuThreshold: 1000,
            backend: .auto
        )

        _ = try await roi.generateMask(
            width: 128,
            height: 128,
            x: 0,
            y: 0,
            roiWidth: 64,
            roiHeight: 64,
            configuration: config
        )

        let stats = await roi.getStatistics()
        XCTAssertEqual(stats.totalOperations, 1)
        XCTAssertEqual(stats.gpuOperations, 1)
        XCTAssertEqual(stats.cpuOperations, 0)
    }

    // MARK: - Statistics Tracking Tests

    /// Tests statistics reset.
    func testStatisticsReset() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        // Perform some operations
        let config = J2KMetalROIConfiguration(backend: .cpu)
        _ = try await roi.generateMask(
            width: 10,
            height: 10,
            x: 0,
            y: 0,
            roiWidth: 5,
            roiHeight: 5,
            configuration: config
        )

        var stats = await roi.getStatistics()
        XCTAssertGreaterThan(stats.totalOperations, 0)

        // Reset
        await roi.resetStatistics()
        stats = await roi.getStatistics()
        XCTAssertEqual(stats.totalOperations, 0)
        XCTAssertEqual(stats.totalProcessingTime, 0.0, accuracy: 0.001)
    }

    /// Tests statistics accumulation.
    func testStatisticsAccumulation() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        let config = J2KMetalROIConfiguration(backend: .cpu)

        // Perform multiple operations
        for _ in 0..<5 {
            _ = try await roi.generateMask(
                width: 10,
                height: 10,
                x: 0,
                y: 0,
                roiWidth: 5,
                roiHeight: 5,
                configuration: config
            )
        }

        let stats = await roi.getStatistics()
        XCTAssertEqual(stats.totalOperations, 5)
        XCTAssertEqual(stats.cpuOperations, 5)
        XCTAssertEqual(stats.totalPixelsProcessed, 500) // 5 × 100 pixels
    }

    // MARK: - Edge Case Tests

    /// Tests 1×1 image.
    func testSinglePixelImage() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        let mask = try await roi.generateMask(
            width: 1,
            height: 1,
            x: 0,
            y: 0,
            roiWidth: 1,
            roiHeight: 1,
            configuration: .default
        )

        XCTAssertEqual(mask.count, 1)
        XCTAssertEqual(mask[0].count, 1)
        XCTAssertTrue(mask[0][0])
    }

    /// Tests very large shift value.
    func testLargeShiftValue() async throws {
        guard J2KMetalDevice.isAvailable else {
            throw XCTSkip("Metal not available on this platform")
        }

        let device = try await J2KMetalDevice()
        let shaderLibrary = try await J2KMetalShaderLibrary(device: device)
        let roi = try await J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

        let coeffs: [[Int32]] = [[1]]
        let mask: [[Bool]] = [[true]]

        let config = J2KMetalROIConfiguration(backend: .cpu)
        let shift: UInt32 = 10  // Multiply by 1024

        let scaled = try await roi.applyMaxShift(
            coefficients: coeffs,
            mask: mask,
            shift: shift,
            width: 1,
            height: 1,
            configuration: config
        )

        XCTAssertEqual(scaled[0][0], 1 << 10)
    }

    #endif // canImport(Metal)
}
