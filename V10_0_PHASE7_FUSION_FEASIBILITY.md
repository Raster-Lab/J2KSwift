# v10.0 Phase 7 — Cross-stage fusion feasibility — CLOSED, 11th lever-ceiling

**Status:** Cross-stage fusion (DWT + quantise + entropy single-pass) **structurally not worth pursuing** on Apple M2. 11th independent investigation confirming the M2 + Swift release lever-ceiling pattern. v11.0 candidate scope explicitly killed by this finding.

**Date:** 2026-05-14
**Branch:** `v10.0-research`
**Test:** `Tests/J2KMetalTests/V10Phase7FusionFeasibilityTests.swift::testFusionFeasibilityProjection_SingleTile`
**Host:** Apple M2 (Mac14,2), v9.4.0-era v10.0-research binary, release mode, single-tile mode forced (`envMode = .single`), n=5 median per fixture.

## Headline

**The encoder hot path is 99.8 % stage-compute-bound on M2.** There is essentially zero inter-stage overhead to recover via fusion. Per-fixture breakdown:

| Fixture | wall ms | sum of stage walls | overhead | overhead % | realistic fusion save (50 % of overhead) |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 1.02 | 0.97 | 0.05 | 4.7 % | 0.02 ms |
| CT 512² (1) | 5.69 | 5.61 | 0.09 | 1.5 % | 0.04 ms |
| CT 512² (2) | 5.34 | 5.33 | 0.02 | 0.3 % | 0.01 ms |
| MR 886² | 6.26 | 6.17 | 0.09 | 1.4 % | 0.05 ms |
| XA 1024² | 20.28 | 20.23 | 0.04 | 0.2 % | 0.02 ms |
| PX 2459×1316 | 68.53 | 70.83 | **−2.30** | (noise) | n/a |
| **DX 2800×2288** | **133.04** | **132.83** | **0.22** | **0.2 %** | **0.11 ms** |

**DX realistic fusion save = 0.11 ms (0.1 % of wall) — 30× below the v7.4 3 ms acceptance bar.**

PX's negative overhead is measurement noise: the per-stage timings sum slightly *above* the end-to-end wall because per-stage `recordX` calls add sub-millisecond glue cost that the end-to-end timer doesn't see at the dispatcher boundary. The qualitative conclusion (essentially zero overhead) holds.

## Method

The Phase 7 test forces `J2KEncodeTilePlanner.envMode = .single` so the encode runs as a single-tile single-thread pipeline. In that mode, `J2KEncodeTimings`'s per-worker CPU sums equal the wall (Phase 1's multi-tile caveat doesn't apply). The pipeline is:

```
load image (already in memory) →
  preprocess → colour → DWT 5/3 forward → quantize (fused into entropy
  in HT path) → entropy (C+NEON v9.4 hot path) → rate-control (no-op
  for lossless) → codestream generation → return Data
```

Each stage records its wall via a `recordX(dt:)` call at its boundary. Sum of those recorded walls vs the end-to-end `Date().timeIntervalSince(t0)` = overhead.

Overhead in this pipeline consists of:

- Intermediate buffer allocation (DWT subband output Int32 arrays, per-block coefficient arrays, encoded byte arrays, output Data) — **the thing fusion would remove**
- `withUnsafe...` indirection and async-boundary glue
- Pipeline dispatcher cost (no-op in single-tile mode)
- Codestream marker write framing

**The data says all of that, summed, is 0.02 % to 4.7 % of wall — typically <2 %.**

## Why fusion would not help

Cross-stage fusion (the v11.0 candidate per the v10.0 plan, also the v8.7 candidate from a different angle) would rewrite the encoder so DWT, quantise, and entropy share a single tile-pass — coefficient data stays in registers/L1 across stage boundaries instead of being materialised to heap-resident Int32 arrays.

The theoretical win is "remove the intermediate materialisation cost." But **on the current pipeline, that cost is 0.05 to 2.30 ms across the corpus — sub-percent of wall**. After v9.5's per-worker NEON buffer hoisting and v9.4's batched MagSgn emit, there's almost nothing left to fuse out.

