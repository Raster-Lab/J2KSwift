// J2KGPUHTDispatch.swift
// M2-prime scaffold: tile-level GPU HT cleanup batch dispatch.
//
// Owns the integration shim between the production decoder
// (J2KDecoderPipeline) and the kernel-level GPU HT cleanup
// decoder (J2KMetal.J2KMetalHTCleanup). Responsibilities:
//
//   1. Take a batch of conformant cleanup-only HT codeblocks and
//      build the J2KMetalHTCleanup descriptor + concatenated
//      codestream pool the kernel expects.
//   2. Dispatch the kernel once per batch (amortising the
//      per-dispatch overhead the phase-3 plan focused on).
//   3. Convert the kernel's UInt32 OpenJPH sign-magnitude output
//      to the pipeline's Int32 integer-magnitude convention,
//      replicating the per-block CPU step in
//      `J2KHTConformantDispatch.swift:92-107`.
//
// This file is the M2-prime scaffold (M2P-1). Pipeline integration
// (M2P-2), the `--gpu-ht` CLI flag (M2P-4), and the bit-exact
// parity gate (M2P-3) come in subsequent commits on this branch.
//
// Design notes:
// - Eligible blocks are conformant cleanup-only with non-empty data.
//   Anything else (refinement passes, custom-format, empty blocks)
//   falls back to CPU caller-side. We never return partial results
//   for an unparseable block — the dispatch surfaces the index list
//   it actually decoded and the caller fills in the rest from CPU.
// - This module already depends on J2KMetal (Package.swift:61), so
//   the import is unconditional. The Metal types themselves are
//   `#if canImport(Metal)`-gated inside J2KMetal, which means on
//   non-Apple platforms `J2KMetalHTCleanup.isAvailable` returns
//   false and `run(...)` throws `unsupportedFeature`. Callers
//   should check `J2KGPUHTDispatch.isAvailable` before dispatching.

import Foundation
import J2KCore
import J2KMetal

#if canImport(Metal)
@preconcurrency import Metal
#endif

/// One codeblock for GPU HT batch dispatch. Decoupled from the
/// pipeline's private `CodeBlockInfo` so this dispatcher is unit-
/// testable in isolation.
struct GPUHTBlock: Sendable {
    /// Codeblock width in samples (typically ≤ 64).
    let width: Int
    /// Codeblock height in samples (typically ≤ 64).
    let height: Int
    /// Raw conformant block bytes (post-`HTBlockLayoutConformant.assemble`).
    let data: [UInt8]
    /// `missingMSBs` per ITU T.814 — `p = 30 - missingMSBs`.
    let missingMSBs: Int
}

/// Decoded result for one block. `coefficients` is in the
/// pipeline's `Int32` integer-magnitude convention (sign in bit 31
/// via 2's complement, magnitude in the low bits). Order matches
/// the `decodedBlockIndices` returned alongside.
struct GPUHTBlockResult: Sendable {
    let coefficients: [Int32]
}

/// Output of `J2KGPUHTDispatch.decodeBatch`. The dispatcher only
/// returns results for blocks it could actually decode; caller is
/// responsible for filling in the remainder from CPU.
struct GPUHTBatchResult: Sendable {
    /// Indices into the input `blocks` array, in the same order as
    /// `results`. Length equals `results.count`.
    let decodedBlockIndices: [Int]
    /// Decoded coefficients per block. Length equals
    /// `decodedBlockIndices.count`.
    let results: [GPUHTBlockResult]
    /// Indices that were not decoded (parse failure, empty data,
    /// etc.). Caller should run these through the CPU HT path.
    let cpuFallbackIndices: [Int]
}

/// v5.8.0: GPU-resident HT batch — the codeblock buffer plus
/// per-(component, level) scatter plans, ready to feed straight
/// into `J2KMetalDWT.inverse2DInt32FullFusedFromCodeblocks`.
///
/// The pipeline's `applyEntropyDecoding` builds this when the
/// fused path is active (`useGPUHT && session && reversible53 &&
/// conformantHT && all-blocks-eligible`); the inverse-DWT stage
/// consumes it. After the fused dispatch completes, the caller is
/// responsible for returning `codeblockBuffer` to `bufferPool`.
struct J2KGPUHTBatch: Sendable {
    let codeblockBuffer: any MTLBuffer
    let outputSampleCount: Int
    /// Per component → per level (innermost first) → scatter plan.
    let plansByComponent: [Int: [J2KMetalDWT.LevelScatterPlan]]
    /// The pool that owns `codeblockBuffer`. After the fused
    /// dispatch, return the buffer to this pool.
    let bufferPool: J2KMetalBufferPool
}

