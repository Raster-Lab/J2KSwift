# Multi-Codec JPEG 2000 Benchmark: Post-Optimization Results

**Date:** April 15, 2026  
**Branch:** `benchmark/multi-codec-comparison`  
**Binary:** Release build (`.build/release/j2k`), Swift 6  
**Platform:** Apple M2 (8-core), 24 GB RAM, macOS 15.7.5 (arm64)  
**Runs per test:** 5 (+ 1 warmup)

---

## Latest Verified Snapshot (April 15, 2026)

A fresh full release-mode rerun was performed after the chunked Tier-1 parallel scheduler update. The current 1024×1024 grayscale comparison is:

| Metric | J2KSwift | OpenJPEG | Grok |
|-------|:---:|:---:|:---:|
| Lossless Encode (`bench_gray_1024`) | **109.9 ms** | 127.5 ms | 79.8 ms |
| Lossy Encode (`bench_gray_1024`) | **79.9 ms** | 128.7 ms | 62.2 ms |
| Lossless Decode (`bench_gray_1024`) | **105.6 ms** | 113.3 ms | 53.7 ms |
| Lossy Decode (`bench_gray_1024`) | **66.1 ms** | 75.2 ms | 44.8 ms |

Focused quality and interoperability validation on the same benchmark image:
- **J2KSwift self-decode:** PSNR = **22.7361 dB**, MSE = **346.317686**, MAE = **14.089388**
- **OpenJPEG decoding J2KSwift output:** PSNR = **22.7357 dB**, MSE = **346.342674**, MAE = **14.089888**
- **Lossless cross-decode remained exact:** MAE = **0**, MSE = **0**, Max Error = **0**
- **Cross-codec interoperability:** **6 / 6** encode→decode combinations completed successfully

### Post-Fix RGB Verification (April 15, 2026)

A focused rerun after the lossy quantization calibration fix confirmed that the earlier color undershoot has been resolved:

| Image | Previous J2KSwift Size | Verified Post-Fix Size | Target Budget |
|-------|:---:|:---:|:---:|
| bench_color_512 | 13,413 B | **39,765 B** | 39,321 B |
| bench_color_1024 | 49,143 B | **158,444 B** | 157,286 B |

PCRD now reaches the full top-layer byte targets on both RGB benchmark cases.

### Follow-Up PCRD Correction (April 15, 2026)

A second targeted follow-up landed in the standard EBCOT rate-control path after the snapshot above:

- zero-byte refinement passes are now treated as effectively free quality gains instead of being penalized with a synthetic byte cost
- selecting a later truncation point now commits the full pass prefix for that code-block, matching PCRD expectations
- the focused validation set is currently green, including RGB budget protection, grayscale medium-bitrate quality, grayscale medium-quality quality, and the new zero-byte refinement regression

This keeps the recent throughput gains intact while addressing a correctness edge case in pass selection.

---

## Codec Versions

| Codec | Version | Role |
|-------|---------|------|
| **J2KSwift** | post-optimization (Apr 14, 2026) | Native Swift 6 JPEG 2000 |
| **OpenJPEG** | 2.5.4 (`opj_compress` / `opj_decompress`) | ISO reference implementation |
| **Grok** | latest (`grk_compress` / `grk_decompress`) | High-performance C++ codec |
| **Pillow** | 11.3 (Python bindings) | General-purpose image library |

---

## Optimizations Reflected In This Run

This benchmark refresh includes the current Tier-1 parallel encoder design now active in the release binary:

### 1. Chunk-Based Tier-1 Worker Scheduling (`J2KEncoderPipeline.swift`)

The standard EBCOT path now uses coarse worker chunks sized for Apple Silicon instead of shared per-result collection overhead:
- roughly **2 × available cores** worth of Tier-1 work chunks
- lower dispatch and ARC overhead on large images
- deterministic output ordering preserved

### 2. Direct Ordered Result Buffer + Thread-Local State (`J2KEncoderPipeline.swift`)

