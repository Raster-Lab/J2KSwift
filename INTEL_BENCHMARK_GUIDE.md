# Intel x86_64 Benchmark Guide

This guide provides step-by-step instructions for benchmarking J2KSwift on Intel x86_64 platforms and comparing results with the Apple Silicon (M2) baseline.

## Prerequisites

### Hardware Requirements
- Intel x86_64 processor (Core i5/i7/i9 or Xeon)
- Minimum 8 GB RAM
- macOS (10.15+) or Linux (Ubuntu 20.04+)

### Software Requirements

1. **Swift 6.x**
   ```bash
   swift --version  # Should show Swift 6.0+
   ```

2. **OpenJPEG v2.5.x**
   ```bash
   # macOS
   brew install openjpeg
   
   # Linux
   sudo apt install libopenjp2-tools
   ```

3. **OpenJPH (optional, for extended comparisons)**
   ```bash
   # macOS
   brew install openjph
   
   # Linux - build from source
   git clone https://github.com/aous72/OpenJPH.git
   cd OpenJPH
   mkdir build && cd build
   cmake ..
   make -j$(nproc)
   sudo make install
   ```

4. **Grok (optional, for extended comparisons)**
   ```bash
   # macOS
   brew install grok
   
   # Linux - build from source
   git clone https://github.com/GrokImageCompression/grok.git
   cd grok
   mkdir build && cd build
   cmake ..
   make -j$(nproc)
   sudo make install
   ```

5. **Python 3.8+** (for test image generation and analysis)
   ```bash
   python3 --version
   ```

## Quick Start

### 1. Clone and Build J2KSwift

```bash
git clone https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift
swift build -c release
```

Verify the build:
```bash
.build/release/j2k --version
```

### 2. Run Full Intel Benchmark Suite

```bash
bash Scripts/intel_benchmark.sh
```

This will:
- Detect your Intel CPU model
- Generate synthetic test images (256×256 to 2048×2048)
- Run 50 iterations per test (after 5 warmup runs)
- Compare J2KSwift vs OpenJPEG (and optionally OpenJPH/Grok)
- Generate CSV results and markdown report

**Expected runtime**: 30-60 minutes depending on CPU

### 3. Review Results

Results are written to:
- **Raw data**: `/tmp/j2k_intel_bench/benchmark_results_intel.csv`
- **Report**: `intel_benchmark_report.md`

## Benchmark Scenarios

The benchmark suite tests the following configurations:

### Image Sizes
| Name | Resolution | Bit Depth | Type |
|------|-----------|-----------|------|
| grad-256 | 256×256 | 8-bit | Synthetic gradient |
| grad-512 | 512×512 | 8-bit | Synthetic gradient |
| grad-1024 | 1024×1024 | 8-bit | Synthetic gradient |
| grad-2048 | 2048×2048 | 8-bit | Synthetic gradient |
| med-512-12b | 512×512 | 12-bit | Medical phantom |
| med-512-16b | 512×512 | 16-bit | Medical phantom |
| med-1024-16b | 1024×1024 | 16-bit | Medical phantom |

### Encoding Modes
| Mode | Description | Target |
|------|-------------|--------|
| lossless | Reversible 5/3 DWT | Exact reconstruction (MAE=0) |
| lossy-q0.9 | Quality factor 0.9 | High quality (~40+ dB PSNR) |
| lossy-2bpp | 2 bits per pixel | Moderate compression |
| lossy-1bpp | 1 bit per pixel | High compression |
| lossy-0.5bpp | 0.5 bits per pixel | Very high compression |

### Codecs Tested
- **J2KSwift**: Pure Swift HTJ2K implementation
- **OpenJPEG**: Reference C implementation (v2.5.x)
- **OpenJPH** (optional): High-Throughput JPEG 2000
- **Grok** (optional): GPU-accelerated JPEG 2000

## Manual Testing

### Single Image Test

