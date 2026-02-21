// DICOMWorkflow.swift
// J2KSwift Examples
//
// Demonstrates how to integrate J2KSwift into DICOM workflows.
// J2KSwift has zero DICOM dependencies; it operates on raw pixel bytes.
// Your DICOM toolkit is responsible for reading/writing DICOM datasets.

import Foundation
import J2KCore
import J2KCodec

// MARK: - Simulated DICOM Pixel Data

/// Simulates the raw pixel-data bytes from a DICOM (7FE0,0010) attribute.
struct DICOMPixelData {
    let rows: Int          // DICOM tag (0028,0010)
    let columns: Int       // DICOM tag (0028,0011)
    let samplesPerPixel: Int   // DICOM tag (0028,0002)
    let bitsStored: Int        // DICOM tag (0028,0101)
    let pixelRepresentation: Int  // 0 = unsigned, 1 = signed
    let photometricInterpretation: String  // e.g., "MONOCHROME2", "RGB"
    let rawBytes: Data         // Raw JPEG 2000 pixel data item
}

func makeMockDICOMPixelData() -> DICOMPixelData {
    // Create a small synthetic CT slice (128×128 monochrome, 8-bit)
    let width  = 128
    let height = 128
    var pixels = Data(count: width * height)
    for i in 0 ..< width * height {
        pixels[i] = UInt8((i * 13) & 0xFF)
    }

    // Compress with J2KSwift (lossless, as required for TS 1.2.840.10008.1.2.4.90)
    let component = J2KComponent(index: 0, bitDepth: 8, signed: false,
                                 width: width, height: height, data: pixels)
    let image     = J2KImage(width: width, height: height, components: [component],
                             colorSpace: .grayscale)

    let encoder   = try! J2KEncoder(configuration: .lossless).encode(image)

    return DICOMPixelData(
        rows: height,
        columns: width,
        samplesPerPixel: 1,
        bitsStored: 8,
        pixelRepresentation: 0,
        photometricInterpretation: "MONOCHROME2",
        rawBytes: encoder
    )
}

// MARK: - Example 1: Decode DICOM pixel data (TS .90 / .91)

func decodeDICOMPixelData(_ dicom: DICOMPixelData) throws -> J2KImage {
    let decoder = J2KDecoder()
    let image   = try decoder.decode(dicom.rawBytes)
    print("Decoded DICOM pixel data: \(image.width)×\(image.height), "
          + "\(image.components.count) component(s), "
          + "\(image.components[0].bitDepth)-bit")
    return image
}

// MARK: - Example 2: Encode pixel data for DICOM (TS .90 — lossless)

func encodeLosslessForDICOM(rows: Int, columns: Int, bitsStored: Int,
                             pixelRepresentation: Int, rawPixels: Data) throws -> Data {
    let signed    = pixelRepresentation != 0
    let component = J2KComponent(index: 0, bitDepth: bitsStored, signed: signed,
                                 width: columns, height: rows, data: rawPixels)
    let image     = J2KImage(width: columns, height: rows, components: [component],
                             colorSpace: .grayscale)

    let encoder   = J2KEncoder(configuration: .lossless)
    let j2kBytes  = try encoder.encode(image)
    print("Encoded for DICOM (lossless): \(j2kBytes.count) bytes")
    return j2kBytes
}

// MARK: - Example 3: Encode RGB colour image (TS .91 — lossy)

func encodeRGBForDICOM(rows: Int, columns: Int, rgbInterleaved: Data) throws -> Data {
    let pixelCount = rows * columns
    var rData = Data(count: pixelCount)
    var gData = Data(count: pixelCount)
    var bData = Data(count: pixelCount)
    for i in 0 ..< pixelCount {
        rData[i] = rgbInterleaved[i * 3]
        gData[i] = rgbInterleaved[i * 3 + 1]
        bData[i] = rgbInterleaved[i * 3 + 2]
    }

    let r = J2KComponent(index: 0, bitDepth: 8, signed: false, width: columns, height: rows, data: rData)
    let g = J2KComponent(index: 1, bitDepth: 8, signed: false, width: columns, height: rows, data: gData)
    let b = J2KComponent(index: 2, bitDepth: 8, signed: false, width: columns, height: rows, data: bData)

    let image    = J2KImage(width: columns, height: rows, components: [r, g, b], colorSpace: .sRGB)
    let encoder  = J2KEncoder(configuration: .highQuality)
    let j2kBytes = try encoder.encode(image)
    print("Encoded RGB for DICOM (lossy): \(j2kBytes.count) bytes")
    return j2kBytes
}

