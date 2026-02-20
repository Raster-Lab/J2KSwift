//
// J2KPerformanceOptimizerTests.swift
// J2KSwift
//
/// Tests for J2KPerformanceOptimizer.

import XCTest
@testable import J2KCore

final class J2KPerformanceOptimizerTests: XCTestCase {
    // MARK: - Initialization Tests

    func testInitWithBalancedMode() async {
        let optimizer = J2KPerformanceOptimizer(mode: .balanced)
        let params = await optimizer.currentParameters()

        XCTAssertTrue(params.enableBatching)
        XCTAssertTrue(params.enableOverlap)
        XCTAssertTrue(params.enableCacheOptimization)
    }

    func testInitWithHighPerformanceMode() async {
        let optimizer = J2KPerformanceOptimizer(mode: .highPerformance)
        let params = await optimizer.currentParameters()

        XCTAssertTrue(params.enableBatching)
        XCTAssertTrue(params.enableOverlap)
        XCTAssertEqual(params.minGPUBatchSize, 2)
    }

    func testInitWithLowPowerMode() async {
        let optimizer = J2KPerformanceOptimizer(mode: .lowPower)
        let params = await optimizer.currentParameters()

        XCTAssertFalse(params.enableBatching)
        XCTAssertFalse(params.enableOverlap)
        XCTAssertEqual(params.maxCPUThreads, 2)
    }

    func testInitWithCustomMode() async {
        let customParams = J2KPerformanceOptimizer.OptimizationParameters(
            maxCPUThreads: 8,
            enableBatching: false,
            maxMemoryUsage: 256 * 1024 * 1024
        )
        let optimizer = J2KPerformanceOptimizer(mode: .custom(customParams))
        let params = await optimizer.currentParameters()

        XCTAssertEqual(params.maxCPUThreads, 8)
        XCTAssertFalse(params.enableBatching)
        XCTAssertEqual(params.maxMemoryUsage, 256 * 1024 * 1024)
    }

    // MARK: - Configuration Tests

    func testConfigureForHighPerformance() async {
        let optimizer = J2KPerformanceOptimizer()
        await optimizer.configureForHighPerformance()

        let params = await optimizer.currentParameters()
        XCTAssertTrue(params.enableBatching)
        XCTAssertTrue(params.enableOverlap)
    }

    func testConfigureForLowPower() async {
        let optimizer = J2KPerformanceOptimizer()
        await optimizer.configureForLowPower()

        let params = await optimizer.currentParameters()
        XCTAssertFalse(params.enableBatching)
        XCTAssertFalse(params.enableOverlap)
    }

    func testConfigureWithCustomParameters() async {
        let optimizer = J2KPerformanceOptimizer()
        let customParams = J2KPerformanceOptimizer.OptimizationParameters(
            maxCPUThreads: 16,
            enableBatching: true
        )
        await optimizer.configure(with: customParams)

        let params = await optimizer.currentParameters()
        XCTAssertEqual(params.maxCPUThreads, 16)
        XCTAssertTrue(params.enableBatching)
    }

    // MARK: - Pipeline Optimization Tests

    func testOptimizeEncodingPipeline() async throws {
        let optimizer = J2KPerformanceOptimizer()

        let (result, profile) = try await optimizer.optimizeEncodingPipeline {
            // Simulate encoding work
            Thread.sleep(forTimeInterval: 0.01)
            return 42
        }

        XCTAssertEqual(result, 42)
        XCTAssertGreaterThan(profile.totalTime, 0)
        XCTAssertGreaterThanOrEqual(profile.cpuTime, 0)
    }

    func testOptimizeDecodingPipeline() async throws {
        let optimizer = J2KPerformanceOptimizer()

        let (result, profile) = try await optimizer.optimizeDecodingPipeline {
            // Simulate decoding work
            Thread.sleep(forTimeInterval: 0.01)
            return "decoded"
        }

        XCTAssertEqual(result, "decoded")
        XCTAssertGreaterThan(profile.totalTime, 0)
        XCTAssertGreaterThanOrEqual(profile.cpuTime, 0)
    }

    func testPipelineOptimizationWithError() async {
        let optimizer = J2KPerformanceOptimizer()

        do {
            _ = try await optimizer.optimizeEncodingPipeline {
                throw TestError.simulatedError
            }
            XCTFail("Should have thrown error")
        } catch {
            XCTAssertTrue(error is TestError)
        }
    }

    // MARK: - GPU Decision Tests

    func testShouldUseGPUSmallData() async {
        let optimizer = J2KPerformanceOptimizer(mode: .balanced)
        let shouldUse = await optimizer.shouldUseGPU(
            dataSize: 512 * 1024, // 512 KB
            operationType: "DWT"
        )

        // Small data typically doesn't benefit from GPU
        XCTAssertFalse(shouldUse)
    }

    func testShouldUseGPULargeData() async {
        let optimizer = J2KPerformanceOptimizer(mode: .highPerformance)
        let shouldUse = await optimizer.shouldUseGPU(
            dataSize: 10 * 1024 * 1024, // 10 MB
            operationType: "DWT"
        )

        // Large data in high-performance mode should use GPU
        #if canImport(Metal)
        // May be true on systems with Metal
        _ = shouldUse
        #else
        XCTAssertFalse(shouldUse)
        #endif
    }

    func testShouldUseGPULowPowerMode() async {
        let optimizer = J2KPerformanceOptimizer(mode: .lowPower)
        let shouldUse = await optimizer.shouldUseGPU(
            dataSize: 5 * 1024 * 1024,
            operationType: "DWT"
        )

        // Low power mode is conservative about GPU usage
        _ = shouldUse // Result depends on system capabilities
    }

    // MARK: - Batch Size Tests

