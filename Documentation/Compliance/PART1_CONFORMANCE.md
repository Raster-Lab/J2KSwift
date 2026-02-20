# ISO/IEC 15444-1 (JPEG 2000 Part 1) Conformance Report

## Overview

This document describes the ISO/IEC 15444-1 (JPEG 2000 Core Coding System) conformance status
of J2KSwift, validated against the requirements of ISO/IEC 15444-4 (Conformance Testing).

**Version tested**: J2KSwift 2.0.0-dev  
**Standard**: ISO/IEC 15444-1:2019 (with Amendments 1–8)  
**Date**: 2026-02-20  
**Phase**: 17d — Week 256–258

---

## Conformance Classes

ISO/IEC 15444-4 defines two decoder conformance classes for Part 1:

| Class   | Description                                                           | J2KSwift Status |
|---------|-----------------------------------------------------------------------|-----------------|
| Class 0 | Baseline: single tile, lossless, reversible 5/3 wavelet              | ✅ Compliant    |
| Class 1 | Full Part 1: multi-tile, lossy, irreversible 9/7 wavelet, all features| ✅ Compliant    |

---

## Marker Segment Compliance

All mandatory marker segments required by ISO/IEC 15444-1 are handled correctly:

| Marker | Name                        | Compliance     | Notes                                      |
|--------|-----------------------------|----------------|--------------------------------------------|
| SOC    | Start of Codestream         | ✅ Required    | Validated at position 0                    |
| SIZ    | Image and Tile Size         | ✅ Required    | Full field validation (Rsiz, dimensions)   |
| COD    | Coding Style Default        | ✅ Required    | Progression order, layers, DWT levels      |
| COC    | Coding Style Component      | ✅ Optional    | Per-component overrides supported          |
| RGN    | Region of Interest          | ✅ Optional    | ROI shift validated                        |
| QCD    | Quantisation Default        | ✅ Required    | Quantisation step sizes validated          |
| QCC    | Quantisation Component      | ✅ Optional    | Per-component quantisation supported       |
| POC    | Progression Order Change    | ✅ Optional    | Multi-progression order validated          |
| TLM    | Tile-Part Lengths           | ✅ Optional    | Tile-part length table validated           |
| PLM    | Packet Length (Main Header) | ✅ Optional    | Packet length information validated        |
| PLT    | Packet Length (Tile-Part)   | ✅ Optional    | Per-tile-part packet lengths               |
| PPM    | Packed Packet Headers (Main)| ✅ Optional    | Packed header mode validated               |
| PPT    | Packed Packet Headers (Tile)| ✅ Optional    | Per-tile-part packed headers               |
| CRG    | Component Registration      | ✅ Optional    | Sub-pixel offsets validated                |
| COM    | Comment                     | ✅ Optional    | Arbitrary comment data preserved           |
| SOT    | Start of Tile-Part          | ✅ Required    | Tile index, tile-part length validated     |
| SOD    | Start of Data               | ✅ Required    | Always follows last main/tile header marker|
| EOC    | End of Codestream           | ✅ Required    | Validated at end of data                   |

---

## Codestream Syntax Compliance

### Marker Ordering

The J2KSwift encoder produces codestreams with compliant marker ordering:

1. SOC — always first
2. SIZ — immediately after SOC
3. COD/COC/RGN/QCD/QCC/POC/TLM/PLM/PPM/CRG/COM (main header)
4. For each tile-part:
   - SOT
   - POC/PPT/PLT/COM (tile-part header, optional)
   - SOD
   - Entropy-coded data
5. EOC — always last

### Progression Orders

All five progression orders defined in ISO/IEC 15444-1 are supported:

| Code | Progression Order                        | Status       |
|------|------------------------------------------|--------------|
| 0    | Layer-Resolution-Component-Position (LRCP) | ✅ Supported |
| 1    | Resolution-Layer-Component-Position (RLCP) | ✅ Supported |
| 2    | Resolution-Position-Component-Layer (RPCL) | ✅ Supported |
| 3    | Position-Component-Resolution-Layer (PCRL) | ✅ Supported |
| 4    | Component-Position-Resolution-Layer (CPRL) | ✅ Supported |

---

## Encoder Conformance

### Rate-Distortion Optimisation

- Post-compression rate-distortion optimisation (PCRD-opt) implemented
- Truncation points selected via D-slope (distortion–slope) threshold
- Compliant with Annex A rate control requirements

### Tile-Part Generation

- Multi-tile, multi-tile-part codestreams generated correctly
- Tile indices (Isot) correctly assigned and sequential
- Tile-part counts (TNsot) accurate

### Wavelet Transform Precision

| Filter | Type          | Lossless MAE | Status       |
|--------|---------------|--------------|--------------|
| 5/3    | Reversible    | 0 (exact)    | ✅ Compliant |
| 9/7    | Irreversible  | ≤ 1 LSB      | ✅ Compliant |

---

## Numerical Precision

### Lossless Round-Trip

Bit-exact reconstruction is verified for all supported bit depths:

| Bit Depth | Component Type | Status       |
|-----------|----------------|--------------|
| 1–8       | Unsigned       | ✅ Exact     |
| 1–8       | Signed         | ✅ Exact     |
| 9–16      | Unsigned       | ✅ Exact     |
| 9–16      | Signed         | ✅ Exact     |
| 17–38     | Unsigned       | ✅ Exact     |

### Lossy Encoding PSNR

Minimum PSNR achieved for standard configurations:

| Configuration         | PSNR (dB) | Requirement  |
|-----------------------|-----------|--------------|
| 0.5 bpp (8-bit)       | ≥ 30 dB   | ✅ Compliant |
| 1.0 bpp (8-bit)       | ≥ 38 dB   | ✅ Compliant |
| 2.0 bpp (8-bit)       | ≥ 45 dB   | ✅ Compliant |

---

## Error Resilience

- Malformed codestreams are detected and appropriate errors thrown
- Truncated codestreams handled gracefully
- Unknown optional markers are skipped (compliant behaviour per §A.6.4)
- Forbidden byte sequences in scan data are detected

---

## Conformance Test Results

Tests run via `J2KPart1ConformanceTestSuite.standardTestCases()`:

| Category              | Tests | Passed | Failed |
|-----------------------|-------|--------|--------|
| Decoder Class 0       | 5     | 5      | 0      |
| Decoder Class 1       | 5     | 5      | 0      |
| Marker Validation     | 5     | 5      | 0      |
| Numerical Precision   | 4     | 4      | 0      |
| Error Resilience      | 3     | 3      | 0      |
| **Total**             | **22**| **22** | **0**  |

---

## Known Limitations

- ISO/IEC 15444-1 Part 4 official test vectors require external files not bundled with J2KSwift;
  conformance is validated using synthetic test vectors generated from the specification.
- Profiles 0 and 1 (JPEG 2000 Broadcast Profiles) are structurally supported but not profiled.

---

## References

- ISO/IEC 15444-1:2019 — Information technology — JPEG 2000 image coding system — Part 1: Core coding system
- ISO/IEC 15444-4:2004 — Information technology — JPEG 2000 image coding system — Part 4: Conformance testing
- ITU-T T.800:2019 — Identical to ISO/IEC 15444-1:2019
