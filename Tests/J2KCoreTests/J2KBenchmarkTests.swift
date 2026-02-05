import XCTest
@testable import J2KCore
import Foundation

/// A benchmarking harness for J2KSwift performance testing.
///
/// This harness provides utilities for measuring performance of various
/// J2KSwift operations, tracking results, and comparing against baselines.
///
/// ## Usage Example
///
/// ```swift
/// let benchmark = J2KBenchmark(name: "Buffer Allocation")
/// let result = await benchmark.measure(iterations: 100) {
///     _ = J2KBuffer(capacity: 1024)
/// }
/// print(result.summary)
/// ```
public struct J2KBenchmark: Sendable {
    /// The name of this benchmark.
    public let name: String
    
    /// Creates a new benchmark with the given name.
    ///
    /// - Parameter name: A descriptive name for the benchmark.
    public init(name: String) {
        self.name = name
    }
    
    /// Gets the current time in seconds.
    private static func currentTime() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }
    
    /// Measures the execution time of a synchronous operation.
    ///
    /// - Parameters:
    ///   - iterations: Number of times to run the operation.
    ///   - warmupIterations: Number of warmup iterations (default: 5).
    ///   - operation: The operation to measure.
    /// - Returns: Benchmark results with timing statistics.
    public func measure(
        iterations: Int,
        warmupIterations: Int = 5,
        operation: () -> Void
    ) -> BenchmarkResult {
        // Warmup
        for _ in 0..<warmupIterations {
            operation()
        }
        
        // Measurement
        var times: [TimeInterval] = []
        times.reserveCapacity(iterations)
        
        for _ in 0..<iterations {
            let start = Self.currentTime()
            operation()
            let end = Self.currentTime()
            times.append(end - start)
        }
        
        return BenchmarkResult(name: name, times: times)
    }
    
    /// Measures the execution time of a throwing operation.
    ///
    /// - Parameters:
    ///   - iterations: Number of times to run the operation.
    ///   - warmupIterations: Number of warmup iterations (default: 5).
    ///   - operation: The throwing operation to measure.
    /// - Returns: Benchmark results with timing statistics.
    /// - Throws: Any error thrown by the operation.
    public func measureThrowing(
        iterations: Int,
        warmupIterations: Int = 5,
        operation: () throws -> Void
    ) throws -> BenchmarkResult {
        // Warmup
        for _ in 0..<warmupIterations {
            try operation()
        }
        
        // Measurement
        var times: [TimeInterval] = []
        times.reserveCapacity(iterations)
        
        for _ in 0..<iterations {
            let start = Self.currentTime()
            try operation()
            let end = Self.currentTime()
            times.append(end - start)
        }
        
        return BenchmarkResult(name: name, times: times)
    }
    
    /// Measures the execution time of an async operation.
    ///
    /// - Parameters:
    ///   - iterations: Number of times to run the operation.
    ///   - warmupIterations: Number of warmup iterations (default: 5).
    ///   - operation: The async operation to measure.
    /// - Returns: Benchmark results with timing statistics.
    public func measureAsync(
        iterations: Int,
        warmupIterations: Int = 5,
        operation: @Sendable () async -> Void
    ) async -> BenchmarkResult {
        // Warmup
        for _ in 0..<warmupIterations {
            await operation()
        }
        
        // Measurement
        var times: [TimeInterval] = []
        times.reserveCapacity(iterations)
        
        for _ in 0..<iterations {
            let start = Self.currentTime()
            await operation()
            let end = Self.currentTime()
            times.append(end - start)
        }
        
        return BenchmarkResult(name: name, times: times)
    }
}

/// Results from a benchmark measurement.
public struct BenchmarkResult: Sendable, CustomStringConvertible {
    /// The name of the benchmark.
    public let name: String
    
    /// Individual timing measurements in seconds.
    public let times: [TimeInterval]
    
    /// The number of iterations.
    public var iterations: Int { times.count }
    
    /// The total time across all iterations.
    public var totalTime: TimeInterval { times.reduce(0, +) }
    
    /// The average time per iteration.
    public var averageTime: TimeInterval {
        guard !times.isEmpty else { return 0 }
        return totalTime / Double(times.count)
    }
    
    /// The minimum time across all iterations.
    public var minTime: TimeInterval {
        times.min() ?? 0
    }
    
    /// The maximum time across all iterations.
    public var maxTime: TimeInterval {
        times.max() ?? 0
    }
    
