# V8.5 — HT entropy consumer body batched-read: projected wash; workstream closed

**Status**: WASH (Phase 0 projection). Closes the "next plan to beat Kakadu" recommendation tree's #2 item before Phase 1 implementation.
**Date**: 2026-05-10
**Branch**: `v8.5-ht-consumer-body-investigation`
**Bench**: [`Tests/J2KCodecTests/V8_5_HTConsumerBodyPhase0Bench.swift`](Tests/J2KCodecTests/V8_5_HTConsumerBodyPhase0Bench.swift)

## Goal

Per `V8_4_DECODE_LEVER_CEILING_CONFIRMED.md`, the only remaining technical decoder lever inside the existing ISA was **algorithmic redesign of the HT entropy consumer body**: collapse the 4 sequential `magsgnDec.read(count: m_i)` calls in `readQuadSamples` into ONE wider read followed by a manual shift+mask split. Phase 0 establishes whether that's worth implementing.

## Method

The consumer body in `J2KHTConformantBlockDecoder.readQuadSamplesScalar` (and its SIMD twin) issues:

```swift
var p0: UInt32 = 0; if r0 != 0 { p0 = magsgnDec.read(count: m0) }
var p1: UInt32 = 0; if r1 != 0 { p1 = magsgnDec.read(count: m1) }
var p2: UInt32 = 0; if r2 != 0 { p2 = magsgnDec.read(count: m2) }
var p3: UInt32 = 0; if r3 != 0 { p3 = magsgnDec.read(count: m3) }
```

— 4 sequential `read(count:)` calls per quad, each paying its own refill check + bit-shift bookkeeping + return-value plumbing.

The hypothesised batched form:

```swift
let combined = UInt64(magsgnDec.read(count: m0 + m1 + m2 + m3))
let p0 = combined & ((UInt64(1) << m0) - 1); let c1 = combined >> m0
let p1 = c1 & ((UInt64(1) << m1) - 1);  let c2 = c1 >> m1
// …
```

— ONE `read(count:)` call, three shifts, four masks. Saves three refill checks and three bit-buffer drains, paying small split overhead.

The microbench measures both shapes on a 4 × 7-bit per-quad pattern (28 bits/quad — typical DX corpus average per the `V740NeonRefillMicrobench`-derived "14 bits per read" figure). Median per-quad ns reported.

## Headline data

```
4-reads:     14.27 ns/quad
batched:      6.04 ns/quad
Δ:           +8.23 ns/quad
```

Each `read(count: 7)` costs ~3.6 ns amortised (consistent with the v8.1 Phase 1B microbench: ~4.06 ns at corpus FF density). Four of them → ~14 ns/quad. The batched single read at count = 28 plus the 4-way split is ~6 ns/quad.

## Projection to DX 2800×2288 wall

DX has ~6.4 M pixels = 1.6 M quads (at 100 % rho). Typical rho ~0.5 → ~800 K quads actually issuing reads.

```
Accumulated CPU savings:  ~6587 µs
Wall savings (÷5 parallelism per v8.4 stage breakdown):
                          ~1.32 ms
```

**1.32 ms wall savings** vs the v7.4 acceptance threshold of **3 ms**. Decisively below.

## Decision: WASH; close v8.5 before Phase 1A

The microbench shows the batched read is genuinely faster in isolation (~2.4× the per-quad cost). But the DX scale doesn't have enough quads to translate that into the 3 ms threshold required to ship a default-on perf change.

Even allowing for measurement variance and a higher rho fraction (e.g. 0.75 → ~1200 K quads → ~2.0 ms wall), it stays below threshold.

This matches the structural pattern documented across **five** independent decoder lever-ceiling investigations:

| investigation | conclusion |
|---|---|
| v6-alpha4 step 12 | C+D refactors reverted; cache locality / i-cache pressure |
| v7.4 closure | Phase 1 NEON reconstruction Δ 0.90 ms (threshold-borderline; promoted in v8 Phase 4) |
| v7.5 closure | Forward HT GPU entropy 6.7× CPU per-block; closed wash |
| v8.1 prefix-scan | 8-byte SWAR microbench wins, end-to-end DX wash; 16-byte NEON also wash |
| **v8.4 / v8.5** (this) | **No remaining technical lever inside the existing ISA produces ≥ 3 ms** |

## What would justify reopening this

The 3 ms wall threshold corresponds to ~15 ms accumulated CPU (÷5 parallelism). For batched-read to clear it on DX, the per-quad savings would need to be **~19 ns/quad** — more than double what was measured. That would require either:

1. **A different bench fixture** with significantly more quads (e.g. an 8-MP-class lossless DX-shape on M3+ where parallelism scales). v8.4 found no crossover at 16 MP.
2. **A bigger per-quad delta** — would require eliminating the bit-buffer drain itself (not just the read-call overhead). That's a larger architectural change than batching.

Both are speculative. Neither qualifies for autonomous-overnight implementation work given the v7.4 / v8.1 acceptance discipline.

## What stays in tree

- `Tests/J2KCodecTests/V8_5_HTConsumerBodyPhase0Bench.swift` — the parity check + microbench. Future-investigator reference; rerun trivially with `swift test --filter 'V8_5_HTConsumerBodyPhase0Bench'`.
- `V8_5_HT_CONSUMER_BODY_FINDING.md` — this document.

No production code change. No new public API surface.

## Reproducing

```bash
swift test -c release --filter 'V8_5_HTConsumerBodyPhase0Bench/testBench_4Reads_vs_Batched_Simple'
```
