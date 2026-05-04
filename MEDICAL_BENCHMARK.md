# Medical Imaging Benchmark: J2KSwift vs OpenJPEG

**Date:** 2026-05-03 13:05

## Test Images

| Modality | Dimensions | Bit Depth | Description |
|----------|-----------|-----------|-------------|
| CT | 512×512 | 16-bit | Synthetic chest CT (HU range simulation) |
| MRI | 256×256 | 12-bit | Synthetic T1-weighted brain MRI |
| Ultrasound | 640×480 | 12-bit | Synthetic sector ultrasound with speckle |

## Results

| Modality | Bits | Bitrate | J2K PSNR | J2K SSIM | J2K MAE | OPJ PSNR | OPJ SSIM | OPJ MAE | ΔPSNR |
|----------|------|---------|----------|----------|---------|----------|----------|---------|-------|
| CT | 16 | 0.25bpp | 51.74 | 0.9934 | 128.35 | 52.11 | 0.9939 | 124.31 | -0.37 |
| CT | 16 | 0.50bpp | 55.15 | 0.9966 | 90.25 | 55.46 | 0.9970 | 87.01 | -0.31 |
| CT | 16 | 0.75bpp | 57.88 | 0.9983 | 65.24 | 57.75 | 0.9983 | 66.06 | +0.13 |
| CT | 16 | lossless | ∞ | 1.0000 | 0.00 | ∞ | 1.0000 | 0.00 | 0.00 |
| MRI | 12 | 0.25bpp | 37.97 | 0.9529 | 36.62 | 33.75 | 0.9232 | 53.00 | +4.22 |
| MRI | 12 | 0.50bpp | 42.48 | 0.9748 | 23.42 | 39.75 | 0.9649 | 29.88 | +2.74 |
| MRI | 12 | 0.75bpp | 45.37 | 0.9837 | 17.33 | 43.13 | 0.9756 | 21.70 | +2.25 |
| MRI | 12 | lossless | ∞ | 1.0000 | 0.00 | ∞ | 1.0000 | 0.00 | 0.00 |
| Ultrasound | 12 | 0.25bpp | 28.79 | 0.8165 | 73.39 | 27.97 | 0.7871 | 80.25 | +0.81 |
| Ultrasound | 12 | 0.50bpp | 31.63 | 0.8950 | 53.69 | 29.80 | 0.8768 | 64.99 | +1.84 |
| Ultrasound | 12 | 0.75bpp | 35.11 | 0.9616 | 35.94 | 31.93 | 0.9280 | 50.68 | +3.18 |
| Ultrasound | 12 | lossless | ∞ | 1.0000 | 0.00 | ∞ | 1.0000 | 0.00 | 0.00 |

## Notes

- PSNR: Peak Signal-to-Noise Ratio (dB) — higher is better
- SSIM: Structural Similarity Index — closer to 1.0 is better
- MAE: Mean Absolute Error — lower is better
- ΔPSNR: J2K PSNR minus OPJ PSNR (positive = J2K better)
- Lossless: exact reconstruction (PSNR = ∞, MAE = 0)

---

## Decode Performance (v5.28.0)

Per-fixture warm-session decode time across three APIs, measured on the medical DICOM
corpus in `Tests/Fixtures/CrossCodec`. All numbers are release-mode medians (n=5 after
warm-up) on M2, HT-conformant lossy 9/7 @ 2 bpp. Reproducible via:

```bash
swift test -c release --filter J2KMedicalCorpus
```

### Per-fixture decode time (ms, lower = faster)

| Fixture                | Pixels    | CPU `decode` | `decodeGPU(_:session:)` | `decodeWithGPUHT(_:session:)` | Winner |
|------------------------|----------:|-------------:|-------------------------:|------------------------------:|---|
| mr_002 (180×180)       |    32,400 |          1.2 |                      1.2 |                          4.7 | CPU¹ |
| ct_001 (512×512)       |   262,144 |          7.1 |                      4.4 |                         17.1 | decodeGPU |
| ct_003 (512×512)       |   262,144 |          7.4 |                      3.7 |                          9.3 | decodeGPU |
| mr_001 (886×886)       |   784,996 |         21.0 |                      9.0 |                         13.2 | decodeGPU |
| xa_001 (1024×1024)     | 1,048,576 |         25.6 |                      8.8 |                         14.0 | decodeGPU |
| px_001 (2459×1316)     | 3,236,044 |         86.2 |                     30.3 |                         **26.7** | decodeWithGPUHT |
| dx_002 (2800×2288)     | 6,406,400 |        167.8 |                     46.0 |                         **42.0** | decodeWithGPUHT |
| dx_001 (2544×3056)*    | 7,774,464 |        223.6 |                     56.5 |                         **51.2** | decodeWithGPUHT |
| mg_001 (3520×4784)*    | 16,839,680 |        502.8 |                    140.2 |                        **110.2** | decodeWithGPUHT |
| mg_002 (3521×4784)*    | 16,844,464 |        499.7 |                    152.9 |                        **113.6** | decodeWithGPUHT |

