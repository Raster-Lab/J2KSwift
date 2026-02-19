# Metal Performance Optimization Guide

This document provides detailed guidance on optimizing Metal GPU performance in J2KSwift for maximum throughput and efficiency.

## Overview

Metal GPU acceleration in J2KSwift provides significant performance improvements for:
- **Discrete Wavelet Transform (DWT)**: 5-15× faster than CPU
- **Multi-Component Transform (MCT)**: 10-25× faster than CPU
- **Color Transforms**: 8-20× faster than CPU
- **ROI Processing**: 12-30× faster than CPU
- **Quantization**: 6-18× faster than CPU

This guide covers:
- Kernel optimization strategies
- Memory bandwidth optimization
- Threadgroup sizing
- Async compute utilization
- Performance profiling

## Quick Start

### Basic Metal Usage

```swift
import J2KMetal

// Create Metal device
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal not available")
}

// Create performance optimizer
let metalPerf = J2KMetalPerformance(device: device)

// Configure for throughput
await metalPerf.optimizeForThroughput()

// Get optimal configuration
let config = await metalPerf.currentConfiguration()
print("Target threadgroup size: \(config.targetThreadsPerThreadgroup)")
print("Async compute: \(config.enableAsyncCompute)")
```

### Performance Tracking

```swift
// Start profiling session
await metalPerf.startSession()

// Record kernel launches during operations
await metalPerf.recordKernelLaunch(
    name: "DWT_5_3_Forward",
    duration: 0.002,
    threadgroupSize: 256,
    batched: true,
    async: true
)

// Get performance metrics
let metrics = await metalPerf.endSession()
print("GPU utilization: \(metrics.gpuUtilization * 100)%")
print("Bandwidth utilization: \(metrics.bandwidthUtilization * 100)%")
```

## Kernel Optimization

### 1. Minimize Kernel Launches

Kernel launch overhead is ~10-20 microseconds per launch. Minimize launches by:

#### Batching Operations

```swift
// Bad: Separate launches for each operation
for tile in tiles {
    launchKernel(tile)  // Multiple launches
}

// Good: Batch tiles together
let batchSize = await metalPerf.optimalBatchSize(tiles.count)
for batch in stride(from: 0, to: tiles.count, by: batchSize) {
    let batchTiles = tiles[batch..<min(batch + batchSize, tiles.count)]
    launchKernel(batchTiles)  // Single launch for batch
}
```

#### Kernel Fusion

Combine multiple operations into a single kernel:

```metal
// Bad: Separate kernels
kernel void colorTransform(...) { /* ... */ }
kernel void waveletTransform(...) { /* ... */ }

// Good: Fused kernel
kernel void colorAndWaveletTransform(...) {
    // Color transform
    float3 yCbCr = rgbToYCbCr(rgb);
    
    // Wavelet transform
    float transformed = waveletStep(yCbCr);
    
    // Write result
    output[gid] = transformed;
}
```

### 2. Optimize Threadgroup Size

Choose threadgroup size based on workload:

#### 1D Workloads

```swift
let threadgroupSize = await metalPerf.optimalThreadgroupSize(
    workloadSize: arraySize,
    memoryPerThread: 16  // bytes
)

// Typical sizes: 256-512 for most operations
encoder.dispatchThreads(
    MTLSize(width: arraySize, height: 1, depth: 1),
    threadsPerThreadgroup: MTLSize(width: threadgroupSize, height: 1, depth: 1)
)
```

#### 2D Workloads (Images)

```swift
let (width, height) = await metalPerf.optimalThreadgroupSize2D(
    width: imageWidth,
    height: imageHeight
)

// Typical: 16×16 or 32×32 for image operations
encoder.dispatchThreads(
    MTLSize(width: imageWidth, height: imageHeight, depth: 1),
    threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
)
```

### 3. Optimize Shader Occupancy

Maximize GPU utilization by optimizing occupancy:

#### Reduce Register Pressure

```metal
// Bad: High register usage
kernel void processPixel(
    device float4* input [[buffer(0)]],
    device float4* output [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    // Many intermediate variables = more registers
    float4 temp1 = input[gid];
    float4 temp2 = transform1(temp1);
    float4 temp3 = transform2(temp2);
    float4 temp4 = transform3(temp3);
    float4 temp5 = transform4(temp4);
    output[gid] = temp5;
}

// Good: Reuse variables
kernel void processPixel(
    device float4* input [[buffer(0)]],
    device float4* output [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    float4 value = input[gid];
    value = transform1(value);
    value = transform2(value);
    value = transform3(value);
    value = transform4(value);
    output[gid] = value;
}
```

#### Use Threadgroup Memory Efficiently

