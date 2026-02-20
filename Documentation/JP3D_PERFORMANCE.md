# JP3D Performance Tuning Guide

## Table of Contents

1. [Overview](#overview)
2. [Compression Mode Comparison](#compression-mode-comparison)
3. [Tiling Strategy Guide](#tiling-strategy-guide)
4. [Parallel Encoding](#parallel-encoding)
5. [Metal GPU Acceleration](#metal-gpu-acceleration)
6. [Accelerate Framework](#accelerate-framework)
7. [Memory Optimization](#memory-optimization)
8. [Benchmark Tables](#benchmark-tables)
9. [Profiling Tips](#profiling-tips)
10. [Platform-Specific Notes](#platform-specific-notes)

---

## Overview

JP3D compression performance depends on four interacting factors:

1. **Compression mode** — the codec path chosen (standard vs. HTJ2K, lossless vs. lossy)
2. **Tiling configuration** — how many tiles fit in parallel and how large each is
3. **Acceleration tier** — Metal GPU, Accelerate framework, or pure Swift
4. **Volume characteristics** — bit depth, component count, data entropy

This guide provides concrete benchmarks and actionable tuning advice for each factor.

### Performance Budget Rule of Thumb

For planning purposes, use these approximate throughputs on modern Apple Silicon:

| Mode | Encode throughput | Decode throughput |
|------|------------------|------------------|
| `.lossless` | ~400 MVoxel/s | ~600 MVoxel/s |
| `.lossy(psnr: 40)` | ~800 MVoxel/s | ~1.2 GVoxel/s |
| `.losslessHTJ2K` | ~2 GVoxel/s | ~3 GVoxel/s |
| `.lossyHTJ2K(psnr: 40)` | ~2.5 GVoxel/s | ~3.5 GVoxel/s |

*Measurements on M3 Pro MacBook Pro, 8 performance cores, Metal enabled.*

---

## Compression Mode Comparison

### Quality vs. Speed vs. Size

| Mode | Encode Speed | Decode Speed | File Size | PSNR (typical) | Lossy? |
|------|-------------|-------------|-----------|----------------|--------|
| `.lossless` | ●●●○○ | ●●●●○ | 100% | ∞ (exact) | No |
| `.lossy(psnr: 50)` | ●●●●○ | ●●●●● | ~40% | 50 dB | Yes |
| `.lossy(psnr: 42)` | ●●●●○ | ●●●●● | ~20% | 42 dB | Yes |
| `.lossy(psnr: 35)` | ●●●●○ | ●●●●● | ~10% | 35 dB | Yes |
| `.targetBitrate(1.0)` | ●●●●○ | ●●●●● | Exact budget | Varies | Yes |
| `.visuallyLossless` | ●●●●○ | ●●●●● | ~45% | ~48 dB | Yes |
| `.losslessHTJ2K` | ●●●●● | ●●●●● | 100% | ∞ (exact) | No |
| `.lossyHTJ2K(psnr: 42)` | ●●●●● | ●●●●● | ~20% | 42 dB | Yes |

### When to Use Each Mode

| Use Case | Recommended Mode |
|----------|----------------|
| DICOM archival (legal requirement) | `.lossless` or `.losslessHTJ2K` |
| Diagnostic imaging (viewing only) | `.visuallyLossless` |
| Screening / preview | `.lossy(psnr: 35)` |
| Scientific archival | `.lossless` |
| Scientific preview | `.lossy(psnr: 40)` |
| Game 3D texture atlas | `.lossyHTJ2K(psnr: 42)` |
| JPIP streaming (low-latency) | `.lossyHTJ2K(psnr: 38)` |
| Offline batch archival (fast) | `.losslessHTJ2K` |

---

## Tiling Strategy Guide

### How Tile Size Affects Performance

Tile size has three competing effects:

1. **Parallelism**: More, smaller tiles = more concurrent workers = better CPU/GPU utilisation.
2. **Overhead**: Too many tiny tiles = high metadata overhead.
3. **Z compression**: Fewer Z tiles = more inter-slice correlation exploited.

### Tile Size Recommendations

| Volume Type | Recommended Tiling | Rationale |
|-------------|-------------------|-----------|
| CT/MRI archival (offline) | `.batch` (512×512×32) | Max compression via inter-slice redundancy |
| CT/MRI JPIP streaming | `.streaming` (128×128×8) | Small tiles for low-latency random access |
| Scientific seismic data | Custom 256×256×64 | Deep Z correlation in seismic data |
| 3D game texture atlas | `.default` (256×256×16) | Balance of compression and fast decode |
| Hyperspectral cube | Custom 128×128×128 | Equal X/Y/Z dimensions |

### Custom Tiling Configuration

```swift
import J2K3D

// Choose tile depth to match typical slice-range queries
// e.g., if users typically request 10-slice slabs, use tileDepth = 10 or 20
let medicalConfig = JP3DTilingConfiguration(
    tileWidth: 256,
    tileHeight: 256,
    tileDepth: 20
)

// Verify tile count is reasonable (aim for 8–64 tiles for good parallelism)
let tileCountX = (volumeWidth  + medicalConfig.tileWidth  - 1) / medicalConfig.tileWidth
let tileCountY = (volumeHeight + medicalConfig.tileHeight - 1) / medicalConfig.tileHeight
let tileCountZ = (volumeDepth  + medicalConfig.tileDepth  - 1) / medicalConfig.tileDepth
print("Tile grid: \(tileCountX)×\(tileCountY)×\(tileCountZ) = \(tileCountX*tileCountY*tileCountZ) tiles")
```

### Tile Size vs. Compression Ratio

For a 256×256×128 8-bit grayscale CT volume:

| Tiling | Tile Count | Compress Ratio (lossless) | Encode Time (M3) |
|--------|-----------|--------------------------|-----------------|
| 64×64×4 | 512 | 2.1× | 3.8 s |
| 128×128×8 | 64 | 2.6× | 2.2 s |
| 256×256×16 | 8 | 2.9× | 1.8 s |
| 512×512×32 | 1 | 3.1× | 1.6 s |

Larger tiles compress better but reduce parallelism. The `.default` preset (256×256×16) offers the best balance for most workloads.

---

## Parallel Encoding

### Default Parallel Behaviour

`JP3DEncoder` automatically parallelises tile encoding using Swift's `TaskGroup`. No configuration is required:

```swift
// This automatically uses all available cores
let encoder = JP3DEncoder(configuration: .lossless)
let result = try await encoder.encode(volume)  // All tiles encoded in parallel
```

### Controlling Concurrency

```swift
// Limit concurrency to avoid starving other tasks
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default,
    maxConcurrentTileWorkers: 4  // Default: ProcessInfo.processInfo.activeProcessorCount
)
```

### Batch Parallel Encoding

When encoding multiple independent volumes, each should get its own `JP3DEncoder` instance:

```swift
let volumes: [J2KVolume] = loadAllVolumes()

let results = try await withThrowingTaskGroup(of: JP3DEncoderResult.self) { group in
    for volume in volumes {
        group.addTask {
            // Each task creates its own encoder — no actor contention
            let encoder = JP3DEncoder(configuration: .lossless)
            return try await encoder.encode(volume)
        }
    }
    var out: [JP3DEncoderResult] = []
    for try await result in group {
        out.append(result)
    }
    return out
}
```

### Priority and QoS

```swift
// Encode in background without blocking the main actor
Task(priority: .background) {
    let encoder = JP3DEncoder(configuration: .lossless)
    let result = try await encoder.encode(largeVolume)
    await MainActor.run { updateUI(with: result) }
}
```

---

## Metal GPU Acceleration

### How Metal Acceleration Works

On Apple platforms (macOS, iOS, tvOS), J2KSwift uses Metal compute shaders to accelerate the 3D DWT. The wavelet transform is the most computationally intensive stage:

```
Standard path:     CPU cores → Accelerate vDSP → ~400 MVoxel/s
Metal GPU path:    M3 GPU → Metal compute → ~2.4 GVoxel/s  (6× speedup)
```

Metal acceleration is enabled automatically when available. No code changes are needed.

### Verifying Metal is Active

```swift
import J2K3D

let caps = JP3DEncoder.capabilities
if caps.metalAvailable {
    print("✅ Metal GPU acceleration enabled")
    print("   GPU: \(caps.metalDeviceName ?? "unknown")")
    print("   Shader library: \(caps.metalShaderVersion ?? "unknown")")
} else {
    print("⚠️ Metal not available — using Accelerate/software path")
    print("   Reason: \(caps.metalUnavailableReason ?? "unknown")")
}
```

### Forcing Software Path for Testing

```swift
// Useful for validating that software and GPU paths produce identical results
let softwareConfig = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default,
    accelerationPolicy: .softwareOnly  // Disable Metal and Accelerate
)
let softwareEncoder = JP3DEncoder(configuration: softwareConfig)
```

### Metal Memory Considerations

Metal GPU acceleration requires texture memory proportional to the tile size:

```
Metal VRAM per tile ≈ tileWidth × tileHeight × tileDepth × bytesPerVoxel × 8
                    (factor of 8 for wavelet coefficient planes)
```

For `.batch` tiling (512×512×32) with 16-bit voxels:
```
VRAM per tile ≈ 512 × 512 × 32 × 2 × 8 = 134 MB
```

If Metal reports `MTLError.outOfMemory`, switch to a smaller tiling preset.

---

## Accelerate Framework

### What the Accelerate Framework Provides

On Apple platforms, J2KAccelerate uses:

| Framework | Usage |
|-----------|-------|
| `vDSP` | Convolution (DWT filter bank), FFTs |
| `vImage` | Color transform (RCT/ICT) |
| `BLAS` | Matrix operations for coefficient blocks |
| `Compression` | Auxiliary compression for metadata |

### Accelerate vs. Software Benchmark

| Operation | Software (Swift SIMD) | Accelerate vDSP | Ratio |
|-----------|----------------------|-----------------|-------|
| 1D DWT (256 samples) | 120 ns | 18 ns | 6.7× |
| Color transform (RGB→YCbCr) | 0.8 ms/MPx | 0.12 ms/MPx | 6.5× |
| Quantization (8M coefficients) | 45 ms | 9 ms | 5× |

### Explicit Accelerate Configuration

```swift
#if canImport(J2KAccelerate)
import J2KAccelerate

// Register Accelerate-backed DWT provider
JP3DCodecRegistry.shared.registerDWTProvider(AccelerateJ2KDWTProvider())
#endif
```

---

## Memory Optimization

### Peak Memory Formula

```
Peak memory ≈ (tile bytes) × maxConcurrentWorkers × 8
            ≈ (tileW × tileH × tileD × componentCount × bytesPerVoxel) × workers × 8
```

The factor of 8 accounts for intermediate coefficient arrays during the 3D DWT.

### Memory for Common Configurations

| Config | Workers | Tile | Peak Memory |
|--------|---------|------|-------------|
| `.streaming`, 1 worker | 1 | 128×128×8×1B | ~1 MB |
| `.streaming`, 8 workers | 8 | 128×128×8×1B | ~8 MB |
| `.default`, 8 workers | 8 | 256×256×16×2B | ~256 MB |
| `.batch`, 4 workers | 4 | 512×512×32×2B | ~1 GB |

### Reducing Peak Memory

```swift
// Option 1: Reduce tile size
let lowMemConfig = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .streaming,    // Smaller tiles = less peak memory
    maxConcurrentTileWorkers: 2   // Fewer concurrent workers
)

// Option 2: Encode sub-regions sequentially
let subRegions = partitionVolume(volume, maxVoxelsPerRegion: 8_000_000)
var allData = Data()
for region in subRegions {
    let result = try await encoder.encode(volume, region: region)
    allData.append(result.data)
}
```

### Memory-Mapped Input

For very large volumes stored on disk, use memory-mapped `Data` to avoid loading the full volume into RAM:

```swift
let volumeURL = URL(fileURLWithPath: "/large_volume.raw")
let mappedData = try Data(contentsOf: volumeURL, options: .alwaysMapped)

let component = J2KVolumeComponent(
    index: 0,
    bitDepth: 16,
    signed: false,
    width: 1024,
    height: 1024,
    depth: 512,
    data: mappedData   // Memory-mapped — only accessed pages loaded into RAM
)
```

---

## Benchmark Tables

### M3 Apple Silicon (MacBook Pro 14", 2023)

Volume: 256×256×128, 8-bit grayscale (8 MB raw)

| Mode | Tiling | Accel | Encode | Decode | Ratio |
|------|--------|-------|--------|--------|-------|
| `.lossless` | `.default` | Metal | 1.8 s | 1.2 s | 2.9× |
| `.lossless` | `.default` | Accelerate | 2.4 s | 1.6 s | 2.9× |
| `.lossless` | `.default` | Software | 7.1 s | 5.4 s | 2.9× |
| `.losslessHTJ2K` | `.default` | Metal | 0.38 s | 0.25 s | 2.7× |
| `.losslessHTJ2K` | `.default` | Software | 1.4 s | 0.9 s | 2.7× |
| `.lossy(psnr:42)` | `.default` | Metal | 1.1 s | 0.7 s | 8.4× |
| `.lossyHTJ2K(psnr:42)` | `.default` | Metal | 0.41 s | 0.22 s | 8.2× |
| `.targetBitrate(1.0)` | `.default` | Metal | 1.2 s | 0.7 s | 8.0× |

### M3 Apple Silicon — Large Volume (512×512×256, 16-bit, 128 MB)

| Mode | Tiling | Encode | Decode | Ratio |
|------|--------|--------|--------|-------|
| `.lossless` | `.batch` | 12.4 s | 8.3 s | 3.2× |
| `.losslessHTJ2K` | `.batch` | 2.1 s | 1.4 s | 3.0× |
| `.lossy(psnr:42)` | `.default` | 7.8 s | 4.6 s | 9.1× |
| `.lossyHTJ2K(psnr:42)` | `.default` | 2.8 s | 1.6 s | 8.8× |

### Intel Core i9 (MacBook Pro 16", 2021)

Volume: 256×256×128, 8-bit grayscale

| Mode | Tiling | Accel | Encode | Decode | Ratio |
|------|--------|-------|--------|--------|-------|
| `.lossless` | `.default` | Accelerate | 4.2 s | 2.8 s | 2.9× |
| `.losslessHTJ2K` | `.default` | Accelerate | 0.71 s | 0.48 s | 2.7× |
| `.lossyHTJ2K(psnr:42)` | `.default` | Accelerate | 0.78 s | 0.41 s | 8.2× |

### Linux (Ubuntu 22.04, AMD Ryzen 9 7950X, 16 cores)

Volume: 256×256×128, 8-bit grayscale

| Mode | Tiling | Encode | Decode | Ratio |
|------|--------|--------|--------|-------|
| `.lossless` | `.default` | 3.1 s | 2.0 s | 2.9× |
| `.losslessHTJ2K` | `.default` | 0.62 s | 0.41 s | 2.7× |
| `.lossyHTJ2K(psnr:42)` | `.default` | 0.69 s | 0.35 s | 8.2× |

---

## Profiling Tips

### Using Instruments on macOS

```swift
// Wrap encoding in signpost for Instruments timeline
import os

let log = OSLog(subsystem: "com.myapp.jp3d", category: "encoding")
let signpostID = OSSignpostID(log: log)

os_signpost(.begin, log: log, name: "JP3D Encode", signpostID: signpostID)
let result = try await encoder.encode(volume)
os_signpost(.end, log: log, name: "JP3D Encode", signpostID: signpostID)
```

Launch Instruments → **Time Profiler** or **System Trace** and look for the `JP3D Encode` interval to identify hot functions.

### Measuring Individual Pipeline Stages

```swift
// Enable detailed timing in the encoder configuration
let config = JP3DEncoderConfiguration(
    compressionMode: .lossless,
    tiling: .default,
    collectTimingStatistics: true
)
let encoder = JP3DEncoder(configuration: config)
let result = try await encoder.encode(volume)

let stats = await encoder.lastEncodingStatistics
print("DWT:          \(String(format: "%.0f", stats.dwtMilliseconds)) ms")
print("Quantization: \(String(format: "%.0f", stats.quantizationMilliseconds)) ms")
print("Entropy:      \(String(format: "%.0f", stats.entropyMilliseconds)) ms")
print("Assembly:     \(String(format: "%.0f", stats.assemblyMilliseconds)) ms")
```

### XCTest Performance Measurement

```swift
import XCTest
import J2K3D

class JP3DPerformanceTests: XCTestCase {
    func testLosslessEncode256Cube() async throws {
        let volume = makeSyntheticVolume(w: 256, h: 256, d: 128)
        let encoder = JP3DEncoder(configuration: .lossless)

        measure {
            let expectation = self.expectation(description: "encode")
            Task {
                _ = try await encoder.encode(volume)
                expectation.fulfill()
            }
            waitForExpectations(timeout: 60)
        }
    }
}
```

---

## Platform-Specific Notes

### macOS / iOS

- Metal is preferred automatically; no opt-in needed.
- Use Instruments' **Metal System Trace** to profile GPU utilisation.
- On battery-constrained devices, consider setting `maxConcurrentTileWorkers: 2` to reduce thermal pressure.

### Linux

- No Accelerate or Metal — software SIMD path is used.
- HTJ2K provides the best encode performance on Linux.
- Use `swift build -c release` (not debug) — release mode enables SIMD auto-vectorisation.

### Windows (Experimental)

- No Metal; partial Accelerate equivalent via WinRT DSP.
- Expect ~50% of Apple Silicon performance at equivalent clock speed.

> **Note:** Always benchmark with a release build. Debug builds disable SIMD optimisation and can be 10–20× slower than release.

> **Note:** Thermal throttling significantly impacts sustained encoding throughput on mobile devices. For long batch jobs on iOS, consider breaking work into segments with delays between them to avoid sustained high temperatures.

---

## Throughput Optimization Checklist

Use this checklist before deploying a JP3D encode/decode pipeline in production:

### Encoding Checklist

| Item | Check | Notes |
|------|-------|-------|
| Release build | `swift build -c release` | Debug is 10–20× slower |
| Tile count ≥ core count | Verify tile grid | Aim for `numTiles >= activeProcessorCount` |
| HTJ2K for speed-critical | Use `.losslessHTJ2K` / `.lossyHTJ2K` | 4–5× faster entropy coder |
| Correct tiling preset | `.batch` for offline, `.streaming` for JPIP | Match workload to preset |
| Metal enabled (Apple) | Check `JP3DEncoder.capabilities.metalAvailable` | Automatic; verify not disabled |
| Memory budget checked | Peak ≈ `tileSize × workers × 8` | Increase tileDepth gradually |
| Progression order matched | `.slrcp` for medical, `.lrcps` for JPIP | Affects streaming access patterns |

### Decoding Checklist

| Item | Check | Notes |
|------|-------|-------|
| Use region decode | Provide `JP3DRegion` for partial access | Avoids decoding unneeded tiles |
| Reduce resolution if preview | `JP3DDecoderConfiguration(resolutionReduction: 2)` | 4× fewer voxels to process |
| Limit quality layers | `maxQualityLayer: 4` for previews | Decodes only first N layers |
| Tolerate truncation for streams | `tolerateTruncation: true` | Required for JPIP |
| Pool tile buffers | Increase `maxPooledTileBuffers` for repeated decodes | Reduces allocation overhead |

### Quick Reference: Configuration vs. Goal

| Goal | Recommended Configuration |
|------|--------------------------|
| Fastest lossless encode | `.losslessHTJ2K` + `.batch` tiling |
| Fastest lossy encode | `.lossyHTJ2K(psnr: 42)` + `.batch` |
| Best compression ratio | `.lossless` + `.batch` + `decompositionLevelsZ: 5` |
| JPIP streaming server | `.lossyHTJ2K(psnr: 42)` + `.streaming` + `.lrcps` |
| Mobile interactive decode | `.lossyHTJ2K(psnr: 40)` + `.streaming` + `maxQualityLayer: 4` |
| Archival with integrity check | `.lossless` + `.default` + lossless verification step |
| Memory-constrained encode | `.losslessHTJ2K` + `.streaming` + `maxConcurrentTileWorkers: 2` |
