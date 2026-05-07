# v6.3.0 plan — multi-tile decode bug fix + deferred levers

**Status**: Plan only. No code in this PR. Sign-off on the candidate work items below before E1 / F1 PRs land.

**Branch**: `feature/v6.3.0-plan`

**Anchors**:
- [`RELEASING.md`](../RELEASING.md) "Release scope expectations" — every minor / major release ships HTJ2K + general-J2K perf work (or honest empirical measurements that inform the next plan)
- [`RELEASE_NOTES_v6.2.0.md`](../RELEASE_NOTES_v6.2.0.md) §"Known limitations" — multi-tile decode stays on CPU pending v6.3.0 investigation
- v6.2.0 measured DX 2800×2288 decode breakdown after the GPU iDWT + GPU HT entropy default-on flip:

  | Stage | DX ms | DX % |
  |---|---:|---:|
  | entropy (incl. gpuHTDispatch) | 17.04 | 41.7% |
  | iDWT | 17.10 | 41.9% |
  | reconstruct | 3.89 | 9.5% |
  | extract | 2.47 | 6.1% |
  | dcShift | 1.23 | 3.0% |

  Total decode wall: **40.83 ms** (was 73.90 ms in v6.0.0, **−45 % via v6.1.0/v6.2.0**).

---

## Why this plan

