# J2KSwift v4.0.0 Release Notes

**Release Date**: 2026-04-24
**Release Type**: Major
**Previous Version**: 3.0.1

---

## Summary

v4.0.0 is a production-readiness milestone for J2KSwift as a medical-grade
JPEG 2000 codec. The release consolidates rate-control, byte-order handling,
IDWT, and test-coverage work driven by real DICOM validation — including
full DICOM Whole Slide Imaging (WSI / pathology) coverage and a DICOMKit
Phase 1 integration pass.

Although the public API surface only grows (no signatures removed or
changed), the scope, clinical validation surface, and internal behavioural
changes across PCRD, 16-bit byte-order inference, and multi-component
tuning justify the major version signal for downstream PACS integrators.

---

## Highlights

### Rate control
- PCRD subband weights derived from the theoretical 9/7 L2 norms × stepsize²
  with an HVS-aware refinement across resolution levels, closing the
  medical-image BD-rate gap vs OpenJPEG.
- HVS subband refinement (LL×1.25, HH damped to ×0.55, etc.) now applies
  to multi-component lossy (RGB) as well as grayscale. HH is noise
  regardless of component, so RGB lossy receives the same perceptual
  tuning as medical grayscale.

### 16-bit byte-order correctness
- New `J2KComponent.ByteOrder` enum (`.littleEndian`, `.bigEndian`) and
  new optional `sampleByteOrder: ByteOrder?` initializer parameter so
  callers can hand-hint the byte order of 16-bit sample buffers.
- Fixes a class of 1024²+ 16-bit lossless corruption where the heuristic
  inferencer tied between LE and BE interpretations.
- Strided 4096-sample byte-order inferencer sweep + default to big-endian
  on tie, restoring correct MG/MR modality output.

### IDWT
- Skip-memset optimization on multi-level 9/7 and 5/3 inverse transforms
  when all cells are written.

### Compression validation
- Fixed a long-standing bug in the WSI lossy-RGB benchmark that asked
  OpenJPEG for 3× the bit budget of J2KSwift (`24 / (bpp * 3)` →
  `24 / bpp`). This had been producing a phantom 3–8 dB PSNR deficit in
  benchmark output. With the corrected formula J2KSwift is at or ahead
  of OpenJPEG on all tested lossy RGB configurations.

### Test coverage
- `testHDRAndColorCoverage` — 19 configurations (8/10/12/14/16-bit ×
  grayscale/RGB at 512²/768²/1024²/2048²).
- `testDICOMWholeSlideImaging` — 10 tile configurations (256²–4096² at
  8/16-bit RGB) with a synthetic H&E pathology generator, both lossless
  round-trip and lossy rate-distortion measurements.
- `testHTJ2KvsOpenJPH` — 7 configurations benchmarking the HTJ2K path
  against OpenJPH.
- `testDecodeHotspotProfile` — per-configuration decode timing with
  10-run medians across grayscale/medical/small-tile configs.
- DICOMKit Phase 1 integration test regressions addressed.

### Build
- `J2KCore` and `J2KCodec` targets now compile with
  `-O -whole-module-optimization` in release configuration.

---

## API changes (additive only)

- `J2KComponent.ByteOrder` — new public `Sendable` enum.
- `J2KComponent.sampleByteOrder: ByteOrder?` — new public property.
- `J2KComponent.init(..., sampleByteOrder: ByteOrder? = nil)` — new
  optional parameter with `nil` default.
- `J2KCodeBlock.quantizationStep: Double?` — new public optional getter
  used by PCRD for stepsize²-scaled subband weighting.

All existing call sites continue to compile without modification.

---

## Breaking Changes

None at the source-API level.

Callers supplying 16-bit imagery who previously relied on the heuristic
byte-order inferencer will see the same behaviour by default (no hint
passed). For deterministic results on boundary cases (1024²+, MG/MR
modalities, tied byte-order penalties), callers should now pass
`sampleByteOrder: .bigEndian` or `.littleEndian` explicitly.

---

## Migration

- Existing code: no changes required.
- For DICOM callers handling 16-bit big-endian `OB`/`OW` sample buffers,
  pass `sampleByteOrder: .bigEndian` to `J2KComponent.init(...)` for
  deterministic encoding.

---

## Known limitations

- HTJ2K (Part-15) block format in this release is a non-standard custom
  layout used by the J2KSwift fast path; it is not bit-compatible with
  OpenJPH or other Part-15 conformant decoders. Full Part-15 conformance
  is tracked as a follow-up work item.
- 256² lossy decode is ~0.73× of OpenJPEG in absolute throughput
  (1.36 ms median vs ~1.0 ms). The gap is in the Swift MQ-coder hot loop
  and is not addressed in this release.

---

## Requirements

- Swift 6.2 or later
- macOS 15+ / iOS 17+ / tvOS 17+ / watchOS 10+ / visionOS 1+ / Linux / Windows

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "4.0.0")
]
```
