import Foundation

/// A framework for benchmarking J2KSwift components against reference implementations.
///
/// This framework provides infrastructure for comparing J2KSwift performance against
/// reference JPEG 2000 implementations like OpenJPEG. It focuses on standardized test
/// cases that can be reproduced across implementations.
///
/// ## Usage
///
/// ```swift
/// let benchmark = J2KReferenceBenchmark(
///     component: .entropyEncoding,
///     testCase: .uniformPattern1K
/// )
///
/// let result = try await benchmark.measureJ2KSwift {
///     // J2KSwift operation
/// }
///
/// print(result.formattedComparison())
/// ```
public struct J2KReferenceBenchmark: Sendable {
    /// The JPEG 2000 component being benchmarked.
    public enum Component: String, Sendable {
        case entropyEncoding = "Entropy Encoding (MQ-Coder)"
        case entropyDecoding = "Entropy Decoding (MQ-Coder)"
        case dwtForward = "DWT Forward Transform"
        case dwtInverse = "DWT Inverse Transform"
        case quantization = "Quantization"
        case dequantization = "Dequantization"
        case colorTransformRCT = "Color Transform (RCT)"
        case colorTransformICT = "Color Transform (ICT)"
        case tier2Encoding = "Tier-2 Encoding"
        case tier2Decoding = "Tier-2 Decoding"
        case fullPipeline = "Full Encoding Pipeline"
    }
    
    /// Standard test cases for reproducible benchmarking.
    public enum TestCase: String, Sendable {
        // Small test cases (1K-10K operations)
        case uniformPattern1K = "Uniform Pattern (1K)"
        case randomPattern1K = "Random Pattern (1K)"
        case skewedPattern1K = "Skewed Pattern (1K)"
        case uniformPattern10K = "Uniform Pattern (10K)"
        case randomPattern10K = "Random Pattern (10K)"
        
        // Medium test cases (100K operations)
        case uniformPattern100K = "Uniform Pattern (100K)"
        case randomPattern100K = "Random Pattern (100K)"
        
        // Image test cases
        case image512x512RGB = "512x512 RGB Image"
        case image1024x1024RGB = "1024x1024 RGB Image"
        case image2048x2048RGB = "2048x2048 RGB Image"
        case image4096x4096RGB = "4096x4096 RGB Image"
        
        // Tile test cases
        case tile256x256 = "256x256 Tile"
        case tile512x512 = "512x512 Tile"
    }
    
    /// The component being benchmarked.
    public let component: Component
    
    /// The test case being used.
    public let testCase: TestCase
    
    /// Number of iterations for measurement (default: 100).
    public let iterations: Int
    
    /// Number of warmup iterations (default: 5).
    public let warmupIterations: Int
    
    /// Creates a new reference benchmark.
    ///
    /// - Parameters:
    ///   - component: The JPEG 2000 component to benchmark.
    ///   - testCase: The standardized test case to use.
    ///   - iterations: Number of measurement iterations (default: 100).
    ///   - warmupIterations: Number of warmup iterations (default: 5).
    public init(
        component: Component,
        testCase: TestCase,
        iterations: Int = 100,
        warmupIterations: Int = 5
    ) {
        self.component = component
        self.testCase = testCase
        self.iterations = iterations
        self.warmupIterations = warmupIterations
    }
    
    /// Measures the performance of a J2KSwift operation.
    ///
    /// - Parameter operation: The operation to measure.
    /// - Returns: A result containing timing statistics.
    public func measureJ2KSwift(operation: () -> Void) -> ReferenceBenchmarkResult {
        let benchmark = J2KBenchmark(name: "\(component.rawValue) - \(testCase.rawValue)")
        let result = benchmark.measure(
            iterations: iterations,
            warmupIterations: warmupIterations,
            operation: operation
        )
        
        return ReferenceBenchmarkResult(
            component: component,
            testCase: testCase,
            implementation: "J2KSwift",
            averageTime: result.averageTime,
            medianTime: result.medianTime,
            minTime: result.minTime,
            maxTime: result.maxTime,
            standardDeviation: result.standardDeviation,
            throughput: result.operationsPerSecond
        )
    }
    
