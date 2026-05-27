// J2KDICOMByteReader.swift
//
// v10.21.0 — J2KDICOMHelpers Phase 3 (DICOM file parser).
//
// Internal byte-reading helpers ported from Sources/J2KCLI/DICOMSupport.swift
// (which has carried these since v8). The CLI version is private to the
// CLI executable target; this internal port lets the helpers product
// expose its own file parser without depending on the CLI.
//
// Kept `internal` (not public) — these are parser plumbing, not API.
// The CLI version stays in place; consumers needing the file parser
// use `J2KDICOMFileParser.parse(_:)` from this product instead.
//
// Byte-layout reference: DICOM PS3.5 §6 (Data Element Structure) +
// §7 (File Meta Information) + §6.2 (Value Representations).

import Foundation

enum J2KDICOMByteReader {

    /// Reads a 16-bit little-endian unsigned integer at `offset`.
    /// Returns 0 on out-of-bounds (defensive — match the CLI semantics).
    static func readU16LE(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let start = data.startIndex
        return UInt16(data[start + offset])
            | UInt16(data[start + offset + 1]) << 8
    }

    /// Reads a 16-bit unsigned integer at `offset` with endianness
    /// selected at runtime.
    static func readU16(_ data: Data, offset: Int, bigEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        let start = data.startIndex
        if bigEndian {
            return UInt16(data[start + offset]) << 8
                | UInt16(data[start + offset + 1])
        }
        return UInt16(data[start + offset])
            | UInt16(data[start + offset + 1]) << 8
    }

    /// Reads a 32-bit unsigned integer at `offset` with endianness
    /// selected at runtime.
    static func readU32(_ data: Data, offset: Int, bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        let start = data.startIndex
        if bigEndian {
            return UInt32(data[start + offset]) << 24
                | UInt32(data[start + offset + 1]) << 16
                | UInt32(data[start + offset + 2]) << 8
                | UInt32(data[start + offset + 3])
        }
        return UInt32(data[start + offset])
            | UInt32(data[start + offset + 1]) << 8
            | UInt32(data[start + offset + 2]) << 16
            | UInt32(data[start + offset + 3]) << 24
    }

    /// Reads `length` bytes at `offset` as an ASCII string, trimming
    /// whitespace and trailing-NUL padding (per DICOM PS3.5 §6.2 for
    /// UID-typed VRs).
    static func readString(_ data: Data, offset: Int, length: Int) -> String? {
        guard length >= 0, offset + length <= data.count else { return nil }
        let start = data.startIndex
        return String(
            data: data.subdata(in: (start + offset)..<(start + offset + length)),
            encoding: .ascii
        )?.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(["\0"])))
    }

    /// Reads value-length for a tag in File Meta Information (always
    /// Explicit VR Little Endian per PS3.5 §7.1).
    ///
    /// The "long" VRs (OB, OD, OF, OL, OW, SQ, UC, UN, UR, UT) carry a
    /// 4-byte length after 2 reserved bytes; everything else has a
    /// 2-byte length immediately after the 2-byte VR.
    static func valueLength(
        _ data: Data,
        offset: Int,
        vr: String,
        bigEndian: Bool
    ) -> (length: Int, headerSize: Int) {
        let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"]
        if longVRs.contains(vr) {
            // 4-byte tag + 2-byte VR + 2 reserved + 4-byte length = 12-byte header
            let length = Int(readU32(data, offset: offset + 8, bigEndian: bigEndian))
            return (length, 12)
        } else {
            // 4-byte tag + 2-byte VR + 2-byte length = 8-byte header
            let length = Int(readU16(data, offset: offset + 6, bigEndian: bigEndian))
            return (length, 8)
        }
    }

    /// Reads value-length for a dataset element (may be Explicit or
    /// Implicit VR). For Implicit VR, the length is always a 4-byte
    /// little-endian field after the 4-byte tag (per PS3.5 §7.1.2).
    static func datasetValueLength(
        _ data: Data,
        offset: Int,
        explicitVR: Bool,
        bigEndian: Bool
    ) -> (length: Int, headerSize: Int) {
        if !explicitVR {
            // Implicit VR: 4-byte tag + 4-byte length (always LE per PS3.5 §7.1.2)
            let length = Int(readU32(data, offset: offset + 4, bigEndian: false))
            return (length, 8)
        }

        guard offset + 6 <= data.count else { return (0, 8) }
        let start = data.startIndex
        let vr = String(
            data: data.subdata(in: (start + offset + 4)..<(start + offset + 6)),
            encoding: .ascii
        ) ?? ""
        return valueLength(data, offset: offset, vr: vr, bigEndian: bigEndian)
    }

    /// Skips a DICOM sequence with undefined length (per PS3.5 §7.5).
    /// The sequence ends at the Sequence Delimitation Item
    /// (FFFE,E0DD); nested items with undefined length are skipped
    /// via their Item Delimitation Items (FFFE,E00D). Returns the
    /// byte offset immediately after the sequence's delimiter.
    static func skipSequence(_ data: Data, from start: Int, bigEndian: Bool) -> Int {
        var pos = start
        while pos + 8 <= data.count {
            let itemTagGroup = readU16(data, offset: pos, bigEndian: bigEndian)
            let itemTagElement = readU16(data, offset: pos + 2, bigEndian: bigEndian)
            let itemLen = Int(readU32(data, offset: pos + 4, bigEndian: bigEndian))

            // Sequence Delimitation Item (FFFE,E0DD) ends this sequence.
            if itemTagGroup == 0xFFFE && itemTagElement == 0xE0DD {
                return pos + 8
            }

            if itemLen == 0xFFFF_FFFF {
                // Undefined-length item — scan for the Item Delimitation
                // Item (FFFE,E00D), skipping inner elements along the way.
                pos += 8
                while pos + 8 <= data.count {
                    let innerGroup = readU16(data, offset: pos, bigEndian: bigEndian)
                    let innerElement = readU16(data, offset: pos + 2, bigEndian: bigEndian)
                    if innerGroup == 0xFFFE && innerElement == 0xE00D {
                        pos += 8
                        break
                    }
                    let (innerLen, innerHeader) = datasetValueLength(
                        data, offset: pos, explicitVR: true, bigEndian: bigEndian)
                    if innerLen == 0xFFFF_FFFF {
                        pos = skipSequence(data, from: pos + innerHeader, bigEndian: bigEndian)
                    } else {
                        pos += innerHeader + innerLen
                    }
                }
            } else {
                pos += 8 + itemLen
            }
        }
        return pos
    }
}
