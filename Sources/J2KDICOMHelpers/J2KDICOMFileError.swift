// J2KDICOMFileError.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Typed errors emitted by `J2KDICOMFileParser.parse(_:)`.

import Foundation

/// Errors thrown by ``J2KDICOMFileParser/parse(_:)``.
public enum J2KDICOMFileError: Error, Sendable, Equatable {

    /// Input is too small to contain even the 128-byte preamble + 4-byte
    /// DICM magic (minimum DICOM file size = 132 bytes).
    case invalidPreamble(size: Int)

    /// Preamble is large enough but bytes `[128..132)` are not the ASCII
    /// string `"DICM"`. Note: legacy DICOM files (pre-DICOM 3.0) may omit
    /// the preamble and start directly with group `0002` — those are
    /// NOT supported by this parser; consumers can hand-strip a custom
    /// header before calling.
    case missingDICMMagic(actual: String)

    /// Scanned the entire dataset but never found the Pixel Data tag
    /// `(7FE0,0010)`. Files without pixel data (e.g., DICOMDIR, SR
    /// reports) hit this — they're valid DICOM but have no image content
    /// for J2KSwift to operate on.
    case missingPixelDataTag

    /// Input bytes ended before a declared element/sequence boundary.
    case truncatedFile(expectedAtLeast: Int, got: Int)

    /// Transfer Syntax UID string is empty or fails ASCII decode.
    case invalidTransferSyntax(uid: String)

    /// An undefined-length sequence could not be skipped (malformed
    /// item delimitation, hit end-of-file before delimiter, etc.).
    case sequenceParsingFailed(offset: Int, reason: String)
}
