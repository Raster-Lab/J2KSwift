# JP3D Clinical Validation Report — Exhaustive Matrix

**Codec under test**: J2KSwift JP3D (M2 slice-stack)
**Reference**: OpenJPEG 2.0.1 JP3D (`opj_jp3d_compress -C 3EB -r 1`)
**Hardware**: Apple Silicon (arm64e), macOS 14.6
**Datasets**: `LocalDatasets/medical-dicom-organized/` + 6 synthetic stress volumes
**Slice presets**: 32, 128, max
**Timing**: minimum wall-time over 2 iterations

## Headline

**49 / 51 rows meet every medical-grade pass criterion**
(45/45 real DICOM, 4/6 synthetic stress).

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
| CT/study_001 | 32 | 512×512×32 (16b) | 3.491:1 | 3.336:1 | 1.0467× | 569 / 1601 ms | **2.81×** | 639 / 1646 ms | **2.57×** | ✓ |
| CT/study_001 | 128 | 512×512×128 (16b) | 3.471:1 | 3.313:1 | 1.0479× | 2248 / 6482 ms | **2.88×** | 2568 / 6502 ms | **2.53×** | ✓ |
| CT/study_001 | max | 512×512×256 (16b) | 3.466:1 | 3.307:1 | 1.0483× | 4556 / 12705 ms | **2.79×** | 5123 / 12917 ms | **2.52×** | ✓ |
| CT/study_002 | 32 | 512×512×32 (16b) | 2.221:1 | 2.164:1 | 1.0266× | 652 / 1965 ms | **3.01×** | 745 / 2048 ms | **2.75×** | ✓ |
| CT/study_002 | 128 | 512×512×128 (16b) | 2.210:1 | 2.155:1 | 1.0253× | 2548 / 7851 ms | **3.08×** | 2960 / 8052 ms | **2.72×** | ✓ |
| CT/study_002 | max | 512×512×256 (16b) | 2.201:1 | 2.150:1 | 1.0237× | 5075 / 15638 ms | **3.08×** | 5909 / 15995 ms | **2.71×** | ✓ |
| CT/study_003 | 32 | 512×512×32 (16b) | 3.087:1 | 2.949:1 | 1.0467× | 583 / 1809 ms | **3.10×** | 680 / 1862 ms | **2.74×** | ✓ |
| CT/study_003 | 128 | 512×512×128 (16b) | 3.128:1 | 2.985:1 | 1.0477× | 2314 / 7153 ms | **3.09×** | 2672 / 7356 ms | **2.75×** | ✓ |
| CT/study_003 | max | 512×512×256 (16b) | 3.033:1 | 2.895:1 | 1.0479× | 4630 / 14538 ms | **3.14×** | 5417 / 14841 ms | **2.74×** | ✓ |
| CT/study_004 | 32 | 512×512×32 (16b) | 2.284:1 | 2.237:1 | 1.0211× | 637 / 1919 ms | **3.01×** | 749 / 1991 ms | **2.66×** | ✓ |
| CT/study_004 | 128 | 512×512×128 (16b) | 2.332:1 | 2.303:1 | 1.0126× | 2533 / 7395 ms | **2.92×** | 2946 / 7631 ms | **2.59×** | ✓ |
| CT/study_004 | max | 512×512×256 (16b) | 2.193:1 | 2.168:1 | 1.0119× | 5146 / 15163 ms | **2.95×** | 5997 / 15581 ms | **2.60×** | ✓ |
| CT/study_005 | 32 | 512×512×32 (16b) | 3.503:1 | 3.340:1 | 1.0489× | 581 / 1637 ms | **2.82×** | 658 / 1668 ms | **2.54×** | ✓ |
| CT/study_005 | 128 | 512×512×128 (16b) | 3.504:1 | 3.353:1 | 1.0452× | 2230 / 6416 ms | **2.88×** | 2588 / 6574 ms | **2.54×** | ✓ |
| CT/study_005 | max | 512×512×256 (16b) | 3.510:1 | 3.376:1 | 1.0398× | 4418 / 12805 ms | **2.90×** | 5146 / 13061 ms | **2.54×** | ✓ |
| MR/study_001 | 32 | 224×256×32 (12b) | 3.326:1 | 3.205:1 | 1.0378× | 127 / 392 ms | **3.09×** | 141 / 401 ms | **2.85×** | ✓ |
| MR/study_001 | 128 | 224×256×128 (12b) | 2.964:1 | 2.869:1 | 1.0330× | 498 / 1643 ms | **3.30×** | 561 / 1673 ms | **2.98×** | ✓ |
| MR/study_001 | max | 224×256×185 (12b) | 3.062:1 | 2.965:1 | 1.0329× | 701 / 2349 ms | **3.35×** | 798 / 2409 ms | **3.02×** | ✓ |
| MR/study_002 | 32 | 512×512×32 (16b) | 1.949:1 | 1.882:1 | 1.0353× | 665 / 2087 ms | **3.14×** | 747 / 2114 ms | **2.83×** | ✓ |
| MR/study_002 | 128 | 512×512×128 (16b) | 1.979:1 | 1.911:1 | 1.0356× | 2546 / 8028 ms | **3.15×** | 2949 / 8227 ms | **2.79×** | ✓ |
| MR/study_002 | max | 512×512×256 (16b) | 1.935:1 | 1.869:1 | 1.0353× | 5097 / 16235 ms | **3.18×** | 5927 / 16570 ms | **2.80×** | ✓ |
| MR/study_003 | 32 | 176×256×32 (12b) | 3.840:1 | 3.640:1 | 1.0549× | 101 / 264 ms | **2.62×** | 113 / 274 ms | **2.43×** | ✓ |
| MR/study_003 | 128 | 176×256×128 (12b) | 3.826:1 | 3.646:1 | 1.0494× | 378 / 1000 ms | **2.64×** | 422 / 1021 ms | **2.42×** | ✓ |
| MR/study_003 | max | 176×256×256 (12b) | 3.815:1 | 3.649:1 | 1.0455× | 756 / 1974 ms | **2.61×** | 839 / 2032 ms | **2.42×** | ✓ |
| MR/study_004 | 32 | 512×512×32 (16b) | 2.472:1 | 2.370:1 | 1.0430× | 606 / 1879 ms | **3.10×** | 707 / 1930 ms | **2.73×** | ✓ |
| MR/study_004 | 128 | 512×512×128 (16b) | 2.345:1 | 2.264:1 | 1.0358× | 2446 / 7529 ms | **3.08×** | 2811 / 7705 ms | **2.74×** | ✓ |
| MR/study_004 | max | 512×512×256 (16b) | 2.358:1 | 2.265:1 | 1.0411× | 4874 / 15232 ms | **3.13×** | 5668 / 15622 ms | **2.76×** | ✓ |
| MR/study_005 | 32 | 192×192×32 (12b) | 4.262:1 | 4.080:1 | 1.0448× | 87 / 208 ms | **2.39×** | 96 / 214 ms | **2.22×** | ✓ |
| MR/study_005 | 128 | 192×192×128 (12b) | 4.236:1 | 4.075:1 | 1.0395× | 322 / 776 ms | **2.41×** | 360 / 799 ms | **2.22×** | ✓ |
| MR/study_005 | max | 192×192×256 (12b) | 4.228:1 | 4.080:1 | 1.0362× | 635 / 1527 ms | **2.41×** | 706 / 1568 ms | **2.22×** | ✓ |
| XA/study_001 | 32 | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 336 / 967 ms | **2.87×** | 388 / 1001 ms | **2.58×** | ✓ |
| XA/study_001 | 128 | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 337 / 967 ms | **2.87×** | 390 / 1002 ms | **2.57×** | ✓ |
| XA/study_001 | max | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 338 / 969 ms | **2.86×** | 383 / 990 ms | **2.58×** | ✓ |
| XA/study_002 | 32 | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0100× | 1496 / 4272 ms | **2.86×** | 1721 / 4365 ms | **2.54×** | ✓ |
| XA/study_002 | 128 | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0100× | 1492 / 4258 ms | **2.85×** | 1726 / 4378 ms | **2.54×** | ✓ |
| XA/study_002 | max | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0100× | 1499 / 4249 ms | **2.83×** | 1723 / 4369 ms | **2.54×** | ✓ |
| XA/study_003 | 32 | 512×512×32 (8b) | 2.648:1 | 2.589:1 | 1.0227× | 413 / 1010 ms | **2.45×** | 413 / 1028 ms | **2.49×** | ✓ |
| XA/study_003 | 128 | 512×512×128 (8b) | 2.653:1 | 2.608:1 | 1.0171× | 1620 / 3890 ms | **2.40×** | 1598 / 3945 ms | **2.47×** | ✓ |
| XA/study_003 | max | 512×512×256 (8b) | 2.653:1 | 2.613:1 | 1.0152× | 3236 / 7748 ms | **2.39×** | 3227 / 7829 ms | **2.43×** | ✓ |
| XA/study_004 | 32 | 512×512×32 (8b) | 2.925:1 | 2.844:1 | 1.0285× | 412 / 975 ms | **2.36×** | 403 / 1002 ms | **2.48×** | ✓ |
| XA/study_004 | 128 | 512×512×128 (8b) | 2.805:1 | 2.745:1 | 1.0218× | 1602 / 3822 ms | **2.39×** | 1580 / 3923 ms | **2.48×** | ✓ |
| XA/study_004 | max | 512×512×256 (8b) | 2.806:1 | 2.752:1 | 1.0197× | 3201 / 7612 ms | **2.38×** | 3273 / 7882 ms | **2.41×** | ✓ |
| XA/study_005 | 32 | 1024×1024×32 (12b) | 3.020:1 | 2.997:1 | 1.0078× | 2289 / 6407 ms | **2.80×** | 2553 / 6433 ms | **2.52×** | ✓ |
| XA/study_005 | 128 | 1024×1024×126 (12b) | 3.034:1 | 3.016:1 | 1.0058× | 8605 / 24582 ms | **2.86×** | 9942 / 25144 ms | **2.53×** | ✓ |
| XA/study_005 | max | 1024×1024×126 (12b) | 3.034:1 | 3.016:1 | 1.0058× | 8563 / 24589 ms | **2.87×** | 9969 / 25130 ms | **2.52×** | ✓ |

