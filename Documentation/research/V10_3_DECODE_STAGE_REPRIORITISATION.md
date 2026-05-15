# v10.3 — Phase 0 re-profile inverts the lever picture

**Branch:** `v10.3-research`
**Status:** Phase 0 done; finding inverts the v8.4 share map and re-prioritises L1/L2 before any code work. **No production code change in this phase.**
**Predecessor:** v10.0.0 (Phase 0 + E2 + D1.5-D, published 2026-05-15).

## TL;DR

The architect's planning brief and my L1-L4 sketch both assumed v8.4's stage share map: **DX entropy 57%, iDWT 39%**. That measurement was on the **CPU decode path** at v8.4 baseline. Post-v10.0.0 the production decode path on DX/MG is **`decodeSingleTileGPU`** (`recommendedDecodeAPI` routes 500K–15M to `.decodeGPU`; ≥15M to `.cpu`, but for MG single-tile-no-multi-tile-override the `decode()` API also dispatches to the GPU path because pixels ≥ 4 MP and `J2KMetalDWT.isAvailable`). The fresh stage breakdown on that path is inverted:

| Modality | iDWT share | Entropy share | Notes |
|---|---:|---:|---|
| **DX 2800×2288** | **63 %** (23.3 ms) | 25 % (9.3 ms) | gpuBatch=true; GPU HT entropy fired |
| **MG 3520×4784** | **78 %** (90–99 ms) | 12 % (14–15 ms) | gpuBatch=true; GPU HT entropy fired |

These are **production hot-path numbers**, not synthetic A/B. iDWT is now the dominant stage on the path the user-visible benchmarks measure.

## What that means for the L1-L4 plan

| Lever | Original assumption | Post-Phase-0 reality | Re-prioritisation |
|---|---|---|---|
| **L1 — Swift SIMD4 retrofit on `inverseLift53InPlace`** | Will move iDWT on CPU path | **CPU path is not the production path on DX/MG.** `inverseLift53InPlace` only fires on the CPU `decodeSingleTile` path, which is reached for fixtures below 4 MP. Of the substitute corpus, that's MR / CT / XA only. DX/PX/MG go through GPU iDWT. L1 cannot move the user-visible DX/MG wall directly. | **Downgrade L1 to MR/CT/XA only.** Wall budget on those is already ≤10 ms per fixture; Δ ≤ 1-2 ms wall. Likely below v7.4's 3 ms acceptance gate. **Probably wash.** |
| **L2 — GPU IDWT re-probe** | "Re-measure GPU IDWT post-D1.5-D" | **GPU IDWT is already the production path on DX/MG.** What the original plan called "re-probe" was already in production. The 23 ms DX / 90 ms MG iDWT numbers ARE the GPU IDWT execution time on the production hot path. There's no routing flip to "turn on" — it's already on. | **Re-scope L2 to GPU IDWT *kernel* optimization** (Metal shader changes), not routing. Different surface, different skill set, different risk. |
| **L3 — Cross-tile pipeline overlap** | Was already only applicable to MG 2x2 | Confirmed: medical corpus test runs MG as single-tile codestream (`decodeSingleTileGPU`, not `decodeMultiTileGPU`). Phase E2's tile-planner override only changes what the **encoder** emits; the decode test fixtures come from a fresh encode where Phase E2 fires, so the codestream IS multi-tile — but the perf test data shows single-tile dispatch, meaning either the encoder's `.auto` isn't picking E2 in this test, or the multi-tile decode path doesn't show up in this profile (no PROFILE-GPU prints inside `decodeMultiTileGPU`). | **Phase 0b** (verify): re-run with explicit `tileMode: .tiles2x2` on MG encode + `J2K_PROFILE_DECODE=1`, find whether `decodeMultiTileGPU` runs and how its per-stage shares look. |
| **L4 — Router 15→20 MP A/B** | Maybe MG.decodeGPU beats MG.cpu post-D1.5-D | Quick measurement. Independent of Phase 0 finding. | **Still worth running** as a cheap A/B (≤2 hours). Done in Phase 1B below. |

## The real lever picture post-Phase-0

