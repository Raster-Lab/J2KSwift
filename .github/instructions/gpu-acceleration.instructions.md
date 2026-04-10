---
description: "Use when editing GPU acceleration code: Metal compute shaders, Vulkan pipelines, Accelerate vDSP/vImage, SIMD optimization, GPU buffer pools, platform-conditional compilation."
applyTo: Sources/J2KAccelerate/**, Sources/J2KMetal/**, Sources/J2KVulkan/**
---

# GPU Acceleration Guidelines

## Platform Guards
Always use conditional compilation for platform-specific APIs:
```swift
#if canImport(Accelerate)
import Accelerate
#endif

#if canImport(Metal)
import Metal
#endif
```

## CPU Fallback
Every GPU-accelerated operation MUST have a CPU fallback path. The GPU path is an optimization, not the only implementation.

## Buffer Management
- Reuse GPU buffers via pool (`J2KMetalBufferPool`, `J2KVulkanBufferPool`)
- Avoid GPU↔CPU round-trips in tight loops
- Use shared/managed memory modes where possible (Metal)
- Track buffer allocations to prevent GPU memory leaks

## Correctness
- GPU output must match CPU reference within tolerance
- Integer operations (lossless DWT): exact match required
- Float operations (lossy DWT, quantization): max error < 1e-5

## Concurrency
- Metal command buffers are not `Sendable` — submit from a single actor
- Vulkan command buffers require proper synchronization
- Accelerate functions are thread-safe but not re-entrant in-place
