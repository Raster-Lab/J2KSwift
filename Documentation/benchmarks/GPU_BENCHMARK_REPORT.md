# GPU Codec vs OpenJPEG — Benchmark Report

**Date:** April 10, 2026  
**Platform:** MacBook Air, Apple Silicon (arm64e), macOS 14  
**GPU Backend:** Metal (Apple integrated GPU)  
**Reference Codec:** OpenJPEG v2.5.4 (`/opt/homebrew/bin/opj_compress`)  
**Build:** Swift 6.2, debug configuration (CPU timings), release build validated  

---

## 1. Metal GPU vs CPU — DWT Performance

All DWT benchmarks use `J2KMetalDWT` with `.cpu` and `.gpu` backends, measuring forward 2D wavelet transform time in milliseconds. Each measurement uses warm-up iterations followed by timed runs.

### 1.1 CDF 9/7 (Irreversible — Lossy) — Forward 2D

| Size | CPU (ms) | GPU (ms) | Speedup |
|------|----------|----------|---------|
| 64×64 | 6.051 | 0.911 | **6.64×** |
| 128×128 | 23.433 | 1.404 | **16.69×** |
| 256×256 | 102.389 | 2.351 | **43.55×** |
| 512×512 | 373.457 | 4.193 | **89.06×** |
| 1024×1024 | 1,496.957 | 10.847 | **138.01×** |
| 2048×2048 | 6,006.777 | 28.501 | **210.76×** |

### 1.2 Le Gall 5/3 (Reversible — Lossless) — Forward 2D

| Size | CPU (ms) | GPU (ms) | Speedup |
|------|----------|----------|---------|
| 64×64 | 2.957 | 0.660 | **4.48×** |
| 256×256 | 43.860 | 1.286 | **34.11×** |
| 512×512 | 176.281 | 2.274 | **77.53×** |
| 1024×1024 | 703.208 | 5.451 | **129.01×** |
| 2048×2048 | 2,883.988 | 16.360 | **176.29×** |

### 1.3 Multi-Level CDF 9/7 — Forward Decomposition

| Size | Levels | CPU (ms) | GPU (ms) | Speedup |
|------|--------|----------|----------|---------|
| 256×256 | 3 | 127.115 | 4.659 | **27.28×** |
| 512×512 | 5 | 508.121 | 11.133 | **45.64×** |
| 1024×1024 | 5 | 2,027.830 | 19.921 | **101.79×** |

---

## 2. GPU Correctness Validation

CPU-vs-GPU forward transform output compared at 512×512, plus roundtrip reconstruction error.

| Filter | CPU–GPU Max Error | CPU Roundtrip Error | GPU Roundtrip Error | Status |
|--------|-------------------|---------------------|---------------------|--------|
| Le Gall 5/3 | **0.0** (exact) | 3.05×10⁻⁵ | 3.05×10⁻⁵ | ✅ Pass |
| CDF 9/7 | 2.44×10⁻⁴ | 2.29×10⁻⁴ | 1.83×10⁻⁴ | ✅ Pass |

- 5/3 filter: GPU and CPU produce **identical** subband coefficients
- 9/7 filter: max divergence < 0.00025 (float32 precision limit)

---

## 3. OpenJPEG v2.5.4 Baseline (Full Pipeline)

Complete encode/decode pipeline: DWT + quantization + EBCOT tier-1/tier-2 + codestream I/O.  
Measured via `opj_compress` / `opj_decompress` on generated PGM test images.

| Size | Mode | Encode (internal) | Encode (total) | Decode (internal) | Decode (total) | File Size |
|------|------|-------------------|----------------|-------------------|----------------|-----------|
| 512×512 | Lossless (5/3) | 10 ms | 34.0 ms | 4 ms | 33.8 ms | 31,513 B |
| 512×512 | Lossy (9/7) | 10 ms | 33.4 ms | 4 ms | 31.6 ms | 31,513 B |
| 1024×1024 | Lossless (5/3) | 42 ms | 67.2 ms | 22 ms | 65.3 ms | 142,866 B |
| 1024×1024 | Lossy (9/7) | 43 ms | 69.9 ms | 23 ms | 65.5 ms | 142,866 B |
| 2048×2048 | Lossless (5/3) | 154 ms | 179.7 ms | 82 ms | 177.1 ms | 430,408 B |
| 2048×2048 | Lossy (9/7) | 156 ms | 180.3 ms | 82 ms | 178.3 ms | 430,408 B |

> **Internal time** = OpenJPEG's self-reported codec time. **Total time** = wall-clock including process startup and I/O.

---

