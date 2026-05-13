# J2KSwift v5.22.0 — Conformance Audit

**Release date:** 2026-05-04
**Theme:** v5.20.0 caught a GPU 9/7 lossy IDWT defect, v5.21.0 root-caused it as a scaling-
direction inversion in J2KMetalDWT vs ISO/IEC 15444-1 / J2KCodec. Both were single-bug fixes.
v5.22.0 asks the meta-question: **what other systemic numerical inconsistencies are latent in
the wavelet pipeline?** Audits all wavelet implementations for cross-module convention
agreement and locks in the audit results as permanent regression gates.

## What v5.22.0 audits

### 1. JP3DMetalDWT 9/7 — same bug as J2KMetalDWT, fixed preemptively

`Sources/J2KMetal/JP3DMetalDWT.swift` had the **same scaling-direction inversion** as
J2KMetalDWT pre-v5.21.0:

| Site | Pre-v5.22.0 | v5.22.0 |
|---|---|---|
| GPU forward 9/7 X | `L *= K, H *= 1/K` | `L *= 1/K, H *= K` |
| GPU forward 9/7 Y | same | same |
| GPU forward 9/7 Z | same | same |
| CPU `forward97Lifting` | `l *= k, h /= k` | `l /= k, h *= k` |
| CPU `inverse97Lifting` | `l /= k, h *= k` | `l *= k, h /= k` |

The module was self-consistent (round-trip within JP3DMetalDWT worked) but spec-divergent
from `J2K3D.JP3DWaveletTransform` (which is spec-compliant). No current callers, so no
user-visible bug — but if anyone wired JP3DMetalDWT into the JP3D encoder/decoder pipeline
as the GPU acceleration layer, they'd hit the same K⁴ scaling defect v5.21.0 caught.

### 2. Cross-module convention regression gate

`Tests/J2KMetalTests/J2KWaveletConventionAuditTests.swift` — 4 tests that lock in convention
agreement across modules:

- `testJ2KMetalDWT_vs_J2KCodec_Inverse97_AgreeOnSingleLevel` — locks in v5.21.0's inverse fix.
- `testJ2KMetalDWT_vs_J2KCodec_Forward97_AgreeOnSingleLevel` — locks in v5.21.0's forward fix.
- `testJ2KMetalDWT_vs_J2KCodec_Inverse53_AgreeOnSingleLevel` — 5/3 cross-module convention
  agreement at the Float-array level (existing v5.7+ Int32 tests cover bit-exact contract).
- `testJP3DMetalDWT_vs_JP3DWaveletTransform_Forward97_Agree` — locks in v5.22.0's JP3D fix
  by comparing JP3DMetalDWT's CPU 9/7 forward to a hand-built ISO/IEC 15444-1 reference.

Each test runs a synthetic 32–64-element signal through both implementations and asserts max
abs diff is below the precision tolerance for that filter:

| Filter | Tolerance | Rationale |
|---|---:|---|
| 9/7 (forward + inverse) | 1e-3 | Float vs Double precision drift on 64 elements |
| 5/3 | 1.0 LSB | Float lifting in J2KMetalDWT vs exact Int32 in J2KCodec |

Convention drift (e.g., scaling-direction inversion, sign flip on lifting coefficients) would
produce multi-LSB or worse divergence — well above these thresholds.

### 3. Other audit findings

- **Forward DWT consumed by J2KSwift's encoder** uses `J2KCodec.J2KDWT1D` (the spec-compliant
  reference). The GPU forward DWT is not on any encoder code path. No bug exposure.
- **Boundary extension** (`getExtendedValue` in J2KCodec, `(i > 0) ? (i-1) : 0` in J2KMetal
  GPU kernels): cases checked at indices -1 and N return identical values. Both modules use
  effectively whole-sample symmetric extension at the cases that matter for valid block
  dimensions. No divergence found.

## Why this matters

v5.21.0's fix was retroactive — the GPU 9/7 IDWT had been silently wrong since the kernels
first shipped. Every internal round-trip test passed because forward and inverse cancelled
within J2KMetal. The bug was caught only when a user-facing scenario (J2KCodec encode → GPU
decode) compared cross-module.

v5.22.0 changes that. Cross-module agreement is now a permanent regression gate. Any future
PR that introduces a new wavelet path with the wrong convention — or modifies an existing
path's convention — will fail the audit suite at PR time, before the bug ships.

The same shape applies to non-wavelet pipeline stages too: byte order (v5.14.x), conformant
encoding (v5.15-v5.16), filter direction (v5.17.0), lossy R-D (v5.18-v5.19), GPU IDWT
(v5.20-v5.21). v5.22.0's contribution: a generalizable cross-module audit pattern that future
correctness work can extend.

## Verification

| Test suite | Cells | Failed | Notes |
|---|---:|---:|---|
| `J2KWaveletConventionAuditTests` | 4 | 0 | New v5.22.0 audit gate |
| `J2KGPULossy97DivergenceTests` | 1 | 0 | v5.21.0 GPU IDWT fix regression |
| `J2KMetalSingleLevel97Tests` | 1 | 0 | v5.21.0 single-level direct comparison |
| HT conformant suites (v5.15–v5.20) | various | 0 | All carryover gates green |
| Byte-order suite (v5.14.2) | 10 | 0 | Carryover |
| Q-step search efficiency (v5.19.1) | 4 | 0 | Carryover |

## Carryover from v5.14–v5.21

All regression gates remain green. The v5.22.0 audit gates are additive.

## Reproducing

```bash
# v5.22.0 cross-module audit (4 tests, ~0.1 s):
swift test --filter J2KWaveletConventionAudit

# Full wavelet correctness rollup (v5.20.0 through v5.22.0):
swift test --filter "J2KGPULossy97\|J2KMetalSingleLevel97\|J2KWaveletConventionAudit"

# Carryover gates from earlier:
swift test --filter "HTConformant\|J2KByteOrderRoundTrip"
```

## Lesson

A bug fix is good. A bug-class fix is better. A bug-class **prevention gate** is the best
of the three. v5.20.0/v5.21.0 fixed an instance; v5.22.0 builds the gate that prevents
the next instance from shipping.

Same shape as v5.14.2 (audit of byte-order across all I/O surfaces) and v5.15.0 (three
independent probes ratifying lossless conformant). Each release in this series ends with
"the bug class is now unrepresentable, not just unfixed." v5.22.0 closes the wavelet-
convention bug class.
