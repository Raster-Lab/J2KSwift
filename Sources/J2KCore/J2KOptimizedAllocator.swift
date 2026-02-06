/// # J2KOptimizedAllocator
///
/// Optimized memory allocation for JPEG 2000 pipeline stages.
///
/// This module provides arena-based allocation, pre-allocated scratch buffers,
/// and batch allocation to reduce overhead in the encoding/decoding pipeline.

import Foundation

/// An arena-based allocator that amortizes allocation costs.
///
/// `J2KArenaAllocator` pre-allocates a contiguous block of memory and hands out
/// slices from it. When the arena is full, it allocates a new block. All memory
/// is freed when the allocator is deallocated, avoiding per-object deallocation costs.
///
/// Example:
/// ```swift
/// let arena = J2KArenaAllocator(blockSize: 1024 * 1024) // 1MB blocks
/// let ptr = arena.allocate(byteCount: 256, alignment: 8)
/// // Use ptr...
/// // All memory freed when arena is deallocated
/// ```
public final class J2KArenaAllocator: @unchecked Sendable {
    /// A single block of allocated memory.
    private final class Block {
        let memory: UnsafeMutableRawPointer
        let capacity: Int
        var offset: Int = 0

        init(capacity: Int) {
            self.capacity = capacity
            self.memory = UnsafeMutableRawPointer.allocate(
                byteCount: capacity,
                alignment: MemoryLayout<UInt64>.alignment
            )
        }

        deinit {
            memory.deallocate()
        }

        /// Attempts to allocate from this block.
        ///
        /// - Parameters:
        ///   - byteCount: Number of bytes to allocate.
        ///   - alignment: Required alignment.
        /// - Returns: Pointer to allocated memory, or nil if insufficient space.
        func allocate(byteCount: Int, alignment: Int) -> UnsafeMutableRawPointer? {
            let alignedOffset = (offset + alignment - 1) & ~(alignment - 1)
            let end = alignedOffset + byteCount
            guard end <= capacity else { return nil }
            offset = end
            return memory.advanced(by: alignedOffset)
        }

        /// Remaining capacity in this block.
        var remaining: Int {
            capacity - offset
        }
    }

    /// The default block size.
    private let blockSize: Int

    /// All allocated blocks.
    private var blocks: [Block] = []

    /// Lock for thread safety.
    private let lock = NSLock()

    /// Total bytes allocated from this arena.
    private var totalAllocated: Int = 0

    /// Creates a new arena allocator.
    ///
    /// - Parameter blockSize: The size of each memory block (default: 1MB).
    public init(blockSize: Int = 1024 * 1024) {
        self.blockSize = blockSize
    }

    /// Allocates memory from the arena.
    ///
    /// - Parameters:
    ///   - byteCount: Number of bytes to allocate.
    ///   - alignment: Required alignment (default: 8).
    /// - Returns: Pointer to the allocated memory.
    public func allocate(byteCount: Int, alignment: Int = MemoryLayout<UInt64>.alignment) -> UnsafeMutableRawPointer {
        lock.lock()
        defer { lock.unlock() }

        // Try allocating from the current (last) block
        if let block = blocks.last, let ptr = block.allocate(byteCount: byteCount, alignment: alignment) {
            totalAllocated += byteCount
            return ptr
        }

        // Need a new block
        let newBlockSize = max(blockSize, byteCount + alignment)
        let block = Block(capacity: newBlockSize)
        blocks.append(block)

        guard let ptr = block.allocate(byteCount: byteCount, alignment: alignment) else {
            // Should never happen since we sized the block appropriately
            fatalError("Arena allocation failed for \(byteCount) bytes")
        }
        totalAllocated += byteCount
        return ptr
    }

    /// Resets the arena, making all previously allocated memory available for reuse.
    ///
    /// After reset, all pointers previously returned by `allocate` are invalid.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        // Keep the first block for reuse, drop the rest
        if let first = blocks.first {
            first.offset = 0
            blocks = [first]
        }
        totalAllocated = 0
    }

    /// Returns statistics about the arena.
    public var statistics: (blockCount: Int, totalCapacity: Int, totalAllocated: Int) {
        lock.lock()
        defer { lock.unlock() }
        let totalCapacity = blocks.reduce(0) { $0 + $1.capacity }
        return (blockCount: blocks.count, totalCapacity: totalCapacity, totalAllocated: totalAllocated)
    }
}

