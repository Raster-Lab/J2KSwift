---
name: gpu-benchmark
description: 'GPU acceleration benchmarking for Metal, Vulkan, and Accelerate backends. Use for comparing GPU vs CPU performance, validating GPU correctness, shader profiling, buffer pool efficiency.'
---

# GPU Acceleration Benchmarking

Benchmark and validate GPU-accelerated JPEG 2000 operations.

## When to Use
- Comparing GPU vs CPU performance for DWT, color transforms, quantization
- Validating GPU output correctness against CPU reference
- Profiling Metal or Vulkan shader performance
- Optimizing GPU buffer management

## Procedure

### 1. Build and Verify GPU Tests Pass
```bash
swift build
swift test --filter J2KAccelerateTests
swift test --filter J2KMetalTests
swift test --filter J2KVulkanTests
```

### 2. CPU Baseline
```bash
# Run codec tests to get CPU timing baseline
swift test -c release --filter J2KMedicalCorpusPerformanceTests
```

### 3. Accelerate Framework Benchmark
Test vDSP/vImage vs naive CPU:
```bash
swift test -c release --filter J2KAccelerateTests
```

Key operations to benchmark:
- DWT (5/3 and 9/7) — `J2KAcceleratedWavelet`
- MCT (ICT/RCT) — `J2KAcceleratedMCT`
- Quantization — `J2KAcceleratedTrellis`
- SIMD block coding — `J2KHTSIMDAcceleration`

### 4. Metal GPU Benchmark (macOS/iOS only)
```bash
swift test -c release --filter J2KMetalTests
```

Key operations:
- GPU DWT — `J2KMetalDWT`
- GPU Color Transform — `J2KMetalColorTransform`
- GPU Quantization — `J2KMetalQuantizer`
- GPU ROI — `J2KMetalROI`
- Buffer pool efficiency — `J2KMetalBufferPool`

### 5. Vulkan GPU Benchmark (Linux/Windows)
```bash
swift test -c release --filter J2KVulkanTests
```

### 6. Correctness Validation
GPU output MUST match CPU reference within tolerance:
```
Lossless operations (integer): exact match
Lossy operations (float): max absolute error < 1e-5
```

### 7. Metal GPU Profiling (macOS)
```bash
# Use Metal System Trace
xcrun xctrace record --template "Metal System Trace" --launch .build/release/j2k encode /tmp/test.pgm /tmp/out.j2k

# GPU frame capture in Xcode for shader debugging
```

### 8. Results Template
```markdown
## GPU Benchmark Results

| Operation | CPU (ms) | Accelerate (ms) | Metal (ms) | Speedup |
|-----------|----------|-----------------|------------|---------|
| DWT 5/3   |          |                 |            |         |
| DWT 9/7   |          |                 |            |         |
| ICT       |          |                 |            |         |
| RCT       |          |                 |            |         |
| Quantize  |          |                 |            |         |

Platform: macOS XX.X, Apple MX, Metal X
Image: WxH, N components, bit depth
```

## Reference Documentation
- `Documentation/METAL_PERFORMANCE.md`
- `Documentation/VULKAN_GPU_COMPUTE.md`
- `Documentation/ACCELERATE_ADVANCED.md`
- `HARDWARE_ACCELERATION.md`
