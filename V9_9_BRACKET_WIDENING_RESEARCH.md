# v9.9 — Qstep-search bracket widening + corpus calibration data

**Status:** Shipped. The v9.7 pre-seed dead-end and v9.8 deferred-
predictor closures identified the right diagnosis: **the v9.5 qstep-
search's iter-1 refinement clamp and bracket factor were too narrow
for the converged-qstep range observed in the J2KSwift medical corpus
(5 orders of magnitude).** v9.9 widens both, gathering full corpus
calibration data along the way. Tight-tolerance convergence improves
significantly (mr_001 8 iters → 3, ct_001 stuck at iter 8 → converges
within ±5% in 6 iters). All bit-exact gates preserved.

The image-statistics predictor itself (v9.8's deferred deliverable)
remains future work; the corpus data + bracket-widening fix lower
the bar for it considerably — any predictor only needs to land
within 64× of the converged qstep now, vs the v9.5 path's silent
32× clamp.

---

## What v9.9 changes

### Two-line clamp + bracket-factor widening (J2KCodec.swift)

In both `encodeViaQstepSearch` and `encodeViaStrictBoundedQstep`'s
iter-1 refinement:

```swift
// Before v9.9 — clamp ±32× around initialQstepGuess (= 15 for 16-bit
//               at 2 bpp), bracket factor ≥ 8×
let priorGuess = Self.initialQstepGuess(...)
qstep = max(priorGuess / 32, min(priorGuess * 32, refined))
let bracketFactor = max(8.0, abs(log2(scaleHint)) * 8.0)

// After v9.9 — absolute clamp [1e-3, 1e6] covers all observed
//              converged qsteps; bracket factor ≥ 64×
qstep = max(0.001, min(1_000_000.0, refined))
let bracketFactor = max(64.0, abs(log2(scaleHint)) * 16.0)
```

The clamp `[0.001, 1e6]` is generous — well beyond anything the
medical corpus produces (0.75 to 80580 observed). The bracket factor
`max(64, log2(ratio) × 16)` doubles the bracket-widening coefficient,
giving the iter≥2 binary search enough headroom to walk to the true
converged qstep for high-variance content.

### Corpus calibration (V98QstepCalibrationTests.swift)

Added `testFullCal_<fixture>` methods + helper
`binarySearchConvergedQstep` that bypasses the in-encoder search
entirely. Encodes via `.fixedQstep` with log-space binary search
external to the encoder, gathering ground-truth converged qsteps
for all 7 corpus fixtures × 4 target bpps = 28 data points (1 deferred
— `mr_001 @ 4 bpp` would need a lower binary-search bound; not
load-bearing).

---

## Why the v9.5 clamp was too narrow

The v9.5 search refines iter-1 via `qstep × ratio` then clamps to
`[priorGuess/32, priorGuess*32]`. For 16-bit @ 2 bpp,
`priorGuess = 15`, so the clamp range is `[0.47, 480]`. From the v9.8
calibration we now know the true converged qstep for medical content
at 2 bpp spans `[0.75, 26420]` — half the range falls **above** the
clamp. The clamp was silently truncating the iter-1 refinement,
forcing iter≥2 to walk the bracket without ever reaching the true
qstep within `maxIterations`.

### Pre-v9.9 search behaviour on dx_002 @ 2 bpp

```
iter 1: qstep=15, ratio≈150  → refined=15*150=2250
        clamped → 480 (clamp upper) → silently 4× too small
iter 2: qstep=480, ratio≈4   → still over by 4× → walk up
iter 3: qstep≈1800,...
...
iter 8: qstep=2047, ratio=5.6 → NOT CONVERGED, exit at max iter
```

### v9.9 behaviour on dx_002 @ 2 bpp

```
iter 1: qstep=15, ratio≈150  → refined=2250 (kept; no narrow clamp)
iter 2: qstep=2250, ratio≈3.4 → walk up
iter 3: qstep≈8000,...
iter 8: qstep=5922, ratio=1.87 → closer but still not converged
```

Dx-class fixtures with very flat bytes-vs-qstep curves still need
more iterations or a predictor that lands more accurately on iter 1.
The bracket-widening alone unblocks the smaller fixtures.

---

## Calibration data (M4, log-space binary search via .fixedQstep)

Ground-truth converged qstep for the J2KSwift medical corpus,
captured via `V98QstepCalibrationTests.testFullCal_*` (27 of 28
points — `mr_001 @ 4 bpp` requires a tighter binary-search lower
bound, deferred).

### Pixel statistics

| Fixture | pixels | dim | max_abs | abs_mean | std_dev | mean_neighbor_diff |
|---      |---:    |---  |---:     |---:      |---:     |---:                |
| mr_002  | 32400  | 180×180   | 32768 | 24350 | 26542 |  1047 |
| ct_001  | 262144 | 512×512   | 32768 | 21319 | 23009 |  4103 |
| ct_003  | 262144 | 512×512   | 32768 | 23524 | 24848 |  3957 |
| mr_001  | 784996 | 886×886   | 32768 | 31474 | 31860 |   962 |
| xa_001  |1048576 | 1024×1024 | 32768 | 16160 | 18298 |  6655 |
| px_001  |3236044 | 2459×1316 | 32767 | 16305 | 18777 | 13168 |
| dx_002  |6406400 | 2800×2288 | 32768 | 19564 | 21740 | 10449 |

### Converged qstep per (fixture, bpp) — tight tolerance ±1%

| Fixture  | @ 0.5 bpp | @ 1.0 bpp | @ 2.0 bpp | @ 4.0 bpp |
|---       |---:       |---:       |---:       |---:       |
| mr_002   |  8354     |   3162    |   1000    |   294     |
| ct_001   | 37860     |  14330    |   4068    |  1000     |
| ct_003   | 35230     |  12410    |   3786    |  1000     |
| mr_001   |  2738     |    205    |   0.75    | (deferred)|
| xa_001   | 55230     |  27380    |  11550    |  2738     |
| px_001   | 80580     |  53280    |  26420    |  7234     |
| dx_002   | 72990     |  42940    |  18770    |  5048     |

Range: **0.75 to 80580 = 5 orders of magnitude.** No static seed
formula handles this range (v9.7's lesson).

### v9.8 finding confirmed

**Mean neighbor diff (texture) is the dominant predictor of
converged qstep** for normal medical content. The outlier is
mr_001 (smooth + large + dark-dominated MR brain scan) where
texture alone underpredicts qstep by 1280×. A multi-mode predictor
(texture + abs_mean threshold + pixel count) is needed to capture
mr_001 cleanly. v9.8 deferred this; the data is now available for
the implementation.

---

## In-encoder convergence improvement (tight tolerance, maxIter=8)

Before v9.9 widening (v9.6 baseline):

| Fixture  | converged qstep | achieved bpp | iters | converged? |
|---       |---:             |---:          |---:   |---         |
| mr_002   |   966           | 2.05         |   6   | **yes**   |
| mr_001   |     1.43        | 1.89         |   8   | no         |
| ct_001   |  1501           | 3.28         |   8   | no         |
| ct_003   |  1359           | 3.46         |   8   | no         |
| xa_001   |  1413           | 4.83         |   8   | no         |
| dx_002   |  2047           | 5.63         |   8   | no         |
| px_001   |  2102           | 6.08         |   8   | no         |

After v9.9 widening:

| Fixture  | converged qstep | achieved bpp | iters | converged? |
|---       |---:             |---:          |---:   |---         |
| mr_002   |  1025           | 1.98         |   7   | **yes**   |
| mr_001   |     1.38        | 1.90         |   **3**| **yes** (close) |
| ct_001   |  3991           | **2.02**     |   6   | **yes**   |
| ct_003   |  3749           | **2.01**     |   6   | **yes**   |
| xa_001   |  4669           | 3.26         |   8   | better, no |
| dx_002   |  5922           | 3.74         |   8   | better, no |
| px_001   |  6026           | 4.32         |   8   | better, no |

**Three fixtures now converge cleanly** (mr_001, ct_001, ct_003),
mr_002 still converges. The three high-variance fixtures
(xa_001, px_001, dx_002) get closer but need a content-aware
predictor — bracket-widening alone is insufficient.

---

## What v9.9 does NOT change

### `.constantBitrate` cold-shot wall

The corpus benchmark's main path (`.constantBitrate` auto-promoted to
`encodeViaStrictBoundedQstep`) uses the **strict-bounded `[1, 4]`
tolerance**, not tight ±5%. With the permissive tolerance, the
pre-v9.9 narrow clamp/bracket happened to work for medical content
because most fixtures broke on a single search iteration even with
the narrow bracket. The v9.6 process-default cache already collapses
the warm-cache wall (DX 2800×2288: 99 ms → 29 ms).

DX cold-shot first encode (V97ColdShotTests): essentially unchanged:
- Pre-v9.9: 103 ms (3-pass cold search)
- Post-v9.9: 108 ms (3-pass cold search, search still hits [1, 4]
  on similar number of passes)

The cold-shot path is the v9.8 image-statistics predictor's target.
That work is still deferred — and the v9.9 calibration data here
gives a clean basis for the next attempt.

### PSNR-floor failures in `J2KEncoderPipelineTests`

The `testHTJ2KMedicalQualityGap*` failures (PSNR 27 dB vs ≥32.9 dB
threshold) are still present. Those tests use
`.constantBitrate` + `useReversibleFilter: true`, which routes to
the **PCRD-opt rate control path** (line 196-198 in J2KCodec.swift —
`!encodingConfiguration.useReversibleFilter` excludes the reversible-
filter case from the auto-promoted qstep search). My v9.9 widening
touches only the qstep-search code paths. The PCRD-opt regression is
a separate pre-existing failure, also reproducible before v9.6.

---

## Bit-exact gates (all green post-widening)

- `HTCrossCodecConformantTests` — MD5 parity vs OpenJPH/OpenJPEG/Kakadu
- `V94NEONHotPathParityTests` — 500-trial NEON path bit-exact sweep
- `V91Phase2cArrayVsRawParityTests`
- `HTBlockEncoderConformantTests`
- `HTConformantConstantBitrateViaQstepTests`
- `HTConformantFixedQstepRDTests`
- `J2KCrossScaleRDQualityProbe` (still passing thanks to v9.8 SIGTRAP fix)
- `V91Phase2ConcurrentContentionProbe` — no contention regression
- All medical corpus stats / RD tests on the broader sweep

The cache stores the converged qstep regardless of how many
iterations the search took. With v9.9, the cached value is more
accurate (the search reaches it more reliably) — which makes
subsequent warm-cache encodes even faster than the v9.6 baseline.

---

## What ships on `v9.9-image-stats-predictor`

| Path | Change |
|---|---|
| `Sources/J2KCodec/J2KCodec.swift` | Two-line clamp + bracket widening in `encodeViaQstepSearch` (line 781-794) and `encodeViaStrictBoundedQstep` (line 421-433, 612-621) |
| `Tests/J2KCodecTests/V98QstepCalibrationTests.swift` | Added `testFullCal_*` methods + `binarySearchConvergedQstep` helper for ground-truth calibration |
| `V9_9_BRACKET_WIDENING_RESEARCH.md` | This document |

---

## Decision matrix

| Metric                          | Result      | Threshold        | Outcome         |
|---                              |---          |---               |---              |
| Bit-exact preserved             | yes         | required         | ✓               |
| Tight-tolerance convergence improvement | yes (3 fixtures unstuck) | ≥1 unstuck | ✓ |
| `.constantBitrate` cold-shot wall improvement | no (within noise) | ≥10% | ✗ (cold-shot is image-stats territory) |
| Corpus calibration data         | yes (27/28)  | full sweep       | ✓               |
| Production code change          | yes (2-line clamp) | minimal | ✓                |

**Outcome:** ship the bracket widening as a small, safe production
improvement that enables better convergence for callers using
`.constantBitrateViaQstep` (tight tolerance). Image-statistics
predictor remains future work — the calibration data now in
`V98QstepCalibrationTests` makes that next step substantially
easier.

---

## Cumulative state of qstep-search research arc

| Release | What landed | DX warm wall | Kakadu gap |
|---      |---         |---:          |---:        |
| v9.4.0  | C+NEON entropy hot path | 91 ms | 4.6×       |
| v9.5    | Entropy NEON wash (research close) | 91 ms | 4.6× |
| v9.6    | **Process-default qstep cache** | **29 ms** | **1.45×** |
| v9.7    | Pre-seed dead-end (research close) | 29 ms | 1.45× |
| v9.8    | Image-stats infra + SIGTRAP fix | 29 ms | 1.45× |
| v9.9    | **Bracket widening + corpus calibration** | 29 ms | 1.45× |

v9.6 remains the headline win. v9.8 and v9.9 are production patches
(SIGTRAP fix; bracket widening) that improve `.constantBitrateViaQstep`
robustness without regressing anything else. The cold-shot DX
first-encode case (image-stats predictor) is still the open research
target; v9.9's calibration corpus makes the next attempt's
hypothesis space much more constrained.
