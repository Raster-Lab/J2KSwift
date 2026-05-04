# J2KSwift v5.27.0 — Medical Corpus Characterisation + CPU-Work Skip

**Release date:** 2026-05-04
**Theme:** v5.24.0–v5.26.0 added stage timings and shipped two GPU-pipeline optimisations
that brought `decodeWithGPUHT` 9/7 lossy from 1.07× to 1.85× on a single 1024×1024 fixture.
v5.27.0 takes a step back and asks: what's the picture across the full medical corpus,
and is there a routing rule we can give callers?

The answer:

1. **The crossover is real.** `decodeGPU` wins below ~1M pixels; `decodeWithGPUHT` wins
   above ~3M pixels. Between, either is fine.
2. **A small remaining CPU-work skip closes the gap further.** When the Float fused
   batch is going to consume the codeblock buffer, the [SubbandInfo] regroup loop and
   the per-subband CPU dequantisation pass are dead code — both can be skipped. Saves
   up to 14 ms on a 2459×1316 fixture.

## Headline (medical corpus, M2, release, n=5 medians, post-v5.27.0)

| Fixture                | CPU      | `decodeGPU`× | `decodeWithGPUHT`× |
|------------------------|---------:|-------------:|-------------------:|
| mr_002 (180×180)       |   1.2 ms |        1.0×  |               0.3× |
| ct_001 (512×512)       |   7.2 ms |        1.6×  |               0.8× |
| mr_001 (886×886)       |  21.1 ms |        2.2×  |               1.6× |
| xa_001 (1024×1024)     |  25.7 ms |        2.8×  |               1.8× |
| **px_001 (2459×1316)** |  86.2 ms |        2.8×  |          **3.2×** |
| **dx_002 (2800×2288)** | 170.1 ms |        3.5×  |          **4.0×** |

Below 1M pixels: `decodeGPU` wins. At and above 3M pixels: `decodeWithGPUHT` overtakes.

## v5.27.0 Item B: CPU-work skip on Float fused path

When `applyEntropyDecoding` builds the Float fused batch
(`floatPlansByComponent` populated), the downstream IDWT consumes the codeblock buffer
directly via `inverse2DFullFusedFromCodeblocks`. The `[SubbandInfo]` regroup loop that
follows the entropy stage was building data the IDWT never read, and `applyDequantization`
was scaling coefficients the GPU scatter kernel was dequantising again. v5.27.0 adds a
short-circuit at line 1655 of `J2KDecoderPipeline.swift`: when `floatPlansByComponent` is
non-nil, `applyEntropyDecoding` returns `([], batch)` directly. Dequant becomes a no-op.

### Per-fixture savings

| Fixture            | v5.26.0 `decodeWithGPUHT` | v5.27.0 `decodeWithGPUHT` | Δ |
|--------------------|--------------------------:|---------------------------:|----:|
| px_001 (2459×1316) |                    41.0 ms |                    27.2 ms | **−14 ms** |
| dx_002 (2800×2288) |                    46.9 ms |                    42.7 ms |  −4 ms |

Stage breakdown on dx_002 (post-v5.27.0):

| Stage                       | ms |
|-----------------------------|----:|
| `gpuHTDispatch`             |  8.9 |
| build Float plans           |  0.6 |
| CPU dequant                 | **0.0** ← v5.27.0: was ~4 ms |
| `inverseWaveletTransform`   | 25.6 |

The dequant column dropped to literally zero. The regroup column dropped from ~1.3 ms
to ~0.6 ms (now just the `buildGPUHTBatchFromResultFloat` cost; the [SubbandInfo]
regroup loop no longer runs).

## v5.27.0 Item A: medical corpus characterisation

`Tests/J2KMetalTests/J2KMedicalCorpusPerformanceTests.swift` — a new benchmark that
sweeps 7 fixtures × 3 APIs × full per-stage breakdown and prints a markdown-friendly
table that drops cleanly into MEDICAL_BENCHMARK.md.

`MEDICAL_BENCHMARK.md` gains a new "Decode Performance (v5.27.0)" section with per-fixture
times, speedups, the routing recommendation, and the v5.26.0 → v5.27.0 delta.

## v5.27.0 Item C: `J2KDecoder.recommendedDecodeAPI(width:height:)`

New static helper that codifies the threshold derived from the corpus data:

```swift
public enum J2KRecommendedDecodeAPI: Sendable {
    case cpu              // < 256×256
    case decodeGPU        // 256² to ~1730×1730
    case decodeWithGPUHT  // ≥ ~1730×1730 (3M pixels)
}

public static func recommendedDecodeAPI(width: Int, height: Int) -> J2KRecommendedDecodeAPI
```

Thresholds:

- `< 65,536 px` (256×256): CPU. Metal dispatch overhead exceeds GPU compute at this size.
- `< 3,000,000 px`: `decodeGPU(_:session:)`. CPU HT entropy is cheaper than GPU HT
  dispatch at this size.
- `≥ 3,000,000 px`: `decodeWithGPUHT(_:session:)`. GPU HT dispatch amortises.

The helper is documentation-as-code: callers can call it directly to route, or read it
to understand the rule.

## Verified

| Test suite                                | Cells | Failed | Notes |
|-------------------------------------------|------:|-------:|-------|
| `J2KGPULossy97DivergenceTests`            |     2 |      0 | `testSessionPathBitEquivalent` exercises v5.27.0 short-circuit |
| `J2KMetalSingleLevel97Tests`              |     1 |      0 | Carryover |
| `J2KWaveletConventionAuditTests`          |     4 |      0 | Carryover |
| `J2KGPULossy97PerformanceTests`           |     1 |      0 | Single-fixture warm-session |
| `J2KMedicalCorpusPerformanceTests`        |     1 |      0 | New v5.27.0 corpus sweep |
| HT conformant suites (v5.15–v5.20)        | various |    0 | All carryover gates green |

The `testSessionPathBitEquivalentToNoSessionPath` correctness gate (added in v5.26.0)
still asserts session decode matches no-session decode within 4 LSB at 16-bit. Observed
post-v5.27.0: max diff = 1 LSB, avg = 0 (Float-precision noise — unchanged from v5.26.0).

The 4 pre-existing perf-aspirational test failures
(`testHTJ2KPerformanceTargetIs3x`, `testScale16Bit`, `testNEONPerformanceBenefit`,
`testHTJ2KBeatsOpenJPEGFullMatrixPrintsSummary`) are unaffected by this work.

## Reproducing

```bash
swift test -c release --filter J2KMedicalCorpus     # full corpus sweep
swift test -c release --filter J2KGPULossy97Performance  # single-fixture
swift test -c release --filter J2KGPULossy97Divergence   # correctness gates
```

## Lesson

v5.24.0 said "the bigger lever is GPU HT dispatch overhead." v5.25.0/v5.26.0 chipped at
the IDWT side. Item B in this release shows the cheapest remaining lever wasn't on the
GPU at all — it was the CPU dequant + regroup that the new GPU path made dead code.

Same shape repeats: when an architecture changes, audit what the old code was doing that
the new code makes redundant. v5.26.0's Float scatter+dequant kernel made the CPU
dequant pass dead; spotting that took a 7-fixture sweep (corpus characterisation) plus
attention to the stage breakdown. The fix was 6 lines.
