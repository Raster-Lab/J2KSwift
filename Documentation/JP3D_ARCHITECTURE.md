# JP3D Architecture Overview

## Table of Contents

1. [Module Structure](#module-structure)
2. [Encoding Pipeline](#encoding-pipeline)
3. [Decoding Pipeline](#decoding-pipeline)
4. [3D Wavelet Transform](#3d-wavelet-transform)
5. [Tile Structure](#tile-structure)
6. [Actor Concurrency Model](#actor-concurrency-model)
7. [Memory Management](#memory-management)
8. [Cross-Platform Strategy](#cross-platform-strategy)
9. [Extension Points](#extension-points)

---

## Module Structure

### Dependency Graph

```
┌─────────────────────────────────────────────────────┐
│                   Your Application                  │
└──────┬──────────────┬───────────────┬───────────────┘
       │              │               │
       ▼              ▼               ▼
┌────────────┐  ┌──────────┐  ┌───────────────┐
│   J2K3D    │  │   JPIP   │  │ J2KFileFormat │
│ (encoder / │  │(streaming│  │  (container   │
│  decoder)  │  │ client)  │  │   I/O)        │
└──────┬─────┘  └────┬─────┘  └──────┬────────┘
       │             │               │
       └─────────────┴───────────────┘
                     │
                     ▼
             ┌───────────────┐
             │    J2KCore    │
             │ (J2KVolume,   │
             │  J2KError,    │
             │  protocols)   │
             └───────┬───────┘
                     │
          ┌──────────┴──────────┐
          │                     │
          ▼                     ▼
  ┌──────────────┐     ┌────────────────┐
  │ J2KAccelerate│     │   J2KMetal     │
  │ (Accelerate  │     │ (Metal compute │
  │  framework)  │     │  shaders)      │
  └──────────────┘     └────────────────┘
```

### Module Responsibilities

| Module | Layer | Key Types | Platforms |
|--------|-------|-----------|-----------|
| `J2KCore` | Foundation | `J2KVolume`, `J2KVolumeComponent`, `J2KError`, `JP3DRegion` | All |
| `J2K3D` | Codec | `JP3DEncoder`, `JP3DDecoder`, `JP3DEncoderConfiguration` | All |
| `JPIP` | Network | `JP3DJPIPClient`, `JP3DStreamingRegion`, `JP3DViewport` | All |
| `J2KAccelerate` | Acceleration | `J2KDWTAccelerated`, `J2KColorTransform` | Apple only |
| `J2KMetal` | GPU Acceleration | Metal compute pipelines | Apple only |
| `J2KFileFormat` | I/O | `J2KFileReader`, `J2KFileWriter` | All |

---

## Encoding Pipeline

### Stage Overview

```
  Input: J2KVolume
       │
       ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 1: Validation & Preprocessing                          │
  │   • Validate component dimensions match volume dimensions    │
  │   • Verify data buffer sizes                                 │
  │   • Normalize multi-component volumes (DC level shift)       │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 2: Tiling                                              │
  │   • Partition volume into JP3DTile objects                   │
  │   • Apply JP3DTilingConfiguration (width×height×depth)       │
  │   • Dispatch tiles to parallel task group                    │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                     ┌───────┴───────┐
                     │ Per-tile work │  (concurrent)
                     └───────┬───────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 3: Color Transform (multi-component only)              │
  │   • RCT (Reversible Color Transform) for lossless            │
  │   • ICT (Irreversible Color Transform) for lossy             │
  │   • Accelerate vDSP path on Apple platforms                  │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 4: 3D Discrete Wavelet Transform                       │
  │   • Le Gall 5/3 filter (lossless) or CDF 9/7 (lossy)        │
  │   • Applied along X, then Y, then Z axes                     │
  │   • Produces 8 subbands: LLL, LLH, LHL, LHH, HLL, HLH, HHL, HHH │
  │   • Accelerate BLAS/LAPACK on Apple; SIMD fallback elsewhere │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 5: Quantization                                        │
  │   • Scalar uniform quantization (lossy)                      │
  │   • Dead-zone quantization for perceptual modes              │
  │   • No quantization (lossless)                               │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 6: Entropy Coding (EBCOT / MQ-Coder)                   │
  │   • Context modeling over 3D neighborhoods                   │
  │   • Block coding of J2K3DCoefficients                        │
  │   • HTJ2K path uses HTMQ coder (ISO 15444-15)                │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 7: Packet Assembly & Bitstream Layering                │
  │   • Quality layers built per JP3DProgressionOrder            │
  │   • Precinct packets assembled into tile-parts               │
  │   • Main header + tile-part headers written                  │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  Output: JP3DEncoderResult (data, metadata)
```

### Tile Parallelism

Each tile is encoded independently in a Swift `TaskGroup`, allowing full CPU parallelism. On an 8-core M3 MacBook Pro, a 512×512×256 volume (64 tiles at `.batch` preset) achieves near-linear scaling:

```swift
// Conceptual internal encoding loop (simplified)
try await withThrowingTaskGroup(of: EncodedTile.self) { group in
    for tile in tiledVolume.tiles {
        group.addTask {
            try await encodeTile(tile, config: configuration)
        }
    }
    for try await encodedTile in group {
        assembler.append(encodedTile)
    }
}
```

---

## Decoding Pipeline

### Stage Overview

```
  Input: Data (JP3 bitstream)
       │
       ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 1: Bitstream Parsing                                   │
  │   • SOC, SIZ, COD, QCD, COM markers                         │
  │   • JP3D-specific SIZ3D and COD3D marker extensions         │
  │   • Tile-part SOT/SOD extraction                            │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 2: Region Filtering (optional)                         │
  │   • If JP3DRegion provided, skip irrelevant tiles            │
  │   • Partial tile extraction at boundaries                    │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                     ┌───────┴───────┐
                     │ Per-tile work │  (concurrent)
                     └───────┬───────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 3: Entropy Decoding                                    │
  │   • MQ-coder decoding / HTMQ fast decoding                  │
  │   • Coefficient reconstruction                               │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 4: Dequantization                                      │
  │   • Reconstruct wavelet coefficients                         │
  │   • Apply step sizes from QCD/QCC markers                    │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 5: Inverse 3D Wavelet Transform                        │
  │   • IDWT along Z, then Y, then X                            │
  │   • Reconstruct voxels from LLL through HHH subbands        │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 6: Inverse Color Transform                             │
  │   • Inverse RCT/ICT as appropriate                          │
  │   • Reconstruct per-component voxel arrays                   │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ Stage 7: Volume Assembly                                     │
  │   • Stitch decoded tiles back into J2KVolume                 │
  │   • Populate JP3DDecoderResult with metadata                 │
  └─────────────────────────┬────────────────────────────────────┘
                             │
                             ▼
  Output: JP3DDecoderResult (volume, isPartial, warnings)
```

---

## 3D Wavelet Transform

### Subband Nomenclature

The 3D DWT produces 8 subbands by applying 1D filtering along each axis independently:

| Subband | X filter | Y filter | Z filter | Energy | Description |
|---------|----------|----------|----------|--------|-------------|
| `LLL` | Low | Low | Low | Highest | Approximation (coarsest scale) |
| `LLH` | Low | Low | High | Medium | Z-direction edges |
| `LHL` | Low | High | Low | Medium | Y-direction edges |
| `LHH` | Low | High | High | Low | YZ diagonal edges |
| `HLL` | High | Low | Low | Medium | X-direction edges |
| `HLH` | High | Low | High | Low | XZ diagonal edges |
| `HHL` | High | High | Low | Low | XY diagonal edges |
| `HHH` | High | High | High | Lowest | 3D corner features |

### Filter Banks

| Mode | Filter | Reversible | Application |
|------|--------|-----------|-------------|
| Lossless | Le Gall 5/3 | Yes | Lossless compression |
| Lossy | CDF 9/7 (Daubechies) | No | Rate-distortion optimal |
| HTJ2K | Configurable (5/3 or 9/7) | Both | High-throughput path |

### Decomposition Levels

The default configuration uses 5 decomposition levels along X and Y, and 3 along Z:

```
Default: nLevelsXY = 5, nLevelsZ = 3

This creates a 3D multi-resolution pyramid suitable for:
  • 256×256×16 minimum volume at default tiling
  • Efficient progressive-resolution delivery
  • Good compression of inter-slice correlation
```

---

## Tile Structure

### JP3DTile and JP3DPrecinct

```
Volume (W × H × D)
└── Tiles (tileW × tileH × tileD each)
    └── Components
        └── Resolution levels (per DWT decomposition)
            └── Precincts (JP3DPrecinct)
                └── Code-blocks (entropy-coded units)
```

### Tile Coordinate System

A tile at grid position `(tx, ty, tz)` covers:

```
x: [tx * tileWidth  ..< (tx+1) * tileWidth ] clipped to [0..<W]
y: [ty * tileHeight ..< (ty+1) * tileHeight] clipped to [0..<H]
z: [tz * tileDepth  ..< (tz+1) * tileDepth ] clipped to [0..<D]
```

```swift
// Access tile metadata after encoding
let encoderResult: JP3DEncoderResult = ...
print("Total tiles: \(encoderResult.tileCount)")

// Tiles are indexed linearly: tileIndex = tz * numTilesXY + ty * numTilesX + tx
```

---

## Actor Concurrency Model

### Swift 6 Actor Isolation

Both `JP3DEncoder` and `JP3DDecoder` are declared as `actor` types, providing automatic mutual exclusion for their mutable state:

```swift
// JP3DEncoder is an actor — all methods are async
public actor JP3DEncoder {
    public let configuration: JP3DEncoderConfiguration

    public init(configuration: JP3DEncoderConfiguration)

    public func encode(_ volume: J2KVolume) async throws -> JP3DEncoderResult
    public func encode(_ volume: J2KVolume, region: JP3DRegion) async throws -> JP3DEncoderResult
}

// JP3DDecoder is an actor — all methods are async
public actor JP3DDecoder {
    public let configuration: JP3DDecoderConfiguration

    public init(configuration: JP3DDecoderConfiguration = JP3DDecoderConfiguration())

    public func decode(_ data: Data) async throws -> JP3DDecoderResult
    public func decode(_ data: Data, region: JP3DRegion) async throws -> JP3DDecoderResult
}
```

### Concurrency Safety of Value Types

All configuration structs and result types are `Sendable`:

```swift
// These cross actor boundaries safely
public struct JP3DEncoderConfiguration: Sendable { ... }
public struct JP3DDecoderConfiguration: Sendable { ... }
public struct JP3DEncoderResult: Sendable { ... }
public struct JP3DDecoderResult: Sendable { ... }
public struct J2KVolume: Sendable { ... }
public struct J2KVolumeComponent: Sendable { ... }
public struct JP3DRegion: Sendable { ... }
```

### Using Multiple Encoders in Parallel

Because each `JP3DEncoder` is an independent actor, you can run multiple encoders concurrently:

```swift
// Encode multiple volumes in parallel
let volumes: [J2KVolume] = loadVolumeBatch()
let results = try await withThrowingTaskGroup(of: JP3DEncoderResult.self) { group in
    for volume in volumes {
        group.addTask {
            let encoder = JP3DEncoder(configuration: .lossless)
            return try await encoder.encode(volume)
        }
    }
    return try await group.reduce(into: []) { $0.append($1) }
}
```

### JP3DJPIPClient as Actor

`JP3DJPIPClient` is also an actor, managing a persistent JPIP session with automatic concurrency control:

```swift
public actor JP3DJPIPClient {
    public func connect() async throws
    public func disconnect() async throws
    public func createSession(volumeID: String) async throws -> JPIPSession
    public func requestRegion(_ region: JP3DRegion) async throws -> Data
    public func requestSliceRange(zRange: Range<Int>, quality: Int) async throws -> Data
    public func updateViewport(_ viewport: JP3DViewport) async throws
}
```

---

## Memory Management

### Copy-on-Write for J2KVolume

`J2KVolume` and `J2KVolumeComponent` use `Data` as their backing store, which is a copy-on-write type. Passing volumes across actors involves no buffer copying unless mutation occurs:

```swift
// Efficient: no copy until mutation
let volume = largeVolume
let encoded = try await encoder.encode(volume)  // volume not mutated — no copy
```

### Tile-Based Memory Footprint

Encoding does not buffer the full volume of wavelet coefficients simultaneously. Each tile is processed and serialized before the next is started, keeping peak memory proportional to the largest tile:

```
Peak memory ≈ 2 × (tileWidth × tileHeight × tileDepth × componentCount × bytesPerVoxel)
            × numberOfConcurrentTileWorkers
```

For `.streaming` tiling (128×128×8) with 8-bit mono:
```
Peak ≈ 2 × (128 × 128 × 8 × 1 × 1) × 8 ≈ 2 MB
```

### Decoder Memory Pool

`JP3DDecoder` maintains an internal tile buffer pool to avoid repeated allocations. The pool is bounded by `JP3DDecoderConfiguration.maxPooledTileBuffers` (default: 16):

```swift
let config = JP3DDecoderConfiguration(
    maxPooledTileBuffers: 32  // Increase for large parallel decodes
)
```

### Autoreleasepool in Batch Processing

When processing many volumes in a loop, wrap each iteration in `autoreleasepool` to ensure timely deallocation of Objective-C-bridged buffers on Apple platforms:

```swift
for url in volumeURLs {
    autoreleasepool {
        let data = try! Data(contentsOf: url)
        let result = try! await decoder.decode(data)
        // process result...
    }
}
```

---

## Cross-Platform Strategy

### Compile-Time Feature Detection

```swift
// J2K3D uses conditional compilation for platform-specific paths

#if canImport(Accelerate)
// Apple platforms: vDSP-accelerated DWT, vImage color transforms
import Accelerate
#endif

#if canImport(Metal)
// Apple platforms: Metal compute shaders for parallel DWT
import Metal
#endif

// Linux / Windows: pure Swift SIMD fallback
```

### Acceleration Tier Summary

| Tier | Platform | Technology | DWT Speedup |
|------|----------|-----------|-------------|
| Tier 3 (baseline) | All | Pure Swift + SIMD | 1× |
| Tier 2 | Apple | Accelerate vDSP | ~3–5× |
| Tier 1 | Apple | Metal compute shaders | ~8–15× |

The library selects the highest available tier automatically at runtime. No configuration is needed.

### Linux Build Notes

On Linux, the J2KAccelerate and J2KMetal modules are excluded from compilation. Only the `J2KCore`, `J2K3D`, `JPIP`, and `J2KFileFormat` modules are available:

```swift
// Package.swift — conditional platform dependency
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2K3D", package: "J2KSwift"),
        // J2KAccelerate and J2KMetal are Apple-only and excluded automatically
    ]
)
```

### Windows Notes

Windows support is experimental. Software encoding is available, but `J2KMetal` is not available. `J2KAccelerate` uses a partial WinRT DSP path where available.

---

## Extension Points

### Custom Progression Order

Implement `JP3DProgressionOrderProvider` to create custom packet ordering:

```swift
public protocol JP3DProgressionOrderProvider: Sendable {
    func packetOrder(for tile: JP3DTile) -> [JP3DPacketAddress]
}
```

### Custom Entropy Coder

The entropy coding stage can be replaced via `JP3DEntropyCoderProvider`:

```swift
public protocol JP3DEntropyCoderProvider: Sendable {
    func makeCoder(for configuration: JP3DEncoderConfiguration) -> any JP3DEntropyCoder
    func makeDecoder(for configuration: JP3DDecoderConfiguration) -> any JP3DEntropyDecoder
}
```

### Plugin Registration

```swift
import J2K3D

// Register custom coder before first use
JP3DCodecRegistry.shared.registerEntropyCoder(MyCustomCoder(), forKey: "custom")

// Use in configuration
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    entropyCoder: "custom"
)
```

> **Note:** Custom entropy coders must be registered before any `JP3DEncoder` or `JP3DDecoder` is created in your process. Thread safety is the responsibility of the registering code.