    /// Measures the performance of a throwing J2KSwift operation.
    ///
    /// - Parameter operation: The throwing operation to measure.
    /// - Returns: A result containing timing statistics.
    /// - Throws: Any error thrown by the operation.
    public func measureJ2KSwiftThrowing(operation: () throws -> Void) throws -> ReferenceBenchmarkResult {
        let benchmark = J2KBenchmark(name: "\(component.rawValue) - \(testCase.rawValue)")
        let result = try benchmark.measureThrowing(
            iterations: iterations,
            warmupIterations: warmupIterations,
            operation: operation
        )
        
        return ReferenceBenchmarkResult(
            component: component,
            testCase: testCase,
            implementation: "J2KSwift",
            averageTime: result.averageTime,
            medianTime: result.medianTime,
            minTime: result.minTime,
            maxTime: result.maxTime,
            standardDeviation: result.standardDeviation,
            throughput: result.operationsPerSecond
        )
    }
    
    /// Measures the performance of an async J2KSwift operation.
    ///
    /// - Parameter operation: The async operation to measure.
    /// - Returns: A result containing timing statistics.
    public func measureJ2KSwiftAsync(operation: @escaping @Sendable () async -> Void) async -> ReferenceBenchmarkResult {
        let benchmark = J2KBenchmark(name: "\(component.rawValue) - \(testCase.rawValue)")
        let result = await benchmark.measureAsync(
            iterations: iterations,
            warmupIterations: warmupIterations,
            operation: operation
        )
        
        return ReferenceBenchmarkResult(
            component: component,
            testCase: testCase,
            implementation: "J2KSwift",
            averageTime: result.averageTime,
            medianTime: result.medianTime,
            minTime: result.minTime,
            maxTime: result.maxTime,
            standardDeviation: result.standardDeviation,
            throughput: result.operationsPerSecond
        )
    }
}

/// Results from a reference benchmark comparison.
public struct ReferenceBenchmarkResult: Sendable {
    /// The component that was benchmarked.
    public let component: J2KReferenceBenchmark.Component
    
    /// The test case that was used.
    public let testCase: J2KReferenceBenchmark.TestCase
    
    /// The implementation name (e.g., "J2KSwift", "OpenJPEG").
    public let implementation: String
    
    /// Average execution time in seconds.
    public let averageTime: TimeInterval
    
    /// Median execution time in seconds.
    public let medianTime: TimeInterval
    
    /// Minimum execution time in seconds.
    public let minTime: TimeInterval
    
    /// Maximum execution time in seconds.
    public let maxTime: TimeInterval
    
    /// Standard deviation of execution times.
    public let standardDeviation: TimeInterval
    
    /// Throughput in operations per second.
    public let throughput: Double
    
    /// Performance relative to a baseline (1.0 = same, 2.0 = 2x faster, 0.5 = 2x slower).
    public var relativePerformance: Double?
    
    /// Creates a new reference benchmark result.
    public init(
        component: J2KReferenceBenchmark.Component,
        testCase: J2KReferenceBenchmark.TestCase,
        implementation: String,
        averageTime: TimeInterval,
        medianTime: TimeInterval,
        minTime: TimeInterval,
        maxTime: TimeInterval,
        standardDeviation: TimeInterval,
        throughput: Double,
        relativePerformance: Double? = nil
    ) {
        self.component = component
        self.testCase = testCase
        self.implementation = implementation
        self.averageTime = averageTime
        self.medianTime = medianTime
        self.minTime = minTime
        self.maxTime = maxTime
        self.standardDeviation = standardDeviation
        self.throughput = throughput
        self.relativePerformance = relativePerformance
    }
    
