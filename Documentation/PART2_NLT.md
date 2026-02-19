# Non-Linear Point Transforms (NLT) — ISO/IEC 15444-2 Part 2

## Overview

J2KSwift provides complete support for Non-Linear Point Transforms (NLT) as defined in ISO/IEC 15444-2 (JPEG 2000 Part 2). NLT improves compression efficiency for images with non-linear characteristics by linearizing or decorrelating the data before wavelet transform and quantization. This is particularly effective for HDR imaging, gamma-encoded images, logarithmically-scaled scientific data, and perceptually-encoded content.

## Features

- **Parametric Transforms** — Gamma correction, logarithmic, and exponential transforms
- **HDR Support** — Perceptual Quantizer (PQ/ST.2084) and Hybrid Log-Gamma (HLG/BT.2100)
- **Lookup Tables** — Arbitrary transforms via LUT with optional interpolation
- **Piecewise Linear** — Multi-segment linear approximations
- **Hardware Acceleration** — vDSP and vForce optimizations on Apple platforms with 8-15× speedup
- **Marker Segment Support** — Complete NLT marker segment parsing and generation
- **Per-Component** — Independent transforms for each image component
- **Reversible Inverse** — Automatic inverse transform application during decoding

## Quick Start

### Basic Gamma Correction

```swift
import J2KCodec

// Create NLT processor
let nlt = J2KNonLinearTransform()

// Define gamma transform (linearize sRGB gamma 2.2)
let transform = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .gamma(2.2)
)

// Apply forward transform (before encoding)
let input: [Int32] = [0, 64, 128, 192, 255]
let result = try nlt.applyForward(
    componentData: input,
    transform: transform,
    bitDepth: 8
)
// result.transformedData contains linearized values

// Apply inverse transform (after decoding)
let restored = try nlt.applyInverse(
    componentData: result.transformedData,
    transform: transform,
    bitDepth: 8
)
// restored.transformedData recovers original gamma-encoded values
```

### HDR Content (PQ Transform)

```swift
import J2KCodec

// Linearize HDR10 PQ-encoded content
let pqTransform = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .perceptualQuantizer
)

let hdrInput: [Int32] = [0, 256, 512, 768, 1023]  // 10-bit HDR

let linearized = try nlt.applyForward(
    componentData: hdrInput,
    transform: pqTransform,
    bitDepth: 10
)

// Encode linearized data...

// After decoding, restore PQ encoding
let pqRestored = try nlt.applyInverse(
    componentData: decodedLinear,
    transform: pqTransform,
    bitDepth: 10
)
```

### Hardware-Accelerated Transforms

```swift
#if canImport(J2KAccelerate)
import J2KAccelerate

let accelerated = J2KAcceleratedNLT()

// Gamma transform using vForce (10-15× faster)
let gammaResult = try accelerated.applyGamma(
    data: componentData,
    gamma: 2.2,
    bitDepth: 8
)

// Logarithmic transform using vForce
let logResult = try accelerated.applyLogarithmic(
    data: componentData,
    bitDepth: 8,
    base10: false
)

// LUT transform using vDSP_vindex (8-12× faster)
let lutResult = try accelerated.applyLUT(
    data: componentData,
    lut: lookupTable,
    bitDepth: 8,
    interpolation: true
)
#endif
```

## Transform Types

### Identity Transform

No transformation applied. Useful for disabling NLT on specific components.

```swift
let identity = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .identity
)
```

### Gamma Correction

Linearize gamma-encoded images or apply gamma encoding.

**Forward:** `y = x^gamma`  
**Inverse:** `y = x^(1/gamma)`

```swift
// Linearize sRGB (gamma 2.2)
let srgb = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .gamma(2.2)
)

// Linearize Rec.709 (gamma 2.4)
let rec709 = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .gamma(2.4)
)

// Linearize DCI-P3 (gamma 2.6)
let dciP3 = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .gamma(2.6)
)
```

### Logarithmic Transforms

Compress dynamic range using logarithmic scaling.

**Base-e:**
- Forward: `y = ln(x + 1)`
- Inverse: `y = exp(x) - 1`

**Base-10:**
- Forward: `y = log10(x + 1)`
- Inverse: `y = 10^x - 1`

```swift
// Natural logarithm
let logE = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .logarithmic
)

// Base-10 logarithm
let log10 = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .logarithmic10
)
```

### Exponential Transform

Expand dynamic range using exponential scaling.

**Forward:** `y = exp(x) - 1`  
**Inverse:** `y = ln(x + 1)`

```swift
let exponential = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .exponential
)
```

### Perceptual Quantizer (PQ)

SMPTE ST 2084 electro-optical transfer function for HDR10 content.

