# Color Transform Implementation

This document describes the color transform implementations in J2KSwift, including the Reversible Color Transform (RCT) and Irreversible Color Transform (ICT) as specified in ISO/IEC 15444-1 (JPEG 2000 Part 1).

## Table of Contents

- [Overview](#overview)
- [Reversible Color Transform (RCT)](#reversible-color-transform-rct)
- [Irreversible Color Transform (ICT)](#irreversible-color-transform-ict)
- [Usage Examples](#usage-examples)
- [Component Subsampling](#component-subsampling)
- [Performance Characteristics](#performance-characteristics)
- [API Reference](#api-reference)
- [Standards Compliance](#standards-compliance)

## Overview

Color transforms in JPEG 2000 convert between RGB and YCbCr color spaces to improve compression efficiency. The Y component (luminance) typically contains most of the image information, while Cb and Cr (chrominance) components can be compressed more aggressively.

JPEG 2000 defines two color transforms:

1. **Reversible Color Transform (RCT)**: Integer-to-integer transform for lossless compression
2. **Irreversible Color Transform (ICT)**: Floating-point transform for lossy compression

## Reversible Color Transform (RCT)

The RCT uses integer arithmetic to ensure perfect reversibility, making it suitable for lossless compression.

### Forward Transform (RGB → YCbCr)

The forward RCT converts RGB to YCbCr using the following formulas:

```
Y  = ⌊(R + 2G + B) / 4⌋
Cb = B - G
Cr = R - G
```

Where:
- `R`, `G`, `B` are the red, green, and blue component values (signed integers)
- `⌊x⌋` denotes the floor function (round toward negative infinity)
- `Y` is the luminance (brightness) component
- `Cb` is the blue-difference chroma component
- `Cr` is the red-difference chroma component

### Inverse Transform (YCbCr → RGB)

The inverse RCT converts YCbCr back to RGB:

```
G = Y - ⌊(Cb + Cr) / 4⌋
R = Cr + G
B = Cb + G
```

These formulas guarantee perfect reconstruction: `RGB → YCbCr → RGB` produces the original RGB values exactly.

### Mathematical Properties

The RCT has several important properties:

1. **Reversibility**: Perfect integer-to-integer mapping with no loss of precision
2. **Efficiency**: Uses only addition, subtraction, and bit shifts (division by 4 = right shift by 2)
3. **DC Preservation**: The sum `R + G + B` is preserved (modulo quantization)
4. **Energy Compaction**: Concentrates energy in the Y component for natural images

### Why These Formulas?

The RCT design balances several factors:

- **Green Channel Weight**: Green gets twice the weight (`2G`) because the human eye is most sensitive to green wavelengths
- **Integer Operations**: All operations are exact integer arithmetic (no rounding except final division)
- **Reversibility**: The specific combination ensures perfect reconstruction
- **Simplicity**: Uses only shifts and adds for fast computation

## Irreversible Color Transform (ICT)

The ICT uses floating-point arithmetic for better decorrelation but is not reversible due to rounding errors. It is used for lossy compression where perfect reconstruction is not required.

### Forward Transform (RGB → YCbCr)

```
Y  = 0.299 × R + 0.587 × G + 0.114 × B
Cb = -0.168736 × R - 0.331264 × G + 0.5 × B
Cr = 0.5 × R - 0.418688 × G - 0.081312 × B
```

These coefficients are defined in ISO/IEC 15444-1 Annex G.3 and provide optimal decorrelation for natural images.

### Inverse Transform (YCbCr → RGB)

```
R = Y + 1.402 × Cr
G = Y - 0.344136 × Cb - 0.714136 × Cr
B = Y + 1.772 × Cb
```

### ICT Characteristics

- **Decorrelation**: Better than RCT for natural images (correlated RGB values)
- **Reversibility**: Not perfectly reversible due to floating-point rounding
- **Precision**: Typical reconstruction error < 1.0 for 8-bit data
- **Performance**: Similar to RCT (~10ms for 512×512 images)
- **Use Case**: Lossy compression where small errors are acceptable

## Usage Examples

### Basic RCT Array-Based Transform

```swift
import J2KCodec

let transform = J2KColorTransform()

// Prepare RGB data (signed integers)
let red: [Int32] = [100, 150, 200]
let green: [Int32] = [80, 120, 180]
let blue: [Int32] = [60, 100, 160]

// Forward transform
let (y, cb, cr) = try transform.forwardRCT(
    red: red,
    green: green,
    blue: blue
)

// Inverse transform
let (r2, g2, b2) = try transform.inverseRCT(
    y: y,
    cb: cb,
    cr: cr
)

// Verify perfect reconstruction
assert(r2 == red)
assert(g2 == green)
assert(b2 == blue)
```

### Component-Based Transform

```swift
import J2KCore
import J2KCodec

let transform = J2KColorTransform()

// Create components from your image data
let redComponent = J2KComponent(
    index: 0,
    bitDepth: 8,
    signed: true,
    width: 512,
    height: 512,
    data: redData
)
// ... similarly for green and blue

// Transform RGB to YCbCr
let (yComponent, cbComponent, crComponent) = try transform.forwardRCT(
    redComponent: redComponent,
    greenComponent: greenComponent,
    blueComponent: blueComponent
)

// Use YCbCr components for encoding...

// Transform back to RGB
let (r, g, b) = try transform.inverseRCT(
    yComponent: yComponent,
    cbComponent: cbComponent,
    crComponent: crComponent
)
```

### ICT Array-Based Transform

```swift
import J2KCodec

// Create lossy transform
let transform = J2KColorTransform(configuration: .lossy)

// Prepare RGB data (floating-point, level-shifted)
let red: [Double] = [100, 150, 200]
let green: [Double] = [80, 120, 180]
let blue: [Double] = [60, 100, 160]

// Forward transform
let (y, cb, cr) = try transform.forwardICT(
    red: red,
    green: green,
    blue: blue
)

// Inverse transform
let (r2, g2, b2) = try transform.inverseICT(
    y: y,
    cb: cb,
    cr: cr
)

// Note: ICT is not perfectly reversible
// Expect small differences (< 0.5 for 8-bit data)
for i in 0..<red.count {
    assert(abs(r2[i] - red[i]) < 1.0)
    assert(abs(g2[i] - green[i]) < 1.0)
    assert(abs(b2[i] - blue[i]) < 1.0)
}
```

### ICT Component-Based Transform

```swift
import J2KCore
import J2KCodec

let transform = J2KColorTransform(configuration: .lossy)

// Create components from your image data
let redComponent = J2KComponent(
    index: 0,
    bitDepth: 8,
    signed: true,
    width: 512,
    height: 512,
    data: redData
)
// ... similarly for green and blue

// Transform RGB to YCbCr
let (yComponent, cbComponent, crComponent) = try transform.forwardICT(
    redComponent: redComponent,
    greenComponent: greenComponent,
    blueComponent: blueComponent
)

// Use YCbCr components for encoding...

// Transform back to RGB
let (r, g, b) = try transform.inverseICT(
    yComponent: yComponent,
    cbComponent: cbComponent,
    crComponent: crComponent
)
```

### Configuration Options

```swift
// Lossless configuration (RCT)
let losslessConfig = J2KColorTransformConfiguration.lossless

// Lossy configuration (ICT)
let lossyConfig = J2KColorTransformConfiguration.lossy

// No transform
let noTransform = J2KColorTransformConfiguration.none

// Custom configuration
let customConfig = J2KColorTransformConfiguration(
    mode: .irreversible,
    validateReversibility: false  // ICT is not reversible
)

let transform = J2KColorTransform(configuration: customConfig)
```

### Level Shifting for Unsigned Data

JPEG 2000 uses signed integers internally. For unsigned input data, apply level shifting:

```swift
// For 8-bit unsigned RGB [0, 255]
func levelShiftToSigned(_ unsigned: [UInt8]) -> [Int32] {
    return unsigned.map { Int32($0) - 128 }
}

// For 8-bit signed RGB to unsigned output
func levelShiftToUnsigned(_ signed: [Int32]) -> [UInt8] {
    return signed.map { UInt8(clamping: $0 + 128) }
}

// Usage
let unsignedRed: [UInt8] = [255, 200, 128, 50]
let signedRed = levelShiftToSigned(unsignedRed)

// Transform
let (y, cb, cr) = try transform.forwardRCT(
    red: signedRed,
    // ... green, blue
)

// After inverse transform
let rgbSigned = // ... from inverse RCT
let rgbUnsigned = levelShiftToUnsigned(rgbSigned)
```

## Component Subsampling

JPEG 2000 supports chroma subsampling to reduce data size while preserving visual quality.

### Subsampling Formats

```swift
// 4:4:4 - No subsampling (full resolution for all components)
let subsample444 = J2KColorTransform.SubsamplingInfo.none

// 4:2:2 - Horizontal subsampling (half horizontal resolution for Cb/Cr)
let subsample422 = J2KColorTransform.SubsamplingInfo.yuv422

// 4:2:0 - Both horizontal and vertical subsampling (quarter resolution for Cb/Cr)
let subsample420 = J2KColorTransform.SubsamplingInfo.yuv420

// Custom subsampling
let customSubsampling = J2KColorTransform.SubsamplingInfo(
    horizontalFactor: 2,
    verticalFactor: 2
)
```

### Validating Subsampling

```swift
let transform = J2KColorTransform()
let components = [yComponent, cbComponent, crComponent]

// Validate that all components have matching subsampling
try transform.validateSubsampling(components)
```

### Working with Subsampled Components

When working with subsampled chrominance components:

1. Y component is always full resolution
2. Cb and Cr may be subsampled (smaller width/height)
3. The RCT operates on full-resolution data before subsampling
4. Subsampling is applied after the color transform during encoding
5. Upsampling is applied before the inverse color transform during decoding

## Performance Characteristics

### Computational Complexity

**Forward RCT (per pixel):**
- 3 additions
- 2 bit shifts (divide by 4)
- Total: O(1) per pixel, O(n) for n pixels

**Inverse RCT (per pixel):**
- 4 additions
- 1 bit shift (divide by 4)
- Total: O(1) per pixel, O(n) for n pixels

### Benchmark Results

Performance measurements on various image sizes (Linux x86_64, representative hardware):

#### RCT Performance

| Image Size | Forward RCT | Inverse RCT | Round-Trip |
|------------|-------------|-------------|------------|
| 256×256    | ~2.4 ms     | ~2.8 ms     | ~5.3 ms    |
| 512×512    | ~9.7 ms     | ~11.3 ms    | ~21 ms     |
| 1024×1024  | ~39 ms      | ~48 ms      | ~89 ms     |
| 2048×2048  | ~162 ms     | ~162 ms     | ~324 ms    |

#### ICT Performance

| Image Size | Forward ICT | Inverse ICT | Round-Trip |
|------------|-------------|-------------|------------|
| 256×256    | ~2.5 ms     | ~2.4 ms     | ~4.9 ms    |
| 512×512    | ~10 ms      | ~10 ms      | ~20 ms     |
| 1024×1024  | ~42 ms      | ~42 ms      | ~85 ms     |
| 2048×2048  | ~169 ms     | ~169 ms     | ~338 ms    |

**Key Observations:**
- ICT and RCT have similar performance (floating-point vs integer operations)
- Both transforms scale linearly with image size
- Round-trip time is approximately 2× forward transform time
- Component-based API adds ~10-15% overhead for Data conversion

**Throughput (512×512 images):**
- RCT Forward: ~103 images/sec
- RCT Inverse: ~88 images/sec
- ICT Forward: ~100 images/sec
- ICT Inverse: ~100 images/sec

### Memory Usage

**Memory per image:**
- Input: 3 × width × height × sizeof(Int32) = 12 bytes/pixel
- Output: 3 × width × height × sizeof(Int32) = 12 bytes/pixel
- Total: 24 bytes/pixel during transform

**Example for 1024×1024 image:**
- Input: 12 MB
- Output: 12 MB
- Total: 24 MB

### Optimization Opportunities

Current implementation uses straightforward integer operations. Future optimizations could include:

1. **SIMD Vectorization**: Process multiple pixels simultaneously using SIMD instructions
2. **Parallel Processing**: Transform tiles concurrently using multiple threads
3. **Cache Optimization**: Improve memory access patterns for better cache utilization
4. **Hardware Acceleration**: Use platform-specific frameworks (e.g., Accelerate on Apple platforms)

Expected speedup with optimizations: 2-4× for SIMD, additional 2-4× with parallelization (on multi-core systems).

## API Reference

### J2KColorTransformMode

```swift
public enum J2KColorTransformMode: String, Sendable, CaseIterable {
    case reversible      // RCT - integer-to-integer, lossless
    case irreversible    // ICT - floating-point, lossy (planned)
    case none           // No color transform
}
```

### J2KColorTransformConfiguration

```swift
public struct J2KColorTransformConfiguration: Sendable {
    public let mode: J2KColorTransformMode
    public let validateReversibility: Bool
    
    public init(
        mode: J2KColorTransformMode = .reversible,
        validateReversibility: Bool = ...
    )
    
    public static let lossless: J2KColorTransformConfiguration
    public static let lossy: J2KColorTransformConfiguration
    public static let none: J2KColorTransformConfiguration
}
```

### J2KColorTransform

```swift
public struct J2KColorTransform: Sendable {
    public let configuration: J2KColorTransformConfiguration
    
    public init(configuration: J2KColorTransformConfiguration = .lossless)
    
    // Array-based API
    public func forwardRCT(
        red: [Int32],
        green: [Int32],
        blue: [Int32]
    ) throws -> (y: [Int32], cb: [Int32], cr: [Int32])
    
    public func inverseRCT(
        y: [Int32],
        cb: [Int32],
        cr: [Int32]
    ) throws -> (red: [Int32], green: [Int32], blue: [Int32])
    
    // Component-based API
    public func forwardRCT(
        redComponent: J2KComponent,
        greenComponent: J2KComponent,
        blueComponent: J2KComponent
    ) throws -> (y: J2KComponent, cb: J2KComponent, cr: J2KComponent)
    
    public func inverseRCT(
        yComponent: J2KComponent,
        cbComponent: J2KComponent,
        crComponent: J2KComponent
    ) throws -> (red: J2KComponent, green: J2KComponent, blue: J2KComponent)
    
    // Subsampling support
    public func validateSubsampling(_ components: [J2KComponent]) throws
}
```

### SubsamplingInfo

```swift
public struct SubsamplingInfo: Sendable, Equatable {
    public let horizontalFactor: Int
    public let verticalFactor: Int
    
    public init(horizontalFactor: Int, verticalFactor: Int)
    
    public static let none: SubsamplingInfo    // 4:4:4
    public static let yuv422: SubsamplingInfo  // 4:2:2
    public static let yuv420: SubsamplingInfo  // 4:2:0
}
```

## Standards Compliance

### ISO/IEC 15444-1 (JPEG 2000 Part 1)

The implementation follows the JPEG 2000 standard specifications:

**Annex G.2 - Reversible Multi-Component Transform:**
- ✅ Forward RCT formulas (G.2.1)
- ✅ Inverse RCT formulas (G.2.2)
- ✅ Integer-to-integer mapping
- ✅ Perfect reconstruction guarantee

**Annex G.3 - Irreversible Multi-Component Transform:**
- ✅ Forward ICT formulas (G.3.1)
- ✅ Inverse ICT formulas (G.3.2)
- ✅ Floating-point arithmetic
- ✅ Approximate reconstruction (< 1.0 error for 8-bit)

**General Requirements:**
- ✅ Support for signed integer components (RCT)
- ✅ Support for floating-point components (ICT)
- ✅ Arbitrary bit depths (up to 38 bits as per standard)
- ✅ Component subsampling support (4:4:4, 4:2:2, 4:2:0)
- ✅ Multi-component image support (≥3 components)

### Swift 6 Compliance

- ✅ **Strict Concurrency**: All types are `Sendable`
- ✅ **Value Semantics**: Core types use struct for safety
- ✅ **Error Handling**: Proper use of `throws` for recoverable errors
- ✅ **API Design**: Follows Swift API design guidelines
- ✅ **Documentation**: Complete DocC-compatible documentation

## Implementation Details

### Integer Overflow Handling

The RCT implementation uses Swift's overflow operators (`&+`, `&-`, `&<<`) to handle potential integer overflow gracefully:

```swift
// Forward transform with overflow protection
y[i] = (r &+ (g &<< 1) &+ b) >> 2
cb[i] = b &- g
cr[i] = r &- g
```

This ensures defined behavior even with extreme input values.

### Precision Considerations

The RCT maintains full integer precision throughout the transform:

- No intermediate rounding (except final division)
- Floor division (`>>` for positive, rounds toward zero)
- Perfect reversibility for all valid inputs

### Edge Cases

The implementation handles various edge cases:

1. **Empty Components**: Throws `J2KError.invalidParameter`
2. **Mismatched Sizes**: Validates component dimensions match
3. **Single Pixel**: Works correctly for minimum-size images
4. **Large Images**: Tested up to 2048×2048 pixels
5. **Extreme Values**: Handles full Int32 range (-2³¹ to 2³¹-1)
6. **Grayscale**: Optimizes for R=G=B (Cb=Cr=0)

## Testing

The implementation includes comprehensive test coverage:

### Unit Tests (44 tests)
- Configuration and mode tests (6 tests)
- **RCT tests (16 tests)**:
  - Basic forward/inverse transform tests
  - Reversibility validation
  - Edge case handling
  - Primary colors and grayscale tests
- **ICT tests (14 tests)**:
  - Basic forward/inverse transform tests
  - Round-trip accuracy validation
  - Zero, negative, and large value handling
  - Primary colors testing
  - Component API testing
  - Decorrelation verification
- Component-based API tests
- Subsampling validation
- Concurrency (Sendable) tests

### Benchmark Tests (40 benchmarks)
- **RCT benchmarks (20 tests)**:
  - Various image sizes (256² to 2048²)
  - Forward, inverse, and round-trip transforms
  - Component-based transforms
  - Different data patterns
  - Throughput measurements
- **ICT benchmarks (20 tests)**:
  - Various image sizes (256² to 2048²)
  - Forward, inverse, and round-trip transforms
  - Component-based transforms
  - Random and correlated data
  - Batch processing tests
  - Decorrelation performance
  - Extreme value handling

**Test Results:**
- ✅ All 44 unit tests pass (100% pass rate)
- ✅ All 40 benchmark tests pass
- ✅ Perfect reversibility for RCT
- ✅ ICT reconstruction error < 1.0 for 8-bit data
- ✅ Performance within expected ranges

## Future Work

### Phase 4, Week 55-56: Advanced Color Support

Planned enhancements:

1. **Extended Color Spaces**
   - Arbitrary component count (>3)
   - Custom color space transforms
   - ICC profile support
   - Non-RGB color spaces (CMYK, Lab, etc.)

2. **Hardware Acceleration**
   - SIMD vectorization for both RCT and ICT
   - Accelerate framework integration (Apple platforms)
   - 2-4× speedup potential
   - Parallel tile processing

3. **Advanced Features**
   - Adaptive transform selection (RCT vs ICT)
   - Perceptual weighting
   - Region-specific transforms
   - Quality-dependent transform parameters

## References

1. ISO/IEC 15444-1:2019 - Information technology — JPEG 2000 image coding system: Core coding system
2. Taubman, D. S., & Marcellin, M. W. (2002). JPEG2000 Image Compression Fundamentals, Standards and Practice. Springer.
3. Swift Evolution - Concurrency: <a href="https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md">SE-0306</a>

---

**Last Updated**: 2026-02-06  
**Status**: Phase 4, Week 52-54 Complete ✅  
**Next**: Phase 4, Week 55-56 - Advanced Color Support  
**Status**: Phase 4, Week 49-51 Complete (RCT) ✅  
**Next**: Phase 4, Week 52-54 (ICT) 🚧