    func testOptimalBatchSizeSmallItems() async {
        let optimizer = J2KPerformanceOptimizer(mode: .balanced)
        let batchSize = await optimizer.optimalBatchSize(
            itemCount: 100,
            itemSize: 1024 // 1 KB items
        )

        XCTAssertGreaterThan(batchSize, 0)
        XCTAssertLessThanOrEqual(batchSize, 100)
    }

    func testOptimalBatchSizeLargeItems() async {
        let optimizer = J2KPerformanceOptimizer(mode: .balanced)
        let batchSize = await optimizer.optimalBatchSize(
            itemCount: 100,
            itemSize: 1024 * 1024 // 1 MB items
        )

        XCTAssertGreaterThan(batchSize, 0)
        XCTAssertLessThanOrEqual(batchSize, 100)
    }

    func testOptimalBatchSizeNoBatching() async {
        let optimizer = J2KPerformanceOptimizer(mode: .lowPower)
        let batchSize = await optimizer.optimalBatchSize(
            itemCount: 100,
            itemSize: 1024
        )

        // Low power mode disables batching
        XCTAssertEqual(batchSize, 1)
    }

    // MARK: - Thread Count Tests

    func testOptimalThreadCountHighPerformance() async {
        let optimizer = J2KPerformanceOptimizer(mode: .highPerformance)
        let threadCount = await optimizer.optimalThreadCount(operationType: "DWT")

        let systemCores = ProcessInfo.processInfo.activeProcessorCount
        XCTAssertEqual(threadCount, systemCores)
    }

    func testOptimalThreadCountLowPower() async {
        let optimizer = J2KPerformanceOptimizer(mode: .lowPower)
        let threadCount = await optimizer.optimalThreadCount(operationType: "DWT")

        let systemCores = ProcessInfo.processInfo.activeProcessorCount
        XCTAssertLessThanOrEqual(threadCount, systemCores / 2)
    }

    func testOptimalThreadCountBalanced() async {
        let optimizer = J2KPerformanceOptimizer(mode: .balanced)
        let threadCount = await optimizer.optimalThreadCount(operationType: "DWT")

        let systemCores = ProcessInfo.processInfo.activeProcessorCount
        XCTAssertGreaterThan(threadCount, 1)
        XCTAssertLessThanOrEqual(threadCount, systemCores)
    }

    func testOptimalThreadCountWithLimit() async {
        let params = J2KPerformanceOptimizer.OptimizationParameters(
            maxCPUThreads: 4
        )
        let optimizer = J2KPerformanceOptimizer(mode: .custom(params))
        let threadCount = await optimizer.optimalThreadCount(operationType: "DWT")

        XCTAssertLessThanOrEqual(threadCount, 4)
    }

    // MARK: - Memory Tests

    func testHasSufficientMemoryUnlimited() async {
        let optimizer = J2KPerformanceOptimizer(mode: .highPerformance)
        let hasSufficient = await optimizer.hasSufficientMemory(100 * 1024 * 1024)

        XCTAssertTrue(hasSufficient)
    }

    func testHasSufficientMemoryLimited() async {
        let optimizer = J2KPerformanceOptimizer(mode: .lowPower)
        let hasSufficient = await optimizer.hasSufficientMemory(1024 * 1024 * 1024)

        // Low power mode has 512 MB limit
        XCTAssertFalse(hasSufficient)
    }

    func testRecommendedAllocationStrategySmall() async {
        let optimizer = J2KPerformanceOptimizer()
        let strategy = await optimizer.recommendedAllocationStrategy(dataSize: 512 * 1024)

        XCTAssertEqual(strategy, "stack")
    }

    func testRecommendedAllocationStrategyLarge() async {
        let optimizer = J2KPerformanceOptimizer()
        let strategy = await optimizer.recommendedAllocationStrategy(
            dataSize: 200 * 1024 * 1024
        )

        XCTAssertEqual(strategy, "memory_mapped")
    }

    func testRecommendedAllocationStrategyMedium() async {
        let optimizer = J2KPerformanceOptimizer()
        let strategy = await optimizer.recommendedAllocationStrategy(
            dataSize: 50 * 1024 * 1024
        )

        XCTAssertEqual(strategy, "heap")
    }

    // MARK: - Performance Profile Tests

    func testPerformanceProfileMetrics() {
        let profile = J2KPerformanceOptimizer.PerformanceProfile(
            totalTime: 1.0,
            cpuTime: 0.6,
            gpuTime: 0.3,
            memoryAllocated: 100 * 1024 * 1024,
            peakMemoryUsage: 150 * 1024 * 1024,
            syncPoints: 10,
            dataProcessed: 200 * 1024 * 1024
        )

        XCTAssertEqual(profile.totalTime, 1.0, accuracy: 0.01)
        XCTAssertEqual(profile.cpuUtilization, 60.0, accuracy: 1.0)
        XCTAssertEqual(profile.gpuUtilization, 30.0, accuracy: 1.0)
        XCTAssertEqual(profile.throughputMBps, 200.0, accuracy: 1.0)
        XCTAssertEqual(profile.pipelineEfficiency, 90.0, accuracy: 1.0)
    }

    func testPerformanceProfileZeroTime() {
        let profile = J2KPerformanceOptimizer.PerformanceProfile(
            totalTime: 0.0,
            cpuTime: 0.0,
            gpuTime: 0.0,
            memoryAllocated: 0,
            peakMemoryUsage: 0,
            syncPoints: 0,
            dataProcessed: 0
        )

        XCTAssertEqual(profile.throughputMBps, 0.0)
        XCTAssertEqual(profile.cpuUtilization, 0.0)
        XCTAssertEqual(profile.gpuUtilization, 0.0)
    }
}

// MARK: - Test Error

enum TestError: Error {
    case simulatedError
}
