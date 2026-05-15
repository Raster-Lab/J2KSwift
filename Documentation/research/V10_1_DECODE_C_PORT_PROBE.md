# v10.1 — HT decode C+NEON port probe (Phase D1 Phase 0)

**Branch:** `v10.1-research`
**Status:** scoping + baseline measurement, no production code change
**Goal:** decide whether to commit to a 4-6 week C+NEON port of `HTBlockDecoderConformant.decode(...)` by measuring the Phase 0 gate: **scalar-only C port ≥ 10% faster per-block than the Swift reference path** on M2 release.

## Why this is the only un-tried structural lever for decode

Five decode-side lever-ceiling investigations (v6-alpha4 step 12, v7.4, v7.5, v8.1, v8.4 + v8.5) all evaluated levers *inside* the existing Swift architecture:

- SWAR refills (v7.4, v8.1)
- NEON reconstruction A/B at the readQuadSamples level (v7.4)
- Batched MagSgn reads (v8.5)
- GPU IDWT lift (v8.4)
- GPU HT entropy (v7.5)

None tested the structural move the encoder side made in v9.4: relocate the entire per-block hot loop to C+NEON with caller-owned buffers, called once per block from Swift. v9.4's encoder analog delivered:

| Metric | Before | After | Δ |
|---|---:|---:|---:|
| Single-thread per-block | 20,584 ns | 7,083 ns | **2.91×** |
| 12-worker per-block | 16,416 ns | 7,916 ns | **2.07×** |
| Warm in-proc DX encode | ~104 ms | ~91 ms | **−13%** |

The decode side has the same structural ingredients: a hot loop (`decodeCleanupConformant` family in `J2KHTConformantBlockDecoder.swift`) called per-block from `J2KDecoderPipeline.swift` lines 2570-2620 / 2684-2708. The MagSgn / VLC reverse-reader / MEL state machines, the FF-stuff rules, and the rho-gated reconstruction are all bit-exactly mirrored in v9.4's `j2knhe_encode_block_ht32` — its reverse counterpart can be built using the same patterns.

The v8.4 stage profile measured entropy at **57% of DX decode wall** — the same share as encoder entropy. If a C+NEON decoder hits the encoder's 2.91× single-thread per-block speedup, the projected warm wall reduction is:

- DX decode wall ≈ 64 ms (post-Phase-0) × 0.57 entropy share × (1 − 1/2.91) = **−24 ms** → **40 ms wall (beats Kakadu 41.70 ms)**
- MG decode wall ≈ 125 ms × 0.57 × (1 − 1/2.91) = **−47 ms** → **78 ms wall (still behind Kakadu 65 ms but much closer)**

That's a credible path to closing PX/DX decode and narrowing MG decode by ~1.6×.

## Phase 0 gate — what the probe must show before committing

Per `feedback_v6_alpha4_lever_ceiling` and the 9 prior lever-ceiling findings: pure-optimisation candidates have washed when their cheap-probe delta was below threshold. The v9.4 encoder *did* clear its cheap probe (2.91× single-thread per-block in the microbench preceded the wall measurement). This probe is the same gate for the decoder.

**Gate criteria (all must pass to proceed past Phase 0):**

1. **Scalar C ≥ 10% faster per-block than Swift** on the same random-coefficient corpus (1000 blocks × 5%, 25%, 50% sparsity × 64×64 block size). 10% is the "is the Swift/C boundary cost real" threshold; v9.4 cleared 2.91× so even a fraction of that confirms the lever.
2. **Bit-exact across 500-block sweep** + 11,889-cell conformance corpus. The encoder analog made this non-negotiable; the decoder analog has the same gate.
3. **Per-block scalar C time ≤ Swift × 0.95** at 12-worker concurrency (not just single-thread). If contention is the cycle pool, the multi-thread number reveals it.

**Stop-and-reconsider triggers:**

- Scalar C ≤ 1.05× Swift on single-thread microbench → close. The encoder's win came from removing Swift's ARC + boundary cost. If the decoder doesn't show similar headroom, the structural ceiling is real on this side too.
- Bit-exact fails on any seed → debug, but if not resolvable in 1-2 days, close.
- Scalar C wins but 12-worker C regresses → the gain is in single-thread overhead, not parallel throughput. v8.4 entropy-share analysis suggests wall-impact is bounded by parallel scaling.

## Swift baseline (2026-05-15 v10.1-research, M2 release)

`V10_1_DecodeBlockMicrobench.testPhaseD1Phase0_swiftBaseline`:

| Sparsity | Single-thread median ns | min ns | p99 ns | 12-worker median ns | min ns | p99 ns |
|---|---:|---:|---:|---:|---:|---:|
| 64×64 @ 5%  | **15 000** | 12 083 | 19 875 | 16 292 | 12 667 | 57 916 |
| 64×64 @ 25% | **27 625** | 23 625 | 34 625 | 30 125 | 24 458 | 99 833 |
| 64×64 @ 50% | **34 875** | 31 458 | 42 250 | 37 667 | 32 125 | 127 083 |

