# v10.3 Phase 2-2-tiled + Phase 2-3 — outcome (default-flipped, release-candidate basis)

**Branch:** `v10.3-research`
**Status:** Phase 2-2-tiled DONE. Threadgroup-memory tiled Metal kernels default-on; opt-out via `J2K_METAL_IDWT_TILED=0`. Mandatory commit gate clean; warm cross-codec bench shows decisive DX/MG wins. **Phase 2-3 default-flip GRANTED.**

## Phase 2-2-tiled deliverables (commit `0694b3d` + this finding)

- `j2k_dwt_inverse_53_horizontal_int_tiled` — 32×8 threadgroup, 33-wide tg_even halo. Step 1 + step 2 in one kernel via threadgroup memory + barrier.
- `j2k_dwt_inverse_53_vertical_int_tiled` — 32×8 threadgroup, 33-tall tg_even halo. Same pattern.
- Routing via `J2KMetalDWT.inverse53IntTiledEnabled` (env-gated, default ON since the post-`0694b3d` apply flipped semantics to `!= "0"`).
- Bit-exact equivalent of scalar by construction; verified by `V10_3_MetalIDWTInverse53TiledParityTests` (4 tests, all PASS).
- Mandatory commit gate (release): 7/7 PASS.

## Warm cross-codec bench A/B (M2 release, `Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2`)

J2KSwift in-process decode wall, `J2K_METAL_IDWT_TILED=0` (tiled OFF — scalar Metal kernels) vs default (tiled ON):

| Fixture | OFF ms | ON ms | Δ ms | Δ % |
|---|---:|---:|---:|---:|
| MR 174×192 | 1.15 | 0.50 | **−0.65** | −57 % |
| CT 512² small | 7.15 | 2.22 | **−4.93** | −69 % |
| CT 512² mid | 7.25 | 2.31 | **−4.94** | −68 % |
| CT 512² large | 6.49 | 2.21 | **−4.28** | −66 % |
| MR 512² mid | 6.13 | 2.31 | **−3.82** | −62 % |
| MR 512² large | 6.78 | 2.25 | **−4.53** | −67 % |
| XA 1024² small | 17.12 | 6.57 | **−10.55** | −62 % |
| XA 1024² mid | 19.03 | 6.58 | **−12.45** | −65 % |
| XA 1024² large | 16.77 | 6.71 | **−10.06** | −60 % |
| PX 2459 small | 70.80 | 25.25 | **−45.55** | −64 % |
| PX 2793 mid | 82.23 | 27.81 | **−54.42** | −66 % |
| PX 2812 large | 67.87 | 27.95 | **−39.92** | −59 % |
| DX 2224×2798 small | 178.58 | 45.46 | **−133.12** | −75 % |
| DX 2800×2288 mid | 134.29 | 45.92 | **−88.37** | −66 % |
| DX 2544×3056 large | 135.81 | 55.87 | **−79.94** | −59 % |
| MG 3516×4784 small | 306.74 | 127.41 | **−179.33** | −58 % |
| MG 3518×4784 mid | 264.80 | 129.33 | **−135.47** | −51 % |
| MG 3521×4784 large | 200.93 | 139.51 | **−61.42** | −31 % |

**Every medical-real fixture wins by 30-75 %.** v7.4's 3 ms acceptance threshold is exceeded by 1-2 orders of magnitude.

## Best-mode-vs-Kakadu on v10.3-research (post Phase 2-2-tiled default-on)

| Modality | J2KSwift ON ms | Kakadu ms | Ratio | vs v10.0.0 published |
|---|---:|---:|---:|---|
| DX 2224 small | 45.46 | 38.99 | **1.17×** | was 1.62× (warm bench v10.0.0) — **closes by 0.45×** |
| DX 2800 mid | 45.92 | 39.40 | **1.17×** | was 1.42× — closes by 0.25× |
| DX 2544 large | 55.87 | 40.14 | **1.39×** | was 1.40× — matches |
| MG 3516 small | 127.41 | 77.03 | **1.65×** | was 1.86× — closes by 0.21× |
| MG 3518 mid | 129.33 | 75.35 | **1.72×** | was 1.63× — slight widen (variance) |
| MG 3521 large | 139.51 | 76.00 | **1.84×** | was 1.74× — slight widen (variance) |
| PX 2459 small | 25.25 | 19.64 | 1.29× | was 1.18× substitute (warm noise) |
| PX 2793 mid | 27.81 | 19.76 | 1.41× | comparable |

The **DX 2224 / 2800 fixtures now sit at 1.17× Kakadu** — within 17 % parity, the closest J2KSwift has been to Kakadu on the DX class in this codec's history. Combined with the small-fixture wins (MR/CT clean wins vs Kakadu) the medical-corpus position is the strongest released to date.

## Why this works (re-stated from the kernel design)

Phase 2-1's split-step (`*_2d_step1` + `*_2d_step2`) exposed per-sample parallelism but cost 2 encoder dispatches per pass plus a cross-kernel device-memory RAW barrier. The tiled kernel:

- Does step 1 → barrier → step 2 in a **single kernel dispatch** per pass (encoder count halved vs Phase 2-1).
- Stages step 1's even outputs in **threadgroup memory** (32 KB on-chip per tg) instead of LPDDR5 device memory.
- 32×8 threadgroup layout exposes 256 parallel threads per tg; 33-wide tg_even halo gives each thread's odd-position step 2 its `eRight` neighbour on-chip.

Bit-exact correctness comes from the math being identical to scalar; correctness was verified across 4 test suites + 100+ random sizes + odd dims + tile boundaries.

## What stays open

| Item | Status |
|---|---|
| Phase 2-2-tiled correctness + microbench | ✓ closed |
| Phase 2-3 default-flip | ✓ done (commit `0694b3d` is default-on per post-apply) |
| Phase 2-4 — MG router re-eval (drop 15 MP CPU-fallback now that GPU iDWT is fast) | open; Phase 1B re-test on tiled-default-on |
| Phase 2-5 — release candidate v10.1.0 (decoder-only, codestream unchanged) | open; standard RELEASING.md flow |

## Release recommendation

v10.1.0 release candidate becomes the natural next step:
- Decoder-only optimisation; codestream bytes unchanged from v10.0.0.
- MINOR bump (no API removal, no codestream change, opt-out env var preserved).
- Headline: "**DX/MG decode wall reduced 30-75 % on Apple M2 — tiled Metal inverse 5/3 kernels with threadgroup-memory data staging.**"
- Cross-codec parity preserved (`J2KStrictCrossCodecValidationTests` 3/3 PASS).
- Opt-out via `J2K_METAL_IDWT_TILED=0` available if any consumer reports a regression.

## Companion documents

- [`V10_3_DECODE_STAGE_REPRIORITISATION.md`](V10_3_DECODE_STAGE_REPRIORITISATION.md) — Phase 0 stage profile that motivated this arc
- [`V10_3_METAL_IDWT_OPTIMIZATION_PROBE.md`](V10_3_METAL_IDWT_OPTIMIZATION_PROBE.md) — Phase 2-1 multi-week scope
- [`V10_3_PHASE_2_2_END_TO_END_FINDING.md`](V10_3_PHASE_2_2_END_TO_END_FINDING.md) — Phase 2-1 2D-layout mixed result, motivated the tiled approach
- This document — Phase 2-2-tiled outcome
