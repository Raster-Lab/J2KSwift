import XCTest
@testable import J2KCore
import Foundation

/// Tests for the pipeline profiler, optimized allocator, thread pool, and zero-copy buffer.
final class J2KPerformanceTuningTests: XCTestCase {
    // MARK: - J2KPipelineProfiler Tests

    func testProfilerMeasureRecordsTiming() throws {
        let profiler = J2KPipelineProfiler()

        let metrics = profiler.measure(stage: .waveletTransform) {
            // Simulate work
            var sum = 0
            for i in 0..<1000 { sum += i }
            _ = sum
        }

        XCTAssertEqual(metrics.stage, .waveletTransform)
        XCTAssertGreaterThan(metrics.elapsedTime, 0)
        XCTAssertEqual(metrics.itemsProcessed, 1)
        XCTAssertNil(metrics.label)
    }

    func testProfilerMeasureWithLabel() throws {
        let profiler = J2KPipelineProfiler()

        let metrics = profiler.measure(
            stage: .entropyCoding,
            itemsProcessed: 16,
            label: "tile-0"
        ) {
            // no-op
        }

        XCTAssertEqual(metrics.stage, .entropyCoding)
        XCTAssertEqual(metrics.itemsProcessed, 16)
        XCTAssertEqual(metrics.label, "tile-0")
    }

    func testProfilerDisabledSkipsTiming() throws {
        let profiler = J2KPipelineProfiler(enabled: false)

        let metrics = profiler.measure(stage: .quantization) {
            // work
        }

        XCTAssertEqual(metrics.elapsedTime, 0)
    }

    func testProfilerRecordAndReport() throws {
        let profiler = J2KPipelineProfiler()

        profiler.profile(stage: .colorTransform) { /* work */ }
        profiler.profile(stage: .waveletTransform) { /* work */ }
        profiler.profile(stage: .quantization) { /* work */ }

        XCTAssertEqual(profiler.metricsCount, 3)

        let report = profiler.generateReport()
        XCTAssertEqual(report.metrics.count, 3)
        XCTAssertGreaterThanOrEqual(report.totalTime, 0)
        XCTAssertNotNil(report.bottleneck)
    }

    func testProfilerReset() throws {
        let profiler = J2KPipelineProfiler()
        profiler.profile(stage: .colorTransform) { /* work */ }
        XCTAssertEqual(profiler.metricsCount, 1)

        profiler.reset()
        XCTAssertEqual(profiler.metricsCount, 0)
    }

    func testProfileReportDescription() throws {
        let profiler = J2KPipelineProfiler()
        profiler.profile(stage: .waveletTransform) { /* work */ }

        let report = profiler.generateReport()
        let desc = report.description
        XCTAssertTrue(desc.contains("Pipeline Profile Report"))
        XCTAssertTrue(desc.contains("Wavelet Transform"))
    }

    func testProfilerMeasureThrowing() throws {
        let profiler = J2KPipelineProfiler()

        let metrics = try profiler.measureThrowing(stage: .fileIO) {
            // No-throw path
        }

        XCTAssertEqual(metrics.stage, .fileIO)
        XCTAssertGreaterThanOrEqual(metrics.elapsedTime, 0)
    }

    func testStageMetricsThroughput() throws {
        let metrics = J2KStageMetrics(
            stage: .entropyCoding,
            elapsedTime: 0.01,
            itemsProcessed: 100
        )

        XCTAssertEqual(metrics.throughput, 10000, accuracy: 1)
    }

    func testStageMetricsThroughputZeroTime() throws {
        let metrics = J2KStageMetrics(
            stage: .quantization,
            elapsedTime: 0,
            itemsProcessed: 10
        )

        XCTAssertEqual(metrics.throughput, 0)
    }