Parallel workers now write directly into a preallocated ordered result buffer while keeping encoder state local to each worker:
- worker-local MQ and scratch buffers
- no hot-path append mutex for production Tier-1 encoding
- no final result sort required in the common path

**Observed effect in the fresh benchmark run:** larger grayscale encode and decode cases continue to outperform OpenJPEG, with the biggest gain in **2048×2048 lossy encode** where J2KSwift measured **179.0 ms** vs **411.3 ms** for OpenJPEG.

---

## Test Images

| Image | Dimensions | Channels | Uncompressed |
|-------|-----------|---------|-------------|
| `bench_gray_256` | 256×256 | Gray | 65 KB |
| `bench_gray_512` | 512×512 | Gray | 262 KB |
| `bench_gray_1024` | 1024×1024 | Gray | 1.05 MB |
| `bench_gray_2048` | 2048×2048 | Gray | 4.19 MB |
| `bench_color_512` | 512×512 | RGB | 786 KB |
| `bench_color_1024` | 1024×1024 | RGB | 3.15 MB |

---

## Encode Performance

### Lossless Encode (5/3 DWT)

| Image | J2KSwift (ms) | OpenJPEG (ms) | Grok (ms) | J2K vs OPJ |
|-------|:---:|:---:|:---:|:---:|
| bench_gray_256 | 45.1 | 42.3 | 42.3 | 1.07× slower |
| bench_gray_512 | 59.6 | 59.5 | 46.1 | ~tie |
| bench_gray_1024 | **109.9** | 127.5 | 79.8 | **1.16× faster** |
| bench_gray_2048 | **327.9** | 416.3 | 120.1 | **1.27× faster** |
| bench_color_512 | 91.8 | 90.9 | 55.8 | 1.01× slower |
| bench_color_1024 | **238.0** | 240.7 | 80.6 | **1.01× faster** |

### Lossy Encode (9/7 DWT, ~20:1)

| Image | J2KSwift (ms) | OpenJPEG (ms) | Grok (ms) | J2K vs OPJ |
|-------|:---:|:---:|:---:|:---:|
| bench_gray_256 | 46.3 | 44.2 | 43.6 | 1.05× slower |
| bench_gray_512 | **50.5** | 60.1 | 49.0 | **1.19× faster** |
| bench_gray_1024 | **79.9** | 128.7 | 62.2 | **1.61× faster** |
| bench_gray_2048 | **179.0** | 411.3 | 122.8 | **2.30× faster** |
| bench_color_512 | 104.0 | 89.7 | 51.9 | 1.16× slower |
| bench_color_1024 | **223.4** | 237.5 | 80.4 | **1.06× faster** |

> **Encode summary:** J2KSwift is now clearly ahead of OpenJPEG on the larger grayscale cases and roughly competitive on the larger color case, but Grok remains the fastest codec in the full matrix.

---

## Decode Performance

### Lossless Decode

| Image | J2KSwift (ms) | OpenJPEG (ms) | Grok (ms) | J2K vs OPJ |
|-------|:---:|:---:|:---:|:---:|
| bench_gray_256 | 45.6 | 41.2 | 42.7 | 1.11× slower |
| bench_gray_512 | 56.2 | 56.0 | 44.6 | ~tie |
| bench_gray_1024 | **105.6** | 113.3 | 53.7 | **1.07× faster** |
| bench_gray_2048 | **271.9** | 313.7 | 77.3 | **1.15× faster** |
| bench_color_512 | **57.3** | 72.5 | 40.6 | **1.27× faster** |
| bench_color_1024 | **121.5** | 185.0 | 53.8 | **1.52× faster** |

### Lossy Decode

| Image | J2KSwift (ms) | OpenJPEG (ms) | Grok (ms) | J2K vs OPJ |
|-------|:---:|:---:|:---:|:---:|
| bench_gray_256 | 37.0 | 33.7 | 36.1 | 1.10× slower |
| bench_gray_512 | 44.0 | 43.0 | 37.9 | 1.02× slower |
| bench_gray_1024 | **66.1** | 75.2 | 44.8 | **1.14× faster** |
| bench_gray_2048 | **131.3** | 216.0 | 54.5 | **1.65× faster** |
| bench_color_512 | **53.6** | 64.0 | 39.9 | **1.19× faster** |
| bench_color_1024 | **123.5** | 197.9 | 61.2 | **1.60× faster** |

