//
// J2KMetalHTForwardDispatchProbe.swift
// J2KSwift
//
// v6-alpha6 phase 0.5 — symmetric to `J2KMetalHTDispatchProbe` but for
// the **encode** direction. Dispatch-cost probe for the eventual GPU
// HT-conformant forward entropy encoder. NOT a real encoder — runs
// the layout the encoder will use (concatenated coefficient pool,
// per-block descriptor array, single kernel dispatch over `blockCount`
// threads) with synthetic per-block work that matches the read+write
// traffic shape an actual encoder will see.
//
// The empirical question this probe answers, per
// `docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md` §4:
//
//   "Does the per-block GPU dispatch + memory-traffic floor leave
//    room for the actual entropy work to win against CPU's
//    parallel-codeblock encode?"
//
// If `gpuKernelSeconds` for ~2300 codeblocks (DX 12 MP) exceeds the
// CPU per-block parallel encode wall (~30–40 ms on M2), GPU is dead
// for this stage and Phase 1 pivots from approach B (GPU classify +
// CPU emit) to approach E (CPU-SIMD only, no GPU).
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Per-codeblock descriptor matching `GPUHTForwardBlockDescriptor` in
/// the Metal shader source. Keep field order in sync — uploaded
/// directly via `copyMemory(from: descriptors)`.
public struct J2KMetalHTForwardBlockDescriptor: Sendable {
    /// Sample offset into the concatenated coefficient pool.
    public let coeffOffset: UInt32
    /// Byte offset into the concatenated output byte pool.
    public let outputOffset: UInt32
    /// Upper bound on bytes this block may write. Real encoders bound
    /// each codeblock's emission with a `maxCodewordCapacity`-style
    /// quantity; we carry it through so the kernel can clamp.
    public let outputCapacity: UInt32
    public let width: UInt16
    public let height: UInt16

    public init(coeffOffset: UInt32, outputOffset: UInt32,
                outputCapacity: UInt32,
                width: UInt16, height: UInt16) {
        self.coeffOffset = coeffOffset
        self.outputOffset = outputOffset
        self.outputCapacity = outputCapacity
        self.width = width
        self.height = height
    }
}

public struct J2KMetalHTForwardDispatchProbeStatistics: Sendable {
    /// Wall-clock for the full Swift call (encode + commit + completion + readback).
    public let wallClockSeconds: Double
    /// `commandBuffer.gpuStartTime` → `commandBuffer.gpuEndTime` (kernel only).
    public let gpuKernelSeconds: Double
    /// Number of codeblocks processed.
    public let blockCount: Int
    /// Total UInt32 coefficients across all blocks (read traffic).
    public let totalCoefficients: Int
    /// Total bytes the kernel was asked to write (write traffic upper bound).
    public let totalOutputCapacity: Int
}

/// Wrapper that uploads coefficients + per-block descriptors + scratch
/// output buffer, dispatches `j2k_ht_forward_dispatch_probe`, and
/// reports both wall-clock and GPU-only timings. Symmetric to
/// `J2KMetalHTDispatchProbe`; uses the
/// `unsafeUninitializedCapacity + memcpy` readback pattern per
/// `feedback_metal_readback.md` to avoid the release-mode deadlock
/// `Array.withUnsafeMutableBytes { copyBytes(from: ...) }` produces.
public struct J2KMetalHTForwardDispatchProbe: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    #if canImport(Metal)
    /// Run the probe over `descriptors`. The coefficient pool is the
    /// concatenation of all per-block sign-magnitude UInt32 inputs
    /// (`descriptors[i].width × descriptors[i].height` slots starting
    /// at `coeffOffset`). The output byte pool is
    /// `descriptors[i].outputCapacity` bytes per block; the kernel
    /// writes up to half the per-block sample count, clamped by
    /// capacity.
    ///
    /// Returns `(output, stats)` where `output` is the produced byte
    /// pool (so callers can sanity-check that writes happened) and
    /// `stats` carries timing.
    public func run(
        descriptors: [J2KMetalHTForwardBlockDescriptor],
        coefficients: [UInt32],
        outputByteCount: Int
    ) async throws -> (output: [UInt8], stats: J2KMetalHTForwardDispatchProbeStatistics) {
        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        func makeBuffer(size: Int) throws -> any MTLBuffer {
            guard let buffer = device.makeBuffer(
                length: max(size, 1), options: .storageModeShared
            ) else {
                throw J2KError.internalError("Failed to allocate Metal buffer of \(size) bytes")
            }
            return buffer
        }

        let descriptorStride = MemoryLayout<J2KMetalHTForwardBlockDescriptor>.stride
        let blockCount = descriptors.count
        let descriptorBuffer = try makeBuffer(size: blockCount * descriptorStride)
        let coefficientBuffer = try makeBuffer(
            size: max(coefficients.count * MemoryLayout<UInt32>.stride, 1))
        let outputBuffer = try makeBuffer(size: max(outputByteCount, 1))

        descriptors.withUnsafeBufferPointer { src in
            descriptorBuffer.contents()
                .copyMemory(from: UnsafeRawPointer(src.baseAddress!),
                            byteCount: blockCount * descriptorStride)
        }
        if !coefficients.isEmpty {
            coefficients.withUnsafeBufferPointer { src in
                coefficientBuffer.contents().copyMemory(
                    from: UnsafeRawPointer(src.baseAddress!),
                    byteCount: src.count * MemoryLayout<UInt32>.stride)
            }
        }

        let pipeline = try await shaderLibrary.computePipeline(for: .htForwardDispatchProbe)

        let wallStart = currentTime()
        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        encoder.setBuffer(coefficientBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        var bc = UInt32(blockCount)
        encoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 3)

        let threadsPerGroup = MTLSize(width: min(blockCount, 64), height: 1, depth: 1)
        let gridSize = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()
        let wallEnd = currentTime()

        let gpuKernelTime = max(0.0, cb.gpuEndTime - cb.gpuStartTime)

        // Per `feedback_metal_readback.md`: do NOT use
        // `Array.withUnsafeMutableBytes { copyBytes(from: ...) }` —
        // that pattern deadlocks in release mode. Use
        // `unsafeUninitializedCapacity + memcpy` instead.
        let output: [UInt8]
        if outputByteCount > 0 {
            output = [UInt8](unsafeUninitializedCapacity: outputByteCount) { dst, initCount in
                memcpy(dst.baseAddress!, outputBuffer.contents(), outputByteCount)
                initCount = outputByteCount
            }
        } else {
            output = []
        }

        let totalCoefficients = descriptors.reduce(0) { $0 + Int($1.width) * Int($1.height) }
        let totalOutputCapacity = descriptors.reduce(0) { $0 + Int($1.outputCapacity) }
        let stats = J2KMetalHTForwardDispatchProbeStatistics(
            wallClockSeconds: wallEnd - wallStart,
            gpuKernelSeconds: gpuKernelTime,
            blockCount: blockCount,
            totalCoefficients: totalCoefficients,
            totalOutputCapacity: totalOutputCapacity
        )
        return (output, stats)
    }
    #else
    public func run(
        descriptors: [J2KMetalHTForwardBlockDescriptor],
        coefficients: [UInt32],
        outputByteCount: Int
    ) async throws -> (output: [UInt8], stats: J2KMetalHTForwardDispatchProbeStatistics) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
