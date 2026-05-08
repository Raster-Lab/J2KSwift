// J2KMetalPrefixSum.swift
//
// v7.1.0 I1.1 — Pass 2 of approach C (GPU forward HT entropy).
//
// Single-threadgroup inclusive prefix-sum over a UInt32 array.
// Used by approach C's Pass 2 to convert per-block byte counts
// into per-block byte offsets in the concatenated output buffer.
//
// **Scope** (per `docs/V7_1_0_I1_0_DESIGN.md`): N up to 1024 elements
// per dispatch. For DX 2x2 multi-tile fixtures we typically have
// ~2,300 blocks per tile — Pass 2's prefix-sum operates on per-tile
// chunks of ≤ 1024 each, with multiple dispatches stitched in I1.2
// orchestration code.
//
// **Why single-threadgroup**: N is small (~thousands). Multi-
// threadgroup scan adds dispatch overhead that exceeds the savings
// at this scale. A single 1024-thread group with two-level simd
// scan completes in microseconds on Apple M2.

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Inclusive prefix-sum over UInt32 arrays — Pass 2 of v7.1.0
/// approach C GPU forward HT entropy pipeline.
///
/// Bit-exact with CPU reference scan; tested by
/// `MetalHTForwardPrefixSumTests`.
public struct J2KMetalPrefixSum: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    /// Maximum number of elements supported by a single dispatch.
    /// Tied to Apple M2 threadgroup-size limit; matches the kernel's
    /// single-threadgroup design constraint.
    public static let maxElementsPerDispatch: Int = 1024

    #if canImport(Metal)
    /// Compute inclusive prefix-sum: `output[i] = input[0] + input[1] + ... + input[i]`.
    ///
    /// - Parameter input: UInt32 array; up to `maxElementsPerDispatch` elements.
    /// - Returns: UInt32 array of the same length with inclusive prefix-sum.
    /// - Throws: `J2KError.invalidParameter` if input is too large for a single
    ///   dispatch; `J2KError.internalError` for Metal allocation/dispatch failures.
    public func inclusiveScan(_ input: [UInt32]) async throws -> [UInt32] {
        guard input.count <= Self.maxElementsPerDispatch else {
            throw J2KError.invalidParameter(
                "J2KMetalPrefixSum: single-dispatch limit is \(Self.maxElementsPerDispatch) elements; " +
                "got \(input.count). Use multi-dispatch orchestration for larger N.")
        }
        if input.isEmpty { return [] }

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let n = input.count
        let byteCount = n * MemoryLayout<UInt32>.stride

        guard let inputBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let outputBuffer = device.makeBuffer(length: byteCount, options: .storageModeShared)
        else {
            throw J2KError.internalError("J2KMetalPrefixSum: failed to allocate Metal buffers")
        }

        input.withUnsafeBufferPointer { src in
            inputBuffer.contents().copyMemory(
                from: UnsafeRawPointer(src.baseAddress!),
                byteCount: byteCount)
        }

        let pipeline = try await shaderLibrary.computePipeline(for: .prefixSumInclusiveUInt32)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder()
        else {
            throw J2KError.internalError("J2KMetalPrefixSum: failed to create command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(inputBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        var nU32 = UInt32(n)
        encoder.setBytes(&nU32, length: MemoryLayout<UInt32>.stride, index: 2)

        // Round threadgroup size up to a multiple of 32 (simdgroup
        // size on Apple Silicon) to keep the simd_prefix_* primitives
        // operating on full warps. The kernel only writes for
        // `tid < n`, so over-dispatching is safe.
        let simdSize = 32
        let tgSize = ((n + simdSize - 1) / simdSize) * simdSize
        let threadsPerGroup = MTLSize(width: tgSize, height: 1, depth: 1)
        let gridSize = MTLSize(width: tgSize, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()

        // Per `feedback_metal_readback.md`: do NOT use
        // `Array.withUnsafeMutableBytes { copyBytes(from: ...) }` —
        // that pattern deadlocks in release mode. Use
        // `unsafeUninitializedCapacity + memcpy` instead.
        let result: [UInt32] = [UInt32](unsafeUninitializedCapacity: n) { dst, initCount in
            memcpy(dst.baseAddress!, outputBuffer.contents(), byteCount)
            initCount = n
        }
        return result
    }
    #else
    public func inclusiveScan(_ input: [UInt32]) async throws -> [UInt32] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif
}
