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
- [ ] `swift build -c release` passes on supported platforms
- [ ] `swift test -c release` passes

### Compliance Verification (ISO/IEC 15444-4)
- [ ] All conformance tests pass
- [ ] Lossless error metrics: MAE = 0 across conformance suite
- [ ] Lossy error metrics within tolerance per spec
- [ ] Cross-codec lossless round-trip with OpenJPEG verified
      (`testDICOMWholeSlideImaging` bit-exact lossless section)

### Medical validation
- [ ] `testHDRAndColorCoverage` — all 19 configurations bit-exact
      lossless
- [ ] `testDICOMWholeSlideImaging` — all 10 tile configurations
      bit-exact lossless, lossy PSNR at or ahead of OpenJPEG
- [ ] `testCompressionRatioOnRealDICOM` passes
- [ ] DICOMKit Phase 1 integration tests pass

### Documentation
- [x] CHANGELOG.md — v4.0.0 entry added
- [x] RELEASE_NOTES_v4.0.0.md — created
- [x] RELEASE_CHECKLIST_v4.0.0.md — created
- [ ] README / Documentation claims aligned with shipped behaviour
      (no HTJ2K Part-15 conformance claims; conformance tracked as
      follow-up work)

## Post-Release

### Artefacts
- [ ] Git tag `v4.0.0` created on `main` after merge
- [ ] GitHub Release published with RELEASE_NOTES_v4.0.0.md body
- [ ] Swift Package Index refresh

---

**Prepared by**: J2KSwift Development Team
**Review Status**: Pending
