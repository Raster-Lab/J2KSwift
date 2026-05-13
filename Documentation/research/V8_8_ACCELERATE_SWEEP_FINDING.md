# V8.8 — Accelerate framework sweep against lossless 5/3 + HT entropy: structurally inapplicable

**Status**: WASH (Phase 0 by API surface review + microbench). Accelerate framework is structurally inapplicable to the lossless 5/3 + HT entropy hot path on M2.
**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research; not for merge)
**Bench**: [`Tests/J2KCodecTests/V8_8_AccelerateSweepPhase0Bench.swift`](Tests/J2KCodecTests/V8_8_AccelerateSweepPhase0Bench.swift)

## Goal

User asked for an Accelerate framework sweep — the second-most-promising Apple-specific kernel target after the v8.8 GCD dispatch probe (which closed wash at 0.80 ms wall savings). This document records the systematic API-surface review.

The lossless encode hot path stages (per v8.4 stage breakdown on DX 2800×2288):

| Stage          | Acc CPU ms | Wall ms | Accelerate-eligible? |
|----------------|-----------:|--------:|----------------------|
| Preprocessing  |      9     |    0.73 | YES — DC level shift maps to `vDSP_vsaddi` |
| Color xform    |      0     |       0 | N/A — grayscale corpus |
| DWT (5/3 fwd)  |    333     |   27.10 | NO — needs integer right-shift |
| Quantization   |      0     |       0 | N/A — lossless = no scaling |
| Entropy (HT)   |    272     |   22.10 | NO — bit-buffer packing |
| Rate control   |      0.3   |    0.02 | N/A — small fraction |
| Codestream     |      9     |    0.73 | NO — byte-level marker writes |

Only **preprocessing** has any Accelerate-eligible operation, and it is structurally below the 3 ms threshold even at 100% reduction.

## Probe 1 — DC level shift, scalar vs vDSP_vsaddi

```
DX-sized Int32 buffer (6,406,400 elements, bitDepth=12):
  Scalar loop:          0.546 ms (current production)
  vDSP_vsaddi:          0.543 ms (Accelerate)
  Δ:                   +0.003 ms (+0.6%)
```

**LLVM auto-vec on the scalar `for i in 0..<count { buf[i] &-= dcOffset }` loop produces the same NEON code as `vDSP_vsaddi`.** The microbench confirms this: 0.6% delta is within run-to-run noise.

```
Projection to DX preprocessing:
  v8.4 measured preprocess acc CPU:  9.0 ms
  v8.4 implied preprocess wall:      0.73 ms
  Even 100% Accelerate reduction:    0.73 ms wall savings (best case)

⇒ < 3 ms structural ceiling. Wash even at best case.
```

## Probe 2 — vDSP Int32 API surface vs 5/3 lifting requirements

The 5/3 reversible lifting math (per ISO/IEC 15444-1 Annex F.4):

```
Forward predict:  d[n] = odd[n] - (even[n] + even[n+1]) >> 1
Forward update:   s[n] = even[n] + (d[n-1] + d[n] + 2) >> 2
```

**Required vDSP Int32 primitives, and what's actually shipped in `Accelerate.framework` on macOS 24.6 / Xcode 26.x:**

| Operation                                   | vDSP function     | Status              |
|---------------------------------------------|-------------------|---------------------|
| Int32 vector add of paired elements         | `vDSP_vaddi`      | ✓ EXISTS            |
| Int32 vector subtract                       | `vDSP_vsubi`      | ✗ **DOES NOT EXIST**|
| Int32 vector arithmetic right-shift by k    | (no equivalent)   | ✗ **DOES NOT EXIST**|
| Int32 vector add with scalar                | `vDSP_vsaddi`     | ✓ EXISTS            |
| Int32 vector multiply                       | `vDSP_vmuli`      | ✗ **DOES NOT EXIST**|

