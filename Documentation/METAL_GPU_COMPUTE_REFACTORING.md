# Metal GPU Compute Refactoring

**Week 247-249 — Sub-phase 17b**

## Overview

This document describes the Metal GPU compute refactoring that optimises the JPEG 2000 shader pipeline for Apple GPUs. The refactoring introduces bit-depth-specific shader variants, tile-based dispatch for large images, indirect command buffers for adaptive workloads, async compute pipelines, and comprehensive GPU profiling infrastructure.

## Architecture

### Shader Pipeline Manager

`J2KMetalShaderPipelineManager` is the primary actor that coordinates all refactored GPU compute operations. It builds on the existing `J2KMetalShaderLibrary` and `J2KMetalBufferPool` infrastructure.

```swift
let pipeline = J2KMetalShaderPipelineManager()
try await pipeline.initialize()
```

### Shader Variants by Bit Depth

The refactored pipeline provides specialised shader variants for each supported bit depth (8/12/16/32-bit), eliminating unnecessary type conversions at runtime.

```swift
let variant = await pipeline.shaderVariant(
    baseName: "j2k_dwt_forward_97_horizontal",
    bitDepth: .depth16
)
// variant.functionName == "j2k_dwt_forward_97_horizontal_16bit"
```

**Supported bit depths:**

| Bit Depth | Bytes/Sample | Use Case |
|-----------|-------------|----------|
| 8-bit | 1 | Standard images (sRGB, JPEG baseline) |
| 12-bit | 2 | Medical imaging (DICOM), cinema |
| 16-bit | 2 | HDR, scientific imaging |
| 32-bit | 4 | Floating-point processing |

### Tile-Based Dispatch

Large images are partitioned into tiles for GPU processing. This enables images larger than GPU memory to be processed, and allows overlapping CPU preparation with GPU execution.

```swift
let tiles = try await pipeline.computeTileGrid(
    imageWidth: 4096, imageHeight: 4096,
    config: .largeImage
)
```

**Configuration presets:**

- `default` — 256×256 tiles with 8px overlap, double-buffered, 4 concurrent tiles
- `largeImage` — 512×512 tiles with 16px overlap, 8 concurrent tiles
- `smallImage` — 1024×1024 tiles, no overlap, single tile

### Indirect Command Buffers

For adaptive workloads where tile sizes vary (e.g., image edges), indirect command buffers allow the GPU to record its own dispatch commands, reducing CPU overhead.

```swift
if await pipeline.supportsIndirectCommandBuffers() {
    let cmdCount = await pipeline.indirectCommandCount(for: tiles.count)
}
```

### Async Compute Pipeline

The async compute pipeline uses double-buffered (or triple-buffered) command submission so that the CPU prepares the next tile while the GPU processes the current one.

```swift
let config = J2KMetalAsyncComputeConfiguration.highThroughput
// inflightBufferCount: 3, multiQueue: true, timelineSync: true
```

**Features:**
- Double/triple-buffered command submission
- Multi-queue for independent operations
- Metal event-based timeline synchronisation
- Configurable compute priority (low/normal/high)

### Metal 3 Features

Metal 3 features are detected at runtime and used when available:

```swift
let features = J2KMetal3Features.detect()
if features.meshShaders { /* Use mesh shaders for adaptive tiling */ }
if features.functionPointers { /* Dynamic shader selection */ }
```

| Feature | Requirement | Use Case |
|---------|-------------|----------|
| Mesh Shaders | Apple GPU (M3+) | Adaptive tiling |
| Raytracing | Apple GPU (A14+/M1+) | Spatial ROI queries |
| Residency Sets | Apple GPU (M3+) | Resource management |
| Function Pointers | Apple GPU (A13+/M1+) | Dynamic shader selection |

## GPU Profiling

### Occupancy Analysis

The pipeline analyses shader occupancy to recommend optimal threadgroup sizes:

```swift
let analysis = await pipeline.analyseOccupancy(
    shaderName: "dwt_forward",
    threadgroupSize: 256,
    registersPerThread: 32,
    threadgroupMemory: 4096
)
// analysis.estimatedOccupancy, analysis.recommendedMaxThreads
```

### Bottleneck Detection

Kernels are classified as ALU-bound, bandwidth-bound, latency-bound, or balanced:

```swift
let bottleneck = await pipeline.analyseBottleneck(
    bytesRead: readBytes, bytesWritten: writeBytes,
    operations: aluOps, duration: kernelDuration
)
// bottleneck.bottleneck == .bandwidthBound
// bottleneck.recommendations == ["Reduce memory traffic..."]
```

### Threadgroup Memory Layout

Optimised threadgroup memory layouts avoid bank conflicts on Apple GPUs:

```swift
let layout = await pipeline.optimalThreadgroupMemoryLayout(
    tileWidth: 256, bitDepth: .depth32
)
// layout.avoidBankConflicts, layout.rowPadding
```

## Tile-Pipelined Encode

The pipelined encode overlaps CPU tile preparation with GPU tile processing:

```swift
let count = try await pipeline.tilePipelinedEncode(
    tiles: tiles,
    prepareTile: { tile in
        // CPU work: load and preprocess tile data
        return tileData
    },
    processTile: { tile, data in
        // GPU work: submit compute commands
    }
)
```

## Performance Benchmarking

### DWT Benchmark

```swift
let result = await pipeline.benchmarkDWT(dataSize: 1_000_000)
// result.cpuTime, result.gpuEstimate, result.speedup
```

### Bandwidth Estimation

```swift
let gbps = await pipeline.estimateBandwidth(
    tileCount: 64, tileSize: 262144, duration: 0.01
)
```

## Multi-GPU Support

On macOS systems with multiple GPUs (Mac Pro, Mac Studio with eGPU):

```swift
let devices = await pipeline.availableDevices()
// ["Apple M2 Max", "AMD Radeon Pro W6800X"]
```

## Key Types

| Type | Description |
|------|-------------|
| `J2KMetalBitDepth` | Supported bit depths (8/12/16/32) |
| `J2KMetalShaderVariant` | Shader variant for a specific bit depth |
| `J2KMetalTileDispatchConfiguration` | Tile dispatch settings |
| `J2KMetalTileDescriptor` | Single tile position and size |
| `J2KMetalIndirectCommandConfiguration` | Indirect command buffer settings |
| `J2KMetalAsyncComputeConfiguration` | Async compute pipeline settings |
| `J2KMetalComputePriority` | Queue priority (low/normal/high) |
| `J2KMetalProfilingEvent` | GPU profiling event |
| `J2KMetalOccupancyAnalysis` | Shader occupancy analysis |
| `J2KMetalThreadgroupMemoryLayout` | Threadgroup memory layout |
| `J2KMetalBottleneck` | Bottleneck classification |
| `J2KMetalBottleneckAnalysis` | Bottleneck analysis result |
| `J2KMetal3Features` | Metal 3 feature availability |
| `J2KMetalShaderPipelineManager` | Main pipeline actor |

## Testing

62 tests cover all functionality:

- Bit depth types and shader variants
- Tile dispatch configuration and grid computation
- Indirect command buffer support detection
- Async compute pipeline configuration
- GPU profiling and event recording
- Occupancy analysis and caching
- Threadgroup memory layout optimisation
- Bottleneck detection (ALU/bandwidth/latency/balanced)
- Metal 3 feature detection
- Tile-pipelined encode
- Multi-GPU enumeration
- Performance benchmarks

Run tests:
```bash
swift test --filter J2KMetalGPUComputeRefactoringTests
```
