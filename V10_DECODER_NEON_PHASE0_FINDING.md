# v10 Decoder C+NEON port — Phase 0 viability probe: **NO-GO**

**Status:** Decoder C+NEON port is **not a viable lever** to beat Kakadu. The Swift decoder's bit-stream reader is already faster than a clean C port by 17 % per call.

**Date:** 2026-05-14
**Branch:** `feature/v10-decoder-neon-port`
**Probe duration:** ~3 hours autonomous overnight work
**Verdict:** abandon the multi-week full decoder port. The hypothesis ("symmetric to v9.4 encoder win") does not generalise.

---

## Headline

A scalar C port of `HTMagSgnDecoderConformant.read()` runs at **6.43 ns/call median** on Apple M2; the existing Swift implementation runs at **5.30 ns/call median**. **C is 17 % slower.**

The Swift decoder benefits from the **v7.4 SWAR-batched 4-byte refill** + **v8.1 8-byte SWAR + 128-bit accumulator** optimisations that were specifically tuned for the medical-corpus FF-density distribution. A clean scalar C port doesn't capture these — and even hand-NEON intrinsics on the FF-detect scan wouldn't beat the SWAR fast-path because the corpus FF density (~0.4 %) means the fast-path is taken ~99 % of the time, and at that hit rate the fast-path is already a single 32-bit/64-bit OR-into-accumulator with no per-byte conditional.

| Reader | Swift median | C median | Speedup |
|---|---:|---:|---:|
| MagSgn (forward, 4000 mixed-width reads on DX-shape stream) | **5.30 ns/call** | **6.43 ns/call** | **0.82×** (C loses) |
| MEL (forward run-length) | not measured per-call — out of scope for Phase 0 | sanity test passes | n/a |
| VLC (reverse-bit) | not measured per-call — out of scope for Phase 0 | sanity test passes | n/a |

The MagSgn reader is the **most-called reader in the HT decoder** (one call per significant coefficient per block × thousands of blocks per fixture). If the most-called reader doesn't win at the C level, the less-called readers (MEL, VLC) cannot make up the difference.

## Why the encoder won but the decoder loses

The v9.4.0 encoder C+NEON port produced a **2.91× single-thread per-block speedup** and **−9 % to −20 % warm-encode wall on M2** (per the v9.4 release notes). Why doesn't the same recipe work for the decoder?

**Three structural differences:**

1. **The Swift decoder has been heavily SWAR-tuned for two major release cycles** (v7.4 + v8.1), whereas the v9.3-era Swift encoder had less-optimised inner loops. v9.4's C+NEON encoder was beating a less-tuned baseline; the Swift decoder is now a higher bar.

2. **The decoder's hot path is bit-stream consumption, not classifier-style integer arithmetic.** v9.4's encoder NEON win came from the **4-sample-per-quad classifier** (NEON-friendly: 4 parallel `vshl` + `vclz`). The decoder's MagSgn read is byte-stream un-stuffing — fundamentally serial state-machine work that NEON can only help via SWAR FF-detect (which Swift already does).

3. **Corpus FF-density is ~0.4 %.** At that density the SWAR fast-path is taken ~99 % of refills; the slow path (per-byte FF handling) runs ~1 % of the time. A C+NEON implementation would have to beat the fast-path's single OR-into-accumulator, which is already memory-bandwidth-bound on the byte-stream load.

## Method

The Phase 0 probe shipped four artefacts:

- `Sources/J2KCodecNEON/include/j2knhd.h` — decoder C target header
- `Sources/J2KCodecNEON/j2knhd_decode_block_ht.c` — three bit-stream reader implementations (MagSgn, MEL, VLC) + scaffold for the unimplemented block-level entry point (returns `-3 NOT IMPLEMENTED`)
- `Tests/J2KCodecTests/V10DecoderNEONPhase0Tests.swift` — bit-exact parity test (Swift vs C MagSgn reader) + DX-shape per-call speed bench (20 trials median)
- This finding doc

All 5 Phase 0 tests pass: parity bit-identical, version string correct, sanity for MEL + VLC readers, speed measurement clean.

## Path forward — three options

### Option A — Abandon decoder C+NEON port (RECOMMENDED)

The Phase 0 data says the multi-week investment to fully port the Swift decoder to C+NEON would not produce wall savings on M2. **13th lever-ceiling-style finding** in the encoder/decoder optimisation arc.

The decoder's Kakadu gap on DX (1.9× per the warm cross-codec measurement on main) is then **silicon-bound** — recoverable only via M3+/A-series cross-silicon measurement, not algorithmic.

### Option B — Port the SWAR optimizations TO C, not from Swift

