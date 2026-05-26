// J2KDICOMTransferSyntax.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1
//
// Public enum mirroring the DICOM Transfer Syntax UIDs that designate
// JPEG 2000 (Part 1) and HTJ2K (Part 15) codestreams as the pixel-data
// encoding. Consumers parsing DICOM files with their own DICOM library
// (DICOMKit, pydicom via XPC, etc.) get a Transfer Syntax UID + Pixel
// Data bytes, and can then bridge to J2KSwift via this enum's
// `encodingConfiguration()` helper (defined in the companion extension).
//
// ADR-004 compliant: no DICOM library dependency anywhere in J2KSwift.
// This module depends only on J2KCore + J2KCodec. Consumers who don't
// need DICOM ergonomics simply don't import J2KDICOMHelpers.

import Foundation

/// DICOM Transfer Syntax UIDs that designate JPEG 2000 / HTJ2K codestreams.
///
/// These are the seven UIDs currently registered with DICOM Standard
/// Part 5 (Annex A) under the JPEG 2000 family. Lossy variants are
/// included for completeness, but note that J2KSwift's primary product
/// target (per [feedback_lossless_only_v5_38]) is exact-reconstruction
/// medical archive — lossy support exists but isn't an active
/// development focus.
///
/// ## Usage
///
/// ```swift
/// import J2KDICOMHelpers
///
/// // From a UID string (typical: read by a DICOM parser)
/// guard let ts = J2KDICOMTransferSyntax(uid: "1.2.840.10008.1.2.4.201") else {
///     // Not a recognised JPEG 2000 / HTJ2K UID
///     return
/// }
/// assert(ts == .htj2kLossless)
///
/// // Round-trip the UID
/// assert(ts.uid == "1.2.840.10008.1.2.4.201")
///
/// // Classify
/// if ts.isHTJ2K && ts.isLossless { ... }
///
/// // Build a matching J2KEncodingConfiguration (see companion extension)
/// let cfg = ts.encodingConfiguration(bitDepth: 16)
/// ```
public enum J2KDICOMTransferSyntax: Sendable, Equatable, Hashable, CaseIterable {

    /// JPEG 2000 Image Compression (Lossless Only) — Part 1, reversible 5/3 DWT.
    ///
    /// DICOM UID: `1.2.840.10008.1.2.4.90`
    case j2kLossless

    /// JPEG 2000 Image Compression — Part 1, lossy 9/7 DWT (also covers lossless).
    ///
    /// DICOM UID: `1.2.840.10008.1.2.4.91`
    case j2kLossy

    /// JPEG 2000 Part 2 Multi-component Image Compression (Lossless Only).
    ///
    /// DICOM UID: `1.2.840.10008.1.2.4.92`
    ///
    /// - Note: Retired in DICOM 2024c. Retained for backward compatibility
    ///   with archives produced under earlier DICOM editions.
    case j2kPart2MulticompLossless

    /// JPEG 2000 Part 2 Multi-component Image Compression (Lossless or Lossy).
    ///
    /// DICOM UID: `1.2.840.10008.1.2.4.93`
    ///
    /// - Note: Retired in DICOM 2024c. Retained for backward compatibility.
    case j2kPart2Multicomp

    /// High-Throughput JPEG 2000 (HTJ2K) Image Compression (Lossless Only) —
    /// Part 15, reversible 5/3 DWT.
    ///
    /// DICOM UID: `1.2.840.10008.1.2.4.201`
    case htj2kLossless

    /// High-Throughput JPEG 2000 (HTJ2K) Image Compression with Reversible
    /// Codestream Containment Wavelet (RPCL) — Part 15, with rate-controlled
    /// constant-bitrate output.
    ///
    /// DICOM UID: `1.2.840.10008.1.2.4.202`
    case htj2kLossyConstant

    /// High-Throughput JPEG 2000 (HTJ2K) Image Compression — Part 15,
    /// lossy 9/7 DWT.
    ///
    /// DICOM UID: `1.2.840.10008.1.2.4.203`
    case htj2kLossy

    // MARK: - UID Round-trip

    /// Returns the canonical DICOM Transfer Syntax UID string.
    public var uid: String {
        switch self {
        case .j2kLossless:               return "1.2.840.10008.1.2.4.90"
        case .j2kLossy:                  return "1.2.840.10008.1.2.4.91"
        case .j2kPart2MulticompLossless: return "1.2.840.10008.1.2.4.92"
        case .j2kPart2Multicomp:         return "1.2.840.10008.1.2.4.93"
        case .htj2kLossless:             return "1.2.840.10008.1.2.4.201"
        case .htj2kLossyConstant:        return "1.2.840.10008.1.2.4.202"
        case .htj2kLossy:                return "1.2.840.10008.1.2.4.203"
        }
    }

    /// Creates a `J2KDICOMTransferSyntax` from a DICOM UID string.
    ///
    /// Returns `nil` when the UID isn't one of the seven JPEG 2000 / HTJ2K
    /// UIDs registered in DICOM Part 5 Annex A.
    ///
    /// The lookup is whitespace- and trailing-null-tolerant — DICOM Value
    /// Representations of UID type may be padded with a trailing NUL byte
    /// to maintain even length per PS3.5 §6.2.
    public init?(uid: String) {
        let trimmed = uid.trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        switch trimmed {
        case "1.2.840.10008.1.2.4.90":  self = .j2kLossless
        case "1.2.840.10008.1.2.4.91":  self = .j2kLossy
        case "1.2.840.10008.1.2.4.92":  self = .j2kPart2MulticompLossless
        case "1.2.840.10008.1.2.4.93":  self = .j2kPart2Multicomp
        case "1.2.840.10008.1.2.4.201": self = .htj2kLossless
        case "1.2.840.10008.1.2.4.202": self = .htj2kLossyConstant
        case "1.2.840.10008.1.2.4.203": self = .htj2kLossy
        default: return nil
        }
    }

    // MARK: - Classification

    /// `true` when this Transfer Syntax produces a bit-exact reversible
    /// codestream (5/3 wavelet + reversible colour transform).
    public var isLossless: Bool {
        switch self {
        case .j2kLossless,
             .j2kPart2MulticompLossless,
             .htj2kLossless:
            return true
        case .j2kLossy,
             .j2kPart2Multicomp,
             .htj2kLossyConstant,
             .htj2kLossy:
            return false
        }
    }

    /// `true` when this Transfer Syntax uses HTJ2K (Part 15) block coding
    /// rather than the legacy EBCOT entropy coder of Part 1.
    public var isHTJ2K: Bool {
        switch self {
        case .htj2kLossless,
             .htj2kLossyConstant,
             .htj2kLossy:
            return true
        case .j2kLossless,
             .j2kLossy,
             .j2kPart2MulticompLossless,
             .j2kPart2Multicomp:
            return false
        }
    }

    /// `true` when the Transfer Syntax is a JPEG 2000 Part 2 multi-component
    /// extension (now retired from DICOM 2024c, but archives may still
    /// reference these UIDs).
    public var isPart2: Bool {
        switch self {
        case .j2kPart2MulticompLossless, .j2kPart2Multicomp:
            return true
        default:
            return false
        }
    }
}
