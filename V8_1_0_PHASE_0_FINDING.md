# V8.1.0 Phase 0 — MagSgn refill FF-density characterisation

**Status**: GREENLIGHT — proceed to Phase 1 (prototype NEON 16-byte refill).
**Date**: 2026-05-10
**Branch**: `v8.1-phase-0-prefix-scan-microbench`
**Bench**: [`Tests/J2KCodecTests/V8_1_PrefixScanPhase0Bench.swift`](Tests/J2KCodecTests/V8_1_PrefixScanPhase0Bench.swift)

## Goal

Measurement-first characterisation of the v7.4 SWAR-batched MagSgn refill across a controlled FF-density sweep — the data needed to decide whether v8.1's "bit-parallel prefix-scan on chained-unstuff state" workstream has measurable headroom on Apple M2.

## Method

Apple M2, Swift 6.2 release-mode, median of 5 runs at each cell, 200 000 read iterations per run, 4 MiB synthetic byte stream with controlled 0xFF probability (stuff-bit constraint enforced so streams are valid MagSgn). 14-bit reads (DX corpus average, per v7.4 microbench).

## Headline data — FF-density sweep at 14-bit reads

| target FF % | realised FF % | scalar ns/call | batched ns/call | speedup | batched Δ vs density-0 |
|---|---:|---:|---:|---:|---:|
| 0.0 | 0.000 | 7.18 | **5.17** | **1.39×** | +0.0 % |
| 0.4 (corpus) | 0.396 | 7.18 | **6.29** | **1.14×** | +21.8 % |
| 1.0 | 0.986 | 7.19 | 7.22 | 1.00× | +39.8 % |
| 5.0 | 4.762 | 7.35 | 8.32 | **0.88×** | +61.1 % |
| 10.0 | 9.089 | 7.50 | 9.78 | **0.77×** | +89.3 % |
| 25.0 | 19.993 | 7.92 | 10.44 | **0.76×** | +102.0 % |

Width sweep at corpus density (0.4 %) reproduces the v7.4 microbench shape:

| width | scalar ns | batched ns | speedup |
|---|---:|---:|---:|
| 3 bits  |  4.37 |  4.22 | 1.04× |
| 7 bits  |  4.91 |  4.79 | 1.02× |
| 14 bits |  7.12 |  6.28 | 1.13× |
| 32 bits | 12.44 |  8.34 | 1.49× |

## Findings

1. **Scalar is density-independent** (7.18 → 7.92 ns/call from 0 % to 25 %, ~10 % rise from extra mask-and-shift work). No fast/slow asymmetry — every byte is treated uniformly.

2. **v7.4 batched is highly density-sensitive**. Degrades 102 % from density 0 % to 25 %. The break-even point with scalar is between 0.4 % and 1.0 %. Above 1 %, **batched is slower than scalar**.

3. **The slow path inside `refillBatched` is more expensive than pure scalar** because it does the SWAR FF-detect first, then falls back to byte-by-byte — pure overhead at high density.

4. **Corpus headroom is real**. At 0.4 % density, batched costs 6.29 ns/call vs the fast-path-only floor of 5.17 ns/call — i.e. **1.12 ns/call of slow-path overhead at the medical-corpus operating point**. With ~25 M `read()` calls per DX 2800×2288 entropy decode, that's roughly 28 ms of total slow-path cost on DX. Eliminating any meaningful fraction of it is well above v7.4's 3 ms ≥-DX-A/B acceptance threshold.

## Decision: GREENLIGHT Phase 1

Phase 1 prototypes a **NEON 16-byte refill** with two design pillars:

1. **128-bit accumulator** (`tmp_lo: UInt64` + `tmp_hi: UInt64`). Lets the fast path absorb 16 bytes (= 128 bits) per iteration when no 0xFF is present.

2. **NEON prefix-scan slow path** (instead of the current 4-byte scalar fallback):
   - 1× `vld1q_u8` 16-byte load
   - 1× `vceqq_u8` against 0xFF → 16-byte FF mask
   - Prefix-shift the FF-mask by 1 to get the per-byte u-state (with carried-in unstuff)
   - `vbslq_u8` selects 0x7F (when u-state) vs 0xFF (otherwise) → per-byte mask
   - `vandq_u8(v, mask)` → masked bytes
   - `popcount_prefix(u_state)` → per-byte cumulative-bit-position offset (8·i − popcount)
   - shifted-OR reduction into the 128-bit accumulator

Probability of a clean 16-byte fast path at corpus density 0.4 %: **(1 − 0.004)¹⁶ ≈ 93.8 %** — still dominantly fast-path, with 4× the per-batch throughput.

## Risks / measurement-wash candidates

- **128-bit accumulator overhead in `read()`**. Two-limb shifts on every read may negate the refill win. Mitigation: keep `tmp_lo` as the primary read source, drain `tmp_hi` only when `bits` exceeds 64. Microbench `read()` cost in isolation as part of Phase 1.
- **NEON prefix-scan dispatch overhead**. On 16-byte chunks, the per-batch NEON setup may dominate the saving. Mitigation: Phase 1 prototypes BOTH "16-byte SWAR + scalar slow path" and "16-byte NEON prefix-scan", and we ship whichever wins (or neither if both wash).
- **Corpus FF density may already be optimal**. If real DX block streams cluster heavily at <0.4 %, the slow-path lever is smaller than the synthetic measurement suggests. Mitigation: instrument `refillBatched` in a debug build to log realised slow-path-hit ratio on actual fixtures (Phase 1 task).

## Reproducing

```bash
swift test -c release --filter 'V8_1_PrefixScanPhase0Bench'
```

Both tests run in <1 s. Full table is printed to stdout.
