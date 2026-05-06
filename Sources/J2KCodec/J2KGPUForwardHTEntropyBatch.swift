// J2KGPUForwardHTEntropyBatch.swift
//
// v6-alpha6 phase 1.2 — standalone batched API for the GPU forward
// HT entropy path. Production wire-in (Phase 1.3) calls into this
// from `applyEntropyCodingHTJ2KFused`; the API is exposed as public
// so dedicated bit-exact tests can drive it without standing up the
// full encoder pipeline.
//
// The contract:
//   1. Build a per-block descriptor array (coeffOffset, tupleOffset,
//      sampleCount, p) from the input `PendingBlock` list.
//   2. Concatenate all blocks' sign-magnitude UInt32 coefficients
//      into a single pool sized for one GPU upload.
//   3. Dispatch the GPU classifier ONCE — Phase 0.5 demonstrated
//      this layout amortises the dispatch overhead across all
//      blocks of a tile (DX 1584 blocks → 2.3 µs/block ≈ 11 % of
//      CPU entropy budget).
//   4. Per-block emit: walk each block's slice of the tuple stream
//      and call `HTBlockEncoderConformant.encode(..., preClassifiedTuples:)`
//      on CPU. The MagSgn / MEL / VLC streams stay on CPU due to
//      the `0xFF` byte-stuffing rule (plan doc §3).
//   5. Return per-block `(magsgn, mel, vlc)` byte tuples in the
//      same order as input.
//
// **Bit-exact correctness invariant**: the `(magsgn, mel, vlc)`
// tuple this returns for any block is byte-identical to what
// `HTBlockEncoderConformant.encode(...)` returns for the same
// block on the CPU-only path. Validated by
// `HTGPUForwardHTEntropyBatchBitExactTests`.

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

        // 3. Per-block CPU emit. Reuses one set of stream encoders
        //    across all blocks in this batch (matches the v5.38 M8
        //    pattern in the production CPU path).
        let emitT0 = Date().timeIntervalSinceReferenceDate
        var out: [EncodedBlock] = []
        out.reserveCapacity(blocks.count)
        var magsgnEnc = HTMagSgnEncoderConformant()
        var melEnc = HTMELEncoderConformant()
        var vlcEnc = HTReverseBitEmitterConformant()

        for (i, b) in blocks.enumerated() {
            let desc = descriptors[i]
            let coeffStart = Int(desc.coeffOffset)
            let coeffEnd   = coeffStart + b.coefficients.count
            let tupleStart = Int(desc.tupleOffset)
            let tupleEnd   = tupleStart + b.coefficients.count
            let result = coefficients.withUnsafeBufferPointer { coeffBuf in
                tuples.withUnsafeBufferPointer { tupleBuf in
                    // Construct slices via baseAddress arithmetic to
                    // avoid array copies.
                    let coeffSlice = UnsafeBufferPointer(
                        start: coeffBuf.baseAddress! + coeffStart,
                        count: coeffEnd - coeffStart)
                    let tupleSlice = UnsafeBufferPointer(
                        start: tupleBuf.baseAddress! + tupleStart,
                        count: tupleEnd - tupleStart)
                    return HTBlockEncoderConformant.encode(
                        coefficients: coeffSlice,
                        width: b.width, height: b.height,
                        missingMSBs: b.missingMSBs,
                        magsgnEnc: &magsgnEnc, melEnc: &melEnc,
                        vlcEnc: &vlcEnc,
                        useSIMDClassification: false,
                        preClassifiedTuples: tupleSlice)
                }
            }
            out.append(EncodedBlock(
                magsgn: result.magsgn, mel: result.mel, vlc: result.vlc))
        }
        let emitMs = (Date().timeIntervalSinceReferenceDate - emitT0) * 1000.0

        J2KGPUForwardHTEntropyTelemetry.recordGPUFire(
            blockCount: blocks.count,
            dispatchMs: dispatchMs,
            emitMs: emitMs)

        return out
    }
}