> **Decode summary:** J2KSwift now beats OpenJPEG on all of the larger decode workloads and shows especially strong gains on 2048×2048 grayscale and 1024×1024 color.

---

## Compressed File Sizes

| Image | Mode | J2KSwift (bytes) | OpenJPEG (bytes) | Grok (bytes) | J2K vs OPJ |
|-------|------|:---:|:---:|:---:|:---:|
| bench_gray_256 | lossless | 2,100 | 2,139 | 2,136 | -1.8% |
| bench_gray_256 | lossy | 1,003 | 2,139 | 2,133 | -53.1% |
| bench_gray_512 | lossless | 30,146 | 30,185 | 30,182 | -0.1% |
| bench_gray_512 | lossy | 11,249 | 13,077 | 13,047 | -14.0% |
| bench_gray_1024 | lossless | 139,973 | 140,012 | 140,009 | -0.03% |
| bench_gray_1024 | lossy | 53,092 | 52,378 | 52,283 | +1.4% |
| bench_gray_2048 | lossless | 823,658 | 823,697 | 823,694 | -0.005% |
| bench_gray_2048 | lossy | 211,205 | 208,477 | 208,820 | +1.3% |
| bench_color_512 | lossless | 79,432 | 79,471 | 79,468 | -0.05% |
| bench_color_512 | lossy | 13,413 | 39,206 | 39,287 | -65.8% ⚠️ |
| bench_color_1024 | lossless | 276,343 | 276,382 | 276,379 | -0.01% |
| bench_color_1024 | lossy | 49,143 | 157,122 | 157,250 | -68.7% ⚠️ |

> **Size summary:** lossless file sizes still match the reference codecs extremely closely. The table above captures the earlier pre-fix snapshot; the focused post-fix RGB rerun now lands on the intended byte budgets.

---

## Quality Metrics (1024×1024 Grayscale, Lossy ~20:1)

| Metric | J2KSwift | OpenJPEG | Grok | J2K vs OPJ |
|--------|:---:|:---:|:---:|:---:|
| PSNR (dB) | 22.7361 | 31.4794 | 31.4044 | -8.7433 dB |
| MSE | 346.317686 | 46.253155 | 47.058750 | +648.8% |
| MAE | 14.089388 | 4.365349 | 4.377127 | +222.8% |
| Max Error | 97 | 84 | 86 | — |

### Cross-Codec Validation Of J2KSwift Output

| Decode Path | PSNR (dB) | MSE | MAE | Max Error |
|-------------|:---------:|:---:|:---:|:---------:|
| J2KSwift → J2KSwift | 22.7361 | 346.317686 | 14.089388 | 97 |
| J2KSwift → OpenJPEG | 22.7357 | 346.342674 | 14.089888 | 97 |
| J2KSwift lossless → OpenJPEG | Inf | 0.000000 | 0.000000 | 0 |

### Focused Internal Pipeline Profile (Fresh 1024×1024 Run)

#### Lossy Encode, q = 0.5

| Stage | Time |
|-------|------|
| Preprocess | 1.8 ms |
| Color Transform | 0.1 ms |
| DWT | 8.5 ms |
| Entropy Extract | 1.4 ms |
| Entropy Encode | 17.2 ms |
| Total Entropy | 19.0 ms |
| Rate Control | 1.6 ms |
| Codestream | 2.4 ms |

#### Lossless Encode

| Stage | Time |
|-------|------|
| Preprocess | 1.3 ms |
| Color Transform | 0.1 ms |
| DWT | 11.6 ms |
| Entropy Encode | 42.4 ms |
| Total Entropy | 42.6 ms |
| Rate Control | 0.1 ms |
| Codestream | 2.0 ms |

