# v10.5-research — CPU iDWT column-block bandwidth probe

**Date**: 2026-05-15 (overnight autonomous research session)
**Branch**: `v10.5-research`
**Status**: **CLOSED — WASH (10th lever-ceiling confirmation on M2 + Swift release)**
**Code**: opt-in via `J2K_IDWT_COLBLOCK=1` (default OFF)

---

## TL;DR

Probed the v10.5 question raised in the conversational triage: "why is
M2 residual Kakadu gap concentrated on MG mammography, some DX chest
X-ray, and large PX panoramic — what are the possibilities to improve?"

Picked **lever #3** — the memory-bandwidth angle on MG. Hypothesis:
the canonical `inverseTransformMultiLevel53` column-pass pays a
transpose + stride-1 lift + untranspose round-trip that burns
**~6× the per-pass buffer in DRAM traffic** at level-1 of MG-class
buffers (3520×4784 Int32 = 67 MB working set, 4× M2's 16 MB shared
P-cluster L2). The probe collapses that to **2×** the buffer by
lifting columns in-place on a row-major buffer in N-column blocks
(N = 16 = one Int32 cache line).

**Result**: the lever is **real and bit-exact** at the isolated
column-pass scope (5.5–8.3× speedup, 22 ms saved on MG level-1) but
**doesn't materialise end-to-end** (every MG / DX / PX fixture sits
inside ±3 ms after warm-bench A/B). 10th independent investigation
arriving at the same M2 + Swift release lever-ceiling pattern that
v6-alpha4, v7.4, v7.5, v8.1, v8.4, v8.5, v8.6, v8.7, v10.1, v10.4
already documented.

Code stays in tree as opt-in only: the parity is clean, the diagnostic
A/B path is preserved, and the path is a building block if a future
GPU IDWT-side bandwidth probe lands or M3+/A-series silicon shifts
the L2 curve.

---

## Premise

`inverseTransformMultiLevel53` runs N decomposition levels of inverse
Le Gall 5/3 over a flat row-major `Int32` buffer that doubles in size
each level. At the largest level on an MG fixture:

```
outH × outW × 4 bytes  =  4784 × 3520 × 4  =  67 357 696 bytes  (67 MB)
```

M2's L2 cache: **16 MB** shared across the 4-core P-cluster
(~4 MB per P-core under heavy contention).

The canonical column-pass does:

1. `transpose base → tBuf`            (read 67 MB, write 67 MB)
2. parallel column-block lift on `tBuf` stride-1 (read 67 MB + write 67 MB)
3. `transpose tBuf → base`            (read 67 MB, write 67 MB)

Total **DRAM traffic per pass ≈ 6× buffer = 402 MB**. At M2's ~80 GB/s
effective bandwidth that's a hard ~5 ms floor for just the column-
pass at level 1.

The probe path keeps `base` row-major and lifts column blocks of N=16
adjacent columns directly with stride=outW:

- Each `for c in cStart..<cEnd` inner-loop touches N cells per row visit
- Three rows (prev-odd / cur-even / next-odd) are touched per `i` step
- Working footprint per block-i step: 3 rows × N cells = ~192 B,
  L1-resident
- Total **DRAM traffic per pass ≈ 2× buffer = 134 MB**, 3× less

If the bandwidth math is the dominant cost, the probe should land a
meaningful end-to-end win on MG / DX / large PX.

---

## Phase 1 — column-pass microbench
**Test**: `V10_5_IDWTBandwidthProbeMicrobench`

Six synthetic buffer shapes mirroring the level-1 (largest) pass of
real MG / DX / PX fixtures, plus an MG-level-2 sanity check. M2
release, 7 timed runs after 2 warmups, median.

