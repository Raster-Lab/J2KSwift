// J2KDICOMFileWithPixelData.swift
//
// v10.24.0 — J2KDICOMHelpers Phase 3.1 (uncompressed pixel extraction).
//
// Sibling type to v10.21.0's ``J2KDICOMFile``. The shape difference:
// `.uncompressed` here ALSO carries `pixelDataBytes`, where v10.21's
// `.uncompressed` carried only metadata.
//
// Returned by the new ``J2KDICOMFileParser/parseExtractingPixelData(_:)``
// method (v10.24.0). The existing ``J2KDICOMFileParser/parse(_:)``
// continues to return ``J2KDICOMFile`` unchanged — consumers pick
// whichever shape they need.

import Foundation

/// Result of parsing a DICOM file with
/// ``J2KDICOMFileParser/parseExtractingPixelData(_:)`` (v10.24.0).
///
/// Both cases carry `pixelDataBytes`:
/// - For `.j2kCompressed`, the bytes are the complete Pixel Data Item
///   sequence (BOT + per-frame Items + Sequence Delimitation Item per
///   PS3.5 §A.4); pass to
///   ``J2KDICOMPixelDataDecapsulator/extractFrames(_:)`` to split into
///   per-frame J2K codestreams.
/// - For `.uncompressed`, the bytes are the raw pixel data
///   (`rows × columns × samplesPerPixel × bytesPerSample × numberOfFrames`)
///   in source byte order — consumers' DICOM library / image-construction
///   handles layout (planar configuration, mosaic frames, etc.) and any
///   endianness conversion needed for their target use.
public enum J2KDICOMFileWithPixelData: Sendable, Equatable {

    /// DICOM file's Transfer Syntax UID is a JPEG 2000 / HTJ2K variant.
    /// Same semantics as ``J2KDICOMFile/j2kCompressed(metadata:pixelDataBytes:)``.
    case j2kCompressed(metadata: J2KDICOMFileMetadata, pixelDataBytes: Data)

    /// DICOM file's Transfer Syntax UID is not a JPEG 2000 / HTJ2K
    /// variant (uncompressed Explicit/Implicit VR or a non-J2K compressed
    /// format). `pixelDataBytes` is the raw `(7FE0,0010)` Pixel Data
    /// element's value bytes — for uncompressed UIDs that's the
    /// concatenated frame bytes in source byte order; for compressed
    /// non-J2K UIDs (which are rare in J2KSwift's typical use) it's the
    /// encapsulated sequence which would need format-specific
    /// decapsulation.
    case uncompressed(metadata: J2KDICOMFileMetadata, pixelDataBytes: Data)

    /// Convenience: returns the metadata regardless of variant.
    public var metadata: J2KDICOMFileMetadata {
        switch self {
        case .j2kCompressed(let m, _): return m
        case .uncompressed(let m, _):  return m
        }
    }

    /// Convenience: returns the pixel data bytes regardless of variant.
    public var pixelDataBytes: Data {
        switch self {
        case .j2kCompressed(_, let b): return b
        case .uncompressed(_, let b):  return b
        }
    }

    /// Convenience: `true` if this is a JPEG 2000 / HTJ2K variant.
    public var isJ2KCompressed: Bool {
        if case .j2kCompressed = self { return true }
        return false
    }
}
