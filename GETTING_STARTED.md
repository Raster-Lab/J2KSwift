# Getting Started with J2KSwift

A beginner-friendly guide to using J2KSwift for JPEG 2000 image encoding and decoding.

**Version**: 1.1.0  
**Status**: Fully Functional Codec

## Table of Contents

- [Introduction](#introduction)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Basic Concepts](#basic-concepts)
- [Encoding Images](#encoding-images)
- [Decoding Images](#decoding-images)
- [Working with Files](#working-with-files)
- [Advanced Features](#advanced-features)
- [Next Steps](#next-steps)

## Introduction

J2KSwift is a pure Swift 6.2 implementation of JPEG 2000 (ISO/IEC 15444) that provides:
- **Complete encoder and decoder pipelines** (v1.1.0)
- Modern async/await API
- Type-safe error handling
- Hardware acceleration on Apple platforms (2-8× speedup)
- Network streaming with JPIP
- Comprehensive format support (JP2, J2K, JPX, JPM)
- 96.1% test pass rate

This guide will help you start using J2KSwift in your projects.

## Installation

### Swift Package Manager

Add J2KSwift to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.1.0")
]
```

Then add the modules you need to your target:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2KCodec", package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),
    ]
)
```

### Available Modules

- **J2KCore**: Core types and utilities (always required)
- **J2KCodec**: Encoding and decoding functionality
- **J2KAccelerate**: Hardware acceleration (automatically falls back on unsupported platforms)
- **J2KFileFormat**: File format support (JP2, J2K, JPX, JPM)
- **JPIP**: Network streaming protocol

## Quick Start

### Encode an Image (3 lines!)

```swift
import J2KCodec

let image = J2KImage(width: 512, height: 512, components: 3)
let encoder = J2KEncoder(encodingConfiguration: .balanced)
let j2kData = try encoder.encode(image)
```

### Decode an Image (2 lines!)

```swift
import J2KCodec

let decoder = J2KDecoder()
let image = try decoder.decode(j2kData)
```

That's it! You now have a working JPEG 2000 encoder and decoder.

## Basic Concepts

### J2KImage

The fundamental type representing a JPEG 2000 image:

```swift
import J2KCore

// Create a simple RGB image
let image = J2KImage(
    width: 512,
    height: 512,
    components: 3,        // R, G, B
    bitDepth: 8
)

print("Image size: \(image.width)×\(image.height)")
print("Components: \(image.components.count)")
print("Has alpha: \(image.hasAlpha)")
```

### J2KEncodingConfiguration

Controls encoding parameters with convenient presets:

```swift
import J2KCodec

// Use a preset (recommended)
let lossless = J2KEncodingConfiguration.lossless      // Perfect quality
let fast = J2KEncodingConfiguration.fast              // Quick encoding
let balanced = J2KEncodingConfiguration.balanced      // Good balance (default)
let quality = J2KEncodingConfiguration.quality        // Best quality
```

### Color Spaces

J2KSwift supports various color spaces:

```swift
// Common color spaces
let srgb = J2KColorSpace.sRGB       // Standard RGB
let gray = J2KColorSpace.grayscale  // Grayscale
let ycbcr = J2KColorSpace.yCbCr     // YCbCr (for JPEG 2000)

// HDR color spaces
let hdr = J2KColorSpace.hdr         // HDR with PQ or HLG
let hdrLinear = J2KColorSpace.hdrLinear  // Linear HDR
```

## Encoding Images

### Simple Encoding

The easiest way to encode an image:

```swift
import J2KCodec

// Create an image with pixel data
let image = J2KImage(width: 256, height: 256, components: 3, bitDepth: 8)
// ... fill image.components[0].data, etc. with your pixel data ...

// Encode with balanced preset (recommended)
let encoder = J2KEncoder(encodingConfiguration: .balanced)
let j2kData = try encoder.encode(image)

print("Encoded \(j2kData.count) bytes")
```

### Encoding with Different Quality Levels

```swift
// Lossless encoding (perfect quality, larger file)
let losslessEncoder = J2KEncoder(encodingConfiguration: .lossless)
let losslessData = try losslessEncoder.encode(image)

// Fast encoding (quick, smaller file)
let fastEncoder = J2KEncoder(encodingConfiguration: .fast)
let fastData = try fastEncoder.encode(image)

// Quality encoding (best quality, slower)
let qualityEncoder = J2KEncoder(encodingConfiguration: .quality)
let qualityData = try qualityEncoder.encode(image)
```

### Encoding with Progress Tracking

```swift
let encoder = J2KEncoder(encodingConfiguration: .balanced)

let data = try encoder.encode(image) { progress in
    print("\(progress.stage.rawValue): \(progress.percentage)% complete")
}

// Output:
// preprocessing: 10% complete
// colorTransform: 20% complete
// waveletTransform: 40% complete
// quantization: 60% complete
// entropyCoding: 80% complete
// rateControl: 90% complete
// codestreamGeneration: 100% complete
```

## Decoding Images

### Simple Decoding

Decode a JPEG 2000 codestream or file:

```swift
import J2KCodec

let decoder = J2KDecoder()
let image = try decoder.decode(j2kData)

print("Decoded: \(image.width)×\(image.height), \(image.componentCount) components")

// Access pixel data
for (index, component) in image.components.enumerated() {
    print("Component \(index): \(component.width)×\(component.height), \(component.bitDepth)-bit")
    // component.data contains the pixel values
}
```

### Progressive Decoding

Decode to a target quality level:

```swift
import J2KCodec

// Decode to 80% quality (faster, lower memory)
let options = J2KProgressiveDecodingOptions(
    mode: .quality,
    targetQuality: 0.8
)

let decoder = J2KDecoder()
let image = try decoder.decode(j2kData, options: options)
```

### Region-of-Interest Decoding

Decode only a specific region:

```swift
import J2KCodec

// Decode only the center 200×200 pixels
let roiOptions = J2KROIDecodingOptions(
    region: CGRect(x: 156, y: 156, width: 200, height: 200),
    strategy: .fullQuality
)

let decoder = J2KDecoder()
let roiImage = try decoder.decode(j2kData, options: roiOptions)

print("Decoded ROI: \(roiImage.width)×\(roiImage.height)")  // 200×200
```

### Decoding with Progress Tracking

```swift
let decoder = J2KDecoder()

let image = try decoder.decode(j2kData) { progress in
    print("\(progress.stage.rawValue): \(progress.percentage)% complete")
}
```

## Working with Files

### Saving to JP2 File

```swift
import J2KFileFormat

// Encode and save to JP2 file
let encoder = J2KEncoder(encodingConfiguration: .balanced)
let j2kData = try encoder.encode(image)

let writer = J2KFileWriter(format: .jp2)
try writer.write(j2kData, to: URL(fileURLWithPath: "output.jp2"))
```

### Loading from JP2 File

```swift
import J2KFileFormat
import J2KCodec

// Read JP2 file
let reader = J2KFileReader()
let j2kData = try reader.read(from: URL(fileURLWithPath: "input.jp2"))

// Decode the data
let decoder = J2KDecoder()
let image = try decoder.decode(j2kData.codestream)
```

### Complete Round-Trip Example

```swift
import J2KCore
import J2KCodec
import J2KFileFormat

// 1. Create an image
let original = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
// ... fill with pixel data ...

// 2. Encode it
let encoder = J2KEncoder(encodingConfiguration: .lossless)
let j2kData = try encoder.encode(original)

// 3. Save to file
let writer = J2KFileWriter(format: .jp2)
try writer.write(j2kData, to: URL(fileURLWithPath: "image.jp2"))

// 4. Read from file
let reader = J2KFileReader()
let fileData = try reader.read(from: URL(fileURLWithPath: "image.jp2"))

// 5. Decode it
let decoder = J2KDecoder()
let decoded = try decoder.decode(fileData.codestream)

// 6. Verify round-trip (for lossless)
assert(decoded.width == original.width)
assert(decoded.height == original.height)
assert(decoded.componentCount == original.componentCount)
```

## Advanced Features

### Quality Metrics

Compare original and compressed images:

```swift
import J2KCodec

let metrics = J2KQualityMetrics()

// Calculate PSNR
let psnr = try metrics.calculatePSNR(
    original: originalImage,
    compressed: decodedImage
)
print("PSNR: \(psnr) dB")

// Calculate SSIM
let ssim = try metrics.calculateSSIM(
    original: originalImage,
    compressed: decodedImage
)
print("SSIM: \(ssim)")
```

### Hardware Acceleration

Hardware acceleration is enabled automatically on Apple platforms:

```swift
// J2KSwift automatically uses vDSP and SIMD when available
// No configuration needed - just use the encoder/decoder as normal

let encoder = J2KEncoder(encodingConfiguration: .balanced)
// This will use hardware acceleration if available (2-8× speedup)
let data = try encoder.encode(image)
```

### Custom Configurations

For fine-grained control, create a custom configuration:

```swift
import J2KCodec

var config = J2KEncodingConfiguration.balanced

// Customize settings
config.decompositionLevels = 6
config.qualityLayers = 10
config.codeBlockSize = (width: 32, height: 32)
config.progressionOrder = .LRCP

let encoder = J2KEncoder(encodingConfiguration: config)
let data = try encoder.encode(image)
```

## Next Steps

### Learn More

Now that you've got the basics, explore these guides for deeper knowledge:

- **[TUTORIAL_ENCODING.md](TUTORIAL_ENCODING.md)** - Detailed encoding tutorial
- **[TUTORIAL_DECODING.md](TUTORIAL_DECODING.md)** - Detailed decoding tutorial
- **[ADVANCED_ENCODING.md](ADVANCED_ENCODING.md)** - Advanced encoding techniques
- **[ADVANCED_DECODING.md](ADVANCED_DECODING.md)** - Advanced decoding features
- **[API_REFERENCE.md](API_REFERENCE.md)** - Complete API documentation

### Key Topics

- **Wavelet Transforms**: [WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md)
- **Entropy Coding**: [ENTROPY_CODING.md](ENTROPY_CODING.md)
- **Quantization**: [QUANTIZATION.md](QUANTIZATION.md)
- **Rate Control**: [RATE_CONTROL.md](RATE_CONTROL.md)
- **Color Transforms**: [COLOR_TRANSFORM.md](COLOR_TRANSFORM.md)
- **File Formats**: [JP2_FILE_FORMAT.md](JP2_FILE_FORMAT.md)
- **Performance**: [PERFORMANCE.md](PERFORMANCE.md)

### Common Recipes

#### Creating a Simple Encoder/Decoder App

```swift
import J2KCore
import J2KCodec
import Foundation

// Simple command-line tool
@main
struct J2KTool {
    static func main() async throws {
        guard CommandLine.arguments.count == 4 else {
            print("Usage: j2ktool <encode|decode> <inputfile> <outputfile>")
            return
        }
        
        let command = CommandLine.arguments[1]
        let inputPath = CommandLine.arguments[2]
        let outputPath = CommandLine.arguments[3]
        
        switch command {
        case "encode":
            // Load image, encode, save
            let image = try loadImage(from: inputPath)
            let encoder = J2KEncoder(encodingConfiguration: .balanced)
            let data = try encoder.encode(image)
            try data.write(to: URL(fileURLWithPath: outputPath))
            print("Encoded: \(data.count) bytes")
            
        case "decode":
            // Load data, decode, save
            let data = try Data(contentsOf: URL(fileURLWithPath: inputPath))
            let decoder = J2KDecoder()
            let image = try decoder.decode(data)
            try saveImage(image, to: outputPath)
            print("Decoded: \(image.width)×\(image.height)")
            
        default:
            print("Unknown command: \(command)")
        }
    }
    
    static func loadImage(from path: String) throws -> J2KImage {
        // TODO: Implement image loading from common formats
        // For now, create a test image
        return J2KImage(width: 512, height: 512, components: 3)
    }
    
    static func saveImage(_ image: J2KImage, to path: String) throws {
        // TODO: Implement image saving to common formats
        print("Image size: \(image.width)×\(image.height)")
    }
}
```

#### Batch Processing

```swift
func processImages(in directory: URL) async throws {
    let encoder = J2KEncoder(encodingConfiguration: .balanced)
    let decoder = J2KDecoder()
    let fileManager = FileManager.default
    
    let files = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    
    for fileURL in files where fileURL.pathExtension == "jp2" {
        print("Processing: \(fileURL.lastPathComponent)")
        
        // Decode
        let data = try Data(contentsOf: fileURL)
        let image = try decoder.decode(data)
        
        // Process image (example: re-encode with different quality)
        let newData = try encoder.encode(image)
        
        // Save with new name
        let newURL = fileURL.deletingPathExtension()
            .appendingPathExtension("processed.jp2")
        try newData.write(to: newURL)
    }
}
```

### Troubleshooting

#### Common Issues

1. **Build Error: Module not found**
   - Make sure you've added the module to your target dependencies
   - Check that you're importing the correct module name

2. **Encoding fails with "Invalid dimensions"**
   - Ensure image width and height are positive
   - Check that component dimensions match image dimensions

3. **Decoding fails with "Invalid data"**
   - Verify the input data is actually JPEG 2000 format
   - Check that the file isn't corrupted

4. **Performance is slow**
   - On Apple platforms, hardware acceleration should be automatic
   - Try using a faster encoding preset (`.fast` or `.balanced`)
   - For large images, consider using tiling

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for more help.

### Getting Help

- **Documentation**: Browse all guides in the repository
- **GitHub Issues**: https://github.com/Raster-Lab/J2KSwift/issues
- **Discussions**: https://github.com/Raster-Lab/J2KSwift/discussions
- **API Reference**: [API_REFERENCE.md](API_REFERENCE.md)

### Contributing

J2KSwift is open source! Contributions are welcome:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

**Next**: Read [TUTORIAL_ENCODING.md](TUTORIAL_ENCODING.md) for a comprehensive encoding tutorial, or explore [ADVANCED_ENCODING.md](ADVANCED_ENCODING.md) for advanced features.

**Version**: 1.1.0  
**Last Updated**: 2026-02-14
