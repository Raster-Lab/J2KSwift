# v10.8-research — DX/PX residual Kakadu gap probe

**Date**: 2026-05-20
**Branch**: `v10.8-research`
**Status**: **CLOSED — WASH (12th lever-ceiling confirmation on M2 + Swift release)**
**Recommendation**: pivot to cross-silicon positioning or product-layer wins

---

## TL;DR

After v10.3.0 shipped MG mammography tied with Kakadu on M2 (1.01-1.08× via the
two default-flips), the user pushed for closing the remaining residual gap:

| Fixture | J2KSwift v10.3.0 ms | Kakadu ms | gap | ms to close |
|---|---:|---:|---:|---:|
| DX 2800×2288   | ~48 | ~39 | **1.23×** | **−9 ms** |
| DX large 2544×3056 | ~57 | ~38 | **1.50×** | **−19 ms** |
| PX 2459×1316   | ~26 | ~20 | **1.30×** | **−6 ms** |
| PX large 2812×1316 | ~28 | ~20 | **1.40×** | **−8 ms** |

Two angles probed:

1. **decode() vs decodeGPU() routing** (Phase 2): does the
   `_gpuInverse53PixelThreshold = 4_000_000` keep PX (3.24-3.7 MP) on the
   slower CPU IDWT when GPU IDWT would help?
2. **Multi-tile encode for DX/PX** (Phase 3): does encoding DX/PX with 2×2
   tiling produce a faster decode (same way the v9.6 MG-only 2×2 override
   helped MG)?

**Both close as wash on every DX/PX fixture (Δ within ±0.6 ms)**. The v10.3.0
gains exposed a *negative* lever (a stale flag default that was hurting MG);
no symmetric finding exists on the DX/PX single-tile path. The 1.05-1.5×
residual is structural on M2 + Swift release.

---

## Phase 2 result — `decode()` vs `decodeGPU()` (10 trials, M2 release)

| Fixture | px | decode() med | decodeGPU med | Δ med | frac GPU wins |
|---|---:|---:|---:|---:|---:|
| CT 512² | 262K | 2.46 | 2.86 | −0.38 | 0% |
| XA 1024² | 1.05M | 6.83 | 6.94 | 0.00 | 40% |
| PX 2459×1316 | 3.24M | 26.89 | 26.91 | −0.15 | 40% |
| PX mid 2793×1316 | 3.68M | 28.04 | 28.27 | +0.06 | 50% |
| PX large 2812×1316 | 3.70M | 28.48 | 28.71 | −0.06 | 40% |
| DX small 2224×2798 | 6.22M | 45.31 | 45.63 | +0.04 | 50% |
| DX 2800×2288 | 6.40M | 47.95 | 48.17 | −0.23 | 40% |
| DX large 2544×3056 | 7.77M | 56.92 | 57.37 | +0.40 | 70% |

**Verdict**: `_gpuInverse53PixelThreshold = 4 MP` is NOT a stale default.
Lowering it to cover PX would not produce a meaningful win. The two paths
are effectively equivalent at PX/DX scale because the GPU IDWT dispatch
overhead amortises only marginally below 4 MP and not at all at the
~6-8 MP DX class (already on GPU IDWT).

## Phase 3 result — single-tile vs 2×2 tile encode (10 trials, M2 release)

| Fixture | px | single-tile ms | 2×2 ms | Δ ms | speedup |
|---|---:|---:|---:|---:|---:|
| PX 2459×1316 | 3.24M | 26.45 | 26.09 | +0.36 | 1.01× |
| PX large 2812×1316 | 3.70M | 28.39 | 27.83 | +0.56 | 1.02× |
| DX 2800×2288 | 6.40M | 47.25 | 47.01 | +0.24 | 1.01× |
| DX large 2544×3056 | 7.77M | 56.14 | 56.15 | −0.01 | 1.00× |

