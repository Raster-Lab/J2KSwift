// ProgressiveDecoding.swift
// J2KSwift Examples
//
// Demonstrates incremental / progressive JPEG 2000 decoding, including
// partial-data decoding, resolution-level decoding, ROI decoding, and
// quality-layer decoding.

import Foundation
import J2KCore
import J2KCodec

// MARK: - Helper

func makeImage(width: Int = 128, height: Int = 128) -> J2KImage {
    let count = width * height
    var pixels = Data(count: count)
    for i in 0 ..< count {
        pixels[i] = UInt8((i * 7) & 0xFF)
    }
    let r = J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: pixels)
    let g = J2KComponent(index: 1, bitDepth: 8, signed: false, width: width, height: height, data: pixels)
    let b = J2KComponent(index: 2, bitDepth: 8, signed: false, width: width, height: height, data: pixels)
    return J2KImage(width: width, height: height, components: [r, g, b])
}

func encodeLayered(image: J2KImage, layers: Int) throws -> Data {
    let config = J2KEncodingConfiguration(
        progressionOrder: .LRCP,
        qualityLayers: layers,
        decompositionLevels: 5
    )
    return try J2KEncoder(encodingConfiguration: config).encode(image)
}

// MARK: - Example 1: Incremental decoder (simulate streaming arrival)

func incrementalDecoderExample() throws {
    let image = makeImage(width: 64, height: 64)
    let data  = try encodeLayered(image: image, layers: 4)
    print("Full codestream: \(data.count) bytes")

    let incremental = J2KIncrementalDecoder()

    // Simulate arriving in three chunks
    let chunkSize = data.count / 3
    incremental.append(data.prefix(chunkSize))
    if let partial = try incremental.tryDecode() {
        print("After chunk 1: \(partial.width)×\(partial.height) (partial)")
    } else {
        print("After chunk 1: not yet decodable")
    }

    incremental.append(data.dropFirst(chunkSize).prefix(chunkSize))
    if let partial = try incremental.tryDecode() {
        print("After chunk 2: \(partial.width)×\(partial.height) (partial)")
    }

    incremental.append(data.dropFirst(chunkSize * 2))
    incremental.complete()

    let final = try incremental.tryDecode()
    print("Final: \(final?.width ?? 0)×\(final?.height ?? 0)")
}

// MARK: - Example 2: Resolution-level decoding (thumbnails)

func resolutionLevelExample() throws {
    let image = makeImage(width: 256, height: 256)
    let data  = try encodeLayered(image: image, layers: 1)

    let decoder = J2KAdvancedDecoder()

    for level in 0 ... 3 {
        let options   = J2KResolutionDecodingOptions(resolutionLevel: level)
        let thumbnail = try decoder.decodeResolution(data, options: options)
        print("Level \(level): \(thumbnail.width)×\(thumbnail.height)")
    }
}

// MARK: - Example 3: ROI (region-of-interest) decoding

func roiDecodingExample() throws {
    let image = makeImage(width: 256, height: 256)
    let data  = try encodeLayered(image: image, layers: 1)

    let decoder = J2KAdvancedDecoder()

    let options = J2KROIDecodingOptions(
        regionX: 64,
        regionY: 64,
        regionWidth: 64,
        regionHeight: 64
    )
    let roi = try decoder.decodeRegion(data, options: options)
    print("\nROI decoded: \(roi.width)×\(roi.height) pixels")
}

// MARK: - Example 4: Quality-layer decoding

func qualityLayerExample() throws {
    let image = makeImage(width: 128, height: 128)
    let data  = try encodeLayered(image: image, layers: 8)

    let decoder = J2KAdvancedDecoder()

    for layers in [1, 2, 4, 8] {
        let options = J2KQualityDecodingOptions(qualityLayers: layers)
        let draft   = try decoder.decodeQuality(data, options: options)
        print("Quality layers \(layers): \(draft.width)×\(draft.height)")
    }
}

// MARK: - Example 5: Partial decode (combined resolution + quality)

func partialDecodeExample() throws {
    let image = makeImage(width: 256, height: 256)
    let data  = try encodeLayered(image: image, layers: 8)

    let decoder = J2KAdvancedDecoder()

    let options = J2KPartialDecodingOptions(
        resolutionLevel: 2,
        qualityLayers: 3,
        components: [0, 1, 2]
    )
    let partial = try decoder.decodePartial(data, options: options)
    print("\nPartial decode (res=2, q=3): \(partial.width)×\(partial.height)")
}

// MARK: - Run examples

do {
    print("=== Example 1: Incremental decoder ===")
    try incrementalDecoderExample()

    print("\n=== Example 2: Resolution-level thumbnails ===")
    try resolutionLevelExample()

    print("\n=== Example 3: ROI decoding ===")
    try roiDecodingExample()

    print("\n=== Example 4: Quality-layer decoding ===")
    try qualityLayerExample()

    print("\n=== Example 5: Partial decode ===")
    try partialDecodeExample()
} catch {
    print("Error: \(error)")
    exit(1)
}