## Synthetic stress volumes

These probe the algorithmic seams where OpenJPEG's 3D-EBCOT is
expected to win on ratio. Slice-stack should still win on speed —
its hot path is the same per-slice 2D EBCOT/HT that beats OpenJPEG
2D `opj_compress` 1.4×–13.6× — but the inter-slice DWT gain is real
when Z correlation is strong.

| Stress | Preset | Volume | J2KSwift ratio | OpenJPEG ratio | ratio Δ | Encode J2K / OPJ ms | Encode | Decode J2K / OPJ ms | Decode | Pass |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| thinslice_ct | ultracorr | 512×512×96 (16b) | 3.317:1 | 3.139:1 | 1.0566× | 1587 / 4456 ms | **2.81×** | 1845 / 4520 ms | **2.45×** | ✓ |
| thinslice_ct | thin | 512×512×64 (16b) | 2.342:1 | 2.276:1 | 1.0289× | 1194 / 3453 ms | **2.89×** | 1385 / 3519 ms | **2.54×** | ✓ |
| thinslice_ct | moderate | 512×512×64 (16b) | 1.804:1 | 1.774:1 | 1.0172× | 1291 / 3908 ms | **3.03×** | 1500 / 3995 ms | **2.66×** | ✓ |
| seismic | z128 | 256×256×128 (16b) | 1.956:1 | 2.222:1 | 0.8802× | 635 / 1665 ms | **2.62×** | 733 / 1709 ms | **2.33×** | ✗ |
| hyperspectral | b64 | 256×256×64 (12b) | 2.296:1 | 2.696:1 | 0.8518× | 303 / 795 ms | **2.63×** | 350 / 817 ms | **2.34×** | ✗ |
| noise12u | z64 | 128×128×64 (12b) | 1.233:1 | 1.239:1 | 0.9950× | 145 / 315 ms | **2.17×** | 192 / 324 ms | **1.69×** | ✓ |

