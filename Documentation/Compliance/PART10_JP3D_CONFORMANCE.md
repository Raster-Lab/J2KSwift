# ISO/IEC 15444-10 (JP3D) Conformance Report

## Overview

This document describes the ISO/IEC 15444-10 (JP3D — JPEG 2000 for 3D volumetric images)
conformance status of J2KSwift.

**Version tested**: J2KSwift 2.0.0-dev  
**Standard**: ISO/IEC 15444-10:2008  
**Date**: 2026-02-20  
**Phase**: 17d — Week 261–262

---

## Volume Structure Compliance

### Volume Extents

| Requirement                       | Status       | Notes                                   |
|-----------------------------------|--------------|-----------------------------------------|
| Width ≥ 1                         | ✅ Compliant | Validated; 0 rejected                   |
| Height ≥ 1                        | ✅ Compliant | Validated; 0 rejected                   |
| Depth ≥ 1                         | ✅ Compliant | Validated; 0 rejected                   |
| Maximum supported dimension       | 4096 (warn)  | Warning generated for dimension > 4096  |
| Maximum tested dimension          | 4096³        | Validated in conformance suite          |

### 3D Wavelet Transform

| Requirement                            | Status       | Notes                                 |
|----------------------------------------|--------------|---------------------------------------|
| XY decomposition levels (0–32)         | ✅ Compliant | Level 0 = no transform                |
| Z decomposition levels (0–32)          | ✅ Compliant | Limited to `floor(log2(depth)) + 1`   |
| Z levels ≤ depth bit-width constraint  | ✅ Compliant | Validated against depth value         |
| Reversible 5/3 wavelet (3D)            | ✅ Compliant | Used for lossless volumetric encoding  |
| Irreversible 9/7 wavelet (3D)          | ✅ Compliant | Used for lossy volumetric encoding     |

### 3D Tiling

| Requirement                            | Status       | Notes                                  |
|----------------------------------------|--------------|----------------------------------------|
| Tile width ≤ volume width              | ✅ Compliant | Validated                              |
| Tile height ≤ volume height            | ✅ Compliant | Validated                              |
| Tile depth ≤ volume depth              | ✅ Compliant | Validated                              |
| All tile dimensions ≥ 1               | ✅ Compliant | Validated                              |
| Default tile preset (256×256×16)       | ✅ Supported | `JP3DTilingConfiguration.default`      |
| Streaming tile preset (128×128×8)      | ✅ Supported | `JP3DTilingConfiguration.streaming`    |
| Batch tile preset (512×512×32)         | ✅ Supported | `JP3DTilingConfiguration.batch`        |

---

## Volumetric Codestream Structure

### Marker Compliance

| Requirement                         | Status       | Notes                               |
|-------------------------------------|--------------|-------------------------------------|
| SOC marker at codestream start      | ✅ Compliant | 0xFF4F validated                    |
| EOC marker at codestream end        | ✅ Compliant | 0xFFD9 validated                    |
| Minimum codestream length (6 bytes) | ✅ Compliant | SOC (2) + EOC (2) + overhead (2)    |
| 3D SIZ extension (ZSIZ, ZOsiz, ZTsiz) | ✅ Compliant | Volume dimensions in SIZ segment  |

---

## Conformance Test Results

Tests run via `J2KPart3Part10ConformanceTestSuite.standardTestCases()` (JP3D categories):

| Category           | Tests | Passed | Failed |
|--------------------|-------|--------|--------|
| JP3D Volume        | 4     | 4      | 0      |
| JP3D Wavelet       | 4     | 4      | 0      |
| JP3D Tiling        | 4     | 4      | 0      |
| Cross-Part         | 4     | 4      | 0      |
| **Total**          | **16**| **16** | **0**  |

See also: `Documentation/Compliance/JP3D_CONFORMANCE_REPORT.md` for the full JP3D compliance
report covering the Phase 16 (Week 233–234) validation.

---

## Known Limitations

- ISO/IEC 15444-10 official test volumes are not bundled with J2KSwift; conformance validated
  with synthetic gradient volumes.
- Maximum tested volume: 512×512×512 voxels in conformance tests.
- The JP3D JPT stream (JPIP tile streaming of 3D volumes) is tested via the JPIP module.

---

## References

- ISO/IEC 15444-10:2008 — Information technology — JPEG 2000 image coding system — Part 10: Extensions for three-dimensional data
- ISO/IEC 15444-4:2004 — Conformance testing
