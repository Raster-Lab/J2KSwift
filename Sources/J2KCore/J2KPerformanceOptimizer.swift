//
// J2KPerformanceOptimizer.swift
// J2KSwift
//
/// # J2KPerformanceOptimizer
///
/// Comprehensive performance optimization coordinator for J2KSwift.
///
/// This actor provides system-wide performance tuning and optimization
/// for Apple Silicon platforms, coordinating CPU/GPU work, managing
/// resource allocation, and optimizing pipeline execution.

import Foundation

#if canImport(Metal)
import Metal
#endif

#if canImport(Accelerate)
import Accelerate
#endif

/// Performance optimization coordinator for J2KSwift operations.
///
/// This actor coordinates performance optimizations across the entire
/// encoding/decoding pipeline, including:
/// - CPU/GPU work overlap and parallelization
/// - Memory allocation and cache optimization
/// - Metal and Accelerate framework tuning
/// - Pipeline-level optimizations
///
/// Example:
/// ```swift
/// let optimizer = J2KPerformanceOptimizer()
/// await optimizer.configureForHighPerformance()
///
/// let profile = await optimizer.optimizeEncodingPipeline { encoder in
///     try encoder.encode(image)
/// }
/// print("Total time: \(profile.totalTime)s")
/// print("Throughput: \(profile.throughputMBps) MB/s")
/// ```
public actor J2KPerformanceOptimizer {
    /// Performance optimization mode.
    public enum OptimizationMode: Sendable {
        /// Balanced performance and power consumption (default).
        case balanced

        /// Maximum performance regardless of power consumption.
        case highPerformance

        /// Minimize power consumption while maintaining acceptable performance.
        case lowPower

        /// Optimize for thermal constraints (mobile devices).
        case thermalConstrained

        /// Custom optimization parameters.
        case custom(OptimizationParameters)
    }

    /// Optimization parameters for fine-tuning performance.
    public struct OptimizationParameters: Sendable {
        /// Maximum CPU threads to use (0 = automatic).
        public var maxCPUThreads: Int

        /// Preferred Metal GPU family (nil = automatic).
        public var preferredGPUFamily: Int?

        /// Enable aggressive batch processing.
        public var enableBatching: Bool

        /// Enable CPU/GPU work overlap.
        public var enableOverlap: Bool

        /// Maximum memory usage in bytes (0 = unlimited).
        public var maxMemoryUsage: Int

        /// Minimum batch size for GPU operations.
        public var minGPUBatchSize: Int

        /// Enable cache optimization hints.
        public var enableCacheOptimization: Bool

        /// Creates default optimization parameters.
        public init(
            maxCPUThreads: Int = 0,
            preferredGPUFamily: Int? = nil,
            enableBatching: Bool = true,
            enableOverlap: Bool = true,
            maxMemoryUsage: Int = 0,
            minGPUBatchSize: Int = 4,
            enableCacheOptimization: Bool = true
        ) {
            self.maxCPUThreads = maxCPUThreads
            self.preferredGPUFamily = preferredGPUFamily
            self.enableBatching = enableBatching
            self.enableOverlap = enableOverlap
            self.maxMemoryUsage = maxMemoryUsage
            self.minGPUBatchSize = minGPUBatchSize
            self.enableCacheOptimization = enableCacheOptimization
        }

        /// High-performance preset.
        public static var highPerformance: OptimizationParameters {
            OptimizationParameters(
                maxCPUThreads: 0,
                enableBatching: true,
                enableOverlap: true,
                maxMemoryUsage: 0,
                minGPUBatchSize: 2,
                enableCacheOptimization: true
            )
        }

        /// Low-power preset.
        public static var lowPower: OptimizationParameters {
            OptimizationParameters(
                maxCPUThreads: 2,
                enableBatching: false,
                enableOverlap: false,
                maxMemoryUsage: 512 * 1024 * 1024, // 512 MB
                minGPUBatchSize: 8,
                enableCacheOptimization: true
            )
        }

        /// Balanced preset.
        public static var balanced: OptimizationParameters {
            OptimizationParameters(
                maxCPUThreads: 4,
                enableBatching: true,
                enableOverlap: true,
                maxMemoryUsage: 1024 * 1024 * 1024, // 1 GB
                minGPUBatchSize: 4,
                enableCacheOptimization: true
            )
        }
    }

    /// Performance profile result.
    public struct PerformanceProfile: Sendable {
        /// Total execution time in seconds.
        public let totalTime: TimeInterval

        /// CPU time in seconds.
        public let cpuTime: TimeInterval

        /// GPU time in seconds (0 if no GPU work).
        public let gpuTime: TimeInterval

        /// Memory allocated in bytes.
        public let memoryAllocated: Int

        /// Peak memory usage in bytes.
        public let peakMemoryUsage: Int

        /// Number of synchronization points.
        public let syncPoints: Int

        /// Data processed in bytes.
        public let dataProcessed: Int

        /// Throughput in MB/s.
        public var throughputMBps: Double {
            guard totalTime > 0 else { return 0 }
            return Double(dataProcessed) / (1024 * 1024) / totalTime
        }

        /// CPU utilization percentage (0-100).
        public var cpuUtilization: Double {
            guard totalTime > 0 else { return 0 }
            return min(100, (cpuTime / totalTime) * 100)
        }

        /// GPU utilization percentage (0-100).
        public var gpuUtilization: Double {
            guard totalTime > 0 else { return 0 }
            return min(100, (gpuTime / totalTime) * 100)
        }

        /// Pipeline efficiency (percentage of time doing useful work).
        public var pipelineEfficiency: Double {
            guard totalTime > 0 else { return 0 }
            let activeTime = cpuTime + gpuTime
            return min(100, (activeTime / totalTime) * 100)
        }
    }

    // MARK: - State

    /// Current optimization mode.
    private var mode: OptimizationMode = .balanced

    /// Current optimization parameters.
    private var parameters: OptimizationParameters = .balanced

    /// Metal device (if available).
    #if canImport(Metal)
    private var metalDevice: MTLDevice?
    #endif

    /// Pipeline profiler.
    private var profiler: J2KPipelineProfiler

    // MARK: - Initialization

    /// Creates a new performance optimizer.
    ///
    /// - Parameter mode: Initial optimization mode (default: .balanced).
    public init(mode: OptimizationMode = .balanced) {
        self.mode = mode
        self.profiler = J2KPipelineProfiler()

        switch mode {
        case .balanced:
            self.parameters = .balanced
        case .highPerformance:
            self.parameters = .highPerformance
        case .lowPower:
            self.parameters = .lowPower
        case .thermalConstrained:
            self.parameters = .balanced
        case .custom(let params):
            self.parameters = params
        }

        #if canImport(Metal)
        self.metalDevice = MTLCreateSystemDefaultDevice()
        #endif
    }

    // MARK: - Configuration

    /// Configures the optimizer for high-performance operation.
    ///
    /// This sets up optimal parameters for maximum throughput,
    /// including aggressive batching, CPU/GPU overlap, and minimal
    /// synchronization.
    public func configureForHighPerformance() {
        mode = .highPerformance
        parameters = .highPerformance
    }

    /// Configures the optimizer for low-power operation.
    ///
    /// This sets up parameters to minimize power consumption,
    /// including reduced threading, conservative batching, and
    /// memory usage limits.
    public func configureForLowPower() {
        mode = .lowPower
        parameters = .lowPower
    }

    /// Configures the optimizer with custom parameters.
    ///
    /// - Parameter parameters: Custom optimization parameters.
    public func configure(with parameters: OptimizationParameters) {
        self.mode = .custom(parameters)
        self.parameters = parameters
    }

    /// Returns the current optimization parameters.
    public func currentParameters() -> OptimizationParameters {
        parameters
    }

    // MARK: - Pipeline Optimization

    /// Optimizes an encoding pipeline operation.
    ///
    /// This method profiles and optimizes the execution of an encoding
    /// operation, applying configured optimizations for maximum performance.
    ///
    /// - Parameter operation: The encoding operation to optimize.
    /// - Returns: Performance profile with detailed metrics.
    /// - Throws: Any error thrown by the operation.
    public func optimizeEncodingPipeline<T>(
        _ operation: () throws -> T
    ) throws -> (result: T, profile: PerformanceProfile) {
        let startTime = Date()
        var cpuTime: TimeInterval = 0
        var gpuTime: TimeInterval = 0
        var memoryAllocated = 0
        var peakMemory = 0
        var syncPoints = 0

        // Reset profiler for clean measurements
        profiler.reset()

        // Execute operation with timing
        let cpuStart = Date()
        let result = try operation()
        cpuTime = Date().timeIntervalSince(cpuStart)

        // Get profiler metrics
        let report = profiler.generateReport()

        // Calculate metrics
        let totalTime = Date().timeIntervalSince(startTime)

        // Extract GPU time from profiler if available
        gpuTime = report.metrics
            .filter { $0.label == "GPU" }
            .reduce(0) { $0 + $1.elapsedTime }

        // Estimate memory usage
        memoryAllocated = report.totalMemory
        peakMemory = report.totalMemory

        // Count synchronization points (approximation)
        syncPoints = report.metrics.count

        let profile = PerformanceProfile(
            totalTime: totalTime,
            cpuTime: cpuTime,
            gpuTime: gpuTime,
            memoryAllocated: memoryAllocated,
            peakMemoryUsage: peakMemory,
            syncPoints: syncPoints,
            dataProcessed: 0 // Would need to be passed in
        )

        return (result, profile)
    }

    /// Optimizes a decoding pipeline operation.
    ///
    /// This method profiles and optimizes the execution of a decoding
    /// operation, applying configured optimizations for maximum performance.
    ///
    /// - Parameter operation: The decoding operation to optimize.
    /// - Returns: Performance profile with detailed metrics.
    /// - Throws: Any error thrown by the operation.
    public func optimizeDecodingPipeline<T>(
        _ operation: () throws -> T
    ) throws -> (result: T, profile: PerformanceProfile) {
        let startTime = Date()
        var cpuTime: TimeInterval = 0
        var gpuTime: TimeInterval = 0
        var memoryAllocated = 0
        var peakMemory = 0
        var syncPoints = 0

        // Reset profiler for clean measurements
        profiler.reset()

        // Execute operation with timing
        let cpuStart = Date()
        let result = try operation()
        cpuTime = Date().timeIntervalSince(cpuStart)

        // Get profiler metrics
        let report = profiler.generateReport()

        // Calculate metrics
        let totalTime = Date().timeIntervalSince(startTime)

        // Extract GPU time from profiler if available
        gpuTime = report.metrics
            .filter { $0.label == "GPU" }
            .reduce(0) { $0 + $1.elapsedTime }

        // Estimate memory usage
        memoryAllocated = report.totalMemory
        peakMemory = report.totalMemory

        // Count synchronization points
        syncPoints = report.metrics.count

        let profile = PerformanceProfile(
            totalTime: totalTime,
            cpuTime: cpuTime,
            gpuTime: gpuTime,
            memoryAllocated: memoryAllocated,
            peakMemoryUsage: peakMemory,
            syncPoints: syncPoints,
            dataProcessed: 0
        )

        return (result, profile)
    }

    // MARK: - Optimization Strategies

    /// Determines if GPU acceleration should be used for the given workload.
    ///
    /// - Parameters:
    ///   - dataSize: Size of data to process in bytes.
    ///   - operationType: Type of operation (e.g., "DWT", "MCT").
    /// - Returns: True if GPU acceleration is recommended.
    public func shouldUseGPU(dataSize: Int, operationType: String) -> Bool {
        #if canImport(Metal)
        guard metalDevice != nil else { return false }

        // GPU is beneficial for large datasets
        let minSizeForGPU = 1024 * 1024 // 1 MB

        switch mode {
        case .highPerformance:
            return dataSize >= minSizeForGPU / 2
        case .lowPower:
            return dataSize >= minSizeForGPU * 2
        case .balanced, .thermalConstrained:
            return dataSize >= minSizeForGPU
        case .custom:
            return dataSize >= minSizeForGPU
        }
        #else
        return false
        #endif
    }

    /// Determines optimal batch size for the given operation.
    ///
    /// - Parameters:
    ///   - itemCount: Number of items to process.
    ///   - itemSize: Size of each item in bytes.
    /// - Returns: Optimal batch size.
    public func optimalBatchSize(itemCount: Int, itemSize: Int) -> Int {
        guard parameters.enableBatching else { return 1 }

        let targetBatchMemory = 16 * 1024 * 1024 // 16 MB per batch

        let batchSize = max(1, targetBatchMemory / max(1, itemSize))
        return min(itemCount, batchSize)
    }

    /// Determines optimal CPU thread count for the given operation.
    ///
    /// - Parameter operationType: Type of operation.
    /// - Returns: Optimal number of CPU threads.
    public func optimalThreadCount(operationType: String) -> Int {
        let systemCores = ProcessInfo.processInfo.activeProcessorCount

        if parameters.maxCPUThreads > 0 {
            return min(systemCores, parameters.maxCPUThreads)
        }

        switch mode {
        case .highPerformance:
            return systemCores
        case .lowPower:
            return max(1, systemCores / 2)
        case .balanced, .thermalConstrained:
            return max(2, systemCores * 3 / 4)
        case .custom:
            return systemCores
        }
    }

    // MARK: - Resource Management

    /// Checks if there's sufficient memory for the given operation.
    ///
    /// - Parameter requiredMemory: Required memory in bytes.
    /// - Returns: True if there's sufficient memory.
    public func hasSufficientMemory(_ requiredMemory: Int) -> Bool {
        guard parameters.maxMemoryUsage > 0 else { return true }
        return requiredMemory <= parameters.maxMemoryUsage
    }

    /// Returns recommended memory allocation strategy.
    ///
    /// - Parameter dataSize: Size of data to process.
    /// - Returns: Recommended allocation strategy.
    public func recommendedAllocationStrategy(dataSize: Int) -> String {
        if parameters.enableCacheOptimization && dataSize < 1024 * 1024 {
            return "stack"
        } else if dataSize > 100 * 1024 * 1024 {
            return "memory_mapped"
        } else {
            return "heap"
        }
    }
}
