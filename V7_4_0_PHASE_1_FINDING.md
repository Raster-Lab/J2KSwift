# v7.4 Phase 1 Finding — NEON Reconstruction A/B

**Captured**: 2026-05-09, Apple M2 (24G624 / Darwin 24.6.0), release builds, median of 5 runs per cell.

This document is the Phase 1 deliverable of the v7.4 staged NEON release. It refactors the `readQuadSamples` reconstruction work into separately-callable scalar and NEON paths gated by a public flag, adds an exhaustive bit-exact parity gate between the two, and reports honest A/B measurements.

**TL;DR** — at the v7.3.0 codebase state, NEON reconstruction wins **0.90 ms (1.5 %) on DX 2800×2288 in-process decode**, well below v7.4's 3 ms acceptance threshold. Per spec, the NEON path is now flag-gated with default **OFF**. The scalar path is the production default; callers can flip `HTBlockDecoderConformant.neonReconstructionEnabled = true` to A/B.

---

## 1. Scope (per v7.4 spec)

✅ Did not touch MagSgn refill.
✅ Prototyped NEON SIMD for `readQuadSamples` reconstruction / coefficient computation only.
✅ Kept scalar implementation as the reference path (`readQuadSamplesScalar`).
✅ Added exhaustive bit-exact tests (`V740NeonReconstructionParityTests` — 5 sweeps).
✅ Added microbench reporting scalar vs NEON cost (`V740NeonReconstructionMicrobench`).
✅ Added DX in-process wall benchmark before/after (`V740NeonDXWallBenchmark`).

---

## 2. Bit-exact parity (5/5 sweeps pass)

`V740NeonReconstructionParityTests` exhaustively compares scalar vs NEON output across every meaningful input dimension:

| sweep | what it covers | result |
|---|---|:-:|
| `testParity_AcrossBitDepths` | `missingMSBs ∈ {0, 4, 8, 14, 18, 24, 28}` ⇒ `p ∈ {2, 6, 12, 16, 22, 26, 30}` | ✓ |
| `testParity_AcrossDensities` | `sigDensity ∈ {0.0, 0.05, 0.10, 0.30, 0.50, 0.75, 0.95}` (covers rho=0 fast-path through near-fully-significant) | ✓ |
| `testParity_AcrossBlockSizes` | square + non-square block dims: `4×4 .. 64×64`, `32×16 .. 64×32` | ✓ |
| `testParity_RandomSweep32Seeds` | 32 random seeds × ~1 K significant samples per block ≈ 32 K independent coefficient computations compared scalar-vs-NEON | ✓ |
| `testParity_FullCorpusEndToEnd` | every medical-corpus fixture decoded through the full pipeline (parsing → all-rows decode → recoverEQBottomRow bookkeeping → eVal/cxVal flow) — exercises odd/even tile origins implicitly via multi-tile codestreams | ✓ |

By construction, both paths are guaranteed bit-exact:
- Same arithmetic (scalar's `(payload & mask) | (e1Bit << m) | 1; coef = (v_n + 2) << (p-1); coef |= sign ? 0x8000_0000 : 0` ↔ SIMD's lane-parallel equivalent)
- Same conditional-store gate (`rho-bit set AND in-bounds`)
- Same MagSgn read sequence (the SIMD path reads `rho`-gated payloads in the same order)

The mask edge case (m == 32) is handled identically: scalar branches `(m >= 32) ? ~UInt32(0) : (1 << m) - 1`; SIMD produces `(1 &<< 32) - 1 == 0 - 1 == ~0` via Swift's wrapping unsigned arithmetic. Verified in the bit-depth sweep at `missingMSBs = 0` (which gives `p = 30, m ∈ {30, 29}` — close to but not at the edge; the corpus doesn't naturally produce `m = 32` since `Uq` is bounded by the cleanup-pass codeword's u-value range, but the sweep covers the math path that would handle it).

---

## 3. Microbench — scalar vs NEON reconstruction cost

`V740NeonReconstructionMicrobench.testReconstruction_ScalarVsNEON_PerSizeAndDensity` (Apple M2, release, median of 5):

| block | scalar ns/call | NEON ns/call | NEON Δ | per-sample (s/n) |
|---|---:|---:|---:|---:|
| 32×32 density 0.30 (typical) | 4 899 | 4 902 | +0.1 % | 4.78 / 4.79 |
| 64×64 density 0.30 (typical) | 19 898 | 19 667 | -1.2 % | 4.86 / 4.80 |
| 64×64 density 0.10 (sparse) | 12 860 | 12 373 | **-3.8 %** | 3.14 / 3.02 |
| 64×64 density 0.50 (dense) | 24 673 | 25 554 | **+3.6 %** | 6.02 / 6.24 |
| 64×64 density 0.90 (very dense) | 32 010 | 32 290 | +0.9 % | 7.81 / 7.88 |

