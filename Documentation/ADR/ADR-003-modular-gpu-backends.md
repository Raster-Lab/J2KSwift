# ADR-003 — Modular GPU Backends

**Status**: Accepted

**Date**: 2024-09-01

## Context

The computationally intensive stages of JPEG 2000 — the discrete wavelet
transform (DWT), colour transforms, and quantisation — are embarrassingly
parallel over the spatial extent of each tile. Modern GPUs can execute these
operations orders of magnitude faster than a scalar CPU implementation.

However, the GPU programming APIs available differ drastically by platform:

- **Apple platforms** (macOS, iOS, tvOS, visionOS) provide **Metal**, a
  high-level, well-documented GPU compute API that is only available on Apple
  hardware.
- **Linux and Windows** have no Metal support but have broad coverage of
  **Vulkan**, an explicit, cross-platform GPU API backed by SPIR-V compute
  shaders.

A monolithic "GPU module" that conditionally compiled Metal and Vulkan code
would be difficult to test, maintain, and document. Contributors who work only
on macOS would need to understand Vulkan internals, and vice versa.

## Decision

J2KSwift implements GPU acceleration as **two independent, parallel modules**:

- **`J2KMetal`** — compiled only when `canImport(Metal)` is true (Apple
  platforms). Implements `J2KMetalDWT`, `J2KMetalQuantizer`, and
  `J2KMetalColorTransform` using Metal compute shaders written in Metal
  Shading Language.
- **`J2KVulkan`** — compiled on Linux and Windows. Implements
  `J2KVulkanDWT`, `J2KVulkanQuantizer`, and `J2KVulkanColourTransform`
  using SPIR-V compute shaders.

Both modules implement a common `J2KGPUBackend` protocol defined in `J2KCore`.
A runtime selector, `J2KGPUBackendSelector`, chooses the appropriate backend:

```swift
// J2KGPUBackendSelector selection logic (simplified)
static var best: any J2KGPUBackend {
    #if canImport(Metal)
    if let metal = J2KMetalContext.shared { return J2KMetalBackend(context: metal) }
    #endif
    #if os(Linux) || os(Windows)
    if let vulkan = J2KVulkanContext.shared { return J2KVulkanBackend(context: vulkan) }
    #endif
    return J2KCPUBackend()  // SIMD CPU fallback via J2KAccelerate
}
```

The codec pipeline in `J2KCodec` interacts only with `J2KGPUBackend`; it is
completely unaware of which concrete backend is active.

## Consequences

### Positive

- The Metal and Vulkan implementations are fully isolated; a change to the
  Metal shaders cannot accidentally break the Vulkan path.
- Each module can be tested independently on its native platform.
- The CPU fallback (`J2KAccelerate`) means the library works on any Swift 6
  platform even without GPU support, enabling CI on headless Linux servers.
- Applications that do not need GPU acceleration simply do not import
  `J2KMetal` or `J2KVulkan`, keeping binary size minimal.

### Negative / Trade-offs

- **Code duplication**: the DWT, quantisation, and colour transform logic is
  implemented three times (Metal, Vulkan, CPU). Correctness bugs must be fixed
  in all three implementations.
- **Integration testing complexity**: end-to-end GPU tests require running on
  both an Apple device (for Metal) and a Linux machine with a Vulkan-capable
  GPU (for Vulkan). CI requires two different platform runners.
- **`J2KGPUBackend` protocol stability**: adding a new GPU-accelerated
  operation requires updating the protocol and all three implementations
  simultaneously.

## See Also

- `Documentation/ARCHITECTURE.md#gpu-backends`
- `ADR-001-swift6-strict-concurrency.md`
