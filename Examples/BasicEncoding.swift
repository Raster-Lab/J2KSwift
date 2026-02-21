// BasicEncoding.swift
// J2KSwift Examples
//
// Demonstrates the simplest encode → decode round-trip using J2KSwift.
// Run this file with: swift BasicEncoding.swift

import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

// MARK: - Helper: create a synthetic test image

/// Creates a simple 64×64 RGB test image (uniform grey).
func makeTestImage(width: Int = 64, height: Int = 64) -> J2KImage {
    let pixelCount = width * height
    let grey = Data(repeating: 128, count: pixelCount)

    let red   = J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: grey)
    let green = J2KComponent(index: 1, bitDepth: 8, signed: false, width: width, height: height, data: grey)
    let blue  = J2KComponent(index: 2, bitDepth: 8, signed: false, width: width, height: height, data: grey)

    return J2KImage(width: width, height: height, components: [red, green, blue], colorSpace: .sRGB)
}

// MARK: - Example 1: Basic encode/decode

func basicEncodeDecodeExample() throws {
    let original = makeTestImage()

    // Encode with the balanced (default) configuration
    let encoder = J2KEncoder()
    let encoded = try encoder.encode(original)
    print("Encoded \(original.width)×\(original.height) image → \(encoded.count) bytes")

    // Decode
    let decoder = J2KDecoder()
    let decoded = try decoder.decode(encoded)
    print("Decoded back to \(decoded.width)×\(decoded.height), \(decoded.components.count) component(s)")
}

// MARK: - Example 2: Lossless encode

func losslessEncodeExample() throws {
    let original = makeTestImage()

    let encoder = J2KEncoder(configuration: .lossless)
    let encoded = try encoder.encode(original)
    print("Lossless encoded → \(encoded.count) bytes")

    // Verify round-trip pixel equality
    let decoder = J2KDecoder()
    let decoded = try decoder.decode(encoded)
    let originalBytes = original.components[0].data
    let decodedBytes  = decoded.components[0].data
    print("Pixel-perfect round-trip: \(originalBytes == decodedBytes)")
}

// MARK: - Example 3: Quality presets comparison

func qualityPresetsExample() throws {
    let original = makeTestImage(width: 256, height: 256)
    let presets: [(String, J2KConfiguration)] = [
        ("lossless",       .lossless),
        ("highQuality",    .highQuality),
        ("balanced",       .balanced),
        ("fast",           .fast),
        ("maxCompression", .maxCompression),
    ]

    print("\nQuality preset comparison (256×256 RGB):")
    for (name, preset) in presets {
        let encoder = J2KEncoder(configuration: preset)
        let data = try encoder.encode(original)
        print("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0)): \(data.count) bytes")
    }
}

// MARK: - Example 4: Write and read a JP2 file

func fileRoundTripExample() throws {
    let original = makeTestImage()
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("example.jp2")

    // Write
    let writer = J2KFileWriter(format: .jp2)
    try writer.write(original, to: url)
    print("\nWrote \(url.path)")

    // Read back
    let reader = J2KFileReader()
    let loaded = try reader.read(from: url)
    print("Read back: \(loaded.width)×\(loaded.height)")

    // Clean up
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Run all examples

do {
    print("=== Example 1: Basic encode/decode ===")
    try basicEncodeDecodeExample()

    print("\n=== Example 2: Lossless encode ===")
    try losslessEncodeExample()

    print("\n=== Example 3: Quality presets ===")
    try qualityPresetsExample()

    print("\n=== Example 4: File round-trip ===")
    try fileRoundTripExample()
} catch {
    print("Error: \(error)")
    exit(1)
}
