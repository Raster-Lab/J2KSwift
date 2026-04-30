//
// J2KMetalHTDispatchProbe.swift
// J2KSwift
//
// Dispatch-cost probe for the GPU HT decoder prototype. NOT a real
// decoder — runs the layout the eventual GPU HT decoder will use
// (concatenated codestream pool, per-block descriptor array, single
// kernel dispatch over `blockCount` threads) with trivial per-block
// work, so we can isolate the Metal launch + memory marshaling cost
// from the actual decode work.
//
// Used by GPU_EBCOT_FEASIBILITY follow-up work to answer:
//   - At what blockCount does GPU dispatch beat the per-CPU-thread
//     parallel codeblock decode (J2KCPU's task-group baseline)?
//   - What's the marginal cost of one extra codeblock on GPU?
//   - Is the per-codeblock memory traffic the bottleneck, or compute?
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Per-codeblock descriptor matching the `GPUHTBlockDescriptor` struct
/// declared in the Metal shader source. Keep field order in sync.
public struct J2KMetalHTBlockDescriptor: Sendable {
    public let dataOffset: UInt32
    public let dataLength: UInt32
    public let outputOffset: UInt32
    public let width: UInt16
    public let height: UInt16

    public init(dataOffset: UInt32, dataLength: UInt32, outputOffset: UInt32,
                width: UInt16, height: UInt16) {
        self.dataOffset = dataOffset
        self.dataLength = dataLength
        self.outputOffset = outputOffset
        self.width = width
        self.height = height
    }
}

public struct J2KMetalHTDispatchProbeStatistics: Sendable {
    /// Wall-clock for the full Swift call (encode + commit + completion).
    public let wallClockSeconds: Double
    /// `commandBuffer.gpuStartTime` → `commandBuffer.gpuEndTime` (kernel only).
    public let gpuKernelSeconds: Double
    /// Number of codeblocks processed.
    public let blockCount: Int
}

/// Wrapper that uploads a batch of codeblock descriptors + codestream
/// + scratch output, dispatches the `j2k_ht_dispatch_probe` kernel,
/// and reports both wall-clock and GPU-only timings.
public struct J2KMetalHTDispatchProbe: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    /// Whether Metal is available on the current platform.
    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    #if canImport(Metal)
    /// Run the probe over `blocks`. The codestream pool is the
    /// concatenation of all per-block bytes (`blocks[i].data` is taken
    /// from `codestreamPool` at the descriptor's `dataOffset`/`dataLength`).
    /// The output pool is sized to the total `width × height` of all
    /// blocks; per-block writes go to `outputOffset`.
    ///
    /// Returns `(output, stats)` where `output` is the produced Int32
    /// pool and `stats` carries timing.
    public func run(
        descriptors: [J2KMetalHTBlockDescriptor],
        codestreamPool: [UInt8],
        outputSampleCount: Int
    ) async throws -> (output: [Int32], stats: J2KMetalHTDispatchProbeStatistics) {
        let dbg = ProcessInfo.processInfo.environment["J2K_PROBE_DEBUG"] != nil
        if dbg { print("[probe] init start") }
        try await metalDevice.initialize()
        if dbg { print("[probe] device ok") }
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        if dbg { print("[probe] loading shaders") }
        try await shaderLibrary.loadShaders(device: device)
        if dbg { print("[probe] shaders ok") }

        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1), options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let descriptorStride = MemoryLayout<J2KMetalHTBlockDescriptor>.stride
        let blockCount = descriptors.count
        let descriptorBuffer = try makeBuffer(size: blockCount * descriptorStride)
        let codestreamBuffer = try makeBuffer(size: max(codestreamPool.count, 1))
        let outputBuffer = try makeBuffer(size: outputSampleCount * MemoryLayout<Int32>.stride)

        descriptors.withUnsafeBufferPointer { src in
            descriptorBuffer.contents()
                .copyMemory(from: UnsafeRawPointer(src.baseAddress!),
                            byteCount: blockCount * descriptorStride)
        }
        if !codestreamPool.isEmpty {
            codestreamPool.withUnsafeBytes { src in
                codestreamBuffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }

        if dbg { print("[probe] requesting pipeline") }
        let pipeline = try await shaderLibrary.computePipeline(for: .htDispatchProbe)
        if dbg { print("[probe] pipeline ok") }

        let wallStart = currentTime()
        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        encoder.setBuffer(codestreamBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        var bc = UInt32(blockCount)
        encoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 3)

        let threadsPerGroup = MTLSize(width: min(blockCount, 64), height: 1, depth: 1)
        let gridSize = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        if dbg { print("[probe] committing") }

        cb.commit()
        if dbg { print("[probe] awaiting completion") }
        await cb.completed()
        if dbg { print("[probe] completed") }
        let wallEnd = currentTime()

        let gpuKernelTime = max(0.0, cb.gpuEndTime - cb.gpuStartTime)

        var output = [Int32](repeating: 0, count: outputSampleCount)
        if outputSampleCount > 0 {
            output.withUnsafeMutableBytes { dst in
                dst.copyBytes(from: UnsafeRawBufferPointer(
                    start: outputBuffer.contents(),
                    count: outputSampleCount * MemoryLayout<Int32>.stride
                ))
            }
        }

        let stats = J2KMetalHTDispatchProbeStatistics(
            wallClockSeconds: wallEnd - wallStart,
            gpuKernelSeconds: gpuKernelTime,
            blockCount: blockCount
        )
        return (output, stats)
    }
    #else
    public func run(
        descriptors: [J2KMetalHTBlockDescriptor],
        codestreamPool: [UInt8],
        outputSampleCount: Int
    ) async throws -> (output: [Int32], stats: J2KMetalHTDispatchProbeStatistics) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
