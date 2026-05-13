# J2KSwift Performance Results

**Date:** April 14, 2026  
**Build:** Release (`swift build -c release`), Swift 6.2  
**Platform:** Apple M2 (8-core), 24 GB RAM, macOS 15.7.5 (arm64)  
**Runs:** 5 per test (+ 1 warmup), median reported

---

## Codec Versions

| Codec | Version | Notes |
|-------|---------|-------|
| J2KSwift | v2.4.0-dev (post-optimization) | Pure Swift 6, single-threaded pipeline |
| OpenJPEG | 2.5.4 | ISO reference C implementation |
| Grok | latest | Multi-threaded C++ codec |
| Pillow | 11.3 | Python bindings (OpenJPEG backend) |

---

## Optimizations Applied

| # | Optimization | File(s) | Impact |
|---|-------------|---------|--------|
| 1 | Rate control recalibration | `J2KRateControl.swift` | +8.25 dB PSNR for lossy grayscale |
| 2 | Subband pre-indexing | `J2KDecoderPipeline.swift` | O(1) vs O(n) component lookup |
| 3 | Component-parallel IDWT | `J2KDecoderPipeline.swift` | Concurrent decode for ≥2 components |
| 4 | Parallel 9/7 2D DWT | `J2KDWT1DOptimized.swift` | Concurrent row/column transforms (≥8) |
| 5 | Double-precision inverse RCT | `J2KColorTransform.swift` | Eliminated 6 temp allocations per decode |

---

## Encode Performance

### Lossless (5/3 DWT)

| Image | J2KSwift | OpenJPEG | Grok | vs OPJ |
|-------|-------:|-------:|-------:|:------:|
| 256×256 gray | 28.2 ms | 24.9 ms | 25.4 ms | 1.13× slower |
| 512×512 gray | 40.1 ms | 36.3 ms | 27.9 ms | 1.10× slower |
| 1024×1024 gray | 76.5 ms | 75.6 ms | 35.2 ms | 1.01× slower |
| 2048×2048 gray | **226.0 ms** | 258.0 ms | 67.6 ms | **1.14× faster** |
| 512×512 RGB | 64.9 ms | 54.1 ms | 31.1 ms | 1.20× slower |
| 1024×1024 RGB | 172.1 ms | 146.2 ms | 46.6 ms | 1.18× slower |

### Lossy (9/7 DWT, ~20:1)

| Image | J2KSwift | OpenJPEG | Grok | vs OPJ |
|-------|-------:|-------:|-------:|:------:|
| 256×256 gray | 29.3 ms | 25.3 ms | 25.6 ms | 1.16× slower |
| 512×512 gray | 42.8 ms | 36.5 ms | 27.8 ms | 1.17× slower |
| 1024×1024 gray | 89.5 ms | 77.0 ms | 35.7 ms | 1.16× slower |
| 2048×2048 gray | 273.1 ms | 260.0 ms | 68.9 ms | 1.05× slower |
| 512×512 RGB | 66.1 ms | 54.7 ms | 31.7 ms | 1.21× slower |
| 1024×1024 RGB | 178.4 ms | 147.7 ms | 47.5 ms | 1.21× slower |

**Summary:** J2KSwift encode is within 1.01–1.21× of OpenJPEG, and **faster at 2048² lossless**. Grok is 2–4× faster due to multi-threaded C++ pipeline.

---

## Decode Performance

### Lossless

| Image | J2KSwift | OpenJPEG | Grok | vs OPJ |
|-------|-------:|-------:|-------:|:------:|
| 256×256 gray | 26.5 ms | 24.6 ms | 25.3 ms | 1.08× slower |
| 512×512 gray | **33.5 ms** | 34.6 ms | 27.9 ms | **1.03× faster** |
| 1024×1024 gray | **58.3 ms** | 69.4 ms | 32.2 ms | **1.19× faster** |
| 2048×2048 gray | **162.2 ms** | 233.3 ms | 53.9 ms | **1.44× faster** |
| 512×512 RGB | 82.8 ms | 51.2 ms | 28.5 ms | 1.62× slower |
| 1024×1024 RGB | 243.6 ms | 137.2 ms | 38.3 ms | 1.77× slower |

### Lossy

