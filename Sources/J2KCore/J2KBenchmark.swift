//
// J2KBenchmark.swift
// J2KSwift
//
import Foundation

/// A benchmarking harness for J2KSwift performance testing.
///
/// This harness provides utilities for measuring performance of various
/// J2KSwift operations, tracking results, and comparing against baselines.
///
/// > Important: This is an **internal testing utility** of the J2KSwift library.
/// > It is exposed as `public` only for use in test targets and benchmarking tools.
/// > Direct use in production code is not recommended.
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
        if sorted.count.isMultiple(of: 2) {
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
///
/// `J2KBenchmarkRunner` uses actor isolation to provide thread-safe access
/// to its mutable state without manual locking.
public actor J2KBenchmarkRunner {
    /// Results collected by the runner.
    private var results: [BenchmarkResult] = []

    /// Creates a new benchmark runner.
    public init() {}

    /// Adds a benchmark result.
    ///
    /// - Parameter result: The result to add.
    public func add(_ result: BenchmarkResult) {
        results.append(result)
    }

    /// Gets all collected results.
    ///
    /// - Returns: Array of benchmark results.
    public func getResults() -> [BenchmarkResult] {
        results
    }

    /// Clears all collected results.
    public func clear() {
        results.removeAll()
    }

    /// Generates a full report of all benchmarks.
    ///
    /// - Returns: A formatted report string.
    public func report() -> String {
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
        J2KMemoryInfo.currentResidentMemory()
    }
}
