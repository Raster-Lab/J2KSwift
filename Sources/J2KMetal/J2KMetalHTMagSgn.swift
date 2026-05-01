//
// J2KMetalHTMagSgn.swift
// J2KSwift
//
// Phase-1 GPU HT decoder slice: MagSgn forward bit reader.
//
// Per-codeblock decoder kernel that reads N bits per sample from a
// forward-stuffed MagSgn byte stream — the same operation
// `HTMagSgnDecoderConformant.read(count:)` performs on CPU. One thread
// per codeblock; descriptor + pool layout matches the dispatch-probe
// (J2KMetalHTDispatchProbe) so phase-2's full cleanup-pass kernel
// reuses the same upload/marshal plumbing.
//
// This is **not** a full HT decoder yet. It exists so we can validate
// the MSL bit-reader against the CPU reference in isolation, and to
// pin down the per-thread compute cost before adding the MEL/VLC
// passes on top in phase 2.
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Per-codeblock MagSgn descriptor. Memory layout mirrors the MSL
/// `GPUHTMagSgnDescriptor` struct field-for-field — no padding.
public struct J2KMetalHTMagSgnBlockDescriptor: Sendable {
    public let dataOffset: UInt32
    public let dataLength: UInt32
    public let widthsOffset: UInt32
    public let outputOffset: UInt32
    public let sampleCount: UInt32

    public init(dataOffset: UInt32, dataLength: UInt32,
                widthsOffset: UInt32, outputOffset: UInt32,
                sampleCount: UInt32) {
        self.dataOffset = dataOffset
        self.dataLength = dataLength
        self.widthsOffset = widthsOffset
        self.outputOffset = outputOffset
        self.sampleCount = sampleCount
    }
}

/// Wraps `j2k_ht_magsgn_decode`. Identical batched layout to the
/// dispatch probe so the same memory-marshaling characterisation
/// applies (~1 ms wall-clock floor + ~0.04 ms/codeblock from the
/// probe results — phase-1 numbers will land somewhere comparable
/// since the per-thread work is also light).
public struct J2KMetalHTMagSgn: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary
    public let bufferPool: J2KMetalBufferPool

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil,
                bufferPool: J2KMetalBufferPool? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
        self.bufferPool = bufferPool ?? J2KMetalBufferPool()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    public struct Statistics: Sendable {
        public let wallClockSeconds: Double
        public let gpuKernelSeconds: Double
        public let blockCount: Int
        public let totalSamples: Int
    }

    #if canImport(Metal)
    /// Run the MagSgn decoder over `descriptors`. Returns one `UInt32`
    /// per sample (sum of `desc.sampleCount` across all blocks).
    public func run(
        descriptors: [J2KMetalHTMagSgnBlockDescriptor],
        codestreamPool: [UInt8],
        widthsPool: [UInt8],
        outputSampleCount: Int
    ) async throws -> (output: [UInt32], stats: Statistics) {
        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let descriptorStride = MemoryLayout<J2KMetalHTMagSgnBlockDescriptor>.stride
        let blockCount = descriptors.count
        let descriptorBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(blockCount * descriptorStride, 1))
        let codestreamBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(codestreamPool.count, 1))
        let widthsBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(widthsPool.count, 1))
        let outputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(outputSampleCount * MemoryLayout<UInt32>.stride, 1))

        descriptors.withUnsafeBufferPointer { src in
            descriptorBuffer.contents().copyMemory(
                from: UnsafeRawPointer(src.baseAddress!),
                byteCount: blockCount * descriptorStride)
        }
        if !codestreamPool.isEmpty {
            codestreamPool.withUnsafeBytes { src in
                codestreamBuffer.contents().copyMemory(
                    from: src.baseAddress!, byteCount: src.count)
            }
        }
        if !widthsPool.isEmpty {
            widthsPool.withUnsafeBytes { src in
                widthsBuffer.contents().copyMemory(
                    from: src.baseAddress!, byteCount: src.count)
            }
        }

        let pipeline = try await shaderLibrary.computePipeline(for: .htMagsgnDecode)

        let wallStart = currentTime()
        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        encoder.setBuffer(codestreamBuffer, offset: 0, index: 1)
        encoder.setBuffer(widthsBuffer, offset: 0, index: 2)
        encoder.setBuffer(outputBuffer, offset: 0, index: 3)
        var bc = UInt32(blockCount)
        encoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 4)

        let threadsPerGroup = MTLSize(width: min(blockCount, 64), height: 1, depth: 1)
        let gridSize = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        cb.commit()
        await cb.completed()
        let wallEnd = currentTime()

        let gpuKernelTime = max(0.0, cb.gpuEndTime - cb.gpuStartTime)

        // Readback uses unsafeUninitializedCapacity + memcpy to avoid the
        // release-mode Swift-runtime deadlock observed when copying from
        // MTLBuffer.contents() into an Array via withUnsafeMutableBytes
        // (see HTCleanup readback for the full diagnosis).
        let byteCount = outputSampleCount * MemoryLayout<UInt32>.stride
        let output: [UInt32]
        if outputSampleCount > 0 {
            output = [UInt32](unsafeUninitializedCapacity: outputSampleCount) { ptr, initializedCount in
                memcpy(ptr.baseAddress!, outputBuffer.contents(), byteCount)
                initializedCount = outputSampleCount
            }
        } else {
            output = []
        }

        let pool = bufferPool
        let toReturn = [descriptorBuffer, codestreamBuffer, widthsBuffer, outputBuffer]
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        let totalSamples = descriptors.reduce(0) { $0 + Int($1.sampleCount) }
        let stats = Statistics(
            wallClockSeconds: wallEnd - wallStart,
            gpuKernelSeconds: gpuKernelTime,
            blockCount: blockCount,
            totalSamples: totalSamples
        )
        return (output, stats)
    }
    #else
    public func run(
        descriptors: [J2KMetalHTMagSgnBlockDescriptor],
        codestreamPool: [UInt8],
        widthsPool: [UInt8],
        outputSampleCount: Int
    ) async throws -> (output: [UInt32], stats: Statistics) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