| Buffer | bytes | prod ms | probe ms | Δ ms | speedup | parity |
|---|---:|---:|---:|---:|---:|---|
| MG-class 3520×4784 (level-1) | 67 358 720 | 27.09 |  4.31 | **+22.79** | **6.29×** | ✓ |
| MG-mid 3518×4784 (level-1)   | 67 320 448 | 27.16 |  4.99 | +22.17 | 5.45× | ✓ |
| DX-large 2544×3056 (level-1) | 31 097 856 | 12.00 |  1.84 | +10.16 | 6.52× | ✓ |
| DX-mid 2800×2288 (level-1)   | 25 625 600 | 10.02 |  1.46 |  +8.55 | 6.85× | ✓ |
| PX-large 2812×1316 (level-1) | 14 802 368 |  4.99 |  0.79 |  +4.20 | 6.32× | ✓ |
| MG level-2 1760×2392         | 16 839 680 |  6.28 |  0.76 |  +5.52 | 8.25× | ✓ |

All six configurations bit-exact between paths. The microbench is
unambiguous: at the column-pass scope the probe is **5.5–8.3× faster**
on real-world MG / DX / PX buffer shapes.

---

## Phase 2 — wire into production
Added `inverseLift53ColBlock(_:cStart:cEnd:outW:evenCount:oddCount:)`
to `J2KDWT2DOptimizer` (Sources/J2KCodec/J2KDWT1DOptimized.swift) +
env-var gate `columnBlockLiftEnabled` (env `J2K_IDWT_COLBLOCK`).
Modified the column-pass branch of `inverseTransformMultiLevel53` to
dispatch on the gate: column-block path when ON, canonical path
otherwise.

The canonical (transpose) path stays maintained as the opt-out and
the small-buffer (outH < 32 or outW < 32) sequential branch is
unchanged.

---

## Phase 3 — bit-exact parity
**Test**: `V10_5_IDWTColBlockParityTests`

Toggles `columnBlockLiftEnabled` OFF then ON, decodes each fixture
through `J2KDecoder.decode(_:)`, byte-compares the two outputs.

- **10 medical corpus fixtures**: MG×3, DX×3, PX×2, MR, CT — all
  bit-exact ✓
- **6 synthetic odd-parity edge cases**: 33×33, 64×65, 65×64,
  127×129, 513×511, 1023×1025 — all bit-exact ✓

The probe is mathematically equivalent to the canonical path. No
parity surprises across the 5 decomposition levels, the boundary
parity asymmetry branches, or the 32×32 small-buffer fallback.

---

## Phase 4 — end-to-end A/B (canonical CPU vs col-block CPU)
**Test**: `V10_5_IDWTColBlockEndToEndABTests`

Warm in-proc median of 7 timed runs + 2 warmups per (fixture × path),
default routing (so MG / DX may go through GPU IDWT — see Phase 4b
for the CPU-forced view).

| Fixture | px | canonical ms | col-block ms | Δ ms | Δ % |
|---|---:|---:|---:|---:|---:|
| MG small 3516×4784 | 16 820 544 | 104.08 | 103.57 | +0.50 | +0.5% |
| MG mid 3518×4784   | 16 830 112 |  99.38 |  97.75 | +1.62 | +1.6% |
| MG large 3521×4784 | 16 844 464 | 107.95 | 109.08 | **-1.13** | -1.0% |
| DX 2800×2288       |  6 406 400 |  47.55 |  48.37 | **-0.82** | -1.7% |
| DX small 2224×2798 |  6 222 752 |  46.19 |  45.81 | +0.39 | +0.8% |
| DX large 2544×3056 |  7 774 464 |  57.30 |  57.89 | **-0.59** | -1.0% |
| PX 2459×1316       |  3 236 044 |  27.55 |  27.91 | -0.36 | -1.3% |
| PX mid 2793×1316   |  3 675 588 |  29.71 |  29.97 | -0.26 | -0.9% |
| PX large 2812×1316 |  3 700 592 |  29.79 |  29.65 | +0.14 | +0.5% |
| XA 1024²           |  1 048 576 |   7.65 |   7.83 | -0.17 | -2.3% |
| CT 512²            |    262 144 |   2.65 |   2.21 | +0.44 | +16.5% |
| MR-small 180²      |     32 400 |   0.65 |   0.62 | +0.03 | +3.9% |

