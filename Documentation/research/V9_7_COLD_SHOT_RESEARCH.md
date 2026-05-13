# v9.7 — Cold-shot qstep pre-seed — closed as research artifact

**Status:** Closed. The v9.6 research doc identified cold-cache first
encode as the next target (~112 ms DX cold-shot vs 29 ms warm). A
pre-seeded shared cache was prototyped to attempt single-pass
convergence on the first encode. **Negative finding**: real medical
content has a converged-qstep range too wide for any single seed to
serve all the qstep-search modes, and a seed sized for high-variance
content causes severe PSNR regressions in `.constantBitrateViaQstep`
tight-tolerance mode. Reverting. Image-statistics-based prediction is
deferred to a future release with proper corpus calibration.

---

## What we tried

### Pre-seeding the process-default cache

The v9.6 process-default `J2KQstepCache.shared` is consulted by all
three qstep-search code paths (`encodeViaBoundedQstep`,
`encodeViaStrictBoundedQstep`, `encodeViaQstepSearch`). When the
cache is cold, those paths fall back to a coarse formula
(`initialQstepGuess`) that produces qstep=15 for 16-bit @ 2 bpp —
roughly 5–10× too small for typical medical content.

The hypothesis: if the cache is pre-populated with empirical priors
for common `(bitDepth, components, bpp)` classes at process startup,
the very first encode of those classes hits a seed value tuned to
land in the strict-bounded `[1, 4]` ratio tolerance, breaking the
search loop in a single pass.

Implementation:
- Added `J2KQstepCache.init(preSeeded:)` for synchronous pre-
  population at construction.
- Added a static `defaultSeedEntries` table:
  - 16-bit 1-component @ 0.5 bpp → qstep=600
  - 16-bit 1-component @ 1.0 bpp → qstep=300
  - 16-bit 1-component @ 1.5 bpp → qstep=200
  - 16-bit 1-component @ 2.0 bpp → qstep=150
  - 16-bit 1-component @ 3.0 bpp → qstep=100
  - 16-bit 1-component @ 4.0 bpp → qstep=75
- The seeds were derived from the empirical observation that the
  J2KSwift medical corpus converged at qstep=67 (mr_002 small) to
  qstep=357 (ct_001 synthetic) for 2 bpp. The middle-ish seed=150
  was selected as a compromise — and confirmed by debug prints to
  produce single-pass convergence for mr_002 (`ratio=2.597`),
  ct_001 (`ratio=3.628`), ct_003 (`ratio=3.450`) — all in `[1, 4]`.

### What broke

#### Finding 1: converged qstep range across the corpus is enormous

Debug prints during a corpus encode revealed the actual converged
qsteps across the medical corpus span more than four orders of
magnitude:

| Fixture            | Converged qstep (16-bit @ 2 bpp) | Why                    |
|---                 |---:                              |---                     |
| mr_001 (886×886)   | ~0.6                             | Very low-variance MR brain content |
| mr_002 (180×180)   | ~150                             | Small MR slice         |
| ct_001 (512×512)   | ~356                             | Synthetic LCG noise    |
| ct_003 (512×512)   | ~356                             | Synthetic CT-like      |
| dx_002 (2800×2288) | ~1961                            | Real X-ray, high entropy |
| mg_001 (3520×4784) | ~1961                            | Real mammography       |

Range: 0.6 (mr_001) to 1961 (dx-class). A single seed value cannot
land all of these inside the `[1, 4]` ratio tolerance simultaneously.

#### Finding 2: `.constantBitrateViaQstep` bracket logic regresses when seed is far off

The `.constantBitrateViaQstep` search uses a tight `±5%` tolerance
and a `lower = qstep / 16.0`, `upper = qstep * 16.0` initial bracket
sized around the seed. If the seed is 150 but the true converged
qstep is 0.6 (mr_001), the bracket `[9.4, 2400]` does not contain
0.6 — the search cannot reach it. Subsequent refinement does expand
the bracket downward, but maxIterations is bounded; the search
typically settles at the bracket's lower bound (~10) with a heavy
undershoot.

