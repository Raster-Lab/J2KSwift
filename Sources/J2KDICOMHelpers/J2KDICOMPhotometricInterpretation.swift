// J2KDICOMPhotometricInterpretation.swift
//
// v10.17.0 — J2KDICOMHelpers Phase 1
//
// Public enum mirror of the DICOM `(0028,0004) PhotometricInterpretation`
// element values that are relevant to JPEG 2000 / HTJ2K-encoded pixel
// data. Provides a mapping to/from `J2KCore.J2KColorSpace`.
//
// ADR-004 compliant: no DICOM library dependency. The string raw values
// are the DICOM-defined constants (PS3.3 §C.7.6.3.1.2).

import Foundation
import J2KCore

/// DICOM Photometric Interpretation values relevant to JPEG 2000 /
/// HTJ2K-encoded pixel data.
///
/// The raw values are the canonical DICOM-defined string constants per
/// DICOM PS3.3 §C.7.6.3.1.2.
public enum J2KDICOMPhotometricInterpretation: String, Sendable, Equatable, Hashable, CaseIterable {

    /// Single-component greyscale where 0 is white (less common).
    case monochrome1 = "MONOCHROME1"

    /// Single-component greyscale where 0 is black (the medical-imaging norm).
    case monochrome2 = "MONOCHROME2"

    /// Three-component RGB (sRGB by convention).
    case rgb = "RGB"

    /// Three-component YCbCr in full-range encoding (BT.601 / BT.709 colour
    /// primaries; encoded values span 0–255 / 0–4095, no head/foot room).
    case yBrFull = "YBR_FULL"

    /// Three-component YCbCr with 2x1 horizontal chroma subsampling
    /// (4:2:2 layout). Common in JPEG-derived pixel data.
    case yBrFull422 = "YBR_FULL_422"

    /// YCbCr derived via the JPEG 2000 Reversible Colour Transform (RCT).
    /// Pairs with `J2KEncodingConfiguration(lossless: true)` (5/3 +
    /// reversible RCT).
    case yBrRct = "YBR_RCT"

    /// YCbCr derived via the JPEG 2000 Irreversible Colour Transform (ICT).
    /// Pairs with `J2KEncodingConfiguration(lossless: false)` (9/7 +
    /// irreversible ICT).
    case yBrIct = "YBR_ICT"

    // MARK: - J2KColorSpace bridge

    /// Returns the corresponding `J2KColorSpace`.
    ///
    /// MONOCHROME1 and MONOCHROME2 both map to `.grayscale`; the inversion
    /// semantics of MONOCHROME1 are a display-time concern, not a
    /// colour-space distinction at the codec layer.
    ///
    /// RGB maps to `.sRGB`. All YCbCr variants (full-range, 4:2:2, RCT,
    /// ICT) map to `.yCbCr`; the encode-time codec-transform choice
    /// (`useReversibleFilter`) is what distinguishes RCT from ICT, not
    /// the colour-space enum value.
    public var colorSpace: J2KColorSpace {
        switch self {
        case .monochrome1, .monochrome2:
            return .grayscale
        case .rgb:
            return .sRGB
        case .yBrFull, .yBrFull422, .yBrRct, .yBrIct:
            return .yCbCr
        }
    }

    /// Reverse mapping from `J2KColorSpace`. Returns `nil` for
    /// colour-space values that don't have an unambiguous DICOM
    /// counterpart (`.hdr`, `.hdrLinear`, `.iccProfile(_)`, `.unknown`).
    ///
    /// For `.grayscale` returns `.monochrome2` (the medical norm).
    /// For `.yCbCr` returns `.yBrFull` (the most general DICOM YCbCr
    /// variant; callers needing the lossless-RCT or lossy-ICT distinction
    /// should construct the enum directly).
    public init?(colorSpace: J2KColorSpace) {
        switch colorSpace {
        case .grayscale: self = .monochrome2
        case .sRGB:      self = .rgb
        case .yCbCr:     self = .yBrFull
        case .hdr, .hdrLinear, .iccProfile, .unknown:
            return nil
        }
    }
}