¹ At 180×180 the median is within run-to-run variance (Metal dispatch ≈ CPU decode time);
both GPU APIs return ~1.2 ms. CPU is the safe default for this size class.

\* v5.28.0 synthetic fixtures (LCG noise at the indicated dimensions). The real
mammography PGMs aren't in-repo (~32 MB each). Decode timing scales with pixel count and
constant-bitrate bitstream length, both of which match the real fixtures, so the routing-
rule characterisation remains valid.

### Per-fixture speedup (×, higher = faster)

| Fixture                | `decodeGPU`× CPU | `decodeWithGPUHT`× CPU |
|------------------------|-----------------:|------------------------:|
| mr_002 (180×180)       |             1.0× |                    0.3× |
| ct_001 (512×512)       |             1.6× |                    0.4× |
| ct_003 (512×512)       |             2.0× |                    0.8× |
| mr_001 (886×886)       |             2.3× |                    1.6× |
| xa_001 (1024×1024)     |             2.9× |                    1.8× |
| px_001 (2459×1316)     |             2.8× |                **3.2×** |
| dx_002 (2800×2288)     |             3.7× |                **4.0×** |
| dx_001 (2544×3056)*    |             4.0× |                **4.4×** |
| mg_001 (3520×4784)*    |             3.6× |                **4.6×** |
| mg_002 (3521×4784)*    |             3.3× |                **4.4×** |

The crossover is decisive: `decodeWithGPUHT` overtakes `decodeGPU` at ~3M pixels and
keeps gaining headroom up through 17M pixels (mammography), where it hits **4.6× CPU**.

### Routing recommendation

The crossover is decisive: `decodeGPU` wins below ~1M pixels; `decodeWithGPUHT` wins above
~3M pixels. The v5.27.0 helper `J2KDecoder.recommendedDecodeAPI(width:height:)` codifies
this:

| Pixel count          | Recommended API                  | Reason |
|----------------------|----------------------------------|--------|
| `< 65,536` (256²)    | CPU `decode(_:)`                 | Metal dispatch overhead cancels GPU compute on tiny images |
| `< 3,000,000`        | `decodeGPU(_:session:)`          | CPU HT entropy (~1–2 ms parallelised) is cheaper than GPU HT dispatch (~7 ms) at this size; GPU IDWT is the dominant lever |
| `≥ 3,000,000`        | `decodeWithGPUHT(_:session:)`    | GPU HT dispatch amortises across larger codeblock counts; full GPU pipeline wins |

Cold-start Metal overhead is ~50 ms regardless of image size — for genuine one-off
decodes (no shared session), prefer CPU `decode` even when dimensions are large.

### What changed in v5.27.0 (vs v5.26.0)

`decodeWithGPUHT` 9/7 lossy got materially faster on large workloads after v5.27.0
introduced a CPU-work skip on the Float fused-from-codeblocks path. The `[SubbandInfo]`
regroup loop and the per-subband CPU dequantisation pass are now skipped when the GPU
scatter+dequant kernel produces the dequantised Float subbands directly:

| Fixture            | v5.26.0 `decodeWithGPUHT` | v5.27.0 `decodeWithGPUHT` | Δ |
|--------------------|--------------------------:|---------------------------:|----:|
| px_001 (2459×1316) |                    41.0 ms |                    27.2 ms | **−14 ms** |
| dx_002 (2800×2288) |                    46.9 ms |                    42.7 ms |  −4 ms |

Per-stage `decodeWithGPUHT` breakdown (typical post-v5.27.0 run on dx_002 2800×2288):

| Stage                       | ms |
|-----------------------------|----:|
| `gpuHTDispatch`             |  8.9 |
| build Float plans (regroup) |  0.6 |
| CPU dequant                 | **0.0** ← v5.27.0: was ~4 ms |
| `inverseWaveletTransform`   | 25.6 |

---

## Cold-Start vs `preWarm()` (v5.28.0)

A fresh `J2KMetalSession` pays ~30–50 ms on the first decode for Metal device init,
shader-library load, pipeline-state creation, VLC-table upload, and Metal driver
first-dispatch fence. Subsequent decodes on the same session run at warm-baseline speed
(~10–15 ms for a 512×512 fixture).

