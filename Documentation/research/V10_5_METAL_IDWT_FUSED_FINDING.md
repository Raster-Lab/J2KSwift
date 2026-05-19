# v10.5-research — GPU IDWT H+V fused-kernel bandwidth probe

**Date**: 2026-05-19 (autonomous follow-up to the
[v10.5 CPU column-block probe](V10_5_IDWT_COLBLOCK_BANDWIDTH_PROBE.md))
**Branch**: `v10.5-research`
**Status**: **OPT-IN — borderline gate clearance, default OFF**
**Code**: opt-in via `J2K_METAL_IDWT_FUSED=1`

---

## TL;DR

Probed the v10.5 follow-on lever raised after the CPU column-block
arc closed wash: "GPU IDWT Metal kernel re-optimization — untouched
as a bandwidth probe, separate multi-week arc."

The current v10.3 Phase 2-2-tiled IDWT path runs **3 kernel
dispatches per IDWT level**: two horizontal passes (LL+HL → colLow,
LH+HH → colHigh) and one vertical pass (colLow + colHigh → output).
Each per-level pair writes 2 × 67 MB of intermediate colLow/colHigh
to device memory, then reads it back in the V pass. Bandwidth math
at MG L1 (3520×4784 Int32 = 67 MB):

| Stage | Read MB | Write MB |
|---|---:|---:|
| H1 (LL+HL → colLow)        | 33.6 | 33.7 |
| H2 (LH+HH → colHigh)       | 33.6 | 33.7 |
| V  (colLow+colHigh → output) | 67.4 | 67.4 |
| **Total / level**           | **134.6** | **134.8** |

A **fused H+V kernel** that holds the H-pass output in threadgroup
memory across the V-pass lift collapses this to LL+HL+LH+HH reads
(67 MB) + output write (67 MB) ≈ 134 MB total — **2× DRAM saving**
plus a 3 → 1 kernel-dispatch reduction (saves ≈ 80 µs × 5 levels of
encoder overhead).

Projected wall savings on MG: ~1.7 ms (DRAM at 80 GB/s) + ~0.8 ms
(encoder overhead) ≈ **2.5–3.5 ms**, right at the v7.4 3 ms gate.

**Result**: built the fused kernel
(`j2k_dwt_inverse_53_fused_int_tiled` — tg(32, 10), 32×16 output tile,
1-row halo via redundant H-pass on lid.y == 0 and lid.y == 9), wired
the Swift dispatcher behind a `J2K_METAL_IDWT_FUSED` env flag, and
ran the full validation chain:

| Phase | Result |
|---|---|
| Parity gate (small / odd / medical corpus) | **3/3 PASS** (bit-exact vs tiled) |
| Microbench A/B (10 synthetic fixtures) | Mixed: MG 3520 **+1.23×** / −6.28 ms, MG 3521 0.98× / +0.88 ms, smaller fixtures 0.75-0.95× (regressions) |
| End-to-end warm A/B (medical corpus, 2 runs) | MG small +5.97-7.84 ms (5.9-7.6%), MG mid +2.35-5.85 ms (2.4-6.0%), MG large +2.96 / -4.38 ms (flips sign — variance ≈ 5 ms), smaller fixtures within ±1 ms |

**Decision**: **default OFF**, opt-in only via `J2K_METAL_IDWT_FUSED=1`.

Reasons:
1. **Variance at the gate**. MG large flips sign run-to-run inside
   the 3 ms gate, indicating system noise is comparable to the lift.
   The two-run aggregate is +3.5 ms across MG (real signal) but the
   per-run gate clearance is unreliable.
2. **Smaller-fixture wash**. DX (6-8 MP), PX (3-4 MP), XA (1 MP), CT
   (262 K) sit inside ±1 ms of tiled — no improvement, occasional
   small regressions.
3. **Per `feedback_no_half_releases.md`**, research stays gated until
   the win is decisive. A pixel-threshold gated default-on (≥12 MP →
   fused, else tiled) would be a reasonable future direction once
   10+ run variance data is collected and the threshold pinned.
4. **Cross-silicon re-evaluation**. Apple M3 / M4 / A-series have
   larger L2 (24-28 MB) and faster DRAM fabric — the bandwidth math
   shifts. The lever should be re-measured on each silicon class
   before any default-flip.

---

## What landed

**Metal kernel** (`Sources/J2KMetal/J2KShaders.metal`):
`j2k_dwt_inverse_53_fused_int_tiled` — single-kernel H+V inverse 5/3
Int with threadgroup-memory staging. Threadgroup (32, 10) produces a
32×16 output tile; lid.y ∈ {0, 9} compute halo rows that feed the V
lift's symmetric extension without writing output. Three barriers:
H-Stage-A → H-Stage-B → V-Step-1 → V-Step-2.