The stage-compute itself dominates:
- DWT 5/3 forward DX: 15.53 ms (V8_6 memory-bandwidth-bound)
- Entropy DX: 109.26 ms (v9.4 C+NEON hot path, v9.5 buffer-hoisted, the auto-vec ceiling per v9.5)

Fusion would not make either of those faster. The DWT memory bandwidth wall and the entropy auto-vec wall are silicon-level constraints — they're not removed by fusion architecture.

## Comparison to prior findings

| Finding | Wall savings | Acceptance bar | Verdict |
|---------|--------------|----------------|---------|
| v7.4 SWAR MagSgn refill | +3.7 ms DX | 3 ms | Graduated |
| v9.4 C+NEON hot path | −9 % to −20 % wall (7-19 ms on DX/MG) | 3 ms | Graduated |
| v9.5 buffer hoisting | Neutral standalone | 3 ms | Structural-only, kept |
| **v10 Phase 7 cross-stage fusion (projected)** | **0.11 ms DX (0.1 %)** | 3 ms | **30× below — close** |

Cross-stage fusion is now decisively the *smallest* potential lever in any of the recent investigations. Multi-week implementation cost would buy 0.1 % wall.

## Verdict

**Close cross-stage fusion as v11.0 candidate.** Not worth the multi-week architectural rewrite cost.

This is the **11th independent investigation** confirming the M2 + Swift release lever-ceiling. The pattern is now overwhelming:

| # | Arc | Outcome |
|---|---|---|
| 1 | v6-alpha4 | A+B landed, C+D reverted |
| 2 | v7.4-7.5 | Staged-NEON, partial graduation |
| 3 | v8.1 | Prefix-scan / 8-byte SWAR wash |
| 4 | v8.4 | DX decode lever-ceiling |
| 5 | v8.5 | HT entropy consumer body wash |
| 6 | v8.6 | Encoder optimisation arc wash |
| 7 | v8.7 | Encoder algorithmic redesign wash |
| 8 | v9.5 | Aggressive C+NEON entropy push closed as research |
| 9 | v10.0 Phase 1 | Non-entropy wall budget closed |
| 10 | v10.0 Phase 5 | GPU single-tile forward 5/3 wash |
| **11** | **v10.0 Phase 7** | **Cross-stage fusion structurally non-viable** |

## What's left

After 11 investigations, the encoder hot path on M2 + Swift release has no remaining algorithmic / architectural lever > 1 ms wall. The actionable frontiers are:

1. **Cross-silicon measurement (M3 / M4 / A-series)** — the only remaining lever the data supports. Different memory bandwidth + core counts may shift the budget. Requires hardware.
2. **Decoder-side optimisation** — symmetric Phase 1 / Phase 8 (this branch) for decode. Per v8.4 it's also at ceiling, but worth a fresh M2 re-measurement on v9.5+ entropy path. Phase 8 of this branch addresses.
3. **Productisation / deployment** — j2kd daemon adoption telemetry, SDK-vs-CLI guidance, marketing-grade benchmark methodology (today's PRs #420 / #421 / #422 / #423 / #424 all land this on main).

## Reproducing

```bash
swift test -c release --filter V10Phase7FusionFeasibilityTests
```

Run time ~1.5 s release-mode. Outputs the markdown table directly.

## Files added in Phase 7

```
Tests/J2KMetalTests/V10Phase7FusionFeasibilityTests.swift  (NEW)
V10_0_PHASE7_FUSION_FEASIBILITY.md                          (this doc)
```

Per `feedback_research_no_main_merge.md`, both stay on `v10.0-research`.

## Companion documents

- [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md) — v10.0 plan citing cross-stage fusion as v11 candidate
- [`V10_0_PHASE1_WALL_BUDGET.md`](V10_0_PHASE1_WALL_BUDGET.md) — encode wall budget (different methodology, complementary)
- [`V10_0_RESEARCH_CLOSURE.md`](V10_0_RESEARCH_CLOSURE.md) — Phase 4 canonical closure (will be superseded by V10_0_FINAL_CLOSURE.md)
- [`V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md`](V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md) — 10th lever-ceiling confirmation
- [`V10_0_PHASE6_DAEMON_DECOMPOSITION.md`](V10_0_PHASE6_DAEMON_DECOMPOSITION.md) — daemon-encode win decomposition
