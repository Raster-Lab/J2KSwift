// J2KDICOMFile.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Public discriminated-union result type returned by
// `J2KDICOMFileParser.parse(_:)`.

import Foundation

/// Result of parsing a DICOM file with `J2KDICOMFileParser.parse(_:)`.
///
/// The parser branches on the file's Transfer Syntax UID:
///
/// - `.j2kCompressed` — the UID is one of the seven DICOM Part 5
///   Annex A JPEG 2000 / HTJ2K variants. The full Pixel Data Item
///   sequence (BOT + per-frame Items + Sequence Delimitation Item per
///   PS3.5 §A.4) is captured in `pixelDataBytes`. Use
///   ``J2KDICOMPixelDataDecapsulator/extractFrames(_:)`` (v10.19.0) to
///   split into per-frame J2K codestreams, then ``J2KDecoder/decode(_:)``
///   to decode each.
///
/// - `.uncompressed` — the UID indicates a non-JPEG 2000 transfer
///   syntax (uncompressed or a non-J2K compressed format like JPEG /
///   RLE / etc.). Only metadata is returned; consumers wanting pixel
///   data should use their own DICOM library (pydicom, DICOMKit,
///   dcm4che, etc.).
public enum J2KDICOMFile: Sendable, Equatable {

    /// DICOM file's Transfer Syntax UID is a JPEG 2000 / HTJ2K variant.
    ///
    /// - `metadata`: Image Pixel Module attributes (rows, columns,
    ///   bits, photometric interpretation, etc.).
    /// - `pixelDataBytes`: The complete Pixel Data Item sequence
    ///   starting at the first byte after the `(7FE0,0010)` element's
    ///   header and ending at (or after) the Sequence Delimitation Item.
    ///   Hand off to ``J2KDICOMPixelDataDecapsulator/extractFrames(_:)``
    ///   for per-frame J2K codestreams.
    case j2kCompressed(metadata: J2KDICOMFileMetadata, pixelDataBytes: Data)

    /// DICOM file's Transfer Syntax UID is not a JPEG 2000 / HTJ2K variant.
    ///
    /// Only metadata is returned. Consumers wanting to read pixel data
    /// should use their own DICOM library.
    case uncompressed(metadata: J2KDICOMFileMetadata)

    /// Convenience accessor — returns the metadata regardless of variant.
    public var metadata: J2KDICOMFileMetadata {
        switch self {
        case .j2kCompressed(let m, _): return m
        case .uncompressed(let m):     return m
        }
    }

    /// Convenience: `true` if the file is one of the JPEG 2000 variants.
    public var isJ2KCompressed: Bool {
        if case .j2kCompressed = self { return true }
        return false
    }
}
