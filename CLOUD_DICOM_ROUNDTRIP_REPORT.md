# Cloud Radiology DICOM — Encode/Decode Round-Trip Report

**Date:** 2026-05-29
**Codec:** J2KSwift `j2k` CLI (release build, v10.24.0 line)
**Dataset:** Google Drive — `…/Radiology DICOM Data` (CloudStorage, materialized locally)
**Scope:** **all 30,329 DICOM files**, 7 modality folders (CT, DX, MG, MR, PX, US, XA)
**Test:** every file `encode --lossless` → `decode` → **bit-exact** pixel verification vs pydicom
**Harness:** [Scripts/localdataset_roundtrip.py](Scripts/localdataset_roundtrip.py)
**Wall time:** 38.4 min, 8 workers · per-file data in `results/cloud_full/results.csv`

---

## TL;DR

- **30,267 of 30,329 files are real images, and 100% of them round-trip bit-exact losslessly.** Zero decode failures, zero pixel mismatches, zero verification skips.
- **The 62 files that fail are not images** — they are DICOM *report / raw-data* objects (Raw Data Storage, X-Ray Dose SR, Enhanced SR, Comprehensive SR) that contain **no Pixel Data**. This is exactly the "few might not have image" you flagged. No image codec can encode them; J2KSwift rejects them with an accurate message. **Not a codec defect.**
- This dataset is much richer than the earlier LocalDataset: it adds **ultrasound colour cine (YBR_FULL_422, multi-frame)**, **JPEG-LS** and **JPEG-Baseline** compressed sources, **MONOCHROME1**, and several new SOP classes — **all verified bit-exact**.
- One **harness** bug was found and fixed mid-run (colour images were being written to a grayscale `.pgm`); the codec itself decoded the colour data correctly once the output format matched.

**Bottom line: every image in the cloud dataset encodes and decodes losslessly. The only "failures" are non-image objects, correctly rejected.**

---

## Overall results

| Status | Count | % |
|---|---:|---:|
| ✅ OK — encoded, decoded, **bit-exact lossless verified** | 30,267 | 99.80% |
| ⛔ ENCODE_FAIL — non-image DICOM (no pixel data) | 62 | 0.20% |
| DECODE_FAIL | 0 | 0 |
| VERIFY_MISMATCH (silent corruption) | 0 | 0 |
| VERIFY_SKIP (not verified) | 0 | 0 |

Lossless compression across all images: **19.87 GB → 9.41 GB (2.11× average)**.

### By modality folder

| Folder | Total | OK | Non-image rejects |
|---|---:|---:|---:|
| CT | 14,021 | 13,976 | 45 |
| MR | 15,700 | 15,689 | 11 |
| US | 225 | 219 | 6 |
| XA | 309 | 309 | 0 |
| MG | 40 | 40 | 0 |
| DX | 19 | 19 | 0 |
| PX | 15 | 15 | 0 |

> Note: the modality *folders* do not match the DICOM `Modality` tag — e.g. several "MR" study folders contain CT-labelled images and CT raw-data objects. The **type tables below use the actual DICOM tags**, which is the ground truth of what was tested.

---

## How many types were tested

This dataset exercised **12 SOP classes**, **5 transfer syntaxes**, **4 photometric interpretations**, **2 sample layouts** (grayscale + RGB), **3 bit-depth configs**, and both single- and multi-frame data. Every image-bearing type passed at **100%**.

### By SOP Class (the "what kind of object" view)

| SOP Class | Total | OK | Pass% | Image? |
|---|---:|---:|---:|:--:|
| CT Image Storage | 20,817 | 20,817 | 100% | ✅ |
| MR Image Storage | 8,834 | 8,834 | 100% | ✅ |
| X-Ray Angiographic Image Storage | 309 | 309 | 100% | ✅ |
| Ultrasound Multi-frame Image Storage | 143 | 143 | 100% | ✅ |
| Ultrasound Image Storage | 76 | 76 | 100% | ✅ |
| Computed Radiography Image Storage | 40 | 40 | 100% | ✅ |
| Digital X-Ray Image Storage – For Presentation | 34 | 34 | 100% | ✅ |
| Secondary Capture Image Storage | 14 | 14 | 100% | ✅ |
| **Raw Data Storage** | 39 | 0 | — | ❌ no pixels |
| **X-Ray Radiation Dose SR Storage** | 9 | 0 | — | ❌ report |
| **Enhanced SR Storage** | 8 | 0 | — | ❌ report |
| **Comprehensive SR Storage** | 6 | 0 | — | ❌ report |

→ **8 image-bearing SOP classes, all 100% lossless. 4 non-image SOP classes (62 files), correctly rejected.**

### By Transfer Syntax (the "how it's encoded on disk" view)

| Transfer Syntax | Name | Total | OK | Pass% |
|---|---|---:|---:|---:|
| 1.2.840.10008.1.2.1 | Explicit VR Little Endian | 21,141 | 21,085 | 99.7%¹ |
| 1.2.840.10008.1.2 | Implicit VR Little Endian | 8,954 | 8,948 | 99.9%¹ |
| 1.2.840.10008.1.2.4.50 | **JPEG Baseline (lossy)** | 219 | 219 | 100% |
| 1.2.840.10008.1.2.4.80 | **JPEG-LS Lossless** | 9 | 9 | 100% |
| 1.2.840.10008.1.2.4.70 | **JPEG Lossless** | 6 | 6 | 100% |

