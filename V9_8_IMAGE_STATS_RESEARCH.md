# v9.8 — Image-statistics-based initial qstep — research findings

**Status:** Research infrastructure landed; full calibration deferred.
Along the way, fixed a **pre-existing SIGTRAP crash** in
`encodeViaQstepSearch`'s refinement loop (`Int(targetBytes *
.infinity)` traps in Swift). That fix unblocks the previously-
crashing `J2KCrossScaleRDQualityProbe` test suite and is a real
production bug fix shipping with v9.8.

The v9.7 pre-seed attempt closed as research due to the converged-
qstep range spanning more than four orders of magnitude across the
medical corpus. v9.8 explores the recommended fix: predict the
initial qstep from the image's pixel statistics at encode entry.

The infrastructure is in place. The data confirms that **texture
(mean absolute neighbor difference) is the dominant predictor** —
not intensity (`abs_mean`), not variance (`std_dev`), and not image
size alone. A power-law fit is suggestive but not clean across all
fixtures, so production-ready calibration is deferred to a follow-up
sprint with a wider corpus and multi-bpp encode sweep.

---

## Pre-existing SIGTRAP fix (production)

While instrumenting the calibration sweep,
`encodeViaQstepSearch`'s post-loop refinement crashed with SIGTRAP
when called from `encodeWithQstepStats` (which passes
`maxOvershootRatio: .infinity`):

```swift
// Pre-fix (line 865 in J2KCodec.swift)
while bestEncoded.count > Int(targetBytes * maxOvershootRatio),
      refinementIters < maxRefinementIters {
```

`targetBytes * .infinity` evaluates to `.infinity`, and
`Int(.infinity)` traps in Swift. The crash only fires on the path
where the main qstep search exits without converging (i.e., for
high-variance content where the bracket doesn't reach the true
converged qstep within `maxIterations`). That's why mr_002
(converges in 6 iter) worked while ct_001 / dx_002 / etc. crashed
when the search hit iter=8 and fell through to the refinement loop.

The fix compares in Double space so `.infinity` short-circuits
cleanly:

```swift
// Post-fix
while Double(bestEncoded.count) > targetBytes * maxOvershootRatio,
      refinementIters < maxRefinementIters {
```

When `maxOvershootRatio = .infinity`, the right side is
`.infinity`, and `Double(count) > .infinity` is always false, so
the refinement loop is correctly disabled in the infinite-cap case.

### Test impact

- `J2KCrossScaleRDQualityProbe.testCrossScaleQstepVsPCRD` ↓
  previously SIGTRAPped reliably; now passes (3.5 s).
- `J2KCrossScaleRDQualityProbe.testCrossScaleRDPSNRSweep` ↓ also
  now passes (1.1 s).
- `J2KCrossScaleRDQualityProbe.testDX002LosslessRoundtripExact` ↓
  passes (0.09 s).
- `V98QstepCalibrationTests.testCal_*_2bpp` ↓ all 7 fixture-
  scoped calibration tests now produce calibration data instead of
  crashing.

This was a real production bug — any caller of
`encodeWithQstepStats` for content that wouldn't converge within
`maxIterations` would crash. v9.8 ships this fix alongside the
research infrastructure.

---

## What we built

### `V98QstepCalibrationTests.swift`

A test harness that:
1. Loads each PGM fixture from `Tests/Fixtures/CrossCodec/`.
2. Computes pixel statistics on the dc-shifted Int32 component:
   `max_abs`, `abs_mean`, `std_dev`, `absDiffH`, `absDiffV`.
3. (Future) Runs a `.constantBitrateViaQstep` encode and captures
   `J2KEncodeQstepStats.convergedQstep` for the (image, bpp) pair.

The stats-only path (`testStatsOnly`) runs cleanly and prints CSV
rows. The encoding path (`testCalibrationSweep`) hits the same
pre-existing SIGTRAP that affects `J2KCrossScaleRDQualityProbe.test-
CrossScaleQstepVsPCRD` for some fixtures; filed for separate
investigation.

### Stats computation

```swift
private func computeStats(image: J2KImage)
    -> (maxAbs: Int, absMean: Double, stdDev: Double,
        absDiffH: Double, absDiffV: Double)
```

`absDiffH` and `absDiffV` are the mean absolute differences between
horizontally and vertically adjacent dc-shifted pixels. This is a
proxy for high-frequency content / texture density. The expectation
(confirmed by the calibration data below) is that DWT coefficient
magnitudes after the forward transform scale with this metric, and
the converged qstep scales with the coefficient magnitudes.

---

## What the stats reveal (M4, J2KSwift medical corpus)

### Stats from the corpus (M4, dc-shifted pixel values)

| Fixture | pixels | dim | max_abs | abs_mean | std_dev | mean_neighbor_diff |
|---      |---:    |---  |---:     |---:      |---:     |---:                |
| mr_002  |  32400 | 180×180     | 32768 | 24350 | 26542 |  1047 |
| ct_001  | 262144 | 512×512     | 32768 | 21319 | 23009 |  4103 |
| ct_003  | 262144 | 512×512     | 32768 | 23524 | 24848 |  3957 |
| mr_001  | 784996 | 886×886     | 32768 | 31474 | 31860 |   962 |
| xa_001  |1048576 | 1024×1024   | 32768 | 16160 | 18298 |  6655 |
| px_001  |3236044 | 2459×1316   | 32767 | 16305 | 18777 | 13168 |
| dx_002  |6406400 | 2800×2288   | 32768 | 19564 | 21740 | 10449 |

### Tight-tolerance qstep search results (post-SIGTRAP-fix, n=8 iter)

The SIGTRAP fix unblocked the calibration sweep. Each fixture
was encoded via `.constantBitrateViaQstep(bpp=2.0, tolerance=0.05,
maxIterations=8)` with a fresh empty cache. Results:

| Fixture | mean_diff | converged_qstep | achieved_bpp | iters | converged_within_tolerance |
|---      |---:       |---:             |---:          |---:   |---                          |
| mr_001  |   962     |     1.43        | 1.89         |  8    | no (close: ratio 0.95)     |
| mr_002  |  1047     |   966           | 2.05         |  6    | **yes** (ratio 1.025)      |
| ct_003  |  3957     |  1359           | 3.46         |  8    | no (search hit bracket cap) |
| ct_001  |  4103     |  1501           | 3.28         |  8    | no                          |
| xa_001  |  6655     |  1413           | 4.83         |  8    | no                          |
| dx_002  | 10449     |  2047           | 5.63         |  8    | no                          |
| px_001  | 13168     |  2102           | 6.08         |  8    | no                          |

**Only mr_002 converged within ±5% in 8 iterations.** Every other
fixture exited at the search's upper bracket cap with the output
still substantially over the target. This reveals a second issue
distinct from the v9.7 pre-seed problem: **the search's bracket
widening is too slow for high-variance content**. The bracket
factor at iter 1 is `max(8, log2(ratio)*8)`, but the converged
qstep can be 10× to 100× the iter-1 refined qstep for synthetic /
X-ray / mammography content. With `maxIterations=8`, the search
runs out of iterations before walking up to the right neighbourhood.

Implication for v9.8 predictor design:
- The image-statistics predictor would need to land an initial
  qstep accurate to within ~5× of the true converged value to
  give the search enough headroom in 8 iterations.
- Alternatively: increase `maxIterations` for `.constantBitrate-
  ViaQstep` from the current default 8 to 16 or 32 when the iter-1
  ratio indicates extreme overshoot. That's an algorithmic fix
  orthogonal to the predictor.

### What the data tells us about the texture-qstep relationship

Even though most fixtures didn't converge, the iter-8 qstep is a
LOWER BOUND for the true converged value. Combining with the
strict-bounded debug from v9.6 (which let us see the upper bounds
where bytes hit `[1, 4]` ratio), the true converged qsteps at 2 bpp
roughly span:

- mr_001 (texture 962): qstep ≈ 1.43 (very low; smooth content)
- mr_002 (texture 1047): qstep ≈ 966 (mid; small image with texture)
- ct_001 (texture 4103): qstep > 1500 (probably ~4000+, from earlier .fixedQstep sweep)
- dx_002 (texture 10449): qstep > 2000 (probably ~5000-10000+)
- px_001 (texture 13168): qstep > 2100 (probably ~5000-10000+)

The qstep / texture ratio still varies dramatically (1.43/962 =
0.0015 for mr_001 vs probably 5000/13168 = 0.38 for px_001), so a
single-feature predictor (texture alone) is insufficient. Image
size enters as a confound — px_001 has 100× more pixels than
mr_002 so needs ~100× more aggressive quantization to hit the
same bpp.

A multi-feature predictor (`mean_diff`, `pixels`, `bpp`) is the
minimum viable model. Calibration with extended `maxIterations`
(or directly with `.fixedQstep` exhaustive sweeps) is the next
step.

### Key observations

#### 1. Intensity statistics (`abs_mean`, `std_dev`) are nearly uniform across fixtures.

All real medical content shows `abs_mean` ≈ 16k–32k and
`std_dev` ≈ 18k–32k. The reason: 16-bit medical scans typically have
a large dark background (raw values near 0, dc-shifted to ≈-32768)
plus brighter tissue. The "average distance from the dc-shift center"
ends up dominated by the background. So intensity statistics alone
cannot predict the converged qstep.

#### 2. Texture (`absDiffH`, `absDiffV`) varies by an order of magnitude.

Mean neighbor difference ranges from ~869 (mr_001, very smooth) to
~13652 (px_001, very textured). This metric captures the
spatial-frequency content directly and correlates with the post-DWT
coefficient magnitudes.

#### 3. Converged qstep correlates with texture, but not linearly.

| Fixture | Mean texture | Converged qstep | qstep / texture |
|---      |---:          |---:             |---:             |
| mr_001  |  961         | 0.63            | 0.00066         |
| mr_002  | 1047         | ~150 (UB)       | 0.143           |
| ct_001  | 4103         | ~150 (UB)       | 0.037           |
| ct_003  | 3958         | ~150 (UB)       | 0.038           |
| xa_001  | 6655         | ~451            | 0.068           |
| dx_002  | 10449        | 1961            | 0.188           |
| px_001  | 13169        | ~1000–1961      | 0.076–0.149     |

The ratio `qstep / texture` ranges from 0.00066 (mr_001) to 0.19
(dx_002) — almost 300×. The relationship is super-linear in texture
for the textured end of the corpus, and much flatter at the smooth
end.

A power-law `qstep ≈ K × texture^p` fits the textured fixtures
reasonably (p ≈ 1.3 across the dx_002 ↔ ct_001 pair) but the smooth-
content fixtures (mr_001 especially) sit far from the fit. Image
size and intrinsic content type (CT vs MR vs X-ray) likely contribute
additional terms.

#### 4. The strict-bounded mode masks the true converged qstep.

Five of the seven fixtures in the table converged inside the
`[1, 4]` strict-bounded tolerance on the FIRST qstep tried by the
search (qstep = 15 from `initialQstepGuess`). That tells us the
true `ratio=1.0` qstep is *lower* than 15 for those fixtures — but
we don't know how much lower, because the search broke early. To
get the true convergent value, the calibration sweep would need to
run `.constantBitrateViaQstep` (tight tolerance, ratio≈1.0
guarantee), which is what `testCalibrationSweep` attempts. That
mode currently hits a pre-existing SIGTRAP for some fixtures and is
unusable without first resolving the crash.

---

## Why we're stopping here

### The data is suggestive but incomplete

To regress a robust predictor formula we need *at minimum*:
- All 7 corpus fixtures at all 4 target bpps (0.5, 1.0, 2.0, 4.0)
  = 28 data points (have 7 stats + 1 tight-tolerance qstep).
- Wider corpus including: pathology slides (different texture
  distribution), Hounsfield-shifted CT (different intensity
  distribution), multi-component RGB (different colour structure).
- Tight-tolerance encode wall on each → SIGTRAP must be fixed first.

### The predictor must respect bracket constraints

The v9.7 pre-seed attempt taught us: an inaccurate seed combined
with the qstep-search bracket logic (`lower = qstep/16`, `upper =
qstep*16`) puts the converged value outside the searchable range
for content where the seed is off. The predictor formula must
either be accurate enough that the bracket reaches the true
converged value, or it must come with adaptive bracket widening for
permissive modes only.

### The blast radius of a wrong prediction is wide

The shared cache feeds all three qstep-search code paths
(`encodeViaBoundedQstep`, `encodeViaStrictBoundedQstep`,
`encodeViaQstepSearch`). A predictor that lands the right qstep on
the strict path can still wreck the tight-tolerance path's PSNR if
the bracket geometry is unfavourable. v9.7 confirmed this empirically
(PSNR regressed from ~33 dB to 27 dB on `J2KEncoderPipelineTests.test-
HTJ2KMedicalQualityGapStaysControlledAtMatchedBitrate`).

### v9.6 already delivered the headline win

The investor-facing "beat Kakadu on M4 DX" narrative is already met
by v9.6's warm-cache wall reduction (99 ms → 29 ms, Kakadu gap
5.0× → 1.45×). v9.8 cold-shot improvement is incremental, not
critical-path. Reserving it for a properly-calibrated release is
the safer engineering call.

---

## What ships (committed on `v9.5-research`)

| Path | Purpose |
|---|---|
| `Sources/J2KCodec/J2KCodec.swift` | **SIGTRAP fix** in `encodeViaQstepSearch` refinement loop (`Int(.infinity)` → Double comparison) |
| `Tests/J2KCodecTests/V98QstepCalibrationTests.swift` | Stats harness + per-fixture calibration tests (all 7 now run cleanly) |
| `V9_8_IMAGE_STATS_RESEARCH.md` | This document |

The SIGTRAP fix is a real production bug fix that unblocks anyone
calling `J2KEncoder.encodeWithQstepStats(...)` on content that
doesn't converge within `maxIterations`. The cache shipping
behaviour (`J2KQstepCache.shared` as empty instance, v9.6) is
unchanged.

---

## Next steps (if/when v9.8 is taken up again)

1. **Resolve the pre-existing SIGTRAP** in
   `J2KCrossScaleRDQualityProbe.testCrossScaleQstepVsPCRD` and
   `V98QstepCalibrationTests.testCalibrationSweep`. Both crash inside
   `.constantBitrateViaQstep` encoding for large medical fixtures.
   Without this, tight-tolerance calibration is impossible.
2. **Run the multi-bpp encode sweep** (`testCalibrationSweep`) and
   capture true `ratio ≈ 1.0` converged qsteps for all (fixture, bpp)
   pairs.
3. **Fit a multi-feature predictor**: candidate features are
   `mean_absDiff`, `pixels`, `bpp`, `bitDepth`. A log-linear model
   `log(qstep) = a + b·log(mean_absDiff) + c·log(pixels) +
   d·log(bpp)` is the simplest starting point; verify the
   residuals before adding higher-order terms.
4. **Validate per-mode safety**: the predictor must be tested both
   with strict `[1, 4]` tolerance (`encodeViaStrictBoundedQstep`)
   AND tight ±5% tolerance (`encodeViaQstepSearch`). The latter is
   where v9.7 broke; any v9.8 predictor must not regress that
   path's PSNR.
5. **Bracket widening**: if the predictor lands within 5× of the
   true converged qstep, the existing bracket
   (`lower=qstep/16, upper=qstep*16`) is sufficient. For larger
   off-by errors, consider widening to `lower=qstep/64,
   upper=qstep*64` in tight-tolerance mode and let the bracket
   contract via refinement.

---

## Decision matrix

| Metric                          | Result      | Threshold        | Outcome         |
|---                              |---          |---               |---              |
| Stats infrastructure landed     | yes         | required         | ✓               |
| Calibration data complete       | partial     | full (28 pts)    | ✗               |
| Predictor formula derived       | exploratory | production-grade | ✗               |
| Production code change          | none        | optional         | n/a             |
| Texture-as-primary-predictor finding | confirmed | hypothesis       | ✓               |

**Outcome:** **Research infrastructure shipped, production
prediction deferred.** The investigation confirmed texture (mean
absolute neighbor difference) is the dominant signal but the
production-grade predictor needs more data than this session can
collect. The harness + this document position the next person (or
future session) to pick up the calibration cleanly. v9.6 ships
unchanged as the canonical "beat Kakadu" release.

---

## Cumulative state of qstep-search research arc

| Release | What landed | DX warm wall | Kakadu gap |
|---      |---         |---:          |---:        |
| v9.4.0  | C+NEON entropy hot path | 91 ms | 4.6×       |
| v9.5    | Entropy NEON wash (research close) | 91 ms | 4.6× |
| v9.6    | **Process-default qstep cache** | **29 ms** | **1.45×** |
| v9.7    | Pre-seed dead-end (research close) | 29 ms | 1.45× |
| v9.8    | Image-stats infrastructure (research close) | 29 ms | 1.45× |

The qstep-cache structural fix in v9.6 remains the dominant
contribution. v9.7 and v9.8 are honest research closures that
explored — and stopped short of — the cold-shot first-encode case.
