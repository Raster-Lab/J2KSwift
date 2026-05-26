// J2KDICOMPixelDataEncapsulation.swift
//
// v10.19.0 — J2KDICOMHelpers Phase 2: DICOM Pixel Data encapsulation
// helpers.
//
// JPEG 2000-tagged DICOM Pixel Data is laid out per PS3.5 §A.4 as a
// sequence of Items inside an undefined-length `(7FE0,0010) OB`
// Pixel Data element:
//
//   [Item-tag FFFE,E000] [Length LE u32]              ← (optional) Basic Offset Table
//   [Item-tag FFFE,E000] [Length LE u32] [J2K frame 0 bytes] [optional pad]
//   [Item-tag FFFE,E000] [Length LE u32] [J2K frame 1 bytes] [optional pad]
//   …
//   [Sequence Delim FFFE,E0DD] [Length 00 00 00 00]
//
// The Basic Offset Table (BOT), when non-empty, contains one big-endian
// u32 offset per frame, measured from the start of the FIRST FRAME ITEM
// (NOT from the start of Pixel Data — important detail). When empty
// (length = 0), the BOT item is still present but carries no offsets;
// the decoder must scan the Item sequence linearly to find frame N.
//
// Each frame Item's data is a complete, decoder-ready JPEG 2000 / HTJ2K
// codestream starting with SOC (0xFF 0x4F). Item lengths must be even
// per DICOM PS3.5 §6.4 — frames with odd codestream byte counts get a
// trailing 0x00 pad byte (the pad is NOT part of the codestream, just
// part of the Item).
//
// ADR-004 compliant: no DICOM library dependency. The byte-layout
// rules are codified directly here from PS3.5 §A.4 / §6.4.

import Foundation

// MARK: - Encapsulator

/// Wraps J2K codestreams into DICOM Pixel Data encapsulated bytes.
///
/// Use this when you have one or more J2K / HTJ2K codestreams (typically
/// from `J2KEncoder.encode(_:)` or `J2KSwift`'s JP3D encoders) and need
/// to write them into a DICOM file's `(7FE0,0010)` Pixel Data element
/// per PS3.5 §A.4.
public enum J2KDICOMPixelDataEncapsulator {

    /// Wraps a single J2K codestream into one DICOM Pixel Data Item.
    ///
    /// Returns the 8-byte Item header (`FFFE E000` + length LE u32) +
    /// codestream bytes + optional 0x00 pad byte if the codestream
    /// length is odd. Item length includes the pad byte (per PS3.5 §6.4
    /// "Data Element Length shall always be an even number").
    ///
    /// - Parameter codestream: A complete J2K / HTJ2K codestream (the
    ///   bytes that begin with SOC `0xFF 0x4F`).
    /// - Returns: The Item bytes ready to insert into a Pixel Data sequence.
    public static func encapsulateItem(_ codestream: Data) -> Data {
        // Per PS3.5 §6.4 — Data Element Length must be even.
        let paddedLength = (codestream.count + 1) & ~1
        let needsPad = paddedLength != codestream.count

        var item = Data()
        item.reserveCapacity(8 + paddedLength)

        // Item tag FFFE,E000 — written little-endian as (FE FF) (00 E0).
        item.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])

        // Length LE u32.
        let len = UInt32(paddedLength)
        item.append(UInt8(len & 0xFF))
        item.append(UInt8((len >> 8) & 0xFF))
        item.append(UInt8((len >> 16) & 0xFF))
        item.append(UInt8((len >> 24) & 0xFF))

        // Payload + (optional) pad.
        item.append(codestream)
        if needsPad { item.append(0x00) }

        return item
    }

    /// Wraps one or more J2K codestreams into a DICOM Pixel Data Item
    /// sequence, optionally prefixed with a Basic Offset Table.
    ///
    /// Per PS3.5 §A.4 the sequence is:
    /// - BOT item (always present; length 0 if not populated)
    /// - One Item per frame, each carrying the frame's codestream
    /// - Sequence Delimitation Item (`FFFE,E0DD`) with length 0
    ///
    /// When `includeBOT == true`, the BOT contains one big-endian u32
    /// per frame: the offset of that frame's Item header measured from
    /// the start of the FIRST FRAME ITEM (NOT from the start of the
    /// returned bytes). When `false`, the BOT is emitted with length 0
    /// (per the standard, this is the common case for single-frame
    /// images — a populated BOT is optional even for multi-frame).
    ///
    /// - Parameters:
    ///   - frames: One J2K / HTJ2K codestream per frame.
    ///   - includeBOT: When true, populate the BOT with per-frame offsets.
    /// - Returns: The complete Item sequence (BOT + frames + delimiter).
    public static func encapsulateFrames(
        _ frames: [Data],
        includeBOT: Bool = false
    ) -> Data {
        // Build the frame items first so we can compute BOT offsets
        // measured from the start of the first frame item.
        var frameItems: [Data] = []
        frameItems.reserveCapacity(frames.count)
        var offsets: [UInt32] = []
        offsets.reserveCapacity(frames.count)
        var runningOffset: UInt32 = 0
        for frame in frames {
            offsets.append(runningOffset)
            let item = encapsulateItem(frame)
            frameItems.append(item)
            runningOffset = runningOffset &+ UInt32(item.count)
        }

        // BOT item: 8-byte header + (optional) u32 offsets payload.
        let botPayloadCount = includeBOT ? frames.count * 4 : 0
        var output = Data()
        output.reserveCapacity(8 + botPayloadCount + frameItems.reduce(0) { $0 + $1.count } + 8)

        // BOT item tag + length.
        output.append(contentsOf: [0xFE, 0xFF, 0x00, 0xE0])
        let botLen = UInt32(botPayloadCount)
        output.append(UInt8(botLen & 0xFF))
        output.append(UInt8((botLen >> 8) & 0xFF))
        output.append(UInt8((botLen >> 16) & 0xFF))
        output.append(UInt8((botLen >> 24) & 0xFF))

        if includeBOT {
            // BOT entries — BIG-endian u32 per DICOM PS3.5 §A.4.
            // (Note: confusingly, the BOT entries are little-endian per
            // some interpretations — but the canonical reading per the
            // most recent DICOM Standard and the dcm4che / pydicom
            // reference codebases is little-endian. We follow the
            // current standard: little-endian u32.)
            for offset in offsets {
                output.append(UInt8(offset & 0xFF))
                output.append(UInt8((offset >> 8) & 0xFF))
                output.append(UInt8((offset >> 16) & 0xFF))
                output.append(UInt8((offset >> 24) & 0xFF))
            }
        }

        // Frame items.
        for item in frameItems {
            output.append(item)
        }

        // Sequence Delimitation Item — FFFE,E0DD, length 0.
        output.append(contentsOf: [0xFE, 0xFF, 0xDD, 0xE0])
        output.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

        return output
    }
}

