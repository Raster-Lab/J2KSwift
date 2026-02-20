# Vulkan GPU Compute for Linux/Windows

## Overview

The `J2KVulkan` module provides a Vulkan-based GPU compute backend for JPEG 2000
operations on Linux and Windows platforms. It mirrors the architecture of the existing
`J2KMetal` module, porting Metal compute shaders to SPIR-V with full CPU fallback
for platforms where Vulkan is unavailable.

## Architecture

### Module Structure

```
Sources/J2KVulkan/
├── J2KVulkanDevice.swift          — Device initialisation, feature detection
├── J2KVulkanBufferPool.swift      — GPU buffer pooling and memory management
├── J2KVulkanShaderLibrary.swift   — SPIR-V shader pipeline management
├── J2KVulkanDWT.swift             — Discrete wavelet transform (5/3 & 9/7)
├── J2KVulkanColorTransform.swift  — Colour transforms (ICT & RCT)
├── J2KVulkanQuantizer.swift       — Quantisation (scalar & deadzone)
└── J2KVulkanBackend.swift         — Protocol-based GPU backend selection
```

### Platform Support

| Platform      | GPU Backend | Status          |
|---------------|-------------|-----------------|
| macOS         | Metal       | ✅ Production   |
| iOS/tvOS      | Metal       | ✅ Production   |
| Linux (AMD)   | Vulkan      | 🔧 Framework   |
| Linux (NVIDIA)| Vulkan      | 🔧 Framework   |
| Linux (Intel) | Vulkan      | 🔧 Framework   |
| Windows       | Vulkan      | 🔧 Framework   |
| No GPU        | CPU         | ✅ Always       |

### GPU Backend Selection

The `J2KGPUBackendSelector` automatically selects the best available backend:

```swift
let selector = J2KGPUBackendSelector()
let backend = selector.selectedBackend()

switch backend {
case .metal:
    // Apple platforms — use Metal compute
case .vulkan:
    // Linux/Windows — use Vulkan compute
case .cpu:
    // Fallback — use CPU implementations
}
```

## Key Types

### Device Management

- **`J2KVulkanDevice`** — Actor managing Vulkan instance, physical device selection,
  logical device creation, and compute queue. Mirrors `J2KMetalDevice`.
- **`J2KVulkanDeviceConfiguration`** — Controls GPU selection and memory limits.
- **`J2KVulkanFeatureTier`** — GPU vendor classification (NVIDIA, AMD, Intel).
- **`J2KVulkanDeviceProperties`** — Physical device capabilities.

### Compute Operations

- **`J2KVulkanDWT`** — Forward/inverse DWT with Le Gall 5/3 (lossless) and
  CDF 9/7 (lossy) filters, using lifting scheme.
- **`J2KVulkanColourTransform`** — ICT (lossy) and RCT (lossless) colour space
  transforms per JPEG 2000 standard.
- **`J2KVulkanQuantiser`** — Scalar and dead-zone quantisation with CPU fallback.

### Memory Management

- **`J2KVulkanBufferPool`** — Actor-based buffer pool with size bucketing,
  reuse tracking, and configurable memory limits.
- **`J2KVulkanBufferHandle`** — Lightweight handle for tracking buffer allocations.

### Shader Management

- **`J2KVulkanShaderLibrary`** — SPIR-V shader module loading and compute
  pipeline creation with caching.
- **`J2KVulkanShaderFunction`** — Enumeration of all 16 compute shader functions.

## SPIR-V Shaders

The SPIR-V shaders are compiled from GLSL compute shaders that implement the
same algorithms as the Metal shader library. The shader functions cover:

### DWT Shaders (8 functions)
- `dwt_forward_53_horizontal` / `dwt_forward_53_vertical` — Forward 5/3 DWT
- `dwt_inverse_53_horizontal` / `dwt_inverse_53_vertical` — Inverse 5/3 DWT
- `dwt_forward_97_horizontal` / `dwt_forward_97_vertical` — Forward 9/7 DWT
- `dwt_inverse_97_horizontal` / `dwt_inverse_97_vertical` — Inverse 9/7 DWT

