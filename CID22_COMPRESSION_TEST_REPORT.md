# Cloudinary Image Dataset '22 (CID22) — Compression Test Report

**Date:** 2026-05-30
**Codec:** J2KSwift `j2k` CLI (release build, v10.24.0 line)
**Dataset:** CID22 validation reference set — 49 pristine **512×512 RGB** PNGs (natural photos + graphics), from <https://cloudinary.com/labs/cid22>
**Why:** validate the codec on **non-DICOM, natural, colour** imagery — the libraries must work beyond medical greyscale.
**Harness:** [Scripts/image_corpus_roundtrip.py](Scripts/image_corpus_roundtrip.py)

---

## TL;DR

Testing against CID22 **found a real, serious codec bug** that the medical (DICOM) corpus never exposed:

> **J2KSwift's HTJ2K encoder silently lost data in *lossless* mode** on 4 of 49 natural RGB images (up to 38,946 px wrong, max error 238). Plain J2K lossless was always bit-exact.

The bug is now **root-caused, fixed, and verified**. After the fix:
- **Plain J2K lossless: 49/49 bit-exact** ✅
- **HTJ2K lossless: 49/49 bit-exact** ✅ (was 45/49)
- **OpenJPH (reference HT codec) decodes our output bit-exact** ✅
- **Full medical-corpus + cross-codec gate: green** ✅ (no regression)

This is exactly the value of testing against a non-DICOM corpus: medical data is 12/16-bit and never approaches full scale, so it never triggered the defect; CID22's full-range 8-bit colour content did.

---

## Results (after fix)

### Lossless round-trip (correctness)

| Codec | Bit-exact | Median compression |
|---|---|---|
| J2K (EBCOT) lossless | **49/49 (100%)** | 2.77× |
| HTJ2K (Part-15) lossless | **49/49 (100%)** | 2.55× |

Zero decode failures, zero mismatches.

### Lossy quality sweep (J2K, natural-image rate–distortion)

| `--quality` | Images OK | Median PSNR (dB) | Median ratio | Median bpp |
|---|---:|---:|---:|---:|
| 0.95 | 49 | 52.59 | 3.99× | 6.02 |
| 0.90 | 49 | 51.09 | 4.78× | 5.02 |
| 0.85 | 49 | 49.28 | 5.97× | 4.02 |
| 0.75 | 49 | 45.09 | 8.83× | 2.72 |
| 0.50 | 49 | 38.65 | 19.79× | 1.21 |

A clean, monotone R–D curve across the full quality range — the lossy path behaves correctly on natural images.

---

## The bug: HTJ2K lossless encoder data loss

### Discovery
The first run flagged **4 of 49 images** where `--htj2k --lossless` did **not** round-trip:

| Image | px wrong | max err |
|---|---:|---:|
| `2190188.png` | 23,344 | 192 |
| `382297.png` | 38,946 | 237 |
| `297394.png` | 11,785 | 238 |
| `21169144185_3f7977cb5a_o.png` | 2,831 | 212 |

### It is the encoder, not the decoder
Cross-checked against the **OpenJPH** reference codec:
- j2k HT-encode → **OpenJPH decode**: same wrong result → our **encoder** writes wrong coefficients.
- **OpenJPH** reversible-encode → j2k decode: **0 diff** → our **decoder** is correct.
- OpenJPH self-round-trip: 0 diff → the content *is* losslessly representable.

### Root cause
[Sources/J2KCodec/J2KEncoderPipeline.swift](Sources/J2KCodec/J2KEncoderPipeline.swift) — the conformant HT encoder converts coefficients to OpenJPH sign-magnitude as `sign | (|v| << (31 - K_max))`, where the magnitude window `K_max` was derived from the **single-level** subband gain `{LL:0, HL/LH:1, HH:2}`. A multi-level reversible 5/3 transform expands the coefficient range (the deep **LL** band especially); high-contrast 8-bit content (hard 0↔255 edges) then produces coefficients whose magnitude exceeds `2^K_max`. `|v| << shift` overflowed **bit 31 (the sign bit)**, silently dropping the top bitplane.

Instrumentation on the minimal case: `comp=1 sub=ll res=0 kMax=8 window=256 maxAbs=259 → OVERFLOW`. Minimal reproducer shrunk to an **8×8 tile** ([Documentation/Benchmarks/data/htj2k_bug_repro/](Documentation/Benchmarks/data/htj2k_bug_repro/)).

Why medical data was immune: 12/16-bit DICOM stores low-range data in a wider container and never approaches full scale, so its 5/3 coefficients stayed inside the (under-sized) window.

### The fix
A centralized `htConformantReversibleGain(subband:rctActive:)` sizes the magnitude window to match **OpenJPH's proven-sufficient** reversible K_max (LL = B+1, detail = B+2, +1 bit when the reversible colour transform is active), taking `max` with the previous gain so windows **only grow, never shrink**. Applied **consistently** in the QCD marker (ε signalling) and the per-block shift, and **scoped to the HT-conformant path** so legacy EBCOT / custom-HT codestreams are byte-identical to before. The decoder needs no change — it derives K_max from the QCD ε it reads.

### Verification
- 8×8 reproducer + all 4 failing images → bit-exact, **and OpenJPH decodes our output bit-exact**.
- All 49 CID22 → 49/49 bit-exact (J2K + HTJ2K); the 45 previously-passing images unchanged.
- HT-conformant medical sample (CT/MR/DX/MG/PX 16/12/8-bit) → 47/47 bit-exact + OpenJPH cross-decode clean.
- Mandatory gate green: `J2KMedicalCorpusPerformanceTests`, `J2KMedicalCorpusEncodePerformanceTests`, `J2KStrictCrossCodecValidationTests`, `J2KHTConformantMedicalRoundTripTests`.
- New regression test [V10_25_HTConformantReversibleWindowTests](Tests/J2KCodecTests/V10_25_HTConformantReversibleWindowTests.swift) (exact reproducer + synthetic high-contrast RGB/greyscale across decomposition depths).

---

## Notes

- **Dataset scope:** CID22's full set (250 references) is gated behind a 7.2 GB archive whose CDN repeatedly truncated at ~3.6 GB, and stores the references *after* 7 GB of distorted IQA variants — so the official **49-image validation reference set** was used. It is uniformly 512×512 RGB 8-bit; it was sufficient to expose and fix the bug. Broader coverage (greyscale, 16-bit, alpha, varied sizes) would need the full set or additional sources.
- The HTJ2K lossless compression ratio dipped slightly (2.65→2.55× median) — the modest extra window headroom is the cost of correctness; still well within normal HT-vs-EBCOT range.

## Reproduce

```bash
swift build -c release --product j2k
python3 Scripts/image_corpus_roundtrip.py \
  --dataset Datasets/cid22/CID22_validation_set/original \
  --bin .build/release/j2k --workers 8 \
  --qualities 0.95,0.90,0.85,0.75,0.50 --htj2k \
  --out results/cid22_validation
```
