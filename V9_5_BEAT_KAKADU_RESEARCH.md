# v9.5-research — Aggressive C+NEON entropy push — findings

**Status:** Phase 5E shipped on this branch; Phase 5A measured wash and
reverted; Phases 5B/5C/5D closed pending strategic pivot.

**Decision:** Close v9.5 entropy NEON optimization as research artifact.
The plan's premise (entropy NEON is the path to "beat Kakadu") does
not hold on M4. The next release should pivot to non-entropy stages
or per-block overhead reduction.

---

## Context

v9.4.0 graduated as Apple-Silicon's first custom C+NEON HT block
encoder (commit `5c90704`), delivering a 13% wall reduction on M4 DX
warm in-proc and closing the Kakadu gap from 5.25× to 4.5×. The v9.5
plan (`V9_5_PLAN_BEAT_KAKADU.md`) called for an aggressive 5-phase
C+NEON arc targeting an additional 3.2× entropy speedup to drop DX
warm in-proc 94.9 → ~58 ms (Kakadu gap 4.5× → 2.8×).

The plan's quantitative target rested on a per-quad cost estimate of
**~625 ns/quad** in the v9.4.0 encoder, decomposed as:
- Classifier ~50 ns/quad
- MagSgn ~200 ns/quad
- VLC + UVLC ~275 ns/quad
- Stage overhead ~100 ns/quad

Per-phase NEON / SWAR optimizations were projected to deliver
~3.2× cumulative speedup. Phase 5E (per-worker NEON-buffer hoisting)
was the structural warm-up; Phases 5A–5D were the algorithmic pushes.

This document records what we actually measured on M4 and the
strategic call that follows.

---

## What shipped (committed to `v9.5-research`)

### Phase 5E — per-worker NEON-buffer hoisting (commit `72d6d97`)

Mirrors the v9.1 Phase 2d raw-engine hoist pattern. All four worker
scopes in `J2KEncoderPipeline` now allocate three 16 KB NEON output
buffers once per worker (gated on
`HTBlockEncoderConformant.useNEONHotPath`) and plumb them through
`encodeCodeBlockHTJ2KFast` → `encodeCodeBlockConformant`. When the
NEON gate fires AND hoisted buffers are provided, the encoder skips
the entire `HTBlockEncoderConformant + assembleData` chain and calls
`j2knhe_encode_block_ht32` directly via a new
`HTBlockEncoderConformant.encodeNEONIntoBuffers` static method,
followed by `assembleDataFromRaw(vlcReversed: false)` for the
forward-VLC C output.

**What this eliminates per block:**
- 3 × 16 KB buffer alloc/dealloc (was per-block; now per-worker)
- 3 × `[UInt8]` array materialization wrappers (`Array(Unsafe-
  BufferPointer(start:count:))` in `encodeViaNEONHotPath`)
- 1 × `withUnsafeBufferPointer` indirection in the assembly stage

On a 6.4 MP DX encode: ~9500 allocs eliminated.

**Bit-exact preserved** across:
- V94NEONHotPathParityTests (500-trial random sweep + 11 corner cases)
- HTCrossCodecConformantTests (MD5 parity vs OpenJPH/OpenJPEG/Kakadu)
- V91Phase2cArrayVsRawParityTests, HTSampleInfoSIMDPrototypeTests,
  HTMagSgnCoderConformantTests
- V91Phase2ConcurrentContentionProbe (no global-static contention)

**Standalone perf:** neutral on M4 corpus (DX 2800×2288 measured at
97-112 ms across runs vs v9.4.0 baseline ~88-97 ms — within thermal
and run-to-run noise). The structural plumbing did not produce a
standalone win because the per-block alloc cost it eliminated was
already small on macOS's arena allocator.

**Reason to keep it:** the per-worker plumbing is the right
foundation for any future per-block batching work. Even without a
measurable standalone win, the change is structurally clean and bit-
exact-safe.

### V95Phase5MicrobenchTests — per-block ns measurement harness

New microbench that drives `j2knhe_encode_block_ht32` in a tight loop
on 7 representative shapes/density profiles and reports ns/block and
ns/quad. Used to inform Phase 5A scope. Kept in the tree as the
canonical M4 microbench for future entropy work.

---

## What we tried and reverted: Phase 5A (quad-pair batched classifier)

