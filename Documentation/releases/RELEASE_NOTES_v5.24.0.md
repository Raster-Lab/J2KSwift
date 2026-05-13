# J2KSwift v5.24.0 — Stage-Level Decode Timings + 9/7 Lossy Strategy

**Release date:** 2026-05-04
**Theme:** v5.23.0 measured end-to-end warm-session 9/7 lossy decode speedup at
~1.05–1.54× and described the ceiling as "GPU IDWT only owns part of the work; HT entropy
is on CPU." That description was **wrong** — the GPU HT entropy decoder is wired into
`decodeWithGPUHT` and has been since the M2-prime integration landed. v5.24.0 adds
stage-level timing instrumentation, runs a three-path comparison, and corrects the
narrative based on what the breakdown actually shows.

## Headline finding

For 9/7 lossy decode at 1024×1024, three paths warm-session, release mode, M2, n=5:

| Path                                          | Median   | Speedup |
|-----------------------------------------------|---------:|--------:|
| `decode`         (CPU)                        | 25.6 ms  | 1.00×   |
| `decodeGPU(_:session:)` (CPU HT + GPU IDWT)   | 17.8 ms  | **1.43×** |
| `decodeWithGPUHT(_:session:)` (GPU HT + IDWT) | 24.0 ms  | 1.07×   |

`decodeGPU` — which keeps HT entropy on CPU — is the fastest path today. `decodeWithGPUHT`
is *slower* because the per-tile GPU HT dispatch overhead (~11.6 ms) exceeds the
parallelised CPU HT cost (~1.3 ms) on this workload size.

## Per-stage breakdown (means, ms)

```
Stage                            CPU   gpuIDWT    GPU-HT
extractTileData                  0.2       0.2       0.2
entropyDecoding                  1.3       1.3      12.1
  ├─ gpuHTDispatch               0.0       0.0      11.6  ← cost on GPU-HT path
  └─ regroup (CPU)               1.3       1.3       0.5
dequantization                   0.5       0.4       0.6
inverseWaveletTransform         22.7      15.2      10.6  ← biggest GPU win
inverseColorTransform            0.0       0.0       0.0
dcLevelUnshift                   0.4       0.2       0.2
reconstructImage                 0.5       0.5       0.6
─────                            ───   ───────    ──────
instrumented total              25.6      17.8      24.3
```

Three observations from the breakdown:

1. **CPU HT entropy is fast** — 1.3 ms across all 224 codeblocks, parallelised across cores.
   The "HT entropy still on CPU" line in v5.23.0's notes implied this was a bottleneck;
   the data shows it isn't.
2. **GPU IDWT is the dominant win** — 22.7 → 15.2 ms in `decodeGPU` (saves 7.5 ms);
   → 10.6 ms in `decodeWithGPUHT` (saves a further 4.6 ms via smaller per-level
   upload/readback envelopes).
3. **GPU HT dispatch is the regression** — 11.6 ms per tile even after session warm-up.
   This is per-call dispatch + memory-transfer + kernel-launch overhead, not the kernel
   work itself (the kernel benchmark in `J2KMetalHTCleanupTests` was already known to be
   ~0.5× CPU in release mode per the prior release-readiness report).

## What v5.24.0 ships

### `J2KDecodeTimings` — stage-level decoder timings accumulator

`Sources/J2KCodec/J2KDecodeTimings.swift` — process-global, NSLock-protected,
always-on. Mirrors the `J2KMetalUMACounters` pattern. Tracks 8 stages:

- `extractTileData`
- `entropyDecoding` (with sub-stage `gpuHTDispatch`)
- `dequantization`
- `inverseWaveletTransform`
- `inverseColorTransform`
- `dcLevelUnshift`
- `reconstructImage`

`reset()` before a decode, `snapshot()` after. Cost is ~tens of nanoseconds per stage
(NSLock + double add) — negligible against the millisecond-scale work bracketed.