    func testReportTimeDistribution() throws {
        let profiler = J2KPipelineProfiler()
        profiler.profile(stage: .colorTransform) {
            var sum = 0
            for i in 0..<10000 { sum += i }
            _ = sum
        }
        profiler.profile(stage: .waveletTransform) {
            var sum = 0
            for i in 0..<10000 { sum += i }
            _ = sum
        }

        let report = profiler.generateReport()
        let distribution = report.timeDistribution

        // All fractions should sum to approximately 1.0
        let totalFraction = distribution.values.reduce(0, +)
        XCTAssertEqual(totalFraction, 1.0, accuracy: 0.01)
    }

    func testPipelineStageAllCases() throws {
        // Verify all pipeline stages are defined
        XCTAssertGreaterThanOrEqual(J2KPipelineStage.allCases.count, 8)
    }

    // MARK: - J2KArenaAllocator Tests

    func testArenaBasicAllocation() throws {
        let arena = J2KArenaAllocator(blockSize: 4096)

        let ptr1 = arena.allocate(byteCount: 64)
        let ptr2 = arena.allocate(byteCount: 128)

        // Pointers should be different
        XCTAssertNotEqual(ptr1, ptr2)

        // Write and read back
        ptr1.storeBytes(of: UInt64(42), as: UInt64.self)
        XCTAssertEqual(ptr1.load(as: UInt64.self), 42)
    }

    func testArenaMultipleBlocks() throws {
        let arena = J2KArenaAllocator(blockSize: 128)

        // Allocate more than one block's worth
        _ = arena.allocate(byteCount: 100)
        _ = arena.allocate(byteCount: 100) // Should trigger new block

        let stats = arena.statistics
        XCTAssertGreaterThanOrEqual(stats.blockCount, 2)
        XCTAssertEqual(stats.totalAllocated, 200)
    }

    func testArenaReset() throws {
        let arena = J2KArenaAllocator(blockSize: 4096)

        _ = arena.allocate(byteCount: 256)
        _ = arena.allocate(byteCount: 256)

        arena.reset()

        let stats = arena.statistics
        XCTAssertEqual(stats.totalAllocated, 0)
        XCTAssertEqual(stats.blockCount, 1) // Keeps first block
    }

    func testArenaLargeAllocation() throws {
        let arena = J2KArenaAllocator(blockSize: 256)

        // Allocate larger than block size
        let ptr = arena.allocate(byteCount: 1024)
        XCTAssertNotNil(ptr)

        let stats = arena.statistics
        XCTAssertGreaterThanOrEqual(stats.totalCapacity, 1024)
    }

    // MARK: - J2KScratchBuffers Tests

    func testScratchBuffersCreation() throws {
        let scratch = J2KScratchBuffers(tileWidth: 128, tileHeight: 128, componentCount: 3)

        XCTAssertEqual(scratch.tileWidth, 128)
        XCTAssertEqual(scratch.tileHeight, 128)
        XCTAssertEqual(scratch.componentCount, 3)
        XCTAssertGreaterThan(scratch.totalMemory, 0)
    }

    func testScratchBuffersDWT() throws {
        let scratch = J2KScratchBuffers(tileWidth: 64, tileHeight: 64)

        scratch.withDWTBuffer { buffer in
            XCTAssertGreaterThanOrEqual(buffer.count, 128) // max(64,64)*2
            buffer[0] = 1.0
            buffer[1] = 2.0
            XCTAssertEqual(buffer[0], 1.0)
            XCTAssertEqual(buffer[1], 2.0)
        }
    }

    func testScratchBuffersQuantization() throws {
        let scratch = J2KScratchBuffers(tileWidth: 32, tileHeight: 32)

        scratch.withQuantizationBuffer { buffer in
            XCTAssertGreaterThanOrEqual(buffer.count, 32 * 32)
            buffer[0] = 42
            XCTAssertEqual(buffer[0], 42)
        }
    }

