# Getting Started with J2KSwift

@Metadata {
    @PageKind(article)
}

Add J2KSwift to your project and start encoding and decoding JPEG 2000 images
in minutes.

## Adding J2KSwift to Your Project

Add the package dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git",
             from: "2.0.0"),
]
```

Then add the products you need to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2KCodec", package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),
    ]
)
```

> Tip: Only import the modules you actually use. ``J2KCore`` and ``J2KCodec``
> are sufficient for basic encoding and decoding. Add ``J2KFileFormat`` if you
> need to read or write JP2 container files, and ``JPIP`` for interactive
> streaming.

## Basic Encoding

Create a ``J2KEncoder``, optionally configure it, and call `encode(_:)`:

```swift
import J2KCodec

// Lossless encoding with default settings
let encoder = J2KEncoder()
let codestream = try encoder.encode(image)
```

For lossy compression, supply a ``J2KEncodingConfiguration``:

```swift
var config = J2KEncodingConfiguration()
config.isLossless = false
config.targetBitrate = 0.5  // bits per pixel

let encoder = J2KEncoder(configuration: config)
let codestream = try encoder.encode(image)
```

Or use a preset via ``J2KEncodingPreset``:

```swift
let encoder = J2KEncoder(preset: .highQuality)
let codestream = try encoder.encode(image)
```

## Basic Decoding

Create a ``J2KDecoder`` and call `decode(from:)`:

```swift
import J2KCodec

let decoder = J2KDecoder()
let image = try decoder.decode(from: codestreamData)

print("Size: \(image.width)×\(image.height)")
print("Components: \(image.componentCount)")
```

### Decoding a Region

Use ``J2KPartialDecodingOptions`` to decode only part of the image:

```swift
let options = J2KPartialDecodingOptions(
    region: .init(x: 0, y: 0, width: 512, height: 512)
)
let decoder = J2KDecoder()
let tile = try decoder.decode(from: codestreamData, options: options)
```

### Decoding at a Lower Resolution

Use ``J2KResolutionDecodingOptions`` to skip higher decomposition levels:

```swift
let options = J2KResolutionDecodingOptions(level: 3)
let decoder = J2KDecoder()
let thumbnail = try decoder.decode(from: codestreamData,
                                   resolutionOptions: options)
```

## File Format Detection

``J2KFormatDetector`` inspects the first bytes of a file to determine the
JPEG 2000 variant:

```swift
import J2KFileFormat

let format = J2KFormatDetector.detect(data: fileData)

switch format {
case .j2k:
    print("Raw JPEG 2000 codestream")
case .jp2:
    print("JP2 container file")
case .jpx:
    print("Extended JP2 (JPX) file")
case .mj2:
    print("Motion JPEG 2000 file")
default:
    print("Unknown format")
}
```

### Reading a JP2 File

``J2KFileReader`` parses the JP2 box structure and extracts the embedded
codestream:

```swift
let reader = J2KFileReader()
let file = try reader.read(from: jp2Data)
let image = try J2KDecoder().decode(from: file.codestream)
```

### Writing a JP2 File

``J2KFileWriter`` wraps a codestream in a JP2 container with the required
metadata boxes:

```swift
let writer = J2KFileWriter()
let jp2Data = try writer.write(codestream: codestream, image: image)
```

## Configuration Presets

``J2KEncodingPreset`` provides ready-made configurations for common
workflows:

| Preset                | Use Case                            |
|-----------------------|-------------------------------------|
| `.archivalLossless`   | Bit-perfect preservation            |
| `.highQuality`        | Visually lossless, moderate size    |
| `.balanced`           | Good quality at reasonable bitrates |
| `.streaming`          | Low-latency, bandwidth-constrained |

Each preset sets sensible defaults for wavelet levels, code-block sizes,
progression order, and quality layers.

## Platform Considerations

J2KSwift supports macOS 15+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+,
Linux, and Windows.

- **Apple platforms** — the ``J2KAccelerate`` module uses the Accelerate
  framework (vDSP, vImage) for faster transforms. ``J2KMetal`` adds GPU
  acceleration on devices with Metal support.
- **Linux / Windows** — ``J2KVulkan`` provides GPU acceleration where a
  Vulkan 1.2+ driver is available. The CPU-only path is always available as
  a fallback.
- **Concurrency** — all types conform to ``Sendable`` and work with Swift 6
  strict concurrency. Network services (``JPIPClient``, ``JPIPServer``) are
  actors.

> Important: The ``J2KMetal`` module is only compiled on platforms where Metal
> is available (`#if canImport(Metal)`). Likewise, ``J2KVulkan`` requires the
> Vulkan headers and loader at build time.

## Next Steps

- <doc:Architecture> — understand how the modules fit together.
- <doc:EncodingPipeline> — learn about every stage of encoding.
- <doc:DecodingPipeline> — learn about partial and progressive decoding.
- <doc:MigrationGuide> — upgrade from v1.9 to v2.0.
