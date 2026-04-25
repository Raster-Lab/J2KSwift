# JP3D Clinical Validation Report — Exhaustive Matrix

**Codec under test**: J2KSwift JP3D (M2 slice-stack)
**Reference**: OpenJPEG 2.0.1 JP3D (`opj_jp3d_compress -C 3EB -r 1`)
**Hardware**: Apple Silicon (arm64e), macOS 14.6
**Datasets**: `LocalDatasets/medical-dicom-organized/` + 6 synthetic stress volumes
**Slice presets**: 32, 128, max
**Timing**: minimum wall-time over 2 iterations

## Headline

**45 / 51 rows meet every medical-grade pass criterion**
(39/45 real DICOM, 6/6 synthetic stress).

Pass criteria per row:
- Bit-exact lossless round-trip (non-negotiable)
- Compression ratio within 1 % of OpenJPEG (`ratio_delta ≥ 0.99`)
- Encode wall-time at least 1.5× faster than OpenJPEG
- Decode wall-time at least 1.5× faster than OpenJPEG

## Real DICOM studies

Every CT, MR, and XA study in the local dataset was prepared via the
hardened [Scripts/prep_jp3d_volume.py](../Scripts/prep_jp3d_volume.py),
which skips non-image DICOM (DICOMDIR / GSPS / SR / RT) and bins by
geometry to extract the largest homogeneous volumetric series per
study. Slices are sorted by `InstanceNumber` and sampled evenly
across the volume (so the benchmark sees representative anatomy, not
just the first N slices of a localiser).

