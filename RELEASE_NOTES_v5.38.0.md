# J2KSwift v5.38.0 Release Notes

**Release Date**: 2026-05-05
**Release Type**: Minor
**Previous Version**: 5.22.0
**Branch**: v5.38-release-candidate

---

## Summary

v5.38.0 refocuses J2KSwift's product target on **bit-exact lossless medical archival** and delivers a series of compounding encoder optimisations that bring DX 12 MP encode to **2.06× faster than v5.22** — achieved entirely in pure Swift without any algorithmic changes to the HT conformant pipeline.

The headline correctness gate is **28 / 28 tests passed** across the full medical + cross-codec benchmark suite (lossless medical gate, 20-case in-process medical benchmark vs OpenJPEG 2.5.4, and strict cross-codec validation). All 11 lossless tests achieve **MAE = 0** (bit-exact reconstruction). All 7 medical fixtures cross-decode bit-exactly through OpenJPEG 2.5.4, OpenJPH, Grok, and Kakadu 8.4.1 — in both EBCOT-fair (Part 1) and HT-fair (Part 15) modes.

---

## What's New

### M1 — Lossless gate scaffolding + bit-exact roundtrip table
- `J2KLosslessMedicalGateTests.testLosslessRoundTripBitExactAcrossMedicalCorpus` exercises 7 DICOM fixtures (MR-small 180², CT 512², MR 886², XA 1024², PX 2459×1316, DX 2800×2288) through `J2KEncoder(.lossless).encode → J2KDecoder.decode` and asserts bit-exact roundtrip.
- `Tests/J2KCodecTests/CrossCodecTooling.swift` consolidates external-codec tooling and adds Kakadu 8.4.1 demo to the codec roster.

### M2 — Lossless cross-codec matrix (OpenJPEG + OpenJPH + Grok + Kakadu)
- `testLosslessCrossCodecMatrixAcrossMedicalCorpus` drives all 7 fixtures × 4 external codecs = 28 cross-decode pairs, all bit-exact.
- Default-mode, HT-fair, and EBCOT-fair sweeps with median-of-5 timing.
- **Format finding**: J2KSwift + OpenJPH default to HT/Part-15; OpenJPEG, Grok, Kakadu default to EBCOT/Part-1. In HT-fair mode all five codecs converge to identical byte counts on every fixture.

### M3 Step-A — `J2KBitWriter.writeBytes` bulk fast path (−43% DX encode)
- Replaced byte-by-byte loop with `buffer.append(contentsOf:)` (single memcpy) when the writer is byte-aligned and byte-stuffing is disabled — always true for post-SOD tile-data writes.
- DX 2800×2288: 156.9 ms → 88.2 ms (**1.78×**). Codestream-generation stage drops from 47% → 7% of total.

### M4 — HT vs EBCOT comparison + format trade-off documentation
- New `testJ2KSwiftLosslessHTvsEBCOTOnMedicalCorpus` runs both lossless paths and quantifies the trade-off per fixture.
- EBCOT lossless is 13–32% denser; HT lossless is 2–4× faster encode/decode. Both paths bit-exact.
- EBCOT bytes match OpenJPEG/Grok/Kakadu defaults byte-for-byte on every fixture.

### M5 — Branchless 5/3 forward lifting (DWT −9 to −15%)
- Split bulk lifting loops into branchless body + scalar tail, enabling LLVM NEON auto-vectorisation.
- DX DWT stage: 35.5 ms → 31.9 ms. Cumulative DX encode: **1.87×**.

### M7 — `extractComponentData` branch hoist (preprocess −66 to −72%)
- Specialised the 16-bit extraction loop to one of 4 closed-form bodies before the loop, eliminating per-pixel `byteOrder`/`signed` branches and enabling auto-vectorisation.
- DX preprocess: 7.18 ms → 2.43 ms (−66%). Cumulative DX encode: still **1.87×** (preprocess was small fraction).

### M8 — HT conformant entropy encoder buffer reuse (entropy −4 to −10%)
- Added `reset()` to `HTMagSgnEncoderConformant`, `HTMELEncoderConformant`, and bit-emitter types, using `removeAll(keepingCapacity: true)`.
- Pre-allocated encoders once per chunk; 6900 heap allocations per DX encode eliminated.
- Cumulative DX encode: **2.00×**.

### M9 — Sign-magnitude buffer reuse + pointer-based encoder (entropy −10%)
- New `HTBlockEncoderConformant.encode` overload taking `UnsafeBufferPointer<UInt32>` coefficients.
- `conformantIn` buffer re-used per chunk, eliminating ~36 MB allocator churn per DX encode.
- Per-quad hot loop now uses direct pointer indexing — no Swift `Array` bounds check.
- Cumulative DX encode: **2.06×** | PX: **2.12×**.

### M10 — Negative result (micro-optimisations on per-quad scan)
- Interior fast-path and `@inline(__always)` attempts both fell within run-to-run noise. Reverted; lessons documented.

---

## Cumulative Encode Speedup vs v5.22 Baseline

| Fixture | v5.22 | v5.38.0 | Speedup |
|---|---:|---:|---:|
| DX 2800×2288 (12 MP) | 156.9 ms | **76.0 ms** | **2.06×** |
| PX 2459×1316 (3.2 MP) | 78.3 ms | **36.9 ms** | **2.12×** |
| XA 1024×1024 | 22.4 ms | **11.4 ms** | **1.96×** |
| MR 886×886 | 7.6 ms | **5.3 ms** | **1.43×** |

---

## Format-Fair Cross-Codec Results (median of 5 runs)

### HT-fair (Part 15) encode time

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu | Fastest |
|---|---:|---:|---:|---:|:---|
| MR-small 180×180 | 29.5 ms | 7.3 ms | 8.9 ms | **3.0 ms** | Kakadu |
| CT 512×512 | 208.7 ms | 11.7 ms | 10.0 ms | **3.5 ms** | Kakadu |
| DX 2800×2288 | 5295.5 ms | 128.6 ms | 58.9 ms | **25.5 ms** | Kakadu |

### EBCOT-fair (Part 1) — byte-identical output across all codecs

All 7 fixtures × 5 codecs produce **identical compressed byte counts** in EBCOT-fair mode. Cross-decode matrix: **28/28 ✓**.

---

## Test Suite Results (v5.38 release candidate, 2026-05-05)

| Suite | Tests | Passed | Failed | Duration |
|---|---:|---:|---:|---:|
| J2KLosslessMedicalGateTests | 5 | 5 | 0 | 1213.9 s |
| J2KMedicalBenchmarkTests | 20 | 20 | 0 | 509.3 s |
| J2KStrictCrossCodecValidationTests | 3 | 3 | 0 | 7.0 s |
| **Total** | **28** | **28** | **0** | **1730.2 s** |

All 11 lossless test cases: **MAE = 0** (perfect bit-exact reconstruction).

---

## Bug Fixes

None — this release is performance and correctness-validation only.

---

## Compatibility

- **Public API**: additive only. No breaking changes.
- **`getVersion()`** now returns `"5.38.0"`.
- Lossy paths (`.constantBitrateStrict`, constrained-RD, 9/7 GPU encode) remain green and are not extended in this release. All focus is on lossless medical archival.

---

## Verification Commands

```bash
swift build
swift test --filter "J2KLosslessMedicalGateTests|J2KMedicalBenchmarkTests|J2KStrictCrossCodecValidationTests"
```
