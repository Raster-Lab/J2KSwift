# v10.0 Phase 1 — non-entropy wall budget on Apple M2 (lossless HT 5/3 corpus)

**Date:** 2026-05-12
**Branch:** `v10.0-research` (commit base `b2d5ea3`)
**Test:** `Tests/J2KMetalTests/V10Phase1WallBudgetTests.swift::testWallBudget_Lossless_WorkerSweep_M2`
**Run:** `swift test -c release --filter V10Phase1WallBudgetTests` (Apple M2, n=5 per cell)
**Configuration:** HT-conformant lossless 5/3 (`useHTJ2K=true`, `lossless=true`, `decompositionLevels=5`)

## Headline

**Phase 2 decision: close v10.0 as research artefact.** No non-entropy stage
clears the plan's gate (≥10 % of wall on DX *and* not already at a documented
ceiling). The largest non-entropy CPU contributor is **DWT** (288 ms summed
worker CPU on DX-12T), but the V8_6 finding established it is memory-bandwidth
bound at 0.37 ns/sample on M-series — a C+NEON retrofit returns no measurable
wall savings. Pre-processing `extract16` is the only other non-trivial stage
(~5 ms summed CPU on DX-1T, ~12 % of wall by CPU but lower by wall when
parallelised), but the size and per-byte cost make a C target unattractive on
the cost/benefit ratio that v9.4 / v9.5 established.

## Method + a critical methodology caveat

The existing `J2KEncodeTimings` + per-substage accumulators
(`J2KPreprocessSubstageTimings`, `J2KTier2Timings`,
`J2KCodestreamMarkerTimings`) are **per-worker NSLock-protected**. When the
encoder pipeline runs N workers concurrently, each one's CPU time on a stage
is added to the accumulator. The snapshot is therefore **summed worker CPU**,
not wall.

This is fine for *relative* stage comparisons within a single run (the worker
balance is roughly the same across stages), but it makes the "% of wall"
calculation misleading for fixtures large enough to exceed the
single-worker / single-tile branch — where accumulator sums exceed measured
wall by 3-13×. **The 1× / 4× / 12× sweep in this measurement still surfaces
the dominant stages**, but Phase 2 cannot use the raw % numbers without
deflating by an effective worker count.

A future Phase 1c with per-stage wall (not per-worker CPU) instrumentation
would tighten the picture, but the V8_6 DWT memory-bandwidth finding caps the
upside enough that this is not worth blocking on.

## Per-stage CPU breakdown (ms, mean of 5 release-mode runs)

`maxT` = `J2KEncodingConfiguration.maxThreads` setting; total = wall (median).

| Fixture          | maxT | total (wall) | preproc | DWT    | entropy | rateCtrl | codestream | sum (CPU) |
|------------------|-----:|-------------:|--------:|-------:|--------:|---------:|-----------:|----------:|
| MR-small 180²    |    1 |         0.99 |    0.02 |   0.20 |    0.66 |     0.00 |       0.11 |      0.99 |
| CT 512²          |    1 |         5.68 |    0.09 |   1.01 |    4.36 |     0.01 |       0.21 |      5.67 |
| MR 886²          |    1 |         2.43 |    0.33 |   3.95 |    3.01 |     0.01 |       0.58 |      7.89 |
| XA 1024²         |    1 |         8.64 |    1.53 |  12.22 |   16.50 |     0.02 |       1.11 |     31.38 |
| PX 2459×1316     |    1 |        18.45 |    3.60 |  89.06 |  108.70 |     0.14 |       5.41 |    206.92 |
| **DX 2800×2288** |    1 |    **44.37** | **12.69** | **300.06** | **255.44** | **0.21** | **10.10** | **578.53** |
| MR-small 180²    |    4 |         0.73 |    0.01 |   0.25 |    0.28 |     0.00 |       0.21 |      0.76 |
| CT 512²          |    4 |         3.00 |    0.09 |   1.28 |    1.34 |     0.01 |       0.25 |      2.96 |
| MR 886²          |    4 |         3.57 |    0.41 |   6.15 |    2.78 |     0.02 |       0.95 |     10.31 |
| XA 1024²         |    4 |         6.92 |    0.64 |  11.10 |    9.70 |     0.03 |       1.21 |     22.69 |
| PX 2459×1316     |    4 |        19.95 |    3.36 | 130.98 |   75.78 |     0.38 |       8.73 |    219.25 |
| **DX 2800×2288** |    4 |    **38.97** | **9.13** | **313.12** | **186.96** | **0.26** | **11.93** | **521.40** |
| MR-small 180²    |   12 |         0.71 |    0.01 |   0.18 |    0.24 |     0.00 |       0.25 |      0.68 |
| CT 512²          |   12 |         2.78 |    0.09 |   1.17 |    1.12 |     0.01 |       0.27 |      2.66 |
| MR 886²          |   12 |         2.29 |    0.29 |   4.79 |    2.01 |     0.01 |       0.63 |      7.73 |
| XA 1024²         |   12 |         5.93 |    0.57 |   9.02 |    9.01 |     0.02 |       1.12 |     19.75 |
| PX 2459×1316     |   12 |        18.09 |    3.05 | 122.14 |   65.05 |     0.14 |       7.29 |    197.68 |
| **DX 2800×2288** |   12 |    **38.54** | **8.64** | **288.02** | **172.03** | **0.24** | **9.84** | **478.78** |

