//
// J2KEntropyIntegrityAccounting.swift
// J2KSwift
//
// Per-code-block byte accounting gathered during entropy decoding, and its
// aggregation into the public ``J2KCodestreamIntegrity`` report.
//
// The public model lives in `J2KCore` (see `J2KCodestreamIntegrity.swift`
// there) because ``J2KError`` does and the corruption case carries a report.
// These types stay here because they touch `MQDecoder` and
// `RawBypassDecoder`, which are internal to this module.
//

import Foundation
import J2KCore

// MARK: - Per-block accumulation

/// Byte accounting for one code-block, accumulated across its pass segments.
///
/// A block coded with bypass or restart mode is split into several
/// independently terminated segments, so both figures are sums.
struct J2KBlockIntegrity: Sendable {
    /// Bytes the packet header declared across every segment of this block.
    var declaredBytes: Int = 0
    /// Bytes the entropy decoders actually consumed.
    var consumedBytes: Int = 0
    /// Reads past the end of a segment, summed across segments.
    var overReadCount: Int = 0
    /// Coding passes the packet header declared.
    var passesDeclared: Int = 0
    /// Coding passes actually decoded.
    var passesDecoded: Int = 0

    /// Declared bytes the decoder never read.
    var underRead: Int { max(0, declaredBytes - consumedBytes) }

    /// Folds in one finished MQ segment.
    ///
    /// Called immediately before the decoder is replaced for the next pass
    /// segment, and once more when the bit-plane loop ends, so every instance
    /// is counted exactly once.
    mutating func absorb(_ decoder: MQDecoder) {
        declaredBytes += decoder.segmentBytes
        consumedBytes += decoder.consumedBytes
        overReadCount += decoder.overReadCount
    }

    /// Folds in one finished raw-bypass segment.
    ///
    /// Bypass passes are coded without the arithmetic coder, so they have no
    /// over-read to report — the raw reader simply stops at the end.
    mutating func absorb(_ decoder: RawBypassDecoder) {
        declaredBytes += decoder.segmentBytes
        consumedBytes += decoder.consumedBytes
    }

    mutating func merge(_ other: J2KBlockIntegrity) {
        declaredBytes += other.declaredBytes
        consumedBytes += other.consumedBytes
        overReadCount += other.overReadCount
        passesDeclared += other.passesDeclared
        passesDecoded += other.passesDecoded
    }
}

// MARK: - Builder

/// Accumulates per-block accounting during a decode and renders the report.
///
/// Decoding runs concurrently over chunks of code-blocks, so each chunk fills
/// its own builder and the results are merged. Merging is associative and the
/// block indices are assigned by the caller, so the merged report does not
/// depend on the order chunks happen to finish in.
struct J2KIntegrityBuilder: Sendable {
    private(set) var blocks: [(index: Int, integrity: J2KBlockIntegrity)] = []
    private(set) var missingEOC: Bool = false

    mutating func record(block index: Int, _ integrity: J2KBlockIntegrity) {
        blocks.append((index, integrity))
    }

    mutating func recordMissingEOC() { missingEOC = true }

    mutating func merge(_ other: J2KIntegrityBuilder) {
        blocks.append(contentsOf: other.blocks)
        missingEOC = missingEOC || other.missingEOC
    }

    /// Renders the report.
    ///
    /// - Parameter isPartialDecode: whether the caller limited the decode by
    ///   quality layer, resolution or region. When true, under-read and tile
    ///   residual are expected and are measured but not flagged.
    func report(isPartialDecode: Bool) -> J2KCodestreamIntegrity {
        var anomalies: [J2KIntegrityAnomaly] = []
        var blocksUnderRead = 0
        var maxUnderRead = 0
        var totalUnderRead = 0
        var blocksOverRead = 0
        var maxOverRead = 0

        // Sort so the anomaly list is deterministic regardless of the order
        // concurrent chunks completed in.
        for (index, integrity) in blocks.sorted(by: { $0.index < $1.index }) {
            let under = integrity.underRead
            totalUnderRead += under
            maxUnderRead = max(maxUnderRead, under)

            if under > J2KIntegrityThresholds.benignBlockUnderRead {
                blocksUnderRead += 1
                if !isPartialDecode {
                    anomalies.append(.codeBlockUnderRead(
                        block: index,
                        declared: integrity.declaredBytes,
                        consumed: integrity.consumedBytes))
                }
            }

            maxOverRead = max(maxOverRead, integrity.overReadCount)
            if integrity.overReadCount > J2KIntegrityThresholds.benignBlockOverRead {
                blocksOverRead += 1
                if !isPartialDecode {
                    anomalies.append(.codeBlockOverRead(
                        block: index,
                        declared: integrity.declaredBytes,
                        overRead: integrity.overReadCount))
                }
            }
        }

        // A partial decode stops before the end of the codestream by design,
        // so the absence of EOC says nothing about the file.
        if missingEOC && !isPartialDecode {
            anomalies.append(.missingEndOfCodestream)
        }

        return J2KCodestreamIntegrity(
            codeBlocksDecoded: blocks.count,
            blocksUnderRead: blocksUnderRead,
            maxBlockUnderRead: maxUnderRead,
            totalUnderReadBytes: totalUnderRead,
            blocksOverRead: blocksOverRead,
            maxBlockOverRead: maxOverRead,
            missingEndOfCodestream: missingEOC,
            isPartialDecode: isPartialDecode,
            anomalies: anomalies
        )
    }
}

// MARK: - Concurrent collection

/// Gathers integrity accounting from concurrently decoded chunks of code-blocks.
///
/// Entropy decoding fans out over chunks. Each chunk fills a private
/// ``J2KIntegrityBuilder`` and folds it in here once, when the chunk finishes,
/// so the lock is taken once per chunk rather than once per code-block and
/// stays off the per-block hot path.
final class J2KIntegrityCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var builder = J2KIntegrityBuilder()

    init() {}

    /// Folds one finished chunk's accounting into the whole.
    func absorb(_ chunk: J2KIntegrityBuilder) {
        guard !chunk.blocks.isEmpty else { return }
        lock.lock()
        builder.merge(chunk)
        lock.unlock()
    }

    /// Records that the codestream ended without an `EOC` marker.
    func recordMissingEOC() {
        lock.lock()
        builder.recordMissingEOC()
        lock.unlock()
    }

    /// Renders the aggregated report.
    func report(isPartialDecode: Bool) -> J2KCodestreamIntegrity {
        lock.lock()
        defer { lock.unlock() }
        return builder.report(isPartialDecode: isPartialDecode)
    }
}