| Study | Preset | Volume | J2KSwift ratio | OpenJPEG ratio | ratio Δ | Encode J2K / OPJ ms | Encode | Decode J2K / OPJ ms | Decode | Pass |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| CT/study_001 | 32 | 512×512×32 (16b) | 3.491:1 | 3.336:1 | 1.0467× | 1000 / 1609 ms | **1.61×** | 650 / 1650 ms | **2.54×** | ✓ |
| CT/study_001 | 128 | 512×512×128 (16b) | 3.472:1 | 3.313:1 | 1.0481× | 3986 / 6385 ms | **1.60×** | 2582 / 6697 ms | **2.59×** | ✓ |
| CT/study_001 | max | 512×512×256 (16b) | 3.472:1 | 3.307:1 | 1.0500× | 7989 / 12626 ms | **1.58×** | 5107 / 12897 ms | **2.53×** | ✓ |
| CT/study_002 | 32 | 512×512×32 (16b) | 2.225:1 | 2.164:1 | 1.0281× | 1132 / 1977 ms | **1.75×** | 740 / 2029 ms | **2.74×** | ✓ |
| CT/study_002 | 128 | 512×512×128 (16b) | 2.216:1 | 2.155:1 | 1.0282× | 4534 / 7929 ms | **1.75×** | 2954 / 8025 ms | **2.72×** | ✓ |
| CT/study_002 | max | 512×512×256 (16b) | 2.206:1 | 2.150:1 | 1.0260× | 9010 / 15597 ms | **1.73×** | 5910 / 15981 ms | **2.70×** | ✓ |
| CT/study_003 | 32 | 512×512×32 (16b) | 3.088:1 | 2.949:1 | 1.0469× | 1061 / 1826 ms | **1.72×** | 685 / 1859 ms | **2.71×** | ✓ |
| CT/study_003 | 128 | 512×512×128 (16b) | 3.130:1 | 2.985:1 | 1.0484× | 4170 / 7151 ms | **1.72×** | 2686 / 7326 ms | **2.73×** | ✓ |
| CT/study_003 | max | 512×512×256 (16b) | 3.038:1 | 2.895:1 | 1.0495× | 8405 / 14476 ms | **1.72×** | 5405 / 14820 ms | **2.74×** | ✓ |
| CT/study_004 | 32 | 512×512×32 (16b) | 2.298:1 | 2.237:1 | 1.0273× | 1121 / 1941 ms | **1.73×** | 741 / 1991 ms | **2.69×** | ✓ |
| CT/study_004 | 128 | 512×512×128 (16b) | 2.339:1 | 2.303:1 | 1.0155× | 4359 / 7398 ms | **1.70×** | 2915 / 7652 ms | **2.63×** | ✓ |
| CT/study_004 | max | 512×512×256 (16b) | 2.205:1 | 2.168:1 | 1.0175× | 8969 / 15454 ms | **1.72×** | 5956 / 15653 ms | **2.63×** | ✓ |
| CT/study_005 | 32 | 512×512×32 (16b) | 3.504:1 | 3.340:1 | 1.0489× | 1014 / 1633 ms | **1.61×** | 645 / 1670 ms | **2.59×** | ✓ |
| CT/study_005 | 128 | 512×512×128 (16b) | 3.510:1 | 3.353:1 | 1.0470× | 3955 / 6446 ms | **1.63×** | 2550 / 6587 ms | **2.58×** | ✓ |
| CT/study_005 | max | 512×512×256 (16b) | 3.571:1 | 3.376:1 | 1.0578× | 7712 / 12781 ms | **1.66×** | 5059 / 13023 ms | **2.57×** | ✓ |
| MR/study_001 | 32 | 224×256×32 (12b) | 3.326:1 | 3.205:1 | 1.0378× | 126 / 392 ms | **3.11×** | 144 / 406 ms | **2.82×** | ✓ |
| MR/study_001 | 128 | 224×256×128 (12b) | 2.964:1 | 2.869:1 | 1.0330× | 497 / 1658 ms | **3.34×** | 566 / 1685 ms | **2.98×** | ✓ |
| MR/study_001 | max | 224×256×185 (12b) | 3.062:1 | 2.965:1 | 1.0329× | 694 / 2363 ms | **3.41×** | 797 / 2403 ms | **3.01×** | ✓ |
| MR/study_002 | 32 | 512×512×32 (16b) | 1.949:1 | 1.882:1 | 1.0353× | 1178 / 2030 ms | **1.72×** | 750 / 2084 ms | **2.78×** | ✓ |
| MR/study_002 | 128 | 512×512×128 (16b) | 1.979:1 | 1.911:1 | 1.0356× | 4541 / 8026 ms | **1.77×** | 2928 / 8242 ms | **2.82×** | ✓ |
| MR/study_002 | max | 512×512×256 (16b) | 1.935:1 | 1.869:1 | 1.0354× | 9173 / 16220 ms | **1.77×** | 5957 / 16570 ms | **2.78×** | ✓ |
| MR/study_003 | 32 | 176×256×32 (12b) | 3.840:1 | 3.640:1 | 1.0549× | 180 / 267 ms | **1.49×** | 115 / 273 ms | **2.37×** | ✗ |
| MR/study_003 | 128 | 176×256×128 (12b) | 3.826:1 | 3.646:1 | 1.0493× | 679 / 1008 ms | **1.48×** | 429 / 1032 ms | **2.40×** | ✗ |
| MR/study_003 | max | 176×256×256 (12b) | 3.829:1 | 3.649:1 | 1.0492× | 1351 / 1996 ms | **1.48×** | 844 / 2015 ms | **2.39×** | ✗ |
| MR/study_004 | 32 | 512×512×32 (16b) | 2.472:1 | 2.370:1 | 1.0430× | 1094 / 1898 ms | **1.74×** | 707 / 1926 ms | **2.72×** | ✓ |
| MR/study_004 | 128 | 512×512×128 (16b) | 2.345:1 | 2.264:1 | 1.0358× | 4382 / 7523 ms | **1.72×** | 2856 / 7700 ms | **2.70×** | ✓ |
| MR/study_004 | max | 512×512×256 (16b) | 2.360:1 | 2.265:1 | 1.0418× | 8913 / 15259 ms | **1.71×** | 5705 / 15587 ms | **2.73×** | ✓ |
| MR/study_005 | 32 | 192×192×32 (12b) | 4.262:1 | 4.080:1 | 1.0448× | 151 / 212 ms | **1.40×** | 97 / 215 ms | **2.21×** | ✗ |
| MR/study_005 | 128 | 192×192×128 (12b) | 4.313:1 | 4.075:1 | 1.0583× | 569 / 778 ms | **1.37×** | 356 / 804 ms | **2.26×** | ✗ |
| MR/study_005 | max | 192×192×256 (12b) | 4.322:1 | 4.080:1 | 1.0594× | 1122 / 1529 ms | **1.36×** | 702 / 1562 ms | **2.22×** | ✗ |
| XA/study_001 | 32 | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 343 / 969 ms | **2.83×** | 392 / 993 ms | **2.53×** | ✓ |
| XA/study_001 | 128 | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 342 / 974 ms | **2.85×** | 390 / 995 ms | **2.55×** | ✓ |
| XA/study_001 | max | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 338 / 974 ms | **2.88×** | 390 / 991 ms | **2.54×** | ✓ |
| XA/study_002 | 32 | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0099× | 1489 / 4267 ms | **2.87×** | 1728 / 4377 ms | **2.53×** | ✓ |
| XA/study_002 | 128 | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0099× | 1503 / 4272 ms | **2.84×** | 1743 / 4363 ms | **2.50×** | ✓ |
| XA/study_002 | max | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0099× | 1494 / 4271 ms | **2.86×** | 1742 / 4370 ms | **2.51×** | ✓ |
| XA/study_003 | 32 | 512×512×32 (8b) | 2.648:1 | 2.589:1 | 1.0227× | 415 / 1012 ms | **2.44×** | 409 / 1038 ms | **2.54×** | ✓ |
| XA/study_003 | 128 | 512×512×128 (8b) | 2.653:1 | 2.608:1 | 1.0171× | 1965 / 3894 ms | **1.98×** | 1637 / 3944 ms | **2.41×** | ✓ |
| XA/study_003 | max | 512×512×256 (8b) | 2.653:1 | 2.613:1 | 1.0152× | 4051 / 7726 ms | **1.91×** | 3273 / 7835 ms | **2.39×** | ✓ |
| XA/study_004 | 32 | 512×512×32 (8b) | 2.925:1 | 2.844:1 | 1.0285× | 492 / 973 ms | **1.98×** | 409 / 995 ms | **2.43×** | ✓ |
| XA/study_004 | 128 | 512×512×128 (8b) | 2.805:1 | 2.745:1 | 1.0218× | 1876 / 3820 ms | **2.04×** | 1621 / 3883 ms | **2.40×** | ✓ |
| XA/study_004 | max | 512×512×256 (8b) | 2.806:1 | 2.752:1 | 1.0197× | 4030 / 7539 ms | **1.87×** | 3212 / 7655 ms | **2.38×** | ✓ |
| XA/study_005 | 32 | 1024×1024×32 (12b) | 3.020:1 | 2.997:1 | 1.0078× | 2185 / 6263 ms | **2.87×** | 2563 / 6425 ms | **2.51×** | ✓ |
| XA/study_005 | 128 | 1024×1024×126 (12b) | 3.038:1 | 3.016:1 | 1.0073× | 8888 / 24491 ms | **2.76×** | 10055 / 25121 ms | **2.50×** | ✓ |
| XA/study_005 | max | 1024×1024×126 (12b) | 3.038:1 | 3.016:1 | 1.0073× | 8928 / 24574 ms | **2.75×** | 10026 / 25126 ms | **2.51×** | ✓ |

