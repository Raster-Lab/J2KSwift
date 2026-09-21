//
// J2KCodestreamIntegrity.swift
// J2KSwift
//
// Integrity accounting for the entropy-coded segment of a codestream.
//
// ## Why this exists
//
// The MQ arithmetic decoder of ISO/IEC 15444-1 Annex C cannot fail. It is a
// total function: every bit pattern decodes to *some* symbol sequence, and
// once its segment is exhausted `BYTEIN` feeds `0xFF` indefinitely by
// definition. That is correct, specified behaviour — and it means a corrupted
// entropy payload produces a plausible-looking image with no error anywhere.
//
// Before this type existed the decoder validated nothing past the `SOD`
// marker. A 16-byte corruption swept across the entropy payload of a test
// codestream was accepted silently at every one of 496 positions, and *not
// one* of those decodes returned correct samples; the worst returned a
// completely garbage image (maximum absolute error 63302 on a 65535 scale).
// A single flipped bit produced wrong samples 626 times out of 629.
//
// ## What is measured
//
// The packet header states how many bytes belong to each code-block. A
// synchronised decoder consumes that segment; a desynchronised one stops
// early, leaving a tail untouched. That shortfall is the signal — it needs no
// cooperation from the encoder and costs one comparison per code-block.
//
// ## What is *not* corruption
//
// Three legal situations look superficially like damage, and conflating them
// with corruption would reject valid files:
//
// - **Over-reading is normal.** Annex C defines the past-the-end `0xFF` feed,
//   and a healthy block runs a few bytes into it on the flush tail.
// - **Truncation is legal and intentional.** JPEG 2000 is designed to be cut
//   at a packet boundary and still decode; that is what the progression
//   orders are *for*. A deliberately truncated stream, a quality-layer-limited
//   decode and a JPIP prefix all legitimately leave data unconsumed.
// - **Encoders differ.** How much of a terminated segment a decoder consumes
//   depends on the encoder's flush strategy, and T.800 permits dropping
//   trailing `0xFF` bytes. Thresholds here are calibrated against real output
//   from four independent encoders rather than against this library's own.
//
// See ``J2KIntegrityThresholds`` for the calibration and its provenance.
//

import Foundation

// MARK: - Validation policy

/// How the decoder reacts to a codestream whose entropy data fails its
/// integrity checks.
public enum J2KValidationMode: String, Sendable, Codable, CaseIterable {
    /// Reject a codestream whose entropy data shows signs of corruption.
    ///
    /// This is the default. A caller that does nothing gets an error rather
    /// than a plausible-looking wrong image, which for diagnostic imaging is
    /// the only defensible default.
    case strict

    /// Decode regardless, and report what was found.
    ///
    /// The integrity report is still computed — ``J2KDecodeResult/integrity``
    /// carries it — so a caller can apply its own policy. Use this for
    /// best-effort recovery of known-damaged data, or where a deliberately
    /// truncated stream is expected and the caller does not want to describe
    /// the truncation up front.
    case lenient
}

// MARK: - Calibrated thresholds

/// The thresholds separating "damaged" from "unusual but legal".
///
/// These are measured, not chosen. See `Documentation/INTEGRITY_CALIBRATION.md`
/// for the corpus, the distributions and the reproduction command.
public enum J2KIntegrityThresholds {
    /// Unconsumed bytes in a single code-block segment that are attributed to
    /// normal encoder flush behaviour rather than to damage.
    ///
    /// Calibrated against the clean-stream distribution across four
    /// independent encoders; see the calibration document for the measured
    /// per-encoder maxima.
    public static let benignBlockUnderRead: Int = calibratedBenignBlockUnderRead

    /// Over-read beyond which a block is treated as desynchronised.
    ///
    /// Small over-reads are the specified flush tail and carry no signal.
    public static let benignBlockOverRead: Int = calibratedBenignBlockOverRead

}

// MARK: - Anomalies

/// A single integrity finding.
public enum J2KIntegrityAnomaly: Sendable, Equatable, CustomStringConvertible {
    /// A code-block left more of its declared segment unread than any clean
    /// encoder output does.
    case codeBlockUnderRead(block: Int, declared: Int, consumed: Int)

    /// A code-block ran far past the end of its segment, which means the
    /// arithmetic decoder lost synchronisation and was decoding the
    /// past-the-end `0xFF` feed as if it were data.
    case codeBlockOverRead(block: Int, declared: Int, overRead: Int)

