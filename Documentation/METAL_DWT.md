# Metal-Accelerated Wavelet Transforms (METAL_DWT)

## Overview

`J2KMetalDWT` provides GPU-accelerated discrete wavelet transforms (DWT) for JPEG 2000 encoding and decoding using Metal compute shaders. It supports 1D/2D forward and inverse transforms with CDF 9/7 (lossy), Le Gall 5/3 (lossless), arbitrary convolution-based, and lifting scheme wavelet filters.

## Architecture

### Components

| Component | Type | Description |
|-----------|------|-------------|
| `J2KMetalDWT` | `actor` | Main DWT interface with GPU/CPU backend selection |
| `J2KMetalDWTConfiguration` | `struct` | DWT configuration (filter, levels, tiling, thresholds) |
| `J2KMetalDWTSubbands` | `struct` | Single-level 2D decomposition result (LL, LH, HL, HH) |
| `J2KMetalDWTDecomposition` | `struct` | Multi-level decomposition result |
| `J2KMetalDWTFilter` | `enum` | Wavelet filter selection |
| `J2KMetalDWTBackend` | `enum` | Backend selection (GPU, CPU, auto) |
| `J2KMetalDWTStatistics` | `struct` | Performance statistics |
| `J2KMetalArbitraryFilter` | `struct` | Custom filter coefficients |
| `J2KMetalLiftingScheme` | `struct` | Lifting scheme configuration |

### Metal Compute Shaders

**Standard DWT Shaders (16 kernels)**:
- `j2k_dwt_forward_97_horizontal` / `j2k_dwt_forward_97_vertical` — CDF 9/7 forward
- `j2k_dwt_inverse_97_horizontal` / `j2k_dwt_inverse_97_vertical` — CDF 9/7 inverse
- `j2k_dwt_forward_53_horizontal` / `j2k_dwt_forward_53_vertical` — Le Gall 5/3 forward
- `j2k_dwt_inverse_53_horizontal` / `j2k_dwt_inverse_53_vertical` — Le Gall 5/3 inverse

**Arbitrary Wavelet Shaders (8 kernels)**:
- `j2k_dwt_forward_arbitrary_horizontal` / `j2k_dwt_forward_arbitrary_vertical` — Generic convolution forward
- `j2k_dwt_inverse_arbitrary_horizontal` / `j2k_dwt_inverse_arbitrary_vertical` — Generic convolution inverse
- `j2k_dwt_forward_lifting_horizontal` / `j2k_dwt_forward_lifting_vertical` — Lifting scheme forward
- `j2k_dwt_inverse_lifting_horizontal` / `j2k_dwt_inverse_lifting_vertical` — Lifting scheme inverse

### Data Flow

```
Input Image → Horizontal DWT (rows) → Vertical DWT (columns) → Subbands (LL, LH, HL, HH)
```

For multi-level decomposition, the LL subband is recursively decomposed.

## Usage

### Basic 2D DWT

```swift
let dwt = J2KMetalDWT(configuration: .lossy)
try await dwt.initialize()

// Forward transform
let subbands = try await dwt.forward2D(
    data: imageData,
    width: 512,
    height: 512
)

// Access subbands
print("LL: \(subbands.ll.count) coefficients")
print("LH: \(subbands.lh.count) coefficients")

// Inverse transform
let reconstructed = try await dwt.inverse2D(subbands: subbands)
```

### Multi-Level Decomposition

```swift
let dwt = J2KMetalDWT(configuration: .init(
    filter: .irreversible97,
    decompositionLevels: 5
))

let decomposition = try await dwt.forwardMultiLevel(
    data: imageData,
    width: 2048,
    height: 2048
)

print("Levels: \(decomposition.levels.count)")
print("Final approximation: \(decomposition.approximationWidth)×\(decomposition.approximationHeight)")

// Reconstruct
let reconstructed = try await dwt.inverseMultiLevel(decomposition: decomposition)
```

### Tile-Based Processing

```swift
let dwt = J2KMetalDWT(configuration: .largeImage)

let tiles = try await dwt.forwardTiled(
    data: imageData,
    width: 4096,
    height: 4096,
    tileWidth: 1024,
    tileHeight: 1024
)

for tile in tiles {
    print("Tile at (\(tile.tileX), \(tile.tileY))")
    print("  LL size: \(tile.subbands.llWidth)×\(tile.subbands.llHeight)")
}
```

### Lossless Compression

```swift
let dwt = J2KMetalDWT(configuration: .lossless)

let subbands = try await dwt.forward2D(
    data: imageData,
    width: 256,
    height: 256
)
```

### Arbitrary Wavelet Filters

```swift
let customFilter = J2KMetalArbitraryFilter(
    analysisLowpass: [0.026749, -0.016864, -0.078223, 0.266864, 0.602949, 0.266864, -0.078223, -0.016864, 0.026749],
    analysisHighpass: [0.045636, -0.028772, -0.295636, 0.557543, -0.295636, -0.028772, 0.045636],
    synthesisLowpass: [0.045636, 0.028772, -0.295636, -0.557543, -0.295636, 0.028772, 0.045636],
    synthesisHighpass: [0.026749, 0.016864, -0.078223, -0.266864, 0.602949, -0.266864, -0.078223, 0.016864, 0.026749]
)

let dwt = J2KMetalDWT(configuration: .init(filter: .arbitrary(customFilter)))
```

