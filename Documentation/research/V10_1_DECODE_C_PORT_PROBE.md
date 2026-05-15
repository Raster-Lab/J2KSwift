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