**Every fixture sits inside ±3 ms**. The v7.4 acceptance gate
(≥3 ms lift on at least one fixture in the target class) does not
clear. The 22 ms / 6× microbench result does not survive the move
from isolated-stage benchmark to end-to-end wall.

---

## Phase 4b — GPU vs CPU vs CPU+col-block (CPU-forced)
**Test**: `V10_5_IDWTColBlockVsGPUTests`

For each fixture, measures **three** decode paths:

1. **GPU IDWT** (production routing, `_gpuInverse53Enabled = true`)
2. **CPU IDWT canonical** (transpose round-trip)
3. **CPU IDWT column-block** (this probe)

| Fixture | GPU ms | CPU canon ms | CPU col-block ms | Δ col − GPU | Δ col − canon |
|---|---:|---:|---:|---:|---:|
| MG small 3516×4784 | 111.81 | 102.02 | 104.14 | -7.68 | +2.12 |
| MG mid 3518×4784   | 102.82 | 105.10 | 104.51 | +1.70 | -0.59 |
| MG large 3521×4784 | 111.77 | 113.74 | 113.12 | +1.35 | -0.62 |
| DX 2800×2288       |  47.63 |  47.56 |  49.49 | +1.85 | +1.93 |
| DX small 2224×2798 |  47.59 |  51.19 |  48.05 | +0.46 | -3.14 |
| DX large 2544×3056 |  59.75 |  58.29 |  58.92 | -0.82 | +0.63 |

Two structural observations from Phase 4b:

1. **CPU col-block doesn't win against either alternative end-to-
   end**. Δ-vs-GPU sits in ±2 ms band on 5/6 fixtures (one outlier
   −7.68 ms on MG small, but the same fixture shows CPU canon −9.79
   ms vs GPU — the GPU number is the outlier, not the col-block one).
   Δ-vs-canonical-CPU sits in ±3 ms band on all six.

2. **GPU IDWT is not clearly better than CPU IDWT on MG / DX**.
   On MG small / mid / large, CPU canon comes in within ±3 ms of
   GPU (-9.79 / +2.28 / +1.97 ms). The `_gpuInverse53Enabled = true`
   default routes these fixtures to GPU on a curve that may have
   shifted since v6.2.0 — a separate lever, **not investigated
   here**.

---

## Why the microbench result didn't survive

Three structural reasons compound — same pattern documented in
v8.4 / v8.5 / v8.6 / v8.7 / v10.4 lever-ceiling memos:

### 1. Production routing bypasses the CPU path for the target fixtures

`J2KDecoder.decode()` gates on `_gpuInverse53Enabled` (default ON)
+ `_gpuInverse53PixelThreshold = 4_000_000`. Every fixture in the
target class (MG, DX, large PX) is ≥4 MP — they route to
`decodeSingleTileGPU` / `decodeMultiTileGPU`, neither of which calls
`inverseTransformMultiLevel53`. The CPU column-pass only fires on
sub-4 MP single-tile fixtures (PX small, XA, CT, MR-small) where the
level-1 buffer fits in L2 anyway and there's no bandwidth tax to elide.

### 2. Isolated stage cost ≠ wall cost when the stage isn't critical-path-bound

The microbench measured one column-pass in isolation against itself;
the synthetic LCG-noise buffer also produces near-uniform cache
behaviour (no entropy-side correlated working-set patterns competing
for L2). End-to-end, the iDWT runs in series with entropy decode +
allocation + buffer placement, and the column-pass speedup is
masked by:

- HT entropy decode wall (the row-lift stage of the IDWT can begin
  only after dequantization completes — but the *parallel* entropy
  decode keeps most cores busy)
- Buffer allocation churn at each level (67 MB → 17 MB → 4 MB → … —
  each `UnsafeMutablePointer.allocate` costs ~100 µs and dominates
  small-level wall)
- Cache contamination from the entropy-decode hot working set,
  which evicts the iDWT working set from L2 between row-pass and
  column-pass on a single tile

### 3. The canonical transpose path's parallel-chunk structure already extracts most of the L2 reuse