### Lifting Scheme

```swift
// CDF 9/7 via lifting (equivalent to .irreversible97 but using lifting kernels)
let dwt = J2KMetalDWT(configuration: .init(filter: .lifting(.cdf97)))

// Custom lifting scheme
let customLifting = J2KMetalLiftingScheme(
    coefficients: [-1.586134342, -0.052980118, 0.882911075, 0.443506852],
    scaleLowpass: 1.230174105,
    scaleHighpass: 1.0 / 1.230174105
)
let dwt2 = J2KMetalDWT(configuration: .init(filter: .lifting(customLifting)))
```

### Backend Selection

```swift
let dwt = J2KMetalDWT(configuration: .init(gpuThreshold: 256))

// Automatic (GPU for large images, CPU for small)
let result1 = try await dwt.forward2D(data: data, width: 512, height: 512)

// Force CPU
let result2 = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .cpu)

// Force GPU
let result3 = try await dwt.forward2D(data: data, width: 512, height: 512, backend: .gpu)

// Check effective backend
let backend = await dwt.effectiveBackend(width: 64, height: 64, backend: .auto)
// Returns .cpu (below threshold)
```

### Performance Monitoring

```swift
let dwt = J2KMetalDWT()

// Run operations...
let stats = await dwt.statistics()
print("Total operations: \(stats.totalOperations)")
print("GPU operations: \(stats.gpuOperations)")
print("CPU operations: \(stats.cpuOperations)")
print("GPU utilization: \(stats.gpuUtilization * 100)%")
print("Processing time: \(stats.totalProcessingTime)s")
print("Peak GPU memory: \(stats.peakGPUMemory) bytes")

// Reset
await dwt.resetStatistics()
```

## Performance

### Target Performance

| Image Size | GPU vs CPU Speedup | Notes |
|------------|-------------------|-------|
| 256×256 | ~1× | GPU overhead dominates |
| 512×512 | 2-5× | GPU becomes beneficial |
| 1024×1024 | 5-10× | Strong GPU advantage |
| 2048×2048 | 8-15× | Optimal GPU utilization |
| 4096×4096 | 10-15× | Peak GPU performance |

### Apple Silicon Optimizations

- **16-wide SIMD**: Leverages Apple GPU SIMD width for parallel sample processing
- **Fast math mode**: Enabled for improved throughput in irreversible transforms
- **Unified memory**: Zero-copy CPU-GPU data transfer on Apple Silicon
- **Threadgroup memory**: Used for shared data access patterns within workgroups
- **Coalesced access**: Memory layout optimized for sequential GPU thread access

### Memory Management

- Buffer pooling via `J2KMetalBufferPool` reduces allocation overhead
- Size bucketing (power-of-2) enables efficient buffer reuse
- Peak GPU memory tracked in statistics for monitoring
- Tile-based processing reduces peak memory for large images

## Wavelet Filters

### CDF 9/7 (Irreversible)

The standard JPEG 2000 lossy filter implemented using the lifting scheme:
- 4 lifting steps with coefficients: α=-1.586134342, β=-0.052980118, γ=0.882911075, δ=0.443506852
- Scaling factor K=1.230174105
- Floating-point arithmetic (32-bit float on GPU)

### Le Gall 5/3 (Reversible)

The standard JPEG 2000 lossless filter:
- Predict step: d[n] = x[2n+1] - floor((x[2n] + x[2n+2]) / 2)
- Update step: s[n] = x[2n] + floor((d[n-1] + d[n] + 2) / 4)
- Integer arithmetic for perfect reconstruction

### Arbitrary Convolution

Generic convolution-based DWT supporting any analysis/synthesis filter pair:
- Configurable filter length and coefficients
- Symmetric boundary extension
- Optimized GPU dispatch for common filter sizes (3, 5, 7, 9 taps)

### Lifting Scheme

Configurable lifting-based DWT with:
- Variable number of lifting steps
- Configurable scaling factors
- In-place computation for reduced memory usage
- Predefined CDF 9/7 lifting preset

## Platform Support

| Platform | Metal Support | Fallback |
|----------|--------------|----------|
| macOS 13+ (Apple Silicon) | ✅ Full | CPU reference |
| macOS 13+ (Intel) | ✅ Limited | CPU reference |
| iOS 16+ | ✅ Full | CPU reference |
| tvOS 16+ | ✅ Full | CPU reference |
| visionOS 1+ | ✅ Full | CPU reference |
| Linux | ❌ | CPU reference |
| Windows | ❌ | CPU reference |

All platforms have a complete CPU reference implementation that is used when Metal is unavailable or when processing small images below the GPU threshold.

## Testing

The Metal DWT module includes 47+ tests covering:

- **Configuration**: Filter types, presets, custom configurations
- **Type validation**: Subbands, decompositions, statistics
- **Backend selection**: Auto, forced GPU/CPU, fallback behavior
- **1D DWT**: Forward/inverse with 9/7, 5/3, lifting filters
- **2D DWT**: Forward/inverse, non-square images
- **Multi-level**: Decomposition, reconstruction, level clamping
- **Tile processing**: Splitting, full-image tiles
- **Numerical accuracy**: Round-trip reconstruction, energy preservation
- **Error handling**: Invalid parameters, empty inputs
- **Statistics**: Operation tracking, reset

Run tests:
```bash
swift test --filter J2KMetalDWTTests
```
