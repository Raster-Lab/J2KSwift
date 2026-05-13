# Advanced Encoding Features

This document describes the advanced encoding features implemented in J2KSwift, including encoding presets, progressive encoding modes, and variable bitrate control.

## Overview

J2KSwift provides sophisticated encoding capabilities that enable:
- **Quick configuration** through presets optimized for different use cases
- **Progressive encoding** for streaming and adaptive delivery
- **Flexible bitrate control** for various quality and size requirements
- **Perceptual optimization** using visual frequency weighting and quality metrics

## Encoding Presets

Encoding presets provide predefined configurations optimized for different performance/quality tradeoffs.

### Available Presets

#### Fast Preset
Optimized for encoding speed with acceptable quality.

```swift
let config = J2KEncodingPreset.fast.configuration()
let encoder = J2KEncoder(configuration: config)
```

**Characteristics:**
- 3 decomposition levels (vs 5 for balanced)
- 64×64 code blocks (larger for faster processing)
- 3 quality layers
- Single-threaded encoding
- No visual weighting
- 512×512 tile size

**Performance:** 2-3× faster than balanced preset  
**Use Cases:** Real-time encoding, thumbnails, previews, draft quality

#### Balanced Preset (Default)
Optimal balance of quality and performance for general use.

```swift
let config = J2KEncodingPreset.balanced.configuration()
let encoder = J2KEncoder(configuration: config)
```

**Characteristics:**
- 5 decomposition levels (standard)
- 32×32 code blocks (optimal balance)
- 5 quality layers
- Multi-threaded encoding (auto-detect cores)
- Visual weighting enabled for lossy
- 1024×1024 tile size

**Performance:** Reference baseline  
**Use Cases:** General purpose, web delivery, storage, most applications

#### Quality Preset
Maximum quality encoding for archival and professional use.

```swift
let config = J2KEncodingPreset.quality.configuration()
let encoder = J2KEncoder(configuration: config)
```

**Characteristics:**
- 6 decomposition levels (maximum detail)
- 32×32 code blocks
- 10 quality layers (fine-grained progression)
- Multi-threaded with aggressive optimization
- Visual weighting enabled
- 2048×2048 tile size

**Performance:** 1.5-2× slower than balanced  
**Use Cases:** Archival, medical imaging, professional photography, maximum quality requirements

### Customizing Presets

Presets can be customized with different quality settings:

```swift
// Fast preset with higher quality
let config = J2KEncodingPreset.fast.configuration(quality: 0.95)

// Balanced preset with lossless compression
let config = J2KEncodingPreset.balanced.configuration(lossless: true)
```

### Custom Configuration

For complete control, create a custom configuration:

```swift
let config = J2KEncodingConfiguration(
    quality: 0.85,
    lossless: false,
    decompositionLevels: 4,
    codeBlockSize: (width: 48, height: 48),
    qualityLayers: 7,
    progressionOrder: .rpcl,
    enableVisualWeighting: true,
    tileSize: (width: 768, height: 768),
    bitrateMode: .constantBitrate(bitsPerPixel: 0.75),
    maxThreads: 4
)

try config.validate()  // Ensures parameters are valid
let encoder = J2KEncoder(configuration: config)
```

## Progressive Encoding

Progressive encoding enables images to be decoded at different levels of quality or resolution, perfect for streaming and adaptive delivery.

### Progressive Modes

#### SNR (Quality) Progressive

Encodes multiple quality layers for progressive quality improvement:

```swift
// 8 quality layers for smooth progression
let mode = J2KProgressiveMode.snr(layers: 8)
var config = J2KEncodingConfiguration()
config.qualityLayers = mode.qualityLayers
config.progressionOrder = mode.recommendedProgressionOrder  // LRCP
```

**Use Cases:**
- Progressive web image delivery
- Quality-adaptive streaming
- Bandwidth-constrained networks
- Low-to-high quality transitions

#### Spatial (Resolution) Progressive

Encodes multiple resolution levels through wavelet decomposition:

```swift
// Up to 5 decomposition levels
let mode = J2KProgressiveMode.spatial(maxLevel: 5)
var config = J2KEncodingConfiguration()
config.decompositionLevels = mode.decompositionLevels!
config.progressionOrder = mode.recommendedProgressionOrder  // RLCP
```

**Resolution Levels:**
- Level 0: Full resolution
- Level 1: 1/2 resolution (each dimension)
- Level 2: 1/4 resolution
- Level 3: 1/8 resolution
- Level N: 1/(2^N) resolution

**Use Cases:**
- Multi-resolution image pyramids
- Zoom applications
- Responsive image delivery
- Thumbnail generation

#### Layer Progressive (Streaming)

Optimized for streaming with immediate display:

