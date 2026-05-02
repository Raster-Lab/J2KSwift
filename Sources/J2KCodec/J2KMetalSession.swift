// J2KMetalSession.swift
//
// v5.6.0 (M3-prime): a long-lived bundle of Metal infrastructure
// that callers construct once and reuse across many decode calls,
// amortising the ~50–60 ms per-process Metal device init / shader
// compile cost the v5.5.0 perf report identified.
//
// Pattern:
//
//   let session = J2KMetalSession()
//   let decoder = J2KDecoder()
//   for data in batch {
//       let img = try await decoder.decodeWithGPUHT(data, session: session)
//   }
//
// The first `decodeWithGPUHT` call on a fresh session pays the
// shader compile cost (~50 ms on Apple M2). Every subsequent call
// reuses the cached MSL library, compute pipelines, and buffer
// pool — that's where the warm-process speedup comes from.
//
// All three underlying types are already actors (J2KMetalDevice,
// J2KMetalShaderLibrary) or wrap actor state (J2KMetalBufferPool,
// itself an actor), so the session is safe to share across
// concurrent decode calls. The session itself is a Sendable struct
// — sharing the references, not duplicating state.

import Foundation
import J2KCore
import J2KMetal

/// A reusable bundle of Metal infrastructure for warm-process
/// decode. Construct once at the SDK boundary; pass into
/// `J2KDecoder.decodeWithGPUHT(_:session:)` on every decode call
/// to amortise device init and shader compilation across calls.
///
/// The session is always available as a type, but its underlying
/// Metal objects only do real work when the GPU HT path is opted
/// into. On platforms without Metal (`canImport(Metal) == false`),
/// the session is a harmless no-op.
public struct J2KMetalSession: Sendable {
    /// Shared Metal device. Lazily initialised on first GPU dispatch.
    public let device: J2KMetalDevice

    /// Shared shader library. The first decode that touches it
    /// pays the ~50 ms MSL compile; subsequent decodes reuse the
    /// cached `MTLLibrary` and compute pipelines.
    public let shaderLibrary: J2KMetalShaderLibrary

    /// Shared buffer pool. Per-frame Metal buffers (descriptors,
    /// codestream, output, widths) come from here and are returned
    /// after each decode, so the pool's hit rate climbs with use.
    public let bufferPool: J2KMetalBufferPool

    /// Creates a session with a fresh device, library, and pool.
    /// All three are lazy: no Metal work happens until the first
    /// decode that uses this session.
    ///
    /// - Parameters:
    ///   - device: Optional pre-built `J2KMetalDevice`. Defaults to a fresh one.
    ///   - shaderLibrary: Optional pre-built `J2KMetalShaderLibrary`. Defaults to a fresh one.
    ///   - bufferPool: Optional pre-built `J2KMetalBufferPool`. Defaults to a fresh one.
    public init(
        device: J2KMetalDevice? = nil,
        shaderLibrary: J2KMetalShaderLibrary? = nil,
        bufferPool: J2KMetalBufferPool? = nil
    ) {
        self.device = device ?? J2KMetalDevice()
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
        self.bufferPool = bufferPool ?? J2KMetalBufferPool()
    }

    /// Whether GPU paths are usable on this platform — mirrors
    /// `J2KMetalDevice.isAvailable`.
    public static var isAvailable: Bool {
        J2KMetalDevice.isAvailable
    }
}