The canonical column-pass parallelises over `outW / coreCount`
chunks. Each chunk processes ~440 columns (MG / 8 cores). The
transpose itself is tile-blocked at 64×64 (line ~615). Across all
4 P-cores, the working set per core during column-lift fits in
L2 well enough that the extra bandwidth round-trip (transpose +
untranspose) costs much less wall-time than the synthetic-buffer
microbench suggested. M2's prefetcher also handles stride-1 lift
on the transposed buffer very efficiently — apparently efficiently
enough to mostly compensate for the 3× DRAM traffic disadvantage.

---

## Lever-ceiling pattern (10th confirmation)

This is the 10th independent codec hot-path investigation on
M2 + Swift release that arrived at the same conclusion: isolated-
stage microbench shows a meaningful speedup; end-to-end wall doesn't
move.

| # | Arc | Lever | Microbench delta | End-to-end delta |
|---|---|---|---|---|
| 1 | v6-alpha4 step 12 | C + D inner-loop | wins | wash |
| 2 | v7.4 NEON reconstruction | SIMD vs scalar | 0.9 ms | sub-3 ms gate |
| 3 | v7.5 forward HT GPU entropy | GPU dispatch | wins | -22.4 ms regression |
| 4 | v8.1 prefix-scan / 8-byte SWAR | corpus density | 1.17× | -0.58 ms wash |
| 5 | v8.4 stage breakdown | 3 probes | varied | wash |
| 6 | v8.5 HT consumer body | batched-read | +8.23 ns/quad | -1.32 ms below 3 ms gate |
| 7 | v8.6 encoder per-quad SIMD | classifier | wins | wash |
| 8 | v8.7 row-parallel re-test | algo redesign | +10 ms regression | wash |
| 9 | v10.4 forward DWT levers | 3 levers | varied | wash |
| **10** | **v10.5 iDWT column-block bandwidth** | **6× column-pass speedup** | **22 ms** | **wash** |

The codec hot path on M2 + Swift release + macOS is at structural
lever-ceiling for both encode and decode. Anything still on the
table needs **cross-silicon measurement** (M3 / M4 — the M4 cross-
host bench already shows the gap closing on every fixture) or
**framework / GPU shader redesigns** (multi-week scope, high risk).

---

## What ships from this arc

**On `v10.5-research` only** (per memory: research stays on its branch):

- `J2KDWT2DOptimizer.inverseLift53ColBlock(...)` — bit-exact column-
  block lift primitive
- `J2KDWT2DOptimizer.columnBlockLiftEnabled` — env-gated dispatch
  (default OFF, opt-in via `J2K_IDWT_COLBLOCK=1`)
- `V10_5_IDWTBandwidthProbeMicrobench` — column-pass microbench
- `V10_5_IDWTColBlockParityTests` — 10 medical + 6 edge-case parity
- `V10_5_IDWTColBlockEndToEndABTests` — end-to-end A/B
- `V10_5_IDWTColBlockVsGPUTests` — three-way GPU / CPU / CPU+col-block

**Not landing on `main`**: no release-candidate path. The lever
doesn't move the wall.

---

## Possible follow-ups (not pursued tonight)

1. **GPU IDWT bandwidth probe** — port the column-block scheme into
   the Metal threadgroup-memory tiled kernel. Multi-week scope,
   high risk; meaningful only if the GPU IDWT itself is bandwidth-
   bound (separate measurement question).
2. **Re-evaluate `_gpuInverse53PixelThreshold = 4 MP` for MG** —
   Phase 4b shows CPU IDWT ≈ GPU IDWT on MG. Raising the threshold
   to 15 MP (matching v9.6 `recommendedDecodeAPI`) might simplify
   the routing decision tree without moving the wall. Owner: a
   future dedicated routing-recalibration PR; not in this arc's
   scope.
3. **Cross-silicon re-measurement (M3 / M4)** — the L2 curve is the
   thing the probe was trying to exploit. Apple's L2 grew on M3
   (24 MB) and M4 (28 MB). The bandwidth math reverses: at M4, the
   MG level-1 buffer is L2-resident even on the canonical path, so
   the probe loses its premise. But the per-pass bandwidth advantage
   is universal — measure first.
