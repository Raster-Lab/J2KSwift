# J2KSwift ISO/IEC 15444 Conformance Matrix

## Overview

This matrix summarises J2KSwift's conformance status against all implemented parts of the
ISO/IEC 15444 (JPEG 2000) family of standards.

**Library Version**: J2KSwift 2.0.0-dev  
**Date**: 2026-02-21  
**Phase**: 17h — Part 4 Conformance Final Validation (Week 290–292)  
**Certification**: ✅ **Certified** (ISO/IEC 15444-4:2004)  

---

## Summary

| Part | Title                                    | Class 0 | Class 1 | HTJ2K | Notes                            |
|------|------------------------------------------|---------|---------|-------|----------------------------------|
| 1    | Core Coding System                       | ✅      | ✅      | —     | Full encoder and decoder         |
| 2    | Extensions                               | —       | ✅      | —     | MCT, NLT, TCQ, AWD, ROI, DCO    |
| 3    | Motion JPEG 2000                         | —       | ✅      | —     | MJ2 container, VideoToolbox      |
| 4    | Conformance Testing                      | ✅      | ✅      | ✅    | Final validation complete        |
| 10   | Three-Dimensional Data (JP3D)            | —       | ✅      | —     | 3D wavelet, volumetric codestream|
| 15   | High Throughput JPEG 2000 (HTJ2K)        | —       | —       | ✅    | All profiles: Unrestricted/HT/HT-Rev |

---

## Detailed Conformance by Part

### Part 1 — Core Coding System (ISO/IEC 15444-1:2019)

| Feature                        | Required | Status    |
|--------------------------------|----------|-----------|
| SOC/SIZ/COD/QCD markers        | Yes      | ✅ Pass   |
| EOC marker                     | Yes      | ✅ Pass   |
| Reversible 5/3 wavelet         | Yes      | ✅ Pass   |
| Irreversible 9/7 wavelet       | Yes      | ✅ Pass   |
| Class 0 decoder                | Yes      | ✅ Pass   |
| Class 1 decoder                | Yes      | ✅ Pass   |
| Lossless round-trip (all depths)| Yes     | ✅ Pass   |
| All progression orders (0–4)   | Yes      | ✅ Pass   |
| Multi-tile, multi-tile-part    | Yes      | ✅ Pass   |
| Rate-distortion optimisation   | Yes      | ✅ Pass   |
| Error resilience               | Optional | ✅ Pass   |

### Part 2 — Extensions (ISO/IEC 15444-2:2021)

| Extension                      | Required | Status    |
|--------------------------------|----------|-----------|
| DC Offset (DCO)                | Optional | ✅ Pass   |
| Arbitrary Wavelet (AWD)        | Optional | ✅ Pass   |
| Multi-Component Transform (MCT)| Optional | ✅ Pass   |
| Non-Linear Transform (NLT)     | Optional | ✅ Pass   |
| Trellis-Coded Quantisation (TCQ)| Optional| ✅ Pass   |
| Extended ROI                   | Optional | ✅ Pass   |
| Extended Precision             | Optional | ✅ Pass   |
| JPX File Format                | Optional | ✅ Pass   |

### Part 3 — Motion JPEG 2000 (ISO/IEC 15444-3:2007)

| Feature                        | Required | Status    |
|--------------------------------|----------|-----------|
| MJ2 signature box              | Yes      | ✅ Pass   |
| File type brand `mjp2`         | Yes      | ✅ Pass   |
| Frame-level J2K codestreams    | Yes      | ✅ Pass   |
| Frame rate metadata            | Yes      | ✅ Pass   |
| Temporal consistency           | Yes      | ✅ Pass   |
| VideoToolbox integration       | Optional | ✅ Pass (Apple) |

### Part 10 — Three-Dimensional Data (ISO/IEC 15444-10:2008)

| Feature                        | Required | Status    |
|--------------------------------|----------|-----------|
| 3D SIZ extension               | Yes      | ✅ Pass   |
| 3D wavelet transform (5/3)     | Yes      | ✅ Pass   |
| 3D wavelet transform (9/7)     | Yes      | ✅ Pass   |
| Volumetric tiling              | Yes      | ✅ Pass   |
| JP3D codestream structure      | Yes      | ✅ Pass   |
| Z-decomposition level bounds   | Yes      | ✅ Pass   |

### Part 4 — Conformance Testing (ISO/IEC 15444-4:2004)

| Feature                        | Required | Status    |
|--------------------------------|----------|-----------|
| Decoder Class-0 validation     | Yes      | ✅ Pass   |
| Decoder Class-1 validation     | Yes      | ✅ Pass   |
| Encoder Class-0 validation     | Yes      | ✅ Pass   |
| Encoder Class-1 validation     | Yes      | ✅ Pass   |
| Cross-part conformance (7)     | Yes      | ✅ Pass   |
| OpenJPEG cross-validation      | Yes      | ✅ Pass   |
| Conformance archiving          | Yes      | ✅ Pass   |
| Certification report           | Yes      | ✅ Pass   |

### Part 15 — High Throughput JPEG 2000 (ISO/IEC 15444-15:2019)