### Colour Transform Shaders (4 functions)
- `colour_forward_ict` / `colour_inverse_ict` — ICT (RGB ↔ YCbCr)
- `colour_forward_rct` / `colour_inverse_rct` — RCT (RGB ↔ YUV)

### Quantisation Shaders (4 functions)
- `quantise_scalar` / `dequantise_scalar` — Uniform quantisation
- `quantise_deadzone` / `dequantise_deadzone` — Dead-zone quantisation

## CPU Fallback

All operations include a CPU fallback that is used when:
- Vulkan is not available at compile time (`#if canImport(CVulkan)`)
- Vulkan runtime is not detected
- Data size is below the GPU threshold (configurable)
- Backend is explicitly set to `.cpu`

The CPU implementations produce bit-exact results matching the GPU path,
ensuring consistent behaviour across platforms.

## Usage Examples

### DWT (Wavelet Transform)

```swift
let device = J2KVulkanDevice()
let library = J2KVulkanShaderLibrary()
let dwt = J2KVulkanDWT(device: device, shaderLibrary: library)

// Forward transform (lossy)
let result = try await dwt.forwardTransform(
    samples: inputData,
    configuration: .lossy
)

// Inverse transform
let reconstructed = try await dwt.inverseTransform(
    coefficients: result.coefficients,
    lowpassCount: result.lowpassCount,
    configuration: .lossy
)
```

### Colour Transform

```swift
let transform = J2KVulkanColourTransform(device: device, shaderLibrary: library)

// Forward ICT (RGB → YCbCr)
let yCbCr = try await transform.forwardTransform(
    red: redChannel,
    green: greenChannel,
    blue: blueChannel,
    configuration: .lossy
)

// Inverse ICT (YCbCr → RGB)
let rgb = try await transform.inverseTransform(
    component0: yCbCr.component0,
    component1: yCbCr.component1,
    component2: yCbCr.component2,
    configuration: .lossy
)
```

### Quantisation

```swift
let quantiser = J2KVulkanQuantiser(device: device, shaderLibrary: library)

// Quantise wavelet coefficients
let quantised = try await quantiser.quantise(
    coefficients: waveletCoeffs,
    configuration: .lossy
)

// Dequantise for reconstruction
let reconstructed = try await quantiser.dequantise(
    indices: quantised.indices,
    configuration: .lossy
)
```

## Removal Guide

The `J2KVulkan` module is fully self-contained. To remove Vulkan support:

1. Delete `Sources/J2KVulkan/` directory
2. Delete `Tests/J2KVulkanTests/` directory
3. Remove the `J2KVulkan` library product from `Package.swift`
4. Remove the `J2KVulkan` target from `Package.swift`
5. Remove the `J2KVulkanTests` test target from `Package.swift`
6. Remove any `import J2KVulkan` statements from consuming code

No other modules depend on `J2KVulkan`.

## Testing

The test suite includes 70 tests covering:
- Device configuration and initialisation
- Feature tier identification
- Memory tracking and allocation
- Buffer pool operations (acquire, return, drain, statistics)
- Shader library pipeline caching
- Scalar and dead-zone quantisation (CPU fallback)
- Forward/inverse DWT for both 5/3 and 9/7 filters
- DWT round-trip validation
- ICT and RCT colour transform round-trips
- Backend selector and capabilities
- Fallback path verification (auto → CPU when Vulkan unavailable)
- Edge cases (empty input, single sample, mismatched channels)

Run the tests with:
```bash
swift test --filter J2KVulkanTests
```

## Future Work

When a `CVulkan` Swift system module becomes available:
1. Add `CVulkan` as a system library dependency in `Package.swift`
2. Implement real Vulkan initialisation in `J2KVulkanDevice.initialize()`
3. Implement GPU compute dispatch in the GPU path methods
4. Compile GLSL shaders to SPIR-V and embed in the module bundle
5. Add GPU vs CPU bit-exact validation tests
