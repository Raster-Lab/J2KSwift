# v10.16-research — GPU decode underperformance (#440)

**Branch:** `v10.16-research`
**Status:** Phase 0–3 complete — Levers 1 & 2 WASH; #440 confirmed structural on M2
**Date:** 2026-05-21
**Issue:** [#440](https://github.com/Raster-Lab/J2KSwift/issues/440) — `decodeGPU` / `decodeWithGPUHT` underperform CPU `decode()` and Kakadu on mid/large medical images.

## Goal

Root-cause why the GPU decode paths underperform on ≥3 MP medical images
on Apple M2, and probe at least one concrete optimisation lever for the
GPU inverse-DWT pipeline.

## Phase 0 — reproduction

`J2KMedicalCorpusPerformanceTests.testCorpusWarmSessionAcrossDecodeAPIs`
(warm in-process, median of 5, **lossy 2 bpp** constant-bitrate HT):

| Fixture | px | CPU ms | decodeGPU | decodeWithGPUHT | Winner |
|---|---:|---:|---:|---:|---|
| mr_002 180² | 32 K | 1.2 | 1.2 | 5.8 | decodeGPU |
| ct_001 512² | 262 K | 6.6 | 5.9 | 9.0 | decodeGPU |
| ct_003 512² | 262 K | 6.8 | 3.0 | 8.9 | decodeGPU |
| mr_001 886² | 785 K | 20.7 | 8.6 | 12.7 | decodeGPU |
| xa_001 1024² | 1.05 M | 25.3 | 8.0 | 12.9 | decodeGPU |
| px_001 2459×1316 | 3.24 M | 82.2 | 24.4 | 25.8 | decodeGPU |
| dx_002 2800×2288 | 6.4 M | 47.3 | 51.0 | 43.0 | decodeWithGPUHT |
| dx_001 2544×3056 | 7.77 M | 54.9 | 54.6 | 50.1 | decodeWithGPUHT |
| mg_001 3520×4784 | 16.8 M | 137.8 | 137.9 | 109.7 | decodeWithGPUHT |
| mg_002 3521×4784 | 16.8 M | 142.9 | 138.6 | 117.0 | decodeWithGPUHT |

On lossy 2 bpp, decodeWithGPUHT *wins* the large band — the opposite of
#440's report. The discrepancy is the encode mode (#440 measured
lossless); see Phase 1.

## Phase 1 — lossless A/B + stage profile

`V10_16_GPUDecodeFusedIDWTTests.testLever1PerfAB` (warm, median of 7,
**lossless** HT-conformant):

| Fixture | px | CPU `decode()` | decodeGPU | decodeWithGPUHT |
|---|---:|---:|---:|---:|
| mr_002 | 32 K | 0.6 | 0.6 | 9.0 |
| ct_001 | 262 K | 2.7 | 3.0 | 8.4 |
| ct_003 | 262 K | 2.6 | 2.9 | 8.7 |
| mr_001 | 785 K | 5.1 | 5.2 | 22.3 |
| xa_001 | 1.05 M | 7.2 | 7.5 | 33.0 |
| px_001 | 3.24 M | 26.6 | 27.4 | 118.8 |
| dx_002 | 6.4 M | 47.8 | 47.8 | 128.7 |

**Key finding — the lossy/lossless flip.** `decodeWithGPUHT` swings from
*winner* on lossy 2 bpp to **2.7–4.6× slower than CPU** on lossless
(px_001 118.8 ms vs CPU 26.6 ms). GPU HT entropy decode cost scales with
codestream size; lossless medical codestreams are 5–10× larger than
2 bpp, and the GPU MagSgn/MEL kernels collapse on them. This confirms
#440 and validates the v10.0.0 router decision to drop `.decodeWithGPUHT`
from auto-routing.

**`decodeGPU` ≈ CPU on lossless.** Across the whole band the GPU-IDWT
path is a wash against `decode()` (e.g. dx_002 47.8 ≡ 47.8). The CPU
C+NEON inverse DWT (default-on since v10.0.0 D1.5-D) has closed the gap
the GPU IDWT used to win — on lossless, GPU IDWT no longer pulls ahead.

**Stage breakdown** (lossless `decode()`, `DecodeStageProfileLosslessCorpusTests`;
stage times are parallel-summed across the decode task group, so they
over-count wall — read them as relative weight):

| Fixture | total ms | extract | entropy | dequant | iDWT |
|---|---:|---:|---:|---:|---:|
| px_001 3.24 M | 27.0 | 4.4 | 55.8 | 6.1 | 72.7 |
| dx_002 6.4 M | 48.2 | 6.5 | 118.0 | 5.1 | 112.5 |

Entropy and iDWT are **co-dominant** on lossless (≈ 50/50 on DX) — there
is no single wedge to optimise.

## Phase 2 — optimisation levers

### Lever 1 — multi-level-fused IDWT for `decodeGPU`

`decodeGPU` runs the inverse DWT through the **per-level** dispatch
(`J2KMetalDWT.inverse2DInt32` called once per decomposition level; each
call commits its own Metal command buffer and reads the Int32 result
back to a CPU array). A 5-level decode pays 5 commit/await round-trips +
4 inter-level GPU→CPU→GPU transfers.