## Synthetic stress volumes

These probe the algorithmic seams where OpenJPEG's 3D-EBCOT is
expected to win on ratio. Slice-stack should still win on speed —
its hot path is the same per-slice 2D EBCOT/HT that beats OpenJPEG
2D `opj_compress` 1.4×–13.6× — but the inter-slice DWT gain is real
when Z correlation is strong.

| Stress | Preset | Volume | J2KSwift ratio | OpenJPEG ratio | ratio Δ | Encode J2K / OPJ ms | Encode | Decode J2K / OPJ ms | Decode | Pass |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| thinslice_ct | ultracorr | 512×512×96 (16b) | 3.317:1 | 3.139:1 | 1.0566× | 2778 / 4433 ms | **1.60×** | 1853 / 4512 ms | **2.43×** | ✓ |
| thinslice_ct | thin | 512×512×64 (16b) | 2.342:1 | 2.276:1 | 1.0288× | 2113 / 3456 ms | **1.64×** | 1390 / 3512 ms | **2.53×** | ✓ |
| thinslice_ct | moderate | 512×512×64 (16b) | 1.804:1 | 1.774:1 | 1.0172× | 2316 / 3898 ms | **1.68×** | 1522 / 4008 ms | **2.63×** | ✓ |
| seismic | z128 | 256×256×128 (16b) | 8.806:1 | 2.222:1 | 3.9639× | 858 / 1672 ms | **1.95×** | 436 / 1703 ms | **3.91×** | ✓ |
| hyperspectral | b64 | 256×256×64 (12b) | 7.704:1 | 2.696:1 | 2.8581× | 424 / 802 ms | **1.89×** | 229 / 821 ms | **3.58×** | ✓ |
| noise12u | z64 | 128×128×64 (12b) | 1.233:1 | 1.239:1 | 0.9950× | 143 / 318 ms | **2.23×** | 195 / 327 ms | **1.68×** | ✓ |