| Image | J2KSwift | OpenJPEG | Grok | vs OPJ |
|-------|-------:|-------:|-------:|:------:|
| 256×256 gray | 26.9 ms | 24.7 ms | 25.8 ms | 1.09× slower |
| 512×512 gray | **30.0 ms** | 31.0 ms | 26.9 ms | **1.03× faster** |
| 1024×1024 gray | **44.1 ms** | 56.1 ms | 29.9 ms | **1.27× faster** |
| 2048×2048 gray | **89.1 ms** | 151.7 ms | 38.8 ms | **1.70× faster** |
| 512×512 RGB | 81.1 ms | 47.3 ms | 28.3 ms | 1.71× slower |
| 1024×1024 RGB | 239.1 ms | 123.6 ms | 35.9 ms | 1.93× slower |

**Summary:** Grayscale decode is **up to 1.70× faster** than OpenJPEG at large sizes. Color decode is 1.6–1.9× slower (EBCOT/DWT bottleneck, not color transform).

---

## Quality Metrics (1024×1024 Grayscale, Lossy ~20:1)

| Metric | J2KSwift | OpenJPEG | Grok |
|--------|-------:|-------:|-------:|
| PSNR | 29.85 dB | 31.48 dB | 31.40 dB |
| MSE | 67.26 | 46.25 | 47.06 |
| MAE | 5.13 | 4.37 | 4.38 |
| Max Error | 64 | 84 | 86 |

### PSNR Improvement

| | Before | After | Delta |
|---|-------:|-------:|------:|
| J2KSwift | 21.6 dB | **29.85 dB** | **+8.25 dB** |
| Gap vs OpenJPEG | 9.9 dB | **1.63 dB** | **−8.3 dB** |

---

## Compressed File Sizes

| Image | Mode | J2KSwift | OpenJPEG | vs OPJ |
|-------|------|-------:|-------:|:------:|
| 256×256 gray | lossless | 2,100 B | 2,139 B | −1.8% |
| 512×512 gray | lossless | 35,737 B | 35,776 B | −0.1% |
| 1024×1024 gray | lossless | 139,973 B | 140,012 B | −0.03% |
| 2048×2048 gray | lossless | 828,040 B | 828,079 B | −0.005% |
| 512×512 RGB | lossless | 79,432 B | 79,471 B | −0.05% |
| 1024×1024 RGB | lossless | 284,905 B | 284,944 B | −0.01% |
| 256×256 gray | lossy | 3,441 B | 2,139 B | +60.9% |
| 512×512 gray | lossy | 13,346 B | 13,064 B | +2.2% |
| 1024×1024 gray | lossy | 52,962 B | 52,378 B | +1.1% |
| 2048×2048 gray | lossy | 211,250 B | 203,682 B | +3.7% |
| 512×512 RGB | lossy | 13,484 B | 39,206 B | −65.6% ⚠️ |
| 1024×1024 RGB | lossy | 53,042 B | 156,934 B | −66.2% ⚠️ |

> **Lossless** sizes match OpenJPEG within 39 bytes (header-only difference).  
> ⚠️ **Lossy color** sizes are ~3× too small — rate control for multi-component images needs separate calibration.

---

## Pillow 11.3 Comparison (Lossless)

| Image | Pillow Enc | J2KSwift Enc | Pillow Dec | J2KSwift Dec |
|-------|-------:|-------:|-------:|-------:|
| 256×256 gray | 3.0 ms | 28.2 ms | 3.0 ms | 26.5 ms |
| 512×512 gray | 22.8 ms | 40.1 ms | 21.0 ms | 33.5 ms |
| 1024×1024 gray | 87.8 ms | **76.5 ms** | 81.9 ms | **58.3 ms** |
| 2048×2048 gray | 433.6 ms | **226.0 ms** | 412.7 ms | **162.2 ms** |
| 512×512 RGB | 21.1 ms | 64.9 ms | 28.4 ms | 82.8 ms |
| 1024×1024 RGB | 76.5 ms | 172.1 ms | 111.8 ms | 243.6 ms |

J2KSwift outperforms Pillow at ≥1024² grayscale (1.15–2.54× faster).

---

## Cross-Codec Interoperability

All 6/6 encoder↔decoder combinations pass lossless round-trip (1024×1024):

| Encoded By | Decoded By | Status |
|-----------|-----------|:------:|
| J2KSwift | OpenJPEG | ✅ |
| J2KSwift | Grok | ✅ |
| OpenJPEG | J2KSwift | ✅ |
| OpenJPEG | Grok | ✅ |
| Grok | J2KSwift | ✅ |
| Grok | OpenJPEG | ✅ |

---

