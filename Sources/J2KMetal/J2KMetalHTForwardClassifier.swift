//
// J2KMetalHTForwardClassifier.swift
// J2KSwift
//
// v6-alpha6 phase 1 (approach B) — per-sample classifier for
// HT-conformant forward entropy. Mirrors `sampleInfo` in
// `J2KHTConformantBlockEncoder.swift` line for line; output tuples
// are bit-exact equivalent to what the CPU `HTSampleInfoSIMDPrototype`
// produces. The CPU-side encoder consumes the tuple stream this
// emits and produces the inherently-serial MagSgn / MEL / VLC byte
// streams that have to stay on CPU due to the `0xFF` byte-stuffing
// rule (see `docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md` §3).
//
// This is the *parallelizable half* of forward HT entropy; the
// CPU-emitter integration that uses these tuples is Phase 1.1.
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Per-codeblock descriptor matching `GPUHTForwardClassifyDescriptor`
/// in the Metal shader source. Keep field order in sync — uploaded
/// directly via `copyMemory(from: descriptors)`.
public struct J2KMetalHTForwardClassifyDescriptor: Sendable {
    /// Sample offset into the concatenated coefficient pool.
    public let coeffOffset: UInt32
    /// Tuple (UInt64) offset into the output pool.
    public let tupleOffset: UInt32
    /// Sample count for this block (`width * height`).
    public let sampleCount: UInt32
    /// Bit-depth shift parameter — the `p` from the CPU `sampleInfo`
    /// formula (`val = (t * 2) >> p & ~1`). Per ISO/IEC 15444-15
    /// terminology this is `Kmsbs + 1` style; the CPU code threads it
    /// through as `UInt32 p`.
    public let p: UInt32

    public init(coeffOffset: UInt32, tupleOffset: UInt32,
                sampleCount: UInt32, p: UInt32) {
        self.coeffOffset = coeffOffset
        self.tupleOffset = tupleOffset
        self.sampleCount = sampleCount
        self.p = p
    }
}

/// Output-tuple decoder — bit-exact inverse of the kernel's pack:
///   bit 63 = sig, bits 56..62 = eQ, bits 0..31 = payload.
public struct J2KMetalHTForwardClassifierTuple: Sendable, Equatable {
    public let sig: Bool
    public let eQ: UInt32
    public let payload: UInt32

    public init(sig: Bool, eQ: UInt32, payload: UInt32) {
        self.sig = sig
        self.eQ = eQ
        self.payload = payload
    }

    /// Decode the kernel-emitted UInt64.
    public static func unpack(_ raw: UInt64) -> Self {
        let sig = (raw >> 63) & 1 != 0
        let eQ = UInt32((raw >> 56) & 0x7F)
        let payload = UInt32(raw & 0xFFFF_FFFF)
        return Self(sig: sig, eQ: eQ, payload: payload)
    }
}

/// Wrapper that uploads coefficients + per-block descriptors,
/// dispatches `j2k_ht_forward_classify_samples`, and reads back the
/// per-sample tuple stream.
public struct J2KMetalHTForwardClassifier: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    #if canImport(Metal)
    /// Run the classifier.
    ///
    /// - Parameters:
    ///   - descriptors: per-codeblock layout array.
    ///   - coefficients: concatenated UInt32 coefficient pool, indexed
    ///     by `descriptor.coeffOffset` for a span of
    ///     `descriptor.sampleCount` samples.
    ///   - tupleCount: total output tuple count = sum of all
    ///     `descriptor.sampleCount` values.
    /// - Returns: a UInt64 array of length `tupleCount`. Each entry
    ///   decodes via `J2KMetalHTForwardClassifierTuple.unpack`.
    public func classify(
        descriptors: [J2KMetalHTForwardClassifyDescriptor],
        coefficients: [UInt32],
        tupleCount: Int
    ) async throws -> [UInt64] {
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

        let descriptorStride = MemoryLayout<J2KMetalHTForwardClassifyDescriptor>.stride
        let blockCount = descriptors.count
        let descriptorBuffer = try makeBuffer(size: blockCount * descriptorStride)
        let coefficientBuffer = try makeBuffer(
            size: max(coefficients.count * MemoryLayout<UInt32>.stride, 1))
        let tupleBuffer = try makeBuffer(
            size: max(tupleCount * MemoryLayout<UInt64>.stride, 1))

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

        let pipeline = try await shaderLibrary.computePipeline(for: .htForwardClassifySamples)

        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        encoder.setBuffer(coefficientBuffer, offset: 0, index: 1)
        encoder.setBuffer(tupleBuffer, offset: 0, index: 2)
        var bc = UInt32(blockCount)
        encoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 3)

        let threadsPerGroup = MTLSize(width: min(blockCount, 64), height: 1, depth: 1)
        let gridSize = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()

        cb.commit()
        await cb.completed()

        // Per `feedback_metal_readback.md`: do NOT use
        // `Array.withUnsafeMutableBytes { copyBytes(from: ...) }` —
        // that pattern deadlocks in release mode. Use
        // `unsafeUninitializedCapacity + memcpy` instead.
        let tuples: [UInt64]
        if tupleCount > 0 {
            tuples = [UInt64](unsafeUninitializedCapacity: tupleCount) { dst, initCount in
                memcpy(dst.baseAddress!, tupleBuffer.contents(),
                       tupleCount * MemoryLayout<UInt64>.stride)
                initCount = tupleCount
            }
        } else {
            tuples = []
        }
        return tuples
    }
    #else
    public func classify(
        descriptors: [J2KMetalHTForwardClassifyDescriptor],
        coefficients: [UInt32],
        tupleCount: Int
    ) async throws -> [UInt64] {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif
}
