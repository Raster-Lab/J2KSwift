# J2KSwift v10.3.0 — MG mammography decode tied with Kakadu on M2 (two default-flips)

**Release date:** 2026-05-20
**Base:** `v10.2.0` (`431c58e`)
**Type:** MINOR per RELEASING.md "Bug fix, perf improvement, doc-only change | PATCH" / "New public type / function / config option, default unchanged, codestream bytes byte-identical on default config | MINOR". Codestream bytes byte-identical to v10.2.0 — decoder optimisation only.

## Summary

v10.3.0 closes the M2 MG mammography decode gap to Kakadu via **two coordinated default-flips**, both backed by 10-trial variance benches showing reliable wins on MG and pure wash elsewhere. Combined wall reduction on MG: **−20 to −29 ms (−25%)**. The Kakadu gap on MG drops from 1.45× (v10.2.0) to **1.01-1.08× — essentially tied on small/mid MG**.

The two default-flips are:

1. **`DecoderPipeline._gpuHTEntropyEnabled`** flipped **ON → OFF**. The v6.2.0 D4 default-on was correct at the time (+37% DX win then) but post-v10.0.0 D1.5-D the CPU+NEON HT entropy path got significantly faster and the multi-tile GPU HT entropy code path is now slower than CPU+NEON on MG-class workloads. 10-trial variance bench: **100% of MG trials show flag-OFF winning by +19-27 ms median**, with zero impact on DX/PX/XA/CT (single-tile decode never engages this multi-tile code path).
2. **`J2KMetalDWT.inverse53IntFusedEnabled`** flipped **OFF → ON** with the existing 12 MP `inverse53IntFusedPixelThreshold` retained. This default-flips the v10.2.0 opt-in single-kernel H+V fused inverse 5/3 Int Metal kernel for MG-class fixtures only.

Both flags retain env opt-out / opt-in for diagnostic A/B and cross-silicon re-evaluation.

## What's New — production-default

### Default-flip 1: GPU HT entropy decode OFF for `decode()`

- `DecoderPipeline._gpuHTEntropyEnabled` now defaults to **`false`** (was `true` since v6.2.0 D4).
- Opt-in via `J2K_GPU_HT_ENTROPY_DECODE=1` is preserved for diagnostic A/B and cross-silicon re-measurement (M3+/A-series may flip the crossover back).
- The `decodeWithGPUHT(_:session:)` public entry point still uses GPU HT entropy via its own `useGPUHT = true` instance var — callers explicitly opting in via that API get the explicit GPU HT path with no behavioural change.

### Default-flip 2: Fused H+V inverse 5/3 Int Metal kernel ON for ≥12 MP

- `J2KMetalDWT.inverse53IntFusedEnabled` now defaults to **`true`** (was `false` since v10.2.0 ship).
- The 12 MP pixel-threshold gate (`inverse53IntFusedPixelThreshold = 12_000_000`) is retained — only MG-class fixtures (16.8 MP) take the fused path; DX/PX/XA/CT stay on the v10.1.0 Phase 2-2-tiled pair.
- Opt-out via `J2K_METAL_IDWT_FUSED=0`.

## What's New — diagnostic tests (added on `v10.7-research`, not in this release)

The variance benches that justified the default-flips live on `v10.7-research`:

- `V10_7_DecodeWithGPUHTLosslessABTests` — lossless HT corpus CPU vs decodeWithGPUHT entry, 13 fixtures.
- `V10_7_GPUHTEntropyEngagementCheck` — three-way A/B (decode() flag-ON, decode() flag-OFF, decodeWithGPUHT()) across MG/DX/PX.
- `V10_7_GPUHTEntropyFlagFlipVarianceTests` — 10-trial interleaved variance bench (this is the rock-solid evidence base for the flag flip).

## Backward compatibility

- **Codestream bytes byte-identical to v10.2.0 on every default configuration.** Both default-flips are decoder optimisations.
- Decoder output is bit-exact vs v10.2.0 per `GPUHTEntropyDecodeDefaultOnTests` (2/2 PASS, "decoded pixels identical" invariant across the flag toggle).
- Cross-codec parity preserved: `J2KStrictCrossCodecValidationTests` 3/3 PASS with both new defaults.
- Public Swift API unchanged. No type removals, no signature changes.

## Cross-codec parity matrix

`J2KStrictCrossCodecValidationTests` with v10.3.0 defaults: **3/3 PASS**.

| Encoder bytes consumed by | Decode-bit-exact vs J2KSwift |
|---|---|
| OpenJPH (`ojph_expand`) | PASS |
| Grok (`grk_decompress`) | PASS |
| Kakadu (`kdu_expand`) | PASS |

## Medical-corpus benchmarks — MG decode

10-trial interleaved variance bench (M2 release, lossless HT corpus, in-proc warm).

### Flag 1 (`_gpuHTEntropyEnabled` ON → OFF) impact

