# Intel Benchmark Quick Start

This is a condensed guide for running J2KSwift benchmarks on Intel x86_64 hardware.

## Prerequisites (5 minutes)

```bash
# 1. Verify you're on Intel
uname -m  # Should show: x86_64

# 2. Install Swift 6.x (if not already installed)
# macOS: Download from swift.org
# Linux: Follow instructions at swift.org/download

# 3. Install OpenJPEG
# macOS:
brew install openjpeg

# Linux:
sudo apt install libopenjp2-tools

# 4. Verify installations
swift --version
opj_compress -h
```

## Run Benchmarks (30-60 minutes)

```bash
# 1. Clone and build J2KSwift
git clone https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift
swift build -c release

# 2. Run full benchmark suite
bash Scripts/intel_benchmark.sh

# The script will:
# - Auto-detect your Intel CPU
# - Generate test images (256×256 to 2048×2048)
# - Run 50 iterations per test (after 5 warmup runs)
# - Compare J2KSwift vs OpenJPEG
# - Generate CSV and markdown reports

# 3. Monitor progress
# Watch terminal output for progress updates
# Expected runtime: 30-60 min depending on CPU speed
```

## Review Results

```bash
# CSV data (for spreadsheet analysis)
cat /tmp/j2k_intel_bench/benchmark_results_intel.csv

# Markdown report (human-readable)
cat intel_benchmark_report.md

# Look for key metrics:
# - Speedup >1.0× means J2KSwift is faster than OpenJPEG
# - File sizes should be within 1-2% between codecs
# - PSNR values verify quality (lossless = inf, lossy ≥30dB)
```

## Update HTJ2K_PERFORMANCE.md

After benchmarks complete:

1. **Copy your CPU specs:**
   ```bash
   # macOS
   sysctl -n machdep.cpu.brand_string
   sysctl -n hw.ncpu
   
   # Linux
   lscpu | grep "Model name"
   nproc
   ```

2. **Extract key results from CSV:**
   - Look for 1024×1024 lossless encode time
   - Look for Med-512-16b lossless encode time
   - Calculate speedup ratios

3. **Fill in the Intel section in HTJ2K_PERFORMANCE.md:**
   - Replace "TBD" values with actual results
   - Add your CPU specs
   - Update the Intel vs M2 comparison table

## Example: Updating Results

If your results show:
- Intel i7-12700K
- 1024×1024 lossless: J2KSwift 95ms, OpenJPEG 155ms
- Speedup: 155/95 = 1.63×

Update HTJ2K_PERFORMANCE.md line ~395:

```markdown
| Grad-1024 | 1024×1024 | 8 | **1.63×** | TBD | TBD | TBD | TBD |
```

And update the comparison table (~410):

```markdown
| 1024×1024 lossless (absolute) | 70.6 ms | 95 ms | 0.74× |
| 1024×1024 lossless (speedup vs OPJ) | 1.70× | 1.63× | — |
```

## Troubleshooting

**Issue: "Architecture not x86_64"**
- You're on Apple Silicon or ARM. This guide is for Intel only.
- For Apple Silicon, results already exist in HTJ2K_PERFORMANCE.md

**Issue: "opj_compress: command not found"**
```bash
# macOS
brew install openjpeg

# Linux
sudo apt install libopenjp2-tools

# Verify
which opj_compress
```

**Issue: "swift build fails"**
```bash
# Update Swift to 6.0+
swift --version

# Clean and rebuild
swift package clean
swift build -c release
```

**Issue: "Benchmark taking too long"**
```bash
# Edit Scripts/intel_benchmark.sh
# Change line ~69: RUNS=50 to RUNS=10
# Change line ~68: WARMUP=5 to WARMUP=2
```

## Quick Single-Image Test

Test a single image before running full suite:

```bash
# Generate test image
python3 << 'EOF'
import struct
with open('/tmp/test.pgm', 'wb') as f:
    f.write(b'P5\n512 512\n255\n')
    for y in range(512):
        for x in range(512):
            f.write(struct.pack('B', (x*3 + y*7) % 256))
EOF

# Benchmark J2KSwift (5 runs)
for i in {1..5}; do
    time .build/release/j2k encode /tmp/test.pgm /tmp/j2k.j2k --lossless
done

# Benchmark OpenJPEG (5 runs)
for i in {1..5}; do
    time opj_compress -i /tmp/test.pgm -o /tmp/opj.j2k -r 1
done

# Compare file sizes (should be nearly identical)
ls -lh /tmp/j2k.j2k /tmp/opj.j2k

# Verify lossless correctness
.build/release/j2k decode /tmp/j2k.j2k /tmp/dec.pgm
.build/release/j2k compare /tmp/test.pgm /tmp/dec.pgm
# Should show: MAE = 0.0 (exact match)
```

## Share Results

To contribute Intel benchmark results:

1. **Create GitHub issue** with title: `[Intel Benchmark] CPU_MODEL results`
2. **Attach files:**
   - `benchmark_results_intel.csv`
   - `intel_benchmark_report.md`
3. **Include system info:**
   - CPU model and specs
   - OS version
   - Swift version
   - OpenJPEG version

## Next Steps

After running benchmarks:

- [ ] Review results in `intel_benchmark_report.md`
- [ ] Update HTJ2K_PERFORMANCE.md with your data
- [ ] Compare against Apple M2 baseline
- [ ] Share results with J2KSwift team (optional)
- [ ] Consider testing with AVX2/AVX-512 flags (advanced)

---

**Need help?** See [INTEL_BENCHMARK_GUIDE.md](INTEL_BENCHMARK_GUIDE.md) for detailed instructions.
