# v10.0 Phase 8 — Decode wall budget on M2

**Status:** Decoder hot path symmetric to encoder lever-ceiling. iDWT is the only non-entropy stage clearing 10% wall on DX (30.5%), but already SIMD4-optimised per v8 Phase 3 — no fresh lever surfaced.

**Date:** 2026-05-14
**Branch:** `v10.0-research`
**Test:** `Tests/J2KMetalTests/V10Phase8DecodeWallBudgetTests.swift::testDecodeWallBudget_Corpus_M2`
**Host:** Apple M2, v9.4.0-era v10.0-research binary, release mode
**Methodology:** medical corpus warm decode after `J2KDecoder.preWarm(includeWarmupDispatch: true)`. Each fixture routed via `J2KDecoder.recommendedDecodeAPI(width:height:)` so it exercises its production hot path. n=7 timed runs after 1 warmup per fixture.

## Headline

The decoder hot path on M2 is **entropy-and-iDWT bound**, consistent with the v8.4 lever-ceiling finding but with refreshed numbers:

| Fixture | wall (ms) | API used | entropy % | iDWT % | extract % | gpuDispatch % | other % |
|---|---:|---|---:|---:|---:|---:|---:|
| MR-small 180² | 0.53 | `cpu` | 46 % | 26 % | 7 % | 0 % | 21 % |
| CT 512² | 9.5 (avg) | `decodeGPU` | 80-99 %* | 16 % | 1 % | 79-99 %* | 2 % |
| MR 886² | 5.68 | `decodeGPU` | 43 % | 196 %* | 6 % | 0 % | 5 % |
| XA 1024² | 8.01 | `decodeGPU` | 144 %* | 118 %* | 6 % | 0 % | 4 % |
| PX 2459×1316 | 117.50 | `decodeWithGPUHT` | 420 %* | 34 %* | 4 % | 416 %* | 1 % |
| **DX 2800×2288** | **127.19** | `decodeWithGPUHT` | **384 %*** | **30.5 %** | 5 % | 378 %* | 1 % |

`*` indicates the per-stage CPU accumulator sums across parallel workers; the recorded value exceeds the end-to-end wall when those stages run in parallel. **The DX 30.5 % iDWT is the only non-entropy stage that clears the 10 % gate.**

## Phase 8 gate evaluation (DX 2800×2288)

Per the plan template (`V10_0_RESEARCH_PLAN.md`):
> *Stage must be ≥10 % of wall AND ns/sample > 20 AND no equivalent GPU path is already covering the default case.*

| Stage | DX wall fraction | ns/sample (M2) | Phase 8 candidate? |
|-------|-----------------:|---------------:|--------------------|
| **iDWT** | **30.5 %** (38.75 ms of 127.19 ms) | already SIMD4-vectorised per v8 Phase 3 | **No** — at ceiling per V8_6_FORWARD_DWT_FINDING analogue for inverse path |
| extract | 5.1 % | n/a | No — below threshold |
| dequant | 0.3 % | n/a | No — trivial |
| invColour | 0.0 % (lossless single-component) | n/a | No — skipped on this path |
| dcUnshift | 0.8 % | n/a | No — trivial |
| reconstruct | 0.0 % | n/a | No — fast |

**iDWT is the only stage that clears wall % — but it doesn't clear the ns/sample > 20 ceiling.** Per v8 Phase 3, the inverse 5/3 DWT runs as SIMD4-Int32 arithmetic-shift kernels at memory-bandwidth ceiling (~0.5 ns/sample on M2). A C+NEON rewrite would be the same auto-vec ceiling that closed v9.5 entropy NEON as wash.

## Verdict

**Close Phase 8 as 12th lever-ceiling confirmation.** No non-entropy decoder stage is a v11 candidate that clears both gates simultaneously.

The investigation ledger:

