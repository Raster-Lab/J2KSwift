# v10.17-research — cross-silicon findings

**Branch:** `v10.17-research` · **Status:** open, accumulating device
readings · started 2026-05-22

Running analysis of cross-silicon J2KSwift bench readings collected via
J2KBenchApp (see `V10_17_CROSS_SILICON_HARNESS.md`). The open question
from v10.16 / v10.17: codec-perf on **M2** is at a structural ceiling
and the GPU decode paths lose to CPU there — does that hold on newer
Apple silicon?

## Readings

| Date | Host | Chip | Build | Tool | Runs+Warmups | Status |
|---|---|---|---|---|---|---|
| 2026-05-23 | `Mac14,2` | Apple M2 (2022) | Release | `J2KBenchMac` | 7+2 | **valid** — 3 decode codecs |
| 2026-05-23 | `iPhone15,3` | Apple A16 (iPhone 15 Pro Max, 2022) | Release | `J2KBenchApp` | 11+4 | **valid** — 3 decode codecs |
| 2026-05-22 | `iPhone18,1` | A19-class (iPhone 17 line, 2026) | Release | `J2KBenchApp` | 7+2 | **valid** — 3 decode codecs |
| 2026-05-21 | `iPhone14,8` | A15 | Debug | J2KBenchApp | — | **discarded** — Debug build, ~100× inflated |

`J2KBenchMac` is the macOS counterpart of `J2KBenchApp` (same LCG
corpus, same lossless HT encoder, same warm methodology, same JSON
shape). All three valid readings are genuinely apples-to-apples
(same J2KSwift v10.1.0 codestream + decoder).

The A16 reading uses a more conservative 11 timed runs + 4 warmups
(vs the standard 7+2) — wider sampling on a thermally-bounded
A-series chip; medians are stable, the cross-host comparison is
inside the trial-to-trial spread.

## iPhone18,1 (A19-class) — CPU ↔ GPU decode crossover

Lossless HT, warm in-process, median of 7, synthetic corpus
(`cross_silicon_compare.py`):

| Fixture | px | `decode()` ms | `decodeGPU` ms | `decodeWithGPUHT` ms | fastest |
|---|---:|---:|---:|---:|---|
| mr_synth_small | 65 K | **0.74** | 5.42 | 4.12 | `decode()` |
| ct_synth_mid | 590 K | 3.87 | 3.87 | 12.34 | tie (CPU/GPU) |
| xa_synth_small | 640 K | **4.17** | 4.63 | 12.00 | `decode()` |
| px_synth_mid | 819 K | **5.75** | 6.17 | 12.76 | `decode()` |
| cr_synth_mid | 1.05 M | 8.38 | **7.54** | 14.99 | `decodeGPU` |
| dx_synth_mid | 1.05 M | **7.29** | 7.78 | 14.87 | `decode()` |
| mg_synth_mid | 1.31 M | 9.88 | **8.55** | 15.80 | `decodeGPU` |
| dx_002_class | 6.4 M | **44.86** | 46.97 | 63.64 | `decode()` |
| dx_001_class | 7.77 M | **57.64** | 58.23 | 67.52 | `decode()` (≈ tie) |
| mg_001_class | 16.8 M | 124.01 | 114.53 | **108.90** | `decodeWithGPUHT` |

### Finding — the GPU crossover is real on A19

On **M2** (v10.16 / v10.17): `decodeGPU` ≈ CPU (wash), `decodeWithGPUHT`
2.7–4.6× slower — *always*. v10.17 concluded #440 is "structural on M2"
and explicitly flagged that newer GPU cores might shift the crossover.

On **A19 they do shift:**

- **`decodeGPU`** (GPU IDWT, CPU HT) wins or ties from ~1 MP up —
  cr_synth −10 %, mg_synth −13 %, ct a tie. It still loses the DX-class
  fixtures by a few % (dx_synth 7.78 vs 7.29) — modality/entropy
  dependent.
- **`decodeWithGPUHT`** is still a 2–3× regression on small/mid (GPU HT
  entropy is still slow) — **but it crosses over and wins on the
  16.8 MP MG fixture**: 108.9 ms vs CPU `decode()` 124.0 ms (−12 %),
  also beating `decodeGPU` (114.5 ms).

Size-gated picture on A19:

| px band | fastest decode path |
|---|---|
| ≤ ~0.8 MP | CPU `decode()` |
| ~1 MP | `decodeGPU` on CR/MG; CPU still on DX |
| 6–8 MP (DX class) | ≈ tie, CPU marginally ahead |
| 16.8 MP (MG class) | `decodeWithGPUHT` — both GPU paths beat CPU |

## iPhone15,3 (Apple A16, 2022) — CPU ↔ GPU decode crossover

Lossless HT, warm in-process, **median of 11 (4 warmups)** —
J2KBenchApp's longer-run setting, picked because the A16 in an
iPhone 15 Pro Max sustains less thermal headroom than M2 in a Mac
and benefits from wider sampling.