¹ The only failures in the two uncompressed syntaxes are the 62 non-image report/raw objects. **Every image passed.** The three compressed syntaxes (decoded through the pydicom helper, then re-encoded losslessly by J2KSwift) all passed at 100%.

### By Photometric Interpretation

| Photometric | Total | OK | Pass% |
|---|---:|---:|---:|
| MONOCHROME2 | 30,045 | 30,045 | 100% |
| YBR_FULL_422 (colour) | 219 | 219 | 100% |
| MONOCHROME1 | 3 | 3 | 100% |
| (none — non-image) | 62 | 0 | — |

### By sample layout, bit depth, frame count, signedness

| Dimension | Breakdown (all image values = 100% OK) |
|---|---|
| Samples/pixel | grayscale `spp=1`: 30,110 · **colour `spp=3`: 219** |
| Bit depth (alloc/stored) | `16/16`: 20,820 · `16/12`: 9,073 · `8/8`: 374 |
| Frame count | single-frame: 30,030 · **multi-frame: 299** (156 XA + 143 US cine) |
| Pixel representation | unsigned: 30,329 (no signed-pixel files in this corpus) |

---

## The 62 non-image files ("few might not have image")

Every one of the 62 `ENCODE_FAIL` files was confirmed (independently, via pydicom) to have **no Pixel Data element**. They are legitimate DICOM objects that ship inside studies but carry **reports or raw acquisition data, not images**:

| Type | Count | Where |
|---|---:|---|
| Raw Data Storage | 39 | CT/MR study `*_Raw_data_*` folders |
| X-Ray Radiation Dose SR Storage | 9 | CT studies (dose reports) |
| Enhanced SR Storage | 8 | CT `Examination_Report_*` folders |
| Comprehensive SR Storage | 6 | US studies (`unnamed_2` report folders) |

J2KSwift's behaviour is **correct**: it walks the dataset, finds no `(7FE0,0010)` Pixel Data tag, and reports `DICOM file missing Pixel Data tag (7FE0,0010)`. pydicom itself refuses to produce a pixel array for these. The complete list is in `results/cloud_full/results.csv` (`status == ENCODE_FAIL`).

---

## Ultrasound colour cine — new capability, fully verified

This dataset's **219 ultrasound images are the most demanding content tested**: lossy-JPEG-compressed, **YBR_FULL_422 colour (3 samples/pixel)**, and **143 of them are multi-frame cine** (30–95 frames; the largest composes a 10160×7580×3 RGB mosaic ≈ 231 MP). All 219 **round-trip bit-exact**:

- Single-frame colour (e.g. 758×1016×3) → lossless J2K → decode → **identical**.
- Multi-frame colour cine → tiled into an RGB mosaic (`cols=⌈√n⌉`) → lossless J2K → decode → **identical** (verified by reconstructing the expected mosaic from pydicom frames and comparing every byte).

**Harness fix applied mid-run:** the first US pass reported 219 "decode failures" — `PGM format requires single component`. That was the **test harness** writing colour (3-component) output to a grayscale `.pgm` file; the CLI correctly refused. Switching the decode output to `.ppm` for multi-component images resolved it, and the colour data decoded perfectly. **The codec was never at fault** — verified by a standalone decode of a colour US image to PPM, which matched the source bit-for-bit.

---

## Notes carried over from the prior (LocalDataset) audit

A code audit of the CLI's DICOM *loader* ([Sources/J2KCLI/DICOMSupport.swift](Sources/J2KCLI/DICOMSupport.swift)) found two latent defects, **neither of which this dataset triggers** (confirmed: no signed-pixel files, no `BitsStored ≤ 8` with `BitsAllocated = 16`, no undefined-length sequences before pixel data):

1. **`BitsAllocated=16` + `BitsStored ≤ 8`** → silent pixel corruption (reproduced on synthetic input). The common configs here — `16/16`, `16/12`, `8/8` — are all clean.
2. **`skipDICOMSequence` hardcodes Explicit-VR parsing** → would mis-skip an undefined-length sequence in an Implicit-VR file. No such file exists in this corpus.

These remain worth fixing proactively, but have **zero impact on the cloud dataset**.

---

## What changed in the harness for this run

- **Cloud-safe directory walk** (`os.walk(followlinks=False)`) so the self-referential `Radiology DICOM Data` shortcut symlink can't cause infinite recursion.
- **Rich DICOM type capture** per file (SOP class, modality, transfer syntax, photometric, samples, bit depth, signedness, frames) → the "Types tested" tables.
- **Bit-exact RGB and RGB-multiframe verification** (previously skipped) → ultrasound colour is now fully validated.
- **Correct output format** (`.ppm` for colour, `.pgm` for grayscale) so multi-component decode is exercised properly.

---

## Reproduce

```bash
swift build -c release --product j2k
DS="/Users/raster/Library/CloudStorage/GoogleDrive-…/Radiology DICOM Data"
python3 Scripts/localdataset_roundtrip.py \
  --dataset "$DS" \
  --bin .build/release/j2k \
  --python "$PWD/.venv/bin/python3" \
  --workers 8 --verify \
  --out results/cloud_full
# -> results/cloud_full/results.csv   (per-file: status, type metadata, timings, sizes)
# -> results/cloud_full/REPORT.md      (auto summary incl. "Types tested" tables)
```

Narrow with `--modality US`, `--limit N`, or `--verify-sample N`. The `J2K_DICOM_PYTHON` interpreter must have pydicom + JPEG plugins (`pylibjpeg`, `Pillow`) for the compressed (US/PX/MG) sources.
