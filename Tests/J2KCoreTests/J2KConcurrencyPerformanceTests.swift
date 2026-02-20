//
// J2KConcurrencyPerformanceTests.swift
// J2KSwift
//
// Week 240-241: Concurrency performance tuning tests.
// Tests concurrent vs serial encode/decode, scalability across core counts,
// memory pressure under high concurrency, and work-stealing patterns.
//

import XCTest
import Foundation
@testable import J2KCore

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
final class J2KConcurrencyPerformanceTests: XCTestCase {

    // MARK: - Concurrency Limits

    func testConcurrencyLimitsDefault() {
        let limits = J2KConcurrencyLimits.forSystem()
        XCTAssertGreaterThanOrEqual(limits.maxParallelism, 1)
        XCTAssertEqual(limits.maxMemoryBudget, 0)
        XCTAssertEqual(limits.minItemsPerTask, 1)
        XCTAssertTrue(limits.enableWorkStealing)
    }

    func testConcurrencyLimitsSerial() {
        let limits = J2KConcurrencyLimits.serial
        XCTAssertEqual(limits.maxParallelism, 1)
        XCTAssertFalse(limits.enableWorkStealing)
    }

    func testConcurrencyLimitsForCoreCount() {
        let limits2 = J2KConcurrencyLimits.forCoreCount(2)
        XCTAssertEqual(limits2.maxParallelism, 2)

        let limits8 = J2KConcurrencyLimits.forCoreCount(8)
        XCTAssertEqual(limits8.maxParallelism, 8)

        let limits16 = J2KConcurrencyLimits.forCoreCount(16)
        XCTAssertEqual(limits16.maxParallelism, 16)
    }

    func testConcurrencyLimitsClampMinimum() {
        let limits = J2KConcurrencyLimits(maxParallelism: -1)
        XCTAssertEqual(limits.maxParallelism, 1)

        let limits0 = J2KConcurrencyLimits(maxParallelism: 0)
        XCTAssertEqual(limits0.maxParallelism, 1)
    }

    func testConcurrencyLimitsCustom() {
        let limits = J2KConcurrencyLimits(
            maxParallelism: 4,
            maxMemoryBudget: 512 * 1024 * 1024,
            minItemsPerTask: 2,
            enableWorkStealing: false
        )
        XCTAssertEqual(limits.maxParallelism, 4)
        XCTAssertEqual(limits.maxMemoryBudget, 512 * 1024 * 1024)
        XCTAssertEqual(limits.minItemsPerTask, 2)
        XCTAssertFalse(limits.enableWorkStealing)
    }

    // MARK: - Actor Contention Metrics

    func testActorContentionMetricsProperties() {
        let metrics = J2KActorContentionMetrics(
            messageSends: 100,
            isolationCrossings: 20,
            contentionTime: 0.005,
            totalTime: 0.1,
            taskCount: 4,
            hotPaths: ["encoder.entropy", "decoder.wavelet"]
        )
        XCTAssertEqual(metrics.messageSends, 100)
        XCTAssertEqual(metrics.isolationCrossings, 20)
        XCTAssertEqual(metrics.taskCount, 4)
        XCTAssertEqual(metrics.contentionPercentage, 5.0, accuracy: 0.1)
        XCTAssertEqual(metrics.messagesPerTask, 25.0)
        XCTAssertEqual(metrics.averageContentionMicroseconds, 250.0, accuracy: 0.1)
        XCTAssertEqual(metrics.hotPaths.count, 2)
        XCTAssertFalse(metrics.description.isEmpty)
    }

    func testActorContentionMetricsZeroValues() {
        let metrics = J2KActorContentionMetrics(
            messageSends: 0,
            isolationCrossings: 0,
            contentionTime: 0,
            totalTime: 0,
            taskCount: 0,
            hotPaths: []
        )
        XCTAssertEqual(metrics.contentionPercentage, 0)
        XCTAssertEqual(metrics.messagesPerTask, 0)
        XCTAssertEqual(metrics.averageContentionMicroseconds, 0)
    }

    // MARK: - Actor Contention Analyser

    func testActorContentionAnalyzerLifecycle() async {
        let analyzer = J2KActorContentionAnalyzer()
        let isActive = await analyzer.isActive
        XCTAssertFalse(isActive)

        await analyzer.beginAnalysis()
        let isActiveAfterBegin = await analyzer.isActive
        XCTAssertTrue(isActiveAfterBegin)

        await analyzer.recordMessageSend(label: "test")
        await analyzer.recordIsolationCrossing(label: "crossing1", duration: 0.001)
        await analyzer.recordIsolationCrossing(label: "crossing2", duration: 0.002)

        let metrics = await analyzer.endAnalysis(taskCount: 2)
        XCTAssertEqual(metrics.messageSends, 1)
        XCTAssertEqual(metrics.isolationCrossings, 2)
        XCTAssertEqual(metrics.taskCount, 2)
        XCTAssertEqual(metrics.contentionTime, 0.003, accuracy: 0.0001)
        XCTAssertEqual(metrics.hotPaths.count, 3)

        let isActiveAfterEnd = await analyzer.isActive
        XCTAssertFalse(isActiveAfterEnd)
    }

