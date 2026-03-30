//
// TIFFSupport.swift
// J2KSwift
//
/// Minimal uncompressed TIFF reader/writer for 8/16/32-bit greyscale, RGB, and RGBA.
///
/// Supports both little-endian (`II`) and big-endian (`MM`) byte order on input.
/// Output is always little-endian. No dependency on libtiff.

import Foundation
import J2KCore

extension J2KCLI {

    // MARK: - TIFF Tags

    private enum TIFFTag: UInt16 {
        case imageWidth             = 256
        case imageLength            = 257
        case bitsPerSample          = 258
        case compression            = 259
        case photometricInterpretation = 262
        case stripOffsets           = 273
        case samplesPerPixel        = 277
        case rowsPerStrip           = 278
        case stripByteCounts        = 279
        case planarConfiguration    = 284
        case sampleFormat           = 339
    }

    // MARK: - TIFF Reading

    /// Load an uncompressed TIFF file into a `J2KImage`.
    static func loadTIFF(_ data: Data) throws -> J2KImage {
        guard data.count >= 8 else {
            throw J2KError.invalidParameter("Invalid TIFF: file too small")
        }

        // Byte order
        let bigEndian: Bool
        let bom = data[data.startIndex..<data.startIndex + 2]
        if bom.elementsEqual([0x49, 0x49]) {       // "II"
            bigEndian = false
        } else if bom.elementsEqual([0x4D, 0x4D]) { // "MM"
            bigEndian = true
        } else {
            throw J2KError.invalidParameter("Invalid TIFF: unrecognised byte-order mark")
        }

        // Magic 42
        let magic = readU16(data, offset: 2, bigEndian: bigEndian)
        guard magic == 42 else {
            throw J2KError.invalidParameter("Invalid TIFF: wrong magic number (\(magic))")
        }

        // Offset to first IFD
        let ifdOffset = Int(readU32(data, offset: 4, bigEndian: bigEndian))
        guard ifdOffset + 2 <= data.count else {
            throw J2KError.invalidParameter("Invalid TIFF: IFD offset out of range")
        }

        // Parse IFD
        let entryCount = Int(readU16(data, offset: ifdOffset, bigEndian: bigEndian))
        var tags: [UInt16: [UInt32]] = [:]

        for i in 0..<entryCount {
            let entryOffset = ifdOffset + 2 + i * 12
            guard entryOffset + 12 <= data.count else { break }

            let tag   = readU16(data, offset: entryOffset, bigEndian: bigEndian)
            let type  = readU16(data, offset: entryOffset + 2, bigEndian: bigEndian)
            let count = Int(readU32(data, offset: entryOffset + 4, bigEndian: bigEndian))
            let valueOrOffset = entryOffset + 8

            let typeSize: Int
            switch type {
            case 1: typeSize = 1  // BYTE
            case 3: typeSize = 2  // SHORT
            case 4: typeSize = 4  // LONG
            default: typeSize = 0
            }

            if typeSize == 0 { continue }

            let totalBytes = count * typeSize
            let valuesOffset: Int
            if totalBytes <= 4 {
                valuesOffset = valueOrOffset
            } else {
                valuesOffset = Int(readU32(data, offset: valueOrOffset, bigEndian: bigEndian))
            }

            var values: [UInt32] = []
            for j in 0..<count {
                let off = valuesOffset + j * typeSize
                guard off + typeSize <= data.count else { break }
                switch type {
                case 1: values.append(UInt32(data[off]))
                case 3: values.append(UInt32(readU16(data, offset: off, bigEndian: bigEndian)))
                case 4: values.append(readU32(data, offset: off, bigEndian: bigEndian))
                default: break
                }
            }
            tags[tag] = values
        }

        // Extract required tag values
        guard let width  = tags[TIFFTag.imageWidth.rawValue]?.first.map({ Int($0) }) else {
            throw J2KError.invalidParameter("TIFF missing ImageWidth tag")
        }
        guard let height = tags[TIFFTag.imageLength.rawValue]?.first.map({ Int($0) }) else {
            throw J2KError.invalidParameter("TIFF missing ImageLength tag")
        }
        let samplesPerPixel = Int(tags[TIFFTag.samplesPerPixel.rawValue]?.first ?? 1)
        let bitsPerSampleArr = tags[TIFFTag.bitsPerSample.rawValue] ?? [8]
        let bitsPerSample = Int(bitsPerSampleArr.first ?? 8)
        let compression = tags[TIFFTag.compression.rawValue]?.first ?? 1
        let photoInterp = Int(tags[TIFFTag.photometricInterpretation.rawValue]?.first ?? 1)
        let sampleFormat = Int(tags[TIFFTag.sampleFormat.rawValue]?.first ?? 1)
        let planarConfig = Int(tags[TIFFTag.planarConfiguration.rawValue]?.first ?? 1)

        // Validate
        guard compression == 1 else {
            throw J2KError.invalidParameter("Only uncompressed TIFF is supported (compression=\(compression))")
        }
        guard bitsPerSample == 8 || bitsPerSample == 16 || bitsPerSample == 32 else {
            throw J2KError.invalidParameter("Unsupported TIFF bit depth: \(bitsPerSample)")
        }
        guard sampleFormat == 1 || sampleFormat == 2 else {
            throw J2KError.invalidParameter("Unsupported TIFF sample format: \(sampleFormat). Only unsigned (1) and signed (2) integers are supported.")
        }

        let signed = sampleFormat == 2
        let bytesPerSample = bitsPerSample / 8

        // Assemble pixel data from strips
        let stripOffsets    = tags[TIFFTag.stripOffsets.rawValue] ?? []
        let stripByteCounts = tags[TIFFTag.stripByteCounts.rawValue] ?? []
        let rowsPerStrip    = Int(tags[TIFFTag.rowsPerStrip.rawValue]?.first ?? UInt32(height))

        var pixelData = Data()
        let expectedBytes = width * height * samplesPerPixel * bytesPerSample

        if stripOffsets.isEmpty {
            throw J2KError.invalidParameter("TIFF missing StripOffsets tag")
        }

        for i in 0..<stripOffsets.count {
            let offset = Int(stripOffsets[i])
            let count: Int
            if i < stripByteCounts.count {
                count = Int(stripByteCounts[i])
            } else {
                let stripRows = min(rowsPerStrip, height - (i * rowsPerStrip))
                count = stripRows * width * samplesPerPixel * bytesPerSample
            }
            guard offset + count <= data.count else {
                throw J2KError.invalidParameter("TIFF strip data out of range")
            }
            pixelData.append(data[offset..<(offset + count)])
        }

        guard pixelData.count >= expectedBytes else {
            throw J2KError.invalidParameter("TIFF: insufficient pixel data (\(pixelData.count) < \(expectedBytes))")
        }

        // Byte-swap big-endian 16/32-bit samples to host order (little-endian)
        if bigEndian && bytesPerSample > 1 {
            pixelData = byteSwapData(pixelData, bytesPerSample: bytesPerSample)
        }

        // De-interleave into separate J2KComponent planes
        let components: [J2KComponent]
        if planarConfig == 2 {
            // Already planar — split into slices
            let planeSize = width * height * bytesPerSample
            var comps: [J2KComponent] = []
            for s in 0..<samplesPerPixel {
                let start = s * planeSize
                let end = min(start + planeSize, pixelData.count)
                comps.append(J2KComponent(
                    index: s,
                    bitDepth: bitsPerSample,
                    signed: signed,
                    width: width,
                    height: height,
                    subsamplingX: 1,
                    subsamplingY: 1,
                    data: pixelData.subdata(in: start..<end)
                ))
            }
            components = comps
        } else if samplesPerPixel == 1 {
            components = [J2KComponent(
                index: 0,
                bitDepth: bitsPerSample,
                signed: signed,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: pixelData.prefix(expectedBytes)
            )]
        } else {
            // Interleaved — de-interleave
            components = deinterleaveComponents(
                pixelData,
                width: width,
                height: height,
                samplesPerPixel: samplesPerPixel,
                bytesPerSample: bytesPerSample,
                bitsPerSample: bitsPerSample,
                signed: signed
            )
        }

        let colorSpace: J2KColorSpace = (photoInterp == 2) ? .sRGB : .grayscale

        return J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: colorSpace
        )
    }

    // MARK: - TIFF Writing

    /// Save a `J2KImage` as an uncompressed little-endian TIFF file.
    static func saveTIFF(_ image: J2KImage, to url: URL) throws {
        guard !image.components.isEmpty else {
            throw J2KError.invalidParameter("Cannot write TIFF: image has no components")
        }

        let samplesPerPixel = image.componentCount
        let bitsPerSample = image.components[0].bitDepth
        let bytesPerSample = (bitsPerSample + 7) / 8
        // Normalise to standard byte widths
        let actualBytesPerSample: Int
        if bytesPerSample <= 1 { actualBytesPerSample = 1 }
        else if bytesPerSample <= 2 { actualBytesPerSample = 2 }
        else { actualBytesPerSample = 4 }

        let width = image.width
        let height = image.height
        let stripSize = width * height * samplesPerPixel * actualBytesPerSample

        // Build interleaved pixel data
        var pixelData = Data(count: stripSize)
        let pixelCount = width * height

        if samplesPerPixel == 1 {
            let comp = image.components[0]
            pixelData = comp.data.prefix(stripSize)
            // Pad if necessary
            if pixelData.count < stripSize {
                pixelData.append(Data(count: stripSize - pixelData.count))
            }
        } else {
            for i in 0..<pixelCount {
                for s in 0..<samplesPerPixel {
                    let comp = image.components[s]
                    let srcOffset = i * actualBytesPerSample
                    let dstOffset = (i * samplesPerPixel + s) * actualBytesPerSample
                    for b in 0..<actualBytesPerSample {
                        if srcOffset + b < comp.data.count {
                            pixelData[dstOffset + b] = comp.data[srcOffset + b]
                        }
                    }
                }
            }
        }

        // Build the TIFF file
        var out = Data()

        // Header: II, 42, offset to IFD (after header + pixel data)
        out.append(contentsOf: [0x49, 0x49])                    // II = little-endian
        appendLE16(&out, 42)                                      // magic
        let ifdOffset = UInt32(8 + stripSize)
        appendLE32(&out, ifdOffset)                               // IFD offset

        // Pixel data (immediately after header)
        out.append(pixelData)

        // IFD
        let photoInterp: UInt16 = samplesPerPixel >= 3 ? 2 : 1  // RGB : MinIsBlack
        let sampleFormat: UInt16 = image.components[0].signed ? 2 : 1

        // Tags to write
        struct IFDEntry {
            let tag: UInt16
            let type: UInt16   // 3=SHORT, 4=LONG
            let count: UInt32
            let value: UInt32
        }

        var entries: [IFDEntry] = [
            IFDEntry(tag: 256, type: 4, count: 1, value: UInt32(width)),       // ImageWidth
            IFDEntry(tag: 257, type: 4, count: 1, value: UInt32(height)),      // ImageLength
        ]

        // BitsPerSample: if samplesPerPixel > 1, needs external array
        let bpsArrayOffset: UInt32
        if samplesPerPixel == 1 {
            entries.append(IFDEntry(tag: 258, type: 3, count: 1, value: UInt32(bitsPerSample)))
            bpsArrayOffset = 0
        } else {
            // We'll store the BPS array after the IFD
            bpsArrayOffset = 0xFFFF_FFFE  // placeholder; filled below
            entries.append(IFDEntry(tag: 258, type: 3, count: UInt32(samplesPerPixel), value: bpsArrayOffset))
        }

        entries.append(contentsOf: [
            IFDEntry(tag: 259, type: 3, count: 1, value: 1),                  // Compression = None
            IFDEntry(tag: 262, type: 3, count: 1, value: UInt32(photoInterp)),
            IFDEntry(tag: 273, type: 4, count: 1, value: 8),                  // StripOffsets
            IFDEntry(tag: 277, type: 3, count: 1, value: UInt32(samplesPerPixel)),
            IFDEntry(tag: 278, type: 4, count: 1, value: UInt32(height)),     // RowsPerStrip
            IFDEntry(tag: 279, type: 4, count: 1, value: UInt32(stripSize)),  // StripByteCounts
            IFDEntry(tag: 339, type: 3, count: 1, value: UInt32(sampleFormat)),
        ])

        entries.sort { $0.tag < $1.tag }

        // Compute where extra data goes (after IFD)
        let ifdSize = 2 + entries.count * 12 + 4  // count + entries + next-IFD pointer
        let extraDataOffset = UInt32(ifdOffset) + UInt32(ifdSize)

        // Fix up BitsPerSample offset if multi-sample
        if samplesPerPixel > 1 {
            for i in 0..<entries.count {
                if entries[i].tag == 258 {
                    entries[i] = IFDEntry(tag: 258, type: 3, count: UInt32(samplesPerPixel), value: extraDataOffset)
                }
            }
        }

        // Write IFD
        appendLE16(&out, UInt16(entries.count))
        for entry in entries {
            appendLE16(&out, entry.tag)
            appendLE16(&out, entry.type)
            appendLE32(&out, entry.count)
            appendLE32(&out, entry.value)
        }
        appendLE32(&out, 0)  // Next IFD = none

        // Write extra data: BitsPerSample array
        if samplesPerPixel > 1 {
            for _ in 0..<samplesPerPixel {
                appendLE16(&out, UInt16(bitsPerSample))
            }
        }

        try out.write(to: url)
    }

    // MARK: - Helpers

    private static func readU16(_ data: Data, offset: Int, bigEndian: Bool) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return bigEndian ? (b0 << 8 | b1) : (b1 << 8 | b0)
    }

    private static func readU32(_ data: Data, offset: Int, bigEndian: Bool) -> UInt32 {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return bigEndian
            ? (b0 << 24 | b1 << 16 | b2 << 8 | b3)
            : (b3 << 24 | b2 << 16 | b1 << 8 | b0)
    }

    private static func appendLE16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendLE32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    /// Byte-swap an entire data buffer between big-endian and little-endian.
    private static func byteSwapData(_ data: Data, bytesPerSample: Int) -> Data {
        var result = data
        let count = data.count / bytesPerSample
        for i in 0..<count {
            let base = i * bytesPerSample
            if bytesPerSample == 2 {
                result.swapAt(base, base + 1)
            } else if bytesPerSample == 4 {
                result.swapAt(base, base + 3)
                result.swapAt(base + 1, base + 2)
            }
        }
        return result
    }

    /// De-interleave pixel-interleaved data into separate component planes.
    private static func deinterleaveComponents(
        _ data: Data,
        width: Int,
        height: Int,
        samplesPerPixel: Int,
        bytesPerSample: Int,
        bitsPerSample: Int,
        signed: Bool
    ) -> [J2KComponent] {
        let pixelCount = width * height
        var planes = Array(repeating: Data(count: pixelCount * bytesPerSample), count: samplesPerPixel)

        for i in 0..<pixelCount {
            for s in 0..<samplesPerPixel {
                let srcOffset = (i * samplesPerPixel + s) * bytesPerSample
                let dstOffset = i * bytesPerSample
                for b in 0..<bytesPerSample {
                    if srcOffset + b < data.count {
                        planes[s][dstOffset + b] = data[srcOffset + b]
                    }
                }
            }
        }

        return planes.enumerated().map { (index, planeData) in
            J2KComponent(
                index: index,
                bitDepth: bitsPerSample,
                signed: signed,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: planeData
            )
        }
    }
}
