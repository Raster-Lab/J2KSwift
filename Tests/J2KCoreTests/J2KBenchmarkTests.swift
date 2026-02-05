import XCTest
@testable import J2KCore
import Foundation

/// Tests for the benchmarking harness.
final class J2KBenchmarkTests: XCTestCase {
    
    // MARK: - BenchmarkResult Tests
    
    func testBenchmarkResultStatistics() throws {
        let times: [TimeInterval] = [0.001, 0.002, 0.003, 0.004, 0.005]
        let result = BenchmarkResult(name: "Test", times: times)
        
        XCTAssertEqual(result.iterations, 5)
        XCTAssertEqual(result.totalTime, 0.015, accuracy: 0.0001)
        XCTAssertEqual(result.averageTime, 0.003, accuracy: 0.0001)
        XCTAssertEqual(result.minTime, 0.001, accuracy: 0.0001)
        XCTAssertEqual(result.maxTime, 0.005, accuracy: 0.0001)
        XCTAssertEqual(result.medianTime, 0.003, accuracy: 0.0001)
    }
    
    func testBenchmarkResultMedianOddCount() throws {
        let times: [TimeInterval] = [0.005, 0.001, 0.003]
        let result = BenchmarkResult(name: "Test", times: times)
        
        // Sorted: 0.001, 0.003, 0.005 - median is 0.003
        XCTAssertEqual(result.medianTime, 0.003, accuracy: 0.0001)
    }
    
    func testBenchmarkResultMedianEvenCount() throws {
        let times: [TimeInterval] = [0.001, 0.002, 0.003, 0.004]
        let result = BenchmarkResult(name: "Test", times: times)
        
        // Sorted: 0.001, 0.002, 0.003, 0.004 - median is (0.002 + 0.003) / 2 = 0.0025
        XCTAssertEqual(result.medianTime, 0.0025, accuracy: 0.0001)
    }
    
    func testBenchmarkResultStandardDeviation() throws {
        let times: [TimeInterval] = [0.001, 0.002, 0.003, 0.004, 0.005]
        let result = BenchmarkResult(name: "Test", times: times)
        
        // std dev of [1,2,3,4,5] / 1000 = sqrt(2.5) / 1000
        let expectedStdDev = sqrt(2.5) / 1000
        XCTAssertEqual(result.standardDeviation, expectedStdDev, accuracy: 0.0001)
    }
    
    func testBenchmarkResultOperationsPerSecond() throws {
        let times: [TimeInterval] = [0.001, 0.001, 0.001] // 1ms each
        let result = BenchmarkResult(name: "Test", times: times)
        
        // 1ms average = 1000 ops/sec
        XCTAssertEqual(result.operationsPerSecond, 1000, accuracy: 1)
    }
    
    func testBenchmarkResultSummary() throws {
        let times: [TimeInterval] = [0.001]
        let result = BenchmarkResult(name: "Test", times: times)
        
        let summary = result.summary
        XCTAssertTrue(summary.contains("Test:"))
        XCTAssertTrue(summary.contains("Iterations: 1"))
        XCTAssertTrue(summary.contains("Average:"))
    }
    
    func testBenchmarkResultEmptyTimes() throws {
        let result = BenchmarkResult(name: "Empty", times: [])
        
        XCTAssertEqual(result.iterations, 0)
        XCTAssertEqual(result.totalTime, 0)
        XCTAssertEqual(result.averageTime, 0)
        XCTAssertEqual(result.minTime, 0)
        XCTAssertEqual(result.maxTime, 0)
        XCTAssertEqual(result.medianTime, 0)
        XCTAssertEqual(result.standardDeviation, 0)
    }
    
    // MARK: - BenchmarkComparison Tests
    
    func testBenchmarkComparison() throws {
        let baseline = BenchmarkResult(name: "Baseline", times: [0.002])
        let current = BenchmarkResult(name: "Current", times: [0.001])
        
        let comparison = current.compare(to: baseline)
        
        XCTAssertTrue(comparison.isFaster)
        XCTAssertFalse(comparison.isSlower)
        XCTAssertEqual(comparison.speedupRatio, 2.0, accuracy: 0.01)
        XCTAssertEqual(comparison.percentImprovement, 50.0, accuracy: 0.1)
    }
    
    func testBenchmarkComparisonSlower() throws {
        let baseline = BenchmarkResult(name: "Baseline", times: [0.001])
        let current = BenchmarkResult(name: "Current", times: [0.002])
        
        let comparison = current.compare(to: baseline)
        
        XCTAssertFalse(comparison.isFaster)
        XCTAssertTrue(comparison.isSlower)
        XCTAssertEqual(comparison.speedupRatio, 0.5, accuracy: 0.01)
    }
    
    func testBenchmarkComparisonSummary() throws {
        let baseline = BenchmarkResult(name: "Baseline", times: [0.002])
        let current = BenchmarkResult(name: "Current", times: [0.001])
        
        let comparison = current.compare(to: baseline)
        let summary = comparison.summary
        
        XCTAssertTrue(summary.contains("Comparison:"))
        XCTAssertTrue(summary.contains("Speedup:"))
        XCTAssertTrue(summary.contains("faster"))
    }
    
    // MARK: - J2KBenchmark Tests
    
