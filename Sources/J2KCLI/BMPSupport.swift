//
// BMPSupport.swift
// J2KSwift
//
/// Minimal BMP reader for 8-bit greyscale, 24-bit RGB, and 32-bit RGBA.
///
/// Handles standard BITMAPINFOHEADER (40-byte DIB header) with bottom-up
/// and top-down row order. No external dependencies.

import Foundation
import J2KCore

extension J2KCLI {

    // MARK: - BMP Reading

    /// Load a BMP file into a `J2KImage`.
    ///
    /// Supports:
    /// - 8-bit indexed/greyscale (256-entry palette)
    /// - 24-bit uncompressed RGB
    /// - 32-bit uncompressed RGBA
    ///
    /// - Parameter data: Raw BMP file data.
    /// - Returns: A `J2KImage` with 8-bit components.
    /// - Throws: ``J2KError`` if the format is unsupported or the data is malformed.
    static func loadBMP(_ data: Data) throws -> J2KImage {
        guard data.count >= 54 else {
            throw J2KError.invalidParameter("BMP file too small")
        }

        // File header (14 bytes)
        guard data[0] == 0x42, data[1] == 0x4D else {  // "BM"
            throw J2KError.invalidParameter("Invalid BMP: wrong magic bytes")
        }

        let dataOffset = readLE32(data, offset: 10)

        // DIB header
        let dibSize = readLE32(data, offset: 14)
        guard dibSize >= 40 else {
            throw J2KError.invalidParameter("Unsupported BMP DIB header size: \(dibSize)")
        }

        let rawWidth  = Int(Int32(bitPattern: readLE32(data, offset: 18)))
        let rawHeight = Int(Int32(bitPattern: readLE32(data, offset: 22)))
        let width  = abs(rawWidth)
        let height = abs(rawHeight)
        let topDown = rawHeight < 0

        guard width > 0, height > 0 else {
            throw J2KError.invalidDimensions("BMP dimensions must be positive: \(width)×\(height)")
        }

        let bitsPerPixel = Int(readLE16(data, offset: 28))
        let compression  = readLE32(data, offset: 30)

        guard compression == 0 || compression == 3 else {
            throw J2KError.invalidParameter("Unsupported BMP compression: \(compression)")
        }

        let pixelDataStart = Int(dataOffset)

        switch bitsPerPixel {
        case 8:
            return try loadBMP8(data, width: width, height: height,
                                topDown: topDown, pixelDataStart: pixelDataStart,
                                dibHeaderOffset: 14, dibSize: Int(dibSize))
        case 24:
            return try loadBMP24(data, width: width, height: height,
                                 topDown: topDown, pixelDataStart: pixelDataStart)
        case 32:
            return try loadBMP32(data, width: width, height: height,
                                 topDown: topDown, pixelDataStart: pixelDataStart)
        default:
            throw J2KError.invalidParameter("Unsupported BMP bit depth: \(bitsPerPixel)")
        }
    }

    // MARK: - 8-bit BMP

    private static func loadBMP8(
        _ data: Data, width: Int, height: Int,
        topDown: Bool, pixelDataStart: Int,
        dibHeaderOffset: Int, dibSize: Int
    ) throws -> J2KImage {
        // Read palette (256 entries × 4 bytes each, BGRA)
        let paletteOffset = dibHeaderOffset + dibSize
        guard data.count >= paletteOffset + 256 * 4 else {
            throw J2KError.invalidParameter("BMP 8-bit: palette data missing")
        }

        var paletteR = [UInt8](repeating: 0, count: 256)
        var paletteG = [UInt8](repeating: 0, count: 256)
        var paletteB = [UInt8](repeating: 0, count: 256)
        for i in 0..<256 {
            let off = paletteOffset + i * 4
            paletteB[i] = data[off]
            paletteG[i] = data[off + 1]
            paletteR[i] = data[off + 2]
        }

        // Check if palette is greyscale
        var isGreyscale = true
        for i in 0..<256 {
            if paletteR[i] != paletteG[i] || paletteG[i] != paletteB[i] {
                isGreyscale = false
                break
            }
        }

        let rowStride = (width + 3) & ~3  // Rows padded to 4-byte boundary

        if isGreyscale {
            var grey = Data(count: width * height)
            for row in 0..<height {
                let srcRow = topDown ? row : (height - 1 - row)
                let srcOff = pixelDataStart + srcRow * rowStride
                let dstOff = row * width
                for x in 0..<width {
                    let idx = Int(data[srcOff + x])
                    grey[dstOff + x] = paletteR[idx]
                }
            }
            let comp = J2KComponent(index: 0, bitDepth: 8, width: width, height: height, data: grey)
            return J2KImage(width: width, height: height, components: [comp], colorSpace: .grayscale)
        } else {
            var rData = Data(count: width * height)
            var gData = Data(count: width * height)
            var bData = Data(count: width * height)
            for row in 0..<height {
                let srcRow = topDown ? row : (height - 1 - row)
                let srcOff = pixelDataStart + srcRow * rowStride
                let dstOff = row * width
                for x in 0..<width {
                    let idx = Int(data[srcOff + x])
                    rData[dstOff + x] = paletteR[idx]
                    gData[dstOff + x] = paletteG[idx]
                    bData[dstOff + x] = paletteB[idx]
                }
            }
            let components = [
                J2KComponent(index: 0, bitDepth: 8, width: width, height: height, data: rData),
                J2KComponent(index: 1, bitDepth: 8, width: width, height: height, data: gData),
                J2KComponent(index: 2, bitDepth: 8, width: width, height: height, data: bData),
            ]
            return J2KImage(width: width, height: height, components: components, colorSpace: .sRGB)
        }
    }

