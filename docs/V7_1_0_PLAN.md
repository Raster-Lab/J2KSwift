# v7.1.0 plan — beat Kakadu (encode + decode)

**Status**: Plan only. No code in this PR. Sign-off on the candidate work items below before any feature PR lands.

**Branch**: `feature/v7.1.0-plan`

**Primary target**: **Beat Kakadu on every medical-corpus fixture.** v7.0.0 (the multi-tile encode default-flip) closed the MR 886² gap (J2KSwift now wins 1.21× ahead). XA / PX / DX still lag by 1.5× / 2.2× / 2.8× behind. v7.1.0 attacks those remaining gaps directly.

**Anchors**:
- [`RELEASE_NOTES_v7.0.0.md`](../RELEASE_NOTES_v7.0.0.md) — v7.0.0 baseline (MR flipped ahead; XA/PX/DX gaps remain)
- [`docs/V6_4_0_PLAN.md`](V6_4_0_PLAN.md) §H + §I + §K — deferred work items that v7.1.0 bundles
- [`docs/V6_4_0_G1_2_INVESTIGATION.md`](V6_4_0_G1_2_INVESTIGATION.md) — SemVer Path 2 decision rationale that produced v7.0.0
- [`docs/V6_3_0_E1_2_INVESTIGATION.md`](V6_3_0_E1_2_INVESTIGATION.md) — Defects A + B blocking GPU multi-tile compute
- [`docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md`](V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md) — approach C / D taxonomy

---

## Where we are vs Kakadu (post-v7.0.0)

| Modality | Shape | px | J2KSwift v7.0.0 | Kakadu | gap | status |
|---|---|---:|---:|---:|---:|---|
| MR-small | 180×180 | 32K | **1.0** | 2.8 | 2.8× ahead | ✅ won at v5.38 |
| CT | 512×512 | 262K | **3.3** | 3.6 | tie | ✅ tied at v5.38 |
| **MR** | **886×886** | **785K** | **3.05** | **3.7** | **1.21× ahead** | **✅ won at v7.0.0** |
| **XA** | **1024×1024** | **1.05M** | **7.86** | **5.1** | **+1.5× behind** | **🎯 v7.1.0 target** |
| **PX** | **2459×1316** | **3.24M** | **24.26** | **11.2** | **+2.2× behind** | **🎯 v7.1.0 target** |
| **DX** | **2800×2288** | **6.41M** | **52.79** | **18.9** | **+2.8× behind** | **🎯 v7.1.0 target** |

**v7.1.0 must close the XA / PX / DX gaps to flip ahead of Kakadu.** Closing all three is ambitious; the trajectory ships incrementally so even partial completion lands shippable wins.

### Where the time goes (DX 2800×2288 encode wall, post-v7.0.0)

