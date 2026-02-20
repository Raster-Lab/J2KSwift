//
// J2KConcurrencyTuning.swift
// J2KSwift
//
// Concurrency performance tuning infrastructure for JPEG 2000 pipelines.
//
// Week 240-241: Actor contention analysis, parallel pipeline design,
// configurable concurrency limits, and work-stealing patterns.
//

import Foundation
import Synchronization

// MARK: - Concurrency Limits

/// Configuration for controlling concurrency in JPEG 2000 pipelines.
///
/// `J2KConcurrencyLimits` provides configurable limits that respect
/// system resources and prevent over-subscription of CPU and memory.
///
/// Example:
/// ```swift
/// let limits = J2KConcurrencyLimits.forSystem()
/// print("Max parallelism: \(limits.maxParallelism)")
/// ```
public struct J2KConcurrencyLimits: Sendable {
    /// Maximum number of concurrent tasks.
    public let maxParallelism: Int

    /// Maximum memory budget in bytes (0 = unlimited).
    public let maxMemoryBudget: Int

    /// Minimum items per task for parallelism to be worthwhile.
    public let minItemsPerTask: Int

    /// Whether to enable work-stealing for uneven workloads.
    public let enableWorkStealing: Bool

    /// Creates custom concurrency limits.
    ///
    /// - Parameters:
    ///   - maxParallelism: Maximum parallel tasks (default: system processor count).
    ///   - maxMemoryBudget: Maximum memory in bytes (default: 0 = unlimited).
    ///   - minItemsPerTask: Minimum items per task (default: 1).
    ///   - enableWorkStealing: Enable work-stealing (default: true).
    public init(
        maxParallelism: Int = ProcessInfo.processInfo.activeProcessorCount,
        maxMemoryBudget: Int = 0,
        minItemsPerTask: Int = 1,
        enableWorkStealing: Bool = true
    ) {
        self.maxParallelism = max(1, maxParallelism)
        self.maxMemoryBudget = max(0, maxMemoryBudget)
        self.minItemsPerTask = max(1, minItemsPerTask)
        self.enableWorkStealing = enableWorkStealing
    }

    /// Creates limits optimized for the current system.
    ///
    /// Automatically detects processor count and adjusts parallelism
    /// to avoid over-subscription.
    ///
    /// - Returns: System-optimized concurrency limits.
    public static func forSystem() -> J2KConcurrencyLimits {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        return J2KConcurrencyLimits(
            maxParallelism: cores,
            maxMemoryBudget: 0,
            minItemsPerTask: 1,
            enableWorkStealing: true
        )
    }

    /// Creates limits for a specific core count (useful for testing).
    ///
    /// - Parameter coreCount: Simulated core count.
    /// - Returns: Limits configured for the specified core count.
    public static func forCoreCount(_ coreCount: Int) -> J2KConcurrencyLimits {
        J2KConcurrencyLimits(
            maxParallelism: max(1, coreCount),
            maxMemoryBudget: 0,
            minItemsPerTask: 1,
            enableWorkStealing: true
        )
    }

    /// Serial execution limits (no parallelism).
    public static let serial = J2KConcurrencyLimits(
        maxParallelism: 1,
        maxMemoryBudget: 0,
        minItemsPerTask: 1,
        enableWorkStealing: false
    )
}

// MARK: - Actor Contention Metrics

/// Metrics for analysing actor contention in concurrent pipelines.
///
/// Tracks message-passing overhead, isolation crossings, and contention
/// hotspots to guide optimization of actor boundaries.
public struct J2KActorContentionMetrics: Sendable, CustomStringConvertible {
    /// Total number of actor message sends.
    public let messageSends: Int

    /// Total number of isolation boundary crossings.
    public let isolationCrossings: Int

    /// Total time spent waiting for actor access in seconds.
    public let contentionTime: TimeInterval

    /// Total wall-clock time of the measured operation in seconds.
    public let totalTime: TimeInterval

    /// Number of tasks that ran during measurement.
    public let taskCount: Int

    /// Labels for hot-path segments.
    public let hotPaths: [String]

