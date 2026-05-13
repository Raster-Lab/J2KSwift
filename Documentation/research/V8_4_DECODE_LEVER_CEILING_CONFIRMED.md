# V8.4 — DX decode lever-ceiling on Apple M2 confirmed via three independent probes

**Status**: WASH. The "next plan to beat Kakadu" exploration confirms the M2 + Swift release lever-ceiling for the J2KSwift HTJ2K 5/3 lossless decoder hot path. No remaining technical lever produces ≥ 3 ms wall-time win on DX 2800×2288.
**Date**: 2026-05-10
**Branch**: `v8.4-decode-stage-breakdown`
**Probe**: [`Tests/J2KCodecTests/V8_4_GPUIDWTPerfProbe.swift`](Tests/J2KCodecTests/V8_4_GPUIDWTPerfProbe.swift)

## Context

Post-v8.0.1, J2KSwift warm in-process decode beats Kakadu CLI on 4 of 6 medical fixtures (MR-small / CT / MR / XA) but trails on **PX (1.26×) and DX (1.46×)**. The user asked "what is the next plan to beat Kakadu" — this finding documents the three probes run to answer that.

## Probe 1 — Fresh stage-by-stage breakdown on DX 2800×2288

`DecodeStageProfileLosslessCorpusTests.testDecodeStageProfile_LosslessCorpus_M2Baseline` on v8.0.1:

| stage | DX wall (ms, parallelism-adjusted) | % of wall |
|---|---:|---:|
| entropy | ~31 | **57 %** |
| iDWT | ~21 | **39 %** |
| extract | ~1.3 | 2 % |
| dequant | ~0.6 | 1 % |
| dcShift | ~0.3 | 1 % |
| **total** | **~54** | 100 % |

Compared to the v5.38 finding ("entropy is 45 % of DX"):
- Entropy share has GROWN to 57 % (because v8 Phase 3 SIMD4 IDWT reduced iDWT cost; relative share of the unchanged entropy went up).
- iDWT share is now 39 % (was 25-30 % at v5.38).

**No stage is ≥ 80 % alone**. Even eliminating entropy ENTIRELY only saves 31 ms wall — putting J2KSwift at ~22 ms vs Kakadu's ~17 ms pure decode. **Single-stage elimination cannot close the gap.**

## Probe 2 — GPU IDWT lift on DX 2x2 (the v8.2/v8.3 follow-up)

The v8.2 routing fix forces CPU IDWT when batched-entropy is active, sidestepping the v8.3-fixed GPU multi-tile-per-tile IDWT bug. With the GPU IDWT now correct, can lifting v8.2 produce a wall-time win on DX 2x2 (1.6 MP/tile, above the 1 MP GPU-IDWT threshold)?

`V8_4_GPUIDWTPerfProbe.testProbe_DX_GPUIDWTLeg` (median of 9):

| leg | description | DX wall |
|---|---|---:|
| A | batched entropy + CPU IDWT (v8.2 fix ON, current default) | 59.39 ms |
| B | batched entropy + GPU IDWT (v8.2 fix bypassed, v8.3-correct) | 59.80 ms |
| C | per-tile path (no batched, fused-from-codeblocks → CPU IDWT) | 59.54 ms |

- **Δ (A − B) = −0.40 ms** (within noise; GPU IDWT does NOT win)
- Δ (A − C) = −0.15 ms (no per-tile-vs-batched difference)

**WASH.** v8.2 routing fix stays absolute. GPU IDWT lever-ceiling for DX-class fixtures confirmed.

## Probe 3 — GPU-HT entropy at 16+ MP

The V8Phase5WarmInProcessBenchmark trend (PX 6.4× → DX 2.4× slower than CPU) suggested GPU-HT *entropy* might cross over and start winning at higher pixel counts. Test on a synthetic 4097×4097 = 16.8 M px fixture (the original mg-class scale that surfaced the v8.2 bug).

`V8_4_GPUIDWTPerfProbe.testProbe_LargeFixture_GPUHTEntropy` (median of 9):

| path | wall (ms) |
|---|---:|
| CPU warm decode | 153.27 |
| GPU-HT warm decode | 157.35 |

- **Δ (CPU − GPU-HT) = −4.08 ms** (CPU still wins at 2.6× DX size)

**WASH.** The crossover trend does not materialise even at 16 MP — per-block GPU cost on M2 stays above CPU.

## Conclusion

The Apple M2 + Swift release lever-ceiling for J2KSwift's HTJ2K 5/3 lossless decoder is structurally confirmed. Across **four** distinct lever-ceiling investigations (v6-alpha4 step 12, v7.4-7.5 closure, v8.1 prefix-scan, this v8.4 work), no technical lever inside the existing architecture produces ≥ 3 ms wall-time win on DX or larger fixtures.

**The remaining options to close the Kakadu gap are**:

1. **`j2kd` XPC daemon adoption** (already shipped in v8.0.0). Closes the *user-visible* CLI gap from 72 ms cold-shot to ~55 ms (eliminates Metal startup tax). Zero codec work; deployment-side lever.

2. **Algorithmic redesign of the HT entropy decoder consumer body** (`J2KHTConformantBlockDecoder` read-loop batching). Multi-week scope; high risk; the only remaining technical lever inside the existing ISA. Future-investigator territory.

3. **Apple A-series / M3+ measurement** on physical hardware. May show different cycle profiles. Currently un-measurable without device access.

The decoder itself has no extractable single-codec wins remaining within the existing kernel + lifting + scatter architecture on Apple M2 + Swift release.

## Reproducing

```bash
swift test -c release --filter 'DecodeStageProfileLosslessCorpusTests'
swift test -c release --filter 'V8_4_GPUIDWTPerfProbe'
```