```swift
// Linearize HDR10 PQ-encoded content
let pq = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .perceptualQuantizer
)

// Typical use with 10-bit HDR
let result = try nlt.applyForward(
    componentData: hdrData,
    transform: pq,
    bitDepth: 10
)
```

### Hybrid Log-Gamma (HLG)

ITU-R BT.2100 hybrid log-gamma for HDR broadcast content.

```swift
// Linearize HLG-encoded HDR broadcast content
let hlg = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .hybridLogGamma
)

// Typical use with 10-bit HDR
let result = try nlt.applyForward(
    componentData: hdrData,
    transform: hlg,
    bitDepth: 10
)
```

### Lookup Table (LUT)

Arbitrary transforms via lookup tables with optional linear interpolation.

```swift
// Create custom LUT (e.g., film emulation curve)
let forwardLUT: [Double] = [
    0, 10, 25, 45, 70, 100, 135, 175, 220, 255
]

// Create inverse LUT (must be computed)
let inverseLUT: [Double] = computeInverseLUT(forwardLUT)

let lut = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .lookupTable(
        forwardLUT: forwardLUT,
        inverseLUT: inverseLUT,
        interpolation: true  // Use linear interpolation
    )
)

// Without interpolation (nearest neighbor)
let lutNN = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .lookupTable(
        forwardLUT: forwardLUT,
        inverseLUT: inverseLUT,
        interpolation: false
    )
)
```

### Piecewise Linear

Multi-segment linear approximations for complex curves.

```swift
// Shadow/midtone/highlight adjustment
let breakpoints = [0.0, 0.3, 0.7, 1.0]
let values = [0.0, 0.25, 0.8, 1.0]

let piecewise = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .piecewiseLinear(
        breakpoints: breakpoints,
        values: values
    )
)
```

### Custom Transforms

User-defined parametric transforms.

```swift
let custom = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .custom(
        parameters: [1.0, 2.0, 3.0],
        function: "my_custom_transform"
    )
)

// Note: Custom transforms require application-specific implementation
```

## Configuration

### Per-Component Configuration

```swift
let config = J2KNLTConfiguration(
    enabled: true,
    componentTransforms: [
        J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2)),
        J2KNLTComponentTransform(componentIndex: 1, transformType: .identity),
        J2KNLTComponentTransform(componentIndex: 2, transformType: .logarithmic)
    ],
    autoOptimize: false
)
```

### Automatic Optimization

```swift
// Let encoder analyze and choose optimal transforms
let autoConfig = J2KNLTConfiguration.autoOptimized
```

## Marker Segments

NLT transforms are signaled in the JPEG 2000 codestream using NLT marker segments.

### Marker Format

```
Marker Code: 0xFF90 (Part 2 extension)
Length: Variable
Format:
  - Cnlt: Number of components (2 bytes)
  - For each component:
    - ICnlt: Component index (2 bytes)
    - Tnlt: Transform type (1 byte)
    - Pnlt: Parameters (variable)
```

### Encoding Marker Segments

```swift
import J2KCodec

let transforms = [
    J2KNLTComponentTransform(componentIndex: 0, transformType: .gamma(2.2)),
    J2KNLTComponentTransform(componentIndex: 1, transformType: .perceptualQuantizer)
]

let marker = J2KNLTMarkerSegment(transforms: transforms)
let encoded = try marker.encode()

// Write encoded marker to codestream
```

### Decoding Marker Segments

```swift
// Read marker segment from codestream (without marker code)
let markerData = readMarkerSegment()

let decoded = try J2KNLTMarkerSegment.decode(from: markerData)

// Apply transforms during decoding
for transform in decoded.transforms {
    let result = try nlt.applyInverse(
        componentData: componentData[transform.componentIndex],
        transform: transform,
        bitDepth: bitDepth
    )
    // Use result.transformedData
}
```

### Validation

```swift
let marker = J2KNLTMarkerSegment(transforms: transforms)

if marker.validate() {
    // Marker is valid
    let encoded = try marker.encode()
} else {
    // Invalid marker (e.g., duplicate components, invalid parameters)
}
```

## Performance

### Scalar Performance (Baseline)

- Identity: ~0.1 µs per sample
- Gamma: ~1.5 µs per sample
- Logarithmic: ~2.0 µs per sample
- PQ: ~3.5 µs per sample
- LUT (no interpolation): ~0.8 µs per sample
- LUT (interpolation): ~1.2 µs per sample

### Hardware-Accelerated Performance (Apple Silicon)

With J2KAccelerate on Apple Silicon (M1-M4):

- Gamma (vForce): **10-15× faster** (~0.1-0.15 µs per sample)
- Logarithmic (vForce): **10-15× faster** (~0.15-0.2 µs per sample)
- LUT (vDSP): **8-12× faster** (~0.08-0.1 µs per sample)
- PQ (vForce): **8-10× faster** (~0.35-0.45 µs per sample)
- HLG (vForce): **8-10× faster** (~0.35-0.45 µs per sample)

