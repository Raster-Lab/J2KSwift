# J2KSwift v5.29.0 — Encode Stage Timings + `encodeGPU` Regression Discovery

**Release date:** 2026-05-04
**Theme:** v5.24-v5.28 architected the decode pipeline to 2.6-4.6× speedup on the
medical corpus. v5.29.0 starts the equivalent investigation on the encode side. Mirrors
the v5.24.0 pattern: ship stage timings + initial corpus characterisation first, let the
data inform what to optimise.

The data delivers two unexpected findings:

1. **`encodeGPU` is currently a regression** at every fixture size — slower than CPU
   `encode` by 2-39%. The GPU forward DWT pays dispatch overhead it doesn't recover.
2. **At 17M-pixel mammography, `rateControl` is 75% of encode time** — 679-701 ms out
   of 900-920 ms total. PCRD-opt layer truncation scales super-linearly.

## Headline measurements

`encode` vs `encodeGPU` on the medical corpus (M2, release, n=5 medians):

| Fixture                | CPU `encode` | `encodeGPU` | CPU/GPU× |
|------------------------|-------------:|------------:|---------:|
| ct_001 (512×512)       |        4.1 ms |       4.2 ms |   0.97× |
| xa_001 (1024×1024)     |       17.0 ms |      27.7 ms |  **0.61×** |
| px_001 (2459×1316)     |       50.1 ms |      68.7 ms |  **0.73×** |
| dx_002 (2800×2288)     |      110.1 ms |     132.5 ms |   0.83× |
| mg_001 (3520×4784)*    |      899.7 ms |     979.0 ms |   0.92× |

CPU `encode` wins everywhere. The gap is largest at 1024² (61%) where GPU forward DWT
overhead is a large fraction of total encode time but the GPU dispatch cost doesn't
amortise against the small workload.

## CPU encode stage breakdown (ms)

| Fixture                | preproc | colour | DWT  | quant | entropy | rateCtrl | codestream |
|------------------------|--------:|-------:|-----:|------:|--------:|---------:|-----------:|
| xa_001 (1024×1024)     |     1.2 |    0.0 |  3.3 |   0.1 |     7.6 |      2.6 |        1.9 |
| px_001 (2459×1316)     |     3.8 |    0.0 | 10.4 |   0.1 |    24.6 |      7.4 |        5.7 |
| dx_002 (2800×2288)     |     7.4 |    0.0 | 21.5 |   0.1 |    46.3 |     24.2 |       10.9 |
| dx_001 (2544×3056)*    |     9.4 |    0.0 | 26.9 |   0.2 |    56.8 |    132.3 |       13.0 |
| mg_001 (3520×4784)*    |    19.7 |    0.0 | 56.9 |   0.2 |   115.3 |  **678.8** |     28.0 |
| mg_002 (3521×4784)*    |    19.8 |    0.0 | 57.1 |   0.2 |   115.3 |  **701.1** |     28.6 |

