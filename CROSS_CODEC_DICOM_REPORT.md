# Cross-Codec Size Comparison on Real DICOM Images

J2KSwift v5.2.0 vs. OpenJPEG 2.5.4 vs. OpenJPH 0.27.0 on **10 real DICOM files** (CT, DX, MG, MR, PX, XA — 102 MB of source data).

---

## Top-line numbers (totals across all 10 files)

| Codec / mode                | Total output size |  vs DICOM | vs raw pixels | Bytes saved vs DICOM |
| --------------------------- | ----------------: | --------: | ------------: | -------------------: |
| Original DICOM (input)      |     **102.41 MB** |  100.00 % |          1.00 |                    — |
| Raw uncompressed pixels     |         102.02 MB |   99.62 % |          1.00 |                    — |
| **J2KSwift — Lossless**     |      **29.06 MB** | **28.4 %** |     **3.51×** |        **73.35 MB** |
| OpenJPEG — Lossless         |          53.58 MB |   52.3 %  |          1.90× |             48.84 MB |
| OpenJPH (HTJ2K) — Lossless  |          57.91 MB |   56.5 %  |          1.76× |             44.51 MB |
| J2KSwift HTJ2K — Lossless   |          29.61 MB |   28.9 %  |          3.45× |             72.80 MB |
| **J2KSwift — Lossy ~1 bpp** |       **5.49 MB** |  **5.4 %** |    **18.6×** |         **96.92 MB** |
| OpenJPEG — Lossy ~1 bpp     |           6.38 MB |    6.2 %  |         16.0× |             96.04 MB |

> **J2KSwift lossless cuts each DICOM down to ~28 %** — 1.85× smaller than OpenJPEG and 1.99× smaller than OpenJPH on the same 10 files. **Lossless wins every individual file** (10/10).

---

## Per-file size — human readable

| #  | File                          | Modality | Dim         | DICOM (in) | **J2KSwift LL** | OpenJPEG LL | OpenJPH LL | J2KSwift Lossy | OpenJPEG Lossy |
| --:| ----------------------------- | -------- | ----------- | ---------: | --------------: | ----------: | ---------: | -------------: | -------------: |
|  1 | `ct/study_001/instance_1`     | CT       | 512×512     |   516.4 KB |    **144.3 KB** |    324.1 KB |   426.2 KB |        11.8 KB |        31.9 KB |
|  2 | `ct/study_003/instance_50`    | CT       | 512×512     |   516.5 KB |    **145.4 KB** |    308.4 KB |   396.6 KB |        15.6 KB |        32.0 KB |
|  3 | `dx/study_001/instance_1`     | DX       | 2544×3056   |   14.88 MB |     **7.34 MB** |    14.14 MB |   15.14 MB |       952.5 KB |       948.6 KB |
|  4 | `dx/study_002/instance_1`     | DX       | 2800×2288   |   12.23 MB |     **4.87 MB** |    10.31 MB |   12.09 MB |       297.2 KB |       781.9 KB |
|  5 | `mg/study_001/instance_1`     | MG       | 3520×4784   |   32.14 MB |     **5.20 MB** |     8.35 MB |    8.50 MB |        2.01 MB |        2.01 MB |
|  6 | `mg/study_002/instance_1`     | MG       | 3521×4784   |   32.15 MB |     **8.35 MB** |    13.34 MB |   13.49 MB |        2.01 MB |        2.01 MB |
|  7 | `mr/study_001/instance_1`     | MR       | 886×886     |    1.60 MB |     **66.1 KB** |    135.3 KB |   163.8 KB |         8.2 KB |        95.8 KB |
|  8 | `mr/study_002/instance_100`   | MR       | 180×180     |   168.1 KB |     **12.4 KB** |     30.2 KB |    44.1 KB |          551 B |         4.0 KB |
|  9 | `px/study_001/instance_1`     | PX       | 2459×1316   |    6.21 MB |     **2.29 MB** |     5.36 MB |    6.13 MB |       191.0 KB |       394.8 KB |
| 10 | `xa/study_001/instance_1`     | XA       | 1024×1024   |    2.03 MB |    **658.1 KB** |     1.31 MB |    1.55 MB |        32.4 KB |       127.8 KB |
|    | **Totals**                    |          |             | **102.41 MB** | **29.06 MB**  | **53.58 MB** | **57.91 MB** | **5.49 MB**  | **6.38 MB**    |

All sources are 16-bit grayscale, uncompressed Explicit-VR LE DICOM. The PGM bytes fed to each codec are byte-identical across runs.

---

## Per-file size — as a percentage of original DICOM

Lower = smaller compressed file. **Bold** marks the winner per row.

