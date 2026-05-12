# v10.0-research — non-entropy wall-budget characterisation + C target selection

**Status:** Plan draft. No code yet. Branch: `v10.0-research` off `v9.9-image-stats-predictor` (will rebase onto main once v9.9 lands).

## Context

The v9.x arc closed the Kakadu encode gap from 5× to 1.45× on M4
daemon DX:

| Release | Headline change | DX gap to Kakadu |
|---------|----------------|------------------|
| v9.3.0  | Path B Phase 2 + MagSgn batching | 4.39× → 3.69× |
| v9.4-research | C+NEON entropy hot path | hand-NEON ≈ auto-vec (closed as research, opt-in graduation) |
| v9.5-research | 5-phase aggressive C push | closed as research (per-quad assumption was 40–90× too high) |
| **v9.6** | **Process-default qstep cache** | **3.69× → 1.45×** ← headline win |
| v9.7/v9.8 | pre-seed dead-end; SIGTRAP fix | no perf wash |
| v9.9 | image-stats qstep predictor + bracket widening + test fixes | research; image-stats is the predictor for the cache |

The Kakadu gap on warm-cache DX is now small enough that further
single-stage encoder optimisation has diminishing returns. The
remaining 0.45× headroom — if it is recoverable at all — is spread
across multiple non-entropy stages, not concentrated in one place
that a focused C rewrite would eliminate.

The team has chosen C (extending the `J2KCodecNEON` SwiftPM pattern)
as the optimisation toolchain going forward. The question this
research branch must answer is: **which non-entropy stage, if any, is
the right next C target?**

## What we already know about the non-entropy stages

From [V8_6_FORWARD_DWT_FINDING.md](V8_6_FORWARD_DWT_FINDING.md) and
existing microbenches (see survey appendix), four candidate stages
have measured properties that constrain the answer:

| Stage | Status | Headroom on M4 |
|-------|--------|----------------|
| DWT 5/3 forward (lossless) | 0.37 ns/sample @ n=2048 (L1-resident); **memory-bandwidth-bound** | ≤3% wall, no SIMD retrofit gain |
| DWT 9/7 forward (lossy) | LLVM-optimised Swift + vDSP; GPU path exists | small CPU gain; GPU already covers default lossy |
| Tier-2 packet encoding | Bitstream multiplexer; inherently branchy | limited C/SIMD payoff |
| Quantisation + colour transform | Lightweight IC-bound | small wall fraction |
| Trellis PCRD-opt loop | Iterative rate-distortion search | **unmeasured** — likely the largest unstudied contributor |
| Pre/post-processing (bit-depth conv, padding) | **Unmeasured** | unknown |

The two cells marked "unmeasured" are the only honest reasons to
believe a v10.0 C target would clear the bar. Everything else has
documented ceilings.

## Approach

This is a **measure-first** plan. The v9.4 and v9.5 research arcs
established that the autovec ceiling on M4 is real (the
`Microbench before committing to a multi-phase plan` lesson) — a
plan that commits to a C target without first quantifying the
remaining wall budget will repeat v9.5's per-quad-assumption error.

Phase 1 produces the wall budget. Phase 2 makes the C-target decision
*from* that budget. Phase 3 implements only if Phase 2 found a target
worth doing.

### Phase 1 — non-entropy wall budget on M4 (no C written)

**Deliverable:** a measured percentage breakdown of warm in-process
DX-encode wall time across:

1. DWT (already partly measured — re-run on current branch)
2. Quantisation (forward, including trellis PCRD-opt if engaged)
3. Colour transform (RCT and ICT, both)
4. Tier-2 packet header + body assembly
5. Codestream marker writing
6. Pre/post-processing (bit-depth conversion, mirror-padding,
   sub-band scatter/gather)
7. Memory allocation / `Data` assembly
8. (Reference baseline) entropy stage (current Swift + C-NEON paths)

**Method:** extend `J2KEncodeTimings` to capture per-substage walls;
run on the medical corpus + cross-codec corpus; report 1×, 4×, 12×
worker results so contention effects are visible.

**Gate to move to Phase 2:** at least one non-entropy stage measures
≥10% of wall on a representative corpus image, with ns/sample > 20
(the rough autovec ceiling threshold from
`feedback_microbench_before_plan.md`). If nothing clears the bar,
close as research with a documented "encoder wall is mature on M4"
finding.

### Phase 2 — C target selection

**Inputs:** Phase 1's wall budget; ns/sample for each candidate;
parallel-efficiency telemetry; whether the stage already has a GPU
path that would also serve.

**Decision rule:**
1. Stage must be ≥10% of wall AND ns/sample > 20 AND no equivalent
   GPU path is already covering the default case.
2. Tie-breakers (lower better): branchiness, hand-NEON suitability,
   existing parity-test infrastructure.

**Most likely candidates given current evidence:**
- **Trellis PCRD-opt loop** (`J2KTrellisQuantizer.swift`, 638 lines)
  — never microbenched; iterative; rate-distortion search with
  per-codeblock evaluation; likely contains real Swift-level
  overhead.
- **Pre-processing** (bit-depth widening + mirror-padding +
  sub-band scatter) — unmeasured; gather/scatter is a NEON sweet
  spot if the wall fraction is meaningful.

DWT and entropy are already covered or capped; quantisation kernel
and colour transform are small enough that even a 2× speedup is
sub-1% wall.