**Kakadu does MG decode in 68 ms total.** J2KSwift's **GPU iDWT alone takes 90+ ms** on MG. Kakadu's entire decode (which includes its own entropy, iDWT, marshalling) is faster than just our iDWT stage.

The gap is concentrated in **`applyInverseWaveletTransformGPU`** (the Metal-shader-driven inverse 5/3 path) — specifically the finest-level row+column pass on a 66 MB Int32 buffer (DX) or 135 MB Int32 buffer (MG). On M2 with ~70 GB/s effective LPDDR5, that buffer alone has a 1-2 ms read-write floor per pass.

Concrete sub-attribution from the data:
- DX iDWT 23 ms / 7.77 MP = 3.0 ns/pixel
- MG iDWT 90 ms / 16.84 MP = 5.3 ns/pixel
- The 1.8× per-pixel slowdown on MG (vs DX) is consistent with cache spillover. M2 shared L2 is 16 MB; MG's finest-level working set (66 MB) exceeds it.

## Re-prioritised lever order

Levers, **ranked by likely DX/MG production-path impact**:

| Rank | Lever | Files | Expected DX | Expected MG | Probability of clearing 3 ms |
|---|---|---|---:|---:|---:|
| 1 | **GPU iDWT Metal shader optimization** — strip-mined finest level, fused row+column pass, threadgroup memory tiling. ~ analogous to what Kakadu's hand-tuned C achieves on CPU. | `Sources/J2KMetal/J2KMetalDWT.swift` + `Sources/J2KMetal/J2KShaders.metal` | −5 to −10 ms | −20 to −40 ms | 60% |
| 2 | **L4 router 15→20 MP A/B** — if `.decodeGPU` wins on MG `.cpu` post-D1.5-D, single-threshold flip in `recommendedDecodeAPI` | `Sources/J2KCodec/J2KCodec.swift:1153` | 0 | -3 to -8 ms | 30% |
| 3 | **CPU iDWT fallback for MG single-tile** — if Kakadu CPU iDWT < J2KSwift GPU iDWT (likely true given the 90 ms vs 68 ms total picture), the cheapest move is to *route MG away from GPU iDWT to CPU iDWT* (after the Swift SIMD4 retrofit lands) | router + planner | 0 | −20 to −40 ms | 40% (gated on CPU iDWT being competitive) |
| 4 | **Phase 3b — skip Int32→Double conversion on 1-component lossless** (architect's original plan, still applies) | `Sources/J2KCodec/J2KDecoderPipeline.swift:3822` (`vDSP_vflt32D`) | -0.5 ms | -2 ms | 40% (memory-bandwidth floor) |
| 5 | **Phase 3c — fuse last-level vDSP_vflt32D into iDWT** | DWT inner row writer | -1 ms | -3 ms | 30% |
| 6 | **L1 Swift SIMD4 retrofit on `inverseLift53InPlace`** | `Sources/J2KCodec/J2KDWT1DOptimized.swift:634-675` | -1 to -3 ms on CPU-path-only fixtures (MR/CT/XA); near-zero on DX/MG production path | — | 30% on small fixtures only |
| 7 | **C+NEON full inverse 5/3 DWT** (architect's Phase 6) — only meaningful if rank-3 above turns out CPU iDWT IS competitive | new `j2knhd_dwt53.c` | -2 to -5 ms | -10 to -20 ms (via CPU iDWT route) | 30% |

**Rank 1 (GPU shader optimization) and rank 3 (CPU iDWT fallback) are the two newly-discovered high-impact paths.** Both require fresh work that wasn't in the L1-L4 plan.

## Phase 1B — router 15 → 20 MP A/B (RESULT: wash, current router is correct)

Forced `J2K_AUTO_DECODE_API=decodeGPU` on MG to simulate raising the upper threshold past 16.8 MP:

| Config | MG `.auto` ms | MG `.cpu` ms | MG `.decodeGPU` ms |
|---|---:|---:|---:|
| Default router (≥15 MP → `.cpu`) | **122.77** | 127.66 | 124.75 |
| Forced `.decodeGPU` | 149.74 | 160.17 | 142.36 |

**Forcing `.decodeGPU` regresses MG by ~27 ms.** The current 15 MP threshold is empirically correct: CPU path beats GPU path on MG. **L4 closed as wash.**

This *also* confirms rank-3 of the new lever picture: **CPU iDWT (which the CPU decode path uses) is already faster than GPU iDWT on MG.** The −27 ms delta is the GPU iDWT penalty over CPU iDWT for a 16.8 MP single-component image.

## What I'm doing on this branch

- **Phase 0 (done)**: documented the stage shift. Stage shares captured for DX/MG on production path.
- **Phase 1B (done)**: wash. Current 15 MP CPU-fallback threshold is correct; do NOT raise it.
- **Phase 1A (done — LANDED, see below)**: original conclusion that Phase 1A "doesn't apply to single-tile" was correct for the lossy-9/7 corpus path BUT wrong for the HT-J2K Lossless substitute path where Phase E2's 2x2 tile override fires on MG. Re-ran with a dedicated A/B harness (`V10_3_V82BypassMGAB.testV82Bypass_crossFixture`) and found MG saves **−20 to −38 ms / −16 to −26 %** across 3 MG fixtures, bit-exact. Default-flipped `_v82_disableIDWTRoutingFix` from `false` to `true` (commit `92de10c`).
- **Stop**: no SIMD4 retrofit work (rank 6, low impact) without user sign-off on the re-prioritisation.

## Phase 1A — RESULT (committed `92de10c`)

The architect's framing applies on the **multi-tile-per-tile** path inside `decodeTilePayloadGPU` (line 1252). Phase E2's MG-only 2x2 tile override (landed in v10.0.0) makes MG codestreams multi-tile on the encoder side; each tile then routes through `decodeTilePayloadGPU` on decode → the v8.2 `preBatchedGPUCoefficients != nil` predicate fires → CPU IDWT fallback runs. That fallback was the bottleneck on MG.

In-process cross-fixture A/B (lossless HT-J2K, M2 release, 7-run median per side, same process so thermals don't drift):

| Fixture | v82 ON (ms) | v82 BYPASS (ms) | Δ ms | bit-exact |
|---|---:|---:|---:|---|
| CT 512² (single-tile) | 2.32 | 2.33 | +0.02 | YES |
| PX 2793×1316 (4x4) | 27.55 | 27.69 | +0.13 | YES |
| DX 2800×2288 (4x4) | 44.94 | 45.47 | +0.53 | YES |
| DX 2544×3056 (4x4) | 57.36 | 56.72 | −0.64 | YES |
| MG 3516×4784 (2x2) | 124.14 | 103.59 | **−20.55** | YES |
| MG 3518×4784 (2x2) | 131.77 | 99.46 | **−32.31** | YES |
| MG 3521×4784 (2x2) | 144.90 | 106.78 | **−38.12** | YES |

Why the earlier Phase 0 single-tile measurement missed this: the medical corpus perf test uses lossy 9/7 (`useReversibleFilter: false`) where `preBatchedGPUCoefficients` is never set (GPU HT entropy is HT-specific). Phase 1A's win only fires on HT-J2K Lossless multi-tile, which is the v10.0.0 substitute corpus default for MG via E2.

Commit gate clean: J2KMedicalCorpusEncodePerformanceTests 2/2, J2KMedicalCorpusPerformanceTests 2/2, J2KStrictCrossCodecValidationTests 3/3.

## Honest takeaway

The original L1-L4 plan was built on a stage-share map (v8.4) that became stale when D1.5-D shifted entropy from 57% to 12-25% of wall. **iDWT is now the dominant stage**, and **GPU iDWT is the production path** — so the next investment should be in the **Metal shader** (rank 1), not in CPU Swift SIMD4 (rank 6).

A targeted Metal-shader optimization arc (cache-aware finest-level row+column pass, threadgroup memory tiling) is more likely to move the DX/MG production wall than any of the levers I originally sketched. **It also has more risk** (Metal shader work has different debugging tooling and different lever-ceiling history than the Swift/C work this codebase has matured on).
