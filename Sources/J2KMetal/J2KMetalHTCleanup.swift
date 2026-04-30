//
// J2KMetalHTCleanup.swift
// J2KSwift
//
// Phase-2 GPU HT decoder slice: full cleanup-pass decoder. Combines
// MEL run-length + VLC table lookup + UVLC + MagSgn into a single
// MSL kernel. Bit-exact with the CPU `HTBlockDecoderConformant.decode`.
//
// One thread per codeblock; descriptor + pool layout matches the
// dispatch probe and the phase-1 MagSgn decoder so the same upload
// / marshal plumbing is reused.
//
// Tables (vlcDecoderTable0/1Conformant, 1024 UInt16 entries each)
// are passed in as `[UInt16]` parameters by the caller — the caller
// owns table construction (the J2KCodec module computes them; tests
// supply them directly). MEL exp values are inlined as a `constant`
// array in the kernel itself — only 13 ints, never changes.
//

import Foundation
import J2KCore

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// Per-codeblock cleanup descriptor. Memory layout mirrors the MSL
/// `GPUHTCleanupDescriptor` struct field-for-field — all-UInt32 fields
/// for unambiguous 4-byte alignment across Swift/MSL, stride 32 bytes.
/// `@frozen` locks the field order so the release-mode optimizer
/// cannot reorder fields and break the GPU-side struct match.
@frozen
public struct J2KMetalHTCleanupBlockDescriptor: Sendable {
    public let magsgnOffset: UInt32
    public let magsgnLength: UInt32
    public let melVlcOffset: UInt32
    public let melVlcLength: UInt32       // == scup
    public let outputOffset: UInt32       // sample offset into Int32/UInt32 pool
    public let width: UInt32
    public let height: UInt32
    public let missingMSBs: UInt32

    public init(magsgnOffset: UInt32, magsgnLength: UInt32,
                melVlcOffset: UInt32, melVlcLength: UInt32,
                outputOffset: UInt32,
                width: UInt32, height: UInt32, missingMSBs: UInt32) {
        self.magsgnOffset = magsgnOffset
        self.magsgnLength = magsgnLength
        self.melVlcOffset = melVlcOffset
        self.melVlcLength = melVlcLength
        self.outputOffset = outputOffset
        self.width = width
        self.height = height
        self.missingMSBs = missingMSBs
    }
}

public struct J2KMetalHTCleanup: Sendable {

    public let metalDevice: J2KMetalDevice
    public let shaderLibrary: J2KMetalShaderLibrary

    public init(metalDevice: J2KMetalDevice = J2KMetalDevice(),
                shaderLibrary: J2KMetalShaderLibrary? = nil) {
        self.metalDevice = metalDevice
        self.shaderLibrary = shaderLibrary ?? J2KMetalShaderLibrary()
    }

    public static var isAvailable: Bool { J2KMetalDWT.isAvailable }

    public struct Statistics: Sendable {
        public let wallClockSeconds: Double
        public let gpuKernelSeconds: Double
        public let blockCount: Int
        public let totalSamples: Int
    }

    #if canImport(Metal)
    /// Run the cleanup-pass decoder over `descriptors`. Returns one
    /// UInt32 per output sample in OpenJPH sign-magnitude convention
    /// (bit 31 = sign, magnitude in bits below `p = 30 - missingMSBs`).
    /// Caller is responsible for converting to integer-magnitude Int32
    /// at the dispatch boundary if downstream pipeline needs that.
    public func run(
        descriptors: [J2KMetalHTCleanupBlockDescriptor],
        codestreamPool: [UInt8],
        vlcTable0: [UInt16],
        vlcTable1: [UInt16],
        outputSampleCount: Int
    ) async throws -> (output: [UInt32], stats: Statistics) {
        precondition(vlcTable0.count == 1024, "vlcTable0 must have 1024 entries")
        precondition(vlcTable1.count == 1024, "vlcTable1 must have 1024 entries")

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

        let descriptorStride = MemoryLayout<J2KMetalHTCleanupBlockDescriptor>.stride
        let blockCount = descriptors.count
        let descriptorBuffer = try makeBuffer(size: blockCount * descriptorStride)
        let codestreamBuffer = try makeBuffer(size: max(codestreamPool.count, 1))
        let vlc0Buffer = try makeBuffer(size: 1024 * MemoryLayout<UInt16>.stride)
        let vlc1Buffer = try makeBuffer(size: 1024 * MemoryLayout<UInt16>.stride)
        let outputBuffer = try makeBuffer(size: outputSampleCount * MemoryLayout<UInt32>.stride)

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
        vlcTable0.withUnsafeBytes { src in
            vlc0Buffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }
        vlcTable1.withUnsafeBytes { src in
            vlc1Buffer.contents().copyMemory(from: src.baseAddress!, byteCount: src.count)
        }

        let pipeline = try await shaderLibrary.computePipeline(for: .htCleanupDecode)

        let wallStart = currentTime()
        guard let cb = queue.makeCommandBuffer(),
              let encoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create Metal command buffer/encoder")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        encoder.setBuffer(codestreamBuffer, offset: 0, index: 1)
        encoder.setBuffer(vlc0Buffer, offset: 0, index: 2)
        encoder.setBuffer(vlc1Buffer, offset: 0, index: 3)
        encoder.setBuffer(outputBuffer, offset: 0, index: 4)
        var bc = UInt32(blockCount)
        encoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 5)

        let threadsPerGroup = MTLSize(width: min(blockCount, 64), height: 1, depth: 1)
        let gridSize = MTLSize(width: blockCount, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        cb.commit()
        await cb.completed()
        let wallEnd = currentTime()

        if cb.status == .error {
            let errDesc = cb.error?.localizedDescription ?? "(no description)"
            throw J2KError.internalError("HT cleanup GPU kernel failed: \(errDesc)")
        }

        let gpuKernelTime = max(0.0, cb.gpuEndTime - cb.gpuStartTime)

        var output = [UInt32](repeating: 0, count: outputSampleCount)
        if outputSampleCount > 0 {
            output.withUnsafeMutableBytes { dst in
                dst.copyBytes(from: UnsafeRawBufferPointer(
                    start: outputBuffer.contents(),
                    count: outputSampleCount * MemoryLayout<UInt32>.stride
                ))
            }
        }

        let totalSamples = descriptors.reduce(0) { $0 + Int($1.width) * Int($1.height) }
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
        descriptors: [J2KMetalHTCleanupBlockDescriptor],
        codestreamPool: [UInt8],
        vlcTable0: [UInt16],
        vlcTable1: [UInt16],
        outputSampleCount: Int
    ) async throws -> (output: [UInt32], stats: Statistics) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