    func testBenchmarkMeasure() throws {
        let benchmark = J2KBenchmark(name: "Simple Allocation")
        
        let result = benchmark.measure(iterations: 10, warmupIterations: 2) {
            _ = J2KBuffer(capacity: 1024)
        }
        
        XCTAssertEqual(result.name, "Simple Allocation")
        XCTAssertEqual(result.iterations, 10)
        XCTAssertGreaterThan(result.averageTime, 0)
    }
    
    func testBenchmarkMeasureThrowing() throws {
        let benchmark = J2KBenchmark(name: "Throwing Operation")
        
        let result = try benchmark.measureThrowing(iterations: 5) {
            var reader = J2KBitReader(data: Data([0x01, 0x02, 0x03]))
            _ = try reader.readUInt8()
        }
        
        XCTAssertEqual(result.iterations, 5)
        XCTAssertGreaterThan(result.averageTime, 0)
    }
    
    func testBenchmarkMeasureAsync() async throws {
        let benchmark = J2KBenchmark(name: "Async Operation")
        
        let result = await benchmark.measureAsync(iterations: 5) {
            // Simulate async work
            let pool = J2KMemoryPool()
            let buffer = await pool.acquire(capacity: 1024)
            await pool.release(buffer)
        }
        
        XCTAssertEqual(result.iterations, 5)
        XCTAssertGreaterThan(result.averageTime, 0)
    }
    
    // MARK: - J2KBenchmarkRunner Tests
    
    func testBenchmarkRunner() throws {
        let runner = J2KBenchmarkRunner()
        
        let result1 = BenchmarkResult(name: "Test1", times: [0.001])
        let result2 = BenchmarkResult(name: "Test2", times: [0.002])
        
        runner.add(result1)
        runner.add(result2)
        
        let results = runner.getResults()
        XCTAssertEqual(results.count, 2)
        
        let report = runner.report()
        XCTAssertTrue(report.contains("Test1"))
        XCTAssertTrue(report.contains("Test2"))
        XCTAssertTrue(report.contains("Benchmark Report"))
    }
    
    func testBenchmarkRunnerClear() throws {
        let runner = J2KBenchmarkRunner()
        runner.add(BenchmarkResult(name: "Test", times: [0.001]))
        
        XCTAssertEqual(runner.getResults().count, 1)
        
        runner.clear()
        
        XCTAssertEqual(runner.getResults().count, 0)
    }
    
    func testBenchmarkRunnerEmptyReport() throws {
        let runner = J2KBenchmarkRunner()
        let report = runner.report()
        
        XCTAssertTrue(report.contains("No benchmark results"))
    }
    
    // MARK: - Performance Benchmark Tests
    
    func testBufferAllocationPerformance() throws {
        let benchmark = J2KBenchmark(name: "Buffer Allocation (1KB)")
        
        let result = benchmark.measure(iterations: 100) {
            _ = J2KBuffer(capacity: 1024)
        }
        
        // Just verify it ran successfully
        XCTAssertEqual(result.iterations, 100)
        XCTAssertGreaterThan(result.operationsPerSecond, 0)
    }
    
    func testImageBufferAllocationPerformance() throws {
        let benchmark = J2KBenchmark(name: "ImageBuffer Allocation (256x256)")
        
        let result = benchmark.measure(iterations: 50) {
            _ = J2KImageBuffer(width: 256, height: 256, bitDepth: 8)
        }
        
        XCTAssertEqual(result.iterations, 50)
        XCTAssertGreaterThan(result.operationsPerSecond, 0)
    }
    
    func testBitReaderPerformance() throws {
        let data = Data(repeating: 0x42, count: 1024)
        let benchmark = J2KBenchmark(name: "BitReader (1KB read)")
        
        let result = try benchmark.measureThrowing(iterations: 100) {
            var reader = J2KBitReader(data: data)
            while !reader.isAtEnd {
                _ = try reader.readUInt8()
            }
        }
        
        XCTAssertEqual(result.iterations, 100)
        XCTAssertGreaterThan(result.operationsPerSecond, 0)
    }
    
    func testBitWriterPerformance() throws {
        let benchmark = J2KBenchmark(name: "BitWriter (1KB write)")
        
        let result = benchmark.measure(iterations: 100) {
            var writer = J2KBitWriter()
            for _ in 0..<1024 {
                writer.writeUInt8(0x42)
            }
        }
        
        XCTAssertEqual(result.iterations, 100)
        XCTAssertGreaterThan(result.operationsPerSecond, 0)
    }
    
    func testImageBufferCopyOnWritePerformance() throws {
        let benchmark = J2KBenchmark(name: "ImageBuffer COW")
        
        let original = J2KImageBuffer(width: 1024, height: 1024, bitDepth: 8)
        
        let result = benchmark.measure(iterations: 1000) {
            var copy = original
            copy.setPixel(at: 0, value: 255) // Trigger COW
        }
        
        XCTAssertEqual(result.iterations, 1000)
    }
    
    func testMemoryPoolPerformance() async throws {
        let benchmark = J2KBenchmark(name: "MemoryPool Acquire/Release")
        let pool = J2KMemoryPool()
        
        let result = await benchmark.measureAsync(iterations: 100) {
            let buffer = await pool.acquire(capacity: 4096)
            await pool.release(buffer)
        }
        
        XCTAssertEqual(result.iterations, 100)
        XCTAssertGreaterThan(result.operationsPerSecond, 0)
    }
}
