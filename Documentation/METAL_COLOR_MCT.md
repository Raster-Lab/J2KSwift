# Metal-Accelerated Color Transforms and MCT (METAL_COLOR_MCT)

## Overview

`J2KMetalColorTransform` and `J2KMetalMCT` provide GPU-accelerated color space transforms and multi-component transforms for JPEG 2000 encoding and decoding using Metal compute shaders. They support ICT/RCT color transforms, non-linear point transforms (PQ, HLG, gamma, logarithmic, exponential, LUT), and arbitrary N×N multi-component transforms with optimized 3×3 and 4×4 fast paths.

## Architecture

### Components

| Component | Type | Description |
|-----------|------|-------------|
| `J2KMetalColorTransform` | `actor` | Color transform interface with GPU/CPU backend selection |
| `J2KMetalColorTransformConfiguration` | `struct` | Color transform configuration (type, threshold) |
| `J2KMetalColorTransformResult` | `struct` | Color transform output (3 components + metadata) |
| `J2KMetalColorTransformStatistics` | `struct` | Performance statistics |
| `J2KMetalColorTransformType` | `enum` | Transform type selection (ICT, RCT) |
| `J2KMetalColorTransformBackend` | `enum` | Backend selection (GPU, CPU, auto) |
| `J2KMetalNLTType` | `enum` | Non-linear transform type |
| `J2KMetalMCT` | `actor` | MCT interface with GPU/CPU backend selection |
| `J2KMetalMCTConfiguration` | `struct` | MCT configuration (threshold, batch size) |
| `J2KMetalMCTResult` | `struct` | MCT output (N components + metadata) |
| `J2KMetalMCTStatistics` | `struct` | MCT performance statistics |
| `J2KMetalMCTBackend` | `enum` | Backend selection (GPU, CPU, auto) |

### Metal Compute Shaders

**Color Transform Shaders (4 kernels, existing)**:
- `j2k_ict_forward` / `j2k_ict_inverse` — ICT (RGB ↔ YCbCr, float)
- `j2k_rct_forward` / `j2k_rct_inverse` — RCT (RGB ↔ YUV, integer)

**MCT Shaders (4 kernels)**:
- `j2k_mct_matrix_multiply` — General N×N matrix-vector multiply
- `j2k_mct_matrix_multiply_3x3` — Optimized 3×3 unrolled fast path
- `j2k_mct_matrix_multiply_4x4` — Optimized 4×4 unrolled fast path
- `j2k_color_mct_fused` — Fused color transform + MCT in single pass

**Non-Linear Transform Shaders (4 kernels)**:
- `j2k_nlt_parametric` — Gamma, logarithmic, exponential transforms
- `j2k_nlt_lut` — LUT-based transform with linear interpolation
- `j2k_nlt_pq` — Perceptual Quantizer (SMPTE ST 2084) forward/inverse
- `j2k_nlt_hlg` — Hybrid Log-Gamma (ITU-R BT.2100) forward/inverse

### Data Flow

```
Color Transform:
  RGB Components → ICT/RCT → YCbCr/YUV Components

MCT:
  N Components → Matrix Multiply → N Transformed Components

Fused Color + MCT:
  N Components → Color Transform → MCT → N Output Components
  (single GPU pass, reduced memory bandwidth)

NLT:
  Input Signal → Non-Linear Transform → Output Signal
```

## Usage

### Color Transform (ICT)

```swift
let colorTransform = J2KMetalColorTransform(configuration: .lossy)

// Forward ICT: RGB → YCbCr
let result = try await colorTransform.forwardTransform(
    red: redChannel,
    green: greenChannel,
    blue: blueChannel
)
// result.component0 = Y, component1 = Cb, component2 = Cr

// Inverse ICT: YCbCr → RGB
let rgb = try await colorTransform.inverseTransform(
    component0: result.component0,
    component1: result.component1,
    component2: result.component2
)
```

### Color Transform (RCT)

```swift
let colorTransform = J2KMetalColorTransform(configuration: .lossless)

// Forward RCT: RGB → YUV (integer arithmetic)
let result = try await colorTransform.forwardTransform(
    red: redChannel,
    green: greenChannel,
    blue: blueChannel
)
```

### Non-Linear Transforms

```swift
let ct = J2KMetalColorTransform()

// Gamma correction
let gamma = try await ct.applyNLT(data: input, type: .gamma(2.2))

// PQ (HDR)
let pq = try await ct.applyNLT(data: input, type: .pq)

// HLG (HDR)
let hlg = try await ct.applyNLT(data: input, type: .hlg)

// LUT-based
let lut = try await ct.applyNLT(
    data: input,
    type: .lut(table: lookupTable, inputMin: 0.0, inputMax: 1.0)
)
```

### Multi-Component Transform

