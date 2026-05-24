# Cross-silicon J2KSwift wall comparison

_3 hosts; baseline (speedup denominator) = first row._

## Hosts

| # | Host | J2KSwift version | JSON |
|---|---|---|---|
| 0 | Apple M2 (Mac14,2) | J2KSwift version 10.1.0 | `benchmark-results-Mac142-10.1.0-warm-inproc-20260523.json` |
| 1 | Apple A16 (iPhone15,3) | J2KSwift version 10.1.0 | `benchmark-results-iPhone153-10.1.0-warm-inproc-20260523.json` |
| 2 | iPhone18,1 (iPhone18,1) | J2KSwift version 10.1.0 | `benchmark-results-iPhone181-10.1.0-warm-inproc-20260522.json` |

## DECODE — J2KSwift wall (ms), median of N

| Fixture | Apple M2 ms | Apple A16 ms | iPhone18,1 ms | Apple A16/base | iPhone18,1/base |
|---|---|---|---|---|---|
| cr_synth_mid | 7.37 | 8.68 | 8.38 | 0.85× | 0.88× |
| ct_synth_mid | 4.61 | 5.04 | 3.87 | 0.91× | 1.19× |
| dx_001_class | 57.62 | 69.88 | 57.64 | 0.82× | 1.00× |
| dx_002_class | 51.59 | 55.67 | 44.86 | 0.93× | 1.15× |
| dx_synth_mid | 7.42 | 8.49 | 7.29 | 0.87× | 1.02× |
| mg_001_class | 117.96 | 152.56 | 124.01 | 0.77× | 0.95× |
| mg_synth_mid | 9.94 | 10.95 | 9.88 | 0.91× | 1.01× |
| mr_synth_small | 0.79 | 0.81 | 0.74 | 0.96× | 1.06× |
| px_synth_mid | 6.22 | 7.57 | 5.75 | 0.82× | 1.08× |
| xa_synth_small | 6.52 | 5.08 | 4.17 | 1.28× | 1.56× |

## ENCODE — J2KSwift wall (ms), median of N

| Fixture | Apple M2 ms | Apple A16 ms | iPhone18,1 ms | Apple A16/base | iPhone18,1/base |
|---|---|---|---|---|---|
| cr_synth_mid | 6.58 | 8.19 | 5.88 | 0.80× | 1.12× |
| ct_synth_mid | 4.88 | 4.83 | 4.64 | 1.01× | 1.05× |
| dx_001_class | 44.40 | 53.46 | 40.41 | 0.83× | 1.10× |
| dx_002_class | 36.35 | 43.25 | 34.32 | 0.84× | 1.06× |
| dx_synth_mid | 6.34 | 7.47 | 6.22 | 0.85× | 1.02× |
| mg_001_class | 80.82 | 103.65 | 86.11 | 0.78× | 0.94× |
| mg_synth_mid | 7.98 | 9.45 | 7.59 | 0.84× | 1.05× |
| mr_synth_small | 0.99 | 1.08 | 0.68 | 0.92× | 1.45× |
| px_synth_mid | 5.68 | 6.97 | 4.70 | 0.81× | 1.21× |
| xa_synth_small | 4.61 | 4.86 | 4.55 | 0.95× | 1.01× |

## CPU ↔ GPU decode crossover (per host)

_`decode()` vs `decodeGPU()` vs `decodeWithGPUHT()`. A GPU column below `decode()` means GPU decode beats CPU on that silicon — which would re-open V10_17 for that hardware._

### Apple M2 (Mac14,2)

| Fixture | decode() ms | decodeGPU ms | decodeWithGPUHT ms | fastest |
|---|---|---|---|---|
| cr_synth_mid | 7.37 | 7.45 | 31.58 | decode() |
| ct_synth_mid | 4.61 | 4.46 | 29.80 | decodeGPU |
| dx_001_class | 57.62 | 59.46 | 132.80 | decode() |
| dx_002_class | 51.59 | 47.84 | 126.70 | decodeGPU |
| dx_synth_mid | 7.42 | 7.23 | 31.72 | decodeGPU |
| mg_001_class | 117.96 | 123.42 | 120.28 | decode() |
| mg_synth_mid | 9.94 | 8.99 | 32.02 | decodeGPU |
| mr_synth_small | 0.79 | 9.41 | 8.76 | decode() |
| px_synth_mid | 6.22 | 6.06 | 29.50 | decodeGPU |
| xa_synth_small | 6.52 | 5.08 | 27.82 | decodeGPU |

### Apple A16 (iPhone15,3)

| Fixture | decode() ms | decodeGPU ms | decodeWithGPUHT ms | fastest |
|---|---|---|---|---|
| cr_synth_mid | 8.68 | 8.57 | 37.29 | decodeGPU |
| ct_synth_mid | 5.04 | 4.81 | 35.32 | decodeGPU |
| dx_001_class | 69.88 | 69.80 | 129.14 | decodeGPU |
| dx_002_class | 55.67 | 56.07 | 136.65 | decode() |
| dx_synth_mid | 8.49 | 8.65 | 34.91 | decode() |
| mg_001_class | 152.56 | 149.20 | 149.77 | decodeGPU |
| mg_synth_mid | 10.95 | 10.83 | 37.60 | decodeGPU |
| mr_synth_small | 0.81 | 8.59 | 9.87 | decode() |
| px_synth_mid | 7.57 | 7.16 | 30.44 | decodeGPU |
| xa_synth_small | 5.08 | 5.13 | 35.05 | decode() |

### iPhone18,1 (iPhone18,1)

| Fixture | decode() ms | decodeGPU ms | decodeWithGPUHT ms | fastest |
|---|---|---|---|---|
| cr_synth_mid | 8.38 | 7.54 | 14.99 | decodeGPU |
| ct_synth_mid | 3.87 | 3.87 | 12.34 | decodeGPU |
| dx_001_class | 57.64 | 58.23 | 67.52 | decode() |
| dx_002_class | 44.86 | 46.97 | 63.64 | decode() |
| dx_synth_mid | 7.29 | 7.78 | 14.87 | decode() |
| mg_001_class | 124.01 | 114.53 | 108.90 | decodeWithGPUHT |
| mg_synth_mid | 9.88 | 8.55 | 15.80 | decodeGPU |
| mr_synth_small | 0.74 | 5.42 | 4.12 | decode() |
| px_synth_mid | 5.75 | 6.17 | 12.76 | decode() |
| xa_synth_small | 4.17 | 4.63 | 12.00 | decode() |

