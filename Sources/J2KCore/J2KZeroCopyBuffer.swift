/// # J2KZeroCopyBuffer
///
/// Zero-copy buffer views for efficient data passing between pipeline stages.
///
/// This module provides buffer types that allow sharing data between stages
/// without copying, using borrowed views and immutable shared regions.

import Foundation

/// A read-only view into a region of a buffer without copying data.
///
/// `J2KBufferSlice` provides zero-copy access to a sub-region of an existing
/// buffer. The slice borrows the underlying memory and is valid only while the
/// source buffer remains alive.
///
/// Example:
/// ```swift
/// let buffer = J2KZeroCopyBuffer(data: imageData)
/// let slice = buffer.slice(offset: 0, count: 1024)
/// slice.withUnsafeBytes { ptr in
///     // Read first 1024 bytes without copying
/// }
/// ```
public struct J2KBufferSlice: Sendable {
    /// The underlying shared storage.
    private let storage: J2KSharedBuffer

    /// The byte offset into the storage.
    public let offset: Int

    /// The number of bytes in this slice.
    public let count: Int

    /// Creates a new buffer slice.
    ///
    /// - Parameters:
    ///   - storage: The shared buffer providing the underlying memory.
    ///   - offset: The byte offset into the storage.
    ///   - count: The number of bytes in this slice.
    internal init(storage: J2KSharedBuffer, offset: Int, count: Int) {
        self.storage = storage
        self.offset = offset
        self.count = count
    }

    /// Provides read-only access to the slice's bytes.
    ///
    /// - Parameter body: A closure that receives the buffer pointer.
    /// - Returns: The result of the closure.
    /// - Throws: Rethrows any error from the closure.
    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try storage.withUnsafeBytes { fullPtr in
            let slicePtr = UnsafeRawBufferPointer(
                start: fullPtr.baseAddress?.advanced(by: offset),
                count: count
            )
            return try body(slicePtr)
        }
    }

    /// Creates a sub-slice of this slice.
    ///
    /// - Parameters:
    ///   - subOffset: The offset within this slice.
    ///   - subCount: The number of bytes in the sub-slice.
    /// - Returns: A new slice, or nil if the range is out of bounds.
    public func subSlice(offset subOffset: Int, count subCount: Int) -> J2KBufferSlice? {
        guard subOffset >= 0, subCount >= 0, subOffset + subCount <= count else {
            return nil
        }
        return J2KBufferSlice(storage: storage, offset: offset + subOffset, count: subCount)
    }

    /// Copies the slice contents to a new Data object.
    ///
    /// Use this only when a copy is actually needed.
    ///
    /// - Returns: A Data copy of the slice contents.
    public func toData() -> Data {
        withUnsafeBytes { ptr in
            Data(ptr)
        }
    }
}

/// An immutable shared buffer that supports zero-copy slicing.
///
/// `J2KSharedBuffer` holds a reference-counted immutable block of memory.
/// Multiple `J2KBufferSlice` instances can reference non-overlapping or
/// overlapping regions of the same shared buffer without copying.
///
/// Example:
/// ```swift
/// let shared = J2KSharedBuffer(data: rawImageData)
/// let component0 = shared.slice(offset: 0, count: width * height)
/// let component1 = shared.slice(offset: width * height, count: width * height)
/// ```
public final class J2KSharedBuffer: @unchecked Sendable {
    /// The underlying memory.
    private let buffer: UnsafeMutableRawBufferPointer

    /// The total capacity of the buffer.
    public let capacity: Int

