# V8.1.0 Phase 4 — 16-byte NEON full-vector prefix-scan + 192-bit accumulator: no additional lever

**Status**: WASH — 16-byte NEON prototype is no better than the Phase 1B 8-byte SWAR path at corpus density and worse at higher densities. **v8.1 prefix-scan / SWAR refill workstream definitively closed.**
**Date**: 2026-05-10
**Branch**: `v8.1-phase-4-16byte-neon-prefix-scan`
**Bench**: [`Tests/J2KCodecTests/V8_1_Phase4_NEON16Bench.swift`](Tests/J2KCodecTests/V8_1_Phase4_NEON16Bench.swift)

## Goal

Implement and measure the "future-investigator" path called out in `V8_1_0_PHASE_2_FINDING.md`: the 16-byte NEON full-vector prefix-scan with a 192-bit accumulator (`tmp_lo` + `tmp_mid` + `tmp_hi`). Decision rule: **if the 16-byte path beats the 8-byte path by ≥ 0.5 ns/call at corpus density 0.4 %, Phase 5 production-integrates it.**

## Method

Apple M2, Swift 6.2 release-mode, median of 5 runs at each cell, 200,000 read iterations, 4 MiB synthetic stream, 14-bit reads (DX corpus average). Three-way A/B at the `read(count:)` API:

1. v7.4 4-byte SWAR (production default)
2. v8.1 8-byte SWAR (Phase 1B opt-in)
3. v8.1 16-byte NEON prefix-scan + 192-bit accumulator (Phase 4 prototype)

The 16-byte prototype uses `SIMD16<UInt8>` for FF detect and per-byte u-state computation (the compiler maps SIMD16 ops to NEON on ARM64). Scalar reduction does 16 shifted-OR contributions into the 192-bit accumulator. `read()` does an unconditional 3-limb 192-bit right shift.

## Headline data — 3-way FF-density sweep at 14-bit reads

| target FF % | v7.4 4B ns | v8.1 8B ns | v8.1 16B ns (proto) | 16B vs 8B | 16B vs v7.4 |
|---|---:|---:|---:|---:|---:|
| 0.0          | 3.78 | 3.69 | 3.69 | **1.00×** | 1.02× |
| 0.4 (corpus) | 4.81 | 4.03 | **4.00** | **1.01×** | 1.20× |
| 1.0          | 5.15 | 4.29 | 4.42 | **0.97×** | 1.16× |
| 5.0          | 6.30 | 5.52 | 6.23 | **0.89×** | 1.01× |
| 10.0         | 7.23 | 6.19 | 6.87 | **0.90×** | 1.05× |
| 25.0         | 7.33 | 7.05 | 7.31 | **0.96×** | 1.00× |

**At corpus density (0.4 %): 16-byte saves 0.03 ns/call vs 8-byte — essentially noise.** Decision rule (≥ 0.5 ns/call) NOT met.

**At densities ≥ 1 %: 16-byte is SLOWER than 8-byte.** The 192-bit `read()` shift cost (3-limb cascade: 3 shifts + 3 ORs = 6 ops vs the 8-byte path's 3 ops) outweighs the per-refill savings as slow-path frequency rises.

## Why the 16-byte path doesn't beat the 8-byte path

1. **`read()` cost dominates the per-call budget.** The 192-bit accumulator drain in `read()` runs on every call; the 16-byte refill runs only when `bits < count`. At corpus density and 14-bit reads, refill frequency is roughly 1 in every 5 reads — so the 192-bit drain pays the cost 5× more often than the 16-byte refill saves cycles.

2. **SIMD16 → NEON mapping doesn't reduce slow-path serial dependency.** The 16-byte slow path's residual cost is the 16 shifted-OR contributions into the 192-bit accumulator. Each contribution depends on the previous accumulator state — no SIMD speedup is available there. The SIMD parts (FF detect, u-state shift, mask compute) are already very cheap; eliminating them in scalar code was never going to be the lever.

3. **Apple M2 has unusually wide load throughput.** The `lo64` + `hi64` pair load in the fast path is one cycle. The cycle savings vs two separate 4-byte loads (v7.4) or one 8-byte load (Phase 1B) are minimal — the fast path is already memory-bandwidth-bound, not load-count-bound.

4. **The fundamental wash from Phase 2 is unchanged.** The synthetic-microbench → real-DX-wall translation breakdown documented in `V8_1_0_PHASE_2_FINDING.md` still applies. Even if the 16-byte path SHOWED a microbench win (it doesn't), end-to-end DX wall would absorb it into the surrounding entropy-decode dependency graph just as Phase 2's 8-byte production result did.

## Parity (4 tests, all PASS in release mode)

- `testParity_Prototype16VsProduction` — 5 densities × 3 seeds × 4 widths × 200 reads = 12,000 cells
- `testParity_StreamExhaustionPadding` — 11 stream sizes × 4 widths × 10 reads = 440 cells
- `testParity_HeavyFFEdgeCases` — 4 16-byte FF-pattern cases × 4 widths × 8 reads = 128 cells
- `testBench_v74_v8_8byte_v8_16byte_FFDensitySweep_14bit` — bench prints headline data

Every parity cell produces bit-identical output between the 16-byte prototype and v7.4 production.

## On A-series re-measurement

The Phase 2 finding flagged "A-series re-measurement on iPhone 17 Pro / iOS 26.x" as a future-investigator path. **iOS Simulator on Apple Silicon Mac runs ARM64 NATIVELY on M2 hardware** — it is not a faithful proxy for actual A-series silicon. The iOS Simulator measurement would just reproduce M2 numbers with a small Foundation/runtime overhead delta.

**Real A-series measurement requires physical iPhone hardware.** Without that, the A-series path remains unmeasured. If a future J2KSwift release ships on iPad / iPhone with active development on those devices, re-running `V8_1_Phase1B_Microbench` and `V8_1_Phase2_DXWallAB` on the device (via Xcode device test) would close the question.

## Decision: WASH; v8.1 workstream definitively closed

1. **`swarRefill8Enabled` stays default OFF.** Production uses v7.4 4-byte SWAR.
2. **The 16-byte NEON prototype stays in the test file** as future-investigator reference — it was the most ambitious extraction of the lever and the data shows the lever doesn't exist on M2.
3. **No production integration of the 16-byte path.** Decision rule (≥ 0.5 ns/call vs 8-byte at corpus density) not met.
4. **v8.1 prefix-scan / SWAR refill workstream closed.** Three iterations of Apple M2 measurement (Phase 1A 8-byte microbench wins → Phase 2 DX wall wash → Phase 4 16-byte microbench no-win) converge on the same conclusion: the lever isn't extractable on this hardware family + Swift release.

## What's left for future investigators

- **Real A-series measurement** on physical iPhone hardware (not Simulator).
- **Different algorithmic class** entirely — not refill-internal optimisation, but a redesign of the entropy decoder's `read()` consumer (J2KHTConformantBlockDecoder) that batches multiple `read()`s into wider operations. That moves the lever out of MagSgn refill and into the entropy decoder body.
- **GPU HT entropy** with the v7.5.1-disabled batched path's correctness fixed (the `decodeMultiTileGPUBatched` 24-bit overflow root-cause is still open per `project_v7_5_1_hotfix.md`).

## Reproducing

```bash
swift test -c release --filter 'V8_1_Phase4_NEON16Bench'
```

All 4 tests run in <1 s.
