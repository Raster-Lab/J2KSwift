# ``J2KVulkan``

Vulkan GPU compute acceleration for JPEG 2000 operations on Linux and Windows platforms.

## Overview

J2KVulkan provides GPU-accelerated JPEG 2000 processing using the Vulkan compute API. It mirrors the functionality of the ``J2KMetal`` module, delivering hardware-accelerated discrete wavelet transforms, colour transforms, and quantisation on platforms where Metal is unavailable.

The ``J2KVulkanDevice`` actor manages the Vulkan instance, physical device, and compute queue. ``J2KVulkanBufferPool`` handles GPU memory allocation with efficient buffer reuse. Compute shaders are compiled from SPIR-V modules managed by ``J2KVulkanShaderLibrary``.

The ``J2KGPUBackendSelector`` automatically chooses the optimal GPU backend (Metal or Vulkan) based on platform availability, enabling transparent cross-platform GPU acceleration.

## Topics

### Device Management

- ``J2KVulkanDevice``
- ``J2KVulkanBufferPool``

### Compute Operations

- ``J2KVulkanDWT``
- ``J2KVulkanColourTransform``
- ``J2KVulkanQuantiser``

### Shader Infrastructure

- ``J2KVulkanShaderLibrary``

### Backend Selection

- ``J2KGPUBackendSelector``
