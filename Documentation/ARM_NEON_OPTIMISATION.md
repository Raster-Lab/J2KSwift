# ARM NEON Optimisation Guide

## Overview

J2KSwift includes ARM NEON SIMD-optimised implementations of performance-critical
JPEG 2000 operations. These optimisations target ARM64 platforms (Apple Silicon and
ARM64 Linux) and are cleanly isolated so they can be removed without affecting
other code.

## Architecture Isolation

All ARM NEON-specific code resides in dedicated `ARM/` directories:

```
Sources/
├── J2KCodec/
│   └── ARM/
│       └── J2KNeonEntropyCoding.swift    # NEON entropy coding
├── J2KAccelerate/
│   └── ARM/
│       └── J2KNeonTransforms.swift       # NEON wavelet & colour transforms
```

### Conditional Compilation

All NEON code is guarded with `#if arch(arm64)`:

```swift
#if arch(arm64)
// NEON-optimised path: processes 4 samples per instruction
let simdCount = length / 4
for i in 0..<simdCount {
    let vec = SIMD4<Float>(...)
    // SIMD operations
}
#else
// Scalar fallback
for i in 0..<length {
    // Scalar operations
}
#endif
```

### Removal Guide

To remove ARM NEON support entirely:

1. Delete `Sources/J2KCodec/ARM/` directory
2. Delete `Sources/J2KAccelerate/ARM/` directory
3. Optionally remove ARM-specific test files:
   - `Tests/J2KAccelerateTests/J2KNeonSIMDTests.swift`
   - `Tests/J2KAccelerateTests/J2KARM64PlatformTests.swift`
   - `Tests/J2KCodecTests/J2KNeonEntropyTests.swift`

No other code changes are required — all non-ARM code paths are self-contained.

## NEON-Optimised Operations

### Entropy Coding (`J2KNeonEntropyCoding.swift`)

Located in `Sources/J2KCodec/ARM/`, this file provides NEON-accelerated
Tier-1 coding operations:

| Type | Operation | Speedup (ARM64) |
|------|-----------|-----------------|
| `NeonContextFormation` | Batch context label computation | 2–4× |
| `NeonBitPlaneCoder` | Significance propagation pass | 2–4× |
| `NeonBitPlaneCoder` | Magnitude refinement extraction | 2–4× |
| `NeonBitPlaneCoder` | Significance state update | 2–4× |
| `NeonContextModelling` | Sign context computation | 2× |
| `NeonContextModelling` | Run-length detection | 2–4× |

#### Context Formation

The MQ-coder context label is computed by examining the 8 neighbours
(horizontal, vertical, diagonal) of each coefficient. NEON acceleration
processes 4 coefficients simultaneously:

```swift
let formation = NeonContextFormation()
let contexts = formation.batchContextLabels(
    significanceState: stateArray,
    width: codeBlockWidth,
    rowOffset: rowStart,
    length: rowLength
)
```

#### Bit-Plane Coding

The three coding passes (SPP, MRP, cleanup) are accelerated:

```swift
let coder = NeonBitPlaneCoder()

// Significance propagation candidates
let candidates = coder.significancePropagationCandidates(
    significanceState: state, width: width,
    rowOffset: offset, length: length
)

// Magnitude refinement bits
let bits = coder.magnitudeRefinementBits(
    coefficients: coeffs, significanceState: state, bitPlane: bp
)

// Update significance after coding
coder.updateSignificance(
    significanceState: &state, coefficients: coeffs, bitPlane: bp
)
```

### Wavelet Transforms (`J2KNeonTransforms.swift`)

Located in `Sources/J2KAccelerate/ARM/`, this file provides NEON-accelerated
wavelet lifting and colour transforms:

| Type | Operation | Speedup (ARM64) |
|------|-----------|-----------------|
| `NeonWaveletLifting` | Forward/inverse 5/3 lifting | 2–3× |
| `NeonWaveletLifting` | Forward/inverse 9/7 lifting | 2–3× |
| `NeonColourTransform` | Forward/inverse ICT (lossy) | 2–4× |
| `NeonColourTransform` | Forward/inverse RCT (lossless) | 2–4× |
| `NeonColourTransform` | Pixel format conversion | 2× |

#### 5/3 Wavelet (Lossless)

The Le Gall 5/3 filter uses integer arithmetic for perfect reconstruction:

```swift
let lifter = NeonWaveletLifting()
var data: [Float] = loadSignal()

// Forward transform
lifter.forward53(data: &data, length: data.count)

// Inverse transform
lifter.inverse53(data: &data, length: data.count)
```

#### 9/7 Wavelet (Lossy)

The CDF 9/7 filter uses floating-point lifting with SIMD acceleration:

```swift
lifter.forward97(data: &data, length: data.count)
lifter.inverse97(data: &data, length: data.count)
```

#### Colour Transforms

ICT (irreversible, lossy) and RCT (reversible, lossless):

```swift
let transform = NeonColourTransform()

// ICT: RGB → YCbCr (lossy)
transform.forwardICT(r: &r, g: &g, b: &b, count: pixelCount)
transform.inverseICT(y: &y, cb: &cb, cr: &cr, count: pixelCount)

// RCT: RGB → YUV (lossless)
transform.forwardRCT(r: &r, g: &g, b: &b, count: pixelCount)
transform.inverseRCT(y: &y, u: &u, v: &v, count: pixelCount)
```

## Platform Detection

Runtime capability detection is provided for both entropy and transform operations:

```swift
let entropyCap = NeonEntropyCodingCapability.detect()
print("NEON entropy: \(entropyCap.isAvailable), width: \(entropyCap.vectorWidth)")

let transformCap = NeonTransformCapability.detect()
print("NEON transform: \(transformCap.isAvailable), width: \(transformCap.vectorWidth)")
```

## Testing

### Test Files

- `Tests/J2KAccelerateTests/J2KNeonSIMDTests.swift` — 19 tests for wavelet and colour transforms
- `Tests/J2KCodecTests/J2KNeonEntropyTests.swift` — 22 tests for entropy coding operations
- `Tests/J2KAccelerateTests/J2KARM64PlatformTests.swift` — 14 tests for HT SIMD on ARM64

### Running Tests

```bash
# Run all NEON tests
swift test --filter "J2KNeonSIMDTests|J2KNeonEntropyTests|J2KARM64PlatformTests"

# Run transform tests only
swift test --filter "J2KNeonSIMDTests"

# Run entropy tests only
swift test --filter "J2KNeonEntropyTests"
```

### Cross-Platform Behaviour

On non-ARM64 platforms:
- All operations fall back to scalar implementations automatically
- Tests that require ARM64 use `#if arch(arm64)` or `throw XCTSkip()`
- Round-trip correctness tests pass on all platforms
- Performance assertions are skipped on non-ARM64

## Design Principles

1. **Platform-agnostic SIMD types**: Uses Swift's `SIMD4<Int32>` and `SIMD4<Float>`
   which map to NEON on ARM64 and SSE on x86_64 automatically.

2. **Scalar remainder handling**: All SIMD loops handle the non-multiple-of-4
   remainder with scalar fallback code.

3. **Boundary safety**: All neighbour-access patterns include bounds checking
   to prevent out-of-bounds memory access.

4. **Sendable conformance**: All types conform to `Sendable` for use with
   Swift 6.2 strict concurrency.

5. **No external dependencies**: Uses only Foundation and Swift standard library.
   No C interop or inline assembly required.