/// Pre-allocated scratch buffers for pipeline stages.
///
/// `J2KScratchBuffers` maintains a set of reusable temporary buffers
/// sized for common pipeline operations, avoiding repeated allocation
/// and deallocation during encoding/decoding.
///
/// Example:
/// ```swift
/// let scratch = J2KScratchBuffers(tileWidth: 256, tileHeight: 256)
/// scratch.withDWTBuffer { buffer in
///     // Use buffer for DWT computation
/// }
/// ```
public final class J2KScratchBuffers: @unchecked Sendable {
    /// The width of tiles this scratch set supports.
    public let tileWidth: Int

    /// The height of tiles this scratch set supports.
    public let tileHeight: Int

    /// Number of components.
    public let componentCount: Int

    /// Pre-allocated DWT row buffer.
    private let dwtBuffer: UnsafeMutableBufferPointer<Float>

    /// Pre-allocated quantization buffer.
    private let quantBuffer: UnsafeMutableBufferPointer<Int32>

    /// Pre-allocated temporary buffer for general use.
    private let tempBuffer: UnsafeMutableBufferPointer<UInt8>

    /// Lock for thread safety.
    private let lock = NSLock()

    /// Creates pre-allocated scratch buffers for the given tile dimensions.
    ///
    /// - Parameters:
    ///   - tileWidth: Width of tiles (default: 256).
    ///   - tileHeight: Height of tiles (default: 256).
    ///   - componentCount: Number of image components (default: 3).
    public init(tileWidth: Int = 256, tileHeight: Int = 256, componentCount: Int = 3) {
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        self.componentCount = componentCount

        let tileSize = tileWidth * tileHeight

        // DWT needs at least one row/column length
        let dwtSize = max(tileWidth, tileHeight) * 2
        self.dwtBuffer = .allocate(capacity: dwtSize)
        self.dwtBuffer.initialize(repeating: 0)

        // Quantization buffer: one full tile component
        self.quantBuffer = .allocate(capacity: tileSize)
        self.quantBuffer.initialize(repeating: 0)

        // Temp buffer: one full tile component in bytes
        self.tempBuffer = .allocate(capacity: tileSize * componentCount)
        self.tempBuffer.initialize(repeating: 0)
    }

    deinit {
        dwtBuffer.deallocate()
        quantBuffer.deallocate()
        tempBuffer.deallocate()
    }

    /// Provides access to the DWT scratch buffer.
    ///
    /// - Parameter body: Closure that receives the mutable buffer.
    /// - Returns: The result of the closure.
    /// - Throws: Rethrows any error from the closure.
    public func withDWTBuffer<Result>(
        _ body: (UnsafeMutableBufferPointer<Float>) throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(dwtBuffer)
    }

    /// Provides access to the quantization scratch buffer.
    ///
    /// - Parameter body: Closure that receives the mutable buffer.
    /// - Returns: The result of the closure.
    /// - Throws: Rethrows any error from the closure.
    public func withQuantizationBuffer<Result>(
        _ body: (UnsafeMutableBufferPointer<Int32>) throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(quantBuffer)
    }

    /// Provides access to the temporary scratch buffer.
    ///
    /// - Parameter body: Closure that receives the mutable buffer.
    /// - Returns: The result of the closure.
    /// - Throws: Rethrows any error from the closure.
    public func withTempBuffer<Result>(
        _ body: (UnsafeMutableBufferPointer<UInt8>) throws -> Result
    ) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(tempBuffer)
    }

    /// Returns the total memory allocated by these scratch buffers.
    public var totalMemory: Int {
        dwtBuffer.count * MemoryLayout<Float>.stride
            + quantBuffer.count * MemoryLayout<Int32>.stride
            + tempBuffer.count * MemoryLayout<UInt8>.stride
    }
}