## Failures

- `synthetic/seismic` (z128): ratio_delta 0.8802 < 0.99
- `synthetic/hyperspectral` (b64): ratio_delta 0.8518 < 0.99

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

- **Real medical (CT/MR/XA, every study × every slice preset)** — J2KSwift
  beats OpenJPEG on ratio in *every* row by 0.6–5.5 %, and runs 2.2–3.4×
  faster on both encode and decode. The 3D-EBCOT inter-slice gain that
  one might assume favours OpenJPEG does not materialise on real anatomy
  at clinical bit depths: medical Z correlation is real but irregular,
  and the slice-stack 2D EBCOT path's per-slice rate-distortion search
  more than recovers the gap.

- **Synthetic thin-slice CT** (σ = 5, 20, 80 noise across Z) — these
  mimic 0.5–2 mm-spacing CT and are the closest synthetic analog to
  real high-resolution clinical data. All three pass; J2KSwift wins
  ratio by 1.7–5.7 %.

- **Synthetic seismic-like wavefield + hyperspectral cube** — the only
  failures. These are the *worst case* for slice-stack: pathologically
  smooth, perfectly-periodic Z evolution that gives OpenJPEG's 3D
  wavelet a 12–15 % ratio advantage. Even here, J2KSwift bit-exactly
  round-trips, runs ≥ 2.3× faster on both encode and decode, and the
  failure is purely on the `ratio_delta ≥ 0.99` honesty gate. This is
  the documented seam in `docs/JP3D_BEAT_OPENJPEG_PLAN.md` — closing
  it requires an optional Z-axis DWT prior to slice serialisation
  inside `JP3DSliceStackCodec` (open follow-up). Non-medical earth-
  observation / seismic users should expect that gap until that lands.

- **Uncorrelated 12-bit noise** — entropy ceiling for every codec; the
  0.5 % ratio gap (1.233 vs 1.239) is rate-control overhead, not
  algorithmic. Speed wins still hold (2.17× / 1.69×), and the row
  passes.