    // MARK: - 24-bit BMP

    private static func loadBMP24(
        _ data: Data, width: Int, height: Int,
        topDown: Bool, pixelDataStart: Int
    ) throws -> J2KImage {
        let rowStride = (width * 3 + 3) & ~3  // Padded to 4-byte boundary

        var rData = Data(count: width * height)
        var gData = Data(count: width * height)
        var bData = Data(count: width * height)

        for row in 0..<height {
            let srcRow = topDown ? row : (height - 1 - row)
            let srcOff = pixelDataStart + srcRow * rowStride
            let dstOff = row * width
            for x in 0..<width {
                let px = srcOff + x * 3
                guard px + 2 < data.count else {
                    throw J2KError.invalidParameter("BMP 24-bit: pixel data truncated")
                }
                bData[dstOff + x] = data[px]
                gData[dstOff + x] = data[px + 1]
                rData[dstOff + x] = data[px + 2]
            }
        }

        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: width, height: height, data: rData),
            J2KComponent(index: 1, bitDepth: 8, width: width, height: height, data: gData),
            J2KComponent(index: 2, bitDepth: 8, width: width, height: height, data: bData),
        ]
        return J2KImage(width: width, height: height, components: components, colorSpace: .sRGB)
    }

    // MARK: - 32-bit BMP

    private static func loadBMP32(
        _ data: Data, width: Int, height: Int,
        topDown: Bool, pixelDataStart: Int
    ) throws -> J2KImage {
        let rowStride = width * 4  // No padding needed for 32-bit

        var rData = Data(count: width * height)
        var gData = Data(count: width * height)
        var bData = Data(count: width * height)
        var aData = Data(count: width * height)

        for row in 0..<height {
            let srcRow = topDown ? row : (height - 1 - row)
            let srcOff = pixelDataStart + srcRow * rowStride
            let dstOff = row * width
            for x in 0..<width {
                let px = srcOff + x * 4
                guard px + 3 < data.count else {
                    throw J2KError.invalidParameter("BMP 32-bit: pixel data truncated")
                }
                bData[dstOff + x] = data[px]
                gData[dstOff + x] = data[px + 1]
                rData[dstOff + x] = data[px + 2]
                aData[dstOff + x] = data[px + 3]
            }
        }

        let components = [
            J2KComponent(index: 0, bitDepth: 8, width: width, height: height, data: rData),
            J2KComponent(index: 1, bitDepth: 8, width: width, height: height, data: gData),
            J2KComponent(index: 2, bitDepth: 8, width: width, height: height, data: bData),
            J2KComponent(index: 3, bitDepth: 8, width: width, height: height, data: aData),
        ]
        return J2KImage(width: width, height: height, components: components, colorSpace: .sRGB)
    }

    // MARK: - BMP Writing

    /// Save a `J2KImage` as a 24-bit or 8-bit BMP file.
    ///
    /// - Parameters:
    ///   - image: The image to save.
    ///   - url: Destination file URL.
    /// - Throws: ``J2KError`` if the image format is unsupported.
    static func saveBMP(_ image: J2KImage, to url: URL) throws {
        let data = try buildBMPData(image)
        try data.write(to: url)
    }

    /// Build BMP file data in memory.
    static func buildBMPData(_ image: J2KImage) throws -> Data {
        let width = image.width
        let height = image.height

        if image.componentCount == 1 {
            return try buildBMP8Grey(image)
        } else if image.componentCount >= 3 {
            return try buildBMP24(image)
        } else {
            throw J2KError.invalidParameter("BMP output requires 1 or 3+ components (got \(image.componentCount))")
        }
    }

    private static func buildBMP8Grey(_ image: J2KImage) throws -> Data {
        let width = image.width
        let height = image.height
        let comp = image.components[0]
        let rowStride = (width + 3) & ~3
        let paletteSize = 256 * 4
        let pixelDataSize = rowStride * height
        let fileSize = 14 + 40 + paletteSize + pixelDataSize
        let dataOffset = 14 + 40 + paletteSize

        var out = Data(count: fileSize)

        // File header
        out[0] = 0x42; out[1] = 0x4D  // "BM"
        writeLE32(&out, offset: 2, value: UInt32(fileSize))
        writeLE32(&out, offset: 10, value: UInt32(dataOffset))

        // DIB header
        writeLE32(&out, offset: 14, value: 40)
        writeLE32(&out, offset: 18, value: UInt32(width))
        writeLE32(&out, offset: 22, value: UInt32(height))
        writeLE16(&out, offset: 26, value: 1)   // planes
        writeLE16(&out, offset: 28, value: 8)   // bits per pixel
        writeLE32(&out, offset: 30, value: 0)   // compression

        // Greyscale palette
        for i in 0..<256 {
            let off = 54 + i * 4
            let v = UInt8(i)
            out[off] = v; out[off + 1] = v; out[off + 2] = v; out[off + 3] = 0
        }

        // Pixel data (bottom-up)
        for row in 0..<height {
            let srcRow = height - 1 - row
            let dstOff = dataOffset + row * rowStride
            for x in 0..<width {
                let idx = srcRow * width + x
                out[dstOff + x] = idx < comp.data.count ? comp.data[idx] : 0
            }
        }

        return out
    }

    private static func buildBMP24(_ image: J2KImage) throws -> Data {
        let width = image.width
        let height = image.height
        let r = image.components[0]
        let g = image.components[1]
        let b = image.components[2]
        let rowStride = (width * 3 + 3) & ~3
        let pixelDataSize = rowStride * height
        let fileSize = 14 + 40 + pixelDataSize
        let dataOffset = 14 + 40

        var out = Data(count: fileSize)

        // File header
        out[0] = 0x42; out[1] = 0x4D
        writeLE32(&out, offset: 2, value: UInt32(fileSize))
        writeLE32(&out, offset: 10, value: UInt32(dataOffset))

        // DIB header
        writeLE32(&out, offset: 14, value: 40)
        writeLE32(&out, offset: 18, value: UInt32(width))
        writeLE32(&out, offset: 22, value: UInt32(height))
        writeLE16(&out, offset: 26, value: 1)
        writeLE16(&out, offset: 28, value: 24)
        writeLE32(&out, offset: 30, value: 0)

        // Pixel data (bottom-up, BGR)
        for row in 0..<height {
            let srcRow = height - 1 - row
            let dstOff = dataOffset + row * rowStride
            for x in 0..<width {
                let idx = srcRow * width + x
                let px = dstOff + x * 3
                out[px]     = idx < b.data.count ? b.data[idx] : 0
                out[px + 1] = idx < g.data.count ? g.data[idx] : 0
                out[px + 2] = idx < r.data.count ? r.data[idx] : 0
            }
        }

        return out
    }

    // MARK: - LE helpers

    private static func readLE16(_ data: Data, offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func readLE32(_ data: Data, offset: Int) -> UInt32 {
        UInt32(data[offset]) |
        UInt32(data[offset + 1]) << 8 |
        UInt32(data[offset + 2]) << 16 |
        UInt32(data[offset + 3]) << 24
    }

    private static func writeLE16(_ data: inout Data, offset: Int, value: UInt16) {
        data[offset]     = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeLE32(_ data: inout Data, offset: Int, value: UInt32) {
        data[offset]     = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
