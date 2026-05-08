// J2KMetalHTVLCEmit.swift
//
// v7.1.0 I1.2d — Pass 3 of approach C (GPU forward HT entropy).
// VLC reverse-bit-stream batched byte-write.
//
// Wraps `j2k_ht_vlc_emit_blocks_batched` (Sources/J2KMetal/J2KShaders.metal)
// — the per-block-serial port of `HTReverseBitEmitterConformant`'s
// `encode + finish` from `Sources/J2KCodec/J2KHTConformantBitStream.swift`.
//
// VLC is the trickiest of the three Pass 3 streams:
//   - Bytes packed LSB-first within each byte, but the byte SEQUENCE
//     is built in REVERSE: emit-order byte 0 ends up at the END of
//     the on-wire stream, the last emitted byte ends up at the START.
//   - Initial state writes a 0xFF sentinel at byteIdx=0 (which lands
//     at the end of the on-wire region after the in-kernel reverse).
//   - Reverse FF-stuffing on `> 0x8F` previous bytes — with the
//     deferred-stuff release optimization when the would-be stuff
//     byte's low 7 bits don't equal 0x7F.
//
// Same Apple-Silicon byte-store RMW alignment requirement as
// I1.2b/I1.2c: per-block output offsets MUST be 4-byte aligned.
// Wrapper reuses `J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets:)`
// for the canonical computation.
//
// **Bit-exactness gate**: `MetalHTForwardVLCEmitTests` compares the
// kernel's output byte-for-byte against `HTReverseBitEmitterConformant`
// across hand-picked edge cases (the deferred-stuff release branch,
// the `> 0x8F` stuff trigger, the implicit 0xFF sentinel) and a
// randomised sweep.

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// VLC byte-write — Pass 3 of v7.1.0 approach C GPU forward HT entropy.
///
/// Bit-exact with `HTReverseBitEmitterConformant`; tested by
/// `MetalHTForwardVLCEmitTests`.
public struct J2KMetalHTVLCEmit: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    /// One codeword-emit pair — `count` LSB-first bits taken from
    /// `codeword`'s low-order bits. Mirrors
    /// `HTReverseBitEmitterConformant.encode(codeword:count:)`.
    public struct Item: Sendable {
        public let codeword: UInt32
        public let count: UInt32
        public init(codeword: UInt32, count: UInt32) {
            self.codeword = codeword
            self.count = count
        }
    }

    public typealias BlockDescriptor = J2KMetalHTMagSgnEmit.BlockDescriptor
    public typealias BatchedResult = J2KMetalHTMagSgnEmit.BatchedResult

    #if canImport(Metal)
    /// Emit VLC byte streams for a batch of blocks on the GPU.
    ///
    /// - Parameters:
    ///   - items: flat list of `(codeword, count)` items across all blocks.
    ///   - descriptors: per-block `(itemStart, itemCount)` slice.
    ///   - outputOffsets: per-block 4-byte-aligned start byte index
    ///     into the shared output buffer. Use
    ///     `J2KMetalHTMagSgnEmit.alignedOffsets(byteBudgets:)` for
    ///     the canonical computation. **MUST be 4-byte aligned**.
    ///   - outputCapacity: size of the shared output buffer; pass
    ///     `alignedOffsets(...).capacity`.
    /// - Returns: concatenated bytes (full buffer; callers slice
    ///   per-block via `outputOffsets[i]` + `perBlockByteCount[i]`)
    ///   and per-block emitted byte counts. Each block's region holds
    ///   the bytes in **forward on-wire order** (the 0xFF sentinel is
    ///   the LAST byte of the region; the byte adjacent to the
    ///   MagSgn stream is the FIRST byte of the region).
    public func emitBlocks(items: [Item],
                           descriptors: [BlockDescriptor],
                           outputOffsets: [UInt32],
                           outputCapacity: Int) async throws -> BatchedResult {
        guard descriptors.count == outputOffsets.count else {
            throw J2KError.invalidParameter(
                "J2KMetalHTVLCEmit: descriptors.count (\(descriptors.count)) " +
                "must match outputOffsets.count (\(outputOffsets.count))")
        }
        if descriptors.isEmpty {
            return BatchedResult(bytes: [], perBlockByteCount: [])
        }
        precondition(outputCapacity > 0,
                     "J2KMetalHTVLCEmit: outputCapacity must be positive")

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
            throw J2KError.internalError("J2KMetalHTVLCEmit: failed to allocate Metal buffers")
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
        memset(countsBuf.contents(), 0, countsBytes)

        let pipeline = try await shaderLibrary.computePipeline(for: .htVlcEmitBlocksBatched)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder()
        else {
            throw J2KError.internalError("J2KMetalHTVLCEmit: failed to create command buffer/encoder")
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
