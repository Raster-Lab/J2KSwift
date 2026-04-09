//
// ImageIO.swift
// J2KSwift
//
/// Image I/O utilities for loading and saving PGM/PPM/RAW/TIFF/PNG/DICOM files

import Foundation
import J2KCore
import J2KCodec

extension J2KCLI {
    /// Load an image from a file (PGM, PPM, TIFF, PNG, DICOM, or RAW format)
    static func loadImage(from path: String) throws -> J2KImage {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

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
    static func loadImageFromStdin() throws -> J2KImage {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard !data.isEmpty else {
            throw J2KError.invalidParameter("No data received on stdin")
        }
        return try loadImageFromData(data)
    }

    /// Load an image from raw `Data`, auto-detecting the format from magic bytes.
    static func loadImageFromData(_ data: Data) throws -> J2KImage {
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
                return try decoder.decode(data)
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
                return try decoder.decode(data)
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
        component.data.withUnsafeBytes { buffer in
            if bytesPerPixel == 1 {
                data.append(contentsOf: buffer)
            } else {
                for i in 0..<(image.width * image.height) {
                    let offset = i * 2
                    if offset + 1 < buffer.count {
                        data.append(buffer[offset])
                        data.append(buffer[offset + 1])
                    }
                }
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
        var data = Data()
        let header = "P6\n\(image.width) \(image.height)\n\(maxValue)\n"
        data.append(header.data(using: .ascii)!)
        let bytesPerSample = bitDepth <= 8 ? 1 : 2
        for i in 0..<(image.width * image.height) {
            if bytesPerSample == 1 {
                let rVal = i < r.data.count ? r.data[i] : 0
                let gVal = i < g.data.count ? g.data[i] : 0
                let bVal = i < b.data.count ? b.data[i] : 0
                data.append(rVal)
                data.append(gVal)
                data.append(bVal)
            } else {
                let idx = i * 2
                let rVal = idx + 1 < r.data.count ? (Int(r.data[idx]) | Int(r.data[idx + 1]) << 8) : 0
                let gVal = idx + 1 < g.data.count ? (Int(g.data[idx]) | Int(g.data[idx + 1]) << 8) : 0
                let bVal = idx + 1 < b.data.count ? (Int(b.data[idx]) | Int(b.data[idx + 1]) << 8) : 0
                // PPM 16-bit is big-endian
                data.append(UInt8((rVal >> 8) & 0xFF))
                data.append(UInt8(rVal & 0xFF))
                data.append(UInt8((gVal >> 8) & 0xFF))
                data.append(UInt8(gVal & 0xFF))
                data.append(UInt8((bVal >> 8) & 0xFF))
                data.append(UInt8(bVal & 0xFF))
            }
        }
        return data
    }

    /// Load a PGM (Portable GrayMap) file
    static func loadPGM(_ data: Data) throws -> J2KImage {
        var offset = 0

        // Read magic number
        guard let magic = readLine(from: data, offset: &offset),
              magic == "P5" else {
            throw J2KError.invalidParameter("Invalid PGM file: wrong magic number")
        }

        // Skip comments
        while offset < data.count && data[offset] == 0x23 { // '#'
            _ = readLine(from: data, offset: &offset)
        }

        // Read width and height
        guard let dimensions = readLine(from: data, offset: &offset),
              let parts = parseDimensions(dimensions) else {
            throw J2KError.invalidParameter("Invalid PGM file: missing dimensions")
        }
        let (width, height) = parts

        // Read max value
        guard let maxValStr = readLine(from: data, offset: &offset),
              let maxValue = Int(maxValStr) else {
            throw J2KError.invalidParameter("Invalid PGM file: missing max value")
        }

        // Determine bit depth from max value: ceil(log2(maxValue + 1))
        let bitDepth: Int = {
            if maxValue <= 255 { return 8 }
            var bits = 0; var v = maxValue
            while v > 0 { v >>= 1; bits += 1 }
            return bits
        }()

        // Read pixel data
        let bytesPerPixel = bitDepth <= 8 ? 1 : 2
        let expectedBytes = width * height * bytesPerPixel
        guard offset + expectedBytes <= data.count else {
            throw J2KError.invalidParameter("Invalid PGM file: insufficient pixel data")
        }

        let pixelData = data.subdata(in: offset..<(offset + expectedBytes))

        // Create component (data is already in correct format)
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

    /// Load a PPM (Portable PixMap) file
    static func loadPPM(_ data: Data) throws -> J2KImage {
        var offset = 0

        // Read magic number
        guard let magic = readLine(from: data, offset: &offset),
              magic == "P6" else {
            throw J2KError.invalidParameter("Invalid PPM file: wrong magic number")
        }

        // Skip comments
        while offset < data.count && data[offset] == 0x23 { // '#'
            _ = readLine(from: data, offset: &offset)
        }

        // Read width and height
        guard let dimensions = readLine(from: data, offset: &offset),
              let parts = parseDimensions(dimensions) else {
            throw J2KError.invalidParameter("Invalid PPM file: missing dimensions")
        }
        let (width, height) = parts

        // Read max value
        guard let maxValStr = readLine(from: data, offset: &offset),
              let maxValue = Int(maxValStr) else {
            throw J2KError.invalidParameter("Invalid PPM file: missing max value")
        }

        // Determine bit depth from max value: ceil(log2(maxValue + 1))
        let bitDepth: Int = {
            if maxValue <= 255 { return 8 }
            var bits = 0; var v = maxValue
            while v > 0 { v >>= 1; bits += 1 }
            return bits
        }()

        // Read pixel data (interleaved RGB)
        let bytesPerPixel = bitDepth <= 8 ? 1 : 2
        let expectedBytes = width * height * 3 * bytesPerPixel
        guard offset + expectedBytes <= data.count else {
            throw J2KError.invalidParameter("Invalid PPM file: insufficient pixel data")
        }

        let pixelData = data.subdata(in: offset..<(offset + expectedBytes))

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
        component.data.withUnsafeBytes { buffer in
            if bytesPerPixel == 1 {
                // 8-bit: copy directly
                data.append(contentsOf: buffer)
            } else {
                // 16-bit: need to copy
                for i in 0..<(image.width * image.height) {
                    let offset = i * 2
                    if offset + 1 < buffer.count {
                        data.append(buffer[offset])
                        data.append(buffer[offset + 1])
                    }
                }
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

        var data = Data()

        // Write header
        let header = "P6\n\(image.width) \(image.height)\n\(maxValue)\n"
        data.append(header.data(using: .ascii)!)

        // Write pixel data (interleaved RGB)
        let bytesPerPixel = bitDepth <= 8 ? 1 : 2
        for i in 0..<(image.width * image.height) {
            let rVal = max(0, min(Int(r.data[i]), maxValue))
            let gVal = max(0, min(Int(g.data[i]), maxValue))
            let bVal = max(0, min(Int(b.data[i]), maxValue))

            if bytesPerPixel == 1 {
                data.append(UInt8(rVal))
                data.append(UInt8(gVal))
                data.append(UInt8(bVal))
            } else {
                data.append(UInt8(rVal >> 8))
                data.append(UInt8(rVal & 0xFF))
                data.append(UInt8(gVal >> 8))
                data.append(UInt8(gVal & 0xFF))
                data.append(UInt8(bVal >> 8))
                data.append(UInt8(bVal & 0xFF))
            }
        }

        try data.write(to: url)
    }

    /// Read a line from data
    private static func readLine(from data: Data, offset: inout Int) -> String? {
        var lineData = Data()

        while offset < data.count {
            let byte = data[offset]
            offset += 1

            if byte == 0x0A { // '\n'
                break
            }

            if byte != 0x0D { // Ignore '\r'
                lineData.append(byte)
            }
        }

        return String(data: lineData, encoding: .ascii)?.trimmingCharacters(in: .whitespaces)
    }

    /// Parse dimensions from string "width height"
    private static func parseDimensions(_ str: String) -> (Int, Int)? {
        let parts = str.split(separator: " ").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }
}
