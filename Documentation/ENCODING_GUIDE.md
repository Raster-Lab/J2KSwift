# Encoding Guide

This guide covers all encoding options available in J2KSwift, from basic usage to
advanced tile-based and progression-order configurations.

---

## Quick Reference

```swift
import J2KCore
import J2KCodec

let encoder = J2KEncoder(configuration: .balanced)
let data    = try encoder.encode(image)
```

---

## J2KEncoder

`J2KEncoder` is a lightweight, `Sendable` struct.  Two initialisers are available:

```swift
// Initialise with a simple quality preset
let encoder = J2KEncoder(configuration: .lossless)

// Initialise with a full J2KEncodingConfiguration for fine-grained control
let config = J2KEncodingConfiguration(
    progressionOrder: .LRCP,
    qualityLayers: 6,
    decompositionLevels: 5,
    useHTJ2K: false
)
let encoder = J2KEncoder(encodingConfiguration: config)
```

---

## Quality Presets

| Preset             | Quality | Recommended for |
|--------------------|---------|-----------------|
| `.lossless`        | 1.00    | Medical imaging, archival |
| `.highQuality`     | 0.95    | Professional photography |
| `.balanced`        | 0.85    | General purpose |
| `.fast`            | 0.70    | Web delivery |
| `.maxCompression`  | 0.50    | Bandwidth-constrained delivery |

```swift
let archiveEncoder = J2KEncoder(configuration: .lossless)
let webEncoder     = J2KEncoder(configuration: .fast)
```

---

## J2KEncodingConfiguration

For precise control over every encoding parameter:

```swift
let config = J2KEncodingConfiguration(
    progressionOrder: .RLCP,    // resolution–layer–component–precinct
    qualityLayers: 8,
    decompositionLevels: 5,
    codeBlockWidth: 64,
    codeBlockHeight: 64,
    useHTJ2K: false,
    enableEPH: true,             // End-of-Packet Header markers
    enableSOP: true,             // Start-Of-Packet markers
    multipleComponentTransform: true
)
```

### Progression Orders

| Value  | Description |
|--------|-------------|
| `.LRCP` | Layer–Resolution–Component–Precinct (best for quality-progressive delivery) |
| `.RLCP` | Resolution–Layer–Component–Precinct (best for resolution-progressive delivery) |
| `.RPCL` | Resolution–Precinct–Component–Layer |
| `.PCRL` | Precinct–Component–Resolution–Layer |
| `.CPRL` | Component–Precinct–Resolution–Layer |

---

## Tiling

Tiling divides the image into independently decodable rectangular regions.
This is essential for large images and JPIP streaming.

```swift
// Encode with 512×512 tiles
let tiled = J2KImage(
    width: 4096,
    height: 4096,
    components: components,
    tileWidth: 512,
    tileHeight: 512
)
let data = try encoder.encode(tiled)
```

---

## Lossless Encoding (Le Gall 5/3 wavelet)

```swift
let encoder = J2KEncoder(configuration: .lossless)
// The 5/3 reversible wavelet filter is selected automatically for lossless mode.
let data = try encoder.encode(image)
```

---

## Multi-Component Transform (MCT)

MCT (also called Multiple Component Transform) converts RGB to YCbCr before
encoding, improving compression efficiency for colour images.

- **Irreversible Colour Transform (ICT)** is used for lossy encoding.
- **Reversible Colour Transform (RCT)** is used for lossless encoding.

MCT is enabled by default when `multipleComponentTransform: true` is set in the
configuration and the image has three or more components.

---

## Writing to a File

```swift
import J2KFileFormat

let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: URL(fileURLWithPath: "output.jp2"), configuration: .balanced)

// Write raw codestream (no JP2 container)
let j2kWriter = J2KFileWriter(format: .j2k)
try j2kWriter.write(image, to: URL(fileURLWithPath: "output.j2k"))

// Write HTJ2K codestream (JPH container)
let jphWriter = J2KFileWriter(format: .jph)
try jphWriter.write(image, to: URL(fileURLWithPath: "output.jph"))
```

---

## Error Handling

Encoding throws `J2KError` on failure:

```swift
do {
    let data = try encoder.encode(image)
} catch J2KError.invalidParameter(let msg) {
    print("Bad parameter: \(msg)")
} catch J2KError.internalError(let msg) {
    print("Internal error: \(msg)")
} catch {
    print("Unexpected error: \(error)")
}
```

---

## See Also

- [HTJ2K Guide](HTJ2K_GUIDE.md) — High-Throughput JPEG 2000 encoding
- [Metal GPU Guide](METAL_GPU_GUIDE.md) — GPU-accelerated encoding on Apple platforms
- [CLI Guide](CLI_GUIDE.md) — `j2k encode` command
- [Examples/BasicEncoding.swift](../Examples/BasicEncoding.swift)
