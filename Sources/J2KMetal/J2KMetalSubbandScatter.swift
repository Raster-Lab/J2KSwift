// J2KMetalSubbandScatter.swift
//
// v5.7.0 (M4P-1): GPU subband scatter kernel wrapper.
//
// Replaces the CPU-side `getSubbandAsInt32` regroup loop in
// J2KDecoderPipeline with a GPU dispatch that scatters per-codeblock
// Int32 output (already produced by `J2KMetalHTCleanup.runIntegerMagnitude`)
// into per-subband 2D buffers. Designed to chain into the same
// command buffer as the inverse DWT in M4P-3.
//
// Layout of the descriptor (32 bytes, all UInt32) mirrors the MSL
// `GPUScatterDescriptor` struct field-for-field. `@frozen` locks
// the field order so the release-mode optimizer cannot reorder.

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Per-codeblock placement metadata for the GPU subband scatter.
/// One descriptor per (codeblock × scatter dispatch).
@frozen
public struct J2KMetalSubbandScatterDescriptor: Sendable {
    /// Int32-element offset into the source codeblock buffer.
    public let codeblockOffset: UInt32
    /// Codeblock width in samples.
    public let blockWidth: UInt32
    /// Codeblock height in samples.
    public let blockHeight: UInt32
    /// X position of this block within its target subband 2D buffer.
    public let subbandX: UInt32
    /// Y position of this block within its target subband 2D buffer.
    public let subbandY: UInt32
    /// Row pitch of the target subband buffer (= subband width).
    public let subbandStride: UInt32
    /// Target subband: 0=LL, 1=LH, 2=HL, 3=HH. Other values undefined.
    public let targetSubband: UInt32
    /// Padding so stride is a clean 32 bytes (matches MSL struct).
    private let _pad: UInt32

    public init(
        codeblockOffset: UInt32, blockWidth: UInt32, blockHeight: UInt32,
        subbandX: UInt32, subbandY: UInt32, subbandStride: UInt32,
        targetSubband: UInt32
    ) {
        self.codeblockOffset = codeblockOffset
        self.blockWidth = blockWidth
        self.blockHeight = blockHeight
        self.subbandX = subbandX
        self.subbandY = subbandY
        self.subbandStride = subbandStride
        self.targetSubband = targetSubband
        self._pad = 0
    }
}

/// v5.26.0 Float-and-dequant variant of the scatter descriptor.
/// Replaces the trailing `_pad` with a `Float stepSize` carrying
/// the per-subband dequantisation step. The 9/7 lossy fused-from-
/// codeblocks scatter kernel reads Int32 codeblock data, applies
/// `(coeff ± 0.5) * stepSize` (HTJ2K conformant cleanup-only), and
/// writes Float into LL/LH/HL/HH 2D buffers in a single pass.
@frozen
public struct J2KMetalSubbandScatterDescriptorFloat: Sendable {
    public let codeblockOffset: UInt32
    public let blockWidth: UInt32
    public let blockHeight: UInt32
    public let subbandX: UInt32
    public let subbandY: UInt32
    public let subbandStride: UInt32
    public let targetSubband: UInt32
    /// Per-block dequantisation step size. The kernel applies
    /// `(coeff ± 0.5) * stepSize` (or zero if coeff == 0).
    public let stepSize: Float

    public init(
        codeblockOffset: UInt32, blockWidth: UInt32, blockHeight: UInt32,
        subbandX: UInt32, subbandY: UInt32, subbandStride: UInt32,
        targetSubband: UInt32, stepSize: Float
    ) {
        self.codeblockOffset = codeblockOffset
        self.blockWidth = blockWidth
        self.blockHeight = blockHeight
        self.subbandX = subbandX
        self.subbandY = subbandY
        self.subbandStride = subbandStride
        self.targetSubband = targetSubband
        self.stepSize = stepSize
    }
}

