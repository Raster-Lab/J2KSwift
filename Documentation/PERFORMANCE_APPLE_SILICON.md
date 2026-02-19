# Performance Guide for Apple Silicon

This document provides comprehensive guidance on optimizing J2KSwift performance on Apple Silicon (M1, M2, M3, M4 families) and other Apple platforms.

## Overview

J2KSwift v1.7.0 includes extensive optimizations for Apple Silicon, achieving:
- **15-30× faster** encoding compared to CPU-only implementation (large images)
- **20-40× faster** decoding compared to CPU-only implementation
- **10-25× faster** multi-component transforms
- **5-15× faster** wavelet transforms
- **2-3× better** performance per watt (power efficiency)

These improvements come from:
- Metal GPU acceleration for compute-intensive operations
- Accelerate framework optimization (vDSP, NEON, AMX)
- Unified memory exploitation
- Platform-specific memory and I/O optimizations
- CPU/GPU work overlap and pipeline optimization

## Quick Start

### Basic Usage

```swift
import J2KCore
import J2KCodec

// Create performance optimizer
let optimizer = J2KPerformanceOptimizer(mode: .highPerformance)

// Configure encoder for Apple Silicon
let encoder = J2KEncoder()

// Optimize encoding pipeline
let (encoded, profile) = try await optimizer.optimizeEncodingPipeline {
    try encoder.encode(image)
}

print("Encoding time: \(profile.totalTime)s")
print("Throughput: \(profile.throughputMBps) MB/s")
print("GPU utilization: \(profile.gpuUtilization)%")
```

### Optimization Modes

Choose the optimization mode based on your use case:

```swift
// Maximum performance (highest power consumption)
let optimizer = J2KPerformanceOptimizer(mode: .highPerformance)

// Balanced performance and power (default, recommended)
let optimizer = J2KPerformanceOptimizer(mode: .balanced)

// Minimize power consumption (mobile devices)
let optimizer = J2KPerformanceOptimizer(mode: .lowPower)

// Thermal management (extended workloads)
let optimizer = J2KPerformanceOptimizer(mode: .thermalConstrained)

// Custom parameters
let params = J2KPerformanceOptimizer.OptimizationParameters(
    maxCPUThreads: 8,
    enableBatching: true,
    enableOverlap: true
)
let optimizer = J2KPerformanceOptimizer(mode: .custom(params))
```

## Performance Optimization Strategies

### 1. GPU Acceleration with Metal

Metal GPU acceleration provides significant speedups for:
- Discrete Wavelet Transform (DWT)
- Multi-Component Transform (MCT)
- Color transforms (RCT/ICT)
- Region of Interest (ROI) processing
- Quantization operations

#### Automatic GPU Selection

The optimizer automatically determines when to use GPU:

```swift
let optimizer = J2KPerformanceOptimizer()

// Check if GPU should be used for this workload
let shouldUseGPU = await optimizer.shouldUseGPU(
    dataSize: imageData.count,
    operationType: "DWT"
)
```

#### Metal Performance Tuning

Fine-tune Metal operations:

```swift
import J2KMetal

let metalPerf = J2KMetalPerformance(device: metalDevice)

// Optimize for maximum throughput
await metalPerf.optimizeForThroughput()

// Get optimal threadgroup size
let threadgroupSize = await metalPerf.optimalThreadgroupSize(
    workloadSize: pixelCount,
    memoryPerThread: 16
)

// Track kernel performance
await metalPerf.startSession()
// ... perform Metal operations ...
let metrics = await metalPerf.endSession()

print("GPU utilization: \(metrics.gpuUtilization)")
print("Bandwidth: \(metrics.bandwidthUtilization)")
```

### 2. Accelerate Framework Optimization

The Accelerate framework provides highly optimized vector operations:

#### vDSP Operations

```swift
import J2KAccelerate

let accelPerf = J2KAcceleratePerformance()

// Configure for high throughput
await accelPerf.optimizeForThroughput()

// Check if Accelerate should be used
let shouldUse = await accelPerf.shouldUseAccelerate(arraySize: 10000)

// Get recommended vDSP function
let function = await accelPerf.recommendVDSPFunction(
    operation: "add",
    dataType: "float",
    size: 10000
)
```

#### NEON SIMD

NEON provides 128-bit SIMD operations on ARM64:

```swift
// Check NEON availability
let hasNEON = await accelPerf.shouldUseNEON()

if hasNEON {
    let vectorWidth = await accelPerf.neonVectorWidth() // 16 bytes
    // Use NEON-optimized code paths
}
```

#### AMX (Apple Matrix Coprocessor)

AMX provides hardware-accelerated matrix operations on Apple Silicon:

