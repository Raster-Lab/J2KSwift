//
// PNGSupport.swift
// J2KSwift
//
/// Minimal PNG reader/writer for 8-bit and 16-bit greyscale, RGB, and RGBA.
///
/// Uses zlib (available on all supported platforms) for IDAT compression.
/// No dependency on libpng.

import Foundation
import J2KCore
import CZlib

extension J2KCLI {

    // MARK: - PNG Reading

    /// Load a PNG file into a `J2KImage`.
    ///
    /// Supports 8-bit and 16-bit greyscale, greyscale+alpha, RGB, and RGBA.
    /// Rejects interlaced and palette-based PNG.
    static func loadPNG(_ data: Data) throws -> J2KImage {
        // Verify PNG signature
        let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 8,
              data.prefix(8).elementsEqual(pngSignature) else {
            throw J2KError.invalidParameter("Invalid PNG: wrong signature")
        }

        // Parse chunks
        var offset = 8
        var width = 0, height = 0, bitDepth = 0, colourType = 0, interlace = 0
        var idatData = Data()
        var ihdrFound = false

        while offset + 8 <= data.count {
            let chunkLen = Int(readBE32(data, offset: offset))
            let chunkType = String(data: data.subdata(in: (offset + 4)..<(offset + 8)), encoding: .ascii) ?? ""
            let chunkDataStart = offset + 8
            let chunkEnd = chunkDataStart + chunkLen + 4  // +4 for CRC

            guard chunkEnd <= data.count else { break }

            switch chunkType {
            case "IHDR":
                guard chunkLen >= 13 else {
                    throw J2KError.invalidParameter("Invalid PNG IHDR chunk")
                }
                width      = Int(readBE32(data, offset: chunkDataStart))
                height     = Int(readBE32(data, offset: chunkDataStart + 4))
                bitDepth   = Int(data[chunkDataStart + 8])
                colourType = Int(data[chunkDataStart + 9])
                interlace  = Int(data[chunkDataStart + 12])
                ihdrFound = true

            case "IDAT":
                idatData.append(data.subdata(in: chunkDataStart..<(chunkDataStart + chunkLen)))

            case "IEND":
                break

            default:
                break
            }

            offset = chunkEnd
        }

        guard ihdrFound else {
            throw J2KError.invalidParameter("Invalid PNG: missing IHDR chunk")
        }
        guard interlace == 0 else {
            throw J2KError.invalidParameter("Interlaced PNG is not supported")
        }
        guard bitDepth == 8 || bitDepth == 16 else {
            throw J2KError.invalidParameter("Unsupported PNG bit depth: \(bitDepth). Only 8 and 16 are supported.")
        }
        guard colourType != 3 else {
            throw J2KError.invalidParameter("Indexed-colour PNG is not supported; convert to RGB first.")
        }

        let channels: Int
        switch colourType {
        case 0: channels = 1  // greyscale
        case 2: channels = 3  // RGB
        case 4: channels = 2  // greyscale + alpha
        case 6: channels = 4  // RGBA
        default:
            throw J2KError.invalidParameter("Unsupported PNG colour type: \(colourType)")
        }

        // Decompress IDAT
        let decompressed = try zlibDecompress(idatData)

        // Reverse row filters
        let bytesPerPixel = channels * (bitDepth / 8)
        let scanlineBytes = width * bytesPerPixel
        let expectedSize = height * (1 + scanlineBytes)  // 1 filter byte per row

        guard decompressed.count >= expectedSize else {
            throw J2KError.invalidParameter("PNG: decompressed IDAT too small (\(decompressed.count) < \(expectedSize))")
        }

        var unfiltered = Data(count: height * scanlineBytes)
        let bpp = bytesPerPixel  // bytes per complete pixel

        for row in 0..<height {
            let filterByte = decompressed[row * (1 + scanlineBytes)]
            let srcRow = row * (1 + scanlineBytes) + 1
            let dstRow = row * scanlineBytes

            for x in 0..<scanlineBytes {
                let raw = decompressed[srcRow + x]

                let a: UInt8 = x >= bpp ? unfiltered[dstRow + x - bpp] : 0
                let b: UInt8 = row > 0 ? unfiltered[(row - 1) * scanlineBytes + x] : 0
                let c: UInt8 = (row > 0 && x >= bpp) ? unfiltered[(row - 1) * scanlineBytes + x - bpp] : 0

                let recon: UInt8
                switch filterByte {
                case 0: recon = raw                                                // None
                case 1: recon = raw &+ a                                           // Sub
                case 2: recon = raw &+ b                                           // Up
                case 3: recon = raw &+ UInt8((UInt16(a) + UInt16(b)) / 2)          // Average
                case 4: recon = raw &+ paethPredictor(a, b, c)                     // Paeth
                default: recon = raw
                }

                unfiltered[dstRow + x] = recon
            }
        }

        // For 16-bit PNG, data is big-endian — convert to little-endian (host)
        if bitDepth == 16 {
            let sampleCount = width * height * channels
            for i in 0..<sampleCount {
                let idx = i * 2
                unfiltered.swapAt(idx, idx + 1)
            }
        }

        // De-interleave into component planes
        let bytesPerSample = bitDepth / 8
        let pixelCount = width * height
        var components: [J2KComponent] = []

        // v5.14.2: tag PNG-loaded 16-bit components with
        // `.littleEndian`. The reader explicitly swaps PNG's
        // big-endian on-disk layout to host-LE above, so the
        // resulting `J2KComponent.data` is in LE byte order.
        // Without this tag the encoder must infer (fragile) and
        // writers can't tell whether the data is in spec format.
        let bo: J2KComponent.ByteOrder? = bitDepth > 8 ? .littleEndian : nil

        for ch in 0..<channels {
            var planeData = Data(count: pixelCount * bytesPerSample)
            for i in 0..<pixelCount {
                let srcOffset = (i * channels + ch) * bytesPerSample
                let dstOffset = i * bytesPerSample
                for b in 0..<bytesPerSample {
                    planeData[dstOffset + b] = unfiltered[srcOffset + b]
                }
            }
            components.append(J2KComponent(
                index: ch,
                bitDepth: bitDepth,
                signed: false,
                width: width,
                height: height,
                subsamplingX: 1,
                subsamplingY: 1,
                data: planeData,
                sampleByteOrder: bo
            ))
        }

        let colorSpace: J2KColorSpace = channels >= 3 ? .sRGB : .grayscale

        return J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: colorSpace
        )
    }

    // MARK: - PNG Writing

    /// Save a `J2KImage` as a PNG file.
    ///
    /// Supports 1, 2, 3, or 4 components at 8 or 16 bits per channel.
    static func savePNG(_ image: J2KImage, to url: URL) throws {
        let channels = image.componentCount
        let bitDepth = image.components[0].bitDepth
        let width = image.width
        let height = image.height

        guard bitDepth == 8 || bitDepth == 16 else {
            throw J2KError.invalidParameter(
                "PNG output requires 8 or 16 bits per channel (got \(bitDepth))")
        }
        guard channels >= 1 && channels <= 4 else {
            throw J2KError.invalidParameter(
                "PNG output requires 1–4 components (got \(channels))")
        }

        let colourType: UInt8
        switch channels {
        case 1: colourType = 0   // greyscale
        case 2: colourType = 4   // greyscale + alpha
        case 3: colourType = 2   // RGB
        case 4: colourType = 6   // RGBA
        default: colourType = 2
        }

        let bytesPerSample = bitDepth / 8
        let scanlineBytes = width * channels * bytesPerSample

        // v5.14.2: per-component byte order. PNG spec requires BE
        // for 16-bit; check `sampleByteOrder` for each channel —
        // the decoder produces BE, the PNG loader produces LE,
        // user-built components could be either.
        let componentIsBE: [Bool] = (0..<channels).map { ch in
            componentDataIsBigEndian(image.components[ch])
        }

        // bpp is the per-pixel byte count, used as the
        // left-pixel-reference offset for Sub / Average / Paeth.
        let bpp = channels * bytesPerSample

        // Build filtered scanlines.
        //
        // v5.17.0 re-implementation: Sub / Up / Average / Paeth filters
        // with proper ORIGINAL-byte semantics. v5.14.2 had switched to
        // filter type 0 (None) after catching the pre-v5.14.2 bug
        // where Sub used the FILTERED byte for the subtraction
        // reference (PNG spec requires the ORIGINAL byte). The fix
        // here keeps the v5.14.2 correctness guarantee while
        // recovering compression efficiency:
        //   1. Build the full row of raw (unfiltered) sample bytes
        //      first, in PNG byte-order (BE for 16-bit).
        //   2. Compute SAD (sum of absolute differences) for each
        //      filter type — the standard PNG MAE heuristic.
        //   3. Pick the filter with smallest SAD; emit it.
        // Pixel byte references for Sub / Up / Avg / Paeth are read
        // from the ORIGINAL row arrays, never from the filtered
        // output. The Phase 1 / v5.14.2 PNG round-trip regression
        // test catches any reintroduction of the original bug.
        var filtered = Data(capacity: height * (1 + scanlineBytes))
        var prevRowRaw = [UInt8](repeating: 0, count: scanlineBytes)
        var currentRowRaw = [UInt8](repeating: 0, count: scanlineBytes)

        for row in 0..<height {
            // 1. Materialise the unfiltered scanline.
            for x in 0..<scanlineBytes {
                let pixelInRow = x / (channels * bytesPerSample)
                let remainder = x % (channels * bytesPerSample)
                let ch = remainder / bytesPerSample
                let byteInSample = remainder % bytesPerSample

                let comp = image.components[ch]
                let pixelIndex = row * width + pixelInRow

                var sampleByte: UInt8 = 0
                if bitDepth == 16 {
                    let leIdx = pixelIndex * 2
                    if componentIsBE[ch] {
                        sampleByte = leIdx + byteInSample < comp.data.count
                            ? comp.data[leIdx + byteInSample] : 0
                    } else {
                        // Source is LE: swap to PNG BE.
                        if byteInSample == 0 {
                            sampleByte = leIdx + 1 < comp.data.count ? comp.data[leIdx + 1] : 0
                        } else {
                            sampleByte = leIdx < comp.data.count ? comp.data[leIdx] : 0
                        }
                    }
                } else {
                    let srcIdx = pixelIndex * bytesPerSample + byteInSample
                    sampleByte = srcIdx < comp.data.count ? comp.data[srcIdx] : 0
                }
                currentRowRaw[x] = sampleByte
            }

            // 2. Choose the best filter via the MAE heuristic. For
            //    each candidate compute sum of absolute (signed-byte)
            //    deltas — the conventional PNG selection metric.
            //    Lower SAD on natural images correlates with better
            //    zlib compression of the filtered scanline.
            var bestFilter: UInt8 = 0
            var bestSAD = Int.max
            var bestFiltered = [UInt8](repeating: 0, count: scanlineBytes)
            var scratch = [UInt8](repeating: 0, count: scanlineBytes)

            for filterType: UInt8 in 0...4 {
                applyFilter(
                    type: filterType,
                    row: currentRowRaw,
                    prevRow: prevRowRaw,
                    bpp: bpp,
                    out: &scratch)
                // SAD over signed-byte interpretation (per PNG spec
                // §12.8 minimum-sum-of-absolute-differences heuristic).
                var sad = 0
                for b in scratch {
                    sad += abs(Int(Int8(bitPattern: b)))
                }
                if sad < bestSAD {
                    bestSAD = sad
                    bestFilter = filterType
                    swap(&bestFiltered, &scratch)
                }
            }

            // 3. Emit filter type byte then the filtered scanline.
            filtered.append(bestFilter)
            filtered.append(contentsOf: bestFiltered)

            // Slide the row buffer for the next iteration.
            swap(&prevRowRaw, &currentRowRaw)
        }

        // Compress with zlib
        let compressed = try zlibCompress(filtered)

        // Build PNG file
        var out = Data()

        // Signature
        out.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        // IHDR
        var ihdr = Data()
        appendBE32(&ihdr, UInt32(width))
        appendBE32(&ihdr, UInt32(height))
        ihdr.append(UInt8(bitDepth))
        ihdr.append(colourType)
        ihdr.append(0)  // compression method
        ihdr.append(0)  // filter method
        ihdr.append(0)  // interlace method
        writePNGChunk(&out, type: "IHDR", data: ihdr)

        // IDAT chunk(s) — split at 32 KB
        let chunkSize = 32768
        var idatOffset = 0
        while idatOffset < compressed.count {
            let end = min(idatOffset + chunkSize, compressed.count)
            writePNGChunk(&out, type: "IDAT", data: compressed.subdata(in: idatOffset..<end))
            idatOffset = end
        }

        // IEND
        writePNGChunk(&out, type: "IEND", data: Data())

        try out.write(to: url)
    }

    // MARK: - PNG Helpers

    private static func readBE32(_ data: Data, offset: Int) -> UInt32 {
        return UInt32(data[offset]) << 24
             | UInt32(data[offset + 1]) << 16
             | UInt32(data[offset + 2]) << 8
             | UInt32(data[offset + 3])
    }

    private static func appendBE32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
    }

    private static func writePNGChunk(_ out: inout Data, type: String, data: Data) {
        appendBE32(&out, UInt32(data.count))
        guard let typeData = type.data(using: .ascii) else { return }
        out.append(typeData)
        out.append(data)
        // CRC over type + data
        var crcInput = typeData
        crcInput.append(data)
        let crc = crc32PNG(crcInput)
        appendBE32(&out, crc)
    }

    /// Paeth predictor function used by PNG filtering.
    private static func paethPredictor(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8 {
        let ia = Int(a), ib = Int(b), ic = Int(c)
        let p = ia + ib - ic
        let pa = abs(p - ia)
        let pb = abs(p - ib)
        let pc = abs(p - ic)
        if pa <= pb && pa <= pc { return a }
        if pb <= pc { return b }
        return c
    }

    /// Apply one of the five PNG filter types to a row of ORIGINAL
    /// (unfiltered) bytes, writing the filtered bytes into `out`.
    /// All references to neighboring bytes use the original sample
    /// values per PNG spec §9.2 — never the filtered output.
    ///
    /// - Parameters:
    ///   - type: Filter type (0=None, 1=Sub, 2=Up, 3=Average, 4=Paeth).
    ///   - row: This row's raw, unfiltered sample bytes.
    ///   - prevRow: Previous row's raw bytes (zeros for the first row).
    ///   - bpp: Bytes per pixel, used as the filter's left-pixel offset.
    ///   - out: Output buffer; must have count == row.count.
    private static func applyFilter(
        type: UInt8,
        row: [UInt8],
        prevRow: [UInt8],
        bpp: Int,
        out: inout [UInt8]
    ) {
        let n = row.count
        switch type {
        case 0:  // None — Filt(x) = Orig(x)
            for x in 0..<n { out[x] = row[x] }
        case 1:  // Sub — Filt(x) = Orig(x) - Orig(x - bpp)
            for x in 0..<n {
                let a: UInt8 = x >= bpp ? row[x - bpp] : 0
                out[x] = row[x] &- a
            }
        case 2:  // Up — Filt(x) = Orig(x) - Prior(x)
            for x in 0..<n {
                let b: UInt8 = prevRow[x]
                out[x] = row[x] &- b
            }
        case 3:  // Average — Filt(x) = Orig(x) - floor((Orig(x-bpp) + Prior(x)) / 2)
            for x in 0..<n {
                let a: Int = x >= bpp ? Int(row[x - bpp]) : 0
                let b: Int = Int(prevRow[x])
                let avg = UInt8((a + b) >> 1)
                out[x] = row[x] &- avg
            }
        case 4:  // Paeth — Filt(x) = Orig(x) - Paeth(Orig(x-bpp), Prior(x), Prior(x-bpp))
            for x in 0..<n {
                let a: UInt8 = x >= bpp ? row[x - bpp] : 0
                let b: UInt8 = prevRow[x]
                let c: UInt8 = x >= bpp ? prevRow[x - bpp] : 0
                out[x] = row[x] &- paethPredictor(a, b, c)
            }
        default:
            // Unknown filter type — fall through to None.
            for x in 0..<n { out[x] = row[x] }
        }
    }

    /// CRC-32 used by PNG (same polynomial as zlib crc32).
    private static func crc32PNG(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        let table = makeCRC32Table()
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func makeCRC32Table() -> [UInt32] {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                if c & 1 != 0 {
                    c = 0xEDB8_8320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            table[n] = c
        }
        return table
    }

    // MARK: - zlib wrappers

    /// Decompress zlib-compressed data (PNG IDAT uses zlib, not raw deflate).
    static func zlibDecompress(_ data: Data) throws -> Data {
        var stream = z_stream()

        let inputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        data.copyBytes(to: inputPtr, count: data.count)
        defer { inputPtr.deallocate() }

        stream.next_in = inputPtr
        stream.avail_in = UInt32(data.count)

        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw J2KError.internalError("zlib inflateInit failed")
        }
        defer { inflateEnd(&stream) }

        var result = Data()
        let bufSize = 65536
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { outBuf.deallocate() }

        repeat {
            stream.next_out = outBuf
            stream.avail_out = UInt32(bufSize)
            let ret = inflate(&stream, Z_NO_FLUSH)
            guard ret == Z_OK || ret == Z_STREAM_END else {
                throw J2KError.internalError("zlib inflate error: \(ret)")
            }
            let have = bufSize - Int(stream.avail_out)
            result.append(outBuf, count: have)
            if ret == Z_STREAM_END { break }
        } while stream.avail_out == 0

        return result
    }

    /// Compress data using zlib (for PNG IDAT).
    static func zlibCompress(_ data: Data) throws -> Data {
        var stream = z_stream()

        let inputPtr = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        data.copyBytes(to: inputPtr, count: data.count)
        defer { inputPtr.deallocate() }

        stream.next_in = inputPtr
        stream.avail_in = UInt32(data.count)

        guard deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw J2KError.internalError("zlib deflateInit failed")
        }
        defer { deflateEnd(&stream) }

        var result = Data()
        let bufSize = 65536
        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { outBuf.deallocate() }

        repeat {
            stream.next_out = outBuf
            stream.avail_out = UInt32(bufSize)
            let ret = deflate(&stream, Z_FINISH)
            guard ret == Z_OK || ret == Z_STREAM_END else {
                throw J2KError.internalError("zlib deflate error: \(ret)")
            }
            let have = bufSize - Int(stream.avail_out)
            result.append(outBuf, count: have)
            if ret == Z_STREAM_END { break }
        } while true

        return result
    }
}
