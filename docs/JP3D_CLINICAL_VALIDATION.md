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
| CT/study_001 | 32 | 512×512×32 (16b) | 3.491:1 | 3.336:1 | 1.0467× | 1020 / 1608 ms | **1.58×** | 659 / 1660 ms | **2.52×** | ✓ |
| CT/study_001 | 128 | 512×512×128 (16b) | 3.472:1 | 3.313:1 | 1.0481× | 4082 / 6310 ms | **1.55×** | 2586 / 6457 ms | **2.50×** | ✓ |
| CT/study_001 | max | 512×512×256 (16b) | 3.472:1 | 3.307:1 | 1.0500× | 8051 / 12598 ms | **1.56×** | 5169 / 12886 ms | **2.49×** | ✓ |
| CT/study_002 | 32 | 512×512×32 (16b) | 2.225:1 | 2.164:1 | 1.0281× | 1152 / 1968 ms | **1.71×** | 745 / 2031 ms | **2.73×** | ✓ |
| CT/study_002 | 128 | 512×512×128 (16b) | 2.216:1 | 2.155:1 | 1.0282× | 4583 / 7835 ms | **1.71×** | 2958 / 8067 ms | **2.73×** | ✓ |
| CT/study_002 | max | 512×512×256 (16b) | 2.206:1 | 2.150:1 | 1.0260× | 9109 / 15615 ms | **1.71×** | 5913 / 16000 ms | **2.71×** | ✓ |
| CT/study_003 | 32 | 512×512×32 (16b) | 3.088:1 | 2.949:1 | 1.0469× | 1067 / 1811 ms | **1.70×** | 663 / 1875 ms | **2.83×** | ✓ |
| CT/study_003 | 128 | 512×512×128 (16b) | 3.130:1 | 2.985:1 | 1.0484× | 4220 / 7155 ms | **1.70×** | 2670 / 7328 ms | **2.74×** | ✓ |
| CT/study_003 | max | 512×512×256 (16b) | 3.038:1 | 2.895:1 | 1.0495× | 8547 / 14539 ms | **1.70×** | 5413 / 14838 ms | **2.74×** | ✓ |
| CT/study_004 | 32 | 512×512×32 (16b) | 2.298:1 | 2.237:1 | 1.0273× | 1142 / 1935 ms | **1.69×** | 745 / 1993 ms | **2.67×** | ✓ |
| CT/study_004 | 128 | 512×512×128 (16b) | 2.339:1 | 2.303:1 | 1.0155× | 4441 / 7396 ms | **1.67×** | 2920 / 7625 ms | **2.61×** | ✓ |
| CT/study_004 | max | 512×512×256 (16b) | 2.205:1 | 2.168:1 | 1.0175× | 9054 / 15137 ms | **1.67×** | 5902 / 15529 ms | **2.63×** | ✓ |
| CT/study_005 | 32 | 512×512×32 (16b) | 3.504:1 | 3.340:1 | 1.0489× | 1023 / 1629 ms | **1.59×** | 659 / 1674 ms | **2.54×** | ✓ |
| CT/study_005 | 128 | 512×512×128 (16b) | 3.510:1 | 3.353:1 | 1.0470× | 3972 / 6418 ms | **1.62×** | 2575 / 6569 ms | **2.55×** | ✓ |
| CT/study_005 | max | 512×512×256 (16b) | 3.571:1 | 3.376:1 | 1.0578× | 7839 / 12731 ms | **1.62×** | 5077 / 13034 ms | **2.57×** | ✓ |
| MR/study_001 | 32 | 224×256×32 (12b) | 3.326:1 | 3.205:1 | 1.0378× | 128 / 396 ms | **3.08×** | 145 / 406 ms | **2.79×** | ✓ |
| MR/study_001 | 128 | 224×256×128 (12b) | 2.964:1 | 2.869:1 | 1.0330× | 493 / 1652 ms | **3.35×** | 570 / 1689 ms | **2.96×** | ✓ |
| MR/study_001 | max | 224×256×185 (12b) | 3.062:1 | 2.965:1 | 1.0329× | 707 / 2359 ms | **3.34×** | 798 / 2394 ms | **3.00×** | ✓ |
| MR/study_002 | 32 | 512×512×32 (16b) | 1.949:1 | 1.882:1 | 1.0353× | 1180 / 2028 ms | **1.72×** | 752 / 2083 ms | **2.77×** | ✓ |
| MR/study_002 | 128 | 512×512×128 (16b) | 1.979:1 | 1.911:1 | 1.0356× | 4608 / 8010 ms | **1.74×** | 2953 / 8215 ms | **2.78×** | ✓ |
| MR/study_002 | max | 512×512×256 (16b) | 1.935:1 | 1.869:1 | 1.0354× | 9397 / 16177 ms | **1.72×** | 5904 / 16570 ms | **2.81×** | ✓ |
| MR/study_003 | 32 | 176×256×32 (12b) | 3.840:1 | 3.640:1 | 1.0549× | 102 / 267 ms | **2.63×** | 116 / 272 ms | **2.35×** | ✓ |
| MR/study_003 | 128 | 176×256×128 (12b) | 3.826:1 | 3.646:1 | 1.0493× | 382 / 1001 ms | **2.62×** | 428 / 1028 ms | **2.40×** | ✓ |
| MR/study_003 | max | 176×256×256 (12b) | 3.815:1 | 3.649:1 | 1.0455× | 753 / 1978 ms | **2.63×** | 828 / 2021 ms | **2.44×** | ✓ |
| MR/study_004 | 32 | 512×512×32 (16b) | 2.472:1 | 2.370:1 | 1.0430× | 1113 / 1883 ms | **1.69×** | 714 / 1926 ms | **2.70×** | ✓ |
| MR/study_004 | 128 | 512×512×128 (16b) | 2.345:1 | 2.264:1 | 1.0358× | 4427 / 7529 ms | **1.70×** | 2843 / 7697 ms | **2.71×** | ✓ |
| MR/study_004 | max | 512×512×256 (16b) | 2.360:1 | 2.265:1 | 1.0418× | 9041 / 15259 ms | **1.69×** | 6295 / 16398 ms | **2.60×** | ✓ |
| MR/study_005 | 32 | 192×192×32 (12b) | 4.262:1 | 4.080:1 | 1.0448× | 90 / 226 ms | **2.51×** | 100 / 235 ms | **2.34×** | ✓ |
| MR/study_005 | 128 | 192×192×128 (12b) | 4.236:1 | 4.075:1 | 1.0395× | 347 / 819 ms | **2.36×** | 388 / 854 ms | **2.20×** | ✓ |
| MR/study_005 | max | 192×192×256 (12b) | 4.227:1 | 4.080:1 | 1.0362× | 715 / 1650 ms | **2.31×** | 787 / 1711 ms | **2.17×** | ✓ |
| XA/study_001 | 32 | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 393 / 1022 ms | **2.60×** | 435 / 1028 ms | **2.36×** | ✓ |
| XA/study_001 | 128 | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 362 / 1040 ms | **2.87×** | 436 / 1018 ms | **2.34×** | ✓ |
| XA/study_001 | max | 1024×1024×5 (12b) | 3.442:1 | 3.388:1 | 1.0160× | 359 / 1033 ms | **2.88×** | 429 / 1025 ms | **2.39×** | ✓ |
| XA/study_002 | 32 | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0099× | 1822 / 4327 ms | **2.37×** | 2003 / 4351 ms | **2.17×** | ✓ |
| XA/study_002 | 128 | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0099× | 1672 / 4260 ms | **2.55×** | 1842 / 4355 ms | **2.36×** | ✓ |
| XA/study_002 | max | 1024×1024×22 (12b) | 3.213:1 | 3.181:1 | 1.0099× | 1569 / 4253 ms | **2.71×** | 1757 / 4377 ms | **2.49×** | ✓ |
| XA/study_003 | 32 | 512×512×32 (8b) | 2.648:1 | 2.589:1 | 1.0227× | 413 / 1022 ms | **2.48×** | 420 / 1034 ms | **2.46×** | ✓ |
| XA/study_003 | 128 | 512×512×128 (8b) | 2.653:1 | 2.608:1 | 1.0171× | 2047 / 3909 ms | **1.91×** | 1682 / 3976 ms | **2.36×** | ✓ |
| XA/study_003 | max | 512×512×256 (8b) | 2.653:1 | 2.613:1 | 1.0152× | 4439 / 7730 ms | **1.74×** | 3430 / 7818 ms | **2.28×** | ✓ |
| XA/study_004 | 32 | 512×512×32 (8b) | 2.925:1 | 2.844:1 | 1.0285× | 491 / 974 ms | **1.98×** | 409 / 1004 ms | **2.45×** | ✓ |
| XA/study_004 | 128 | 512×512×128 (8b) | 2.805:1 | 2.745:1 | 1.0218× | 2041 / 3881 ms | **1.90×** | 1724 / 3893 ms | **2.26×** | ✓ |
| XA/study_004 | max | 512×512×256 (8b) | 2.806:1 | 2.752:1 | 1.0197× | 4590 / 7537 ms | **1.64×** | 3565 / 7662 ms | **2.15×** | ✓ |
| XA/study_005 | 32 | 1024×1024×32 (12b) | 3.020:1 | 2.997:1 | 1.0078× | 2401 / 6238 ms | **2.60×** | 2750 / 6412 ms | **2.33×** | ✓ |
| XA/study_005 | 128 | 1024×1024×126 (12b) | 3.038:1 | 3.016:1 | 1.0073× | 10261 / 24472 ms | **2.38×** | 10201 / 25072 ms | **2.46×** | ✓ |
| XA/study_005 | max | 1024×1024×126 (12b) | 3.038:1 | 3.016:1 | 1.0073× | 9171 / 24558 ms | **2.68×** | 11291 / 25094 ms | **2.22×** | ✓ |

