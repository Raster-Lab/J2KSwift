//
// J2KMetalBufferPool.swift
// J2KSwift
//
// J2KMetalBufferPool.swift
// J2KSwift
//
// GPU buffer pooling and memory management for Metal operations.
//

import Foundation
import J2KCore

#if canImport(Metal)
import Metal
#endif

// MARK: - Buffer Allocation Strategy

/// Memory allocation strategy for Metal buffers.
///
/// Controls how Metal buffers are allocated, affecting CPU-GPU data transfer
/// performance and memory usage patterns.
public enum J2KMetalBufferAllocationStrategy: Sendable {
    /// Shared memory accessible by both CPU and GPU (unified memory on Apple Silicon).
    case shared
    /// Managed memory with explicit synchronization (macOS only, falls back to shared).
    case managed
    /// Private memory accessible only by GPU (fastest GPU access, requires blit for transfer).
    case `private`
}

// MARK: - Buffer Pool Configuration

/// Configuration for the Metal buffer pool.
///
/// Controls pool sizing, reuse strategy, and memory limits.
public struct J2KMetalBufferPoolConfiguration: Sendable {
    /// Maximum number of buffers to keep in the pool for reuse.
    public var maxPoolSize: Int

    /// Maximum total memory for pooled buffers in bytes.
    public var maxPoolMemory: UInt64

    /// Default allocation strategy for new buffers.
    public var defaultStrategy: J2KMetalBufferAllocationStrategy

    /// Whether to enable buffer reuse pooling.
    public var enablePooling: Bool

    /// Creates a new buffer pool configuration.
    ///
    /// - Parameters:
    ///   - maxPoolSize: Maximum number of pooled buffers. Defaults to `64`.
    ///   - maxPoolMemory: Maximum pool memory in bytes. Defaults to `256 MB`.
    ///   - defaultStrategy: Default allocation strategy. Defaults to `.shared`.
    ///   - enablePooling: Whether to enable pooling. Defaults to `true`.
    public init(
        maxPoolSize: Int = 64,
        maxPoolMemory: UInt64 = 256 * 1024 * 1024,
        defaultStrategy: J2KMetalBufferAllocationStrategy = .shared,
        enablePooling: Bool = true
    ) {
        self.maxPoolSize = maxPoolSize
        self.maxPoolMemory = maxPoolMemory
        self.defaultStrategy = defaultStrategy
        self.enablePooling = enablePooling
    }

    /// Default buffer pool configuration.
    public static let `default` = J2KMetalBufferPoolConfiguration()
}

// MARK: - Buffer Pool Statistics

