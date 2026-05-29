# LocalDataset Encode/Decode Round-Trip Report

**Date:** 2026-05-29
**Codec:** J2KSwift `j2k` CLI (release build, v10.24.0 line)
**Dataset:** `LocalDatasets/medical-dicom-organized` — 30,104 DICOM files, 6 modalities
**Test:** every file `encode --lossless` → `decode` → **bit-exact** pixel verification vs pydicom
**Harness:** [Scripts/localdataset_roundtrip.py](Scripts/localdataset_roundtrip.py)

---

## TL;DR for the testing team

The testing team reported "a few images in LocalDataset are not working." **The codec is not the problem.**

- **30,048 of 30,104 files are real images. 100% of them round-trip bit-exact losslessly.** Zero decode failures, zero pixel mismatches.
- **The 56 files that "don't work" are not images at all.** They are non-image DICOM objects — Raw Data Storage, X-Ray Radiation Dose Structured Reports, and Enhanced Structured Reports — that contain **no Pixel Data** (confirmed independently by pydicom). No image codec on earth can encode a file that has no image in it. J2KSwift rejects them with an accurate diagnostic: `DICOM file missing Pixel Data tag (7FE0,0010)`.
- The "few not working" the testers saw are exactly these 56 report/raw objects sitting inside the `ct/` and `mr/` study folders.

So: **nothing is broken in the codec for this dataset.** Separately, an adversarial code audit found **two genuine latent defects in the CLI's DICOM *loader*** (not the codec) for input classes that **do not occur anywhere in this dataset** — documented below so they can be fixed proactively.

---

## Results

| Status | Count | % |
|---|---:|---:|
| ✅ OK — encoded, decoded, **bit-exact lossless** | 30,048 | 99.81% |
| ⛔ ENCODE_FAIL — non-image DICOM (no pixel data) | 56 | 0.19% |
| DECODE_FAIL | 0 | 0.00% |
| VERIFY_MISMATCH (lossless corruption) | 0 | 0.00% |

### By modality

| Modality | Total | OK | Non-image rejects | Notes |
|---|---:|---:|---:|---|
| ct (CT) | 14,021 | 13,976 | 45 | 45 rejects = Raw Data / SR / dose objects |
| mr (MR) | 15,700 | 15,689 | 11 | 11 rejects = Raw Data Storage |
| xa (angio) | 309 | 309 | 0 | 156 are **multi-frame cine** (9–593 frames) — all lossless |
| mg (mammo) | 40 | 40 | 0 | |
| dx (X-ray) | 19 | 19 | 0 | |
| px (other) | 15 | 15 | 0 | JPEG-Lossless–compressed source (`1.2.840.10008.1.2.4.70`) |

Of 30,048 real images, **every single one re-decodes to pixels identical to the source** (lossless guarantee holds across the entire corpus).

---

## What the 56 "not working" files actually are

Every one of the 56 `ENCODE_FAIL` files was independently re-examined with pydicom. **All 56 have no Pixel Data element** (`(7FE0,0010)` absent; `ds.pixel_array` raises "must be present"; `Rows`/`Columns` absent). A recursive walk of every element and sub-sequence found zero pixel-data tags anywhere.

| SOP Class | Count | What it is |
|---|---:|---|
| Raw Data Storage | 39 | Vendor raw acquisition payloads — no rendered image |
| X-Ray Radiation Dose SR Storage | 9 | Dose **report** (structured text), not an image |
| Enhanced SR Storage | 8 | Structured **report**, not an image |

These are legitimately part of clinical studies (a CT study ships dose reports and raw data alongside the image slices) but they are **not images**. pydicom itself refuses to produce a pixel array for them. J2KSwift's behaviour is **correct**: it walks all dataset elements, never finds `(7FE0,0010)`, reaches end-of-file cleanly, and throws an accurate error.

**Verdict: not a codec bug. Correct rejection of non-image input.** The full list is in `results/localdataset_full/results.csv` (filter `status == ENCODE_FAIL`).

---

## Multi-frame angiography (xa) — handled correctly and losslessly

156 of the 309 `xa` files are **multi-frame cine loops** (9 to 593 frames of 512×512). J2KSwift composes the frames into a 2D **mosaic** (`cols = ⌈√n⌉`, `rows = ⌈n/cols⌉`, frame *i* at tile `(i mod cols, i ÷ cols)`, unused tiles zero-filled) and encodes that as a single lossless image — e.g. 30 frames → 6×5 grid (3072×2560); 593 frames → 25×24 grid (12800×12288, ~157 MP).

This was verified **bit-exact** by reconstructing the expected mosaic from pydicom frames and comparing to the decoded output, across the full frame-count range (9 → 593 frames). **Every frame's pixels are recoverable byte-for-byte; no frame is dropped; padding tiles are clean zeros.**

> **Caveat (geometric, not data, loss):** the mosaic flattens the *temporal/cine* dimension into a spatial grid. The pixel data is fully preserved, but a consumer that needs per-frame playback must un-tile using the layout above. This is a CLI display convenience, not a property of the codec.

---

## Latent defects found by code audit (NOT triggered by this dataset)

A multi-agent adversarial audit of the CLI DICOM loader ([Sources/J2KCLI/DICOMSupport.swift](Sources/J2KCLI/DICOMSupport.swift)) found two **genuine** defects. Both are in the **CLI's diagnostic DICOM reader**, not the J2KCodec core library, and **neither is reachable by any file in this dataset** (the corpus is entirely MONOCHROME2, single-sample, unsigned, 8/12/16-bit, with defined-length sequences). They are reported so they can be fixed before a dataset that *does* hit them shows up.

