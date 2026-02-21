# JP3D Guide — Volumetric Imaging

The `J2K3D` module extends JPEG 2000 to three-dimensional volumetric data
(ISO/IEC 15444-10, JP3D).  Typical use cases include CT/MRI medical volumes,
seismic data cubes, and scientific simulation outputs.

---

## Core Types

| Type | Description |
|------|-------------|
| `J2KVolume` | 3-D image with width × height × depth voxels |
| `J2KVolumeComponent` | Per-component descriptor (bit depth, subsampling, voxel spacing) |
| `J2KVolumeMetadata` | Medical metadata (modality, patient ID, window centre/width) |
| `JP3DEncoder` (actor) | Encodes a volume to JP3D codestream |
| `JP3DDecoder` (actor) | Decodes a JP3D codestream back to a volume |
| `JP3DEncoderConfiguration` | Encoding parameters |
| `JP3DDecoderConfiguration` | Decoding parameters |

---

## Creating a Volume

```swift
import J2K3D

// Describe a single 8-bit component: 256×256×64 voxels
let component = J2KVolumeComponent(
    index: 0,
    bitDepth: 8,
    signed: false,
    width: 256,
    height: 256,
    depth: 64
)

// Voxel data (width × height × depth bytes per component)
let voxelData = Data(repeating: 128, count: 256 * 256 * 64)

let volume = J2KVolume(
    width: 256,
    height: 256,
    depth: 64,
    components: [component],
    voxelData: [voxelData]
)
```

### Medical Metadata

```swift
var metadata = J2KVolumeMetadata()
metadata.modality = "CT"
metadata.patientID = "ANON-001"
metadata.windowCenter = 40.0    // HU
metadata.windowWidth  = 400.0   // HU

let volume = J2KVolume(
    width: 512,
    height: 512,
    depth: 128,
    components: [component],
    voxelData: [voxelData],
    metadata: metadata
)
```

---

## Encoding a Volume

```swift
import J2K3D

let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    decompositionLevelsXY: 5,
    decompositionLevelsZ: 3,
    tileWidth: 64,
    tileHeight: 64,
    tileDepth: 16,
    progressionOrder: .LRCPS
)

let encoder = JP3DEncoder(configuration: config)

// Optional progress callback
await encoder.setProgressCallback { progress in
    print("Encoding \(progress.percentComplete)%")
}

let result: JP3DEncoderResult = try await encoder.encode(volume)
print("Encoded \(result.data.count) bytes")
```

### Compression Modes

| Mode | Description |
|------|-------------|
| `.lossless` | Reversible 5/3 wavelet, no quality loss |
| `.lossy` | Irreversible 9/7 wavelet |
| `.targetBitrate` | Rate-controlled encoding |
| `.targetPSNR` | PSNR-targeted encoding |
| `.visuallyLossless` | Perceptually transparent |
| `.htj2k` | HTJ2K block coder for maximum throughput |

---

## Decoding a Volume

```swift
import J2K3D

let decoder = JP3DDecoder()

let result: JP3DDecoderResult = try await decoder.decode(data)
let volume  = result.volume
print("\(volume.width)×\(volume.height)×\(volume.depth) voxels")
```

### Metadata Peek (without full decode)

```swift
let info: JP3DSIZInfo = try decoder.peekMetadata(data)
print("Volume: \(info.width)×\(info.height)×\(info.depth)")
```

---

## Streaming Encoding (Slice-by-Slice)

For very large volumes that do not fit in memory, use `JP3DStreamWriter`:

```swift
import J2K3D

let writer = JP3DStreamWriter(configuration: config)

for sliceIndex in 0 ..< volume.depth {
    let sliceData = loadSlice(index: sliceIndex)
    try await writer.addSlice(sliceData, atIndex: sliceIndex)
}

let finalData = try await writer.finalise()
```

---

## Metal GPU DWT (Apple Platforms)

```swift
import J2KMetal

let metalDWT = JP3DMetalDWT()
try await metalDWT.initialize()

// Forward 3-D DWT along all axes
let coefficients = try await metalDWT.forwardMultiLevel(
    voxelData,
    width: 256,
    height: 256,
    depth: 64,
    xyLevels: 4,
    zLevels: 2,
    filter: .leGall53
)
```

---

## JPIP Streaming of JP3D Volumes

```swift
import JPIP
import J2K3D

let client = JP3DJPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)
let session = try await client.createSession(target: "volumes/ct_scan.jp3d")

// Request a sub-volume (axial slab: slices 10–20)
let slab = try await client.requestSubvolume(
    sliceRange: 10 ..< 20,
    resolutionLevel: 1
)
```

---

## HTJ2K Encoding of Volumes

```swift
import J2K3D

let htConfig = JP3DHTJ2KConfiguration.lowLatency
let htEncoder = JP3DEncoder(configuration: JP3DEncoderConfiguration(htj2k: htConfig))
let htResult  = try await htEncoder.encode(volume)
```

---

## Conformance

J2KSwift implements ISO/IEC 15444-10 (JP3D) and ISO/IEC 15444-2 Part 10.

---

## See Also

- [JP3D Architecture](JP3D_ARCHITECTURE.md)
- [JP3D Getting Started](JP3D_GETTING_STARTED.md)
- [JP3D HTJ2K Integration](JP3D_HTJ2K_INTEGRATION.md)
- [JPIP Guide](JPIP_GUIDE.md)
- [Examples/VolumetricImaging.swift](../Examples/VolumetricImaging.swift)