```bash
# Generate a test image
python3 << 'EOF'
import struct
with open('/tmp/test_512.pgm', 'wb') as f:
    f.write(b'P5\n512 512\n255\n')
    for y in range(512):
        for x in range(512):
            f.write(struct.pack('B', (x + y) % 256))
EOF

# Benchmark J2KSwift
time .build/release/j2k encode /tmp/test_512.pgm /tmp/j2k_out.j2k --lossless

# Benchmark OpenJPEG
time opj_compress -i /tmp/test_512.pgm -o /tmp/opj_out.j2k -r 1

# Compare file sizes
ls -lh /tmp/j2k_out.j2k /tmp/opj_out.j2k

# Verify correctness
.build/release/j2k decode /tmp/j2k_out.j2k /tmp/j2k_dec.pgm
opj_decompress -i /tmp/opj_out.j2k -o /tmp/opj_dec.pgm
.build/release/j2k compare /tmp/test_512.pgm /tmp/j2k_dec.pgm
```

### Performance Profiling

For detailed pipeline profiling on Intel:

```bash
# Build with profiling enabled
swift build -c release -Xswiftc -DPROFILING_ENABLED

# Run with performance analysis
time .build/release/j2k encode input.pgm output.j2k --lossless --verbose

# Use macOS Instruments (if on macOS)
instruments -t "Time Profiler" .build/release/j2k encode input.pgm output.j2k --lossless
```

## Interpreting Results

### Speedup Metrics

The benchmark compares encode/decode times and computes speedup ratios:

```
Speedup = OpenJPEG_Time / J2KSwift_Time
```

- **>1.0×**: J2KSwift is faster
- **<1.0×**: OpenJPEG is faster
- **~1.0×**: Comparable performance

### Expected Performance Ranges (Intel)

Based on typical Intel Core i7/i9 (10th-13th gen):

| Image Size | Expected Speedup Range |
|-----------|----------------------|
| 256×256 | 0.7× - 1.2× (small overhead) |
| 512×512 | 1.0× - 1.5× |
| 1024×1024 | 1.2× - 1.8× |
| 2048×2048 | 1.3× - 2.0× |
| 16-bit medical | 1.4× - 2.0× |

**Note**: Absolute times will be slower than Apple M2 due to architecture differences, but relative speedup vs OpenJPEG should be maintained.

### Quality Metrics

For lossy compression, verify PSNR values:

- **PSNR ≥ 40 dB**: High quality, visually lossless
- **PSNR 35-40 dB**: Good quality
- **PSNR 30-35 dB**: Acceptable quality
- **PSNR < 30 dB**: Visible artifacts

Lossless mode should show **PSNR = inf** (infinite) or exact MAE = 0.

## Updating HTJ2K_PERFORMANCE.md

After running benchmarks, update the performance document:

1. **Add Intel Results Section**
   - Copy the generated `intel_benchmark_report.md` content
   - Add after the "Platform-Specific Notes" section

2. **Create Comparison Tables**
   - Compare Intel vs Apple M2 speedups
   - Highlight architecture-specific differences

3. **Update Executive Summary**
   - Include Intel performance claims if competitive

### Template for Intel Section

```markdown
### Intel x86_64 (Intel Core i7-12700K)

- **CPU**: Intel Core i7-12700K, 12 cores (8P+4E)
- **OS**: macOS 14.0 / Ubuntu 22.04
- **Swift**: 6.2 (Release build)
- **OpenJPEG**: v2.5.4

#### Pipeline-Level Performance vs OpenJPEG (Intel)

| Image | Resolution | Bit Depth | Lossless | Lossy q0.9 | Lossy 1bpp |
|-------|-----------|-----------|----------|------------|------------|
| Grad-512 | 512×512 | 8 | **1.25×** | **1.40×** | **1.18×** |
| Grad-1024 | 1024×1024 | 8 | **1.62×** | **1.51×** | **1.48×** |
| Med-512-16b | 512×512 | 16 | **1.71×** | **1.65×** | **1.62×** |

#### Intel vs Apple M2 Comparison

| Metric | Apple M2 | Intel i7-12700K | Ratio |
|--------|----------|-----------------|-------|
| 1024×1024 lossless encode | 70.6 ms | ~XX ms | X.XX× |
| Med-512-16b lossless | 31.0 ms | ~XX ms | X.XX× |
| Relative speedup vs OPJ | 1.70× | 1.62× | 0.95× |
```