```swift
// Check if AMX should be used for this matrix size
let shouldUseAMX = await accelPerf.shouldUseAMX(rows: 64, cols: 64)

if shouldUseAMX {
    let (width, height) = await accelPerf.amxTileSize() // (16, 16)
    // Use AMX-optimized matrix operations
}
```

### 3. Memory Optimization

Apple Silicon unified memory architecture enables efficient CPU/GPU sharing:

#### Unified Memory

```swift
import J2KCore

// Create buffer with unified memory support
let buffer = J2KAppleMemory.createBuffer(
    size: imageSize,
    options: [.unifiedMemory, .simdAligned]
)
```

#### Memory-Mapped I/O

For large files, use memory mapping:

```swift
// Read large file efficiently
let data = try J2KAppleMemory.readMemoryMapped(
    path: imagePath,
    options: [.nocache]
)
```

#### Large Page Support

Enable large pages for better TLB efficiency:

```swift
let buffer = try J2KAppleMemory.allocateLargePageBuffer(size: largeSize)
```

### 4. Pipeline Optimization

#### CPU/GPU Work Overlap

Maximize throughput by overlapping CPU and GPU work:

```swift
let optimizer = J2KPerformanceOptimizer()
await optimizer.configureForHighPerformance()

let params = await optimizer.currentParameters()
XCTAssertTrue(params.enableOverlap) // CPU/GPU overlap enabled
```

#### Batch Processing

Process multiple images efficiently:

```swift
let batchSize = await optimizer.optimalBatchSize(
    itemCount: imageCount,
    itemSize: imageSize
)

// Process in optimal batches
for batch in stride(from: 0, to: imageCount, by: batchSize) {
    let batchImages = images[batch..<min(batch + batchSize, imageCount)]
    // Process batch...
}
```

#### Thread Pool Sizing

Optimize CPU thread usage:

```swift
let threadCount = await optimizer.optimalThreadCount(operationType: "DWT")

// Use optimal thread count for parallel operations
```

### 5. Power Efficiency

Optimize for battery life on mobile devices:

#### Low Power Mode

```swift
let optimizer = J2KPerformanceOptimizer(mode: .lowPower)
await optimizer.configureForLowPower()
```

#### Thermal Management

Monitor and respond to thermal state:

```swift
import J2KCore

let platform = J2KApplePlatform()

// Monitor thermal state
let thermalState = await platform.thermalState()

switch thermalState {
case .nominal:
    // Full performance
    await optimizer.configureForHighPerformance()
    
case .fair, .serious:
    // Reduce load
    await optimizer.configureForLowPower()
    
case .critical:
    // Minimal processing
    break
}
```

#### Quality of Service

Use appropriate QoS classes:

```swift
// Background processing
let qos = DispatchQoS.QoSClass.utility

DispatchQueue.global(qos: qos).async {
    // Encode images in background
}

// Interactive encoding
let qos = DispatchQoS.QoSClass.userInitiated

DispatchQueue.global(qos: qos).async {
    // Encode for immediate display
}
```

## Performance Benchmarks

### 4K Image (3840×2160)

Typical performance on M1 Max:

```
Encoding:     0.045s (443 MB/s)
Decoding:     0.032s (622 MB/s)
Compression:  12.5:1
Total:        532 MB/s
```

### 8K Image (7680×4320)

Typical performance on M1 Max:

```
Encoding:     0.178s (447 MB/s)
Decoding:     0.125s (636 MB/s)
Compression:  12.3:1
Total:        541 MB/s
```

### Multi-Spectral (8 components, 2048×2048, 12-bit)

```
Encoding:     0.089s (356 MB/s)
Decoding:     0.062s (511 MB/s)
Compression:  8.2:1
Total:        433 MB/s
```

## Platform-Specific Recommendations

### M1 Family (M1, M1 Pro, M1 Max, M1 Ultra)

- **GPU cores**: 7-64 cores
- **Optimal threadgroup size**: 256-512 threads
- **Memory bandwidth**: 200-800 GB/s
- **Recommended batch size**: 4-8 images

```swift
let config = J2KMetalPerformance.Configuration(
    targetThreadsPerThreadgroup: 256,
    enableAsyncCompute: true,
    minBatchSize: 4
)
```

### M2 Family (M2, M2 Pro, M2 Max, M2 Ultra)

- **GPU cores**: 8-76 cores
- **Optimal threadgroup size**: 256-512 threads
- **Memory bandwidth**: 200-800 GB/s
- **Recommended batch size**: 4-8 images

Similar configuration to M1 family.

### M3 Family (M3, M3 Pro, M3 Max)

- **GPU cores**: 10-40 cores
- **Dynamic caching** improves GPU utilization
- **Mesh shading** available (not currently used)
- **Recommended batch size**: 2-4 images (smaller due to dynamic caching)

```swift
let config = J2KMetalPerformance.Configuration(
    targetThreadsPerThreadgroup: 512,
    enableAsyncCompute: true,
    minBatchSize: 2
)
```