```swift
let mct = J2KMetalMCT()

// Forward MCT with ICT matrix
let result = try await mct.forwardTransform(
    components: [redData, greenData, blueData],
    matrix: J2KMetalMCT.ictForwardMatrix,
    componentCount: 3
)

// Inverse MCT
let inverse = try await mct.inverseTransform(
    components: result.components,
    matrix: J2KMetalMCT.ictInverseMatrix,
    componentCount: 3
)
```

### Fused Color + MCT

```swift
let mct = J2KMetalMCT()

// Single-pass fused operation (reduced memory bandwidth)
let result = try await mct.fusedColorMCTTransform(
    components: [redData, greenData, blueData],
    colorMatrix: J2KMetalMCT.ictForwardMatrix,
    mctMatrix: customMCTMatrix,
    componentCount: 3
)
```

### Batch Processing

```swift
let mct = J2KMetalMCT()

// Process multiple tiles with the same matrix
let results = try await mct.batchTransform(
    tiles: [tile1Components, tile2Components, tile3Components],
    matrix: transformMatrix,
    componentCount: 3
)
```

## Backend Selection

Both `J2KMetalColorTransform` and `J2KMetalMCT` support automatic GPU/CPU backend selection:

| Backend | Behavior |
|---------|----------|
| `.auto` | GPU if sample count ≥ threshold, CPU otherwise |
| `.gpu` | Force GPU (falls back to CPU if Metal unavailable) |
| `.cpu` | Force CPU execution |

Default thresholds:
- Color transform: 1024 samples
- MCT: 512 samples

## GPU Optimizations

### 3×3 Fast Path
Unrolled computation for 3-component images (RGB/YCbCr):
```metal
// No loop overhead — direct register computation
output[gid] = matrix[0] * c0 + matrix[1] * c1 + matrix[2] * c2;
```

### 4×4 Fast Path
Unrolled computation for 4-component images (RGBA/CMYK):
```metal
output[gid] = matrix[0] * c0 + matrix[1] * c1 + matrix[2] * c2 + matrix[3] * c3;
```

### Fused Operations
Combined color + MCT in a single GPU pass:
- Eliminates intermediate buffer writes
- Reduces memory bandwidth by ~50%
- Single kernel launch instead of two

### PQ and HLG
Hardware-accelerated HDR transfer functions:
- SMPTE ST 2084 Perceptual Quantizer for HDR10
- ITU-R BT.2100 Hybrid Log-Gamma for broadcast HDR
- Forward and inverse transforms supported

## Performance Statistics

Both actors track detailed performance metrics:

```swift
let stats = await mct.statistics()
print("Total operations: \(stats.totalOperations)")
print("GPU utilization: \(stats.gpuUtilization * 100)%")
print("Fast path usage: \(stats.fastPathUtilization * 100)%")
print("Samples/second: \(stats.samplesPerSecond)")
```

## Predefined Matrices

| Matrix | Usage |
|--------|-------|
| `J2KMetalMCT.ictForwardMatrix` | Standard ICT (RGB → YCbCr) |
| `J2KMetalMCT.ictInverseMatrix` | Standard ICT inverse (YCbCr → RGB) |
| `J2KMetalMCT.averaging3Matrix` | Simple decorrelation for 3 components |

## Matrix Utilities

```swift
let mct = J2KMetalMCT()

// Identity matrix
let identity = await mct.identityMatrix(n: 3)

// Matrix multiplication
let product = await mct.matrixMultiply(matrixA, matrixB, n: 3)

// Matrix transpose
let transposed = await mct.transposeMatrix(matrix, n: 3)
```

## Platform Support

| Platform | Color Transform | MCT | NLT |
|----------|----------------|-----|-----|
| macOS (Apple Silicon) | GPU + CPU | GPU + CPU | GPU + CPU |
| macOS (Intel) | GPU + CPU | GPU + CPU | GPU + CPU |
| iOS/iPadOS | GPU + CPU | GPU + CPU | GPU + CPU |
| Linux | CPU only | CPU only | CPU only |

## Performance Targets

- **Color transform**: 10-25× speedup vs CPU for large images on Apple Silicon
- **MCT 3×3**: Near-peak GPU throughput with unrolled fast path
- **MCT N×N**: Scales with component count and sample count
- **Fused operations**: ~50% bandwidth reduction vs sequential transforms
- **NLT**: Parallel per-sample computation, memory-bound

## Test Coverage

- **35 color transform tests**: ICT/RCT forward/inverse, NLT (gamma, log, exp, PQ, HLG, LUT), error handling, statistics
- **42 MCT tests**: 3×3/4×4/N×N transforms, identity/roundtrip, fused operations, batch processing, matrix utilities, error handling, statistics
- **160 total Metal tests** (36 device + 47 DWT + 35 color + 42 MCT)