// MARK: - Example 4: HTJ2K encoding (TS .201 / .202 / .203)

func encodeHTJ2KForDICOM(rows: Int, columns: Int, bitsStored: Int, rawPixels: Data,
                          lossless: Bool, progressionOrder: String = "RPCL") throws -> Data {
    let component = J2KComponent(index: 0, bitDepth: bitsStored, signed: false,
                                 width: columns, height: rows, data: rawPixels)
    let image     = J2KImage(width: columns, height: rows, components: [component],
                             colorSpace: .grayscale)

    // RPCL is required by Transfer Syntax 1.2.840.10008.1.2.4.203
    let progression: J2KProgressionOrder = progressionOrder == "RPCL" ? .RPCL : .LRCP
    let htConfig = J2KEncodingConfiguration(
        progressionOrder: progression,
        qualityLayers: 1,
        decompositionLevels: 5,
        useHTJ2K: true
    )
    let encoder  = J2KEncoder(encodingConfiguration: htConfig)
    let j2kBytes = try encoder.encode(image)
    print("HTJ2K encoded for DICOM (lossless=\(lossless)): \(j2kBytes.count) bytes")
    return j2kBytes
}

// MARK: - Example 5: Signed pixel data (CT Hounsfield units)

func encodeSignedCT(rows: Int, columns: Int, huValues: [Int16]) throws -> Data {
    // Pack Int16 values as two bytes (little-endian) per pixel
    var rawData = Data(capacity: huValues.count * 2)
    for hu in huValues {
        let lo = UInt8(bitPattern: Int8(truncatingIfNeeded: hu & 0xFF))
        let hi = UInt8(bitPattern: Int8(truncatingIfNeeded: (hu >> 8) & 0xFF))
        rawData.append(lo)
        rawData.append(hi)
    }

    let component = J2KComponent(index: 0, bitDepth: 16, signed: true,
                                 width: columns, height: rows, data: rawData)
    let image     = J2KImage(width: columns, height: rows, components: [component],
                             colorSpace: .grayscale)

    let encoder   = J2KEncoder(configuration: .lossless)
    let j2kBytes  = try encoder.encode(image)
    print("Signed CT encoded: \(j2kBytes.count) bytes (\(rows)×\(columns) @ 16-bit signed)")
    return j2kBytes
}

// MARK: - Run examples

do {
    print("=== Example 1: Decode DICOM pixel data ===")
    let mock  = makeMockDICOMPixelData()
    let _     = try decodeDICOMPixelData(mock)

    print("\n=== Example 2: Encode lossless (TS .90) ===")
    let rawCT = Data(repeating: 128, count: 64 * 64)
    let _     = try encodeLosslessForDICOM(rows: 64, columns: 64, bitsStored: 8,
                                           pixelRepresentation: 0, rawPixels: rawCT)

    print("\n=== Example 3: Encode RGB lossy (TS .91) ===")
    let rgbData = Data(repeating: 200, count: 64 * 64 * 3)
    let _       = try encodeRGBForDICOM(rows: 64, columns: 64, rgbInterleaved: rgbData)

    print("\n=== Example 4: HTJ2K encode (TS .201-.203) ===")
    let _     = try encodeHTJ2KForDICOM(rows: 64, columns: 64, bitsStored: 8,
                                         rawPixels: rawCT, lossless: true, progressionOrder: "RPCL")

    print("\n=== Example 5: Signed CT pixel data ===")
    let huValues: [Int16] = (0 ..< 64 * 64).map { Int16(($0 % 400) - 200) }
    let _                 = try encodeSignedCT(rows: 64, columns: 64, huValues: huValues)
} catch {
    print("Error: \(error)")
    exit(1)
}
