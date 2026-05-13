# Validation Suite Report: J2KSwift

**Date:** 2026-04-08 20:55

## Cross-Decoder Validation

| Test | Bits | Bitrate | Path | PSNR | SSIM | MAE | Size | Status |
|------|------|---------|------|------|------|-----|------|--------|
| CT-16bit | 16 | 0.25bpp | J2K→OPJ | 51.53 | 0.9939 | 128.53 | 8443 | OK |
| CT-16bit | 16 | 0.25bpp | OPJ→J2K | 52.11 | 0.9939 | 124.31 | 8202 | OK |
| CT-16bit | 16 | 0.50bpp | J2K→OPJ | 54.98 | 0.9968 | 92.25 | 16690 | OK |
| CT-16bit | 16 | 0.50bpp | OPJ→J2K | 55.46 | 0.9970 | 87.01 | 16262 | OK |
| CT-16bit | 16 | 0.75bpp | J2K→OPJ | 57.47 | 0.9981 | 68.52 | 24890 | OK |
| CT-16bit | 16 | 0.75bpp | OPJ→J2K | 57.75 | 0.9983 | 66.06 | 24519 | OK |
| CT-16bit | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 301178 | OK |
| CT-16bit | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 301217 | OK |
| MRI-12bit | 12 | 0.25bpp | J2K→OPJ | 37.68 | 0.9514 | 37.37 | 2212 | OK |
| MRI-12bit | 12 | 0.25bpp | OPJ→J2K | 36.39 | 0.9463 | 41.05 | 2051 | OK |
| MRI-12bit | 12 | 0.50bpp | J2K→OPJ | 42.45 | 0.9757 | 23.32 | 4271 | OK |
| MRI-12bit | 12 | 0.50bpp | OPJ→J2K | 42.08 | 0.9710 | 24.30 | 4080 | OK |
| MRI-12bit | 12 | 0.75bpp | J2K→OPJ | 45.16 | 0.9833 | 17.63 | 6334 | OK |
| MRI-12bit | 12 | 0.75bpp | OPJ→J2K | 45.09 | 0.9836 | 17.44 | 6154 | OK |
| MRI-12bit | 12 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 57299 | OK |
| MRI-12bit | 12 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 57338 | OK |
| US-12bit | 12 | 0.25bpp | J2K→OPJ | 28.22 | 0.7133 | 87.77 | 9851 | OK |
| US-12bit | 12 | 0.25bpp | OPJ→J2K | 28.67 | 0.8161 | 73.85 | 9559 | OK |
| US-12bit | 12 | 0.50bpp | J2K→OPJ | 31.01 | 0.9025 | 59.52 | 19508 | OK |
| US-12bit | 12 | 0.50bpp | OPJ→J2K | 31.15 | 0.9118 | 55.28 | 19001 | OK |
| US-12bit | 12 | 0.75bpp | J2K→OPJ | 33.86 | 0.9385 | 43.11 | 29126 | OK |
| US-12bit | 12 | 0.75bpp | OPJ→J2K | 34.41 | 0.9600 | 38.05 | 28666 | OK |
| US-12bit | 12 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 158023 | OK |
| US-12bit | 12 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 158062 | OK |

## Stress & Edge-Case Tests

