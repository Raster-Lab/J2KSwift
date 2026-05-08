// J2KGPUForwardHTCleanupPassEmit.swift
//
// v7.1.0 I1.3b — Swift orchestrator for the unified Pass 3
// cleanup-pass + 3-stream emit kernel (single-block spike). The
// kernel `j2k_ht_cleanup_pass_emit_block` lives in
// `Sources/J2KMetal/J2KShaders.metal`; this wrapper lives in
// J2KCodec because it needs the CPU's `vlcTable0Conformant`,
// `vlcTable1Conformant`, `uvlcTableConformant`, `melExpConformant`
// constants — those are J2KCodec-internal and J2KMetal can't import
// J2KCodec (the dependency direction is J2KCodec → J2KMetal).
//
// Direct port of `HTBlockEncoderConformant.encode(preClassifiedTuples:)`
// from `J2KHTConformantBlockEncoder.swift`. Per the I1.3 design doc:
// per-block byte budgets cannot be derived from per-sample
// classification alone — they depend on the cleanup-pass state
// machine. So Pass 3 is one unified per-block kernel. The bit-
// packing primitives proven in I1.2 / I1.2b / I1.2c / I1.2d are
// inlined inside the kernel (MSL forbids kernel-from-kernel calls).
//
// **Scope**: I1.3b is single-block only. Multi-block dispatch
// (one threadgroup per block, the production shape) is I1.3c.
// Production wire-in + corpus A/B is I1.3d.