> **Quality summary:** interoperability is solid and lossless remains exact, but the current lossy J2KSwift path is still well behind OpenJPEG and Grok in rate-distortion quality on the grayscale benchmark case.

---

## Pillow 11.3 Comparison (Lossless)

| Image | Pillow Encode (ms) | J2KSwift Encode (ms) | Pillow Decode (ms) | J2KSwift Decode (ms) |
|-------|:---:|:---:|:---:|:---:|
| 256×256 gray | 5.4 | 45.1 | 5.4 | 45.6 |
| 512×512 gray | 35.7 | 59.6 | 32.1 | 56.2 |
| 1024×1024 gray | 149.3 | **109.9** | 140.4 | **105.6** |
| 2048×2048 gray | 697.3 | **327.9** | 684.0 | **271.9** |
| 512×512 color | 37.5 | 91.8 | 46.5 | 57.3 |
| 1024×1024 color | 121.3 | 238.0 | 171.8 | **121.5** |

> J2KSwift now clearly outperforms Pillow on the larger grayscale cases and is also faster on 1024×1024 color decode.

---

## Cross-Codec Interoperability (1024×1024 Lossless)

All 6/6 encoder↔decoder pairs pass:

| Encoded By | Decoded By | Result |
|-----------|-----------|--------|
| J2KSwift | OpenJPEG | ✅ OK |
| J2KSwift | Grok | ✅ OK |
| OpenJPEG | J2KSwift | ✅ OK |
| OpenJPEG | Grok | ✅ OK |
| Grok | J2KSwift | ✅ OK |
| Grok | OpenJPEG | ✅ OK |

---

## Analysis

### Strengths

- **Large grayscale throughput:** J2KSwift outperformed OpenJPEG on the larger grayscale encode and decode cases, including **2048×2048 lossy encode** at **179.0 ms vs 411.3 ms**.
- **Color decode is now ahead of OpenJPEG in this run:** **57.3 ms vs 72.5 ms** at 512×512 and **121.5 ms vs 185.0 ms** at 1024×1024.
- **Lossless file size efficiency remains excellent:** the lossless outputs stayed within a few dozen bytes of OpenJPEG and Grok.
- **Interoperability remains strong:** all **6 / 6** cross-codec encode→decode combinations completed successfully, and OpenJPEG decoded the J2KSwift lossless output bit-exactly.

### Known Limitations

1. **Lossy quality gap on the main grayscale benchmark remains large:** at roughly matched file size on 1024×1024 grayscale, J2KSwift measured **22.7361 dB** vs **31.4794 dB** for OpenJPEG.

2. **Lossy grayscale rate-distortion quality still needs work:** the color size undershoot has been fixed, but the main grayscale PSNR gap versus OpenJPEG and Grok remains.

3. **Grok still leads the overall wall-clock race:** J2KSwift narrowed the gap versus OpenJPEG, but Grok remains faster across the full matrix.

4. **Small-image startup overhead is still visible:** the 256×256 paths remain slightly slower than the C/C++ codecs.

### Next Optimization Targets

| Priority | Target | Expected Gain |
|----------|--------|--------------|
| High | Full release benchmark refresh after the latest PCRD fix | Quantify the grayscale quality lift with verified numbers |
| High | Additional grayscale distortion-model refinement for standard EBCOT | Further close the remaining PSNR gap at matched size |
| Medium | Further Tier-1 hot-path reductions | Narrow the remaining gap to Grok |
| Medium | Fine-tune constant-quality bitrate mapping after the PCRD correction | Improve matched-size consistency |
| Low | Small-image fast path cleanup | Reduce process and setup overhead |

---

## Reproducibility

```bash
# Build release binary
swift build -c release

# Generate the benchmark inputs under /tmp using the Python snippets
# from the benchmark procedure for the grayscale and color test images.

# Run the full multi-codec benchmark
bash Scripts/multi_codec_benchmark_v2.sh

# Results written to /tmp/multi_codec_results.csv
```

The benchmark inputs for this report were generated locally with simple Python image generators before the full matrix was executed.
