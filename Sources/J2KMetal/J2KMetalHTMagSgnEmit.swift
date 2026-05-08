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
}