### Phase 3 — C implementation (only if Phase 2 selects a target)

Same template as `J2KCodecNEON`:
- New SwiftPM C target (plain C, no C++).
- One `extern` entry point per hot path; caller-owned buffers.
- Bit-exact parity test sweep (500+ random fixtures) must pass before
  any timing measurement is reported.
- Cross-codec MD5 parity must hold with the C path enabled.
- Concurrent-contention probe must show no global-static contention.
- Env-var opt-in gate (`J2K_<TARGET>_C_PATH=1`); default off in
  research.

**Graduation matrix** (filled in per phase 2 target):
| Outcome | Decision |
|---------|----------|
| Parity gate fails | Block. Diagnose. |
| ≥2.0× single-stage speedup AND ≥10% wall reduction on warm DX | Graduate, flip default. |
| 1.3–2.0× speedup OR 5–10% wall reduction | Ship opt-in (env var default off). |
| <1.3× speedup OR <5% wall | Close as research artifact. |
| Worse than Swift | Close, document regression. |

### Phase 4 — write-up and decision

A `V10_0_<TARGET>_FINDING.md` with methodology, measurement,
decision; standard pattern matching V9_4, V9_5, V9_6.

## Out of scope for v10.0-research

- **Cross-stage fusion (DWT + quantise + entropy single-pass)**:
  multi-week architectural rewrite (V8_7 finding). Candidate for
  v11.0 if v10.0 closes negative.
- **GPU forward 9/7 default-on for the encoder**: M2 regression
  unresolved (per `project_path_c_outcome.md`); needs separate
  research arc.
- **AVX/AVX-512**: x86-only; Apple Silicon is ARM.
- **Decode-side optimisation**: positioned as marketable strength;
  no need to disturb (per v9.3 finding).
- **DICOM benchmark scripts cleanup**: separate tooling release.

## Schedule estimate

- **Day 1**: Phase 1a — extend J2KEncodeTimings to capture each
  non-entropy substage; verify telemetry is per-tile + per-worker
  safe.
- **Day 2**: Phase 1b — run on medical corpus and cross-codec
  corpus; collect numbers at 1, 4, 12 workers.
- **Day 3**: Phase 1c — analyse + write the wall budget report; make
  Phase 2 decision (target or close).
- **Days 4–8**: Phase 3 (only if a target was selected): C target +
  parity sweep + cross-codec MD5 gate + concurrent contention probe
  + measurement.
- **Day 9**: Phase 4 — write-up + graduation decision.

Total: 1–2 work-weeks. Research-mode scope.

## Open questions intentionally left to phase-2 judgement

- **Whether the target deserves a named release (v10.0.0) or ships
  as a quiet opt-in flag**: depends on the graduation matrix; user
  can override at the phase 4 decision point.
- **Whether to land the v9.9 image-stats predictor as part of
  v10.0 or as a separate v9.10 release**: v9.9 is currently
  research-on-branch; if its wall contribution is meaningful (which
  Phase 1 will show), bundling makes sense.

---

## Appendix — non-entropy hot-path map (file:line citations)

DWT 5/3 forward (lossless):
- `Sources/J2KCodec/J2KDWT1D.swift:202-244` — generic entry
- `Sources/J2KCodec/J2KDWT1D.swift:349-498` — inner lifting (autovec-friendly)
- `Sources/J2KCodec/J2KDWT2D.swift:170-275` — 2D single-level

DWT 9/7 forward (lossy):
- `Sources/J2KCodec/J2KDWT1D.swift:501-598` — `forwardTransform97`
- `Sources/J2KCodec/J2KDWT2D.swift:889-970` — 2D assembly
- `Sources/J2KMetal/J2KShaders.metal:6-123` — GPU kernels

Tier-2 packet encode:
- `Sources/J2KCodec/J2KTier2Coding.swift:225-291` — header + batch
- `Sources/J2KCodec/J2KTier2Coding.swift:97-200` — quality-layer PCRD

Colour transform:
- `Sources/J2KCodec/J2KColorTransform.swift:139-200` (RCT scalar)
- `Sources/J2KCodec/J2KColorTransform.swift:348-396` (RCT batch)
- `Sources/J2KCodec/J2KColorTransform.swift:464-604` (ICT scalar)

Quantisation:
- `Sources/J2KCodec/J2KQuantization.swift:851-933`
- `Sources/J2KCodec/J2KTrellisQuantizer.swift` (entire — 638 lines, unmeasured)

Existing microbenches to reuse / extend:
- `Tests/J2KCodecTests/V96DWTMicrobenchTests.swift`
- `Tests/J2KCodecTests/J2KColorTransformBenchmarkTests.swift`
- `Tests/J2KMetalTests/J2KMetalDWT53IntBenchmarkTests.swift`
- `Tests/J2KMetalTests/Tier2WritePacketSubstageProfileTests.swift`

Prior findings to read before Phase 1:
- `V8_6_FORWARD_DWT_FINDING.md` (DWT 5/3 ceiling)
- `V8_7_ENCODER_REDESIGN_FINDING.md` (encoder wall split)
- `V9_4_NEON_HOT_PATH_RESEARCH.md` (autovec-ceiling lesson)
- `V9_5_*_FINDING.md` (per-quad assumption miss)
- `V9_6_QSTEP_CACHE_FINDING.md` (current baseline)
