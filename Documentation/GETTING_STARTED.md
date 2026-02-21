# Getting Started with J2KSwift

Welcome to J2KSwift — a pure Swift 6 implementation of JPEG 2000 (ISO/IEC 15444) encoding
and decoding with strict concurrency support.

This guide gets you up and running in under five minutes.

---

## Installation

### Swift Package Manager

Add J2KSwift to your `Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "J2KCore", package: "J2KSwift"),
                .product(name: "J2KCodec", package: "J2KSwift"),
                .product(name: "J2KFileFormat", package: "J2KSwift"),
            ]
        ),
    ]
)
```

### Platform Support

| Platform | Minimum Version | Notes |
|----------|----------------|-------|
| macOS    | 14.0           | Full support including Metal GPU acceleration |
| iOS      | 17.0           | Full support including Metal GPU acceleration |
| tvOS     | 17.0           | Full support including Metal GPU acceleration |
| visionOS | 1.0            | Full support including Metal GPU acceleration |
| Linux    | Ubuntu 22.04+  | CPU and Vulkan GPU paths; no Metal |
| Windows  | Windows 10+    | CPU and Vulkan GPU paths; no Metal |

---

## Your First Encode and Decode

### Encode a JPEG 2000 image

```swift
import J2KCore
import J2KCodec

// 1. Create image components (here: RGB, 8-bit, 4×4 pixels)
let pixels = Data(repeating: 128, count: 4 * 4)
let red   = J2KComponent(index: 0, bitDepth: 8, signed: false, width: 4, height: 4, data: pixels)
let green = J2KComponent(index: 1, bitDepth: 8, signed: false, width: 4, height: 4, data: pixels)
let blue  = J2KComponent(index: 2, bitDepth: 8, signed: false, width: 4, height: 4, data: pixels)

// 2. Assemble a J2KImage
let image = J2KImage(width: 4, height: 4, components: [red, green, blue])

// 3. Encode with the default (balanced) configuration
let encoder = J2KEncoder()
let encoded: Data = try encoder.encode(image)
print("Encoded \(encoded.count) bytes")
```

### Decode a JPEG 2000 image

```swift
import J2KCodec

let decoder = J2KDecoder()
let decoded: J2KImage = try decoder.decode(encoded)
print("Decoded \(decoded.width)×\(decoded.height), \(decoded.components.count) component(s)")
```

### Read and write files

```swift
import J2KFileFormat

// Read
let reader = J2KFileReader()
let image  = try reader.read(from: URL(fileURLWithPath: "/path/to/image.jp2"))

// Write
let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: URL(fileURLWithPath: "/path/to/output.jp2"))
```

---

## Choosing a Quality Preset

`J2KConfiguration` provides five built-in presets:

| Preset               | Quality | Use case |
|----------------------|---------|----------|
| `.lossless`          | 1.00    | Medical, archival |
| `.highQuality`       | 0.95    | Professional imaging |
| `.balanced`          | 0.85    | General purpose (default) |
| `.fast`              | 0.70    | Web delivery, thumbnails |
| `.maxCompression`    | 0.50    | Bandwidth-constrained |

```swift
let encoder = J2KEncoder(configuration: .lossless)
let data = try encoder.encode(image)
```

---

## Platform-Specific Setup Notes

### Apple Platforms — Metal GPU Acceleration

Import `J2KMetal` to enable GPU-accelerated wavelet transforms and colour conversion.
No additional configuration is needed; `J2KMetalDevice` auto-selects the best GPU.

```swift
import J2KMetal

let device = J2KMetalDevice()
try device.initialize()
// All subsequent J2KMetal operations use the GPU automatically.
```

### Linux / Windows — Vulkan GPU Compute

Import `J2KVulkan` and ensure the Vulkan SDK is installed on the target system.
J2KSwift falls back to CPU processing when no Vulkan device is present.

```swift
import J2KVulkan

let backend = J2KVulkanBackend()
// Uses GPU if Vulkan is available, CPU otherwise.
```

---

## Next Steps

- **[Encoding Guide](ENCODING_GUIDE.md)** — all encoding options, tiling, progression orders
- **[Decoding Guide](DECODING_GUIDE.md)** — progressive, region-of-interest, and resolution decoding
- **[HTJ2K Guide](HTJ2K_GUIDE.md)** — High-Throughput JPEG 2000 (ISO/IEC 15444-15)
- **[Metal GPU Guide](METAL_GPU_GUIDE.md)** — Apple GPU acceleration
- **[JPIP Guide](JPIP_GUIDE.md)** — JPEG 2000 Interactive Protocol streaming
- **[JP3D Guide](JP3D_GUIDE.md)** — volumetric / medical imaging
- **[MJ2 Guide](MJ2_GUIDE.md)** — Motion JPEG 2000 video
- **[CLI Guide](CLI_GUIDE.md)** — command-line tool (`j2k`)
- **[DICOM Integration](DICOM_INTEGRATION.md)** — using J2KSwift in DICOM workflows
