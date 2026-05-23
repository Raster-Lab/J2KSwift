//
// DICOMReader.swift
// J2KBenchApp — image viewer
//
// Minimal, input-only uncompressed-DICOM pixel-data extractor. Parses
// explicit/implicit VR in little- and big-endian transfer syntaxes and
// returns the first frame's pixels as a `J2KImage`. Compressed /
// encapsulated transfer syntaxes are rejected with a clear error —
// this is a viewer convenience, not a full DICOM toolkit.
//
// Ported (and trimmed: no Python fallback, no multi-frame mosaic) from
// `Sources/J2KCLI/DICOMSupport.swift`.

import Foundation
import J2KCore

enum DICOMReader {

    enum DICOMError: LocalizedError {
        case compressed(String)
        case unsupported(String)
        var errorDescription: String? {
            switch self {
            case .compressed(let ts):
                return "This DICOM uses a compressed transfer syntax (\(ts)). "
                     + "The viewer reads uncompressed DICOM only."
            case .unsupported(let why):
                return "Unsupported DICOM file: \(why)."
            }
        }
    }

    /// Decode an uncompressed DICOM file. Returns `nil` if `data` is not
    /// a DICOM file at all; throws `DICOMError` for a DICOM file this
    /// minimal reader cannot handle.
    static func read(_ data: Data) throws -> J2KImage? {
        // Preamble (128 bytes) + "DICM" magic.
        guard data.count >= 136,
              data.subdata(in: 128..<132) == Data([0x44, 0x49, 0x43, 0x4D])
        else { return nil }

        // File Meta group (0002) is always Explicit VR Little Endian.
        var offset = 132
        var transferSyntax = "1.2.840.10008.1.2.1"
        while offset + 8 <= data.count {
            guard u16(data, offset, false) == 0x0002 else { break }
            let element = u16(data, offset + 2, false)
            let vr = ascii(data, offset + 4, 2) ?? ""
            let (vl, hs) = explicitValueLength(data, offset, vr, false)
            if element == 0x0010, let s = ascii(data, offset + hs, vl) {
                transferSyntax = s.trimmingCharacters(
                    in: .whitespacesAndNewlines.union(CharacterSet(["\0"])))
            }
            offset += hs + vl
        }

        // Interpret the transfer syntax.
        let explicitVR = transferSyntax != "1.2.840.10008.1.2"
        let bigEndian = transferSyntax == "1.2.840.10008.1.2.2"
        let compressed = transferSyntax.hasPrefix("1.2.840.10008.1.2.4")
            || transferSyntax.hasPrefix("1.2.840.10008.1.2.5")

        // Walk the dataset for the pixel-interpretation tags.
        var rows = 0, cols = 0
        var bitsAllocated = 16, bitsStored = 0
        var pixelRepresentation = 0, samplesPerPixel = 1, planar = 0
        var photometric = ""
        var pixelOffset = -1, pixelLength = 0

        while offset + 8 <= data.count {
            let group = u16(data, offset, bigEndian)
            let element = u16(data, offset + 2, bigEndian)

            if group == 0x7FE0 && element == 0x0010 {
                let (vl, hs) = datasetValueLength(data, offset, explicitVR, bigEndian)
                pixelOffset = offset + hs
                pixelLength = vl
                break
            }

            let (vl, hs) = datasetValueLength(data, offset, explicitVR, bigEndian)
            let valueStart = offset + hs
            if vl == 0xFFFF_FFFF {
                offset = skipSequence(data, valueStart, bigEndian)
                continue
            }
            switch (group, element) {
            case (0x0028, 0x0002): samplesPerPixel = Int(u16(data, valueStart, bigEndian))
            case (0x0028, 0x0004): photometric = ascii(data, valueStart, vl) ?? ""
            case (0x0028, 0x0006): planar = Int(u16(data, valueStart, bigEndian))
            case (0x0028, 0x0010): rows = Int(u16(data, valueStart, bigEndian))
            case (0x0028, 0x0011): cols = Int(u16(data, valueStart, bigEndian))
            case (0x0028, 0x0100): bitsAllocated = Int(u16(data, valueStart, bigEndian))
            case (0x0028, 0x0101): bitsStored = Int(u16(data, valueStart, bigEndian))
            case (0x0028, 0x0103): pixelRepresentation = Int(u16(data, valueStart, bigEndian))
            default: break
            }
            offset = valueStart + vl
        }

        guard pixelOffset >= 0 else {
            throw DICOMError.unsupported("no pixel data element")
        }
        if compressed || pixelLength == 0xFFFF_FFFF {
            throw DICOMError.compressed(transferSyntax)
        }
        guard rows > 0, cols > 0 else {
            throw DICOMError.unsupported("missing Rows/Columns")
        }

        let effectiveBits = bitsStored == 0 ? bitsAllocated : bitsStored
        let bytesPerSample = max(1, (bitsAllocated + 7) / 8)
        let spp = max(1, samplesPerPixel)
        let pixelCount = rows * cols
        let frameBytes = pixelCount * spp * bytesPerSample
        guard frameBytes > 0, pixelOffset + frameBytes <= data.count else {
            throw DICOMError.unsupported("pixel data truncated")
        }

        // First frame only — a viewer doesn't need the multi-frame mosaic.
        let frame = data.subdata(in: pixelOffset..<(pixelOffset + frameBytes))
        let planes = splitPlanes(frame, samplesPerPixel: spp, planar: planar,
                                 pixelCount: pixelCount, bytesPerSample: bytesPerSample)

        let byteOrder: J2KComponent.ByteOrder? =
            bytesPerSample == 2 ? (bigEndian ? .bigEndian : .littleEndian) : nil
        let components = planes.enumerated().map { index, plane in
            J2KComponent(index: index, bitDepth: effectiveBits,
                         signed: pixelRepresentation != 0,
                         width: cols, height: rows,
                         subsamplingX: 1, subsamplingY: 1,
                         data: plane, sampleByteOrder: byteOrder)
        }

        let interp = photometric
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let colorSpace: J2KColorSpace =
            interp == "RGB" ? .sRGB
            : interp.hasPrefix("YBR") ? .yCbCr
            : .grayscale

        return J2KImage(width: cols, height: rows,
                        components: components, colorSpace: colorSpace)
    }

