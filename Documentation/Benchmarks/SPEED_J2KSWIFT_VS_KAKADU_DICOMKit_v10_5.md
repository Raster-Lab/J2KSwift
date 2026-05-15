# Speed — J2KSwift vs Kakadu (DICOMKit SampleStudies, v10.5-research)

Decode timings (encode is J2KSwift-only — Kakadu in this test is decode-only).
Pulled from the same Kakadu cross-codec run as [`KAKADU_VS_J2KSWIFT_SAMPLESTUDIES_DICOMKit_v10_5.md`](KAKADU_VS_J2KSWIFT_SAMPLESTUDIES_DICOMKit_v10_5.md).

- **Build:** DEBUG (`swift test` default — no `-O`, no `preWarm()`). Kakadu = release `kdu_expand` CLI.
- **Methodology:** 2 untimed warmups + 7 timed runs, median of 7. All times in **ms**.

## Per-fixture decode

| Label | Dim | J2KSwift route | Enc J2K | Dec J2K | Dec Kakadu | Kak/J2K |
|---|---|---|---|---|---|---|
| CT-001 | 512×512 16-b | CPU | 724.68 | 627.19 | 8.09 | **77.5×** |
| CT-002 | 512×512 16-b | CPU | 711.89 | 629.81 | 7.73 | **81.4×** |
| CT-003 | 512×512 16-b | CPU | 724.86 | 624.09 | 8.03 | **77.7×** |
| CT-004 | 512×512 16-b | CPU | 734.90 | 626.61 | 8.12 | **77.1×** |
| CT-005 | 512×512 16-b | CPU | 727.47 | 637.57 | 8.33 | **76.5×** |
| CT-006 | 512×512 16-b | CPU | 744.90 | 660.84 | 7.85 | **84.2×** |
| CT-007 | 512×512 16-b | CPU | 733.85 | 643.19 | 7.80 | **82.5×** |
| CT-008 | 512×512 16-b | CPU | 738.38 | 648.30 | 8.48 | **76.4×** |
| CT-009 | 512×512 16-b | CPU | 742.34 | 648.80 | 8.16 | **79.5×** |
| CT-010 | 512×512 16-b | CPU | 734.85 | 644.84 | 8.38 | **77.0×** |
| MR-001 | 128×128 12-b | CPU | 52.59 | 68.96 | 4.83 | **14.3×** |
| MR-002 | 128×128 12-b | CPU | 57.13 | 74.37 | 4.60 | **16.2×** |
| MR-003 | 128×128 12-b | CPU | 53.83 | 69.81 | 4.78 | **14.6×** |
| MR-004 | 128×128 12-b | CPU | 54.13 | 71.85 | 4.97 | **14.4×** |
| MR-005 | 128×128 12-b | CPU | 57.10 | 74.16 | 4.63 | **16.0×** |
| XA-001 | 1024×1024 12-b | decodeGPU | 3 716.29 | 2 328.11 | 24.76 | **94.0×** |
| XA-002 | 1024×1024 12-b | decodeGPU | 3 182.88 | 1 993.75 | 22.19 | **89.8×** |
| PX-001 | 2793×1316 12-b | decodeGPU | 7 482.52 | 6 094.87 | 79.33 | **76.8×** |
| DX-001 | 2544×3056 12-b | decodeGPU | 19 459.08 | 15 311.73 | 168.03 | **91.1×** |
| DX-002 | 2544×3056 12-b | decodeGPU | 20 013.03 | 16 336.62 | 182.06 | **89.7×** |
| MG-001 | 3520×4784 12-b | decodeGPU | 26 178.05 | 19 261.27 | 145.95 | **132.0×** |
| MG-002 | 3517×4784 12-b | decodeGPU | 29 387.55 | 21 284.93 | 150.51 | **141.4×** |
| DX-001-HT | 2544×3056 12-b | decodeWithGPUHT | 19 999.51 | 15 627.11 | 170.31 | **91.8×** |
| DX-002-HT | 2544×3056 12-b | decodeWithGPUHT | 19 887.66 | 16 087.12 | 186.36 | **86.3×** |
| MG-001-HT | 3520×4784 12-b | decodeWithGPUHT | 27 591.17 | 24 109.32 | 148.92 | **161.9×** |
| MG-002-HT | 3517×4784 12-b | decodeWithGPUHT | 30 349.74 | 24 446.11 | 171.34 | **142.7×** |
| **Total** | — | mixed | **214 840.39** | **169 631.31** | **1 554.56** | **109.1×** |

## By modality / route (aggregate)

| Group | Fixtures | Σ Dec J2K (ms) | Σ Dec Kak (ms) | Kak/J2K |
|---|---|---|---|---|
| CT (CPU) | 10 | 6 391.24 | 80.97 | **79.0×** |
| MR (CPU) | 5 | 359.15 | 23.81 | **15.1×** |
| XA (decodeGPU) | 2 | 4 321.86 | 46.95 | **92.0×** |
| PX (decodeGPU) | 1 | 6 094.87 | 79.33 | **76.8×** |
| DX (decodeGPU) | 2 | 31 648.35 | 350.09 | **90.4×** |
| MG (decodeGPU) | 2 | 40 546.20 | 296.46 | **136.8×** |
| DX (decodeWithGPUHT) | 2 | 31 714.23 | 356.67 | **88.9×** |
| MG (decodeWithGPUHT) | 2 | 48 555.43 | 320.26 | **151.6×** |

## Read this with care

- **Decode gap is a debug-build artifact.** The canonical release-mode warm-in-process picture is in [`CROSS_HOST_M2_M4_v10_1_0_inproc.md`](CROSS_HOST_M2_M4_v10_1_0_inproc.md): on M2, **J2KSwift+inproc is the lowest-median decoder on 27/38 fixtures** (Kakadu 7, Grok 4) and lowest-median encoder on 30/38 (Kakadu 8). The 14–162× factors above are debug (no `-O`) + no `preWarm()` artifacts — **not** a release perf claim.
- **Encode-side here is J2KSwift-only** (Kakadu in this test is decode-only). For J2KSwift vs Kakadu **encode** speed, see `CROSS_HOST_M2_M4_v10_1_0_inproc.md` or rerun `Scripts/benchmarks/cross_codec_warm_bench.py` (warm-in-process, release build, j2kd daemon).
- Per [`DICOM_STUDIO_CLAIM_SCOPE_FINDING.md`](DICOM_STUDIO_CLAIM_SCOPE_FINDING.md), do not lift these numbers into product positioning.
