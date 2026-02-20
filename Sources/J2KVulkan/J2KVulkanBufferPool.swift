//
// J2KVulkanBufferPool.swift
// J2KSwift
//
// GPU buffer pooling and memory management for Vulkan compute operations.
//

import Foundation
import J2KCore

// MARK: - Vulkan Memory Type

/// Memory type for Vulkan buffer allocation.
///
/// Maps to Vulkan memory property flags for selecting the appropriate
/// memory heap for a given buffer usage pattern.
public enum J2KVulkanMemoryType: Sendable {
    /// Device-local memory (fastest GPU access, requires staging for CPU transfer).
    case deviceLocal
    /// Host-visible, host-coherent memory (CPU-accessible, slower GPU access).
    case hostVisible
    /// Host-visible, host-cached memory (optimised for CPU reads).
    case hostCached
}

// MARK: - Buffer Pool Configuration

/// Configuration for the Vulkan buffer pool.
///
/// Controls pool sizing, reuse strategy, and memory limits.
public struct J2KVulkanBufferPoolConfiguration: Sendable {
    /// Maximum number of buffers to keep in the pool for reuse.
    public var maxPoolSize: Int

    /// Maximum total memory for pooled buffers in bytes.
    public var maxPoolMemory: UInt64

    /// Default memory type for new buffers.
    public var defaultMemoryType: J2KVulkanMemoryType

    /// Whether to enable buffer reuse pooling.
    public var enablePooling: Bool

    /// Creates a new buffer pool configuration.
    ///
    /// - Parameters:
    ///   - maxPoolSize: Maximum number of pooled buffers. Defaults to `64`.
    ///   - maxPoolMemory: Maximum pool memory in bytes. Defaults to `256 MB`.
    ///   - defaultMemoryType: Default memory type. Defaults to `.hostVisible`.
    ///   - enablePooling: Whether to enable pooling. Defaults to `true`.
    public init(
        maxPoolSize: Int = 64,
        maxPoolMemory: UInt64 = 256 * 1024 * 1024,
        defaultMemoryType: J2KVulkanMemoryType = .hostVisible,
        enablePooling: Bool = true
    ) {
        self.maxPoolSize = maxPoolSize
        self.maxPoolMemory = maxPoolMemory
        self.defaultMemoryType = defaultMemoryType
        self.enablePooling = enablePooling
    }

    /// Default buffer pool configuration.
    public static let `default` = J2KVulkanBufferPoolConfiguration()
}

// MARK: - Buffer Pool Statistics

/// Statistics about Vulkan buffer pool usage.
///
/// Provides insight into pool efficiency for monitoring and tuning.
public struct J2KVulkanBufferPoolStatistics: Sendable {
    /// Total number of buffer allocations requested.
    public var totalAllocations: Int
    /// Number of allocations satisfied from the pool (cache hits).
    public var poolHits: Int
    /// Number of allocations requiring new buffer creation (cache misses).
    public var poolMisses: Int
    /// Current number of buffers in the pool.
    public var currentPoolSize: Int
    /// Current total memory used by pooled buffers in bytes.
    public var currentPoolMemory: UInt64
    /// Total number of buffers returned to the pool.
    public var totalReturns: Int

    /// Pool hit rate as a percentage (0.0 to 1.0).
    public var hitRate: Double {
        guard totalAllocations > 0 else { return 0.0 }
        return Double(poolHits) / Double(totalAllocations)
    }

    /// Creates initial (zero) statistics.
    public init() {
        self.totalAllocations = 0
        self.poolHits = 0
        self.poolMisses = 0
        self.currentPoolSize = 0
        self.currentPoolMemory = 0
        self.totalReturns = 0
    }
}

// MARK: - Vulkan Buffer Handle

/// Represents a Vulkan buffer allocation for CPU-side tracking.
///
/// When Vulkan is available, this wraps a VkBuffer and its associated
/// VkDeviceMemory. When running in CPU fallback mode, this tracks a
/// plain memory allocation.
public struct J2KVulkanBufferHandle: Sendable {
    /// Unique identifier for this buffer.
    public let id: UInt64
    /// Size of the buffer in bytes.
    public let size: Int
    /// Memory type used for this buffer.
    public let memoryType: J2KVulkanMemoryType

    /// Creates a buffer handle.
    public init(id: UInt64, size: Int, memoryType: J2KVulkanMemoryType) {
        self.id = id
        self.size = size
        self.memoryType = memoryType
    }
}

// MARK: - Buffer Pool