## Known Limitations

| Issue | Detail | Status |
|-------|--------|--------|
| Color decode 1.8× slower | EBCOT/DWT bottleneck for multi-component images | Profiling needed |
| Lossy color rate ~3× low | `qualityToBitrate()` needs multi-component calibration | Fix pending |
| Small image overhead | Fixed startup cost dominates at ≤512² | Acceptable |
| Grok 2–4× faster | Multi-threaded C++; J2KSwift is single-threaded pipeline | Parallel tiles planned |

---

## Reproducibility

```bash
swift build -c release
bash Scripts/multi_codec_benchmark_v2.sh
# Results: /tmp/multi_codec_results.csv
```

---

## Appendix: Raw CSV Data

```csv
codec,mode,image,dimensions,time_ms,output_bytes
j2kswift,lossless_encode,bench_gray_256.pgm,bench_gray_256,28.2,2100
openjpeg,lossless_encode,bench_gray_256.pgm,bench_gray_256,24.9,2139
grok,lossless_encode,bench_gray_256.pgm,bench_gray_256,25.4,2136
j2kswift,lossless_encode,bench_gray_512.pgm,bench_gray_512,40.1,35737
openjpeg,lossless_encode,bench_gray_512.pgm,bench_gray_512,36.3,35776
grok,lossless_encode,bench_gray_512.pgm,bench_gray_512,27.9,35773
j2kswift,lossless_encode,bench_gray_1024.pgm,bench_gray_1024,76.5,139973
openjpeg,lossless_encode,bench_gray_1024.pgm,bench_gray_1024,75.6,140012
grok,lossless_encode,bench_gray_1024.pgm,bench_gray_1024,35.2,140009
j2kswift,lossless_encode,bench_gray_2048.pgm,bench_gray_2048,226.0,828040
openjpeg,lossless_encode,bench_gray_2048.pgm,bench_gray_2048,258.0,828079
grok,lossless_encode,bench_gray_2048.pgm,bench_gray_2048,67.6,828076
j2kswift,lossless_encode,bench_color_512.ppm,bench_color_512,64.9,79432
openjpeg,lossless_encode,bench_color_512.ppm,bench_color_512,54.1,79471
grok,lossless_encode,bench_color_512.ppm,bench_color_512,31.1,79468
j2kswift,lossless_encode,bench_color_1024.ppm,bench_color_1024,172.1,284905
openjpeg,lossless_encode,bench_color_1024.ppm,bench_color_1024,146.2,284944
grok,lossless_encode,bench_color_1024.ppm,bench_color_1024,46.6,284941
j2kswift,lossy_encode,bench_gray_256.pgm,bench_gray_256,29.3,3441
openjpeg,lossy_encode,bench_gray_256.pgm,bench_gray_256,25.3,2139
grok,lossy_encode,bench_gray_256.pgm,bench_gray_256,25.6,2133
j2kswift,lossy_encode,bench_gray_512.pgm,bench_gray_512,42.8,13346
openjpeg,lossy_encode,bench_gray_512.pgm,bench_gray_512,36.5,13064
grok,lossy_encode,bench_gray_512.pgm,bench_gray_512,27.8,13061
j2kswift,lossy_encode,bench_gray_1024.pgm,bench_gray_1024,89.5,52962
openjpeg,lossy_encode,bench_gray_1024.pgm,bench_gray_1024,77.0,52378
grok,lossy_encode,bench_gray_1024.pgm,bench_gray_1024,35.7,52283
j2kswift,lossy_encode,bench_gray_2048.pgm,bench_gray_2048,273.1,211250
openjpeg,lossy_encode,bench_gray_2048.pgm,bench_gray_2048,260.0,203682
grok,lossy_encode,bench_gray_2048.pgm,bench_gray_2048,68.9,201326
j2kswift,lossy_encode,bench_color_512.ppm,bench_color_512,66.1,13484
openjpeg,lossy_encode,bench_color_512.ppm,bench_color_512,54.7,39206
grok,lossy_encode,bench_color_512.ppm,bench_color_512,31.7,39287
j2kswift,lossy_encode,bench_color_1024.ppm,bench_color_1024,178.4,53042
openjpeg,lossy_encode,bench_color_1024.ppm,bench_color_1024,147.7,156934
grok,lossy_encode,bench_color_1024.ppm,bench_color_1024,47.5,157133
j2kswift,lossless_decode,bench_gray_256.pgm,bench_gray_256,26.5,0
openjpeg,lossless_decode,bench_gray_256.pgm,bench_gray_256,24.6,0
grok,lossless_decode,bench_gray_256.pgm,bench_gray_256,25.3,0
j2kswift,lossless_decode,bench_gray_512.pgm,bench_gray_512,33.5,0
openjpeg,lossless_decode,bench_gray_512.pgm,bench_gray_512,34.6,0
grok,lossless_decode,bench_gray_512.pgm,bench_gray_512,27.9,0
j2kswift,lossless_decode,bench_gray_1024.pgm,bench_gray_1024,58.3,0
openjpeg,lossless_decode,bench_gray_1024.pgm,bench_gray_1024,69.4,0
grok,lossless_decode,bench_gray_1024.pgm,bench_gray_1024,32.2,0
j2kswift,lossless_decode,bench_gray_2048.pgm,bench_gray_2048,162.2,0
openjpeg,lossless_decode,bench_gray_2048.pgm,bench_gray_2048,233.3,0
grok,lossless_decode,bench_gray_2048.pgm,bench_gray_2048,53.9,0
j2kswift,lossless_decode,bench_color_512.ppm,bench_color_512,82.8,0
openjpeg,lossless_decode,bench_color_512.ppm,bench_color_512,51.2,0
grok,lossless_decode,bench_color_512.ppm,bench_color_512,28.5,0
j2kswift,lossless_decode,bench_color_1024.ppm,bench_color_1024,243.6,0
openjpeg,lossless_decode,bench_color_1024.ppm,bench_color_1024,137.2,0
grok,lossless_decode,bench_color_1024.ppm,bench_color_1024,38.3,0
j2kswift,lossy_decode,bench_gray_256.pgm,bench_gray_256,26.9,0
openjpeg,lossy_decode,bench_gray_256.pgm,bench_gray_256,24.7,0
grok,lossy_decode,bench_gray_256.pgm,bench_gray_256,25.8,0
j2kswift,lossy_decode,bench_gray_512.pgm,bench_gray_512,30.0,0
openjpeg,lossy_decode,bench_gray_512.pgm,bench_gray_512,31.0,0
grok,lossy_decode,bench_gray_512.pgm,bench_gray_512,26.9,0
j2kswift,lossy_decode,bench_gray_1024.pgm,bench_gray_1024,44.1,0
openjpeg,lossy_decode,bench_gray_1024.pgm,bench_gray_1024,56.1,0
grok,lossy_decode,bench_gray_1024.pgm,bench_gray_1024,29.9,0
j2kswift,lossy_decode,bench_gray_2048.pgm,bench_gray_2048,89.1,0
openjpeg,lossy_decode,bench_gray_2048.pgm,bench_gray_2048,151.7,0
grok,lossy_decode,bench_gray_2048.pgm,bench_gray_2048,38.8,0
j2kswift,lossy_decode,bench_color_512.ppm,bench_color_512,81.1,0
openjpeg,lossy_decode,bench_color_512.ppm,bench_color_512,47.3,0
grok,lossy_decode,bench_color_512.ppm,bench_color_512,28.3,0
j2kswift,lossy_decode,bench_color_1024.ppm,bench_color_1024,239.1,0
openjpeg,lossy_decode,bench_color_1024.ppm,bench_color_1024,123.6,0
grok,lossy_decode,bench_color_1024.ppm,bench_color_1024,35.9,0
pillow,lossless_encode,bench_gray_256.pgm,256x256,3.0,2139
pillow,lossless_decode,bench_gray_256.pgm,256x256,3.0,0
pillow,lossless_encode,bench_gray_512.pgm,512x512,22.8,35776
pillow,lossless_decode,bench_gray_512.pgm,512x512,21.0,0
pillow,lossless_encode,bench_gray_1024.pgm,1024x1024,87.8,140012
pillow,lossless_decode,bench_gray_1024.pgm,1024x1024,81.9,0
pillow,lossless_encode,bench_gray_2048.pgm,2048x2048,433.6,828079
pillow,lossless_decode,bench_gray_2048.pgm,2048x2048,412.7,0
pillow,lossless_encode,bench_color_512.ppm,512x512,21.1,29356
pillow,lossless_decode,bench_color_512.ppm,512x512,28.4,0
pillow,lossless_encode,bench_color_1024.ppm,1024x1024,76.5,96466
pillow,lossless_decode,bench_color_1024.ppm,1024x1024,111.8,0
```
