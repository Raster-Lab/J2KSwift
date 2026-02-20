//
// ImageIO.swift
// J2KSwift
//
/// Image I/O utilities for loading and saving PGM/PPM/RAW files

import Foundation
import J2KCore

extension J2KCLI {
    /// Load an image from a file (PGM, PPM, or RAW format)
    static func loadImage(from path: String) throws -> J2KImage {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)

        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pgm":
            return try loadPGM(data)
        case "ppm":
            return try loadPPM(data)
        case "raw":
            // For RAW files, we need dimensions in filename or separate config
            throw J2KError.invalidParameter("RAW format requires explicit dimensions (not yet implemented)")
        default:
            throw J2KError.invalidParameter("Unsupported image format: \(ext)")
        }
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

        // Determine bit depth
        let bitDepth = maxValue <= 255 ? 8 : 16

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

        // Determine bit depth
        let bitDepth = maxValue <= 255 ? 8 : 16

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

    /// Save an image to a file (PGM or PPM format)
    static func saveImage(_ image: J2KImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pgm":
            try savePGM(image, to: url)
        case "ppm":
            try savePPM(image, to: url)
        case "raw":
            throw J2KError.invalidParameter("RAW format output not yet implemented")
        default:
            throw J2KError.invalidParameter("Unsupported output format: \(ext)")
        }
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