**Shader registration**
(`Sources/J2KMetal/J2KMetalShaderLibrary.swift`):
`dwtInverse53FusedIntTiled` case added.

**Swift dispatcher**
(`Sources/J2KMetal/J2KMetalDWT.swift`):
- New `inverse53IntFusedEnabled` flag (default OFF, opt-in via
  `J2K_METAL_IDWT_FUSED=1`)
- New private `encodeInverse2DInt32_Fused` dispatcher
- Routing: when `inverse53IntFusedEnabled && !hOddOrigin && !vOddOrigin`,
  takes precedence over `inverse53IntTiledEnabled`

**Tests** (`Tests/J2KMetalTests/V10_5_*`):
- `V10_5_MetalIDWTInverse53FusedParityTests` — 3 test methods, 21
  fixture/seed combinations, bit-exact vs scalar reference path
- `V10_5_MetalIDWTInverse53FusedMicrobench` — A/B vs tiled, 10
  synthetic fixtures including MG/DX/PX class
- `V10_5_MetalIDWTInverse53FusedEndToEndABTests` — warm A/B on the
  real medical corpus through the full decode pipeline

**Metallib**:
`Sources/J2KMetal/default.metallib` regenerated via
`Scripts/build_metallib.sh` to include the new kernel.

---

## Microbench result

`V10_5_MetalIDWTInverse53FusedMicrobench` (M2 release, warmups=2,
iterations=7):

| Fixture | Pixels | Tiled ms | Fused ms | Speedup | Δ ms |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 32 K | 0.32 | 0.30 | 1.06× | −0.02 |
| CT 512² | 262 K | 0.43 | 0.47 | 0.92× | +0.04 |
| MR 886² | 785 K | 0.81 | 1.02 | 0.79× | +0.21 |
| XA 1024² | 1.05 M | 1.04 | 1.21 | 0.86× | +0.17 |
| PX 2459×1316 | 3.2 M | 1.97 | 2.57 | 0.77× | +0.60 |
| PX 2793×1316 | 3.7 M | 4.16 | 5.54 | 0.75× | +1.38 |
| DX 2800×2288 | 6.4 M | 9.99 | 9.56 | **1.05×** | −0.43 |
| DX 2544×3056 | 7.8 M | 11.43 | 10.20 | **1.12×** | −1.23 |
| **MG 3520×4784** | **16.8 M** | **33.29** | **27.01** | **1.23×** | **−6.28** |
| MG 3521×4784 | 16.8 M | 34.35 | 35.23 | 0.98× | +0.88 |

The MG 3520 → 1.23× speedup confirms the bandwidth math works in
isolation. The MG 3521 wash (despite being only 1 px wider) shows
that GPU IDWT timing on M2 has run-to-run variance comparable to
the per-run lever lift at this fixture scale.

