// J2KMetalHTMagSgnEmit.swift
//
// v7.1.0 I1.2 — Pass 3 of approach C (GPU forward HT entropy).
// MagSgn-only single-block byte-write spike.
//
// Wraps `j2k_ht_magsgn_emit_block` (Sources/J2KMetal/J2KShaders.metal),
// the per-block serial bit-emitter that mirrors `HTMagSgnEncoderConformant`
// in `Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift`. One threadgroup
// per block, one thread does the inherently-serial bit-write while the
// rest of the warp idles; block-level parallelism (one threadgroup per
// block) is what keeps the GPU occupied.
//
// **Scope**: single-block emit only. Multi-block dispatch + MEL/VLC
// streams + integration with the v6-alpha6 classifier (Pass 1) and the
// I1.1 prefix-sum (Pass 2) land in subsequent I1.2 / I1.3 PRs.
//
// **Bit-exactness gate**: `MetalHTForwardMagSgnEmitTests` compares
// the kernel's output byte-for-byte against `HTMagSgnEncoderConformant`
// across hand-picked edge cases (FF-stuffing, terminate rollback,
// pad-drops-FF) and a randomised sweep.

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// MagSgn byte-write — Pass 3 of v7.1.0 approach C GPU forward HT entropy.
///
/// Bit-exact with `HTMagSgnEncoderConformant`; tested by
/// `MetalHTForwardMagSgnEmitTests`.
public struct J2KMetalHTMagSgnEmit: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    /// One `(codeword, count)` pair to feed the encoder, mirroring the
    /// `HTMagSgnEncoderConformant.encode(codeword:count:)` API.
    public struct Item: Sendable {
        public let codeword: UInt32
        public let count: UInt32
        public init(codeword: UInt32, count: UInt32) {
            self.codeword = codeword
            self.count = count
        }
    }

    #if canImport(Metal)
    /// Emit the MagSgn byte stream for one block on the GPU.
    ///
    /// - Parameters:
    ///   - items: list of `(codeword, count)` pairs; `count` must be ≤ 32.
    ///   - outputCapacity: upper-bound on the emitted byte count. The
    ///     output buffer is allocated this large; the actual byte count
    ///     is returned alongside the trimmed bytes. A safe upper bound
    ///     is `ceil(totalBits / 7) + 1` (every byte may reserve a
    ///     stuff-bit slot, plus the terminate-flush byte).
    /// - Returns: the emitted bytes, trimmed to the kernel-reported length.
    /// - Throws: `J2KError.internalError` for Metal allocation/dispatch failures.
    public func emitBlock(items: [Item],
                          outputCapacity: Int) async throws -> [UInt8] {
        if items.isEmpty {
            return []
        }
        precondition(outputCapacity > 0,
                     "J2KMetalHTMagSgnEmit: outputCapacity must be positive")

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let itemBytes = items.count * MemoryLayout<SIMD2<UInt32>>.stride
        guard let itemsBuf = device.makeBuffer(length: itemBytes, options: .storageModeShared),
              let outputBuf = device.makeBuffer(length: outputCapacity, options: .storageModeShared),
              let countBuf = device.makeBuffer(length: MemoryLayout<UInt32>.stride,
                                               options: .storageModeShared)
        else {
            throw J2KError.internalError("J2KMetalHTMagSgnEmit: failed to allocate Metal buffers")
        }

        // Pack items into the buffer as a contiguous run of (codeword, count) uint2.
        let itemsPtr = itemsBuf.contents().bindMemory(to: SIMD2<UInt32>.self,
                                                      capacity: items.count)
        for (i, item) in items.enumerated() {
            itemsPtr[i] = SIMD2<UInt32>(item.codeword, item.count)
        }
        // Zero the count slot so a kernel that fails to write it surfaces as 0.
        countBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee = 0

        let pipeline = try await shaderLibrary.computePipeline(for: .htMagSgnEmitBlock)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder()
        else {
            throw J2KError.internalError("J2KMetalHTMagSgnEmit: failed to create command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(itemsBuf, offset: 0, index: 0)
        var itemCount = UInt32(items.count)
        encoder.setBytes(&itemCount, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBuffer(outputBuf, offset: 0, index: 2)
        var outputOffset: UInt32 = 0
        encoder.setBytes(&outputOffset, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBuffer(countBuf, offset: 0, index: 4)

        // One threadgroup, 32 threads — only thread 0 is active, the
        // remaining 31 idle. Apple's per-warp scheduler still takes
        // 32-wide groups so we don't try to dispatch 1 thread.
        let threadsPerGroup = MTLSize(width: 32, height: 1, depth: 1)
        let gridSize = MTLSize(width: 32, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()

        let emittedCount = Int(countBuf.contents()
            .bindMemory(to: UInt32.self, capacity: 1).pointee)
        precondition(emittedCount <= outputCapacity,
                     "J2KMetalHTMagSgnEmit: kernel-reported byte count \(emittedCount) " +
                     "exceeds outputCapacity \(outputCapacity)")

        // Per `feedback_metal_readback.md`: do NOT use
        // `Array.withUnsafeMutableBytes { copyBytes(from: ...) }` —
        // that pattern deadlocks in release mode. Use
        // `unsafeUninitializedCapacity + memcpy` instead.
        let result: [UInt8] = [UInt8](unsafeUninitializedCapacity: emittedCount) { dst, initCount in
            if emittedCount > 0 {
                memcpy(dst.baseAddress!, outputBuf.contents(), emittedCount)
            }
            initCount = emittedCount
        }
        return result
    }
    #else
    public func emitBlock(items: [Item],
                          outputCapacity: Int) async throws -> [UInt8] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    // MARK: - v7.1.0 I1.2b — batched (multi-block) dispatch

    /// One block of input to the batched emit — its `(codeword, count)`
    /// items live in a flat shared buffer; this struct says where this
    /// block's run starts and how many items it owns.
    public struct BlockDescriptor: Sendable {
        public let itemStart: UInt32
        public let itemCount: UInt32
        public init(itemStart: UInt32, itemCount: UInt32) {
            self.itemStart = itemStart
            self.itemCount = itemCount
        }
    }

    /// Result of a batched emit — concatenated bytes across all blocks
    /// (in offset order) and per-block emitted byte counts.
    public struct BatchedResult: Sendable {
        public let bytes: [UInt8]
        public let perBlockByteCount: [UInt32]
    }

    /// Compute 4-byte-aligned per-block start offsets from per-block
    /// byte budgets. **Required** for batched dispatch — Apple Silicon
    /// GPUs implement `device uchar*` stores as 32-bit RMW operations,
    /// so two threadgroups that share a 4-byte word race. Rounding
    /// each block's region size up to 4 bytes guarantees no two blocks
    /// share a word.
    ///
    /// Returns `(offsets, requiredCapacity)`:
    ///   - `offsets[i]` — 4-byte-aligned start of block i in the
    ///     shared output buffer.
    ///   - `requiredCapacity` — sum of aligned-up per-block sizes;
    ///     the minimum `outputCapacity` to pass to `emitBlocks`.
    public static func alignedOffsets(byteBudgets: [UInt32]) -> (offsets: [UInt32], capacity: Int) {
        var offsets = [UInt32](repeating: 0, count: byteBudgets.count)
        var acc: UInt32 = 0
        for (i, b) in byteBudgets.enumerated() {
            offsets[i] = acc
            let alignedSize = (b &+ 3) & ~UInt32(3)
            acc &+= alignedSize
        }
        return (offsets, Int(acc))
    }

    #if canImport(Metal)
    /// Emit MagSgn byte streams for a batch of blocks on the GPU.
    ///
    /// One threadgroup per block; the GPU runs many in parallel
    /// (this is the production shape of Pass 3). Each block writes
    /// its bytes at `outputOffsets[i]` in the shared `output` buffer.
    ///
    /// - Parameters:
    ///   - items: flat list of `(codeword, count)` items across all
    ///     blocks. Each block's range is given by `descriptors`.
    ///   - descriptors: per-block `(itemStart, itemCount)` slice into
    ///     `items`. Must have the same length as `outputOffsets` and
    ///     match the number of blocks.
    ///   - outputOffsets: per-block start byte index into the shared
    ///     output buffer. **Each offset MUST be a multiple of 4 bytes**
    ///     and the gap between consecutive offsets must be ≥ the
    ///     aligned-up byte budget for the block. See
    ///     `alignedOffsets(byteBudgets:)` for the canonical computation.
    ///     Reason: Apple Silicon implements `device uchar*` stores as
    ///     32-bit RMW, so two threadgroups sharing a 4-byte word race —
    ///     one wins, the other's byte gets clobbered. Aligning each
    ///     block's region to a word boundary eliminates the race.
    ///   - outputCapacity: total size of the shared output buffer in
    ///     bytes. Must be ≥ `alignedOffsets(byteBudgets:).capacity`.
    /// - Returns: concatenated bytes (size `outputCapacity`, sliced
    ///   on a per-block basis by callers using `outputOffsets[i]`
    ///   and the kernel-reported `perBlockByteCount[i]`) and per-block
    ///   emitted byte counts.
    /// - Throws: `J2KError.invalidParameter` if input shapes don't agree;
    ///   `J2KError.internalError` for Metal allocation/dispatch failures.
    public func emitBlocks(items: [Item],
                           descriptors: [BlockDescriptor],
                           outputOffsets: [UInt32],
                           outputCapacity: Int) async throws -> BatchedResult {
        guard descriptors.count == outputOffsets.count else {
            throw J2KError.invalidParameter(
                "J2KMetalHTMagSgnEmit: descriptors.count (\(descriptors.count)) " +
                "must match outputOffsets.count (\(outputOffsets.count))")
        }
        if descriptors.isEmpty {
            return BatchedResult(bytes: [], perBlockByteCount: [])
        }
        precondition(outputCapacity > 0,
                     "J2KMetalHTMagSgnEmit: outputCapacity must be positive")

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let blockCount = descriptors.count
        let itemBytes = max(MemoryLayout<SIMD2<UInt32>>.stride,
                            items.count * MemoryLayout<SIMD2<UInt32>>.stride)
        let descBytes = blockCount * MemoryLayout<SIMD2<UInt32>>.stride
        let offsetBytes = blockCount * MemoryLayout<UInt32>.stride
        let countsBytes = blockCount * MemoryLayout<UInt32>.stride

        guard let itemsBuf = device.makeBuffer(length: itemBytes, options: .storageModeShared),
              let descBuf = device.makeBuffer(length: descBytes, options: .storageModeShared),
              let offsetsBuf = device.makeBuffer(length: offsetBytes, options: .storageModeShared),
              let outputBuf = device.makeBuffer(length: outputCapacity, options: .storageModeShared),
              let countsBuf = device.makeBuffer(length: countsBytes, options: .storageModeShared)
        else {
            throw J2KError.internalError("J2KMetalHTMagSgnEmit: failed to allocate Metal buffers (batched)")
        }

        if !items.isEmpty {
            let itemsPtr = itemsBuf.contents().bindMemory(to: SIMD2<UInt32>.self,
                                                          capacity: items.count)
            for (i, item) in items.enumerated() {
                itemsPtr[i] = SIMD2<UInt32>(item.codeword, item.count)
            }
        }
        let descPtr = descBuf.contents().bindMemory(to: SIMD2<UInt32>.self, capacity: blockCount)
        for (i, d) in descriptors.enumerated() {
            descPtr[i] = SIMD2<UInt32>(d.itemStart, d.itemCount)
        }
        let offsetsPtr = offsetsBuf.contents().bindMemory(to: UInt32.self, capacity: blockCount)
        for (i, off) in outputOffsets.enumerated() {
            offsetsPtr[i] = off
        }
        // Zero the byte-counts buffer so blocks that write nothing surface as 0.
        memset(countsBuf.contents(), 0, countsBytes)

        let pipeline = try await shaderLibrary.computePipeline(for: .htMagSgnEmitBlocksBatched)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder()
        else {
            throw J2KError.internalError("J2KMetalHTMagSgnEmit: failed to create command buffer/encoder (batched)")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(itemsBuf, offset: 0, index: 0)
        encoder.setBuffer(descBuf, offset: 0, index: 1)
        encoder.setBuffer(offsetsBuf, offset: 0, index: 2)
        encoder.setBuffer(outputBuf, offset: 0, index: 3)
        encoder.setBuffer(countsBuf, offset: 0, index: 4)
        var blockCountU32 = UInt32(blockCount)
        encoder.setBytes(&blockCountU32, length: MemoryLayout<UInt32>.stride, index: 5)

        // One threadgroup per block; 32 threads per group (only
        // thread 0 active, 31 idle — block-level parallelism is what
        // pays for the wasted lanes). dispatchThreadgroups so each
        // threadgroup gets a unique threadgroup_position_in_grid.
        let threadsPerGroup = MTLSize(width: 32, height: 1, depth: 1)
        let groupCount = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groupCount, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()

        // Readback: full output buffer + per-block counts. Callers
        // slice the bytes per-block using outputOffsets + the
        // returned perBlockByteCount.
        let bytes: [UInt8] = [UInt8](unsafeUninitializedCapacity: outputCapacity) { dst, initCount in
            memcpy(dst.baseAddress!, outputBuf.contents(), outputCapacity)
            initCount = outputCapacity
        }
        let counts: [UInt32] = [UInt32](unsafeUninitializedCapacity: blockCount) { dst, initCount in
            memcpy(dst.baseAddress!, countsBuf.contents(), countsBytes)
            initCount = blockCount
        }
        return BatchedResult(bytes: bytes, perBlockByteCount: counts)
    }
    #else
    public func emitBlocks(items: [Item],
                           descriptors: [BlockDescriptor],
                           outputOffsets: [UInt32],
                           outputCapacity: Int) async throws -> BatchedResult {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif
}
