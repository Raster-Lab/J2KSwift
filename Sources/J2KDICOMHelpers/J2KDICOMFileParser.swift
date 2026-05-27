// J2KDICOMFileParser.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Lifts the J2K-relevant subset of `Sources/J2KCLI/DICOMSupport.swift`
// (CLI-private, since v8) into the helpers product. Returns enough
// metadata + encapsulated pixel data for the J2K-tagged case for a
// downstream J2KSwift decode to proceed.
//
// EXCLUDED from this Phase 3:
//   - Uncompressed pixel-data extraction (Phase 3.1 / v10.22 candidate)
//   - Compressed-non-J2K transfer syntaxes (CLI handles via Python
//     subprocess; not portable into the helpers product)
//   - DICOM file writing (separate Phase 4 arc)
//
// ADR-004 compliant: no DICOM library dependency — all parsing is
// byte-level from the DICOM Standard (PS3.5 + PS3.3).

import Foundation

/// Parses DICOM files to extract Transfer Syntax + image metadata +
/// (for J2K-tagged transfer syntaxes) the encapsulated Pixel Data
/// byte stream.
public enum J2KDICOMFileParser {

    /// Parses a DICOM file's raw bytes.
    ///
    /// On success returns a ``J2KDICOMFile`` carrying:
    /// - Image-pixel-module metadata (rows, columns, bits, photometric
    ///   interpretation, etc.) as ``J2KDICOMFileMetadata``;
    /// - For J2K-tagged transfer syntaxes (UIDs `1.2.840.10008.1.2.4.90/91/92/93`
    ///   and `1.2.840.10008.1.2.4.201/202/203`): the raw Pixel Data
    ///   Item sequence as `Data`. Hand off to
    ///   ``J2KDICOMPixelDataDecapsulator/extractFrames(_:)`` (v10.19.0)
    ///   to split into per-frame J2K codestreams.
    /// - For all other transfer syntaxes: metadata only.
    ///
    /// Throws ``J2KDICOMFileError`` on malformed input.
    ///
    /// - Parameter data: Complete `.dcm` file bytes including the
    ///   128-byte preamble and `"DICM"` magic. Legacy DICOM files
    ///   that omit the preamble are not supported here.
    /// - Returns: A ``J2KDICOMFile`` describing the parsed contents.
    public static func parse(_ data: Data) throws -> J2KDICOMFile {
        // 1. Preamble + DICM magic.
        try validatePreamble(data)

        // 2. Group 0002 (File Meta Information) — always Explicit VR LE.
        let (transferSyntaxUID, postGroup0002Offset) = try parseFileMetaInformation(data)

        // 3. Classify the Transfer Syntax. nil ⇒ unknown or non-J2K.
        let j2kTransferSyntax = J2KDICOMTransferSyntax(uid: transferSyntaxUID)
        let endianness = endiannessForUID(transferSyntaxUID)

        // 4. Walk the main dataset to extract image-pixel-module tags +
        //    locate the Pixel Data element.
        let (metadata, pixelDataOffset, pixelDataLength) = try parseDataset(
            data,
            startOffset: postGroup0002Offset,
            transferSyntaxUID: transferSyntaxUID,
            isExplicitVR: endianness.isExplicitVR,
            isBigEndian: endianness.isBigEndian)

        // 5. For non-J2K transfer syntaxes, return metadata only.
        guard j2kTransferSyntax != nil else {
            return .uncompressed(metadata: metadata)
        }

        // 6. For J2K-tagged transfer syntaxes, capture the Pixel Data
        //    byte stream. Per DICOM PS3.5 §A.4, encapsulated Pixel Data
        //    has length = 0xFFFF_FFFF (undefined); fixed-length pixel
        //    data with a J2K UID is non-standard but tolerable — we
        //    capture exactly the declared bytes either way.
        let pixelDataBytes: Data
        if pixelDataLength == 0xFFFF_FFFF {
            // Encapsulated: scan from pixelDataOffset to the Sequence
            // Delimitation Item (FFFE,E0DD) and include those 8 bytes
            // so the consumer can pass the whole thing to
            // J2KDICOMPixelDataDecapsulator.extractFrames(_:).
            let end = scanToSequenceEnd(
                data, from: pixelDataOffset, bigEndian: endianness.isBigEndian)
            let start = data.startIndex + pixelDataOffset
            let stop = data.startIndex + end
            guard stop <= data.endIndex else {
                throw J2KDICOMFileError.truncatedFile(
                    expectedAtLeast: end, got: data.count)
            }
            pixelDataBytes = data.subdata(in: start..<stop)
        } else {
            let start = data.startIndex + pixelDataOffset
            let stop = start + pixelDataLength
            guard stop <= data.endIndex else {
                throw J2KDICOMFileError.truncatedFile(
                    expectedAtLeast: pixelDataOffset + pixelDataLength,
                    got: data.count)
            }
            pixelDataBytes = data.subdata(in: start..<stop)
        }

        return .j2kCompressed(metadata: metadata, pixelDataBytes: pixelDataBytes)
    }