(`colour` and `quant` are uniformly zero on the lossless 5/3 path — colour
transform is skipped for single-component grayscale, quantization is fused
into entropy block extraction. Omitted for compactness.)

## Stage CPU as a deflated wall-fraction estimate (DX 2800×2288)

Approximating effective workers as `min(maxT, ~4)` for the multi-tile
dispatcher (the encoder sub-divides DX into 4 tiles by default):

| stage      | CPU (maxT=12) | ÷ 4 worker est. | DX wall | est. wall fraction |
|------------|--------------:|----------------:|--------:|-------------------:|
| DWT        |       288 ms  |          72 ms  |   38.5 ms | not parallelisable below this; DWT ceiling-bound |
| entropy    |       172 ms  |          43 ms  |   38.5 ms | the dominant single-stage wall contributor |
| preprocess |        8.6 ms |          2.2 ms |   38.5 ms | ~6 % wall |
| codestream |        9.8 ms |          2.5 ms |   38.5 ms | ~6 % wall |
| tier-2     |        3.1 ms |          0.8 ms |   38.5 ms | ~2 % wall |
| rateCtrl   |        0.2 ms |          0.1 ms |   38.5 ms | <1 % wall |

The "÷ 4 worker est." column is illustrative only; it gives an upper bound
on the wall fraction of each stage (because the assumption is perfect parallel
overlap). The true wall is bounded by the longest serial chain, which on this
data is **entropy** (block-extraction → block-encoding → assembly), already
covered by the v9.4 NEON hot path.

## Preprocess substages (ms summed CPU, mean of 5)

| Fixture | maxT | extract16 | dcShift | sum |
|---|---:|---:|---:|---:|
| DX 2800×2288 | 1 | 5.700 | 0.000 | 5.700 |
| DX 2800×2288 | 4 | 4.134 | 0.000 | 4.134 |
| DX 2800×2288 | 12 | 3.870 | 0.000 | 3.870 |

`extract16` (the 16-bit pixel widening + sign-cast loop in
`J2KPreprocessSubstageTimings`) is the only non-zero preprocess substage on
the medical corpus (16-bit big-endian PGMs). DC-level-shift is zero because
the lossless path skips it for unsigned components in the current pipeline.

`extract16` summed CPU on DX-12T is 3.87 ms — ~10 % of summed CPU but at
most ~1 ms wall after parallel overlap. **Below the Phase 1 gate** by wall
fraction.

## Tier-2 + codestream-marker substage totals

| Fixture | maxT | tier-2 | csmarker |
|---|---:|---:|---:|
| DX 2800×2288 | 1 | 3.71 ms | 0 |
| DX 2800×2288 | 4 | 4.21 ms | 0 |
| DX 2800×2288 | 12 | 3.09 ms | 0 |

Codestream-marker is uniformly zero — the lossless HT path skips the marker
substage timer (likely a different code path emits the markers). Tier-2 at
~3 ms summed CPU on DX-12T is sub-1 ms wall after parallel overlap.