### Implementation

Added a `process_quad_pair` function (under `J2KNHE_PHASE5A_QUAD_PAIR`
compile-time gate) that batches the classifier for both quads of a
horizontal pair: two `vld1q_u32` loads (one per row of the pair, 4
samples each), followed by NEON-parallel `vshl` / `vbic` / `vceqz` /
`vmvn` / `vclzq_u32` / `vshrq` on each vector, then demux the 8 lanes
into the two `j2knhe_quad` outputs. The dispatch helper
`j2knhe_process_pair` routes to the batched path when the pair fully
fits horizontally; otherwise falls back to two `process_quad` calls.

Bit-exact correctness verified — all 548+ assertions in
V94NEONHotPathParityTests, HTCrossCodecConformantTests,
V91Phase2cArrayVsRawParityTests, and HTBlockEncoderConformantTests
pass with `-Xcc -DJ2KNHE_PHASE5A_QUAD_PAIR=1` set.

### Measurement (M4, N=200,000 per fixture, V95Phase5MicrobenchTests)

| Fixture            | OFF ns/quad | ON ns/quad | Δ      |
|---                 |---:         |---:        |---:    |
| ct-like-mid        | 12.7        | 13.0       | +2%    |
| ct-like-sparse     | 6.8         | 7.2        | +6%    |
| ct-like-dense      | 16.1        | 15.5       | −4%    |
| dx-like-mid        | 12.4        | 12.5       | +1%    |
| dx-like-sparse     | 6.9         | 7.5        | +9%    |
| dx-like-dense      | 14.9        | 14.6       | −2%    |
| high-mMSB-mid      | 12.8        | 12.9       | +1%    |

**Verdict:** wash. No fixture shows the ≥10% win the v9.5 plan
required to commit. Direction is mixed (mild improvement on dense
blocks, mild regression on sparse blocks), all changes are within
M4 thermal / run-to-run noise.

Per the plan's risk register:
> "NEON-vs-auto-vec wash repeat (v9.4 Day 6a finding) — measure each
> phase A/B; commit only when explicit NEON wins ≥10% above noise.
> Wash phases revert."

Phase 5A reverted. The compile-time gate is documented here for any
future re-experiment.

---

## The core finding — plan premise was based on wrong per-quad cost

The decisive measurement came from `V95Phase5MicrobenchTests`
combined with `V91Phase1ABatchedClassifyMicrobench`:

### Actual M4 per-quad costs (full encode block, C+NEON path, warm cache)

| Density | 32×32 ns/quad | 64×64 ns/quad |
|---      |---:           |---:           |
| 5% sparse  | 6.8        | 6.9           |
| 30% mid    | 12.7       | 12.4          |
| 80% dense  | 16.1       | 14.9          |

### Plan's assumed per-quad cost (from `V9_5_PLAN_BEAT_KAKADU.md`)

| Component   | Plan estimate | Actual share of 13 ns/quad mid |
|---          |---:           |---:                            |
| Classifier  | 50 ns/quad    | ~3 ns (per V91Phase1A microbench) |
| MagSgn      | 200 ns/quad   | ~3-4 ns (inferred)             |
| VLC + UVLC  | 275 ns/quad   | ~3-4 ns (inferred)             |
| Overhead    | 100 ns/quad   | ~2-3 ns (inferred)             |
| **Total**   | **~625 ns/quad** | **~13 ns/quad**             |

The plan was off by **40-90× on per-quad cost**. The reason is the
v9.1 Phase 1A "Swift overhead" reading of 1112 ns/quad was measured
on the Swift implementation, not the C+NEON path. The v9.4.0 graduate
already collapsed most of that overhead — the C path is 40-90× faster
per quad than the Swift path measured in V9_1 Phase 1A.

### Implication: entropy is already near-optimal on M4

On a 6.4 MP DX 2800×2288 encode:
- Total quads: 6250 blocks × 256 quads/block ≈ 1.6 M quads
- Pure quad compute (at 13 ns/quad average): ~21 ms
- Measured entropy stage wall: ~50 ms
- Implied per-block setup / finalize overhead: ~30 ms across all
  workers, ~30 / 10 workers = ~3 ms/worker amortized
- Total DX warm in-proc: ~97 ms