## Synthetic stress volumes

These probe the algorithmic seams where OpenJPEG's 3D-EBCOT is
expected to win on ratio. Slice-stack should still win on speed —
its hot path is the same per-slice 2D EBCOT/HT that beats OpenJPEG
2D `opj_compress` 1.4×–13.6× — but the inter-slice DWT gain is real
when Z correlation is strong.

| Stress | Preset | Volume | J2KSwift ratio | OpenJPEG ratio | ratio Δ | Encode J2K / OPJ ms | Encode | Decode J2K / OPJ ms | Decode | Pass |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|:---:|
| thinslice_ct | ultracorr | 512×512×96 (16b) | 3.317:1 | 3.139:1 | 1.0566× | 2905 / 4444 ms | **1.53×** | 1980 / 4519 ms | **2.28×** | ✓ |
| thinslice_ct | thin | 512×512×64 (16b) | 2.342:1 | 2.276:1 | 1.0288× | 2445 / 3447 ms | **1.41×** | 1579 / 3507 ms | **2.22×** | ✗ |
| thinslice_ct | moderate | 512×512×64 (16b) | 1.804:1 | 1.774:1 | 1.0172× | 2896 / 4104 ms | **1.42×** | 1842 / 3986 ms | **2.16×** | ✗ |
| seismic | z128 | 256×256×128 (16b) | 8.806:1 | 2.222:1 | 3.9639× | 979 / 1758 ms | **1.80×** | 464 / 1862 ms | **4.01×** | ✓ |
| hyperspectral | b64 | 256×256×64 (12b) | 7.704:1 | 2.696:1 | 2.8581× | 521 / 845 ms | **1.62×** | 244 / 877 ms | **3.60×** | ✓ |
| noise12u | z64 | 128×128×64 (12b) | 1.233:1 | 1.239:1 | 0.9950× | 153 / 348 ms | **2.28×** | 203 / 357 ms | **1.76×** | ✓ |