/// Target subband identifier matching the MSL kernel's
/// `targetSubband` switch. Provides a Swift-side enum with
/// stable raw values.
public enum J2KMetalSubbandTarget: UInt32, Sendable {
    case ll = 0
    case lh = 1
    case hl = 2
    case hh = 3
}

/// GPU subband scatter kernel runner.
///
/// Designed for use in fused HT cleanup → DWT pipelines: the
/// `encode(into:...)` API takes an existing command buffer and
/// pre-allocated GPU buffers, encodes a single dispatch, and
/// returns. No commit, no readback. Caller controls the cb lifetime.
///
/// For standalone testing or one-shot use, `run(...)` allocates,
/// encodes, commits, and reads back the four subband buffers. M4P-1
/// uses the standalone path; M4P-3 wires the encode-into path into
/// the production decoder.
public struct J2KMetalSubbandScatter: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary
    public let bufferPool: J2KMetalBufferPool

    public init(
        metalDevice: J2KMetalDevice = J2KMetalDevice(),
        shaderLibrary: J2KMetalShaderLibrary? = nil,
        bufferPool: J2KMetalBufferPool? = nil
    ) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
        self.bufferPool = bufferPool ?? J2KMetalBufferPool()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    /// Standalone scatter dispatch: allocate per-subband output
    /// buffers, run the kernel, read back the 2D arrays. Intended
    /// for unit tests + a sanity ground-truth comparison against
    /// the CPU-side regroup. Production callers should use
    /// `encode(into:...)` instead so the scatter chains into the
    /// fused HT → DWT command buffer.
    #if canImport(Metal)
    public func run(
        descriptors: [J2KMetalSubbandScatterDescriptor],
        codeblocks: [Int32],
        llDimensions: (width: Int, height: Int),
        lhDimensions: (width: Int, height: Int),
        hlDimensions: (width: Int, height: Int),
        hhDimensions: (width: Int, height: Int)
    ) async throws -> (
        ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32]
    ) {
        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let descStride = MemoryLayout<J2KMetalSubbandScatterDescriptor>.stride
        let descCount = descriptors.count
        let descBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(descCount * descStride, 1))
        let codeblocksBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(codeblocks.count * MemoryLayout<Int32>.stride, 1))

        let llCount = llDimensions.width * llDimensions.height
        let lhCount = lhDimensions.width * lhDimensions.height
        let hlCount = hlDimensions.width * hlDimensions.height
        let hhCount = hhDimensions.width * hhDimensions.height
        let llBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(llCount * MemoryLayout<Int32>.stride, 1))
        let lhBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(lhCount * MemoryLayout<Int32>.stride, 1))
        let hlBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(hlCount * MemoryLayout<Int32>.stride, 1))
        let hhBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(hhCount * MemoryLayout<Int32>.stride, 1))

        // Zero-init outputs (the kernel only writes into significant
        // codeblock cells; padded areas must remain 0). The buffer
        // pool may return a previously-used buffer.
        memset(llBuffer.contents(), 0, llCount * MemoryLayout<Int32>.stride)
        memset(lhBuffer.contents(), 0, max(lhCount, 1) * MemoryLayout<Int32>.stride)
        memset(hlBuffer.contents(), 0, max(hlCount, 1) * MemoryLayout<Int32>.stride)
        memset(hhBuffer.contents(), 0, max(hhCount, 1) * MemoryLayout<Int32>.stride)

        descriptors.withUnsafeBufferPointer { src in
            descBuffer.contents().copyMemory(
                from: UnsafeRawPointer(src.baseAddress!),
                byteCount: descCount * descStride)
        }
        if !codeblocks.isEmpty {
            codeblocks.withUnsafeBytes { src in
                codeblocksBuffer.contents().copyMemory(
                    from: src.baseAddress!, byteCount: src.count)
            }
        }

        let pipeline = try await shaderLibrary.computePipeline(for: .subbandScatter)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create scatter cb/encoder")
        }
        try encode(into: encoder,
                   pipeline: pipeline,
                   descriptorBuffer: descBuffer,
                   descriptorCount: descCount,
                   codeblocksBuffer: codeblocksBuffer,
                   llBuffer: llBuffer, lhBuffer: lhBuffer,
                   hlBuffer: hlBuffer, hhBuffer: hhBuffer,
                   maxBlockWidth: descriptors.map { Int($0.blockWidth) }.max() ?? 0,
                   maxBlockHeight: descriptors.map { Int($0.blockHeight) }.max() ?? 0)
        encoder.endEncoding()
        cb.commit()
        await cb.completed()

        if cb.status == .error {
            throw J2KError.internalError(
                "subband scatter GPU kernel failed: \(cb.error?.localizedDescription ?? "(no description)")")
        }

        // Readback (same memcpy pattern as elsewhere — avoids the
        // release-mode Swift/Metal boundary deadlock).
        func readback(_ buffer: any MTLBuffer, count: Int) -> [Int32] {
            guard count > 0 else { return [] }
            return [Int32](unsafeUninitializedCapacity: count) { ptr, init_ in
                memcpy(ptr.baseAddress!, buffer.contents(),
                       count * MemoryLayout<Int32>.stride)
                init_ = count
            }
        }
        let llOut = readback(llBuffer, count: llCount)
        let lhOut = readback(lhBuffer, count: lhCount)
        let hlOut = readback(hlBuffer, count: hlCount)
        let hhOut = readback(hhBuffer, count: hhCount)

        let pool = bufferPool
        let toReturn: [any MTLBuffer] = [
            descBuffer, codeblocksBuffer,
            llBuffer, lhBuffer, hlBuffer, hhBuffer]
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        return (llOut, lhOut, hlOut, hhOut)
    }

    /// Encode a scatter dispatch into an existing compute encoder.
    /// Caller is responsible for descriptor + codeblocks buffer
    /// setup, allocating output buffers, zero-initialising padded
    /// regions, committing the cb, and reading back.
    public func encode(
        into encoder: any MTLComputeCommandEncoder,
        pipeline: any MTLComputePipelineState,
        descriptorBuffer: any MTLBuffer,
        descriptorCount: Int,
        codeblocksBuffer: any MTLBuffer,
        llBuffer: any MTLBuffer,
        lhBuffer: any MTLBuffer,
        hlBuffer: any MTLBuffer,
        hhBuffer: any MTLBuffer,
        maxBlockWidth: Int,
        maxBlockHeight: Int
    ) throws {
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        encoder.setBuffer(codeblocksBuffer, offset: 0, index: 1)
        encoder.setBuffer(llBuffer, offset: 0, index: 2)
        encoder.setBuffer(lhBuffer, offset: 0, index: 3)
        encoder.setBuffer(hlBuffer, offset: 0, index: 4)
        encoder.setBuffer(hhBuffer, offset: 0, index: 5)
        var dc = UInt32(descriptorCount)
        encoder.setBytes(&dc, length: MemoryLayout<UInt32>.stride, index: 6)

        // 3D dispatch: (sample_col, sample_row, block_idx). Each
        // thread handles one sample of one block. Bounds-checked
        // against the block's own dimensions inside the kernel.
        let gridW = max(1, maxBlockWidth)
        let gridH = max(1, maxBlockHeight)
        let gridZ = max(1, descriptorCount)
        encoder.dispatchThreads(
            MTLSize(width: gridW, height: gridH, depth: gridZ),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }
    #else
    public func run(
        descriptors: [J2KMetalSubbandScatterDescriptor],
        codeblocks: [Int32],
        llDimensions: (width: Int, height: Int),
        lhDimensions: (width: Int, height: Int),
        hlDimensions: (width: Int, height: Int),
        hhDimensions: (width: Int, height: Int)
    ) async throws -> (ll: [Int32], lh: [Int32], hl: [Int32], hh: [Int32]) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif
}