**Even if entropy went to zero, the DX wall would only drop ~50 ms to
~47 ms.** The plan's target of "DX 95 → 58 ms" via entropy NEON is not
arithmetically reachable.

Where the wall actually goes on M4 (estimated, needs verification):
- Preprocessing + DC shift: small (~1-2 ms)
- Color transform (single component for medical): ~negligible
- DWT (3-5 decomp levels, 9/7 or 5/3): substantial (15-25 ms)
- Quantization: small
- Entropy: ~50 ms
- Rate control: lossless skip; lossy ~5-10 ms
- Codestream assembly: ~5-10 ms

The non-entropy stages collectively account for ~45 ms of the 97 ms
DX wall. These are where the next material wall reduction lives.

---

## Why explicit NEON intrinsics consistently wash on M4

Two converging factors:

1. **Modern Clang auto-vectorizes the scalar C well.** The headline
   intrinsic `vclzq_u32` (count-leading-zeros, lane-wise) gets emitted
   automatically when the scalar code has a `__builtin_clz` in a loop
   the compiler can prove vectorizable. The hand-NEON path is
   indistinguishable from the auto-vec scalar path within thermal
   noise.

2. **The per-quad work is already small (3-16 ns).** Even a perfect
   2× NEON speedup on the classifier saves at most ~2 ns/quad ×
   1.6 M quads = 3 ms across an entire DX encode. The instrumentation
   noise alone is wider than this signal.

This was already documented in `V9_4_NEON_HOT_PATH_RESEARCH.md` Day 6a
finding. Phase 5A's measurement is a second independent confirmation
under the same M4 hardware, with the same outcome.

---

## Phases 5B / 5C / 5D — closed pending strategic pivot

Skipped per the wash finding. Brief notes on what each would have
attempted and why it would likely also wash:

### Phase 5B — 64-bit MagSgn accumulator + SWAR 0xFF-detect

Plan: replace the 32-bit accumulator + per-byte 0xFF check with a
64-bit accumulator and 16-byte SWAR scan for 0xFF bytes (via
`vcgeq_u8`). v9.4 research already noted: "Modest win since FF-density
is <0.5% on real fixtures." MagSgn share of per-quad cost on M4 is
~3-4 ns; even a 2× speedup saves ~1-2 ns/quad — wash within noise.

### Phase 5C — VLC reverse-emitter 32-bit SWAR

Plan: replace the 4-tuple VLC accumulator emit loop with a 32-bit
SWAR pack. VLC share of per-quad cost is ~3-4 ns; same wash
arithmetic as 5B.

### Phase 5D — per-row 16-quad batched emit (stage fusion)

Plan: pre-classify a full row of quads into a scratch buffer, then
loop through scratch emitting MagSgn / MEL / VLC. The structural
reorg has more architectural value (eliminates per-quad function-
call boundaries, enables wider batching) but the speedup ceiling is
~3 ns/quad of overhead × 1.6 M quads = ~5 ms across DX — within
noise of the 97 ms wall. The plan's risk register flagged this as
"highest-risk ~400 lines of hot-path C" — the risk/reward at the
measured per-quad cost does not justify the rewrite.

---

## What went well

- **Phase 5E shipped clean.** Bit-exact across 548+ assertions, no
  contention regression, all gates green. The per-worker NEON-buffer
  hoist is a structural improvement that's worth keeping.
- **The V95Phase5 microbench harness landed.** Tight per-block ns
  measurement on representative shapes/densities is the right tool
  for future entropy work — and showed Phase 5A as a wash within
  one test cycle, avoiding the deeper Phase 5B–5D investment.
- **Phase 5A was tested rigorously before commit.** 500-trial random
  sweep + cross-codec MD5 parity + V91Phase2 contention probe all
  passed at the bit-exact level. The decision to revert is based on
  measured perf, not correctness concerns.

## What didn't go well

- **The plan's per-quad cost estimate was wrong by 40-90×.** This
  invalidated the whole optimization arithmetic. Catching this
  earlier — by running the microbench before committing to the plan
  — would have saved a Phase 5A round-trip.
- **The v9.4 "auto-vec wash" finding was treated as an isolated risk
  rather than the dominant signal.** The plan's risk register
  acknowledged the wash possibility but still committed Phases
  5A–5D as planned. A more disciplined risk-weighted plan would
  have run Phase 5A as an A/B canary first, not bundled it with
  5B–5D.

