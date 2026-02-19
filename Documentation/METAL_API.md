# Metal API Reference

## Overview

The J2KMetal module provides GPU-accelerated JPEG 2000 operations using Apple's Metal framework. This document provides a comprehensive guide to the Metal API, including device management, buffer pooling, shader compilation, and GPU-accelerated transforms.

## Table of Contents

1. [Architecture](#architecture)
2. [Device Management](#device-management)
3. [Buffer Management](#buffer-management)
4. [Shader Library](#shader-library)
5. [Wavelet Transforms](#wavelet-transforms)
6. [Color Transforms](#color-transforms)
7. [Multi-Component Transforms](#multi-component-transforms)
8. [Region of Interest (ROI)](#region-of-interest-roi)
9. [Quantization](#quantization)
10. [Performance Optimization](#performance-optimization)
11. [Best Practices](#best-practices)
12. [Error Handling](#error-handling)

## Architecture

The J2KMetal module follows a layered architecture:

```
┌─────────────────────────────────────┐
│   High-Level Operations             │
│   (DWT, Color, MCT, ROI, Quant)     │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│   Shader Library & Pipeline Mgmt    │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│   Buffer Pool & Memory Management   │
└─────────────────────────────────────┘
           ↓
┌─────────────────────────────────────┐
│   Metal Device & Command Queue      │
└─────────────────────────────────────┘
```

### Key Design Principles

- **Actor Isolation**: All Metal types are actors for thread-safe concurrent access
- **Conditional Compilation**: `#if canImport(Metal)` ensures cross-platform compatibility
- **Graceful Fallback**: CPU implementations available when Metal is unavailable
- **Memory Efficiency**: Buffer pooling and reuse minimize allocations
- **Pipeline Caching**: Compiled shaders are cached for performance

## Device Management

### J2KMetalDevice

The `J2KMetalDevice` actor manages Metal device selection, command queue creation, and feature detection.

#### Initialization

```swift
import J2KMetal

// Create with default configuration
let device = J2KMetalDevice()

// Create with custom configuration
let config = J2KMetalDeviceConfiguration(
    preferLowPower: false,
    maxMemoryUsage: 2 * 1024 * 1024 * 1024, // 2 GB
    enableFallback: true
)
let device = J2KMetalDevice(configuration: config)
```

#### Configuration Options

```swift
public struct J2KMetalDeviceConfiguration: Sendable {
    /// Prefer low-power GPU on multi-GPU systems
    public var preferLowPower: Bool
    
    /// Maximum GPU memory usage in bytes (0 = unlimited)
    public var maxMemoryUsage: UInt64
    
    /// Fall back to CPU when Metal is unavailable
    public var enableFallback: Bool
    
    /// Predefined configurations
    public static let `default`: J2KMetalDeviceConfiguration
    public static let highPerformance: J2KMetalDeviceConfiguration
    public static let lowPower: J2KMetalDeviceConfiguration
}
```

#### Feature Detection

```swift
public enum J2KMetalFeatureTier: Sendable {
    case unknown           // Unsupported GPU
    case intelIntegrated   // Intel integrated GPU
    case intelDiscrete     // Intel discrete GPU
    case appleSilicon      // Apple Silicon M1+
}

// Get device feature tier
let tier = await device.featureTier()

// Check memory availability
let availableMemory = await device.availableMemory()
```

#### Device Capabilities

```swift
// Check if Metal is available
let isAvailable = await device.isAvailable()

// Get device name
let name = await device.deviceName()

// Get max threadgroup size
let maxThreads = await device.maxThreadsPerThreadgroup()
```

## Buffer Management

### J2KMetalBufferPool

The `J2KMetalBufferPool` actor manages GPU buffer allocation, pooling, and reuse to minimize allocation overhead.

#### Buffer Strategies

```swift
public enum J2KMetalBufferStrategy: Sendable {
    case shared    // Shared between CPU and GPU (zero-copy)
    case managed   // Synchronized between CPU and GPU
    case `private` // GPU-only (best performance)
}
```

#### Usage

```swift
let bufferPool = J2KMetalBufferPool(device: device)

// Allocate buffer
let buffer = try await bufferPool.allocate(
    size: 4096,
    strategy: .private
)

// Use buffer...

// Return to pool for reuse
await bufferPool.deallocate(buffer)

// Reset pool (clear all buffers)
await bufferPool.reset()

// Get statistics
let stats = await bufferPool.statistics()
print("Total allocations: \(stats.totalAllocations)")
print("Pool hits: \(stats.poolHits)")
print("Memory usage: \(stats.memoryUsage) bytes")
```

## Shader Library

### J2KMetalShaderLibrary

The `J2KMetalShaderLibrary` actor manages shader compilation, pipeline state creation, and caching.

#### Shader Functions

```swift
public enum J2KMetalShaderFunction: String, CaseIterable, Sendable {
    // Discrete Wavelet Transform (8 shaders)
    case dwt53ForwardHorizontal
    case dwt53ForwardVertical
    case dwt53InverseHorizontal
    case dwt53InverseVertical
    case dwt97ForwardHorizontal
    case dwt97ForwardVertical
    case dwt97InverseHorizontal
    case dwt97InverseVertical
    
    // Arbitrary Wavelet (8 shaders)
    case arbitraryConvolutionForwardHorizontal
    case arbitraryConvolutionForwardVertical
    case arbitraryConvolutionInverseHorizontal
    case arbitraryConvolutionInverseVertical
    case arbitraryLiftingForwardHorizontal
    case arbitraryLiftingForwardVertical
    case arbitraryLiftingInverseHorizontal
    case arbitraryLiftingInverseVertical
    
    // Color Transforms (4 shaders)
    case colorICTForward
    case colorICTInverse
    case colorRCTForward
    case colorRCTInverse
    
    // MCT (7 shaders)
    case mctMatrixMultiply
    case mctOptimized3x3
    case mctOptimized4x4
    case mctFusedColorTransform
    
    // NLT (4 shaders)
    case nltParametric
    case nltLUT
    case nltPQ
    case nltHLG
    
    // ROI (5 shaders)
    case roiMaskGenerate
    case roiCoefficientScale
    case roiMaskBlend
    case roiFeathering
    case roiWaveletMapping
    
    // Quantization (8 shaders)
    case quantizeScalar
    case dequantizeScalar
    case quantizeDeadzone
    case dequantizeDeadzone
    case visualWeighting
    case perceptualWeighting
    case trellisQuantization
    case distortionEstimation
}
```

#### Usage

```swift
let shaderLibrary = J2KMetalShaderLibrary(device: device)

// Get compiled pipeline state
let pipeline = try await shaderLibrary.getPipelineState(
    for: .dwt97ForwardHorizontal
)

// Clear cache
await shaderLibrary.clearCache()

// Get cache statistics
let cacheStats = await shaderLibrary.cacheStatistics()
```

## Wavelet Transforms

### J2KMetalDWT

The `J2KMetalDWT` actor provides GPU-accelerated discrete wavelet transforms.

#### Filter Types

```swift
public enum J2KMetalDWTFilter: Sendable {
    case reversible53                        // Le Gall 5/3
    case irreversible97                      // CDF 9/7
    case arbitrary(J2KMetalArbitraryFilter) // Custom coefficients
    case lifting(J2KMetalLiftingScheme)     // Lifting scheme
}
```

#### 1D Transform

```swift
let dwt = J2KMetalDWT(device: device, shaderLibrary: shaderLibrary)

// Forward 1D transform
let (lowpass, highpass) = try await dwt.forward1D(
    input: signalData,
    filter: .irreversible97
)

// Inverse 1D transform
let reconstructed = try await dwt.inverse1D(
    lowpass: lowpass,
    highpass: highpass,
    filter: .irreversible97
)
```

#### 2D Transform

```swift
// Forward 2D transform
let subbands = try await dwt.forward2D(
    input: imageData,
    width: 1920,
    height: 1080,
    levels: 5,
    filter: .irreversible97
)

// Inverse 2D transform
let reconstructed = try await dwt.inverse2D(
    subbands: subbands,
    width: 1920,
    height: 1080,
    levels: 5,
    filter: .irreversible97
)
```

#### Multi-Level Decomposition

```swift
// Decompose with multiple levels
let decomposition = try await dwt.decompose(
    data: imageData,
    width: 1920,
    height: 1080,
    levels: 5,
    filter: .irreversible97,
    tileBased: true  // Use tiling for large images
)
```

## Color Transforms

### J2KMetalColorTransform

The `J2KMetalColorTransform` actor provides GPU-accelerated color space transformations.

#### Transform Types

```swift
public enum J2KColorTransformType: Sendable {
    case none      // No transform
    case ict       // Irreversible Component Transform (lossy)
    case rct       // Reversible Component Transform (lossless)
}
```

#### Usage

```swift
let colorTransform = J2KMetalColorTransform(
    device: device,
    shaderLibrary: shaderLibrary
)

// Forward ICT (RGB → YCbCr)
let yCbCr = try await colorTransform.forwardICT(
    r: redChannel,
    g: greenChannel,
    b: blueChannel
)

// Inverse ICT (YCbCr → RGB)
let rgb = try await colorTransform.inverseICT(
    y: yCbCr.y,
    cb: yCbCr.cb,
    cr: yCbCr.cr
)

// Forward RCT (lossless)
let rct = try await colorTransform.forwardRCT(
    r: redChannel,
    g: greenChannel,
    b: blueChannel
)
```

#### Non-Linear Transforms (NLT)

```swift
// Apply PQ (Perceptual Quantizer) for HDR
let pq = try await colorTransform.applyNLT(
    input: hdrData,
    transform: .pq(parameters: .bt2100)
)

// Apply HLG (Hybrid Log-Gamma) for HDR
let hlg = try await colorTransform.applyNLT(
    input: hdrData,
    transform: .hlg(parameters: .bt2100)
)

// Apply LUT-based transform
let lut = try await colorTransform.applyNLT(
    input: data,
    transform: .lut(table: customLUT, interpolation: .linear)
)
```

## Multi-Component Transforms

### J2KMetalMCT

The `J2KMetalMCT` actor provides GPU-accelerated multi-component transforms for spectral images.

#### Transform Configuration

```swift
// N×N matrix transform
let mct = J2KMetalMCT(device: device, shaderLibrary: shaderLibrary)

// Define transform matrix
let matrix: [[Float]] = [
    [0.299,  0.587,  0.114],
    [-0.169, -0.331,  0.500],
    [0.500, -0.419, -0.081]
]

// Apply transform
let transformed = try await mct.applyMatrix(
    components: inputComponents,
    matrix: matrix
)
```

#### Optimized Transforms

```swift
// 3×3 optimized (fast path)
let result3x3 = try await mct.applyOptimized3x3(
    components: [c1, c2, c3],
    matrix: matrix3x3
)

// 4×4 optimized (fast path)
let result4x4 = try await mct.applyOptimized4x4(
    components: [c1, c2, c3, c4],
    matrix: matrix4x4
)
```

#### Fused Operations

```swift
// Fused color transform + MCT
let fused = try await mct.applyFusedColorMCT(
    r: red,
    g: green,
    b: blue,
    mctMatrix: matrix
)
```

## Region of Interest (ROI)

### J2KMetalROI

The `J2KMetalROI` actor provides GPU-accelerated region of interest encoding.

#### ROI Methods

```swift
let roi = J2KMetalROI(device: device, shaderLibrary: shaderLibrary)

// Generate ROI mask
let mask = try await roi.generateMask(
    width: 1920,
    height: 1080,
    regions: [
        J2KROIRegion(x: 100, y: 100, width: 500, height: 500, priority: 1.0),
        J2KROIRegion(x: 800, y: 400, width: 300, height: 300, priority: 0.5)
    ]
)

// Scale coefficients based on ROI
let scaled = try await roi.scaleCoefficients(
    coefficients: waveletCoefficients,
    mask: mask,
    maxShift: 37  // JPEG 2000 max shift
)

// Blend multiple ROI masks
let blended = try await roi.blendMasks(
    masks: [mask1, mask2, mask3],
    featherRadius: 10
)
```

#### Advanced ROI

```swift
// Apply feathering to ROI boundaries
let feathered = try await roi.applyFeathering(
    mask: mask,
    radius: 10,
    falloff: .gaussian
)

// Map ROI to wavelet domain
let waveletROI = try await roi.mapToWaveletDomain(
    mask: spatialMask,
    decompositionLevel: 5
)
```

## Quantization

### J2KMetalQuantizer

The `J2KMetalQuantizer` actor provides GPU-accelerated quantization and dequantization.

#### Quantization Methods

```swift
let quantizer = J2KMetalQuantizer(device: device, shaderLibrary: shaderLibrary)

// Scalar quantization
let quantized = try await quantizer.quantizeScalar(
    coefficients: waveletCoefficients,
    stepSize: 0.05
)

// Deadzone quantization
let quantizedDZ = try await quantizer.quantizeDeadzone(
    coefficients: waveletCoefficients,
    stepSize: 0.05,
    deadzoneSize: 0.8
)

// Dequantization
let dequantized = try await quantizer.dequantizeScalar(
    coefficients: quantized,
    stepSize: 0.05
)
```

#### Perceptual Weighting

```swift
// Apply visual weighting
let weighted = try await quantizer.applyVisualWeighting(
    coefficients: coefficients,
    subband: .hl,  // High-low subband
    baseStepSize: 0.05
)

// Apply perceptual weighting
let perceptual = try await quantizer.applyPerceptualWeighting(
    coefficients: coefficients,
    csf: contrastSensitivityFunction
)
```

#### Trellis Quantization

```swift
// Apply trellis quantization
let trellis = try await quantizer.quantizeTrellis(
    coefficients: coefficients,
    stepSize: 0.05,
    distortionWeight: 1.0
)
```

## Performance Optimization

### J2KMetalPerformance

The `J2KMetalPerformance` actor provides performance monitoring and optimization.

#### Threadgroup Optimization

```swift
public enum J2KMetalThreadgroupStrategy: Sendable {
    case auto              // Automatic selection
    case threads1D(Int)    // 1D threadgroup
    case threads2D(Int, Int) // 2D threadgroup
}
```

#### Performance Monitoring

```swift
let performance = J2KMetalPerformance(device: device)

// Start profiling
await performance.beginProfiling()

// Execute operations...
let result = try await dwt.forward2D(...)

// End profiling and get metrics
let metrics = await performance.endProfiling()

print("GPU time: \(metrics.gpuTime) ms")
print("CPU time: \(metrics.cpuTime) ms")
print("Memory bandwidth: \(metrics.bandwidth) GB/s")
print("Kernel launches: \(metrics.kernelLaunches)")
```

#### Async Compute

```swift
// Enable async compute for overlapping operations
await performance.enableAsyncCompute()

// Execute multiple operations concurrently
async let dwt = metalDWT.forward2D(...)
async let color = metalColor.forwardICT(...)

let (dwtResult, colorResult) = try await (dwt, color)
```

#### Bandwidth Estimation

```swift
// Estimate memory bandwidth
let bandwidth = await performance.estimateBandwidth(
    dataSize: 4 * 1920 * 1080,
    duration: metrics.gpuTime
)

// Optimize for bandwidth
await performance.optimizeForBandwidth(
    threshold: 100.0  // GB/s
)
```

## Best Practices

### 1. Buffer Reuse

```swift
// ✅ Good: Reuse buffers from pool
let buffer1 = try await bufferPool.allocate(size: 4096, strategy: .private)
// Use buffer...
await bufferPool.deallocate(buffer1)

let buffer2 = try await bufferPool.allocate(size: 4096, strategy: .private)
// buffer2 may reuse buffer1's memory

// ❌ Bad: Create new buffers repeatedly
for _ in 0..<1000 {
    let buffer = device.makeBuffer(length: 4096, options: .storageModePrivate)
    // Memory leak!
}
```

### 2. Pipeline Compilation

```swift
// ✅ Good: Pre-compile pipelines at startup
await shaderLibrary.precompileAll()

// ❌ Bad: Compile on first use (causes stutter)
let pipeline = try await shaderLibrary.getPipelineState(for: .dwt97ForwardHorizontal)
```

### 3. Batch Operations

```swift
// ✅ Good: Batch multiple operations
let results = try await dwt.batchForward2D(
    images: imageArray,
    filter: .irreversible97
)

// ❌ Bad: Process one at a time
for image in imageArray {
    let result = try await dwt.forward2D(input: image, ...)
}
```

### 4. Memory Strategy

```swift
// ✅ Good: Use private storage for GPU-only data
let buffer = try await bufferPool.allocate(size: size, strategy: .private)

// ✅ Good: Use shared storage for frequent CPU/GPU transfers
let buffer = try await bufferPool.allocate(size: size, strategy: .shared)

// ❌ Bad: Use managed storage unnecessarily (slower)
let buffer = try await bufferPool.allocate(size: size, strategy: .managed)
```

### 5. Resource Management

```swift
// ✅ Good: Release resources when done
defer {
    Task {
        await bufferPool.reset()
        await shaderLibrary.clearCache()
    }
}

// ❌ Bad: Let resources accumulate
// Memory usage grows unbounded
```

## Error Handling

### Metal Errors

```swift
public enum J2KMetalError: Error, Sendable {
    case deviceUnavailable
    case bufferAllocationFailed
    case shaderCompilationFailed(String)
    case pipelineCreationFailed(String)
    case commandExecutionFailed
    case unsupportedFeature(String)
    case invalidConfiguration(String)
}
```

### Error Handling Patterns

```swift
// Handle Metal unavailability
do {
    let result = try await dwt.forward2D(...)
} catch J2KMetalError.deviceUnavailable {
    // Fall back to CPU
    let result = try cpuDWT.forward2D(...)
} catch {
    print("Unexpected error: \(error)")
}

// Validate before execution
guard await device.isAvailable() else {
    throw J2KMetalError.deviceUnavailable
}

// Check memory availability
let required = imageSize * 4
let available = await device.availableMemory()
guard available >= required else {
    throw J2KMetalError.bufferAllocationFailed
}
```

## Platform Compatibility

### Conditional Compilation

All Metal code uses conditional compilation to support non-Apple platforms:

```swift
#if canImport(Metal)
import Metal

public actor J2KMetalDevice {
    // Metal implementation
}
#else
public actor J2KMetalDevice {
    // Stub implementation (always unavailable)
}
#endif
```

### Runtime Checks

```swift
// Check Metal availability at runtime
if await device.isAvailable() {
    // Use Metal
} else {
    // Fall back to CPU
}
```

## See Also

- [Metal Performance Guide](METAL_PERFORMANCE.md) - Optimization techniques
- [Apple Silicon Optimization Guide](APPLE_SILICON_OPTIMIZATION.md) - Platform-specific tuning
- [Hardware Acceleration](../HARDWARE_ACCELERATION.md) - General acceleration overview
- [Metal DWT Documentation](METAL_DWT.md) - Wavelet transform details
- [Metal Color/MCT Documentation](METAL_COLOR_MCT.md) - Color transform details
- [Metal ROI/Quantization Documentation](METAL_ROI_QUANTIZATION.md) - ROI and quantization details

---

**Last Updated**: 2026-02-19  
**Version**: 1.7.0  
**Maintainer**: J2KSwift Team