    // MARK: - Private helpers

    /// Minimum DICOM file size: 128-byte preamble + 4-byte DICM magic.
    private static let preambleAndMagicSize = 132

    private static func validatePreamble(_ data: Data) throws {
        guard data.count >= preambleAndMagicSize else {
            throw J2KDICOMFileError.invalidPreamble(size: data.count)
        }
        let start = data.startIndex
        let magicBytes = data.subdata(in: (start + 128)..<(start + 132))
        let magic = String(data: magicBytes, encoding: .ascii) ?? "?"
        guard magic == "DICM" else {
            throw J2KDICOMFileError.missingDICMMagic(actual: magic)
        }
    }

    /// Parses group 0002 (File Meta Information). Always Explicit VR LE
    /// per PS3.5 §7.1. Returns the extracted Transfer Syntax UID and
    /// the byte offset of the first byte AFTER group 0002.
    private static func parseFileMetaInformation(
        _ data: Data
    ) throws -> (transferSyntaxUID: String, postGroupOffset: Int) {

        var offset = 132  // first byte after preamble + DICM magic
        var transferSyntaxUID = ""

        while offset + 8 <= data.count {
            let group = J2KDICOMByteReader.readU16LE(data, offset: offset)
            let element = J2KDICOMByteReader.readU16LE(data, offset: offset + 2)

            // Group 0002 ends as soon as we see a non-0002 group.
            if group != 0x0002 { break }

            // Always Explicit VR LE in group 0002.
            let start = data.startIndex
            guard offset + 6 <= data.count else {
                throw J2KDICOMFileError.truncatedFile(
                    expectedAtLeast: offset + 6, got: data.count)
            }
            let vrBytes = data.subdata(in: (start + offset + 4)..<(start + offset + 6))
            let vr = String(data: vrBytes, encoding: .ascii) ?? ""
            let (valueLength, headerSize) = J2KDICOMByteReader.valueLength(
                data, offset: offset, vr: vr, bigEndian: false)
            let valueStart = offset + headerSize

            // Transfer Syntax UID element.
            if element == 0x0010 {
                if let uid = J2KDICOMByteReader.readString(
                    data, offset: valueStart, length: valueLength) {
                    transferSyntaxUID = uid
                }
            }

            offset = valueStart + valueLength
        }

        guard !transferSyntaxUID.isEmpty else {
            throw J2KDICOMFileError.invalidTransferSyntax(uid: transferSyntaxUID)
        }

        return (transferSyntaxUID, offset)
    }

    /// DICOM Transfer Syntax UIDs that select Big-Endian byte order.
    /// Per PS3.5 §10 only `1.2.840.10008.1.2.2` (Explicit VR BE) qualifies;
    /// `1.2.840.10008.1.2` (Implicit VR LE) is implicit + little-endian
    /// and every other UID is explicit + little-endian.
    private static func endiannessForUID(
        _ uid: String
    ) -> (isBigEndian: Bool, isExplicitVR: Bool) {
        switch uid {
        case "1.2.840.10008.1.2":
            // Implicit VR Little Endian (the default transfer syntax)
            return (isBigEndian: false, isExplicitVR: false)
        case "1.2.840.10008.1.2.2":
            // Explicit VR Big Endian (retired in DICOM 2024c but still
            // present in legacy archives)
            return (isBigEndian: true, isExplicitVR: true)
        default:
            // Everything else (including all J2K family UIDs) is
            // Explicit VR Little Endian for the dataset portion.
            return (isBigEndian: false, isExplicitVR: true)
        }
    }

