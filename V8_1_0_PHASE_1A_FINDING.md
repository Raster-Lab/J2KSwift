# V8.1.0 Phase 1A — 8-byte SWAR + 128-bit accumulator prototype

**Status**: STRONG GREENLIGHT — proceed to Phase 1B (production integration).
**Date**: 2026-05-10
**Branch**: `v8.1-phase-1a-8byte-swar-128bit-acc`
**Bench**: [`Tests/J2KCodecTests/V8_1_PrefixScanPhase1ABench.swift`](Tests/J2KCodecTests/V8_1_PrefixScanPhase1ABench.swift)

## Goal

Prototype, in a test-only file, an 8-byte SWAR refill backed by a 128-bit accumulator (`tmp_lo: UInt64` + `tmp_hi: UInt64`). Measure A/B vs the v7.4 4-byte SWAR production refill. Decide whether the lever is large enough to justify a production integration in Phase 1B.

## Method

Apple M2, Swift 6.2 release-mode, median of 5 runs at each cell, 200 000 read iterations per cell, 4 MiB synthetic stream with controlled 0xFF density (stuff-bit constraint enforced). 14-bit reads (DX corpus average).

The prototype mirrors `HTMagSgnDecoderConformant`'s `read(count:)` API and is API-compatible — same per-call cost attribution, same buffer warm-up, same reset cadence as the v7.4 baseline.

The prototype's `read(count:)` does an UNCONDITIONAL 128-bit right shift (`tmp` and `tmpHi` together) — the cost of the carry-shift is included in the per-call number, so the comparison is honest.

## Headline data — FF-density sweep at 14-bit reads

| target FF % | v7.4 ns/call | proto ns/call | proto Δ | proto speedup vs v7.4 |
|---|---:|---:|---:|---:|
| 0.0 (best)   | 4.13 | **3.43** | **-17.0 %** | **1.21×** |
| 0.4 (corpus) | 4.96 | **3.61** | **-27.3 %** | **1.37×** |
| 1.0          | 5.37 | **3.82** | **-28.8 %** | **1.40×** |
| 5.0          | 6.61 | **4.85** | **-26.6 %** | **1.36×** |
| 10.0         | 7.72 | **5.56** | **-27.9 %** | **1.39×** |
| 25.0         | 8.35 | **5.97** | **-28.6 %** | **1.40×** |

## Findings

1. **Win across the entire density range.** Best case (no FFs): 1.21×. Worst case (25 % FFs): 1.40×. The 128-bit accumulator + 8-byte fast path beats the v7.4 4-byte path even when the 8-byte fast path almost never fires.

2. **At corpus density 0.4 %, the prototype saves 1.35 ns/call** (4.96 → 3.61). With ~25 M `read()` calls per DX 2800×2288 entropy decode, that's an estimated **~34 ms DX wall saving** — roughly 11× v7.4's 3 ms ≥-DX-A/B acceptance threshold. Even halving the call-count estimate, ~17 ms saving. The lever is large.

3. **128-bit `read()` shift cost is fully amortised.** The unconditional `(tmp >> count) | (tmpHi << (64 - count))` per-call ops the prototype pays in `read()` are net positive — the 8-byte fast path saves more than the carry-shift costs at every density tested.

4. **The slow-path improvement is structural, not just batch widening.** v7.4 4-byte slow path runs an outer-loop iteration per 4 bytes of FF-bearing data; the prototype's 8-byte slow path halves the outer-loop overhead. That's why even 25 %-density (where the 8-byte fast path P ≈ 10 %, i.e. 90 % slow path) still wins 1.40× over v7.4.

## Parity

3 parity tests, all PASS in release mode:

- `testParity_ProductionVsPrototype_AcrossDensities` — 5 densities × 4 seeds × 4 widths × 200 reads = 16 000 cells
- `testParity_StreamExhaustionPadding` — 9 stream sizes × 4 widths × 10 reads = 360 cells, including empty / sub-batch / boundary-edge cases
- `testParity_HeavyFFEdgeCases` — 5 hand-crafted 0xFF-pattern cases × 4 widths × 8 reads = 160 cells

Every cell produces bit-identical output between v7.4 production and the prototype. The 128-bit accumulator is bit-exact-equivalent to the 64-bit accumulator on the existing `read()` semantics.

## Decision: STRONG GREENLIGHT for Phase 1B

The prototype is correct and clearly faster across all FF densities. Phase 1B integrates the prototype's design into `HTMagSgnDecoderConformant` proper:

1. Add `tmpHi: UInt64 = 0` field to the struct.
2. Modify `read(count:)` to do the 128-bit right shift — the bench confirms this cost is amortised by the refill savings, and on v7.4-disabled paths (where `tmpHi` stays 0) the result is equivalent (just adds `(tmpHi << ...)` ORed into a zero, plus `tmpHi >>= count` on a zero — both are no-ops mathematically).
3. Add `refillBatched8()` method — body identical to the prototype's `refill()`.
4. Add `nonisolated(unsafe) public static var swarRefill8Enabled: Bool = false` static gate (initially default OFF for safety; flipped ON in Phase 3 if DX A/B clears 3 ms).
5. Wire `refill()` to dispatch `swarRefill8Enabled` → `refillBatched8` → `refillBatched` → `refillScalar` in priority order.

Phase 2 will then run a production-callsite microbench + end-to-end DX A/B with the gate enabled, and Phase 3 will flip the default if Δ ≥ 3 ms.

## Reproducing

```bash
swift test -c release --filter 'V8_1_PrefixScanPhase1ABench'
```

All 4 tests run in <1 s. The headline FF-density sweep is printed to stdout.
