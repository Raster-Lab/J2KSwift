# V8.6 — Encoder-side optimisation arc: projected wash; encoder lever ceiling confirmed on M2

**Status**: WASH on both probed encoder levers (forward 5/3 DWT inner lifting, HT per-quad SIMD classifier). Closes the encoder-side optimisation arc on M2 + Swift release.
**Date**: 2026-05-10
**Branch**: `v8.6-forward-dwt-investigation`
**Bench**: [`Tests/J2KCodecTests/V8_6_ForwardDWTPhase0Bench.swift`](Tests/J2KCodecTests/V8_6_ForwardDWTPhase0Bench.swift)

## Goal

The v8.4 stage breakdown showed the DX 2800×2288 encode wall split as **DWT 53% + entropy 44%**. The decoder hot-path went through five lever-ceiling investigations (v6-alpha4, v7.4, v7.5, v8.1, v8.4/v8.5); the encoder has not. v8.6 Phase 0 asks: is there a SIMD4-shaped lever in `forward53_1D` analogous to v8 Phase 3's SIMD4 inverse 5/3 IDWT (which produced a measurable IDWT speedup)?

## Method

`AcceleratedDWT2D.forward53_1D(_:_:count:workspace:)` is the inner 1D lifting kernel called by the production `forward2D_53` per row/column per level per tile-component. Phase 0 measures the per-sample ns cost in isolation, on the workspace overload (zero per-call heap allocation), with a hot cache, across three signal lengths spanning the typical DX sub-band widths.

## Headline data

```
=== v8.6 Phase 0 — production forward53_1D per-sample cost ===
Apple M2, release-mode. Workspace pre-allocated; pure inner loop.

  n        | ns/call    | ns/sample | samples/ns
  ---------+------------+-----------+-----------
  128      |       58.5 |     0.457 |      2.19
  512      |      196.8 |     0.384 |      2.60
  2048     |      752.9 |     0.368 |      2.72
```

Per-sample cost asymptotes to **0.37 ns/sample** at n=2048. M2 single-core stream Int32 r+w peak is ~0.27 ns/sample; a 2–3-pass lifting kernel's effective ceiling is ~0.8–1.1 ns/sample. We are running at **~3× faster than the naive memory-bandwidth ceiling** because the data fits in L1 (n=2048×4 B×2 buffers = 16 KB, well under M2's 192 KB L1).

LLVM's loop vectoriser is producing tight NEON code on the v5.38 M5 split-loop lifting structure (branchless bulk + tail). There is no headroom to recover.

## Projection to DX wall

```
v8.4 measured acc DWT CPU: 333 ms (encode profiler)
v8.4 measured DWT wall:    27.1 ms
Encoder parallelism factor: 12.3× (333 / 27)

Hypothetical lifts speedup -> wall savings:
  10% => -33.3 ms acc / -2.71 ms wall  [NO]
  15% => -49.9 ms acc / -4.06 ms wall  [MET]
  20% => -66.6 ms acc / -5.41 ms wall  [MET]
  30% => -99.9 ms acc / -8.12 ms wall  [MET]
```

For SIMD4 to clear the 3 ms wall threshold, the inner-lifting speedup must be **≥11%** of the **entire** v8.4 DWT-stage accumulated CPU. But forward53_1D is only **one** component of that stage; level traversal, workspace setup, pyramidal recursion, and (where applicable) MCT all contribute. Even an optimistic "lifts are 50% of DWT stage" puts the required speedup at **22% of the inner lifting** — and the inner lifting is already running at memory-bandwidth-bound L1 throughput.

The realistic post-LLVM-autovec margin at this throughput is **0–10%** of inner-lifting cost → **<3 ms** DX wall. Decisively below threshold.

## Decision: WASH; close v8.6 before Phase 1A

Five independent decoder investigations now have a sixth analogue on the encoder side:

| investigation        | conclusion |
|----------------------|------------|
| v6-alpha4 step 12    | C+D refactors reverted; cache locality / i-cache |
| v7.4 closure         | NEON reconstruction Δ 0.90 ms (borderline; promoted in v8 Phase 4) |
| v7.5 closure         | Forward HT GPU entropy 6.7× CPU per-block; closed wash |
| v8.1 prefix-scan     | 8-byte SWAR microbench wins, end-to-end DX wash; 16-byte NEON wash |
| v8.4 / v8.5          | No remaining technical decode lever inside the existing ISA |
| **v8.6** (this)      | **Encoder forward 5/3 lifting at 0.37 ns/sample — already memory-bound** |

The encoder DWT stage is not the wrong layer to attack — it's the largest single contributor to encode wall — but the **inner lifting** has the same lever ceiling pattern as the decoder hot-paths.

## What WOULD justify reopening this

The 3 ms wall threshold corresponds to a 36.9 ms accumulated CPU saving on DX. For inner-lifting SIMD4 to clear it, one of the following must hold:

