// J2KDICOMCodestreamDetector.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1
//
// Sniffs the leading marker bytes of a JPEG 2000 codestream to classify
// it into one of the DICOM Transfer Syntax categories. Detects:
//
//   - SOC marker (0xFF 0x4F) — required first two bytes of any J2K codestream
//   - CAP marker (0xFF 0x50) — Extended Capabilities marker; presence implies
//     Part 15 (HTJ2K). Absent in Part 1 codestreams.
//   - SIZ marker (0xFF 0x51) — image-size marker; required, immediately
//     following SOC. Used here to skip past the SIZ segment so the scanner
//     can find CAP downstream.
//
// Lossless vs lossy detection looks inside the COD marker (progression /
// quantisation hints) but those aren't deterministically present at sniff
// time (the COD's `qmfbid` field disambiguates 5/3 from 9/7), so the
// detector returns the LOSSLESS variant when CAP is present (HTJ2K) and
// the LOSSLESS Part-1 variant when CAP is absent. Callers needing the
// exact lossy/lossless distinction should inspect the source's DICOM
// Transfer Syntax UID directly (the codestream alone is ambiguous in
// the lossless 5/3 case — a 5/3 codestream is bit-exact lossless but
// can also be a degenerate output of the lossy-tagged UID).

import Foundation
import J2KCore

/// Inspects a JPEG 2000 codestream to identify the most likely matching
/// DICOM Transfer Syntax.
public enum J2KDICOMCodestreamDetector {

    /// Scans `codestream` for SOC + (optional) CAP markers and returns
    /// the matching DICOM Transfer Syntax category.
    ///
    /// Returns `nil` when the bytes don't begin with the SOC marker
    /// (`0xFF 0x4F`), i.e., the input isn't a raw J2K codestream at all.
    ///
    /// **Important — sniff ambiguity**: a 5/3 (lossless) codestream can be
    /// the output of either a Part 1 lossless-only UID
    /// (`1.2.840.10008.1.2.4.90`) or a Part 1 lossy UID
    /// (`1.2.840.10008.1.2.4.91`) used in its lossless mode. Without the
    /// original DICOM dataset's Transfer Syntax UID, the codestream alone
    /// can't distinguish these — the detector reports the LOSSLESS
    /// variant (`.j2kLossless` / `.htj2kLossless`) as the canonical
    /// guess. Callers who have the source UID should prefer
    /// `J2KDICOMTransferSyntax(uid:)` over sniffing.
    ///
    /// - Parameter codestream: Raw bytes of a J2K codestream (post-`jp2c` /
    ///                          stripped of any container box framing).
    /// - Returns: The detected Transfer Syntax, or `nil` if the bytes
    ///            don't look like a J2K codestream.
    public static func detect(_ codestream: Data) -> J2KDICOMTransferSyntax? {
        // 1. Verify SOC marker.
        guard codestream.count >= 4 else { return nil }
        guard readMarker(codestream, at: 0) == J2KMarker.soc.rawValue else {
            return nil
        }

        // 2. Skip past SIZ (which immediately follows SOC) and check whether
        //    the next marker is CAP (HTJ2K) or something else (Part 1).
        //    SIZ has a 2-byte length field at offset 4 (after marker).
        guard codestream.count >= 6 else {
            // SOC present but truncated — caller has a malformed codestream.
            // Conservative classification: assume legacy Part 1 lossless.
            return .j2kLossless
        }

        // SOC at [0..2], SIZ marker at [2..4], SIZ length at [4..6].
        guard readMarker(codestream, at: 2) == J2KMarker.siz.rawValue else {
            // Atypical layout (e.g., COM marker before SIZ); fall back to
            // a forward scan in the first 256 bytes.
            return scanForCAP(in: codestream, upTo: min(256, codestream.count))
                ? .htj2kLossless
                : .j2kLossless
        }
        let sizLength = readU16BE(codestream, at: 4)
        // SIZ marker (2) + length field (2) + payload (sizLength - 2)
        // The `length` field reports the bytes from itself to the end of
        // the segment payload, inclusive of itself, so the next marker
        // starts at offset `2 + 2 + (sizLength)` = `4 + sizLength`.
        let postSIZ = 4 + Int(sizLength)
        guard postSIZ + 2 <= codestream.count else { return .j2kLossless }

        // 3. The marker immediately after SIZ is typically CAP (HTJ2K) or
        //    COD/COM/etc. (Part 1).
        if readMarker(codestream, at: postSIZ) == J2KMarker.cap.rawValue {
            return .htj2kLossless
        }
        // Some HTJ2K encoders emit COM (private) before CAP — do a brief
        // forward scan within the first 256 bytes to confirm.
        if scanForCAP(in: codestream, upTo: min(256, codestream.count)) {
            return .htj2kLossless
        }
        return .j2kLossless
    }

    // MARK: - Private helpers

    private static func readMarker(_ data: Data, at offset: Int) -> UInt16 {
        return readU16BE(data, at: offset)
    }

    private static func readU16BE(_ data: Data, at offset: Int) -> UInt16 {
        precondition(offset + 2 <= data.count)
        let hi = UInt16(data[data.startIndex + offset])
        let lo = UInt16(data[data.startIndex + offset + 1])
        return (hi << 8) | lo
    }

    /// Forward-scan for the CAP marker (0xFF 0x50) in the first `limit`
    /// bytes of `data`. Returns `true` if found. Bounded scan keeps the
    /// sniff cheap — the CAP marker, when present, is always among the
    /// first handful of markers in the main header.
    private static func scanForCAP(in data: Data, upTo limit: Int) -> Bool {
        let end = min(limit, data.count)
        guard end >= 2 else { return false }
        // Walk byte-by-byte looking for the marker pair. Most J2K
        // markers are unique in the prefix so this is overwhelmingly
        // accurate within the bounded window.
        for i in 0..<(end - 1) {
            let m = readU16BE(data, at: i)
            if m == J2KMarker.cap.rawValue { return true }
        }
        return false
    }
}