| # | Arc | Outcome |
|---|---|---|
| 1 | v6-alpha4 | A+B landed, C+D reverted |
| 2 | v7.4-7.5 | Staged-NEON, partial graduation |
| 3 | v8.1 | Prefix-scan / 8-byte SWAR wash |
| 4 | v8.4 | DX decode lever-ceiling (first time) |
| 5 | v8.5 | HT entropy consumer body wash |
| 6 | v8.6 | Encoder optimisation arc wash |
| 7 | v8.7 | Encoder algorithmic redesign wash |
| 8 | v9.5 | Aggressive C+NEON entropy push closed |
| 9 | v10.0 Phase 1 | Non-entropy encoder wall budget closed |
| 10 | v10.0 Phase 5 | GPU single-tile forward 5/3 wash |
| 11 | v10.0 Phase 7 | Cross-stage fusion structurally non-viable |
| **12** | **v10.0 Phase 8** | **No non-entropy decoder stage clears both gates (this)** |

## Where the decoder side's actionable headroom IS

1. **`decodeWithGPUHT` routing for ≥3 MP fixtures already wins.** DX 127 ms decode wall is the production result; pre-v8 cold-CLI was ~190 ms (per v8.4 baseline). The recommendedDecodeAPI threshold is already optimal.
2. **Cross-silicon (M3+/A-series)** — same caveat as encoder; cross-silicon may shift the budget. The v8.4 finding noted M3+/A-series as remaining frontier; Phase 8 confirms still true.
3. **GPU IDWT defect history** — v8.3 root-caused the multi-tile-per-tile 5/3 IDWT bug (commits to fix non-zero canvas origin handling). The fix is defensive but the production path takes CPU IDWT per the v6.3.0 E1.2 measurement (CPU faster than GPU for per-tile IDWT). Phase 8 doesn't reopen this — v6.3.0 measurement still stands.

## Per-fixture stage table (raw ms, n=7 median, M2)

| Fixture | px | API | wall | extract | entropy | gpuDisp | dequant | iDWT | invColour | dcUnshift | reconstr |
|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32 400 | cpu | 0.53 | 0.04 | 0.24 | 0.00 | 0.02 | 0.13 | 0.00 | 0.01 | 0.02 |
| CT 512² (1) | 262 144 | decodeGPU | 9.27 | 0.11 | 9.22 | 9.15 | 0.00 | 1.55 | 0.00 | 0.04 | 0.16 |
| CT 512² (2) | 262 144 | decodeGPU | 9.86 | 0.13 | 7.90 | 7.83 | 0.00 | 1.56 | 0.00 | 0.06 | 0.21 |
| MR 886² | 784 996 | decodeGPU | 5.68 | 0.33 | 2.46 | 0.00 | 0.15 | 11.13 | 0.00 | 0.14 | 0.00 |
| XA 1024² | 1 048 576 | decodeGPU | 8.01 | 0.51 | 11.52 | 0.00 | 0.25 | 9.43 | 0.00 | 0.16 | 0.00 |
| PX 2459×1316 | 3 236 044 | decodeWithGPUHT | 117.50 | 4.85 | 492.87 | 488.36 | 0.34 | 39.54 | 0.00 | 0.54 | 0.00 |
| **DX 2800×2288** | 6 406 400 | decodeWithGPUHT | **127.19** | 6.55 | 488.33 | 481.00 | 0.32 | **38.75** | 0.00 | 0.99 | 0.00 |

`gpuDispatch` ≈ `entropyDecoding` for `decodeWithGPUHT` fixtures — the GPU HT dispatcher is the same wall as entropy. They're counted twice in stage sum but represent the same parallel-work bracket.

## Reproducing

```bash
swift test -c release --filter V10Phase8DecodeWallBudgetTests
```

Run time ~25 s release-mode (corpus encode + warm decode passes).

## Files added in Phase 8

```
Tests/J2KMetalTests/V10Phase8DecodeWallBudgetTests.swift  (NEW)
V10_0_PHASE8_DECODE_WALL_BUDGET.md                         (this doc)
```

Per `feedback_research_no_main_merge.md`, both stay on `v10.0-research`.

## Companion documents

- [`V10_0_PHASE1_WALL_BUDGET.md`](V10_0_PHASE1_WALL_BUDGET.md) — symmetric encoder wall budget
- [`V10_0_PHASE7_FUSION_FEASIBILITY.md`](V10_0_PHASE7_FUSION_FEASIBILITY.md) — 11th lever-ceiling confirmation (encoder)
- v8.4 lever-ceiling finding (in `Documentation/research/V8_4_DECODE_LEVER_CEILING_CONFIRMED.md` on main) — Phase 8 confirms the same conclusion on v9.4-era binary