Wired into all 14 existing `J2K_PROFILE_DECODE` profile sites (7 GPU + 7 CPU) inside
`J2KDecoderPipeline`. The env-var-gated `print` calls remain unchanged; the timings
accumulator runs in addition to them.

### `decodeGPU(_:session:)` — public API addition

`Sources/J2KCodec/J2KCodec.swift` — new public entry point that mirrors
`decodeWithGPUHT(_:session:)` but keeps HT entropy on CPU. On 9/7 lossy workloads where
per-tile GPU HT dispatch overhead exceeds the parallelised CPU HT cost (small/medium
images, low block counts), this entry point is faster than `decodeWithGPUHT`.

```swift
let session = J2KMetalSession()
let img = try await J2KDecoder().decodeGPU(data, session: session)
```

### `J2KGPULossy97PerformanceTests` — three-path benchmark

`Tests/J2KMetalTests/J2KGPULossy97PerformanceTests.swift` — extended to compare CPU,
`decodeGPU`, and `decodeWithGPUHT` side-by-side with full per-stage breakdown including
the `gpuHTDispatch` sub-stage. Reset/snapshot via `J2KDecodeTimings`.

## Errata for v5.23.0

v5.23.0's release notes and CHANGELOG entry described the 9/7 lossy ceiling as "modest
because `decodeWithGPUHT` only owns IDWT + colour transform + quantisation; HT entropy is
still on CPU." That was wrong. HT entropy IS on the GPU when `decodeWithGPUHT` is called
(via `J2KGPUHTDispatch.decodeBatch`), and the actual reason the ceiling is modest is the
opposite: GPU HT dispatch overhead exceeds CPU HT cost on small/medium images. The
v5.23.0 measurement gate is still valid; only the narrative was misframed.

## Strategy implication for next milestone

The next architectural milestone — extending the GPU-resident batch path (today only
fires for 5/3 lossless) to 9/7 lossy with a 9/7 scatter + fused float IDWT path — would:

- Close the IDWT gap (gpuIDWT 15.2 → ~10.6 ms by removing per-level upload/readback)
- Eliminate the small CPU regroup (0.5 ms in `decodeWithGPUHT`)
- **Not** fix the 11.6 ms `gpuHTDispatch` overhead

So that milestone makes `decodeWithGPUHT` competitive with `decodeGPU` on this workload,
but to make `decodeWithGPUHT` actually beat `decodeGPU` the GPU HT dispatch needs to drop
below ~5 ms. That's a separate optimisation track (smaller dispatch envelope, threadgroup
sizing, indirect command buffers, or workload-size routing).

For now: **callers wanting the fastest 9/7 lossy decode on warm session should use
`decodeGPU(_:session:)`**. `decodeWithGPUHT` remains the right path for 5/3 lossless
(where the fully fused GPU-resident path fires) and for very large 9/7 lossy workloads
where the dispatch overhead amortises.

## Verified

| Test suite                            | Cells | Failed | Notes |
|---------------------------------------|------:|-------:|-------|
| `J2KGPULossy97PerformanceTests`       |     1 |      0 | v5.24.0 stage breakdown |
| `J2KWaveletConventionAuditTests`      |     4 |      0 | carryover from v5.22.0 |
| `J2KGPULossy97DivergenceTests`        |     1 |      0 | carryover from v5.21.0 |
| `J2KMetalSingleLevel97Tests`          |     1 |      0 | carryover from v5.21.0 |
| HT conformant suites (v5.15–v5.20)    | various |    0 | All carryover gates green |

## Reproducing

```bash
swift test -c release --filter J2KGPULossy97Performance
```

## Lesson

Headline numbers without stage breakdown lie by omission. v5.23.0 measured a real
end-to-end speedup but described the ceiling using a model of the pipeline that didn't
match the merged code. v5.24.0 fixes the model with data: stage timings show GPU HT
dispatch is the regression, not CPU HT being the floor. Same shape as v5.22.0's audit
discipline: every fix should be accompanied by the measurement that verifies it works
end-to-end, not just at the kernel level.