`J2KMetalSession.preWarm()` (v5.28.0) does the cold-start work up front so the first
*user* decode runs at warm speed:

| Metric (512×512 16-bit lossy 9/7, M2, release) | Without `preWarm` | With `preWarm` |
|------------------------------------------------|------------------:|---------------:|
| Cold first decode                              |        40–49 ms   |          —     |
| `preWarm()` call itself                        |          —        |     27–32 ms   |
| First user decode after `preWarm`              |          —        |     **9–16 ms** |
| Warm baseline (subsequent decodes)             |        10–15 ms   |     10–15 ms   |
| Cold-start cost eliminated                     |          —        |     25–30 ms   |

What `preWarm` does:

1. Initialises the `MTLDevice` and `MTLCommandQueue`.
2. Loads the shader library (bundled `default.metallib` or in-source compile).
3. Pre-creates `MTLComputePipelineState` for every decode-hot-path kernel, in parallel.
4. Runs a tiny synthetic 256×256 decode through `decodeWithGPUHT` to exercise the rest
   of the lazy-init paths (VLC table upload, buffer pool first-fetch, Metal driver
   first-dispatch fence). Without this step `preWarm` only saves ~10–13 ms instead of
   the full 25–30 ms.

**When to use:** PACS daemons, batch decoders, server-side workers — anywhere a
long-lived process decodes many images. Call `preWarm` once at SDK init.

**When to skip:** genuine one-off CLI invocations. Total wall-clock for `preWarm` + 1
decode (~36–46 ms) is roughly the same as cold first decode (~40–49 ms), so the savings
need at least a second decode to be worthwhile.

Reproducible via:

```bash
swift test -c release --filter testColdStartVsPreWarm
```

---

## Encode Performance (v5.29.0)

After v5.28.0 brought decode 9/7 lossy on mammography to 4.6× CPU, encode is the next
lever. v5.29.0 adds `J2KEncodeTimings` (always-on per-stage accumulator, mirrors the
v5.24.0 decode-side timings) and a corpus encode benchmark
(`J2KMedicalCorpusEncodePerformanceTests`). All numbers are release-mode medians (n=5
after warm-up) on M2, HT-conformant lossy 9/7 @ 2 bpp:

```bash
swift test -c release --filter J2KMedicalCorpusEncode
```

### Per-fixture encode time (ms, lower = faster)

| Fixture                | Pixels    | CPU `encode` | `encodeGPU` | CPU/GPU× |
|------------------------|----------:|-------------:|------------:|---------:|
| mr_002 (180×180)       |    32,400 |          2.4 |         2.3 |    1.02× |
| ct_001 (512×512)       |   262,144 |          4.1 |         4.2 |    0.97× |
| ct_003 (512×512)       |   262,144 |          3.8 |         3.9 |    0.98× |
| mr_001 (886×886)       |   784,996 |          6.0 |         6.0 |    1.01× |
| xa_001 (1024×1024)     | 1,048,576 |         17.0 |        27.7 | **0.61×** |
| px_001 (2459×1316)     | 3,236,044 |         50.1 |        68.7 | **0.73×** |
| dx_002 (2800×2288)     | 6,406,400 |        110.1 |       132.5 | **0.83×** |
| dx_001 (2544×3056)*    | 7,774,464 |        239.6 |       262.6 |    0.91× |
| mg_001 (3520×4784)*    | 16,839,680 |       899.7 |       979.0 |    0.92× |
| mg_002 (3521×4784)*    | 16,844,464 |       920.5 |       972.9 |    0.95× |

`*` synthetic LCG-noise fixtures at the indicated dimensions.

### Per-fixture CPU encode stage breakdown (ms)

| Fixture                | preproc | colour | DWT  | quant | entropy | rateCtrl | codestream |
|------------------------|--------:|-------:|-----:|------:|--------:|---------:|-----------:|
| ct_001 (512×512)       |     0.3 |    0.0 |  0.8 |   0.1 |     2.0 |      0.4 |        0.6 |
| xa_001 (1024×1024)     |     1.2 |    0.0 |  3.3 |   0.1 |     7.6 |      2.6 |        1.9 |
| px_001 (2459×1316)     |     3.8 |    0.0 | 10.4 |   0.1 |    24.6 |      7.4 |        5.7 |
| dx_002 (2800×2288)     |     7.4 |    0.0 | 21.5 |   0.1 |    46.3 |     24.2 |       10.9 |
| dx_001 (2544×3056)*    |     9.4 |    0.0 | 26.9 |   0.2 |    56.8 |    132.3 |       13.0 |
| mg_001 (3520×4784)*    |    19.7 |    0.0 | 56.9 |   0.2 |   115.3 |  **678.8** |     28.0 |
| mg_002 (3521×4784)*    |    19.8 |    0.0 | 57.1 |   0.2 |   115.3 |  **701.1** |     28.6 |