    /// The codestream never presented an `EOC` marker.
    ///
    /// ISO/IEC 15444-1 requires every codestream to end with `EOC`
    /// (`0xFFD9`). Without this check a transfer cut at the `EOC` boundary
    /// is indistinguishable from a complete file — it decodes bit-exactly
    /// and reports nothing.
    case missingEndOfCodestream

    public var description: String {
        switch self {
        case .missingEndOfCodestream:
            return "codestream has no EOC marker, so it may be truncated"
        case .codeBlockUnderRead(let block, let declared, let consumed):
            return "code-block \(block) consumed \(consumed) of \(declared) declared bytes "
                + "(\(declared - consumed) unread)"
        case .codeBlockOverRead(let block, let declared, let overRead):
            return "code-block \(block) read \(overRead) bytes past the end of its "
                + "\(declared)-byte segment"
        }
    }
}

// MARK: - Aggregated report

/// What the decoder observed about the integrity of a codestream's entropy data.
///
/// Always computed, in both validation modes. In ``J2KValidationMode/strict``
/// a report that is not ``isIntact`` becomes a thrown error; in
/// ``J2KValidationMode/lenient`` it is returned alongside the image.
public struct J2KCodestreamIntegrity: Sendable, Equatable {
    /// Code-blocks the decoder processed.
    public let codeBlocksDecoded: Int

    /// Blocks whose unread tail exceeded ``J2KIntegrityThresholds/benignBlockUnderRead``.
    public let blocksUnderRead: Int

    /// The largest unread tail on any single block, in bytes.
    public let maxBlockUnderRead: Int

    /// Total unread bytes across every code-block.
    public let totalUnderReadBytes: Int

    /// Whether the codestream ended without an `EOC` marker.
    public let missingEndOfCodestream: Bool

    /// Blocks that ran past the end of their segment by more than
    /// ``J2KIntegrityThresholds/benignBlockOverRead``.
    public let blocksOverRead: Int

    /// The largest over-read on any single block, in bytes.
    ///
    /// Reported unconditionally, including below the threshold, because the
    /// benign flush tail is exactly what calibrates that threshold.
    public let maxBlockOverRead: Int

    /// Whether the caller asked for a partial decode.
    ///
    /// A quality-layer-limited or resolution-limited decode leaves data
    /// unconsumed by design, so the under-read signal carries no information
    /// and is not reported as an anomaly.
    public let isPartialDecode: Bool

    /// Everything that looked wrong, in the order it was found.
    public let anomalies: [J2KIntegrityAnomaly]

    /// Whether the entropy data showed no sign of damage.
    public var isIntact: Bool { anomalies.isEmpty }

    /// A one-line summary suitable for a log line or an error message.
    public var summary: String {
        guard !isIntact else {
            return "intact: \(codeBlocksDecoded) code-blocks, all segments consumed"
        }
        var parts: [String] = []
        if blocksUnderRead > 0 {
            parts.append("\(blocksUnderRead)/\(codeBlocksDecoded) code-blocks left data unread "
                + "(largest \(maxBlockUnderRead) bytes, \(totalUnderReadBytes) total)")
        }
        if blocksOverRead > 0 {
            parts.append("\(blocksOverRead) code-blocks read past their segment")
        }
        if missingEndOfCodestream {
            parts.append("no EOC marker")
        }
        return parts.joined(separator: "; ")
    }

    /// An intact report, for paths that perform no entropy decoding.
    public static let intact = J2KCodestreamIntegrity(
        codeBlocksDecoded: 0,
        blocksUnderRead: 0, maxBlockUnderRead: 0, totalUnderReadBytes: 0,
        blocksOverRead: 0, maxBlockOverRead: 0, missingEndOfCodestream: false,
        isPartialDecode: false,
        anomalies: []
    )

    public init(
        codeBlocksDecoded: Int,
        blocksUnderRead: Int,
        maxBlockUnderRead: Int,
        totalUnderReadBytes: Int,
        blocksOverRead: Int,
        maxBlockOverRead: Int,
        missingEndOfCodestream: Bool,
        isPartialDecode: Bool,
        anomalies: [J2KIntegrityAnomaly]
    ) {
        self.codeBlocksDecoded = codeBlocksDecoded
        self.blocksUnderRead = blocksUnderRead
        self.maxBlockUnderRead = maxBlockUnderRead
        self.totalUnderReadBytes = totalUnderReadBytes
        self.blocksOverRead = blocksOverRead
        self.maxBlockOverRead = maxBlockOverRead
        self.missingEndOfCodestream = missingEndOfCodestream
        self.isPartialDecode = isPartialDecode
        self.anomalies = anomalies
    }
}
