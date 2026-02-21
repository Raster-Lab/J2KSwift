# ``J2KAccelerate``

Hardware-accelerated operations using Apple's Accelerate framework and SIMD optimisations for ARM Neon and x86 SSE/AVX.

## Overview

J2KAccelerate provides high-performance implementations of computationally intensive JPEG 2000 operations by leveraging platform-specific acceleration. On Apple platforms, the module uses the Accelerate framework (vDSP, vImage, and BLAS) for vectorised mathematical operations. On all platforms, it provides SIMD-optimised code paths for ARM Neon and x86 SSE/AVX instruction sets.

The module accelerates discrete wavelet transforms, multi-component colour transforms, non-linear transforms, and memory operations. It automatically detects available hardware capabilities and selects the optimal code path at runtime.

All types are conditionally compiled using `#if canImport(Accelerate)` to ensure graceful fallback on platforms where the Accelerate framework is unavailable.

## Topics

### Accelerated Wavelet Transform

- ``J2KDWTAccelerated``

### Accelerated Colour Transform

- ``J2KAcceleratedMCT``

### Non-Linear Transform

- ``J2KAcceleratedNLT``

### Advanced Accelerate Integration

- ``J2KAdvancedAccelerate``
- ``J2KvDSPDeepIntegration``
- ``J2KvImageDeepIntegration``
- ``J2KBLASDeepIntegration``

### Memory Optimisation

- ``J2KMemoryOptimisation``
- ``J2KCOWBuffer``

### SIMD Capabilities

- ``NeonTransformCapability``
- ``X86TransformCapability``

### Performance Monitoring

- ``J2KAcceleratePerformance``
