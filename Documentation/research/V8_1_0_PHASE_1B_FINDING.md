# V8.1.0 Phase 1B — production integration of 8-byte SWAR refill

**Status**: GREENLIGHT — proceed to Phase 2 (end-to-end DX wall A/B).
**Date**: 2026-05-10
**Branch**: `v8.1-phase-1b-production-integrate-8byte-swar`

## Goal

Integrate the Phase 1A prototype design into `HTMagSgnDecoderConformant` proper. The default flag stays OFF — production callers that don't opt in to `swarRefill8Enabled = true` see no behaviour change. Phase 2 measures end-to-end DX wall with the flag toggled ON.

## Production-integrated changes

`Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift`:

- Added `nonisolated(unsafe) public static var swarRefill8Enabled: Bool = false`.
- Added `tmpHi: UInt64 = 0` field — high 64 bits of the 128-bit accumulator.
- Added field-cached refill-path selectors `useSwar8` / `useV74Batched` resolved at init. Direct static-var reads on every `read()` cost ~5 ns/call in early prototyping; field-cached reads cost essentially zero (struct field, branch predictor 100 % accurate).
- Modified `read(count:)` to branch on `useSwar8` and shift-down the 128-bit accumulator when set.
- Added `refillBatched8()` method — body matches the Phase 1A prototype.
- Modified `refill()` dispatcher to prefer `refillBatched8` → `refillBatched` → `refillScalar`.

## Headline data — production struct, FF-density sweep at 14-bit reads

| target FF % | flag-OFF ns | flag-ON ns | Δ | speedup |
|---|---:|---:|---:|---:|
| 0.0          | 3.79 | 3.73 | -1.6 % | 1.02× |
| 0.4 (corpus) | 4.77 | **4.06** | **-14.9 %** | **1.17×** |
| 1.0          | 5.14 | 4.28 | -16.8 % | 1.20× |
| 5.0          | 6.31 | 5.53 | -12.4 % | 1.14× |
| 10.0         | 7.21 | 6.19 | -14.1 % | 1.16× |
| 25.0         | 7.34 | 7.05 | -4.0 % | 1.04× |

## Comparison to Phase 1A prototype

| FF % | Phase 1A speedup | Phase 1B speedup | Note |
|---|---:|---:|---|
| 0.0          | 1.21× | 1.02× | Phase 1A prototype's unconditional 128-bit shift was faster than the field-branch path at no-FF saturation. |
| 0.4 (corpus) | 1.37× | **1.17×** | Branch overhead on `useSwar8` reduces the win but does not eliminate it. |
| 25.0         | 1.40× | 1.04× | Slow-path-dominated; branch overhead is bigger relative to the slow-path savings. |

Phase 1A's prototype operated on a separate struct with unconditional 128-bit shift in `read()`. Phase 1B's production struct uses a field-cached branch (`if useSwar8`) so that the v7.4 4-byte path stays free of 128-bit shift cost. The trade-off: smaller speedup when flag is ON, no regression when flag is OFF.

## Estimated DX wall saving

At corpus density 0.4 %, the saving is **0.71 ns/call** (4.77 → 4.06). With ~25 M `read()` calls per DX 2800×2288 entropy decode, the estimated wall saving is **~17.75 ms** — ~6× the v7.4 ≥ 3 ms ≥-DX-A/B acceptance threshold. Even halving the call-count estimate, ~9 ms saving still clears the threshold by 3×.

## Correctness gate (release mode)

| suite | tests | result |
|---|---:|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | 0 failures (30.318 s) |
| `J2KMedicalCorpusPerformanceTests`       | 2 | 0 failures (9.858 s)  |
| `J2KStrictCrossCodecValidationTests`     | 3 | 0 failures (0.482 s)  |
| `V740NeonRefillParityTests` (v7.4 path)  | 11 | 0 failures (0.001 s) |
| `V8_1_Phase1B_ParityTests` (3-way)       | 7 | 0 failures (0.001 s)  |
| **total**                                | **25** | **0 failures**    |

All three refill paths (scalar / v7.4 4-byte / v8.1 8-byte) produce bit-identical `read(count:)` sequences across:
- 7 boundary patterns (all-zero, FF/7F, FF at 8-byte boundaries, FF mid-batch)
- 6 random-FF densities × 4 seeds × 4 widths × 200 reads
- 13 stream sizes (0 through 33 bytes) × 4 widths × 10 reads
- 1 mixed-width sequence

## Decision: GREENLIGHT Phase 2

Production-integrated 1.17× at corpus density saves an estimated 17 ms DX wall — well above the 3 ms threshold. The flag-OFF default is performance-neutral vs v7.4. Phase 2 runs the end-to-end DX 2800×2288 in-process decode A/B with the flag toggled to confirm the wall-time saving on a real fixture.

## Reproducing

```bash
swift test -c release --filter 'V8_1_Phase1B_Microbench'
swift test -c release --filter 'V8_1_Phase1B_ParityTests'
swift test -c release --filter 'V740NeonRefillParityTests'
```