`inverse2DInt32MultiLevelFused` chains every level inside ONE command
buffer (output of level *k* stays GPU-resident as the LL input of level
*k-1*, single final readback). It already exists — added in the M4P
GPU-HT arc (commit `e0be585`) — but its call site in
`applyInverseWaveletTransformGPU` is gated to `useGPUHT`, so
`decodeGPU` / `decode()` never reach it.

**Lever 1** adds `DecoderPipeline._gpuDecodeFusedIDWTEnabled` (env
`J2K_GPU_DECODE_FUSED_IDWT`, default OFF) to that gate so the CPU-HT
GPU-decode path takes the fused dispatch.

**Parity** — `testLever1Parity`: flag OFF vs ON is **bit-identical**
across all 7 fixtures, and the lossless decode is bit-exact to the
original. The fused path is correct (not bit-rotted).

**A/B** — `testLever1PerfAB`, decodeGPU OFF → ON:

| Fixture | px | decodeGPU OFF | decodeGPU ON | Δ ms |
|---|---:|---:|---:|---:|
| ct_001 | 262 K | 3.0 | 1.9 | −1.1 |
| ct_003 | 262 K | 2.9 | 1.9 | −1.1 |
| mr_001 | 785 K | 5.2 | 5.3 | +0.1 |
| xa_001 | 1.05 M | 7.5 | 7.5 | +0.0 |
| px_001 | 3.24 M | 27.4 | 27.8 | +0.4 |
| dx_002 | 6.4 M | 47.8 | 48.1 | +0.4 |

**Verdict: WASH.** Δ ≤ 0.4 ms on the ≥3 MP target band (≤ 1.3 ms in a
confirming second run) — an order of magnitude under the 3 ms
acceptance gate. The −0.6…−1.3 ms on the 262 K CT fixtures is real but
far below threshold and irrelevant to #440's mid/large target.
Command-buffer round-trips are not the GPU IDWT bottleneck.

### Lever 2 — fused-H+V kernel threshold

The per-level IDWT picks the single-dispatch fused H+V inverse-5/3
kernel (`encodeInverse2DInt32_Fused`) only when a level's output pixel
count is ≥ `inverse53IntFusedPixelThreshold` (12 MP, set by a v10.5
`decodeWithGPUHT` variance bench). No DX/PX decomposition level reaches
12 MP, so they always run the tiled H + tiled V pair. **Lever 2** lowers
the threshold to 3 MP so the ≥3 MP fixtures' largest level uses the
fused kernel — re-tested end-to-end on `decodeGPU`
(`testLever2FusedKernelThreshold`):

| Fixture | px | thr 12 MP | thr 3 MP | Δ ms | parity |
|---|---:|---:|---:|---:|---:|
| mr_001 | 785 K | 5.5 | 5.4 | −0.1 | bit-exact |
| xa_001 | 1.05 M | 7.3 | 7.8 | +0.5 | bit-exact |
| px_001 | 3.24 M | 27.1 | 27.3 | +0.2 | bit-exact |
| dx_002 | 6.4 M | 49.5 | 49.8 | +0.3 | bit-exact |

**Verdict: WASH.** Δ −0.1…+0.5 ms, bit-exact. Confirms the v10.5 12 MP
threshold — the fused H+V kernel is not faster than the tiled pair
below 12 MP.

## Phase 3 — conclusion

**#440's GPU-decode underperformance is structural on Apple M2.**

- The inverse DWT is at CPU/GPU parity on lossless; **two independent
  dispatch-fusion levers wash** — Lever 1 (fusion across decomposition
  levels) and Lever 2 (fused H+V kernel within a level). Both bit-exact.
  This is the **13th independent lever-ceiling confirmation** on M2 +
  Swift release.
- `decodeWithGPUHT` is unusable on lossless (2.7–4.6× slower) — GPU HT
  entropy collapses on large codestreams. The auto-router already
  excludes it; no change needed.
- `recommendedDecodeAPI` (500 K–15 M → `decodeGPU`) is sound: `decodeGPU`
  wins on lossy mid-band and is a harmless wash on lossless. No router
  recalibration recommended.

The only credible remaining lever is an architecture-scale **GPU HT
entropy redesign** (the MagSgn/MEL/VLC kernels), estimated multi-week,
high-risk — out of scope for an isolated research arc. The other open
frontier is **cross-silicon** (M3/M4/A-series): the GPU/CPU crossover
may differ on newer silicon, which is why Lever 1's flag is retained as
opt-in rather than deleted.

## Deliverables

- `DecoderPipeline._gpuDecodeFusedIDWTEnabled` — opt-in flag
  (`J2K_GPU_DECODE_FUSED_IDWT=1`), **default OFF**. Production decode
  behaviour byte-identical to v10.9.3. Retained for M3/M4/A-series
  re-evaluation.
- `Tests/J2KMetalTests/V10_16_GPUDecodeFusedIDWTTests.swift` — parity
  (bit-exact) + Lever 1 warm A/B + Lever 2 fused-threshold A/B.
- This finding doc.

No `main` merge — research-branch deliverable per the research-branch
policy. `#440` stays open as a tracked optimisation target with the
GPU-HT-entropy redesign noted as the credible (multi-week) path.