**Two distinct regimes:**
- **≤6.4M pixels**: `entropyCoding` is the dominant stage (42-49%). HT block coding is
  the natural target for GPU acceleration (mirroring v5.26.0's GPU HT decoder).
- **≥7.8M pixels**: `rateControl` dominates and scales super-linearly. At 17M px it's
  ~270× slower than at 1M px (versus ~17× pixel count). PCRD-opt layer truncation
  needs profiling.

## What v5.29.0 ships

### `J2KEncodeTimings` — stage-level encode timings accumulator

`Sources/J2KCodec/J2KEncodeTimings.swift` — process-global, NSLock-protected, always-on.
Mirrors the v5.24.0 `J2KDecodeTimings`. Tracks 7 stages:

- `preprocessing`
- `colorTransform`
- `waveletTransform`
- `quantization`
- `entropyCoding`
- `rateControl`
- `codestreamGeneration`

`reset()` before an encode, `snapshot()` after. Cost is ~tens of nanoseconds per stage.

Wired into both `J2KEncoderPipeline.encode` and `J2KEncoderPipeline.encodeGPU`. The
existing `J2K_PROFILE` env-var stderr prints are preserved; the timings accumulator
runs in addition.

### `J2KMedicalCorpusEncodePerformanceTests` — corpus encode benchmark

`Tests/J2KMetalTests/J2KMedicalCorpusEncodePerformanceTests.swift` — sweeps the same 10
fixtures as the v5.27.0/v5.28.0 decode benchmark (180×180 to 16.8M px, including the
synthetic mammography fixtures) × CPU and GPU encode × full per-stage breakdown. Prints
markdown-friendly tables for paste into MEDICAL_BENCHMARK.md.

### `MEDICAL_BENCHMARK.md` updates

New "Encode Performance (v5.29.0)" section appended. Per-fixture times, per-stage
breakdown, three honest findings, routing recommendation (today: always use CPU
`encode`).

## What v5.29.0 does NOT do

This is a **characterisation** release, not an optimisation release. It mirrors v5.24.0's
shape: ship the timings infrastructure + the data, let the data inform v5.30.

No encode behaviour changes. No new public APIs. No regressions to existing tests.

## Verified

| Test suite                                | Cells | Failed | Notes |
|-------------------------------------------|------:|-------:|-------|
| `J2KGPULossy97DivergenceTests`            |     2 |      0 | Carryover (v5.26 session bit-equiv) |
| `J2KMetalSingleLevel97Tests`              |     1 |      0 | Carryover |
| `J2KWaveletConventionAuditTests`          |     4 |      0 | Carryover |
| `J2KMedicalCorpusPerformanceTests`        |     2 |      0 | Decode corpus + cold-start |
| `J2KMedicalCorpusEncodePerformanceTests`  |     1 |      0 | New v5.29.0 encode corpus |
| HT conformant suites (v5.15–v5.20)        | various |    0 | All carryover gates green |

The 4 pre-existing perf-aspirational test failures
(`testHTJ2KPerformanceTargetIs3x`, `testScale16Bit`, `testNEONPerformanceBenefit`,
`testHTJ2KBeatsOpenJPEG*`) are unaffected by this work.

## Reproducing

```bash
swift test -c release --filter J2KMedicalCorpusEncode
```

## Strategy implications for v5.30

Three concrete next-release candidates ranked by expected impact:

### Option A — investigate `rateControl` super-linear scaling (recommended)

At 17M pixels, PCRD-opt layer truncation is 679-701 ms — 75% of encode wall time. At
1M pixels it's 2.6 ms (a 270× ratio for 17× pixel count). That's not normal for a
near-linear algorithm; either the codeblock count grows faster than expected, the qstep
search is firing more iterations, or there's a hot loop with sub-optimal complexity.

Profile, identify the cause, fix. Could yield 5-10× on mammography encode if the
algorithm has a fixable hot loop.

### Option B — GPU HT entropy encoder

Mirror the v5.26.0 GPU HT decoder pattern in the forward direction. At medium workloads
(1-6M px), entropy is the dominant stage (~50% of encode time). Same architectural
levers (session-warm Metal pipeline, fused codeblock buffer, GPU-resident scatter)
should apply.

Larger scope than option A. Probably 2-3 weeks of work for parity with the decode
infrastructure.

### Option C — fix or remove `encodeGPU`

The current `encodeGPU` path is a regression. Either:
- Profile the GPU forward DWT to find why dispatch overhead exceeds CPU compute, fix
- Or route `encodeGPU` to fall back to CPU when GPU is slower (workload-size routing
  helper, similar to `J2KDecoder.recommendedDecodeAPI` from v5.27.0)

Cleanup work, modest impact.

**Recommendation: Option A first.** The 700 ms of mammography encode time being spent
on rate control is suspicious enough to warrant investigation before committing to a
multi-week GPU HT encoder build. If A reveals a fixable hot loop, mammography encode
could move from 920 ms to ~200-300 ms — bigger user-facing impact than B's ~50 ms
saving on typical fixtures. If A is just an inherent algorithm cost, then B becomes
the right next step.

## Lesson

The same pattern as v5.24.0: stage timings + corpus characterisation reveals
unexpected things. v5.24.0 found "GPU HT entropy is on GPU but slower than CPU at
typical sizes" (which led to v5.25-v5.27's optimisation arc). v5.29.0 finds:

- `encodeGPU` is a regression (the headline number was hiding it)
- rateControl is the surprise dominant stage at huge workloads (no one was looking)

Don't optimise until you've measured. Don't believe a "GPU-accelerated" path is
actually faster until the data confirms it.
