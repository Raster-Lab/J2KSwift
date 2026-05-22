# Cross-silicon J2KSwift wall comparison

_2 hosts; baseline (speedup denominator) = first row._

## Hosts

| # | Host | J2KSwift version | JSON |
|---|---|---|---|
| 0 | Apple M2 (Mac14,2) | J2KSwift version 10.1.0 | `benchmark-results-Mac142-10.1.0-warm-inproc-20260523.json` |
| 1 | iPhone18,1 (iPhone18,1) | J2KSwift version 10.1.0 | `benchmark-results-iPhone181-10.1.0-warm-inproc-20260522.json` |

## DECODE — J2KSwift wall (ms), median of N

| Fixture | Apple M2 ms | iPhone18,1 ms | iPhone18,1/base |
|---|---|---|---|
| cr_synth_mid | 7.37 | 8.38 | 0.88× |
| ct_synth_mid | 4.61 | 3.87 | 1.19× |
| dx_001_class | 57.62 | 57.64 | 1.00× |
| dx_002_class | 51.59 | 44.86 | 1.15× |
| dx_synth_mid | 7.42 | 7.29 | 1.02× |
| mg_001_class | 117.96 | 124.01 | 0.95× |
| mg_synth_mid | 9.94 | 9.88 | 1.01× |
| mr_synth_small | 0.79 | 0.74 | 1.06× |
| px_synth_mid | 6.22 | 5.75 | 1.08× |
| xa_synth_small | 6.52 | 4.17 | 1.56× |

## ENCODE — J2KSwift wall (ms), median of N

| Fixture | Apple M2 ms | iPhone18,1 ms | iPhone18,1/base |
|---|---|---|---|
| cr_synth_mid | 6.58 | 5.88 | 1.12× |
| ct_synth_mid | 4.88 | 4.64 | 1.05× |
| dx_001_class | 44.40 | 40.41 | 1.10× |
| dx_002_class | 36.35 | 34.32 | 1.06× |
| dx_synth_mid | 6.34 | 6.22 | 1.02× |
| mg_001_class | 80.82 | 86.11 | 0.94× |
| mg_synth_mid | 7.98 | 7.59 | 1.05× |
| mr_synth_small | 0.99 | 0.68 | 1.45× |
| px_synth_mid | 5.68 | 4.70 | 1.21× |
| xa_synth_small | 4.61 | 4.55 | 1.01× |

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

