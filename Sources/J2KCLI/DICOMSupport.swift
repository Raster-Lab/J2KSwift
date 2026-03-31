//
// DICOMSupport.swift
// J2KSwift
//
/// Minimal DICOM pixel-data extractor (input only).
///
/// Parses uncompressed DICOM files with explicit and implicit VR, in both
/// little-endian and big-endian transfer syntaxes. Strips all metadata and
/// returns only the raw pixel data as a `J2KImage`.
///
/// This code lives in the CLI target only — no DICOM dependency is added to
/// the J2KSwift library (per ADR-004).

import Foundation
import J2KCore

extension J2KCLI {

    // MARK: - Transfer Syntax

    private enum DICOMTransferSyntax {
        case implicitVRLittleEndian
        case explicitVRLittleEndian
        case explicitVRBigEndian
    }

    // MARK: - Public API

    /// Load a DICOM file, stripping all metadata and returning the pixel data
    /// as a `J2KImage`.
    ///
    /// Only uncompressed transfer syntaxes are supported. JPEG 2000 transfer
    /// syntaxes produce a helpful error directing the user to `j2k decode`.
    static func loadDICOM(_ data: Data) throws -> J2KImage {
        // 1. Validate preamble + magic
        guard data.count >= 132 + 4 else {
            throw J2KError.invalidParameter("Not a valid DICOM file: too small")
        }
        let magic = String(data: data.subdata(in: 128..<132), encoding: .ascii)
        guard magic == "DICM" else {
            throw J2KError.invalidParameter(
                "Not a valid DICOM file (missing DICM prefix). " +
                "Ensure the file includes the 128-byte preamble.")
        }

        // 2. Read File Meta Information (group 0002, always Explicit VR LE)
        var offset = 132
        var transferSyntax: DICOMTransferSyntax = .explicitVRLittleEndian

        // Read tags in group 0002 to find Transfer Syntax UID
        while offset + 8 <= data.count {
            let group   = dcmReadU16LE(data, offset: offset)
            let element = dcmReadU16LE(data, offset: offset + 2)

            if group != 0x0002 { break }

            // Group 0002 is always Explicit VR Little Endian
            let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)), encoding: .ascii) ?? ""
            let (valueLength, headerSize) = dcmValueLength(data, offset: offset, vr: vr, bigEndian: false)
            let valueStart = offset + headerSize

            if element == 0x0010 {
                // Transfer Syntax UID
                if let tsUID = dcmReadString(data, offset: valueStart, length: valueLength) {
                    transferSyntax = try parseDICOMTransferSyntax(tsUID)
                }
            }

            offset = valueStart + valueLength
        }

        // 3. Parse dataset to extract pixel-interpretation tags
        let bigEndian = (transferSyntax == .explicitVRBigEndian)
        let explicitVR = (transferSyntax != .implicitVRLittleEndian)

        var rows = 0
        var columns = 0
        var bitsAllocated = 16
        var bitsStored = 0
        var pixelRepresentation = 0  // 0 = unsigned, 1 = signed
        var samplesPerPixel = 1
        var photometricInterpretation = ""
        var planarConfiguration = 0
        var numberOfFrames = 1
        var pixelDataOffset = -1

        while offset + 4 <= data.count {
            let group   = dcmReadU16(data, offset: offset, bigEndian: bigEndian)
            let element = dcmReadU16(data, offset: offset + 2, bigEndian: bigEndian)
            let tag = (group, element)

            // Pixel Data tag — stop here
            if tag == (0x7FE0, 0x0010) {
                let (vl, hs) = dcmDatasetValueLength(data, offset: offset, explicitVR: explicitVR, bigEndian: bigEndian)
                pixelDataOffset = offset + hs
                if vl == 0xFFFF_FFFF {
                    // Undefined length = encapsulated
                    throw J2KError.invalidParameter(
                        "Encapsulated pixel data is not supported; only uncompressed DICOM files can be read.")
                }
                break
            }

            // Read value
            let (vl, hs) = dcmDatasetValueLength(data, offset: offset, explicitVR: explicitVR, bigEndian: bigEndian)
            let valueStart = offset + hs

            if vl == 0xFFFF_FFFF {
                // Undefined-length sequence — skip it
                offset = skipDICOMSequence(data, from: valueStart, bigEndian: bigEndian)
                continue
            }

            switch tag {
            case (0x0028, 0x0002):
                samplesPerPixel = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0004):
                photometricInterpretation = dcmReadString(data, offset: valueStart, length: vl) ?? ""
            case (0x0028, 0x0006):
                planarConfiguration = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0008):
                if let s = dcmReadString(data, offset: valueStart, length: vl), let n = Int(s.trimmingCharacters(in: .whitespaces)) {
                    numberOfFrames = n
                }
            case (0x0028, 0x0010):
                rows = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0011):
                columns = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0100):
                bitsAllocated = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0101):
                bitsStored = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            case (0x0028, 0x0102):
                break  // High Bit — parsed but not needed
            case (0x0028, 0x0103):
                pixelRepresentation = Int(dcmReadU16(data, offset: valueStart, bigEndian: bigEndian))
            default:
                break
            }

            offset = valueStart + vl
        }

        // Validate
        guard pixelDataOffset >= 0 else {
            throw J2KError.invalidParameter("DICOM file missing Pixel Data tag (7FE0,0010)")
        }
        guard rows > 0 && columns > 0 else {
            throw J2KError.invalidParameter("DICOM file missing Rows/Columns tags")
        }
        if bitsStored == 0 { bitsStored = bitsAllocated }
        if numberOfFrames > 1 {
            if let warnData = "Warning: DICOM file has \(numberOfFrames) frames; extracting first frame only.\n".data(using: .utf8) {
                FileHandle.standardError.write(warnData)
            }
        }

        let signed = pixelRepresentation != 0
        let bytesPerSample = bitsAllocated / 8
        let frameSize = columns * rows * samplesPerPixel * bytesPerSample

        guard pixelDataOffset + frameSize <= data.count else {
            throw J2KError.invalidParameter("DICOM pixel data truncated")
        }

        var pixelData = data.subdata(in: pixelDataOffset..<(pixelDataOffset + frameSize))

        // Byte-swap big-endian 16-bit samples to host order
        if bigEndian && bytesPerSample == 2 {
            let sampleCount = pixelData.count / 2
            for i in 0..<sampleCount {
                pixelData.swapAt(i * 2, i * 2 + 1)
            }
        }

        // De-interleave into component planes
        let components: [J2KComponent]
        if samplesPerPixel == 1 {
            components = [J2KComponent(
                index: 0,
                bitDepth: bitsStored,
                signed: signed,
                width: columns,
                height: rows,
                subsamplingX: 1,
                subsamplingY: 1,
                data: pixelData
            )]
        } else if planarConfiguration == 1 {
            // Planar — data is plane-by-plane
            let planeSize = columns * rows * bytesPerSample
            var comps: [J2KComponent] = []
            for s in 0..<samplesPerPixel {
                let start = s * planeSize
                let end = min(start + planeSize, pixelData.count)
                comps.append(J2KComponent(
                    index: s,
                    bitDepth: bitsStored,
                    signed: signed,
                    width: columns,
                    height: rows,
                    subsamplingX: 1,
                    subsamplingY: 1,
                    data: pixelData.subdata(in: start..<end)
                ))
            }
            components = comps
        } else {
            // Interleaved by pixel — de-interleave
            let pixelCount = columns * rows
            var planes = Array(repeating: Data(count: pixelCount * bytesPerSample), count: samplesPerPixel)
            for i in 0..<pixelCount {
                for s in 0..<samplesPerPixel {
                    let srcOff = (i * samplesPerPixel + s) * bytesPerSample
                    let dstOff = i * bytesPerSample
                    for b in 0..<bytesPerSample {
                        if srcOff + b < pixelData.count {
                            planes[s][dstOff + b] = pixelData[srcOff + b]
                        }
                    }
                }
            }
            components = planes.enumerated().map { (idx, planeData) in
                J2KComponent(
                    index: idx,
                    bitDepth: bitsStored,
                    signed: signed,
                    width: columns,
                    height: rows,
                    subsamplingX: 1,
                    subsamplingY: 1,
                    data: planeData
                )
            }
        }

        // Map colour space
        let pi = photometricInterpretation.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let colorSpace: J2KColorSpace
        switch pi {
        case "RGB":
            colorSpace = .sRGB
        case "YBR_FULL", "YBR_FULL_422":
            // TODO: Convert YBR to RGB
            colorSpace = .sRGB
        default:
            colorSpace = .grayscale
        }

        return J2KImage(
            width: columns,
            height: rows,
            components: components,
            colorSpace: colorSpace
        )
    }

    // MARK: - Transfer Syntax Parsing

    private static func parseDICOMTransferSyntax(_ uid: String) throws -> DICOMTransferSyntax {
        let trimmed = uid.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(["\0"])))
        switch trimmed {
        case "1.2.840.10008.1.2":
            return .implicitVRLittleEndian
        case "1.2.840.10008.1.2.1":
            return .explicitVRLittleEndian
        case "1.2.840.10008.1.2.2":
            return .explicitVRBigEndian
        default:
            // Check for JPEG 2000 transfer syntaxes
            if trimmed.hasPrefix("1.2.840.10008.1.2.4.90") || trimmed.hasPrefix("1.2.840.10008.1.2.4.91") {
                throw J2KError.invalidParameter(
                    "Input is already JPEG 2000 compressed (TS: \(trimmed)). Use `j2k decode` instead.")
            }
            // Other compressed transfer syntaxes
            if trimmed.hasPrefix("1.2.840.10008.1.2.4") || trimmed.hasPrefix("1.2.840.10008.1.2.5") {
                throw J2KError.invalidParameter(
                    "Compressed DICOM transfer syntax (\(trimmed)) is not supported. Only uncompressed DICOM files can be read.")
            }
            // Unknown — try as explicit VR LE
            return .explicitVRLittleEndian
        }
    }

    // MARK: - Low-level DICOM helpers

    private static func dcmReadU16LE(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func dcmReadU16(_ data: Data, offset: Int, bigEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        if bigEndian {
            return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
        }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func dcmReadU32(_ data: Data, offset: Int, bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        if bigEndian {
            return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16
                 | UInt32(data[offset + 2]) << 8 | UInt32(data[offset + 3])
        }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
             | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func dcmReadString(_ data: Data, offset: Int, length: Int) -> String? {
        guard offset + length <= data.count else { return nil }
        return String(data: data.subdata(in: offset..<(offset + length)), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(["\0"])))
    }

    /// Read value length for a tag in File Meta Information (always Explicit VR LE).
    private static func dcmValueLength(_ data: Data, offset: Int, vr: String, bigEndian: Bool) -> (length: Int, headerSize: Int) {
        // Explicit VR with 4-byte length for OB, OD, OF, OL, OW, SQ, UC, UN, UR, UT
        let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OW", "SQ", "UC", "UN", "UR", "UT"]
        if longVRs.contains(vr) {
            // 4 bytes tag + 2 VR + 2 reserved + 4 length
            let length = Int(dcmReadU32(data, offset: offset + 8, bigEndian: bigEndian))
            return (length, 12)
        } else {
            // 4 bytes tag + 2 VR + 2 length
            let length = Int(dcmReadU16(data, offset: offset + 6, bigEndian: bigEndian))
            return (length, 8)
        }
    }

    /// Read value length for a tag in the dataset (may be explicit or implicit VR).
    private static func dcmDatasetValueLength(_ data: Data, offset: Int, explicitVR: Bool, bigEndian: Bool) -> (length: Int, headerSize: Int) {
        if !explicitVR {
            // Implicit VR: tag (4) + length (4)
            let length = Int(dcmReadU32(data, offset: offset + 4, bigEndian: false))  // implicit is always LE
            return (length, 8)
        }

        guard offset + 6 <= data.count else { return (0, 8) }
        let vr = String(data: data.subdata(in: (offset + 4)..<(offset + 6)), encoding: .ascii) ?? ""
        return dcmValueLength(data, offset: offset, vr: vr, bigEndian: bigEndian)
    }

    /// Skip a DICOM sequence with undefined length.
    private static func skipDICOMSequence(_ data: Data, from start: Int, bigEndian: Bool) -> Int {
        var pos = start
        while pos + 8 <= data.count {
            let itemTag = (dcmReadU16(data, offset: pos, bigEndian: bigEndian),
                          dcmReadU16(data, offset: pos + 2, bigEndian: bigEndian))
            let itemLen = Int(dcmReadU32(data, offset: pos + 4, bigEndian: bigEndian))

            if itemTag == (0xFFFE, 0xE0DD) {
                // Sequence Delimitation Item
                return pos + 8
            }

            if itemLen == 0xFFFF_FFFF {
                // Undefined length item — scan for Item Delimitation
                pos += 8
                while pos + 8 <= data.count {
                    let innerTag = (dcmReadU16(data, offset: pos, bigEndian: bigEndian),
                                   dcmReadU16(data, offset: pos + 2, bigEndian: bigEndian))
                    if innerTag == (0xFFFE, 0xE00D) {
                        pos += 8
                        break
                    }
                    // Skip inner element
                    let (vl, hs) = dcmDatasetValueLength(data, offset: pos, explicitVR: true, bigEndian: bigEndian)
                    if vl == 0xFFFF_FFFF {
                        pos = skipDICOMSequence(data, from: pos + hs, bigEndian: bigEndian)
                    } else {
                        pos += hs + vl
                    }
                }
            } else {
                pos += 8 + itemLen
            }
        }
        return pos
    }
}
