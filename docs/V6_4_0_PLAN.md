# v6.4.0 plan — closing the Kakadu encode gap

**Status**: Plan only. No code in this PR. Sign-off on the candidate work items below before any feature PR lands.

**Branch**: `feature/v6.4.0-plan`

**Theme**: **Aggressive scope to close the J2KSwift → Kakadu encode gap on the medical corpus.** The user has signalled a Kakadu-deadline-driven push — v6.4.0 takes on the hard high-upside work that v6.0 → v6.3 deliberately deferred (multi-tile parallelism + GPU entropy + multi-tile compute correctness). Some phases are high-risk; the trajectory is structured so even partial completion ships shippable wins.

**Anchors**:
- [`RELEASING.md`](../RELEASING.md) "Release scope expectations" — every minor / major release ships HTJ2K + general-J2K perf work
- [`MEDICAL_BENCHMARK_V6.md`](../MEDICAL_BENCHMARK_V6.md) — current Kakadu gap measurements (HT-fair table, v5.38 baseline)
- [`docs/V6_3_0_E1_2_INVESTIGATION.md`](V6_3_0_E1_2_INVESTIGATION.md) — Defects A + B blocking multi-tile GPU compute
- [`docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md`](V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md) — GPU forward HT entropy approach taxonomy (B closed as regression in [#305](https://github.com/Raster-Lab/J2KSwift/pull/305); E washed in [#306](https://github.com/Raster-Lab/J2KSwift/pull/306); **C and D unexplored**)

---

## Where we are vs Kakadu (post-v6.3.0)

Format-fair HT-conformant lossless 5/3 wall time on the medical corpus, Apple M2 release mode. Numbers source: [`MEDICAL_BENCHMARK_V6.md`](../MEDICAL_BENCHMARK_V6.md) v5.38 HT-fair table + v6.1.0–v6.3.0 deltas projected forward.

### Encode (ms)

| Modality | Shape | J2KSwift v5.38 | J2KSwift v6.3.0 (est.) | Kakadu | v6.3 gap |
|---|---|---:|---:|---:|---:|
| MR-small | 180×180   |  1.0 |  1.0 |  2.8 | **we win 2.8×** |
| CT       | 512×512   |  3.3 |  3.3 |  3.6 | tie |
| MR       | 886×886   |  5.9 |  5.9 |  3.7 | +1.6× behind |
| XA       | 1024×1024 | 11.5 | 11.5 |  5.1 | +2.3× behind |
| **PX**   | **2459×1316** | **38.6** | **31.0** (E2 +18%) |  **11.2** | **+2.8× behind** |
| **DX**   | **2800×2288** | **72.1** | **57.7** (E1+E2 ~20%) | **18.9** | **+3.0× behind** |

### Decode (ms) — single-tile, post-v6.2.0

| Modality | J2KSwift v6.3.0 | Kakadu | gap |
|---|---:|---:|---:|
| MR 886²  |  ~6.0 |  4.9 | +1.2× |
| **DX 2800×2288** | **~38** | **~17** | **+2.2×** |

**The Kakadu encode gap on PX + DX is the headline lever for v6.4.0.** Decode is in-spec everywhere except at high-end DX where Kakadu's SIMD edge persists; v6.4.0 pushes harder there too via E1.3 multi-tile compute.

### What v6.0 → v6.3 already shipped
- v6.0.0: `.auto` multi-tile (single-tile production-default, opt-in GPU forward DWT)
- v6.1.0: GPU forward DWT default-on for ≥4 MP — DX encode +21.3 %
- v6.2.0: GPU iDWT + GPU HT entropy decode default-on for ≥4 MP single-tile — DX decode +46.2 %
- v6.3.0: Multi-tile decode correctness (routing widen + bit-exact gate); GPU forward DWT threshold 4 MP → 3 MP (PX encode +10.9 %)

### What's still on the table
The v6-alpha4 lever-ceiling memory (`feedback_v6_alpha4_lever_ceiling.md`) settled this: **CPU-only single-thread micro-optimisations have hit their ceiling on Apple M2 + Swift release + macOS.** The remaining levers are all parallelism + GPU + architectural:

1. **Multi-tile encode parallelism** — was -28% to -35% encode WIN at v5.39 M4 / v6-alpha1; discarded when wrap-and-stitch was replaced by native multi-tile because per-tile parallelism wasn't refactored along with it
2. **Multi-tile decode GPU compute correctness** — Defects A + B blocking the +46% wins on multi-tile fixtures
3. **GPU forward HT entropy approach C / D** — unexplored. Approach B regressed -200% in [#305](https://github.com/Raster-Lab/J2KSwift/pull/305); approach E washed in [#306](https://github.com/Raster-Lab/J2KSwift/pull/306). C and D are high-upside untried.
4. **Tier-1 architectural: per-block intermediate buffer elimination** — write directly to codestream pool during entropy. v7-scale refactor flagged in F1 (#324) as the only remaining tier-1 lever.

---

## Why this plan

v6.4.0 is the first release where the lever-ceiling memory's "structural Kakadu gap" claim is being **directly retested** — not by retrying CPU levers, but by attacking the dimensions CPU optimization can't reach: parallelism across tiles, GPU offload of the correct stage (entropy), and the multi-tile GPU compute fix that v6.3.0 deferred. The deadline pressure justifies bundling these into one release rather than spreading across v6.4 / v6.5 / v6.6.

The plan also acknowledges that **some phases will fail empirically** (approach C is high-risk like B was) and structures the trajectory so even a failed-spike phase can ship as opt-in / data-only. v6-alpha6's pattern (#305 approach B shipped opt-in despite regression for cross-device retesting) carries forward.

---

## Candidate work items

### G. Multi-tile encode parallelism (HIGH-CONFIDENCE WIN)

#### G1. Native multi-tile encoder per-tile parallelism

The v6-alpha3 native multi-tile encoder (`encodeNativeMultiTile`) is single-threaded across tiles. The v5.39 M4 wrap-and-stitch path that preceded it used `withTaskGroup` and measured XA 28 % / PX 35 % / DX 30 % encode speedup. Re-parallelise per-tile by adding `withTaskGroup` with bounded concurrency (mirror the `maxInFlightTilesGPU = 8` pattern from `decodeMultiTileGPU`).

**Phase 0**: Audit current encodeNativeMultiTile for shared mutable state — the entropy stage uses a per-tile `J2KCodeBlock` array, which is the unit of parallelism.

**Phase 1**: Refactor `encodeNativeMultiTile` to dispatch tiles via chunked TaskGroup. Each tile runs the full sub-pipeline (extract → DWT → quant → entropy) independently into per-tile output buffers; sequential composite into the codestream pool runs after all tiles complete.

**Phase 2**: Production-default `auto` planner promotion gate — re-evaluate whether multi-tile should auto-fire at the corpus-fair fixtures (PX/DX/MG) once parallelism is back. Per `MEDICAL_BENCHMARK_V6.md` v6-alpha3 finding: pre-parallelism, auto-promotion regressed PX (42 ms multi vs 37 ms single). Post-parallelism: rerun the A/B and decide.

**Empirical projection** (vs current single-tile times):
- XA: 11.5 → ~8.3 ms (+28%)
- PX: 31.0 → ~20 ms (+35%)
- DX: 57.7 → ~40 ms (+30%)
- MG: ~120 → ~85 ms (+30%)

If projections hold, **DX encode 40 ms vs Kakadu 18.9 ms = gap closes from 3.0× → 2.1×**. Not a complete close, but a major dent.

**Risk**: Low. The wrap-and-stitch path already proved per-tile parallelism is correctness-clean; we just need to wire it to the native multi-tile path.

**Gate**: HTTileParityMatrixTests 12/12 + cross-codec 21/21 + corpus encode A/B with new wins captured.

### H. Multi-tile decode GPU compute correctness (E1.3)

#### H1. Defect A — GPU HT entropy multi-tile coefficient drift

[`docs/V6_3_0_E1_2_INVESTIGATION.md`](V6_3_0_E1_2_INVESTIGATION.md) #Defect A: GPU HT entropy in the per-tile multi-tile context produces coefficients that diff from CPU HT by exactly 32768 (= DC offset for 16-bit) on DX 2800×2288. The bug is per-tile-shape-specific; single-tile DX 6.4 MP via the same `J2KGPUHTDispatch.decodeBatchGPUResident` API is bit-exact since v5.5.0.

**Phase 0**: Diff per-block GPU vs CPU coefficients on a single failing DX tile. Identify which block(s) drift and by what magnitude. Compare per-tile descriptor sequence (`magsgnOffset`, `melVlcOffset`, `outputOffset`, `width`, `height`, `missingMSBs`) against the equivalent single-tile descriptors at the same canvas position.

**Phase 1**: Fix the per-tile invariant. Hypothesis: the `outputSampleCount` / `sampleOffsets` arithmetic mis-counts at tile-local subband sizes, OR the `bandKb` per-block encoding is image-global where it should be tile-local, OR the kernel's `missingMSBs` interpretation differs between single-tile and per-tile invocations.

**Gate**: `MultiTileDecodeGPUDefaultOnTests` 12/12 still bit-exact AFTER re-enabling `isGPUPath: true` in `decodeTilePayloadGPU`.

#### H2. Defect B — GPU 5/3 IDWT parity-aware boundary lifting

[`docs/V6_3_0_E1_2_INVESTIGATION.md`](V6_3_0_E1_2_INVESTIGATION.md) #Defect B: GPU 5/3 inverse kernel applies boundary lifting assuming canvas origin (0, 0). Multi-tile per-tile invocations with non-zero tile-component canvas origin require parity-aware lifting per **ISO 15444-1 Annex F.4.1.1** that the GPU kernel doesn't implement.

**Phase 0**: Port the CPU `J2KDWT2DOptimizer.inverseTransformMultiLevel53`'s parity-aware boundary lifting into a Metal kernel variant. The CPU implementation uses `tileOriginX/Y` to switch boundary symmetric extension; the GPU kernels need the same parameter and branch.

**Phase 1**: Wire the new kernel into `applyInverseWaveletTransformGPU` when `isMultiTilePerTile: true` AND `tileOriginX != 0 || tileOriginY != 0`. Tile origin (0, 0) keeps the existing kernel.

**Gate**: `HTTileParityMatrixTests` 12/12 self-RT diff = 0 with `isMultiTilePerTile: false` re-enabled in `decodeTilePayloadGPU`.

#### H3. E1.3 closure — re-enable GPU per-tile compute by default

After H1 + H2 land, re-enable `isGPUPath: true` and `isMultiTilePerTile: false` in `decodeTilePayloadGPU`. Multi-tile decode for ≥4 MP fixtures gains the same +37–46 % GPU win single-tile already enjoys.

**Empirical projection**: DX 2800×2288 multi-tile decode 4.0 ms (CPU) → 2.5 ms (GPU end-to-end), tracks the single-tile +37–46 % envelope.

**Risk**: Medium. Defect B requires kernel work. Defect A's root cause is unknown — Phase 0 instrumentation may surface a 1-line fix or a structural redesign.

### I. GPU forward HT entropy — approach C OR D (HIGH-RISK, HIGH-UPSIDE)

#### I1. Approach C — three-pass GPU pipeline (classify + prefix-sum + byte-write)

Per [`V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md`](V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md) §4 approach C: classify on GPU → bit-budget prefix-sum on GPU → byte-write on GPU with per-block correction for 0xFF byte stuffing. Estimated **~35–40 % wall reduction on DX entropy** if the correction pass is fast.

**Phase 0**: Design doc — flesh out the prefix-sum kernel (which Metal primitive: `MPSScan`? hand-rolled per-warp scan? two-level scan for >32k elements?), the bit-write kernel, and the 0xFF correction pass logic. The correction is the high-risk part: 0xFF bytes mid-stream require post-byte stuffing that breaks naive parallel writes.

**Phase 1**: Implement classify + prefix-sum kernels. Reuse approach B's classifier from [#304](https://github.com/Raster-Lab/J2KSwift/pull/304); add prefix-sum to compute per-block byte offsets.

**Phase 2**: Implement byte-write kernel. Output goes directly to a GPU codeblock buffer the CPU reads back at the end of entropy.

**Phase 3**: Implement 0xFF correction pass — either a second GPU dispatch that scans for 0xFF runs and inserts stuff bytes, or a CPU fix-up that scans the readback buffer.

**Phase 4**: Wire through `applyEntropyCodingHTJ2KFused` behind `_gpuForwardHTEntropyEnabled` (already plumbed from v6-alpha6). Telemetry mirror of approach B.

**Gate**: every phase ships bit-exact codestream bytes vs CPU encoder; corpus 6/6 byte-identical; cross-codec 21/21.

**Decision point** at end of Phase 4: corpus A/B wall time. **If DX wall reduction ≥ 15 %, ship default-on with threshold gate**. Otherwise: ship opt-in (mirror approach B's #305 path); pivot to approach D.

#### I2. Approach D — per-warp/threadgroup serial fallback

Only activated if approach C fails the Phase 4 decision gate. Approach D uses SIMD-group serial within block (32-wide groups), needing careful threadgroup bit-state management. Estimated **~25–35 % wall reduction on DX**.

If both C and D regress on M2, defer to v6.5.0 with cross-device retesting (M3/M4/M4 Pro/M4 Max may shift the dispatch latency floor enough for these to flip positive).

**Risk**: HIGH. v6-alpha6 approach B regressed -200 % at every corpus scale (#305). C + D are unexplored but face the same fundamental dispatch + readback latency floor that defeated B. The Apple M2 dispatch overhead is the suspected cause; cross-device retesting may help.

### J. Tier-1 architectural — per-block intermediate buffer elimination (v7-SCALE STRETCH)

#### J1. Direct-to-codestream-pool entropy emission

F1 (#324) finding: tileDataAppend on DX = 0.7 ms at 18.4 GB/s memory bandwidth — already at memcpy bandwidth ceiling. The only way to reduce is to **eliminate the per-block intermediate buffer entirely** so block bytes write directly into the final codestream pool during entropy coding.

This is a v7-scale architectural refactor: the entropy stage must know the final codestream offset for each block before emission, which requires either:
- **Two-pass entropy**: first pass computes block sizes, second pass writes directly. Doubles entropy work.
- **Speculative offset reservation**: emit each block's bytes at a worst-case-sized offset, then compact afterward. Saves bandwidth on average but needs compact pass.
- **Reverse-emission with offset patch**: emit blocks back-to-back with a length prefix that gets patched after each block completes.

**Phase 0**: Design doc + prototype. Decide which of the three architectural shapes to pursue.

**Phase 1+**: Implementation + bit-exact validation + corpus A/B.

**Risk**: VERY HIGH. v7-scale work that may or may not land in v6.4.0. Listed here for scope completeness; the v6.4.0 trajectory does not depend on J landing.

### K. Decoder warm-session for multi-tile dispatch (HIGH-CONFIDENCE INCREMENTAL)

#### K1. Pre-warmed `J2KMetalSession.processShared` for multi-tile

v6.2.0 D3 (#316) plumbed `processShared` through `decode(_:)`. v6.3.0 F2 (#323) plumbed it through `decodeGPU(_:)` / `decodeWithGPUHT(_:)` no-session overloads. K1 closes the last cold-start path: **multi-tile per-tile dispatch within `decodeMultiTileGPU`**. Each per-tile task currently builds its own `J2KMetalSession` from scratch if Defect A/B forced compute to CPU; once H closes, per-tile dispatch should explicitly reuse the warm singleton.

**Risk**: Low. Mirror of D3 / F2 patterns. Already partially in place; this is hardening for the H1+H2 followup.

---

## Phase trajectory (proposed)

The trajectory ships **G first** (lowest risk, biggest immediate Kakadu-gap-narrow), then **H** (medium risk, restores deferred multi-tile decode wins), then **I** (high risk, the entropy-stage gamble). **J** is a stretch goal — listed for scope completeness but may slip to v6.5+. Each phase is its own PR per `RELEASING.md` branching strategy.

| phase | scope | branch | gate |
|---|---|---|---|
| **Plan** (this PR) | Doc + scope sign-off | `feature/v6.4.0-plan` | sign-off |
| **G1.0** | Multi-tile encode parallelism — Phase 0 audit + design | `feature/v6.4.0-multi-tile-encode-parallelism-design` | doc only |
| **G1.1** | Native multi-tile encoder per-tile parallelism | `feature/v6.4.0-multi-tile-encode-parallelism` | corpus A/B + parity matrix bit-exact |
| **G1.2** | `auto` planner promotion + production-default decision | `feature/v6.4.0-auto-multi-tile-default-on` | corpus A/B (auto vs single) + parity matrix |
| **H1** | Defect A — GPU HT entropy multi-tile root-cause + fix | `feature/v6.4.0-multi-tile-gpu-ht-entropy-fix` | `MultiTileDecodeGPUDefaultOnTests` 12/12 with `isGPUPath: true` |
| **H2** | Defect B — GPU 5/3 IDWT parity-aware kernel | `feature/v6.4.0-gpu-idwt-parity-aware` | `HTTileParityMatrixTests` 12/12 with `isMultiTilePerTile: false` |
| **H3** | Re-enable multi-tile GPU compute by default | `feature/v6.4.0-multi-tile-gpu-compute-default-on` | corpus decode A/B + parity matrix |
| **I1** | GPU forward HT entropy approach C — design + prefix-sum spike | `feature/v6.4.0-gpu-fwd-ht-entropy-approach-c-design` | doc + isolated kernel benchmarks |
| **I2** | Approach C full pipeline (classify + prefix-sum + byte-write + 0xFF correction) | `feature/v6.4.0-gpu-fwd-ht-entropy-approach-c` | bit-exact bytes + corpus A/B; ≥ 15 % DX wall reduction → default-on, else opt-in |
| **I3** | Approach D fallback (only if I2 regresses) | `feature/v6.4.0-gpu-fwd-ht-entropy-approach-d` | bit-exact + corpus A/B |
| **K1** | Multi-tile per-tile warm-session hardening | `feature/v6.4.0-multi-tile-warm-session` | bit-exact + telemetry |
| **J1** | (Stretch) Tier-1 per-block-buffer elimination — design | `feature/v6.4.0-tier1-direct-codestream-design` | doc + prototype microbenchmark |
| **Release v6.4.0** | All-merged + release notes | `v6.4.0-release-candidate` | RELEASING.md flow |

---

## Decision gate before G1.0 lands

Confirm one of:

- **"Go by your recommendation"** — I'll start with **G1.0** (multi-tile encode parallelism design + audit). Lowest-risk highest-confidence work first; ship the win that the v5.39 M4 wrap-and-stitch already proved viable. Chain through G1.1, G1.2, then move to H. I will defer J until G/H/I have all landed.

- **Reorder the trajectory** — e.g., I (GPU forward HT entropy approach C) first to retire the high-risk gamble early. If I lands a win, G's wins compound; if I fails, G/H still ship the release.

- **Cap the scope** — if the Kakadu deadline is tight, ship G + H1 + H2 only, defer I to v6.5.0. v6.4.0 ships as "multi-tile encode + decode parallelism / correctness" without the entropy gamble.

- **Add a work item not listed** — propose and we'll fit it into the trajectory.

---

## What v6.4.0 explicitly does NOT plan

- **CPU-only single-thread micro-optimisations** — locked out by `feedback_v6_alpha4_lever_ceiling.md`. The v6-alpha4 step 12 sweep proved diminishing returns; v6.4.0 only attacks parallelism + GPU + architectural dimensions.
- **Lossy work** — out of scope per `feedback_lossless_only_v5_38.md` (parked 2026-05-05). No lossy default flips, no PCRD work, no lossy 9/7 encode-side optimisation.
- **Cross-device threshold re-tuning** — needs M3 / M4 / M4 Pro / M4 Max hardware, not currently available. Infrastructure is in place; the work itself waits for hardware.
- **DICOM encapsulation validation** — overdue per `project_v5_35_scope.md` memory but it's correctness work, not perf. Defer to a separate `validation/` arc unless explicitly bundled by the user for this release.
- **JP3D / volumetric encode-decode** — orthogonal feature gap to the Kakadu encode wall-time gap; out of scope unless explicitly added.

---

## v-series arc summary so far

| version | shipped | DX encode win | DX decode win |
|---|---|---:|---:|
| v5.38.0 | lossless medical archival baseline | — | — |
| v6.0.0 | `.auto` multi-tile production-default + opt-in GPU forward DWT | encode 1.3× | — |
| v6.1.0 | GPU forward DWT default-on for ≥4 MP | encode +21.3 % | — |
| v6.2.0 | GPU iDWT + GPU HT entropy default-on for ≥4 MP single-tile | — | decode +46.2 % |
| v6.3.0 | Multi-tile decode correctness + threshold 4 MP → 3 MP | encode +10.9 % (PX); +17.4 % (DX) | — |
| **v6.4.0** | **Multi-tile encode parallelism + multi-tile GPU decode compute (E1.3) + GPU forward HT entropy approach C/D** | **TBD — projection: encode 25–45 % combined (G1 + I if I lands)** | **TBD — projection: multi-tile decode +37–46 % once H closes** |

If G + H + I (I winning the gamble) all land, **v6.4.0 closes the Kakadu DX encode gap from 3.0× → ~1.5×** — the biggest single-release reduction since v6.0.0. If only G + H land, the gap closes to ~2.1×, still the biggest multi-release reduction since the lever-ceiling work began.
