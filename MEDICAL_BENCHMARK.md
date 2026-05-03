# Medical Imaging Benchmark: J2KSwift vs OpenJPEG

**Date:** 2026-05-03 12:13

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
