# JPEG 2000 Quantization

This document describes the quantization implementation in J2KSwift, which is part of Phase 3 of the development roadmap.

## Overview

Quantization is the primary source of lossy compression in JPEG 2000. It converts the continuous-valued wavelet coefficients to discrete integer indices, reducing the precision of the data while maintaining perceptual quality.

J2KSwift implements the quantization stage according to ISO/IEC 15444-1 (JPEG 2000 Part 1), supporting multiple quantization modes for different use cases.

## Quantization Modes

### 1. Scalar Quantization

Standard uniform quantization where all coefficients in a subband are quantized using the same step size.

```swift
// Forward quantization
q = sign(c) × floor(|c| / Δ)

// Inverse quantization (reconstruction)
c' = (q + 0.5 × sign(q)) × Δ
```

**Characteristics:**
- Simple and efficient
- Uniform spacing between quantization levels
- Reconstruction to bin centers

### 2. Deadzone Quantization

Similar to scalar quantization but with an enlarged zero bin (deadzone). This provides better compression for sparse signals by mapping more small values to zero.

```swift
// Forward quantization
q = sign(c) × floor((|c| - t) / Δ) + 1   for |c| > t
q = 0                                     for |c| <= t

// where t = Δ × deadzoneWidth × 0.5
```

**Characteristics:**
- Better rate-distortion performance
- Preserves sparsity in wavelet domain
- Configurable deadzone width (typically 0.5 to 2.0)

### 3. Expounded Quantization

Each subband has an explicitly specified step size, allowing fine-grained control over quality at different frequency bands.

**Characteristics:**
- Maximum flexibility
- Requires explicit step size table
- Useful for custom quality profiles

### 4. No Quantization (Lossless Mode)

Coefficients are passed through without modification. Only valid when used with the reversible (5/3) wavelet transform.

**Characteristics:**
- Perfect reconstruction
- Used for lossless compression
- Integer-to-integer mapping

## Step Size Calculation

The step size for each subband is derived from a base step size using:

```
Δ_b = Δ_base × 2^(level) / G_b
```

Where:
- `Δ_base` is the base step size (derived from quality settings)
- `level` is the decomposition level (0 = finest)
- `G_b` is the subband gain

### Subband Gains

| Filter Type | LL | LH/HL | HH |
|-------------|-----|-------|-----|
| 5/3 (reversible) | 1.0 | √2 | 2.0 |
| 9/7 (irreversible) | 1.0 | 2.0 | 4.0 |

## Usage Examples

### Basic Usage

```swift
import J2KCodec

// Create quantizer with default lossy parameters
let params = J2KQuantizationParameters.lossy
let quantizer = J2KQuantizer(parameters: params)

// Quantize a coefficient
let quantized = quantizer.quantizeCoefficient(125.5, stepSize: 4.0)

// Dequantize (reconstruct)
let reconstructed = quantizer.dequantizeIndex(quantized, stepSize: 4.0)
```

### Quality-Based Quantization

```swift
// Create parameters from quality factor (0.0 = lowest, 1.0 = highest)
let params = J2KQuantizationParameters.fromQuality(0.85)
let quantizer = J2KQuantizer(parameters: params, reversible: false)

// Quantize 2D subband
let quantized = try quantizer.quantize2D(
    coefficients: dwtCoefficients,
    subband: .hl,
    decompositionLevel: 1,
    totalLevels: 3
)
```

### Lossless Quantization

```swift
// Create lossless parameters
let params = J2KQuantizationParameters.lossless
let quantizer = J2KQuantizer(parameters: params, reversible: true)

// For lossless mode, coefficients pass through unchanged (as integers)
let quantized = try quantizer.quantize2D(
    coefficients: intCoefficients,
    subband: .ll,
    decompositionLevel: 0,
    totalLevels: 1
)
```

### Custom Step Sizes (Expounded Mode)

```swift
// Define explicit step sizes for each subband
let explicitSteps: [String: Double] = [
    "LL3": 0.5,
    "LH1": 4.0, "HL1": 4.0, "HH1": 8.0,
    "LH2": 2.0, "HL2": 2.0, "HH2": 4.0,
    "LH3": 1.0, "HL3": 1.0, "HH3": 2.0
]

let params = J2KQuantizationParameters(
    mode: .expounded,
    baseStepSize: 1.0,
    implicitStepSizes: false,
    explicitStepSizes: explicitSteps
)

let quantizer = J2KQuantizer(parameters: params)
```

### Complete Decomposition Quantization