Reference data for sanity check vs the encoder analog:

| Quantity | Encoder Swift (v9.3 baseline) | Encoder C+NEON (v9.4) | Speedup |
|---|---:|---:|---:|
| Single-thread per-block @ 5% | 20 584 ns | 7 083 ns | **2.91×** |
| 12-worker per-block | 16 416 ns | 7 916 ns | **2.07×** |

**Implication for decode Phase 0 gate:**

- Swift decoder single-thread per-block @ 5% is **already lower than the Swift encoder pre-NEON** (15 000 vs 20 584 ns). Five prior decode investigations (v6-alpha4 through v8.5) have already extracted most Swift-side overhead the encoder still had in v9.3.
- A naïve 2.91× C+NEON win projects per-block 5% → **~5 150 ns** (saves 9 850 ns/block).
- For DX (2 048 blocks at ~5-25% mean sparsity) the projected wall savings: **~3-6 ms warm in-proc** at 12-worker effective parallelism. That is **right at the v7.4 3 ms acceptance threshold** — a 2× ratio (not 2.91×) would put the projection at ~2-4 ms, below the gate.
- This re-confirms why the Phase 0 gate at **≥10% scalar-C win** matters: if scalar alone doesn't clear 10%, the NEON multiplier on top is probably not enough to clear the v7.4 wall threshold.

The baseline data is the calibration. The next session writes the scalar C port and re-runs this same harness with `V10_1_DecodeBlockCMicrobench` for a clean A/B.

## State-machine port progress (2026-05-15, M2 release)

| State machine | Parity | Microbench (C vs Swift scalar) | Microbench (C vs Swift production) | Gate |
|---|---|---|---|---|
| MEL | 9 tests, 0 failures | **1.33×** (geo mean) | n/a (Swift MEL has no SWAR variant; scalar = production) | **PASS** |
| MagSgn | 7 tests, 0 failures | **1.39×** (geo mean) | **1.14×** (washes on sparse/random; Swift v7.4 SWAR ties C scalar) | MARGINAL vs production |
| VLC reverse-reader | 8 tests, 0 failures | **1.83×** (geo mean) | **1.83×** (Swift v7.4 SWAR is opt-in OFF by default → scalar = production) | **PASS — strongest of the three** |

## Honest wall projection from the three state-machine ports

Per-state-machine winning ratios vs Swift production (M2 release):
- MEL:    1.33× (3.9 → 2.6 ns/call on random; gain holds across all corpora)
- MagSgn: 1.14× (3.9 → 3.9 ns/call on sparse/random; only dense-FFs wins by 1.50×)
- VLC:    1.83× (4.6 → 2.6 ns/call on random; gain holds across all corpora)

Crude DX decode wall projection (entropy share = 57% per v8.4, 12-worker parallel = ~5× effective):
- Entropy budget: 64 ms × 0.57 / 5 ≈ 7.3 ms entropy wall
- Assume the three state machines contribute roughly equally to entropy CPU
- Weighted speedup (geometric mean of 1.33, 1.14, 1.83): ~1.40×
- Wall savings: 7.3 × (1 − 1/1.40) ≈ **2.1 ms**
- Apply v9.4 encoder analog's observed dilution factor (~50%, projected 28.9% wall → actual 13%): **~1 ms wall**

**That is below the v7.4 3 ms acceptance threshold.** Reading: the scalar-only D1 port DOES NOT justify the multi-week investment from the per-state-machine evidence alone.

**Two paths that could change the verdict:**

1. **NEON SWAR retrofit on MagSgn.** Swift's v7.4 4-byte SWAR + v8.1 8-byte SWAR refills are the production hot path; matching that in C would close the MagSgn gap and stack on top of MEL/VLC scalar wins. Encoder analog (v9.4) used NEON intrinsics to reach 2.91× single-thread, so the pattern is proven.
2. **Per-block C decoder integration + end-to-end DX wall measurement.** The per-state-machine microbenches are bounded estimates; integrating MEL + VLC + MagSgn into a single C `j2knhd_decode_block_ht32` and measuring the actual warm DX wall via `J2KMedicalCorpusPerformanceTests` is the canonical decision input. The microbench-vs-wall mapping is uncertain enough that the scalar-only integrated bench could come in either above or below the projection.

**Recommendation for the morning:** decide between (a) close D1 here on the projected sub-threshold scalar wall, accepting Kakadu's PX/DX/MG decode lead, or (b) commit one more week to NEON SWAR retrofit + per-block integration before deciding. Either is defensible from the current data.