```metal
kernel void efficientShared(
    device float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    threadgroup float* shared [[threadgroup(0)]],
    uint tid [[thread_position_in_threadgroup]],
    uint gid [[thread_position_in_grid]]
) {
    // Load to shared memory
    shared[tid] = input[gid];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    
    // Process using shared memory
    float result = process(shared, tid);
    
    // Write result
    output[gid] = result;
}
```

## Memory Bandwidth Optimization

### 1. Coalesce Memory Accesses

Access memory in a coalesced pattern for maximum bandwidth:

```metal
// Bad: Strided access
kernel void stridedAccess(
    device float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    uint gid [[thread_position_in_grid]],
    constant uint& stride [[buffer(2)]]
) {
    output[gid] = input[gid * stride];  // Poor cache utilization
}

// Good: Sequential access
kernel void sequentialAccess(
    device float* input [[buffer(0)]],
    device float* output [[buffer(1)]],
    uint gid [[thread_position_in_grid]]
) {
    output[gid] = input[gid];  // Cache-friendly
}
```

### 2. Optimize Memory Access Patterns

```swift
let (pattern, batchSize) = await metalPerf.optimalMemoryAccess(
    dataSize: imageSize,
    stride: pixelStride,
    accessPattern: "sequential"
)

print("Recommended pattern: \(pattern)")
print("Batch size: \(batchSize)")
```

### 3. Use Appropriate Buffer Types

```swift
// Shared storage: CPU and GPU both access
let sharedBuffer = device.makeBuffer(
    length: size,
    options: .storageModeShared
)

// Managed storage: Explicit synchronization
let managedBuffer = device.makeBuffer(
    length: size,
    options: .storageModeManaged
)

// Private storage: GPU-only (fastest)
let privateBuffer = device.makeBuffer(
    length: size,
    options: .storageModePrivate
)
```

### 4. Estimate and Monitor Bandwidth

```swift
let bytesRead = imageSize * 4  // RGBA float
let bytesWritten = imageSize * 4
let duration = 0.01  // 10ms

let utilization = await metalPerf.estimateBandwidthUtilization(
    bytesRead: bytesRead,
    bytesWritten: bytesWritten,
    duration: duration
)

print("Bandwidth utilization: \(utilization * 100)%")

// Typical Apple Silicon bandwidth:
// M1:      200-400 GB/s
// M1 Max:  400 GB/s
// M2 Max:  400 GB/s
// M3 Max:  300-400 GB/s (with dynamic caching)
```

## Async Compute Optimization

### 1. Enable Async Compute

Use async compute for parallel GPU execution:

```swift
let config = J2KMetalPerformance.Configuration(
    enableAsyncCompute: true
)
let metalPerf = J2KMetalPerformance(device: device, configuration: config)

// Check support
let supportsAsync = await metalPerf.supportsAsyncCompute()
print("Async compute: \(supportsAsync)")
```

### 2. Independent Operations

Launch independent operations in parallel:

```metal
// DWT kernel (compute-bound)
kernel void waveletTransform(...) { /* ... */ }

// Color transform kernel (memory-bound)
kernel void colorTransform(...) { /* ... */ }
```

```swift
// Launch both kernels
let commandBuffer = commandQueue.makeCommandBuffer()!

// First encoder: DWT (uses compute units)
let encoder1 = commandBuffer.makeComputeCommandEncoder()!
encoder1.setComputePipelineState(dwtPipeline)
// ... dispatch DWT
encoder1.endEncoding()

// Second encoder: Color transform (uses memory bandwidth)
let encoder2 = commandBuffer.makeComputeCommandEncoder()!
encoder2.setComputePipelineState(colorPipeline)
// ... dispatch color transform
encoder2.endEncoding()

commandBuffer.commit()  // Both execute in parallel
```

### 3. Track Async Usage

```swift
await metalPerf.startSession()

await metalPerf.recordKernelLaunch(
    name: "DWT",
    duration: 0.003,
    async: true
)

await metalPerf.recordKernelLaunch(
    name: "ColorTransform",
    duration: 0.002,
    async: true
)

let metrics = await metalPerf.endSession()
print("Async compute usage: \(metrics.asyncComputeUsage)%")
```

## Device-Specific Optimization

### M1 Family

```swift
// M1 characteristics
let (maxThreadgroups, maxThreadsPerThreadgroup, recommended) =
    await metalPerf.deviceCharacteristics()

// M1 typically:
// - 7-64 GPU cores
// - Max 1024 threads per threadgroup
// - Recommended: 256 threadgroups

let config = J2KMetalPerformance.Configuration(
    maxThreadgroupSize: 1024,
    targetThreadsPerThreadgroup: 256,
    minBatchSize: 4
)
```

### M2 Family

Similar to M1, with slight improvements in efficiency.

### M3 Family

```swift
// M3 with dynamic caching
let config = J2KMetalPerformance.Configuration(
    maxThreadgroupSize: 1024,
    targetThreadsPerThreadgroup: 512,  // Can use more threads
    minBatchSize: 2,  // Smaller batches due to caching
    maxBandwidthUtilization: 0.9  // Higher utilization possible
)
```