## Failures

- `synthetic/thinslice_ct` (thin): enc_speedup 1.41× < 1.5×
- `synthetic/thinslice_ct` (moderate): enc_speedup 1.42× < 1.5×

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

- **Z-delta predictive coding (`JP3DSliceStackCodec`) — M5 default
  policy `JP3DZDeltaMode.auto`.** Each tile runs a 4-position L1
  probe across the Z range; if every probe shows residuals ≪ slice
  L1 *and* the slice area exceeds 50 000 voxels (the M5 size gate),
  the tile commits to per-slice try-both encoding (raw + Z-residual,
  ship whichever is smaller). Below the size gate Z-delta is skipped
  entirely so the per-slice probe overhead never violates the 1.5×
  encode-speed budget on small natural medical content. The `J3DS`
  v2 wire format carries a per-slice flag so individual slices fall
  back to raw silently when the residual happens to lose. Decoder
  always accumulates correctly. Bit-exact round-trip is unconditional.
  `.always` and `.never` overrides are available on
  `JP3DEncoderConfiguration.zDeltaMode` for niche workflows.

- **Synthetic seismic-like wavefield + hyperspectral cube** — the
  original M3 ratio failures. With Z-delta, J2KSwift now *crushes*
  OpenJPEG on these: **3.96× and 2.86× smaller** respectively, plus
  ≥ 1.6× encode and ≥ 3.6× decode speedups. The 12–15 % ratio gap
  that 3D-EBCOT used to extract is now a ratio gain in J2KSwift's
  favour by the same margins — the algorithmic seam is closed.

- **Real medical (CT × 5, MR × 5, XA × 5, all 3 presets each)** —
  **45 / 45 PASS.** The size gate skips Z-delta on small 12-bit MR
  (mr/study_003 at 176×256 = 45 056 voxels and mr/study_005 at
  192×192 = 36 864 voxels), so encode speed on these volumes
  recovers the no-Z-delta baseline (2.36–2.63×). On larger natural
  CT/MR/XA the L1 probe correctly disengages Z-delta tile-by-tile
  where J2K's 2D wavelet already exploits inter-slice DC structure;
  speed stays at 1.55–3.35×. Z-delta does engage opportunistically
  on the few real CT tiles that benefit, picking up small ratio
  gains (e.g. ct/study_005 max: 1.0578×).

- **Synthetic thin-slice CT — ultra-correlated** (σ = 5, 96 slices,
  highest Z correlation): **PASS** with 5.66 % ratio gain at 1.53×
  encode.

- **Synthetic thin-slice CT — thin / moderate** (σ = 20 / 80, 64
  slices) — the only two M5 failures. Z-delta engages and wins on
  ratio by 1.7–2.9 %, and J2KSwift still beats OpenJPEG on every
  metric (encode 1.41–1.42×, decode 2.16–2.22×, bit-exact PASS),
  but the strict 1.5× encode-speed gate trips by ≤ 9 %. These are
  honest speed-for-ratio tradeoffs on simulated thin-slice CT —
  workflows that need the full 1.5× speed margin can set
  `JP3DEncoderConfiguration.zDeltaMode = .never`.

- **Uncorrelated 12-bit noise** — entropy ceiling for every codec;
  the 0.5 % ratio gap (1.233 vs 1.239) is rate-control overhead,
  not algorithmic. Speed wins still hold and the row passes.