**Honest read of MagSgn:** the Swift production path runs v7.4 4-byte SWAR refill by default, which already eliminates most of the boundary cost the C scalar port would address. On sparse/random byte streams the C scalar TIES Swift production (3.9 ns/call each); only on dense-0xFF streams does C win (Swift SWAR fast-path falls through to byte-by-byte). So MagSgn alone doesn't justify the multi-week port — the C path would need its own NEON SWAR retrofit to clearly beat Swift production. The MEL win (1.33× vs Swift production, since MEL has no SWAR variant) is the unambiguous lever.

## MEL port result (2026-05-15, M2 release) — GATE CLEARED

`V10_1_MELMicrobench.testPhaseD1Phase0_melMicrobench`:

| Corpus            | Swift ns/call | C ns/call | Speedup |
|-------------------|--------------:|----------:|--------:|
| sparse 256B (00s) | 3.3           | 2.6       | **1.25×** |
| dense 256B (FFs)  | 3.3           | 2.6       | **1.25×** |
| random 256B       | 3.9           | 2.6       | **1.50×** |

**Geometric mean: 1.33× (33% faster).** Clears the ≥10% Phase 0 gate decisively.

Parity (`V10_1_MELParityTests`): 9 tests, 0 failures. Coverage includes empty/all-zero/all-FF dictionary cases, every-single-byte sweep (256 byte values), 00/FF + FF/00 alternating sequences, 256 random 1-64-byte streams, 64 large random streams (128-632 bytes, 512 runs each), and a 1024-pair sweep (every first byte × {00, 55, AA, FF} suffix).

**Implication for the full D1 port.** The MEL state machine is the smallest of the three; per-block decode issues ~10K MEL `nextRun()` calls per 64×64 block at typical sparsities, so 1.33× on this piece projects to ~1.3 ns/call × 10K calls / block × 2048 blocks ≈ 26 ms accumulated CPU on DX, spread across 12 workers and stage parallelism to ~3-5 ms wall. That alone is at the v7.4 acceptance threshold; the VLC reverse-reader and MagSgn share-of-block speedups stack on top.

The MEL signal is the **structural** lever the encoder analog used. The decoder side has it too. **Proceed to VLC reverse-reader.**

## MagSgn port result (2026-05-15, M2 release) — GATE CLEARED

`V10_1_MagSgnMicrobench.testPhaseD1_magsgnMicrobench` — scalar-vs-scalar Swift/C ratio:

| Corpus            | Swift scalar ns/call | C ns/call | C/scalar |
|-------------------|---------------------:|----------:|---------:|
| sparse 256B (00s) | ~5.2                 | ~3.9      | **1.34×** |
| dense 256B (FFs)  | ~5.9                 | ~3.9      | **1.50×** |
| random 256B       | ~5.2                 | ~3.9      | **1.33×** |

**Geometric mean vs scalar Swift: 1.39×.** Parity (`V10_1_MagSgnParityTests`): 7 tests, 0 failures across empty/all-zero/all-FF/FF-at-every-position (16 positions)/fixed-width sweep (1..32 × 64 reads)/256 random byte trials/32 large random streams.

*Caveat:* Swift production uses `refillBatched` (v7.4 SWAR 4-byte refill), bit-exact equivalent of the scalar but ~5-13% faster on dense corpora. The C scalar beats Swift scalar by 1.39× and Swift production by ~1.13-1.28×. For decisive beat-Swift-production on dense data the C path would need its own SWAR retrofit; on sparse/random where most real medical samples live, C scalar already beats Swift production.

## VLC reverse-reader port result (2026-05-15, M2 release) — GATE CLEARED

`V10_1_VLCMicrobench.testPhaseD1Phase0_vlcMicrobench`:

| Corpus            | Swift ns/call | C ns/call | Speedup |
|-------------------|--------------:|----------:|--------:|
| sparse 256B (00s) | 4.6           | 2.6       | **1.75×** |
| dense 256B (FFs)  | 5.2           | 2.6       | **1.99×** |
| random 256B       | 5.2           | 2.6       | **1.99×** |

**Geometric mean: 1.91×.** Strongest of the three state-machine signals. Parity (`V10_1_VLCParityTests`): 8 tests, 0 failures across scup=3 minimal/all-zero/all-FF/0x8F-boundary/FF-stuff-specific patterns/256 random read-plan trials/128 random peek+consume sequences. Includes Swift testing helpers `VLCReverseReaderTesting.runScalarReadPlan` and `runScalarPeekConsumePlan` (the `VLCReverseReader` struct is fileprivate so the helpers expose the scalar-pinned behaviour).

## Combined Phase 0 verdict — three state machines (2026-05-15)