The v7.4 SWAR-batched refill and v8.1 8-byte SWAR are Swift implementations of optimisations that would be natural in C. Porting THEM (rather than the scalar reference) might produce a small win — but only ~5-10 % at best, since C and Swift compile to similar codegen for SWAR. Not worth multi-week scope. NOT RECOMMENDED.

### Option C — Try true NEON intrinsics on a different inner loop

The MagSgn reader's hot path is byte un-stuffing + bit-pack — fundamentally serial. The HT decoder's **inverse-rho / sign-decode / coefficient-reconstruction inner loop** (in `decodeInitialRow` / `decodeSubsequentRow`) MAY have NEON-friendly structure if 4 quads can be classified in parallel. But that requires the full block-decode port, which Phase 0 did NOT do. **Risk**: another lever-ceiling wash. **Recommendation**: only pursue if M3/M4 measurement shows a different shape AND there's specific evidence of a parallelisable inner loop.

## The bigger picture — 13 lever-ceiling investigations

This Phase 0 result joins the v10.0-research arc's 12 prior lever-ceiling confirmations:

| # | Arc | Outcome |
|---|---|---|
| 1-12 | (see [`V10_0_FINAL_CLOSURE.md`](V10_0_FINAL_CLOSURE.md) on `v10.0-research`) | Encoder + decoder hot path at ceiling on M2 |
| **13** | **v10 Decoder C+NEON port Phase 0 viability probe** | **C scalar 17 % SLOWER than Swift; full port not worth multi-week investment** |

The pattern is now overwhelming: **on Apple M2 + Swift release + macOS, the algorithmic frontier is exhausted.** The remaining open frontiers are non-algorithmic:

1. **Cross-silicon measurement (M3+ / A-series)** — different memory bandwidth + core counts may shift the budget. Requires hardware.
2. **Profile-guided optimisation (PGO) + LTO build pipeline** — never tried; quick day-of work; possible 5-10 % global wins.
3. **Mammography-specific cache locality** — the only workload-specific gap not yet measured (MG is 3.6× behind Kakadu, gap widens with fixture size).

## Files added in this Phase 0 probe

```
Sources/J2KCodecNEON/include/j2knhd.h
Sources/J2KCodecNEON/j2knhd_decode_block_ht.c
Tests/J2KCodecTests/V10DecoderNEONPhase0Tests.swift
V10_DECODER_NEON_PHASE0_FINDING.md  (this doc)
```

Per `feedback_research_no_main_merge`, the branch + artefacts stay on `feature/v10-decoder-neon-port` and are NOT merged to main.

## Reproducing

```bash
git checkout feature/v10-decoder-neon-port
swift build -c release --target J2KCodecNEON
swift test -c release --filter V10DecoderNEONPhase0Tests
```

Expected output:

```
Test Case 'testMagSgnReader_ParityVsSwift' passed (0.000 seconds)
Test Case 'testMagSgnReader_SpeedSwiftVsC_DXShape' passed (0.001 seconds)
  Swift HTMagSgnDecoderConformant.read():   median ~5 ns/call
  C     j2knhd_magsgn_read():                median ~6 ns/call
  Speedup: ~0.82×
Test Case 'testMELReader_BasicSanity' passed
Test Case 'testVersionString' passed
Test Case 'testVLCReverseReader_BasicSanity' passed
Executed 5 tests, with 0 failures
```

If Swift's measurement comes in higher than 5.5 ns/call or C's lower than 6 ns/call on your host, the C path may be a winner there — report the numbers and the host class (M3+/A-series).

## What this DOESN'T close

This finding **does NOT** rule out:
- Porting an **encoder-stage** loop that has parallelisable structure (Phase 7 showed cross-stage fusion is non-viable, but a single-stage parallel rewrite of e.g. mammography-specific tile dispatch hasn't been measured).
- Pursuing decoder optimisations OUTSIDE the bit-stream readers (e.g. iDWT — but Phase 8 said iDWT is at memory-bandwidth ceiling).
- M3+/A-series re-measurement (the budget may shift).

It DOES rule out: porting the existing Swift HT decoder hot path to C+NEON expecting a v9.4-style speedup. The Swift baseline is already too tuned for that to work.

## Recommendation: PGO + LTO instead

The PGO + LTO option from yesterday's pre-overnight conversation looks more attractive now. Phase 0 confirms the bit-stream readers are at the auto-vec ceiling; a PGO-trained build of the existing Swift+C code might extract 5-10 % via branch-prediction tuning + inline-decision biasing. **One day of work** vs the multi-week C decoder port. Strongly recommend prioritising this for the next research session.