### M4 Family (M4, M4 Pro, M4 Max)

- **GPU cores**: 10-40 cores
- **Enhanced ray tracing** (not currently used)
- **Improved power efficiency**
- **Recommended batch size**: 2-4 images

Similar configuration to M3 family.

## Profiling and Debugging

### Enable Profiling

```swift
let optimizer = J2KPerformanceOptimizer()

// Profile encoding
let (result, profile) = try await optimizer.optimizeEncodingPipeline {
    try encoder.encode(image)
}

// Analyze profile
print("Total time: \(profile.totalTime)s")
print("CPU time: \(profile.cpuTime)s (\(profile.cpuUtilization)%)")
print("GPU time: \(profile.gpuTime)s (\(profile.gpuUtilization)%)")
print("Memory: \(profile.peakMemoryUsage / 1024 / 1024) MB")
print("Sync points: \(profile.syncPoints)")
print("Throughput: \(profile.throughputMBps) MB/s")
print("Efficiency: \(profile.pipelineEfficiency)%")
```

### Metal Performance Tracking

```swift
let metalPerf = J2KMetalPerformance(device: device)
await metalPerf.startSession()

// Record kernel launches
await metalPerf.recordKernelLaunch(
    name: "DWT",
    duration: 0.002,
    threadgroupSize: 256,
    batched: true,
    async: true
)

// Get metrics
let metrics = await metalPerf.endSession()
print("Total launches: \(metrics.totalLaunches)")
print("GPU time: \(metrics.totalGPUTime)s")
print("GPU utilization: \(metrics.gpuUtilization * 100)%")
print("Bandwidth: \(metrics.bandwidthUtilization * 100)%")
print("Async compute: \(metrics.asyncComputeUsage)%")
```

### Accelerate Performance Tracking

```swift
let accelPerf = J2KAcceleratePerformance()
await accelPerf.startSession()

// Record operations
await accelPerf.recordOperation(
    type: "vDSP",
    duration: 0.001,
    dataSize: 1024 * 1024,
    inPlace: true
)

// Get metrics
let metrics = await accelPerf.endSession()
print("vDSP ops: \(metrics.totalVDSPOperations)")
print("NEON ops: \(metrics.totalNEONOperations)")
print("AMX ops: \(metrics.totalAMXOperations)")
print("Speedup: \(metrics.averageSpeedup)×")
print("Memory saved: \(metrics.memorySaved / 1024 / 1024) MB")
```

## Troubleshooting

### Low GPU Utilization

If GPU utilization is low:

1. **Check data size**: GPU is most efficient for large datasets (>1 MB)
2. **Enable batching**: Process multiple operations together
3. **Reduce synchronization**: Minimize CPU/GPU sync points
4. **Use async compute**: Enable parallel GPU operations

```swift
// Check if GPU should be used
let shouldUse = await optimizer.shouldUseGPU(
    dataSize: data.count,
    operationType: "DWT"
)

if !shouldUse {
    print("Data too small for GPU, using CPU")
}
```

### High Memory Usage

If memory usage is high:

1. **Enable in-place operations**: Reduce memory allocations
2. **Use memory mapping**: For large files
3. **Batch processing**: Process in smaller chunks
4. **Release intermediate buffers**: Explicitly deallocate

```swift
// Check memory
let hasSufficient = await optimizer.hasSufficientMemory(requiredSize)

// Use recommended strategy
let strategy = await optimizer.recommendedAllocationStrategy(dataSize: size)
```

### Thermal Throttling

If experiencing thermal throttling:

1. **Monitor thermal state**: Check `J2KApplePlatform.thermalState()`
2. **Reduce batch size**: Process fewer items at once
3. **Lower QoS**: Use `.utility` instead of `.userInitiated`
4. **Enable thermal mode**: Use `.thermalConstrained` optimization

```swift
let platform = J2KApplePlatform()
let state = await platform.thermalState()

if state == .critical {
    await optimizer.configure(with: .lowPower)
}
```

## Best Practices

1. **Profile first**: Measure before optimizing
2. **Use appropriate mode**: Choose optimization mode for your use case
3. **Batch when possible**: Process multiple items together
4. **Monitor resources**: Track CPU, GPU, memory, and thermal state
5. **Test on target hardware**: Performance varies across Apple Silicon generations
6. **Consider power**: Balance performance with battery life on mobile

## See Also

- [METAL_PERFORMANCE.md](METAL_PERFORMANCE.md) - Metal-specific optimization
- [APPLE_OPTIMIZATIONS.md](APPLE_OPTIMIZATIONS.md) - Apple platform features
- [ACCELERATE_ADVANCED.md](ACCELERATE_ADVANCED.md) - Advanced Accelerate usage