/// Statistics about buffer pool usage.
///
/// Provides insight into pool efficiency for monitoring and tuning.
public struct J2KMetalBufferPoolStatistics: Sendable {
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

// MARK: - Buffer Pool

/// Manages a pool of reusable Metal buffers for GPU operations.
///
/// `J2KMetalBufferPool` reduces allocation overhead by reusing Metal buffers
/// across operations. Buffers are matched by size and returned to the pool
/// when no longer needed.
///
/// ## Usage
///
/// ```swift
/// let pool = J2KMetalBufferPool()
///
/// // Acquire a buffer (may reuse pooled buffer)
/// let handle = try await pool.acquireBuffer(
///     device: metalDevice,
///     size: 4096,
///     strategy: .shared
/// )
///
/// // Use the buffer...
///
/// // Return buffer to pool for reuse
/// await pool.returnBuffer(handle)
/// ```
///
/// ## Memory Management
///
/// The pool automatically tracks memory usage and evicts old buffers
/// when limits are exceeded. Use ``drain()`` to release all pooled buffers.
public actor J2KMetalBufferPool {
    /// Whether Metal buffer pooling is available on this platform.
    public static var isAvailable: Bool {
        #if canImport(Metal)
        return true
        #else
        return false
        #endif
    }

    /// The pool configuration.
    public let configuration: J2KMetalBufferPoolConfiguration

    /// Pool usage statistics.
    private var _statistics = J2KMetalBufferPoolStatistics()

    #if canImport(Metal)
    /// Pooled buffers organized by size bucket for efficient matching.
    private var pool: [Int: [any MTLBuffer]] = [:]
    #endif

    /// Total memory currently used by pooled buffers.
    private var pooledMemory: UInt64 = 0

    /// Total count of buffers in the pool.
    private var pooledCount: Int = 0

    /// Creates a new buffer pool with the given configuration.
    ///
    /// - Parameter configuration: The pool configuration. Defaults to `.default`.
    public init(configuration: J2KMetalBufferPoolConfiguration = .default) {
        self.configuration = configuration
    }

    /// Returns the current pool statistics.
    ///
    /// - Returns: A snapshot of the pool statistics.
    public func statistics() -> J2KMetalBufferPoolStatistics {
        var stats = _statistics
        stats.currentPoolSize = pooledCount
        stats.currentPoolMemory = pooledMemory
        return stats
    }

    #if canImport(Metal)
    /// Acquires a Metal buffer of at least the specified size.
    ///
    /// If pooling is enabled and a suitable buffer exists in the pool, it is
    /// reused. Otherwise, a new buffer is allocated from the device.
    ///
    /// - Parameters:
    ///   - device: The Metal device to allocate from.
    ///   - size: The minimum buffer size in bytes.
    ///   - strategy: The memory allocation strategy. Defaults to the pool's default.
    /// - Returns: A Metal buffer of at least `size` bytes.
    /// - Throws: ``J2KError/internalError(_:)`` if allocation fails.
    public func acquireBuffer(
        device: any MTLDevice,
        size: Int,
        strategy: J2KMetalBufferAllocationStrategy? = nil
    ) throws -> any MTLBuffer {
        _statistics.totalAllocations += 1

        let bucketSize = sizeBucket(for: size)

        // Try to reuse a pooled buffer
        if configuration.enablePooling, let buffer = dequeueBuffer(size: bucketSize) {
            _statistics.poolHits += 1
            return buffer
        }

        // Allocate a new buffer
        _statistics.poolMisses += 1
        let effectiveStrategy = strategy ?? configuration.defaultStrategy
        let options = resourceOptions(for: effectiveStrategy)

        guard let buffer = device.makeBuffer(length: bucketSize, options: options) else {
            throw J2KError.internalError(
                "Failed to allocate Metal buffer of \(bucketSize) bytes"
            )
        }

        return buffer
    }

    /// Returns a buffer to the pool for potential reuse.
    ///
    /// The buffer is added to the pool if pooling is enabled and pool limits
    /// are not exceeded. Otherwise, the buffer is released immediately.
    ///
    /// - Parameter buffer: The buffer to return.
    public func returnBuffer(_ buffer: any MTLBuffer) {
        _statistics.totalReturns += 1

        guard configuration.enablePooling else { return }

        let bufferSize = buffer.length
        let memoryAfter = pooledMemory + UInt64(bufferSize)

        // Check pool limits
        guard pooledCount < configuration.maxPoolSize,
              memoryAfter <= configuration.maxPoolMemory else {
            return // Buffer is released (dropped)
        }

        let bucket = sizeBucket(for: bufferSize)
        if pool[bucket] == nil {
            pool[bucket] = []
        }
        pool[bucket]!.append(buffer)
        pooledCount += 1
        pooledMemory += UInt64(bufferSize)
    }
    #endif

    /// Drains all buffers from the pool, releasing their memory.
    public func drain() {
        #if canImport(Metal)
        pool.removeAll()
        #endif
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

    /// Rounds a size up to the nearest bucket size for efficient matching.
    private func sizeBucket(for size: Int) -> Int {
        // Round up to nearest power of 2, minimum 4096
        let minBucket = 4096
        guard size > minBucket else { return minBucket }

        var bucket = minBucket
        while bucket < size {
            bucket *= 2
        }
        return bucket
    }

    #if canImport(Metal)
    /// Dequeues a buffer from the pool matching the given size.
    private func dequeueBuffer(size: Int) -> (any MTLBuffer)? {
        guard var buffers = pool[size], !buffers.isEmpty else { return nil }

        let buffer = buffers.removeLast()
        pool[size] = buffers
        pooledCount -= 1
        pooledMemory -= UInt64(buffer.length)
        return buffer
    }

    /// Converts an allocation strategy to Metal resource options.
    private func resourceOptions(
        for strategy: J2KMetalBufferAllocationStrategy
    ) -> MTLResourceOptions {
        switch strategy {
        case .shared:
            return .storageModeShared
        case .managed:
            #if os(macOS)
            return .storageModeManaged
            #else
            return .storageModeShared
            #endif
        case .private:
            return .storageModePrivate
        }
    }
    #endif
}
