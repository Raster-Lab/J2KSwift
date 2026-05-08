// J2KMetalHTMELEmit.swift
//
// v7.1.0 I1.2c — Pass 3 of approach C (GPU forward HT entropy).
// MEL batched byte-write.
//
// Wraps `j2k_ht_mel_emit_blocks_batched` (Sources/J2KMetal/J2KShaders.metal)
// — a multi-block dispatch where each threadgroup runs the per-block-
// serial bit-emit in `HTForwardBitEmitterConformant` from
// `Sources/J2KCodec/J2KHTConformantBitStream.swift`.
//
// Differences vs `J2KMetalHTMagSgnEmit` (the I1.2 / I1.2b sibling):
//   - **MSB-first** packing (vs LSB-first for MagSgn). Bits emit in
//     MSB-then-LSB order; finish() left-shifts the partial byte by
//     the unfilled count to position bits in the high half.
//   - **No rollback** on terminate, no FF-drop on padded byte. The
//     final partial byte is always appended.
//
// Same Apple-Silicon byte-store RMW alignment requirement as I1.2b:
// per-block output offsets MUST be 4-byte aligned. Use
// `J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets:)` (the helper
// is module-shared) to compute the canonical offsets.
//
// **Bit-exactness gate**: `MetalHTForwardMELEmitTests` compares the
// kernel's output byte-for-byte against `HTForwardBitEmitterConformant`
// across hand-picked edge cases (FF-stuff, single-bit emit, padded
// terminate) and a randomised sweep.

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// MEL byte-write — Pass 3 of v7.1.0 approach C GPU forward HT entropy.
///
/// Bit-exact with `HTForwardBitEmitterConformant`; tested by
/// `MetalHTForwardMELEmitTests`.
public struct J2KMetalHTMELEmit: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    /// One bit-emit pair — MSB-first emission of `count` bits taken
    /// from `value`'s low-order bits. Mirrors
    /// `HTForwardBitEmitterConformant.emit(bits:count:)`.
    public struct Item: Sendable {
        public let value: UInt32
        public let count: UInt32
        public init(value: UInt32, count: UInt32) {
            self.value = value
            self.count = count
        }
    }

    public typealias BlockDescriptor = J2KMetalHTMagSgnEmit.BlockDescriptor
    public typealias BatchedResult = J2KMetalHTMagSgnEmit.BatchedResult

    #if canImport(Metal)
    /// Emit MEL byte streams for a batch of blocks on the GPU.
    ///
    /// - Parameters:
    ///   - items: flat list of `(value, count)` items across all blocks.
    ///   - descriptors: per-block `(itemStart, itemCount)` slice.
    ///   - outputOffsets: per-block 4-byte-aligned start byte index
    ///     into the shared output buffer. See
    ///     `J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets:)` for
    ///     the canonical computation. **MUST be 4-byte aligned** to
    ///     avoid the Apple Silicon RMW race documented in I1.2b.
    ///   - outputCapacity: size of the shared output buffer; pass
    ///     `alignedOffsets(...).capacity`.
    /// - Returns: concatenated bytes (full buffer, callers slice
    ///   per-block via `outputOffsets[i]` + `perBlockByteCount[i]`)
    ///   and per-block emitted byte counts.
    public func emitBlocks(items: [Item],
                           descriptors: [BlockDescriptor],
                           outputOffsets: [UInt32],
                           outputCapacity: Int) async throws -> BatchedResult {
        guard descriptors.count == outputOffsets.count else {
            throw J2KError.invalidParameter(
                "J2KMetalHTMELEmit: descriptors.count (\(descriptors.count)) " +
                "must match outputOffsets.count (\(outputOffsets.count))")
        }
        if descriptors.isEmpty {
            return BatchedResult(bytes: [], perBlockByteCount: [])
        }
        precondition(outputCapacity > 0,
                     "J2KMetalHTMELEmit: outputCapacity must be positive")

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
            throw J2KError.internalError("J2KMetalHTMELEmit: failed to allocate Metal buffers")
        }

        if !items.isEmpty {
            let itemsPtr = itemsBuf.contents().bindMemory(to: SIMD2<UInt32>.self,
                                                          capacity: items.count)
            for (i, item) in items.enumerated() {
                itemsPtr[i] = SIMD2<UInt32>(item.value, item.count)
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
        memset(countsBuf.contents(), 0, countsBytes)

        let pipeline = try await shaderLibrary.computePipeline(for: .htMelEmitBlocksBatched)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder()
        else {
            throw J2KError.internalError("J2KMetalHTMELEmit: failed to create command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(itemsBuf, offset: 0, index: 0)
        encoder.setBuffer(descBuf, offset: 0, index: 1)
        encoder.setBuffer(offsetsBuf, offset: 0, index: 2)
        encoder.setBuffer(outputBuf, offset: 0, index: 3)
        encoder.setBuffer(countsBuf, offset: 0, index: 4)
        var blockCountU32 = UInt32(blockCount)
        encoder.setBytes(&blockCountU32, length: MemoryLayout<UInt32>.stride, index: 5)

        let threadsPerGroup = MTLSize(width: 32, height: 1, depth: 1)
        let groupCount = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreadgroups(groupCount, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()

        // Per `feedback_metal_readback.md`: do NOT use
        // `Array.withUnsafeMutableBytes { copyBytes(from: ...) }`.
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
