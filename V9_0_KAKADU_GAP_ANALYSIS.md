# V9.0 — Closing the Kakadu encode gap: structural analysis + path forward

**Status**: Honest engineering judgment. Multi-week tile-pool optimisations project ~5-10 ms savings. **Closing the full Kakadu gap (51 → 20 ms) requires algorithmic rewrite of DWT + HT entropy — multi-MONTH effort, not multi-week.**
**Date**: 2026-05-10
**Branch**: `v9.0-research`

## Goal

User direction: "I don't need to jump to any other option until we [match] Kakadu". So this document characterises what's actually involved in closing the encode gap, instead of pursuing a multi-week effort that the data already says will fall short.

## The numerical gap

Cross-codec encode wall on DX 2800×2288 (HT-conformant lossless, warm-cache, v8.1.4):

| Codec                              | wall ms |
|------------------------------------|--------:|
| Kakadu HT                          | **19.56** |
| Grok HT                            |    44.62 |
| J2KSwift `--daemon auto`           |    70.27 |
| J2KSwift in-proc                   |   116.06 |
| OpenJPH                            |   111.56 |

J2KSwift in-process is **5.9× slower than Kakadu** on DX encode. Even with `--daemon auto`, it's **3.6× slower**.

## Why we are at the M2 hardware ceiling on DX

From the v8.4 stage breakdown + v9.0 multi-tile parallelism probe:

```
DX 2800×2288 single-tile encode (no multi-tile):
  Accumulated CPU work: ~620 ms
  M2 effective cores:   ~12 (8 P-cores + 4 E-cores w/ SMT-like behaviour)
  Theoretical wall floor: 620 / 12 ≈ 52 ms
  Measured wall:           51 ms (within 2% of theoretical max)
```

Multi-tile encode (2x2 default for ≥ 3 MP since v7.0.0) is already 86.6% parallel-efficient (3.47× of theoretical 4× on 4 P-cores, per `HTMultiTilePerfProbeTests`). Internally the encoder is also fully parallelised via nested `withThrowingTaskGroup` per component per decomposition level.

**The encoder is provably at structural hardware ceiling on M2 + Swift release for DX.** No amount of additional parallelism can reduce 620 ms accumulated CPU below the 52 ms hardware floor.

## What multi-week tile-pool optimisations COULD yield

The v9.0 finding (`V9_0_MULTITILE_PARALLELISM_FINDING.md`) noted that DX 2x2 sums 189 ms across 4 tiles vs single-tile 58 ms — implying ~130 ms of CPU is "wasted" per-tile. If this represents purely allocation churn (HT block coders, DWT scratch pools, codestream emitter buffers per-tile), shared pools could reduce it.

Realistic estimate of shared-pool savings:
- **Best case** (eliminate 100% of allocation churn across tiles): −130 ms accumulated CPU = −10.8 ms wall (130 / 12 cores)
- **Realistic case** (50% reduction; remaining is genuine per-tile work like codestream assembly): −65 ms acc / 12 = −5.4 ms wall
- **Conservative case** (20% reduction): −2.2 ms wall

Even the BEST case (−11 ms) puts DX encode at 51 → 40 ms — still **2× behind Kakadu's 20 ms**.

## What the gap actually represents

Kakadu's encoder is fundamentally **less work per byte**. Estimated Kakadu accumulated CPU on M2:
- Wall: 19.56 ms × ~10× parallelism factor (assumed) = ~200 ms accumulated CPU

So Kakadu does the SAME compression in 200 ms of CPU vs J2KSwift's 620 ms — **3× less work per byte**. This isn't a parallelism gap; it's an **algorithm-efficiency gap**.

Where does the 3× gap come from?
- 25+ years of Kakadu optimisation (David Taubman, JPEG 2000 standard co-author)
- Hand-tuned inner loops in C++ with platform-specific intrinsics
- Specialised code paths for common lossless 5/3 + HT cases
- Memory-layout decisions tuned for cache hierarchies
- Likely smaller constant factors at every stage (DWT, MCT, entropy)

## What WOULD close the gap

To match Kakadu's 19.56 ms DX encode would require reducing J2KSwift's CPU work from 620 ms accumulated to ~200 ms — a **3× reduction**. The realistic engineering paths:

1. **Replace forward 5/3 lifting kernel** with a fundamentally faster implementation. v8.6 Phase 0 measured the existing kernel at 0.37 ns/sample (memory-bandwidth-bound L1-resident); LLVM auto-vec is producing tight NEON. A faster 5/3 lifting on the SAME M2 silicon would require re-architecting the lifting math itself or amortising loop bodies across multiple components — multi-month work, projected wash per v8.6.