```swift
// 6 layers with resolution-first ordering
let mode = J2KProgressiveMode.layerProgressive(layers: 6, resolutionFirst: true)
var config = J2KEncodingConfiguration()
config.qualityLayers = mode.qualityLayers
config.progressionOrder = mode.recommendedProgressionOrder
```

**Use Cases:**
- Real-time streaming
- Network-adaptive delivery
- Interactive applications
- Progressive download

#### Combined Progressive

Provides both quality AND resolution progression:

```swift
// 8 quality layers × 5 decomposition levels
let mode = J2KProgressiveMode.combined(
    qualityLayers: 8,
    decompositionLevels: 5
)
var config = J2KEncodingConfiguration()
config.qualityLayers = mode.qualityLayers
config.decompositionLevels = mode.decompositionLevels!
config.progressionOrder = mode.recommendedProgressionOrder  // RPCL
```

**Use Cases:**
- Advanced streaming applications
- Multi-purpose image delivery
- Adaptive content delivery networks (CDN)
- Maximum flexibility

### Progressive Encoding Strategies

Use predefined strategies for common scenarios:

```swift
// Quality-progressive: Best for quality progression
let strategy = J2KProgressiveEncodingStrategy.qualityProgressive(layers: 8)

// Resolution-progressive: Best for resolution progression
let strategy = J2KProgressiveEncodingStrategy.resolutionProgressive(levels: 5)

// Streaming: Optimized for network delivery
let strategy = J2KProgressiveEncodingStrategy.streaming(layers: 6, levels: 4)
```

### Progressive Decoding

Decode images progressively with fine-grained control:

```swift
let decoder = J2KDecoder()

// Decode up to layer 3 (preview quality)
let preview = try decoder.decodeProgressive(
    data,
    options: J2KProgressiveDecodingOptions(maxLayer: 3)
)

// Decode at 1/4 resolution
let thumbnail = try decoder.decodeProgressive(
    data,
    options: J2KProgressiveDecodingOptions(maxResolutionLevel: 2)
)

// Decode specific region at full quality
let region = J2KRegion(x: 100, y: 100, width: 512, height: 512)
let detail = try decoder.decodeProgressive(
    data,
    options: J2KProgressiveDecodingOptions(region: region)
)
```

## Variable Bitrate Control

J2KSwift supports multiple bitrate control modes for different encoding requirements.

### Constant Quality Mode (Default)

Maintains consistent quality across the image:

```swift
var config = J2KEncodingConfiguration()
config.bitrateMode = .constantQuality
config.quality = 0.9  // 90% quality
```

**Characteristics:**
- Quality remains constant
- File size varies based on image complexity
- Best visual quality for target setting
- Default mode for most applications

### Constant Bitrate Mode

Targets a specific file size or bitrate:

```swift
var config = J2KEncodingConfiguration()
config.bitrateMode = .constantBitrate(bitsPerPixel: 0.5)
// Results in 2:1 compression ratio
```

**Characteristics:**
- File size is predictable
- Quality varies to achieve target size
- Useful for bandwidth-limited scenarios
- Common compression ratios:
  - 0.5 bpp: 2:1 compression
  - 1.0 bpp: 1:1 compression (near-lossless)
  - 2.0 bpp: 0.5:1 compression (very high quality)

### Variable Bitrate Mode

Maintains quality above a threshold while respecting a maximum file size:

```swift
var config = J2KEncodingConfiguration()
config.bitrateMode = .variableBitrate(
    minQuality: 0.7,      // Never go below 70% quality
    maxBitsPerPixel: 1.0  // But don't exceed 1 bpp
)
```

**Characteristics:**
- Quality-constrained with size limit
- Best of both worlds
- Adapts to image complexity
- Ensures minimum quality while controlling size

### Lossless Mode

Perfect reconstruction with no quality loss:

```swift
var config = J2KEncodingConfiguration()
config.bitrateMode = .lossless
config.lossless = true  // Also set this flag
```

**Characteristics:**
- Zero quality loss
- Perfect reconstruction
- File size varies significantly by content
- Uses reversible color transform (RCT)
- Uses 5/3 reversible wavelet filter

## Visual Frequency Weighting

Visual frequency weighting optimizes compression based on human visual perception.

### How It Works

The human visual system has varying sensitivity to different spatial frequencies:
- Most sensitive around 4-8 cycles per degree
- Less sensitive to very low and high frequencies
- Varies by viewing distance and display resolution

J2KSwift uses the Mannos-Sakrison Contrast Sensitivity Function (CSF) model to:
1. Calculate spatial frequency for each wavelet subband
2. Convert to visual frequency based on viewing geometry
3. Compute sensitivity using CSF model
4. Adjust quantization step sizes accordingly

### Usage

Visual weighting is automatically enabled in balanced and quality presets:

