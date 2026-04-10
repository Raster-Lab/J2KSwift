---
name: htj2k-benchmark
description: 'HTJ2K vs legacy JPEG 2000 benchmarking. Use for comparing FBCOT vs EBCOT throughput, HTJ2K encode/decode speed, quality parity validation, mixed-mode performance, OpenJPEG HTJ2K interop, JPH file format benchmarks.'
---

# HTJ2K Benchmark (ISO/IEC 15444-15 vs Legacy Part 1)

Benchmark and validate High-Throughput JPEG 2000 performance against legacy JPEG 2000.

## When to Use
- Comparing HTJ2K (FBCOT) vs legacy (EBCOT) encode/decode throughput
- Validating HTJ2K quality parity with legacy at same compression ratio
- Benchmarking mixed-mode coding (HT + legacy blocks)
- Cross-codec HTJ2K interop with OpenJPEG
- Profiling individual coding primitives (MEL, VLC, MagSgn)
- Measuring JPH file format I/O performance
- Verifying ISO/IEC 15444-15 performance targets (10–100× speedup)

## Procedure

### 1. Build in Release Mode
```bash
swift build -c release
```

### 2. Create Test Images
```bash
# Grayscale gradients at multiple sizes
for SIZE in 256 512 1024 2048 4096; do
  python3 -c "
import struct
with open('/tmp/htbench_gray_${SIZE}.pgm', 'wb') as f:
    f.write(b'P5\n${SIZE} ${SIZE}\n255\n')
    for y in range(${SIZE}):
        for x in range(${SIZE}):
            f.write(struct.pack('B', (x * 3 + y * 7) % 256))
"
done

# Color test image 1024x1024
python3 -c "
import struct, math
with open('/tmp/htbench_color_1024.ppm', 'wb') as f:
    f.write(b'P6\n1024 1024\n255\n')
    for y in range(1024):
        for x in range(1024):
            r = int(128 + 127 * math.sin(x * 0.05))
            g = int(128 + 127 * math.sin(y * 0.05))
            b = int(128 + 127 * math.sin((x + y) * 0.03))
            f.write(struct.pack('BBB', r, g, b))
"
```

### 3. HTJ2K vs Legacy Benchmark Matrix

| Scenario | Sizes | Filter | Metrics |
|----------|-------|--------|---------|
| HTJ2K lossless encode | 256² – 4096² | 5/3 | time (ms), throughput (MP/s), file size |
| Legacy lossless encode | 256² – 4096² | 5/3 | time (ms), throughput (MP/s), file size |
| HTJ2K lossy encode | 256² – 4096² | 9/7 | time (ms), PSNR, file size |
| Legacy lossy encode | 256² – 4096² | 9/7 | time (ms), PSNR, file size |
| HTJ2K decode | 256² – 4096² | Both | time (ms), throughput (MP/s) |
| Legacy decode | 256² – 4096² | Both | time (ms), throughput (MP/s) |
| Mixed-mode encode | 1024², 2048² | Both | time (ms), file size |
| OpenJPEG HTJ2K | 256² – 2048² | Both | time (ms), cross-codec MAE |

### 4. Run J2KSwift Benchmark Tests

```bash
# HTJ2K-specific benchmarks (encode, decode, passes, block sizes)
swift test -c release --filter J2KHTJ2KBenchmarkTests

# Full codec benchmarks (includes legacy baseline)
swift test -c release --filter PerformanceTests
```

### 5. OpenJPEG HTJ2K Comparison

**OpenJPEG HTJ2K encode** (requires OpenJPEG ≥ v2.5.0 with HTJ2K support):
```bash
# Lossless HTJ2K
time opj_compress -i /tmp/htbench_gray_1024.pgm -o /tmp/opj_ht_lossless.j2k -r 1 -HTJ2K_LOSSLESS

# Lossy HTJ2K
time opj_compress -i /tmp/htbench_gray_1024.pgm -o /tmp/opj_ht_lossy.j2k -r 20 -HTJ2K

# Legacy lossless (baseline)
time opj_compress -i /tmp/htbench_gray_1024.pgm -o /tmp/opj_legacy_lossless.j2k -r 1

# Legacy lossy (baseline)
time opj_compress -i /tmp/htbench_gray_1024.pgm -o /tmp/opj_legacy_lossy.j2k -r 20
```

**OpenJPEG HTJ2K decode**:
```bash
time opj_decompress -i /tmp/opj_ht_lossless.j2k -o /tmp/opj_ht_decoded.pgm
time opj_decompress -i /tmp/opj_legacy_lossless.j2k -o /tmp/opj_legacy_decoded.pgm
```

### 6. Cross-Codec Interop Validation