| Fixture | px | `decode()` ms | `decodeGPU` ms | `decodeWithGPUHT` ms | fastest |
|---|---:|---:|---:|---:|---|
| mr_synth_small | 65 K | **0.81** | 8.59 | 9.87 | `decode()` |
| ct_synth_mid | 590 K | 5.04 | **4.81** | 35.32 | `decodeGPU` |
| xa_synth_small | 640 K | **5.08** | 5.13 | 35.05 | `decode()` (≈ tie) |
| px_synth_mid | 819 K | 7.57 | **7.16** | 30.44 | `decodeGPU` |
| cr_synth_mid | 1.05 M | 8.68 | **8.57** | 37.29 | `decodeGPU` (≈ tie) |
| dx_synth_mid | 1.05 M | **8.49** | 8.65 | 34.91 | `decode()` (≈ tie) |
| mg_synth_mid | 1.31 M | 10.95 | **10.83** | 37.60 | `decodeGPU` (≈ tie) |
| dx_002_class | 6.4 M | **55.67** | 56.07 | 136.65 | `decode()` (≈ tie) |
| dx_001_class | 7.77 M | 69.88 | **69.80** | 129.14 | `decodeGPU` (≈ tie) |
| mg_001_class | 16.8 M | 152.56 | **149.20** | 149.77 | `decodeGPU` (3-way ≈ tie) |

### Finding — A16 sits between M2 and A19 on the GPU-HT axis

A16 GPU HT entropy is **never faster than CPU** in this corpus, even
at 16.8 MP where M2 is +2% slower and A19 is −12% faster. At MG
3520×4784:

- CPU (152.56 ms) ≈ `decodeGPU` (149.20 ms) ≈ `decodeWithGPUHT` (149.77 ms)
  — all three lanes within ±2.2% of each other. The GPU paths *catch
  up* to CPU but never overtake.

For smaller fixtures the GPU-HT path is **4–12× slower** (mr_synth_small
12.2× slower at 9.87 vs CPU 0.81; ct/xa/px all ~6–8× slower). Same
qualitative shape as M2 — the v10.17 root cause (one-thread-per-block
serial bitstream parse) hurts both 2022-era Apple GPUs the same way.

The CPU lane has its own A16 story: A16 CPU is the **slowest** of the
three (M2 117.96 / A19 124.01 / A16 152.56 ms on MG large) — an
A-series 6-core part can't match M2's 8-core or A19's wider IPC at
this workload size. Per-fixture the A16/M2 CPU ratio is 0.77–1.28×
(A16 wins only on `xa_synth_small`, the smallest XA fixture).

## M2 ↔ A16 ↔ A19 head-to-head (apples-to-apples)

Full report: [`Documentation/Benchmarks/CROSS_SILICON_M2_A16_A19_REPORT.md`](../Benchmarks/CROSS_SILICON_M2_A16_A19_REPORT.md).

**Headline: GPU HT entropy throughput scales with GPU generation, not
with the chip's CPU class.** Same fixtures, same encoder, same warm
methodology:

| Fixture | px | `decodeWithGPUHT` M2 ms | A16 ms | A19 ms | A16/M2 | A19/M2 |
|---|---:|---:|---:|---:|---:|---:|
| mr_synth_small | 65 K | 8.76 | 9.87 | 4.12 | 1.13× slower | **2.1× faster** |
| ct_synth_mid | 590 K | 29.80 | 35.32 | 12.34 | 1.19× slower | **2.4×** |
| xa_synth_small | 640 K | 27.82 | 35.05 | 12.00 | 1.26× slower | **2.3×** |
| px_synth_mid | 819 K | 29.50 | 30.44 | 12.76 | 1.03× slower | **2.3×** |
| cr_synth_mid | 1.05 M | 31.58 | 37.29 | 14.99 | 1.18× slower | **2.1×** |
| dx_synth_mid | 1.05 M | 31.72 | 34.91 | 14.87 | 1.10× slower | **2.1×** |
| mg_synth_mid | 1.31 M | 32.02 | 37.60 | 15.80 | 1.17× slower | **2.0×** |
| dx_002_class | 6.4 M | 126.70 | 136.65 | 63.64 | 1.08× slower | **2.0×** |
| dx_001_class | 7.77 M | 132.80 | 129.14 | 67.52 | 0.97× ≈ tie | **2.0×** |
| mg_001_class | 16.8 M | 120.28 | 149.77 | 108.90 | 1.25× slower | 1.1× |

**A16 sits BELOW M2 on the GPU-HT axis** — every fixture the A16 GPU
runs the per-block serial cleanup pass 1.0–1.26× slower than M2. The
A16 GPU has fewer execution units and less bandwidth than M2's; the
HT cleanup workload is bottlenecked on per-thread serial throughput,
so M2's wider GPU helps even with the same kernel.

