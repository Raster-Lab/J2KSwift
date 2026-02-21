# Decoding Guide

This guide covers all decoding options in J2KSwift, including full-image decoding,
progressive decoding, region-of-interest (ROI) decoding, and resolution-level decoding.

---

## Quick Reference

```swift
import J2KCodec

let decoder = J2KDecoder()
let image   = try decoder.decode(data)
```

---

## J2KDecoder

`J2KDecoder` is a lightweight, `Sendable` struct that decodes any valid JPEG 2000
codestream or JP2/JPX/JPH file.

```swift
// Decode a full image
let decoder = J2KDecoder()
let image: J2KImage = try decoder.decode(data)
```

---

## Reading from a File

```swift
import J2KFileFormat

let reader = J2KFileReader()
let image  = try reader.read(from: URL(fileURLWithPath: "/path/to/image.jp2"))

// Auto-detect format and validate before decoding
let format = try reader.detectFormat(at: URL(fileURLWithPath: "image.j2k"))
print("Format: \(format.rawValue)")
```

---

## Progressive Decoding

Use `J2KIncrementalDecoder` to decode a codestream as it arrives over a network or
from a streaming source.

```swift
import J2KCodec

let incremental = J2KIncrementalDecoder()

// Feed chunks as they arrive
incremental.append(firstChunk)
incremental.append(secondChunk)

// Attempt to decode with whatever data is available
if let partial = try incremental.tryDecode() {
    print("Partial image: \(partial.width)×\(partial.height)")
}

// Mark stream as complete and get final image
incremental.complete()
let finalImage = try incremental.tryDecode()!
```

---

## Region-of-Interest (ROI) Decoding

Decode only a sub-region of the image, avoiding unnecessary decompression of the
full frame.  Requires a tiled codestream for best performance.

```swift
import J2KCodec

let advancedDecoder = J2KAdvancedDecoder()

let options = J2KROIDecodingOptions(
    regionX: 512,
    regionY: 256,
    regionWidth: 256,
    regionHeight: 256
)
let roi: J2KImage = try advancedDecoder.decodeRegion(data, options: options)
```

---

## Resolution-Level Decoding

Decode at a lower resolution to produce a thumbnail or overview without decoding
the full-resolution data.

```swift
let options = J2KResolutionDecodingOptions(
    resolutionLevel: 3   // 0 = full resolution, N = 1/(2^N) resolution
)
let thumbnail: J2KImage = try advancedDecoder.decodeResolution(data, options: options)
// thumbnail.width  ≈ image.width  / 8
// thumbnail.height ≈ image.height / 8
```

---

## Quality-Layer Decoding

Decode only a subset of quality layers to trade quality for speed.

```swift
let options = J2KQualityDecodingOptions(
    qualityLayers: 2   // decode only the first 2 of N layers
)
let draft: J2KImage = try advancedDecoder.decodeQuality(data, options: options)
```

---

## Partial Decoding

```swift
let options = J2KPartialDecodingOptions(
    resolutionLevel: 2,
    qualityLayers: 4,
    components: [0, 1, 2]
)
let partial: J2KImage = try advancedDecoder.decodePartial(data, options: options)
```

---

## Accessing Pixel Data

```swift
for component in image.components {
    let bytes = component.data       // Raw pixel bytes
    let width  = component.width
    let height = component.height
    let depth  = component.bitDepth  // e.g., 8, 12, 16
}
```

---

## Error Handling

```swift
do {
    let image = try decoder.decode(data)
} catch J2KError.invalidData(let msg) {
    print("Invalid codestream: \(msg)")
} catch J2KError.unsupportedFeature(let msg) {
    print("Unsupported: \(msg)")
} catch {
    print("Decode error: \(error)")
}
```

---

## See Also

- [Encoding Guide](ENCODING_GUIDE.md)
- [JPIP Guide](JPIP_GUIDE.md) — progressive delivery via network streaming
- [CLI Guide](CLI_GUIDE.md) — `j2k decode` command
- [Examples/ProgressiveDecoding.swift](../Examples/ProgressiveDecoding.swift)