```swift
var config = J2KEncodingConfiguration()
config.enableVisualWeighting = true
config.quality = 0.8  // Applies perceptual weighting
```

### Custom Viewing Parameters

For advanced control, use `J2KVisualWeighting` directly:

```swift
let weighting = J2KVisualWeighting(
    configuration: J2KVisualWeightingConfiguration(
        peakFrequency: 4.0,        // cycles per degree
        decayRate: 0.4,            // sensitivity falloff
        viewingDistance: 60.0,     // cm (typical monitor)
        displayPPI: 96.0,          // pixels per inch
        minimumWeight: 0.1,        // 10% of base
        maximumWeight: 4.0         // 4× base
    )
)

// Calculate weight for specific subband
let weight = weighting.weight(
    for: .hh,                  // High-high frequency subband
    decompositionLevel: 2,
    totalLevels: 5,
    imageWidth: 1024,
    imageHeight: 768
)

// Apply to quantization step size
let perceptualStepSize = baseStepSize * weight
```

## Perceptual Quality Metrics

J2KSwift provides multiple quality metrics for evaluating compression:

### PSNR (Peak Signal-to-Noise Ratio)

Simple MSE-based metric, widely used for benchmarking:

```swift
let metrics = J2KQualityMetrics()
let psnr = try metrics.psnr(original: originalImage, compressed: compressedImage)
print("PSNR: \(psnr.value) dB")

// Per-component PSNR
if let componentPSNRs = psnr.componentValues {
    for (index, value) in componentPSNRs.enumerated() {
        print("Component \(index): \(value) dB")
    }
}
```

**Interpretation:**
- 40+ dB: Excellent quality
- 30-40 dB: Good quality
- 20-30 dB: Acceptable quality
- <20 dB: Poor quality

### SSIM (Structural Similarity Index)

Perceptually motivated metric considering luminance, contrast, and structure:

```swift
let ssim = try metrics.ssim(original: originalImage, compressed: compressedImage)
print("SSIM: \(ssim.value)")  // Range: -1 to 1 (1 = perfect)
```

**Interpretation:**
- 0.95-1.0: Excellent quality (near-identical)
- 0.90-0.95: Good quality (barely perceptible)
- 0.80-0.90: Fair quality (noticeable differences)
- <0.80: Poor quality (visible artifacts)

**Advantages:**
- Better correlation with human perception than PSNR
- Considers structural information
- More reliable for quality assessment

### MS-SSIM (Multi-Scale SSIM)

Extended SSIM evaluating quality at multiple scales:

```swift
let msssim = try metrics.msssim(
    original: originalImage,
    compressed: compressedImage,
    scales: 5  // Number of scales to evaluate
)
print("MS-SSIM: \(msssim.value)")
```

**Advantages:**
- Captures quality across different viewing distances
- More robust than single-scale SSIM
- Best perceptual correlation

## Progression Orders

JPEG 2000 supports five progression orders for packet organization:

### LRCP (Layer-Resolution-Component-Position)
- Encode by quality layer first
- Good for quality-progressive applications
- Used in: Fast preset, SNR progressive mode

### RLCP (Resolution-Layer-Component-Position)
- Encode by resolution first
- Good for resolution-progressive applications
- Used in: Spatial progressive mode

### RPCL (Resolution-Position-Component-Layer)
- Encode by resolution, then spatial position
- Best for streaming and progressive download
- Used in: Balanced preset, Quality preset, Combined progressive mode

### PCRL (Position-Component-Resolution-Layer)
- Encode by spatial position first
- Good for spatial locality and region-of-interest
- Used in: Custom configurations for ROI applications

### CPRL (Component-Position-Resolution-Layer)
- Encode by component first
- Good for applications processing components separately
- Used in: Custom configurations for multi-spectral imaging

## Performance Considerations

### Encoding Speed vs Quality

| Preset/Mode | Relative Speed | Quality | Best For |
|-------------|---------------|---------|----------|
| Fast | 1.0× (baseline) | Good | Real-time, previews |
| Balanced | 0.4-0.5× | Excellent | General use |
| Quality | 0.2-0.3× | Best | Archival, professional |
| Lossless | 0.6-0.8× | Perfect | Medical, critical data |

### Memory Usage

- **Tiling**: Enables memory-efficient processing of large images
  - Fast: 512×512 tiles
  - Balanced: 1024×1024 tiles
  - Quality: 2048×2048 tiles
- **Progressive encoding**: Minimal memory overhead
- **Multi-threading**: Scales well up to 8 cores (81% efficiency)

### File Size Guidelines

Typical compression ratios by quality:

| Quality | Compression Ratio | File Size | Visual Quality |
|---------|------------------|-----------|----------------|
| 0.5 | 15:1 to 20:1 | ~5% | Acceptable |
| 0.7 | 10:1 to 15:1 | ~8% | Good |
| 0.9 | 5:1 to 10:1 | ~15% | Excellent |
| 0.95 | 3:1 to 5:1 | ~25% | Near-lossless |
| 1.0 (lossless) | 2:1 to 3:1 | ~40% | Perfect |

