# J2KSwift v4.0.0 Release Checklist

**Version**: 4.0.0
**Release Date**: 2026-04-24
**Release Type**: Major Release

## Pre-Release Verification

### Code Quality
- [x] VERSION file updated to 4.0.0
- [x] CHANGELOG.md updated with v4.0.0 entry
- [x] Public API surface changes are additive-only (new `ByteOrder` enum,
      new optional `sampleByteOrder` init parameter, new
      `quantizationStep` getter)
- [x] `swift build -c release` passes — *Build complete! (105.86s), 2026-04-24*
- [x] Key release test filters pass (see below)

### Compliance Verification (ISO/IEC 15444)
- [x] Conformance suite — **315/315 tests passed, 0 failures**
      (`swift test -c release --filter Conformance`, 2026-04-24)
  - Covers: Part 1 (core codestream), Part 2 (extensions), Part 3/10
    (Motion JPEG 2000, JP3D), Part 4 (conformance testing), Part 15
    (HTJ2K), plus MJ2 validator and the JP3D compliance suite.
- [x] Lossless round-trip: MAE = 0 verified via
      `testDICOMWholeSlideImaging` (all 10 tile configurations
      bit-exact lossless) and `testHDRAndColorCoverage` (all 19
      configurations bit-exact lossless).
- [x] Cross-codec lossless round-trip with OpenJPEG verified — all 10
      WSI tile configurations match OpenJPEG byte-for-byte on the
      lossless path.

### Medical validation
- [x] `testHDRAndColorCoverage` — passed (4.97s). All 19 configurations
      (8/10/12/14/16-bit × grayscale/RGB at 512²–2048²).
- [x] `testDICOMWholeSlideImaging` — passed (53.59s). All 10 tile
      configurations bit-exact lossless; lossy RGB PSNR at or ahead of
      OpenJPEG (+0.02 to +0.26 dB across 6 lossy points).
- [x] `testCompressionRatioOnRealDICOM` — passed (60.64s).
- [x] `J2KDICOMKitIntegrationTests` — 5/5 passed (lossless 8/12/16-bit
      grayscale, lossless RGB, lossy grayscale).

### Documentation
- [x] CHANGELOG.md — v4.0.0 entry added
- [x] RELEASE_NOTES_v4.0.0.md — created
- [x] RELEASE_CHECKLIST_v4.0.0.md — created (this file)
- [x] Release notes document known limitations (HTJ2K non-conformance,
      256² lossy decode gap)

## Post-Release

### Artefacts
- [ ] PR merged to `main`
- [ ] Git tag `v4.0.0` created on `main`
- [ ] GitHub Release published with RELEASE_NOTES_v4.0.0.md body
- [ ] Swift Package Index refresh

---

**Prepared by**: J2KSwift Development Team
**Review Status**: Pre-release verification complete — ready to merge
