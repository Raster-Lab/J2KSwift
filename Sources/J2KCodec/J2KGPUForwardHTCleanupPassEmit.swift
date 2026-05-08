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

    #if canImport(Metal)
    /// Run the unified cleanup-pass kernel on a single codeblock's
    /// pre-classified tuple stream.
    ///
    /// - Parameters:
    ///   - tuples: per-sample tuple stream in the GPU classifier's
    ///     output format (`sig:1 | eQ:7 | (24 unused) | payload:32`),
    ///     row-major `y * width + x` order. Length `width * height`.
    ///   - width: codeblock width.
    ///   - height: codeblock height.
    ///   - missingMSBs: coefficient bit-budget reduction (matches
    ///     CPU `encode`'s `missingMSBs` parameter); kernel doesn't
    ///     use this directly (`p` is implicit in tuple payloads),
    ///     but it's accepted for parity with the CPU signature.
    /// - Returns: three byte streams, byte-identical to
    ///   `HTBlockEncoderConformant.encode(preClassifiedTuples:)`.
    public func emitBlock(tuples: [UInt64],
                          width: Int,
                          height: Int,
                          missingMSBs: Int) async throws -> EmitResult {
        precondition(tuples.count == width * height,
                     "J2KGPUForwardHTCleanupPassEmit: tuples.count must equal width × height")
        precondition(width <= 64 && height <= 64,
                     "J2KGPUForwardHTCleanupPassEmit: I1.3b spike supports up to 64×64 blocks")

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        // Upper-bound output capacities: every quad emits at most a
        // few bits per stream; with FF-stuff overhead and pad, 8K per
        // stream covers the worst case for a 64×64 block. (The actual
        // emitted byte count is reported back via the count buffer.)
        let perStreamCap = 8192
        let countsBytes = 3 * MemoryLayout<UInt32>.stride

        let tuplesBytes = max(MemoryLayout<UInt64>.stride,
                              tuples.count * MemoryLayout<UInt64>.stride)

        // Build / fetch shared lookup tables (could cache on the
        // shader library, but since the I1.3b spike runs single-
        // block per dispatch, per-call upload is fine for now).
        let (vlc0Buf, vlc1Buf, uvlcBuf, melExpBytes) = try makeTableBuffers(device: device)

        guard let tuplesBuf = device.makeBuffer(length: tuplesBytes, options: .storageModeShared),
              let magsgnBuf = device.makeBuffer(length: perStreamCap, options: .storageModeShared),
              let melBuf = device.makeBuffer(length: perStreamCap, options: .storageModeShared),
              let vlcBuf = device.makeBuffer(length: perStreamCap, options: .storageModeShared),
              let countsBuf = device.makeBuffer(length: countsBytes, options: .storageModeShared)
        else {
            throw J2KError.internalError("J2KGPUForwardHTCleanupPassEmit: failed to allocate Metal buffers")
        }

        // Copy tuples into device buffer.
        let tuplesPtr = tuplesBuf.contents().bindMemory(to: UInt64.self, capacity: tuples.count)
        for (i, t) in tuples.enumerated() {
            tuplesPtr[i] = t
        }
        memset(countsBuf.contents(), 0, countsBytes)

        let pipeline = try await shaderLibrary.computePipeline(for: .htCleanupPassEmitBlock)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder()
        else {
            throw J2KError.internalError("J2KGPUForwardHTCleanupPassEmit: failed to create command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(tuplesBuf, offset: 0, index: 0)
        var w = UInt32(width), h = UInt32(height), m = UInt32(missingMSBs)
        encoder.setBytes(&w, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBytes(&h, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.setBytes(&m, length: MemoryLayout<UInt32>.stride, index: 3)
        encoder.setBuffer(vlc0Buf, offset: 0, index: 4)
        encoder.setBuffer(vlc1Buf, offset: 0, index: 5)
        encoder.setBuffer(uvlcBuf, offset: 0, index: 6)
        // melExp is 13 bytes; setBytes is the right path for a small
        // constant array passed as a `constant uchar*`.
        melExpBytes.withUnsafeBytes { raw in
            encoder.setBytes(raw.baseAddress!, length: raw.count, index: 7)
        }
        encoder.setBuffer(magsgnBuf, offset: 0, index: 8)
        encoder.setBuffer(melBuf, offset: 0, index: 9)
        encoder.setBuffer(vlcBuf, offset: 0, index: 10)
        encoder.setBuffer(countsBuf, offset: 0, index: 11)

        // One threadgroup, 32 threads (only thread 0 does work; rest idle).
        let tg = MTLSize(width: 32, height: 1, depth: 1)
        let grid = MTLSize(width: 32, height: 1, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: tg)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()

        let counts = countsBuf.contents().bindMemory(to: UInt32.self, capacity: 3)
        let msLen = Int(counts[0])
        let melLen = Int(counts[1])
        let vlcLen = Int(counts[2])
        precondition(msLen <= perStreamCap && melLen <= perStreamCap && vlcLen <= perStreamCap,
                     "J2KGPUForwardHTCleanupPassEmit: kernel-reported byte count exceeds per-stream cap")

        let magsgn: [UInt8] = [UInt8](unsafeUninitializedCapacity: msLen) { dst, init_ in
            if msLen > 0 { memcpy(dst.baseAddress!, magsgnBuf.contents(), msLen) }
            init_ = msLen
        }
        let mel: [UInt8] = [UInt8](unsafeUninitializedCapacity: melLen) { dst, init_ in
            if melLen > 0 { memcpy(dst.baseAddress!, melBuf.contents(), melLen) }
            init_ = melLen
        }
        let vlc: [UInt8] = [UInt8](unsafeUninitializedCapacity: vlcLen) { dst, init_ in
            if vlcLen > 0 { memcpy(dst.baseAddress!, vlcBuf.contents(), vlcLen) }
            init_ = vlcLen
        }
        return EmitResult(magsgn: magsgn, mel: mel, vlc: vlc)
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
