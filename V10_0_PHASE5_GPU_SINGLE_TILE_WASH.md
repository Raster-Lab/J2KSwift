# v10.0 Phase 5 — GPU single-tile forward 5/3 DWT vs `.auto` multi-tile CPU: wash

**Status:** Closed. 10th lever-ceiling confirmation on M2 + Swift release.
**Date:** 2026-05-12
**Branch:** `v10.0-research`
**Test:** `Tests/J2KMetalTests/V10Phase5GPUSingleTileABTests.swift::testGPUForwardSingleTileVsAuto_MultiCPU`
**Host:** Apple M2, macOS, release-mode (n=7 median after 2 warmups)

## Headline

Re-running the v6.1.0-era choice (GPU single-tile forward 5/3 DWT) against
the current `.auto` multi-tile CPU default on post-v9.5 main shows the
`.auto` default **definitively wins on every tested fixture**:

| Fixture          | A: `.auto` multi-CPU | B: single + GPU | C: single + CPU | Δ(B - A) |
|------------------|---------------------:|----------------:|----------------:|---------:|
| PX 2459×1316     |              17.41   |          25.54  |          28.18  |  +8.13   |
| **DX 2800×2288** |          **40.46**   |      **45.11**  |      **58.94**  | **+4.65** |

DX Δ +4.65 ms is **above the v7.4 acceptance threshold of 3 ms**, so this is
not within measurement noise — the `.auto` default wins decisively.

## What changed since v6.1.0

The original v6.1.0 default-on decision for GPU forward 5/3 DWT was based on
measurement showing GPU at 6 MP was 23 % faster than CPU at 6 MP (per
v6.3.0 E2 note in `J2KEncoderPipeline._gpuForward53PixelThreshold` doc-
comment: 55.03 ms CPU → 42.33 ms GPU). The CPU number then was for the
single-tile path, before v7.0.0 made `.auto` (multi-tile) the production
default.

Three subsequent perf releases have closed the CPU-vs-GPU gap from below:

| Release | Encoder change                                | DX direction |
|---------|-----------------------------------------------|---------------|
| v7.0.0  | `.auto` (multi-tile 2x2 for ≥3 MP) default    | Parallel CPU across 4 tiles |
| v9.3.0  | Path B counter false-sharing + stack scratch  | -16 % per-block CPU |
| v9.4.0  | Custom C+NEON HT entropy hot path             | -9 % to -20 % warm DX CPU |
| v9.5.0  | Per-worker NEON-buffer hoisting (Phase 5E)    | Structural plumbing |

Together these dropped DX warm-encode CPU wall from ~55 ms (v6.x) to
40.46 ms (post-v9.5). Single-tile GPU dispatch on DX stays at ~45 ms
(unchanged since v6.x — Metal dispatch + readback is the floor on M2).

**The CPU multi-tile path has quietly overtaken single-tile GPU since v6.x.**
On post-v9.5 M2 main, the `.auto` default is the optimal choice for every
default-config workload measured.

## Bit-exact verification (GPU vs CPU forward DWT, single-tile)

The test holds tile mode constant at `.single` and toggles only the GPU
flag (B vs C). Codestream bytes:

| Fixture          | B (GPU) bytes | C (CPU) bytes | parity |
|------------------|--------------:|--------------:|--------|
| PX 2459×1316     |     6,431,507 |     6,431,507 | **IDENTICAL ✓** |
| DX 2800×2288     |    12,683,182 |    12,683,182 | **IDENTICAL ✓** |

The GPU forward 5/3 path produces a codestream bit-identical to the CPU
forward 5/3 path within the same tile mode. The existing
`HTGPUForward53CrossCodecTests` continues to enforce this on every CI run.

## Tile-mode codestream variance (A vs B)

A (multi-tile) and B (single-tile) produce **different** codestream bytes
because the tile-stream structure inherently differs (per-tile SOT/SOD
markers, per-tile resyncs, packet layouts):

| Fixture          | A (.auto multi-tile) | B (.single GPU) | Δ      |
|------------------|---------------------:|----------------:|-------:|
| PX 2459×1316     |            6,453,588 |       6,431,507 | 0.34 % |
| DX 2800×2288     |           12,705,470 |      12,683,182 | 0.18 % |

Both decode bit-exactly to the same pixel image (verified by
`HTTileParityMatrixTests`). The variance is structural, not a correctness
regression.

## Phase 5 decision

**10th independent investigation confirming the M2 + Swift release
lever-ceiling pattern.** The growing investigation list:

1. v6-alpha4 — A+B landed, C+D reverted
2. v7.4-7.5 — staged-NEON closed
3. v8.1 — prefix-scan / 8-byte SWAR wash
4. v8.4 — DX decode lever-ceiling
5. v8.5 — HT entropy consumer body wash
6. v8.6 — encoder optimisation arc wash
7. v8.7 — encoder algorithmic redesign wash
8. v9.5 — aggressive C+NEON entropy push closed as research
9. v10.0 Phase 1 — non-entropy wall budget closed as research
10. **v10.0 Phase 5 — GPU single-tile forward 5/3 vs `.auto` multi-CPU
    closed as wash (this doc)**

The `.auto` default remains optimal for the production lossless HT 5/3
encoder on M2. GPU forward 5/3 DWT stays in the codebase for opt-in /
single-tile-forced workflows; the env-var `J2K_GPU_FORWARD_53=0` opt-out
remains the diagnostic A/B knob.

## What this rules out

This Phase 5 conclusively closes the v10.0 plan's "Out of scope" footnote:

> **GPU forward 9/7 default-on for the encoder**: M2 regression
> unresolved (per `project_path_c_outcome.md`); needs separate research arc.

The above note targets 9/7 (lossy), but the underlying assumption — that
GPU forward DWT might be the unblocking lever — is now disproven for the
5/3 (lossless) path on M2 + post-v9.5 CPU. The 9/7 question stays open;
this Phase 5 does not investigate it.

## Where the real levers actually are (unchanged from Phase 1 closure)

1. **j2kd daemon adoption** — v9.5.0 ships the one-command install.
   Already delivered.
2. **M3+/A-series cross-silicon measurement** — different memory bandwidth
   + core counts may shift the budget. Open frontier. Requires hardware
   I don't have on this host.
3. **Cross-stage fusion (DWT + quantise + entropy single-pass)** — v11.0
   candidate per the original plan. Multi-week scope. Currently the only
   remaining structural lever per all 10 investigations.

## Reproducing

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter V10Phase5GPUSingleTileABTests
```

The test outputs markdown tables (median of 7 after 2 warmups) for direct
copy into this finding doc. Run time ~2 seconds release-mode.

## Files added

- `Tests/J2KMetalTests/V10Phase5GPUSingleTileABTests.swift` — A/B/C test
- `V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md` — this finding doc

Per the `feedback_research_no_main_merge.md` policy, both stay on
`v10.0-research` and are not cherry-picked to `main`.