    func testScratchBuffersTemp() throws {
        let scratch = J2KScratchBuffers(tileWidth: 16, tileHeight: 16, componentCount: 4)

        scratch.withTempBuffer { buffer in
            XCTAssertGreaterThanOrEqual(buffer.count, 16 * 16 * 4)
            buffer[0] = 0xFF
            XCTAssertEqual(buffer[0], 0xFF)
        }
    }

    // MARK: - J2KThreadPool Tests

    func testThreadPoolParallelMapEmpty() async throws {
        let pool = J2KThreadPool()
        let result: [Int] = try await pool.parallelMap([]) { $0 }
        XCTAssertTrue(result.isEmpty)
    }

    func testThreadPoolParallelMapSingle() async throws {
        let pool = J2KThreadPool()
        let result = try await pool.parallelMap([42]) { $0 * 2 }
        XCTAssertEqual(result, [84])
    }

    func testThreadPoolParallelMapMultiple() async throws {
        let pool = J2KThreadPool()
        let input = Array(0..<100)
        let result = try await pool.parallelMap(input) { $0 * 2 }

        XCTAssertEqual(result.count, 100)
        for (index, value) in result.enumerated() {
            XCTAssertEqual(value, index * 2, "Mismatch at index \(index)")
        }
    }

    func testThreadPoolParallelMapPreservesOrder() async throws {
        let pool = J2KThreadPool(configuration: J2KThreadPoolConfiguration(maxConcurrency: 4))
        let input = Array(0..<50)

        let result = try await pool.parallelMap(input) { value -> Int in
            // Vary processing time to test ordering
            var sum = 0
            let iterations = (value % 5 == 0) ? 10000 : 100
            for i in 0..<iterations { sum += i }
            _ = sum
            return value
        }

        XCTAssertEqual(result, input)
    }

    func testThreadPoolParallelMapWithError() async throws {
        let pool = J2KThreadPool()
        let input = Array(0..<10)

        do {
            _ = try await pool.parallelMap(input) { value -> Int in
                if value == 5 {
                    throw J2KError.internalError("Test error")
                }
                return value
            }
            XCTFail("Expected error to be thrown")
        } catch {
            // Expected
            XCTAssertTrue(error is J2KError)
        }
    }

    func testThreadPoolParallelForEach() async throws {
        let pool = J2KThreadPool()
        let input = Array(0..<20)

        // Use a simple side-effect-free operation for forEach
        try await pool.parallelForEach(input) { value in
            var sum = 0
            for i in 0..<value { sum += i }
            _ = sum
        }

        let stats = await pool.statistics
        XCTAssertEqual(stats.submitted, 20)
        XCTAssertEqual(stats.completed, 20)
    }

    func testThreadPoolStatistics() async throws {
        let pool = J2KThreadPool()
        _ = try await pool.parallelMap(Array(0..<10)) { $0 }

        let stats = await pool.statistics
        XCTAssertEqual(stats.submitted, 10)
        XCTAssertEqual(stats.completed, 10)
    }

    func testThreadPoolSingleConcurrency() async throws {
        let pool = J2KThreadPool(
            configuration: J2KThreadPoolConfiguration(maxConcurrency: 1)
        )
        let input = Array(0..<5)
        let result = try await pool.parallelMap(input) { $0 * 3 }
        XCTAssertEqual(result, [0, 3, 6, 9, 12])
    }

    func testThreadPoolResetStatistics() async throws {
        let pool = J2KThreadPool()
        _ = try await pool.parallelMap([1, 2, 3]) { $0 }

        await pool.resetStatistics()
        let stats = await pool.statistics
        XCTAssertEqual(stats.submitted, 0)
        XCTAssertEqual(stats.completed, 0)
    }

    // MARK: - J2KZeroCopyBuffer Tests

    func testZeroCopyBufferFromData() throws {
        let data = Data([1, 2, 3, 4, 5, 6, 7, 8])
        let buffer = J2KZeroCopyBuffer(data: data)

        XCTAssertEqual(buffer.count, 8)
    }

