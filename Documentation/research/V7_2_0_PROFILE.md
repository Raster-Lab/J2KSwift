# v7.2.0 — Phase 0 Profile

**Captured**: 2026-05-08, Apple M2, release builds, median of 5 runs unless noted.

This document is the Phase-0 deliverable of the v7.2.0 plan. It establishes the per-stage and UMA-counter baseline that every subsequent v7.2.0 PR measures itself against.

---

## 0. Pre-Phase-0 fix shipped here

The decode-side stage profile test (`DecodeStageProfileLosslessCorpusTests`) reported **all-zero stage timings** for fixtures ≥ 500K pixels (MR/XA/PX/DX) because the multi-tile per-tile decode functions `decodeTilePayload` and `decodeTilePayloadGPU` had no `J2KDecodeTimings.record*` calls. Single-tile paths (`decodeSingleTile` / `decodeSingleTileGPU`) did have the recordings, which is why MR-small (32K) and CT (262K) reported correctly — those fixtures encode as single-tile.

This Phase 0 PR adds the missing recordings to both per-tile functions, mirroring the existing single-tile pattern. Stage timings are now process-global accumulators across parallel tiles (CPU-time semantics, identical to the encode-side profile).

---

## 1. Decode stage breakdown (lossless 5/3 HT-conformant, default routing)

```
Encoder: J2KEncoder default config → J2KEncodeTilePlanner.auto layout
Decoder: J2KDecoder().decode(_:)
```

| Fixture | px | total ms | extract | entropy | (gpuHT) | dequant | iDWT | dcShift | sum (CPU-time) | accounted % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32K | 0.68 | 0.04 | 0.33 | 0.00 | 0.02 | 0.15 | 0.03 | 0.58 | 84% |
| CT 512² | 262K | 3.03 | 0.09 | 1.44 | 0.00 | 0.02 | 0.98 | 0.13 | 2.84 | 94% |
| MR 886² | 785K | 5.38 | 0.30 | 3.35 | 0.00 | 0.15 | 9.23 | 0.11 | 13.14 | **244%** |
| XA 1024² | 1.05M | 8.94 | 0.47 | 15.70 | 0.00 | 0.17 | 9.46 | 0.16 | 25.95 | **290%** |
| **PX 2459×1316** | **3.24M** | **32.16** | 3.30 | **105.67** | 0.00 | 2.93 | **69.77** | 0.60 | 182.28 | **567%** |
| **DX 2800×2288** | **6.41M** | **59.23** | 5.32 | **209.20** | 0.00 | 4.26 | **113.95** | 1.37 | 334.09 | **564%** |

The `> 100% accounted %` rows are multi-tile fixtures (per `J2KEncodeTilePlanner.auto`: ≥3M → 4x4, 500K-3M → 2x2, < 500K → single). Stage times are CPU-time accumulated across parallel tiles. Wall-time per stage = CPU-time / parallelism factor.

### Decode stage % of CPU-time on DX 2800×2288 (the wedge map)

| stage | CPU-time ms | % of decode CPU work | % of decode wall (est, /5.6×) |
|---|---:|---:|---:|
| **entropy** | **209.20** | **62.6%** | **~37 ms wall (~63%)** |
| iDWT | 113.95 | 34.1% | ~20 ms wall (~34%) |
| extract | 5.32 | 1.6% | ~1 ms |
| dequant | 4.26 | 1.3% | ~1 ms |
| dcShift | 1.37 | 0.4% | ~0 ms |

(`gpuHT` sub-stage is 0 because no GPU entropy fires on the default path for these fixtures — see § UMA.)

**Read**: closing the 2.7× Kakadu decode gap on DX is **dominantly an entropy-stage problem**. A 50% reduction in entropy CPU-work translates to ~18 ms wall reduction on DX (59 → 41 ms, gap 2.7× → 1.7×).

---

## 2. Encode stage breakdown (same routing)

