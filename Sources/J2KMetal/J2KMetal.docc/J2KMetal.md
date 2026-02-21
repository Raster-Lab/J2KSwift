# ``J2KMetal``

Metal GPU compute acceleration for JPEG 2000 operations on Apple platforms.

## Overview

J2KMetal leverages Apple's Metal framework to offload computationally intensive JPEG 2000 operations to the GPU. This includes discrete wavelet transforms, colour transforms, quantisation, and multi-component transforms. By utilising the massively parallel architecture of modern GPUs, J2KMetal can deliver significant performance improvements over CPU-only processing for large images.

The ``J2KMetalDevice`` actor manages the Metal device and command queue, providing thread-safe access to GPU resources. ``J2KMetalBufferPool`` handles efficient allocation and reuse of GPU memory buffers. Shader pipelines are managed by ``J2KMetalShaderPipelineManager``, which compiles and caches compute kernels from the ``J2KMetalShaderLibrary``.

This module is available only on Apple platforms where Metal is supported (macOS, iOS, tvOS, visionOS).

## Topics

### Device Management

- ``J2KMetalDevice``
- ``J2KMetalBufferPool``

### Compute Operations

- ``J2KMetalDWT``
- ``J2KMetalColorTransform``
- ``J2KMetalMCT``
- ``J2KMetalQuantizer``

### Shader Infrastructure

- ``J2KMetalShaderLibrary``
- ``J2KMetalShaderPipelineManager``
