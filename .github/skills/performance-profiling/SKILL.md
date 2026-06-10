---
name: performance-profiling
description: 'Performance profiling and optimization for J2KSwift. Use for identifying bottlenecks, pipeline stage timing, memory profiling, encoder/decoder benchmarking, comparing with OpenJPEG, concurrency tuning.'
---

# Performance Profiling

Profile and optimize J2KSwift encode/decode performance.

## When to Use
- Identifying performance bottlenecks in the codec pipeline
- Benchmarking encode/decode speed
- Comparing performance against OpenJPEG
- Optimizing memory usage
- Tuning concurrency settings

## Procedure

### 1. Build Release Configuration
```bash
swift build -c release
```

### 2. Pipeline Stage Profiling
Run the built-in pipeline profiler to get per-stage timing:
```bash
# Encode with profiling
.build/release/j2k benchmark --input /tmp/test.pgm --iterations 10

# Alternatively, run performance tests
swift test -c release --filter J2KMedicalCorpusPerformanceTests
```

### 3. OpenJPEG Baseline Comparison
```bash
# Run the comparison script
bash Scripts/benchmark_openjpeg.sh

# Or manual comparison
time opj_compress -i /tmp/test.pgm -o /tmp/opj_out.j2k -r 1
time .build/release/j2k encode /tmp/test.pgm /tmp/j2k_out.j2k
```

### 4. Memory Profiling
```bash
# Use leaks tool (macOS)
leaks --atExit -- .build/release/j2k encode /tmp/test.pgm /tmp/out.j2k

# Use Instruments for detailed memory analysis
xcrun xctrace record --template "Allocations" --launch .build/release/j2k encode /tmp/test.pgm /tmp/out.j2k
```

### 5. CPU Profiling
```bash
# Sample-based profiling
xcrun xctrace record --template "Time Profiler" --launch .build/release/j2k encode /tmp/test.pgm /tmp/out.j2k

# Quick sample
sample $(pgrep j2k) 5 -file /tmp/j2k_sample.txt
```

### 6. Key Metrics to Collect

| Metric | Tool | Target |
|--------|------|--------|
| Encode time (ms/MP) | benchmark | < OpenJPEG |
| Decode time (ms/MP) | benchmark | < OpenJPEG |
| Peak RSS (MB) | leaks/Instruments | Minimize |
| DWT time (% of total) | pipeline profiler | < 40% |
| MQ coding (% of total) | pipeline profiler | < 30% |

### 7. Optimization Areas (Priority Order)
1. **DWT** — Hottest path. SIMD, Accelerate, cache-friendly access
2. **MQ Coder** — Tight loop. Branch prediction, lookup tables
3. **Memory allocation** — Buffer pools, zero-copy, stack allocation
4. **Parallelism** — Multi-tile concurrent encoding, dispatch groups
5. **Quantization** — SIMD vectorization

### 8. Validate Optimization
After any optimization, always verify correctness:
```bash
swift test --filter J2KCodecTests
swift test --filter J2KAccelerateTests
```

## Reference Scripts
- `Scripts/benchmark_openjpeg.sh` — OpenJPEG comparison
- `Scripts/compare_performance.py` — Performance data analysis
- `Scripts/profile_encoder.py` — Encoder profiling
- `Scripts/medical_benchmark.py` — Medical image benchmarks

## Reference Documentation
- `PERFORMANCE_BENCHMARK.md`
- `BENCHMARK_COMPARISON.md`
- `Documentation/PERFORMANCE_APPLE_SILICON.md`
- `Documentation/PERFORMANCE_COMPARISON.md`
