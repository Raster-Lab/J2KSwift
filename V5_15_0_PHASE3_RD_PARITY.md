# v5.15.0 Phase 3 — R-D parity finding

**Date:** 2026-05-03
**Scope:** Confirm J2KSwift HT conformant is competitive with OpenJPH at matched achieved bpp.

## TL;DR

**Lossless** HT conformant: parity confirmed across all dimensions (Phase 1+2 = 11,889 cells, all
bit-exact, including OpenJPH cross-decode at non-power-of-2 dims).

**Lossy** HT conformant: **NOT competitive** — J2KSwift-HT is 2.5–6.9 dB *worse* than both J2KSwift's
own legacy EBCOT path AND OpenJPH at matched bpp. This is a substantial encoder rate-control gap that
the v5.15.0 "hardening + default switch" scope was not sized to absorb. Deferred to v5.16.0.

## Lossy R-D matched-bpp matrix (synth corpus, --quick)

| Image | bpp | J2KSwift (EBCOT) | **J2KSwift-HT** | OpenJPEG | OpenJPH | Grok |
|---|---:|---:|---:|---:|---:|---:|
| synth_8b_512 | 0.50 | n/a | **30.46** | 31.24 | n/a | 31.23 |
| synth_8b_512 | 1.00 | 33.22 | **30.73** | 32.97 | 33.60 | 32.96 |
| synth_8b_512 | 2.00 | 38.57 | **31.48** | n/a | 38.26 | n/a |
| synth_12b_512 | 0.50 | n/a | **26.50** | 27.42 | n/a | 27.41 |
| synth_12b_512 | 1.00 | 29.42 | **26.74** | 29.25 | 29.59 | 29.22 |
| synth_12b_512 | 2.00 | 34.30 | **27.40** | n/a | 34.20 | n/a |

PSNR in dB. Bold cells are the v5.15.0 J2KSwift-HT path; values are matched-bpp interpolated from raw
points. Source: `results/rd_benchmark_v5_15_0/rd_summary.md`.

## Pattern

J2KSwift-HT compresses fine — encoder + decoder produce valid HT codestreams that round-trip through
OpenJPH bit-exactly in lossless mode. The issue is **rate-control behavior** in lossy mode:

- 8-bit @1.0 bpp: gap = -2.49 dB vs J2KSwift-EBCOT, -2.87 dB vs OpenJPH.
- 8-bit @2.0 bpp: gap widens to -7.09 dB vs EBCOT, -6.78 dB vs OpenJPH.
- 12-bit @2.0 bpp: -6.90 dB vs EBCOT, -6.80 dB vs OpenJPH.

The fact that the gap *widens* with higher bitrate suggests the issue is not noise floor — it's a
quantization mismatch where adding more bits doesn't recover precision the way a properly-tuned R-D
optimizer would.

## Why this is real engineering work, not a one-line fix

The lossy path's QCD marker writing
([J2KEncoderPipeline.swift:3612-3669](Sources/J2KCodec/J2KEncoderPipeline.swift#L3612-L3669))
uses scalar expounded quantization with stepsizes computed by `J2KStepSizeCalculator` and tunable
parameters from `lossyQuantizationParameters(bitDepth:componentCount:)`. This pipeline was tuned for
the legacy EBCOT block coder. The HT block coder has different significance/refinement-pass semantics
(single cleanup pass instead of three sub-passes) which means:

1. Bin-center alignment differs — EBCOT places coefficients with rounding via a deadzone; HT cleanup
   pass uses bin-center quantization (`(2μ_p + 1) << (p-1)`).
2. Layer truncation in HT codestreams happens at codeblock boundaries (PLT/PLM-driven), with no
   per-pass granularity, so PCRD-opt allocations have to be quantum-coarser.
3. K_max in lossy HT carries different semantics than in EBCOT — `missingMSBs` interacts with the
   stepsize / dynamic-range relationship differently.

OpenJPH ships an HT-specific R-D optimizer (`tile_codestream::flush` + `subband::~subband`) that
J2KSwift's pipeline doesn't currently mirror. Closing the gap means either porting OpenJPH's
HT-specific allocator or building a J2KSwift-native one — multi-day work.

## v5.15.0 disposition

**Ship as planned with these clarifications:**
- Lossless HT conformant: ✅ ratified by Phase 1 (11,868 cells, three independent probes) and
  Phase 2 (21 cells real-corpus). Three regression gates added.
- Lossy HT conformant: ⚠️ documented R-D gap. The encoder produces valid output that decodes
  correctly, but the bitrate/distortion tradeoff is significantly worse than both legacy EBCOT
  and OpenJPH. Do not silently switch lossy users to HT until v5.16.0.

**v5.16.0 motivation captured:**
- Investigate whether legacy EBCOT vs HT has different quantization-step semantics that need
  bit-depth-tuned compensation.
- Compare `J2KStepSizeCalculator` outputs against OpenJPH's `subband::set_qstep` for the same
  inputs at multiple bpp targets — find the divergence.
- Consider porting OpenJPH's HT-specific R-D allocator if the per-coeffer fix doesn't close the
  gap to <0.3 dB.

## Reproducing

```bash
swift build -c release && python3 Scripts/rd_benchmark.py --quick \
  --out-dir results/rd_benchmark_v5_15_0
```

Outputs: `rd_results.csv`, `rd_summary.md`, per-image `.png` plots.
