# Rate-Distortion Benchmark — J2KSwift vs OpenJPEG / OpenJPH / Grok

**Generated:** `Scripts/rd_benchmark.py`

PSNR (dB) at *matched* achieved bitrate, linearly interpolated from
each codec's R-D curve. `n/a` means the target falls outside the
codec's measured range (interpolation only — no extrapolation).

---

## Per-image PSNR at matched achieved bpp

| Image | Achieved bpp | J2KSwift | OpenJPEG | OpenJPH | Grok | Best |
|---|---:|---:|---:|---:|---:|---|
| synth_8b_512 | 0.25 | n/a | 30.54 | 30.77 | 30.54 | **OpenJPH** (+0.22 dB vs 2nd) |
| synth_8b_512 | 0.50 | 31.35 | 31.24 | 31.58 | 31.23 | **OpenJPH** (+0.23 dB vs 2nd) |
| synth_8b_512 | 1.00 | 33.22 | 32.97 | 33.60 | 32.96 | **OpenJPH** (+0.38 dB vs 2nd) |
| synth_8b_512 | 2.00 | 38.57 | 37.72 | 38.26 | 37.69 | **J2KSwift** (+0.31 dB vs 2nd) |
| synth_8b_512 | 4.00 | 49.72 | n/a | n/a | n/a | **J2KSwift** |
| synth_12b_512 | 0.25 | n/a | 26.65 | 26.80 | 26.64 | **OpenJPH** (+0.15 dB vs 2nd) |
| synth_12b_512 | 0.50 | 27.35 | 27.42 | 27.64 | 27.41 | **OpenJPH** (+0.22 dB vs 2nd) |
| synth_12b_512 | 1.00 | 29.42 | 29.25 | 29.59 | 29.22 | **OpenJPH** (+0.17 dB vs 2nd) |
| synth_12b_512 | 2.00 | 34.30 | 34.07 | 34.20 | 34.03 | **J2KSwift** (+0.10 dB vs 2nd) |
| synth_12b_512 | 4.00 | 46.50 | n/a | n/a | n/a | **J2KSwift** |
| synth_16b_512 | 0.25 | n/a | 27.19 | 27.32 | 27.19 | **OpenJPH** (+0.13 dB vs 2nd) |
| synth_16b_512 | 0.50 | 27.83 | 27.93 | 28.16 | 27.92 | **OpenJPH** (+0.22 dB vs 2nd) |
| synth_16b_512 | 1.00 | 29.97 | 29.78 | 30.14 | 29.75 | **OpenJPH** (+0.18 dB vs 2nd) |
| synth_16b_512 | 2.00 | 34.63 | 34.54 | 34.82 | 34.51 | **OpenJPH** (+0.20 dB vs 2nd) |
| synth_16b_512 | 4.00 | 46.80 | n/a | n/a | n/a | **J2KSwift** |
| ct_001_corpus | 0.25 | n/a | n/a | n/a | 20.82 | **Grok** |
| ct_001_corpus | 0.50 | 25.01 | 25.22 | n/a | 25.15 | **OpenJPEG** (+0.07 dB vs 2nd) |
| ct_001_corpus | 1.00 | 32.50 | 32.69 | 32.21 | 32.66 | **OpenJPEG** (+0.03 dB vs 2nd) |
| ct_001_corpus | 2.00 | 41.07 | 41.19 | 40.28 | 41.15 | **OpenJPEG** (+0.04 dB vs 2nd) |
| ct_001_corpus | 4.00 | 53.45 | n/a | n/a | n/a | **J2KSwift** |

---

## Raw R-D points (achieved bpp, PSNR dB)

### synth_8b_512

