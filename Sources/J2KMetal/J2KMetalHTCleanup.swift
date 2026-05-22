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

    // MARK: - v10.17-research — issue #440 GPU HT entropy redesign

    /// Lever A — reorder per-codeblock descriptors by descending
    /// codestream length before dispatch, so each 32-lane SIMD warp
    /// decodes blocks of similar entropy depth. The one-thread-per-block
    /// cleanup kernel makes a warp run at the speed of its slowest lane;
    /// grouping similar-cost blocks cuts that intra-warp divergence
    /// stall.
    ///
    /// **Lever A-prime** — a plain descriptor reorder regressed every
    /// fixture (v10.17 A/B): adjacent descriptors index adjacent
    /// regions of the codestream pool, so reordering scatters each
    /// warp's pool reads and thrashes the cache. A-prime therefore
    /// repacks the codestream pool into the sorted order too, rewriting
    /// the per-block offsets — preserving the warp-contiguous read
    /// pattern while still cost-sorting the blocks. Each descriptor
    /// carries its own `outputOffset`, so the output is bit-identical.
    /// Env `J2K_GPU_HT_SORT`, default OFF for the A/B.
    nonisolated(unsafe) public static var divergenceSortEnabled: Bool = {
        if let v = ProcessInfo.processInfo.environment["J2K_GPU_HT_SORT"] {
            return v == "1" || v.lowercased() == "true" || v.lowercased() == "yes"
        }
        return false
    }()

    /// Descending-cost descriptor sort + matching codestream-pool
    /// repack. `magsgnLength + melVlcLength` is the per-block codestream
    /// byte count — a proxy for the serial bit-parsing depth of the
    /// thread that decodes that block.
    static func maybeSortForDivergence(
        _ descriptors: [J2KMetalHTCleanupBlockDescriptor],
        pool: [UInt8]
    ) -> (descriptors: [J2KMetalHTCleanupBlockDescriptor], pool: [UInt8]) {
        guard divergenceSortEnabled, descriptors.count > 32 else {
            return (descriptors, pool)
        }
        let order = descriptors.indices.sorted {
            (UInt64(descriptors[$0].magsgnLength) + UInt64(descriptors[$0].melVlcLength))
                > (UInt64(descriptors[$1].magsgnLength) + UInt64(descriptors[$1].melVlcLength))
        }
        var newPool = [UInt8]()
        newPool.reserveCapacity(pool.count)
        var newDescriptors: [J2KMetalHTCleanupBlockDescriptor] = []
        newDescriptors.reserveCapacity(descriptors.count)
        for idx in order {
            let d = descriptors[idx]
            let ms = Int(d.magsgnOffset), msl = Int(d.magsgnLength)
            let mv = Int(d.melVlcOffset), mvl = Int(d.melVlcLength)
            guard ms + msl <= pool.count, mv + mvl <= pool.count else {
                return (descriptors, pool)   // malformed — leave untouched
            }
            let newMs = UInt32(newPool.count)
            newPool.append(contentsOf: pool[ms..<ms + msl])
            let newMv = UInt32(newPool.count)
            newPool.append(contentsOf: pool[mv..<mv + mvl])
            newDescriptors.append(J2KMetalHTCleanupBlockDescriptor(
                magsgnOffset: newMs, magsgnLength: d.magsgnLength,
                melVlcOffset: newMv, melVlcLength: d.melVlcLength,
                outputOffset: d.outputOffset, width: d.width,
                height: d.height, missingMSBs: d.missingMSBs))
        }
        return (newDescriptors, newPool)
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

        // v10.17-research Lever A-prime — divergence sort + pool repack.
        let (descriptors, codestreamPool) =
            Self.maybeSortForDivergence(descriptors, pool: codestreamPool)

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let descriptorStride = MemoryLayout<J2KMetalHTCleanupBlockDescriptor>.stride
        let blockCount = descriptors.count

        // Per-frame buffers come from the pool (bucket-rounded, returned
        // after readback). VLC tables are static spec data — uploaded
        // once into the shader library cache and reused across calls.
        let descriptorBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(blockCount * descriptorStride, 1))
        let codestreamBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(codestreamPool.count, 1))
        let outputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(outputSampleCount * MemoryLayout<UInt32>.stride, 1))
        let (vlc0Buffer, vlc1Buffer) = try await shaderLibrary.vlcTableBuffers(
            device: device, vlc0: vlcTable0, vlc1: vlcTable1)

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

        // dispatchThreads with threadsPerGroup=min(blockCount, 64) lets
        // Apple's SIMD scheduler pack 64 codeblocks (= 2 warps × 32 lanes)
        // into one threadgroup. The previous threadgroup-of-1 dispatch
        // forced one CB per warp, leaving 31 SIMD lanes idle on every
        // dispatch. The kernel uses only `thread`-private state and reads
        // `device`/`constant` buffers via per-thread offsets, so threads
        // within a warp are fully independent — no shared memory or
        // barriers needed. The `if (tid >= blockCount) return;` guard at
        // the top of the kernel handles the simd-width padding case.
        // Matches the phase-1 MagSgn convention (J2KMetalHTMagSgn.swift:133).
        let groupWidth = max(1, min(blockCount, 64))
        let threadsPerGroup = MTLSize(width: groupWidth, height: 1, depth: 1)
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

        // Read back via direct UnsafeMutableBufferPointer.initialize(from:)
        // — `Array.withUnsafeMutableBytes { dst.copyBytes(from:) }` was
        // observed to deadlock in release builds when the source pointer
        // came from a Metal `MTLBuffer.contents()` immediately after
        // `await cb.completed()`. The cause is a Swift-runtime / Metal
        // boundary issue, not a GPU error (status is .completed at this
        // point); writing into a separately-allocated raw buffer first
        // sidesteps it cleanly.
        let byteCount = outputSampleCount * MemoryLayout<UInt32>.stride
        let output: [UInt32]
        if outputSampleCount > 0 {
            J2KMetalUMACounters.incrementContents()
            J2KMetalUMACounters.incrementMemcpy()
            output = [UInt32](unsafeUninitializedCapacity: outputSampleCount) { ptr, initializedCount in
                memcpy(ptr.baseAddress!, outputBuffer.contents(), byteCount)
                initializedCount = outputSampleCount
            }
        } else {
            output = []
        }

        // Per-frame buffers are returned to the pool for reuse on the
        // next call. VLC table buffers stay cached in the shader library
        // and are NOT returned. We schedule the returns in a detached
        // Task because `bufferPool.returnBuffer` is actor-isolated and
        // we don't need to await it before returning the decoded output
        // (the buffers have already been memcpy'd out).
        let pool = bufferPool
        let toReturn = [descriptorBuffer, codestreamBuffer, outputBuffer]
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        let totalSamples = descriptors.reduce(0) { $0 + Int($1.width) * Int($1.height) }
        let stats = Statistics(
            wallClockSeconds: wallEnd - wallStart,
            gpuKernelSeconds: gpuKernelTime,
            blockCount: blockCount,
            totalSamples: totalSamples
        )
        return (output, stats)
    }

    /// Run the cleanup-pass decoder followed by per-sample
    /// dequantisation, both encoded in a single command buffer.
    /// Returns Int32 integer-magnitude coefficients (sign in bit 31
    /// via 2's complement, magnitude in the low bits) — the
    /// pipeline's native convention. The CPU-side dequant loop in
    /// `J2KGPUHTDispatch` was the per-sample shift+sign step that
    /// this kernel chain replaces.
    ///
    /// Bit-exact with `run(...)`'s UInt32 output put through the
    /// same dequant on CPU. v5.6.0; introduced for warm-process
    /// pipelines where the CPU dequant loop was the second-largest
    /// cost (after Metal init) per the v5.5.0 perf report.
    public func runIntegerMagnitude(
        descriptors: [J2KMetalHTCleanupBlockDescriptor],
        codestreamPool: [UInt8],
        vlcTable0: [UInt16],
        vlcTable1: [UInt16],
        outputSampleCount: Int
    ) async throws -> (output: [Int32], stats: Statistics) {
        precondition(vlcTable0.count == 1024, "vlcTable0 must have 1024 entries")
        precondition(vlcTable1.count == 1024, "vlcTable1 must have 1024 entries")

        // v10.17-research Lever A-prime — divergence sort + pool repack.
        let (descriptors, codestreamPool) =
            Self.maybeSortForDivergence(descriptors, pool: codestreamPool)

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let descriptorStride = MemoryLayout<J2KMetalHTCleanupBlockDescriptor>.stride
        let blockCount = descriptors.count

        // Acquire all per-frame buffers up front. The intermediate
        // sgnMagBuffer holds the cleanup kernel's UInt32 output and
        // is reused as the dequant kernel's input — same byte
        // count, just reinterpreted by the kernel binding.
        // v5.10: `sgnMagBuffer` is a pure GPU intermediate — written
        // by the cleanup kernel, read by the dequant kernel, never
        // touched by CPU. `.private` lets Apple's Metal stack pick
        // a faster layout and skip implicit coherency syncs. The
        // descriptor / codestream / output buffers stay `.shared`
        // because they are written / read by CPU at the boundary.
        let descriptorBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(blockCount * descriptorStride, 1))
        let codestreamBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(codestreamPool.count, 1))
        let sgnMagBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(outputSampleCount * MemoryLayout<UInt32>.stride, 1),
            strategy: .private)
        let outputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(outputSampleCount * MemoryLayout<Int32>.stride, 1))
        let (vlc0Buffer, vlc1Buffer) = try await shaderLibrary.vlcTableBuffers(
            device: device, vlc0: vlcTable0, vlc1: vlcTable1)

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

        let cleanupPipeline = try await shaderLibrary.computePipeline(for: .htCleanupDecode)
        let dequantPipeline = try await shaderLibrary.computePipeline(for: .htDequant)

        let wallStart = currentTime()
        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create Metal command buffer")
        }

        // Dispatch 1: HT cleanup — writes UInt32 sign-magnitude
        // into sgnMagBuffer.
        guard let cleanupEncoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create cleanup encoder")
        }
        cleanupEncoder.setComputePipelineState(cleanupPipeline)
        cleanupEncoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        cleanupEncoder.setBuffer(codestreamBuffer, offset: 0, index: 1)
        cleanupEncoder.setBuffer(vlc0Buffer, offset: 0, index: 2)
        cleanupEncoder.setBuffer(vlc1Buffer, offset: 0, index: 3)
        cleanupEncoder.setBuffer(sgnMagBuffer, offset: 0, index: 4)
        var bc = UInt32(blockCount)
        cleanupEncoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 5)
        let cleanupGroupWidth = max(1, min(blockCount, 64))
        cleanupEncoder.dispatchThreads(
            MTLSize(width: blockCount, height: 1, depth: 1),
            threadsPerThreadgroup:
                MTLSize(width: cleanupGroupWidth, height: 1, depth: 1))
        cleanupEncoder.endEncoding()

        // Dispatch 2: dequant — reads sgnMagBuffer, writes Int32
        // outputBuffer. Each thread handles one sample of one
        // block; the kernel bounds-checks per-block dimensions.
        guard let dequantEncoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create dequant encoder")
        }
        dequantEncoder.setComputePipelineState(dequantPipeline)
        dequantEncoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        dequantEncoder.setBuffer(sgnMagBuffer, offset: 0, index: 1)
        dequantEncoder.setBuffer(outputBuffer, offset: 0, index: 2)
        dequantEncoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 3)
        let maxSamples = descriptors.reduce(0) {
            max($0, Int($1.width) * Int($1.height))
        }
        dequantEncoder.dispatchThreads(
            MTLSize(width: max(maxSamples, 1), height: max(blockCount, 1), depth: 1),
            threadsPerThreadgroup: MTLSize(width: 32, height: 1, depth: 1))
        dequantEncoder.endEncoding()

        cb.commit()
        await cb.completed()
        let wallEnd = currentTime()

        if cb.status == .error {
            let errDesc = cb.error?.localizedDescription ?? "(no description)"
            throw J2KError.internalError("HT cleanup+dequant GPU chain failed: \(errDesc)")
        }

        let gpuKernelTime = max(0.0, cb.gpuEndTime - cb.gpuStartTime)

        // Read back Int32 directly. Same memcpy pattern as the
        // sign-magnitude path (avoids the release-mode Swift /
        // Metal boundary deadlock documented in feedback memory).
        let byteCount = outputSampleCount * MemoryLayout<Int32>.stride
        let output: [Int32]
        if outputSampleCount > 0 {
            J2KMetalUMACounters.incrementContents()
            J2KMetalUMACounters.incrementMemcpy()
            output = [Int32](unsafeUninitializedCapacity: outputSampleCount) { ptr, initializedCount in
                memcpy(ptr.baseAddress!, outputBuffer.contents(), byteCount)
                initializedCount = outputSampleCount
            }
        } else {
            output = []
        }

        let pool = bufferPool
        let toReturn = [descriptorBuffer, codestreamBuffer, sgnMagBuffer, outputBuffer]
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        let totalSamples = descriptors.reduce(0) { $0 + Int($1.width) * Int($1.height) }
        let stats = Statistics(
            wallClockSeconds: wallEnd - wallStart,
            gpuKernelSeconds: gpuKernelTime,
            blockCount: blockCount,
            totalSamples: totalSamples)
        return (output, stats)
    }
    #endif

    /// v5.8.0: same as `runIntegerMagnitude` but returns the GPU
    /// output buffer (Int32 integer-magnitude) instead of reading it
    /// back as `[Int32]`. The caller takes ownership of the buffer
    /// and is responsible for returning it to the buffer pool when
    /// done — typically by passing it through to the next stage of
    /// a fused HT → scatter → DWT pipeline.
    ///
    /// Use this entry point when the codeblock output stays
    /// GPU-resident across pipeline stages. Use `runIntegerMagnitude`
    /// when the caller needs `[Int32]` arrays.
    #if canImport(Metal)
    public func runIntegerMagnitudeReturningBuffer(
        descriptors: [J2KMetalHTCleanupBlockDescriptor],
        codestreamPool: [UInt8],
        vlcTable0: [UInt16],
        vlcTable1: [UInt16],
        outputSampleCount: Int
    ) async throws -> (
        outputBuffer: any MTLBuffer,
        outputSampleCount: Int,
        stats: Statistics
    ) {
        precondition(vlcTable0.count == 1024, "vlcTable0 must have 1024 entries")
        precondition(vlcTable1.count == 1024, "vlcTable1 must have 1024 entries")

        // v10.17-research Lever A-prime — divergence sort + pool repack.
        let (descriptors, codestreamPool) =
            Self.maybeSortForDivergence(descriptors, pool: codestreamPool)

        try await metalDevice.initialize()
        let queue = try await metalDevice.commandQueue()
        let device = queue.device
        try await shaderLibrary.loadShaders(device: device)

        let descriptorStride = MemoryLayout<J2KMetalHTCleanupBlockDescriptor>.stride
        let blockCount = descriptors.count

        // v5.10: `sgnMagBuffer` is a pure GPU intermediate (cleanup
        // writes, dequant reads). Allocate `.private`. The output
        // buffer is returned to the caller, which may CPU-read it
        // (the v5.6.0 / v5.9d slow paths slice per-block via
        // `.contents()`); keep it `.shared` for correctness across
        // all caller paths. v5.12+ could split the entry points if
        // we want a private-only `outputBuffer` for fast-lane-only
        // callers.
        let descriptorBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(blockCount * descriptorStride, 1))
        let codestreamBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(codestreamPool.count, 1))
        let sgnMagBuffer = try await bufferPool.acquireBuffer(
            device: device,
            size: max(outputSampleCount * MemoryLayout<UInt32>.stride, 1),
            strategy: .private)
        let outputBuffer = try await bufferPool.acquireBuffer(
            device: device, size: max(outputSampleCount * MemoryLayout<Int32>.stride, 1))
        let (vlc0Buffer, vlc1Buffer) = try await shaderLibrary.vlcTableBuffers(
            device: device, vlc0: vlcTable0, vlc1: vlcTable1)

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

        let cleanupPipeline = try await shaderLibrary.computePipeline(for: .htCleanupDecode)
        let dequantPipeline = try await shaderLibrary.computePipeline(for: .htDequant)

        let wallStart = currentTime()
        guard let cb = queue.makeCommandBuffer() else {
            throw J2KError.internalError("Failed to create Metal command buffer")
        }

        guard let cleanupEncoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create cleanup encoder")
        }
        cleanupEncoder.setComputePipelineState(cleanupPipeline)
        cleanupEncoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        cleanupEncoder.setBuffer(codestreamBuffer, offset: 0, index: 1)
        cleanupEncoder.setBuffer(vlc0Buffer, offset: 0, index: 2)
        cleanupEncoder.setBuffer(vlc1Buffer, offset: 0, index: 3)
        cleanupEncoder.setBuffer(sgnMagBuffer, offset: 0, index: 4)
        var bc = UInt32(blockCount)
        cleanupEncoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 5)
        let cleanupGroupWidth = max(1, min(blockCount, 64))
        cleanupEncoder.dispatchThreads(
            MTLSize(width: blockCount, height: 1, depth: 1),
            threadsPerThreadgroup:
                MTLSize(width: cleanupGroupWidth, height: 1, depth: 1))
        cleanupEncoder.endEncoding()

        guard let dequantEncoder = cb.makeComputeCommandEncoder() else {
            throw J2KError.internalError("Failed to create dequant encoder")
        }
        dequantEncoder.setComputePipelineState(dequantPipeline)
        dequantEncoder.setBuffer(descriptorBuffer, offset: 0, index: 0)
        dequantEncoder.setBuffer(sgnMagBuffer, offset: 0, index: 1)
        dequantEncoder.setBuffer(outputBuffer, offset: 0, index: 2)
        dequantEncoder.setBytes(&bc, length: MemoryLayout<UInt32>.stride, index: 3)
        let maxSamples = descriptors.reduce(0) {
            max($0, Int($1.width) * Int($1.height))
        }
        dequantEncoder.dispatchThreads(
            MTLSize(width: max(maxSamples, 1), height: max(blockCount, 1), depth: 1),
            threadsPerThreadgroup: MTLSize(width: 32, height: 1, depth: 1))
        dequantEncoder.endEncoding()

        cb.commit()
        await cb.completed()
        let wallEnd = currentTime()

        if cb.status == .error {
            let errDesc = cb.error?.localizedDescription ?? "(no description)"
            throw J2KError.internalError("HT cleanup+dequant GPU chain failed: \(errDesc)")
        }

        let gpuKernelTime = max(0.0, cb.gpuEndTime - cb.gpuStartTime)

        // Return the descriptor + codestream + sgnMag buffers to
        // the pool (no longer needed). The OUTPUT buffer is NOT
        // returned — caller owns it and will pass it to the next
        // pipeline stage.
        let pool = bufferPool
        let toReturn = [descriptorBuffer, codestreamBuffer, sgnMagBuffer]
        Task { for b in toReturn { await pool.returnBuffer(b) } }

        let totalSamples = descriptors.reduce(0) { $0 + Int($1.width) * Int($1.height) }
        let stats = Statistics(
            wallClockSeconds: wallEnd - wallStart,
            gpuKernelSeconds: gpuKernelTime,
            blockCount: blockCount,
            totalSamples: totalSamples)

        return (outputBuffer, outputSampleCount, stats)
    }
    #else
    public func runIntegerMagnitudeReturningBuffer(
        descriptors: [J2KMetalHTCleanupBlockDescriptor],
        codestreamPool: [UInt8],
        vlcTable0: [UInt16],
        vlcTable1: [UInt16],
        outputSampleCount: Int
    ) async throws -> (
        outputBuffer: Any,
        outputSampleCount: Int,
        stats: Statistics
    ) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    public func run(
        descriptors: [J2KMetalHTCleanupBlockDescriptor],
        codestreamPool: [UInt8],
        vlcTable0: [UInt16],
        vlcTable1: [UInt16],
        outputSampleCount: Int
    ) async throws -> (output: [UInt32], stats: Statistics) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }

    public func runIntegerMagnitude(
        descriptors: [J2KMetalHTCleanupBlockDescriptor],
        codestreamPool: [UInt8],
        vlcTable0: [UInt16],
        vlcTable1: [UInt16],
        outputSampleCount: Int
    ) async throws -> (output: [Int32], stats: Statistics) {
        throw J2KError.unsupportedFeature("Metal is not available on this platform")
    }
    #endif

    private func currentTime() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000.0
    }
}