    /// Percentage of time spent in contention.
    public var contentionPercentage: Double {
        guard totalTime > 0 else { return 0 }
        return (contentionTime / totalTime) * 100
    }

    /// Average messages per task.
    public var messagesPerTask: Double {
        guard taskCount > 0 else { return 0 }
        return Double(messageSends) / Double(taskCount)
    }

    /// Average contention time per crossing in microseconds.
    public var averageContentionMicroseconds: Double {
        guard isolationCrossings > 0 else { return 0 }
        return (contentionTime / Double(isolationCrossings)) * 1_000_000
    }

    public var description: String {
        """
        Actor Contention Analysis:
          Message sends:        \(messageSends)
          Isolation crossings:  \(isolationCrossings)
          Contention time:      \(String(format: "%.4f", contentionTime * 1000)) ms (\(String(format: "%.1f", contentionPercentage))%)
          Total time:           \(String(format: "%.4f", totalTime * 1000)) ms
          Tasks:                \(taskCount)
          Avg contention/cross: \(String(format: "%.2f", averageContentionMicroseconds)) µs
          Hot paths:            \(hotPaths.isEmpty ? "none" : hotPaths.joined(separator: ", "))
        """
    }
}

// MARK: - Actor Contention Analyzer

/// Analyzes actor contention to identify message-passing overhead and hot paths.
///
/// `J2KActorContentionAnalyzer` instruments concurrent operations to measure
/// isolation crossings and identify bottlenecks in actor-based pipelines.
///
/// Example:
/// ```swift
/// let analyzer = J2KActorContentionAnalyzer()
/// await analyzer.beginAnalysis()
/// // ... perform concurrent operations ...
/// await analyzer.recordIsolationCrossing(label: "encoder.entropy")
/// let metrics = await analyzer.endAnalysis(taskCount: 8)
/// print(metrics)
/// ```
public actor J2KActorContentionAnalyzer {
    private var analysisStartTime: TimeInterval = 0
    private var messageSendCount: Int = 0
    private var isolationCrossingCount: Int = 0
    private var contentionDuration: TimeInterval = 0
    private var hotPathLabels: [String] = []
    private var isAnalysing: Bool = false

    /// Creates a new contention analyzer.
    public init() {}

    /// Begins a new contention analysis session.
    public func beginAnalysis() {
        analysisStartTime = ProcessInfo.processInfo.systemUptime
        messageSendCount = 0
        isolationCrossingCount = 0
        contentionDuration = 0
        hotPathLabels = []
        isAnalysing = true
    }

    /// Records an actor message send.
    ///
    /// - Parameter label: Optional label for the message target.
    public func recordMessageSend(label: String? = nil) {
        guard isAnalysing else { return }
        messageSendCount += 1
        if let label = label, !hotPathLabels.contains(label) {
            hotPathLabels.append(label)
        }
    }

    /// Records an isolation boundary crossing with timing.
    ///
    /// - Parameters:
    ///   - label: Label identifying the crossing point.
    ///   - duration: Time spent at the crossing in seconds.
    public func recordIsolationCrossing(label: String, duration: TimeInterval = 0) {
        guard isAnalysing else { return }
        isolationCrossingCount += 1
        contentionDuration += duration
        if !hotPathLabels.contains(label) {
            hotPathLabels.append(label)
        }
    }

    /// Ends analysis and returns contention metrics.
    ///
    /// - Parameter taskCount: Number of concurrent tasks that ran.
    /// - Returns: Contention metrics for the analysis session.
    public func endAnalysis(taskCount: Int) -> J2KActorContentionMetrics {
        let elapsed = ProcessInfo.processInfo.systemUptime - analysisStartTime
        isAnalysing = false

        return J2KActorContentionMetrics(
            messageSends: messageSendCount,
            isolationCrossings: isolationCrossingCount,
            contentionTime: contentionDuration,
            totalTime: elapsed,
            taskCount: taskCount,
            hotPaths: hotPathLabels
        )
    }

    /// Whether an analysis session is active.
    public var isActive: Bool { isAnalysing }
}