```bash
# J2KSwift HTJ2K → OpenJPEG decode
.build/release/j2k encode /tmp/htbench_gray_1024.pgm /tmp/j2k_ht.jph --htj2k
opj_decompress -i /tmp/j2k_ht.jph -o /tmp/j2k_ht_decoded_by_opj.pgm

# OpenJPEG HTJ2K → J2KSwift decode
opj_compress -i /tmp/htbench_gray_1024.pgm -o /tmp/opj_ht.j2k -r 1 -HTJ2K_LOSSLESS
.build/release/j2k decode /tmp/opj_ht.j2k /tmp/opj_ht_decoded_by_j2k.pgm

# Verify lossless roundtrip
.build/release/j2k compare /tmp/htbench_gray_1024.pgm /tmp/j2k_ht_decoded_by_opj.pgm
.build/release/j2k compare /tmp/htbench_gray_1024.pgm /tmp/opj_ht_decoded_by_j2k.pgm
```

### 7. Coding Primitive Profiling

Profile individual HTJ2K coding primitives to find bottlenecks:

| Primitive | What to Measure |
|-----------|----------------|
| **MEL coder** | Run-length encode/decode time per code block |
| **VLC coder** | Table lookup + encode/decode time per code block |
| **MagSgn coder** | Raw bit packing/unpacking time per code block |
| **Cleanup pass** | Full pass time (all three primitives combined) |
| **SigProp pass** | Significance propagation refinement time |
| **MagRef pass** | Magnitude refinement time |

```bash
# Run with instrumentation
swift test -c release --filter J2KHTJ2KBenchmarkTests/testHTJ2KCodingPrimitivePerformance
```

### 8. Quality Parity Validation

HTJ2K must produce identical quality at the same compression ratio as legacy:

| Metric | Requirement |
|--------|-------------|
| **PSNR** | HTJ2K ≥ Legacy PSNR at same rate |
| **MAE (lossless)** | = 0 for both HTJ2K and legacy |
| **MSE** | HTJ2K ≤ Legacy MSE at same rate |
| **File size** | HTJ2K ≈ Legacy (±5% at same quality) |

### 9. Performance Targets (ISO/IEC 15444-15)

| Metric | ISO Target | J2KSwift Achieved |
|--------|-----------|-------------------|
| Encode speedup vs EBCOT | 10–100× | 57–70× |
| Decode speedup vs EBCOT | 10–100× | 57–70× |
| Quality parity | Identical at same rate | ✅ Verified |
| Memory efficiency | ≤ Legacy | ✅ Comparable/better |

### 10. Results Template

```markdown
## HTJ2K vs Legacy Benchmark Results

### Encode Speed (lossless, 5/3 DWT)
| Size | HTJ2K (ms) | Legacy (ms) | Speedup | OpenJPEG HT (ms) | OpenJPEG Legacy (ms) |
|------|-----------|-------------|---------|-------------------|---------------------|
| 256² |           |             |         |                   |                     |
| 512² |           |             |         |                   |                     |
| 1024²|           |             |         |                   |                     |
| 2048²|           |             |         |                   |                     |
| 4096²|           |             |         |                   |                     |

### Decode Speed (lossless)
| Size | HTJ2K (ms) | Legacy (ms) | Speedup |
|------|-----------|-------------|---------|
| 256² |           |             |         |
| 512² |           |             |         |
| 1024²|           |             |         |

### Quality Parity (lossy, rate 20:1)
| Size | HTJ2K PSNR | Legacy PSNR | HTJ2K Size | Legacy Size |
|------|-----------|-------------|------------|-------------|
| 512² |           |             |            |             |
| 1024²|           |             |            |             |

### Coding Primitive Breakdown (1024², per block avg)
| Primitive | Encode (μs) | Decode (μs) |
|-----------|------------|-------------|
| MEL       |            |             |
| VLC       |            |             |
| MagSgn    |            |             |
| Total     |            |             |

### Cross-Codec HTJ2K Interop
| Scenario | MAE | PSNR | Status |
|----------|-----|------|--------|
| J2KSwift HT → OpenJPEG | | | |
| OpenJPEG HT → J2KSwift | | | |

Platform: macOS XX.X, Apple MX
J2KSwift: vX.X.X
OpenJPEG: vX.X.X
```

## Constraints
- ALWAYS build in release mode (`-c release`) for fair comparison
- ALWAYS benchmark both HTJ2K AND legacy with the SAME input images
- ALWAYS include at least 1 warmup iteration before timing
- ALWAYS report both encode AND decode times
- ALWAYS verify lossless roundtrip produces MAE = 0
- ALWAYS report system info (Apple Silicon model, macOS version) with results
- Compare like-for-like: same DWT filter, same compression ratio, same tile config
- Report throughput in megapixels/second for size-independent comparison

## Reference Files
- `HTJ2K.md` — HTJ2K implementation guide
- `HTJ2K_PERFORMANCE.md` — Historical performance results
- `HTJ2K_CONFORMANCE_REPORT.md` — ISO/IEC 15444-15 conformance report
- `BENCHMARK_COMPARISON.md` — General benchmark comparisons
- `GPU_BENCHMARK_REPORT.md` — GPU acceleration benchmarks
- `Tests/J2KCodecTests/J2KHTJ2KBenchmarkTests.swift` — HTJ2K test suite
- `Sources/J2KCodec/J2KHTCodec.swift` — HTJ2K codec API
- `Sources/J2KCodec/J2KHTBlockCoder.swift` — FBCOT block coder