    /// Returns a formatted string with benchmark results.
    public var formattedSummary: String {
        var lines: [String] = []
        lines.append("Benchmark: \(component.rawValue) - \(testCase.rawValue)")
        lines.append("Implementation: \(implementation)")
        lines.append(String(format: "Average Time: %.3f ms", averageTime * 1000))
        lines.append(String(format: "Median Time:  %.3f ms", medianTime * 1000))
        lines.append(String(format: "Min Time:     %.3f ms", minTime * 1000))
        lines.append(String(format: "Max Time:     %.3f ms", maxTime * 1000))
        lines.append(String(format: "Std Dev:      %.3f ms", standardDeviation * 1000))
        lines.append(String(format: "Throughput:   %.0f ops/sec", throughput))
        
        if let relative = relativePerformance {
            let percentage = (relative - 1.0) * 100
            let direction = relative >= 1.0 ? "faster" : "slower"
            let multiplier = relative >= 1.0 ? relative : 1.0 / relative
            lines.append(String(format: "Relative:     %.1fx %@ (%.1f%%)", multiplier, direction, abs(percentage)))
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Compares this result with another to compute relative performance.
    ///
    /// - Parameter other: The baseline result to compare against.
    /// - Returns: A new result with relative performance computed.
    public func compared(to other: ReferenceBenchmarkResult) -> ReferenceBenchmarkResult {
        let relative = other.averageTime / self.averageTime
        return ReferenceBenchmarkResult(
            component: component,
            testCase: testCase,
            implementation: implementation,
            averageTime: averageTime,
            medianTime: medianTime,
            minTime: minTime,
            maxTime: maxTime,
            standardDeviation: standardDeviation,
            throughput: throughput,
            relativePerformance: relative
        )
    }
}

/// A collection of reference benchmark results for easy comparison.
public struct ReferenceBenchmarkSuite: Sendable {
    /// All benchmark results in this suite.
    public let results: [ReferenceBenchmarkResult]
    
    /// Creates a new benchmark suite.
    ///
    /// - Parameter results: The benchmark results to include.
    public init(results: [ReferenceBenchmarkResult]) {
        self.results = results
    }
    
    /// Returns a formatted comparison table.
    public var formattedComparison: String {
        guard !results.isEmpty else {
            return "No benchmark results available."
        }
        
        var lines: [String] = []
        lines.append("=" * 80)
        lines.append("J2KSwift Reference Benchmark Suite")
        lines.append("=" * 80)
        lines.append("")
        
        // Group by component
        let grouped = Dictionary(grouping: results) { $0.component }
        
        for (component, componentResults) in grouped.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            lines.append("\(component.rawValue)")
            lines.append("-" * 80)
            
            for result in componentResults {
                lines.append("")
                lines.append("Test Case: \(result.testCase.rawValue)")
                lines.append(String(format: "  Average: %.3f ms (%.0f ops/sec)", 
                                  result.averageTime * 1000, result.throughput))
                
                if let relative = result.relativePerformance {
                    let multiplier = relative >= 1.0 ? relative : 1.0 / relative
                    let direction = relative >= 1.0 ? "faster" : "slower"
                    lines.append(String(format: "  Relative: %.2fx %@ than baseline", multiplier, direction))
                }
            }
            
            lines.append("")
        }
        
        lines.append("=" * 80)
        return lines.joined(separator: "\n")
    }
    
    /// Exports results to CSV format.
    public var csvExport: String {
        var lines: [String] = []
        lines.append("Component,TestCase,Implementation,AvgTime(ms),MedianTime(ms),MinTime(ms),MaxTime(ms),StdDev(ms),Throughput(ops/sec),RelativePerf")
        
        for result in results {
            let relativeStr = result.relativePerformance.map { String(format: "%.3f", $0) } ?? ""
            lines.append([
                result.component.rawValue,
                result.testCase.rawValue,
                result.implementation,
                String(format: "%.6f", result.averageTime * 1000),
                String(format: "%.6f", result.medianTime * 1000),
                String(format: "%.6f", result.minTime * 1000),
                String(format: "%.6f", result.maxTime * 1000),
                String(format: "%.6f", result.standardDeviation * 1000),
                String(format: "%.2f", result.throughput),
                relativeStr
            ].joined(separator: ","))
        }
        
        return lines.joined(separator: "\n")
    }
}

// MARK: - Helper

private func * (lhs: String, rhs: Int) -> String {
    String(repeating: lhs, count: rhs)
}
