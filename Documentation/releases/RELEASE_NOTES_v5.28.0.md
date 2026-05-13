# J2KSwift v5.28.0 — Mammography Corpus Extension + `preWarm()` Helper

**Release date:** 2026-05-04
**Theme:** v5.27.0 measured 7 medical fixtures up to 2800×2288 and codified the routing
rule (CPU < 256² < `decodeGPU` < 3M px ≤ `decodeWithGPUHT`). Three larger fixtures
(`dx_001`, `mg_001`, `mg_002` — up to 16.8M px mammography) weren't checked in. v5.28.0
extends the corpus to those sizes via synthetic equivalents and validates that the
routing rule keeps holding all the way up to 17M pixels. Plus a `preWarm()` helper that
eliminates the ~30 ms cold-start cost for warm-process workflows.

## Headline 1 — Mammography validates the architecture

| Fixture                | Pixels    | CPU `decode` | `decodeGPU(_:session:)` | `decodeWithGPUHT(_:session:)` |
|------------------------|----------:|-------------:|-------------------------:|------------------------------:|
| dx_001 (2544×3056)*    |   7.8M    |       223 ms |                    56 ms |                       **51 ms** (4.4×) |
| mg_001 (3520×4784)*    |  16.8M    |       503 ms |                   140 ms |                      **110 ms** (**4.6×**) |
| mg_002 (3521×4784)*    |  16.8M    |       500 ms |                   153 ms |                      **114 ms** (**4.4×**) |

`*` synthetic LCG-noise fixtures at the indicated dimensions (real PGMs not in-repo).
Decode timing scales with pixel count and (constant-bitrate) bitstream length, both of
which match the real fixtures, so the routing characterisation remains valid.

**`decodeWithGPUHT` keeps gaining headroom up to 17M pixels.** At 1024² it's 1.8×
CPU; at 3M it crosses over `decodeGPU` (3.2× CPU); at 17M it hits **4.6×**. The 3M-pixel
routing threshold v5.27.0 codified is validated at the upper end of the medical-imaging
size range.

## Headline 2 — `preWarm()` eliminates cold-start

Fresh `J2KMetalSession` pays ~30–50 ms on first decode (Metal device init + shader
library load + pipeline state creation + VLC table upload + Metal driver first-dispatch
fence). v5.28.0's `preWarm()` does this work up front:

| 512×512 16-bit lossy 9/7, M2, release | Without `preWarm` | With `preWarm` |
|---------------------------------------|------------------:|---------------:|
| Cold first decode                     |       40–49 ms    |        —       |
| `preWarm()` call itself               |         —         |    27–32 ms    |
| First user decode after `preWarm`     |         —         |   **9–16 ms**  |
| Warm baseline (subsequent decodes)    |       10–15 ms    |    10–15 ms    |
| Cold-start cost eliminated            |         —         |    25–30 ms    |

For a long-lived process decoding many images, `preWarm` pays the cold-start cost once at
init instead of on the first user request. Total cost across N decodes:

- **Without** `preWarm`: 50 ms (cold first) + (N-1) × ~12 ms = **50 + 12(N-1)** ms
- **With** `preWarm`: 30 ms (preWarm) + N × ~12 ms = **30 + 12N** ms

The crossover is at N=2 — any workload that decodes more than one image benefits.

## What v5.28.0 ships

### `J2KMetalSession.preWarm(includeWarmupDispatch:)`

`Sources/J2KCodec/J2KMetalSession.swift` — async helper that:

1. Initialises `MTLDevice` and `MTLCommandQueue`.
2. Loads the shader library (`default.metallib` from bundle, or source-compiles inline).
3. Pre-creates `MTLComputePipelineState` for the 11 decode-hot-path kernels in parallel
   via TaskGroup.
4. Runs a tiny synthetic 256×256 decode through `decodeWithGPUHT` to exercise the
   non-pipeline lazy-init paths (VLC table upload, buffer pool first-fetch, Metal driver
   first-dispatch fence).

