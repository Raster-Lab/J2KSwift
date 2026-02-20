# JP3D Getting Started Guide

## Table of Contents

1. [Overview](#overview)
2. [Requirements](#requirements)
3. [Package.swift Setup](#packageswift-setup)
4. [Core Concepts](#core-concepts)
5. [Your First Encode](#your-first-encode)
6. [Your First Decode](#your-first-decode)
7. [Common Patterns](#common-patterns)
8. [Configuration Presets](#configuration-presets)
9. [Error Handling](#error-handling)
10. [Troubleshooting Quick Reference](#troubleshooting-quick-reference)
11. [Next Steps](#next-steps)

---

## Overview

### What is JP3D?

JP3D (ISO/IEC 15444-10) is the volumetric extension of the JPEG 2000 image compression standard. Where standard JPEG 2000 compresses 2D images, JP3D compresses three-dimensional volumes such as:

- **Medical imaging** — CT, MRI, and PET scan stacks
- **Scientific visualization** — simulation outputs, seismic data
- **Remote sensing** — hyperspectral 3D data cubes
- **3D texture atlases** — game assets, rendering pipelines

JP3D extends the wavelet transform into the third spatial dimension, enabling compression ratios and quality levels comparable to 2D JPEG 2000 but applied across full volumetric datasets.

### How JP3D Differs from a Stack of JPEG 2000 Images

| Characteristic | JP3D | Stack of J2K images |
|----------------|------|---------------------|
| Compression ratio | Higher — exploits inter-slice redundancy | Lower — each slice independent |
| Random slice access | Supported via tile structure | Trivially supported |
| 3D wavelet transform | Yes (LLL through HHH subbands) | No |
| Streamable via JPIP | Yes — region, slice, and viewport queries | Limited |
| File container | Single `.jp3` / `.j3k` file | Multiple files |
| API complexity | Higher | Lower |
| Dependency | `J2K3D` module | `J2KCodec` module |

### J2KSwift JP3D Status

| Feature | Status |
|---------|--------|
| Lossless encoding | ✅ Available |
| Lossy encoding (PSNR-targeted) | ✅ Available |
| HTJ2K lossless/lossy | ✅ Available |
| Tile-based encoding | ✅ Available |
| JPIP volumetric streaming | ✅ Available |
| Accelerate framework | ✅ macOS/iOS |
| Metal GPU acceleration | ✅ Apple platforms |
| Linux support | ✅ Software path |

---

## Requirements

### Platform Requirements

| Platform | Minimum Version | Notes |
|----------|----------------|-------|
| macOS | 14.0+ | Full feature set including Metal |
| iOS | 17.0+ | Full feature set including Metal |
| tvOS | 17.0+ | Full feature set |
| watchOS | 10.0+ | Software path only |
| Linux | Ubuntu 22.04+ | Software path only, Swift 5.9+ |
| Windows | Windows 11 | Experimental, Swift 5.9+ |

### Toolchain Requirements

| Tool | Minimum Version |
|------|----------------|
| Swift | 6.0 |
| Xcode | 15.0+ (Apple platforms) |
| Swift Package Manager | 5.9+ |

### Memory Guidelines

JP3D volumes can be large. As a rule of thumb:

| Volume Dimensions | 8-bit/component | 16-bit/component |
|-------------------|----------------|------------------|
| 128 × 128 × 64    | ~1 MB          | ~2 MB            |
| 256 × 256 × 128   | ~8 MB          | ~16 MB           |
| 512 × 512 × 256   | ~64 MB         | ~128 MB          |
| 1024 × 1024 × 512 | ~512 MB        | ~1 GB            |

Ensure your target device has sufficient RAM before encoding large volumes.

---

## Package.swift Setup

### Adding the J2K3D Dependency

```swift
// Package.swift
// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MyVolumetricApp",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    dependencies: [
        .package(
            url: "https://github.com/anthropics/J2KSwift.git",
            from: "1.8.0"
        )
    ],
    targets: [
        .target(
            name: "MyVolumetricApp",
            dependencies: [
                // Core volume types (J2KVolume, J2KVolumeComponent, J2KError)
                .product(name: "J2KCore", package: "J2KSwift"),
                // JP3D encoder and decoder actors
                .product(name: "J2K3D", package: "J2KSwift"),
                // Optional: JPIP streaming client
                .product(name: "JPIP", package: "J2KSwift"),
                // Optional: Accelerate-based DSP acceleration
                .product(name: "J2KAccelerate", package: "J2KSwift"),
            ]
        ),
        .testTarget(
            name: "MyVolumetricAppTests",
            dependencies: ["MyVolumetricApp"]
        ),
    ]
)
```

### Module Summary

| Module | Purpose | Required? |
|--------|---------|-----------|
| `J2KCore` | Volume types, errors, base protocols | Yes |
| `J2K3D` | `JP3DEncoder`, `JP3DDecoder`, configurations | Yes |
| `JPIP` | `JP3DJPIPClient`, streaming sessions | Optional |
| `J2KAccelerate` | Accelerate-backed wavelet/color transforms | Optional |
| `J2KMetal` | Metal GPU acceleration | Optional |
| `J2KFileFormat` | File I/O helpers, JP2/JP3 container | Optional |

---

## Core Concepts

### J2KVolume

A `J2KVolume` is the fundamental data type representing a three-dimensional array of voxels:

```swift
import J2KCore

// A volume with one component (grayscale CT data)
let component = J2KVolumeComponent(
    index: 0,
    bitDepth: 16,
    signed: false,
    width: 256,
    height: 256,
    depth: 128,
    data: rawVoxelData  // Data with width * height * depth * (bitDepth / 8) bytes
)

let volume = J2KVolume(
    width: 256,
    height: 256,
    depth: 128,
    components: [component]
)
```

### JP3DEncoderConfiguration

Controls how a volume is compressed:

```swift
import J2K3D

// Lossless — every voxel exactly preserved
let losslessConfig = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default
)

// Lossy with 40 dB PSNR target
let lossyConfig = JP3DEncoderConfiguration(
    compressionMode: .lossy(psnr: 40.0),
    tiling: .default
)

// High-throughput lossless (fastest encode/decode)
let htjConfig = JP3DEncoderConfiguration(
    compressionMode: .losslessHTJ2K,
    tiling: .streaming
)
```

### Compression Modes at a Glance

| Mode | Quality | Speed | File Size |
|------|---------|-------|-----------|
| `.lossless` | Perfect | Medium | Large |
| `.lossy(psnr: 45)` | Excellent | Fast | Medium |
| `.lossy(psnr: 35)` | Good | Fast | Small |
| `.targetBitrate(bitsPerVoxel: 1.0)` | Variable | Fast | Exact |
| `.visuallyLossless` | Perceptually perfect | Medium | Medium-small |
| `.losslessHTJ2K` | Perfect | Very fast | Large |
| `.lossyHTJ2K(psnr: 45)` | Excellent | Very fast | Medium |

---

## Your First Encode

### Minimal Example

```swift
import J2KCore
import J2K3D

// 1. Build the volume
func makeSyntheticVolume() -> J2KVolume {
    let width = 64, height = 64, depth = 32
    var voxels = Data(count: width * height * depth)
    for z in 0..<depth {
        for y in 0..<height {
            for x in 0..<width {
                let index = z * height * width + y * width + x
                voxels[index] = UInt8((x + y + z) % 256)
            }
        }
    }
    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: 8,
        signed: false,
        width: width,
        height: height,
        depth: depth,
        data: voxels
    )
    return J2KVolume(width: width, height: height, depth: depth, components: [component])
}

// 2. Create encoder with lossless configuration
let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default
))

// 3. Encode
let volume = makeSyntheticVolume()
let result = try await encoder.encode(volume)

print("Encoded \(result.width)×\(result.height)×\(result.depth) volume")
print("Compression ratio: \(String(format: "%.2f", result.compressionRatio))×")
print("Data size: \(result.data.count) bytes")
```

### Writing to Disk

```swift
import Foundation

// After encoding:
let outputURL = URL(fileURLWithPath: "/tmp/my_volume.jp3")
try result.data.write(to: outputURL)
print("Written to \(outputURL.path)")
```

---

## Your First Decode

### Minimal Example

```swift
import J2KCore
import J2K3D

// Load compressed data from disk
let inputURL = URL(fileURLWithPath: "/tmp/my_volume.jp3")
let compressedData = try Data(contentsOf: inputURL)

// Create decoder
let decoder = JP3DDecoder(configuration: JP3DDecoderConfiguration())

// Decode the full volume
let decodeResult = try await decoder.decode(compressedData)

if decodeResult.isPartial {
    print("Warning: partial decode. \(decodeResult.tilesDecoded)/\(decodeResult.tilesTotal) tiles.")
    for warning in decodeResult.warnings {
        print("  ⚠️ \(warning)")
    }
}

let volume = decodeResult.volume
print("Decoded \(volume.width)×\(volume.height)×\(volume.depth) volume")
print("Components: \(volume.components.count)")
```

### Decoding a Specific Region

```swift
// Only decode a sub-region to save memory and time
let region = JP3DRegion(
    x: 64..<192,
    y: 64..<192,
    z: 16..<48
)

let regionResult = try await decoder.decode(compressedData, region: region)
print("Region voxel count: \(regionResult.volume.components[0].data.count)")
```

---

## Common Patterns

### Pattern 1: Medical CT Scan

```swift
import J2KCore
import J2K3D

func encodeCTScan(slices: [Data], width: Int, height: Int) async throws -> Data {
    // Each slice is width * height * 2 bytes of 16-bit unsigned DICOM data
    let fullData = slices.reduce(Data(), +)
    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: 16,
        signed: false,
        width: width,
        height: height,
        depth: slices.count,
        data: fullData
    )
    let volume = J2KVolume(
        width: width,
        height: height,
        depth: slices.count,
        components: [component]
    )

    // Lossless for diagnostic-quality archival
    let config = JP3DEncoderConfiguration(
        compressionMode: .lossless,
        tiling: JP3DTilingConfiguration(
            tileWidth: 256,
            tileHeight: 256,
            tileDepth: slices.count  // Single z-tile for CT depth
        )
    )
    let encoder = JP3DEncoder(configuration: config)
    let result = try await encoder.encode(volume)
    return result.data
}
```

### Pattern 2: Scientific Float Data

```swift
func encodeScientificVolume(floatBuffer: [Float], w: Int, h: Int, d: Int) async throws -> Data {
    // Convert Float to 32-bit representation
    var rawData = Data(count: floatBuffer.count * 4)
    rawData.withUnsafeMutableBytes { ptr in
        ptr.copyBytes(from: UnsafeBufferPointer(start: floatBuffer, count: floatBuffer.count))
    }

    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: 32,
        signed: true,
        width: w,
        height: h,
        depth: d,
        data: rawData
    )

    let encoder = JP3DEncoder(configuration: .lossless)
    let result = try await encoder.encode(
        J2KVolume(width: w, height: h, depth: d, components: [component])
    )
    return result.data
}
```

### Pattern 3: Multi-Component RGB Volume

```swift
func encodeRGBVolume(
    rData: Data, gData: Data, bData: Data,
    width: Int, height: Int, depth: Int
) async throws -> JP3DEncoderResult {
    let components = zip([rData, gData, bData], 0...).map { data, index in
        J2KVolumeComponent(
            index: index,
            bitDepth: 8,
            signed: false,
            width: width,
            height: height,
            depth: depth,
            data: data
        )
    }
    let volume = J2KVolume(width: width, height: height, depth: depth, components: components)
    let encoder = JP3DEncoder(configuration: .visuallyLossless)
    return try await encoder.encode(volume)
}
```

### Pattern 4: Streaming-Optimized Encode

```swift
// Use the streaming tiling preset for JPIP delivery
let streamingConfig = JP3DEncoderConfiguration(
    compressionMode: .lossy(psnr: 42.0),
    tiling: .streaming,  // 128×128×8 tiles
    progressionOrder: .lrcps  // Layer-resolution-component-position
)
let encoder = JP3DEncoder(configuration: streamingConfig)
```

---

## Configuration Presets

### Tiling Presets

```swift
// Default: balanced for general use
JP3DTilingConfiguration.default     // 256×256×16 voxels per tile

// Streaming: small tiles for low-latency JPIP delivery
JP3DTilingConfiguration.streaming   // 128×128×8 voxels per tile

// Batch: large tiles for throughput-optimized offline processing
JP3DTilingConfiguration.batch       // 512×512×32 voxels per tile
```

### Encoder Configuration Shorthands

```swift
// Shorthand initialisers available on JP3DEncoderConfiguration
let lossless        = JP3DEncoderConfiguration.lossless
let visuallyLossless = JP3DEncoderConfiguration.visuallyLossless
let htjLossless     = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K, tiling: .default)
```

### Progression Order Selection Guide

| Order | Best For |
|-------|---------|
| `.lrcps` | General-purpose, quality-progressive delivery |
| `.rlcps` | Resolution-progressive (thumbnail-first) |
| `.pcrls` | Spatial region-of-interest priority |
| `.slrcp` | Slice-by-slice streaming (medical) |
| `.cprls` | Component-priority (multi-spectral) |

---

## Error Handling

### J2KError Cases

```swift
import J2KCore

do {
    let result = try await encoder.encode(volume)
} catch J2KError.invalidParameter(let message) {
    // Bad input — e.g., inconsistent component dimensions
    print("Invalid parameter: \(message)")
} catch J2KError.internalError(let message) {
    // Encoder bug or unsupported configuration
    print("Internal error: \(message)")
} catch J2KError.outOfMemory {
    // Volume too large for available memory
    print("Out of memory — reduce volume dimensions or tile size")
} catch {
    print("Unexpected error: \(error)")
}
```

### Common Error Scenarios

| Error | Cause | Fix |
|-------|-------|-----|
| `invalidParameter("component data size")` | Data length doesn't match width×height×depth×(bitDepth/8) | Verify component `data` byte count |
| `invalidParameter("tiling")` | Tile dimension larger than volume dimension | Use smaller tiles or `.default` preset |
| `outOfMemory` | Volume too large | Use streaming tiling, or encode in tiles |
| `internalError("codec")` | Unsupported bit depth/mode combination | Check supported configurations |
| `invalidParameter("depth < 2")` | Volume has fewer than 2 slices | Use standard 2D J2KEncoder instead |

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Quick Fix |
|---------|-------------|-----------|
| Build error: `no module 'J2K3D'` | Missing dependency | Add `J2K3D` product to Package.swift |
| Crash on large volume | OOM | Use `.streaming` tiling preset |
| Zero compression ratio | Volume too small | Minimum ~8×8×2 for meaningful compression |
| Slow encode | Default tiling suboptimal | Try `.batch` tiling for offline work |
| `isPartial == true` on decode | Truncated data | Verify data integrity before decode |
| HTJ2K not available | Unsupported platform | Check platform minimum versions |
| Metal errors on macOS | GPU unavailable | Library falls back to software automatically |

### Verifying Your Setup

```swift
import J2K3D

// Print library version information
print(JP3DEncoder.version)  // e.g., "J2K3D 1.8.0 (JP3D/ISO 15444-10)"

// Check available acceleration
let caps = JP3DEncoder.capabilities
print("Metal:     \(caps.metalAvailable)")
print("Accelerate:\(caps.accelerateAvailable)")
print("HTJ2K:     \(caps.htj2kAvailable)")
```

---

## Next Steps

After completing this guide, explore the following documentation:

| Document | What You'll Learn |
|----------|-------------------|
| [`JP3D_ARCHITECTURE.md`](JP3D_ARCHITECTURE.md) | Internal pipeline stages, actor model, memory management |
| [`JP3D_API_REFERENCE.md`](JP3D_API_REFERENCE.md) | Complete API docs for every public type |
| [`JP3D_PERFORMANCE.md`](JP3D_PERFORMANCE.md) | Benchmarks, tiling strategy, GPU acceleration |
| [`JP3D_HTJ2K_INTEGRATION.md`](JP3D_HTJ2K_INTEGRATION.md) | High-throughput JPEG 2000 for JP3D |
| [`JP3D_STREAMING_GUIDE.md`](JP3D_STREAMING_GUIDE.md) | JPIP streaming with `JP3DJPIPClient` |
| [`JP3D_MIGRATION.md`](JP3D_MIGRATION.md) | Migrating from 2D J2KEncoder to JP3DEncoder |
| [`JP3D_TROUBLESHOOTING.md`](JP3D_TROUBLESHOOTING.md) | In-depth diagnostics and known issues |
| [`JP3D_EXAMPLES.md`](JP3D_EXAMPLES.md) | Real-world usage examples end-to-end |

> **Note:** All JP3D operations are `async`. Ensure your call sites are inside an `async` context or use `Task { }` when bridging from synchronous code.

> **Note:** The `J2K3D` module requires Swift 6 strict concurrency. If you encounter actor isolation warnings, consult the [Architecture Guide](JP3D_ARCHITECTURE.md#actor-concurrency-model).
