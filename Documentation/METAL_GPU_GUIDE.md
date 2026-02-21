# Metal GPU Acceleration Guide

J2KSwift uses Apple's Metal framework to accelerate the most compute-intensive stages
of JPEG 2000 encoding and decoding on Apple platforms (macOS, iOS, tvOS, visionOS).

---

## Architecture

```
J2KImage ──► J2KMetalColorTransform ──► J2KMetalDWT ──► J2KMetalQuantizer ──► Codestream
                (ICT / RCT on GPU)        (DWT on GPU)     (Quantise on GPU)
```

All Metal actors require Metal to be available at runtime.  When Metal is unavailable
(e.g., on a Linux CI runner) they fall back to CPU processing automatically.

---

## Enabling Metal

Metal acceleration is provided by the `J2KMetal` module.  Add it to your target:

```swift
// Package.swift
.product(name: "J2KMetal", package: "J2KSwift"),
```

---

## J2KMetalDevice

`J2KMetalDevice` manages the underlying `MTLDevice` and provides capability queries.

```swift
import J2KMetal

let device = J2KMetalDevice()
try device.initialize()

print("GPU: \(device.deviceName())")
print("Tier: \(device.featureTier())")
print("Working set: \(device.maxWorkingSetSize() / (1024 * 1024)) MB")
```

---

## GPU-Accelerated Wavelet Transform

`J2KMetalDWT` performs forward and inverse Discrete Wavelet Transforms on the GPU
using Metal Shading Language compute kernels.

```swift
import J2KMetal

let dwtActor = J2KMetalDWT()
try await dwtActor.initialize()

// Forward 2-D DWT (5/3 lossless)
let coefficients = try await dwtActor.forward2D(
    imageData,
    width: image.width,
    height: image.height,
    filter: .leGall53
)

// Multi-level forward DWT
let multiLevel = try await dwtActor.forwardMultiLevel(
    imageData,
    width: image.width,
    height: image.height,
    levels: 5,
    filter: .cdf97
)

// Inverse DWT (reconstruction)
let reconstructed = try await dwtActor.inverse2D(
    coefficients,
    width: image.width,
    height: image.height,
    filter: .leGall53
)
```

### DWT Statistics

```swift
let stats = await dwtActor.statistics()
print("GPU passes: \(stats.gpuPassCount), CPU fallbacks: \(stats.cpuFallbackCount)")
```

---

## GPU-Accelerated Colour Transform

`J2KMetalColorTransform` performs Irreversible Colour Transform (ICT) and Reversible
Colour Transform (RCT) on the GPU.

```swift
import J2KMetal

let colourActor = J2KMetalColorTransform()

let config = J2KMetalColorTransformConfiguration(
    transform: .ict,  // .ict for lossy, .rct for lossless
    componentCount: 3
)

let result: J2KMetalColorTransformResult = try await colourActor.forward(
    componentData: [redData, greenData, blueData],
    configuration: config
)
```

---

## GPU-Accelerated Quantisation

`J2KMetalQuantizer` quantises and dequantises wavelet coefficients on the GPU.

```swift
import J2KMetal

let quantizer = J2KMetalQuantizer()

let qConfig = J2KMetalQuantizationConfiguration(
    stepSizes: [0.1, 0.2, 0.4],
    deadzone: true
)

let quantised: J2KMetalQuantizationResult = try await quantizer.quantize(
    coefficients,
    configuration: qConfig
)

let restored: J2KMetalDequantizationResult = try await quantizer.dequantize(
    quantised.quantizedData,
    configuration: qConfig
)
```

---

## Multiple Component Transform (MCT) on GPU

```swift
import J2KMetal

let mctActor = J2KMetalMCT()

let mctConfig = J2KMetalMCTConfiguration(
    transform: .rct,
    componentCount: 3,
    bitDepth: 8
)

let mctResult: J2KMetalMCTResult = try await mctActor.forward(
    components: [r, g, b],
    configuration: mctConfig
)

let stats: J2KMetalMCTStatistics = await mctActor.statistics()
```

---

## Memory Budgeting

```swift
// Check whether there is sufficient GPU memory before a large operation
if device.canAllocate(bytes: 256 * 1024 * 1024) {
    // Safe to proceed with 256 MB GPU allocation
    device.trackAllocation(bytes: 256 * 1024 * 1024)
    // ... perform operation ...
    device.trackDeallocation(bytes: 256 * 1024 * 1024)
}

print("Current GPU usage: \(device.memoryUsage() / (1024 * 1024)) MB")
```

---

## JP3D Metal DWT

Volumetric (3-D) wavelet transforms are also GPU-accelerated:

```swift
import J2KMetal

let metalDWT = JP3DMetalDWT()
// See JP3D_GUIDE.md for volumetric Metal DWT examples.
```

---

## Performance Expectations

| Operation                | CPU (Apple M2) | Metal GPU (Apple M2) |
|--------------------------|---------------|----------------------|
| Forward DWT 4 K×4 K      | ~85 ms        | ~8 ms (≈10× faster)  |
| Inverse DWT 4 K×4 K      | ~90 ms        | ~9 ms (≈10× faster)  |
| ICT colour transform 4 K | ~12 ms        | ~1 ms (≈12× faster)  |

---

## Vulkan GPU (Linux / Windows)

For non-Apple platforms, import `J2KVulkan`:

```swift
import J2KVulkan
// See VULKAN_GPU_COMPUTE.md for full Vulkan documentation.
```

---

## See Also

- [Metal GPU Compute Refactoring](METAL_GPU_COMPUTE_REFACTORING.md) — internal architecture
- [Accelerate Deep Integration](ACCELERATE_DEEP_INTEGRATION.md) — Accelerate framework usage
- [Examples/GPUAcceleration.swift](../Examples/GPUAcceleration.swift)