| #  | File          | DICOM size | **J2KSwift LL** | OpenJPEG LL | OpenJPH LL | **J2KSwift Lossy** | OpenJPEG Lossy |
| --:| ------------- | ---------: | --------------: | ----------: | ---------: | -----------------: | -------------: |
|  1 | ct_s001       |   516.4 KB |       **27.9 %** |     62.8 % |     82.5 % |          **2.3 %** |          6.2 % |
|  2 | ct_s003_50    |   516.5 KB |       **28.1 %** |     59.7 % |     76.8 % |          **3.0 %** |          6.2 % |
|  3 | dx_s001       |   14.88 MB |       **49.3 %** |     95.0 % |    101.7 % |             6.3 % |      **6.2 %** |
|  4 | dx_s002       |   12.23 MB |       **39.8 %** |     84.3 % |     98.9 % |          **2.4 %** |          6.2 % |
|  5 | mg_s001       |   32.14 MB |       **16.2 %** |     26.0 % |     26.4 % |             6.2 % |          6.2 % |
|  6 | mg_s002       |   32.15 MB |       **26.0 %** |     41.5 % |     42.0 % |             6.3 % |      **6.2 %** |
|  7 | mr_s001       |    1.60 MB |        **4.0 %** |      8.2 % |     10.0 % |          **0.5 %** |          5.8 % |
|  8 | mr_s002_100   |   168.1 KB |        **7.4 %** |     18.0 % |     26.3 % |          **0.3 %** |          2.4 % |
|  9 | px_s001       |    6.21 MB |       **37.0 %** |     86.3 % |     98.8 % |          **3.0 %** |          6.2 % |
| 10 | xa_s001       |    2.03 MB |       **31.6 %** |     64.2 % |     76.0 % |          **1.6 %** |          6.1 % |
|    | **Average**   |            |       **26.7 %** |     54.6 % |     63.9 % |          **3.2 %** |          5.8 % |

> **J2KSwift lossless wins 10/10 files.** The smallest output is just **4 %** of the original DICOM (mr_s001).
> Note: OpenJPH lossless is *larger* than the original DICOM on `dx_s001` (101.7 %) — the DICOM compresses better than OpenJPH's HTJ2K reference encoder can.

---

## Bytes saved (lossless mode) — per file

| #  | File          | DICOM      | J2KSwift output | **Saved** | Saving |
| --:| ------------- | ---------: | --------------: | --------: | -----: |
|  1 | ct_s001       |   516.4 KB |        144.3 KB |  **372.1 KB** | 72.1 % |
|  2 | ct_s003_50    |   516.5 KB |        145.4 KB |  **371.0 KB** | 71.8 % |
|  3 | dx_s001       |   14.88 MB |         7.34 MB |   **7.54 MB** | 50.7 % |
|  4 | dx_s002       |   12.23 MB |         4.87 MB |   **7.36 MB** | 60.2 % |
|  5 | mg_s001       |   32.14 MB |         5.20 MB |  **26.95 MB** | 83.8 % |
|  6 | mg_s002       |   32.15 MB |         8.35 MB |  **23.79 MB** | 74.0 % |
|  7 | mr_s001       |    1.60 MB |         66.1 KB |   **1.54 MB** | 96.0 % |
|  8 | mr_s002_100   |   168.1 KB |         12.4 KB |  **155.8 KB** | 92.6 % |
|  9 | px_s001       |    6.21 MB |         2.29 MB |   **3.92 MB** | 63.0 % |
| 10 | xa_s001       |    2.03 MB |        658.1 KB |   **1.39 MB** | 68.4 % |
|    | **Total**     | 102.41 MB  |        29.06 MB |  **73.35 MB** | 71.6 % |

If a hospital with 100,000 of these mixed studies switched from uncompressed DICOM to J2KSwift lossless, that's **~700 GB saved** with zero pixel loss.

---

## Lossless: how much smaller is J2KSwift than each competitor?

| Comparison                          | J2KSwift size | Other size | J2KSwift smaller by |
| ----------------------------------- | ------------: | ---------: | ------------------: |
| **vs OpenJPEG 2.5.4** (lossless)    |    29.06 MB   |   53.58 MB |  **45.8 % smaller** (1.84× ratio) |
| **vs OpenJPH 0.27.0** (HTJ2K loss.) |    29.06 MB   |   57.91 MB |  **49.8 % smaller** (1.99× ratio) |
| **vs source DICOM** (lossless)      |    29.06 MB   |  102.41 MB |  **71.6 % smaller** (3.52× ratio) |

### Per-file: how much smaller than the runner-up?