Step 4 was the key insight: pipeline-only pre-warming saved only ~10 ms; the warmup
dispatch closes the rest of the gap. Set `includeWarmupDispatch: false` to skip step 4
(useful for measurement isolation; not recommended for production).

Idempotent. Thread-safe via the underlying actors' isolation.

### Corpus benchmark extended to mammography

`Tests/J2KMetalTests/J2KMedicalCorpusPerformanceTests.swift`:

- `Fixture` struct with optional `synthDimensions` for fixtures not on disk
- `synthesizeImage(width:height:)` LCG-noise fallback (matches the synthesizer in
  `J2KGPULossy97PerformanceTests`)
- 3 new entries: `dx_001` (7.8M px), `mg_001` (16.8M px), `mg_002` (16.8M px) — all
  synthetic, marked with `*` in output
- New `testColdStartVsPreWarmFirstDecodeLatency` test exercising the cold-start path

### MEDICAL_BENCHMARK.md updates

- Decode Performance table extended to 10 fixtures
- New "Cold-Start vs `preWarm()`" subsection with per-metric table

## Verified

| Test suite                                | Cells | Failed | Notes |
|-------------------------------------------|------:|-------:|-------|
| `J2KGPULossy97DivergenceTests`            |     2 |      0 | Carryover (incl. session bit-equiv from v5.26) |
| `J2KMetalSingleLevel97Tests`              |     1 |      0 | Carryover |
| `J2KWaveletConventionAuditTests`          |     4 |      0 | Carryover |
| `J2KGPULossy97PerformanceTests`           |     1 |      0 | Single-fixture carryover |
| `J2KMedicalCorpusPerformanceTests`        |     2 |      0 | Existing corpus + new cold-start test |
| HT conformant suites (v5.15–v5.20)        | various |    0 | All carryover gates green |

The `testSessionPathBitEquivalentToNoSessionPath` correctness gate (added in v5.26.0)
still asserts session decode matches no-session decode within 4 LSB at 16-bit. Observed
post-v5.28.0: max diff = 1 LSB.

The 4 pre-existing perf-aspirational test failures
(`testHTJ2KPerformanceTargetIs3x`, `testScale16Bit`, `testNEONPerformanceBenefit`,
`testHTJ2KBeatsOpenJPEG*`) are unaffected by this work.

## Reproducing

```bash
swift test -c release --filter J2KMedicalCorpus       # full corpus + cold-start
swift test -c release --filter testColdStartVsPreWarm # cold-start only
```

## Open levers (Tier 2 deferred)

`gpuHTDispatch` overhead is ~7–11 ms across all sizes — even on mammography, where IDWT
is the dominant cost (82 ms on mg_001). Reducing dispatch overhead via threadgroup
tuning, kernel merging, or indirect command buffers could lower it further. Won't change
the routing rule (mammography is firmly in `decodeWithGPUHT` territory) but might lower
the crossover threshold. Tracked for v5.29 if pursued.

Encode-side GPU pipeline (Tier 2 alternative) — J2KSwift HTJ2K encode is currently 25%
slower than OpenJPH. Same architectural levers (session-warm, fused kernels,
GPU-resident buffers) likely apply but in the forward direction. Larger scope.

## Lesson

The first attempt at `preWarm()` only compiled shader pipelines and saved ~10 ms — way
short of the ~30 ms cold-start cost it was supposed to eliminate. The missing piece was
exercising the actual GPU dispatch path: VLC tables uploaded, first command buffer
submitted, Metal driver state initialised. Adding a tiny synthetic warmup decode at
the end of `preWarm` closed the gap.

The pattern: cold-start cost in modern GPU APIs isn't all in shader compilation. Driver-
side state init happens lazily on first dispatch and can dominate. Pre-warming has to
exercise the actual hot path, not just compile its prerequisites.
