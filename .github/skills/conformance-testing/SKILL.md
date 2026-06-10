---
name: conformance-testing
description: 'ISO/IEC 15444-4 conformance testing for JPEG 2000 releases. Use for pre-release validation, compliance verification, running conformance test suites, checking error tolerances, generating compliance reports.'
---

# Conformance Testing (ISO/IEC 15444-4)

Pre-release compliance verification against the JPEG 2000 standard.

## When to Use
- Before any release (mandatory)
- After major codec changes
- When verifying a new conformance profile
- Generating compliance reports

## Procedure

### 1. Run All Conformance Tests
```bash
swift test --filter J2KConformanceTestingTests
swift test --filter J2KComplianceTests
```

### 2. Run Security and Stress Tests
```bash
swift test --filter J2KSecurityTests
swift test --filter J2KStressTests
```

### 3. Run Interoperability Tests
```bash
swift test --filter J2KInteroperabilityTests
swift test --filter J2KCrossPlatformValidationTests
```

### 4. Full Build Verification
```bash
swift build
swift test
```

### 5. Verify Error Tolerances

Check decoded image quality metrics:

| Mode | Metric | Threshold |
|------|--------|-----------|
| Lossless (5/3 DWT) | MAE | = 0 |
| Near-lossless (9/7 DWT) | MAE | ≤ 2 |
| Lossy | MAE | Per test case |
| Visual quality | PSNR | ≥ 30 dB |

### 6. Profile Checklist

Verify each applicable profile:

#### Profile 0 (Baseline)
- [ ] Single tile, single component
- [ ] Multi-component (RGB)
- [ ] 5/3 reversible DWT
- [ ] 9/7 irreversible DWT
- [ ] Multiple decomposition levels

#### Profile 1 (Extended)
- [ ] ROI coding
- [ ] MCT (multiple component transforms)
- [ ] Extended quantization

#### HTJ2K (Part 15)
- [ ] HT block coding
- [ ] Cleanup pass decoding
- [ ] Placeholder passes

### 7. Generate Compliance Report

Document results in the following format:
```markdown
## Conformance Report - v<version>
- Date: <date>
- Profile 0: PASS/FAIL (N/M tests)
- Profile 1: PASS/FAIL (N/M tests)
- HTJ2K: PASS/FAIL (N/M tests)
- Error Metrics: MAE=<val>, PSNR=<val>dB
- Known Limitations: <list>
```

### 8. Release Gate Decision
- **GO**: All mandatory tests pass, error metrics within tolerance
- **NO-GO**: Any conformance test fails, document and fix before release

## Reference Files
- `CONFORMANCE_TESTING.md` — Conformance testing guide
- `RELEASE_CHECKLIST.md` — Release checklist template
- `Tests/J2KCoreTests/J2KConformanceTestingTests.swift` — Test suite
- `Sources/J2KCore/J2KPart1Conformance.swift` — Part 1 codestream validators
