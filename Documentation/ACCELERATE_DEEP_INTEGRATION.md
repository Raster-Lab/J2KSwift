# Accelerate Framework Deep Integration

## Overview

Week 244-246 adds deep integration with Apple's Accelerate framework for maximum CPU performance in JPEG 2000 encoding and decoding. This builds on the existing Accelerate support with enhanced vDSP, vImage, and BLAS/LAPACK capabilities plus memory optimisation utilities.

## Components

### J2KvDSPDeepIntegration

Vectorised quantisation and frequency-domain operations using vDSP.

#### Vectorised Quantisation

```swift
let vdsp = J2KvDSPDeepIntegration()

// Quantise wavelet coefficients (5-20× faster than scalar)
let quantised = try vdsp.quantise(coefficients: data, stepSize: 0.5)

// Dequantise
let dequantised = try vdsp.dequantise(quantised: quantised, stepSize: 0.5)

// Dead-zone quantisation (JPEG 2000 standard)
let dzQuantised = try vdsp.deadZoneQuantise(coefficients: data, stepSize: 0.5)
```

#### DFT for Non-Power-of-2 Lengths

```swift
// DFT works with any length (unlike FFT which requires power-of-2)
let spectrum = try vdsp.dft(signal: [1.0, 2.0, 3.0, 4.0, 5.0])
let reconstructed = try vdsp.idft(spectrum: spectrum)
```

#### In-Place Operations

```swift
// Minimise memory allocation with in-place operations
var data = [1.0, 2.0, 3.0, 4.0]
vdsp.scalarMultiplyInPlace(&data, scalar: 2.5)
try vdsp.scalarDivideInPlace(&data, scalar: 5.0)
try vdsp.vectorAddInPlace(&data, addend: [10.0, 20.0, 30.0, 40.0])
```

#### Wavelet Filter Convolution

```swift
// Optimised convolution for arbitrary wavelet filters
let filtered = try vdsp.waveletConvolve(
    signal: data,
    kernel: [0.5, 1.0, 0.5],
    mode: .same  // Output same length as input
)
```

### J2KvImageDeepIntegration

16-bit pixel format conversion and tiled processing for large images.

#### 16-Bit Format Conversion

```swift
let vimage = J2KvImageDeepIntegration()

// 16-bit to normalised float
let floats = try vimage.convert16BitToFloat(
    data: pixelData, width: 256, height: 256
)

// Float back to 16-bit
let pixels = try vimage.convertFloatTo16Bit(
    data: floats, width: 256, height: 256
)
```

#### Tiled Processing

```swift
// Split large image into tiles for memory-efficient processing
let tiles = try vimage.splitIntoTiles(
    data: imageData, width: 4096, height: 4096, tileSize: 512
)

// Process each tile independently...

// Reassemble tiles
let result = try vimage.assembleTiles(
    tiles: processedTiles, width: 4096, height: 4096
)
```

#### 16-Bit Image Scaling

```swift
let scaled = try vimage.scale16Bit(
    data: pixels16,
    fromSize: (width: 1920, height: 1080),
    toSize: (width: 960, height: 540)
)
```

### J2KBLASDeepIntegration

Eigenvalue decomposition and batch matrix operations.

#### Eigenvalue Decomposition (KLT)

```swift
let blas = J2KBLASDeepIntegration()

// Compute covariance matrix from image components
let cov = try blas.covarianceMatrix(components: [redData, greenData, blueData])

// Eigenvalue decomposition for optimal transform
let (eigenvalues, eigenvectors) = try blas.eigenDecomposition(
    matrix: cov, n: 3
)
```

#### Batch Matrix Operations

```swift
// Process multiple tiles with the same transform
let results = try blas.batchMatrixMultiply(
    matrices: tileData,
    transform: kltMatrix,
    m: 3, n: 3, k: 3
)
```

### J2KMemoryOptimisation

Cache-aligned allocation and copy-on-write buffer management.

#### Cache-Aligned Allocation

```swift
let mem = J2KMemoryOptimisation()

// 128-byte aligned for M-series cache lines
let buffer = try mem.allocateAligned(count: 1024, alignment: 128)
```

#### Copy-on-Write Buffer

```swift
var buffer = J2KCOWBuffer(data: [1.0, 2.0, 3.0])
var copy = buffer          // No copy, shared storage
copy.modify { $0[0] = 99.0 } // Copy-on-write triggers here
// buffer[0] is still 1.0
```

## Performance Characteristics

| Operation | Speedup vs Scalar | API Used |
|---|---|---|
| Vectorised quantisation | 5-20× | `vDSP_vsmulD`/`vDSP_vsdivD` |
| Dead-zone quantisation | 3-10× | `vDSP_vabsD` + `vDSP_vsdivD` |
| DFT (non-power-of-2) | 2-5× | Direct computation with vDSP |
| 16-bit format conversion | 5-10× | `vDSP_vfltu16D`/`vDSP_vfixu16D` |
| Eigenvalue decomposition | 20-50× | LAPACK `dsyev_` |
| Batch matrix multiply | 15-40× | BLAS `cblas_dgemm` |
| Covariance matrix | 5-15× | `vDSP_meanvD`/`vDSP_dotprD` |
| Image scaling (16-bit) | 3-8× | `vImageScale_PlanarF` |

## Platform Support

All deep integration features use `#if canImport(Accelerate)` guards:
- **macOS**: Full support via Accelerate.framework
- **iOS/iPadOS**: Full support via Accelerate.framework
- **Linux**: Graceful fallback (features report `isAvailable = false`)

## Files

- `Sources/J2KAccelerate/J2KAccelerateDeepIntegration.swift` — Implementation
- `Tests/J2KAccelerateTests/J2KAccelerateDeepIntegrationTests.swift` — Tests (35+)
- `Documentation/ACCELERATE_DEEP_INTEGRATION.md` — This guide