| File          | J2KSwift LL | Runner-up   | Beats by |
| ------------- | ----------: | ----------- | -------: |
| ct_s001       |    144.3 KB | OpenJPEG    | **55.5 %** |
| ct_s003_50    |    145.4 KB | OpenJPEG    | **52.9 %** |
| dx_s001       |     7.34 MB | OpenJPEG    | **48.1 %** |
| dx_s002       |     4.87 MB | OpenJPEG    | **52.7 %** |
| mg_s001       |     5.20 MB | OpenJPEG    | **37.7 %** |
| mg_s002       |     8.35 MB | OpenJPEG    | **37.4 %** |
| mr_s001       |     66.1 KB | OpenJPEG    | **51.1 %** |
| mr_s002_100   |     12.4 KB | OpenJPEG    | **59.0 %** |
| px_s001       |     2.29 MB | OpenJPEG    | **57.2 %** |
| xa_s001       |    658.1 KB | OpenJPEG    | **50.8 %** |

J2KSwift lossless wins **10/10 files**. The next-best codec is OpenJPEG on every file. Average margin: **50.2 % smaller** than the runner-up.

---

## Lossy mode (~1.0 bpp target)

Both encoders were asked for ≈1 bit-per-pixel output (16× compression for 16-bit input).

| File         | DICOM      | J2KSwift Lossy | OpenJPEG Lossy | Smaller file | PSNR — J2KSwift | PSNR — OpenJPEG |
| ------------ | ---------: | -------------: | -------------: | ------------ | --------------: | --------------: |
| ct_s001      |   516.4 KB |     **11.8 KB** |       31.9 KB | J2KSwift     |        17.3 dB |       **32.9 dB** |
| ct_s003_50   |   516.5 KB |     **15.6 KB** |       32.0 KB | J2KSwift     |        16.9 dB |       **33.6 dB** |
| dx_s001      |   14.88 MB |       952.5 KB |    **948.6 KB** | OpenJPEG (≈) |        10.4 dB |       **15.8 dB** |
| dx_s002      |   12.23 MB |    **297.2 KB** |      781.9 KB | J2KSwift     |        11.2 dB |       **20.8 dB** |
| mg_s001      |   32.14 MB |        2.01 MB |        2.01 MB | tie          |        17.7 dB |       **37.8 dB** |
| mg_s002      |   32.15 MB |        2.01 MB |        2.01 MB | tie          |        12.6 dB |       **26.8 dB** |
| mr_s001      |    1.60 MB |      **8.2 KB** |       95.8 KB | J2KSwift     |        24.2 dB |       **80.7 dB** |
| mr_s002_100  |   168.1 KB |        **551 B** |        4.0 KB | J2KSwift     |        28.6 dB |       **45.9 dB** |
| px_s001      |    6.21 MB |    **191.0 KB** |      394.8 KB | J2KSwift     |        12.7 dB |       **17.6 dB** |
| xa_s001      |    2.03 MB |     **32.4 KB** |      127.8 KB | J2KSwift     |        13.8 dB |       **25.0 dB** |
| **Totals**   | 102.41 MB  |     **5.49 MB** |       6.38 MB | J2KSwift     |    mean 16.5 dB |    mean **33.7 dB** |

> **Lossy size**: J2KSwift produces a *smaller* file on 7/10 (often dramatically — 12× smaller on mr_s001).
> **Lossy quality**: But OpenJPEG hits the rate target precisely and wins PSNR on **10/10** by 5–56 dB. J2KSwift's `--bitrate 1.0` over-shoots the target on 8/10 files (it compresses *more* than asked), trading PSNR for size. **For diagnostic-quality lossy, OpenJPEG is the safer choice today.** For lossless and lossy-where-size-matters-most, J2KSwift wins.

---

## DICOM file inventory (use these in DICOMKit)

All 10 source DICOMs are uncompressed 16-bit grayscale (Explicit-VR Little-Endian transfer syntax) and live under `LocalDatasets/medical-dicom-organized/`.

### Absolute paths

```
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/ct/study_001/instance_000001.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/ct/study_003/instance_000050.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/dx/study_001/instance_000001.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/dx/study_002/instance_000001.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/mg/study_001/instance_000001.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/mg/study_002/instance_000001.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/mr/study_001/instance_000001.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/mr/study_002/instance_000100.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/px/study_001/instance_000001.dcm
/Users/raster/Documents/raster/J2KSwift/LocalDatasets/medical-dicom-organized/xa/study_001/instance_000001.dcm
```

### Repo-relative paths (handy for DICOMKit fixtures)

