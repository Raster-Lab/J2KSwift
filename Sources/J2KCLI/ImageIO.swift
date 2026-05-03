//
// ImageIO.swift
// J2KSwift
//
/// Image I/O utilities for loading and saving PGM/PPM/RAW/TIFF/PNG/DICOM files

import Foundation
import J2KCore
import J2KCodec

/// Whether the host platform stores multi-byte values low-byte-first.
/// All Apple-platform targets (macOS / iOS / tvOS / watchOS / visionOS)
/// are little-endian, so this is effectively constant — but the
/// runtime check keeps it correct on any platform Swift ports to.
private let hostIsLittleEndian: Bool = {
    var v: UInt16 = 1
    return withUnsafeBytes(of: &v) { $0.first == 1 }
}()

/// v5.14.1: returns whether `component.data` already holds 16-bit
/// samples in big-endian order (no swap needed before writing to a
/// PGM/PPM file, both of which require big-endian per the spec).
///
/// Resolution order:
///  1. `component.sampleByteOrder` if explicit (e.g. the decoder
///     pipeline tags its output `.bigEndian` since v5.14.1).
///  2. Legacy default — assume host byte order. On Apple Silicon
///     (LE host) the legacy default is "data is in LE" so we'd
///     need to swap; before v5.14.1 the writers always swapped
///     unconditionally and got it right for inputs the user built
///     themselves but wrong for decoder output (which has been
///     pre-swapped to BE). Tagging the decoder's output makes
///     this resolution path correct for the round-trip case
///     without changing behaviour for legacy callers.
private func componentDataIsBigEndian(_ component: J2KComponent) -> Bool {
    if let order = component.sampleByteOrder {
        return order == .bigEndian
    }
    return !hostIsLittleEndian
}

