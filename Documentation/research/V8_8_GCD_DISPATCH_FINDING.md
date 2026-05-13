# V8.8 — GCD `concurrentPerform` vs Swift `TaskGroup` dispatch overhead: projected wash

**Status**: WASH (Phase 0 projection). Closes the GCD-dispatch lever before Phase 1A prototype.
**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0`
**Bench**: [`Tests/J2KCodecTests/V8_8_GCDvsTaskGroupPhase0Bench.swift`](Tests/J2KCodecTests/V8_8_GCDvsTaskGroupPhase0Bench.swift)

## Goal

v8.7 phase-0 identified that the forward 2D 5/3 DWT's 18.78 ms wall on DX 2800×2288 single-level is dominated NOT by inner lifting (0.37 ns/sample, ~6 ms acc CPU) NOR by transpose (0.07 ns/cell, 0.4% of stage), but by **per-strip TaskGroup dispatch + the 25 MB srcBuf/dstBuf copies + multi-tile coordination**.

`forward2D_53Pooled` uses Swift's `await withTaskGroup` with one task per column-strip. For DX with `stripWidth = 8`, that's ~350 tasks per L0 column pass. Each Swift `Task` allocation pays ~1–2 µs of structured-concurrency overhead (closure capture, parent-task linkage, async/await suspension boundaries, task cancellation tracking).

Apple's `DispatchQueue.concurrentPerform` runs over the same pthread_workqueue under libdispatch but skips the structured-concurrency tracking and async boundary crossings. The user requested an Apple-specific kernel-level probe; this was the candidate most likely to clear the threshold given the v8.7 dispatch-overhead identification.

## Headline data

```
=== v8.8 Phase 0 — dispatch overhead A/B at DX strip count ===
Workload: 350 strips × 18304 scalar ops/strip (~10 µs/strip).
Apple M2, release-mode. 7 runs, median.

  N strips | TaskGroup ms | concurrentPerform ms | Δ ms     | %
  ---------+--------------+----------------------+----------+------
  10       |        0.076 |                0.074 |   +0.002 |  +2.9%
  50       |        0.213 |                0.174 |   +0.039 | +18.5%
  100      |        0.343 |                0.280 |   +0.063 | +18.4%
  350      |        1.092 |                0.942 |   +0.150 | +13.7%
  700      |        2.127 |                1.779 |   +0.348 | +16.4%
```

`concurrentPerform` is consistently **13–18% faster** than `TaskGroup` at meaningful strip counts, confirming the Swift structured-concurrency overhead is real and measurable. But the **absolute** delta at DX scale is **0.15 ms per call**.

## Projection to DX wall

```
per-call savings @ 350 strips:   0.150 ms wall
pyramid factor (5-level):        1.332x
multi-tile factor (2x2 auto):    4.000x
estimated total wall savings:    0.798 ms

⇒ < 3 ms threshold. Wash; close.
```

## Decision: WASH; close v8.8 before Phase 1A

The dispatch-overhead delta exists and is consistent across DX-scale batch sizes. But the per-call savings at 350 strips is 0.15 ms wall; even after multiplying through the 5-level pyramid (1.33×) and the 2x2 multi-tile dispatch (4×), the projected DX wall savings is **0.80 ms** — below the v7.4 ≥3 ms acceptance threshold.

Phase 1A would require restructuring `forward2D_53Pooled` (and the row-pass path) to use `concurrentPerform`, which has a synchronous signature and forces the surrounding `async` function into a `withCheckedContinuation` workaround. That's non-trivial scaffolding work for sub-threshold gain, plus loses the structured-concurrency cancellation guarantees the encoder pipeline depends on at the higher layers.

## Companion data — `concurrentPerform` IS measurably faster

This investigation confirms what is likely a folklore datapoint in the Apple performance community: at ≥50 small task-units, `DispatchQueue.concurrentPerform` is meaningfully (13–18%) faster than `withTaskGroup`. For codebases where the per-task work is genuinely tiny and the parent task doesn't need cancellation propagation, the GCD path is the right primitive. v8.x J2KSwift uses TaskGroup intentionally (cancellation propagates through to the encoder's `cancel()` API), so the trade-off favours TaskGroup.

## Nine-investigation lever-ceiling table

| Direction  | Investigations                                                                                        | Outcome  |
|------------|-------------------------------------------------------------------------------------------------------|----------|
| Decode     | v6-alpha4, v7.4, v7.5, v8.1, v8.4, v8.5                                                                | WASH all |
| Encode     | v8.6 forward DWT lifting, v8.6 HT SIMD classifier, v8.7 algorithmic                                    | WASH all |
| Dispatch   | **v8.8 GCD concurrentPerform (this)**                                                                  | **WASH** |

Nine independent investigations on M2 + Swift release + macOS confirm the J2KSwift codec hot-path is at structural lever ceiling.

## What WOULD justify reopening this

1. **Per-task work shrinks below ~5 µs** — at very-fine-grained dispatch the `concurrentPerform` advantage scales linearly (~13-18% reduction in dispatch overhead becomes a larger fraction of total work). The current per-strip work is 10-15 µs.
2. **A different machine class** — M3+/A-series may have different libdispatch / Swift runtime tuning that shifts the trade-off. Out of scope without device access.
3. **Dropping the cancellation guarantee** — would simplify the `concurrentPerform` integration. Would require a public-API audit of where cancellation flows through encoder pipelines.

## What stays in tree

- `Tests/J2KCodecTests/V8_8_GCDvsTaskGroupPhase0Bench.swift` — the dispatch-overhead microbench. Future-investigator reference.
- `V8_8_GCD_DISPATCH_FINDING.md` — this document.

No production code change. No public API surface change.