## Examples

### Quick Start with Presets

```swift
import J2KCore
import J2KCodec

// Fast encoding for real-time preview
let fastConfig = J2KEncodingPreset.fast.configuration()
let fastEncoder = J2KEncoder(configuration: fastConfig)
let previewData = try fastEncoder.encode(image)

// High-quality archival encoding
let qualityConfig = J2KEncodingPreset.quality.configuration()
let qualityEncoder = J2KEncoder(configuration: qualityConfig)
let archivalData = try qualityEncoder.encode(image)
```

### Progressive Streaming

```swift
// Encode with progressive layers
let config = J2KEncodingPreset.balanced.configuration()
config.qualityLayers = 8
config.progressionOrder = .rpcl
let encoder = J2KEncoder(configuration: config)
let progressiveData = try encoder.encode(image)

// Decode progressively
let decoder = J2KDecoder()

// Quick preview (layers 1-2)
let preview = try decoder.decodeProgressive(
    progressiveData,
    options: J2KProgressiveDecodingOptions(maxLayer: 2, earlyStop: true)
)

// Medium quality (layers 1-4)
let medium = try decoder.decodeProgressive(
    progressiveData,
    options: J2KProgressiveDecodingOptions(maxLayer: 4, earlyStop: true)
)

// Full quality (all layers)
let full = try decoder.decode(progressiveData)
```

### Constant Bitrate Encoding

```swift
// Target 0.5 bits per pixel (2:1 compression)
var config = J2KEncodingConfiguration()
config.bitrateMode = .constantBitrate(bitsPerPixel: 0.5)
let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)

// Verify file size
let bitsPerPixel = Double(data.count * 8) / Double(image.width * image.height * image.components.count)
print("Achieved: \(bitsPerPixel) bpp")  // Should be close to 0.5
```

### Quality Assessment

```swift
// Encode image
let encoder = J2KEncoder(configuration: config)
let compressed = try encoder.encode(originalImage)

// Decode for comparison
let decoder = J2KDecoder()
let reconstructed = try decoder.decode(compressed)

// Evaluate quality
let metrics = J2KQualityMetrics()
let psnr = try metrics.psnr(original: originalImage, compressed: reconstructed)
let ssim = try metrics.ssim(original: originalImage, compressed: reconstructed)
let msssim = try metrics.msssim(original: originalImage, compressed: reconstructed)

print("PSNR: \(psnr.value) dB")
print("SSIM: \(ssim.value)")
print("MS-SSIM: \(msssim.value)")
```

## Best Practices

### Choosing a Preset

1. **Use Fast** when:
   - Real-time encoding is required
   - Quality can be sacrificed for speed
   - Generating previews or thumbnails
   - Processing on resource-constrained devices

2. **Use Balanced** when:
   - Quality and speed are both important
   - General-purpose encoding
   - Web delivery
   - Most applications (default choice)

3. **Use Quality** when:
   - Maximum quality is required
   - Archival or long-term storage
   - Medical or scientific imaging
   - Professional photography
   - Encoding speed is not critical

### Progressive Encoding

1. **Use SNR progressive** for:
   - Web image delivery
   - Quality-adaptive streaming
   - Bandwidth-constrained scenarios

2. **Use Spatial progressive** for:
   - Multi-resolution applications
   - Zoom interfaces
   - Responsive image delivery

3. **Use Combined progressive** for:
   - Advanced streaming applications
   - Maximum flexibility
   - CDN delivery with adaptive bitrate

### Bitrate Control

1. **Use Constant Quality** (default) for:
   - Best visual quality
   - When file size is not critical
   - Most applications

2. **Use Constant Bitrate** for:
   - Predictable file sizes
   - Bandwidth-limited delivery
   - Storage-constrained scenarios

3. **Use Variable Bitrate** for:
   - Quality-constrained with size limits
   - Adaptive quality based on content
   - Best balance of quality and size

4. **Use Lossless** for:
   - Medical imaging
   - Scientific data
   - Archival master copies
   - When perfect reconstruction is required

## References

- JPEG 2000 Standard (ISO/IEC 15444-1)
- Mannos & Sakrison CSF Model (1974)
- Wang et al., "Image Quality Assessment" (2004)
- OpenJPEG documentation

## See Also

- [WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md) - Wavelet decomposition details
- [QUANTIZATION.md](QUANTIZATION.md) - Quantization methods
- [RATE_CONTROL.md](RATE_CONTROL.md) - Rate-distortion optimization
- [MILESTONES.md](MILESTONES.md) - Project roadmap and status
