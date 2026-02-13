# Encoding Tutorial

A comprehensive guide to encoding images with J2KSwift.

## Table of Contents

- [Introduction](#introduction)
- [Basic Encoding](#basic-encoding)
- [Encoding Presets](#encoding-presets)
- [Quality Control](#quality-control)
- [Progressive Encoding](#progressive-encoding)
- [Region of Interest (ROI)](#region-of-interest-roi)
- [Tiled Encoding](#tiled-encoding)
- [Advanced Options](#advanced-options)
- [Performance Tips](#performance-tips)

## Introduction

This tutorial covers everything you need to know about encoding images with J2KSwift, from basic operations to advanced techniques.

> **Note**: The high-level `J2KEncoder.encode()` API is fully functional as of v1.0. This tutorial demonstrates the complete encoding capabilities.

## Basic Encoding

### Simple Encoding

```swift
import J2KCore
import J2KCodec

// Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)

// Encode with default settings
let encoder = J2KEncoder()
let data = try encoder.encode(image)

print("Encoded \(data.count) bytes")
```

### Custom Configuration

```swift
// Create a custom configuration
let config = J2KConfiguration(
    quality: 0.9,              // 0.0 to 1.0 (higher is better)
    lossless: false,           // Lossless compression
    decompositionLevels: 5,    // Wavelet decomposition levels
    compressionRatio: 10       // Target compression ratio
)

let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)
```

## Encoding Presets

J2KSwift provides three encoding presets optimized for different use cases:

### Fast Preset

Optimized for speed, suitable for real-time applications:

```swift
import J2KCodec

let preset = J2KEncodingPresets.fast

// Configuration:
// - 3 decomposition levels
// - 64×64 code blocks
// - 3 quality layers
// - Single-threaded
// - 2-3× faster than balanced

let config = J2KConfiguration(preset: preset)
let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)
```

**Use cases:**
- Real-time video encoding
- Preview generation
- Quick compression for transmission
- Mobile applications

### Balanced Preset (Default)

Optimal balance between quality and speed:

```swift
let preset = J2KEncodingPresets.balanced

// Configuration:
// - 5 decomposition levels
// - 32×32 code blocks
// - 5 quality layers
// - Multi-threaded
// - Optimal for most use cases

let config = J2KConfiguration(preset: preset)
```

**Use cases:**
- General purpose image compression
- Web delivery
- Standard archival
- Desktop applications

### Quality Preset

Optimized for maximum quality:

```swift
let preset = J2KEncodingPresets.quality

// Configuration:
// - 6 decomposition levels
// - 32×32 code blocks
// - 10 quality layers
// - Multi-threaded
// - 1.5-2× slower but best quality

let config = J2KConfiguration(preset: preset)
```

**Use cases:**
- Professional photography
- Medical imaging
- Scientific applications
- Long-term archival

### Custom Preset

Create your own preset:

```swift
let customPreset = J2KEncodingPreset(
    name: "Mobile",
    decompositionLevels: 4,
    codeBlockWidth: 64,
    codeBlockHeight: 64,
    layers: 3,
    quality: 0.85,
    parallelization: false
)

let config = J2KConfiguration(preset: customPreset)
```

## Quality Control

### Quality Parameter

Control quality with a 0.0 to 1.0 scale:

```swift
// Low quality, high compression
let lowQuality = J2KConfiguration(quality: 0.5)

// Medium quality
let mediumQuality = J2KConfiguration(quality: 0.8)

// High quality
let highQuality = J2KConfiguration(quality: 0.95)

// Very high quality
let veryHighQuality = J2KConfiguration(quality: 0.99)
```

### Lossless Encoding

For perfect reconstruction:

```swift
let losslessConfig = J2KConfiguration(lossless: true)
let encoder = J2KEncoder(configuration: losslessConfig)

// Lossless encoding uses:
// - 5/3 reversible wavelet filter
// - Reversible color transform (RCT)
// - No quantization
// - All bit planes included
```

### Compression Ratio

Target a specific compression ratio:

```swift
// 10:1 compression
let config = J2KConfiguration(compressionRatio: 10)

// 20:1 compression
let config = J2KConfiguration(compressionRatio: 20)

// 50:1 compression (high compression, lower quality)
let config = J2KConfiguration(compressionRatio: 50)
```

### Visual Weighting

Apply perceptual quality weighting:

```swift
import J2KCodec

// Create visual weighting based on CSF
let weighting = J2KVisualWeighting(
    viewingDistance: 50.0,  // cm
    displayResolution: 72.0  // DPI
)

// Get subband weights
let weights = weighting.calculateSubbandWeights(
    decompositionLevels: 5,
    baseFrequency: 1.0
)

// Apply to configuration
let config = J2KConfiguration(
    quality: 0.9,
    visualWeights: weights
)
```

### Quality Metrics

Measure encoding quality:

```swift
import J2KCodec

let metrics = J2KQualityMetrics()

// Calculate PSNR
let psnr = try metrics.calculatePSNR(
    original: originalImage,
    reconstructed: encodedImage
)
print("PSNR: \(psnr) dB")

// Calculate SSIM (Structural Similarity)
let ssim = try metrics.calculateSSIM(
    original: originalImage,
    reconstructed: encodedImage
)
print("SSIM: \(ssim)")

// Multi-scale SSIM
let msssim = try metrics.calculateMSSSIM(
    original: originalImage,
    reconstructed: encodedImage,
    scales: 5
)
print("MS-SSIM: \(msssim)")
```

## Progressive Encoding

Enable different types of progressive encoding:

### SNR Progressive (Quality Layers)

Encode with progressive quality layers:

```swift
import J2KCodec

let progressive = J2KProgressiveEncoding.snrProgressive(layers: 5)

let config = J2KConfiguration(
    quality: 0.9,
    progressiveMode: progressive
)

// Results in 5 quality layers:
// Layer 0: Base quality (~20% of target)
// Layer 1: Low quality (~40% of target)
// Layer 2: Medium quality (~60% of target)
// Layer 3: High quality (~80% of target)
// Layer 4: Full quality (100% of target)
```

**Use cases:**
- Progressive image loading in browsers
- Streaming applications
- Bandwidth-adaptive delivery

### Spatial Progressive (Resolution Levels)

Encode with progressive resolution:

```swift
let progressive = J2KProgressiveEncoding.spatialProgressive(levels: 5)

let config = J2KConfiguration(
    progressiveMode: progressive
)

// Creates pyramid of resolutions:
// Level 0: Full resolution (1:1)
// Level 1: Half resolution (1:2)
// Level 2: Quarter resolution (1:4)
// Level 3: Eighth resolution (1:8)
// Level 4: Sixteenth resolution (1:16)
```

**Use cases:**
- Thumbnail generation
- Zoom interfaces
- Multi-resolution displays

### Layer Progressive

Stream-optimized progressive encoding:

```swift
let progressive = J2KProgressiveEncoding.layerProgressive(
    layers: 10,
    streaming: true
)

let config = J2KConfiguration(
    progressiveMode: progressive
)
```

**Use cases:**
- JPIP streaming
- Network transmission
- Progressive rendering

### Combined Progressive

Combine multiple progressive modes:

```swift
let progressive = J2KProgressiveEncoding.combined(
    qualityLayers: 5,
    resolutionLevels: 5
)

let config = J2KConfiguration(
    progressiveMode: progressive
)
```

## Region of Interest (ROI)

Encode specific regions with higher quality:

### Rectangle ROI

```swift
import J2KCodec

// Define rectangular ROI
let roi = J2KROIShape.rectangle(
    x: 100, y: 100,
    width: 200, height: 200
)

// Create ROI with priority
let roiRegion = J2KROI(
    shape: roi,
    priority: 10,  // Higher priority = better quality
    method: .maxShift
)

// Configure encoding with ROI
let config = J2KConfiguration(
    quality: 0.8,
    regionOfInterest: [roiRegion]
)

let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)
```

### Ellipse ROI

```swift
// Define elliptical ROI (for faces, objects)
let roi = J2KROIShape.ellipse(
    centerX: 256, centerY: 256,
    radiusX: 100, radiusY: 80
)

let roiRegion = J2KROI(shape: roi, priority: 15, method: .maxShift)
```

### Polygon ROI

```swift
// Define arbitrary polygon ROI
let points: [(Int, Int)] = [
    (100, 100),
    (200, 100),
    (250, 200),
    (150, 250),
    (50, 200)
]
let roi = J2KROIShape.polygon(points: points)

let roiRegion = J2KROI(shape: roi, priority: 12, method: .maxShift)
```

### Multiple ROIs

```swift
// Encode with multiple regions of interest
let face1 = J2KROI(
    shape: .ellipse(centerX: 200, centerY: 150, radiusX: 50, radiusY: 60),
    priority: 15,
    method: .maxShift
)

let face2 = J2KROI(
    shape: .ellipse(centerX: 350, centerY: 180, radiusX: 45, radiusY: 55),
    priority: 15,
    method: .maxShift
)

let text = J2KROI(
    shape: .rectangle(x: 50, y: 400, width: 400, height: 50),
    priority: 12,
    method: .maxShift
)

let config = J2KConfiguration(
    quality: 0.8,
    regionOfInterest: [face1, face2, text]
)
```

## Tiled Encoding

Encode large images efficiently using tiles:

### Basic Tiling

```swift
// Create image with tiling
let image = J2KImage(
    width: 4096,
    height: 4096,
    components: 3,
    bitDepth: 8,
    tileWidth: 512,   // 512×512 tiles
    tileHeight: 512
)

// Encode (automatically processes tile-by-tile)
let encoder = J2KEncoder()
let data = try encoder.encode(image)
```

**Benefits:**
- Reduced memory usage (up to 64× reduction)
- Parallel tile processing
- Random access to image regions

### Custom Tile Configuration

```swift
let image = J2KImage(
    width: 8192,
    height: 6144,
    components: 3,
    bitDepth: 8,
    tileWidth: 1024,    // Larger tiles
    tileHeight: 1024,
    tileOffsetX: 0,     // Tile origin
    tileOffsetY: 0
)
```

### Optimal Tile Size

```swift
// For typical images:
// - 256×256: Small tiles, high overhead
// - 512×512: Good balance (recommended)
// - 1024×1024: Large tiles, less overhead
// - 2048×2048: Very large, may impact memory

// Rule of thumb: Tile size should be 2-4× code block size
let codeBlockSize = 32
let optimalTileSize = codeBlockSize * 16  // 512 pixels
```

## Advanced Options

### Color Transform Selection

```swift
// Reversible Color Transform (lossless)
let rctConfig = J2KConfiguration(
    lossless: true,
    colorTransform: .reversible  // RCT for RGB->YCbCr
)

// Irreversible Color Transform (lossy)
let ictConfig = J2KConfiguration(
    lossless: false,
    colorTransform: .irreversible  // ICT for RGB->YCbCr
)

// No color transform
let noTransformConfig = J2KConfiguration(
    colorTransform: .none
)
```

### Wavelet Filter Selection

```swift
// 5/3 Reversible filter (for lossless)
let reversibleConfig = J2KConfiguration(
    lossless: true,
    waveletFilter: .filter53
)

// 9/7 Irreversible filter (for lossy, better compression)
let irreversibleConfig = J2KConfiguration(
    lossless: false,
    waveletFilter: .filter97
)
```

### Decomposition Levels

```swift
// More levels = better compression, slower encoding
// Typical range: 3-6 levels

// 3 levels (fast, less compression)
let fastConfig = J2KConfiguration(decompositionLevels: 3)

// 5 levels (balanced, recommended)
let balancedConfig = J2KConfiguration(decompositionLevels: 5)

// 6 levels (slow, best compression)
let bestConfig = J2KConfiguration(decompositionLevels: 6)

// Maximum safe levels based on image size
let maxLevels = Int(log2(Double(min(width, height)))) - 3
```

### Code Block Size

```swift
// Larger code blocks = better compression, more memory
// Typical sizes: 32×32, 64×64

let config = J2KConfiguration(
    codeBlockWidth: 64,
    codeBlockHeight: 64
)

// Constraints:
// - Width and height must be powers of 2
// - Width ≤ 1024, Height ≤ 1024
// - Width × Height ≤ 4096
```

### Bit Rate Control

```swift
import J2KCodec

// Target specific bitrate
let rateControl = J2KRateControl(
    targetBitrate: 1.0,  // bits per pixel
    mode: .constantBitrate,
    strict: true  // Enforce bitrate strictly
)

let config = J2KConfiguration(
    rateControl: rateControl
)
```

## Performance Tips

### 1. Use Appropriate Presets

```swift
// For real-time encoding
let encoder = J2KEncoder(configuration: .fast)

// For archival/quality
let encoder = J2KEncoder(configuration: .quality)
```

### 2. Enable Hardware Acceleration

```swift
// Hardware acceleration is automatic on Apple platforms
// To disable (for testing):
let config = J2KConfiguration(
    useHardwareAcceleration: false
)
```

### 3. Optimize Tile Size

```swift
// For large images (>4K), use tiling
if width * height > 16_777_216 {  // 4096×4096
    image = J2KImage(
        width: width,
        height: height,
        components: 3,
        tileWidth: 512,
        tileHeight: 512
    )
}
```

### 4. Choose Appropriate Decomposition Levels

```swift
// Calculate optimal levels based on image size
let minDimension = min(width, height)
let optimalLevels = min(5, Int(log2(Double(minDimension))) - 3)

let config = J2KConfiguration(decompositionLevels: optimalLevels)
```

### 5. Batch Processing

```swift
// Process multiple images efficiently
let encoder = J2KEncoder(configuration: config)

for imageFile in imageFiles {
    let image = try loadImage(from: imageFile)
    let data = try encoder.encode(image)
    try save(data, to: outputFile)
}
```

### 6. Parallel Encoding

```swift
// Encode multiple images in parallel
await withTaskGroup(of: Data.self) { group in
    for image in images {
        group.addTask {
            let encoder = J2KEncoder(configuration: config)
            return try! encoder.encode(image)
        }
    }
    
    for await data in group {
        // Process encoded data
    }
}
```

### 7. Memory Management

```swift
// For very large images, use tiling and monitor memory
let tracker = J2KMemoryTracker()
tracker.setLimit(500_000_000)  // 500 MB limit

// Encode with memory tracking
let config = J2KConfiguration(
    memoryTracker: tracker
)
```

## Complete Example

Here's a complete encoding workflow:

```swift
import J2KCore
import J2KCodec
import J2KFileFormat

func encodeImageWithOptions(
    inputURL: URL,
    outputURL: URL,
    preset: J2KEncodingPreset = .balanced,
    quality: Double = 0.9,
    progressive: Bool = true
) throws {
    // Load image (from your image library)
    let image = try loadImage(from: inputURL)
    
    // Configure ROI for faces (if detected)
    let faces = detectFaces(in: image)
    let rois = faces.map { face in
        J2KROI(
            shape: .ellipse(
                centerX: face.centerX,
                centerY: face.centerY,
                radiusX: face.width / 2,
                radiusY: face.height / 2
            ),
            priority: 15,
            method: .maxShift
        )
    }
    
    // Configure progressive mode
    let progressiveMode = progressive
        ? J2KProgressiveEncoding.snrProgressive(layers: 5)
        : nil
    
    // Create configuration
    let config = J2KConfiguration(
        preset: preset,
        quality: quality,
        progressiveMode: progressiveMode,
        regionOfInterest: rois.isEmpty ? nil : rois
    )
    
    // Encode
    let encoder = J2KEncoder(configuration: config)
    let encodedData = try encoder.encode(image)
    
    // Write to file
    let writer = J2KFileWriter(format: .jp2)
    try writer.write(encodedData, to: outputURL)
    
    // Calculate metrics
    let metrics = J2KQualityMetrics()
    let decoded = try J2KDecoder().decode(encodedData)
    let psnr = try metrics.calculatePSNR(original: image, reconstructed: decoded)
    let ssim = try metrics.calculateSSIM(original: image, reconstructed: decoded)
    
    print("Encoded: \(encodedData.count) bytes")
    print("PSNR: \(psnr) dB")
    print("SSIM: \(ssim)")
    print("Compression ratio: \(Double(imageSize) / Double(encodedData.count))")
}

// Usage
try encodeImageWithOptions(
    inputURL: URL(fileURLWithPath: "input.png"),
    outputURL: URL(fileURLWithPath: "output.jp2"),
    preset: .quality,
    quality: 0.95,
    progressive: true
)
```

## Next Steps

- **[Decoding Tutorial](TUTORIAL_DECODING.md)**: Learn about decoding options
- **[Performance Tutorial](TUTORIAL_PERFORMANCE.md)**: Optimize encoding performance
- **[Advanced Encoding](ADVANCED_ENCODING.md)**: Deep dive into advanced features
- **[API Reference](API_REFERENCE.md)**: Complete API documentation

---

**Status**: Documentation for Phase 8 (Production Ready)  
**Last Updated**: 2026-02-07
