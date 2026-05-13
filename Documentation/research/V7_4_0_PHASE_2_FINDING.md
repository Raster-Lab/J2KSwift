# v7.4 Phase 2 Finding — NEON MagSgn Refill (chained-state batched)

**Captured**: 2026-05-09, Apple M2 (24G624 / Darwin 24.6.0), release builds, median of 5 runs per cell.

This document is the Phase 2 deliverable of the v7.4 staged NEON release. It refactors `HTMagSgnDecoderConformant.refill` into separately-callable scalar and SWAR-batched paths gated by a public flag, adds an exhaustive bit-exact parity gate, and reports honest A/B measurements.

**TL;DR** — the SWAR-batched 4-byte refill **clears the 3 ms acceptance threshold**: DX 2800×2288 in-process decode improves by **3.70 ms (5.9 %)** vs the scalar reference. Per spec, the batched path is now the production default (`HTMagSgnDecoderConformant.neonRefillEnabled = true`).

---

## 1. What Phase 2 unblocked

Per Phase 1's spec rule:

> Do not start chained-state MagSgn refill prefix-scan until reconstruction NEON has landed or been rejected with measurements.

Phase 1 rejected reconstruction NEON for default-on (Δ = 0.90 ms < 3 ms). Phase 2 was unblocked and proceeded with the chained-state refill work.

---

## 2. Implementation approach

The MagSgn unstuff state is inherently chained: byte N's unstuff depends on byte N-1 == 0xFF. A naive SIMD prefix-scan would propagate this across vector lanes — complex, with uncertain payoff.

Phase 2 takes a pragmatic alternative: **detect `0xFF` early and split into a fast common case + scalar fallback**.

For each 4-byte batch:
1. Unaligned 32-bit load (`UnsafeRawPointer.loadUnaligned(as: UInt32.self)`)
2. SWAR `0xFF`-byte detect: `(p32 ^ 0xFFFFFFFF)` makes `0xFF` bytes become zero; standard SWAR zero-byte test `(inv &- 0x01010101) & ~inv & 0x80808080` flags any `0xFF`
3. **Fast path** (no `0xFF` AND no carried unstuff): one OR into the accumulator at the current bit offset, advance 32 bits. No per-byte conditionals.
4. **Slow fallback** (`0xFF` detected or carried unstuff): byte-by-byte scalar handling for the 4 bytes — identical to `refillScalar` semantics.

At the corpus-typical `0xFF` density (~0.4 % of bytes), ~99 % of batches hit the fast path. The slow path is bit-exact-by-construction since it IS the scalar code.

---

## 3. Bit-exact parity (11/11 sweeps pass)

`V740NeonRefillParityTests` exhaustively compares scalar vs batched output across:

| sweep | what it covers | result |
|---|---|:-:|
| `testParity_AllZero` | 64 zero bytes — fast-path-only | ✓ |
| `testParity_AllFF` | 64 × `0xFF` — slow-path-only with maximum unstuff | ✓ |
| `testParity_AlternatingFF00` | `FF, 00, FF, 00, …` — every other byte forces a slow batch | ✓ |
| `testParity_AlternatingFFAA` | `FF, AA, …` — high-bit unstuff exercised + masking | ✓ |
| `testParity_FFAtEachPositionInBatch` | `0xFF` at position 0/1/2/3 of every 4-byte batch — covers SWAR detect for each lane | ✓ |
| `testParity_RandomSweep32Seeds` | 32 random seeds × 256-byte streams × 60 mixed-width reads | ✓ |
| `testParity_StreamExhaustPadding` | 8 bytes + 200 reads × 7 bits → 0xFF padding fills the rest | ✓ |
| `testParity_StreamExhaustPaddingFromFFEnd` | stream ending in `0xFF` then padding — carried unstuff across boundary | ✓ |
| `testParity_EmptyStream` | 0 bytes → all 0xFF padding | ✓ |
| `testParity_OneByteStreams` | 1-byte streams across `{0x00, 0x7F, 0x80, 0xAA, 0xFE, 0xFF}` × 5 reads each | ✓ |
| `testParity_ThreeByteStreamUnderBatchSize` | 3 bytes (< 4-byte batch size) — exercises the scalar tail | ✓ |

