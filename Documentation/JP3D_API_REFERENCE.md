# JP3D API Reference

## Table of Contents

1. [J2KVolume](#j2kvolume)
2. [J2KVolumeComponent](#j2kvolumecomponent)
3. [JP3DRegion](#jp3dregion)
4. [JP3DEncoder](#jp3dencoder)
5. [JP3DEncoderConfiguration](#jp3dencoderconfiguration)
6. [JP3DEncoderResult](#jp3dencoderresult)
7. [JP3DDecoder](#jp3ddecoder)
8. [JP3DDecoderConfiguration](#jp3ddecoderconfiguration)
9. [JP3DDecoderResult](#jp3ddecoderesult)
10. [JP3DCompressionMode](#jp3dcompressionmode)
11. [JP3DTilingConfiguration](#jp3dtilingconfiguration)
12. [JP3DProgressionOrder](#jp3dprogressionorder)
13. [JP3DTile](#jp3dtile)
14. [JP3DPrecinct](#jp3dprecinct)
15. [JP3DSubband](#jp3dsubband)
16. [J2K3DCoefficients](#j2k3dcoefficients)
17. [JP3DHTJ2KConfiguration](#jp3dhtj2kconfiguration)
18. [JP3DJPIPClient](#jp3djpipclient)
19. [JP3DViewport](#jp3dviewport)
20. [JP3DStreamingRegion](#jp3dstreamingregion)
21. [JP3DProgressionMode](#jp3dprogressionmode)

---

## J2KVolume

**Module:** `J2KCore`  
**Declaration:** `public struct J2KVolume: Sendable`

Represents a three-dimensional image volume composed of one or more components. Each component holds a separate array of voxel data.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `width` | `Int` | Number of voxels along the X axis |
| `height` | `Int` | Number of voxels along the Y axis |
| `depth` | `Int` | Number of voxels along the Z axis |
| `components` | `[J2KVolumeComponent]` | Ordered list of volume components (channels) |

### Initializer

```swift
public init(
    width: Int,
    height: Int,
    depth: Int,
    components: [J2KVolumeComponent]
)
```

**Parameters:**
- `width` — Must be ≥ 1.
- `height` — Must be ≥ 1.
- `depth` — Must be ≥ 2 for 3D encoding.
- `components` — Must have at least one element. All components must have matching `width`, `height`, and `depth`.

**Throws:** Does not throw; invalid arguments will produce runtime errors during encoding.

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| `voxelCount` | `Int` | `width * height * depth` |
| `componentCount` | `Int` | `components.count` |
| `isGrayscale` | `Bool` | `componentCount == 1` |
| `isColor` | `Bool` | `componentCount == 3` |

### Example

```swift
import J2KCore

let component = J2KVolumeComponent(
    index: 0,
    bitDepth: 16,
    signed: false,
    width: 512,
    height: 512,
    depth: 256,
    data: rawCTData
)
let volume = J2KVolume(width: 512, height: 512, depth: 256, components: [component])
print(volume.voxelCount)  // 67,108,864
```

---

## J2KVolumeComponent

**Module:** `J2KCore`  
**Declaration:** `public struct J2KVolumeComponent: Sendable`

A single scalar component of a `J2KVolume`. For a grayscale CT scan, there is one component. For an RGB volume, there are three.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `index` | `Int` | Zero-based component index |
| `bitDepth` | `Int` | Bits per voxel (8, 10, 12, 14, 16, or 32) |
| `signed` | `Bool` | `true` if voxel values are signed integers |
| `width` | `Int` | Component width in voxels |
| `height` | `Int` | Component height in voxels |
| `depth` | `Int` | Component depth in voxels |
| `data` | `Data` | Raw voxel bytes in raster-z order: `[z0y0x0, z0y0x1, ..., z(D-1)y(H-1)x(W-1)]` |

### Initializer

```swift
public init(
    index: Int,
    bitDepth: Int,
    signed: Bool,
    width: Int,
    height: Int,
    depth: Int,
    data: Data
)
```

**Data Layout:** Voxels are stored in interleaved Z-Y-X order. For 16-bit components, each voxel occupies 2 bytes in big-endian order.

**Required data length:** `width * height * depth * (bitDepth / 8)` bytes.

### Supported Bit Depths

| `bitDepth` | `signed` | Typical Use |
|-----------|---------|-------------|
| 8 | false | 8-bit grayscale, RGBA textures |
| 10 | false | HDR displays |
| 12 | false | Medical DICOM 12-bit |
| 16 | false | Medical DICOM 16-bit |
| 16 | true | Signed CT Hounsfield units |
| 32 | false | Float scientific data |
| 32 | true | Signed float scientific data |

### Example

```swift
import J2KCore

// 16-bit signed (Hounsfield units from CT scanner)
let bytesNeeded = 512 * 512 * 256 * 2  // 2 bytes per voxel
var data = Data(count: bytesNeeded)
// ... fill data from DICOM source ...

let ctComponent = J2KVolumeComponent(
    index: 0,
    bitDepth: 16,
    signed: true,
    width: 512,
    height: 512,
    depth: 256,
    data: data
)
```

---

## JP3DRegion

**Module:** `J2KCore`  
**Declaration:** `public struct JP3DRegion: Sendable`

Describes a rectangular sub-region of a `J2KVolume` for partial encode or decode operations.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `x` | `Range<Int>` | Voxel range along X axis (exclusive upper bound) |
| `y` | `Range<Int>` | Voxel range along Y axis |
| `z` | `Range<Int>` | Voxel range along Z axis |

### Initializer

```swift
public init(x: Range<Int>, y: Range<Int>, z: Range<Int>)
```

### Computed Properties

| Property | Type | Description |
|----------|------|-------------|
| `width` | `Int` | `x.count` |
| `height` | `Int` | `y.count` |
| `depth` | `Int` | `z.count` |
| `voxelCount` | `Int` | `width * height * depth` |

### Example

```swift
import J2KCore

// Decode only the central slab
let roi = JP3DRegion(
    x: 128..<384,
    y: 128..<384,
    z: 64..<192
)

let result = try await decoder.decode(data, region: roi)
```

---

## JP3DEncoder

**Module:** `J2K3D`  
**Declaration:** `public actor JP3DEncoder`

Encodes a `J2KVolume` into a JP3D-compliant bitstream. Thread-safe via Swift actor isolation.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `configuration` | `JP3DEncoderConfiguration` | The configuration used by this encoder |

### Type Properties

| Property | Type | Description |
|----------|------|-------------|
| `version` | `String` | Library version string, e.g. `"J2K3D 1.9.0"` |
| `capabilities` | `JP3DCapabilities` | Runtime capability flags |

### Initializers

```swift
public init(configuration: JP3DEncoderConfiguration)
public init(configuration: JP3DEncoderConfiguration = .default)
```

### Methods

#### encode(_:)

```swift
public func encode(_ volume: J2KVolume) async throws -> JP3DEncoderResult
```

Encodes the entire volume.

- **Parameter** `volume` — Volume to encode.
- **Returns:** `JP3DEncoderResult` containing the compressed bitstream and metadata.
- **Throws:** `J2KError.invalidParameter` if the volume is malformed; `J2KError.internalError` on codec failure; `J2KError.outOfMemory` if insufficient memory.

#### encode(_:region:)

```swift
public func encode(_ volume: J2KVolume, region: JP3DRegion) async throws -> JP3DEncoderResult
```

Encodes only the specified sub-region of the volume.

- **Parameter** `region` — Must be fully contained within the volume dimensions.

### Example

```swift
import J2K3D

let encoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(
    compressionMode: .lossy(psnr: 45.0),
    tiling: .default
))

let result = try await encoder.encode(volume)
print("Compressed to \(result.data.count) bytes")
print("Ratio: \(result.compressionRatio)×")
```

---

## JP3DEncoderConfiguration

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DEncoderConfiguration: Sendable`

All parameters controlling JP3D encoding behaviour.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `compressionMode` | `JP3DCompressionMode` | `.lossless` | Compression quality strategy |
| `tiling` | `JP3DTilingConfiguration` | `.default` | Tile dimensions |
| `progressionOrder` | `JP3DProgressionOrder` | `.lrcps` | Packet progression order |
| `qualityLayers` | `Int` | `8` | Number of quality layers (1–64) |
| `decompositionLevelsXY` | `Int` | `5` | DWT levels along X and Y |
| `decompositionLevelsZ` | `Int` | `3` | DWT levels along Z |
| `htj2kConfiguration` | `JP3DHTJ2KConfiguration?` | `nil` | HTJ2K settings (used when compressionMode is `.losslessHTJ2K` or `.lossyHTJ2K`) |
| `enableColorTransform` | `Bool` | `true` | Apply RCT/ICT for multi-component volumes |

### Static Presets

```swift
JP3DEncoderConfiguration.lossless         // lossless + .default tiling
JP3DEncoderConfiguration.visuallyLossless // visuallyLossless + .default tiling
JP3DEncoderConfiguration.streaming        // lossy(psnr:42) + .streaming tiling + .lrcps
```

### Example

```swift
let config = JP3DEncoderConfiguration(
    compressionMode: .lossy(psnr: 40.0),
    tiling: .streaming,
    progressionOrder: .slrcp,
    qualityLayers: 12,
    decompositionLevelsXY: 5,
    decompositionLevelsZ: 3
)
```

---

## JP3DEncoderResult

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DEncoderResult: Sendable`

The output of a successful `JP3DEncoder.encode` call.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `data` | `Data` | The compressed JP3D bitstream |
| `width` | `Int` | Source volume width |
| `height` | `Int` | Source volume height |
| `depth` | `Int` | Source volume depth |
| `componentCount` | `Int` | Number of components |
| `isLossless` | `Bool` | `true` if no information was discarded |
| `tileCount` | `Int` | Total number of encoded tiles |
| `compressionRatio` | `Double` | `rawBytes / compressedBytes` |

### Example

```swift
let result = try await encoder.encode(volume)
print("""
  Dimensions:  \(result.width)×\(result.height)×\(result.depth)
  Components:  \(result.componentCount)
  Tiles:       \(result.tileCount)
  Lossless:    \(result.isLossless)
  Ratio:       \(String(format: "%.2f", result.compressionRatio))×
  Bytes:       \(result.data.count)
""")
```

---

## JP3DDecoder

**Module:** `J2K3D`  
**Declaration:** `public actor JP3DDecoder`

Decodes a JP3D bitstream back to a `J2KVolume`.

### Initializer

```swift
public init(configuration: JP3DDecoderConfiguration = JP3DDecoderConfiguration())
```

### Methods

#### decode(_:)

```swift
public func decode(_ data: Data) async throws -> JP3DDecoderResult
```

Decodes the full bitstream.

#### decode(_:region:)

```swift
public func decode(_ data: Data, region: JP3DRegion) async throws -> JP3DDecoderResult
```

Decodes only the voxels within `region`, skipping unneeded tiles.

#### decode(_:resolutionLevel:)

```swift
public func decode(_ data: Data, resolutionLevel: Int) async throws -> JP3DDecoderResult
```

Decodes at a reduced resolution. `resolutionLevel: 0` is full resolution; each increment halves dimensions along each axis.

### Example

```swift
import J2K3D

let decoder = JP3DDecoder()

// Full decode
let fullResult = try await decoder.decode(compressedData)

// Thumbnail (1/8 resolution)
let thumbResult = try await decoder.decode(compressedData, resolutionLevel: 3)
print("Thumbnail: \(thumbResult.volume.width)×\(thumbResult.volume.height)×\(thumbResult.volume.depth)")
```

---

## JP3DDecoderConfiguration

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DDecoderConfiguration: Sendable`

Parameters controlling decoding behaviour.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `maxQualityLayer` | `Int?` | `nil` | Decode up to this quality layer only (`nil` = all) |
| `resolutionReduction` | `Int` | `0` | Decode at `1/(2^n)` resolution |
| `maxPooledTileBuffers` | `Int` | `16` | Maximum tile buffers to pool |
| `validateChecksums` | `Bool` | `true` | Verify PLT/TLM markers |
| `tolerateTruncation` | `Bool` | `false` | Return partial result on truncated bitstream |

### Example

```swift
let config = JP3DDecoderConfiguration(
    maxQualityLayer: 4,         // decode first 4 quality layers only
    resolutionReduction: 1,     // half resolution
    tolerateTruncation: true    // return partial data rather than throwing
)
let decoder = JP3DDecoder(configuration: config)
```

---

## JP3DDecoderResult

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DDecoderResult: Sendable`

The output of a `JP3DDecoder.decode` call.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `volume` | `J2KVolume` | The decoded volume |
| `isPartial` | `Bool` | `true` if the bitstream was truncated or some tiles failed |
| `warnings` | `[String]` | Non-fatal issues encountered during decoding |
| `tilesDecoded` | `Int` | Number of tiles successfully decoded |
| `tilesTotal` | `Int` | Total tiles expected in the bitstream |

### Example

```swift
let result = try await decoder.decode(data)

guard !result.isPartial else {
    print("Partial decode: \(result.tilesDecoded)/\(result.tilesTotal) tiles")
    result.warnings.forEach { print("⚠️ \($0)") }
    // Use result.volume — may have gaps
    return
}

let vol = result.volume
```

---

## JP3DCompressionMode

**Module:** `J2K3D`  
**Declaration:** `public enum JP3DCompressionMode: Sendable`

Controls the quality/size trade-off for encoding.

### Cases

| Case | Parameters | Description |
|------|-----------|-------------|
| `.lossless` | — | Bit-exact reconstruction using Le Gall 5/3 DWT |
| `.lossy(psnr:)` | `psnr: Double` | Target PSNR in dB per component (typical: 35–50) |
| `.targetBitrate(bitsPerVoxel:)` | `bitsPerVoxel: Double` | Exact bits-per-voxel budget |
| `.visuallyLossless` | — | Perceptually lossless (~45 dB PSNR equivalent) |
| `.losslessHTJ2K` | — | Bit-exact using ISO 15444-15 high-throughput coder |
| `.lossyHTJ2K(psnr:)` | `psnr: Double` | PSNR-targeted using high-throughput coder |

### Example

```swift
// Exactly 1.5 bits per voxel budget
let bitrate = JP3DCompressionMode.targetBitrate(bitsPerVoxel: 1.5)

// 42 dB with fast HTJ2K
let fast = JP3DCompressionMode.lossyHTJ2K(psnr: 42.0)

let config = JP3DEncoderConfiguration(compressionMode: fast, tiling: .streaming)
```

---

## JP3DTilingConfiguration

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DTilingConfiguration: Sendable`

Controls how a volume is partitioned into independently-compressed tiles.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `tileWidth` | `Int` | Tile size along X (must be ≥ 16) |
| `tileHeight` | `Int` | Tile size along Y |
| `tileDepth` | `Int` | Tile size along Z |

### Static Presets

| Preset | Width | Height | Depth | Best For |
|--------|-------|--------|-------|---------|
| `.default` | 256 | 256 | 16 | General-purpose |
| `.streaming` | 128 | 128 | 8 | JPIP low-latency delivery |
| `.batch` | 512 | 512 | 32 | Offline throughput |

### Custom Tiling

```swift
// Thin-slab tiling for slice-by-slice medical access
let slabConfig = JP3DTilingConfiguration(
    tileWidth: 512,
    tileHeight: 512,
    tileDepth: 4    // Very thin in Z for fast slice retrieval
)
```

---

## JP3DProgressionOrder

**Module:** `J2K3D`  
**Declaration:** `public enum JP3DProgressionOrder: Sendable`

Determines the order in which packets are written to the bitstream.

### Cases

| Case | Mnemonic | Best For |
|------|---------|---------|
| `.lrcps` | Layer-Resolution-Component-Position | General quality-progressive |
| `.rlcps` | Resolution-Layer-Component-Position | Thumbnail-first delivery |
| `.pcrls` | Position-Component-Resolution-Layer | Spatial ROI priority |
| `.slrcp` | Slice-Layer-Resolution-Component-Position | Medical slice streaming |
| `.cprls` | Component-Position-Resolution-Layer | Multi-spectral priority |

### Example

```swift
// Slice-by-slice for medical imaging JPIP server
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .streaming,
    progressionOrder: .slrcp
)
```

---

## JP3DTile

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DTile: Sendable`

Metadata about a single tile within an encoded volume.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `index` | `Int` | Linear tile index |
| `region` | `JP3DRegion` | Volume coordinates this tile covers |
| `byteOffset` | `Int` | Byte offset within the bitstream |
| `byteLength` | `Int` | Compressed size in bytes |
| `qualityLayers` | `Int` | Number of quality layers in this tile |

---

## JP3DPrecinct

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DPrecinct: Sendable`

Represents a precinct within a tile — the unit of spatial random access within a quality layer.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `tileIndex` | `Int` | Parent tile index |
| `resolutionLevel` | `Int` | DWT resolution level (0 = finest) |
| `componentIndex` | `Int` | Component this precinct belongs to |
| `region` | `JP3DRegion` | Volume region at this resolution |

---

## JP3DSubband

**Module:** `J2K3D`  
**Declaration:** `public enum JP3DSubband: Sendable`

The eight subbands produced by a single-level 3D DWT.

### Cases

| Case | X filter | Y filter | Z filter |
|------|---------|---------|---------|
| `.lll` | Low | Low | Low |
| `.llh` | Low | Low | High |
| `.lhl` | Low | High | Low |
| `.lhh` | Low | High | High |
| `.hll` | High | Low | Low |
| `.hlh` | High | Low | High |
| `.hhl` | High | High | Low |
| `.hhh` | High | High | High |

---

## J2K3DCoefficients

**Module:** `J2K3D`  
**Declaration:** `public struct J2K3DCoefficients: Sendable`

Holds wavelet coefficients for a single subband of a single component at one resolution level.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `subband` | `JP3DSubband` | Which subband these coefficients belong to |
| `width` | `Int` | Coefficient array width |
| `height` | `Int` | Coefficient array height |
| `depth` | `Int` | Coefficient array depth |
| `values` | `[Float]` | Coefficient values in Z-Y-X order |

---

## JP3DHTJ2KConfiguration

**Module:** `J2K3D`  
**Declaration:** `public struct JP3DHTJ2KConfiguration: Sendable`

Fine-grained HTJ2K (ISO 15444-15) configuration for use with `.losslessHTJ2K` and `.lossyHTJ2K` compression modes.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `codeBlockWidth` | `Int` | `64` | Code-block width (32 or 64) |
| `codeBlockHeight` | `Int` | `64` | Code-block height (32 or 64) |
| `codeBlockDepth` | `Int` | `4` | Code-block depth |
| `enableROI` | `Bool` | `false` | Region-of-interest upshift |
| `singlePassHTJ2K` | `Bool` | `true` | Use single-pass fast block coding |

### Example

```swift
let htj2kConfig = JP3DHTJ2KConfiguration(
    codeBlockWidth: 64,
    codeBlockHeight: 64,
    codeBlockDepth: 4,
    singlePassHTJ2K: true
)
let encoderConfig = JP3DEncoderConfiguration(
    compressionMode: .losslessHTJ2K,
    tiling: .batch,
    htj2kConfiguration: htj2kConfig
)
```

---

## JP3DJPIPClient

**Module:** `JPIP`  
**Declaration:** `public actor JP3DJPIPClient`

Manages a JPIP (ISO 15444-9) streaming session for incremental volumetric data delivery.

### Initializer

```swift
public init(serverURL: URL, configuration: JPIPClientConfiguration = .default)
```

### Methods

#### connect()

```swift
public func connect() async throws
```

Establishes the JPIP session with the server. Must be called before any request methods.

#### disconnect()

```swift
public func disconnect() async throws
```

Gracefully closes the JPIP session and releases network resources.

#### createSession(volumeID:)

```swift
public func createSession(volumeID: String) async throws -> JPIPSession
```

Creates a new JPIP session for the given volume identifier.

- **Returns:** A `JPIPSession` handle for subsequent requests.
- **Throws:** `JPIPError.volumeNotFound` if the server cannot locate the volume.

#### requestRegion(_:)

```swift
public func requestRegion(_ region: JP3DRegion) async throws -> Data
```

Requests the compressed data for the given 3D region from the current session.

#### requestSliceRange(zRange:quality:)

```swift
public func requestSliceRange(zRange: Range<Int>, quality: Int) async throws -> Data
```

Requests a contiguous range of Z slices at the given quality level (1–100).

#### updateViewport(_:)

```swift
public func updateViewport(_ viewport: JP3DViewport) async throws
```

Updates the current viewport, causing the server to prioritise data relevant to that view.

### Example

```swift
import JPIP

let client = JP3DJPIPClient(serverURL: URL(string: "jpip://imaging.hospital.org")!)

try await client.connect()
let session = try await client.createSession(volumeID: "CT_CHEST_001")

// Request a region of interest
let roi = JP3DRegion(x: 100..<300, y: 100..<300, z: 50..<150)
let data = try await client.requestRegion(roi)

// Decode incrementally
let decoder = JP3DDecoder(configuration: JP3DDecoderConfiguration(tolerateTruncation: true))
let result = try await decoder.decode(data)

try await client.disconnect()
```

---

## JP3DViewport

**Module:** `JPIP`  
**Declaration:** `public struct JP3DViewport: Sendable`

Describes the currently active rendering viewport for viewport-driven streaming.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `xRange` | `Range<Int>` | Visible X voxel range |
| `yRange` | `Range<Int>` | Visible Y voxel range |
| `zRange` | `Range<Int>` | Visible Z voxel range |

### Example

```swift
let viewport = JP3DViewport(
    xRange: 64..<192,
    yRange: 64..<192,
    zRange: 0..<64
)
try await client.updateViewport(viewport)
```

---

## JP3DStreamingRegion

**Module:** `JPIP`  
**Declaration:** `public struct JP3DStreamingRegion: Sendable`

Combines a spatial region with quality and resolution metadata for use in adaptive streaming.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `xRange` | `Range<Int>` | X voxel range |
| `yRange` | `Range<Int>` | Y voxel range |
| `zRange` | `Range<Int>` | Z voxel range |
| `qualityLayer` | `Int` | Target quality layer (1-based) |
| `resolutionLevel` | `Int` | Target resolution level (0 = full) |

### Example

```swift
let streamRegion = JP3DStreamingRegion(
    xRange: 0..<256,
    yRange: 0..<256,
    zRange: 0..<128,
    qualityLayer: 3,
    resolutionLevel: 1    // half resolution
)
```

---

## JP3DProgressionMode

**Module:** `JPIP`  
**Declaration:** `public enum JP3DProgressionMode: Sendable`

Controls how a `JP3DJPIPClient` prioritises streaming data delivery.

### Cases

| Case | Description |
|------|-------------|
| `.adaptive` | Automatically selects based on network conditions and viewport |
| `.resolutionFirst` | Deliver lowest resolution first, then refine |
| `.qualityFirst` | Deliver base quality for all tiles, then refine |
| `.sliceBySliceForward` | Deliver slices in ascending Z order |
| `.sliceBySliceReverse` | Deliver slices in descending Z order |
| `.sliceBySliceBidirectional` | Deliver slices outward from the current Z focus |
| `.viewDependent` | Prioritise tiles visible in the current viewport |
| `.distanceOrdered` | Prioritise tiles by distance from focal point |

### Example

```swift
let clientConfig = JPIPClientConfiguration(
    progressionMode: .viewDependent,
    maxConcurrentRequests: 4,
    cacheCapacityMB: 256
)
let client = JP3DJPIPClient(serverURL: serverURL, configuration: clientConfig)
```