| Test | Bits | Bitrate | Path | PSNR | SSIM | MAE | Size | Status |
|------|------|---------|------|------|------|-----|------|--------|
| Uniform-50% | 16 | 0.25bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 135 | OK |
| Uniform-50% | 16 | 0.25bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-50% | 16 | 0.50bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 135 | OK |
| Uniform-50% | 16 | 0.50bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-50% | 16 | 0.75bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 135 | OK |
| Uniform-50% | 16 | 0.75bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-50% | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 108 | OK |
| Uniform-50% | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-50% | 16 | 0.25bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 135 | OK |
| Uniform-50% | 16 | 0.25bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-50% | 16 | 0.50bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 135 | OK |
| Uniform-50% | 16 | 0.50bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-50% | 16 | 0.75bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 135 | OK |
| Uniform-50% | 16 | 0.75bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-50% | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 108 | OK |
| Uniform-50% | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 147 | OK |
| Uniform-0% | 16 | 0.25bpp | J2K→J2K | 90.31 | 1.0000 | 2.00 | 181 | OK |
| Uniform-0% | 16 | 0.25bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-0% | 16 | 0.50bpp | J2K→J2K | 90.31 | 1.0000 | 2.00 | 181 | OK |
| Uniform-0% | 16 | 0.50bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-0% | 16 | 0.75bpp | J2K→J2K | 90.31 | 1.0000 | 2.00 | 181 | OK |
| Uniform-0% | 16 | 0.75bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-0% | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 110 | OK |
| Uniform-0% | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-0% | 16 | 0.25bpp | J2K→OPJ | 90.31 | 1.0000 | 2.00 | 181 | OK |
| Uniform-0% | 16 | 0.25bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-0% | 16 | 0.50bpp | J2K→OPJ | 90.31 | 1.0000 | 2.00 | 181 | OK |
| Uniform-0% | 16 | 0.50bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-0% | 16 | 0.75bpp | J2K→OPJ | 90.31 | 1.0000 | 2.00 | 181 | OK |
| Uniform-0% | 16 | 0.75bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-0% | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 110 | OK |
| Uniform-0% | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | 0.25bpp | J2K→J2K | 90.31 | 1.0000 | 2.00 | 183 | OK |
| Uniform-100% | 16 | 0.25bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | 0.50bpp | J2K→J2K | 90.31 | 1.0000 | 2.00 | 183 | OK |
| Uniform-100% | 16 | 0.50bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | 0.75bpp | J2K→J2K | 90.31 | 1.0000 | 2.00 | 183 | OK |
| Uniform-100% | 16 | 0.75bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 110 | OK |
| Uniform-100% | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | 0.25bpp | J2K→OPJ | 90.31 | 1.0000 | 2.00 | 183 | OK |
| Uniform-100% | 16 | 0.25bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | 0.50bpp | J2K→OPJ | 90.31 | 1.0000 | 2.00 | 183 | OK |
| Uniform-100% | 16 | 0.50bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | 0.75bpp | J2K→OPJ | 90.31 | 1.0000 | 2.00 | 183 | OK |
| Uniform-100% | 16 | 0.75bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| Uniform-100% | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 110 | OK |
| Uniform-100% | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 149 | OK |
| LowContrast | 16 | 0.25bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 1528 | OK |
| LowContrast | 16 | 0.25bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 1096 | OK |
| LowContrast | 16 | 0.50bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 1528 | OK |
| LowContrast | 16 | 0.50bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 1096 | OK |
| LowContrast | 16 | 0.75bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 1528 | OK |
| LowContrast | 16 | 0.75bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 1096 | OK |
| LowContrast | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 1057 | OK |
| LowContrast | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 1096 | OK |
| LowContrast | 16 | 0.25bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 1528 | OK |
| LowContrast | 16 | 0.25bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 1096 | OK |
| LowContrast | 16 | 0.50bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 1528 | OK |
| LowContrast | 16 | 0.50bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 1096 | OK |
| LowContrast | 16 | 0.75bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 1528 | OK |
| LowContrast | 16 | 0.75bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 1096 | OK |
| LowContrast | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 1057 | OK |
| LowContrast | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 1096 | OK |
| HighNoise | 16 | 0.25bpp | J2K→J2K | 13.01 | 0.2590 | 11835.64 | 8377 | OK |
| HighNoise | 16 | 0.25bpp | OPJ→OPJ | 12.86 | 0.2742 | 12032.02 | 8107 | OK |
| HighNoise | 16 | 0.50bpp | J2K→J2K | 13.71 | 0.4251 | 10845.49 | 16607 | OK |
| HighNoise | 16 | 0.50bpp | OPJ→OPJ | 13.61 | 0.4845 | 10960.60 | 16247 | OK |
| HighNoise | 16 | 0.75bpp | J2K→J2K | 14.51 | 0.5752 | 9848.35 | 24819 | OK |
| HighNoise | 16 | 0.75bpp | OPJ→OPJ | 14.45 | 0.6151 | 9914.92 | 24295 | OK |
| HighNoise | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 550154 | OK |
| HighNoise | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 550193 | OK |
| HighNoise | 16 | 0.25bpp | J2K→OPJ | 13.01 | 0.2590 | 11835.63 | 8377 | OK |
| HighNoise | 16 | 0.25bpp | OPJ→J2K | 12.86 | 0.2742 | 12032.02 | 8107 | OK |
| HighNoise | 16 | 0.50bpp | J2K→OPJ | 13.71 | 0.4250 | 10845.47 | 16607 | OK |
| HighNoise | 16 | 0.50bpp | OPJ→J2K | 13.61 | 0.4845 | 10960.60 | 16247 | OK |
| HighNoise | 16 | 0.75bpp | J2K→OPJ | 14.51 | 0.5752 | 9848.32 | 24819 | OK |
| HighNoise | 16 | 0.75bpp | OPJ→J2K | 14.45 | 0.6151 | 9914.92 | 24295 | OK |
| HighNoise | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 550154 | OK |
| HighNoise | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 550193 | OK |
| Checker-8 | 16 | 0.25bpp | J2K→J2K | 16.00 | 0.9377 | 6082.54 | 2213 | OK |
| Checker-8 | 16 | 0.25bpp | OPJ→OPJ | 14.58 | 0.9116 | 8082.15 | 1939 | OK |
| Checker-8 | 16 | 0.50bpp | J2K→J2K | 26.59 | 0.9949 | 1740.93 | 4280 | OK |
| Checker-8 | 16 | 0.50bpp | OPJ→OPJ | 25.20 | 0.9933 | 2170.26 | 4095 | OK |
| Checker-8 | 16 | 0.75bpp | J2K→J2K | 32.02 | 0.9985 | 915.47 | 6335 | OK |
| Checker-8 | 16 | 0.75bpp | OPJ→OPJ | 30.69 | 0.9981 | 1150.97 | 6114 | OK |
| Checker-8 | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 40852 | OK |
| Checker-8 | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 40891 | OK |
| Checker-8 | 16 | 0.25bpp | J2K→OPJ | 16.00 | 0.9377 | 6083.29 | 2213 | OK |
| Checker-8 | 16 | 0.25bpp | OPJ→J2K | 14.58 | 0.9116 | 8082.15 | 1939 | OK |
| Checker-8 | 16 | 0.50bpp | J2K→OPJ | 26.59 | 0.9949 | 1741.69 | 4280 | OK |
| Checker-8 | 16 | 0.50bpp | OPJ→J2K | 25.20 | 0.9933 | 2170.26 | 4095 | OK |
| Checker-8 | 16 | 0.75bpp | J2K→OPJ | 32.01 | 0.9985 | 916.19 | 6335 | OK |
| Checker-8 | 16 | 0.75bpp | OPJ→J2K | 30.69 | 0.9981 | 1150.97 | 6114 | OK |
| Checker-8 | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 40852 | OK |
| Checker-8 | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 40891 | OK |
| Checker-1 | 16 | 0.25bpp | J2K→J2K | 84.29 | 1.0000 | 4.00 | 573 | OK |
| Checker-1 | 16 | 0.25bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 207 | OK |
| Checker-1 | 16 | 0.50bpp | J2K→J2K | 84.29 | 1.0000 | 4.00 | 573 | OK |
| Checker-1 | 16 | 0.50bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 207 | OK |
| Checker-1 | 16 | 0.75bpp | J2K→J2K | 84.29 | 1.0000 | 4.00 | 573 | OK |
| Checker-1 | 16 | 0.75bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 207 | OK |
| Checker-1 | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 224 | OK |
| Checker-1 | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 263 | OK |
| Checker-1 | 16 | 0.25bpp | J2K→OPJ | 80.77 | 1.0000 | 6.00 | 573 | OK |
| Checker-1 | 16 | 0.25bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 207 | OK |
| Checker-1 | 16 | 0.50bpp | J2K→OPJ | 80.77 | 1.0000 | 6.00 | 573 | OK |
| Checker-1 | 16 | 0.50bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 207 | OK |
| Checker-1 | 16 | 0.75bpp | J2K→OPJ | 80.77 | 1.0000 | 6.00 | 573 | OK |
| Checker-1 | 16 | 0.75bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 207 | OK |
| Checker-1 | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 224 | OK |
| Checker-1 | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 263 | OK |
| DeadPixels | 16 | 0.25bpp | J2K→J2K | 37.67 | 0.9501 | 427.07 | 8496 | OK |
| DeadPixels | 16 | 0.25bpp | OPJ→OPJ | 38.48 | 0.9548 | 408.03 | 8177 | OK |
| DeadPixels | 16 | 0.50bpp | J2K→J2K | 43.03 | 0.9810 | 273.33 | 16714 | OK |
| DeadPixels | 16 | 0.50bpp | OPJ→OPJ | 46.64 | 0.9908 | 187.73 | 16397 | OK |
| DeadPixels | 16 | 0.75bpp | J2K→J2K | 48.52 | 0.9940 | 158.34 | 24914 | OK |
| DeadPixels | 16 | 0.75bpp | OPJ→OPJ | 54.76 | 0.9984 | 78.71 | 24587 | OK |
| DeadPixels | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 79757 | OK |
| DeadPixels | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 79796 | OK |
| DeadPixels | 16 | 0.25bpp | J2K→OPJ | 37.67 | 0.9501 | 427.06 | 8496 | OK |
| DeadPixels | 16 | 0.25bpp | OPJ→J2K | 38.48 | 0.9548 | 408.03 | 8177 | OK |
| DeadPixels | 16 | 0.50bpp | J2K→OPJ | 43.03 | 0.9810 | 273.32 | 16714 | OK |
| DeadPixels | 16 | 0.50bpp | OPJ→J2K | 46.64 | 0.9908 | 187.73 | 16397 | OK |
| DeadPixels | 16 | 0.75bpp | J2K→OPJ | 48.52 | 0.9940 | 158.33 | 24914 | OK |
| DeadPixels | 16 | 0.75bpp | OPJ→J2K | 54.76 | 0.9984 | 78.71 | 24587 | OK |
| DeadPixels | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 79757 | OK |
| DeadPixels | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 79796 | OK |
| LowContrast-12 | 12 | 0.25bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 481 | OK |
| LowContrast-12 | 12 | 0.25bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 322 | OK |
| LowContrast-12 | 12 | 0.50bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 481 | OK |
| LowContrast-12 | 12 | 0.50bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 322 | OK |
| LowContrast-12 | 12 | 0.75bpp | J2K→J2K | ∞ | 1.0000 | 0.00 | 481 | OK |
| LowContrast-12 | 12 | 0.75bpp | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 322 | OK |
| LowContrast-12 | 12 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 283 | OK |
| LowContrast-12 | 12 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 322 | OK |
| LowContrast-12 | 12 | 0.25bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 481 | OK |
| LowContrast-12 | 12 | 0.25bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 322 | OK |
| LowContrast-12 | 12 | 0.50bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 481 | OK |
| LowContrast-12 | 12 | 0.50bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 322 | OK |
| LowContrast-12 | 12 | 0.75bpp | J2K→OPJ | ∞ | 1.0000 | 0.00 | 481 | OK |
| LowContrast-12 | 12 | 0.75bpp | OPJ→J2K | ∞ | 1.0000 | 0.00 | 322 | OK |
| LowContrast-12 | 12 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 283 | OK |
| LowContrast-12 | 12 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 322 | OK |
| HighNoise-12 | 12 | 0.25bpp | J2K→J2K | 12.98 | 0.2514 | 743.71 | 2192 | OK |
| HighNoise-12 | 12 | 0.25bpp | OPJ→OPJ | 12.79 | 0.2607 | 756.74 | 2035 | OK |
| HighNoise-12 | 12 | 0.50bpp | J2K→J2K | 13.64 | 0.4240 | 683.97 | 4261 | OK |
| HighNoise-12 | 12 | 0.50bpp | OPJ→OPJ | 13.52 | 0.4734 | 690.89 | 4065 | OK |
| HighNoise-12 | 12 | 0.75bpp | J2K→J2K | 14.48 | 0.5838 | 619.65 | 6314 | OK |
| HighNoise-12 | 12 | 0.75bpp | OPJ→OPJ | 14.30 | 0.6009 | 630.08 | 5953 | OK |
| HighNoise-12 | 12 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 103423 | OK |
| HighNoise-12 | 12 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 103462 | OK |
| HighNoise-12 | 12 | 0.25bpp | J2K→OPJ | 12.98 | 0.2511 | 743.50 | 2192 | OK |
| HighNoise-12 | 12 | 0.25bpp | OPJ→J2K | 12.79 | 0.2608 | 756.89 | 2035 | OK |
| HighNoise-12 | 12 | 0.50bpp | J2K→OPJ | 13.64 | 0.4236 | 683.39 | 4261 | OK |
| HighNoise-12 | 12 | 0.50bpp | OPJ→J2K | 13.49 | 0.4760 | 694.98 | 4065 | OK |
| HighNoise-12 | 12 | 0.75bpp | J2K→OPJ | 14.49 | 0.5833 | 618.47 | 6314 | OK |
| HighNoise-12 | 12 | 0.75bpp | OPJ→J2K | 14.26 | 0.6025 | 634.96 | 5953 | OK |
| HighNoise-12 | 12 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 103423 | OK |
| HighNoise-12 | 12 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 103462 | OK |