/// v5.8.0: GPU-resident dispatch result. Holds the codeblock
/// output buffer (Int32 integer-magnitude) without reading it
/// back to host. Caller (typically the pipeline's
/// `applyEntropyDecoding`) is responsible for returning the
/// buffer to the pool when done — typically by passing it to
/// `J2KMetalDWT.inverse2DInt32FullFusedFromCodeblocks` and
/// returning after the fused dispatch completes.
///
/// `decodedBlockOutputOffsets` maps each decoded block's INPUT
/// index in the original `blocks` array to its OUTPUT offset (in
/// Int32 elements) inside the codeblock buffer. Pipeline uses
/// this to build per-level scatter descriptors that map
/// codeblocks to their (subband, x, y) destinations.
struct GPUHTBatchGPUResidentResult: Sendable {
    let codeblockBuffer: any MTLBuffer
    let outputSampleCount: Int
    /// [original block index → output offset in codeblockBuffer
    /// (Int32 elements)]. Eligible blocks only.
    let decodedBlockOutputOffsets: [Int: Int]
    let cpuFallbackIndices: [Int]
    /// v5.8 dedupe: per-block decoded coefficients (Int32 integer-
    /// magnitude) sliced from the codeblock buffer's shared memory
    /// at decode time. Saves the caller from running a second GPU
    /// decode just to get array form when both forms are needed
    /// (e.g. CPU regroup → [SubbandInfo] AND fused-DWT batch).
    /// Apple Silicon GPU buffers use unified memory, so this slice
    /// is just a memcpy from CPU-visible storage.
    let decodedBlockCoefficients: [Int: [Int32]]
}

enum J2KGPUHTDispatch {

    /// Whether GPU HT batch dispatch is available on this build.
    /// Mirrors `J2KMetalHTCleanup.isAvailable` so callers don't have
    /// to import J2KMetal directly to gate.
    static var isAvailable: Bool {
        J2KMetalHTCleanup.isAvailable
    }

    /// Run the GPU HT cleanup decoder over `blocks`. Eligible blocks
    /// (conformant cleanup-only, non-empty, parseable) are batched
    /// into a single kernel dispatch; ineligible blocks are
    /// reported in `cpuFallbackIndices` for the caller to handle.
    ///
    /// - Parameter blocks: Codeblocks to attempt on GPU. Blocks may
    ///   come from any subband, level, or component — the kernel
    ///   does not care, it operates per-codeblock.
    /// - Parameter cleanup: Optional pre-built `J2KMetalHTCleanup`
    ///   instance. Pass one in to share the buffer pool across
    ///   multiple `decodeBatch` calls (e.g. across tiles in the
    ///   same decode session).
    /// - Returns: The subset of blocks decoded on GPU plus the
    ///   indices of blocks that fell back to CPU.
    /// - Throws: ``J2KError/unsupportedFeature(_:)`` if Metal isn't
    ///   available, or kernel dispatch errors propagated from
    ///   `J2KMetalHTCleanup.run`.
    static func decodeBatch(
        blocks: [GPUHTBlock],
        cleanup: J2KMetalHTCleanup? = nil,
        session: J2KMetalSession? = nil
    ) async throws -> GPUHTBatchResult {
        guard isAvailable else {
            throw J2KError.unsupportedFeature(
                "GPU HT dispatch requires Metal (not available on this platform)")
        }
        if blocks.isEmpty {
            return GPUHTBatchResult(
                decodedBlockIndices: [],
                results: [],
                cpuFallbackIndices: [])
        }

        // Pass 1: filter eligible blocks, build descriptors and pool.
        var eligibleIndices: [Int] = []
        var fallbackIndices: [Int] = []
        var descriptors: [J2KMetalHTCleanupBlockDescriptor] = []
        var pool: [UInt8] = []
        var sampleOffsets: [Int] = []  // per-eligible-block, into output buffer

        for (i, block) in blocks.enumerated() {
            if block.data.isEmpty {
                fallbackIndices.append(i)
                continue
            }
            guard let parsed = HTBlockLayoutConformant.parse(block: block.data)
            else {
                fallbackIndices.append(i)
                continue
            }

            let magsgnOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.magsgn)
            let melVlcOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.melVlc)

            let outputOffset = sampleOffsets.last
                .map { $0 + blocks[eligibleIndices.last!].width *
                       blocks[eligibleIndices.last!].height } ?? 0
            sampleOffsets.append(outputOffset)