/// Manages a pool of reusable Vulkan buffers for GPU compute operations.
///
/// `J2KVulkanBufferPool` reduces allocation overhead by reusing Vulkan
/// buffers across operations. Buffers are matched by size bucket and
/// returned to the pool when no longer needed.
///
/// ## Usage
///
/// ```swift
/// let pool = J2KVulkanBufferPool()
///
/// // Acquire a buffer handle
/// let handle = try await pool.acquireBuffer(size: 4096)
///
/// // Use the buffer for compute operations...
///
/// // Return buffer to pool for reuse
/// await pool.returnBuffer(handle)
/// ```
///
/// ## Memory Management
///
/// The pool automatically tracks memory usage and evicts old buffers
/// when limits are exceeded. Use ``drain()`` to release all pooled buffers.
public actor J2KVulkanBufferPool {
    /// Whether Vulkan buffer pooling is available on this platform.
    public static var isAvailable: Bool {
        J2KVulkanDevice.isAvailable
    }

    /// The pool configuration.
    public let configuration: J2KVulkanBufferPoolConfiguration

    /// Pool usage statistics.
    private var _statistics = J2KVulkanBufferPoolStatistics()

    /// Pooled buffer handles organised by size bucket.
    private var pool: [Int: [J2KVulkanBufferHandle]] = [:]

    /// Total memory currently used by pooled buffers.
    private var pooledMemory: UInt64 = 0

    /// Total count of buffers in the pool.
    private var pooledCount: Int = 0

    /// Next buffer ID for unique identification.
    private var nextBufferID: UInt64 = 0

    /// Creates a new buffer pool with the given configuration.
    ///
    /// - Parameter configuration: The pool configuration. Defaults to `.default`.
    public init(configuration: J2KVulkanBufferPoolConfiguration = .default) {
        self.configuration = configuration
    }

    /// Returns the current pool statistics.
    ///
    /// - Returns: A snapshot of the pool statistics.
    public func statistics() -> J2KVulkanBufferPoolStatistics {
        var stats = _statistics
        stats.currentPoolSize = pooledCount
        stats.currentPoolMemory = pooledMemory
        return stats
    }

    /// Acquires a Vulkan buffer of at least the specified size.
    ///
    /// If pooling is enabled and a suitable buffer exists in the pool, it is
    /// reused. Otherwise, a new buffer handle is created.
    ///
    /// - Parameters:
    ///   - size: The minimum buffer size in bytes.
    ///   - memoryType: The memory type. Defaults to the pool's default.
    /// - Returns: A buffer handle for tracking the allocation.
    /// - Throws: ``J2KError/internalError(_:)`` if allocation fails.
    public func acquireBuffer(
        size: Int,
        memoryType: J2KVulkanMemoryType? = nil
    ) throws -> J2KVulkanBufferHandle {
        _statistics.totalAllocations += 1

        let bucketSize = sizeBucket(for: size)

        // Try to reuse a pooled buffer
        if configuration.enablePooling, let handle = dequeueBuffer(size: bucketSize) {
            _statistics.poolHits += 1
            return handle
        }

        // Create a new buffer handle
        _statistics.poolMisses += 1
        let effectiveType = memoryType ?? configuration.defaultMemoryType
        let handle = J2KVulkanBufferHandle(
            id: generateBufferID(),
            size: bucketSize,
            memoryType: effectiveType
        )

        return handle
    }

    /// Returns a buffer to the pool for potential reuse.
    ///
    /// The buffer is added to the pool if pooling is enabled and pool limits
    /// are not exceeded. Otherwise, the buffer is released immediately.
    ///
    /// - Parameter handle: The buffer handle to return.
    public func returnBuffer(_ handle: J2KVulkanBufferHandle) {
        _statistics.totalReturns += 1

        guard configuration.enablePooling else { return }

        let bufferSize = handle.size
        let memoryAfter = pooledMemory + UInt64(bufferSize)

        // Check pool limits
        guard pooledCount < configuration.maxPoolSize,
              memoryAfter <= configuration.maxPoolMemory else {
            return
        }

        let bucket = sizeBucket(for: bufferSize)
        if pool[bucket] == nil {
            pool[bucket] = []
        }
        pool[bucket]!.append(handle)
        pooledCount += 1
        pooledMemory += UInt64(bufferSize)
    }

    /// Drains all buffers from the pool, releasing their memory.
    public func drain() {
        pool.removeAll()
        pooledCount = 0
        pooledMemory = 0
    }

    /// Returns the number of buffers currently in the pool.
    ///
    /// - Returns: The count of pooled buffers.
    public func count() -> Int {
        pooledCount
    }

    // MARK: - Private Helpers

    /// Rounds a size up to the nearest power-of-two bucket, minimum 4096.
    private func sizeBucket(for size: Int) -> Int {
        let minBucket = 4096
        guard size > minBucket else { return minBucket }

        var bucket = minBucket
        while bucket < size {
            bucket *= 2
        }
        return bucket
    }

    /// Dequeues a buffer from the pool matching the given size.
    private func dequeueBuffer(size: Int) -> J2KVulkanBufferHandle? {
        guard var buffers = pool[size], !buffers.isEmpty else { return nil }

        let handle = buffers.removeLast()
        pool[size] = buffers
        pooledCount -= 1
        pooledMemory -= UInt64(handle.size)
        return handle
    }

    /// Generates a unique buffer ID.
    private func generateBufferID() -> UInt64 {
        nextBufferID += 1
        return nextBufferID
    }
}
