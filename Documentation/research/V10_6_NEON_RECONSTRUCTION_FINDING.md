# v10.6-research — C+NEON HT reconstruction SIMD port

**Date**: 2026-05-19
**Branch**: `v10.6-research`
**Status**: **CLOSED — WASH (11th lever-ceiling confirmation on M2 + Swift release)**
**Code**: opt-in via `J2K_NEON_HT_RECONSTRUCT_SIMD=1` (default OFF)

---

## TL;DR

User asked "what is the next work, plan and start working, and we need to
beat Kakadu in all". Honest reality check: on M2 + Swift release, beating
Kakadu in all means closing 19-35 % wall gaps on MG / DX / PX — far
beyond what single levers have delivered in 10+ prior investigations.
The most credible remaining lever in the codec hot path is HT entropy
decode body redesign (memory tags it "multi-week, high risk").

Picked the targeted sub-lever within that scope: **port the Swift
`readQuadSamplesSIMD` reconstruction path to the C+NEON HT decoder**.
Memory `project_v7_4_0_shipped.md` says the Swift SIMD reconstruction
saved 2.5-4.5 ms (median 2.96 ms) on DX in v8 Phase 4. The C+NEON path
(default-on since v10.0.0 D1.5-D) ships with the scalar reconstruction
loop — a known TODO per the source comment ("the SIMD variant is a
future retrofit gated on Phase D1.5-C wall measurement").

**Result**: built the SIMD path (NEON intrinsics, lane-parallel
mask/v_n/coef build), parity-clean across 32+ fixture/seed combos —
but the per-block microbench shows **SIMD is 2-8 % SLOWER than scalar**
on every density tested. Clang's auto-vectorizer is already optimising
the scalar `for (int i = 0; i < 4; i++)` loop better than my hand-written
NEON intrinsics. The explicit `vld1q_u32` / `vst1q_u32` ceremony around
4 already-vectorizable arithmetic ops costs more than the parallelism
saves.

**11th independent lever-ceiling confirmation** on M2 + Swift release.
Pattern: v6-alpha4, v7.4-7.5, v8.1, v8.4-8.7, v10.1, v10.4, v10.5
(column-block + GPU IDWT fused), v10.6.

Code stays in tree as **opt-in via `J2K_NEON_HT_RECONSTRUCT_SIMD=1`**:
bit-exact across 32+ parity combos, available for diagnostic A/B and
cross-silicon re-measurement (Clang's auto-vectorizer behaviour may
shift on different ARM cores / different Clang versions).

---

## What landed

**C kernel** (`Sources/J2KCodecNEON/j2knhd_decode_block_ht.c`):
- `read_quad_samples_scalar` — the existing scalar path, renamed and
  preserved as the reference for parity comparison.
- `read_quad_samples_simd` — NEW: NEON-intrinsic lane-parallel
  reconstruction (mask = (1 << m) - 1, v_n = (payload & mask) |
  (e1 << m) | 1, coef = (v_n + 2) << (p-1), conditional sign-or).
  MagSgn reads stay serial (bit stream is sequential per quad). The
  per-lane conditional stores at the end match the scalar bounds /
  rho gate exactly.
- `read_quad_samples` — dispatcher that selects between scalar and
  SIMD based on `state->reconstruct_use_simd`.

**Function signature** (`include/j2knhd.h`): `j2knhd_decode_block_ht32`
gains a `bool reconstruct_use_simd` parameter (between `magsgn_use_swar4`
and `coefs_out`). All four existing call sites updated.

**Swift gate** (`Sources/J2KCodec/J2KHTConformantBlockDecoder.swift`):
- `HTBlockDecoderConformantNEON.reconstructionSIMDEnabled` — default
  OFF, env opt-in via `J2K_NEON_HT_RECONSTRUCT_SIMD=1`.
- `decodeViaNEONHotPath` reads the flag and forwards to
  `j2knhd_decode_block_ht32`.

**Tests** (`Tests/J2KCodecTests/V10_6_*`):
- `V10_6_NEONReconstructionParityTests` — 3 test methods, 11 + 6 + 32 =
  49 (fixture, seed) combinations across small / density / random sweep.
  **3/3 PASS** bit-exact vs scalar reference.
- `V10_6_NEONReconstructionMicrobench` — block-decode A/B across 4
  density buckets at 64×64.

---

## Microbench result

`V10_6_NEONReconstructionMicrobench` (M2 release, 1000 blocks per
density × 5 iterations = 5000 timed samples per corpus):

| Corpus | scalar med ns | SIMD med ns | speedup | Δ ns/block |
|---|---:|---:|---:|---:|
| 64×64 density 0.05 | 10083 | 10250 | **0.98×** | +167 |
| 64×64 density 0.25 | 17333 | 18375 | **0.94×** | +1042 |
| 64×64 density 0.50 | 21583 | 23500 | **0.92×** | +1917 |
| 64×64 density 0.80 | 19458 | 21083 | **0.92×** | +1625 |

**SIMD is 2-8 % slower across every density**. The trend is consistent:
denser blocks (more significant samples → more reconstruction work)
see *larger* absolute regressions, exactly opposite to what the
parallelism-saves-arithmetic theory predicts.

---

## Why the SIMD lever is wash in C (but not in Swift)

The Swift `readQuadSamplesSIMD` saved 2.5-4.5 ms on DX in v8 Phase 4
per `project_v7_4_0_shipped.md`. Same algorithm; opposite result in C.
The cause is the difference in optimiser maturity:

- **Swift compiler** (Swift 6.2 on Apple's swift toolchain): less
  aggressive auto-vectorization of small loops on Int32 lanes. The
  hand-written `SIMD4<UInt32>` ops compile to native NEON Q-register
  arithmetic; the scalar path stays scalar. The 4-way parallelism is
  a real win.
- **Clang** (Apple's clang for `-O3` C builds): already auto-vectorizes
  the scalar `for (int i = 0; i < 4; i++)` loop body. With 4 iterations
  and uniform bit-field extraction + arithmetic, this is exactly the
  pattern Clang targets best. The hand-written NEON intrinsics add
  `vld1q_u32` + `vst1q_u32` ceremony around an already-vectorized
  arithmetic core.

Net: the SIMD lever's win comes from **outperforming the optimiser**,
which is platform-dependent. In Swift it works; in C-with-Clang it
doesn't.

This pattern matters for future work: don't assume Swift-side SIMD
wins transfer to the C path. Each language's optimiser has different
strengths.

---

## Decision

**Default OFF, opt-in via `J2K_NEON_HT_RECONSTRUCT_SIMD=1`.** The lever
is preserved opt-in for:

- diagnostic A/B (the flag flips paths cleanly with bit-exact output)
- cross-silicon / cross-compiler re-measurement (different ARM cores /
  different Clang versions may shift the auto-vectorization picture)
- future investigation if a clearer per-block ns/coef breakdown
  identifies a sub-lever inside the reconstruction body (e.g.,
  batched MagSgn unpack at quad granularity)

**Not landing on `main`**: production routing unchanged.

---

## Strategic implication for "beat Kakadu in all on M2"

After 11 confirmations of structural lever ceiling on M2 + Swift
release, the credible paths to closing the residual gap remain:

1. **Cross-silicon (M3/M4/A-series) validation** — M4 already wins on
   most fixtures per `CROSS_HOST_M2_M4_v10_1_0_inproc.md`. The
   marketable claim per `feedback_apple_only_v8.md` already supports
   "fastest on Apple Silicon" using M4 numbers.
2. **j2kd daemon adoption** (deployment, not codec). Closes CLI gap
   to ~1.5×.
3. **Product-level wins** — DICOM fast-path, true ROI / partial-
   resolution decode, batch-pipeline optimisations. These are feature
   work, not codec hot-path tuning, and can move wall numbers without
   touching the structural floor.
4. **Multi-week architectural redesign** of HT entropy block decode —
   not pointwise loop optimisation (this arc's scope), but algorithmic
   change (e.g., GPU HT entropy with batched dispatch across all
   blocks of a tile in one shader run — Apple Silicon UMA could
   amortise differently from v7.5's prior per-block GPU attempt).

The 11 prior confirmations all targeted pointwise levers. The next
real probe needs to be at the architecture level.

---

## Files modified / added

- `Sources/J2KCodecNEON/include/j2knhd.h` — `j2knhd_decode_block_ht32`
  gains `reconstruct_use_simd` parameter
- `Sources/J2KCodecNEON/j2knhd_decode_block_ht.c` — `read_quad_samples_scalar`,
  `read_quad_samples_simd`, dispatcher, state-struct field, signature
- `Sources/J2KCodec/J2KHTConformantBlockDecoder.swift` —
  `HTBlockDecoderConformantNEON.reconstructionSIMDEnabled` opt-in,
  `decodeViaNEONHotPath` passes the flag
- `Tests/J2KCodecTests/V10_2_DecodeBlockParityTests.swift` — call
  site signature update
- `Tests/J2KCodecTests/V10_2_DecodeBlockCMicrobench.swift` — 3 call
  site signature updates
- `Tests/J2KCodecTests/V10_6_NEONReconstructionParityTests.swift` (new)
- `Tests/J2KCodecTests/V10_6_NEONReconstructionMicrobench.swift` (new)
- `Documentation/research/V10_6_NEON_RECONSTRUCTION_FINDING.md` (this file)