The smaller-fixture regressions (PX/XA/MR 0.75-0.92×) trace to the
fused kernel's higher constant overhead: 3 barriers per dispatch
(vs the tiled pair's 1+1 = 2), larger threadgroup memory footprint
(2.5 KB vs 1.1 KB) reducing occupancy, and the tg(32, 10) shape's
12.5% redundant halo H-pass compute.

---

## End-to-end warm A/B (medical corpus, two consecutive runs)

`V10_5_MetalIDWTInverse53FusedEndToEndABTests` — M2 release, in-proc,
7 timed runs + 2 warmups per (fixture × path):

**Run 1**

| Fixture | px | tiled ms | fused ms | Δ ms | Δ % |
|---|---:|---:|---:|---:|---:|
| MG small 3516×4784 | 16.8 M | 103.25 | 95.41 | **+7.84** | **+7.6%** |
| MG mid 3518×4784 | 16.8 M | 96.29 | 93.93 | +2.35 | +2.4% |
| MG large 3521×4784 | 16.8 M | 105.31 | 102.35 | +2.96 | +2.8% |
| DX 2800×2288 | 6.4 M | 46.83 | 46.94 | −0.11 | −0.2% |
| DX small 2224×2798 | 6.2 M | 45.50 | 45.86 | −0.36 | −0.8% |
| DX large 2544×3056 | 7.8 M | 56.00 | 56.86 | −0.85 | −1.5% |
| PX 2459×1316 | 3.2 M | 26.82 | 27.74 | −0.91 | −3.4% |
| PX mid 2793×1316 | 3.7 M | 29.42 | 29.51 | −0.09 | −0.3% |
| PX large 2812×1316 | 3.7 M | 29.61 | 29.48 | +0.13 | +0.4% |
| XA 1024² | 1.0 M | 7.66 | 8.00 | −0.34 | −4.5% |
| CT 512² | 262 K | 2.75 | 3.07 | −0.32 | −11.6% |

**Run 2**

| Fixture | px | tiled ms | fused ms | Δ ms | Δ % |
|---|---:|---:|---:|---:|---:|
| MG small 3516×4784 | 16.8 M | 101.02 | 95.05 | **+5.97** | **+5.9%** |
| MG mid 3518×4784 | 16.8 M | 98.29 | 92.44 | **+5.85** | **+6.0%** |
| MG large 3521×4784 | 16.8 M | 102.71 | 107.09 | **−4.38** | **−4.3%** |
| DX 2800×2288 | 6.4 M | 46.25 | 46.38 | −0.14 | −0.3% |
| DX small 2224×2798 | 6.2 M | 45.15 | 44.87 | +0.28 | +0.6% |
| DX large 2544×3056 | 7.8 M | 55.93 | 56.07 | −0.14 | −0.2% |
| PX 2459×1316 | 3.2 M | 26.90 | 27.30 | −0.40 | −1.5% |
| PX mid 2793×1316 | 3.7 M | 29.08 | 29.50 | −0.42 | −1.5% |
| PX large 2812×1316 | 3.7 M | 29.83 | 29.53 | +0.29 | +1.0% |
| XA 1024² | 1.0 M | 8.20 | 7.61 | +0.59 | +7.1% |
| CT 512² | 262 K | 2.76 | 2.51 | +0.25 | +9.0% |

**Two-run aggregate (MG class)**:
- MG small: avg +6.9 ms (range +5.97 to +7.84) → **clears 3 ms gate consistently**
- MG mid: avg +4.1 ms (range +2.35 to +5.85) → clears gate on average
- MG large: avg −0.7 ms (range +2.96 to −4.38) → **flips sign**, unreliable

**Smaller fixtures (DX / PX / XA / CT)**: sit inside ±1 ms of tiled
in both directions; no consistent signal.

---

## Verdict and decision tree

The fused kernel is **bit-exact**, the **MG small / MG mid wins are
reproducible** in magnitude, but **MG large is unstable** and the
v7.4 3 ms gate is borderline-clear on aggregate.

The user's stated use case ("MG mammography decode improvement")
benefits 2.4-7.6% on small / mid MG, marginally or negatively on
large MG. Smaller-fixture workloads see no win.

**Default OFF** preserves the v10.1.0 Phase 2-2-tiled wins across
the full fixture range, while keeping the fused path available
for diagnostic A/B and cross-silicon re-measurement.

**Future default-flip candidates** (not in this arc):
1. Pixel-threshold gated default-on (≥12 MP → fused, ≥12 MP gets
   the consistent MG-small / MG-mid +5-7 ms wins, < 12 MP keeps
   tiled). Pattern mirrors `_gpuInverse53PixelThreshold = 4_000_000`.
2. Cross-silicon re-measurement on M3 / M4 — different L2 / DRAM
   curves may flip the variance pattern.
3. Reducing fused-kernel overhead (single-barrier H+V via different
   thread layout, e.g. each thread does 4 outputs in a 16×16 tg) —
   would lower the smaller-fixture wash.

---

## Files modified / added

- `Sources/J2KMetal/J2KShaders.metal` — `j2k_dwt_inverse_53_fused_int_tiled`
- `Sources/J2KMetal/J2KMetalShaderLibrary.swift` — `dwtInverse53FusedIntTiled` case
- `Sources/J2KMetal/J2KMetalDWT.swift` — `inverse53IntFusedEnabled`
  flag, `encodeInverse2DInt32_Fused` dispatcher, routing precedence
- `Sources/J2KMetal/default.metallib` — regenerated to include the
  new kernel
- `Tests/J2KMetalTests/V10_5_MetalIDWTInverse53FusedParityTests.swift`
- `Tests/J2KMetalTests/V10_5_MetalIDWTInverse53FusedMicrobench.swift`
- `Tests/J2KMetalTests/V10_5_MetalIDWTInverse53FusedEndToEndABTests.swift`
- `Documentation/research/V10_5_METAL_IDWT_FUSED_FINDING.md` (this file)

**Not landing on `main`**: opt-in research artifact; production
routing change deferred to a future arc.