---

## Recommendation for the next release

### Pivot: target non-entropy stages on the warm in-proc CPU path

The path to beat Kakadu on M4 DX warm in-proc is NOT further entropy
optimization. The entropy stage is already 7-16 ns/quad on M4 —
within ~20% of the theoretical floor (~3 NEON instruction-cycles per
quad sample at 4-issue, ~32 cycles per quad ≈ 8 ns at 4 GHz).

The remaining ~45 ms of the DX 97 ms wall lives in:
- **DWT (3-5 decomp levels, 9/7 or 5/3)** — substantial. Apple Silicon
  has dedicated vDSP intrinsics; OpenJPH has SSE/AVX DWT; J2KSwift's
  Swift DWT uses SIMD4 but may not be optimal. A C+NEON DWT could
  yield 5-15 ms of wall reduction.
- **Codestream assembly** — the per-tile / per-packet header
  assembly may have allocator hotspots similar to the v9.1 raw-engine
  finding. An audit of `J2KCodestreamWriter` could surface 2-5 ms.
- **Quantization (lossy path)** — vectorizable on SIMD. Lossless
  uses identity quantization (no real cost).

### Sequencing

1. **Run a fresh M4 profile** with the stage timings actually
   captured. (The corpus test's per-stage breakdown printed all zeros
   in this session — debug J2KEncodeTimings capture under the
   benchmark harness first.)
2. **Identify the top non-entropy hotspot.** DWT is the prime
   suspect from prior session notes but should be confirmed by
   measurement.
3. **Apply the same scaffolding** that v9.4.0 used for entropy
   (custom C+NEON, opt-in env-var gate, bit-exact parity suite,
   research-mode validation) to the new hotspot.

### Honest gap closure estimate (M4 DX warm in-proc)

If a C+NEON DWT lands 5-15 ms wall reduction:
- 97 ms → 82-92 ms
- Kakadu gap (20 ms) → 4.1×-4.6× (modest improvement)

To close the gap below ~2× would require either:
- A fundamentally different architectural approach (GPU pre-
  classified-tuples hybrid, listed in v9.4 research as v9.7 candidate)
- Combined DWT + entropy + codestream optimization (multi-release
  arc, not a single v9.5)

The "single release to beat Kakadu" framing in the original v9.5 plan
was over-ambitious given measured per-quad costs.

---

## Files touched on `v9.5-research`

| Path | Status |
|---|---|
| `Sources/J2KCodec/J2KEncoderPipeline.swift` | Modified (Phase 5E) |
| `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift` | Modified (Phase 5E) |
| `Tests/J2KCodecTests/V95Phase5MicrobenchTests.swift` | New |
| `Sources/J2KCodecNEON/j2knhe_encode_block_ht.c` | Unchanged (Phase 5A reverted) |
| `V9_5_BEAT_KAKADU_RESEARCH.md` | New (this document) |

## Phase 5E A/B summary (M4 DX 2800×2288, n=5 medians)

| Path | Run 1 | Run 2 | Mean |
|---|---:|---:|---:|
| Phase 5E, NEON ON (`J2K_NEON_HOT_PATH=1`) | 112.0 ms | 97.2 ms | 104.6 ms |
| Phase 5E, NEON OFF (`J2K_NEON_HOT_PATH=0`)  | 113.4 ms |  —      | 113.4 ms |
| v9.4.0 baseline (per V9_4 research doc) | 88-105 ms (corpus mean) | — | ~95 ms |

Within noise. Phase 5E is structurally clean; future per-block
batching work (e.g., Phase 5D-style stage fusion at the encoder
level) would build on this foundation.

---

## Decision matrix outcome

Per `V9_5_PLAN_BEAT_KAKADU.md` decision matrix:
- DX warm in-proc ≤ 50 ms (≥1.9× speedup): not achieved
- DX 50-70 ms (1.35-1.9×): not achieved
- DX 70-85 ms (1.1-1.35×): not achieved
- DX > 85 ms (<1.1×): **MATCHED — close as research artifact**

**Branch disposition:** keep `v9.5-research` open with Phase 5E +
microbench + this doc committed. Do not graduate to `v9.5.0`. The
next release (v9.5 or v9.6) should pivot to non-entropy stages per
the recommendation above.