// MARK: - Decapsulator

/// Errors emitted by `J2KDICOMPixelDataDecapsulator`.
public enum J2KDICOMPixelDataError: Error, Sendable, Equatable {
    /// The input was too short to contain even the BOT Item header.
    case truncated(needed: Int, got: Int)
    /// Expected an Item tag (`FFFE,E000`) at the given offset.
    case itemTagExpected(offset: Int)
    /// Item length runs past the end of the input buffer.
    case itemLengthOverrun(itemOffset: Int, declaredLength: Int)
    /// Sequence Delimitation Item (`FFFE,E0DD`) malformed (non-zero length).
    case malformedSequenceDelimitation(actualLength: UInt32)
}

/// Extracts J2K codestream frames from DICOM Pixel Data encapsulated bytes.
public enum J2KDICOMPixelDataDecapsulator {

    /// Parses a DICOM Pixel Data encapsulated sequence and returns the
    /// constituent J2K codestream frame(s).
    ///
    /// The input is expected to be the bytes between the `(7FE0,0010)`
    /// Pixel Data element's 8-byte header (tag + VR + reserved + length)
    /// and the (optional) Sequence Delimitation Item — i.e., starting
    /// at the BOT Item tag and ending at or before the
    /// `FFFE,E0DD` delimiter.
    ///
    /// Strips trailing 0x00 pad bytes from each frame's payload only when
    /// the codestream payload is one byte longer than the actual J2K
    /// codestream — detection uses the EOC marker (`0xFF 0xD9`) being
    /// the last two bytes before a single pad byte. Conservatively
    /// retains all bytes when EOC isn't at the expected position.
    ///
    /// - Parameter encapsulated: DICOM Pixel Data sequence bytes (BOT + frame items + delimiter).
    /// - Returns: One `Data` per frame, each a decoder-ready J2K codestream.
    /// - Throws: `J2KDICOMPixelDataError` on malformed input.
    public static func extractFrames(_ encapsulated: Data) throws -> [Data] {
        var frames: [Data] = []
        var offset = 0

        // BOT Item — REQUIRED to be present (even if length 0).
        guard encapsulated.count >= 8 else {
            throw J2KDICOMPixelDataError.truncated(needed: 8, got: encapsulated.count)
        }
        let botTag = readU32LE(encapsulated, at: 0)
        guard botTag == 0xE000_FFFE else {
            throw J2KDICOMPixelDataError.itemTagExpected(offset: 0)
        }
        let botLen = readU32LE(encapsulated, at: 4)
        offset = 8 + Int(botLen)
        guard offset <= encapsulated.count else {
            throw J2KDICOMPixelDataError.itemLengthOverrun(
                itemOffset: 0, declaredLength: Int(botLen))
        }

        // Frame items — loop until Sequence Delimitation.
        while offset + 8 <= encapsulated.count {
            let tag = readU32LE(encapsulated, at: offset)
            if tag == 0xE0DD_FFFE {
                // Sequence Delimitation Item — length must be 0.
                let delimLen = readU32LE(encapsulated, at: offset + 4)
                if delimLen != 0 {
                    throw J2KDICOMPixelDataError.malformedSequenceDelimitation(
                        actualLength: delimLen)
                }
                break
            }
            guard tag == 0xE000_FFFE else {
                throw J2KDICOMPixelDataError.itemTagExpected(offset: offset)
            }
            let frameLen = readU32LE(encapsulated, at: offset + 4)
            let frameStart = offset + 8
            let frameEnd = frameStart + Int(frameLen)
            guard frameEnd <= encapsulated.count else {
                throw J2KDICOMPixelDataError.itemLengthOverrun(
                    itemOffset: offset, declaredLength: Int(frameLen))
            }

            // Slice the frame payload + strip a single trailing pad byte
            // if it looks like one (EOC 0xFF 0xD9 at [-3..-1] of the
            // payload means the last byte is pad).
            var frameBytes = encapsulated.subdata(in: frameStart..<frameEnd)
            if frameBytes.count >= 3 {
                let last3 = frameBytes.suffix(3)
                let bytes = Array(last3)
                if bytes[0] == 0xFF && bytes[1] == 0xD9 && bytes[2] == 0x00 {
                    frameBytes = frameBytes.dropLast()
                }
            }
            frames.append(frameBytes)

            offset = frameEnd
        }

        return frames
    }

    // MARK: - Private helpers

    private static func readU32LE(_ data: Data, at offset: Int) -> UInt32 {
        precondition(offset + 4 <= data.count)
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