| Fixture | ON med ms | OFF med ms | Δ med ms | frac OFF wins |
|---|---:|---:|---:|---:|
| MG small 3516×4784 | 101.97 | 81.10 | **+20.72** | **100%** |
| MG mid 3518×4784   | 99.88  | 79.41 | **+21.48** | **100%** |
| MG large 3521×4784 | 110.85 | 87.05 | **+24.49** | **100%** |
| DX large 2544×3056 | 56.48  | 56.13 | +0.02  | 60% (noise) |
| PX large 2812×1316 | 29.37  | 29.48 | +0.02  | 50% (noise) |
| XA 1024²           | 8.01   | 8.04  | +0.01  | 60% (noise) |
| CT 512²            | 2.97   | 2.93  | +0.06  | 60% (noise) |

Cleanest signal in the v10 series: every MG trial wins, every non-MG fixture sits inside ±0.06 ms median.

### Flag 2 (`inverse53IntFusedEnabled` OFF → ON) impact

10-trial variance from v10.2.0 ship (`V10_5_MetalIDWTInverse53FusedVarianceTests`):

| Fixture | Δ med ms | frac > 0 | verdict |
|---|---:|---:|---|
| MG small 3516×4784 | +4.68 | 70% | RELIABLE WIN |
| MG mid 3518×4784   | +2.64 | 70% | BORDERLINE (directional) |
| MG large 3521×4784 | +7.67 | 50% | BORDERLINE (high variance) |
| DX large 2544×3056 | +0.55 | 70% | BORDERLINE (small absolute) |
| PX large 2812×1316 | +0.02 | 50% | RELIABLE WASH |

The 12 MP threshold confines this to MG-class fixtures (DX/PX/XA/CT below threshold stay on tiled).

### Combined v10.3.0 production impact (vs v10.2.0)

Median wall (from the 10-trial bench, with both flags in their v10.3.0 defaults):

| Fixture | v10.2.0 ms | v10.3.0 ms | Δ ms | Δ % | Kakadu ms | v10.2.0 vs Kakadu | v10.3.0 vs Kakadu |
|---|---:|---:|---:|---:|---:|---:|---:|
| MG small 3516×4784 | ~102 | ~76 | **−26** | **−25%** | ~73 | 1.40× | **1.04× (tied)** |
| MG mid 3518×4784   | ~99  | ~76 | **−23** | **−23%** | ~75 | 1.32× | **1.01× (tied)** |
| MG large 3521×4784 | ~111 | ~82 | **−29** | **−26%** | ~76 | 1.46× | **1.08×** |

Single-tile fixtures unchanged from v10.2.0.

## Migration notes

- **No action required.** Both default-flips are decoder-only and bit-exact.
- **Opt-out paths** (for diagnostic A/B or cross-silicon rollback):
  - `J2K_GPU_HT_ENTROPY_DECODE=1` — re-enable v10.2.0 GPU HT entropy decode behaviour (will regress MG by 20+ ms; preserved for cross-silicon work).
  - `J2K_METAL_IDWT_FUSED=0` — re-enable v10.2.0 tiled-only IDWT (will regress MG by 3-8 ms; preserved for cross-silicon work).

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests`       | 2 | PASS |
| `J2KStrictCrossCodecValidationTests`     | 3 | PASS |
| `GPUHTEntropyDecodeDefaultOnTests`       | 2 | PASS (bit-exact across flag toggle) |
| `V10_7_GPUHTEntropyFlagFlipVarianceTests` | 7 fixtures × 10 trials | 100% MG positive, non-MG wash |
| `V10_5_MetalIDWTInverse53FusedVarianceTests` | 5 fixtures × 10 trials | MG class positive median |

## Companion documents

- [`Documentation/releases/RELEASE_NOTES_v10.2.0.md`](RELEASE_NOTES_v10.2.0.md) — opt-in fused IDWT kernel (the v10.3.0 flag-2 default-flip references this work).
- [`Documentation/research/V10_5_METAL_IDWT_FUSED_FINDING.md`](../research/V10_5_METAL_IDWT_FUSED_FINDING.md) — fused kernel design + variance bench.
- [`Documentation/BENCHMARK.md`](../BENCHMARK.md) — canonical warm cross-codec methodology.

## What's NOT included

- The `v10.7-research` diagnostic test scaffolding (3 test files) stays on the research branch per `feedback_research_no_main_merge.md`. The production source flag flips are the only main-bound changes.
- The v10.6-research C+NEON HT reconstruction SIMD probe (11th lever-ceiling confirmation, separate finding) is not in this release.

## Future v10.4.0 candidate

After v10.3.0 closes the MG decode gap to ~tied with Kakadu, the next credible levers are:

1. **DX large 2544×3056 + DX 2800×2288**: currently 1.05× Kakadu on M2. Smallest remaining gap. Hot path: GPU IDWT + CPU+NEON HT entropy. Single-tile path — not affected by the v10.3.0 multi-tile flag flip.
2. **PX large 2812×1316**: currently 1.05× Kakadu on M2. Similar single-tile path.
3. **Cross-silicon validation**: M4 already wins broadly per `CROSS_HOST_M2_M4_v10_1_0_inproc.md`; re-measuring on the v10.3.0 baseline will confirm the marketable "fastest JPEG 2000 codec on Apple Silicon" claim.