    /// The median time across all iterations.
    public var medianTime: TimeInterval {
        guard !times.isEmpty else { return 0 }
        let sorted = times.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[mid - 1] + sorted[mid]) / 2
        } else {
            return sorted[mid]
        }
    }
    
    /// The standard deviation of the times.
    public var standardDeviation: TimeInterval {
        guard times.count > 1 else { return 0 }
        let mean = averageTime
        let squaredDiffs = times.map { ($0 - mean) * ($0 - mean) }
        let variance = squaredDiffs.reduce(0, +) / Double(times.count - 1)
        return sqrt(variance)
    }
    
    /// Operations per second based on average time.
    public var operationsPerSecond: Double {
        guard averageTime > 0 else { return 0 }
        return 1.0 / averageTime
    }
    
    /// A summary string of the benchmark results.
    public var summary: String {
        let avgMs = averageTime * 1000
        let minMs = minTime * 1000
        let maxMs = maxTime * 1000
        let medMs = medianTime * 1000
        let stdMs = standardDeviation * 1000
        let ops = operationsPerSecond
        
        return """
        \(name):
          Iterations: \(iterations)
          Average:    \(String(format: "%.4f", avgMs)) ms
          Median:     \(String(format: "%.4f", medMs)) ms
          Min:        \(String(format: "%.4f", minMs)) ms
          Max:        \(String(format: "%.4f", maxMs)) ms
          Std Dev:    \(String(format: "%.4f", stdMs)) ms
          Ops/sec:    \(String(format: "%.2f", ops))
        """
    }
    
    public var description: String { summary }
    
    /// Compares this result against a baseline.
    ///
    /// - Parameter baseline: The baseline result to compare against.
    /// - Returns: A comparison result.
    public func compare(to baseline: BenchmarkResult) -> BenchmarkComparison {
        BenchmarkComparison(current: self, baseline: baseline)
    }
}

/// Comparison between two benchmark results.
public struct BenchmarkComparison: Sendable, CustomStringConvertible {
    /// The current benchmark result.
    public let current: BenchmarkResult
    
    /// The baseline benchmark result.
    public let baseline: BenchmarkResult
    
    /// The ratio of current to baseline average time (< 1 is faster).
    public var speedupRatio: Double {
        guard baseline.averageTime > 0 else { return 1.0 }
        return baseline.averageTime / current.averageTime
    }
    
    /// The percentage improvement (positive = faster).
    public var percentImprovement: Double {
        guard baseline.averageTime > 0 else { return 0 }
        return ((baseline.averageTime - current.averageTime) / baseline.averageTime) * 100
    }
    
    /// Whether the current result is faster than baseline.
    public var isFaster: Bool {
        current.averageTime < baseline.averageTime
    }
    
    /// Whether the current result is slower than baseline.
    public var isSlower: Bool {
        current.averageTime > baseline.averageTime
    }
    
    /// A summary of the comparison.
    public var summary: String {
        let direction = isFaster ? "faster" : (isSlower ? "slower" : "same")
        let change = abs(percentImprovement)
        return """
        Comparison: \(current.name) vs \(baseline.name)
          Speedup:    \(String(format: "%.2fx", speedupRatio))
          Change:     \(String(format: "%.1f%%", change)) \(direction)
          Current:    \(String(format: "%.4f", current.averageTime * 1000)) ms
          Baseline:   \(String(format: "%.4f", baseline.averageTime * 1000)) ms
        """
    }
    
    public var description: String { summary }
}

/// A benchmark runner that collects and reports multiple benchmark results.
public final class J2KBenchmarkRunner: @unchecked Sendable {
    /// Results collected by the runner.
    private var results: [BenchmarkResult] = []
    
    /// Lock for thread-safe access to results.
    private let lock = NSLock()
    
    /// Creates a new benchmark runner.
    public init() {}
    
    /// Adds a benchmark result.
    ///
    /// - Parameter result: The result to add.
    public func add(_ result: BenchmarkResult) {
        lock.lock()
        defer { lock.unlock() }
        results.append(result)
    }
    
    /// Gets all collected results.
    ///
    /// - Returns: Array of benchmark results.
    public func getResults() -> [BenchmarkResult] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
    
    /// Clears all collected results.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        results.removeAll()
    }
    
    /// Generates a full report of all benchmarks.
    ///
    /// - Returns: A formatted report string.
    public func report() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        guard !results.isEmpty else {
            return "No benchmark results collected."
        }
        
        var report = """
        ═══════════════════════════════════════════════════════════════
        J2KSwift Benchmark Report
        ═══════════════════════════════════════════════════════════════
        
        """
        
        for result in results {
            report += result.summary + "\n"
        }
        
        report += """
        ═══════════════════════════════════════════════════════════════
        """
        
        return report
    }
}

/// Memory benchmark utilities.
public struct J2KMemoryBenchmark: Sendable {
    /// Measures the memory used by an operation.
    ///
    /// Note: This is an approximation based on reported memory stats.
    /// On Linux, this uses /proc/self/statm. On other platforms, returns 0.
    ///
    /// - Parameters:
    ///   - operation: The operation to measure.
    /// - Returns: Approximate memory used in bytes.
    public static func measureMemory(operation: () -> Void) -> Int {
        // Get baseline memory
        let baselineMemory = getMemoryUsage()
        
        // Run operation
        operation()
        
        // Get peak memory
        let peakMemory = getMemoryUsage()
        
        return max(0, peakMemory - baselineMemory)
    }
    
    /// Gets current memory usage in bytes.
    private static func getMemoryUsage() -> Int {
        #if os(Linux)
        // On Linux, read from /proc/self/statm
        if let contents = try? String(contentsOfFile: "/proc/self/statm", encoding: .utf8) {
            let parts = contents.split(separator: " ")
            if let residentPages = Int(parts[1]) {
                // Multiply by page size (typically 4096)
                return residentPages * 4096
            }
        }
        return 0
        #else
        // On other platforms, return 0 (memory measurement not available)
        return 0
        #endif
    }
}

// MARK: - Benchmark Tests

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
