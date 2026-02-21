// HTJ2KTranscoding.swift
// J2KSwift Examples
//
// Demonstrates HTJ2K (ISO/IEC 15444-15) encoding, decoding, and transcoding
// from/to standard JPEG 2000.

import Foundation
import J2KCore
import J2KCodec
import J2KFileFormat

// MARK: - Helper

func makeSyntheticImage(width: Int, height: Int) -> J2KImage {
    let count = width * height
    var data = Data(capacity: count)
    for i in 0 ..< count {
        data.append(UInt8(i & 0xFF))
    }
    let r = J2KComponent(index: 0, bitDepth: 8, signed: false, width: width, height: height, data: data)
    let g = J2KComponent(index: 1, bitDepth: 8, signed: false, width: width, height: height, data: data)
    let b = J2KComponent(index: 2, bitDepth: 8, signed: false, width: width, height: height, data: data)
    return J2KImage(width: width, height: height, components: [r, g, b])
}

// MARK: - Example 1: Encode with HTJ2K

func htj2kEncodeExample() throws {
    let image = makeSyntheticImage(width: 128, height: 128)

    let htConfig = J2KEncodingConfiguration(
        progressionOrder: .LRCP,
        qualityLayers: 1,
        decompositionLevels: 5,
        useHTJ2K: true,
        enableFastMEL: true,
        enableVLCOptimization: true,
        enableMagSgnPacking: true
    )
    let encoder = J2KEncoder(encodingConfiguration: htConfig)
    let htData  = try encoder.encode(image)
    print("HTJ2K encoded \(image.width)×\(image.height) → \(htData.count) bytes")

    // Decode (J2KDecoder handles both J2K and HTJ2K transparently)
    let decoder = J2KDecoder()
    let decoded = try decoder.decode(htData)
    print("Decoded: \(decoded.width)×\(decoded.height)")
}

// MARK: - Example 2: Compare standard J2K vs HTJ2K size

func compareJ2KvsHTJ2K() throws {
    let image = makeSyntheticImage(width: 256, height: 256)

    // Standard J2K
    let stdEncoder = J2KEncoder(configuration: .balanced)
    let stdData    = try stdEncoder.encode(image)

    // HTJ2K
    let htConfig = J2KEncodingConfiguration(
        progressionOrder: .LRCP,
        qualityLayers: 1,
        decompositionLevels: 5,
        useHTJ2K: true
    )
    let htEncoder = J2KEncoder(encodingConfiguration: htConfig)
    let htData    = try htEncoder.encode(image)

    print("\nStandard J2K: \(stdData.count) bytes")
    print("HTJ2K:        \(htData.count) bytes")
}

// MARK: - Example 3: Transcode standard J2K → HTJ2K

func transcodeToHTJ2K() throws {
    // First produce a standard J2K codestream
    let image      = makeSyntheticImage(width: 128, height: 128)
    let stdEncoder = J2KEncoder(configuration: .balanced)
    let stdData    = try stdEncoder.encode(image)
    print("\nOriginal (standard J2K): \(stdData.count) bytes")

    // Transcode synchronously
    let transcoder = J2KTranscoder()
    let htData     = try transcoder.transcode(stdData, to: .htj2k)
    print("Transcoded to HTJ2K:    \(htData.count) bytes")

    // Verify the result decodes correctly
    let decoder = J2KDecoder()
    let decoded = try decoder.decode(htData)
    print("Verified: \(decoded.width)×\(decoded.height)")
}

// MARK: - Example 4: Transcode HTJ2K → standard J2K (async)

func transcodeFromHTJ2KAsync() async throws {
    let image     = makeSyntheticImage(width: 128, height: 128)
    let htConfig  = J2KEncodingConfiguration(useHTJ2K: true)
    let htEncoder = J2KEncoder(encodingConfiguration: htConfig)
    let htData    = try htEncoder.encode(image)

    let transcoder = J2KTranscoder()
    let stdData    = try await transcoder.transcodeAsync(htData, to: .standard)
    print("\nTranscoded HTJ2K → standard J2K: \(stdData.count) bytes")
}

// MARK: - Example 5: Write a JPH file

func writeJPHFileExample() throws {
    let image = makeSyntheticImage(width: 64, height: 64)
    let url   = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("example.jph")

    let htConfig = J2KEncodingConfiguration(useHTJ2K: true)
    let encoder  = J2KEncoder(encodingConfiguration: htConfig)
    let htData   = try encoder.encode(image)

    try htData.write(to: url)
    print("\nWrote JPH file: \(url.path) (\(htData.count) bytes)")
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Detect whether data is HTJ2K

func detectHTJ2K() throws {
    let image      = makeSyntheticImage(width: 32, height: 32)
    let htConfig   = J2KEncodingConfiguration(useHTJ2K: true)
    let htEncoder  = J2KEncoder(encodingConfiguration: htConfig)
    let htData     = try htEncoder.encode(image)

    let stdEncoder = J2KEncoder(configuration: .balanced)
    let stdData    = try stdEncoder.encode(image)

    let transcoder = J2KTranscoder()
    print("\nIs HTJ2K (ht): \(try transcoder.isHTJ2K(htData))")
    print("Is HTJ2K (std): \(try transcoder.isHTJ2K(stdData))")
}

// MARK: - Run examples

do {
    print("=== Example 1: HTJ2K encode/decode ===")
    try htj2kEncodeExample()

    print("\n=== Example 2: J2K vs HTJ2K sizes ===")
    try compareJ2KvsHTJ2K()

    print("\n=== Example 3: Transcode to HTJ2K ===")
    try transcodeToHTJ2K()

    print("\n=== Example 4: Transcode HTJ2K → J2K (async) ===")
    let sema = DispatchSemaphore(value: 0)
    Task {
        do {
            try await transcodeFromHTJ2KAsync()
        } catch {
            print("Async error: \(error)")
        }
        sema.signal()
    }
    sema.wait()

    print("\n=== Example 5: Write JPH file ===")
    try writeJPHFileExample()

    print("\n=== Detect HTJ2K ===")
    try detectHTJ2K()
} catch {
    print("Error: \(error)")
    exit(1)
}
