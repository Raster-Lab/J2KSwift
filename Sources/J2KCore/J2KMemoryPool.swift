/// # J2KMemoryPool
///
/// Memory pool for efficient temporary buffer allocation and reuse.
///
/// This module provides a memory pool that allows efficient allocation and reuse
/// of temporary buffers during JPEG 2000 encoding and decoding operations.

import Foundation

/// A memory pool for efficient temporary buffer allocation.
///
/// `J2KMemoryPool` maintains a pool of reusable buffers to minimize allocation
/// overhead during image processing operations. Buffers are automatically returned
/// to the pool when they are no longer needed.
///
/// The pool is thread-safe and can be used from multiple concurrent operations.
///
/// Example:
/// ```swift
/// let pool = J2KMemoryPool()
/// let buffer = pool.acquire(capacity: 4096)
/// // Use buffer...
/// pool.release(buffer)
/// ```
internal actor J2KMemoryPool {
    /// Configuration for the memory pool.
    internal struct Configuration: Sendable {
        /// Maximum number of buffers to keep in the pool.
        let maxBuffers: Int

        /// Maximum total memory to keep in the pool (in bytes).
        let maxTotalSize: Int

        /// Creates a new configuration.
        ///
        /// - Parameters:
        ///   - maxBuffers: Maximum number of buffers (default: 32).
        ///   - maxTotalSize: Maximum total size in bytes (default: 64MB).
        init(maxBuffers: Int = 32, maxTotalSize: Int = 64 * 1024 * 1024) {
            self.maxBuffers = maxBuffers
            self.maxTotalSize = maxTotalSize
        }
    }

    /// Entry in the pool.
    private struct PoolEntry {
        let buffer: J2KBuffer
        let lastUsed: Date
    }

    private var pool: [Int: [PoolEntry]] = [:]
    private var totalSize: Int = 0
    private let configuration: Configuration

    /// Creates a new memory pool with the specified configuration.
    ///
    /// - Parameter configuration: The pool configuration (default: default configuration).
    internal init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Acquires a buffer with at least the specified capacity.
    ///
    /// If a suitable buffer is available in the pool, it will be reused.
    /// Otherwise, a new buffer will be allocated.
    ///
    /// - Parameter capacity: The minimum required capacity in bytes.
    /// - Returns: A buffer with at least the requested capacity.
    internal func acquire(capacity: Int) -> J2KBuffer {
        // Round capacity to next power of 2 for better reuse
        let roundedCapacity = nextPowerOfTwo(capacity)

        // Try to find a buffer in the pool
        if var entries = pool[roundedCapacity], !entries.isEmpty {
            let entry = entries.removeFirst()
            pool[roundedCapacity] = entries
            totalSize -= roundedCapacity
            return entry.buffer
        }

        // No buffer available, create a new one
        return J2KBuffer(capacity: roundedCapacity)
    }

    /// Releases a buffer back to the pool for reuse.
    ///
    /// The buffer may be kept in the pool for future reuse, or it may be
    /// discarded if the pool is full.
    ///
    /// - Parameter buffer: The buffer to release.
    internal func release(_ buffer: J2KBuffer) {
        let capacity = buffer.capacity

        // Check if we can add to the pool
        if totalSize + capacity > configuration.maxTotalSize {
            // Pool is full, evict oldest entries
            evictOldestEntries(toFit: capacity)

            // Still can't fit after eviction, discard buffer
            guard totalSize + capacity <= configuration.maxTotalSize else {
                return
            }
        }

        // Add to pool
        let entry = PoolEntry(buffer: buffer, lastUsed: Date())
        if pool[capacity] == nil {
            pool[capacity] = []
        }
        pool[capacity]?.append(entry)
        totalSize += capacity

        // Trim if we have too many buffers
        trimPoolIfNeeded()
    }

    /// Clears all buffers from the pool.
    internal func clear() {
        pool.removeAll()
        totalSize = 0
    }

    /// Returns statistics about the pool.
    ///
    /// - Returns: A dictionary with pool statistics.
    internal func statistics() -> [String: Int] {
        let bufferCount = pool.values.reduce(0) { $0 + $1.count }
        return [
            "bufferCount": bufferCount,
            "totalSize": totalSize,
            "capacityBuckets": pool.keys.count
        ]
    }

    // MARK: - Private Methods

    private func nextPowerOfTwo(_ n: Int) -> Int {
        guard n > 0 else { return 1 }
        var result = 1
        while result < n {
            result *= 2
        }
        return result
    }

    private func evictOldestEntries(toFit requiredSpace: Int) {
        // Sort all entries by last used date
        var allEntries: [(capacity: Int, entry: PoolEntry)] = []
        for (capacity, entries) in pool {
            for entry in entries {
                allEntries.append((capacity: capacity, entry: entry))
            }
        }

        allEntries.sort { $0.entry.lastUsed < $1.entry.lastUsed }

        // Evict oldest entries until we have enough space
        var freedSpace = 0
        var indicesToRemove: [(capacity: Int, index: Int)] = []

        for item in allEntries {
            guard totalSize - freedSpace + requiredSpace > configuration.maxTotalSize else {
                break
            }

            if let index = pool[item.capacity]?.firstIndex(where: {
                $0.lastUsed == item.entry.lastUsed
            }) {
                indicesToRemove.append((capacity: item.capacity, index: index))
                freedSpace += item.capacity
            }
        }

        // Remove entries (in reverse order to maintain indices)
        for (capacity, index) in indicesToRemove.reversed() {
            pool[capacity]?.remove(at: index)
            totalSize -= capacity
        }
    }

    private func trimPoolIfNeeded() {
        let totalBuffers = pool.values.reduce(0) { $0 + $1.count }
        guard totalBuffers > configuration.maxBuffers else { return }

        // Remove excess buffers (oldest first)
        var allEntries: [(capacity: Int, entry: PoolEntry)] = []
        for (capacity, entries) in pool {
            for entry in entries {
                allEntries.append((capacity: capacity, entry: entry))
            }
        }

        allEntries.sort { $0.entry.lastUsed < $1.entry.lastUsed }

        let toRemove = totalBuffers - configuration.maxBuffers
        for i in 0..<min(toRemove, allEntries.count) {
            let item = allEntries[i]
            if let index = pool[item.capacity]?.firstIndex(where: {
                $0.lastUsed == item.entry.lastUsed
            }) {
                pool[item.capacity]?.remove(at: index)
                totalSize -= item.capacity
            }
        }
    }
}
