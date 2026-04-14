# Intel Benchmark Setup Summary

## What's Been Created

I've set up a complete Intel x86_64 benchmarking infrastructure for J2KSwift. Here's what's ready:

### 1. Automated Benchmark Script
**File**: `Scripts/intel_benchmark.sh`

This script automatically:
- Detects your Intel CPU model and specs
- Generates synthetic test images (gradient and medical phantoms)
- Runs comprehensive benchmarks comparing:
  - J2KSwift (HTJ2K)
  - OpenJPEG v2.5.x (baseline)
  - OpenJPH (optional, if installed)
  - Grok (optional, if installed)
- Tests multiple scenarios:
  - Image sizes: 256×256, 512×512, 1024×1024, 2048×2048
  - Bit depths: 8-bit, 12-bit, 16-bit
  - Modes: lossless, lossy (q0.9, 2bpp, 1bpp, 0.5bpp)
- Outputs results in CSV and markdown formats
- Runs 50 iterations per test (after 5 warmup runs) for statistical accuracy

### 2. Documentation

**INTEL_BENCHMARK_GUIDE.md** (Comprehensive guide)
- Prerequisites and installation
- Detailed benchmark methodology
- Result interpretation
- Troubleshooting
- Advanced testing scenarios

**INTEL_QUICK_START.md** (Quick reference)
- 5-minute setup
- One-command benchmark execution
- Simple result review
- Quick troubleshooting

**README_INTEL_BENCHMARK.md** (This file)
- Summary of setup
- Quick overview

### 3. HTJ2K_PERFORMANCE.md Updates

Added Intel-specific section with:
- Platform specifications template
- Results tables (ready to fill with TBD placeholders)
- Intel vs Apple M2 comparison framework
- Instructions for running benchmarks

## How to Use

### On Your Intel System

```bash
# 1. Clone the repository
git clone https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift

# 2. Ensure you have Swift 6.x and OpenJPEG
swift --version  # Should show 6.0+
opj_compress -h  # Should show OpenJPEG help

# If missing:
# macOS: brew install openjpeg
# Linux: sudo apt install libopenjp2-tools

# 3. Run the benchmark
bash Scripts/intel_benchmark.sh

# 4. Wait ~30-60 minutes (grab coffee!)

# 5. Review results
cat /tmp/j2k_intel_bench/benchmark_results_intel.csv
cat intel_benchmark_report.md
```

### What Gets Tested

#### Test Images
| Name | Size | Bit Depth | Type |
|------|------|-----------|------|
| grad-256 | 256×256 | 8-bit | Synthetic gradient + noise |
| grad-512 | 512×512 | 8-bit | Synthetic gradient + noise |
| grad-1024 | 1024×1024 | 8-bit | Synthetic gradient + noise |
| grad-2048 | 2048×2048 | 8-bit | Synthetic gradient + noise |
| med-512-12b | 512×512 | 12-bit | Medical CT phantom |
| med-512-16b | 512×512 | 16-bit | Medical CT phantom |
| med-1024-16b | 1024×1024 | 16-bit | Medical CT phantom |

#### Encoding Modes
- **Lossless**: Reversible 5/3 DWT, exact reconstruction
- **Lossy q0.9**: High quality (~40+ dB PSNR)
- **Lossy 2 bpp**: Moderate compression
- **Lossy 1 bpp**: High compression
- **Lossy 0.5 bpp**: Very high compression

#### Metrics Collected
- **Encode time** (median of 50 runs)
- **Decode time** (median of 50 runs)
- **File size** (bytes)
- **PSNR** (dB) for quality validation
- **Speedup ratio** (OpenJPEG_time / J2KSwift_time)

## Expected Results

Based on the Apple M2 baseline in HTJ2K_PERFORMANCE.md, Intel systems should show:

### Absolute Performance
Intel CPUs will be slower than Apple M2 in absolute terms due to:
- Different architecture (x86_64 vs arm64e)
- Memory bandwidth differences
- Cache hierarchy differences

**Example (estimated):**
- Apple M2: 70.6 ms for 1024×1024 lossless
- Intel i7-12700K: ~90-110 ms for 1024×1024 lossless
- Intel i5-10th gen: ~120-150 ms for 1024×1024 lossless

### Relative Performance (vs OpenJPEG)
The speedup ratio vs OpenJPEG should remain competitive:

| Scenario | M2 Speedup | Expected Intel Speedup |
|----------|-----------|----------------------|
| 512×512 8-bit lossless | 1.15× | 1.0-1.3× |
| 1024×1024 8-bit lossless | 1.70× | 1.2-1.6× |
| 512×512 16-bit lossless | 1.68× | 1.4-1.8× |
| Med 16-bit lossy 0.5bpp | 1.80× | 1.5-2.0× |

### Key Insights
- HTJ2K block coder efficiency is architecture-independent
- Pure Swift implementation performs competitively on both architectures
- Larger images and higher bit depths favor J2KSwift more
- 256×256 may show near-parity due to fixed overhead

## Updating HTJ2K_PERFORMANCE.md

After running benchmarks on Intel:

1. **Find the Intel section** (around line 357-420)
2. **Update platform specs** (lines ~372-382):
   ```markdown
   | CPU | Intel Core i7-12700K |
   | Cores | 12 (8P+4E) |
   | Base/Turbo | 3.6 GHz / 5.0 GHz |
   ```

3. **Fill in results table** (lines ~384-392):
   Replace "TBD" with actual speedup values from your CSV

4. **Update comparison table** (lines ~396-404):
   Add absolute times and compute M2 advantage ratio

5. **Commit and push** or create PR:
   ```bash
   git checkout -b intel-benchmark-results
   git add HTJ2K_PERFORMANCE.md
   git commit -m "Add Intel x86_64 benchmark results"
   git push origin intel-benchmark-results
   ```

## File Structure

```
J2KSwift/
├── Scripts/
│   └── intel_benchmark.sh           # Main benchmark runner
├── INTEL_BENCHMARK_GUIDE.md         # Comprehensive guide
├── INTEL_QUICK_START.md             # Quick reference
├── README_INTEL_BENCHMARK.md        # This file
├── HTJ2K_PERFORMANCE.md             # Updated with Intel section
└── intel_benchmark_report.md        # Generated after running benchmark
```

## Benchmark Output

After running `bash Scripts/intel_benchmark.sh`:

```
/tmp/j2k_intel_bench/
├── benchmark_results_intel.csv       # Raw data (all codecs)
├── grad-256.pgm                      # Test images
├── grad-512.pgm
├── grad-1024.pgm
├── grad-2048.pgm
├── med-512-12b.pgm
├── med-512-16b.pgm
├── med-1024-16b.pgm
├── *_j2k.j2k                         # Encoded files (J2KSwift)
├── *_opj.j2k                         # Encoded files (OpenJPEG)
└── *_dec.pgm                         # Decoded files

intel_benchmark_report.md             # Human-readable report
```

## Troubleshooting

### Common Issues

**"Not running on Intel x86_64"**
- Script detects Apple Silicon or ARM
- This is expected if you're on M-series Mac
- Run on actual Intel hardware

**"opj_compress: command not found"**
```bash
# macOS
brew install openjpeg

# Linux
sudo apt install libopenjp2-tools
```

**"Swift build fails"**
- Ensure Swift 6.0+ is installed
- Try: `swift package clean && swift build -c release`

**"Python errors during image generation"**
- Requires Python 3.8+
- Standard library only (no external packages needed)

**"Benchmark too slow"**
- Edit script: reduce RUNS from 50 to 10
- Or test single image first (see INTEL_QUICK_START.md)

## Advanced Options

### Test with AVX2/AVX-512 (Future)

```bash
# Check CPU support
lscpu | grep -i avx

# Build with explicit SIMD flags (experimental)
swift build -c release -Xswiftc -Osize -Xcc -mavx2
```

### Compare Multiple Intel CPUs

Run benchmarks on different Intel systems:
- Desktop (i9-13900K)
- Laptop (i7-1260P)
- Server (Xeon Platinum)

Document performance scaling across Intel product lines.

### Memory Profiling

```bash
# macOS
/usr/bin/time -l .build/release/j2k encode large.pgm output.j2k --lossless

# Linux
/usr/bin/time -v .build/release/j2k encode large.pgm output.j2k --lossless
```

## Next Steps

1. **Run benchmarks** on your Intel system
2. **Review results** and compare with Apple M2
3. **Update documentation** with your findings
4. **Share results** (optional):
   - GitHub issue
   - Pull request
   - Community discussion

## Questions?

- See [INTEL_BENCHMARK_GUIDE.md](INTEL_BENCHMARK_GUIDE.md) for details
- See [INTEL_QUICK_START.md](INTEL_QUICK_START.md) for quick ref
- Open GitHub issue with `[Intel Benchmark]` tag

---

**Ready to benchmark?** Run: `bash Scripts/intel_benchmark.sh`