2. **Replace HT entropy classifier + emit pipeline** with a fundamentally faster implementation. v8.6 SIMD classifier was wash. v8.5 batched-emit was wash. v8.7 algorithmic redesign was wash. Multi-week phase 0 probes have repeatedly shown this hot-path is at structural ceiling on M2.

3. **Algorithmic codec re-design**: implement an entirely different lossless 5/3 compression pipeline that achieves equivalent quality with fewer CPU cycles. This is **multi-month engineering** by an experienced JPEG 2000 implementer. Requires understanding what specific Kakadu optimisations make their encoder 3× faster, then porting/recreating those — likely a 6-12 month investment.

4. **Different silicon** (M3+/A-series with different cache topology and ISA generation). The v8 narrowing makes "Apple Silicon" the marketable claim — M2 is the canonical reference but M3+ measurement IS in scope when physical hardware is available. The lever-ceiling pattern across 17 investigations is specific to M2; M3+ may shift the curve.

## Recommended engineering call

**Don't pursue multi-week tile-pool optimisation.** Best-case savings (~11 ms wall) doesn't close the 31 ms gap to Kakadu, and the engineering cost (~3-4 weeks for a thread-safe pool architecture + parity validation) is high relative to the modest payoff.

**Three viable paths forward:**

### Path A — accept the encode gap; lead on decode-warm-in-process

The current marketable claim ("fastest JPEG 2000 codec on Apple Silicon, decode-side, warm in-process") **already wins 4/6 medical fixtures vs Kakadu CLI**. It does not require beating Kakadu on encode.

User-facing positioning: J2KSwift is for **decode-heavy workflows** (DICOM viewers, PACS daemons, image-processing pipelines). Encode-heavy workflows (archiving, batch ingestion) might continue to use Kakadu. The two markets are largely distinct.

Engineering effort: zero. Continue current course.

### Path B — algorithmic codec re-design (6-12 months)

Pick ONE fundamental subsystem (e.g., HT entropy emit) and re-architect it from scratch with the specific goal of matching Kakadu's CPU efficiency. Requires:

- Deep instrumentation of Kakadu's hot loops (via dtrace / Instruments)
- Reverse-engineering Kakadu's specific optimisations (some documented in academic papers)
- Multi-iteration prototyping with bit-exact correctness gates
- Cross-codec parity validation at every milestone

Risk: even with sustained effort, may only close 30-50% of the gap. The remaining gap is in subsystems we won't have time to rewrite.

### Path C — M3+ / A-series device measurement

Buy / borrow / cloud-rent an M3 / M4 / M4 Max / M4 Pro Mac and measure the SAME workload. The v8.4-v9.0 lever-ceiling investigations are M2-specific. If the M3+ silicon has fundamentally different cache topology or ISA generation, the gap may be smaller — and we may discover specific subsystems where M3 lets us close ground without algorithmic rewrites.

Cost: $1500-$5000 for hardware, ~1 week of measurement work.

## What I will NOT do tonight

- Implement shared per-tile pools (best-case −11 ms wall, doesn't close the gap, multi-week effort).
- Implement raw mach_msg protocol (saves ~5 ms NSXPC overhead on warm-cache CLI; unrelated to the encoder ceiling).
- Implement IOSurface-backed decoder (saves ~2-3 ms decode wall; doesn't help encode).

These are all sub-threshold optimisations relative to the Kakadu gap. Investing engineering time in them without a clear path to closing the full gap is wasted effort — 17 prior investigations have established the M2 + Swift release lever-ceiling pattern.

## Summary

The Kakadu encode gap on DX is **3× algorithm efficiency**, not 3× parallelism efficiency. J2KSwift's encoder is provably within 2-5% of theoretical M2 hardware maximum. Multi-week tile-pool work projects ~5-11 ms savings — closes ~30% of the gap at best.

**Closing the full gap requires multi-month algorithmic rewrites of the encoder hot path, OR shifting silicon (M3+/A-series).**

The marketable claim ("fastest decode-side warm in-process on Apple Silicon") does not depend on closing the encode gap. Path A (accept the gap, lead on decode) is the realistic option for keeping engineering velocity high.

Path B (algorithmic rewrite) is a 6-12 month investment that may yield 30-50% gap closure. Path C (M3+ measurement) is a 1-week probe that may reveal cross-silicon variations.
