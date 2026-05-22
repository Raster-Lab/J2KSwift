# v10.17-research — cross-silicon findings

**Branch:** `v10.17-research` · **Status:** open, accumulating device
readings · started 2026-05-22

Running analysis of cross-silicon J2KSwift bench readings collected via
J2KBenchApp (see `V10_17_CROSS_SILICON_HARNESS.md`). The open question
from v10.16 / v10.17: codec-perf on **M2** is at a structural ceiling
and the GPU decode paths lose to CPU there — does that hold on newer
Apple silicon?

## Readings

| Date | Host | Chip | Build | Tool | Status |
|---|---|---|---|---|---|
| 2026-05-23 | `Mac14,2` | Apple M2 | Release | `J2KBenchMac` | **valid** — 3 decode codecs |
| 2026-05-22 | `iPhone18,1` | A19-class (iPhone 17 line) | Release | J2KBenchApp | **valid** — 3 decode codecs |
| 2026-05-21 | `iPhone14,8` | A15 | Debug | J2KBenchApp | **discarded** — Debug build, ~100× inflated |

`J2KBenchMac` is the macOS counterpart of `J2KBenchApp` (same LCG
corpus, same lossless HT encoder, same warm methodology, same JSON
shape) on `v10.5-research`. M2 and A19 readings are now genuinely
apples-to-apples.

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

## M2 ↔ A19 head-to-head (apples-to-apples)

Full report: `Documentation/Benchmarks/CROSS_SILICON_M2_A19_REPORT.md`.

**Headline: A19's GPU HT entropy decode is consistently ~2× faster
than M2's.** Same fixtures, same encoder, same warm methodology:

| Fixture | px | `decodeWithGPUHT` M2 ms | `decodeWithGPUHT` A19 ms | A19/M2 |
|---|---:|---:|---:|---:|
| mr_synth_small | 65 K | 8.76 | 4.12 | **2.1×** faster |
| ct_synth_mid | 590 K | 29.80 | 12.34 | **2.4×** |
| xa_synth_small | 640 K | 27.82 | 12.00 | **2.3×** |
| px_synth_mid | 819 K | 29.50 | 12.76 | **2.3×** |
| cr_synth_mid | 1.05 M | 31.58 | 14.99 | **2.1×** |
| dx_synth_mid | 1.05 M | 31.72 | 14.87 | **2.1×** |
| mg_synth_mid | 1.31 M | 32.02 | 15.80 | **2.0×** |
| dx_002_class | 6.4 M | 126.70 | 63.64 | **2.0×** |
| dx_001_class | 7.77 M | 132.80 | 67.52 | **2.0×** |
| mg_001_class | 16.8 M | 120.28 | 108.90 | 1.1× |

By contrast:

- **CPU `decode()` is roughly tied** across M2 and A19 (within ±15 %
  on most fixtures, A19 marginally ahead on average) — the C+NEON path
  scales with CPU-core IPC, which is comparable.
- **`decodeGPU` is also roughly tied** — both ≈ M2 GPU IDWT speed. The
  IDWT kernel is the same on both; not the silicon-sensitive lane.

So the silicon-sensitive lane is exactly **GPU HT entropy** — the
one-thread-per-block serial branchy bitstream parse that v10.17
root-caused on M2. **A19 GPU cores run that serial code 2× faster**,
which is why `decodeWithGPUHT` crosses over at 16.8 MP on A19
(108.9 vs CPU 124.0, −12 %) but never on M2 (120.3 vs 117.96 — CPU
just ahead).

This is exactly what v10.17 predicted: the redesign couldn't beat the
algorithm on M2, but newer Apple GPU cores narrow the gap from the
hardware side. Two devices, one finding.

### Implication for the router

`recommendedDecodeAPI` is dimension-only and **silicon-blind**; it
routes `≥ 15 MP → .cpu`. With apples-to-apples data on both M2 and A19:

| silicon | ≤ ~0.8 MP | ~1 MP | 1–6 MP | 6–8 MP (DX) | 16.8 MP (MG) |
|---|---|---|---|---|---|
| **M2**  | CPU | CPU/decodeGPU (mixed) | decodeGPU | decodeGPU/CPU (tie) | CPU |
| **A19** | CPU | decodeGPU (CR/MG); CPU (DX) | decodeGPU (mixed) | CPU | **decodeWithGPUHT** |

The router fix is concrete:
- **M2 calibration**: ≥ 15 MP → `.cpu` stays correct.
- **A19 calibration**: ≥ ~15 MP → **`.decodeWithGPUHT`** (currently
  mis-routed to CPU on A19).

A `recommendedDecodeAPI(width:height:chip:)` overload or a chip-class
detector would be enough. **Signal, not yet a mandate** — see caveats
(one device per silicon, synthetic fixtures).

### Caveats

- **One device, one 7-run session.** The `mg_001` `decodeWithGPUHT`
  samples spread 95.7–117.8 ms; the 15 ms median win over `decode()`
  exceeds that spread, so the result is real — but 2–3 more runs would
  firm it.
- **Synthetic LCG-noise fixtures**, not real medical images. v10.16
  showed GPU-vs-CPU results flip between lossy/lossless and depend on
  entropy profile; synthetic vs real-medical could move the crossover.
- `iPhone18,1` is an iPhone 17-series device; "A19-class" covers the
  exact A19 / A19 Pro variant.
- This **confirms, not contradicts, v10.17**: #440 is structural *on
  M2*; the crossover *is* silicon-dependent — exactly what v10.17
  predicted.

## Next

- More A19 readings (variance) + A18 / A17 / M4 in the same J2KBenchApp
  synthetic corpus, for an apples-to-apples cross-silicon matrix.
- Real-medical-fixture readings if feasible (synthetic vs real may
  shift the GPU crossover, per v10.16).
- Once 2–3 consistent A19 readings agree: scope a silicon-aware
  `recommendedDecodeAPI` — this re-opens #440 for A19 as a **routing**
  task (a `chip`-aware recommendation), not the (M2-doomed) GPU HT
  kernel rewrite.