    /// Creates a shared buffer by copying the given data.
    ///
    /// - Parameter data: The data to store.
    public init(data: Data) {
        self.capacity = data.count
        self.buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: max(data.count, 1),
            alignment: MemoryLayout<UInt64>.alignment
        )
        data.withUnsafeBytes { src in
            buffer.copyMemory(from: src)
        }
    }

    /// Creates a shared buffer by taking ownership of existing raw bytes.
    ///
    /// - Parameters:
    ///   - bytes: Pointer to the bytes.
    ///   - count: Number of bytes.
    public init(copying bytes: UnsafeRawBufferPointer, count: Int) {
        self.capacity = count
        self.buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: max(count, 1),
            alignment: MemoryLayout<UInt64>.alignment
        )
        buffer.copyMemory(from: UnsafeRawBufferPointer(start: bytes.baseAddress, count: count))
    }

    /// Creates an empty shared buffer with the given capacity.
    ///
    /// - Parameter capacity: The buffer capacity in bytes.
    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = UnsafeMutableRawBufferPointer.allocate(
            byteCount: max(capacity, 1),
            alignment: MemoryLayout<UInt64>.alignment
        )
        buffer.initializeMemory(as: UInt8.self, repeating: 0)
    }

    deinit {
        buffer.deallocate()
    }

    /// Provides read-only access to the entire buffer.
    ///
    /// - Parameter body: A closure that receives the buffer pointer.
    /// - Returns: The result of the closure.
    /// - Throws: Rethrows any error from the closure.
    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try body(UnsafeRawBufferPointer(buffer))
    }

    /// Creates a zero-copy slice of this buffer.
    ///
    /// - Parameters:
    ///   - offset: The byte offset.
    ///   - count: The number of bytes.
    /// - Returns: A slice, or nil if the range is out of bounds.
    public func slice(offset: Int, count: Int) -> J2KBufferSlice? {
        guard offset >= 0, count >= 0, offset + count <= capacity else {
            return nil
        }
        return J2KBufferSlice(storage: self, offset: offset, count: count)
    }

    /// Creates a zero-copy slice covering the entire buffer.
    ///
    /// - Returns: A slice covering all bytes.
    public func fullSlice() -> J2KBufferSlice {
        J2KBufferSlice(storage: self, offset: 0, count: capacity)
    }

    /// Converts the entire buffer to Data.
    ///
    /// - Returns: A Data copy of the buffer contents.
    public func toData() -> Data {
        guard let base = buffer.baseAddress else { return Data() }
        return Data(bytes: base, count: capacity)
    }
}

/// A zero-copy buffer that wraps existing data without copying.
///
/// `J2KZeroCopyBuffer` provides a unified interface for working with
/// data that may come from various sources (Data, raw pointers, shared buffers)
/// while minimizing copies.
///
/// Example:
/// ```swift
/// let buffer = J2KZeroCopyBuffer(data: fileData)
/// let header = buffer.slice(offset: 0, count: 12)
/// let payload = buffer.slice(offset: 12, count: buffer.count - 12)
/// ```
public struct J2KZeroCopyBuffer: Sendable {
    /// The shared storage backing this buffer.
    private let storage: J2KSharedBuffer

    /// The total number of bytes in the buffer.
    public var count: Int {
        storage.capacity
    }

    /// Creates a zero-copy buffer from Data.
    ///
    /// Note: This creates a single copy of the data into managed memory.
    /// All subsequent slicing operations are zero-copy.
    ///
    /// - Parameter data: The data to wrap.
    public init(data: Data) {
        self.storage = J2KSharedBuffer(data: data)
    }

    /// Creates a zero-copy buffer with an empty allocation.
    ///
    /// - Parameter capacity: The capacity in bytes.
    public init(capacity: Int) {
        self.storage = J2KSharedBuffer(capacity: capacity)
    }

    /// Creates a zero-copy buffer from a shared buffer.
    ///
    /// - Parameter sharedBuffer: The shared buffer to wrap.
    public init(sharedBuffer: J2KSharedBuffer) {
        self.storage = sharedBuffer
    }

    /// Creates a zero-copy slice of this buffer.
    ///
    /// - Parameters:
    ///   - offset: The byte offset.
    ///   - count: The number of bytes.
    /// - Returns: A slice, or nil if the range is out of bounds.
    public func slice(offset: Int, count: Int) -> J2KBufferSlice? {
        storage.slice(offset: offset, count: count)
    }

    /// Creates a zero-copy slice covering the entire buffer.
    ///
    /// - Returns: A slice covering all bytes.
    public func fullSlice() -> J2KBufferSlice {
        storage.fullSlice()
    }

    /// Provides read-only access to the buffer's bytes.
    ///
    /// - Parameter body: A closure that receives the buffer pointer.
    /// - Returns: The result of the closure.
    /// - Throws: Rethrows any error from the closure.
    public func withUnsafeBytes<Result>(
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) rethrows -> Result {
        try storage.withUnsafeBytes(body)
    }

    /// Converts to Data (copies).
    ///
    /// - Returns: A Data copy of the buffer contents.
    public func toData() -> Data {
        storage.toData()
    }
}
