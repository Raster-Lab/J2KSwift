//
// J2KMetalPerformanceTests.swift
// J2KSwift
//
/// Tests for J2KMetalPerformance.

import XCTest
@testable import J2KMetal

#if canImport(Metal)
import Metal

final class J2KMetalPerformanceTests: XCTestCase {
    var device: MTLDevice!

    override func setUp() {
        super.setUp()
        device = MTLCreateSystemDefaultDevice()
    }

    // MARK: - Initialization Tests

    func testInitWithBalancedConfig() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let config = await optimizer.currentConfiguration()

        XCTAssertTrue(config.enableAsyncCompute)
        XCTAssertTrue(config.batchKernelLaunches)
        XCTAssertEqual(config.targetThreadsPerThreadgroup, 256)
    }

    func testInitWithCustomConfig() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let customConfig = J2KMetalPerformance.Configuration(
            targetThreadsPerThreadgroup: 512,
            enableAsyncCompute: false
        )
        let optimizer = J2KMetalPerformance(device: device, configuration: customConfig)
        let config = await optimizer.currentConfiguration()

        XCTAssertEqual(config.targetThreadsPerThreadgroup, 512)
        XCTAssertFalse(config.enableAsyncCompute)
    }

    // MARK: - Configuration Tests

    func testOptimizeForThroughput() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let config = await optimizer.optimizeForThroughput()

        XCTAssertEqual(config.targetThreadsPerThreadgroup, 512)
        XCTAssertTrue(config.enableAsyncCompute)
        XCTAssertEqual(config.minBatchSize, 2)
    }

    func testOptimizeForLatency() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let config = await optimizer.optimizeForLatency()

        XCTAssertEqual(config.targetThreadsPerThreadgroup, 128)
        XCTAssertFalse(config.enableAsyncCompute)
        XCTAssertFalse(config.batchKernelLaunches)
    }

    // MARK: - Threadgroup Optimization Tests

    func testOptimalThreadgroupSizeSmall() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let size = await optimizer.optimalThreadgroupSize(workloadSize: 64)

        XCTAssertGreaterThanOrEqual(size, 32)
        XCTAssertLessThanOrEqual(size, 256)
        XCTAssertEqual(size % 32, 0) // Should be multiple of 32
    }

    func testOptimalThreadgroupSizeLarge() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let size = await optimizer.optimalThreadgroupSize(workloadSize: 10000)

        XCTAssertGreaterThanOrEqual(size, 32)
        XCTAssertLessThanOrEqual(size, device.maxThreadsPerThreadgroup.width)
    }

    func testOptimalThreadgroupSizeWithMemory() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let size = await optimizer.optimalThreadgroupSize(
            workloadSize: 1000,
            memoryPerThread: 1024
        )

        XCTAssertGreaterThan(size, 0)
        // Should respect memory constraints
        let totalMemory = size * 1024
        XCTAssertLessThanOrEqual(totalMemory, device.maxThreadgroupMemoryLength)
    }

    func testOptimalThreadgroupSize2D() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let (width, height) = await optimizer.optimalThreadgroupSize2D(
            width: 1920,
            height: 1080
        )

        XCTAssertGreaterThan(width, 0)
        XCTAssertGreaterThan(height, 0)
        XCTAssertLessThanOrEqual(width * height, device.maxThreadsPerThreadgroup.width)
        XCTAssertEqual(width % 8, 0) // Should be multiple of 8
        XCTAssertEqual(height % 8, 0)
    }

    func testOptimalThreadgroupSize2DWideAspect() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let (width, height) = await optimizer.optimalThreadgroupSize2D(
            width: 3840,
            height: 1080
        )

        // Wide aspect ratio should favor wider threadgroup
        XCTAssertGreaterThanOrEqual(width, height)
    }

    // MARK: - Memory Bandwidth Tests

    func testOptimalMemoryAccessSequential() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let (pattern, batchSize) = await optimizer.optimalMemoryAccess(
            dataSize: 1024 * 1024,
            stride: 0,
            accessPattern: "sequential"
        )

        XCTAssertEqual(pattern, "sequential")
        XCTAssertGreaterThan(batchSize, 0)
    }

    func testOptimalMemoryAccessStrided() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let (pattern, batchSize) = await optimizer.optimalMemoryAccess(
            dataSize: 1024 * 1024,
            stride: 128,
            accessPattern: "strided"
        )

        XCTAssertTrue(pattern == "scattered" || pattern == "batched")
        XCTAssertGreaterThan(batchSize, 0)
    }

    func testEstimateBandwidthUtilization() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let utilization = await optimizer.estimateBandwidthUtilization(
            bytesRead: 100 * 1024 * 1024,
            bytesWritten: 50 * 1024 * 1024,
            duration: 0.01
        )

        XCTAssertGreaterThanOrEqual(utilization, 0.0)
        XCTAssertLessThanOrEqual(utilization, 1.0)
    }

    func testEstimateBandwidthUtilizationZeroDuration() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let utilization = await optimizer.estimateBandwidthUtilization(
            bytesRead: 1000,
            bytesWritten: 1000,
            duration: 0.0
        )

        XCTAssertEqual(utilization, 0.0)
    }

    // MARK: - Kernel Launch Tests

    func testRecordKernelLaunch() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        await optimizer.startSession()

        await optimizer.recordKernelLaunch(
            name: "DWT",
            duration: 0.001,
            threadgroupSize: 256
        )

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.totalLaunches, 1)
        XCTAssertGreaterThan(metrics.totalGPUTime, 0)
    }

    func testRecordMultipleKernelLaunches() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        await optimizer.startSession()

        for _ in 0..<10 {
            await optimizer.recordKernelLaunch(
                name: "DWT",
                duration: 0.001,
                threadgroupSize: 256
            )
        }

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.totalLaunches, 10)
    }

    func testRecordBatchedLaunches() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        await optimizer.startSession()

        await optimizer.recordKernelLaunch(
            name: "DWT",
            duration: 0.001,
            batched: true
        )
        await optimizer.recordKernelLaunch(
            name: "MCT",
            duration: 0.002,
            batched: false
        )

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.batchedLaunches, 1)
    }

    func testRecordAsyncLaunches() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        await optimizer.startSession()

        await optimizer.recordKernelLaunch(
            name: "DWT",
            duration: 0.001,
            async: true
        )
        await optimizer.recordKernelLaunch(
            name: "MCT",
            duration: 0.002,
            async: false
        )

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.asyncComputeUsage, 50.0, accuracy: 1.0)
    }

    func testShouldBatchLaunches() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)

        let shouldBatch1 = await optimizer.shouldBatchLaunches(launchCount: 2)
        XCTAssertFalse(shouldBatch1)

        let shouldBatch2 = await optimizer.shouldBatchLaunches(launchCount: 10)
        XCTAssertTrue(shouldBatch2)
    }

    func testEstimatedLaunchOverhead() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let overhead = await optimizer.estimatedLaunchOverhead()

        XCTAssertGreaterThan(overhead, 0)
        XCTAssertLessThan(overhead, 0.001) // Should be microseconds
    }

    // MARK: - Performance Metrics Tests

    func testPerformanceMetricsEmpty() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        await optimizer.startSession()
        let metrics = await optimizer.endSession()

        XCTAssertEqual(metrics.totalLaunches, 0)
        XCTAssertEqual(metrics.totalGPUTime, 0.0)
        XCTAssertEqual(metrics.batchedLaunches, 0)
    }

    func testPerformanceMetricsWithData() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        await optimizer.startSession()

        await optimizer.recordKernelLaunch(
            name: "DWT",
            duration: 0.005,
            batched: true,
            async: true
        )

        let metrics = await optimizer.endSession()
        XCTAssertEqual(metrics.totalLaunches, 1)
        XCTAssertEqual(metrics.totalGPUTime, 0.005, accuracy: 0.001)
        XCTAssertGreaterThan(metrics.gpuUtilization, 0)
        XCTAssertGreaterThan(metrics.bandwidthUtilization, 0)
    }

    // MARK: - Device Capabilities Tests

    func testDeviceCharacteristics() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let (maxThreadgroups, maxThreadsPerThreadgroup, recommendedThreadgroups) =
            await optimizer.deviceCharacteristics()

        XCTAssertGreaterThan(maxThreadgroups, 0)
        XCTAssertGreaterThan(maxThreadsPerThreadgroup, 0)
        XCTAssertGreaterThan(recommendedThreadgroups, 0)
        XCTAssertLessThanOrEqual(recommendedThreadgroups, maxThreadgroups)
    }

    func testSupportsAsyncCompute() async throws {
        guard device != nil else {
            throw XCTSkip("Metal not available")
        }

        let optimizer = J2KMetalPerformance(device: device)
        let supportsAsync = await optimizer.supportsAsyncCompute()

        // Modern Apple GPUs should support async compute
        #if os(macOS) || os(iOS)
        XCTAssertTrue(supportsAsync)
        #endif
    }
}

#endif // canImport(Metal)
