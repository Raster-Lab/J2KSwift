// J2KMetalSharedBufferView.swift
//
// v7.2.0 Phase A — UMA encode-side boundary elimination.
//
// Wraps a `.storageModeShared` `MTLBuffer` as a typed, read-only view
// that exposes the buffer's CPU-visible memory directly via
// `UnsafeBufferPointer<Element>`. On Apple Silicon's unified memory
// architecture the GPU and CPU see the same physical pages for
// `.storageModeShared` buffers — so reading from `buffer.contents()`
// after a completed `MTLCommandBuffer` is zero-copy. This type lets
// downstream stages consume GPU output without the
// `Array(unsafeUninitializedCapacity:) + memcpy` step that
// `readInt32Array` (and equivalents) would otherwise perform.
//
// Lifetime
//
//   The view holds a strong reference to the underlying `MTLBuffer`.
//   When the view is deinitialised AND a buffer pool was provided at
//   construction, the buffer is spawned back into the pool via a
//   detached `Task`. Callers may also explicitly `release()` the
//   buffer earlier — the view becomes empty (count = 0) and any
//   further reads are undefined.
//
// Concurrency
//
//   Marked `@unchecked Sendable`. `MTLBuffer.contents()` is documented
//   as returning the same pointer across calls (the buffer's storage
//   doesn't relocate); safe to read concurrently with itself, not
//   safe to mutate while reading. This view is read-only by contract.

#if canImport(Metal)
import Metal
import Foundation

/// Read-only view over a typed slice of a `.storageModeShared`
/// `MTLBuffer`. Exposes the buffer's CPU-visible memory directly,
/// avoiding the readback memcpy that `Array(unsafeUninitializedCapacity:)
/// + memcpy(MTLBuffer.contents() → ptr)` would otherwise perform on
/// every GPU→CPU stage boundary.
///
/// Constructed by Metal pipelines after their command buffer has
/// completed; consumed by downstream CPU stages (entropy encoder,
/// rate-control, etc.) that previously read from `[Element]`.
public final class J2KMetalSharedBufferView<Element>: @unchecked Sendable {
    private let buffer: MTLBuffer
    private let pool: J2KMetalBufferPool?
    public private(set) var count: Int

    /// Creates a view over `buffer`'s first `count` `Element`s. The
    /// view holds a strong reference to `buffer`; if `pool` is
    /// provided, the buffer is returned to the pool when the view is
    /// deinitialised (or when `release()` is called explicitly).
    ///
    /// - Parameters:
    ///   - buffer: the underlying `.storageModeShared` MTLBuffer.
    ///   - count: number of `Element`s the buffer is logically
    ///     considered to hold (may be less than the buffer's
    ///     allocation; the buffer pool buckets are size-class based).
    ///   - pool: optional pool to return the buffer to on deinit.
    public init(
        buffer: MTLBuffer,
        count: Int,
        pool: J2KMetalBufferPool? = nil
    ) {
        self.buffer = buffer
        self.count = count
        self.pool = pool
    }

    /// Calls `body` with an `UnsafeBufferPointer<Element>` over the
    /// view's contents. The pointer is valid only for the duration
    /// of `body`; do not capture it.
    public func withUnsafeBufferPointer<R>(
        _ body: (UnsafeBufferPointer<Element>) throws -> R
    ) rethrows -> R {
        let ptr = buffer.contents().assumingMemoryBound(to: Element.self)
        let buf = UnsafeBufferPointer(start: ptr, count: count)
        // Counters: read this site as a `bufferContentsAccess` (no
        // memcpy follows). Phase 0 baseline used `incrementContents()`
        // to track readback boundaries; the view's purpose is to make
        // those zero. We record nothing here — the view IS the absence
        // of a readback boundary.
        return try body(buf)
    }

    /// Subscripts the underlying buffer at `index`. Bounds checked
    /// in debug builds via `precondition`. Hot-loop callers should
    /// prefer `withUnsafeBufferPointer` to avoid the per-access
    /// bounds check.
    public subscript(index: Int) -> Element {
        precondition(index >= 0 && index < count,
                     "J2KMetalSharedBufferView index \(index) out of range 0..<\(count)")
        return buffer.contents().assumingMemoryBound(to: Element.self)[index]
    }

    /// Explicitly returns the underlying buffer to the pool and
    /// invalidates this view (subsequent reads are undefined). Use
    /// this when the view's lifetime is shorter than its containing
    /// scope and the buffer should be recycled promptly. Idempotent
    /// (calling more than once is a no-op).
    public func release() {
        guard count > 0 else { return }
        let p = pool
        let buf = SendableBuffer(buffer)
        count = 0
        if let p {
            Task { await p.returnBuffer(buf.value) }
        }
    }

    deinit {
        // If `release()` was already called, count == 0 and the
        // buffer has been returned (or had no pool). Otherwise hand
        // the buffer back asynchronously now.
        guard count > 0, let pool else { return }
        let buf = SendableBuffer(buffer)
        Task { await pool.returnBuffer(buf.value) }
    }
}

/// `@unchecked Sendable` wrapper for `MTLBuffer` so the view's
/// Task closures can hand the buffer back to the pool without
/// tripping the strict-concurrency check. The view is read-only
/// by contract; the buffer pool's `returnBuffer` is the sole
/// mutation point and it's actor-isolated.
private struct SendableBuffer: @unchecked Sendable {
    let value: any MTLBuffer
    init(_ value: any MTLBuffer) { self.value = value }
}

#endif
