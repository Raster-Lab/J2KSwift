# ISO/IEC 15444-3 (Motion JPEG 2000) Conformance Report

## Overview

This document describes the ISO/IEC 15444-3 (Motion JPEG 2000) conformance status of J2KSwift.

**Version tested**: J2KSwift 2.0.0-dev  
**Standard**: ISO/IEC 15444-3:2007 (with Amendment 2)  
**Date**: 2026-02-20  
**Phase**: 17d — Week 261–262

---

## MJ2 File Format Compliance

### Signature and File Type

| Requirement                          | Status       | Notes                            |
|--------------------------------------|--------------|----------------------------------|
| JP2 signature box (12 bytes)         | ✅ Compliant | `6A 50 20 20` magic bytes        |
| File type brand `mjp2`               | ✅ Compliant | `6D 6A 70 32` in ftyp box        |
| Compatibility list includes `jp2 `   | ✅ Compliant | Backwards compatible             |
| Movie box (`moov`)                   | ✅ Compliant | Mandatory container box          |
| Track box (`trak`)                   | ✅ Compliant | Video track for frames           |
| Media box (`mdia`)                   | ✅ Compliant | Media information container      |
| Sample description (`stsd`)          | ✅ Compliant | MJ2V sample entry                |

### Frame-Level Compliance

| Requirement                          | Status       | Notes                            |
|--------------------------------------|--------------|----------------------------------|
| Frame-level JPEG 2000 codestreams    | ✅ Compliant | Each frame is an independent J2K codestream |
| Consistent dimensions across frames  | ✅ Compliant | Width/height validated per frame |
| Consistent bit depth across frames   | ✅ Compliant | Component depth consistency      |
| Component count consistent           | ✅ Compliant | Per-frame component count        |

### Temporal Metadata

| Requirement                          | Status       | Notes                            |
|--------------------------------------|--------------|----------------------------------|
| Frame rate (numerator/denominator)   | ✅ Compliant | Range: 1/128 to 999 fps          |
| Duration consistency                 | ✅ Compliant | `|frameCount/duration - fps| < 1%` |
| Timescale field                      | ✅ Compliant | Millisecond-precision timescales |
| Edit list support                    | ✅ Supported | Optional; edit lists preserved   |

---

## Conformance Test Results

Tests run via `J2KPart3Part10ConformanceTestSuite.standardTestCases()` (MJ2 categories):

| Category           | Tests | Passed | Failed |
|--------------------|-------|--------|--------|
| MJ2 Structure      | 4     | 4      | 0      |
| MJ2 Frame Rate     | 4     | 4      | 0      |
| MJ2 Temporal       | 4     | 4      | 0      |
| **Total**          | **12**| **12** | **0**  |

---

## Known Limitations

- VideoToolbox hardware acceleration is only available on Apple platforms. Linux/Windows use
  software JPEG 2000 encoding/decoding for each frame.
- Maximum frame size tested: 8192×8192 pixels, 3 components, 8 bits.
- JPM (JPEG 2000 Part 6 compound document) profiles are not supported.

---

## References

- ISO/IEC 15444-3:2007 — Information technology — JPEG 2000 image coding system — Part 3: Motion JPEG 2000
- ISO/IEC 15444-4:2004 — Conformance testing
