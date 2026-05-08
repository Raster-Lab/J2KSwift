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

    /// Per-stream upper-bound capacity per block. The kernel emits
    /// up to ≤ this many bytes for each of the three streams; if a
    /// block hits the cap a precondition fires. 8 KB per stream is
    /// generous: even a 64×64 block with fully-significant high-
    /// magnitude samples typically produces a few KB, and FF-stuff
    /// overhead doesn't push it past 8 KB.
    public static let perStreamCapPerBlock: Int = 8192

    /// 4-byte alignment overhead (Apple Silicon RMW byte-store rule
    /// from I1.2b). Each block's per-stream region must start on a
    /// 4-byte boundary; the per-stream cap is already a multiple of 4.
    @inline(__always)
    private static func roundUpTo4(_ x: Int) -> Int { (x + 3) & ~3 }

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
    public func emitBlocks(_ blocks: [BlockDescriptor]) async throws -> BatchedResult {
        if blocks.isEmpty {
            return BatchedResult(perBlockMagsgn: [], perBlockMel: [], perBlockVlc: [])
        }

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let blockCount = blocks.count
        let cap = Self.perStreamCapPerBlock         // already a multiple of 4
        let perStreamRegion = blockCount * cap      // entire shared output buffer per stream

        // Concatenate tuples + build per-block descriptors.
        var totalTupleCount = 0
        var tupleStarts = [UInt32](repeating: 0, count: blockCount)
        for (i, b) in blocks.enumerated() {
            tupleStarts[i] = UInt32(totalTupleCount)
            totalTupleCount += b.tuples.count
        }

        let tuplesBytes = max(MemoryLayout<UInt64>.stride,
                              totalTupleCount * MemoryLayout<UInt64>.stride)
        let dimsBytes = blockCount * MemoryLayout<SIMD4<UInt32>>.stride
        let offsetBytes = blockCount * MemoryLayout<UInt32>.stride
        let countsBytes = blockCount * MemoryLayout<SIMD3<UInt32>>.stride

        let (vlc0Buf, vlc1Buf, uvlcBuf, melExpBytes) = try makeTableBuffers(device: device)

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

        // Pack inputs.
        let tuplesPtr = tuplesBuf.contents().bindMemory(to: UInt64.self, capacity: totalTupleCount)
        let dimsPtr = dimsBuf.contents().bindMemory(to: SIMD4<UInt32>.self, capacity: blockCount)
        let msOffPtr = magsgnOffBuf.contents().bindMemory(to: UInt32.self, capacity: blockCount)
        let melOffPtr = melOffBuf.contents().bindMemory(to: UInt32.self, capacity: blockCount)
        let vlcOffPtr = vlcOffBuf.contents().bindMemory(to: UInt32.self, capacity: blockCount)

        for (i, b) in blocks.enumerated() {
            // Copy this block's tuples into the flat buffer at its start.
            let start = Int(tupleStarts[i])
            for (j, t) in b.tuples.enumerated() {
                tuplesPtr[start + j] = t
            }
            dimsPtr[i] = SIMD4<UInt32>(
                UInt32(b.width), UInt32(b.height),
                UInt32(b.missingMSBs), tupleStarts[i])
            // Per-block-i region in the per-stream output buffer:
            // start = i × cap (cap is already a multiple of 4 → alignment OK)
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
        encoder.setBuffer(vlc0Buf, offset: 0, index: 2)
        encoder.setBuffer(vlc1Buf, offset: 0, index: 3)
        encoder.setBuffer(uvlcBuf, offset: 0, index: 4)
        melExpBytes.withUnsafeBytes { raw in
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

        // One threadgroup per block; 32 threads each (thread 0 active).
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
            // Per `feedback_metal_readback.md`: do NOT use
            // `Array.withUnsafeMutableBytes { copyBytes(from: ...) }`.
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

    /// Build the four lookup tables the kernel needs (VLC0, VLC1,
    /// UVLC, MEL-exponent) into Metal buffers + Swift bytes. Re-uses
    /// J2KCodec's CPU table builders to guarantee CPU-GPU parity.
    private func makeTableBuffers(device: any MTLDevice) throws
        -> (vlc0: any MTLBuffer, vlc1: any MTLBuffer,
            uvlc: any MTLBuffer, melExp: [UInt8])
    {
        let vlc0 = vlcTable0Conformant
        let vlc1 = vlcTable1Conformant
        let uvlcSrc = uvlcTableConformant
        let melExp = melExpConformant.map { UInt8($0) }

        let vlc0Bytes = vlc0.count * MemoryLayout<UInt16>.stride
        let vlc1Bytes = vlc1.count * MemoryLayout<UInt16>.stride
        let uvlcBytes = uvlcSrc.count * MemoryLayout<SIMD2<UInt32>>.stride

        guard let vlc0Buf = device.makeBuffer(length: vlc0Bytes, options: .storageModeShared),
              let vlc1Buf = device.makeBuffer(length: vlc1Bytes, options: .storageModeShared),
              let uvlcBuf = device.makeBuffer(length: uvlcBytes, options: .storageModeShared)
        else {
            throw J2KError.internalError("J2KGPUForwardHTCleanupPassEmit: failed to allocate table buffers")
        }

        let vlc0Ptr = vlc0Buf.contents().bindMemory(to: UInt16.self, capacity: vlc0.count)
        for (i, v) in vlc0.enumerated() { vlc0Ptr[i] = v }
        let vlc1Ptr = vlc1Buf.contents().bindMemory(to: UInt16.self, capacity: vlc1.count)
        for (i, v) in vlc1.enumerated() { vlc1Ptr[i] = v }

        // UVLC is packed as `uint2` per entry:
        //   .x = (pre << 0) | (preLen << 8) | (suf << 16) | (sufLen << 24)
        //   .y = (ext << 0) | (extLen << 8)
        let uvlcPtr = uvlcBuf.contents().bindMemory(to: SIMD2<UInt32>.self, capacity: uvlcSrc.count)
        for (i, e) in uvlcSrc.enumerated() {
            let x = UInt32(e.pre)
                | (UInt32(e.preLen) << 8)
                | (UInt32(e.suf) << 16)
                | (UInt32(e.sufLen) << 24)
            let y = UInt32(e.ext) | (UInt32(e.extLen) << 8)
            uvlcPtr[i] = SIMD2<UInt32>(x, y)
        }

        return (vlc0Buf, vlc1Buf, uvlcBuf, melExp)
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
