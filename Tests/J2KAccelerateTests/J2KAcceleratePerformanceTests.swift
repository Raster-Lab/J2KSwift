/// Tests for J2KAcceleratePerformance.

import XCTest
@testable import J2KAccelerate

#if canImport(Accelerate)

final class J2KAcceleratePerformanceTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitWithBalancedConfig() async {
        let optimizer = J2KAcceleratePerformance()
        let config = await optimizer.currentConfiguration()

        XCTAssertTrue(config.enableVDSPOptimization)
        XCTAssertTrue(config.useNEONPaths)
        XCTAssertTrue(config.enableAMX)
        XCTAssertEqual(config.minAccelerateSize, 64)
    }

    func testInitWithCustomConfig() async {
        let customConfig = J2KAcceleratePerformance.Configuration(
            minAccelerateSize: 128,
            enableAMX: false
        )
        let optimizer = J2KAcceleratePerformance(configuration: customConfig)
        let config = await optimizer.currentConfiguration()

        XCTAssertEqual(config.minAccelerateSize, 128)
        XCTAssertFalse(config.enableAMX)
    }

    // MARK: - Configuration Tests

    func testOptimizeForThroughput() async {
        let optimizer = J2KAcceleratePerformance()
        let config = await optimizer.optimizeForThroughput()

        XCTAssertTrue(config.enableVDSPOptimization)
        XCTAssertTrue(config.useNEONPaths)
        XCTAssertTrue(config.enableAMX)
        XCTAssertEqual(config.minAccelerateSize, 32)
        XCTAssertEqual(config.vectorBatchSize, 8192)
    }

    func testOptimizeForLowPower() async {
        let optimizer = J2KAcceleratePerformance()
        let config = await optimizer.optimizeForLowPower()

        XCTAssertTrue(config.enableVDSPOptimization)
        XCTAssertFalse(config.useNEONPaths)
        XCTAssertFalse(config.enableAMX)
        XCTAssertEqual(config.minAccelerateSize, 128)
    }

    func testSetConfiguration() async {
        let optimizer = J2KAcceleratePerformance()
        let customConfig = J2KAcceleratePerformance.Configuration(
            vectorBatchSize: 16384
        )
        await optimizer.setConfiguration(customConfig)

        let config = await optimizer.currentConfiguration()
        XCTAssertEqual(config.vectorBatchSize, 16384)
    }

    // MARK: - Operation Selection Tests

    func testShouldUseAccelerateSmallArray() async {
        let optimizer = J2KAcceleratePerformance()
        let shouldUse = await optimizer.shouldUseAccelerate(arraySize: 32)

        // Below minimum size
        XCTAssertFalse(shouldUse)
    }

    func testShouldUseAccelerateLargeArray() async {
        let optimizer = J2KAcceleratePerformance()
        let shouldUse = await optimizer.shouldUseAccelerate(arraySize: 1000)

        // Above minimum size
        XCTAssertTrue(shouldUse)
    }

    func testShouldUseAccelerateDisabled() async {
        let config = J2KAcceleratePerformance.Configuration(
            enableVDSPOptimization: false
        )
        let optimizer = J2KAcceleratePerformance(configuration: config)
        let shouldUse = await optimizer.shouldUseAccelerate(arraySize: 1000)

        XCTAssertFalse(shouldUse)
    }

    func testOptimalBatchSizeSmall() async {
        let optimizer = J2KAcceleratePerformance()
        let batchSize = await optimizer.optimalBatchSize(
            totalSize: 100,
            elementSize: 4
        )

        XCTAssertGreaterThan(batchSize, 0)
        XCTAssertLessThanOrEqual(batchSize, 100)
    }

    func testOptimalBatchSizeLarge() async {
        let optimizer = J2KAcceleratePerformance()
        let batchSize = await optimizer.optimalBatchSize(
            totalSize: 100000,
            elementSize: 4
        )

        XCTAssertGreaterThan(batchSize, 0)
        XCTAssertLessThanOrEqual(batchSize, 100000)
    }

    // MARK: - vDSP Function Recommendation Tests

    func testRecommendVDSPFunctionAdd() async {
        let optimizer = J2KAcceleratePerformance()
        let function = await optimizer.recommendVDSPFunction(
            operation: "add",
            dataType: "float",
            size: 1000
        )

        XCTAssertEqual(function, "vDSP_vadd")
    }

    func testRecommendVDSPFunctionAddDouble() async {
        let optimizer = J2KAcceleratePerformance()
        let function = await optimizer.recommendVDSPFunction(
            operation: "add",
            dataType: "double",
            size: 1000
        )

        XCTAssertEqual(function, "vDSP_vaddD")
    }

    func testRecommendVDSPFunctionFFTPowerOfTwo() async {
        let optimizer = J2KAcceleratePerformance()
        let function = await optimizer.recommendVDSPFunction(
            operation: "fft",
            dataType: "float",
            size: 1024
        )

        XCTAssertEqual(function, "vDSP_fft_zip")
    }

    func testRecommendVDSPFunctionFFTNonPowerOfTwo() async {
        let optimizer = J2KAcceleratePerformance()
        let function = await optimizer.recommendVDSPFunction(
            operation: "fft",
            dataType: "float",
            size: 1000
        )

        XCTAssertEqual(function, "vDSP_DFT")
    }

    // MARK: - NEON Optimization Tests

    func testShouldUseNEON() async {
        let optimizer = J2KAcceleratePerformance()
        let shouldUse = await optimizer.shouldUseNEON()

        #if arch(arm64)
        XCTAssertTrue(shouldUse)
        #else
        XCTAssertFalse(shouldUse)
        #endif
    }

    func testShouldUseNEONDisabled() async {
        let config = J2KAcceleratePerformance.Configuration(useNEONPaths: false)
        let optimizer = J2KAcceleratePerformance(configuration: config)
        let shouldUse = await optimizer.shouldUseNEON()

        XCTAssertFalse(shouldUse)
    }

    func testNEONVectorWidth() async {
        let optimizer = J2KAcceleratePerformance()
        let width = await optimizer.neonVectorWidth()

        #if arch(arm64)
        XCTAssertEqual(width, 16) // 128-bit vectors
        #else
        XCTAssertEqual(width, 16)
        #endif
    }

    // MARK: - AMX Optimization Tests

    func testShouldUseAMXSmallMatrix() async {
        let optimizer = J2KAcceleratePerformance()
        let shouldUse = await optimizer.shouldUseAMX(rows: 8, cols: 8)

        // Too small for AMX
        XCTAssertFalse(shouldUse)
    }

    func testShouldUseAMXLargeMatrix() async {
        let optimizer = J2KAcceleratePerformance()
        let shouldUse = await optimizer.shouldUseAMX(rows: 64, cols: 64)

        #if arch(arm64) && (os(macOS) || os(iOS))
        if #available(macOS 11.0, iOS 14.0, *) {
            XCTAssertTrue(shouldUse)
        }
        #else
        XCTAssertFalse(shouldUse)
        #endif
    }

    func testShouldUseAMXDisabled() async {
        let config = J2KAcceleratePerformance.Configuration(enableAMX: false)
        let optimizer = J2KAcceleratePerformance(configuration: config)
        let shouldUse = await optimizer.shouldUseAMX(rows: 64, cols: 64)

        XCTAssertFalse(shouldUse)
    }

    func testAMXTileSize() async {
        let optimizer = J2KAcceleratePerformance()
        let (width, height) = await optimizer.amxTileSize()

        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        XCTAssertEqual(width, 16)
        XCTAssertEqual(height, 16)
    }

    // MARK: - Data Conversion Tests

    func testNeedsConversionSameType() async {
        let optimizer = J2KAcceleratePerformance()
        let needs = await optimizer.needsConversion(
            sourceType: "float",
            targetType: "float"
        )

        XCTAssertFalse(needs)
    }

    func testNeedsConversionDifferentType() async {
        let optimizer = J2KAcceleratePerformance()
        let needs = await optimizer.needsConversion(
            sourceType: "float",
            targetType: "double"
        )

        XCTAssertTrue(needs)
    }

    func testNeedsConversionMinimizeDisabled() async {
        let config = J2KAcceleratePerformance.Configuration(
            minimizeConversions: false
        )
        let optimizer = J2KAcceleratePerformance(configuration: config)
        let needs = await optimizer.needsConversion(
            sourceType: "float",
            targetType: "float"
        )

        XCTAssertTrue(needs)
    }

    func testRecommendedDataTypeHighPrecision() async {
        let optimizer = J2KAcceleratePerformance()
        let dataType = await optimizer.recommendedDataType(
            operationType: "general",
            precision: "high"
        )

        XCTAssertEqual(dataType, "double")
    }

    func testRecommendedDataTypeMatrixWithAMX() async {
        let optimizer = J2KAcceleratePerformance()
        let dataType = await optimizer.recommendedDataType(
            operationType: "matrix",
            precision: "normal"
        )

        #if arch(arm64) && (os(macOS) || os(iOS))
        if #available(macOS 11.0, iOS 14.0, *) {
            XCTAssertEqual(dataType, "float16")
        }
        #endif
    }

    func testRecommendedDataTypeDefault() async {
        let optimizer = J2KAcceleratePerformance()
        let dataType = await optimizer.recommendedDataType(
            operationType: "general",
            precision: "normal"
        )

        XCTAssertEqual(dataType, "float")
    }

    // MARK: - In-Place Operation Tests

    func testShouldUseInPlaceSmallData() async {
        let optimizer = J2KAcceleratePerformance()
        let shouldUse = await optimizer.shouldUseInPlace(
            dataSize: 512 * 1024,
            operation: "add"
        )

        // Below threshold
        XCTAssertFalse(shouldUse)
    }

    func testShouldUseInPlaceLargeData() async {
        let optimizer = J2KAcceleratePerformance()
        let shouldUse = await optimizer.shouldUseInPlace(
            dataSize: 10 * 1024 * 1024,
            operation: "add"
        )

        // Above threshold
        XCTAssertTrue(shouldUse)
    }

    func testShouldUseInPlaceDisabled() async {
        let config = J2KAcceleratePerformance.Configuration(
            enableInPlaceOperations: false
        )
        let optimizer = J2KAcceleratePerformance(configuration: config)
        let shouldUse = await optimizer.shouldUseInPlace(
            dataSize: 10 * 1024 * 1024,
            operation: "add"
        )

        XCTAssertFalse(shouldUse)
    }

    func testMemorySavedByInPlace() async {
        let optimizer = J2KAcceleratePerformance()
        let saved = await optimizer.memorySavedByInPlace(dataSize: 1024 * 1024)

        XCTAssertEqual(saved, 1024 * 1024)
    }

    // MARK: - Performance Tracking Tests

    func testRecordOperation() async {
        let optimizer = J2KAcceleratePerformance()
        await optimizer.startSession()

        await optimizer.recordOperation(
            type: "vDSP",
            duration: 0.001,
            dataSize: 1024
        )

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.totalVDSPOperations, 1)
        XCTAssertGreaterThan(metrics.vdspTime, 0)
    }

    func testRecordMultipleOperations() async {
        let optimizer = J2KAcceleratePerformance()
        await optimizer.startSession()

        await optimizer.recordOperation(
            type: "vDSP",
            duration: 0.001,
            dataSize: 1024
        )
        await optimizer.recordOperation(
            type: "NEON",
            duration: 0.002,
            dataSize: 2048
        )
        await optimizer.recordOperation(
            type: "AMX",
            duration: 0.003,
            dataSize: 4096
        )

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.totalVDSPOperations, 1)
        XCTAssertEqual(metrics.totalNEONOperations, 1)
        XCTAssertEqual(metrics.totalAMXOperations, 1)
    }

    func testRecordInPlaceOperations() async {
        let optimizer = J2KAcceleratePerformance()
        await optimizer.startSession()

        await optimizer.recordOperation(
            type: "vDSP",
            duration: 0.001,
            dataSize: 1024 * 1024,
            inPlace: true
        )
        await optimizer.recordOperation(
            type: "vDSP",
            duration: 0.001,
            dataSize: 2048 * 1024,
            inPlace: false
        )

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.totalInPlaceOperations, 1)
        XCTAssertEqual(metrics.memorySaved, 1024 * 1024)
    }

    func testPerformanceMetricsEmpty() async {
        let optimizer = J2KAcceleratePerformance()
        await optimizer.startSession()
        let metrics = await optimizer.endSession()

        XCTAssertEqual(metrics.totalVDSPOperations, 0)
        XCTAssertEqual(metrics.totalNEONOperations, 0)
        XCTAssertEqual(metrics.totalAMXOperations, 0)
        XCTAssertEqual(metrics.vdspTime, 0.0)
    }

    func testPerformanceMetricsSpeedup() async {
        let optimizer = J2KAcceleratePerformance()
        await optimizer.startSession()

        await optimizer.recordOperation(
            type: "vDSP",
            duration: 0.001,
            dataSize: 1024
        )

        let metrics = await optimizer.endSession()
        XCTAssertGreaterThan(metrics.averageSpeedup, 1.0)
    }

    // MARK: - Platform Capabilities Tests

    func testPlatformCapabilities() async {
        let optimizer = J2KAcceleratePerformance()
        let (hasNEON, hasAMX, vectorWidth) = await optimizer.platformCapabilities()

        #if arch(arm64)
        XCTAssertTrue(hasNEON)
        XCTAssertEqual(vectorWidth, 128)

        #if os(macOS) || os(iOS)
        if #available(macOS 11.0, iOS 14.0, *) {
            XCTAssertTrue(hasAMX)
        }
        #endif
        #elseif arch(x86_64)
        XCTAssertFalse(hasNEON)
        XCTAssertEqual(vectorWidth, 256)
        #endif
    }
}

#endif // canImport(Accelerate)