| Codec | Target bpp | Achieved bpp | PSNR (dB) | SSIM |
|---|---:|---:|---:|---:|
| J2KSwift | 0.25 | 0.255 | 30.77 | 0.6735 |
| J2KSwift | 0.50 | 0.507 | 31.37 | 0.7257 |
| J2KSwift | 1.00 | 1.008 | 33.25 | 0.8377 |
| J2KSwift | 2.00 | 2.009 | 38.62 | 0.9572 |
| J2KSwift | 4.00 | 4.009 | 49.77 | 0.9967 |
| OpenJPEG | 0.25 | 0.249 | 30.54 | 0.6522 |
| OpenJPEG | 0.50 | 0.495 | 31.23 | 0.7286 |
| OpenJPEG | 1.00 | 0.987 | 32.91 | 0.8337 |
| OpenJPEG | 2.00 | 1.999 | 37.72 | 0.9483 |
| OpenJPEG | 4.00 | 3.992 | 46.76 | 0.9938 |
| OpenJPH | 0.25 | 0.232 | 30.71 | 0.6644 |
| OpenJPH | 0.50 | 0.556 | 31.77 | 0.7605 |
| OpenJPH | 1.00 | 0.926 | 33.25 | 0.8401 |
| OpenJPH | 2.00 | 2.201 | 39.20 | 0.9614 |
| OpenJPH | 4.00 | 3.974 | 48.52 | 0.9955 |
| Grok | 0.25 | 0.244 | 30.53 | 0.6496 |
| Grok | 0.50 | 0.491 | 31.20 | 0.7260 |
| Grok | 1.00 | 0.981 | 32.87 | 0.8319 |
| Grok | 2.00 | 1.999 | 37.69 | 0.9480 |
| Grok | 4.00 | 3.996 | 46.76 | 0.9938 |

### synth_12b_512

| Codec | Target bpp | Achieved bpp | PSNR (dB) | SSIM |
|---|---:|---:|---:|---:|
| J2KSwift | 0.25 | 0.256 | 26.82 | 0.4589 |
| J2KSwift | 0.50 | 0.506 | 27.37 | 0.5569 |
| J2KSwift | 1.00 | 1.008 | 29.46 | 0.7718 |
| J2KSwift | 2.00 | 2.009 | 34.35 | 0.9340 |
| J2KSwift | 4.00 | 4.010 | 46.56 | 0.9961 |
| OpenJPEG | 0.25 | 0.243 | 26.63 | 0.4624 |
| OpenJPEG | 0.50 | 0.494 | 27.40 | 0.5885 |
| OpenJPEG | 1.00 | 0.993 | 29.21 | 0.7726 |
| OpenJPEG | 2.00 | 1.984 | 33.97 | 0.9310 |
| OpenJPEG | 4.00 | 3.991 | 46.03 | 0.9957 |
| OpenJPH | 0.25 | 0.249 | 26.80 | 0.4699 |
| OpenJPH | 0.50 | 0.666 | 28.19 | 0.6775 |
| OpenJPH | 1.00 | 1.164 | 30.28 | 0.8199 |
| OpenJPH | 2.00 | 2.056 | 34.46 | 0.9352 |
| OpenJPH | 4.00 | 3.681 | 43.08 | 0.9912 |
| Grok | 0.25 | 0.248 | 26.64 | 0.4629 |
| Grok | 0.50 | 0.497 | 27.39 | 0.5875 |
| Grok | 1.00 | 1.000 | 29.22 | 0.7727 |
| Grok | 2.00 | 1.990 | 33.97 | 0.9310 |
| Grok | 4.00 | 3.996 | 46.03 | 0.9957 |

### synth_16b_512