| Feature                        | Required | Status    |
|--------------------------------|----------|-----------|
| CAP marker (Pcap bit 17)       | Yes      | ✅ Pass   |
| CPF marker (Pcpf bit 15)       | Yes      | ✅ Pass   |
| HT block decoder (Annex B)     | Yes      | ✅ Pass   |
| HT Unrestricted profile        | Yes      | ✅ Pass   |
| HT-Only profile                | Yes      | ✅ Pass   |
| HT-Rev-Only profile            | Yes      | ✅ Pass   |
| J2K ↔ HTJ2K lossless transcode | Yes      | ✅ Pass   |
| HTJ2K in JP2 container         | Yes      | ✅ Pass   |
| HTJ2K in MJ2 container         | Optional | ✅ Pass   |
| HTJ2K in JP3D container        | Optional | ✅ Pass   |

---

## Cross-Part Conformance

| Combination                    | Status    | Notes                                |
|--------------------------------|-----------|--------------------------------------|
| Part 1 + Part 2 (Class 0)      | ✅ Pass   | No extensions in Class 0             |
| Part 1 + Part 2 (Class 1)      | ✅ Pass   | All extensions with Class 1          |
| Part 1 + Part 15 (HTJ2K in JP2)| ✅ Pass   | All HT profiles                      |
| Part 3 + Part 15 (HTJ2K in MJ2)| ✅ Pass   | Per-frame HTJ2K codestreams          |
| Part 10 + Part 15 (HTJ2K in JP3D) | ✅ Pass | Volumetric HTJ2K                  |
| Part 3 + Part 1 (MJ2 frames)   | ✅ Pass   | Each frame is Part 1 compliant       |
| Part 10 + Part 1 (JP3D volume) | ✅ Pass   | Volume uses Part 1 core coding       |

---

## Test Coverage

| Part | Test Suite File                                          | Test Count |
|------|----------------------------------------------------------|------------|
| 1    | `Tests/J2KComplianceTests/J2KPart1ConformanceTests.swift`| 49         |
| 2    | `Tests/J2KComplianceTests/J2KPart2ConformanceHardeningTests.swift` | 31 |
| 3+10 | `Tests/J2KComplianceTests/J2KPart3Part10ConformanceTests.swift` | 31 |
| 4    | `Tests/J2KComplianceTests/J2KPart4ConformanceFinalTests.swift` | 41 |
| 15   | `Tests/J2KComplianceTests/J2KPart15IntegratedConformanceTests.swift` | 31 |
| 10   | `Tests/J2KComplianceTests/JP3DComplianceTests.swift`     | 121        |
| **Total** |                                                    | **304**    |

---

## Automated Conformance Runner

The conformance runner can be invoked via:

```bash
# Run all conformance tests
./Scripts/run-conformance.sh

# Run Part 1 only
./Scripts/run-conformance.sh --part 1

# Run with verbose output
./Scripts/run-conformance.sh --verbose

# Generate a markdown report
./Scripts/run-conformance.sh --report
```

Or in Swift:

```swift
let result = J2KConformanceAutomationRunner.runAllSuites()
let report = J2KConformanceAutomationRunner.generateConformanceReport(result)
print(report)
```

---

## CI/CD Integration

Conformance is gated in CI via `.github/workflows/conformance.yml`:

- **Part 1 conformance** — `part1-conformance` job
- **Part 2 conformance** — `part2-conformance` job
- **Part 3+10 conformance** — `part3-part10-conformance` job
- **Part 4 (Final)** — `part4-conformance` job
- **Part 15 (HTJ2K)** — `part15-conformance` job
- **Part 10 (JP3D)** — `jp3d-conformance` job
- **Cross-platform** — `cross-platform-conformance` job (Linux)
- **OpenJPEG interop** — `openjpeg-interoperability` job
- **Integrated gate** — `conformance-gate` job (fails if any above fails)

---

## Known Limitations

See [`KNOWN_LIMITATIONS.md`](KNOWN_LIMITATIONS.md) for documented limitations and deviations.

---

## Conformance Archive

See [`CONFORMANCE_ARCHIVE.md`](CONFORMANCE_ARCHIVE.md) for historical test result records.

---

## Individual Part Reports

- [`PART1_CONFORMANCE.md`](PART1_CONFORMANCE.md) — Core Coding System
- [`PART2_CONFORMANCE.md`](PART2_CONFORMANCE.md) — Extensions
- [`PART3_MJ2_CONFORMANCE.md`](PART3_MJ2_CONFORMANCE.md) — Motion JPEG 2000
- [`PART4_CONFORMANCE_REPORT.md`](PART4_CONFORMANCE_REPORT.md) — Conformance Testing
- [`PART10_JP3D_CONFORMANCE.md`](PART10_JP3D_CONFORMANCE.md) — Three-Dimensional Data
- [`PART15_HTJ2K_CONFORMANCE.md`](PART15_HTJ2K_CONFORMANCE.md) — High Throughput JPEG 2000

---

## References

- ISO/IEC 15444-1:2019 — Core coding system
- ISO/IEC 15444-2:2021 — Extensions
- ISO/IEC 15444-3:2007 — Motion JPEG 2000
- ISO/IEC 15444-4:2004 — Conformance testing
- ISO/IEC 15444-10:2008 — Three-dimensional data
- ISO/IEC 15444-15:2019 — High Throughput JPEG 2000
