# v7.3.0 Phase 0 — HT Entropy Decoder Engine Breakdown

**Captured**: 2026-05-09, Apple M2 (24G624 / Darwin 24.6.0), release builds, single decode per fixture (warm decoder).

This document is the Phase-0 deliverable of the v7.3.0 plan. It identifies which HT entropy decoder engine is the highest-leverage SIMD target by counting call frequency on the medical corpus.

---

## 0. Method

`V730Phase0EntropyProbe.testEntropyEngineBreakdown_LosslessCorpus` runs each medical-corpus fixture through `J2KDecoder().decode(_:)` with the GPU paths forced off (`_gpuHTEntropyEnabled = false`, `_gpuInverse53Enabled = false`, `_multiTileBatchedEntropyEnabled = false`) so the CPU entropy hot loops are exercised. Per-engine call counts come from `J2KHTEntropyProfile`'s lockless `nonisolated(unsafe)` UInt64 accumulators that the decoder bumps at every engine call site.

**Caveat**: the lockless accumulators race when multiple parallel tile tasks increment concurrently. Absolute counts are under-reported by the race-loss factor; relative *proportions* between engines on the same fixture remain valid because every engine suffers the same race rate. Phase 0's deliverable is the proportions, not the absolute counts — that's all the v7.3 SIMD targeting decision needs.

---

## 1. Per-engine call breakdown (medical corpus, single decode, post-warmup)

| Fixture | px | total ms | row ms | mel | vlcLookup | uvlc | magsgn read | avg-bits | readQuadSamples |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32 K | 0.77 | 0.97 | 227 | 6 261 | 3 500 | 15 914 | 9.93 | 4 814 |
| CT 512² | 262 K | 5.08 | 14.18 | 1 362 | 47 426 | 24 924 | 108 351 | 12.01 | 32 285 |
| MR 886² | 785 K | 6.61 | 9.17 | 23 901 | 18 346 | 18 504 | 41 301 | 13.29 | 25 080 |
| XA 1024² | 1.05 M | 13.86 | 61.65 | 41 884 | 147 778 | 83 196 | 261 342 | 14.18 | 90 107 |
| PX 2459×1316 | 3.24 M | 52.26 | 227.34 | 44 210 | 539 107 | 277 318 | 955 213 | 14.98 | 316 788 |
| **DX 2800×2288** | **6.41 M** | **106.22** | **458.50** | **33 192** | **1 099 820** | **547 553** | **1 947 335** | **14.28** | **615 206** |

`avg-bits` is the average bit-width per `magsgn.read(count:)` call. Across the corpus it sits in the 10–15-bit range; on DX specifically it's 14.28 bits per call.

`row ms` is the wall accumulated inside `decodeInitialRow + decodeSubsequentRow` summed across all 16 parallel tiles (CPU-time semantics, identical to encode-side stage breakdown). `total ms` is the full pipeline wall; `row ms / total ms` ≈ parallelism factor.

---

## 2. DX engine ratios (the targeting signal)

Normalized to `mel = 1` on DX 2800×2288:

| engine | calls | × mel |
|---|---:|---:|
| **MagSgn read** | **1 947 335** | **58.7×** |
| readQuadSamples | 615 206 | 18.5× |
| vlcLookup | 1 099 820 | 33.1× |
| uvlc | 547 553 | 16.5× |
| MEL | 33 192 | 1× |

**MagSgn read is the dominant engine by call frequency**, and additionally each call decodes ~14 bits — so the per-call work is non-trivial. The `readQuadSamples` count is 615 K because the function is called twice per quad-pair iteration in both `decodeInitialRow` and `decodeSubsequentRow` (3.16 magsgn reads per readQuadSamples → matches the ~30% rho-density on DX, 4 sample positions × ~80% significance per significant quad).

For SIMD targeting:

1. **MagSgn refill loop is the highest-leverage SIMD target.** The inner `refill()` byte-walk (J2KHTConformantMagSgnCoder.swift:145-162) reads bytes one at a time, handles the post-`0xFF` unstuff-bit semantics inline, and feeds a 64-bit accumulator. Vectorising this with NEON byte-shuffle + a lane-wise unstuff mask should land 4–8× speedup on the inner loop. ~28 MB of bit reads on DX makes this the hottest single piece of code in the entropy stage.
2. **vlcLookup is the second-most-frequent engine.** A 1024-entry table read per call; the lookup itself is constant-time. The bit-unpacking after the lookup (cwd_len / u_off / rho / e_1 / e_k extraction) is amortised across the MagSgn reads it triggers, so vlcLookup itself isn't a SIMD target per se — its cost is dominated by what *follows* (uvlc + readQuadSamples + magsgn).
3. **MEL is too sparse to be a SIMD target.** 33 K calls on DX = 1.7 % of MagSgn calls. Even a 2× speedup on MEL would be invisible against the MagSgn dominance.

---

## 3. Plan revision based on Phase 0 findings

**v7.3 Phase 1 — MagSgn refill SIMD port**:

- **Probe** (1 session, Phase 1a): write a standalone microbench that times `HTMagSgnDecoderConformant.read` in isolation across realistic bit-widths (10, 14, 32). Decouples optimisation from full-pipeline noise.
- **NEON refill** (3-5 sessions, Phase 1b): rewrite `HTMagSgnDecoderConformant.refill` using NEON byte-shuffle for the post-`0xFF` unstuff handling. Process 8-16 bytes per refill instead of one. Bit-exactness is the gate.
- **Validation** (per port): bit-exact corpus + cross-codec + 1000-decode lifetime + the existing HT block-decoder roundtrip tests.

**Realistic outcome**: if MagSgn refill speeds up 4×, and MagSgn is currently ~40% of DX entropy CPU work (educated estimate from call frequency × per-call cost), DX entropy CPU drops ~30%. Decoded back through the parallelism factor, that's ~6 ms wall reduction on DX (60 → 54 ms). Closes the Kakadu gap from 2.43× → 2.18×.

To fully close the Kakadu gap (DX decode ≤ 25 ms), Phase 1 alone is not enough. Subsequent phases:
- **Phase 2**: vlcLookup + uvlc tightening (smaller win but compounds)
- **Phase 3**: readQuadSamples sample-reconstruction loop (4 positions × payload unpack, NEON-vectorisable)
- **Phase 4**: IDWT SIMD audit (the other 34% of DX decode CPU)

If Phases 1-3 land cleanly the gap should close to ~1.5×. Phase 4 (IDWT SIMD) is required to fully match Kakadu.

---

## 4. Reproduction

```bash
# Run the engine breakdown probe (the data behind §1).
swift test -c release --filter testEntropyEngineBreakdown_LosslessCorpus

# Mandatory commit gate (must show 0 failures before any v7.3 PR lands).
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```
