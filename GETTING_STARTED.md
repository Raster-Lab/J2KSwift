# Getting Started with J2KSwift

A beginner-friendly guide to using J2KSwift for JPEG 2000 image encoding and decoding.

## Table of Contents

- [Introduction](#introduction)
- [Installation](#installation)
- [Basic Concepts](#basic-concepts)
- [Your First Encoding](#your-first-encoding)
- [Your First Decoding](#your-first-decoding)
- [Working with Files](#working-with-files)
- [Next Steps](#next-steps)

## Introduction

J2KSwift is a pure Swift 6 implementation of JPEG 2000 (ISO/IEC 15444) that provides:
- Modern async/await API
- Type-safe error handling
- Hardware acceleration on Apple platforms
- Network streaming with JPIP
- Comprehensive format support (JP2, J2K, JPX, JPM)

This guide will help you start using J2KSwift in your projects.

## Installation

### Swift Package Manager

Add J2KSwift to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.0.0")
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

print("Image size: \(image.width)x\(image.height)")
print("Components: \(image.components.count)")
```

### J2KConfiguration

Controls encoding parameters:

```swift
// Default configuration (good quality, reasonable speed)
let defaultConfig = J2KConfiguration()

// High quality configuration
let highQuality = J2KConfiguration(
    quality: 0.95,
    lossless: false,
    decompositionLevels: 5
)

// Lossless configuration
let lossless = J2KConfiguration(
    lossless: true
)
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

## Your First Encoding

### Basic Encoding

The high-level encoding API is fully functional as of v1.0:

```swift
import J2KCore
import J2KCodec

// Create an image (example with dummy data)
let width = 512
let height = 512
let image = J2KImage(width: width, height: height, components: 3, bitDepth: 8)

// Fill with sample data (red gradient)
var redData = Data(count: width * height)
redData.withUnsafeMutableBytes { ptr in
    guard let bytes = ptr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return  // Should not happen for freshly allocated Data
    }
    for y in 0..<height {
        for x in 0..<width {
            let value = UInt8((Double(x) / Double(width)) * 255.0)
            bytes[y * width + x] = value
        }
    }
}

// Set component data
image.components[0] = J2KComponent(
    index: 0, width: width, height: height, bitDepth: 8, signed: false, data: redData
)
image.components[1] = J2KComponent(
    index: 1, width: width, height: height, bitDepth: 8, signed: false, 
    data: Data(count: width * height)
)
image.components[2] = J2KComponent(
    index: 2, width: width, height: height, bitDepth: 8, signed: false, 
    data: Data(count: width * height)
)

// Create encoder with configuration
let config = J2KConfiguration(quality: 0.9)
let encoder = J2KEncoder(configuration: config)

// Encode the image
do {
    let encodedData = try encoder.encode(image)
    print("Encoded \(encodedData.count) bytes")
    
    // The encoded data is a JPEG 2000 codestream
    // To save as a JP2 file, use J2KFileFormat (see "Working with Files" below)
} catch {
    print("Encoding failed: \(error)")
}
```

### Encoding with Progress Reporting

The encoder supports progress callbacks during encoding:

```swift
let encodedData = try encoder.encode(image) { update in
    print("\(update.stage): \(Int(update.overallProgress * 100))%")
}
```

### Encoding Presets

J2KSwift provides convenient presets for different use cases:

```swift
import J2KCodec

// Fast encoding (lower quality, faster)
let fastEncoder = J2KEncoder(
    encodingConfiguration: J2KEncodingPreset.fast.configuration(quality: 0.8)
)

// Balanced (good quality/speed tradeoff)
let balancedEncoder = J2KEncoder(
    encodingConfiguration: J2KEncodingPreset.balanced.configuration(quality: 0.9)
)

// Quality encoding (best quality, slower)
let qualityEncoder = J2KEncoder(
    encodingConfiguration: J2KEncodingPreset.quality.configuration(quality: 0.95)
)

// Lossless encoding
let losslessEncoder = J2KEncoder(
    encodingConfiguration: J2KEncodingPreset.lossless.configuration()
)
```

### Advanced Encoding Configuration

For fine-grained control, create a custom `J2KEncodingConfiguration`:

```swift
var config = J2KEncodingConfiguration(quality: 0.9, lossless: false)
config.decompositionLevels = 5
config.codeBlockSize = J2KSize(width: 64, height: 64)
config.progressionOrder = .lrcp  // Layer-Resolution-Component-Position

let encoder = J2KEncoder(encodingConfiguration: config)
```

### Using Individual Components

For advanced use cases, you can also use individual encoding components directly:

```swift
import J2KCodec

// Wavelet transform
let dwt = J2KDWT2D()
let transformed = try dwt.forwardTransform(
    data: imageData,
    width: width,
    height: height,
    levels: 3,
    filter: .filter97  // Irreversible 9/7 filter
)

// Quantization
let quantizer = J2KQuantization()
let quantized = quantizer.quantize(
    subbands: transformed,
    mode: .scalar,
    baseStepSize: 0.01
)

// Entropy coding
let coder = J2KBitPlaneCoder()
let encoded = try coder.encode(codeBlock: quantized)
```

## Your First Decoding

> **Note**: The high-level `J2KDecoder.decode()` pipeline is not yet implemented in v1.0. 
> This is planned for v1.1 (see ROADMAP_v1.1.md). The example below shows the planned API.

### Planned API (v1.1)

```swift
import J2KCore
import J2KCodec

// Load JPEG 2000 data
let data = try Data(contentsOf: URL(fileURLWithPath: "input.jp2"))

// Create decoder
let decoder = J2KDecoder()

// Decode the image
do {
    let image = try decoder.decode(data)
    print("Decoded image: \(image.width)x\(image.height)")
    print("Color space: \(image.colorSpace)")
    print("Components: \(image.components.count)")
    
    // Access pixel data
    let component0 = image.components[0]
    let firstPixel = component0.data.first ?? 0
    print("First pixel value: \(firstPixel)")
} catch {
    print("Decoding failed: \(error)")
}
```

### Current Status (v1.0)

Individual decoding components are available for direct use:

```swift
import J2KCodec

// Entropy decoding (bit-plane decoding)
let bitPlaneDecoder = BitPlaneDecoder()
let coefficients = try bitPlaneDecoder.decode(codeBlock: encodedBlock)

// Dequantization
let quantizer = J2KQuantizer(parameters: .fromQuality(0.9))
let dequantized = try quantizer.dequantize(
    coefficients: coefficients,
    subband: .ll,
    decompositionLevel: 0,
    totalLevels: 5
)

// Inverse wavelet transform
let transformed = try J2KDWT2D.inverseDecomposition(
    decomposition: waveletData,
    filter: .irreversible97
)
```

> Full decoder pipeline integration is the focus of v1.1 development (see ROADMAP_v1.1.md, Phase 3).

## Working with Files

### File Format Detection

```swift
import J2KFileFormat

let detector = J2KFormatDetector()

do {
    let data = try Data(contentsOf: fileURL)
    let format = try detector.detect(data: data)
    
    switch format {
    case .jp2:
        print("JP2 file (JPEG 2000 Part 1)")
    case .j2k:
        print("J2K codestream")
    case .jpx:
        print("JPX file (JPEG 2000 Part 2)")
    case .jpm:
        print("JPM file (JPEG 2000 Part 6)")
    }
} catch {
    print("Format detection failed: \(error)")
}
```

### Reading JP2 Files

> **Note**: `J2KFileReader.read()` is not yet implemented in v1.0. Planned for v1.1.

```swift
import J2KFileFormat

// Planned API (v1.1)
let reader = J2KFileReader()

do {
    // Read image from file
    let image = try reader.read(from: fileURL)
    
    print("Loaded image: \(image.width)x\(image.height)")
    print("Color space: \(image.colorSpace)")
} catch {
    print("Reading failed: \(error)")
}
```

Currently, you can read the raw codestream data and use individual components to decode it.

### Writing JP2 Files

> **Note**: `J2KFileWriter.write()` is not yet implemented in v1.0. Planned for v1.1.

```swift
import J2KFileFormat

// Planned API (v1.1)
let writer = J2KFileWriter(format: .jp2)

do {
    // Write image to file
    try writer.write(image, to: outputURL)
    print("Saved to \(outputURL.path)")
} catch {
    print("Writing failed: \(error)")
}
```

Currently, you can encode to a codestream using `J2KEncoder` and save the raw data.

## Next Steps

Now that you understand the basics, explore these topics:

### Tutorials

1. **[Encoding Tutorial](TUTORIAL_ENCODING.md)**: Learn advanced encoding techniques
2. **[Decoding Tutorial](TUTORIAL_DECODING.md)**: Master decoding options
3. **[File Format Tutorial](TUTORIAL_FILE_FORMAT.md)**: Work with JP2, JPX, JPM formats
4. **[JPIP Tutorial](TUTORIAL_JPIP.md)**: Stream images over networks
5. **[Performance Tutorial](TUTORIAL_PERFORMANCE.md)**: Optimize your code

### Advanced Topics

- **[Advanced Encoding](ADVANCED_ENCODING.md)**: Visual weighting, presets, progressive encoding
- **[Advanced Decoding](ADVANCED_DECODING.md)**: ROI decoding, progressive decoding, partial decoding
- **[Hardware Acceleration](HARDWARE_ACCELERATION.md)**: Using platform-specific optimizations
- **[Extended Formats](EXTENDED_FORMATS.md)**: 16-bit, HDR, alpha channels

### Reference Documentation

- **[API Reference](API_REFERENCE.md)**: Complete API documentation
- **[Performance Guide](PERFORMANCE.md)**: Benchmarks and optimization tips
- **[Migration Guide](MIGRATION_GUIDE.md)**: Migrate from OpenJPEG or other libraries
- **[Troubleshooting](TROUBLESHOOTING.md)**: Common issues and solutions

### Examples

Check out the [examples repository](https://github.com/Raster-Lab/J2KSwift-Examples) for:
- Complete sample applications
- Platform-specific integrations (iOS, macOS, Linux)
- Real-world use cases
- Performance benchmarks

## Getting Help

- **GitHub Issues**: [Report bugs or request features](https://github.com/Raster-Lab/J2KSwift/issues)
- **Discussions**: [Ask questions and share ideas](https://github.com/Raster-Lab/J2KSwift/discussions)
- **Documentation**: Browse the docs at [j2kswift.org](https://j2kswift.org)

## Quick Reference

### Common Configurations

```swift
// Fast encoding (lower quality)
let fast = J2KConfiguration(
    quality: 0.7,
    decompositionLevels: 3,
    compressionRatio: 10
)

// Balanced (default)
let balanced = J2KConfiguration()

// High quality
let quality = J2KConfiguration(
    quality: 0.95,
    decompositionLevels: 5,
    compressionRatio: 5
)

// Lossless
let lossless = J2KConfiguration(lossless: true)
```

### Error Handling

```swift
import J2KCore

do {
    let result = try encoder.encode(image)
} catch J2KError.invalidParameter(let message) {
    print("Invalid parameter: \(message)")
} catch J2KError.encodingFailed(let message) {
    print("Encoding failed: \(message)")
} catch J2KError.decodingFailed(let message) {
    print("Decoding failed: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Typical Workflow

```swift
// 1. Create or load an image
let image = J2KImage(width: 1024, height: 768, components: 3, bitDepth: 8)

// 2. Configure encoding
let config = J2KConfiguration(quality: 0.9)

// 3. Encode
let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)

// 4. Save to file
let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: outputURL)

// 5. Later, decode
let decoder = J2KDecoder()
let loadedImage = try decoder.decode(data)
```

---

**Ready to start?** Choose a tutorial from the [Next Steps](#next-steps) section and dive in!

**Status**: Documentation for Phase 8 (Production Ready)  
**Last Updated**: 2026-02-07
