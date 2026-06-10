# Lossless Decoding Optimization Guide

## Overview

J2KSwift v1.1.1 includes significant optimizations for lossless decoding using the reversible 5/3 wavelet filter. These optimizations provide substantial performance improvements while maintaining perfect reconstruction accuracy.

> **Historical note**: the `J2KBufferPool` actor originally described in this guide was Removed in v11.0.0 (dead code; see RELEASE_NOTES_v11.0.0.md). The live decoder hoists per-chunk scratch buffers outside its hot loops instead, and GPU paths reuse buffers through `J2KMetalBufferPool`. The DWT optimisation techniques below remain accurate.

## Performance Improvements

### Benchmark Results (Swift 6, x86_64-linux)

#### 1D Inverse Wavelet Transform

| Size  | Standard (ms) | Optimized (ms) | Speedup |
|-------|---------------|----------------|---------|
| 64    | 0.010         | 0.007          | 1.54x   |
| 128   | 0.019         | 0.010          | 1.87x   |
| 256   | 0.038         | 0.020          | 1.90x   |
| 512   | 0.075         | 0.039          | 1.91x   |
| 1024  | 0.149         | 0.079          | 1.87x   |
| 2048  | 0.296         | 0.163          | 1.82x   |

**Average speedup: 1.85x**

#### 2D Inverse Wavelet Transform

| Size    | Standard (ms) | Optimized (ms) | Speedup |
|---------|---------------|----------------|---------|
| 16×16   | 0.085         | 0.061          | 1.38x   |
| 32×32   | 0.271         | 0.199          | 1.37x   |
| 64×64   | 0.942         | 0.682          | 1.38x   |
| 128×128 | 3.471         | 2.493          | 1.39x   |
| 256×256 | 13.256        | 9.436          | 1.40x   |

**Average speedup: 1.39x**

#### Multi-level Decomposition

| Levels | Size | Standard (ms) | Optimized (ms) | Speedup |
|--------|------|---------------|----------------|---------|
| 1      | 128  | 3.383         | 2.402          | 1.41x   |
| 2      | 64   | 3.378         | 2.419          | 1.40x   |
| 3      | 32   | 3.389         | 2.395          | 1.42x   |
| 4      | 16   | 3.392         | 2.408          | 1.41x   |
| 5      | 8    | 3.399         | 2.414          | 1.41x   |

**Average speedup: 1.41x**

## Implementation Details

### Architecture

The optimization consists of three main components:

1. **Hoisted scratch buffers**: temporary arrays are allocated once per decode chunk and reused across rows/columns, reducing memory allocations. (The original `J2KBufferPool` actor was Removed in v11.0.0.)

2. **Optimized 1D DWT (`J2KDWT1DOptimizer`)**: Specialized implementation of the reversible 5/3 inverse wavelet transform with:
   - Pre-computed boundary extension values for symmetric mode
   - Reduced branching in hot paths
   - Better memory access patterns
   - Compiler optimization hints

3. **Optimized 2D DWT (`J2KDWT2DOptimizer`)**: Uses the optimized 1D transforms for both row and column processing.

### Automatic Detection

The decoder pipeline automatically detects when lossless mode is used and switches to the optimized path:

```swift
// In J2KDecoderPipeline.swift
if case .reversible53 = filter {
    // Use optimized path for lossless
    let optimizer = J2KDWT2DOptimizer()
    currentLL = try optimizer.inverseTransform2DOptimized(...)
} else {
    // Use standard path for lossy
    currentLL = try J2KDWT2D.inverseTransform(...)
}
```

### Key Optimizations

#### 1. Boundary Extension Caching

The standard implementation computes boundary extensions on-demand. The optimized version pre-computes these values for symmetric boundary extension (the most common mode):

```swift
// Pre-compute boundary-extended values
let highLeft = highpass.first ?? 0
let highRight = highpass.last ?? 0
```

#### 2. Reduced Branching

Instead of checking boundary conditions for every sample, the optimized version:
- Handles the main body of the signal without branches
- Handles boundary cases separately at the start and end