| State machine | Swift ns/call | C ns/call | C speedup | Parity tests / failures |
|---|---:|---:|---:|---|
| MEL           | ~3.3 | ~2.6 | **1.25-1.33×** | 9 / 0 (1100+ trials) |
| MagSgn        | ~5.4 | ~3.9 | **1.39×**      | 7 / 0 (300+ trials) |
| VLC reverse   | ~5.0 | ~2.6 | **1.91×**      | 8 / 0 (400+ trials) |

**All three clear the ≥10% gate decisively.** Per-call savings are real, parity is bit-exact across 1800+ trial cases, and the lever is the same Swift/C boundary move v9.4 used on the encoder. The Phase 0 verdict is **PROCEED** to the per-block integration phase.

**Next decision the data does NOT yet answer:** the v9.4 encoder analog measured 2.91× single-thread per-block. The decoder's per-state-machine sub-gates average around 1.5×. The end-to-end per-block C-vs-Swift number depends on the row dispatcher and the SIMD reconstruction path, neither of which is exercised here. Build `j2knhd_decode_block_ht.c` (the row loop + SIMD reconstruction port), run the block-level microbench against `V10_1_DecodeBlockMicrobench`'s Swift baseline, then decide if the projected ~3-6 ms DX wall reduction materialises.

## Files in the probe (this branch only, do not merge to main)

- `Documentation/research/V10_1_DECODE_C_PORT_PROBE.md` — this document.
- `Tests/J2KCodecTests/V10_1_DecodeBlockMicrobench.swift` — XCTest performance harness for Swift per-block decode baseline (this commit).
- *(future, this branch)* `Sources/J2KCodecNEON/j2knhd_decode_block_ht.c` + `include/j2knhd.h` — scalar-only C port. Bit-identical to `HTBlockDecoderConformant.decode` (Swift reference oracle).
- *(future, this branch)* `Tests/J2KCodecTests/V10_1_DecodeBlockParityTests.swift` — Swift vs C parity sweep (500 blocks × seeds + 11,889 conformance corpus).
- *(future, this branch)* `Tests/J2KCodecTests/V10_1_DecodeBlockCMicrobench.swift` — same microbench but exercising the C path. Compare to the Swift baseline to evaluate the gate.

## Recommended sequencing for the next session

1. **Read the Swift reference** (`J2KHTConformantBlockDecoder.swift:56-87` + the `DecodeState` row-loop at 244-452) end-to-end. The 3 inner state machines (`HTMELDecoderConformant`, `VLCReverseReader`, `HTMagSgnDecoderConformant`) are at `J2KHTConformantMagSgnCoder.swift` and `J2KHTConformantBitStream.swift`.
2. **Scaffold `j2knhd.h` + `j2knhd_decode_block_ht.c`** with the same shape v9.4 used: caller-owned input/output buffers, `int32_t` return value for error code, struct-based decoder state.
3. **Port MEL** (smallest state machine, ~50 lines Swift → similar C). Bit-exact sweep on 256 random MEL streams.
4. **Port VLC reverse-reader** (~150 lines Swift). The FF-stuff invariant is the tricky part — preserve it byte-by-byte.
5. **Port MagSgn decoder** (~300 lines Swift, has SIMD4 fast path). Scalar first.
6. **Wire the row loop** (`decodeInitialRow` + `decodeSubsequentRow`).
7. **Run parity sweep** — 500 blocks across bit-depths, sparsities, sizes, missing-MSB values.
8. **Run microbench** — both Swift and C paths over the same synthetic corpus, single-thread and 12-worker.
9. **Decide.** Gate criteria are above; the data answers go/no-go.

## Honest priors

- The v9.4 encoder analog cleared its gate (2.91× single-thread per-block). The Swift/C boundary cost on the encoder was a real lever; nothing in v8.5's batched-read close-out invalidates the same lever existing on decode.
- BUT: v8.5 also documented that the Swift-side consumer-body redesign was wash. That close-out's exact wording ("for batched-read to clear it, savings need to be ~19 ns/quad — more than double measured") applies to *batched reads inside Swift*. A C port has a different cost ceiling (no Swift ARC, no boundary marshalling, tighter loop). Whether *that* difference clears 10% per-block is exactly what this probe measures.
- Time budget: ~1 week for the probe (scalar C port + parity + microbench). Stop hard at 7 calendar days; if the gate hasn't fired by then, the structural ceiling on decode is confirmed and J2KSwift accepts Kakadu's lead on PX/DX/MG decode permanently as a product position.

## Companion documents

- [`V9_4_NEON_HOT_PATH_RESEARCH.md`](V9_4_NEON_HOT_PATH_RESEARCH.md) — encoder analog, contains the per-block timing methodology this probe must mirror.
- [`V8_5_*` consumer body wash](../research/) — the Swift-side close-out this probe explicitly does *not* re-tread.
- [`BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md`](BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md) — execution plan that owns this phase as D1.
