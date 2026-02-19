# Part 2 Variable DC Offset and Extended Precision

> ISO/IEC 15444-2 Annex A.3 – Variable DC Offset and Extended Precision Arithmetic

## Overview

J2KSwift implements the variable DC offset and extended precision features defined in ISO/IEC 15444-2 (JPEG 2000 Part 2). These features improve compression efficiency for images with non-zero mean component values and provide higher accuracy for high bit depth and HDR imaging.

## Variable DC Offset

### What Is DC Offset?

The DC offset represents the mean (average) value of an image component's samples. When this value is significantly different from zero, the wavelet coefficients in the low-frequency (LL) subband carry a large DC component that reduces compression efficiency.

By subtracting the DC offset before encoding and signaling it in the codestream, the encoder can center the data around zero, improving the energy compaction of the wavelet transform.

### How It Works

1. **Analysis** (encoder): Compute per-component statistics (mean, min, max)
2. **Removal** (encoder): Subtract the DC offset to center data around zero
3. **Signaling** (codestream): Store offsets in DCO marker segments (0xFF5C)
4. **Restoration** (decoder): Add the offset back during decoding

### Configuration

```swift
// Enable DC offset in encoder configuration
let config = J2KEncodingConfiguration(
    dcOffsetConfiguration: J2KDCOffsetConfiguration(
        enabled: true,
        method: .mean,               // or .midrange
        optimizeForNaturalImages: false
    )
)
let encoder = J2KEncoder(encodingConfiguration: config)
```

### Offset Computation Methods

| Method | Description | Best For |
|--------|-------------|----------|
| `.mean` | Arithmetic mean of all samples | General purpose |
| `.midrange` | Midpoint of (min + max) / 2 | Uniform distributions |
| `.custom` | User-specified offset value | Expert control |

### DCO Marker Segment (0xFF5C)

The DCO marker segment encodes per-component offset values in the codestream:

```
Marker code: 0xFF5C (2 bytes)
Ldco:        Segment length (2 bytes)
Sdco:        Offset type (1 byte): 0=integer, 1=float
SPdco_i:     Offset value for component i (4 bytes each)
```

### Direct API Usage

```swift
let dcOffset = J2KDCOffset(configuration: .default)

// Encoder: compute and remove DC offset
let result = try dcOffset.computeAndRemove(
    componentData: pixelData,
    componentIndex: 0,
    bitDepth: 8,
    signed: false
)
// result.adjustedData — centered data
// result.offset       — offset value for marker segment

// Generate DCO marker for codestream
let marker = dcOffset.createMarkerSegment(from: [result])
let markerData = try marker.encode()

// Decoder: restore DC offset
let restored = dcOffset.apply(offset: result.offset, to: decodedData)
```

### Multi-Component Support

```swift
let dcOffset = J2KDCOffset()

// Process all components (e.g., RGB)
let results = try dcOffset.computeAndRemoveAll(
    components: [redData, greenData, blueData],
    bitDepths: [8, 8, 8],
    signed: [false, false, false]
)

// Restore all components
let restored = try dcOffset.applyAll(
    offsets: results.map { $0.offset },
    to: results.map { $0.adjustedData }
)
```

## Extended Precision

### Guard Bits

Standard JPEG 2000 (Part 1) supports 0–7 guard bits. Part 2 extends this to 0–15 guard bits, providing greater overflow protection for:

- High dynamic range (HDR) images with bit depths > 16
- Multi-level wavelet decomposition (many levels)
- Lossless compression with large dynamic ranges

```swift
// Standard (Part 1 compatible)
let standard = try J2KExtendedGuardBits(count: 2)

// Extended for HDR
let extended = try J2KExtendedGuardBits(count: 10)

// Get recommendation based on image parameters
let recommended = J2KExtendedPrecision.recommendedGuardBits(
    forBitDepth: 16,
    decompositionLevels: 5
)
// Returns 6 (5 levels + 1 extra for >12-bit depth)
```

### Rounding Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| `.truncate` | Round toward zero | Fastest, standard Part 1 |
| `.roundToNearest` | Standard rounding | Best general accuracy |
| `.roundToEven` | Banker's rounding | Minimal cumulative bias |