// MARK: - Thread-Safe Result Collector

/// Internal thread-safe result collector for concurrent pipeline operations.
///
/// Uses `Mutex` for synchronisation, matching the pattern established
/// by `ParallelResultCollector<T>` in J2KCodec.
final class ConcurrentResultCollector<T: Sendable>: Sendable {
    private let _results: Mutex<[T]>

    init(capacity: Int = 0) {
        var initial: [T] = []
        initial.reserveCapacity(capacity)
        _results = Mutex(initial)
    }

    func append(_ element: T) {
        _results.withLock { $0.append(element) }
    }

    var results: [T] {
        _results.withLock { Array($0) }
    }
}

// MARK: - Work-Stealing Queue

/// A work-stealing queue for distributing uneven workloads across workers.
///
/// Uses `Mutex` for thread-safe access to the work queue. Items can be
/// taken from the front (by the owning worker) or stolen from the back
/// (by idle workers), balancing load across all workers.
final class J2KWorkStealingQueue<T: Sendable>: Sendable {
    private let _items: Mutex<[T]>

    /// Creates a work-stealing queue with initial items.
    ///
    /// - Parameter items: Initial items to process.
    init(items: [T] = []) {
        _items = Mutex(items)
    }

    /// Takes an item from the front of the queue (owner operation).
    ///
    /// - Returns: The next item, or nil if the queue is empty.
    func takeOwn() -> T? {
        _items.withLock { items in
            guard !items.isEmpty else { return nil }
            return items.removeFirst()
        }
    }

    /// Steals an item from the back of the queue (thief operation).
    ///
    /// - Returns: A stolen item, or nil if the queue is empty.
    func steal() -> T? {
        _items.withLock { items in
            guard !items.isEmpty else { return nil }
            return items.removeLast()
        }
    }

    /// Number of items remaining in the queue.
    var count: Int {
        _items.withLock { $0.count }
    }

    /// Whether the queue is empty.
    var isEmpty: Bool {
        _items.withLock { $0.isEmpty }
    }
}

// MARK: - Concurrent Pipeline

/// A concurrent pipeline that executes independent work items in parallel
/// with configurable concurrency limits and optional work-stealing.
///
/// `J2KConcurrentPipeline` is designed for tile-level and code-block-level
/// parallelism in JPEG 2000 encoding and decoding, respecting system
/// resources and providing scalability across different core counts.
///
/// Example:
/// ```swift
/// let pipeline = J2KConcurrentPipeline(
///     limits: .forSystem()
/// )
/// let results = try await pipeline.processParallel(tiles) { tile in
///     try encodeTile(tile)
/// }
/// ```
public struct J2KConcurrentPipeline: Sendable {
    /// Concurrency limits for the pipeline.
    public let limits: J2KConcurrencyLimits

    /// Creates a new concurrent pipeline.
    ///
    /// - Parameter limits: Concurrency limits (default: system-optimized).
    public init(limits: J2KConcurrencyLimits = .forSystem()) {
        self.limits = limits
    }

    /// Result of a parallel pipeline execution.
    public struct PipelineResult<T: Sendable>: Sendable {
        /// The computed results in input order.
        public let results: [T]

        /// Wall-clock time for the entire operation in seconds.
        public let totalTime: TimeInterval

        /// Number of tasks that ran concurrently.
        public let concurrency: Int

        /// Speedup relative to serial execution estimate.
        public var estimatedSpeedup: Double {
            guard concurrency > 0 else { return 1.0 }
            return Double(concurrency)
        }
    }

