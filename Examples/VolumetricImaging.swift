// VolumetricImaging.swift
// J2KSwift Examples
//
// Demonstrates JP3D (ISO/IEC 15444-10) volumetric imaging workflows including
// encoding, decoding, and streaming of 3-D voxel data.

import Foundation
import J2KCore
import J2KCodec
import J2K3D

// MARK: - Helper: create a synthetic CT-like volume

func makeSyntheticCTVolume(width: Int, height: Int, depth: Int) -> J2KVolume {
    let voxelCount = width * height * depth
    var voxelData  = Data(capacity: voxelCount)
    for i in 0 ..< voxelCount {
        voxelData.append(UInt8((i * 13 + 7) & 0xFF))
    }

    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: 8,
        signed: false,
        width: width,
        height: height,
        depth: depth,
        data: voxelData
    )

    return J2KVolume(
        width: width,
        height: height,
        depth: depth,
        components: [component],
        spacingX: 0.5,  // 0.5 mm voxel spacing
        spacingY: 0.5,
        spacingZ: 1.0
    )
}

// MARK: - Example 1: Lossless encode and decode

func losslessVolumetricExample() async throws {
    let volume = makeSyntheticCTVolume(width: 64, height: 64, depth: 16)

    let encoder = JP3DEncoder(configuration: .lossless)
    let result  = try await encoder.encode(volume)
    print("Lossless JP3D: \(result.data.count) bytes for \(volume.width)×\(volume.height)×\(volume.depth) volume")

    let decoder     = JP3DDecoder()
    let decResult   = try await decoder.decode(result.data)
    let decodedVol  = decResult.volume
    print("Decoded: \(decodedVol.width)×\(decodedVol.height)×\(decodedVol.depth)")

    // Verify lossless round-trip
    let original = volume.components[0].data
    let decoded  = decodedVol.components[0].data
    print("Pixel-perfect: \(original == decoded)")
}

// MARK: - Example 2: Lossy encode with progress callback

func lossyVolumetricWithProgressExample() async throws {
    let volume = makeSyntheticCTVolume(width: 128, height: 128, depth: 32)

    let config = JP3DEncoderConfiguration(
        compressionMode: .lossy,
        levelsX: 4,
        levelsY: 4,
        levelsZ: 2,
        qualityLayers: 4
    )
    let encoder = JP3DEncoder(configuration: config)

    await encoder.setProgressCallback { progress in
        print("  Progress: \(String(format: "%.0f", progress.percentComplete))%")
    }

    let result = try await encoder.encode(volume)
    print("Lossy JP3D: \(result.data.count) bytes")
}

// MARK: - Example 3: Peek metadata before full decode

func peekMetadataExample() async throws {
    let volume  = makeSyntheticCTVolume(width: 64, height: 64, depth: 8)
    let encoder = JP3DEncoder(configuration: .lossless)
    let result  = try await encoder.encode(volume)

    let decoder = JP3DDecoder()
    let info    = try decoder.peekMetadata(result.data)
    print("\nMetadata peek: \(info.width)×\(info.height)×\(info.depth) @ \(info.bitDepth)-bit")
}

// MARK: - Example 4: Multi-component volume (RGB volumetric)

func multiComponentVolumeExample() async throws {
    let w = 32; let h = 32; let d = 8
    let size = w * h * d

    var rData = Data(count: size)
    var gData = Data(count: size)
    var bData = Data(count: size)
    for i in 0 ..< size {
        rData[i] = UInt8(i & 0xFF)
        gData[i] = UInt8((i * 3) & 0xFF)
        bData[i] = UInt8((i * 7) & 0xFF)
    }

    let r = J2KVolumeComponent(index: 0, bitDepth: 8, signed: false, width: w, height: h, depth: d, data: rData)
    let g = J2KVolumeComponent(index: 1, bitDepth: 8, signed: false, width: w, height: h, depth: d, data: gData)
    let b = J2KVolumeComponent(index: 2, bitDepth: 8, signed: false, width: w, height: h, depth: d, data: bData)

    let volume  = J2KVolume(width: w, height: h, depth: d, components: [r, g, b])
    let encoder = JP3DEncoder(configuration: .lossless)
    let result  = try await encoder.encode(volume)
    print("\nRGB volume encoded: \(result.data.count) bytes, components: \(volume.components.count)")
}

// MARK: - Example 5: HTJ2K-accelerated volumetric encoding

func htj2kVolumetricExample() async throws {
    let volume = makeSyntheticCTVolume(width: 64, height: 64, depth: 16)

    // JP3DEncoderConfiguration with .htj2k compression mode dispatches
    // the HTJ2K block coder internally; JP3DHTJ2KConfiguration.lowLatency
    // provides default parameters that are used when configuring the preset.
    let encConfig = JP3DEncoderConfiguration(
        compressionMode: .htj2k,
        levelsX: 3,
        levelsY: 3,
        levelsZ: 1
    )
    let encoder = JP3DEncoder(configuration: encConfig)
    let result  = try await encoder.encode(volume)
    print("\nHTJ2K volumetric: \(result.data.count) bytes")
}

// MARK: - Run examples

let sema = DispatchSemaphore(value: 0)
Task {
    do {
        print("=== Example 1: Lossless volumetric ===")
        try await losslessVolumetricExample()

        print("\n=== Example 2: Lossy with progress ===")
        try await lossyVolumetricWithProgressExample()

        print("\n=== Example 3: Peek metadata ===")
        try await peekMetadataExample()

        print("\n=== Example 4: Multi-component volume ===")
        try await multiComponentVolumeExample()

        print("\n=== Example 5: HTJ2K volumetric ===")
        try await htj2kVolumetricExample()
    } catch {
        print("Error: \(error)")
    }
    sema.signal()
}
sema.wait()