    func testZeroCopyBufferSlice() throws {
        let data = Data([10, 20, 30, 40, 50, 60])
        let buffer = J2KZeroCopyBuffer(data: data)

        let slice = buffer.slice(offset: 2, count: 3)
        XCTAssertNotNil(slice)

        slice?.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 30)
            XCTAssertEqual(ptr[1], 40)
            XCTAssertEqual(ptr[2], 50)
        }
    }

    func testZeroCopyBufferSliceOutOfBounds() throws {
        let data = Data([1, 2, 3])
        let buffer = J2KZeroCopyBuffer(data: data)

        let slice = buffer.slice(offset: 2, count: 5) // Exceeds bounds
        XCTAssertNil(slice)
    }

    func testZeroCopyBufferFullSlice() throws {
        let data = Data([1, 2, 3, 4])
        let buffer = J2KZeroCopyBuffer(data: data)

        let slice = buffer.fullSlice()
        XCTAssertEqual(slice.count, 4)

        slice.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 1)
            XCTAssertEqual(ptr[3], 4)
        }
    }

    func testZeroCopyBufferSubSlice() throws {
        let data = Data([10, 20, 30, 40, 50, 60, 70, 80])
        let buffer = J2KZeroCopyBuffer(data: data)

        let slice = buffer.slice(offset: 2, count: 4)! // [30, 40, 50, 60]
        let sub = slice.subSlice(offset: 1, count: 2)  // [40, 50]
        XCTAssertNotNil(sub)

        sub?.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 40)
            XCTAssertEqual(ptr[1], 50)
        }
    }

    func testZeroCopyBufferSubSliceOutOfBounds() throws {
        let data = Data([1, 2, 3])
        let buffer = J2KZeroCopyBuffer(data: data)

        let slice = buffer.slice(offset: 0, count: 3)!
        let sub = slice.subSlice(offset: 2, count: 5) // Exceeds bounds
        XCTAssertNil(sub)
    }

    func testZeroCopyBufferToData() throws {
        let original = Data([1, 2, 3, 4, 5])
        let buffer = J2KZeroCopyBuffer(data: original)

        let roundTripped = buffer.toData()
        XCTAssertEqual(roundTripped, original)
    }

    func testBufferSliceToData() throws {
        let data = Data([10, 20, 30, 40, 50])
        let buffer = J2KZeroCopyBuffer(data: data)

        let slice = buffer.slice(offset: 1, count: 3)!
        let sliceData = slice.toData()
        XCTAssertEqual(sliceData, Data([20, 30, 40]))
    }

    func testSharedBufferMultipleSlices() throws {
        let shared = J2KSharedBuffer(data: Data([0, 1, 2, 3, 4, 5, 6, 7]))

        let slice1 = shared.slice(offset: 0, count: 4)!
        let slice2 = shared.slice(offset: 4, count: 4)!

        slice1.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 0)
            XCTAssertEqual(ptr[3], 3)
        }

        slice2.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 4)
            XCTAssertEqual(ptr[3], 7)
        }
    }

    func testSharedBufferCapacity() throws {
        let shared = J2KSharedBuffer(capacity: 1024)
        XCTAssertEqual(shared.capacity, 1024)

        let slice = shared.fullSlice()
        XCTAssertEqual(slice.count, 1024)
    }

    func testZeroCopyBufferWithUnsafeBytes() throws {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let buffer = J2KZeroCopyBuffer(data: data)

        buffer.withUnsafeBytes { ptr in
            XCTAssertEqual(ptr[0], 0xDE)
            XCTAssertEqual(ptr[1], 0xAD)
            XCTAssertEqual(ptr[2], 0xBE)
            XCTAssertEqual(ptr[3], 0xEF)
        }
    }

    func testZeroCopyBufferFromCapacity() throws {
        let buffer = J2KZeroCopyBuffer(capacity: 512)
        XCTAssertEqual(buffer.count, 512)
    }
}
