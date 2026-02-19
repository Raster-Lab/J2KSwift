# Arbitrary Wavelet Kernels — ISO/IEC 15444-2 Part 2

## Overview

J2KSwift supports arbitrary wavelet kernels as defined in ISO/IEC 15444-2 (JPEG 2000 Part 2). This extends the standard Part 1 filters (Le Gall 5/3 and CDF 9/7) with a framework for defining and using custom wavelet filters.

## Features

- **Wavelet Kernel Representation** — Complete filter specification with analysis/synthesis pairs, symmetry properties, and optional lifting scheme
- **Pre-Built Kernel Library** — Haar, Le Gall 5/3, CDF 9/7, Daubechies-4, Daubechies-6, and CDF 5/3
- **ADS Marker Support** — Arbitrary Decomposition Styles marker (0xFF74) for Part 2 codestreams
- **Generic Convolution Engine** — Direct convolution with arbitrary filters, supporting multiple boundary extension modes
- **Hardware Acceleration** — vDSP-accelerated convolution on Apple platforms via `J2KAcceleratedArbitraryWavelet`
- **Kernel Validation** — Validate filter correctness, perfect reconstruction, and serialization

## Quick Start

### Using a Pre-Built Kernel

```swift
import J2KCodec

// Select a kernel from the library
let kernel = J2KWaveletKernelLibrary.haar

// Create a transform engine
let transform = J2KArbitraryWaveletTransform(kernel: kernel)

// 1D forward transform
let signal: [Double] = [1, 2, 3, 4, 5, 6, 7, 8]
let (lowpass, highpass) = try transform.forwardTransform1D(signal: signal)

// 1D inverse transform (reconstruct)
let reconstructed = try transform.inverseTransform1D(lowpass: lowpass, highpass: highpass)
```

### 2D Multi-Level Decomposition

```swift
let kernel = J2KWaveletKernelLibrary.cdf97
let transform = J2KArbitraryWaveletTransform(kernel: kernel)

let image: [[Double]] = (0..<64).map { r in (0..<64).map { c in Double(r * 64 + c) } }

// Forward decomposition with 3 levels
let decomposition = try transform.forwardTransform2D(image: image, levels: 3)

// Access subbands
let finalLL = decomposition.coarsestApproximation
let level0LH = decomposition.levels[0].lh

// Reconstruct
let reconstructed = try transform.inverseTransform2D(decomposition: decomposition)
```

### Defining a Custom Kernel

```swift
let customKernel = J2KWaveletKernel(
    name: "My Custom Wavelet",
    analysisLowpass: [0.5, 0.5],
    analysisHighpass: [-0.5, 0.5],
    synthesisLowpass: [0.5, 0.5],
    synthesisHighpass: [0.5, -0.5],
    symmetry: .symmetric,
    isReversible: false
)

// Validate the kernel
try customKernel.validate()

// Check perfect reconstruction property
let hasPR = customKernel.validatePerfectReconstruction(tolerance: 1e-10)
```

## Available Kernels

| Kernel | Taps (LP/HP) | Symmetry | Reversible | Use Case |
|--------|-------------|----------|------------|----------|
| Haar | 2/2 | Symmetric | Yes | Simple edge detection, fast computation |
| Le Gall 5/3 | 5/3 | Symmetric | Yes | Lossless compression (JPEG 2000 Part 1) |
| CDF 9/7 | 9/7 | Symmetric | No | Lossy compression (JPEG 2000 Part 1) |
| CDF 5/3 | 5/3 | Symmetric | Yes | Normalized Le Gall for quantization |
| Daubechies-4 | 4/4 | Asymmetric | No | 2 vanishing moments, piecewise-linear signals |
| Daubechies-6 | 6/6 | Asymmetric | No | 3 vanishing moments, smoother signals |

## ADS Marker

The ADS (Arbitrary Decomposition Styles) marker segment (0xFF74) specifies custom decomposition structures in Part 2 codestreams.

```swift
// Create an ADS marker
let marker = J2KADSMarker(
    index: 0,
    decompositionOrder: .mallat,
    nodes: [
        J2KADSMarker.DecompositionNode(
            horizontalDecompose: true,
            verticalDecompose: true,
            kernelIndex: 0
        )
    ],
    maxLevels: 5
)

// Encode to codestream
let data = marker.encode()

// Decode from codestream
let decoded = try J2KADSMarker.decode(from: data)
```