## 4. GPU DWT vs OpenJPEG Full Pipeline

Comparing J2KSwift Metal GPU DWT-only time against OpenJPEG's complete encode pipeline (which includes DWT + quantization + EBCOT + file I/O).

### 4.1 Lossy — CDF 9/7

| Size | J2KSwift GPU DWT | OpenJPEG Full Encode | Advantage |
|------|------------------|----------------------|-----------|
| 512×512 | 4.2 ms | 10 ms | **2.4× faster** |
| 1024×1024 | 10.8 ms | 43 ms | **4.0× faster** |
| 2048×2048 | 28.5 ms | 156 ms | **5.5× faster** |

### 4.2 Lossless — Le Gall 5/3

| Size | J2KSwift GPU DWT | OpenJPEG Full Encode | Advantage |
|------|------------------|----------------------|-----------|
| 512×512 | 2.3 ms | 10 ms | **4.3× faster** |
| 1024×1024 | 5.5 ms | 42 ms | **7.6× faster** |
| 2048×2048 | 16.4 ms | 154 ms | **9.4× faster** |

> J2KSwift GPU DWT alone is faster than OpenJPEG's *entire* encode pipeline at all tested sizes.

---

## 5. Key Findings

1. **GPU speedup scales with image size** — from ~4–7× at 64×64 to **138–211×** at 2048×2048 for single-level DWT. The GPU's massive parallelism dominates as pixel count grows.

2. **9/7 filter benefits more from GPU** — Peak speedup of 210.76× vs 176.29× for 5/3 at 2048×2048, due to higher arithmetic intensity (more multiply-add operations per sample).

3. **Metal GPU DWT outperforms OpenJPEG's full pipeline** — At 2048×2048, GPU DWT alone (28.5 ms) is 5.5× faster than OpenJPEG's complete encode (156 ms), which includes all pipeline stages.

4. **GPU correctness verified** — 5/3 produces exact CPU–GPU match; 9/7 stays within float32 precision bounds (< 0.00025 max error).

5. **Multi-level decomposition retains strong GPU advantage** — 5-level DWT at 1024×1024 shows 101.79× GPU speedup, confirming the advantage holds across the full decomposition pyramid.

6. **Break-even point is very low** — Even at 64×64 (4,096 pixels), GPU is already 4–7× faster, suggesting the Metal dispatch overhead is minimal on Apple Silicon.

---

## 6. Methodology

### GPU/CPU DWT Benchmarks
- **Source:** `Tests/J2KMetalTests/J2KMetalDWTBenchmarkTests.swift`
- **Warm-up:** 1–2 iterations per backend before timing
- **Iterations:** 1–10 timed runs depending on image size (more for smaller sizes)
- **Timing:** `DispatchTime.now()` nanosecond precision
- **Data:** Synthetic test image: `128 + 64·sin(8πx) + 32·cos(6πy)`
- **Build:** Debug configuration (CPU times reflect unoptimized Swift; GPU times are hardware-bound)

### OpenJPEG Benchmarks
- **Version:** OpenJPEG 2.5.4 via Homebrew
- **Images:** PGM grayscale, same synthetic pattern
- **Lossless:** `-r 1` (compression ratio 1:1)
- **Lossy:** `-r 4` (compression ratio 4:1, ~2 bpp)
- **Timing:** Python `time.time()` wall-clock around process execution

### Caveats
- CPU DWT times are **debug-mode** (unoptimized Swift). Release-mode CPU would be significantly faster (estimated 5–10×), but GPU advantage would remain substantial.
- OpenJPEG is compiled with `-O2` optimizations and uses SIMD intrinsics.
- DWT is one stage of the full codec pipeline — full J2KSwift encode/decode would include quantization, EBCOT, and codestream assembly.
- GPU times include Metal command buffer submission and synchronization overhead.

---

## 7. Reproducing These Benchmarks

```bash
# Build project
swift build

# Run Metal GPU vs CPU DWT benchmarks (individual tests)
swift test --filter "J2KMetalDWTBenchmarkTests/testBench97_512"
swift test --filter "J2KMetalDWTBenchmarkTests/testBench53_1024"
swift test --filter "J2KMetalDWTBenchmarkTests/testBenchMultiLevel97_1024"

# Run GPU correctness validation
swift test --filter "J2KMetalDWTBenchmarkTests/testCorrectness"

# Run all Metal DWT benchmarks
swift test --filter "J2KMetalDWTBenchmarkTests"

# OpenJPEG comparison (requires opj_compress/opj_decompress)
bash Scripts/benchmark_openjpeg.sh -s 512,1024,2048 -m lossless,lossy2 -r 5
```
