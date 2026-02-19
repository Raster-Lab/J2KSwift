# JPEG 2000 Part 2: Visual Masking and Perceptual Encoding

## Overview

This document describes the visual masking and perceptual encoding features implemented in J2KSwift as part of ISO/IEC 15444-2 (JPEG 2000 Part 2) support.

Perceptual encoding optimizes compression for human visual perception rather than mathematical metrics. By leveraging knowledge of the human visual system (HVS), these techniques achieve better subjective quality at the same bitrate or lower bitrates at the same perceived quality.

## Table of Contents

1. [Visual Frequency Weighting](#visual-frequency-weighting)
2. [Visual Masking](#visual-masking)
3. [Just-Noticeable Difference (JND)](#just-noticeable-difference)
4. [Perceptual Encoder](#perceptual-encoder)
5. [Quality Metrics](#quality-metrics)
6. [Integration Guide](#integration-guide)
7. [Performance Considerations](#performance-considerations)
8. [API Reference](#api-reference)

## Visual Frequency Weighting

### Contrast Sensitivity Function (CSF)

The human visual system has varying sensitivity to spatial frequencies. The Contrast Sensitivity Function (CSF) models this sensitivity, showing peak sensitivity around 4-8 cycles per degree of visual angle.

J2KSwift implements the Mannos-Sakrison CSF model, which is well-suited for wavelet-based image coding:

```swift
import J2KCodec

// Create visual weighting with default CSF parameters
let weighting = J2KVisualWeighting()

// Calculate weight for a specific subband
let weight = weighting.weight(
    for: .hh,
    decompositionLevel: 2,
    totalLevels: 5,
    imageWidth: 1024,
    imageHeight: 1024
)

// Apply to quantization step size
let perceptualStepSize = baseStepSize * weight
```

### Configuration Options

You can customize the CSF parameters for different viewing conditions:

```swift
let config = J2KVisualWeightingConfiguration(
    peakFrequency: 4.0,        // Peak sensitivity at 4 cycles/degree
    decayRate: 0.4,            // Sensitivity decay rate
    viewingDistance: 60.0,     // Viewing distance in cm
    displayPPI: 96.0,          // Display resolution
    minimumWeight: 0.1,        // Prevents over-quantization
    maximumWeight: 4.0         // Prevents under-quantization
)

let weighting = J2KVisualWeighting(configuration: config)
```

### Subband Weights

The visual weighting system automatically calculates weights for all wavelet subbands:

```swift
let allWeights = weighting.weightsForAllSubbands(
    totalLevels: 5,
    imageWidth: 1024,
    imageHeight: 1024
)

// Access weights by level and subband
for (level, levelWeights) in allWeights.enumerated() {
    for (subband, weight) in levelWeights {
        print("Level \(level), \(subband): weight = \(weight)")
    }
}
```

## Visual Masking

### Luminance-Dependent Masking

Distortions are less visible in very dark or very bright regions. This follows the Weber-Fechner law:

```swift
let masking = J2KVisualMasking()

// Calculate luminance masking factor
let luminanceFactor = masking.luminanceMaskingFactor(luminance: 128.0)

// Apply to quantization
let maskedStepSize = baseStepSize * luminanceFactor
```

The masking effect follows a U-shaped curve:
- **Dark regions** (luminance near 0): High masking (factor > 1.0)
- **Mid-gray** (luminance near 127.5): Minimal masking (factor ≈ 1.0)
- **Bright regions** (luminance near 255): High masking (factor > 1.0)

### Texture-Based Masking

Distortions are less visible in highly textured regions with high spatial activity:

```swift
// Calculate texture masking factor
let textureFactor = masking.textureMaskingFactor(variance: 1000.0)

// Higher variance = more masking (higher factor)
```

The texture masking uses a logarithmic curve that saturates at high variance levels to prevent excessive quantization.

### Motion-Adaptive Masking

For video encoding, distortions are less visible in regions with motion:

```swift
let config = J2KVisualMaskingConfiguration(enableMotionMasking: true)
let masking = J2KVisualMasking(configuration: config)

let motionVector = J2KMotionVector(dx: 10.0, dy: 5.0)
let motionFactor = masking.motionMaskingFactor(motionVector: motionVector)
```

Motion masking increases with motion magnitude but saturates to prevent over-quantization.

### Combined Masking

The masking factors combine multiplicatively to produce a single adjustment:

```swift
let overallFactor = masking.calculateMaskingFactor(
    luminance: 128.0,
    localVariance: 500.0,
    motionVector: motionVector  // Optional
)

let maskedStepSize = baseStepSize * overallFactor
```

### Spatially-Varying Masking

For optimal results, apply masking per-codeblock based on local image characteristics:

```swift
let maskingFactors = masking.calculateRegionMaskingFactors(
    samples: imageData,
    width: 64,
    height: 64,
    bitDepth: 8,
    motionField: motionVectors  // Optional for video
)

// maskingFactors[i] contains the factor for pixel i
```

### Masking Presets

Three configuration presets are provided:

```swift
// Conservative: Higher quality, less aggressive masking
let conservative = J2KVisualMaskingConfiguration.conservative

// Default: Balanced settings
let balanced = J2KVisualMaskingConfiguration.default

// Aggressive: Higher compression, more aggressive masking
let aggressive = J2KVisualMaskingConfiguration.aggressive
```

## Just-Noticeable Difference

The JND model calculates the minimum distortion threshold that is perceptible to the human eye:

```swift
let jnd = J2KJNDModel()

let threshold = jnd.jndThreshold(
    luminance: 128.0,
    localVariance: 100.0,
    viewingDistance: 60.0
)

// Quantization errors below this threshold are imperceptible
```

The JND threshold depends on:
1. **Luminance**: Based on Weber-Fechner law
2. **Texture**: Higher variance increases threshold
3. **Viewing distance**: Closer viewing decreases threshold

## Perceptual Encoder

### Quality Targets

The perceptual encoder supports multiple quality targets:

```swift
// Target SSIM value (0-1, higher is better)
let ssimTarget = J2KQualityTarget.ssim(0.95)

// Target MS-SSIM value (0-1, higher is better)
let msssimTarget = J2KQualityTarget.msssim(0.95)

// Target PSNR in dB
let psnrTarget = J2KQualityTarget.psnr(40.0)

// Target bitrate in bits per pixel
let bitrateTarget = J2KQualityTarget.bitrate(2.0)
```

### Configuration

Configure the perceptual encoder with your desired settings:

```swift
let config = J2KPerceptualEncodingConfiguration(
    targetQuality: .ssim(0.95),
    enableVisualMasking: true,
    enableFrequencyWeighting: true,
    maxIterations: 3,
    qualityTolerance: 0.01
)

let encoder = J2KPerceptualEncoder(configuration: config)
```

### Preset Configurations

Four preset configurations are available:

```swift
// High quality: SSIM 0.98, conservative masking
let highQuality = J2KPerceptualEncodingConfiguration.highQuality

// Balanced: MS-SSIM 0.95, default settings
let balanced = J2KPerceptualEncodingConfiguration.balanced

// Default: SSIM 0.95, default settings
let standard = J2KPerceptualEncodingConfiguration.default

// High compression: SSIM 0.90, aggressive masking
let compressed = J2KPerceptualEncodingConfiguration.highCompression
```

### Perceptual Quantization

Calculate perceptually optimized quantization steps:

```swift
let quantSteps = encoder.calculatePerceptualQuantizationSteps(
    baseQuantization: 0.1,
    image: image,
    decompositionLevels: 5
)

// Returns array of steps indexed by [level][subband]
for (level, levelSteps) in quantSteps.enumerated() {
    for (subband, stepSize) in levelSteps {
        print("Level \(level), \(subband): step = \(stepSize)")
    }
}
```

### Spatially-Varying Quantization

For even better perceptual quality, use spatially-varying quantization:

```swift
let spatialSteps = encoder.calculateSpatiallyVaryingQuantization(
    samples: codeblockData,
    width: 64,
    height: 64,
    bitDepth: 8,
    baseQuantization: 0.1,
    subband: .hh,
    decompositionLevel: 2,
    totalLevels: 5
)

// Returns per-pixel quantization steps
```

### Rate-Distortion Optimization

Estimate base quantization for a target bitrate:

```swift
let baseQuant = encoder.estimateBaseQuantization(
    targetBitrate: 2.0,  // bits per pixel
    imageSize: 1024 * 1024
)
```

Adjust quantization based on quality feedback:

```swift
let adjustedQuant = encoder.adjustQuantization(
    currentQuantization: 0.1,
    targetQuality: 0.95,
    achievedQuality: 0.92
)
```

## Quality Metrics

### PSNR (Peak Signal-to-Noise Ratio)

Fast but not perceptually accurate:

```swift
let metrics = J2KQualityMetrics()

let psnrResult = try metrics.psnr(
    original: originalImage,
    compressed: compressedImage
)

print("PSNR: \(psnrResult.value) dB")
```

### SSIM (Structural Similarity Index)

Perceptually motivated metric considering luminance, contrast, and structure:

```swift
let ssimResult = try metrics.ssim(
    original: originalImage,
    compressed: compressedImage
)

print("SSIM: \(ssimResult.value)")  // 0-1, higher is better
```

### MS-SSIM (Multi-Scale SSIM)

Evaluates quality at multiple scales for different viewing distances:

```swift
let msssimResult = try metrics.msssim(
    original: originalImage,
    compressed: compressedImage,
    scales: 5
)

print("MS-SSIM: \(msssimResult.value)")  // 0-1, higher is better
```

### Quality Evaluation

Evaluate if an encoding meets a quality target:

```swift
let meetsTarget = try encoder.meetsQualityTarget(
    original: originalImage,
    encoded: encodedImage
)

if meetsTarget {
    print("Quality target achieved!")
}
```

Calculate all metrics at once:

```swift
let allMetrics = try encoder.calculateAllQualityMetrics(
    original: originalImage,
    encoded: encodedImage
)

for (metric, result) in allMetrics {
    print("\(metric): \(result.value)")
}
```

## Integration Guide

### Basic Perceptual Encoding

Here's a complete example of perceptual encoding:

```swift
import J2KCodec
import J2KCore

// 1. Create encoder with perceptual configuration
let config = J2KPerceptualEncodingConfiguration.balanced
let perceptualEncoder = J2KPerceptualEncoder(configuration: config)

// 2. Load your image
let image = try loadImage(from: "input.jpg")

// 3. Calculate perceptual quantization steps
let quantSteps = perceptualEncoder.calculatePerceptualQuantizationSteps(
    baseQuantization: 0.1,
    image: image,
    decompositionLevels: 5
)

// 4. Encode with these steps
// (Integration with main encoder pipeline - see below)

// 5. Evaluate quality
let quality = try perceptualEncoder.evaluateQuality(
    original: image,
    encoded: encodedImage
)

print("Achieved quality: \(quality.value)")
```

### Integration with Encoding Pipeline

To integrate perceptual encoding with the main J2K encoder:

```swift
// 1. Calculate perceptual weights
let weighting = J2KVisualWeighting()
let masking = J2KVisualMasking()

// 2. For each wavelet coefficient codeblock:
for codeblock in codeblocks {
    // Get frequency weight
    let frequencyWeight = weighting.weight(
        for: codeblock.subband,
        decompositionLevel: codeblock.level,
        totalLevels: totalLevels,
        imageWidth: image.width,
        imageHeight: image.height
    )
    
    // Get spatial masking factors
    let maskingFactors = masking.calculateRegionMaskingFactors(
        samples: codeblock.samples,
        width: codeblock.width,
        height: codeblock.height,
        bitDepth: bitDepth,
        motionField: nil
    )
    
    // Apply perceptual quantization
    for i in 0..<codeblock.samples.count {
        let perceptualStep = baseStep * frequencyWeight * maskingFactors[i]
        codeblock.quantizedCoeffs[i] = quantize(
            codeblock.samples[i],
            stepSize: perceptualStep
        )
    }
}
```

### Iterative Quality-Targeted Encoding

For precise quality targeting:

```swift
func encodeToTargetQuality(
    image: J2KImage,
    targetSSIM: Double,
    tolerance: Double = 0.01
) throws -> Data {
    let encoder = J2KPerceptualEncoder()
    var baseQuant = 0.1
    var iteration = 0
    let maxIterations = 5
    
    while iteration < maxIterations {
        // Encode with current quantization
        let encoded = try encode(image, quantization: baseQuant)
        let decoded = try decode(encoded)
        
        // Evaluate quality
        let quality = try encoder.evaluateQuality(
            original: image,
            encoded: decoded
        )
        
        // Check if target is met
        if abs(quality.value - targetSSIM) < tolerance {
            return encoded
        }
        
        // Adjust quantization
        baseQuant = encoder.adjustQuantization(
            currentQuantization: baseQuant,
            targetQuality: targetSSIM,
            achievedQuality: quality.value
        )
        
        iteration += 1
    }
    
    // Return best attempt
    return try encode(image, quantization: baseQuant)
}
```

## Performance Considerations

### Computational Complexity

**Visual Frequency Weighting:**
- Complexity: O(N) where N is number of subbands
- Cost: Negligible, computed once per subband
- Recommendation: Always enable for perceptual encoding

**Visual Masking:**
- Complexity: O(W×H×K²) where K is window size (typically 8)
- Cost: Moderate, scales with image size
- Recommendation: Enable for high-quality encoding

**Quality Metrics:**
- PSNR: O(W×H) - very fast
- SSIM: O(W×H×K²) - moderate cost
- MS-SSIM: O(W×H×K²×S) where S is number of scales - higher cost

### Optimization Tips

1. **Batch Processing**: Calculate masking factors once per codeblock rather than per coefficient

2. **Quality Metric Frequency**: Don't calculate SSIM/MS-SSIM every iteration, use PSNR for intermediate checks

3. **Spatial Resolution**: For very large images, consider calculating masking on downsampled version

4. **Caching**: Cache frequency weights as they depend only on image dimensions and decomposition levels

### Memory Usage

- Visual weighting: ~100 bytes per configuration
- Masking factors: 8 bytes per pixel (Double)
- Quality metrics: Temporary buffers ~4× image size for SSIM windows

For a 1024×1024 image:
- Masking factors: ~8 MB
- SSIM computation: ~16 MB temporary

## API Reference

### J2KVisualWeighting

```swift
public struct J2KVisualWeighting: Sendable {
    public init(configuration: J2KVisualWeightingConfiguration = .default)
    
    public func weight(
        for subband: J2KSubband,
        decompositionLevel: Int,
        totalLevels: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> Double
    
    public func weightsForAllSubbands(
        totalLevels: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> [[J2KSubband: Double]]
    
    public func perceptualStepSize(
        baseStepSize: Double,
        for subband: J2KSubband,
        decompositionLevel: Int,
        totalLevels: Int,
        imageWidth: Int,
        imageHeight: Int
    ) -> Double
}
```

### J2KVisualMasking

```swift
public struct J2KVisualMasking: Sendable {
    public init(configuration: J2KVisualMaskingConfiguration = .default)
    
    public func calculateMaskingFactor(
        luminance: Double,
        localVariance: Double,
        motionVector: J2KMotionVector? = nil
    ) -> Double
    
    public func calculateRegionMaskingFactors(
        samples: [Int32],
        width: Int,
        height: Int,
        bitDepth: Int,
        motionField: [[J2KMotionVector]]? = nil
    ) -> [Double]
    
    public func luminanceMaskingFactor(luminance: Double) -> Double
    public func textureMaskingFactor(variance: Double) -> Double
    public func motionMaskingFactor(motionVector: J2KMotionVector) -> Double
    
    public func perceptualStepSize(
        baseStepSize: Double,
        luminance: Double,
        localVariance: Double,
        motionVector: J2KMotionVector? = nil
    ) -> Double
}
```

### J2KPerceptualEncoder

```swift
public struct J2KPerceptualEncoder: Sendable {
    public init(configuration: J2KPerceptualEncodingConfiguration = .default)
    
    public func calculatePerceptualQuantizationSteps(
        baseQuantization: Double,
        image: J2KImage,
        decompositionLevels: Int
    ) -> [[J2KSubband: Double]]
    
    public func calculateSpatiallyVaryingQuantization(
        samples: [Int32],
        width: Int,
        height: Int,
        bitDepth: Int,
        baseQuantization: Double,
        subband: J2KSubband,
        decompositionLevel: Int,
        totalLevels: Int
    ) -> [Double]
    
    public func meetsQualityTarget(
        original: J2KImage,
        encoded: J2KImage
    ) throws -> Bool
    
    public func evaluateQuality(
        original: J2KImage,
        encoded: J2KImage
    ) throws -> J2KQualityMetricResult
    
    public func calculateAllQualityMetrics(
        original: J2KImage,
        encoded: J2KImage
    ) throws -> [String: J2KQualityMetricResult]
    
    public func estimateBaseQuantization(
        targetBitrate: Double,
        imageSize: Int
    ) -> Double
    
    public func adjustQuantization(
        currentQuantization: Double,
        targetQuality: Double,
        achievedQuality: Double
    ) -> Double
}
```

### J2KJNDModel

```swift
public struct J2KJNDModel: Sendable {
    public func jndThreshold(
        luminance: Double,
        localVariance: Double,
        viewingDistance: Double = 60.0
    ) -> Double
}
```

### J2KQualityMetrics

```swift
public struct J2KQualityMetrics: Sendable {
    public init()
    
    public func psnr(
        original: J2KImage,
        compressed: J2KImage
    ) throws -> J2KQualityMetricResult
    
    public func ssim(
        original: J2KImage,
        compressed: J2KImage
    ) throws -> J2KQualityMetricResult
    
    public func msssim(
        original: J2KImage,
        compressed: J2KImage,
        scales: Int = 5
    ) throws -> J2KQualityMetricResult
}
```

## References

1. ISO/IEC 15444-2:2004 - Information technology — JPEG 2000 image coding system: Extensions
2. Mannos, J.L., Sakrison, D.J., "The Effects of a Visual Fidelity Criterion on the Encoding of Images," IEEE Trans. Information Theory, 1974
3. Wang, Z., Bovik, A.C., Sheikh, H.R., Simoncelli, E.P., "Image Quality Assessment: From Error Visibility to Structural Similarity," IEEE Trans. Image Processing, 2004
4. Wang, Z., Simoncelli, E.P., Bovik, A.C., "Multi-Scale Structural Similarity for Image Quality Assessment," Asilomar Conference on Signals, Systems and Computers, 2003

## See Also

- [PART2_NLT.md](PART2_NLT.md) - Non-Linear Point Transforms
- [PART2_MCT.md](PART2_MCT.md) - Multi-Component Transforms
- [PART2_EXTENDED_ROI.md](PART2_EXTENDED_ROI.md) - Extended ROI Methods
- [RATE_CONTROL.md](../RATE_CONTROL.md) - Rate-Distortion Optimization
- [QUANTIZATION.md](../QUANTIZATION.md) - Quantization Techniques