**The right-shift step (the *core* of the integer-reversible 5/3 lifting math) has NO Accelerate primitive on Apple Silicon.** vDSP can't express `(a + b) >> 1` or `(a + b + 2) >> 2` without breaking out into manual SIMD intrinsics. Apple's Accelerate framework was designed around float DSP / image / linear-algebra workloads; the integer-with-shift idiom that defines reversible JPEG 2000 lifting is outside its design intent.

The HT entropy path uses bit-buffer packing (UInt32 `<<` / `>>`, MEL/VLC/MagSgn byte emit). Accelerate has **no bit-level primitives at all**. Structurally N/A.

## What Accelerate IS used for in J2KSwift

| Use site                                              | Accelerate calls                                            |
|-------------------------------------------------------|-------------------------------------------------------------|
| `J2KAcceleratedEncoder.swift` — forward 9/7 lifting   | `vDSP_vmul`, `vDSP_vsma`, `vDSP_vsmul`, `vDSP_vadd`         |
| `J2KAcceleratedTrellis.swift` — lossy R-D trellis     | `vDSP_vfillD`, `vDSP_vsubD`, `vDSP_vsqD`, `vDSP_sveD`       |
| `J2KAcceleratedPerceptual.swift` — lossy perceptual   | `vDSP_vsdivD`, `vDSP_vsmulD`, `vDSP_vthresD`, etc.          |

All in **lossy / perceptual** stages, all on **Float / Double**, all **outside** the v5.38+ lossless-only product target (per `feedback_lossless_only_v5_38.md`). The lossless 5/3 path uses scalar Int32 lifting because vDSP can't help.

## Decision: WASH; close v8.8 Accelerate sweep

| Direction                | Acc-eligible? | Best-case wall savings | Decision |
|--------------------------|---------------|------------------------|----------|
| Preprocessing DC shift   | YES           | 0.73 ms                | WASH     |
| Forward 5/3 DWT lifting  | NO (no >>)    | N/A                    | N/A      |
| HT entropy emit          | NO (bit ops)  | N/A                    | N/A      |

This is consistent with the structural finding from v8.6 Phase 0: the forward 5/3 inner lifting runs at 0.37 ns/sample (memory-bound, L1-resident) with LLVM auto-vec already producing tight NEON. There is no Accelerate primitive that does what the lifting needs — the math doesn't decompose into Accelerate's float-oriented primitives.

## Cumulative lever-ceiling state

| Direction  | Investigations                                                                                                         | Outcome  |
|------------|------------------------------------------------------------------------------------------------------------------------|----------|
| Decode     | v6-alpha4, v7.4, v7.5, v8.1, v8.4 (3 probes), v8.5                                                                     | WASH all |
| Encode     | v8.6 forward DWT lifting, v8.6 HT SIMD classifier, v8.7 (3 probes)                                                     | WASH all |
| Dispatch   | v8.8 GCD vs TaskGroup                                                                                                  | WASH     |
| Accelerate | **v8.8 Accelerate sweep (this)**                                                                                       | **WASH** |

**Ten independent investigations** on M2 + Swift release + macOS confirm structural lever ceiling.

## What WOULD justify reopening this

1. **A different stage profile** — if a future J2KSwift release shifts hot-stage cost into a float-arithmetic dominated stage (e.g. lossy R-D trellis re-enabled per the v5.38 lossy-parking decision), Accelerate becomes the natural lever again.
2. **A new Apple compute primitive** — if Apple ships an integer-with-shift `vDSP_vshifti` or AMX-style Int32 lifting primitive in a future SDK, reopen.
3. **A different machine class** — N/A; the API surface gap is in the framework, not the silicon.

## What stays in tree

- `Tests/J2KCodecTests/V8_8_AccelerateSweepPhase0Bench.swift` — DC level shift microbench + API surface probe. Future-investigator reference.
- `V8_8_ACCELERATE_SWEEP_FINDING.md` — this document.
- `V8_8_GCD_DISPATCH_FINDING.md` — companion close-out (also wash).

No production code change. No public API surface change.