The fast-path's correctness invariant: when neither `anyFF` nor carried `unstuff` holds, EVERY one of the 4 bytes contributes `8` bits with no masking, so the lane-parallel result is byte-identical to the scalar loop's output.

---

## 4. Microbench — scalar vs batched per-call cost

`V740NeonRefillMicrobench.testRefill_ScalarVsBatched_PerWidth` (Apple M2, release, median of 5):

| width | scalar ns/call | batched ns/call | batched Δ | speedup |
|---|---:|---:|---:|---:|
| 3 bits (sparse) | 3.54 | 3.38 | -4.5 % | 1.05× |
| 7 bits (typical VLC cwd) | 3.90 | 3.80 | -2.6 % | 1.03× |
| **14 bits (DX corpus avg)** | **5.70** | **4.96** | **-13.0 %** | **1.15×** |
| 32 bits (max width) | 10.09 | 6.77 | -33.0 % | 1.49× |

The wider the read, the more refill iterations are triggered, the more the batched path's 4-bytes-at-once amortisation pays off. At the DX corpus average of ~14 bits per `magsgn.read(count:)` call, the per-call cost drops 13 %.

---

## 5. DX in-process wall — the acceptance gate

`V740NeonRefillDXWallBenchmark.testDXInProcessWall_ScalarVsBatchedRefill` (median of 5):

| path | DX 2800×2288 in-process decode |
|---|---:|
| Scalar refill | **62.76 ms** |
| Batched refill | **59.06 ms** |
| Δ | **3.70 ms (-5.9 %)** ✓ |

**Clears the 3 ms threshold.** Per spec, default flipped to `true`.

---

## 6. Effect on the v7.4 trajectory

| stage | DX in-process decode |
|---|---:|
| v7.3.0 release | 54.34 ms (baseline) |
| v7.4 Phase 1 default flip (NEON reconstruction → scalar) | 55.24 ms (+0.90 ms regression, accepted per spec) |
| v7.4 Phase 2 (this PR, batched refill default ON) | **51.54 ms** (estimated: 55.24 − 3.70) |

(The 51.54 ms estimate combines Phase 1's measured Δ from v7.3.0 plus Phase 2's measured Δ from the post-Phase-1 baseline. Final number should be measured on the merged v7.4 main; deferred to v7.4.0 release-prep.)

If the 51.5 ms estimate holds, Kakadu gap on DX in-process tightens **2.17× → 2.06×** vs v7.3.0.

---

## 7. What's next

Per the spec's staged-NEON design, Phase 2's success unblocks further v7.4 work. Possible Phase 3 candidates:

- **VLC reverse reader's refill** has the same chained `0x8F`-unstuff structure as MagSgn. The same SWAR fast-path pattern should apply — different stuff-bit constant but same algorithmic shape.
- **Re-evaluate Phase 1 reconstruction NEON** now that refill is faster: the relative cost share of reconstruction may have shifted enough to revisit the default.

Both require fresh A/B measurements per the v7.4 acceptance discipline.

---

## 8. Reproduction

```bash
# Build
swift build -c release --product j2k

# Mandatory gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix (12/12 bit-exact)
swift test -c release --filter HTTileParityMatrixTests

# v7.4 NEON refill parity gate (11/11 must pass)
swift test -c release --filter V740NeonRefillParityTests

# v7.4 NEON refill microbench
swift test -c release --filter testRefill_ScalarVsBatched_PerWidth

# v7.4 NEON refill DX in-process A/B
swift test -c release --filter testDXInProcessWall_ScalarVsBatchedRefill
```
