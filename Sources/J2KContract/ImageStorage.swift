// SPDX-License-Identifier: MIT
import Foundation
import J2KCore
import Synchronization

/// An opaque lease value. Providers create a fresh token for each reservation and
/// compare it to their active token; allocation identity alone never grants access.
/// A token is Sendable but does not permit two simultaneous mutable borrows.
public struct StorageWriteLease: Sendable, Equatable, Hashable {
    private let nonce: UUID
    public init() { nonce = UUID() }
}

/// Implementers must retain sealed immutable storage for the full borrow lifetime.
/// Unsafe pointers must never escape the synchronous closure (including as its result).
/// Returning an escaped pointer is a caller error which Swift cannot prevent here.
public protocol ReadOnlyImageStorage: Sendable {
    var byteCount: Int { get }
    var allocationID: UUID { get }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R
}

/// Advanced providers own allocation retention and the shared lifecycle across all
/// wrappers/modules. Reject double reservation, overlapping/reentrant mutation,
/// forged/stale leases, read before seal and every write after seal/abort.
/// No pointer returned by an Array/Data borrow may be adopted as a storage owner.
public protocol WritableImageStorage: Sendable {
    var byteCount: Int { get }
    var allocationID: UUID { get }
    func reserveWrite() throws -> StorageWriteLease
    /// Pointer must not escape, be shared with concurrent work, or span `await`.
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R
    func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage
    func abortAndInvalidate(lease: StorageWriteLease) throws
}

/// A zero-initialised, independently owned allocation. The mutex protects the
/// array and lifecycle; no unsafe pointer is stored or marked Sendable.
/// A mutable borrow holds the mutex and competing/reentrant access fails promptly.
/// Sealing transfers the array reference to immutable storage without mutating or
/// cloning its contents. Sealed readers borrow concurrently from that immutable owner.
public final class OwnedImageStorage: WritableImageStorage, Sendable {
    public let byteCount: Int
    public let allocationID: UUID
    private enum Phase { case available, writing, sealed, invalid }
    private struct State: Sendable {
        var bytes: [UInt8]
        var phase: Phase = .available
        var lease: StorageWriteLease?
    }
    private let state: Mutex<State>

    public init(byteCount: Int, limits: ResourceLimits = .default) throws {
        try Task.checkCancellation()
        guard byteCount > 0 else { throw CodecError(.invalidArgument, "Storage capacity must be positive.") }
        guard byteCount <= limits.maximumDecodedBytes, byteCount <= limits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Storage allocation exceeds the admission budget.")
        }
        self.byteCount = byteCount; self.allocationID = UUID()
        self.state = Mutex(State(bytes: [UInt8](repeating: 0, count: byteCount)))
    }

    public func reserveWrite() throws -> StorageWriteLease {
        try locked { state in
            guard state.phase == .available else {
                throw CodecError(.storageUnavailable, "Storage already has a writer or is sealed/invalid.")
            }
            let lease = StorageWriteLease()
            state.lease = lease; state.phase = .writing
            return lease
        }
    }

    public func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        try locked { state in
            try Self.check(lease, state)
            return try state.bytes.withUnsafeMutableBytes(body)
        }
    }

    public func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage {
        try locked { state in
            try Self.check(lease, state)
            let sealed = SealedImageStorage(bytes: state.bytes, allocationID: allocationID)
            state.bytes = []
            state.lease = nil; state.phase = .sealed
            return sealed
        }
    }

    public func abortAndInvalidate(lease: StorageWriteLease) throws {
        try locked { state in
            try Self.check(lease, state)
            state.bytes = []
            state.lease = nil; state.phase = .invalid
        }
    }

    private static func check(_ lease: StorageWriteLease, _ state: borrowing State) throws {
        guard state.phase == .writing, state.lease == lease else {
            throw CodecError(.storageUnavailable, "Write lease is stale, foreign or unavailable.")
        }
    }

    private func locked<R>(_ body: (inout State) throws -> R) throws -> R {
        guard let result = try state.withLockIfAvailable({ state in try body(&state) }) else {
            throw CodecError(.storageUnavailable, "A storage borrow is already active.")
        }
        return result
    }
}

private final class SealedImageStorage: ReadOnlyImageStorage, Sendable {
    private let bytes: [UInt8]
    let allocationID: UUID
    var byteCount: Int { bytes.count }
    init(bytes: [UInt8], allocationID: UUID) {
        self.bytes = bytes; self.allocationID = allocationID
    }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R {
        try bytes.withUnsafeBytes(body)
    }
}