### Defect 1 — `BitsAllocated=16` with `BitsStored ≤ 8` silently corrupts pixels  ·  severity: **bug**

**Reproduced end-to-end** with the built `j2k` CLI on a synthesized DICOM (16×16, values 0–255):

| BitsAllocated / BitsStored | Round-trip result |
|---|---|
| 16 / 8 | **CORRUPT — 255/256 pixels wrong** (decoded `[0,0,0,1,0,2…]` vs source `[0,1,2,3,4,5…]`) |
| 16 / 16 | ✅ bit-exact |
| 16 / 12 | ✅ bit-exact (the common medical case) |
| 8 / 8 | ✅ bit-exact |

**Root cause:** [DICOMSupport.swift:502](Sources/J2KCLI/DICOMSupport.swift#L502) sets the component byte-order tag only when `bitsStored > 8` (`dicomBO = bitsStored > 8 ? .bigEndian : nil`), but `bytesPerSample` is derived from `bitsAllocated` (= 2). When 8-bit data is padded into 16-bit allocation, the data is 2-byte big-endian samples while the component is tagged `bitDepth = 8` with no byte-order — so the encoder misreads the bytes. **Only the common configs (16/16, 16/12, 8/8) are safe; the 8-in-16 packing is the gap.** No such file exists in LocalDataset.

### Defect 2 — `skipDICOMSequence` hardcodes Explicit-VR parsing  ·  severity: **risk** (narrow)

[DICOMSupport.swift:658](Sources/J2KCLI/DICOMSupport.swift#L658) `skipDICOMSequence` takes no VR-mode parameter and at [line 681](Sources/J2KCLI/DICOMSupport.swift#L681) hardcodes `explicitVR: true` when decoding the inner elements of an **undefined-length item**. For an **Implicit-VR-LE** file that contains an undefined-length sequence with undefined-length items appearing *before* Pixel Data, the inner elements are parsed in the wrong VR mode and the skip can desync.

**Scope is narrow:** it requires Implicit-VR-LE **and** an undefined-length item nested in an undefined-length sequence **before** the pixel data. Defined-length items (the overwhelmingly common case) take a safe code path. A full-corpus scan found **0 files** with any undefined-length sequence before Pixel Data, so this path was never exercised by the 30,104-file run — the clean result does not validate it. Fix: thread the dataset's `explicitVR` flag into `skipDICOMSequence` instead of assuming `true`.

### Input classes audited and confirmed **correct** (also untested by the corpus)

The audit empirically round-tripped synthesized DICOMs for the classes this dataset lacks and confirmed **bit-exact lossless**: signed pixels (`PixelRepresentation=1`) at 8/12/16-bit, RGB / `SamplesPerPixel>1` with `PlanarConfiguration` 0 and 1, MONOCHROME1 (values preserved), big-endian Explicit VR (`1.2.840.10008.1.2.2`), and conformant 12-in-16. These are fine.

### Minor limitations (by design / acceptable)

- Float Pixel Data `(7FE0,0008)` / Double-Float `(7FE0,0009)` are not recognized — parametric-map modalities would be rejected with the same missing-pixel-data error. Reasonable for a lossless-integer archive encoder.
- MONOCHROME1's display-inversion *semantic* is not carried through (pixel **values** are preserved exactly; only the "render inverted" flag is dropped).
- The long-VR set omits `OV`.

---

## A note on the harness itself

The first full run **hung for 105 minutes at 0% CPU**. Root cause (diagnosed via process-stack sampling): a **`ProcessPoolExecutor` + `subprocess` + macOS-`spawn` deadlock** — forking a pool worker to launch a `j2k` child while it holds multiprocessing semaphore/pipe FDs wedges the task queue. **Fix:** the harness uses a **`ThreadPoolExecutor`** instead; all work is in `subprocess.run()` which releases the GIL, giving full parallelism with none of the IPC/spawn fragility. The shipped script ([Scripts/localdataset_roundtrip.py](Scripts/localdataset_roundtrip.py)) is the fixed version.

The verifier was also upgraded to **reconstruct and validate the multi-frame mosaic** rather than skipping it — so the automated gate now covers all 156 cine loops (previously a coverage gap flagged by the audit).

---

## Recommendations

1. **No codec action needed for LocalDataset.** 100% of real images are lossless; the 56 failures are non-image objects correctly rejected.
2. **Pre-filter non-image SOP classes** in the testing pipeline (skip Raw Data Storage, SR, dose objects) so they don't surface as spurious "failures." Alternatively, J2KSwift could emit a softer "non-image DICOM (SOP class X) — nothing to encode" message to make this obvious to testers.
3. **Fix Defect 1** (16-bit-allocated / ≤8-bit-stored byte-order tagging) before any 8-in-16 dataset is tested — it is silent corruption, the worst failure mode.
4. **Fix Defect 2** (`skipDICOMSequence` VR mode) opportunistically; low practical risk for current data.

---

## Reproduce

```bash
swift build -c release --product j2k
python3 Scripts/localdataset_roundtrip.py \
  --dataset LocalDatasets/medical-dicom-organized \
  --bin .build/release/j2k \
  --python "$PWD/.venv/bin/python3" \
  --workers 8 --verify \
  --out results/localdataset_full
# -> results/localdataset_full/results.csv  (per-file)
# -> results/localdataset_full/REPORT.md    (auto summary)
```

Runs all 30,104 files in ~20 min on an 8-core M-series Mac. `--modality ct,mr`, `--limit N`, and `--verify-sample N` narrow the scope.