            descriptors.append(J2KMetalHTCleanupBlockDescriptor(
                magsgnOffset: magsgnOffset,
                magsgnLength: UInt32(parsed.magsgn.count),
                melVlcOffset: melVlcOffset,
                melVlcLength: UInt32(parsed.scup),
                outputOffset: UInt32(outputOffset),
                width: UInt32(block.width),
                height: UInt32(block.height),
                missingMSBs: UInt32(block.missingMSBs)))
            eligibleIndices.append(i)
        }

        if eligibleIndices.isEmpty {
            return GPUHTBatchResult(
                decodedBlockIndices: [],
                results: [],
                cpuFallbackIndices: fallbackIndices)
        }

        // Total output samples = last block's offset + its sample count.
        let lastEligibleIdx = eligibleIndices.last!
        let totalSamples = sampleOffsets.last! +
            blocks[lastEligibleIdx].width * blocks[lastEligibleIdx].height

        // Single batch dispatch. Resolution order:
        //   1. Caller-supplied `cleanup` instance — most explicit.
        //   2. Caller-supplied `session` — share device/library/pool
        //      across decodes for warm-process amortisation.
        //   3. Fresh per-call instance — v5.5.0 default behaviour.
        let cleanupKernel: J2KMetalHTCleanup
        if let cleanup {
            cleanupKernel = cleanup
        } else if let session {
            cleanupKernel = J2KMetalHTCleanup(
                metalDevice: session.device,
                shaderLibrary: session.shaderLibrary,
                bufferPool: session.bufferPool)
        } else {
            cleanupKernel = J2KMetalHTCleanup()
        }

        // v5.6.0: when a session is in scope, run the GPU dequant
        // kernel chained in the same command buffer as the cleanup
        // dispatch. The CPU-side per-sample shift+sign loop below
        // disappears for this path. The sessionless path stays on
        // the v5.5.0 UInt32-output kernel + CPU dequant — same
        // observable behaviour, but the integration shape is the
        // foundation for cb fusion in v5.7.
        var results: [GPUHTBlockResult] = []
        results.reserveCapacity(eligibleIndices.count)
        if session != nil || cleanup != nil {
            let (gpuInts, _) = try await cleanupKernel.runIntegerMagnitude(
                descriptors: descriptors,
                codestreamPool: pool,
                vlcTable0: vlcDecoderTable0Conformant,
                vlcTable1: vlcDecoderTable1Conformant,
                outputSampleCount: totalSamples)
            for (i, blockIdx) in eligibleIndices.enumerated() {
                let block = blocks[blockIdx]
                let start = sampleOffsets[i]
                let end = start + block.width * block.height
                results.append(GPUHTBlockResult(
                    coefficients: Array(gpuInts[start..<end])))
            }
        } else {
            let (gpuOutput, _) = try await cleanupKernel.run(
                descriptors: descriptors,
                codestreamPool: pool,
                vlcTable0: vlcDecoderTable0Conformant,
                vlcTable1: vlcDecoderTable1Conformant,
                outputSampleCount: totalSamples)
            // CPU-side per-block dequant from UInt32 OpenJPH sign-
            // magnitude to Int32 integer-magnitude. Same conversion
            // J2KHTConformantDispatch.swift:100-106 does on the
            // existing CPU HT path.
            for (i, blockIdx) in eligibleIndices.enumerated() {
                let block = blocks[blockIdx]
                let shift = 30 - block.missingMSBs
                let start = sampleOffsets[i]
                let end = start + block.width * block.height
                let coeffs: [Int32] = gpuOutput[start..<end].map { uint in
                    let sign = (uint & 0x8000_0000) != 0
                    let mag = Int32((uint & 0x7FFF_FFFF) >> shift)
                    return sign ? -mag : mag
                }
                results.append(GPUHTBlockResult(coefficients: coeffs))
            }
        }

        return GPUHTBatchResult(
            decodedBlockIndices: eligibleIndices,
            results: results,
            cpuFallbackIndices: fallbackIndices)
    }

    /// v5.8: GPU-resident decode. Same eligibility filter and batch
    /// dispatch as `decodeBatch`, but returns the codeblock output
    /// buffer (Int32 integer-magnitude) without reading back to
    /// host. Caller takes ownership of the returned buffer —
    /// typically passes it to
    /// `J2KMetalDWT.inverse2DInt32FullFusedFromCodeblocks` and
    /// returns it to the pool after the fused dispatch completes.
    ///
    /// Requires a `J2KMetalSession`: the codeblock buffer is
    /// allocated from the session's pool, and the returned buffer
    /// must be returned to the same pool.
    ///
    /// v5.9 zero-copy: `includePerBlockCoefficients = false` skips
    /// the per-block memcpy slicing loop and leaves
    /// `decodedBlockCoefficients` empty in the result. Use when the
    /// caller plans to read codeblock data directly from the GPU
    /// buffer (`bufferPtr + decodedBlockOutputOffsets[i]`) — this
    /// is the v5.9 fast-lane gate. Default `true` preserves the
    /// v5.8 dedupe behaviour for callers that consume both forms.
    static func decodeBatchGPUResident(
        blocks: [GPUHTBlock],
        session: J2KMetalSession,
        includePerBlockCoefficients: Bool = true
    ) async throws -> GPUHTBatchGPUResidentResult? {
        guard isAvailable else {
            throw J2KError.unsupportedFeature(
                "GPU HT dispatch requires Metal (not available on this platform)")
        }
        if blocks.isEmpty { return nil }

        // Pass 1: filter eligible blocks, build descriptors and pool
        // (same shape as decodeBatch).
        var eligibleIndices: [Int] = []
        var fallbackIndices: [Int] = []
        var descriptors: [J2KMetalHTCleanupBlockDescriptor] = []
        var pool: [UInt8] = []
        var sampleOffsets: [Int] = []

        for (i, block) in blocks.enumerated() {
            if block.data.isEmpty {
                fallbackIndices.append(i)
                continue
            }
            guard let parsed = HTBlockLayoutConformant.parse(block: block.data)
            else {
                fallbackIndices.append(i)
                continue
            }

            let magsgnOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.magsgn)
            let melVlcOffset = UInt32(pool.count)
            pool.append(contentsOf: parsed.melVlc)

            let outputOffset = sampleOffsets.last
                .map { $0 + blocks[eligibleIndices.last!].width *
                       blocks[eligibleIndices.last!].height } ?? 0
            sampleOffsets.append(outputOffset)

            descriptors.append(J2KMetalHTCleanupBlockDescriptor(
                magsgnOffset: magsgnOffset,
                magsgnLength: UInt32(parsed.magsgn.count),
                melVlcOffset: melVlcOffset,
                melVlcLength: UInt32(parsed.scup),
                outputOffset: UInt32(outputOffset),
                width: UInt32(block.width),
                height: UInt32(block.height),
                missingMSBs: UInt32(block.missingMSBs)))
            eligibleIndices.append(i)
        }

        // No eligible blocks ⇒ no GPU work to do; signal caller to
        // fall back to the v5.7.0 path entirely (return nil).
        if eligibleIndices.isEmpty {
            return nil
        }

        let lastEligibleIdx = eligibleIndices.last!
        let totalSamples = sampleOffsets.last! +
            blocks[lastEligibleIdx].width * blocks[lastEligibleIdx].height

        // Reuse the session's HT cleanup instance (so device + library
        // + buffer pool match the one the DWT path will use).
        let cleanupKernel = J2KMetalHTCleanup(
            metalDevice: session.device,
            shaderLibrary: session.shaderLibrary,
            bufferPool: session.bufferPool)
        let (codeblockBuffer, _, _) = try await cleanupKernel.runIntegerMagnitudeReturningBuffer(
            descriptors: descriptors,
            codestreamPool: pool,
            vlcTable0: vlcDecoderTable0Conformant,
            vlcTable1: vlcDecoderTable1Conformant,
            outputSampleCount: totalSamples)

        // v5.8 dedupe: slice per-block coefficient arrays from the
        // codeblock buffer's shared memory once. Same content the
        // v5.6.0 `decodeBatch` API reads back on its own; doing it
        // here avoids a second GPU decode in callers that need
        // both [Int32] arrays AND the GPU buffer (i.e. the
        // fused-DWT pipeline path).
        // Map original block index → output offset (in Int32 samples).
        // Always populated. Per-block coefficient slicing is opt-in
        // via `includePerBlockCoefficients`.
        var offsets: [Int: Int] = [:]
        var perBlockCoefficients: [Int: [Int32]] = [:]
        if totalSamples > 0 {
            for (i, originalBlockIdx) in eligibleIndices.enumerated() {
                offsets[originalBlockIdx] = sampleOffsets[i]
            }
            if includePerBlockCoefficients {
                J2KMetalUMACounters.incrementContents()
                let bufferPtr = codeblockBuffer.contents()
                    .bindMemory(to: Int32.self, capacity: totalSamples)
                for (i, originalBlockIdx) in eligibleIndices.enumerated() {
                    let block = blocks[originalBlockIdx]
                    let start = sampleOffsets[i]
                    let count = block.width * block.height
                    J2KMetalUMACounters.incrementMemcpy()
                    let coeffs = [Int32](unsafeUninitializedCapacity: count) { ptr, init_ in
                        memcpy(ptr.baseAddress!, bufferPtr + start,
                               count * MemoryLayout<Int32>.stride)
                        init_ = count
                    }
                    perBlockCoefficients[originalBlockIdx] = coeffs
                }
            }
        }

        return GPUHTBatchGPUResidentResult(
            codeblockBuffer: codeblockBuffer,
            outputSampleCount: totalSamples,
            decodedBlockOutputOffsets: offsets,
            cpuFallbackIndices: fallbackIndices,
            decodedBlockCoefficients: perBlockCoefficients)
    }
}
