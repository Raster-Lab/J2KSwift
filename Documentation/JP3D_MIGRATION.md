# JP3D Migration Guide: From 2D JPEG 2000 to JP3D

## Table of Contents

1. [Overview](#overview)
2. [Conceptual Mapping](#conceptual-mapping)
3. [API Comparison Table](#api-comparison-table)
4. [Step-by-Step Migration](#step-by-step-migration)
5. [Common Migration Patterns](#common-migration-patterns)
6. [Configuration Mapping](#configuration-mapping)
7. [Error Handling Changes](#error-handling-changes)
8. [Performance Considerations](#performance-considerations)
9. [Backward Compatibility](#backward-compatibility)
10. [Mixed 2D / 3D Workflows](#mixed-2d--3d-workflows)
11. [Testing Your Migration](#testing-your-migration)

---

## Overview

If you have existing code using J2KSwift's 2D encoder (`J2KEncoder`) and decoder (`J2KDecoder`) and want to migrate to JP3D volumetric compression, this guide covers the complete transition.

### Why Migrate?

| Reason | Benefit |
|--------|---------|
| Better compression | JP3D exploits inter-slice redundancy; typically 30–60% smaller than equivalent J2K stack |
| Single file | One JP3D file replaces a directory of per-slice J2K files |
| Native JPIP support | JPIP volume streaming vs. per-file downloads |
| 3D ROI decode | Decode arbitrary sub-volumes without loading all slices |
| Standard compliance | ISO/IEC 15444-10 interoperability |

### When NOT to Migrate

| Situation | Keep Using 2D J2KEncoder |
|-----------|--------------------------|
| Volume has only 1–2 slices | JP3D gains no inter-slice compression |
| Each slice is edited independently | Slice-independent access is easier with per-file storage |
| Downstream system requires individual J2K files | Interoperability constraint |
| Very limited RAM (< 8 MB) | JP3D tiling has higher baseline overhead |

---

## Conceptual Mapping

### Core Type Equivalences

| 2D Concept | 3D Equivalent | Notes |
|-----------|---------------|-------|
| `J2KImage` | `J2KVolume` | Image → Volume (adds `depth` dimension) |
| `J2KImageComponent` | `J2KVolumeComponent` | Same structure + `depth` property |
| `J2KEncoder` | `JP3DEncoder` | Both are `actor` types |
| `J2KDecoder` | `JP3DDecoder` | Both are `actor` types |
| `J2KEncoderConfiguration` | `JP3DEncoderConfiguration` | Similar fields |
| `J2KDecoderConfiguration` | `JP3DDecoderConfiguration` | Similar fields |
| `J2KEncoderResult` | `JP3DEncoderResult` | Adds `depth`, `tileCount`, `compressionRatio` |
| `J2KDecoderResult` | `JP3DDecoderResult` | Adds `tilesDecoded`, `tilesTotal`, `isPartial` |
| `J2KRegion` | `JP3DRegion` | Adds `z: Range<Int>` |
| `J2KCompressionMode` | `JP3DCompressionMode` | Adds `losslessHTJ2K`, `lossyHTJ2K(psnr:)` |
| `J2KTilingConfiguration` | `JP3DTilingConfiguration` | Adds `tileDepth` |
| `J2KProgressionOrder` | `JP3DProgressionOrder` | Adds `.slrcp`, `.cprls` |

### Dimensional Mapping

```
J2KImage:
  width  ──────────────→  J2KVolume.width
  height ──────────────→  J2KVolume.height
                          J2KVolume.depth  ← NEW (number of slices)

J2KImageComponent:
  width  ──────────────→  J2KVolumeComponent.width
  height ──────────────→  J2KVolumeComponent.height
                          J2KVolumeComponent.depth  ← NEW
  data (H × W bytes)  →  data (D × H × W bytes)     ← Extended
```

---

## API Comparison Table

### Types

| 2D API | 3D API | Module Change? |
|--------|--------|---------------|
| `J2KImage` | `J2KVolume` | No (`J2KCore`) |
| `J2KImageComponent` | `J2KVolumeComponent` | No (`J2KCore`) |
| `J2KRegion(x:y:width:height:)` | `JP3DRegion(x:y:z:)` | No (`J2KCore`) |
| `J2KEncoder` | `JP3DEncoder` | Yes (`J2KCodec` → `J2K3D`) |
| `J2KDecoder` | `JP3DDecoder` | Yes (`J2KCodec` → `J2K3D`) |

### Encoder

| 2D Method | 3D Method | Difference |
|-----------|-----------|------------|
| `encoder.encode(_ image: J2KImage)` | `encoder.encode(_ volume: J2KVolume)` | Parameter type |
| `encoder.encode(_ image:region:)` | `encoder.encode(_ volume:region:)` | Region is 3D |
| `J2KEncoderResult.data` | `JP3DEncoderResult.data` | Same |
| `J2KEncoderResult.width` | `JP3DEncoderResult.width` | Same |
| `J2KEncoderResult.height` | `JP3DEncoderResult.height` | Same |
| (no depth) | `JP3DEncoderResult.depth` | New |
| (no tileCount) | `JP3DEncoderResult.tileCount` | New |
| (no compressionRatio) | `JP3DEncoderResult.compressionRatio` | New |

### Decoder

| 2D Method | 3D Method | Difference |
|-----------|-----------|------------|
| `decoder.decode(_ data:)` | `decoder.decode(_ data:)` | Same signature |
| `decoder.decode(_ data:region:)` | `decoder.decode(_ data:region:)` | Region is 3D |
| `J2KDecoderResult.image` | `JP3DDecoderResult.volume` | Property name |
| (no isPartial) | `JP3DDecoderResult.isPartial` | New |
| (no warnings) | `JP3DDecoderResult.warnings` | New |
| (no tilesDecoded) | `JP3DDecoderResult.tilesDecoded` | New |

### Configuration

| 2D Field | 3D Field | Difference |
|----------|----------|------------|
| `compressionMode` | `compressionMode` | Same (3D adds `losslessHTJ2K`, `lossyHTJ2K`) |
| `tileWidth` | `tiling.tileWidth` | Nested struct in 3D |
| `tileHeight` | `tiling.tileHeight` | Nested struct |
| (no tileDepth) | `tiling.tileDepth` | New |
| `progressionOrder` | `progressionOrder` | Same enum values + 2 new 3D values |
| `qualityLayers` | `qualityLayers` | Same |
| `decompositionLevels` | `decompositionLevelsXY` + `decompositionLevelsZ` | Split into XY and Z |

---

## Step-by-Step Migration

### Step 1: Update Package.swift

```diff
 dependencies: [
     .package(url: "https://github.com/anthropics/J2KSwift.git", from: "1.9.0")
 ],
 targets: [
     .target(
         name: "MyApp",
         dependencies: [
             .product(name: "J2KCore",    package: "J2KSwift"),
-            .product(name: "J2KCodec",   package: "J2KSwift"),
+            .product(name: "J2K3D",      package: "J2KSwift"),
         ]
     )
 ]
```

### Step 2: Update Imports

```diff
 import J2KCore
-import J2KCodec
+import J2K3D
```

### Step 3: Convert J2KImage to J2KVolume

**Before (2D):**
```swift
let component = J2KImageComponent(
    index: 0,
    bitDepth: 16,
    signed: false,
    width: 512,
    height: 512,
    data: sliceData
)
let image = J2KImage(width: 512, height: 512, components: [component])
```

**After (3D):**
```swift
// Concatenate all slice data: [slice0Data, slice1Data, ...] → single Data
let allSliceData = slices.reduce(Data(), +)

let component = J2KVolumeComponent(
    index: 0,
    bitDepth: 16,
    signed: false,
    width: 512,
    height: 512,
    depth: slices.count,  // ← new
    data: allSliceData    // ← all slices concatenated
)
let volume = J2KVolume(
    width: 512,
    height: 512,
    depth: slices.count,   // ← new
    components: [component]
)
```

### Step 4: Update Encoder Usage

**Before (2D):**
```swift
import J2KCodec

let encoder = J2KEncoder(configuration: J2KEncoderConfiguration(
    compressionMode: .lossless,
    tileWidth: 256,
    tileHeight: 256
))
let result = try await encoder.encode(image)
```

**After (3D):**
```swift
import J2K3D

let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: JP3DTilingConfiguration(
        tileWidth: 256,
        tileHeight: 256,
        tileDepth: 16     // ← new dimension
    )
))
let result = try await encoder.encode(volume)
```

### Step 5: Update Decoder Usage

**Before (2D):**
```swift
let decoder = J2KDecoder()
let result = try await decoder.decode(data)
let image = result.image
```

**After (3D):**
```swift
let decoder = JP3DDecoder()
let result = try await decoder.decode(data)
let volume = result.volume

// Handle new partial decode scenarios
if result.isPartial {
    for warning in result.warnings { print("⚠️ \(warning)") }
}
```

### Step 6: Update Region Decoding

**Before (2D):**
```swift
let region = J2KRegion(x: 100, y: 100, width: 200, height: 200)
let result = try await decoder.decode(data, region: region)
```

**After (3D):**
```swift
let region = JP3DRegion(
    x: 100..<300,
    y: 100..<300,
    z: 50..<100   // ← new Z range
)
let result = try await decoder.decode(data, region: region)
```

---

## Common Migration Patterns

### Pattern 1: Converting a Slice Batch to a Volume

```swift
// Before: encode each slice separately
func encodeSeparateSlices(slices: [J2KImage]) async throws -> [Data] {
    let encoder = J2KEncoder(configuration: J2KEncoderConfiguration(compressionMode: .lossless))
    var results: [Data] = []
    for slice in slices {
        let result = try await encoder.encode(slice)
        results.append(result.data)
    }
    return results
}

// After: encode as a single volume (better compression, single file)
func encodeAsVolume(slices: [J2KImage]) async throws -> Data {
    guard let first = slices.first else { throw J2KError.invalidParameter("empty slice list") }

    let allData = slices.flatMap { image in
        image.components[0].data
    }.reduce(Data(), { acc, byte in acc + Data([byte]) })

    // More efficient: concatenate Data objects directly
    var volumeData = Data()
    for image in slices {
        volumeData.append(image.components[0].data)
    }

    let component = J2KVolumeComponent(
        index: 0,
        bitDepth: first.components[0].bitDepth,
        signed: first.components[0].signed,
        width: first.width,
        height: first.height,
        depth: slices.count,
        data: volumeData
    )
    let volume = J2KVolume(
        width: first.width,
        height: first.height,
        depth: slices.count,
        components: [component]
    )

    let encoder = JP3DEncoder(configuration: .lossless)
    return try await encoder.encode(volume).data
}
```

### Pattern 2: Extracting Individual Slices After Decode

```swift
// After decoding a volume, extract individual slices as J2KImage equivalents
func extractSlice(from volume: J2KVolume, z: Int) -> [Data] {
    let bytesPerVoxel = volume.components[0].bitDepth / 8
    let sliceBytes = volume.width * volume.height * bytesPerVoxel

    return volume.components.map { component in
        let start = z * sliceBytes
        let end   = start + sliceBytes
        return component.data[start..<end]
    }
}

// Usage
let volumeResult = try await decoder.decode(compressedData)
let sliceAtZ50 = extractSlice(from: volumeResult.volume, z: 50)
```

### Pattern 3: Keeping 2D Compatibility During Transition

```swift
// Bridge type that wraps a volume slice to behave like a J2KImage
extension J2KVolume {
    func sliceAsComponents(z: Int) -> [J2KVolumeComponent] {
        let bytesPerVoxel = components[0].bitDepth / 8
        let sliceBytes = width * height * bytesPerVoxel

        return components.map { comp in
            let start = z * sliceBytes
            return J2KVolumeComponent(
                index: comp.index,
                bitDepth: comp.bitDepth,
                signed: comp.signed,
                width: comp.width,
                height: comp.height,
                depth: 1,
                data: comp.data[start..<(start + sliceBytes)]
            )
        }
    }
}
```

---

## Configuration Mapping

### Complete Configuration Before/After

**Before (2D):**
```swift
let config = J2KEncoderConfiguration(
    compressionMode: .lossy(psnr: 42.0),
    tileWidth: 128,
    tileHeight: 128,
    progressionOrder: .lrcp,
    qualityLayers: 8,
    decompositionLevels: 5
)
```

**After (3D):**
```swift
let config = JP3DEncoderConfiguration(
    compressionMode: .lossy(psnr: 42.0),   // unchanged
    tiling: JP3DTilingConfiguration(
        tileWidth: 128,
        tileHeight: 128,
        tileDepth: 8                         // new: Z tile dimension
    ),
    progressionOrder: .lrcps,               // 3D equivalent (extra S for slice)
    qualityLayers: 8,                        // unchanged
    decompositionLevelsXY: 5,               // split from decompositionLevels
    decompositionLevelsZ: 3                 // new: Z decomposition levels
)
```

### Compression Mode Mapping

| 2D Mode | 3D Equivalent | Notes |
|---------|--------------|-------|
| `.lossless` | `.lossless` | Identical |
| `.lossy(psnr: X)` | `.lossy(psnr: X)` | Identical |
| `.targetBitrate(bpp: X)` | `.targetBitrate(bitsPerVoxel: X)` | Parameter renamed: `bpp` → `bitsPerVoxel` |
| `.visuallyLossless` | `.visuallyLossless` | Identical |
| N/A | `.losslessHTJ2K` | New in 3D |
| N/A | `.lossyHTJ2K(psnr:)` | New in 3D |

---

## Error Handling Changes

### New Error Scenarios in 3D

The 3D encoder introduces additional failure modes not present in 2D encoding:

```swift
// 3D-specific error scenarios
do {
    let result = try await encoder.encode(volume)
} catch J2KError.invalidParameter(let msg) where msg.contains("depth") {
    // New in 3D: volume must have depth >= 2
    print("Volume depth too small: \(msg)")
} catch J2KError.invalidParameter(let msg) where msg.contains("tileDepth") {
    // New in 3D: tile depth misconfiguration
    print("Bad tile depth: \(msg)")
} catch J2KError.invalidParameter(let msg) where msg.contains("component depth") {
    // New in 3D: component depths must all match volume.depth
    print("Component depth mismatch: \(msg)")
}
```

### Partial Decode Handling

2D decoders either succeed completely or throw. 3D decoders can return partial results from truncated bitstreams:

```swift
// 2D (old): either complete result or throw
let image = try await decoder.decode(data).image

// 3D (new): may be partial — always check
let result = try await decoder.decode(data)
if result.isPartial {
    // Handle gracefully: result.volume may have gaps in z-direction
    print("Warning: \(result.tilesDecoded)/\(result.tilesTotal) tiles decoded")
}
let volume = result.volume
```

---

## Performance Considerations

### Expected Performance Changes After Migration

| Metric | 2D (stack of J2K) | 3D (JP3D) | Change |
|--------|-------------------|-----------|--------|
| File size | 100% (baseline) | ~65–80% | ✅ Smaller |
| Single-slice decode | Fast | ~Same (region decode) | ↔ Similar |
| Full volume decode | N/A | Faster than decoding all slices | ✅ Faster |
| Initial encode time | Fast (parallel slices) | Similar (parallel tiles) | ↔ Similar |
| Memory peak (encode) | Low (one slice at a time) | Higher (tile-sized) | ⚠️ Higher |
| JPIP access | Per-file HTTP | True volume streaming | ✅ Better |

### Encode Time With Inter-Slice Correlation

JP3D encoding is slower than encoding the same data as independent slices **per slice**, but encodes the full volume at comparable or better overall throughput due to tile parallelism.

---

## Backward Compatibility

### Can I Read Old J2K Files with JP3DDecoder?

No. `JP3DDecoder` only handles JP3D bitstreams (ISO 15444-10). Use `J2KDecoder` from `J2KCodec` for 2D J2K/JP2 files:

```swift
import J2KCodec   // For 2D files
import J2K3D      // For 3D files

func decode(file: URL) async throws {
    let data = try Data(contentsOf: file)

    if JP3DDecoder.canDecode(data) {
        // JP3D volume
        let result = try await JP3DDecoder().decode(data)
        handleVolume(result.volume)
    } else {
        // 2D J2K/JP2
        let result = try await J2KDecoder().decode(data)
        handleImage(result.image)
    }
}
```

### Version Compatibility

| J2KSwift Version | J2K3D Module | JP3D Features |
|-----------------|-------------|--------------|
| 1.9.0+ | ✅ | Full feature set documented here |
| 1.8.0 | ✅ | Core encode/decode; no HTJ2K |
| 1.6.x | ❌ | J2K3D module not available |
| < 1.6 | ❌ | JP3D not supported |

---

## Mixed 2D / 3D Workflows

### Serving Both 2D and 3D Clients

```swift
import J2KCore
import J2KCodec
import J2K3D

actor ImageServer {
    func encodeForClient(_ data: Any, clientSupports3D: Bool) async throws -> Data {
        if clientSupports3D, let volume = data as? J2KVolume {
            let encoder = JP3DEncoder(configuration: .lossless)
            return try await encoder.encode(volume).data
        } else if let image = data as? J2KImage {
            let encoder = J2KEncoder(configuration: J2KEncoderConfiguration(
                compressionMode: .lossless
            ))
            return try await encoder.encode(image).data
        }
        throw J2KError.invalidParameter("unsupported data type")
    }
}
```

---

## Testing Your Migration

### Verify Lossless Round-Trip

```swift
import XCTest
import J2KCore
import J2K3D

class MigrationTests: XCTestCase {

    func testRoundTripPreservesVoxels() async throws {
        let originalVolume = makeSyntheticVolume()

        let encoder = JP3DEncoder(configuration: .lossless)
        let encoded = try await encoder.encode(originalVolume)

        let decoder = JP3DDecoder()
        let decoded = try await decoder.decode(encoded.data)

        XCTAssertFalse(decoded.isPartial)
        XCTAssertEqual(decoded.volume.width,  originalVolume.width)
        XCTAssertEqual(decoded.volume.height, originalVolume.height)
        XCTAssertEqual(decoded.volume.depth,  originalVolume.depth)
        XCTAssertEqual(
            decoded.volume.components[0].data,
            originalVolume.components[0].data,
            "Lossless round-trip must preserve all voxels exactly"
        )
    }

    func testCompressionRatioImprovedOverSliceStack() async throws {
        let slices = makeSyntheticSlices(count: 64, width: 256, height: 256)

        // Encode as 2D slice stack
        let sliceEncoder = J2KEncoder(configuration: J2KEncoderConfiguration(compressionMode: .lossless))
        var totalSliceBytes = 0
        for slice in slices {
            let r = try await sliceEncoder.encode(slice)
            totalSliceBytes += r.data.count
        }

        // Encode as JP3D volume
        let volume = buildVolume(from: slices)
        let volumeEncoder = JP3DEncoder(configuration: .lossless)
        let volumeResult = try await volumeEncoder.encode(volume)

        XCTAssertLessThan(
            volumeResult.data.count,
            totalSliceBytes,
            "JP3D should compress better than a stack of independent J2K slices"
        )
        print("Slice stack: \(totalSliceBytes) bytes")
        print("JP3D volume: \(volumeResult.data.count) bytes")
        print("Improvement: \(String(format: "%.1f", Double(totalSliceBytes) / Double(volumeResult.data.count)))×")
    }
}
```