### M4 Family

Similar to M3, with enhanced efficiency.

## Performance Profiling

### Detailed Metrics

```swift
await metalPerf.startSession()

// Perform operations...
for i in 0..<10 {
    await metalPerf.recordKernelLaunch(
        name: "DWT_\(i)",
        duration: 0.002,
        threadgroupSize: 256,
        batched: i % 4 == 0,
        async: true
    )
}

let metrics = await metalPerf.endSession()

print("Performance Metrics:")
print("  Total launches:    \(metrics.totalLaunches)")
print("  GPU time:          \(metrics.totalGPUTime)s")
print("  Avg overhead:      \(metrics.averageLaunchOverhead * 1000)μs")
print("  GPU utilization:   \(metrics.gpuUtilization * 100)%")
print("  Bandwidth:         \(metrics.bandwidthUtilization * 100)%")
print("  Batched launches:  \(metrics.batchedLaunches)")
print("  Async compute:     \(metrics.asyncComputeUsage)%")
```

### Kernel Launch Overhead

```swift
let overhead = await metalPerf.estimatedLaunchOverhead()
print("Estimated launch overhead: \(overhead * 1_000_000)μs")

// Minimize overhead by batching
let shouldBatch = await metalPerf.shouldBatchLaunches(launchCount: 10)
if shouldBatch {
    // Batch these launches together
}
```

## Advanced Techniques

### 1. Pipeline State Caching

Cache compiled pipeline states:

```swift
import J2KMetal

let shaderLib = await J2KMetalShaderLibrary(device: device)

// Get cached pipeline
let pipeline = try await shaderLib.pipelineState(
    for: .dwtCDF97HorizontalForward
)
```

### 2. Buffer Pooling

Reuse buffers to reduce allocation overhead:

```swift
let bufferPool = await J2KMetalBufferPool(device: device)

// Get buffer from pool
let buffer = try await bufferPool.acquireBuffer(
    size: imageSize * 4,
    options: .storageModePrivate
)

// Use buffer...

// Return to pool
await bufferPool.releaseBuffer(buffer)
```

### 3. Multi-Pass Optimization

Minimize render target switches:

```swift
// Bad: Multiple command buffers
for operation in operations {
    let cmdBuffer = queue.makeCommandBuffer()!
    // ... encode operation
    cmdBuffer.commit()
    cmdBuffer.waitUntilCompleted()  // Synchronous!
}

// Good: Single command buffer
let cmdBuffer = queue.makeCommandBuffer()!
for operation in operations {
    // ... encode all operations
}
cmdBuffer.commit()
// Optionally wait at the end
```

## Troubleshooting

### Low GPU Utilization

If GPU utilization is below 50%:

1. **Increase batch size**: Process more data per kernel launch
2. **Use async compute**: Launch multiple kernels in parallel
3. **Reduce synchronization**: Minimize CPU/GPU sync points
4. **Check kernel complexity**: Ensure kernels have sufficient work

### High Memory Bandwidth

If bandwidth utilization is consistently above 90%:

1. **Reduce memory accesses**: Use shared memory or registers
2. **Improve access patterns**: Ensure coalesced access
3. **Use smaller data types**: Consider float16 instead of float32
4. **Compress intermediate data**: Reduce data movement

### Kernel Launch Overhead

If overhead is significant:

1. **Batch operations**: Combine multiple small launches
2. **Use larger threadgroups**: Process more data per launch
3. **Fuse kernels**: Combine operations into single kernel

## Best Practices

1. **Profile first**: Measure before optimizing
2. **Batch aggressively**: Combine operations when possible
3. **Minimize synchronization**: Avoid CPU/GPU barriers
4. **Use async compute**: Leverage parallel execution
5. **Optimize memory access**: Ensure coalesced patterns
6. **Cache pipeline states**: Avoid recompilation
7. **Pool buffers**: Reuse allocations
8. **Monitor metrics**: Track GPU utilization and bandwidth

## Performance Targets

Target metrics for well-optimized code:

- **GPU utilization**: >70%
- **Bandwidth utilization**: 60-85%
- **Async compute usage**: >50% (when applicable)
- **Launch overhead**: <5% of total GPU time
- **Kernel efficiency**: >80%

## See Also

- [PERFORMANCE_APPLE_SILICON.md](PERFORMANCE_APPLE_SILICON.md) - Overall performance guide
- [METAL_DWT.md](METAL_DWT.md) - DWT-specific Metal optimization
- [METAL_COLOR_MCT.md](METAL_COLOR_MCT.md) - Color/MCT Metal optimization
- [METAL_ROI_QUANTIZATION.md](METAL_ROI_QUANTIZATION.md) - ROI/Quantization optimization