    func testActorContentionAnalyzerIgnoresWhenInactive() async {
        let analyzer = J2KActorContentionAnalyzer()
        // Not started — messages should be ignored
        await analyzer.recordMessageSend(label: "ignored")
        await analyzer.recordIsolationCrossing(label: "ignored", duration: 0.5)

        let metrics = await analyzer.endAnalysis(taskCount: 1)
        XCTAssertEqual(metrics.messageSends, 0)
        XCTAssertEqual(metrics.isolationCrossings, 0)
    }

    // MARK: - Work-Stealing Queue

    func testWorkStealingQueueBasic() {
        let queue = J2KWorkStealingQueue(items: [1, 2, 3, 4, 5])
        XCTAssertEqual(queue.count, 5)
        XCTAssertFalse(queue.isEmpty)

        // takeOwn takes from front
        XCTAssertEqual(queue.takeOwn(), 1)
        // steal takes from back
        XCTAssertEqual(queue.steal(), 5)
        XCTAssertEqual(queue.count, 3)

        XCTAssertEqual(queue.takeOwn(), 2)
        XCTAssertEqual(queue.steal(), 4)
        XCTAssertEqual(queue.takeOwn(), 3)
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.takeOwn())
        XCTAssertNil(queue.steal())
    }

    func testWorkStealingQueueConcurrentAccess() {
        let queue = J2KWorkStealingQueue(items: Array(0..<100))
        let collector = ConcurrentResultCollector<Int>(capacity: 100)

        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            if let item = queue.takeOwn() {
                collector.append(item)
            } else if let item = queue.steal() {
                collector.append(item)
            }
        }

        let takenItems = collector.results
        // No item should be taken twice
        XCTAssertEqual(Set(takenItems).count, takenItems.count)
    }

    // MARK: - Concurrent Pipeline

    func testConcurrentPipelineEmptyInput() async throws {
        let pipeline = J2KConcurrentPipeline(limits: .forSystem())
        let result = try await pipeline.processParallel([Int]()) { $0 * 2 }
        XCTAssertTrue(result.results.isEmpty)
        XCTAssertEqual(result.concurrency, 0)
    }

    func testConcurrentPipelineSingleItem() async throws {
        let pipeline = J2KConcurrentPipeline(limits: .forSystem())
        let result = try await pipeline.processParallel([42]) { $0 * 2 }
        XCTAssertEqual(result.results, [84])
        XCTAssertEqual(result.concurrency, 1)
    }

    func testConcurrentPipelineSerialMode() async throws {
        let pipeline = J2KConcurrentPipeline(limits: .serial)
        let items = Array(1...20)
        let result = try await pipeline.processParallel(items) { $0 * 3 }
        XCTAssertEqual(result.results, items.map { $0 * 3 })
        XCTAssertEqual(result.concurrency, 1)
    }

    func testConcurrentPipelineParallelExecution() async throws {
        let pipeline = J2KConcurrentPipeline(limits: .forCoreCount(4))
        let items = Array(1...100)
        let result = try await pipeline.processParallel(items) { value -> Int in
            // Simulate some work
            var sum = 0
            for i in 0..<1000 {
                sum += i * value
            }
            return sum
        }
        // Verify correctness — results must be in input order
        for (index, value) in items.enumerated() {
            var expected = 0
            for i in 0..<1000 {
                expected += i * value
            }
            XCTAssertEqual(result.results[index], expected)
        }
        XCTAssertGreaterThan(result.concurrency, 1)
    }

    func testConcurrentPipelineWithWorkStealing() async throws {
        let limits = J2KConcurrencyLimits(
            maxParallelism: 4,
            enableWorkStealing: true
        )
        let pipeline = J2KConcurrentPipeline(limits: limits)
        // Use many items to trigger work-stealing path (items > maxConcurrency * 2)
        let items = Array(0..<100)
        let result = try await pipeline.processParallel(items) { value -> Int in
            // Simulate uneven workloads
            var sum = 0
            let iterations = (value % 10 + 1) * 100
            for i in 0..<iterations {
                sum += i
            }
            return sum
        }
        XCTAssertEqual(result.results.count, 100)
        XCTAssertGreaterThan(result.concurrency, 1)
    }

    func testConcurrentPipelineOrderPreservation() async throws {
        let pipeline = J2KConcurrentPipeline(limits: .forCoreCount(8))
        let items = Array(0..<50)
        let result = try await pipeline.processParallel(items) { value -> String in
            "item-\(value)"
        }
        for (index, value) in result.results.enumerated() {
            XCTAssertEqual(value, "item-\(index)")
        }
    }

    func testConcurrentPipelineErrorPropagation() async {
        let pipeline = J2KConcurrentPipeline(limits: .forCoreCount(4))
        let items = Array(0..<20)

        do {
            _ = try await pipeline.processParallel(items) { value -> Int in
                if value == 10 {
                    throw J2KError.invalidParameter("Test error at item 10")
                }
                return value
            }
            XCTFail("Expected error to be thrown")
        } catch {
            // Error should propagate
            XCTAssertTrue(error is J2KError)
        }
    }

    // MARK: - Scalability Tests

    func testConcurrencyBenchmarkComparison() async throws {
        let benchmark = J2KConcurrencyBenchmark()
        let items = Array(0..<50)

        let (serialTime, parallelTime, speedup) = try await benchmark.compareConcurrentVsSerial(
            items: items,
            iterations: 2,
            limits: .forCoreCount(2)
        ) { value -> Int in
            var sum = 0
            for i in 0..<5000 {
                sum += i * value
            }
            return sum
        }

        XCTAssertGreaterThan(serialTime, 0)
        XCTAssertGreaterThan(parallelTime, 0)
        XCTAssertGreaterThan(speedup, 0)
    }

    func testScalabilityMeasurement() async throws {
        let benchmark = J2KConcurrencyBenchmark()
        let items = Array(0..<40)

        let report = try await benchmark.measureScalability(
            items: items,
            coreCounts: [1, 2, 4],
            warmupIterations: 1
        ) { value -> Int in
            var sum = 0
            for i in 0..<5000 {
                sum += i * value
            }
            return sum
        }

        XCTAssertEqual(report.points.count, 3)
        XCTAssertEqual(report.itemCount, 40)
        XCTAssertGreaterThanOrEqual(report.peakSpeedup, 1.0)
        XCTAssertGreaterThanOrEqual(report.peakCoreCount, 1)
        XCTAssertFalse(report.description.isEmpty)

        // Serial (1 core) should have speedup ~1.0
        if let serialPoint = report.points.first(where: { $0.coreCount == 1 }) {
            XCTAssertEqual(serialPoint.speedup, 1.0, accuracy: 0.1)
        }
    }

    // MARK: - Memory Pressure Tests

    func testMemoryMonitorSnapshot() {
        let monitor = J2KConcurrencyMemoryMonitor()
        let snapshot = monitor.snapshot(activeTasks: 4)
        XCTAssertGreaterThanOrEqual(snapshot.residentMemory, 0)
        XCTAssertEqual(snapshot.activeTasks, 4)
    }

    func testMemoryMonitorMeasure() {
        let monitor = J2KConcurrencyMemoryMonitor()
        let delta = monitor.measureMemoryPressure(concurrency: 4) {
            // Allocate some memory
            var arrays: [[Int]] = []
            for i in 0..<10 {
                arrays.append(Array(repeating: i, count: 1000))
            }
            _ = arrays.count
        }
        // Delta should be non-negative
        XCTAssertGreaterThanOrEqual(delta, 0)
    }

    func testHighConcurrencyMemoryPressure() async throws {
        let pipeline = J2KConcurrentPipeline(limits: .forSystem())
        let items = Array(0..<50)

        let baselineMemory = J2KMemoryInfo.currentResidentMemory()
        let result = try await pipeline.processParallel(items) { value -> [Int] in
            // Each task allocates memory
            Array(repeating: value, count: 10_000)
        }
        let peakMemory = J2KMemoryInfo.currentResidentMemory()

        XCTAssertEqual(result.results.count, 50)
        // Memory should not be wildly out of control (just verify non-negative)
        XCTAssertGreaterThanOrEqual(peakMemory, 0)
        _ = baselineMemory // Used for measurement
    }

    // MARK: - Sendable Conformance

    func testConcurrencyLimitsSendable() {
        let _: any Sendable = J2KConcurrencyLimits.forSystem()
        let _: any Sendable = J2KConcurrencyLimits.serial
        XCTAssert(true, "J2KConcurrencyLimits is Sendable")
    }

    func testActorContentionMetricsSendable() {
        let _: any Sendable = J2KActorContentionMetrics(
            messageSends: 0,
            isolationCrossings: 0,
            contentionTime: 0,
            totalTime: 0,
            taskCount: 0,
            hotPaths: []
        )
        XCTAssert(true, "J2KActorContentionMetrics is Sendable")
    }

    func testConcurrentPipelineSendable() {
        let _: any Sendable = J2KConcurrentPipeline(limits: .forSystem())
        XCTAssert(true, "J2KConcurrentPipeline is Sendable")
    }

    func testConcurrencyBenchmarkSendable() {
        let _: any Sendable = J2KConcurrencyBenchmark()
        XCTAssert(true, "J2KConcurrencyBenchmark is Sendable")
    }

    func testMemoryMonitorSendable() {
        let _: any Sendable = J2KConcurrencyMemoryMonitor()
        XCTAssert(true, "J2KConcurrencyMemoryMonitor is Sendable")
    }
}
