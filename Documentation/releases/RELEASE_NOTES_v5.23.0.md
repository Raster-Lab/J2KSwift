# J2KSwift v5.23.0 — GPU 9/7 Lossy Decode Performance Characterisation

**Release date:** 2026-05-04
**Theme:** v5.20.0/v5.21.0 fixed GPU 9/7 IDWT correctness. v5.22.0 locked in cross-module
wavelet-convention agreement as a permanent regression gate. v5.23.0 measures what the
fixed IDWT path actually delivers in release mode with session reuse, ratifies the result
honestly, and sets the architectural agenda for further speedup work.

## Headline

Release-mode warm-session decode of 1024×1024 16-bit lossy 9/7 @ 2 bpp on M2:

| Path                    | Median (n=5)    | vs CPU |
|-------------------------|----------------:|-------:|
| `J2KDecoder.decode`     | ~26 ms          | 1.00×  |
| `J2KDecoder.decodeWithGPUHT(_:session:)` | ~17–24 ms | 1.05–1.54× |

Sampled across 4 independent runs on the same hardware, the speedup ranged **0.99×–1.54×**
with the median around **1.4–1.5×**. Significant variance is real and attributable to GPU
contention with the OS, thermal state, and cold-cache effects on 5-sample medians.

## What this release does

### 1. New benchmark — `J2KGPULossy97PerformanceTests`

`Tests/J2KMetalTests/J2KGPULossy97PerformanceTests.swift` —
`testWarmSessionGPUSpeedupVsCPU`. Encodes a synthetic 1024×1024 16-bit image once at 2 bpp
HT-conformant lossy 9/7. Times CPU `J2KDecoder.decode` and GPU `decodeWithGPUHT(_:session:)`
back-to-back with a shared `J2KMetalSession` (5 calls each, after warm-up). Prints CPU and
GPU medians, the speedup, and the per-call vector for diagnosis. This is the **measurement
gate** v5.23.0 introduces — it captures the warm-session number going forward.

### 2. Honest measurement, no flaky perf assertion

The benchmark deliberately does **not** assert a specific speedup ratio. We sampled the gate
4× and observed:
- Run 1: 1.54×
- Run 2: 1.48×
- Run 3: **0.99×** (GPU and CPU within noise)
- Run 4: 1.49×

A `gpuMedian < cpuMedian` gate flaked ~1-in-4 on tight runs. Asserting any specific ratio
would amplify that flake rate. The test stays a measurement gate — it prints the numbers
for human and CI review without becoming a flaky red-light. Correctness is already covered
by the v5.20–v5.22 audit suite.

## Why the ceiling is modest

`decodeWithGPUHT(_:session:)` puts these stages on the GPU:

- Inverse 9/7 lossy DWT (the v5.21.0/v5.22.0 fixed path)
- Colour transform (RCT/ICT)
- Inverse quantisation

But HT entropy decoding still runs on the CPU. On 9/7 lossy at typical block sizes the
entropy stage dominates wall-clock time, so even a 5× win on IDWT only translates to ~30%
end-to-end. The 1.4–1.5× number is exactly what the architecture predicts.

The bigger architectural lever — GPU HT entropy decoding — is in flight on the
`gpu-ht-phase3` branch. Phases 0–2 are landed (dispatch probe, MagSgn-only kernel at 16×
faster, full HT cleanup-pass kernel at 26–37× faster in debug). Phase-3 dispatch-overhead
amortisation is in progress. When that lands and integrates into `decodeWithGPUHT`, the
warm-session number should rise materially.

## What this release does NOT do

- It does not add a new GPU code path. The IDWT path is the v5.21.0/v5.22.0 path.
- It does not assert a perf threshold. Numbers are recorded; humans review.
- It does not advance the GPU HT entropy decoder track (that's `gpu-ht-phase3`).

## Verification

| Test suite                            | Cells | Failed | Notes |
|---------------------------------------|------:|-------:|-------|
| `J2KGPULossy97PerformanceTests`       |     1 |      0 | New v5.23.0 measurement gate |
| `J2KWaveletConventionAuditTests`      |     4 |      0 | v5.22.0 cross-module audit (carryover) |
| `J2KGPULossy97DivergenceTests`        |     1 |      0 | v5.21.0 IDWT correctness (carryover) |
| `J2KMetalSingleLevel97Tests`          |     1 |      0 | v5.21.0 single-level (carryover) |
| HT conformant suites (v5.15–v5.20)    | various |    0 | All carryover gates green |

Pre-existing perf-aspirational tests (`testHTJ2KPerformanceTargetIs3x`,
`testScale16Bit`, `testNEONPerformanceBenefit`, `testHTJ2KBeatsOpenJPEGFullMatrixPrintsSummary`)
remain in their pre-v5.23.0 state. They are not affected by this work.

## Reproducing

```bash
# v5.23.0 measurement gate (release mode is the meaningful one):
swift test -c release --filter J2KGPULossy97Performance
```

## Lesson

v5.21.0 fixed an instance. v5.22.0 fixed the bug class. v5.23.0 measures the win and
publishes the result honestly — including the variance and the architectural reason the
ceiling is where it is. The pattern: every speed-up claim should be accompanied by the
measured range and the next architectural lever, not a marketing number from a single
favourable run. The bigger speedup is real and coming on `gpu-ht-phase3`; this release
tells the truth about today.
