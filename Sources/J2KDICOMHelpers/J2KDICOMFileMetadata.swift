// J2KDICOMFileMetadata.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Value type capturing the DICOM Image Pixel Module metadata
// (PS3.3 §C.7.6.3.1) extracted by `J2KDICOMFileParser.parse(_:)`.

import Foundation

/// Image-pixel-module metadata extracted from a DICOM file.
///
/// Values mirror the DICOM `(0028,XXXX)` tag group per PS3.3 §C.7.6.3.1.
/// Field names match the DICOM Standard's English keywords (e.g.,
/// `rows` for `Rows (0028,0010)`, `columns` for `Columns (0028,0011)`).
///
/// Optional / missing tags are normalised to sensible defaults:
/// - `bitsStored == 0` means the tag was absent; treat as
///   `bitsAllocated` for downstream interpretation.
/// - `numberOfFrames` defaults to `1` (single-frame image) when the
///   tag is absent (per DICOM `Number of Frames (0028,0008)` semantics).
/// - `planarConfiguration` defaults to `0` (interleaved) when absent
///   (`samplesPerPixel == 1` makes the tag irrelevant anyway).
public struct J2KDICOMFileMetadata: Sendable, Equatable, Hashable {

    /// DICOM `(0002,0010) Transfer Syntax UID` — the wire-format
    /// identifier (e.g., `"1.2.840.10008.1.2.4.201"` for HTJ2K Lossless).
    public let transferSyntaxUID: String

    /// DICOM `(0028,0010) Rows` — image height in pixels.
    public let rows: Int

    /// DICOM `(0028,0011) Columns` — image width in pixels.
    public let columns: Int

    /// DICOM `(0028,0100) Bits Allocated` — bits per sample slot (8, 16, etc.).
    public let bitsAllocated: Int

    /// DICOM `(0028,0101) Bits Stored` — significant bits per sample.
    /// `0` indicates the tag was absent in the source; treat as
    /// `bitsAllocated`.
    public let bitsStored: Int

    /// DICOM `(0028,0103) Pixel Representation` — `0` = unsigned,
    /// `1` = two's-complement signed.
    public let pixelRepresentation: Int

    /// DICOM `(0028,0002) Samples per Pixel` — `1` for grayscale,
    /// `3` for RGB / YCbCr, etc.
    public let samplesPerPixel: Int

    /// DICOM `(0028,0004) Photometric Interpretation` — raw string
    /// (e.g., `"MONOCHROME2"`, `"RGB"`, `"YBR_RCT"`). Use
    /// `J2KDICOMPhotometricInterpretation(rawValue:)` (v10.17.0) to
    /// classify into the enum mirror.
    public let photometricInterpretation: String

    /// DICOM `(0028,0008) Number of Frames` — `1` for single-frame.
    public let numberOfFrames: Int

    /// DICOM `(0028,0006) Planar Configuration` — `0` = interleaved
    /// (component-major within each pixel), `1` = planar (component
    /// arrays separated). Only meaningful when `samplesPerPixel > 1`.
    public let planarConfiguration: Int

    /// Designated initializer. Public so callers can construct test
    /// fixtures or expected-value records.
    public init(
        transferSyntaxUID: String,
        rows: Int,
        columns: Int,
        bitsAllocated: Int,
        bitsStored: Int,
        pixelRepresentation: Int,
        samplesPerPixel: Int,
        photometricInterpretation: String,
        numberOfFrames: Int,
        planarConfiguration: Int
    ) {
        self.transferSyntaxUID = transferSyntaxUID
        self.rows = rows
        self.columns = columns
        self.bitsAllocated = bitsAllocated
        self.bitsStored = bitsStored
        self.pixelRepresentation = pixelRepresentation
        self.samplesPerPixel = samplesPerPixel
        self.photometricInterpretation = photometricInterpretation
        self.numberOfFrames = numberOfFrames
        self.planarConfiguration = planarConfiguration
    }

    /// Convenience: returns `bitsStored` when nonzero, else `bitsAllocated`.
    public var effectiveBitsStored: Int {
        bitsStored == 0 ? bitsAllocated : bitsStored
    }

    /// Convenience: byte count required to store one sample (rounded up).
    public var bytesPerSample: Int {
        max(1, (bitsAllocated + 7) / 8)
    }

    /// Convenience: byte count of one frame's uncompressed pixel data.
    /// `columns × rows × samplesPerPixel × bytesPerSample`.
    public var frameSizeInBytes: Int {
        columns * rows * samplesPerPixel * bytesPerSample
    }
}