Per the multi-tile per-tile load balance (`HTMultiTilePerfProbeTests`):
- **entropy stage: ~45 % of wall** (the dominant lever — historically untouched by GPU offload)
- **DWT stage: ~15 % of wall** (already partially on GPU since v6.1.0; v6.3.0 E2 lowered threshold to 3 MP)
- **codestream / tier-2: ~5 % of wall** (closed by F1 #324 finding; not a worthwhile lever)
- **other (preproc, dequant, etc.): ~5 % of wall** (closed by F3 #326 finding)
- **multi-tile dispatch overhead + content imbalance: ~30 %** (v7.0.0 already captures most of this)

**The entropy stage is the headline attack vector.** Closing 50 % of entropy on DX = ~10 ms saved → DX wall 52.79 → 42 ms → still behind Kakadu 18.9 by 2.2×, but materially closer. Closing 80 % of entropy on DX = ~17 ms → wall 35 ms → 1.85× behind. **Closing entropy + multi-tile compute together = potentially flip ahead.**

---

## Why this plan bundles H + I + K

The original v6.4.0 plan separated H (multi-tile decode compute) and I (GPU forward HT entropy) into independent phases. v7.1.0 **bundles them** because:

1. **v7.0.0 paid the MAJOR-bump cost** — subsequent v7.x MINOR releases don't carry backward-compat tax. Bigger is free in SemVer terms.
2. **Both attack the same product target** (Kakadu gap). Splitting means the consumer sees the combined wins later.
3. **The Kakadu-deadline framing requires bigger releases.** Splitting was conservative; bundling is aggressive — appropriate for the deadline pressure.
4. **Risk-isolation can happen within a single release** — if I-series fails the empirical gate (mirror of v6-alpha6 #305 pattern where approach B regressed), it ships opt-in and v7.1.0's headline carries on H + K. v7.1.0 doesn't depend on I succeeding.

---

## Candidate work items

### H — Multi-tile decode GPU compute correctness (E1.3)

#### H1. Defect A — GPU HT entropy multi-tile coefficient drift

[`docs/V6_3_0_E1_2_INVESTIGATION.md`](V6_3_0_E1_2_INVESTIGATION.md) #Defect A: GPU HT entropy in the per-tile multi-tile context produces coefficients that diff from CPU HT by exactly 32768 (= DC offset for 16-bit) on DX 2800×2288. Single-tile DX 6.4 MP via the same `J2KGPUHTDispatch.decodeBatchGPUResident` API is bit-exact since v5.5.0 — bug is per-tile-shape-specific.

**Phase 0**: Diff per-block GPU vs CPU coefficients on a single failing DX tile. Identify which block(s) drift and by what magnitude. Compare per-tile descriptor sequence against the equivalent single-tile descriptors at the same canvas position.

**Phase 1**: Fix the per-tile invariant. Hypothesis: `outputSampleCount` / `sampleOffsets` arithmetic mis-counts at tile-local subband sizes, OR `bandKb` per-block is image-global where it should be tile-local, OR kernel `missingMSBs` interpretation differs single-tile vs per-tile.

**Gate**: `MultiTileDecodeGPUDefaultOnTests` 12/12 pixel-byte-identical AFTER re-enabling `isGPUPath: true` in `decodeTilePayloadGPU`.

#### H2. Defect B — GPU 5/3 IDWT parity-aware boundary lifting

GPU 5/3 inverse kernel applies boundary lifting assuming canvas origin (0, 0). Multi-tile per-tile invocations with non-zero tile-component canvas origin require parity-aware lifting per **ISO 15444-1 Annex F.4.1.1** that the GPU kernel doesn't implement.

**Phase 0**: Port `J2KDWT2DOptimizer.inverseTransformMultiLevel53`'s parity-aware boundary lifting into a Metal kernel variant. CPU implementation uses `tileOriginX/Y` to switch boundary symmetric extension; GPU kernels need same parameter and branch.

**Phase 1**: Wire new kernel into `applyInverseWaveletTransformGPU` when `isMultiTilePerTile: true` AND `tileOriginX != 0 || tileOriginY != 0`. Tile origin (0, 0) keeps existing kernel.

**Gate**: `HTTileParityMatrixTests` 12/12 self-RT diff = 0 with `isMultiTilePerTile: false` re-enabled in `decodeTilePayloadGPU`.

#### H3. E1.3 closure — re-enable GPU per-tile compute by default

After H1 + H2 land, re-enable `isGPUPath: true` and `isMultiTilePerTile: false` in `decodeTilePayloadGPU`. Multi-tile decode for ≥4 MP fixtures gains the same +37–46 % GPU win single-tile already enjoys.

**Empirical projection**: DX 2800×2288 multi-tile decode gains ~+40 % wall (tracks single-tile envelope). Doesn't directly affect encode wall but closes the decode gap that has lagged since v6.3.0 E1.2 routing widen.

**Risk**: Medium. Defect B requires kernel work; Defect A's root cause is unknown.

### I — GPU forward HT entropy approach C OR D (HEADLINE LEVER)

This is **the biggest direct attack on the Kakadu encode gap**. Entropy is ~45 % of DX wall; offloading even half to GPU saves 10+ ms on DX.

#### I1. Approach C — three-pass GPU pipeline (classify + prefix-sum + byte-write)

Per [`docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md`](V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md) §4 approach C: classify on GPU → bit-budget prefix-sum on GPU → byte-write on GPU with per-block correction for 0xFF byte stuffing. Estimated **~35–40 % wall reduction on DX entropy** if the correction pass is fast.

**Phase 0**: Design doc — flesh out the prefix-sum kernel (which Metal primitive: `MPSScan`? hand-rolled per-warp scan? two-level scan for >32 K elements?), the bit-write kernel, and the 0xFF correction pass logic. The correction is the high-risk part: 0xFF bytes mid-stream require post-byte stuffing that breaks naive parallel writes.

**Phase 1**: Implement classify + prefix-sum kernels. Reuse approach B's classifier from [#304](https://github.com/Raster-Lab/J2KSwift/pull/304); add prefix-sum to compute per-block byte offsets.

**Phase 2**: Implement byte-write kernel. Output goes directly to a GPU codeblock buffer the CPU reads back at the end of entropy.

**Phase 3**: Implement 0xFF correction pass — either a second GPU dispatch that scans for 0xFF runs and inserts stuff bytes, or a CPU fix-up that scans the readback buffer.

**Phase 4**: Wire through `applyEntropyCodingHTJ2KFused` behind `_gpuForwardHTEntropyEnabled` (already plumbed from v6-alpha6). Telemetry mirror of approach B.

**Gate**: every phase ships bit-exact codestream bytes vs CPU encoder; corpus 6/6 byte-identical; cross-codec 21/21.

**Decision point** at end of Phase 4: corpus A/B wall time. **If DX wall reduction ≥ 15 %, ship default-on with threshold gate**. Otherwise: ship opt-in (mirror approach B's [#305](https://github.com/Raster-Lab/J2KSwift/pull/305) path) and v7.1.0's headline carries on H + K only.

#### I2. Approach D — per-warp/threadgroup serial fallback

Only activated if approach C fails the Phase 4 decision gate. Approach D uses SIMD-group serial within block (32-wide groups), needing careful threadgroup bit-state management. Estimated ~25–35 % wall reduction.

If both C and D regress on M2, defer to a future v7.x MINOR with cross-device retesting (M3/M4/M4 Pro/M4 Max may shift dispatch latency floor enough to flip).

**Risk**: HIGH. v6-alpha6 approach B regressed -200 % at every corpus scale ([#305](https://github.com/Raster-Lab/J2KSwift/pull/305)). C + D are unexplored but face the same fundamental dispatch + readback latency floor that defeated B. Apple M2 dispatch overhead is the suspected cause.

### K — Multi-tile per-tile warm-session hardening

#### K1. Pre-warmed `J2KMetalSession.processShared` for multi-tile dispatch

v6.2.0 D3 (#316) plumbed `processShared` through `decode(_:)`. v6.3.0 F2 (#323) plumbed it through `decodeGPU(_:)` / `decodeWithGPUHT(_:)` no-session overloads. K1 closes the last cold-start path: **multi-tile per-tile dispatch within `decodeMultiTileGPU`**. Once H closes, per-tile dispatch should explicitly reuse the warm singleton — already partially in place via `metalSession` plumbing; this is hardening for the H1+H2 followup.

**Risk**: Low. Mirror of D3 / F2 patterns.

---

## Phase trajectory (proposed, Path B bundle)

| phase | scope | branch | gate |
|---|---|---|---|
| **Plan** (this PR) | Doc + scope sign-off | `feature/v7.1.0-plan` | sign-off |
| **H1.0** | Defect A — Phase 0 root-cause (per-block GPU vs CPU coefficient diff) | `feature/v7.1.0-multi-tile-gpu-ht-entropy-investigation` | doc + repro |
| **H1.1** | Defect A fix — per-tile invariant patched | `feature/v7.1.0-multi-tile-gpu-ht-entropy-fix` | `MultiTileDecodeGPUDefaultOnTests` 12/12 with `isGPUPath: true` |
| **H2.0** | Defect B — GPU 5/3 IDWT parity-aware kernel design | `feature/v7.1.0-gpu-idwt-parity-aware-design` | kernel design doc |
| **H2.1** | Defect B kernel + wire-in | `feature/v7.1.0-gpu-idwt-parity-aware` | `HTTileParityMatrixTests` 12/12 with `isMultiTilePerTile: false` |
| **H3** | Re-enable GPU multi-tile compute by default | `feature/v7.1.0-multi-tile-gpu-compute-default-on` | corpus decode A/B |
| **K1** | Multi-tile per-tile warm-session hardening | `feature/v7.1.0-multi-tile-warm-session` | bit-exact + telemetry |
| **I1.0** | GPU forward HT entropy approach C — Phase 0 design + prefix-sum spike | `feature/v7.1.0-gpu-fwd-ht-entropy-c-design` | doc + isolated kernel benchmarks |
| **I1.1** | Approach C — classify + prefix-sum kernels | `feature/v7.1.0-gpu-fwd-ht-entropy-c-prefix` | unit-tested kernels |
| **I1.2** | Approach C — byte-write kernel | `feature/v7.1.0-gpu-fwd-ht-entropy-c-bytewrite` | bit-exact bytes vs CPU |
| **I1.3** | Approach C — 0xFF correction pass + orchestrator | `feature/v7.1.0-gpu-fwd-ht-entropy-c-orchestrator` | corpus A/B; ≥ 15 % DX wall reduction → default-on, else opt-in |
| **I2** | Approach D fallback (only if I1.3 regresses) | `feature/v7.1.0-gpu-fwd-ht-entropy-d` | bit-exact + corpus A/B |
| **Release v7.1.0** | RC + tag | `v7.1.0-release-candidate` | RELEASING.md flow |

**Sequence**: H first (lowest-risk; restores deferred decode wins), K next (low-risk hardening), I last (high-risk; if it lands, v7.1.0 closes XA/PX gaps and dents DX). If I-series fails the decision gate, ship opt-in and v7.1.0 still carries H + K.

---

## Headline projection — beat-Kakadu scenarios

### Scenario A — H + K land; I-series regresses (conservative)

| Modality | v7.0.0 wall | + H delta (decode-side) | + K delta | post-v7.1.0 encode | post-v7.1.0 decode | Kakadu encode | Kakadu beat? |
|---|---:|---:|---:|---:|---:|---:|---|
| MR | 3.05 | (decode +40 %) | — | 3.05 | improved | 3.7 | ✅ already (1.21×) |
| XA | 7.86 | (decode +40 %) | — | 7.86 | improved | 5.1 | ❌ still 1.5× behind |
| PX | 24.26 | (decode +40 %) | — | 24.26 | improved | 11.2 | ❌ still 2.2× behind |
| DX | 52.79 | (decode +40 %) | — | 52.79 | improved | 18.9 | ❌ still 2.8× behind |

Scenario A doesn't move the **encode** Kakadu-beat needle. It restores deferred decode wins (real product value) but leaves the encode gap intact.

### Scenario B — H + K + I-series approach C lands ≥ 35 % entropy reduction (target)

DX entropy = ~45 % of wall = ~24 ms. 35 % reduction = -8 ms → DX wall 52.79 → ~45 ms.

| Modality | v7.0.0 wall | + I-series (encode) | + H (decode) | post-v7.1.0 encode | Kakadu encode | Kakadu beat? |
|---|---:|---:|---:|---:|---:|---|
| MR | 3.05 | minor (entropy small at small fixtures) | improved | ~3.0 | 3.7 | ✅ stays (1.23×) |
| XA | 7.86 | -1.5 ms (entropy ~5 ms) | improved | ~6.4 | 5.1 | ❌ still 1.25× behind |
| PX | 24.26 | -7 ms (entropy ~20 ms) | improved | ~17 | 11.2 | ❌ still 1.5× behind |
| DX | 52.79 | -8 ms | improved | ~45 | 18.9 | ❌ still 2.4× behind |

Scenario B **dents the gap meaningfully** but doesn't beat Kakadu on PX/DX. The architectural per-block-buffer elimination (J / v7.2.0+ scope) is the next lever after I-series.

### Scenario C — I-series approach C lands +50 % entropy reduction (stretch)

DX entropy 24 ms × 50 % = -12 ms saved. DX wall 52.79 → ~41 ms.

| Modality | post-v7.1.0 encode | Kakadu encode | Kakadu beat? |
|---|---:|---:|---|
| MR | ~3.0 | 3.7 | ✅ ahead |
| XA | ~5.5 | 5.1 | ⚠️ tie / slightly behind |
| PX | ~13 | 11.2 | ❌ still 1.16× behind (close) |
| DX | ~41 | 18.9 | ❌ 2.2× behind |

Scenario C closes the XA gap (tie), narrows PX significantly (1.16× behind), still leaves DX. Beating Kakadu on **DX specifically** likely requires the v7.2.0+ architectural lever (J — per-block-buffer elimination) or cross-device GPU retest (M3+ may flip the dispatch curve).

**For the Kakadu deadline scope**: Scenario C is the realistic v7.1.0 target. It flips XA to tie, narrows PX to within a single optimization round of beating, and leaves DX as the v7.2.0 headline.

---

## Decision gate before H1.0 lands

Confirm one of:

- **"Go by your recommendation"** — start with **H1.0** (Defect A Phase 0 root-cause investigation). H is lowest-risk; closes deferred decode wins. Chain H → K → I. If I-series fails decision gate, ship opt-in and v7.1.0's headline carries on H + K.
- **Reorder to I first** — retire the high-risk gamble early. If I lands a win, H + K wins compound; if I fails, defer to v7.2.0 and v7.1.0 ships H + K only.
- **Cap to H + K only** — defer I-series to v7.2.0; v7.1.0 closes the deferred decode wins without the entropy gamble.
- **Add work item not listed** — propose.

---

## What v7.1.0 explicitly does NOT plan

- **CPU-only single-thread micro-optimisations** — locked out by `feedback_v6_alpha4_lever_ceiling.md`.
- **Lossy work** — out of scope per `feedback_lossless_only_v5_38.md`.
- **Cross-device threshold re-tuning** — needs M3+ hardware not currently available.
- **DICOM encapsulation validation** — overdue per `project_v5_35_scope.md` but correctness work, not perf.
- **JP3D / volumetric** — feature gap, not Kakadu-encode-wall lever.
- **J — Tier-1 architectural per-block-buffer elimination** — v7.2.0+ scope; the biggest theoretical lever after I but v7-scale architectural refactor.

---

## v-series arc summary so far

| version | shipped | DX encode win | DX decode win | Kakadu DX gap |
|---|---|---:|---:|---:|
| v5.38.0 | lossless medical archival baseline | — | — | 3.81× behind |
| v6.0.0 | `.auto` multi-tile production-default + opt-in GPU forward DWT | encode 1.3× | — | ~3.0× |
| v6.1.0 | GPU forward DWT default-on for ≥4 MP | encode +21.3 % | — | ~2.9× |
| v6.2.0 | GPU iDWT + GPU HT entropy default-on for ≥4 MP single-tile | — | decode +46.2 % | ~2.9× (encode); decode caught up |
| v6.3.0 | Multi-tile decode correctness + threshold 4 MP → 3 MP | encode +10.9 % (PX); +17.4 % (DX) | — | ~3.0× |
| v7.0.0 | Multi-tile encode default-flip | encode +6 % (DX); MR flipped 1.21× ahead | — | ~2.8× |
| **v7.1.0** | **H (E1.3 GPU multi-tile compute) + I (GPU forward HT entropy approach C) + K (warm-session hardening)** | **TBD — projection: encode -10 to -25 % on DX if I lands** | **+37-46 % decode multi-tile (H closes)** | **target: 1.5–2.0× on DX, tie or win XA, 1.0–1.2× PX** |

**Beating Kakadu fully on DX likely requires v7.2.0 architectural work (J).** v7.1.0's realistic target is "all corpus fixtures within 2× Kakadu encode-wall" + "decode multi-tile fully GPU-accelerated".