```swift
// Quantize all subbands from a DWT decomposition
let (qLL, qLH, qHL, qHH) = try quantizer.quantizeDecomposition(
    ll: llSubband,
    lh: lhSubband,
    hl: hlSubband,
    hh: hhSubband,
    decompositionLevel: 0,
    totalLevels: 3
)

// Dequantize for reconstruction
let (dLL, dLH, dHL, dHH) = try quantizer.dequantizeDecomposition(
    ll: qLL, lh: qLH, hl: qHL, hh: qHH,
    decompositionLevel: 0,
    totalLevels: 3
)
```

## Dynamic Range Adjustment

For different bit depths, the quantization parameters need adjustment:

```swift
// Adjust step size for 16-bit data (relative to 8-bit reference)
let adjustedStep = J2KDynamicRange.adjustStepSize(
    baseStepSize,
    forBitDepth: 16,
    referenceBitDepth: 8
)

// Get maximum magnitude for a bit depth
let maxMag = J2KDynamicRange.maxMagnitude(bitDepth: 12, signed: true) // 2047
```

## Step Size Encoding

For file format compatibility, step sizes are encoded as exponent/mantissa pairs:

```swift
// Encode step size
let (exponent, mantissa) = J2KStepSizeCalculator.encodeStepSize(1.5)

// Decode step size
let stepSize = J2KStepSizeCalculator.decodeStepSize(
    exponent: exponent,
    mantissa: mantissa
)
```

## Guard Bits

Guard bits prevent overflow during quantization:

```swift
// Configure guard bits (0-7)
let guardBits = try J2KGuardBits(count: 2)

let params = J2KQuantizationParameters(
    mode: .deadzone,
    baseStepSize: 1.0,
    guardBits: guardBits
)
```

## Performance Considerations

1. **Step Size Selection**: Smaller step sizes preserve more detail but reduce compression ratio
2. **Deadzone Width**: Larger deadzones improve sparsity but may lose low-amplitude details
3. **Quality Factor**: Use `J2KQuantizationParameters.fromQuality()` for automatic step size selection

## Integration with DWT

Quantization operates on the output of the Discrete Wavelet Transform:

```
Image → DWT → Quantization → Entropy Coding → Bitstream
         ↓
    Subbands: LL, LH, HL, HH at each level
         ↓
    Each subband quantized with appropriate step size
```

## API Reference

### J2KQuantizationMode

```swift
public enum J2KQuantizationMode: Sendable, Equatable, CaseIterable {
    case scalar
    case deadzone
    case expounded
    case noQuantization
}
```

### J2KQuantizationParameters

```swift
public struct J2KQuantizationParameters: Sendable, Equatable {
    public let mode: J2KQuantizationMode
    public let baseStepSize: Double
    public let deadzoneWidth: Double
    public let guardBits: J2KGuardBits
    public let implicitStepSizes: Bool
    public let explicitStepSizes: [String: Double]
    
    public static let lossy: J2KQuantizationParameters
    public static let lossless: J2KQuantizationParameters
    public static func fromQuality(_ quality: Double) -> J2KQuantizationParameters
}
```

### J2KQuantizer

```swift
public struct J2KQuantizer: Sendable {
    public init(parameters: J2KQuantizationParameters, reversible: Bool = false)
    
    public func quantizeCoefficient(_ coefficient: Double, stepSize: Double) -> Int32
    public func dequantizeIndex(_ index: Int32, stepSize: Double) -> Double
    
    public func quantize(coefficients: [Double], subband: J2KSubband, ...) throws -> [Int32]
    public func quantize2D(coefficients: [[Double]], subband: J2KSubband, ...) throws -> [[Int32]]
    public func quantize2D(coefficients: [[Int32]], subband: J2KSubband, ...) throws -> [[Int32]]
    
    public func dequantize(indices: [Int32], subband: J2KSubband, ...) throws -> [Double]
    public func dequantize2D(indices: [[Int32]], subband: J2KSubband, ...) throws -> [[Double]]
    public func dequantize2DToInt(indices: [[Int32]], subband: J2KSubband, ...) throws -> [[Int32]]
    
    public func quantizeDecomposition(...) throws -> (ll:, lh:, hl:, hh:)
    public func dequantizeDecomposition(...) throws -> (ll:, lh:, hl:, hh:)
}
```

## Test Coverage

The quantization module includes 44 comprehensive tests covering:

- All quantization modes
- Step size calculation
- Dynamic range adjustment
- 1D and 2D quantization
- Edge cases (zero values, extreme values)
- Roundtrip (quantize-dequantize) accuracy
- Sendable conformance

## Future Work

- **Week 44-45**: Region of Interest (ROI) - MaxShift method for selective quality
- **Week 46-48**: Rate Control - PCRD-opt algorithm for target bitrate

---

**Last Updated**: 2026-02-06
**Implementation Status**: Complete ✅
**Test Coverage**: 44 tests, 100% pass rate