    /// Walks the main dataset to extract Image Pixel Module attributes
    /// and locate the Pixel Data tag (7FE0,0010). Returns the populated
    /// metadata, the byte offset of the first byte AFTER Pixel Data's
    /// header (where its value bytes begin), and the declared value
    /// length (`0xFFFF_FFFF` for encapsulated).
    private static func parseDataset(
        _ data: Data,
        startOffset: Int,
        transferSyntaxUID: String,
        isExplicitVR: Bool,
        isBigEndian: Bool
    ) throws -> (J2KDICOMFileMetadata, pixelDataOffset: Int, pixelDataLength: Int) {

        var offset = startOffset
        var rows = 0
        var columns = 0
        var bitsAllocated = 16
        var bitsStored = 0
        var pixelRepresentation = 0
        var samplesPerPixel = 1
        var photometricInterpretation = ""
        var planarConfiguration = 0
        var numberOfFrames = 1
        var pixelDataOffset = -1
        var pixelDataLength = 0

        while offset + 4 <= data.count {
            let group = J2KDICOMByteReader.readU16(
                data, offset: offset, bigEndian: isBigEndian)
            let element = J2KDICOMByteReader.readU16(
                data, offset: offset + 2, bigEndian: isBigEndian)
            let tag = (group, element)

            // Pixel Data tag — stop here and report its byte position.
            if tag == (0x7FE0, 0x0010) {
                let (vl, hs) = J2KDICOMByteReader.datasetValueLength(
                    data, offset: offset, explicitVR: isExplicitVR, bigEndian: isBigEndian)
                pixelDataOffset = offset + hs
                pixelDataLength = vl
                break
            }

            // Read value-length for the current element.
            let (vl, hs) = J2KDICOMByteReader.datasetValueLength(
                data, offset: offset, explicitVR: isExplicitVR, bigEndian: isBigEndian)
            let valueStart = offset + hs

            // Undefined-length sequence — skip past its delimiter.
            if vl == 0xFFFF_FFFF {
                let postSequence = J2KDICOMByteReader.skipSequence(
                    data, from: valueStart, bigEndian: isBigEndian)
                guard postSequence > valueStart else {
                    throw J2KDICOMFileError.sequenceParsingFailed(
                        offset: offset,
                        reason: "skipSequence did not advance past undefined-length item")
                }
                offset = postSequence
                continue
            }

            switch tag {
            case (0x0028, 0x0002):
                samplesPerPixel = Int(J2KDICOMByteReader.readU16(
                    data, offset: valueStart, bigEndian: isBigEndian))
            case (0x0028, 0x0004):
                photometricInterpretation = J2KDICOMByteReader.readString(
                    data, offset: valueStart, length: vl) ?? ""
            case (0x0028, 0x0006):
                planarConfiguration = Int(J2KDICOMByteReader.readU16(
                    data, offset: valueStart, bigEndian: isBigEndian))
            case (0x0028, 0x0008):
                if let s = J2KDICOMByteReader.readString(
                    data, offset: valueStart, length: vl),
                   let n = Int(s.trimmingCharacters(in: .whitespaces)) {
                    numberOfFrames = n
                }
            case (0x0028, 0x0010):
                rows = Int(J2KDICOMByteReader.readU16(
                    data, offset: valueStart, bigEndian: isBigEndian))
            case (0x0028, 0x0011):
                columns = Int(J2KDICOMByteReader.readU16(
                    data, offset: valueStart, bigEndian: isBigEndian))
            case (0x0028, 0x0100):
                bitsAllocated = Int(J2KDICOMByteReader.readU16(
                    data, offset: valueStart, bigEndian: isBigEndian))
            case (0x0028, 0x0101):
                bitsStored = Int(J2KDICOMByteReader.readU16(
                    data, offset: valueStart, bigEndian: isBigEndian))
            case (0x0028, 0x0103):
                pixelRepresentation = Int(J2KDICOMByteReader.readU16(
                    data, offset: valueStart, bigEndian: isBigEndian))
            default:
                break
            }

            offset = valueStart + vl
        }

        guard pixelDataOffset >= 0 else {
            throw J2KDICOMFileError.missingPixelDataTag
        }

        let metadata = J2KDICOMFileMetadata(
            transferSyntaxUID: transferSyntaxUID,
            rows: rows,
            columns: columns,
            bitsAllocated: bitsAllocated,
            bitsStored: bitsStored,
            pixelRepresentation: pixelRepresentation,
            samplesPerPixel: samplesPerPixel,
            photometricInterpretation: photometricInterpretation,
            numberOfFrames: max(1, numberOfFrames),
            planarConfiguration: planarConfiguration)

        return (metadata, pixelDataOffset, pixelDataLength)
    }

    /// Scans from `start` until the Sequence Delimitation Item
    /// (FFFE,E0DD), returning the byte offset just past those 8 bytes.
    /// If the delimiter isn't found, returns `data.count` (caller
    /// captures the rest of the file as the Pixel Data byte stream;
    /// the decapsulator will report a clean error if the bytes are
    /// truncated).
    private static func scanToSequenceEnd(
        _ data: Data, from start: Int, bigEndian: Bool
    ) -> Int {
        var pos = start
        while pos + 8 <= data.count {
            let group = J2KDICOMByteReader.readU16(
                data, offset: pos, bigEndian: bigEndian)
            let element = J2KDICOMByteReader.readU16(
                data, offset: pos + 2, bigEndian: bigEndian)
            if group == 0xFFFE && element == 0xE0DD {
                // Found Sequence Delimitation Item — include it
                // (8 bytes: tag + 4-byte zero length) in the returned span.
                return pos + 8
            }
            let len = Int(J2KDICOMByteReader.readU32(
                data, offset: pos + 4, bigEndian: bigEndian))
            if len == 0xFFFF_FFFF {
                // Defensive: shouldn't happen at this level, but advance
                // by 8 bytes to avoid an infinite loop.
                pos += 8
            } else {
                pos += 8 + len
            }
        }
        return data.count
    }
}