## Failures

- `MR/study_003` (32): enc_speedup 1.49× < 1.5×
- `MR/study_003` (128): enc_speedup 1.48× < 1.5×
- `MR/study_003` (max): enc_speedup 1.48× < 1.5×
- `MR/study_005` (32): enc_speedup 1.40× < 1.5×
- `MR/study_005` (128): enc_speedup 1.37× < 1.5×
- `MR/study_005` (max): enc_speedup 1.36× < 1.5×

## Methodology

Both codecs read the same `.bin` (raw little-endian uint16 voxels,
slice-major). J2KSwift via `j2k encode3d`'s raw-volume mode, OpenJPEG
via `bintovolume`. Lossless: J2KSwift `--codec j2k-lossless` (per-Z-slice
2D EBCOT through `J2KEncoder`); OpenJPEG `-C 3EB -r 1` (3D-EBCOT — the
only OpenJPEG JP3D mode that is genuinely lossless; default `-C 2EB`
silently drops precision).

Bit-exact compares the first `raw_bytes` bytes of the decoded `.bin`
against the source — OpenJPEG's `opj_jp3d_decompress` sometimes pads
the trailing samples to a byte alignment.

## Interpretation

- **Z-delta predictive coding (`JP3DSliceStackCodec`)** — landed in
  M4 to close the seismic + hyperspectral failures that the M3
  matrix exposed. For each tile the encoder runs a 4-position L1
  probe across the Z range; if every probe shows residuals ≪ slice
  L1 it commits the tile to per-slice try-both encoding (raw + Z-
  residual, ship whichever is smaller). The `J3DS` v2 wire format
  carries a per-slice flag so individual slices fall back to raw
  silently when the residual happens to lose. Decoder always
  accumulates correctly. Bit-exact round-trip is unconditional.

- **Synthetic seismic-like wavefield + hyperspectral cube** — the
  original M3 ratio failures. With Z-delta, J2KSwift now *crushes*
  OpenJPEG on these: **3.96× and 2.86× smaller** respectively, plus
  ≥ 1.9× encode and ≥ 3.5× decode speedups. The 12–15 % ratio gap
  that 3D-EBCOT used to extract is now a ratio gain in J2KSwift's
  favour by the same margins — the algorithmic seam is closed.

- **Synthetic thin-slice CT** (σ = 5 / 20 / 80) — closest analog
  to clinical 0.5–2 mm CT. Z-delta engages on all three; J2KSwift
  wins ratio by 1.7–5.7 % and is 1.6–1.7× faster on encode (down
  from 2.7–3.0× without Z-delta — the deliberate speed-for-ratio
  trade).

- **Real medical (CT, MR, XA)** — the tile-level L1 probe correctly
  *disengages* Z-delta on most natural anatomy where J2K's 2D
  wavelet already exploits inter-slice DC structure, so encode
  speed stays at the no-Z-delta baseline of 1.6–3.4× faster across
  CT, MR/study_001/002/004, and XA. The remaining failures are all
  in `mr/study_003` (176×256, 12-bit) and `mr/study_005` (192×192,
  12-bit) — small enough volumes that the per-slice probe overhead
  alone (~50 ms over a 100 ms baseline) drops encode speedup to
  1.36–1.49× — *still beating OpenJPEG, but under the 1.5× gate*.
  Bit-exact + ratio gates still pass on every row.

- **Uncorrelated 12-bit noise** — entropy ceiling for every codec;
  the 0.5 % ratio gap (1.233 vs 1.239) is rate-control overhead,
  not algorithmic. Speed wins still hold and the row passes.
