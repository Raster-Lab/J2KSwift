// J2KGPUForwardHTEntropyBatch.swift
//
// v6-alpha6 phase 1.2 / v7.1.0 I1.3d — batched GPU forward HT
// entropy. Production wire-in calls into this from
// `applyEntropyCodingHTJ2KFused`; the API is exposed as public so
// dedicated bit-exact tests can drive it without standing up the
// full encoder pipeline.
//
// The contract (post-I1.3d, **approach C**):
//   1. Build a per-block descriptor array (coeffOffset, tupleOffset,
//      sampleCount, p) from the input `PendingBlock` list.
//   2. Concatenate all blocks' sign-magnitude UInt32 coefficients
//      into a single pool sized for one GPU upload.
//   3. Dispatch the GPU classifier ONCE — Phase 0.5 demonstrated
//      this layout amortises the dispatch overhead across all
//      blocks of a tile.
//   4. Dispatch the **unified Pass 3 cleanup-pass kernel** once
//      across all blocks (one threadgroup per block). Produces all
//      three streams (MagSgn, MEL, VLC) entirely on GPU. See I1.3b
//      / I1.3c (`J2KGPUForwardHTCleanupPassEmit`).
//   5. Return per-block `(magsgn, mel, vlc)` byte tuples in the
//      same order as input.
//
// **Bit-exact correctness invariant**: the `(magsgn, mel, vlc)`
// tuple this returns for any block is byte-identical to what
// `HTBlockEncoderConformant.encode(...)` returns for the same
// block on the CPU-only path. Validated by
// `HTGPUForwardHTEntropyBatchBitExactTests` and the I1.3b/c tests.
//
// **History**: v6-alpha6 phase 1 wired this via approach B (GPU
// classifier + CPU emit), which regressed −200 % at every corpus
// scale on M2 because the dispatch overhead exceeded CPU emit
// cost. v7.1.0 I1.3d swaps step 4 to approach C (full GPU emit)
// per the user's "approach C is definite, even if we compromise
// speed" directive.

import Foundation
import J2KCore
import J2KMetal

/// Public batched GPU-classify + CPU-emit entry point.
public enum J2KGPUForwardHTEntropyBatch {

    /// Per-block input — one entry per codeblock the encoder wants
    /// processed. Coefficients are pre-converted to sign-magnitude
    /// UInt32 per OpenJPH convention (top bit = sign, low bits =
    /// magnitude shifted left by `31 - K_max`).
    public struct PendingBlock: Sendable {
        public let coefficients: [UInt32]
        public let width: Int
        public let height: Int
        public let missingMSBs: Int

        public init(coefficients: [UInt32], width: Int, height: Int,
                    missingMSBs: Int) {
            self.coefficients = coefficients
            self.width = width
            self.height = height
            self.missingMSBs = missingMSBs
        }
    }

    /// Per-block output — three byte streams ready to feed
    /// `HTBlockLayoutConformant.assemble`, in the same order as the
    /// input `PendingBlock` array.
    public struct EncodedBlock: Sendable {
        public let magsgn: [UInt8]
        public let mel: [UInt8]
        public let vlc: [UInt8]
    }

    /// Dispatch one GPU classifier over every block, then emit each
    /// block's bytes on CPU using the GPU-produced tuple stream.
    ///
    /// - Parameters:
    ///   - blocks: per-block coefficient + dimensions + missingMSBs
    ///     descriptors. Must be non-empty (callers should gate via
    ///     `_gpuForwardHTEntropyBlockThreshold` before calling).
    ///   - classifier: optional injected classifier; defaults to a
    ///     fresh `J2KMetalHTForwardClassifier()` reusing the shared
    ///     metal session.
    /// - Returns: per-block `EncodedBlock` in input order.
    public static func encodeBlockBatch(
        _ blocks: [PendingBlock],
        classifier: J2KMetalHTForwardClassifier =
            J2KMetalHTForwardClassifier()
    ) async throws -> [EncodedBlock] {
        guard !blocks.isEmpty else { return [] }

        // 1. Build descriptors + concatenated coefficient pool.
        var descriptors: [J2KMetalHTForwardClassifyDescriptor] = []
        descriptors.reserveCapacity(blocks.count)
        var totalSamples = 0
        for b in blocks { totalSamples += b.width * b.height }

        var coefficients = [UInt32]()
        coefficients.reserveCapacity(totalSamples)

        var coeffOffset: UInt32 = 0
        var tupleOffset: UInt32 = 0
        for b in blocks {
            precondition(b.coefficients.count == b.width * b.height,
                "PendingBlock coefficient count mismatch: " +
                "got \(b.coefficients.count), expected \(b.width * b.height)")
            precondition(b.missingMSBs < 30,
                "missingMSBs must leave room for data; got \(b.missingMSBs)")
            let n = UInt32(b.width * b.height)
            descriptors.append(J2KMetalHTForwardClassifyDescriptor(
                coeffOffset: coeffOffset,
                tupleOffset: tupleOffset,
                sampleCount: n,
                p: UInt32(30 - b.missingMSBs)))
            coefficients.append(contentsOf: b.coefficients)
            coeffOffset += n
            tupleOffset += n
        }

        // 2. Dispatch classifier (one GPU call for the whole batch).
        let dispatchT0 = Date().timeIntervalSinceReferenceDate
        let tuples = try await classifier.classify(
            descriptors: descriptors,
            coefficients: coefficients,
            tupleCount: Int(tupleOffset))
        let dispatchMs = (Date().timeIntervalSinceReferenceDate - dispatchT0) * 1000.0

        // 3. **Approach C** — dispatch the unified Pass 3 cleanup-pass
        //    kernel for the whole batch. Uses the flat-buffer API so
        //    the classifier's already-flat tuples buffer feeds the
        //    emit kernel directly — **no per-block array allocation**.
        //    Saves O(N × samplesPerBlock) Swift allocs that the legacy
        //    `BlockDescriptor` API forced. For DX 2x2 (~2,300 blocks
        //    × 32×32 = ~2.4 M samples) that's a ~18 MB allocation
        //    elided per encode call.
        let emitT0 = Date().timeIntervalSinceReferenceDate

        var emitInputs: [J2KGPUForwardHTCleanupPassEmit.FlatBlockDescriptor] = []
        emitInputs.reserveCapacity(blocks.count)
        for (i, b) in blocks.enumerated() {
            let desc = descriptors[i]
            emitInputs.append(.init(
                width: b.width, height: b.height,
                missingMSBs: b.missingMSBs,
                tupleStart: Int(desc.tupleOffset)))
        }

        let batched = try await J2KGPUForwardHTCleanupPassEmit().emitBlocksFlat(
            tuples: tuples, blocks: emitInputs)
        var out: [EncodedBlock] = []
        out.reserveCapacity(blocks.count)
        for i in 0..<blocks.count {
            out.append(EncodedBlock(
                magsgn: batched.perBlockMagsgn[i],
                mel: batched.perBlockMel[i],
                vlc: batched.perBlockVlc[i]))
        }
        let emitMs = (Date().timeIntervalSinceReferenceDate - emitT0) * 1000.0

        J2KGPUForwardHTEntropyTelemetry.recordGPUFire(
            blockCount: blocks.count,
            dispatchMs: dispatchMs,
            emitMs: emitMs)

        return out
    }
}
