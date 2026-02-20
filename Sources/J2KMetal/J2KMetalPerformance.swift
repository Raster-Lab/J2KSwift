/// # J2KMetalPerformance
///
/// Metal-specific performance optimization and tuning.
///
/// This module provides Metal GPU performance optimization including
/// kernel launch minimization, shader occupancy optimization, memory
/// bandwidth optimization, and async compute utilization.

#if canImport(Metal)
import Metal
#endif
import Foundation

#if canImport(Metal)

/// Metal performance optimizer for GPU-accelerated operations.
///
/// This actor coordinates Metal GPU performance optimizations including:
/// - Kernel launch batching and minimization
/// - Shader occupancy optimization
/// - Register pressure reduction
/// - Memory bandwidth optimization
/// - Async compute pipeline utilization
///
/// Example:
/// ```swift
/// let optimizer = J2KMetalPerformance(device: metalDevice)
/// let config = await optimizer.optimizeForThroughput()
/// await optimizer.recordKernelLaunch(name: "DWT", duration: 0.002)
/// let metrics = await optimizer.performanceMetrics()
/// ```
public actor J2KMetalPerformance {
    /// Metal device.
    private let device: MTLDevice

    /// Performance optimization configuration.
    public struct Configuration: Sendable {
        /// Maximum threadgroup size for kernels.
        public var maxThreadgroupSize: Int

        /// Target threads per threadgroup.
        public var targetThreadsPerThreadgroup: Int

        /// Enable async compute for parallelism.
        public var enableAsyncCompute: Bool

        /// Batch kernel launches when possible.
        public var batchKernelLaunches: Bool

        /// Minimum batch size for kernel launches.
        public var minBatchSize: Int

        /// Maximum memory bandwidth utilization (0.0-1.0).
        public var maxBandwidthUtilization: Double

        /// Enable memory access coalescing hints.
        public var enableMemoryCoalescing: Bool

        /// Creates default configuration.
        public init(
            maxThreadgroupSize: Int = 1024,
            targetThreadsPerThreadgroup: Int = 256,
            enableAsyncCompute: Bool = true,
            batchKernelLaunches: Bool = true,
            minBatchSize: Int = 4,
            maxBandwidthUtilization: Double = 0.85,
            enableMemoryCoalescing: Bool = true
        ) {
            self.maxThreadgroupSize = maxThreadgroupSize
            self.targetThreadsPerThreadgroup = targetThreadsPerThreadgroup
            self.enableAsyncCompute = enableAsyncCompute
            self.batchKernelLaunches = batchKernelLaunches
            self.minBatchSize = minBatchSize
            self.maxBandwidthUtilization = maxBandwidthUtilization
            self.enableMemoryCoalescing = enableMemoryCoalescing
        }

        /// High-throughput configuration.
        public static var highThroughput: Configuration {
            Configuration(
                maxThreadgroupSize: 1024,
                targetThreadsPerThreadgroup: 512,
                enableAsyncCompute: true,
                batchKernelLaunches: true,
                minBatchSize: 2,
                maxBandwidthUtilization: 0.95,
                enableMemoryCoalescing: true
            )
        }

        /// Low-latency configuration.
        public static var lowLatency: Configuration {
            Configuration(
                maxThreadgroupSize: 256,
                targetThreadsPerThreadgroup: 128,
                enableAsyncCompute: false,
                batchKernelLaunches: false,
                minBatchSize: 1,
                maxBandwidthUtilization: 0.75,
                enableMemoryCoalescing: true
            )
        }

        /// Balanced configuration.
        public static var balanced: Configuration {
            Configuration()
        }
    }

    /// Performance metrics.
    public struct Metrics: Sendable {
        /// Total kernel launches.
        public let totalLaunches: Int

        /// Total GPU time in seconds.
        public let totalGPUTime: TimeInterval

        /// Average kernel launch overhead in seconds.
        public let averageLaunchOverhead: TimeInterval

        /// Estimated GPU utilization (0.0-1.0).
        public let gpuUtilization: Double

        /// Memory bandwidth utilization (0.0-1.0).
        public let bandwidthUtilization: Double

        /// Number of batched launches.
        public let batchedLaunches: Int

        /// Async compute usage percentage (0.0-100.0).
        public let asyncComputeUsage: Double
    }

    /// Kernel launch record.
    private struct KernelLaunch {
        let name: String
        let duration: TimeInterval
        let threadgroupSize: Int
        let timestamp: Date
        let batched: Bool
        let async: Bool
    }

    // MARK: - State

    /// Current configuration.
    private var configuration: Configuration = .balanced

    /// Recorded kernel launches.
    private var kernelLaunches: [KernelLaunch] = []

    /// Session start time.
    private var sessionStart: Date?

    // MARK: - Initialization

    /// Creates a Metal performance optimizer.
    ///
    /// - Parameters:
    ///   - device: Metal device to optimize for.
    ///   - configuration: Initial configuration (default: .balanced).
    public init(device: MTLDevice, configuration: Configuration = .balanced) {
        self.device = device
        self.configuration = configuration
    }

    // MARK: - Configuration

    /// Optimizes configuration for maximum throughput.
    ///
    /// - Returns: Optimized configuration.
    public func optimizeForThroughput() -> Configuration {
        configuration = .highThroughput
        return configuration
    }

    /// Optimizes configuration for minimum latency.
    ///
    /// - Returns: Optimized configuration.
    public func optimizeForLatency() -> Configuration {
        configuration = .lowLatency
        return configuration
    }

    /// Sets custom configuration.
    ///
    /// - Parameter config: Custom configuration.
    public func setConfiguration(_ config: Configuration) {
        configuration = config
    }

    /// Returns current configuration.
    public func currentConfiguration() -> Configuration {
        configuration
    }

    // MARK: - Threadgroup Optimization

    /// Calculates optimal threadgroup size for the given workload.
    ///
    /// This method considers:
    /// - Maximum threads per threadgroup supported by device
    /// - Workload size and dimensionality
    /// - Memory requirements and register pressure
    /// - Target occupancy
    ///
    /// - Parameters:
    ///   - workloadSize: Total number of work items.
    ///   - memoryPerThread: Memory required per thread in bytes.
    /// - Returns: Optimal threadgroup size.
    public func optimalThreadgroupSize(
        workloadSize: Int,
        memoryPerThread: Int = 0
    ) -> Int {
        let maxThreads = min(
            device.maxThreadsPerThreadgroup.width,
            configuration.maxThreadgroupSize
        )

        // Start with target size
        var size = configuration.targetThreadsPerThreadgroup

        // Adjust for workload size
        if workloadSize < size {
            size = max(32, (workloadSize + 31) / 32 * 32) // Round up to multiple of 32
        }

        // Adjust for memory constraints
        if memoryPerThread > 0 {
            let threadgroupMemory = device.maxThreadgroupMemoryLength
            let maxThreadsByMemory = threadgroupMemory / max(1, memoryPerThread)
            size = min(size, maxThreadsByMemory)
        }

        // Ensure power of 2 and within limits
        size = min(size, maxThreads)
        size = max(32, size)

        // Round down to nearest power of 2
        var powerOfTwo = 32
        while powerOfTwo * 2 <= size {
            powerOfTwo *= 2
        }

        return powerOfTwo
    }

    /// Calculates optimal 2D threadgroup size for 2D workloads.
    ///
    /// - Parameters:
    ///   - width: Workload width.
    ///   - height: Workload height.
    /// - Returns: Optimal 2D threadgroup size (width, height).
    public func optimalThreadgroupSize2D(
        width: Int,
        height: Int
    ) -> (width: Int, height: Int) {
        let maxThreads = min(
            device.maxThreadsPerThreadgroup.width,
            configuration.maxThreadgroupSize
        )
        let targetThreads = configuration.targetThreadsPerThreadgroup

        // Start with square threadgroup
        let side = Int(sqrt(Double(targetThreads)))
        var tgWidth = max(8, (side + 7) / 8 * 8) // Multiple of 8
        var tgHeight = max(8, (side + 7) / 8 * 8)

        // Adjust for aspect ratio
        let aspectRatio = Double(width) / Double(max(1, height))
        if aspectRatio > 2.0 {
            tgWidth *= 2
            tgHeight /= 2
        } else if aspectRatio < 0.5 {
            tgWidth /= 2
            tgHeight *= 2
        }

        // Ensure within limits
        while tgWidth * tgHeight > maxThreads {
            if tgWidth > tgHeight {
                tgWidth /= 2
            } else {
                tgHeight /= 2
            }
        }

        tgWidth = max(8, min(32, tgWidth))
        tgHeight = max(8, min(32, tgHeight))

        return (tgWidth, tgHeight)
    }

    // MARK: - Memory Bandwidth Optimization

    /// Calculates optimal memory access pattern for the given data layout.
    ///
    /// - Parameters:
    ///   - dataSize: Size of data in bytes.
    ///   - stride: Data stride in bytes.
    ///   - accessPattern: Access pattern ("sequential", "strided", "random").
    /// - Returns: Recommended access pattern and batch size.
    public func optimalMemoryAccess(
        dataSize: Int,
        stride: Int,
        accessPattern: String
    ) -> (pattern: String, batchSize: Int) {
        let cacheLineSize = 64 // bytes

        if configuration.enableMemoryCoalescing {
            if stride == 0 || stride % cacheLineSize == 0 {
                // Already aligned, use sequential access
                return ("sequential", 4)
            } else if stride < cacheLineSize {
                // Small stride, batch to fill cache lines
                let batchSize = (cacheLineSize + stride - 1) / stride
                return ("batched", batchSize)
            } else {
                // Large stride, use scattered access
                return ("scattered", 1)
            }
        }

        return (accessPattern, 1)
    }

    /// Estimates memory bandwidth utilization for the given operation.
    ///
    /// - Parameters:
    ///   - bytesRead: Bytes read from memory.
    ///   - bytesWritten: Bytes written to memory.
    ///   - duration: Operation duration in seconds.
    /// - Returns: Estimated bandwidth utilization (0.0-1.0).
    public func estimateBandwidthUtilization(
        bytesRead: Int,
        bytesWritten: Int,
        duration: TimeInterval
    ) -> Double {
        guard duration > 0 else { return 0 }

        // Typical Apple Silicon bandwidth: ~400 GB/s (M1 Max)
        let estimatedPeakBandwidth = 400_000_000_000.0 // bytes/s

        let totalBytes = Double(bytesRead + bytesWritten)
        let actualBandwidth = totalBytes / duration

        return min(1.0, actualBandwidth / estimatedPeakBandwidth)
    }

    // MARK: - Kernel Launch Optimization

    /// Records a kernel launch for performance tracking.
    ///
    /// - Parameters:
    ///   - name: Kernel name.
    ///   - duration: Kernel execution duration in seconds.
    ///   - threadgroupSize: Threadgroup size used.
    ///   - batched: Whether this was a batched launch.
    ///   - async: Whether this used async compute.
    public func recordKernelLaunch(
        name: String,
        duration: TimeInterval,
        threadgroupSize: Int = 256,
        batched: Bool = false,
        async: Bool = false
    ) {
        let launch = KernelLaunch(
            name: name,
            duration: duration,
            threadgroupSize: threadgroupSize,
            timestamp: Date(),
            batched: batched,
            async: async
        )

        kernelLaunches.append(launch)

        // Keep only recent launches (last 1000)
        if kernelLaunches.count > 1000 {
            kernelLaunches.removeFirst(kernelLaunches.count - 1000)
        }
    }

    /// Determines if kernel launches should be batched.
    ///
    /// - Parameter launchCount: Number of pending launches.
    /// - Returns: True if batching is recommended.
    public func shouldBatchLaunches(launchCount: Int) -> Bool {
        guard configuration.batchKernelLaunches else { return false }
        return launchCount >= configuration.minBatchSize
    }

    /// Estimates kernel launch overhead.
    ///
    /// - Returns: Estimated overhead per launch in seconds.
    public func estimatedLaunchOverhead() -> TimeInterval {
        // Typical Metal kernel launch overhead: 5-20 microseconds
        0.000010 // 10 microseconds
    }

    // MARK: - Performance Metrics

    /// Starts a performance monitoring session.
    public func startSession() {
        sessionStart = Date()
        kernelLaunches.removeAll()
    }

    /// Ends the performance monitoring session and returns metrics.
    ///
    /// - Returns: Performance metrics for the session.
    public func endSession() -> Metrics {
        let totalLaunches = kernelLaunches.count
        let totalGPUTime = kernelLaunches.reduce(0) { $0 + $1.duration }
        let batchedCount = kernelLaunches.filter { $0.batched }.count
        let asyncCount = kernelLaunches.filter { $0.async }.count

        let averageLaunchOverhead = totalLaunches > 0
            ? estimatedLaunchOverhead()
            : 0

        // Estimate GPU utilization
        let sessionDuration = sessionStart.map { Date().timeIntervalSince($0) } ?? 1.0
        let gpuUtilization = min(1.0, totalGPUTime / sessionDuration)

        // Estimate bandwidth (placeholder - would need actual measurements)
        let bandwidthUtilization = gpuUtilization * configuration.maxBandwidthUtilization

        let asyncUsage = totalLaunches > 0
            ? Double(asyncCount) / Double(totalLaunches) * 100.0
            : 0.0

        return Metrics(
            totalLaunches: totalLaunches,
            totalGPUTime: totalGPUTime,
            averageLaunchOverhead: averageLaunchOverhead,
            gpuUtilization: gpuUtilization,
            bandwidthUtilization: bandwidthUtilization,
            batchedLaunches: batchedCount,
            asyncComputeUsage: asyncUsage
        )
    }

    /// Returns current performance metrics.
    public func performanceMetrics() -> Metrics {
        endSession()
    }

    // MARK: - Device Capabilities

    /// Returns device-specific performance characteristics.
    public func deviceCharacteristics() -> (
        maxThreadgroups: Int,
        maxThreadsPerThreadgroup: Int,
        recommendedThreadgroups: Int
    ) {
        let maxThreadgroups = 1024 // Typical for Apple GPUs
        let maxThreadsPerThreadgroup = device.maxThreadsPerThreadgroup.width

        // Recommend moderate number of threadgroups for good occupancy
        let recommendedThreadgroups = 256

        return (
            maxThreadgroups,
            maxThreadsPerThreadgroup,
            recommendedThreadgroups
        )
    }

    /// Checks if the device supports async compute.
    public func supportsAsyncCompute() -> Bool {
        // Apple GPUs support async compute on A11 and later
        // This is a simplified check
        #if os(macOS)
        return true // Apple Silicon Macs support async compute
        #elseif os(iOS)
        return true // Modern iOS devices support async compute
        #else
        return false
        #endif
    }
}

#endif // canImport(Metal)
