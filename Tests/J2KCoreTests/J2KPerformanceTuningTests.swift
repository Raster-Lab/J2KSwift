//
// J2KPerformanceTuningTests.swift
// J2KSwift
//
import XCTest
@testable import J2KCore
import Foundation

/// Tests for the pipeline profiler, optimized allocator, thread pool, and zero-copy buffer.
final class J2KPerformanceTuningTests: XCTestCase {
    // MARK: - J2KPipelineProfiler Tests

    func testProfilerMeasureRecordsTiming() async throws {
        let profiler = J2KPipelineProfiler()

        let metrics = await profiler.measure(stage: .waveletTransform) {
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

    func testProfilerMeasureWithLabel() async throws {
        let profiler = J2KPipelineProfiler()

        let metrics = await profiler.measure(
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

    func testProfilerDisabledSkipsTiming() async throws {
        let profiler = J2KPipelineProfiler(enabled: false)

        let metrics = await profiler.measure(stage: .quantization) {
            // work
        }

        XCTAssertEqual(metrics.elapsedTime, 0)
    }

    func testProfilerRecordAndReport() async throws {
        let profiler = J2KPipelineProfiler()

        await profiler.profile(stage: .colorTransform) { /* work */ }
        await profiler.profile(stage: .waveletTransform) { /* work */ }
        await profiler.profile(stage: .quantization) { /* work */ }

        let count = await profiler.metricsCount
        XCTAssertEqual(count, 3)

        let report = await profiler.generateReport()
        XCTAssertEqual(report.metrics.count, 3)
        XCTAssertGreaterThanOrEqual(report.totalTime, 0)
        XCTAssertNotNil(report.bottleneck)
    }

    func testProfilerReset() async throws {
        let profiler = J2KPipelineProfiler()
        await profiler.profile(stage: .colorTransform) { /* work */ }
        let count1 = await profiler.metricsCount
        XCTAssertEqual(count1, 1)

        await profiler.reset()
        let count2 = await profiler.metricsCount
        XCTAssertEqual(count2, 0)
    }

    func testProfileReportDescription() async throws {
        let profiler = J2KPipelineProfiler()
        await profiler.profile(stage: .waveletTransform) { /* work */ }

        let report = await profiler.generateReport()
        let desc = report.description
        XCTAssertTrue(desc.contains("Pipeline Profile Report"))
        XCTAssertTrue(desc.contains("Wavelet Transform"))
    }

    func testProfilerMeasureThrowing() async throws {
        let profiler = J2KPipelineProfiler()

        let metrics = try await profiler.measureThrowing(stage: .fileIO) {
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

    func testReportTimeDistribution() async throws {
        let profiler = J2KPipelineProfiler()
        await profiler.profile(stage: .colorTransform) {
            var sum = 0
            for i in 0..<10000 { sum += i }
            _ = sum
        }
        await profiler.profile(stage: .waveletTransform) {
            var sum = 0
            for i in 0..<10000 { sum += i }
            _ = sum
        }

        let report = await profiler.generateReport()
        let distribution = report.timeDistribution

        // All fractions should sum to approximately 1.0
        let totalFraction = distribution.values.reduce(0, +)
        XCTAssertEqual(totalFraction, 1.0, accuracy: 0.01)
    }

    func testPipelineStageAllCases() throws {
        // Verify all pipeline stages are defined
        XCTAssertGreaterThanOrEqual(J2KPipelineStage.allCases.count, 8)
    }
}