## Troubleshooting

### Issue: "J2KSwift slower than expected on Intel"

**Possible causes:**
- Debug build instead of release
- Thermal throttling (check CPU temperature)
- Background processes consuming CPU
- Older Intel architecture (pre-10th gen)

**Solutions:**
```bash
# Verify release build
swift build -c release --show-bin-path

# Check for thermal issues (macOS)
sudo powermetrics --samplers cpu_power -n 1

# Run with high priority
sudo nice -n -20 bash Scripts/intel_benchmark.sh
```

### Issue: "OpenJPEG not found"

```bash
# macOS
brew install openjpeg
export OPJ_COMPRESS=/opt/homebrew/bin/opj_compress
export OPJ_DECOMPRESS=/opt/homebrew/bin/opj_decompress

# Linux
sudo apt install libopenjp2-tools
which opj_compress opj_decompress
```

### Issue: "Python image generation fails"

```bash
# Ensure Python 3.8+
python3 --version

# Check required modules
python3 -c "import struct, math, os"

# If missing, install:
# macOS: brew install python@3.11
# Linux: sudo apt install python3
```

## Advanced Benchmarking

### Test with Real Medical Images

```bash
# Download sample DICOM/medical images
# Convert to PGM using ImageMagick or similar
convert medical_ct.dcm -depth 16 medical_ct.pgm

# Benchmark
time .build/release/j2k encode medical_ct.pgm medical_ct.j2k --lossless
time opj_compress -i medical_ct.pgm -o medical_ct_opj.j2k -r 1

# Verify lossless
.build/release/j2k decode medical_ct.j2k medical_ct_dec.pgm
.build/release/j2k compare medical_ct.pgm medical_ct_dec.pgm
# Should show MAE = 0.0
```

### Multi-Threaded Performance

Test scaling across Intel cores:

```bash
# Run with different thread counts
export SWIFT_CONCURRENCY_THREAD_COUNT=4
time .build/release/j2k encode large.pgm output.j2k --lossless

export SWIFT_CONCURRENCY_THREAD_COUNT=8
time .build/release/j2k encode large.pgm output.j2k --lossless

export SWIFT_CONCURRENCY_THREAD_COUNT=16
time .build/release/j2k encode large.pgm output.j2k --lossless
```

### Memory Profiling

```bash
# macOS: Use Instruments or heap tracking
/usr/bin/time -l .build/release/j2k encode large.pgm output.j2k --lossless

# Linux: Use GNU time
/usr/bin/time -v .build/release/j2k encode large.pgm output.j2k --lossless
```

## Reporting Results

When sharing Intel benchmark results:

1. **Include full system specs**:
   - Exact CPU model (`lscpu` or `sysctl -n machdep.cpu.brand_string`)
   - Total RAM
   - OS version
   - Swift version
   - Codec versions (OpenJPEG, OpenJPH, Grok)

2. **Provide both absolute and relative metrics**:
   - Absolute encode/decode times (ms)
   - Speedup ratios vs OpenJPEG
   - Throughput (MP/s or MB/s)

3. **Include quality validation**:
   - PSNR for lossy modes
   - MAE for lossless (should be 0.0)
   - File size comparisons

4. **Note any anomalies**:
   - Thermal throttling events
   - Unexpected slowdowns
   - Memory issues

## Next Steps

After completing Intel benchmarks:

1. Compare results with Apple M2 baseline (HTJ2K_PERFORMANCE.md)
2. Identify architecture-specific bottlenecks
3. Consider Intel-specific optimizations (AVX2, AVX-512)
4. Update project documentation with Intel performance claims
5. Submit results to the J2KSwift team for inclusion in official benchmarks

## Contact

For questions or to share benchmark results:
- GitHub Issues: https://github.com/Raster-Lab/J2KSwift/issues
- Tag results with `[Intel Benchmark]`

---

**Document Version**: 1.0  
**Last Updated**: April 14, 2026
