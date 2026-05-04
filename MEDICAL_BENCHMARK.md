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

## Decode Performance (v5.27.0)

Per-fixture warm-session decode time across three APIs, measured on the medical DICOM
corpus in `Tests/Fixtures/CrossCodec`. All numbers are release-mode medians (n=5 after
warm-up) on M2, HT-conformant lossy 9/7 @ 2 bpp. Reproducible via:

```bash
swift test -c release --filter J2KMedicalCorpus
```

### Per-fixture decode time (ms, lower = faster)

| Fixture                | Pixels    | CPU `decode` | `decodeGPU(_:session:)` | `decodeWithGPUHT(_:session:)` | Winner |
|------------------------|----------:|-------------:|-------------------------:|------------------------------:|---|
| mr_002 (180×180)       |    32,400 |          1.2 |                      1.3 |                          4.5 | CPU¹ |
| ct_001 (512×512)       |   262,144 |          7.2 |                      4.4 |                          9.4 | decodeGPU |
| ct_003 (512×512)       |   262,144 |          7.1 |                      5.2 |                          9.5 | decodeGPU |
| mr_001 (886×886)       |   784,996 |         21.1 |                      9.6 |                         13.5 | decodeGPU |
| xa_001 (1024×1024)     | 1,048,576 |         25.7 |                      9.3 |                         13.9 | decodeGPU |
| px_001 (2459×1316)     | 3,236,044 |         86.2 |                     30.4 |                         **27.2** | decodeWithGPUHT |
| dx_002 (2800×2288)     | 6,406,400 |        170.1 |                     48.2 |                         **42.7** | decodeWithGPUHT |

¹ At 180×180 the median is within run-to-run variance (Metal dispatch ≈ CPU decode time);
both APIs return ~1.2 ms. CPU is the safe default for this size class.

### Per-fixture speedup (×, higher = faster)

| Fixture                | `decodeGPU`× CPU | `decodeWithGPUHT`× CPU |
|------------------------|-----------------:|------------------------:|
| mr_002 (180×180)       |             1.0× |                    0.3× |
| ct_001 (512×512)       |             1.6× |                    0.8× |
| ct_003 (512×512)       |             1.4× |                    0.7× |
| mr_001 (886×886)       |             2.2× |                    1.6× |
| xa_001 (1024×1024)     |             2.8× |                    1.8× |
| px_001 (2459×1316)     |             2.8× |                **3.2×** |
| dx_002 (2800×2288)     |             3.5× |                **4.0×** |

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