### Decomposition Orders

- **Mallat** (`.mallat`): Standard dyadic — only the LL subband is further decomposed at each level.
- **Packet Wavelet** (`.packetWavelet`): Any subband may be further decomposed.

## Kernel Serialization

Kernels can be serialized to binary format for embedding in codestreams:

```swift
let kernel = J2KWaveletKernelLibrary.daubechies4

// Serialize
let data = kernel.encode()

// Deserialize
let restored = try J2KWaveletKernel.decode(from: data)
assert(kernel == restored)
```

## Integration with DWT Pipeline

Kernels can be converted to `J2KDWT1D.CustomFilter` for integration with the existing lifting-based DWT pipeline:

```swift
let kernel = J2KWaveletKernelLibrary.cdf97
let customFilter = kernel.toCustomFilter()

// Use with J2KDWT1D
let (low, high) = try J2KDWT1D.forwardTransform(
    signal: signal,
    filter: .custom(customFilter)
)
```

## Hardware Acceleration

On Apple platforms, `J2KAcceleratedArbitraryWavelet` uses the Accelerate framework's `vDSP_convD` for high-performance convolution:

```swift
import J2KAccelerate

let filter = J2KAcceleratedWaveletFilter(
    analysisLowpass: kernel.analysisLowpass,
    analysisHighpass: kernel.analysisHighpass,
    synthesisLowpass: kernel.synthesisLowpass,
    synthesisHighpass: kernel.synthesisHighpass,
    lowpassScale: kernel.lowpassScale,
    highpassScale: kernel.highpassScale
)

let accel = J2KAcceleratedArbitraryWavelet(filter: filter)
if J2KAcceleratedArbitraryWavelet.isAvailable {
    let (low, high) = try accel.forwardTransform1D(signal: signal)
}
```

## API Reference

### Types

- `J2KWaveletKernel` — Complete wavelet kernel representation
- `J2KWaveletKernel.FilterSymmetry` — Symmetry classification (symmetric, antiSymmetric, asymmetric)
- `J2KWaveletKernelLibrary` — Static library of pre-built kernels
- `J2KADSMarker` — ADS marker segment for Part 2 codestreams
- `J2KADSMarker.DecompositionOrder` — Mallat or packet wavelet
- `J2KADSMarker.DecompositionNode` — Per-node decomposition control
- `J2KArbitraryWaveletTransform` — Generic convolution engine
- `J2KArbitraryDecomposition` — Multi-level decomposition result
- `J2KArbitraryDecompositionLevel` — Single level detail subbands
- `J2KAcceleratedWaveletFilter` — Standalone filter for Accelerate module
- `J2KAcceleratedArbitraryWavelet` — Hardware-accelerated transform

### Key Methods

| Method | Description |
|--------|-------------|
| `J2KWaveletKernel.validate()` | Validates kernel coefficients and properties |
| `J2KWaveletKernel.validatePerfectReconstruction(tolerance:)` | Checks PR condition |
| `J2KWaveletKernel.toCustomFilter()` | Converts to `J2KDWT1D.CustomFilter` |
| `J2KWaveletKernel.encode()` | Serializes to binary |
| `J2KWaveletKernel.decode(from:)` | Deserializes from binary |
| `J2KADSMarker.encode()` | Encodes ADS marker to codestream |
| `J2KADSMarker.decode(from:)` | Decodes ADS marker from codestream |
| `J2KArbitraryWaveletTransform.forwardTransform1D(signal:)` | 1D forward transform |
| `J2KArbitraryWaveletTransform.inverseTransform1D(lowpass:highpass:)` | 1D inverse transform |
| `J2KArbitraryWaveletTransform.forwardTransform2D(image:levels:)` | Multi-level 2D forward |
| `J2KArbitraryWaveletTransform.inverseTransform2D(decomposition:)` | Multi-level 2D inverse |

## Performance Considerations

- Use lifting-based transforms (via `toCustomFilter()`) for standard kernels — they are faster for in-place computation
- Direct convolution is more flexible but slower for large filters
- On Apple platforms, `J2KAcceleratedArbitraryWavelet` provides significant speedup via vDSP
- Symmetric filters allow symmetric boundary extension, which is more efficient than zero-padding
- For production use, prefer the standard Part 1 kernels (5/3, 9/7) unless Part 2 features are required