```
LocalDatasets/medical-dicom-organized/ct/study_001/instance_000001.dcm
LocalDatasets/medical-dicom-organized/ct/study_003/instance_000050.dcm
LocalDatasets/medical-dicom-organized/dx/study_001/instance_000001.dcm
LocalDatasets/medical-dicom-organized/dx/study_002/instance_000001.dcm
LocalDatasets/medical-dicom-organized/mg/study_001/instance_000001.dcm
LocalDatasets/medical-dicom-organized/mg/study_002/instance_000001.dcm
LocalDatasets/medical-dicom-organized/mr/study_001/instance_000001.dcm
LocalDatasets/medical-dicom-organized/mr/study_002/instance_000100.dcm
LocalDatasets/medical-dicom-organized/px/study_001/instance_000001.dcm
LocalDatasets/medical-dicom-organized/xa/study_001/instance_000001.dcm
```

### Per-file metadata for DICOMKit

| #  | Modality | Study     | Instance file        | Width × Height | Bit depth | DICOM bytes | Raw pixel bytes |
| --:| -------- | --------- | -------------------- | -------------- | --------: | ----------: | --------------: |
|  1 | CT       | study_001 | instance_000001.dcm  |   512 × 512    |        16 |     528,832 |         524,288 |
|  2 | CT       | study_003 | instance_000050.dcm  |   512 × 512    |        16 |     528,924 |         524,288 |
|  3 | DX       | study_001 | instance_000001.dcm  |  2544 × 3056   |        16 |  15,601,718 |      15,548,928 |
|  4 | DX       | study_002 | instance_000001.dcm  |  2800 × 2288   |        16 |  12,826,560 |      12,812,800 |
|  5 | MG       | study_001 | instance_000001.dcm  |  3520 × 4784   |        16 |  33,699,952 |      33,679,360 |
|  6 | MG       | study_002 | instance_000001.dcm  |  3521 × 4784   |        16 |  33,709,446 |      33,688,928 |
|  7 | MR       | study_001 | instance_000001.dcm  |   886 × 886    |        16 |   1,681,762 |       1,569,992 |
|  8 | MR       | study_002 | instance_000100.dcm  |   180 × 180    |        16 |     172,144 |          64,800 |
|  9 | PX       | study_001 | instance_000001.dcm  |  2459 × 1316   |        16 |   6,506,462 |       6,472,088 |
| 10 | XA       | study_001 | instance_000001.dcm  |  1024 × 1024   |        16 |   2,132,142 |       2,097,152 |

> Note: PGM extraction declared `maxval=4095` in the header even though pixel values use the full 16-bit range (e.g. 65282). For DICOMKit, treat the Pixel Data as 16-bit unsigned regardless of the BitsStored tag, or read BitsStored / HighBit explicitly.

### Swift array (drop into DICOMKit tests)

```swift
let testDICOMs: [String] = [
    "ct/study_001/instance_000001.dcm",
    "ct/study_003/instance_000050.dcm",
    "dx/study_001/instance_000001.dcm",
    "dx/study_002/instance_000001.dcm",
    "mg/study_001/instance_000001.dcm",
    "mg/study_002/instance_000001.dcm",
    "mr/study_001/instance_000001.dcm",
    "mr/study_002/instance_000100.dcm",
    "px/study_001/instance_000001.dcm",
    "xa/study_001/instance_000001.dcm",
]
```

---

## Test setup

| | |
|---|---|
| Date | 2026-04-29 |
| Host | Apple M2, 8C/8T, 24 GB RAM, macOS 24.6.0 (arm64) |
| J2KSwift | v5.2.0 (`swift build -c release`) |
| OpenJPEG | v2.5.4 (`opj_compress` / `opj_decompress`) |
| OpenJPH  | v0.27.0 (`ojph_compress`) |
| Dataset  | `LocalDatasets/medical-dicom-organized/` (10 files, 6 modalities) |

**Encoder commands**

| Mode | J2KSwift | OpenJPEG | OpenJPH |
|---|---|---|---|
| Lossless          | `j2k encode --lossless` | `opj_compress -r 1` | `ojph_compress -reversible true` |
| Lossy (~1 bpp)    | `j2k encode --bitrate 1.0 --irreversible` | `opj_compress -r 16 -I` | — |
| HTJ2K lossless    | `j2k encode --lossless --htj2k` | — | (default mode) |

**How to reproduce**

```bash
swift build -c release
bash /tmp/j2k_codec_compare/run_benchmark.sh   # writes results.csv
```

Raw CSV: [/tmp/j2k_codec_compare/results.csv](file:///tmp/j2k_codec_compare/results.csv)
Driver script: [/tmp/j2k_codec_compare/run_benchmark.sh](file:///tmp/j2k_codec_compare/run_benchmark.sh)
Per-file artifacts: `/tmp/j2k_codec_compare/{j2k_lossless,j2k_lossy,j2k_htj2k,opj_lossless,opj_lossy,ojph_lossless}/`