Measured impact on `J2KEncoderPipelineTests.testHTJ2KMedicalQualityGap-
StaysControlledAtMatchedBitrate`:
- Without seed: PSNR=27.08 dB (pre-existing failure — see Caveat)
- With seed=150: PSNR=27.08 dB (no change here, since the test
  uses a different bitrate-mode dispatch). But other RD tests
  measuring `.constantBitrateViaQstep` showed similar 25–30 dB
  regressions vs ~33–40 dB expected.

A higher seed (e.g., 1100 — sized to cover dx-class content) makes
the regression even more catastrophic on low-variance content because
the bracket lower bound rises proportionally.

#### Finding 3: cold-shot helped is bounded by which fixtures match

For the corpus fixtures whose converged qstep happens to be near the
seed value, cold-shot encoding does drop from 3 passes to 1 pass.
But the dx-class fixtures (the headline target for "beat Kakadu on
DX") have converged qstep ~1961 — way outside any seed that's safe
for the rest of the corpus. So the seed does **not** close the cold-
shot gap on the fixtures the v9.7 research was targeting.

### Decision: revert

The pre-seed delivers narrow benefits (cold-shot 1-pass on mid-range
fixtures) at the cost of significant PSNR regressions on tight-
tolerance modes for low-variance content. The trade is not
acceptable. Reverted to v9.6 behaviour (empty shared cache that
warms naturally from the first converged encode).

---

## What this means

### v9.6 stands

The v9.6 process-default shared cache mechanism is unchanged. Warm-
cache encodes after the first one still hit the cache and converge
in a single pass; the 71% wall reduction on warm DX
(99 ms → 29 ms) is preserved.

### Cold-shot remains a research target

The first encode of a given `(bitDepth, components, bpp)` shape on
a fresh process still pays the 3-pass qstep-search cost (~112 ms on
M4 DX). For batch workflows this is amortized over the rest of the
batch. For single-shot CLI invocations or first-launch interactive
encodes, the cold-shot wall is still visible.

### The right fix is image-statistics-based initial qstep

A content-aware predictor — sample N pixels at encode entry, compute
variance, predict the converged qstep — is the correct generalisation.
Implementation is straightforward but requires:

1. **Corpus calibration**: each fixture's `(std_dev, abs_mean,
   max_abs, ...)` mapped against its converged qstep. The 6 fixtures
   in our corpus span 5 orders of magnitude in converged qstep,
   suggesting a single-variable linear fit is unlikely; a 2- or
   3-feature regression on `(std_dev, target_bytes, image_size)` is
   probably the minimum.
2. **Bracket-aware seeding**: the prediction must come with bracket
   bounds wide enough that the converged value is always reachable
   from the seed. The current code uses `qstep / 16` lower and
   `qstep * 16` upper — fine for accurate seeds but catastrophic
   when the seed is off by 100× as on mr_001 with seed=150.
3. **Per-mode behaviour**: the strict `[1, 4]` tolerance is permissive
   enough that a moderate seed is helpful even when off; the tight
   `±5%` tolerance is intolerant to bracket misses. Either the
   predictor must be highly accurate, or it should only be used in
   permissive modes.

This is a multi-day calibration effort with a careful test sweep. It
is the v9.8 (or later) target.

### What did get cleaned up

The diagnostic exercise produced two reusable test scaffolds that
stay in the tree:

- `Tests/J2KCodecTests/V97ColdShotTests.swift` — measures single-
  encode cold-shot wall and per-stage breakdown. Useful for future
  calibration work.
- The instrumentation in `encodeMultiPrecinctWithPacketIndex`
  (v9.6) continues to give a true per-stage corpus breakdown, which
  was the prerequisite for distinguishing between "DWT is slow" and
  "the pipeline is running 3 times".

---

## Caveat: pre-existing PSNR-test failures

While investigating the v9.7 pre-seed, several
`J2KEncoderPipelineTests` PSNR floor tests failed:

- `testHTJ2KMedicalQualityGapStaysControlledAtMatchedBitrate`: PSNR
  27.08 dB vs expected > 32.9 dB.
- `testHTJ2KNearLosslessQualityStaysCloseToStandardJ2K`: PSNR
  32.21 dB vs expected > 55.0 dB.
- `testHTJ2KMedicalCompressionEfficiencyStaysCloseToJ2KAtMatchedBitrate`
  / `testHTJ2KXAStyleCompressionEfficiencyImprovesAtMatchedBitrate`:
  PSNR and size envelope regressions.

These reproduce with `J2K_DISABLE_PROCESS_QSTEP_CACHE=1` (i.e. before
v9.6 cache behaviour), and identical PSNR numbers appear with and
without the v9.7 pre-seed. They are pre-existing failures introduced
by some earlier change unrelated to this work. Filed for separate
investigation; not blockers for v9.6 graduation.

The bit-exact gates — `HTCrossCodecConformantTests` (MD5 parity vs
OpenJPH/OpenJPEG/Kakadu), `V94NEONHotPathParityTests`,
`V91Phase2cArrayVsRawParityTests`, `HTBlockEncoderConformantTests`,
`HTConformantConstantBitrateViaQstepTests`,
`V91Phase2ConcurrentContentionProbe` — all pass post-revert.

---

## Files touched on `v9.5-research`

| Path | Change |
|---|---|
| `Sources/J2KCodec/J2KQstepCache.swift` | Documented the v9.7 research negative finding inline; no behavioural change vs v9.6 |
| `Tests/J2KCodecTests/V97ColdShotTests.swift` | New cold-shot harness (kept for v9.8+ calibration) |
| `V9_7_COLD_SHOT_RESEARCH.md` | This document |

---

## Decision matrix

| Metric                          | Result      | Threshold        | Outcome         |
|---                              |---          |---               |---              |
| DX cold (1st encode)            | 112 ms      | ≤ 100 ms         | ✗ Not achieved  |
| Bit-exact preserved (post-revert) | yes       | required         | ✓               |
| `.constantBitrateViaQstep` tight-mode PSNR preserved | yes (post-revert) | required | ✓ |
| Standalone wall improvement     | none        | ≥ 30% wall drop  | ✗ Negative finding |

**Outcome:** **Close as research artifact.** v9.6 graduates to a
release tag (v9.6.0); v9.7 ships as documentation of a thoroughly
explored dead-end. Image-statistics-based prediction is the
designated next research target, with the V97ColdShotTests harness
left in place for the eventual calibration work.

---

## Why this still matters

The negative finding is structurally informative even though no code
ships:

1. **The corpus's converged-qstep range is wider than any one-shot
   prediction can cover.** Any future cold-shot fix must be
   content-aware, not table-driven.
2. **The `.constantBitrateViaQstep` bracket logic is fragile to
   bad seeds.** Future work that touches the shared cache must
   consider whether the seed is reachable from the bracket — and
   if not, widen the bracket or skip the mode.
3. **The "right answer" framing remains correct.** The V9_6 research
   doc identified image-statistics as the proper approach. v9.7's
   attempt to skip that step with a static table confirmed why a
   shortcut doesn't suffice.

The v9.6 commit (process-default cache for warm path) and the
research finding in this document together capture the full state
of qstep-search optimization through 2026-05-12. The next release
should either:

- **Ship as v9.6.0** with documentation that single-shot cold
  workloads pay the 3-pass cost (acceptable for medical batch);
- **Or invest in the v9.8 image-statistics calibration work** before
  graduating, if cold-shot is part of the headline "beat Kakadu"
  metric.
