# Decoding Tutorial

A comprehensive guide to decoding JPEG 2000 images with J2KSwift.

## Table of Contents

- [Introduction](#introduction)
- [Basic Decoding](#basic-decoding)
- [Partial Decoding](#partial-decoding)
- [Region of Interest Decoding](#region-of-interest-decoding)
- [Resolution-Progressive Decoding](#resolution-progressive-decoding)
- [Quality-Progressive Decoding](#quality-progressive-decoding)
- [Incremental Decoding](#incremental-decoding)
- [Advanced Options](#advanced-options)
- [Performance Tips](#performance-tips)

## Introduction

J2KSwift provides powerful decoding capabilities including partial decoding, ROI decoding, and progressive decoding for efficient image access.

> **Note**: The high-level `J2KDecoder.decode()` API is not yet implemented in v1.0. This is planned for v1.1 (see ROADMAP_v1.1.md, Phase 3). This tutorial shows the planned API and currently available decoding components.

## Basic Decoding

### Simple Decoding (Planned API - v1.1)

```swift
import J2KCore
import J2KCodec

// Load JPEG 2000 data
let data = try Data(contentsOf: URL(fileURLWithPath: "image.jp2"))

// Create decoder and decode
let decoder = J2KDecoder()
let image = try decoder.decode(data)

print("Decoded: \(image.width)x\(image.height)")
print("Components: \(image.components.count)")
print("Color space: \(image.colorSpace)")
```

### Decoding from File (Planned API - v1.1)

```swift
import J2KFileFormat

// Read from file directly
let reader = J2KFileReader()
let image = try reader.read(from: URL(fileURLWithPath: "image.jp2"))
```

### Current Decoding Approach (v1.0)

Currently, you can use individual decoding components:

```swift
import J2KCodec

// 1. Entropy decoding
let bitPlaneDecoder = BitPlaneDecoder()
let coefficients = try bitPlaneDecoder.decode(codeBlock: encodedBlock)

// 2. Dequantization
let quantizer = J2KQuantizer(parameters: .fromQuality(0.9))
let dequantized = try quantizer.dequantize(
    coefficients: coefficients,
    subband: .ll,
    decompositionLevel: 0,
    totalLevels: 5
)

// 3. Inverse wavelet transform
let transformed = try J2KDWT2D.inverseDecomposition(
    decomposition: waveletData,
    filter: .irreversible97
)

// 4. Inverse color transform
let colorTransform = J2KColorTransform()
let rgb = try colorTransform.yCbCrToRGB(transformed)
```

### Accessing Pixel Data (Planned API - v1.1)

```swift
// Access pixel values from components
let redComponent = image.components[0]
let greenComponent = image.components[1]
let blueComponent = image.components[2]

// Get pixel at specific location
let x = 100
let y = 100
let index = y * image.width + x

// Access pixel data directly from component data
redComponent.data.withUnsafeBytes { buffer in
    if let bytes = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) {
        let red = bytes[index]
        print("Red value at (\(x), \(y)): \(red)")
    } else {
        print("Error: Unable to access pixel buffer")
    }
}
```

## Partial Decoding

Decode only part of the image data for faster access:

### Decode to Specific Layer

```swift
import J2KCodec

// Decode only the first 3 quality layers
let options = J2KDecodingOptions(
    maxLayers: 3  // Decode layers 0-2 only
)

let decoder = J2KAdvancedDecoding()
let image = try decoder.partialDecode(
    data: encodedData,
    options: options
)

// Results in faster decoding with reduced quality
// Typical speedup: 30-50% faster
```

### Decode to Specific Resolution

```swift
// Decode only to resolution level 2 (1/4 resolution)
let options = J2KDecodingOptions(
    resolutionLevel: 2  // 0=full, 1=1/2, 2=1/4, etc.
)

let decoder = J2KAdvancedDecoding()
let image = try decoder.partialDecode(
    data: encodedData,
    options: options
)

// Image will be 1/4 the original size
print("Decoded size: \(image.width)x\(image.height)")
```

### Decode Specific Components

```swift
// Decode only red and green channels
let options = J2KDecodingOptions(
    components: [0, 1]  // Component indices
)

let decoder = J2KAdvancedDecoding()
let image = try decoder.partialDecode(
    data: encodedData,
    options: options
)

// Image will have only 2 components
print("Components decoded: \(image.components.count)")
```

### Combined Partial Decoding

```swift
// Combine multiple options for maximum speedup
let options = J2KDecodingOptions(
    maxLayers: 2,
    resolutionLevel: 1,
    components: [0]  // Only luminance
)

let decoder = J2KAdvancedDecoding()
let image = try decoder.partialDecode(
    data: encodedData,
    options: options
)

// Very fast decoding: half resolution, low quality, single component
```

## Region of Interest Decoding

Decode only a specific region of the image:

### Rectangle ROI

```swift
import J2KCodec

// Define region to decode
let roi = J2KDecodingROI(
    x: 100,
    y: 100,
    width: 200,
    height: 200
)

let decoder = J2KAdvancedDecoding()

// Strategy 1: Full image extraction (slow but simple)
let image1 = try decoder.decodeROI(
    data: encodedData,
    roi: roi,
    strategy: .fullImageExtraction
)

// Strategy 2: Direct decoding (3-5× faster)
let image2 = try decoder.decodeROI(
    data: encodedData,
    roi: roi,
    strategy: .direct
)

// Strategy 3: Cached (fastest for repeated access)
let image3 = try decoder.decodeROI(
    data: encodedData,
    roi: roi,
    strategy: .cached
)
```

### Performance Comparison

```swift
// Full image extraction:
// - Decodes entire image
// - Extracts requested region
// - Simple but slow for large images

// Direct decoding:
// - Decodes only necessary tiles
// - 3-5× faster than full extraction
// - Recommended for large images

// Cached decoding:
// - Maintains cache of decoded tiles
// - Fastest for repeated ROI access
// - Uses more memory
```

### Multi-Component ROI

```swift
// Decode RGB region
let roi = J2KDecodingROI(
    x: 0, y: 0,
    width: 512, height: 512,
    components: [0, 1, 2]  // R, G, B
)

let image = try decoder.decodeROI(
    data: encodedData,
    roi: roi,
    strategy: .direct
)
```

### ROI with Resolution Level

```swift
// Decode thumbnail from region
let roi = J2KDecodingROI(
    x: 100, y: 100,
    width: 400, height: 400,
    resolutionLevel: 2  // 1/4 resolution
)

let thumbnail = try decoder.decodeROI(
    data: encodedData,
    roi: roi,
    strategy: .direct
)

// Result: 100×100 image (1/4 of 400×400)
```

## Resolution-Progressive Decoding

Access multiple resolution levels:

### Decode Resolution Pyramid

```swift
import J2KCodec

let decoder = J2KAdvancedDecoding()

// Get available resolution levels
let info = try decoder.getImageInfo(data: encodedData)
let maxLevel = info.decompositionLevels

print("Available resolution levels: \(maxLevel + 1)")

// Decode each resolution level
for level in 0...maxLevel {
    let image = try decoder.decodeResolution(
        data: encodedData,
        level: level
    )
    
    let scale = pow(2.0, Double(level))
    let expectedWidth = info.width / Int(scale)
    let expectedHeight = info.height / Int(scale)
    
    print("Level \(level): \(image.width)x\(image.height)")
}
```

### Resolution Level Calculation

```swift
// Original image: 1024×768
// Level 0: 1024×768 (1:1)    - Full resolution
// Level 1:  512×384 (1:2)    - Half resolution
// Level 2:  256×192 (1:4)    - Quarter resolution
// Level 3:  128×96  (1:8)    - Eighth resolution
// Level 4:   64×48  (1:16)   - Sixteenth resolution

// Get dimensions for specific level
func dimensionsForLevel(_ level: Int, original: (Int, Int)) -> (Int, Int) {
    let divisor = Int(pow(2.0, Double(level)))
    return (original.0 / divisor, original.1 / divisor)
}
```

### Decode with Upscaling

```swift
// Decode low resolution and upscale to original size
let image = try decoder.decodeResolution(
    data: encodedData,
    level: 2,
    upscale: true  // Upscale to original dimensions
)

// Fast decoding + upscaling
// Useful for preview/thumbnail generation
```

## Quality-Progressive Decoding

Incrementally decode quality layers:

### Layer-by-Layer Decoding

```swift
import J2KCodec

let decoder = J2KAdvancedDecoding()

// Decode progressively through layers
for layer in 0..<5 {
    let image = try decoder.decodeQuality(
        data: encodedData,
        upToLayer: layer
    )
    
    // Each layer adds more quality
    let quality = calculateQuality(image)
    print("Layer \(layer): Quality \(quality)")
}
```

### Cumulative Layer Decoding

```swift
// Layers are cumulative:
// - Layer 0: Base quality (20% of target)
// - Layer 0-1: Low quality (40% of target)
// - Layer 0-2: Medium quality (60% of target)
// - Layer 0-3: High quality (80% of target)
// - Layer 0-4: Full quality (100% of target)

let baseQuality = try decoder.decodeQuality(
    data: encodedData,
    upToLayer: 0
)

let mediumQuality = try decoder.decodeQuality(
    data: encodedData,
    upToLayer: 2
)

let fullQuality = try decoder.decodeQuality(
    data: encodedData,
    upToLayer: 4
)
```

### Progressive Loading

```swift
// Progressive loading for network streaming
func loadProgressive(data: Data) async throws {
    let decoder = J2KAdvancedDecoding()
    let info = try decoder.getImageInfo(data: data)
    
    for layer in 0..<info.qualityLayers {
        // Decode next layer
        let image = try decoder.decodeQuality(
            data: data,
            upToLayer: layer
        )
        
        // Update display
        await updateDisplay(image)
        
        // Small delay for progressive effect
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}
```

## Incremental Decoding

Decode data as it arrives (useful for streaming):

### Stateful Incremental Decoder

```swift
import J2KCodec

// Create incremental decoder
let decoder = J2KAdvancedDecoding()
let incrementalDecoder = try decoder.createIncrementalDecoder()

// Feed data as it arrives
try incrementalDecoder.addData(chunk1)
try incrementalDecoder.addData(chunk2)
try incrementalDecoder.addData(chunk3)

// Check if image is ready
if incrementalDecoder.isComplete {
    let image = try incrementalDecoder.getImage()
    print("Complete image: \(image.width)x\(image.height)")
} else {
    // Get partial result
    let partial = try incrementalDecoder.getPartialImage()
    print("Partial image available")
}
```

### Streaming from Network

```swift
// Stream and decode progressively
func streamDecode(from url: URL) async throws -> J2KImage {
    let decoder = J2KAdvancedDecoding()
    let incrementalDecoder = try decoder.createIncrementalDecoder()
    
    // Stream data
    let (stream, response) = try await URLSession.shared.bytes(from: url)
    
    var buffer = Data()
    for try await byte in stream {
        buffer.append(byte)
        
        // Feed chunks periodically
        if buffer.count >= 8192 {
            try incrementalDecoder.addData(buffer)
            buffer.removeAll()
            
            // Update display with partial result
            if let partial = try? incrementalDecoder.getPartialImage() {
                await updateDisplay(partial)
            }
        }
    }
    
    // Add remaining data
    if !buffer.isEmpty {
        try incrementalDecoder.addData(buffer)
    }
    
    // Mark complete and get final image
    try incrementalDecoder.complete()
    return try incrementalDecoder.getImage()
}
```

### Handling Incomplete Data

```swift
// Robust handling of incomplete streams
let decoder = J2KAdvancedDecoding()
let incrementalDecoder = try decoder.createIncrementalDecoder()

do {
    try incrementalDecoder.addData(data)
    
    if incrementalDecoder.hasEnoughData {
        let image = try incrementalDecoder.getImage()
        // Process complete image
    } else {
        let progress = incrementalDecoder.completionProgress
        print("Progress: \(progress * 100)%")
    }
} catch J2KError.incompleteData(let message) {
    print("Need more data: \(message)")
    // Wait for more data
}
```

## Advanced Options

### Decoding Configuration

```swift
// Create decoder with configuration
let config = J2KDecodingConfiguration(
    useHardwareAcceleration: true,
    maxMemoryUsage: 500_000_000,  // 500 MB
    cacheDecodedTiles: true,
    parallelTileDecoding: true
)

let decoder = J2KDecoder(configuration: config)
```

### Multi-Threaded Decoding

```swift
// Decode multiple images in parallel
await withTaskGroup(of: J2KImage.self) { group in
    for dataURL in dataURLs {
        group.addTask {
            let data = try! Data(contentsOf: dataURL)
            let decoder = J2KDecoder()
            return try! decoder.decode(data)
        }
    }
    
    for await image in group {
        // Process decoded image
        await processImage(image)
    }
}
```

### Error Recovery

```swift
// Robust decoding with error recovery
func safeDecode(data: Data) -> J2KImage? {
    let decoder = J2KDecoder()
    
    do {
        return try decoder.decode(data)
    } catch J2KError.corruptedData(let message) {
        print("Corrupted data: \(message)")
        
        // Try partial decode
        if let partial = try? decoder.decodePartial(data, ignoreErrors: true) {
            return partial
        }
    } catch J2KError.unsupportedFeature(let message) {
        print("Unsupported feature: \(message)")
    } catch {
        print("Decoding failed: \(error)")
    }
    
    return nil
}
```

### Format-Specific Decoding

```swift
import J2KFileFormat

// Detect format first
let detector = J2KFormatDetector()
let format = try detector.detect(data: data)

switch format {
case .jp2:
    // JP2 file - full metadata available
    let reader = J2KFileReader()
    let image = try reader.read(data: data)
    print("Resolution: \(image.metadata.resolution)")
    
case .j2k:
    // Raw codestream - no metadata
    let decoder = J2KDecoder()
    let image = try decoder.decode(data)
    
case .jpx:
    // JPX file - may have animation
    let reader = J2KFileReader()
    let animation = try reader.readAnimation(data: data)
    print("Frames: \(animation.frameCount)")
    
case .jpm:
    // JPM file - multi-page document
    let reader = J2KFileReader()
    let document = try reader.readDocument(data: data)
    print("Pages: \(document.pageCount)")
}
```

## Performance Tips

### 1. Use Partial Decoding

```swift
// Full decode (slow)
let fullImage = try decoder.decode(data)

// Partial decode (fast)
let options = J2KDecodingOptions(
    maxLayers: 2,
    resolutionLevel: 1
)
let quickImage = try decoder.partialDecode(data, options: options)

// Speedup: 30-50% faster
```

### 2. Use ROI for Large Images

```swift
// For very large images, decode only visible region
if width * height > 100_000_000 {  // >10K resolution
    let visibleROI = J2KDecodingROI(
        x: viewport.x,
        y: viewport.y,
        width: viewport.width,
        height: viewport.height
    )
    
    let image = try decoder.decodeROI(
        data: data,
        roi: visibleROI,
        strategy: .direct
    )
}
```

### 3. Cache Decoded Tiles

```swift
// Enable tile caching for repeated access
let config = J2KDecodingConfiguration(
    cacheDecodedTiles: true,
    maxCacheSize: 100_000_000  // 100 MB
)

let decoder = J2KDecoder(configuration: config)

// First ROI decode
let roi1 = try decoder.decodeROI(data: data, roi: region1)

// Second ROI decode (may reuse cached tiles)
let roi2 = try decoder.decodeROI(data: data, roi: region2)
```

### 4. Use Resolution Pyramid

```swift
// Generate thumbnail quickly
let thumbnail = try decoder.decodeResolution(
    data: data,
    level: 3  // 1/8 resolution
)

// Display thumbnail immediately
await display(thumbnail)

// Load full resolution in background
Task {
    let fullRes = try decoder.decode(data)
    await display(fullRes)
}
```

### 5. Progressive Loading

```swift
// Show progressive quality
Task {
    let info = try decoder.getImageInfo(data: data)
    
    // Show low quality first
    let preview = try decoder.decodeQuality(data: data, upToLayer: 0)
    await display(preview)
    
    // Progressively improve quality
    for layer in 1..<info.qualityLayers {
        let improved = try decoder.decodeQuality(data: data, upToLayer: layer)
        await display(improved)
    }
}
```

### 6. Parallel Decoding

```swift
// Decode multiple images in parallel
let images = await withTaskGroup(of: (Int, J2KImage).self) { group in
    for (index, data) in imageDatas.enumerated() {
        group.addTask {
            let decoder = J2KDecoder()
            let image = try! decoder.decode(data)
            return (index, image)
        }
    }
    
    var results: [(Int, J2KImage)] = []
    for await result in group {
        results.append(result)
    }
    return results.sorted { $0.0 < $1.0 }.map { $0.1 }
}
```

## Complete Example

Here's a complete decoding workflow with all features:

```swift
import J2KCore
import J2KCodec
import J2KFileFormat

class ImageDecoder {
    let decoder: J2KAdvancedDecoding
    
    init() {
        let config = J2KDecodingConfiguration(
            useHardwareAcceleration: true,
            cacheDecodedTiles: true,
            parallelTileDecoding: true
        )
        self.decoder = J2KAdvancedDecoding(configuration: config)
    }
    
    // Decode with automatic optimization
    func decode(_ data: Data, viewport: CGRect? = nil) async throws -> J2KImage {
        // Get image info
        let info = try decoder.getImageInfo(data: data)
        
        print("Image info:")
        print("  Size: \(info.width)×\(info.height)")
        print("  Components: \(info.componentCount)")
        print("  Quality layers: \(info.qualityLayers)")
        print("  Resolution levels: \(info.decompositionLevels + 1)")
        
        // Determine optimal decoding strategy
        if let viewport = viewport {
            // Viewport specified - use ROI decoding
            return try decodeROI(data, viewport: viewport, info: info)
        } else if info.width * info.height > 100_000_000 {
            // Very large image - decode at reduced resolution first
            return try decodeLarge(data, info: info)
        } else {
            // Normal sized image - full decode
            return try decoder.decode(data)
        }
    }
    
    // ROI decoding for viewport
    private func decodeROI(_ data: Data, viewport: CGRect, info: J2KImageInfo) throws -> J2KImage {
        let roi = J2KDecodingROI(
            x: Int(viewport.origin.x),
            y: Int(viewport.origin.y),
            width: Int(viewport.size.width),
            height: Int(viewport.size.height)
        )
        
        return try decoder.decodeROI(
            data: data,
            roi: roi,
            strategy: .cached
        )
    }
    
    // Progressive decoding for large images
    private func decodeLarge(_ data: Data, info: J2KImageInfo) async throws -> J2KImage {
        // First, show low resolution preview
        let preview = try decoder.decodeResolution(
            data: data,
            level: 2  // 1/4 resolution
        )
        
        // Update display
        await updateDisplay(preview)
        
        // Then decode full resolution
        let full = try decoder.decode(data)
        
        return full
    }
    
    // Progressive quality loading
    func loadProgressive(_ data: Data) async throws -> J2KImage {
        let info = try decoder.getImageInfo(data: data)
        
        for layer in 0..<info.qualityLayers {
            let image = try decoder.decodeQuality(
                data: data,
                upToLayer: layer
            )
            
            await updateDisplay(image)
            
            if layer < info.qualityLayers - 1 {
                try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
            }
        }
        
        return try decoder.decode(data)
    }
    
    // Incremental network streaming
    func streamDecode(from url: URL) async throws -> J2KImage {
        let incrementalDecoder = try decoder.createIncrementalDecoder()
        
        let (stream, _) = try await URLSession.shared.bytes(from: url)
        
        var buffer = Data()
        for try await byte in stream {
            buffer.append(byte)
            
            if buffer.count >= 16384 {
                try incrementalDecoder.addData(buffer)
                buffer.removeAll()
                
                // Update display if partial image available
                if let partial = try? incrementalDecoder.getPartialImage() {
                    await updateDisplay(partial)
                }
            }
        }
        
        // Add remaining data
        if !buffer.isEmpty {
            try incrementalDecoder.addData(buffer)
        }
        
        try incrementalDecoder.complete()
        return try incrementalDecoder.getImage()
    }
    
    private func updateDisplay(_ image: J2KImage) async {
        // Update UI with decoded image
        // Implementation depends on your UI framework
    }
}

// Usage
let decoder = ImageDecoder()

// Simple decode
let image = try await decoder.decode(data)

// Progressive decode
let progressive = try await decoder.loadProgressive(data)

// Stream from network
let streamed = try await decoder.streamDecode(from: imageURL)

// ROI decode
let roi = try await decoder.decode(data, viewport: CGRect(x: 100, y: 100, width: 500, height: 500))
```

## Next Steps

- **[File Format Tutorial](TUTORIAL_FILE_FORMAT.md)**: Work with JP2, JPX, JPM formats
- **[JPIP Tutorial](TUTORIAL_JPIP.md)**: Network streaming with JPIP
- **[Performance Tutorial](TUTORIAL_PERFORMANCE.md)**: Optimize decoding performance
- **[Advanced Decoding](ADVANCED_DECODING.md)**: Deep dive into advanced features

---

**Status**: Documentation for Phase 8 (Production Ready)  
**Last Updated**: 2026-02-07
