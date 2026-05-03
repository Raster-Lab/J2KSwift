# Rate-Distortion Benchmark — J2KSwift vs OpenJPEG / OpenJPH / Grok

**Generated:** `Scripts/rd_benchmark.py`

PSNR (dB) at *matched* achieved bitrate, linearly interpolated from
each codec's R-D curve. `n/a` means the target falls outside the
codec's measured range (interpolation only — no extrapolation).

---

## Per-image PSNR at matched achieved bpp

| Image | Achieved bpp | J2KSwift | OpenJPEG | OpenJPH | Grok | Best |
|---|---:|---:|---:|---:|---:|---|
| synth_8b_512 | 0.25 | n/a | n/a | n/a | n/a | n/a | — |
| synth_8b_512 | 0.50 | n/a | 30.46 | 31.24 | n/a | 31.23 | **OpenJPEG** (+0.01 dB vs 2nd) |
| synth_8b_512 | 1.00 | 33.22 | 30.73 | 32.97 | 33.60 | 32.96 | **OpenJPH** (+0.38 dB vs 2nd) |
| synth_8b_512 | 2.00 | 38.57 | 31.48 | n/a | 38.26 | n/a | **J2KSwift** (+0.31 dB vs 2nd) |
| synth_8b_512 | 4.00 | n/a | n/a | n/a | n/a | n/a | — |
| synth_12b_512 | 0.25 | n/a | n/a | n/a | n/a | n/a | — |
| synth_12b_512 | 0.50 | n/a | 26.50 | 27.42 | n/a | 27.41 | **OpenJPEG** (+0.02 dB vs 2nd) |
| synth_12b_512 | 1.00 | 29.42 | 26.74 | 29.25 | 29.59 | 29.22 | **OpenJPH** (+0.17 dB vs 2nd) |
| synth_12b_512 | 2.00 | 34.30 | 27.40 | n/a | 34.20 | n/a | **J2KSwift** (+0.10 dB vs 2nd) |
| synth_12b_512 | 4.00 | n/a | n/a | n/a | n/a | n/a | — |

---

## Raw R-D points (achieved bpp, PSNR dB)

### synth_8b_512

| Codec | Target bpp | Achieved bpp | PSNR (dB) | SSIM |
|---|---:|---:|---:|---:|
| J2KSwift | 0.50 | 0.507 | 31.37 | 0.7257 |
| J2KSwift | 1.00 | 1.008 | 33.25 | 0.8377 |
| J2KSwift | 2.00 | 2.009 | 38.62 | 0.9572 |
| J2KSwift-HT | 0.50 | 0.496 | 30.46 | 0.6140 |
| J2KSwift-HT | 1.00 | 1.015 | 30.74 | 0.6479 |
| J2KSwift-HT | 2.00 | 2.022 | 31.50 | 0.7178 |
| OpenJPEG | 0.50 | 0.495 | 31.23 | 0.7286 |
| OpenJPEG | 1.00 | 0.987 | 32.91 | 0.8337 |
| OpenJPEG | 2.00 | 1.999 | 37.72 | 0.9483 |
| OpenJPH | 0.50 | 0.556 | 31.77 | 0.7605 |
| OpenJPH | 1.00 | 0.926 | 33.25 | 0.8401 |
| OpenJPH | 2.00 | 2.201 | 39.20 | 0.9614 |
| Grok | 0.50 | 0.491 | 31.20 | 0.7260 |
| Grok | 1.00 | 0.981 | 32.87 | 0.8319 |
| Grok | 2.00 | 1.999 | 37.69 | 0.9480 |

### synth_12b_512

| Codec | Target bpp | Achieved bpp | PSNR (dB) | SSIM |
|---|---:|---:|---:|---:|
| J2KSwift | 0.50 | 0.506 | 27.37 | 0.5569 |
| J2KSwift | 1.00 | 1.008 | 29.46 | 0.7718 |
| J2KSwift | 2.00 | 2.009 | 34.35 | 0.9340 |
| J2KSwift-HT | 0.50 | 0.480 | 26.49 | 0.3563 |
| J2KSwift-HT | 1.00 | 1.072 | 26.78 | 0.4200 |
| J2KSwift-HT | 2.00 | 2.063 | 27.44 | 0.5368 |
| OpenJPEG | 0.50 | 0.494 | 27.40 | 0.5885 |
| OpenJPEG | 1.00 | 0.993 | 29.21 | 0.7726 |
| OpenJPEG | 2.00 | 1.984 | 33.97 | 0.9310 |
| OpenJPH | 0.50 | 0.666 | 28.19 | 0.6775 |
| OpenJPH | 1.00 | 1.164 | 30.28 | 0.8199 |
| OpenJPH | 2.00 | 2.056 | 34.46 | 0.9352 |
| Grok | 0.50 | 0.497 | 27.39 | 0.5875 |
| Grok | 1.00 | 1.000 | 29.22 | 0.7727 |
| Grok | 2.00 | 1.990 | 33.97 | 0.9310 |

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