## Higher Resolution Tests

| Test | Bits | Bitrate | Path | PSNR | SSIM | MAE | Size | Status |
|------|------|---------|------|------|------|-----|------|--------|
| CT-2k | 16 | 0.50bpp | J2K→J2K | 57.79 | 0.9981 | 66.31 | 263985 | OK |
| CT-2k | 16 | 0.50bpp | OPJ→OPJ | 57.77 | 0.9981 | 66.03 | 262106 | OK |
| CT-2k | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 4682677 | OK |
| CT-2k | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 4682716 | OK |
| CT-2k | 16 | 0.50bpp | J2K→OPJ | 57.79 | 0.9981 | 66.31 | 263985 | OK |
| CT-2k | 16 | 0.50bpp | OPJ→J2K | 57.77 | 0.9981 | 66.03 | 262106 | OK |
| CT-2k | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 4682677 | OK |
| CT-2k | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 4682716 | OK |
| MRI-2k | 12 | 0.50bpp | J2K→J2K | 48.06 | 0.9848 | 12.91 | 263831 | OK |
| MRI-2k | 12 | 0.50bpp | OPJ→OPJ | 48.34 | 0.9856 | 12.43 | 262079 | OK |
| MRI-2k | 12 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 3310948 | OK |
| MRI-2k | 12 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 3310987 | OK |
| MRI-2k | 12 | 0.50bpp | J2K→OPJ | 48.06 | 0.9848 | 12.91 | 263831 | OK |
| MRI-2k | 12 | 0.50bpp | OPJ→J2K | 48.34 | 0.9856 | 12.43 | 262079 | OK |
| MRI-2k | 12 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 3310948 | OK |
| MRI-2k | 12 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 3310987 | OK |
| CT-4k | 16 | 0.50bpp | J2K→J2K | 58.14 | 0.9982 | 63.67 | 1055739 | OK |
| CT-4k | 16 | 0.50bpp | OPJ→OPJ | 57.99 | 0.9982 | 64.45 | 1048419 | OK |
| CT-4k | 16 | lossless | J2K→J2K | ∞ | 1.0000 | 0.00 | 18639219 | OK |
| CT-4k | 16 | lossless | OPJ→OPJ | ∞ | 1.0000 | 0.00 | 18639258 | OK |
| CT-4k | 16 | 0.50bpp | J2K→OPJ | 58.14 | 0.9982 | 63.68 | 1055739 | OK |
| CT-4k | 16 | 0.50bpp | OPJ→J2K | 57.99 | 0.9982 | 64.45 | 1048419 | OK |
| CT-4k | 16 | lossless | J2K→OPJ | ∞ | 1.0000 | 0.00 | 18639219 | OK |
| CT-4k | 16 | lossless | OPJ→J2K | ∞ | 1.0000 | 0.00 | 18639258 | OK |

## Summary

### Cross-Decoder Validation
- **Total tests:** 24
- **Passed:** 24
- **Failed:** 0
- **PSNR range:** 28.22 – 57.75 dB
- **Lossless perfect:** 6 tests

### Stress & Edge-Case Tests
- **Total tests:** 160
- **Passed:** 160
- **Failed:** 0
- **PSNR range:** 12.79 – 90.31 dB
- **Lossless perfect:** 94 tests

### Higher Resolution Tests
- **Total tests:** 24
- **Passed:** 24
- **Failed:** 0
- **PSNR range:** 48.06 – 58.14 dB
- **Lossless perfect:** 12 tests

## Notes

- PSNR: Peak Signal-to-Noise Ratio (dB) — higher is better
- SSIM: Structural Similarity Index — closer to 1.0 is better
- MAE: Mean Absolute Error — lower is better
- J2K→OPJ: encoded with J2KSwift, decoded with OpenJPEG
- OPJ→J2K: encoded with OpenJPEG, decoded with J2KSwift
- Lossless: exact reconstruction (PSNR = ∞, MAE = 0)
