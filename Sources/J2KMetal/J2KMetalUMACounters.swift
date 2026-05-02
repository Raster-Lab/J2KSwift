// J2KMetalUMACounters.swift
//
// v5.9 UMA-plan instrumentation prerequisite. Tight, disposable.
//
// Three process-global counters tracked via a single NSLock-protected
// enum namespace:
//
//   - memcpyCount                — readback memcpy boundaries
//   - bufferContentsAccessCount  — MTLBuffer.contents() reads
//   - makeBufferCount            — MTLDevice.makeBuffer allocations
//
// Always-on (NSLock overhead ≈ tens of nanoseconds per increment;
// negligible against the millisecond-scale operations they bracket).
// Designed to be deleted as a unit: remove this file, remove the
// `J2KMetalUMACounters.increment*` call sites with a single
// regex sweep, and the codebase is back to v5.8.0 surface.
//
// Tests snapshot + reset around the hot path to get per-decode
// numbers; see `testCorpusWarmProcessPerf` for the canonical
// usage pattern.
//
// Caveat: counters are PROCESS-global, not session-scoped. Tests
// that run in parallel within one process will see interleaved
// counts; snapshot/reset around a single decode in a single test
// case for accurate per-decode numbers.

import Foundation

/// Global UMA-instrumentation counters. Increment at boundary
/// points; snapshot at test/measurement boundaries.
public enum J2KMetalUMACounters {
    nonisolated(unsafe) private static let lock = NSLock()
    nonisolated(unsafe) private static var _memcpyCount: Int = 0
    nonisolated(unsafe) private static var _bufferContentsAccessCount: Int = 0
    nonisolated(unsafe) private static var _makeBufferCount: Int = 0

    /// Snapshot of all three counters at a point in time.
    public struct Snapshot: Sendable, CustomStringConvertible {
        public let memcpyCount: Int
        public let bufferContentsAccessCount: Int
        public let makeBufferCount: Int

        public var description: String {
            "memcpy=\(memcpyCount) contents=\(bufferContentsAccessCount) makeBuffer=\(makeBufferCount)"
        }
    }

    /// Increment the memcpy counter. Call once per
    /// `buffer.contents() → memcpy → Array<T>` readback boundary
    /// (or per equivalent CPU↔GPU memory transfer).
    public static func incrementMemcpy(_ n: Int = 1) {
        lock.lock(); _memcpyCount += n; lock.unlock()
    }

    /// Increment the buffer-contents-access counter. Call once per
    /// `MTLBuffer.contents()` invocation. After v5.10's storage-mode
    /// pass, this counter for `.storageModePrivate` buffers must be
    /// zero — that's the gate.
    public static func incrementContents(_ n: Int = 1) {
        lock.lock(); _bufferContentsAccessCount += n; lock.unlock()
    }

    /// Increment the makeBuffer counter. Call once per
    /// `MTLDevice.makeBuffer(length:options:)` invocation. After
    /// v5.11's MTLHeap pool, this should be a single-digit
    /// per-decode (initial heap allocation + true overflow only).
    public static func incrementMakeBuffer(_ n: Int = 1) {
        lock.lock(); _makeBufferCount += n; lock.unlock()
    }

    /// Read all three counters atomically.
    public static func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            memcpyCount: _memcpyCount,
            bufferContentsAccessCount: _bufferContentsAccessCount,
            makeBufferCount: _makeBufferCount)
    }

    /// Reset all three counters to zero atomically. Tests typically
    /// reset before a decode and snapshot after.
    public static func reset() {
        lock.lock()
        _memcpyCount = 0
        _bufferContentsAccessCount = 0
        _makeBufferCount = 0
        lock.unlock()
    }
}