| Fixture | px | total ms | preproc | DWT | entropy | rateCtrl | codestream | sum CPU-time | accounted % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32K | 0.90 | 0.01 | 0.32 | 0.35 | 0.00 | 0.17 | 0.86 | 95% |
| CT 512² | 262K | 3.22 | 0.07 | 1.16 | 1.64 | 0.00 | 0.30 | 3.17 | 98% |
| MR 886² | 785K | 2.81 | 0.34 | 4.77 | 3.45 | 0.02 | 0.89 | 9.46 | **337%** |
| XA 1024² | 1.05M | 7.80 | 0.54 | 12.72 | 11.13 | 0.03 | 0.98 | 25.39 | **325%** |
| **PX 2459×1316** | **3.24M** | **23.66** | 3.08 | **155.34** | **89.91** | 0.15 | 5.94 | 254.44 | **1075%** |
| **DX 2800×2288** | **6.41M** | **51.44** | 8.06 | **326.16** | **299.77** | 0.29 | 10.56 | 644.85 | **1254%** |

### Encode stage % of CPU-time on DX 2800×2288

| stage | CPU-time ms | % of encode CPU work | % of encode wall (est, /12.5×) |
|---|---:|---:|---:|
| **DWT** | **326.16** | **50.6%** | **~26 ms wall (~50%)** |
| **entropy** | **299.77** | **46.5%** | **~24 ms wall (~46%)** |
| codestream | 10.56 | 1.6% | ~1 ms |
| preproc | 8.06 | 1.3% | ~1 ms |

**Read**: the DX encode gap is split roughly **50/50 between DWT and entropy**. A single-stage win lifts at most ~50% of the gap; both stages need attention to close 2.6×.

---

## 3. UMA counter baseline (per-fixture, warm session, single-run)

```
Pre-warm: J2KMetalSession.processShared.preWarm()
Decoder:  J2KDecoder().decode(_:)
Encoder:  J2KEncoder.encode(_:)
```

### 3a. Default routing (multi-tile-auto encodes)

| Fixture | px | enc memcpy | enc contents | enc makeBuf | dec memcpy | dec contents | dec makeBuf |
|---|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32K | 0 | 0 | 0 | 0 | 0 | 0 |
| CT 512² | 262K | 0 | 0 | 0 | 0 | 0 | 0 |
| MR 886² | 785K | 0 | 0 | 0 | 0 | 0 | 0 |
| XA 1024² | 1.05M | 0 | 0 | 0 | 0 | 0 | 0 |
| PX 2459×1316 | 3.24M | 0 | 0 | 0 | 0 | 0 | 0 |
| DX 2800×2288 | 6.41M | 0 | 0 | 0 | 0 | 0 | 0 |

**All zeros**. No GPU work fires at all for any corpus fixture on default routing. Reason chain:

- MR-small / CT / MR / XA / PX: pixel count < `_gpuInverse53PixelThreshold = 4 000 000` → routes to `decodeMultiTile` / `decodeSingleTile` (CPU-only paths).
- DX 6.41M ≥ 4M → routes to `decodeMultiTileGPU` → `decodeTilePayloadGPU`. Inside that path:
  - GPU entropy gated on `perTilePixels ≥ _gpuHTEntropyMultiTilePerTilePixelThreshold = 1 048 576`. DX 4x4 layout = 700×572 = ~400 K per tile → **CPU entropy fallback** (v7.1.1 hotfix behaviour).
  - Multi-tile per-tile IDWT unconditionally routes to CPU per the v6.3.0 E1.2 deferred work.

**Net**: every default-path decode is fully CPU. The GPU paths are dead code on the typical caller's workload.

### 3b. Forced single-tile encodes (`J2K_HT_TILE_MODE=single`)

| Fixture | px | enc memcpy | enc contents | enc makeBuf | dec memcpy | dec contents | dec makeBuf |
|---|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32K | 0 | 0 | 0 | 0 | 0 | 0 |
| CT 512² | 262K | 0 | 0 | 0 | 0 | 0 | 0 |
| MR 886² | 785K | 0 | 0 | 0 | 0 | 0 | 0 |
| XA 1024² | 1.05M | 0 | 0 | 0 | 0 | 0 | 0 |
| **PX 2459×1316** | **3.24M** | **20** | **20** | 0 | 0 | 0 | 0 |
| **DX 2800×2288** | **6.41M** | **20** | **20** | 0 | **1** | **1** | 0 |

