# J2KSwift v5.1.1 Release Notes

**Release Date**: 2026-04-24
**Release Type**: Patch
**Previous Version**: 5.1.0

---

## Summary

v5.1.1 fixes the `.conformant` HTJ2K lossless round-trip bug that
corrupted every pixel-value-0 sample on real medical DICOM payloads
(reported by DICOMKit). Root cause was a K_max off-by-one in the
shared Part-15 reversible code path — the same rollover present in
OpenJPH 0.26 — so the fix also lifts the v5.0.0-documented "sample
value 0 → 128 on decode" edge case in memory note #5.

Verified on the staged medical-dicom corpus: CT / MR 16-bit lossless
`.conformant` round-trips are now bit-exact through J2KSwift's own
decode API. OpenJPH cross-codec interop tests updated to assert
input equality (strictly stronger than the prior "match OpenJPH's
buggy self round-trip" baseline, which was papering over exactly
this bug).

---

## Fixed

- **`.conformant` HTJ2K lossless round-trip corrupted every
  pixel-value-0 sample on unsigned inputs.** For a B-bit unsigned
  image, DC-shifting maps pixel 0 to signed `-2^(B-1)` whose
  magnitude is `2^(B-1)`. The encoder's K_max (per OpenJPH's native
  ε = `B + G - guardBits`) was `B + G - 1`, giving a magnitude range
  of `[0, 2^(B+G-1) - 1]` that falls one short of representing
  `2^(B-1)`. The magnitude rolled over to 0, decoded as
  non-significant, and the pixel surfaced as `2^(B-1)` (128 at 8-bit,
  32768 at 16-bit) after DC-shift reversal. Fix bumps K_max by 1
  and emits `ε_b = B + G_b + 1 - guardBits` in QCD so any Part-15
  decoder (including OpenJPH) reconstructs the correct range.
  ([J2KEncoderPipeline.swift `encodeCodeBlockConformant`](Sources/J2KCodec/J2KEncoderPipeline.swift),
  [`writeQCDMarker` reversible branch](Sources/J2KCodec/J2KEncoderPipeline.swift))

---

## Changed

- OpenJPH cross-codec tests
  (`testEndToEnd{8x8GradientLossless,32x32NoiseLossless}`) now assert
  the decoded output matches the **original input** rather than
  OpenJPH's own self round-trip. The prior baseline masked the
  pixel-0 rollover because both codecs hit the same bug at the same
  time; the new baseline is strictly stronger and ensures the fix
  didn't trade one bug for another.
- `J2KHTConformantSelfRoundTripTests`'s `selfRoundTripNoise` helper
  no longer skips pixel value 0 — the workaround is obsolete.
- `VERSION` bumped from `5.1.0` to `5.1.1`.

---

## Added

- `J2KHTConformantMedicalRoundTripTests` (J2KCLITests target) — 3
  new regression tests running the exact downstream DICOMKit repro:
  encode a staged DICOM sample with `.conformant`, decode through
  J2KSwift's own API, assert bit-exact. Covers decomp=0 and decomp=3
  across CT + MR at 16-bit.

---

## Test coverage

- 191 HT tests (0 failures).
- 103 tests across DICOM integration, encoder pipeline, lossless
  stress, and quantization (0 failures, all previously-passing suites
  remain green).
- Cross-codec byte-exact check against OpenJPH `ojph_expand`
  preserved (stricter input-equality form).

---

## Known limitations (unchanged from v5.1.0)

- Default `J2KEncodingConfiguration.htj2kBlockFormat` remains
  `.custom`. Flipping to `.conformant` awaits a fix for a
  pre-existing non-power-of-2 subband geometry issue in the shared
  Part-15 block coder (confirmed with `ojph_expand` decoding the same
  bytes, so the bug is upstream of decoder dispatch).
- Fused MEL/VLC terminate byte optimization (~1 byte/block) and
  SIMD block coder (SSSE3/AVX2/AVX512) not yet applied.

---

## Upgrade recommendation

**Required** for any caller using
`htj2kBlockFormat = .conformant` on real medical / non-synthetic
data. v5.1.0 silently corrupted every zero-valued sample; v5.1.1
restores bit-exact lossless round-trip. No API change is needed to
opt in — just link 5.1.1.