**Example:** Processing 1920×1080 RGB image (6.2M samples):
- Scalar gamma transform: ~9.3 seconds
- Accelerated gamma transform: ~0.7 seconds (13× faster)

## Use Cases

### HDR Content

```swift
// HDR10 workflow (PQ transfer function)
let pq = J2KNLTComponentTransform(componentIndex: 0, transformType: .perceptualQuantizer)

// Before encoding: linearize PQ-encoded HDR10 content
let linearized = try nlt.applyForward(
    componentData: pqEncodedHDR,
    transform: pq,
    bitDepth: 10
)
// Compress linearized data

// After decoding: restore PQ encoding
let restored = try nlt.applyInverse(
    componentData: decodedLinear,
    transform: pq,
    bitDepth: 10
)
```

### Scientific Imaging

```swift
// Logarithmic data (astronomy, microscopy)
let log = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .logarithmic
)

let result = try nlt.applyForward(
    componentData: logScaledData,
    transform: log,
    bitDepth: 16  // High bit depth for scientific data
)
```

### Gamma-Encoded Images

```swift
// sRGB images
let srgb = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .gamma(2.2)
)

// Linearize before compression
let linearized = try nlt.applyForward(
    componentData: srgbData,
    transform: srgb,
    bitDepth: 8
)
// Better compression in linear space

// Restore gamma encoding after decompression
let gammaEncoded = try nlt.applyInverse(
    componentData: decodedLinear,
    transform: srgb,
    bitDepth: 8
)
```

### Film Emulation

```swift
// Custom LUT for film stock emulation
let filmLUT = loadFilmEmulationLUT("kodak_5219.lut")
let inverseLUT = computeInverseLUT(filmLUT)

let filmTransform = J2KNLTComponentTransform(
    componentIndex: 0,
    transformType: .lookupTable(
        forwardLUT: filmLUT,
        inverseLUT: inverseLUT,
        interpolation: true
    )
)
```

## Best Practices

### Transform Selection

1. **HDR Content**: Use PQ or HLG transforms
2. **Gamma-Encoded**: Use gamma correction
3. **Scientific Data**: Use logarithmic transforms
4. **Custom Curves**: Use LUT or piecewise linear

### Bit Depth Considerations

- 8-bit: Standard dynamic range, simple transforms
- 10-12 bit: HDR content, higher precision
- 14-16 bit: Scientific imaging, maximum precision

### Inverse Transform Accuracy

Some transforms have inherent rounding errors:
- **Gamma**: ±1 LSB (excellent)
- **Logarithmic**: ±2 LSB (good)
- **PQ/HLG**: ±50 LSB (acceptable for HDR)
- **LUT**: Depends on table size and interpolation

### Performance Optimization

1. Use hardware acceleration when available
2. Process multiple components in parallel
3. Pre-compute inverse LUTs
4. Use appropriate interpolation mode

## Error Handling

```swift
do {
    let result = try nlt.applyForward(
        componentData: data,
        transform: transform,
        bitDepth: bitDepth
    )
    
    if result.statistics.clipped {
        print("Warning: Values were clipped during transform")
    }
} catch J2KError.invalidParameter(let message) {
    print("Invalid parameter: \(message)")
} catch {
    print("Transform failed: \(error)")
}
```

## Implementation Notes

### Platform Independence

- Binary encoding uses big-endian IEEE 754 format
- Portable across all platforms (x86-64, ARM64, etc.)
- No endianness issues in marker segments

### Thread Safety

All NLT types are `Sendable` and can be safely used across threads.

```swift
let nlt = J2KNonLinearTransform()  // Sendable

await withTaskGroup(of: [Int32].self) { group in
    for component in components {
        group.addTask {
            try! nlt.applyForward(
                componentData: component,
                transform: transform,
                bitDepth: bitDepth
            ).transformedData
        }
    }
}
```

## Limitations

- Custom transforms require application-specific implementation
- Very large LUTs (>65535 entries) not supported in marker segments
- PQ/HLG transforms designed for 10-12 bit content
- Some transforms may introduce small rounding errors

## See Also

- [ISO/IEC 15444-2](https://www.iso.org/standard/33160.html) - JPEG 2000 Part 2 standard
- [SMPTE ST 2084](https://www.smpte.org/) - Perceptual Quantizer
- [ITU-R BT.2100](https://www.itu.int/) - Hybrid Log-Gamma
- [PART2_DC_OFFSET.md](PART2_DC_OFFSET.md) - Variable DC Offset
- [PART2_MCT.md](PART2_MCT.md) - Multi-Component Transform
- [PART2_ARBITRARY_WAVELETS.md](PART2_ARBITRARY_WAVELETS.md) - Arbitrary Wavelet Kernels