The v6.2.0 release-candidate validation (PR #318) surfaced a `malformedBlock` error in the multi-tile GPU decode path when both `_gpuInverse53Enabled` and `_gpuHTEntropyEnabled` defaults flipped on. v6.2.0 narrowed the routing to `!metadata.isMultiTile`. **Multi-tile codestreams continue to use the unchanged CPU path on v6.2.0 — this is the headline deferred item for v6.3.0.**

Plus the v6.2.0 plan ([`docs/V6_2_0_PLAN.md`](V6_2_0_PLAN.md)) had several work items the D-series rendered moot or deferred. Those carry forward where still actionable.

---

## Candidate work items

### E. HTJ2K — multi-tile decode bug + deferred GPU work

#### E1. Multi-tile decode bug fix (HEADLINE)

The multi-tile decode path through `decodeMultiTileGPU` → `decodeTilePayloadGPU` → `applyEntropyDecoding(_:metadata:isGPUPath: true)` throws `malformedBlock` when both decode-side gate flags are on. Single-tile is fine.

The error originates from per-tile entropy decode, likely in the `gpuEarly` closure in `applyEntropyDecoding` or the regroup that feeds it. Per-tile codeblock layout, tile-component slicing, or the GPU HT dispatcher's per-tile state may not be correctly threaded.

Phase 0 (doc): characterise the failure — instrument `decodeMultiTileGPU` to capture which tile / which codeblock fails and at what stage. Compare against the working `decodeWithGPUHT(_:session:)` path (which DOES handle multi-tile via the explicit-session API).

Phase 1: implement the fix. Likely candidates:
- per-tile metalSession reuse vs fresh per-tile session
- per-tile GPU HT batch boundary handling
- per-tile `useGPUHT` threading through the parallel `withThrowingTaskGroup` chunks

Phase 2: ship the routing widening — drop the `!metadata.isMultiTile` guard in `DecoderPipeline.decode`. Re-run the cross-codec parity matrix (`HTTileParityMatrixTests` 36/36) and the corpus A/B (`GPUInverse53DefaultOnTests` + `GPUHTEntropyDecodeDefaultOnTests`) with multi-tile included.

Phase 3 (release-blocking): empirical wall-time on multi-tile fixtures — does multi-tile decode see the same +45 % win as single-tile DX? Or is multi-tile per-tile dispatch overhead a different curve?

#### E2. GPU forward DWT threshold re-tune

v6.0.0's threshold = 4 MP was set on M2 with the v6-alpha5 phase 9 sweep. v6.1.0+ default-on, v6.2.0's warm-session decoder plumbing — the curve may have shifted. PX 2459×1316 (3.24 MP) showed +12 % in v6.1.0's #310 A/B and is currently gated to CPU; lowering the threshold to 3 MP would route PX too.

Phase 0: re-run `HTGPUForward53Phase9ThresholdBoundaryTests` against v6.2.0 baseline.
Phase 1: if data supports it, lower `_gpuForward53PixelThreshold` from 4_000_000 to 3_000_000.

Small but real win if the data lands the right way.

#### E3 (deferred study). DWT + entropy GPU command-buffer fusion

Currently entropy and iDWT run as separate GPU dispatches with a CPU regroup between them. Fusing into a single command buffer would eliminate the readback. Substantial GPU architecture change — keep deferred unless E1 surfaces architectural wins from per-tile work that suggest the fusion is closer than thought.

### F. General J2K — codestream + decoder API + preprocess

#### F1. Codestream marker writes sub-stage profiling

PR [#308](https://github.com/Raster-Lab/J2KSwift/pull/308) profiled `writePacket` (2.5 % of DX wall). The remaining ~5.5 ms (8 % wall) of DX codestream stage is unprofiled. Mirror of the #308 pattern for SOC / SIZ / COD / QCD / COM / SOT / SOD / EOC marker writes.

Phase 0 (mirror #308): add `J2KCodestreamMarkerTimings` accumulator and a sub-stage breakdown test. The data identifies whether tier-1 marker-write optimization is worth pursuing.

#### F2. Decoder warm-session for `decodeGPU` and `decodeWithGPUHT` public APIs

v6.2.0 plumbed `J2KMetalSession.processShared` through the default `decode(_:)` entry point. The other public decode APIs (`decodeGPU(_:)`, `decodeWithGPUHT(_:)`) currently construct a fresh `DecoderPipeline()` per call without the shared session — they pay the same cold-start cost the default path used to.

Phase 0 / Phase 1: plumb `processShared` through the no-session overloads of `decodeGPU(_:)` and `decodeWithGPUHT(_:)`. Bit-exact validated; perf A/B should mirror v6.2.0's +37-46 % win.

#### F3. Preprocess `extractComponentData` revisit

Preprocess is 4.8 % of DX encode wall (2.91 ms in v6.1.0, 2.44 ms in v6.2.0 measurement). v5.38 M7 specialised the loop into 4 branchless bodies; LLVM should auto-vectorise. Re-measure post-v6.2.0; investigate whether explicit vDSP / NEON would help.

"Discover and decide" Phase 0 only — likely small if any win.

---

## Phase trajectory (proposed)

| phase | scope | branch | gate |
|---|---|---|---|
| **Plan** (this PR) | Doc + scope sign-off | `feature/v6.3.0-plan` | sign-off |
| **E1.0** | Multi-tile bug investigation + Phase 0 design doc | `feature/v6.3.0-multitile-decode-investigation` | doc + repro test |
| **E1.1** | Multi-tile bug fix | `feature/v6.3.0-multitile-decode-fix` | `HTTileParityMatrixTests` 36/36 + bytes byte-identical |
| **E1.2** | Routing widened — drop `!metadata.isMultiTile` guard | `feature/v6.3.0-multitile-decode-default-on` | corpus A/B + multi-tile A/B |
| **F1** | Codestream marker writes profiling | `feature/v6.3.0-codestream-marker-profile` | empirical sub-stage breakdown |
| **F2** | Decoder warm-session for decodeGPU / decodeWithGPUHT no-session overloads | `feature/v6.3.0-decoder-api-warm-session` | bit-exact + perf A/B |
| **E2** | GPU forward DWT threshold re-tune | `feature/v6.3.0-gpu-forward-53-threshold-revalidate` | data-driven decision |
| **F3** | Preprocess revisit (Phase 0 only) | `feature/v6.3.0-preprocess-revisit` | discover and decide |
| **Release v6.3.0** | All-merged | `v6.3.0-release-candidate` | RELEASING.md flow |

Each phase ships behind a separate PR per RELEASING.md branching strategy. Release notes for v6.3.0 summarise the empirical findings (wins AND any wash results); the data is the deliverable even when the wall-time number is zero.

---

## What v6.3.0 explicitly does NOT plan

- **GPU multi-tile encode** — Phase 5 (#298 era) measured 33–43 % regression for per-tile GPU dispatch on `.auto` layouts. Defer until E1's per-tile decode work surfaces architectural insights.
- **Lossy work** — out of scope per `feedback_lossless_only_v5_38.md` (parked 2026-05-05). No lossy default flips, no PCRD work.
- **Cross-device threshold re-tuning** — needs M3 / M4 / M4 Pro / M4 Max hardware, not currently available. Infrastructure is in place; the work itself waits for hardware.
- **Per-quad emission NEON intrinsics** (was A1 in v6.2.0 plan) — the D-series default-on flips delivered a much bigger win for less risk; NEON intrinsics on per-quad emission would add complexity for a smaller incremental gain. Deferred to a future v6-alpha8 arc unless GPU paths are fully exhausted.
- **DICOM encapsulation validation** — overdue per `project_v5_35_scope.md` memory but it's correctness work, not perf. Defer to a separate `validation/` arc unless explicitly bundled.

---

## Decision gate before E1.0 lands

Confirm one of:
- **Pick a starting work item** (E1.0 / F1 / F2 / E2) — I'll start that PR and chain through subsequent ones in order
- **Reorder the trajectory** — e.g., F1 first while multi-tile bug investigation continues in parallel
- **Add a work item not listed** — propose and we'll fit it into the trajectory
- **"Go by your recommendation"** — I'll start with **E1.0** (multi-tile bug investigation + repro test). It's the v6.2.0 deferred item; closing it restores multi-tile to the GPU routing and unlocks the v6.3.0 headline. F1 / F2 can chain after.

---

## v-series arc summary so far

| version | shipped | DX win |
|---|---|---|
| v5.38.0 | lossless medical archival baseline | — |
| v6.0.0 | `.auto` multi-tile production-default + opt-in GPU forward DWT | encode 1.3× |
| v6.1.0 | GPU forward DWT default-on for ≥4 MP | encode +21.3% |
| v6.2.0 | GPU iDWT + GPU HT entropy default-on for ≥4 MP single-tile | decode +46.2% |
| **v6.3.0** | **multi-tile decode default-on (E1) + chosen J2K-general work (F-series)** | **TBD — multi-tile fixtures get the same +45 % decode win as single-tile** |