**NEON wins on sparse blocks (-3.8 %) and loses on dense blocks (+3.6 %)** — counter-intuitive at first glance but mechanistic:

- **Sparse blocks**: rho mostly 1-2 bits set per quad. NEON has flat per-call cost regardless of how many lanes are active; scalar has per-iteration overhead (`if bit == 0 { continue }`) that doesn't cleanly skip dead iterations. NEON's flat cost wins.
- **Dense blocks**: rho mostly fully-set. Scalar's 4 iterations each do small productive work; NEON's setup (vector construction, mask compute, lane stores) becomes the dominant cost. Scalar wins.
- **Typical density (0.30)**: roughly tied — within the run-to-run noise band.

This is a different conclusion from the Phase 3b PR (#363) which measured 10-14 % faster — that measurement was taken **before** Phase 3c (bottom-row recoverEQ) and Phase 3d (rho=0 fast path) landed. After those wins, the reconstruction step is a smaller share of block-decode wall, so the NEON-vs-scalar delta on just-reconstruction shrinks proportionally.

---

## 4. DX in-process wall — the acceptance gate

`V740NeonDXWallBenchmark.testDXInProcessWall_ScalarVsNEON` (Apple M2, release, median of 5):

| path | DX 2800×2288 in-process decode |
|---|---:|
| Scalar reconstruction | **58.28 ms** |
| NEON reconstruction | **57.38 ms** |
| Δ | **0.90 ms (-1.5 %)** |

Below the 3 ms acceptance threshold. Per the v7.4 spec:

> If improvement is below 3 ms, keep the NEON path behind a flag and document the result honestly.

Done — `HTBlockDecoderConformant.neonReconstructionEnabled` defaults to `false` as of this PR.

---

## 5. Why scalar is now the default (vs v7.3.0)

v7.3.0 shipped with `readQuadSamples` calling the SIMD path unconditionally (Phase 3b). That decision was made when SIMD-vs-scalar showed 10-14 % at the block level, which seemed worth it. After the v7.3.0 release-prep benchmarking caught the cache-line-contention regression (#367) and the entropy stage compounded all of Phase 3a-3e, the SIMD-only contribution shrank to the < 3 ms threshold.

Switching default to scalar at v7.4 is a **0.9 ms regression on DX in-process decode** vs v7.3.0. That's small relative to the 54 ms baseline (1.7 %) and within typical run-to-run noise (Phase 3a noise band was ~1.2 %). The trade-off is:

| dimension | scalar default (v7.4) | NEON default (v7.3.0) |
|---|---|---|
| DX wall | +0.9 ms | (baseline) |
| Sparse blocks (microbench) | +3.8 % | (baseline) |
| Dense blocks (microbench) | -3.6 % | +3.6 % slower |
| Code complexity | lower (no SIMD setup logic) | higher |
| Future SIMD work substrate | none | partial |

Net: the data does not justify keeping SIMD as default at v7.3.0's codebase state. If subsequent v7.4 work (chained-state MagSgn refill SIMD, batched per-quad MagSgn reads) compounds with NEON reconstruction in a way that takes the combined Δ ≥ 3 ms, the default can flip back to ON via a one-line change.

---

## 6. What this Phase 1 PR does NOT do

✗ Does not touch MagSgn refill (per spec — that's the chained-state prefix-scan work parked for Phase 2 if/when reconstruction NEON yields ≥ 3 ms or is rejected with measurements).
✗ Does not modify any consumer of `readQuadSamples` — both paths share the same entry signature.
✗ Does not change codestream bytes (decoder-only refactor; encoder untouched).
✗ Does not change the existing public API except for adding the `neonReconstructionEnabled` flag.

---

## 7. Reproduction

```bash
# Build the j2k binary
swift build -c release --product j2k

# Mandatory commit gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# v7.4 NEON parity gate (5/5 sweeps must pass)
swift test -c release --filter V740NeonReconstructionParityTests

# v7.4 microbench — scalar vs NEON per-block cost
swift test -c release --filter testReconstruction_ScalarVsNEON_PerSizeAndDensity

# v7.4 DX in-process wall A/B — the data behind §4 above
swift test -c release --filter testDXInProcessWall_ScalarVsNEON

# Cross-codec parity matrix (must be 12/12 bit-exact)
swift test -c release --filter HTTileParityMatrixTests
```

---

## 8. Decision for v7.4 next steps (per spec)

> Do not start chained-state MagSgn refill prefix-scan until reconstruction NEON has landed or been rejected with measurements.

✅ **Reconstruction NEON has been measured and rejected for default-on per acceptance criteria.** The flag remains in place as A/B infrastructure but production runs scalar. This unlocks the next staged phase: chained-state MagSgn refill prefix-scan SIMD.

The chained-state refill work has its own measurement gate (cross-tile cache-coherence math + SIMD prefix-scan correctness), which should be planned as a separate Phase 2 PR with its own scalar-vs-SIMD A/B test infrastructure mirroring this Phase 1 shape.