```swift
let config = J2KExtendedPrecisionConfiguration(
    internalBitDepth: 64,
    guardBits: try! J2KExtendedGuardBits(count: 8),
    roundingMode: .roundToEven,
    extendedDynamicRange: true
)
let precision = J2KExtendedPrecision(configuration: config)

let rounded = precision.round(2.5)    // → 2.0 (banker's rounding)
let int32 = precision.roundToInt32(3.5) // → 4
```

### Extended Dynamic Range

For images with bit depths > 16, extended dynamic range uses 64-bit storage to prevent overflow during wavelet transform and quantization:

```swift
let precision = J2KExtendedPrecision(configuration: .highPrecision)

// Convert to extended range for processing
let extended = precision.toExtendedRange(int32Coefficients)

// Process in extended range (Int64)...

// Convert back to Int32 with clamping
let result = precision.fromExtendedRange(extended, bitDepth: 16)
```

### Preset Configurations

| Preset | Bit Depth | Guard Bits | Rounding | Extended Range |
|--------|-----------|------------|----------|----------------|
| `.default` | 32 | 2 | Nearest | No |
| `.standard` | 32 | 2 | Nearest | No |
| `.highPrecision` | 64 | 4 | Even | Yes |

## Pipeline Integration

### Encoder Pipeline

DC offset and extended precision integrate into the encoding pipeline:

```swift
let config = J2KEncodingConfiguration(
    quality: 0.95,
    dcOffsetConfiguration: .default,
    extendedPrecisionConfiguration: .highPrecision
)
let encoder = J2KEncoder(encodingConfiguration: config)
let data = try encoder.encode(image)
```

### Rate-Distortion Optimization

DC offset removal improves compression efficiency by 5–15% for images with non-zero mean values. The `J2KDCOffsetDistortionAdjustment` utility estimates this gain:

```swift
let adjustment = J2KDCOffsetDistortionAdjustment(
    offsets: dcOffsetResults.map { $0.offset },
    bitDepths: [8, 8, 8]
)

// Per-component efficiency gain factor
let gain = adjustment.compressionEfficiencyGain(forComponent: 0)
// e.g., 1.075 for 50% of dynamic range offset

// Adjust distortion estimate
let adjustedDistortion = adjustment.adjustDistortion(100.0, forComponent: 0)
```

### JP2/JPX File Format

When DC offset is enabled, the encoder writes a DCO feature box (`dcof`) in the JP2 header and includes DCO marker segments in the codestream:

```swift
let box = J2KDCOffsetExtensionBox(
    offsetType: .integer,
    componentCount: 3,
    enabled: true
)
```

## Hardware Acceleration

On Apple platforms, DC offset and coefficient scaling operations use the Accelerate framework for 4–8× speedup:

```swift
let accelerated = J2KDCOffsetAccelerated()

// Vectorized mean computation
let mean = try accelerated.computeMean(data)

// Vectorized offset removal
let adjusted = try accelerated.removeOffset(Float(mean), from: data)

// Vectorized coefficient scaling
let scaled = try accelerated.scaleCoefficients(coefficients, by: 2.0)
```

## Performance Characteristics

| Operation | Scalar | Accelerate | Speedup |
|-----------|--------|------------|---------|
| Mean computation | O(n) | vDSP_meanv | 4–8× |
| Offset removal | O(n) | vDSP_vsadd | 4–8× |
| Coefficient scaling | O(n) | vDSP_vsmul | 4–8× |
| Coefficient clamping | O(n) | vDSP_vclip | 4–8× |

## Best Practices

1. **Enable DC offset** for medical imaging, satellite imagery, and scientific data where mean pixel values are typically non-zero.
2. **Use midrange method** for images with uniform distributions or known data ranges.
3. **Use extended precision** (`.highPrecision`) for bit depths > 16 to prevent overflow.
4. **Check guard bit sufficiency** before encoding to prevent wavelet coefficient overflow.
5. **Keep Part 1 compatibility** by using `.disabled` DC offset and `.default` precision for maximum interoperability.

## Standards Reference

- ISO/IEC 15444-2:2004, Annex A.3 — DCO marker segment
- ISO/IEC 15444-2:2004, Annex J — Extended capabilities
- ISO/IEC 15444-2:2004, Table A.37 — DCO marker segment parameters