### Three honest findings

1. **`encodeGPU` is currently a regression** — slower than `encode` on every fixture by
   2-39%. `waveletTransform` GPU dispatch costs more than the CPU forward DWT it's
   supposed to replace (xa_001 at 1024²: CPU DWT 3.3 ms vs GPU DWT 14.9 ms). The
   v5.22.0 audit noted GPU forward DWT was bit-equivalent to spec; this benchmark
   shows it's also a perf regression at every measured size. The `encodeGPU` path
   should be marked deprecated until this is fixed.

2. **`rateControl` is the dominant stage at huge workloads** — at 17M pixels (mammography),
   PCRD-opt layer truncation takes **679–701 ms** out of 900–920 ms total = **75% of
   encode time**. Scales super-linearly: 1M px = 2.6 ms; 17M px = 700 ms (~270× for 17×
   pixel count).

3. **`entropyCoding` dominates at typical medical sizes** — at 1M to 6M pixels, HT
   block coding is 42–49% of total encode time. This is the natural target for any
   GPU-accelerated HT *encoder* mirroring the v5.26.0 GPU HT *decoder* infrastructure.

### Routing recommendation today

For encode, **always use `encode(_:)`** (CPU). `encodeGPU(_:)` is currently a regression
at every measured fixture size. This is the inverse of decode (where `decodeGPU` and
`decodeWithGPUHT` win materially over CPU on warm session).

---

## Encode Performance update (v5.30.0)

v5.29.0's stage breakdown identified `rateControl` as 75% of encode time at mammography
sizes (679–701 ms / 900–920 ms), super-linear scaling. v5.30.0 root-causes it as an
O(B²) inner loop in `improveHTNearTargetAllocation` (a "small local exchange near the
byte target" step that scales catastrophically at large block counts) and adds a
`B ≤ 1024` gate that skips the exchange where individual-block swaps are <0.1% of the
budget anyway.

### Per-fixture impact (v5.29.0 → v5.30.0)

| Fixture                | rateCtrl v5.29 | rateCtrl v5.30 | Total v5.29 | Total v5.30 | Encode speedup |
|------------------------|---------------:|---------------:|------------:|------------:|---------------:|
| ct_001 (512×512)       |        0.4 ms  |        0.4 ms  |     4.1 ms  |     4.0 ms  | (unchanged)    |
| xa_001 (1024×1024)     |        2.6 ms  |        2.5 ms  |    17.0 ms  |    15.9 ms  | (unchanged)    |
| px_001 (2459×1316)     |        7.4 ms  |        7.4 ms  |    50.1 ms  |    52.3 ms  | (unchanged)    |
| dx_002 (2800×2288)     |       24.2 ms  |    **1.0 ms**  |   110.1 ms  |    82.0 ms  |     **1.3×**   |
| dx_001 (2544×3056)*    |      132.3 ms  |    **1.1 ms**  |   239.6 ms  |   101.7 ms  |     **2.4×**   |
| mg_001 (3520×4784)*    |      678.8 ms  |    **2.1 ms**  |   899.7 ms  |   214.2 ms  |     **4.2×**   |
| mg_002 (3521×4784)*    |      701.1 ms  |    **2.1 ms**  |   920.5 ms  |   210.5 ms  |     **4.4×**   |

The gate fires for fixtures with > 1024 codeblocks (dx_002 and larger). Below the
threshold the exchange runs unchanged — small fixtures see no behavioural difference.

### Quality verification

`Tests/J2KCodecTests/J2KEncodeRateControlGateQualityTests.swift` —
`testDX002LossyPSNRPreservedAcrossV5_30Gate` asserts roundtrip PSNR on dx_002 (2800×2288,
~1500 codeblocks → gate fires) is preserved within 1 dB of the pre-v5.30.0 baseline.
The exchange's purpose is "small local swaps that fine-tune R-D allocation" — at these
scales each block is <0.1% of total budget, so swap candidates are below any quality
metric's noise floor. Verified empirically: PSNR is identical pre/post the gate.

(The absolute PSNR on dx_002 at 2 bpp is 14.65 dB, which is low. That's a pre-existing
R-D issue in the encoder's slope formulation on DX/CT fixtures — also visible in
v5.21.0's `testBisectDecodePaths` showing ~2194 LSB avg diff at 4 bpp — and tracked
separately. v5.30.0's gate doesn't change it.)