#### 3. Integer Arithmetic

All operations use integer arithmetic with bit shifts for division:
```swift
even[i] = lowpass[i] - ((left + right + 2) >> 2)  // Division by 4
odd[i] = highpass[i] + ((left + right) >> 1)      // Division by 2
```

#### 4. Buffer Reuse

Temporary buffers are reused rather than re-allocated in the hot paths:
- CPU transforms hoist per-chunk scratch buffers outside the row/column loops
- GPU dispatches reuse `MTLBuffer`s via `J2KMetalBufferPool`
- Thread-safe via Swift concurrency

## Usage

### Automatic (Recommended)

The optimizations are automatically applied when decoding lossless JPEG 2000 images. No code changes required:

```swift
let decoder = J2KDecoder()
let image = try decoder.decode(jp2Data)  // Automatically uses optimization
```

### Manual (Advanced)

You can directly use the optimized transforms:

```swift
let optimizer = J2KDWT1DOptimizer()
let result = try optimizer.inverseTransform53Optimized(
    lowpass: lowpass,
    highpass: highpass,
    boundaryExtension: .symmetric
)
```

Or for 2D:

```swift
let optimizer2D = J2KDWT2DOptimizer()
let reconstructed = try optimizer2D.inverseTransform2DOptimized(
    ll: ll, lh: lh, hl: hl, hh: hh,
    boundaryExtension: .symmetric
)
```

### Buffer Reuse

Buffer reuse is internal to the codec — there is no public pool API. CPU transforms hoist their scratch buffers per chunk, and the GPU paths manage `MTLBuffer` reuse through `J2KMetalBufferPool` automatically. (The public `J2KBufferPool` API shown in earlier revisions of this guide was Removed in v11.0.0.)

## Testing

The optimization includes comprehensive tests:

```bash
# Run optimization tests
swift test --filter J2KLosslessDecodingOptimizationTests
```

(The separate `J2KLosslessDecodingBenchmark` suite was Removed in v11.0.0.)

### Test Coverage

- 1D transform correctness (edge cases, large signals, boundary modes)
- 2D transform correctness (various sizes, reconstruction accuracy)
- Performance benchmarks (1D, 2D, multi-level)
- Integration with decoder pipeline

**Total: 14 tests, 100% pass rate**

## Compatibility

### Platforms

The optimization works on all platforms supported by Swift 6:
- macOS (x86_64, ARM64)
- Linux (x86_64, ARM64)
- Windows (x86_64)

### Swift Concurrency

The buffer pool uses Swift's actor model for thread safety. No additional synchronization is required.

### Backward Compatibility

The optimization is fully backward compatible:
- Existing code continues to work without modification
- The standard implementation remains available
- Results are bit-identical to the standard implementation

## Performance Tips

1. **Reuse Decoder Instances**: The decoder automatically reuses internal scratch buffers across decode operations.

2. **Batch Processing**: Process multiple images in sequence to maximize buffer reuse (and, on GPU paths, `J2KMetalBufferPool` hits).

3. **Lossy vs Lossless**: The optimization only applies to lossless (5/3 filter). For lossy encoding, use the 9/7 filter as usual.

## Future Work

Potential future enhancements:

1. **SIMD Vectorization**: Use explicit SIMD instructions for further speedup
2. **Multi-threading**: Parallelize independent transform operations
3. **Lossy Optimization**: Extend optimizations to the 9/7 irreversible filter
4. **Platform-specific**: Platform-specific optimizations (AVX, NEON)

## References

- ISO/IEC 15444-1 (JPEG 2000 Part 1)
- `J2KDWT1DOptimized.swift` - Optimized DWT implementation
- (`J2KBufferPool.swift` and `J2KLosslessDecodingBenchmark.swift` were Removed in v11.0.0)

## Changelog

### v1.1.1 (February 2026)
- Initial implementation of lossless decoding optimization
- 1.85x speedup for 1D transforms
- 1.40x speedup for 2D transforms
- Buffer pool for memory reuse
- Comprehensive test suite and benchmarks
