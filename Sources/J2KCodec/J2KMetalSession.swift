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

    /// v5.28.0 — pre-warm the GPU decode path so the first user
    /// decode doesn't pay the ~50 ms cold-start cost (Metal device
    /// init + shader library load + pipeline state creation +
    /// first-dispatch driver overhead).
    ///
    /// Recommended at SDK / app startup for warm-process workflows
    /// (PACS daemons, batch decoders, server-side worker pools).
    /// Safe to skip for genuine one-off CLI use, where the cold-
    /// start cost is amortised over the whole process anyway.
    ///
    /// What this does (in order):
    /// 1. Initialises `J2KMetalDevice` (creates `MTLDevice` and
    ///    `MTLCommandQueue`).
    /// 2. Loads the shader library (`default.metallib` from the
    ///    bundle, or source-compiles the inline kernel string).
    ///    This is the dominant ~50 ms first-process cost.
    /// 3. Pre-creates `MTLComputePipelineState` for every decode-
    ///    hot-path kernel, in parallel.
    /// 4. Runs a tiny synthetic decode on this session to exercise
    ///    the rest of the lazy-init paths (VLC table upload, buffer
    ///    pool first-fetch, Metal driver first-dispatch fence). The
    ///    decode is small enough that this step costs only a few
    ///    milliseconds; the saving on the next user decode is
    ///    typically 10–20 ms.
    ///
    /// Encode-side kernels are not pre-warmed here — encode callers
    /// should add their own pre-warm if needed.
    ///
    /// Idempotent: subsequent calls are cheap (steps 1–3 are no-ops
    /// after the first call; step 4 still runs a tiny decode).
    /// Thread-safe via the underlying actors' isolation.
    ///
    /// - Parameters:
    ///   - includeWarmupDispatch: when true (default) runs the tiny
    ///     synthetic decode in step 4. Set false to skip if the
    ///     caller wants only shader-pipeline compilation (e.g. for
    ///     measuring cold-start overhead in benchmarks).
    public func preWarm(includeWarmupDispatch: Bool = true) async throws {
        guard J2KMetalSession.isAvailable else { return }

        #if canImport(Metal)
        try await device.initialize()
        let queue = try await device.commandQueue()
        try await shaderLibrary.loadShaders(device: queue.device)

        // Decode-hot-path pipelines. Pre-compile in parallel so we
        // don't serialise the per-pipeline cost.
        let decodePipelines: [J2KMetalShaderFunction] = [
            .htCleanupDecode,
            .htDequant,
            .subbandScatterFloatDequant,    // v5.26.0
            .dwtInverse97Horizontal,
            .dwtInverse97Vertical,
            .subbandScatter,
            .dwtInverse53HorizontalInt,
            .dwtInverse53VerticalInt,
            .dwtInverse53Horizontal,
            .dwtInverse53Vertical,
            .dequantize,
        ]

        let lib = self.shaderLibrary
        try await withThrowingTaskGroup(of: Void.self) { group in
            for fn in decodePipelines {
                group.addTask {
                    _ = try await lib.computePipeline(for: fn)
                }
            }
            try await group.waitForAll()
        }

        guard includeWarmupDispatch else { return }

        // Tiny synthetic 256×256 16-bit lossy 9/7 conformant decode —
        // exercises the GPU HT cleanup kernel + scatter+dequant +
        // multi-level fused IDWT, plus the VLC table upload and
        // buffer pool first-fetch. Encoded once, decoded once. The
        // dispatch latency is dominated by Metal driver state init,
        // which is exactly what we want to pay here instead of on
        // the user's first decode.
        let warmupImage = J2KMetalSession.makeWarmupImage(side: 256)
        var cfg = J2KEncodingConfiguration(
            quality: 1.0, lossless: false,
            decompositionLevels: 5, qualityLayers: 1,
            progressionOrder: .lrcp, useHTJ2K: true,
            useReversibleFilter: false,
            htj2kBlockFormat: .conformant)
        cfg.bitrateMode = .constantBitrate(bitsPerPixel: 2.0)
        let encoded = try await J2KEncoder(encodingConfiguration: cfg).encode(warmupImage)
        _ = try await J2KDecoder().decodeWithGPUHT(encoded, session: self)
        #endif
    }

    /// Build a small synthetic 16-bit image used by `preWarm`'s
    /// warmup-dispatch step. LCG-derived noise; small enough that
    /// encode + decode add up to a few milliseconds.
    private static func makeWarmupImage(side: Int) -> J2KImage {
        var bytes = [UInt8](repeating: 0, count: side * side * 2)
        var s: UInt64 = 0xfeed_face
        for i in 0..<(side * side) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            let v = Int(s >> 48) & 0xFFFF
            bytes[i * 2]     = UInt8((v >> 8) & 0xFF)
            bytes[i * 2 + 1] = UInt8(v & 0xFF)
        }
        return J2KImage(
            width: side, height: side,
            components: [J2KComponent(
                index: 0, bitDepth: 16, signed: false,
                width: side, height: side,
                data: Data(bytes), sampleByteOrder: .bigEndian)])
    }
}