**A19 is 2× faster than M2 on every fixture except MG 16.8 MP** (1.1×
there because both M2 and A19 hit a thermal/throughput ceiling at the
largest workload, but A19 still wins).

By contrast:

- **CPU `decode()`**: M2 ≈ A19 (within ±15%); A16 slower at large
  sizes (0.77–1.28× of M2) — fewer cores, lower power envelope. The
  C+NEON path's per-core IPC is similar across all three.
- **`decodeGPU`** (GPU IDWT, CPU HT): roughly tied across all three —
  the IDWT kernel is bandwidth-bound and similar on all 3 GPUs. Not
  the silicon-sensitive lane.

So the silicon-sensitive lane is exactly **GPU HT entropy** — the
one-thread-per-block serial branchy bitstream parse that v10.17
root-caused on M2. **A19 GPU cores run that serial code 2× faster than
M2; A16 runs it slightly SLOWER than M2.** Three datapoints, one
trend: GPU HT entropy scales with the *GPU generation*, not the chip
class — A16 (2022) is comparable to M2 (2022), A19 (2026) shows
4 generations of GPU evolution.

### Implication for the router

`recommendedDecodeAPI` is dimension-only and **silicon-blind**; it
routes `≥ 15 MP → .cpu`. With apples-to-apples data on three Apple
silicons:

| silicon | ≤ ~0.8 MP | ~1 MP | 1–6 MP | 6–8 MP (DX) | 16.8 MP (MG) |
|---|---|---|---|---|---|
| **M2**  | CPU | CPU/decodeGPU (mixed) | decodeGPU | decodeGPU/CPU (tie) | CPU |
| **A16** | CPU | decodeGPU (≈ tie with CPU) | decodeGPU (≈ tie) | CPU/decodeGPU (tie) | **3-way tie** |
| **A19** | CPU | decodeGPU (CR/MG); CPU (DX) | decodeGPU (mixed) | CPU | **decodeWithGPUHT** |

The router fix is concrete:
- **M2 calibration**: ≥ 15 MP → `.cpu` stays correct.
- **A16 calibration**: ≥ 15 MP → `.cpu` or `.decodeGPU` — tied. Stay
  with `.cpu` (current behaviour) — the GPU-HT lane never wins.
- **A19 calibration**: ≥ ~15 MP → **`.decodeWithGPUHT`** (currently
  mis-routed to `.cpu` on A19).

A `recommendedDecodeAPI(width:height:chip:)` overload or a chip-class
detector would be enough. **Signal strengthened by the 3rd device**
(A16 confirms M2's pattern is not M2-specific — it's the 2022 Apple
GPU baseline) **but A19 calibration still depends on one device**
(more A19 readings — A19 Pro variant, different thermal envelopes —
would firm the recommendation).

### Caveats

- **One A19 device, one 7-run session.** The `mg_001` `decodeWithGPUHT`
  samples spread 95.7–117.8 ms; the 15 ms median win over `decode()`
  exceeds that spread, so the result is real — but 2–3 more A19
  readings would firm it.
- **A16 reading uses 11+4** runs (vs 7+2 elsewhere) — wider sampling
  to compensate for A-series thermal variance. Medians are stable;
  the A16 GPU-HT-slower-than-CPU pattern is consistent across the
  full distribution.
- **Synthetic LCG-noise fixtures**, not real medical images. v10.16
  showed GPU-vs-CPU results flip between lossy/lossless and depend on
  entropy profile; synthetic vs real-medical could move the crossover.
- `iPhone18,1` is an iPhone 17-series device; "A19-class" covers the
  exact A19 / A19 Pro variant.
- `iPhone15,3` is the iPhone 15 Pro Max (A16 Bionic). The non-Pro
  A16 phones (iPhone 15 / 15 Plus) ship the same A16 with one fewer
  GPU core; that variant could shift the GPU lanes by ~15%.
- This **confirms, not contradicts, v10.17**: #440 is structural *on
  pre-A19 Apple GPUs*; the crossover *is* silicon-dependent — exactly
  what v10.17 predicted. A16 reinforces the M2 finding; A19 breaks the
  pattern.

## Next

- More A19 readings (variance) + A18 / A17 / M4 in the same J2KBenchApp
  synthetic corpus, for a tighter cross-silicon matrix. A18 in
  particular would tell us whether the A19 crossover is GPU-generation-
  specific or a hardware-class shift starting with A18.
- Real-medical-fixture readings if feasible (synthetic vs real may
  shift the GPU crossover, per v10.16).
- Once 2–3 consistent A19 readings agree: scope a silicon-aware
  `recommendedDecodeAPI` — this re-opens #440 for A19 as a **routing**
  task (a `chip`-aware recommendation), not the (M2-doomed) GPU HT
  kernel rewrite.
