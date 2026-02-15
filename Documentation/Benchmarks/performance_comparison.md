# J2KSwift vs OpenJPEG Performance Comparison

**Generated**: 2026-02-15 11:37:06

## Encoding Performance

| Image Size | Implementation | Avg (ms) | Median (ms) | Min (ms) | Max (ms) | Throughput (MP/s) | Compressed Size (KB) | vs OpenJPEG |
|------------|----------------|----------|-------------|----------|----------|-------------------|---------------------|-------------|
| 256×256 | J2KSwift | 38.6 | 38.3 | 38.1 | 39.9 | 1.70 | 91.9 | 40.8% |
| 256×256 | OpenJPEG | 15.8 | 15.7 | 15.6 | 15.9 | 4.16 | 69.8 | 100.0% |
| 512×512 | J2KSwift | 151.9 | 150.7 | 150.2 | 156.2 | 1.73 | 366.9 | 34.8% |
| 512×512 | OpenJPEG | 52.9 | 53.0 | 52.6 | 53.4 | 4.95 | 278.4 | 100.0% |
| 1024×1024 | J2KSwift | 607.2 | 601.7 | 599.6 | 625.1 | 1.73 | 1467.1 | 32.9% |
| 1024×1024 | OpenJPEG | 199.8 | 200.0 | 198.5 | 200.6 | 5.25 | 1113.0 | 100.0% |
| 2048×2048 | J2KSwift | 2427.9 | 2417.1 | 2409.3 | 2468.7 | 1.73 | 5867.2 | 32.3% |
| 2048×2048 | OpenJPEG | 784.1 | 783.4 | 781.4 | 789.1 | 5.35 | 4451.3 | 100.0% |

## Decoding Performance

| Image Size | Implementation | Avg (ms) | Median (ms) | Min (ms) | Max (ms) | Throughput (MP/s) | vs OpenJPEG |
|------------|----------------|----------|-------------|----------|----------|-------------------|-------------|
| 256×256 | J2KSwift | 0.0 | 0.0 | 0.0 | 0.1 | 2726.96 | 55526.6% |
| 256×256 | OpenJPEG | 13.3 | 13.3 | 13.0 | 13.7 | 4.91 | 100.0% |
| 512×512 | OpenJPEG | 42.7 | 42.8 | 42.3 | 43.0 | 6.14 | 100.0% |
| 1024×1024 | OpenJPEG | 159.1 | 159.2 | 158.1 | 159.6 | 6.59 | 100.0% |
| 2048×2048 | OpenJPEG | 616.9 | 616.9 | 613.5 | 620.2 | 6.80 | 100.0% |

## Summary

- **Encoding**: J2KSwift is 32.6% of OpenJPEG speed
  - Target: ≥80% (within 80% of OpenJPEG)
  - Status: ❌ FAIL

- **Decoding**: J2KSwift is 865474.2% of OpenJPEG speed
  - Target: ≥80% (within 80% of OpenJPEG)
  - Status: ✅ PASS