In single-tile mode, only DX hits the decoder GPU IDWT (≥ 4M threshold) → 1 memcpy boundary per decode. Encoder GPU forward DWT fires for both PX and DX → 20 memcpy boundaries per encode (size-independent — fixed at 20 regardless of fixture).

`makeBufferCount = 0` everywhere → the v5.11 MTLHeap pool is fully serving the warm-session workload (Phase B already at target).

---

## 4. Plan revision based on Phase 0 findings (Option 3)

The original v7.2.0 plan estimated "4 readback sites × cumulative 25-40 % DX decode reduction" from UMA decode-boundary elimination. Phase 0 disproves that wedge: on the default decode path, **0 UMA boundaries fire** because GPU paths are gated off for every corpus fixture. Even on the single-tile-forced path, only 1 boundary fires on DX.

The actual wedges are:

| wedge | size | shape |
|---|---|---|
| **DX decode entropy** | ~37 ms wall (62.6 % of CPU work) | Need to widen GPU HT entropy routing to fire on the multi-tile-auto default path. Currently gated off because per-tile pixels (400 K) < 1 MP threshold |
| **DX decode IDWT** | ~20 ms wall (34.1 % of CPU work) | Multi-tile per-tile GPU IDWT was deferred in v6.3.0 E1.2; v7.2 wires it (parallel work to H2/H2.2/H3 from v7.1.0) |
| **PX/DX encode UMA** | 20 memcpy boundaries per encode | Eliminate via `J2KMetalSharedBufferView<T>` pattern from the original plan (encoder side rather than decoder) |
| **DX encode DWT** | ~26 ms wall (50.6 % of CPU work) | Already on GPU (forward DWT GPU); gap is intra-stage. Likely needs SIMD audit / Pass-3-style batched dispatch |
| **DX encode entropy** | ~24 ms wall (46.5 % of CPU work) | Forward HT entropy on GPU? Currently mostly CPU. Bigger architectural lift. |

Per user direction (Option 3), v7.2.0 scope is now:

### Revised v7.2.0 phase structure

- **Phase 0**: Profile + decoder instrumentation fix. ✅ This PR.
- **Phase A — Encode-side UMA elimination**: 20 → 0 memcpy boundaries on encode. Original plan's `J2KMetalSharedBufferView<T>` template, applied to encode-side sites identified via `incrementContents()` audit (not yet enumerated — Phase A1 first action is the audit).
- **Phase E — Decode entropy GPU routing widening**: Lower `_gpuHTEntropyMultiTilePerTilePixelThreshold` from 1 MP → ~256 K to fire on DX 4x4 (400 K/tile), AND wire multi-tile per-tile GPU IDWT (v6.3.0 E1.2 deferred work). Each is its own PR. Bit-exact gate enforced.
- **Phase B — BufferPool warmth + lifetime hardening**: Already at target on warm path (`makeBufferCount = 0`). Scope reduces to "extend `MultiTilePerTileWarmSessionHardeningTests` to encoder + add 100-decode lifetime test." 1 PR.
- **Phase C — CLI per-invocation overhead**: Unchanged. ~50 ms per-invocation gap inside `j2k` binary.
- **Phase D — Stage-specific SIMD**: Conditional. Only fires if A+E don't close DX to ≤ 1.6× of Kakadu.
- **Phase Z — Release v7.2.0**.

### Updated success criterion

DX decode 65.6 → ≤ 40 ms (≥ 1.65× improvement, gap 2.7× → 1.65×). Phase E carries the load on this — the entropy + IDWT routing fixes together address ~96 % of DX decode CPU-time.

DX encode 54.8 → ≤ 35 ms (≥ 1.55× improvement, gap 2.6× → 1.65×). Phase A (UMA encode 20 → 0) + Phase D conditional carry this.

---

## 5. Reproduction

```bash
# Decoder + encoder stage profile
swift test -c release --filter "DecodeStageProfileLosslessCorpusTests|EncodeStageProfileLosslessCorpusTests"

# UMA counter baseline (default routing)
swift test -c release --filter testUMABaseline_LosslessCorpus_v720Phase0

# UMA counter baseline (forced single-tile, exposes GPU paths)
J2K_HT_TILE_MODE=single swift test -c release --filter testUMABaseline_LosslessCorpus_v720Phase0
```