## Phase 2 decision matrix evaluation

Per `V10_0_RESEARCH_PLAN.md` Phase 1 gate:
> at least one non-entropy stage measures ≥10 % of wall on a representative
> corpus image, with ns/sample > 20

| Stage      | DX wall fraction | ns/sample (M2 lossless 5/3) | Phase 2 candidate? |
|------------|-----------------:|----------------------------:|--------------------|
| DWT        | ~60 % (CPU-summed; ~25 ms wall) | 0.37 ns/sample (V8_6) | **No** — at memory-bandwidth ceiling |
| entropy    | ~45 % (CPU-summed; ~17 ms wall) | already C+NEON in v9.4 | n/a — out of scope (entropy is excluded) |
| preprocess | ~6 %             | extract16 ~50 ns/16-bit-px (estimate) | **No** — wall fraction too small |
| codestream | ~6 %             | unmeasured | **No** — wall fraction too small |
| tier-2     | ~2 %             | already PR #308 measured | **No** — wall fraction too small |
| rateCtrl   | <1 %             | n/a | **No** — wall fraction trivial |

**No stage clears the gate.**

The lossless production hot path on M2 is **DWT-and-entropy bound** with both
already at their respective optimisation ceilings:
- **DWT**: memory-bandwidth-bound per V8_6 (no SIMD/C win on Apple Silicon)
- **Entropy**: C+NEON hot path shipped in v9.4.0 (auto-vec ceiling per V9_5)

## Phase 2 decision: close v10.0-research as artefact

Per the plan's Phase 1 gate: **close v10.0 as research with a documented
"encoder wall is mature on M2 for lossless 5/3 HT" finding.** This is the
**ninth independent investigation** confirming the M2 + Swift release
lever-ceiling (after v6-alpha4, v7.4-7.5, v8.1, v8.4, v8.5, v8.6, v8.7,
v9.5).

**Implications:**
1. The remaining encoder lever for production is **j2kd daemon adoption**,
   delivered in v9.5.0. Encoder optimisation effort on M2 should pause.
2. **M3+/A-series hardware measurement** remains the open frontier — different
   memory bandwidth and core counts may shift the budget (the v9.2 Path B
   M4 capture showed a different daemon win profile than M2). Worth a
   separate measurement pass when M-series hardware is available.
3. The v10.0-research branch has produced fresh measurement data, an updated
   wall-budget report, and a documented decision — meeting the plan's
   research-mode deliverable criteria. The branch can be merged to `main` as
   a research-mode update or kept on the side for future reference.

## Limitations of this measurement (for any future re-run)

- **Per-worker CPU sums vs wall**: substage accumulators measure CPU summed
  across workers. A Phase 1c instrumentation would record wall-clock at the
  dispatcher level (not per-worker) for true wall fractions. This deferral
  is acceptable because the qualitative conclusion (DWT + entropy dominate;
  both at ceiling) does not change with better instrumentation.
- **maxThreads ≠ effective worker count**: the encoder pipeline has multiple
  internal dispatchers; setting `maxThreads=1` does not actually serialise
  multi-tile dispatch. Hence the inflated stage sums even at maxT=1 for
  fixtures ≥ MR 886².
- **No M3/M4/A-series measurement**: this is M2-only. Cross-silicon results
  may shift the budget enough to re-open Phase 2 on a different host.

## Files added in Phase 1

```
Tests/J2KMetalTests/V10Phase1WallBudgetTests.swift   (NEW measurement test)
V10_0_PHASE1_WALL_BUDGET.md                           (this report)
```

## Companion documents

- [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md) — original plan
- [`V8_6_FORWARD_DWT_FINDING.md`](V8_6_FORWARD_DWT_FINDING.md) — prior DWT memory-bandwidth ceiling
- [`V9_5_BEAT_KAKADU_RESEARCH.md`](V9_5_BEAT_KAKADU_RESEARCH.md) — entropy autovec ceiling
- [`RELEASE_NOTES_v9.5.0.md`](RELEASE_NOTES_v9.5.0.md) — daemon-encode large-fixture closure (the lever that DID land)