    /// Processes items in parallel with configurable concurrency.
    ///
    /// Items are distributed across up to `limits.maxParallelism` concurrent
    /// tasks. When work-stealing is enabled, idle workers steal from busy
    /// workers to balance load.
    ///
    /// - Parameters:
    ///   - items: The items to process.
    ///   - transform: The transformation to apply to each item.
    /// - Returns: A `PipelineResult` containing results and timing information.
    /// - Throws: The first error encountered during processing.
    public func processParallel<Input: Sendable, Output: Sendable>(
        _ items: [Input],
        transform: @Sendable @escaping (Input) throws -> Output
    ) async throws -> PipelineResult<Output> {
        guard !items.isEmpty else {
            return PipelineResult(results: [], totalTime: 0, concurrency: 0)
        }

        let startTime = ProcessInfo.processInfo.systemUptime

        // For single item or serial mode, skip parallelism overhead
        if items.count <= 1 || limits.maxParallelism <= 1 {
            let results = try items.map(transform)
            let elapsed = ProcessInfo.processInfo.systemUptime - startTime
            return PipelineResult(results: results, totalTime: elapsed, concurrency: 1)
        }

        let maxConcurrency = min(limits.maxParallelism, items.count)

        let results: [Output]
        if limits.enableWorkStealing && items.count > maxConcurrency * 2 {
            results = try await processWithWorkStealing(
                items, maxConcurrency: maxConcurrency, transform: transform
            )
        } else {
            results = try await processWithTaskGroup(
                items, maxConcurrency: maxConcurrency, transform: transform
            )
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        return PipelineResult(results: results, totalTime: elapsed, concurrency: maxConcurrency)
    }

    /// Processes items using a bounded TaskGroup.
    private func processWithTaskGroup<Input: Sendable, Output: Sendable>(
        _ items: [Input],
        maxConcurrency: Int,
        transform: @Sendable @escaping (Input) throws -> Output
    ) async throws -> [Output] {
        try await withThrowingTaskGroup(
            of: (Int, Output).self,
            returning: [Output].self
        ) { group in
            var nextIndex = 0
            var collected: [(Int, Output)] = []
            collected.reserveCapacity(items.count)

            // Submit initial batch up to maxConcurrency
            let initialBatch = min(maxConcurrency, items.count)
            for index in 0..<initialBatch {
                let item = items[index]
                group.addTask {
                    let result = try transform(item)
                    return (index, result)
                }
            }
            nextIndex = initialBatch

            // As tasks complete, submit more to maintain concurrency
            for try await (index, result) in group {
                collected.append((index, result))

                if nextIndex < items.count {
                    let item = items[nextIndex]
                    let capturedIndex = nextIndex
                    group.addTask {
                        let result = try transform(item)
                        return (capturedIndex, result)
                    }
                    nextIndex += 1
                }
            }

            // Sort by original index to maintain order
            collected.sort { $0.0 < $1.0 }
            return collected.map(\.1)
        }
    }

    /// Processes items using work-stealing for uneven workloads.
    ///
    /// Each worker has its own queue. When a worker's queue is exhausted,
    /// it steals from other workers' queues, balancing the load.
    private func processWithWorkStealing<Input: Sendable, Output: Sendable>(
        _ items: [Input],
        maxConcurrency: Int,
        transform: @Sendable @escaping (Input) throws -> Output
    ) async throws -> [Output] {
        // Partition items into per-worker queues
        let indexed = items.enumerated().map { ($0.offset, $0.element) }
        let chunkSize = max(1, (indexed.count + maxConcurrency - 1) / maxConcurrency)
        var workerQueues: [J2KWorkStealingQueue<(Int, Input)>] = []

        for workerIndex in 0..<maxConcurrency {
            let start = workerIndex * chunkSize
            let end = min(start + chunkSize, indexed.count)
            if start < end {
                workerQueues.append(J2KWorkStealingQueue(items: Array(indexed[start..<end])))
            }
        }

        let resultCollector = ConcurrentResultCollector<(Int, Output)>(capacity: items.count)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for workerIndex in 0..<workerQueues.count {
                let ownQueue = workerQueues[workerIndex]
                let allQueues = workerQueues
                let collector = resultCollector
                group.addTask {
                    // Process own queue first
                    while let (index, item) = ownQueue.takeOwn() {
                        let result = try transform(item)
                        collector.append((index, result))
                    }
                    // Steal from other workers when own queue is empty
                    for otherIndex in 0..<allQueues.count where otherIndex != workerIndex {
                        while let (index, item) = allQueues[otherIndex].steal() {
                            let result = try transform(item)
                            collector.append((index, result))
                        }
                    }
                }
            }
            try await group.waitForAll()
        }

        var sorted = resultCollector.results
        sorted.sort { $0.0 < $1.0 }
        return sorted.map(\.1)
    }
}

