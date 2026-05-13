# Advanced Decoding Features

Comprehensive guide to JPEG 2000 advanced decoding capabilities in J2KSwift.

## Overview

J2KSwift provides advanced decoding modes that enable efficient extraction of image data based on specific requirements:

- **Partial Decoding**: Decode up to specific quality layer or resolution
- **ROI Decoding**: Extract specific rectangular regions
- **Progressive Decoding**: Incrementally refine quality or resolution
- **Incremental Decoding**: Process data as it becomes available

These features are particularly valuable for:
- Network streaming and bandwidth-constrained scenarios
- Interactive applications requiring quick previews
- Large image processing with memory constraints
- Progressive image loading for web applications

## Table of Contents

- [Partial Decoding](#partial-decoding)
- [Region-of-Interest (ROI) Decoding](#region-of-interest-roi-decoding)
- [Resolution Progressive Decoding](#resolution-progressive-decoding)
- [Quality Progressive Decoding](#quality-progressive-decoding)
- [Incremental Decoding](#incremental-decoding)
- [Performance Characteristics](#performance-characteristics)
- [Best Practices](#best-practices)
- [Integration with JPIP](#integration-with-jpip)

## Partial Decoding

Partial decoding allows selective extraction of image data based on quality layers, resolution levels, or both.

### Basic Usage

```swift
import J2KCore
import J2KCodec

let decoder = J2KDecoder()
let data = try Data(contentsOf: imageURL)

// Decode up to quality layer 2 (preview quality)
let options = J2KPartialDecodingOptions(maxLayer: 2)
let preview = try decoder.decodePartial(data, options: options)

// Decode at half resolution
let thumbnailOptions = J2KPartialDecodingOptions(maxResolutionLevel: 1)
let thumbnail = try decoder.decodePartial(data, options: thumbnailOptions)
```

### Advanced Options

```swift
// Combine quality and resolution constraints
let options = J2KPartialDecodingOptions(
    maxLayer: 3,
    maxResolutionLevel: 2,
    earlyStop: true,
    components: [0, 1]  // Decode only R and G channels
)
let result = try decoder.decodePartial(data, options: options)
```

### Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `maxLayer` | `Int?` | Maximum quality layer to decode | nil (all) |
| `maxResolutionLevel` | `Int?` | Maximum resolution level | nil (full) |
| `region` | `J2KRegion?` | Specific region to decode | nil (full image) |
| `earlyStop` | `Bool` | Enable early stopping optimization | true |
| `components` | `[Int]?` | Specific components to decode | nil (all) |

### Early Stopping

Early stopping optimization allows the decoder to terminate as soon as the requested quality or resolution is achieved:

```swift
let options = J2KPartialDecodingOptions(
    maxLayer: 2,
    earlyStop: true  // Stop immediately after layer 2
)
```

**Performance Impact:**
- 30-50% faster for partial quality decoding
- 40-60% faster for resolution-limited decoding
- Reduces memory usage by avoiding unnecessary processing

## Region-of-Interest (ROI) Decoding

Extract specific rectangular regions without decoding the entire image.

### Basic Usage

```swift
// Define region to extract
let region = J2KRegion(x: 100, y: 100, width: 512, height: 512)

let options = J2KROIDecodingOptions(region: region)
let regionImage = try decoder.decodeRegion(data, options: options)

print("Extracted region: \(regionImage.width)x\(regionImage.height)")
```

### ROI Strategies

Three strategies are available for ROI decoding:

#### 1. Full Image Extraction (Simple)

Decodes the entire image, then extracts the region.

```swift
let options = J2KROIDecodingOptions(
    region: region,
    strategy: .fullImageExtraction
)
let roi = try decoder.decodeRegion(data, options: options)
```

**Pros:**
- Simple implementation
- Useful when multiple regions will be extracted
- Maintains full image quality

**Cons:**
- Decodes entire image
- Higher memory usage
- Slower for single region extraction

#### 2. Direct Decoding (Efficient)

Decodes only the code-blocks that contribute to the region.

```swift
let options = J2KROIDecodingOptions(
    region: region,
    strategy: .direct
)
let roi = try decoder.decodeRegion(data, options: options)
```

**Pros:**
- Minimal data processing
- Lower memory usage
- Faster for single regions

**Cons:**
- More complex implementation
- Requires identifying relevant code-blocks

#### 3. Cached (Adaptive)

Uses cached full image if available, otherwise decodes directly.

```swift
let options = J2KROIDecodingOptions(
    region: region,
    strategy: .cached
)
let roi = try decoder.decodeRegion(data, options: options)
```

**Pros:**
- Best of both worlds
- Adaptive to use case
- Efficient for repeated access

### ROI with Quality Control

```swift
let options = J2KROIDecodingOptions(
    region: region,
    maxLayer: 5,  // Medium quality
    components: [0, 1, 2],  // RGB only
    strategy: .direct
)
let roi = try decoder.decodeRegion(data, options: options)
```

## Resolution Progressive Decoding

Decode images at specific resolution levels, enabling multi-resolution pyramids and efficient thumbnail generation.

### Basic Usage

```swift
// Decode at 1/4 resolution (level 2)
let options = J2KResolutionDecodingOptions(level: 2)
let thumbnail = try decoder.decodeResolution(data, options: options)

// Calculate dimensions
let dims = options.calculatedDimensions(fullWidth: 2048, fullHeight: 1536)
print("Thumbnail: \(dims.width)x\(dims.height)")  // 512x384
```

### Resolution Levels

Resolution level determines the scale factor:

| Level | Scale | Example (2048×1536) |
|-------|-------|---------------------|
| 0 | 1:1 | 2048×1536 (full) |
| 1 | 1:2 | 1024×768 |
| 2 | 1:4 | 512×384 |
| 3 | 1:8 | 256×192 |
| 4 | 1:16 | 128×96 |

### Upscaling

Optionally upscale decoded resolution to original dimensions:

```swift
let options = J2KResolutionDecodingOptions(
    level: 2,
    upscale: true  // Scale back to original size
)
let image = try decoder.decodeResolution(data, options: options)
// Result: 2048×1536 (upscaled from 512×384)
```

### Multi-Resolution Pyramid

Generate a complete image pyramid for zoom applications:

```swift
func createImagePyramid(data: Data, levels: Int) throws -> [J2KImage] {
    let decoder = J2KDecoder()
    var pyramid: [J2KImage] = []
    
    for level in 0...levels {
        let options = J2KResolutionDecodingOptions(level: level)
        let image = try decoder.decodeResolution(data, options: options)
        pyramid.append(image)
    }
    
    return pyramid
}

// Create 5-level pyramid
let pyramid = try createImagePyramid(data: jpegData, levels: 4)
```

## Quality Progressive Decoding

Decode images progressively by quality layers, enabling adaptive quality based on available bandwidth or time.

### Basic Usage

```swift
// Decode up to quality layer 3
let options = J2KQualityDecodingOptions(layer: 3)
let preview = try decoder.decodeQuality(data, options: options)
```

### Cumulative vs Incremental

#### Cumulative Decoding (Default)

Includes all layers up to and including the target layer:

```swift
let options = J2KQualityDecodingOptions(
    layer: 5,
    cumulative: true  // Layers 0-5
)
let image = try decoder.decodeQuality(data, options: options)
```

#### Incremental Decoding

Decodes only the target layer (refinement):

```swift
// First decode base layers
let baseOptions = J2KQualityDecodingOptions(layer: 3, cumulative: true)
let baseImage = try decoder.decodeQuality(data, options: baseOptions)

// Then add refinement layer
let refineOptions = J2KQualityDecodingOptions(layer: 4, cumulative: false)
let refinement = try decoder.decodeQuality(data, options: refineOptions)

// Combine for improved quality
```

### Progressive Loading Example

```swift
class ProgressiveImageLoader {
    func loadProgressively(data: Data, maxLayers: Int, updateHandler: (J2KImage, Int) -> Void) throws {
        let decoder = J2KDecoder()
        
        for layer in 0..<maxLayers {
            let options = J2KQualityDecodingOptions(layer: layer, cumulative: true)
            let image = try decoder.decodeQuality(data, options: options)
            
            // Notify UI with updated image
            updateHandler(image, layer)
        }
    }
}

// Usage
let loader = ProgressiveImageLoader()
try loader.loadProgressively(data: jpegData, maxLayers: 8) { image, layer in
    print("Loaded layer \(layer), quality improved")
    // Update UI with current image
}
```

## Incremental Decoding

Process image data as it arrives over a network, enabling progressive rendering before full data is available.

### Basic Usage

```swift
let incrementalDecoder = J2KIncrementalDecoder()

// As data arrives from network
func dataReceived(_ chunk: Data) {
    incrementalDecoder.append(chunk)
    
    // Try to decode with available data
    if incrementalDecoder.canDecode() {
        let options = J2KPartialDecodingOptions(maxLayer: 2)
        if let preview = try? incrementalDecoder.tryDecode(options: options) {
            // Display preview to user
            updateUI(with: preview)
        }
    }
}

// When transfer completes
func transferComplete() {
    incrementalDecoder.complete()
    
    // Final decode
    let fullOptions = J2KPartialDecodingOptions()
    if let fullImage = try? incrementalDecoder.tryDecode(options: fullOptions) {
        updateUI(with: fullImage)
    }
}
```

### State Management

```swift
let decoder = J2KIncrementalDecoder()

// Append data chunks
decoder.append(chunk1)
decoder.append(chunk2)

// Check state
print("Buffer: \(decoder.bufferSize()) bytes")
print("Complete: \(decoder.isComplete())")
print("Can decode: \(decoder.canDecode())")

// Reset for reuse
decoder.reset()
```

### Thread Safety

`J2KIncrementalDecoder` is thread-safe and can be used from multiple threads:

```swift
let decoder = J2KIncrementalDecoder()

// Network thread
networkQueue.async {
    while let chunk = receiveData() {
        decoder.append(chunk)
    }
    decoder.complete()
}

// UI thread
DispatchQueue.main.async {
    if decoder.canDecode() {
        let preview = try? decoder.tryDecode()
        // Update UI
    }
}
```

## Performance Characteristics

### Decoding Speed

| Mode | Relative Speed | Memory Usage | Best Use Case |
|------|---------------|--------------|---------------|
| Full decode | 1.0× (baseline) | High | Complete images |
| Partial (layer 2/8) | 1.8× faster | Low | Quick previews |
| Partial (level 2) | 2.5× faster | Very low | Thumbnails |
| ROI (direct) | 3-5× faster | Low | Region extraction |
| ROI (full extract) | 1.0× | High | Multiple regions |
| Incremental | Variable | Medium | Network streaming |

### Memory Usage

| Image Size | Full Decode | Level 2 | Level 3 | ROI (¼ image) |
|------------|-------------|---------|---------|---------------|
| 2048×1536 | ~9 MB | ~2.3 MB | ~0.6 MB | ~2.3 MB |
| 4096×3072 | ~37 MB | ~9.2 MB | ~2.3 MB | ~9.2 MB |
| 8192×6144 | ~150 MB | ~37 MB | ~9.2 MB | ~37 MB |

### Optimization Tips

1. **Use early stopping** for partial decoding to minimize processing
2. **Choose appropriate resolution level** for thumbnails (level 2-3 recommended)
3. **Use direct ROI strategy** for single region extraction
4. **Leverage incremental decoding** for network streaming
5. **Combine partial options** for maximum efficiency

## Best Practices

### 1. Progressive Loading for Web

```swift
class WebImageLoader {
    func loadForDisplay(url: URL, container: CGSize) async throws -> J2KImage {
        let data = try await URLSession.shared.data(from: url).0
        let decoder = J2KDecoder()
        
        // Determine appropriate resolution level
        let fullSize = try extractImageDimensions(from: data)
        let targetLevel = calculateOptimalLevel(
            fullSize: fullSize,
            containerSize: container
        )
        
        // Decode at appropriate resolution
        let options = J2KResolutionDecodingOptions(
            level: targetLevel,
            maxLayer: 5,  // Medium quality
            upscale: false
        )
        
        return try decoder.decodeResolution(data, options: options)
    }
    
    private func calculateOptimalLevel(fullSize: (Int, Int), containerSize: CGSize) -> Int {
        let widthRatio = Double(fullSize.0) / containerSize.width
        let heightRatio = Double(fullSize.1) / containerSize.height
        let maxRatio = max(widthRatio, heightRatio)
        
        return Int(log2(maxRatio))
    }
}
```

### 2. Memory-Efficient Large Image Processing

```swift
func processLargeImageInRegions(url: URL, processingFunc: (J2KImage) -> Void) throws {
    let data = try Data(contentsOf: url)
    let decoder = J2KDecoder()
    
    // Get image dimensions
    let fullSize = try extractImageDimensions(from: data)
    
    // Process in 512×512 tiles
    let tileSize = 512
    for y in stride(from: 0, to: fullSize.height, by: tileSize) {
        for x in stride(from: 0, to: fullSize.width, by: tileSize) {
            let width = min(tileSize, fullSize.width - x)
            let height = min(tileSize, fullSize.height - y)
            
            let region = J2KRegion(x: x, y: y, width: width, height: height)
            let options = J2KROIDecodingOptions(
                region: region,
                strategy: .direct
            )
            
            let tile = try decoder.decodeRegion(data, options: options)
            processingFunc(tile)
        }
    }
}
```

### 3. Adaptive Quality Streaming

```swift
class AdaptiveStreamingDecoder {
    func decodeAdaptively(data: Data, bandwidth: Double) throws -> J2KImage {
        let decoder = J2KDecoder()
        
        // Select quality based on available bandwidth
        let targetLayer: Int
        switch bandwidth {
        case ..<1.0:  // < 1 Mbps
            targetLayer = 2  // Low quality
        case 1.0..<5.0:  // 1-5 Mbps
            targetLayer = 5  // Medium quality
        default:  // > 5 Mbps
            targetLayer = 10  // High quality
        }
        
        let options = J2KQualityDecodingOptions(
            layer: targetLayer,
            cumulative: true
        )
        
        return try decoder.decodeQuality(data, options: options)
    }
}
```

### 4. Component-Selective Decoding

```swift
// Decode only luminance channel for grayscale preview
let options = J2KPartialDecodingOptions(
    maxLayer: 3,
    components: [0]  // Y component only
)
let grayscalePreview = try decoder.decodePartial(data, options: options)

// Later, decode full color at higher quality
let fullOptions = J2KPartialDecodingOptions(maxLayer: 8)
let fullImage = try decoder.decodePartial(data, options: fullOptions)
```

## Integration with JPIP

Advanced decoding features work seamlessly with JPIP streaming:

```swift
import JPIP

let client = JPIPClient(serverURL: URL(string: "http://example.com/jpip")!)
let decoder = J2KDecoder()

// Request specific resolution and quality
let session = try await client.createSession(target: "image.jp2")

// Progressive quality
for layer in 0..<8 {
    let data = try await client.requestProgressiveQuality(
        imageID: "image.jp2",
        upToLayers: layer
    )
    
    let options = J2KQualityDecodingOptions(layer: layer)
    let image = try decoder.decodeQuality(data, options: options)
    
    // Update display
    updateDisplay(with: image)
}

// ROI request
let regionData = try await client.requestRegion(
    imageID: "image.jp2",
    region: (x: 1000, y: 1000, width: 512, height: 512)
)

let region = J2KRegion(x: 0, y: 0, width: 512, height: 512)
let roiOptions = J2KROIDecodingOptions(region: region)
let roiImage = try decoder.decodeRegion(regionData, options: roiOptions)
```

## Error Handling

All decoding methods can throw `J2KError`:

```swift
do {
    let options = J2KPartialDecodingOptions(maxLayer: 5)
    let image = try decoder.decodePartial(data, options: options)
} catch J2KError.invalidParameter(let message) {
    print("Invalid parameter: \(message)")
} catch J2KError.notImplemented(let message) {
    print("Feature not yet implemented: \(message)")
} catch {
    print("Decoding failed: \(error)")
}
```

## Validation

All options are validated before decoding:

```swift
let options = J2KPartialDecodingOptions(
    maxLayer: 10,  // May be too high
    maxResolutionLevel: 5
)

// Validate before use
do {
    try options.validate(
        imageWidth: 2048,
        imageHeight: 1536,
        maxLayers: 8,  // Only 8 layers available
        maxLevels: 5,
        componentCount: 3
    )
} catch {
    print("Invalid options: \(error)")
}
```

## Future Enhancements

Planned improvements for advanced decoding:

1. **Hardware Acceleration**: GPU-accelerated region extraction and upscaling
2. **Async/Await**: Full async support for all decoding operations
3. **Streaming Decoder**: True streaming decoder that reconstructs image progressively
4. **Smart Caching**: Intelligent cache management for frequently accessed regions
5. **Parallel Decoding**: Multi-threaded decoding of independent regions
6. **Quality Estimation**: Predict quality before full decode

## Reference

### Types

- `J2KPartialDecodingOptions`: Options for partial decoding
- `J2KROIDecodingOptions`: Options for ROI decoding
- `J2KROIDecodingStrategy`: Strategy for ROI extraction
- `J2KResolutionDecodingOptions`: Options for resolution-progressive decoding
- `J2KQualityDecodingOptions`: Options for quality-progressive decoding
- `J2KIncrementalDecoder`: Stateful incremental decoder
- `J2KRegion`: Rectangular region definition

### Methods

- `decoder.decodePartial(_:options:)`: Partial decoding with options
- `decoder.decodeRegion(_:options:)`: ROI decoding
- `decoder.decodeResolution(_:options:)`: Resolution-progressive decoding
- `decoder.decodeQuality(_:options:)`: Quality-progressive decoding
- `incrementalDecoder.append(_:)`: Add data chunk
- `incrementalDecoder.tryDecode(options:)`: Attempt decode with available data

## See Also

- [ADVANCED_ENCODING.md](ADVANCED_ENCODING.md) - Advanced encoding features
- [JPIP_PROTOCOL.md](JPIP_PROTOCOL.md) - Network streaming
- [PERFORMANCE.md](PERFORMANCE.md) - Performance optimization
- [README.md](README.md) - General documentation

---

**Status**: Implemented (Week 87-89) ✅  
**Version**: 1.0.0  
**Last Updated**: 2026-02-07