extension J2KCLI {
    /// Load an image from a file (PGM, PPM, TIFF, PNG, DICOM, or RAW format)
    static func loadImage(from path: String) throws -> J2KImage {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])

        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pgm":
            return try loadPGM(data)
        case "ppm":
            return try loadPPM(data)
        case "tiff", "tif":
            return try loadTIFF(data)
        case "png":
            return try loadPNG(data)
        case "dcm", "dicom":
            return try loadDICOM(data)
        case "raw":
            // For RAW files, we need dimensions in filename or separate config
            throw J2KError.invalidParameter("RAW format requires explicit dimensions (not yet implemented)")
        default:
            throw J2KError.invalidParameter("Unsupported image format: \(ext)")
        }
    }

    /// Load an image from stdin, auto-detecting the format from magic bytes.
    static func loadImageFromStdin() async throws -> J2KImage {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty else {
            throw J2KError.invalidParameter("No data received on stdin")
        }
        return try await loadImageFromData(data)
    }

    /// Load an image from raw `Data`, auto-detecting the format from magic bytes.
    static func loadImageFromData(_ data: Data) async throws -> J2KImage {
        // Auto-detect format via magic bytes
        if data.count >= 2 {
            let b0 = data[0], b1 = data[1]

            // PGM (P5)
            if b0 == 0x50 && b1 == 0x35 { return try loadPGM(data) }
            // PPM (P6)
            if b0 == 0x50 && b1 == 0x36 { return try loadPPM(data) }
            // JPEG 2000 codestream (SOC marker 0xFF4F)
            if b0 == 0xFF && b1 == 0x4F {
                let decoder = J2KDecoder()
                return try await decoder.decode(data)
            }
            // TIFF LE
            if b0 == 0x49 && b1 == 0x49 { return try loadTIFF(data) }
            // TIFF BE
            if b0 == 0x4D && b1 == 0x4D { return try loadTIFF(data) }
            // PNG signature
            if b0 == 0x89 && b1 == 0x50 { return try loadPNG(data) }
        }
        // JP2 container (starts with 0x0000000C 6A502020)
        if data.count >= 12 {
            let jp2Sig: [UInt8] = [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20]
            if data.prefix(8).elementsEqual(jp2Sig) {
                let decoder = J2KDecoder()
                return try await decoder.decode(data)
            }
        }
        // DICOM (DICM at offset 128)
        if data.count >= 136 {
            let dicm = String(data: data.subdata(in: 128..<132), encoding: .ascii)
            if dicm == "DICM" { return try loadDICOM(data) }
        }

        throw J2KError.invalidParameter(
            "Cannot auto-detect format from stdin. " +
            "Provide a file with a recognised extension or use a supported format (PGM, PPM, TIFF, PNG, DICOM, J2K, JP2).")
    }

    /// Save an image to a file (PGM, PPM, TIFF, or PNG format)
    static func saveImage(_ image: J2KImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pgm":
            try savePGM(image, to: url)
        case "ppm":
            try savePPM(image, to: url)
        case "tiff", "tif":
            try saveTIFF(image, to: url)
        case "png":
            try savePNG(image, to: url)
        case "raw":
            throw J2KError.invalidParameter("RAW format output not yet implemented")
        default:
            throw J2KError.invalidParameter("Unsupported output format: \(ext)")
        }
    }

    /// Save image data to stdout in the specified format (PNM passthrough for piping).
    static func saveImageToStdout(_ image: J2KImage, format: String?) throws {
        let fmt = (format ?? (image.componentCount >= 3 ? "ppm" : "pgm")).lowercased()

        switch fmt {
        case "pgm":
            let data = try buildPGMData(image)
            FileHandle.standardOutput.write(data)
        case "ppm":
            let data = try buildPPMData(image)
            FileHandle.standardOutput.write(data)
        default:
            // For TIFF/PNG, write to a temporary file then read and pipe
            // This is a fallback; PNM is the recommended pipe format
            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("j2k_pipe.\(fmt)")
            try saveImage(image, to: tmpURL.path)
            let data = try Data(contentsOf: tmpURL)
            FileHandle.standardOutput.write(data)
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    /// Print a message, routing to stderr when stdout is used for data piping.
    static func printInfo(_ message: String, pipeMode: Bool) {
        if pipeMode {
            if let msgData = (message + "\n").data(using: .utf8) {
                FileHandle.standardError.write(msgData)
            }
        } else {
            print(message)
        }
    }

    /// Build PGM data in memory (for piping to stdout).
    static func buildPGMData(_ image: J2KImage) throws -> Data {
        guard image.componentCount == 1 else {
            throw J2KError.invalidParameter("PGM format requires single component (grayscale)")
        }
        let component = image.components[0]
        let maxValue = (1 << component.bitDepth) - 1
        var data = Data()
        let header = "P5\n\(image.width) \(image.height)\n\(maxValue)\n"
        data.append(header.data(using: .ascii)!)
        let bytesPerPixel = component.bitDepth <= 8 ? 1 : 2
        let sourceIsBE = componentDataIsBigEndian(component)
        component.data.withUnsafeBytes { buffer in
            if bytesPerPixel == 1 {
                data.append(contentsOf: buffer)
            } else if sourceIsBE {
                // v5.14.1: source is already in big-endian (decoder
                // path tags its output that way; or user-supplied
                // J2KComponent declared `.bigEndian`). PGM spec
                // requires big-endian, so write as-is.
                data.append(contentsOf: buffer)
            } else {
                // 16-bit: PGM spec requires big-endian byte order.
                // Source is host-order (LE on Apple Silicon); bulk
                // byte-swap into a pre-allocated buffer (avoids
                // 500K+ append calls).
                let pixelCount = image.width * image.height
                var swapped = [UInt8](repeating: 0, count: pixelCount * 2)
                let src = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                swapped.withUnsafeMutableBufferPointer { dst in
                    let d = dst.baseAddress!
                    for i in 0..<pixelCount {
                        let s = i &* 2
                        d[s]     = src[s &+ 1]  // high byte first
                        d[s &+ 1] = src[s]      // low byte second
                    }
                }
                data.append(contentsOf: swapped)
            }
        }
        return data
    }

    /// Build PPM data in memory (for piping to stdout).
    static func buildPPMData(_ image: J2KImage) throws -> Data {
        guard image.componentCount >= 3 else {
            throw J2KError.invalidParameter("PPM format requires at least 3 components (RGB)")
        }
        let r = image.components[0]
        let g = image.components[1]
        let b = image.components[2]
        let bitDepth = max(r.bitDepth, g.bitDepth, b.bitDepth)
        let maxValue = (1 << bitDepth) - 1
        let header = "P6\n\(image.width) \(image.height)\n\(maxValue)\n"
        let headerData = header.data(using: .ascii)!
        let pixelCount = image.width * image.height
        let bytesPerSample = bitDepth <= 8 ? 1 : 2
        let pixelDataSize = pixelCount * 3 * bytesPerSample
        var data = Data(capacity: headerData.count + pixelDataSize)
        data.append(headerData)
        var pixelBytes = [UInt8](repeating: 0, count: pixelDataSize)
        if bytesPerSample == 1 {
            r.data.withUnsafeBytes { rBuf in
                g.data.withUnsafeBytes { gBuf in
                    b.data.withUnsafeBytes { bBuf in
                        let rp = rBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let gp = gBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let bp = bBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        for i in 0..<pixelCount {
                            let off = i &* 3
                            pixelBytes[off]     = i < r.data.count ? rp[i] : 0
                            pixelBytes[off + 1] = i < g.data.count ? gp[i] : 0
                            pixelBytes[off + 2] = i < b.data.count ? bp[i] : 0
                        }
                    }
                }
            }
        } else {
            // v5.14.1: per-component byte order. Decoder tags its
            // output `.bigEndian`; user-supplied components might
            // be either. Read each sample using the right byte
            // order, then re-emit big-endian (PPM spec).
            let rIsBE = componentDataIsBigEndian(r)
            let gIsBE = componentDataIsBigEndian(g)
            let bIsBE = componentDataIsBigEndian(b)
            r.data.withUnsafeBytes { rBuf in
                g.data.withUnsafeBytes { gBuf in
                    b.data.withUnsafeBytes { bBuf in
                        let rp = rBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let gp = gBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let bp = bBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        @inline(__always)
                        func read16(_ p: UnsafePointer<UInt8>, _ idx: Int, _ isBE: Bool) -> Int {
                            let lo = isBE ? Int(p[idx + 1]) : Int(p[idx])
                            let hi = isBE ? Int(p[idx])     : Int(p[idx + 1])
                            return min((hi << 8) | lo, maxValue)
                        }
                        for i in 0..<pixelCount {
                            let idx = i * 2
                            let rVal = idx + 1 < r.data.count ? read16(rp, idx, rIsBE) : 0
                            let gVal = idx + 1 < g.data.count ? read16(gp, idx, gIsBE) : 0
                            let bVal = idx + 1 < b.data.count ? read16(bp, idx, bIsBE) : 0
                            let off = i * 6
                            pixelBytes[off]     = UInt8(rVal >> 8)
                            pixelBytes[off + 1] = UInt8(rVal & 0xFF)
                            pixelBytes[off + 2] = UInt8(gVal >> 8)
                            pixelBytes[off + 3] = UInt8(gVal & 0xFF)
                            pixelBytes[off + 4] = UInt8(bVal >> 8)
                            pixelBytes[off + 5] = UInt8(bVal & 0xFF)
                        }
                    }
                }
            }
        }
        data.append(contentsOf: pixelBytes)
        return data
    }

    /// Load a PGM (Portable GrayMap) file.
    static func loadPGM(_ data: Data) throws -> J2KImage {
        guard data.count >= 2, data[0] == 0x50, data[1] == 0x35 else {
            throw J2KError.invalidParameter("Invalid PGM file: wrong magic number")
        }

        var offset = 2
        guard
            let width = readPNMInt(from: data, offset: &offset),
            let height = readPNMInt(from: data, offset: &offset)
        else {
            throw J2KError.invalidParameter("Invalid PGM file: missing dimensions")
        }

        guard let maxValue = readPNMInt(from: data, offset: &offset) else {
            throw J2KError.invalidParameter("Invalid PGM file: missing max value")
        }

        try consumePNMHeaderTerminator(in: data, offset: &offset)

        let bitDepth: Int = {
            if maxValue <= 255 { return 8 }
            var bits = 0
            var value = maxValue
            while value > 0 {
                value >>= 1
                bits += 1
            }
            return bits
        }()

        let bytesPerPixel = bitDepth <= 8 ? 1 : 2
        let expectedBytes = width * height * bytesPerPixel
        guard offset + expectedBytes <= data.count else {
            throw J2KError.invalidParameter("Invalid PGM file: insufficient pixel data")
        }

        let pixelData = Data(data[offset..<(offset + expectedBytes)])

        let component = J2KComponent(
            index: 0,
            bitDepth: bitDepth,
            signed: false,
            width: width,
            height: height,
            subsamplingX: 1,
            subsamplingY: 1,
            data: pixelData
        )

        // Create image
        return J2KImage(
            width: width,
            height: height,
            components: [component],
            colorSpace: .grayscale
        )
    }

    /// Load a PPM (Portable PixMap) file.
    static func loadPPM(_ data: Data) throws -> J2KImage {
        guard data.count >= 2, data[0] == 0x50, data[1] == 0x36 else {
            throw J2KError.invalidParameter("Invalid PPM file: wrong magic number")
        }

        var offset = 2
        guard
            let width = readPNMInt(from: data, offset: &offset),
            let height = readPNMInt(from: data, offset: &offset)
        else {
            throw J2KError.invalidParameter("Invalid PPM file: missing dimensions")
        }

        guard let maxValue = readPNMInt(from: data, offset: &offset) else {
            throw J2KError.invalidParameter("Invalid PPM file: missing max value")
        }

        try consumePNMHeaderTerminator(in: data, offset: &offset)

        let bitDepth: Int = {
            if maxValue <= 255 { return 8 }
            var bits = 0
            var value = maxValue
            while value > 0 {
                value >>= 1
                bits += 1
            }
            return bits
        }()

        let bytesPerPixel = bitDepth <= 8 ? 1 : 2
        let expectedBytes = width * height * 3 * bytesPerPixel
        guard offset + expectedBytes <= data.count else {
            throw J2KError.invalidParameter("Invalid PPM file: insufficient pixel data")
        }

        let pixelData = Data(data[offset..<(offset + expectedBytes)])

        // De-interleave into separate component Data
        var rData = Data(count: width * height * bytesPerPixel)
        var gData = Data(count: width * height * bytesPerPixel)
        var bData = Data(count: width * height * bytesPerPixel)

        if bytesPerPixel == 1 {
            for i in 0..<(width * height) {
                rData[i] = pixelData[i * 3]
                gData[i] = pixelData[i * 3 + 1]
                bData[i] = pixelData[i * 3 + 2]
            }
        } else {
            for i in 0..<(width * height) {
                rData[i * 2] = pixelData[i * 6]
                rData[i * 2 + 1] = pixelData[i * 6 + 1]
                gData[i * 2] = pixelData[i * 6 + 2]
                gData[i * 2 + 1] = pixelData[i * 6 + 3]
                bData[i * 2] = pixelData[i * 6 + 4]
                bData[i * 2 + 1] = pixelData[i * 6 + 5]
            }
        }

        // Create components
        let components = [
            J2KComponent(
                index: 0, bitDepth: bitDepth, signed: false,
                width: width, height: height,
                subsamplingX: 1, subsamplingY: 1, data: rData),
            J2KComponent(
                index: 1, bitDepth: bitDepth, signed: false,
                width: width, height: height,
                subsamplingX: 1, subsamplingY: 1, data: gData),
            J2KComponent(
                index: 2, bitDepth: bitDepth, signed: false,
                width: width, height: height,
                subsamplingX: 1, subsamplingY: 1, data: bData)
        ]

        // Create image
        return J2KImage(
            width: width,
            height: height,
            components: components,
            colorSpace: .sRGB
        )
    }

    /// Save image as PGM
    static func savePGM(_ image: J2KImage, to url: URL) throws {
        guard image.componentCount == 1 else {
            throw J2KError.invalidParameter("PGM format requires single component (grayscale)")
        }

        let component = image.components[0]
        let maxValue = (1 << component.bitDepth) - 1

        var data = Data()

        // Write header
        let header = "P5\n\(image.width) \(image.height)\n\(maxValue)\n"
        data.append(header.data(using: .ascii)!)

        // Write pixel data efficiently
        let bytesPerPixel = component.bitDepth <= 8 ? 1 : 2
        let sourceIsBE = componentDataIsBigEndian(component)
        component.data.withUnsafeBytes { buffer in
            if bytesPerPixel == 1 {
                // 8-bit: copy directly
                data.append(contentsOf: buffer)
            } else if sourceIsBE {
                // v5.14.1: source is already big-endian; PGM spec
                // requires big-endian, so write as-is.
                data.append(contentsOf: buffer)
            } else {
                // 16-bit: PGM spec requires big-endian byte order.
                // Source is host-order; bulk byte-swap into a
                // pre-allocated buffer.
                let pixelCount = image.width * image.height
                var swapped = [UInt8](repeating: 0, count: pixelCount * 2)
                let src = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
                swapped.withUnsafeMutableBufferPointer { dst in
                    let d = dst.baseAddress!
                    for i in 0..<pixelCount {
                        let s = i &* 2
                        d[s]     = src[s &+ 1]  // high byte first
                        d[s &+ 1] = src[s]      // low byte second
                    }
                }
                data.append(contentsOf: swapped)
            }
        }

        try data.write(to: url)
    }

    /// Save image as PPM
    static func savePPM(_ image: J2KImage, to url: URL) throws {
        guard image.componentCount >= 3 else {
            throw J2KError.invalidParameter("PPM format requires at least 3 components (RGB)")
        }

        let r = image.components[0]
        let g = image.components[1]
        let b = image.components[2]

        let bitDepth = max(r.bitDepth, g.bitDepth, b.bitDepth)
        let maxValue = (1 << bitDepth) - 1

        // Write header
        let header = "P6\n\(image.width) \(image.height)\n\(maxValue)\n"
        let headerData = header.data(using: .ascii)!

        let pixelCount = image.width * image.height
        let bytesPerSample = bitDepth <= 8 ? 1 : 2
        let pixelDataSize = pixelCount * 3 * bytesPerSample

        // Pre-allocate full buffer and write pixel data in bulk
        var data = Data(capacity: headerData.count + pixelDataSize)
        data.append(headerData)

        if bytesPerSample == 1 {
            // 8-bit: bulk interleave R, G, B components
            var pixelBytes = [UInt8](repeating: 0, count: pixelDataSize)
            r.data.withUnsafeBytes { rBuf in
                g.data.withUnsafeBytes { gBuf in
                    b.data.withUnsafeBytes { bBuf in
                        let rp = rBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let gp = gBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let bp = bBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        for i in 0..<pixelCount {
                            let rVal = Int(rp[i])
                            let gVal = Int(gp[i])
                            let bVal = Int(bp[i])
                            let off = i &* 3
                            pixelBytes[off]     = UInt8(clamping: min(rVal, maxValue))
                            pixelBytes[off + 1] = UInt8(clamping: min(gVal, maxValue))
                            pixelBytes[off + 2] = UInt8(clamping: min(bVal, maxValue))
                        }
                    }
                }
            }
            data.append(contentsOf: pixelBytes)
        } else {
            // 16-bit: big-endian interleave. v5.14.1: per-component
            // byte order so decoder output (tagged BE) reads
            // correctly, matching the buildPPMData fix.
            let rIsBE = componentDataIsBigEndian(r)
            let gIsBE = componentDataIsBigEndian(g)
            let bIsBE = componentDataIsBigEndian(b)
            var pixelBytes = [UInt8](repeating: 0, count: pixelDataSize)
            r.data.withUnsafeBytes { rBuf in
                g.data.withUnsafeBytes { gBuf in
                    b.data.withUnsafeBytes { bBuf in
                        let rp = rBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let gp = gBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        let bp = bBuf.baseAddress!.assumingMemoryBound(to: UInt8.self)
                        @inline(__always)
                        func read16(_ p: UnsafePointer<UInt8>, _ idx: Int, _ isBE: Bool) -> Int {
                            let lo = isBE ? Int(p[idx + 1]) : Int(p[idx])
                            let hi = isBE ? Int(p[idx])     : Int(p[idx + 1])
                            return min((hi << 8) | lo, maxValue)
                        }
                        for i in 0..<pixelCount {
                            let idx = i * 2
                            let rVal = read16(rp, idx, rIsBE)
                            let gVal = read16(gp, idx, gIsBE)
                            let bVal = read16(bp, idx, bIsBE)
                            let off = i * 6
                            pixelBytes[off]     = UInt8(rVal >> 8)
                            pixelBytes[off + 1] = UInt8(rVal & 0xFF)
                            pixelBytes[off + 2] = UInt8(gVal >> 8)
                            pixelBytes[off + 3] = UInt8(gVal & 0xFF)
                            pixelBytes[off + 4] = UInt8(bVal >> 8)
                            pixelBytes[off + 5] = UInt8(bVal & 0xFF)
                        }
                    }
                }
            }
            data.append(contentsOf: pixelBytes)
        }

        try data.write(to: url)
    }

    @inline(__always)
    private static func isPNMWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    /// Advances past ASCII whitespace and comment lines in a binary PNM stream.
    private static func skipPNMWhitespaceAndComments(in data: Data, offset: inout Int) {
        while offset < data.count {
            let byte = data[offset]
            if isPNMWhitespace(byte) {
                offset += 1
                continue
            }
            if byte == 0x23 { // '#'
                while offset < data.count && data[offset] != 0x0A {
                    offset += 1
                }
                continue
            }
            break
        }
    }

    /// Reads a decimal integer token from a binary PNM header.
    private static func readPNMInt(from data: Data, offset: inout Int) -> Int? {
        skipPNMWhitespaceAndComments(in: data, offset: &offset)
        guard offset < data.count else { return nil }

        var value = 0
        var sawDigit = false

        while offset < data.count {
            let byte = data[offset]
            guard byte >= 0x30 && byte <= 0x39 else { break }
            sawDigit = true
            value = value * 10 + Int(byte - 0x30)
            offset += 1
        }

        return sawDigit ? value : nil
    }

    /// Consumes the single whitespace separator between the PNM header and the raster data.
    private static func consumePNMHeaderTerminator(in data: Data, offset: inout Int) throws {
        guard offset < data.count, isPNMWhitespace(data[offset]) else {
            throw J2KError.invalidParameter("Invalid PNM file: missing raster separator")
        }

        // Binary PNM requires exactly one header separator byte. Preserve any
        // following bytes verbatim because they belong to the pixel payload.
        offset += 1
        if offset < data.count, data[offset - 1] == 0x0D, data[offset] == 0x0A {
            offset += 1
        }
    }
}