// MARK: - Concurrency Benchmark

/// Benchmarks concurrent vs serial execution for pipeline operations.
///
/// `J2KConcurrencyBenchmark` measures the performance characteristics of
/// concurrent pipelines at different parallelism levels, producing a
/// scalability report.
///
/// Example:
/// ```swift
/// let benchmark = J2KConcurrencyBenchmark()
/// let report = try await benchmark.measureScalability(
///     items: tiles,
///     coreCounts: [1, 2, 4, 8],
///     transform: encodeTile
/// )
/// print(report)
/// ```
public struct J2KConcurrencyBenchmark: Sendable {
    /// Creates a new concurrency benchmark.
    public init() {}

    /// Result of a scalability measurement at a specific core count.
    public struct ScalabilityPoint: Sendable {
        /// The core count used.
        public let coreCount: Int

        /// Wall-clock time in seconds.
        public let time: TimeInterval

        /// Speedup relative to serial (1-core) execution.
        public let speedup: Double

        /// Parallel efficiency (speedup / coreCount).
        public var efficiency: Double {
            guard coreCount > 0 else { return 0 }
            return speedup / Double(coreCount)
        }
    }

    /// Full scalability report across multiple core counts.
    public struct ScalabilityReport: Sendable, CustomStringConvertible {
        /// Individual measurement points.
        public let points: [ScalabilityPoint]

        /// Number of items processed.
        public let itemCount: Int

        /// Peak speedup achieved.
        public var peakSpeedup: Double {
            points.map(\.speedup).max() ?? 1.0
        }

        /// Core count at peak speedup.
        public var peakCoreCount: Int {
            points.max(by: { $0.speedup < $1.speedup })?.coreCount ?? 1
        }

        public var description: String {
            var lines: [String] = []
            lines.append("═══════════════════════════════════════════════════════════════")
            lines.append("Concurrency Scalability Report (\(itemCount) items)")
            lines.append("═══════════════════════════════════════════════════════════════")
            lines.append(String(format: "  %-8s  %-12s  %-10s  %-10s", "Cores", "Time (ms)", "Speedup", "Efficiency"))
            lines.append("  " + String(repeating: "─", count: 48))

            for point in points {
                lines.append(String(format: "  %-8d  %-12.4f  %-10.2fx  %-10.1f%%",
                                    point.coreCount,
                                    point.time * 1000,
                                    point.speedup,
                                    point.efficiency * 100))
            }

            lines.append("")
            lines.append("  Peak speedup: \(String(format: "%.2f", peakSpeedup))x at \(peakCoreCount) cores")
            lines.append("═══════════════════════════════════════════════════════════════")
            return lines.joined(separator: "\n")
        }
    }

    /// Measures scalability across different core counts.
    ///
    /// Runs the same workload at each specified core count and produces
    /// a report showing speedup and efficiency.
    ///
    /// - Parameters:
    ///   - items: The items to process.
    ///   - coreCounts: Core counts to test (default: [1, 2, 4, 8, 16]).
    ///   - warmupIterations: Number of warmup runs (default: 1).
    ///   - transform: The transformation to apply to each item.
    /// - Returns: A scalability report.
    /// - Throws: Any error encountered during processing.
    public func measureScalability<Input: Sendable, Output: Sendable>(
        items: [Input],
        coreCounts: [Int] = [1, 2, 4, 8, 16],
        warmupIterations: Int = 1,
        transform: @Sendable @escaping (Input) throws -> Output
    ) async throws -> ScalabilityReport {
        var points: [ScalabilityPoint] = []
        var serialTime: TimeInterval = 0

        for coreCount in coreCounts {
            let limits = J2KConcurrencyLimits.forCoreCount(coreCount)
            let pipeline = J2KConcurrentPipeline(limits: limits)

            // Warmup
            for _ in 0..<warmupIterations {
                _ = try await pipeline.processParallel(items, transform: transform)
            }

            // Measure
            let start = ProcessInfo.processInfo.systemUptime
            _ = try await pipeline.processParallel(items, transform: transform)
            let elapsed = ProcessInfo.processInfo.systemUptime - start

            if coreCount == 1 || serialTime == 0 {
                serialTime = elapsed
            }

            let speedup = serialTime / max(elapsed, 1e-9)
            points.append(ScalabilityPoint(
                coreCount: coreCount,
                time: elapsed,
                speedup: speedup
            ))
        }

        return ScalabilityReport(points: points, itemCount: items.count)
    }