import Foundation
import J2KCore
import J2KMetal

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Unified Pass 3 cleanup-pass kernel — Pass 1 (classifier) + state
/// machine + bit-packing for all three streams in one per-block
/// kernel. Bit-exact with `HTBlockEncoderConformant.encode(preClassifiedTuples:)`.
public struct J2KGPUForwardHTCleanupPassEmit: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    /// Result of a single-block emit — three byte streams.
    public struct EmitResult: Sendable {
        public let magsgn: [UInt8]
        public let mel: [UInt8]
        public let vlc: [UInt8]
    }

    /// Per-block descriptor for batched dispatch.
    public struct BlockDescriptor: Sendable {
        /// Block width (samples).
        public let width: Int
        /// Block height (samples).
        public let height: Int
        /// `missingMSBs` for the block (matches CPU
        /// `HTBlockEncoderConformant.encode`'s parameter). Implicit
        /// in the tuple payloads, retained for parity.
        public let missingMSBs: Int
        /// Tuples for this block. Length must equal `width × height`.
        public let tuples: [UInt64]
        public init(width: Int, height: Int, missingMSBs: Int, tuples: [UInt64]) {
            precondition(tuples.count == width * height)
            precondition(width <= 64 && height <= 64,
                         "J2KGPUForwardHTCleanupPassEmit: I1.3 supports up to 64×64 blocks")
            self.width = width
            self.height = height
            self.missingMSBs = missingMSBs
            self.tuples = tuples
        }
    }

    /// Result of a batched emit — three byte streams per block.
    public struct BatchedResult: Sendable {
        public let perBlockMagsgn: [[UInt8]]
        public let perBlockMel: [[UInt8]]
        public let perBlockVlc: [[UInt8]]
    }

    /// **v7.1.0 perf** — per-block descriptor for the *flat* API,
    /// where the caller already has a single concatenated UInt64
    /// tuples buffer (typical when the GPU classifier just produced
    /// it). Skips the per-block array slice + re-concat round-trip
    /// that the original `BlockDescriptor` API forces. Saves O(n)
    /// per-block CPU time for large batches.
    public struct FlatBlockDescriptor: Sendable {
        public let width: Int
        public let height: Int
        public let missingMSBs: Int
        /// Index into the flat tuples buffer where this block's
        /// tuples start.
        public let tupleStart: Int
        public init(width: Int, height: Int, missingMSBs: Int, tupleStart: Int) {
            precondition(width <= 64 && height <= 64,
                         "J2KGPUForwardHTCleanupPassEmit: I1.3 supports up to 64×64 blocks")
            self.width = width
            self.height = height
            self.missingMSBs = missingMSBs
            self.tupleStart = tupleStart
        }
    }

    /// Per-stream upper-bound capacity for a block of size
    /// `width × height`. Worst-case bound:
    ///   - MagSgn: each significant sample emits up to ~32 bits;
    ///     with FF-stuff (overhead 8/7) → ~5 bytes per sample.
    ///   - MEL: bounded by quad count × few bits → ≤ 1 byte per sample.
    ///   - VLC: per-quad codeword ≤ 12 bits + UVLC ≤ 32 bits per pair
    ///     → ≤ 1 byte per sample.
    /// Take `5 * width * height` plus a small fixed slack as the
    /// per-stream cap; ensures the kernel never overruns the per-
    /// block region. The cap is rounded up to a multiple of 4 to
    /// preserve the I1.2b byte-store RMW alignment requirement.
    @inline(__always)
    public static func perStreamCap(forBlockWidth w: Int, height h: Int) -> Int {
        let raw = max(64, 5 * w * h + 16)
        return (raw + 3) & ~3   // 4-byte aligned
    }

    /// Largest per-stream cap across a batch — used to size the
    /// shared output buffer. Each block's region starts at
    /// `i * cap` (cap-aligned, so already 4-byte aligned).
    @inline(__always)
    private static func perStreamCap(for blocks: [BlockDescriptor]) -> Int {
        var cap = 0
        for b in blocks {
            cap = max(cap, perStreamCap(forBlockWidth: b.width, height: b.height))
        }
        return cap
    }

    @inline(__always)
    private static func perStreamCap(for blocks: [FlatBlockDescriptor]) -> Int {
        var cap = 0
        for b in blocks {
            cap = max(cap, perStreamCap(forBlockWidth: b.width, height: b.height))
        }
        return cap
    }

    #if canImport(Metal)
    /// Run the unified cleanup-pass kernel on a single codeblock's
    /// pre-classified tuple stream. Convenience wrapper over
    /// `emitBlocks(_:)` for blockCount=1.
    public func emitBlock(tuples: [UInt64],
                          width: Int,
                          height: Int,
                          missingMSBs: Int) async throws -> EmitResult {
        let result = try await emitBlocks([
            BlockDescriptor(width: width, height: height,
                            missingMSBs: missingMSBs, tuples: tuples)
        ])
        return EmitResult(magsgn: result.perBlockMagsgn[0],
                          mel: result.perBlockMel[0],
                          vlc: result.perBlockVlc[0])
    }

    /// Batched emit — one threadgroup per block, dispatched in
    /// parallel. Bit-exact with running
    /// `HTBlockEncoderConformant.encode(preClassifiedTuples:)` on
    /// each block in isolation.
    ///
    /// **Performance**: this overload allocates per-block tuple
    /// arrays inside each `BlockDescriptor`. For callers that
    /// already have a flat tuples buffer (e.g. directly from the
    /// GPU classifier output), prefer `emitBlocksFlat(tuples:blocks:)`
    /// which skips the per-block array allocation + re-concatenation.
    public func emitBlocks(_ blocks: [BlockDescriptor]) async throws -> BatchedResult {
        if blocks.isEmpty {
            return BatchedResult(perBlockMagsgn: [], perBlockMel: [], perBlockVlc: [])
        }

        // Build a flat tuples buffer + flat descriptors, then delegate
        // to the canonical implementation.
        var totalCount = 0
        var flat = [FlatBlockDescriptor]()
        flat.reserveCapacity(blocks.count)
        for b in blocks {
            flat.append(FlatBlockDescriptor(
                width: b.width, height: b.height,
                missingMSBs: b.missingMSBs, tupleStart: totalCount))
            totalCount += b.tuples.count
        }
        var tuples = [UInt64](); tuples.reserveCapacity(totalCount)
        for b in blocks { tuples.append(contentsOf: b.tuples) }
        return try await emitBlocksFlat(tuples: tuples, blocks: flat)
    }

    /// **v7.1.0 perf** — canonical batched emit. Takes a single flat
    /// tuples buffer and per-block descriptors that index into it.
    /// Saves the per-block array allocation + re-concatenation that
    /// the original `emitBlocks([BlockDescriptor])` path forces.
    ///
    /// - Parameters:
    ///   - tuples: concatenated UInt64 tuple stream across all blocks,
    ///     in the order indicated by `blocks[i].tupleStart`. Same
    ///     format as the GPU classifier's output buffer.
    ///   - blocks: per-block descriptors with width/height/missingMSBs
    ///     + tupleStart offset into `tuples`.
    /// - Returns: per-block (magsgn, mel, vlc) byte streams.
    public func emitBlocksFlat(
        tuples: [UInt64],
        blocks: [FlatBlockDescriptor]
    ) async throws -> BatchedResult {
        if blocks.isEmpty {
            return BatchedResult(perBlockMagsgn: [], perBlockMel: [], perBlockVlc: [])
        }

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let blockCount = blocks.count
        let cap = Self.perStreamCap(for: blocks)
        let perStreamRegion = blockCount * cap

        let totalTupleCount = tuples.count
        let tuplesBytes = max(MemoryLayout<UInt64>.stride,
                              totalTupleCount * MemoryLayout<UInt64>.stride)
        let dimsBytes = blockCount * MemoryLayout<SIMD4<UInt32>>.stride
        let offsetBytes = blockCount * MemoryLayout<UInt32>.stride
        let countsBytes = blockCount * MemoryLayout<SIMD3<UInt32>>.stride

        // Cached lookup tables (uploaded once per device, reused
        // across all subsequent dispatches in the same process).
        let cached = try Self.cachedTableBuffers(device: device)

        guard let tuplesBuf = device.makeBuffer(length: tuplesBytes, options: .storageModeShared),
              let dimsBuf = device.makeBuffer(length: dimsBytes, options: .storageModeShared),
              let magsgnBuf = device.makeBuffer(length: perStreamRegion, options: .storageModeShared),
              let melBuf = device.makeBuffer(length: perStreamRegion, options: .storageModeShared),
              let vlcBuf = device.makeBuffer(length: perStreamRegion, options: .storageModeShared),
              let magsgnOffBuf = device.makeBuffer(length: offsetBytes, options: .storageModeShared),
              let melOffBuf = device.makeBuffer(length: offsetBytes, options: .storageModeShared),
              let vlcOffBuf = device.makeBuffer(length: offsetBytes, options: .storageModeShared),
              let countsBuf = device.makeBuffer(length: countsBytes, options: .storageModeShared)
        else {
            throw J2KError.internalError("J2KGPUForwardHTCleanupPassEmit: failed to allocate Metal buffers")
        }

        // Single bulk memcpy of the flat tuples buffer (vs N per-block
        // copy loops in the legacy path).
        if totalTupleCount > 0 {
            tuples.withUnsafeBufferPointer { src in
                tuplesBuf.contents().copyMemory(
                    from: src.baseAddress!,
                    byteCount: totalTupleCount * MemoryLayout<UInt64>.stride)
            }
        }

        let dimsPtr = dimsBuf.contents().bindMemory(to: SIMD4<UInt32>.self, capacity: blockCount)
        let msOffPtr = magsgnOffBuf.contents().bindMemory(to: UInt32.self, capacity: blockCount)
        let melOffPtr = melOffBuf.contents().bindMemory(to: UInt32.self, capacity: blockCount)
        let vlcOffPtr = vlcOffBuf.contents().bindMemory(to: UInt32.self, capacity: blockCount)
        for (i, b) in blocks.enumerated() {
            dimsPtr[i] = SIMD4<UInt32>(
                UInt32(b.width), UInt32(b.height),
                UInt32(b.missingMSBs), UInt32(b.tupleStart))
            msOffPtr[i] = UInt32(i * cap)
            melOffPtr[i] = UInt32(i * cap)
            vlcOffPtr[i] = UInt32(i * cap)
        }
        memset(countsBuf.contents(), 0, countsBytes)

        let pipeline = try await shaderLibrary.computePipeline(for: .htCleanupPassEmitBlocksBatched)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder()
        else {
            throw J2KError.internalError("J2KGPUForwardHTCleanupPassEmit: failed to create command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(tuplesBuf, offset: 0, index: 0)
        encoder.setBuffer(dimsBuf, offset: 0, index: 1)
        encoder.setBuffer(cached.vlc0, offset: 0, index: 2)
        encoder.setBuffer(cached.vlc1, offset: 0, index: 3)
        encoder.setBuffer(cached.uvlc, offset: 0, index: 4)
        cached.melExp.withUnsafeBytes { raw in
            encoder.setBytes(raw.baseAddress!, length: raw.count, index: 5)
        }
        encoder.setBuffer(magsgnBuf, offset: 0, index: 6)
        encoder.setBuffer(magsgnOffBuf, offset: 0, index: 7)
        encoder.setBuffer(melBuf, offset: 0, index: 8)
        encoder.setBuffer(melOffBuf, offset: 0, index: 9)
        encoder.setBuffer(vlcBuf, offset: 0, index: 10)
        encoder.setBuffer(vlcOffBuf, offset: 0, index: 11)
        encoder.setBuffer(countsBuf, offset: 0, index: 12)
        var blockCountU32 = UInt32(blockCount)
        encoder.setBytes(&blockCountU32, length: MemoryLayout<UInt32>.stride, index: 13)

        let tg = MTLSize(width: 32, height: 1, depth: 1)
        let groupCount = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groupCount, threadsPerThreadgroup: tg)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()

        // Slice per-block bytes from the shared output buffers.
        let counts = countsBuf.contents().bindMemory(to: SIMD3<UInt32>.self, capacity: blockCount)
        var perBlockMagsgn: [[UInt8]] = []
        var perBlockMel: [[UInt8]] = []
        var perBlockVlc: [[UInt8]] = []
        perBlockMagsgn.reserveCapacity(blockCount)
        perBlockMel.reserveCapacity(blockCount)
        perBlockVlc.reserveCapacity(blockCount)

        let magsgnBase = magsgnBuf.contents()
        let melBase = melBuf.contents()
        let vlcBase = vlcBuf.contents()

        for i in 0..<blockCount {
            let c = counts[i]
            let msLen = Int(c.x), melLen = Int(c.y), vlcLen = Int(c.z)
            precondition(msLen <= cap && melLen <= cap && vlcLen <= cap,
                         "J2KGPUForwardHTCleanupPassEmit: block \(i) exceeded per-stream cap")
            let off = i * cap
            let ms: [UInt8] = [UInt8](unsafeUninitializedCapacity: msLen) { dst, init_ in
                if msLen > 0 { memcpy(dst.baseAddress!, magsgnBase + off, msLen) }
                init_ = msLen
            }
            let mel: [UInt8] = [UInt8](unsafeUninitializedCapacity: melLen) { dst, init_ in
                if melLen > 0 { memcpy(dst.baseAddress!, melBase + off, melLen) }
                init_ = melLen
            }
            let vlc: [UInt8] = [UInt8](unsafeUninitializedCapacity: vlcLen) { dst, init_ in
                if vlcLen > 0 { memcpy(dst.baseAddress!, vlcBase + off, vlcLen) }
                init_ = vlcLen
            }
            perBlockMagsgn.append(ms)
            perBlockMel.append(mel)
            perBlockVlc.append(vlc)
        }
        return BatchedResult(perBlockMagsgn: perBlockMagsgn,
                             perBlockMel: perBlockMel,
                             perBlockVlc: perBlockVlc)
    }

    /// Cached lookup-table buffers — built lazily on first use,
    /// reused across all subsequent dispatches. The tables are
    /// read-only after upload; once a device-keyed slot exists,
    /// every encode pays only the buffer-binding cost (no allocation,
    /// no Swift→Metal copy).
    fileprivate final class CachedTables: @unchecked Sendable {
        let vlc0: any MTLBuffer
        let vlc1: any MTLBuffer
        let uvlc: any MTLBuffer
        let melExp: [UInt8]
        let device: any MTLDevice

        init(device: any MTLDevice) throws {
            self.device = device

            let vlc0Src = vlcTable0Conformant
            let vlc1Src = vlcTable1Conformant
            let uvlcSrc = uvlcTableConformant
            self.melExp = melExpConformant.map { UInt8($0) }

            let vlc0Bytes = vlc0Src.count * MemoryLayout<UInt16>.stride
            let vlc1Bytes = vlc1Src.count * MemoryLayout<UInt16>.stride
            let uvlcBytes = uvlcSrc.count * MemoryLayout<SIMD2<UInt32>>.stride

            guard let vlc0Buf = device.makeBuffer(length: vlc0Bytes, options: .storageModeShared),
                  let vlc1Buf = device.makeBuffer(length: vlc1Bytes, options: .storageModeShared),
                  let uvlcBuf = device.makeBuffer(length: uvlcBytes, options: .storageModeShared)
            else {
                throw J2KError.internalError(
                    "J2KGPUForwardHTCleanupPassEmit: failed to allocate table buffers")
            }
            let vlc0Ptr = vlc0Buf.contents().bindMemory(to: UInt16.self, capacity: vlc0Src.count)
            for (i, v) in vlc0Src.enumerated() { vlc0Ptr[i] = v }
            let vlc1Ptr = vlc1Buf.contents().bindMemory(to: UInt16.self, capacity: vlc1Src.count)
            for (i, v) in vlc1Src.enumerated() { vlc1Ptr[i] = v }

            // UVLC packed as `uint2` per entry:
            //   .x = pre | (preLen<<8) | (suf<<16) | (sufLen<<24)
            //   .y = ext | (extLen<<8)
            let uvlcPtr = uvlcBuf.contents().bindMemory(
                to: SIMD2<UInt32>.self, capacity: uvlcSrc.count)
            for (i, e) in uvlcSrc.enumerated() {
                let x = UInt32(e.pre)
                    | (UInt32(e.preLen) << 8)
                    | (UInt32(e.suf) << 16)
                    | (UInt32(e.sufLen) << 24)
                let y = UInt32(e.ext) | (UInt32(e.extLen) << 8)
                uvlcPtr[i] = SIMD2<UInt32>(x, y)
            }
            self.vlc0 = vlc0Buf
            self.vlc1 = vlc1Buf
            self.uvlc = uvlcBuf
        }
    }

    nonisolated(unsafe) private static var _cachedTables: CachedTables?
    private static let _cacheLock = NSLock()

    fileprivate static func cachedTableBuffers(
        device: any MTLDevice
    ) throws -> CachedTables {
        _cacheLock.lock()
        defer { _cacheLock.unlock() }
        // Same-device fast path — the typical case (one device per
        // process). Reset the cache if the device changed.
        if let cached = _cachedTables, cached.device === device {
            return cached
        }
        let fresh = try CachedTables(device: device)
        _cachedTables = fresh
        return fresh
    }
    #else
    public func emitBlock(tuples: [UInt64],
                          width: Int,
                          height: Int,
                          missingMSBs: Int) async throws -> EmitResult {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif
}