**Verdict**: 2×2 multi-tile encode produces wash on DX/PX (Δ ≤ 0.56 ms).
The v9.6 MG-only override doesn't generalise downward — MG-class
(16.8 MP, 2400+ min dim) benefited because each tile crossed both the
3 MP IDWT-routing threshold AND the 1 MP entropy-batching threshold,
giving 4× parallelism on a load that was already saturating cores.
DX/PX-class tiles (~2 MP each in 2×2) fall below the IDWT routing
threshold and don't gain enough from the entropy parallelism to
offset multi-tile encoder/decoder overhead.

## Phase 3 supplementary — stage profile on v10.3.0 baseline

`DecodeStageProfileLosslessCorpusTests` (M2 release, median of 5):

| Fixture | total | extract | entropy(cum) | dequant | iDWT(cum) |
|---|---:|---:|---:|---:|---:|
| PX 2459×1316 | 26.29 | 4.01 | 55.25 | 5.20 | 69.11 |
| DX 2800×2288 | 46.61 | 6.48 | 113.49 | 6.20 | 107.19 |

Entropy and iDWT cumulative times are roughly equal — neither is the
single dominant target. extract + dequant add another 10-12 ms cumulative
each (substantial). There is no single-stage wedge of >50% that an
optimization could halve to close a 9-19 ms wall gap.

---

## Why no v10.7-style negative lever exists here

The v10.7 finding (`_gpuHTEntropyEnabled` regressing MG) worked because:

1. A flag default was set in v6.2.0 D4 when the CPU side was much slower.
2. The codec evolved (v10.0.0 NEON HT default-on) making the CPU side faster.
3. The flag's premise (GPU HT wins) no longer held but it stayed default-on.

For DX/PX single-tile decode, there is no equivalent flag with a similar
"set long ago, evolved out from under it" story:

- `_gpuInverse53Enabled = true` (default since v6.2.0 D4) — verified
  empirically equivalent to forcing CPU at DX/PX scale.
- `_multiTileBatchedEntropyEnabled` — only fires on multi-tile; irrelevant
  for single-tile DX/PX.
- NEON HT decoder (default ON since v10.0.0) — verified competitive
  (v10.6-research confirmed Clang auto-vectorisation matches/beats
  hand-written SIMD).

The single-tile decode path's per-stage walls are dominated by
**inherently sequential** work: per-block HT entropy decode (state
machines), GPU IDWT (already tiled + threadgroup-memory optimised in
v10.1.0), CPU dequant (already vDSP). All have had recent optimization
passes within their structural envelopes.

---

## Strategic recommendation

The DX/PX residual gap on M2 is **structural**, not a stale flag. After
12 confirmations (11 wash + 1 reversal) the credible paths forward are
NOT more codec-hot-path tuning:

1. **Cross-silicon positioning** (`feedback_apple_only_v8.md`):
   M4 already wins broadly per `CROSS_HOST_M2_M4_v10_1_0_inproc.md`.
   The marketable claim "fastest JPEG 2000 codec on Apple Silicon" works
   today using M4 baselines.
2. **DICOMKit / product-layer wins**: J2KSwift in DICOM workflows can
   skip overhead Kakadu CLI pays (process spawn, file I/O,
   DICOM-encapsulation parsing). The cross-codec bench is apples-to-apples
   on raw J2K codestreams; the user-facing workflow benchmark looks
   different.
3. **Re-encoding strategy** (encoder change, MAJOR scope): for J2KSwift-
   produced codestreams, customer DICOM workflow could choose tile /
   precinct / code-block parameters tuned for our decode path. Doesn't
   help when consuming third-party codestreams.

The v10.3.0 release achieved the user's "beat Kakadu" goal on MG
mammography (the highest-stakes medical class). The remaining 1.05-1.5×
gap on DX/PX is the structural floor on M2.

---

## Files added

- `Tests/J2KMetalTests/V10_8_DecodeVsDecodeGPUOnDXPXTests.swift`
- `Tests/J2KMetalTests/V10_8_DXPXMultiTileProbeTests.swift`
- `Documentation/research/V10_8_DXPX_GAP_FINDING.md` (this file)

**Not landing on `main`**: research-only. No production routing change
recommended. The v10.3.0 release captures the achievable M2 win.