    // MARK: - Plane split

    private static func splitPlanes(_ frame: Data, samplesPerPixel: Int,
                                    planar: Int, pixelCount: Int,
                                    bytesPerSample: Int) -> [Data] {
        if samplesPerPixel == 1 { return [frame] }
        let planeSize = pixelCount * bytesPerSample
        if planar == 1 {
            return (0..<samplesPerPixel).map { s in
                let start = s * planeSize
                let end = min(start + planeSize, frame.count)
                return start < end ? frame.subdata(in: start..<end)
                                    : Data(count: planeSize)
            }
        }
        // Interleaved → planar.
        var planes = Array(repeating: Data(count: planeSize), count: samplesPerPixel)
        frame.withUnsafeBytes { src in
            let bytes = src.bindMemory(to: UInt8.self)
            for s in 0..<samplesPerPixel {
                planes[s].withUnsafeMutableBytes { dst in
                    let out = dst.bindMemory(to: UInt8.self)
                    for p in 0..<pixelCount {
                        let from = (p * samplesPerPixel + s) * bytesPerSample
                        let to = p * bytesPerSample
                        for k in 0..<bytesPerSample where from + k < bytes.count {
                            out[to + k] = bytes[from + k]
                        }
                    }
                }
            }
        }
        return planes
    }

    // MARK: - Low-level readers

    private static func u16(_ data: Data, _ offset: Int, _ bigEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count, offset >= 0 else { return 0 }
        let a = UInt16(data[offset]), b = UInt16(data[offset + 1])
        return bigEndian ? (a << 8 | b) : (b << 8 | a)
    }

    private static func u32(_ data: Data, _ offset: Int, _ bigEndian: Bool) -> UInt32 {
        guard offset + 4 <= data.count, offset >= 0 else { return 0 }
        let b = (0..<4).map { UInt32(data[offset + $0]) }
        return bigEndian
            ? (b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3])
            : (b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0])
    }

    private static func ascii(_ data: Data, _ offset: Int, _ length: Int) -> String? {
        guard length > 0, offset >= 0, offset + length <= data.count else { return nil }
        return String(data: data.subdata(in: offset..<(offset + length)),
                      encoding: .ascii)
    }

    /// Explicit-VR value length (File Meta group / explicit-VR dataset).
    private static func explicitValueLength(_ data: Data, _ offset: Int,
                                            _ vr: String, _ bigEndian: Bool)
        -> (length: Int, headerSize: Int) {
        let longVRs: Set<String> = ["OB", "OD", "OF", "OL", "OW", "SQ",
                                    "UC", "UN", "UR", "UT"]
        if longVRs.contains(vr) {
            return (Int(u32(data, offset + 8, bigEndian)), 12)
        }
        return (Int(u16(data, offset + 6, bigEndian)), 8)
    }

    private static func datasetValueLength(_ data: Data, _ offset: Int,
                                           _ explicitVR: Bool, _ bigEndian: Bool)
        -> (length: Int, headerSize: Int) {
        if !explicitVR {
            return (Int(u32(data, offset + 4, false)), 8)  // implicit VR is always LE
        }
        let vr = ascii(data, offset + 4, 2) ?? ""
        return explicitValueLength(data, offset, vr, bigEndian)
    }

    /// Skip an undefined-length sequence, returning the offset just
    /// past its delimitation item.
    private static func skipSequence(_ data: Data, _ start: Int,
                                     _ bigEndian: Bool) -> Int {
        var pos = start
        while pos + 8 <= data.count {
            let tag = (u16(data, pos, bigEndian), u16(data, pos + 2, bigEndian))
            let itemLength = Int(u32(data, pos + 4, bigEndian))
            if tag == (0xFFFE, 0xE0DD) { return pos + 8 }   // sequence delimiter
            if itemLength == 0xFFFF_FFFF {
                pos += 8
                while pos + 8 <= data.count {
                    let inner = (u16(data, pos, bigEndian), u16(data, pos + 2, bigEndian))
                    if inner == (0xFFFE, 0xE00D) { pos += 8; break }
                    let (vl, hs) = datasetValueLength(data, pos, true, bigEndian)
                    pos = vl == 0xFFFF_FFFF
                        ? skipSequence(data, pos + hs, bigEndian)
                        : pos + hs + vl
                }
            } else {
                pos += 8 + itemLength
            }
        }
        return pos
    }
}