| Codec | Target bpp | Achieved bpp | PSNR (dB) | SSIM |
|---|---:|---:|---:|---:|
| J2KSwift | 0.25 | 0.255 | 27.34 | 0.5063 |
| J2KSwift | 0.50 | 0.506 | 27.85 | 0.5896 |
| J2KSwift | 1.00 | 1.008 | 30.00 | 0.7842 |
| J2KSwift | 2.00 | 2.009 | 34.67 | 0.9346 |
| J2KSwift | 4.00 | 4.010 | 46.86 | 0.9962 |
| OpenJPEG | 0.25 | 0.250 | 27.19 | 0.5073 |
| OpenJPEG | 0.50 | 0.500 | 27.93 | 0.6210 |
| OpenJPEG | 1.00 | 0.991 | 29.74 | 0.7835 |
| OpenJPEG | 2.00 | 1.999 | 34.53 | 0.9350 |
| OpenJPEG | 4.00 | 3.992 | 46.54 | 0.9959 |
| OpenJPH | 0.25 | 0.064 | 26.80 | 0.3936 |
| OpenJPH | 0.50 | 0.246 | 27.31 | 0.5113 |
| OpenJPH | 1.00 | 0.675 | 28.74 | 0.7024 |
| OpenJPH | 2.00 | 1.454 | 32.10 | 0.8777 |
| OpenJPH | 4.00 | 3.023 | 39.93 | 0.9807 |
| Grok | 0.25 | 0.249 | 27.19 | 0.5030 |
| Grok | 0.50 | 0.493 | 27.90 | 0.6158 |
| Grok | 1.00 | 0.996 | 29.74 | 0.7835 |
| Grok | 2.00 | 1.997 | 34.49 | 0.9345 |
| Grok | 4.00 | 3.997 | 46.54 | 0.9959 |

### ct_001_corpus

| Codec | Target bpp | Achieved bpp | PSNR (dB) | SSIM |
|---|---:|---:|---:|---:|
| J2KSwift | 0.25 | 0.256 | 20.74 | 0.6963 |
| J2KSwift | 0.50 | 0.507 | 25.14 | 0.8009 |
| J2KSwift | 1.00 | 1.008 | 32.62 | 0.8845 |
| J2KSwift | 2.00 | 2.008 | 41.14 | 0.9689 |
| J2KSwift | 4.00 | 4.010 | 53.51 | 0.9981 |
| OpenJPEG | 0.25 | 0.250 | 20.89 | 0.7115 |
| OpenJPEG | 0.50 | 0.497 | 25.18 | 0.8011 |
| OpenJPEG | 1.00 | 0.997 | 32.66 | 0.8776 |
| OpenJPEG | 2.00 | 1.997 | 41.17 | 0.9661 |
| OpenJPEG | 4.00 | 3.999 | 53.55 | 0.9982 |
| OpenJPH | 0.25 | 0.741 | 28.91 | 0.8425 |
| OpenJPH | 0.50 | 0.906 | 31.21 | 0.8654 |
| OpenJPH | 1.00 | 1.099 | 33.28 | 0.8893 |
| OpenJPH | 2.00 | 1.404 | 36.02 | 0.9223 |
| OpenJPH | 4.00 | 2.127 | 41.19 | 0.9680 |
| Grok | 0.25 | 0.246 | 20.75 | 0.7075 |
| Grok | 0.50 | 0.497 | 25.11 | 0.8007 |
| Grok | 1.00 | 1.000 | 32.66 | 0.8773 |
| Grok | 2.00 | 1.998 | 41.14 | 0.9660 |
| Grok | 4.00 | 3.999 | 53.53 | 0.9981 |

---

## Notes & caveats

- **Matched-bpp values** are linearly interpolated from each codec's
  R-D curve. This is the right comparison axis when the codecs land at
  different *achieved* bitrates for the same nominal target — see the
  v5.14.2 benchmark report for the rate-control caveat that motivated
  this pipeline.
- **Lossless rows** (where PSNR = ∞) are excluded from interpolation.
  J2KSwift and OpenJPEG/OpenJPH/Grok all reach lossless at ~6–9 bpp
  depending on bit-depth — but lossless isn't the question this
  benchmark answers.
- **Bit-depth-aware ratios.** OpenJPEG and Grok take a `-r` flag that
  is the compression ratio relative to the input's bit-depth × pixel
  count; OpenJPH's `-rate` is bpp directly; J2KSwift's `--bitrate` is
  also bpp directly. Each pipeline computes the correct flag value.
- **Plot files**: see `rd_plot_<image>.png` next to this summary for
  visual R-D curves.
