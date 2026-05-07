# v6.2.0 plan — HTJ2K + J2K perf, branching-strategy execution

**Status**: Plan only. No code in this PR. Sign-off on the candidate work items below before Phase 0.5 / Phase 1 PRs land.

**Branch**: `feature/v6.2.0-plan`

**Anchor**:
  - [`RELEASING.md`](../RELEASING.md) "Release scope expectations" — every minor/major release ships HTJ2K + general-J2K perf work (or honest empirical-wash measurements that inform the next plan)
  - [`RELEASE_NOTES_v6.1.0.md`](../RELEASE_NOTES_v6.1.0.md) §"Medical-corpus benchmarks" — DX 2800×2288 stage breakdown after the v6.1.0 default-on flip:

    | Stage | DX ms | DX % |
    |---|---:|---:|
    | **entropy** | 36.56 | **60.9%** |
    | **DWT** | 16.45 | **27.4%** |
    | codestream | 4.95 | 8.2% |
    | preproc | 2.91 | 4.8% |

---

## Why this plan splits HTJ2K work from J2K-general work

The recent perf arcs (v6-alpha6 entropy, v6-alpha7 tier-2) taught two lessons:

1. **Single-lever optimisations rarely move the needle on this hot path.** Five PRs in a row before v6.1.0 (#305 / #306 / #307 / #308 / #309) shipped no measurable wall-time win. The wins that landed (v6.0.0 multi-tile `.auto`, v6.1.0 GPU forward DWT default-on) came from architectural shifts pulled at the right scale, not micro-optimisations.

2. **Empirical-first planning beats estimate-first planning.** Before the lossless stage profile (#309), planning was based on stale lossy-mode estimates (entropy 45% / DWT 8%); the actual numbers (entropy 49% / DWT 40%) showed DWT was the immediately-actionable lever. We won't repeat that mistake — every Phase 0 in this plan starts with a fresh measurement.

Per the new [`RELEASING.md`](../RELEASING.md) "Release scope expectations" section, v6.2.0 ships work spanning **both** HTJ2K (Part-15) and general J2K (Part-1 / codestream / tier-2 / file format). HTJ2K is where the biggest unaccelerated lever lives (entropy at 60.9% of DX wall after v6.1.0); J2K-general gets the smaller-but-overdue work that's been deferred since v5.x.

---

## Candidate work items

### A. HTJ2K — entropy stage (60.9% of DX wall)

The biggest unaccelerated stage, attempted twice in v6-alpha6 with negative empirical results. The plan-doc §4 candidate "approach E + NEON for emission" was the documented next step after E (CPU-SIMD classifier only) was a wash. v6.2.0 takes that step.

#### A1. Per-quad emission NEON intrinsics — Phase 0 design + Phase 1 spike

The v5.39 M1 SIMD classifier replaced 5% of per-block emit cost with a SIMD lane-parallel pass; Phase 1.4 (#306) measured a wash because the remaining 95% (rho/eQMax accumulation, MEL/VLC/MagSgn payload preparation) stayed scalar. NEON intrinsics for the per-quad emission targets that 95%.

Phase 0 (doc): characterise the emission hot loop. Identify which sub-steps are SIMD-amenable (rho mask construction, eQMax reduction, MagSgn bit-packing) vs which stay serial (MEL run-length state, VLC byte-stream emission with byte-stuffing).

Phase 1 (spike): one of the SIMD-amenable sub-steps lifted to NEON intrinsics, bit-exact validated against the scalar reference. Wall-time A/B on the corpus.

Phase 2+ (if Phase 1 wins): apply to remaining sub-steps; promote behind a `J2K_HT_EMIT_NEON=1` opt-in flag.

#### A2. DWT + entropy fusion — single GPU command buffer (deferred study)

After v6.1.0's DWT default-on, the DWT output is a GPU-resident buffer that's read back to CPU for entropy coding. Eliminating that readback by running entropy on GPU in the same command buffer would close the per-tile boundary cost. This is a much bigger architectural change than the v6-alpha6 GPU-classify spike attempted; deferred to a v6-alpha9-class arc unless A1 fails to move the needle.

#### A3. GPU forward DWT threshold re-tuning

v6.1.0 ships threshold = 4 MP based on M2 measurement. Re-run `HTGPUForward53Phase9ThresholdBoundaryTests` against the v6.1.0 baseline to confirm 4 MP is still the right break-even (the v6.0.0 measurement was with the path opt-in only; the v6.1.0 default-on path may shift the curve slightly due to warm-session amortisation). Possible outcome: lower the threshold to 3 MP to capture PX 3.2 MP under default-on.

### B. General J2K — codestream stage + decoder-side coverage

The codestream stage is 8.2% of DX wall (4.95 ms); writePacket is 2.5% (PR #308). The remaining 5.5% is unprofiled. Decoder-side hot path has not been profiled at sub-stage granularity at all in the recent arcs.

#### B1. Codestream marker writes sub-stage profiling — mirror of #308

Add `J2KCodestreamTimings` accumulator (mirror of `J2KTier2Timings` from #308) for the marker writes outside `writePacket`: SOC, SIZ, COD, QCD, COM, SOT, SOD per tile, EOC. Diagnostic test prints sub-stage breakdown across the corpus. Identifies which marker write owns the non-writePacket 5.5 ms on DX. Doc-only Phase 0 + diagnostic Phase 1; optimization Phase 2+ depends on the data.

#### B2. Decoder-side stage profile (gap-fill)

`J2KDecodeTimings` exists (v5.24.0); `EncodeStageProfileLosslessCorpusTests` has no decoder analog. Add `DecodeStageProfileLosslessCorpusTests` that runs the corpus through `J2KDecoder.decode` and prints the equivalent table. Cheap to write (mirror of #309); fills the gap that the next decoder-side perf arc would otherwise need to do first.

The medical-corpus decode benchmarks already exist (`J2KMedicalCorpusPerformanceTests` is in the mandatory gate); we just need the per-stage breakdown printed.

#### B3. Preprocess `extractComponentData` revisit

Preprocess is 4.8% of DX wall (2.91 ms). v5.38 M7 specialised the loop into 4 branchless bodies; LLVM auto-vectorisation should already be doing the rest. Re-measure post-v6.1.0 to confirm M7's win is still in place; investigate if LLVM produces SIMD code or if explicit vDSP / NEON would help. Probably small if any win — keep this as a "discover and decide" Phase 0 only.

---

## Phase trajectory (proposed)

| phase | scope | branch | gate |
|---|---|---|---|
| **Plan** (this PR) | Doc + RELEASING.md update | `feature/v6.2.0-plan` | sign-off |
| **A1.0** | Entropy emission NEON design doc | `feature/htj2k-entropy-emit-neon-phase-0` | doc only, no code |
| **A1.1** | Phase 1 spike — one SIMD-able sub-step in NEON | `feature/htj2k-entropy-emit-neon-phase-1` | bit-exact + wall-time A/B |
| **B1.0** | Codestream marker write profiling | `feature/codestream-marker-substage-profile` | empirical sub-stage breakdown |
| **B2** | Decoder stage profile gap-fill | `feature/decode-stage-corpus-profile` | data only |
| **A3** | DWT threshold re-validation | `feature/gpu-forward-53-threshold-revalidate` | 4 MP confirmed or lower-bound found |
| Subsequent | Concrete optimisations driven by the Phase 0 / 1 data above | one PR per concrete change | bit-exact + measurable A/B |
| **Release v6.2.0** | All-merged | `v6.2.0-release-candidate` | RELEASING.md flow incl. cross-codec + medical bench inline |

Each phase ships behind a separate PR per RELEASING.md branching strategy. The release notes for v6.2.0 summarise the empirical findings (wins AND wash results); the data is the deliverable even when the wall-time number is zero.

---

## What v6.2.0 explicitly does NOT plan

To keep scope tight after the v6-alpha6 / v6-alpha7 lessons:

- **Lossy work** — out of scope per `feedback_lossless_only_v5_38.md` (parked 2026-05-05); no lossy default flips, no PCRD work, no `.constantBitrate` re-tuning.
- **Multi-tile GPU revisit** — Phase 5 (#298 era) measured 33–43% regression for per-tile GPU dispatch on `.auto` layouts. Defer until single-tile entropy work (A1) is settled.
- **Cross-device threshold re-tuning** — needs M3 / M4 / M4 Pro / M4 Max hardware, not currently available. The infrastructure is in place (`MEDICAL_BENCHMARK_V6.md` cross-device template); the work itself waits for hardware.
- **DICOM encapsulation validation** — overdue per `project_v5_35_scope.md` memory but it's correctness work, not perf. Defer to a separate `validation/` arc unless the project wants to bundle it explicitly.

---

## Decision gate before Phase 0.5 / Phase 1 land

Confirm one of:
- **Pick a starting work item** (A1.0 / B1.0 / B2 / A3) — I'll start that PR and chain through subsequent ones in order
- **Reorder the trajectory** — e.g., decoder profile first, entropy NEON last
- **Add a work item not listed** — propose and we'll fit it into the trajectory
- **"Go by your recommendation"** — I'll start with B2 (decoder profile, smallest scope, cheapest data; gap-fills the corpus baseline before bigger swings)

The plan above has the v6-alpha6 lesson baked in: every phase has an empirical gate so wash results are documented as wash, not shipped as wins.