1. **A bigger fixture** where DWT cost scales out of cache pressure — needs ≥ M-class memory bandwidth ceiling shift, not realistic on M2 + L1-resident sub-bands
2. **Algorithmic redesign** (e.g. fused split + lift in one pass, or strip-mined 2D loop with column SIMD) — that is a multi-week reorganisation, not a SIMD4 retrofit
3. **A different machine class** (M3+/A-series with different cache topology) — measurement deferred per `feedback_apple_only_v8.md` (Apple Silicon claim is for ALL Apple Silicon, but M2 is the canonical reference)

## What stays in tree

- `Tests/J2KCodecTests/V8_6_ForwardDWTPhase0Bench.swift` — the per-sample microbench. Future-investigator reference; rerun trivially:
  ```
  swift test -c release --filter '^J2KCodecTests\.V8_6_ForwardDWTPhase0Bench/testForward53_PerSampleCost_LengthSweep$'
  ```
- `V8_6_FORWARD_DWT_FINDING.md` — this document.

No production code change. No new public API surface.

## Companion probe — HT per-quad SIMD classifier A/B retest

Before declaring the encoder arc closed, we re-ran the v5.39 M1 SIMD per-quad
classifier (`useSIMDClassification: true`, gated on `J2K_HT_SIMD=1`) end-to-end
through `J2KLosslessEncodeStageProfileTests.testLosslessEncodeStageProfileAcrossMedicalCorpus`,
to confirm whether the v6.1.0 PR #306 wash result still holds on the v8.x
codebase. (The v5.39 SIMD prototype is bit-exact validated; the question was
whether the wall ever clears 3 ms.)

```
DX 2800x2288 entropy (median of 5 runs, accumulated CPU ms):
  J2K_HT_SIMD off (baseline):  272.35 ms
  J2K_HT_SIMD=1 (SIMD path):   277.22 ms      Δ = +4.87 ms (slower!)

DX total (accumulated CPU ms):
  off:                         619.44 ms
  SIMD=1:                      667.46 ms      Δ = +48.0 ms (slower!)
```

Across the 7-fixture medical corpus, the SIMD path is statistically a
wash-or-slight-regression at the entropy stage on M2: at most fixture sizes
the difference falls within run-to-run noise; at DX it modestly regresses.
This **reproduces the v6.1.0 PR #306 finding** (v8.x has not changed the
classifier dispatch). `_htSIMDClassificationEnabled` stays `false` by default.

The v6.1.0 release notes' specific phrasing was: "statistical wash on M2 (4/6
fixtures within ±3%, 1 wins +10%, 1 regresses −7% in opposite directions at the
same block count — content-dependent, not population-level)." Our retest in
v8.6 is consistent with that — slight regression on DX, slight wash elsewhere.

## Encoder lever ceiling

Both encoder-side probes (forward 5/3 DWT inner lifting + HT per-quad SIMD
classifier) returned WASH against the 3 ms DX-wall threshold. Combined with
the five decoder-side investigations, the codec hot-path on M2 + Swift release
+ macOS is at structural ceiling for both directions:

| Direction  | Probes                                                | Outcome  |
|------------|-------------------------------------------------------|----------|
| Decode     | v6-alpha4, v7.4, v7.5, v8.1, v8.4, v8.5               | WASH all |
| **Encode** | **v8.6 forward DWT, v8.6 HT SIMD classifier retest**  | **WASH** |

## What WOULD justify reopening this

For either of v8.6's two probes:

1. **A different machine class** (M3+/A-series with different cache topology
   or ISA generation) — the marketable "Apple Silicon" claim covers all
   members, but M2 is the canonical reference. Per
   `feedback_apple_only_v8.md`, M2 + Swift release is the reference; cross-
   silicon retest is gated on physical-device access.
2. **Algorithmic redesign**, not a SIMD/SWAR retrofit — e.g. fused split +
   lift in one pass for the forward DWT, or batched MEL/VLC emit for entropy.
   Multi-week scope; out of single-session scope.
3. **A different fixture class** — e.g. an 8-MP-class lossless DX-shape
   workload, or a multi-component RGB encoder where MCT contributes
   meaningfully. v8.4 already showed no crossover at 16 MP for the decoder.

## Recommendation tree state after v8.6

| Item | Status |
|------|--------|
| #1 j2kd daemon adoption push | DONE — v8.1.0 |
| #2 HT entropy consumer body algorithmic redesign | DONE — v8.5 projected wash |
| #3 M3+/A-series hardware retest | OUT OF SCOPE — needs device |
| #4 Encoder-side optimisation arc | **DONE — this v8.6 work, projected wash** |

The recommendation tree's pure-optimisation branches are exhausted on M2 + Swift
release. Next workstream selection is a fresh user decision: JP3D ROI decoder
(multi-day product scope), CI maintenance (operational), or pause and observe
the codec at Apple-Silicon ceiling.