    /// Compares concurrent vs serial pipeline execution.
    ///
    /// - Parameters:
    ///   - items: The items to process.
    ///   - iterations: Number of measurement iterations (default: 3).
    ///   - limits: Concurrency limits for the parallel run.
    ///   - transform: The transformation to apply.
    /// - Returns: A tuple of (serialTime, parallelTime, speedup).
    /// - Throws: Any error encountered during processing.
    public func compareConcurrentVsSerial<Input: Sendable, Output: Sendable>(
        items: [Input],
        iterations: Int = 3,
        limits: J2KConcurrencyLimits = .forSystem(),
        transform: @Sendable @escaping (Input) throws -> Output
    ) async throws -> (serialTime: TimeInterval, parallelTime: TimeInterval, speedup: Double) {
        // Measure serial
        let serialPipeline = J2KConcurrentPipeline(limits: .serial)
        var serialTotal: TimeInterval = 0
        for _ in 0..<iterations {
            let result = try await serialPipeline.processParallel(items, transform: transform)
            serialTotal += result.totalTime
        }
        let serialAvg = serialTotal / Double(iterations)

        // Measure parallel
        let parallelPipeline = J2KConcurrentPipeline(limits: limits)
        var parallelTotal: TimeInterval = 0
        for _ in 0..<iterations {
            let result = try await parallelPipeline.processParallel(items, transform: transform)
            parallelTotal += result.totalTime
        }
        let parallelAvg = parallelTotal / Double(iterations)

        let speedup = serialAvg / max(parallelAvg, 1e-9)
        return (serialTime: serialAvg, parallelTime: parallelAvg, speedup: speedup)
    }
}

// MARK: - Memory Pressure Monitor for Concurrency

/// Monitors memory pressure during concurrent pipeline execution.
///
/// Tracks peak memory usage and detects when concurrent operations
/// exceed memory budgets, enabling adaptive concurrency reduction.
public struct J2KConcurrencyMemoryMonitor: Sendable {
    /// Memory snapshot during concurrent execution.
    public struct MemorySnapshot: Sendable {
        /// Resident memory at snapshot time in bytes.
        public let residentMemory: Int

        /// Number of active concurrent tasks.
        public let activeTasks: Int

        /// Estimated memory per task in bytes.
        public var memoryPerTask: Int {
            guard activeTasks > 0 else { return 0 }
            return residentMemory / activeTasks
        }
    }

    /// Creates a new memory monitor.
    public init() {}

    /// Takes a memory snapshot.
    ///
    /// - Parameter activeTasks: Number of currently active tasks.
    /// - Returns: A memory snapshot.
    public func snapshot(activeTasks: Int) -> MemorySnapshot {
        MemorySnapshot(
            residentMemory: J2KMemoryInfo.currentResidentMemory(),
            activeTasks: activeTasks
        )
    }

    /// Measures memory usage during a concurrent operation.
    ///
    /// - Parameters:
    ///   - concurrency: Number of concurrent tasks.
    ///   - operation: The concurrent operation to measure.
    /// - Returns: Peak memory delta in bytes.
    public func measureMemoryPressure(
        concurrency: Int,
        operation: () -> Void
    ) -> Int {
        let baseline = J2KMemoryInfo.currentResidentMemory()
        operation()
        let peak = J2KMemoryInfo.currentResidentMemory()
        return max(0, peak - baseline)
    }
}
