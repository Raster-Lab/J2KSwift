# v10.17-research — GPU HT entropy decode redesign (#440)

**Branch:** `v10.17-research`
**Status:** CLOSED — host-side levers fail (Phase 0–2); the Phase 3
warp-cooperative redesign is **structurally blocked** (implementation
investigation). #440 re-classified as algorithm-level structural.
**Date:** 2026-05-22
**Issue:** [#440](https://github.com/Raster-Lab/J2KSwift/issues/440)

## Goal

v10.16-research closed #440's IDWT levers as wash and named the **GPU
HT entropy decode** the only remaining credible lever. This arc
investigates it: root-cause the bottleneck, probe the cheap host-side
levers, and design the real redesign.

## Phase 0 — the bottleneck

The GPU HT cleanup-pass decoder (`j2k_ht_cleanup_decode` in
`J2KShaders.metal:3347`, dispatched by `J2KMetalHTCleanup.run*`) runs
**one GPU thread per code-block**. Each thread serially walks three
variable-length bitstreams — MEL (run-length), VLC (table-driven quad
classification, read in reverse), MagSgn (per-sample magnitude/sign) —
quad by quad, row-pair by row-pair, for the whole block (up to 64×64 =
4096 samples).

The warp-packing bug is already fixed — `J2KMetalHTCleanup` dispatches
`threadsPerThreadgroup = min(blockCount, 64)` (the old `(1,1,1)` group
that idled 31 lanes/warp was fixed in the Phase-3 arc). What remains:

- **No intra-block parallelism.** One thread = one block's entire
  serial parse. A 64×64 block is 4096 samples decoded sequentially in
  a single thread.
- **GPU threads are poor at serial branchy bitstream parsing** — no
  out-of-order execution, weak branch prediction vs a CPU core.
- Prior end-to-end data (`GPU_HT_M2_PRIME_PERF_REPORT.md`): GPU HT is
  **0.06–0.48× CPU HT** across the corpus; the v10.16 lossless A/B
  measured `decodeWithGPUHT` at **2.7–4.6× slower** than CPU.

The HT cleanup pass is structurally serial *within* a block (MEL
run-lengths, variable-length VLC codewords, and MagSgn bit-widths each
depend on prior decode state) but fully independent *across* blocks.

## Phase 1–2 — host-side levers (both REGRESS)

Hypothesis: one-thread-per-block makes a 32-lane SIMD warp finish only
when its slowest lane does, so warps holding a mix of low/high-entropy
blocks waste lanes. Reorder code-blocks by cost so each warp holds
similar-cost blocks.

`J2KMetalHTCleanup.divergenceSortEnabled` (env `J2K_GPU_HT_SORT`,
**default OFF**) gates the reorder; `V10_17_GPUHTSortTests` is the
parity + warm A/B (median of 7, lossless HT, `decodeWithGPUHT`).

**Lever A — descriptor-only sort.** Reorder descriptors by descending
`magsgnLength + melVlcLength`. Δ end-to-end wall:

| Fixture | px | Δ wall ms |
|---|---:|---:|
| mr_001 | 785 K | +0.5 |
| xa_001 | 1.05 M | +1.3 |
| px_001 | 3.24 M | **+8.9** |
| dx_002 | 6.4 M | **+6.3** |

**Regresses.** Root cause: descriptor order ≡ codestream-pool layout;
reordering descriptors scatters each warp's pool reads across the
codestream and thrashes the cache.

**Lever A-prime — sort + codestream-pool repack.** Repack the pool
into the sorted order too (rewriting per-block offsets) to keep each
warp's reads contiguous. Bit-exact parity holds. Δ end-to-end wall:

| Fixture | px | Δ wall ms |
|---|---:|---:|
| mr_001 | 785 K | +0.9 |
| xa_001 | 1.05 M | −0.2 |
| px_001 | 3.24 M | **+10.4** |
| dx_002 | 6.4 M | **+6.8** |

**Still regresses** — locality was not the (whole) story.

**Why cost-sorting regresses.** The wall is bounded by *threadgroup*
scheduling across GPU cores, not by intra-warp lane divergence.
Original raster/subband order gives every threadgroup a *mixed* set of
block costs, so all threadgroups carry ≈ the average load and finish
together — good core utilisation. Cost-sorting **clusters all the
expensive blocks into the first threadgroups**: those become a long
critical-path pole while the cheap-block threadgroups finish early and
leave cores idle. The intra-warp divergence saved is smaller than the
inter-threadgroup imbalance introduced. **Random order is already
near-optimal for threadgroup balance** — host-side reordering cannot
help.

Both levers are **bit-exact** (parity test 6/6). The lever is retained
opt-in (`J2K_GPU_HT_SORT`, default OFF — production unaffected) only
for M3/M4/A-series re-evaluation, where the scheduler may behave
differently.

## Phase 3 — the redesign (multi-week implementation arc)

Host-side reordering cannot fix #440 — the fix must change the GPU
decode *granularity*. The structural problem is one-thread-per-block;
the redesign makes a **32-lane SIMD warp cooperate on one code-block**.

### Warp-cooperative per-block HT cleanup decode

Dispatch: one `simdgroup` (32 lanes) per code-block instead of one
thread. Threadgroup memory holds the per-quad working set.

The HT cleanup pass decodes row-pair by row-pair. For each row-pair:

1. **Serial sub-step (lane 0).** Decode this row-pair's MEL + VLC
   streams — short relative to MagSgn — producing per quad: `rho`
   (4-bit significance), `Uq` (magnitude exponent). MEL run-length
   state carries across row-pairs, owned by lane 0. Lane 0 also
   computes each quad's MagSgn **bit-length** from `(rho, Uq,
   exponent)` — the exponent context for row 0 is intra-quad, for
   later rows it is the previous row-pair's recovered `eVal` already
   in threadgroup memory — then a **prefix-sum** of bit-lengths gives
   every quad's MagSgn **bit-offset**.
2. **Barrier** (`threadgroup_barrier(mem_threadgroup)`).
3. **Parallel sub-step (all 32 lanes).** Each lane takes one quad,
   seeks its known MagSgn bit-offset, reads its 4 samples'
   magnitude/sign, writes 4 outputs. Fully parallel — up to 32 quads
   (a 64-wide row-pair) decoded at once.
4. **Barrier**; recover `eVal`/`cxVal` for the next row-pair.

This collapses the serial critical path from **O(W·H)** (every sample
read sequentially) to **O((H/2)·(W/4))** for the VLC/MEL decode, with
the heavy MagSgn extraction now **O((H/2)·(W/4)/32)** parallel.

### Why this is a multi-week, high-risk arc

- **MagSgn bit-offset prefix-sum** is the crux — it must compute
  per-sample bit-widths without reading MagSgn. Feasible (widths are
  determined by VLC/UVLC + exponent context), but intricate.
- **Threadgroup-memory layout + barriers** — per-quad `rho/Uq/eVal/
  cxVal/bitOffset`, double-buffered across row-pairs.
- **Correctness is a minefield.** The v7.2.0 batched GPU HT decode
  (PR #356) shipped *silently corrupt* for three releases before
  v7.5.1 caught it. The redesign must run the bit-exact parity gate
  (`V10_2_DecodeBlockParityTests` + a new warp-cooperative parity
  suite) continuously, on every block geometry and `missingMSBs`.
- **Occupancy** — 32 lanes/block raises threadgroup-memory pressure;
  needs tuning so enough warps stay resident.

### Implementation finding — the redesign is structurally blocked

The implementation began by reading the actual cleanup-pass kernel
(`htDecodeInitialRow` / `htDecodeSubsequentRow` and helpers in
`J2KShaders.metal`). The warp-cooperative design above assumes a row
decodes as *VLC-serial → MagSgn-parallel*. The MagSgn half does **not**
parallelise on subsequent rows:

- `htReadQuadSamples` reads `m = Uq − eBit` bits per significant sample
  — per-sample widths are known once `Uq` is known. ✓
- **But `Uq` is not known from the VLC pass alone.**
  `htDecodeSubsequentRow` computes `Uq = u + kappa`, with
  `kappa = popcount(rho) ≥ 2 ? max(1, maxE) : 1`. `maxE` is recomputed
  *every quad-pair* from `eVal`, which `htRecoverEQ` fills from the
  **decoded MagSgn coefficients of the previous quad in the same row**.

So for every quad with ≥ 2 significant samples, `Uq` — hence the MagSgn
bit-offset of the next quad — depends on the previous quad's fully
decoded magnitudes. Subsequent-row quads form a **serial chain through
decoded MagSgn values**. That is exactly the dense-block case #440 is
about; sparse blocks (kappa ≡ 1) parallelise but are already fast.

The genuinely-parallel structure that remains:

| axis | parallelism | note |
|---|---|---|
| across code-blocks | high | already exploited — 1 thread/block |
| MEL+VLC stream vs MagSgn stream | 2× | producer/consumer pipeline |
| the 4 samples of one quad | 4× | only after that quad's `Uq` is known |
| across quads of a dense row | **none** | blocked by the `maxE`/`kappa` chain |

Best case ≈ 2× × 4×, realised through threadgroup memory + a barrier
per quad (~512 barriers for a 64×64 block) whose overhead would consume
most of the theoretical gain. The warp-cooperative redesign cannot
deliver a clear GPU win on the dense/large blocks that matter.

## Conclusion

- The GPU HT entropy bottleneck is **one-thread-per-block serial
  bitstream parsing**, confirmed and root-caused.
- **Two host-side load-balancing levers both regress**, bit-exact —
  cost-sorting unbalances threadgroup scheduling more than it helps
  warp divergence.
- **The warp-cooperative redesign is structurally blocked** — the HT
  cleanup pass's `maxE`/`kappa` propagation serialises dense-row quads
  through decoded MagSgn values. Within-block parallelism is capped at
  ~2–4× and is not barrier-overhead-viable.

**#440 is structural at the algorithm level, not merely the M2
hardware level.** The HT cleanup pass is a serial per-block algorithm;
GPU threads run serial branchy code slowly; there is no within-block
parallelism to recover in the dense case. No multi-week GPU rewrite
changes this. **Recommendation: do not pursue the warp-cooperative
implementation.** Production decode already uses the CPU C+NEON HT
path; `decodeWithGPUHT` should remain out of auto-routing on M2.

Remaining honest options for #440:
- **Cross-silicon re-evaluation** — M3/M4/A-series GPU cores run serial
  threads faster; the CPU/GPU crossover may differ. Cheapest
  informative next step — needs device readings, not code.
- **Kernel micro-optimisation** — lower register pressure for occupancy,
  faster bit-readers. ~1.2–1.5× at best; still short of the 2.7–4.6×
  CPU gap. Low priority.

#440 should be **re-classified from "optimisation target" to
"structural — the GPU is the wrong machine for HT cleanup decode on
M2; the CPU C+NEON path is the production answer."**

## Deliverables

- `J2KMetalHTCleanup.divergenceSortEnabled` — opt-in sort+repack lever
  (`J2K_GPU_HT_SORT`, **default OFF**; production decode byte-identical
  to v10.9.3). Retained for cross-silicon re-evaluation.
- `Tests/J2KMetalTests/V10_17_GPUHTSortTests.swift` — parity + warm
  A/B diagnostic.
- This finding + redesign-design doc.

`#440` stays open but should be re-labelled **structural** — the
warp-cooperative redesign is *not* a recommended arc (the algorithm
resists it). Cross-silicon re-evaluation is the only cheap informative
next step. Research branch — no `main` merge.
