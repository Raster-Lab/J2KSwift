# v7.4 Phase 3 Finding — SWAR-batched VLC reverse-reader refill (rejected, kept behind flag)

**Captured**: 2026-05-09, Apple M2 (24G624 / Darwin 24.6.0), release builds, median of 5 runs per cell.

This document is the Phase 3 deliverable of the v7.4 staged NEON release. It refactors `VLCReverseReader.refill` (inside `J2KHTConformantBlockDecoder`) into separately-callable scalar and SWAR-batched paths gated by a public flag, adds an exhaustive bit-exact parity gate, runs microbench + DX in-process A/B per the v7.4 acceptance discipline, and reports an honest **rejection**.

**TL;DR** — the SWAR-batched 4-byte VLC refill is bit-exact across 5 sweeps and shows modest 1-10 % per-block speedups in microbench, **but does not produce a robust DX 2800×2288 wall-time improvement.** The 3-run median of the DX A/B ranges between **−0.6 ms and +2.5 ms** (run-to-run noise dominates), well below the **3 ms acceptance threshold**. Per spec, `VLCReverseReaderTesting.batchedRefillEnabled` stays at default `false` (scalar path remains production). The flag and parity gate are landed so future work can toggle and re-measure if the cost share of VLC refill changes (e.g. after further hot-path elimination).

---

## 1. What Phase 3 examined

Phase 2 successfully applied the SWAR-batched approach to `HTMagSgnDecoderConformant.refill` for a **+5.9 % DX win**. The Phase 2 spec note flagged the VLC reverse reader as the natural Phase 3 candidate:

> VLC reverse reader's refill has the same chained `0x8F`-unstuff structure as MagSgn. The same SWAR fast-path pattern should apply — different stuff-bit constant but same algorithmic shape.

Phase 3 implemented exactly that pattern. The rejection comes not from a correctness or implementation problem but from the byte distribution of real VLC streams making the SWAR fast-path fire much less often than MagSgn's.

---

## 2. Implementation approach

The VLC reverse reader is a **reverse-iteration** bit reader: bytes are consumed from `byteIdx` downward into the MEL+VLC slab. The unstuff rule fires when the **previously-consumed** byte was `> 0x8F` AND the current byte's low 7 bits are all 1 (`val & 0x7F == 0x7F`).

The Phase 3 batched path mirrors Phase 2's shape with three differences:

1. **Reverse load** — read 4 bytes at addresses `[byteIdx-3 .. byteIdx]` via `UnsafeRawPointer.loadUnaligned(as: UInt32.self)`, then `.byteSwapped` so lane 0 of the in-register `UInt32` corresponds to `memory[byteIdx]` (the byte the scalar code would consume first).
2. **SWAR detect** — instead of MagSgn's `0xFF` test, test "any byte > `0x8F`". On Apple Silicon, `SIMD4<UInt8>(.>) SIMD4<UInt8>(repeating: 0x8F)` lowers to a single NEON `cmhi.16b` / `cmgt` instruction; `any(gt)` is one compare-and-extract.
3. **Fast path predicate** — `!anyOver8F && !unstuff` ⇒ no byte in the batch can trigger unstuff, AND no carried unstuff state from the previous batch. In that case, **every** one of the 4 bytes contributes 8 unmasked bits to `tmp`, byte-identical to the scalar loop's output.

If the predicate fails, the slow fallback executes 4 scalar iterations (identical to `refillScalar`'s body) and re-checks the loop condition.

A double-offset bug surfaced during testing — `withUnsafeBufferPointer` on an `ArraySlice` returns a pointer at the slice's first element (not the underlying array's index 0), so the original code's `base[bytesStart + byteIdx]` over-indexed. Fixed and documented inline; the parity test caught it on the first run via a `signal 5` (SIGTRAP) on the very first sweep.

---

## 3. Bit-exact parity (5/5 sweeps pass)

Because the VLC reader is `fileprivate`, parity is exercised through the public `HTBlockDecoderConformant.decode` entry point, comparing full coefficient outputs between the scalar and batched flag settings.

| sweep | what it covers | result |
|---|---|:-:|
| `testParity_AcrossBitDepths` | `missingMSBs ∈ {0, 4, 8, 14, 18, 24, 28}` × 32×32 blocks | ✓ |
| `testParity_AcrossDensities` | sigDensity ∈ {0.0, 0.05, 0.10, 0.30, 0.50, 0.75, 0.95} × 64×64 | ✓ |
| `testParity_AcrossBlockSizes` | 9 sizes — 4×4 through 64×64, plus mixed 32×16, 16×32, 64×32, 32×64 | ✓ |
| `testParity_RandomSweep64Seeds` | 64 random seeds × 32×32 blocks at 40 % density | ✓ |
| `testParity_FullCorpusEndToEnd` | encode + decode round-trip over the 6 medical-corpus PGMs (MR-small, CT, MR-large, XA, PX, DX) | ✓ |

Total: **5/5 sweeps pass, all coefficient outputs bit-exact between scalar and batched paths.**

---

## 4. Microbench — per-block decode cost

`V740NeonVlcRefillMicrobench` (Apple M2, release, median of 5):

### By block density (32×32, missingMSBs 14)

| cell | scalar µs/block | batched µs/block | Δ | speedup |
|---|---:|---:|---:|---:|
| sparse (5 %) | 2.70 | 2.69 | −0.3 % | 1.00× |
| typical (30 %) | 5.24 | 5.18 | −1.2 % | 1.01× |
| dense (60 %) | 7.61 | 7.00 | **−8.1 %** | **1.09×** |
| very-dense (90 %) | 8.65 | 8.61 | −0.5 % | 1.00× |

### By block size (30 % density, missingMSBs 14)

| block | scalar µs/block | batched µs/block | Δ | speedup |
|---|---:|---:|---:|---:|
| 16×16 | 1.80 | 1.75 | −2.7 % | 1.03× |
| 32×32 | 5.34 | 5.13 | −4.0 % | 1.04× |
| **64×64** | **24.44** | **22.32** | **−8.7 %** | **1.10×** |
| 32×64 | 10.90 | 10.95 | +0.4 % | 1.00× |

The largest gains (64×64 dense) are ~10 %. Phase 2's MagSgn microbench peaked at 1.49× because MagSgn's 0xFF-detect fast path fires ~99 % of the time on corpus-typical bytes (`0xFF` is 1/256 of value space). VLC's `> 0x8F` fast path fires far less often — bytes > 0x8F occupy 7/16 of the uniform value space, so even on uniform random data the 4-batch hit-rate is `(9/16)⁴ ≈ 10 %`. Real VLC streams skew the distribution somewhat, but not enough to overcome this structural disadvantage.

---

## 5. DX in-process wall — the acceptance gate

`V740NeonVlcRefillDXWallBenchmark.testDXInProcessWall_ScalarVsBatchedVlcRefill` (median of 5, three back-to-back runs):

| run | Scalar VLC refill | Batched VLC refill | Δ |
|---|---:|---:|---:|
| 1 | 56.91 ms | 57.52 ms | **−0.61 ms (−1.1 %)** |
| 2 | 57.31 ms | 57.78 ms | **−0.47 ms (−0.8 %)** |
| 3 | 60.66 ms | 58.15 ms | **+2.51 ms (+4.1 %)** |

Run-to-run variance ≈ 3 ms exceeds any underlying signal. **Below the 3 ms threshold in every run.** Per v7.4 acceptance discipline:

> If improvement is below 3 ms, keep the NEON path behind a flag and document the result honestly.

The flag stays default OFF; scalar refill remains production. Phase 2's MagSgn batched refill (default ON) is unaffected — this measurement was taken with Phase 2's default in place, so the measured delta is the marginal contribution of Phase 3 alone.

---

## 6. Why Phase 3 didn't reproduce Phase 2's win

| dimension | Phase 2 (MagSgn) | Phase 3 (VLC) |
|---|---|---|
| stuff-trigger byte | `0xFF` | `> 0x8F` |
| stuff-byte share of value space | 1/256 (0.4 %) | 7/16 (43.75 %) |
| corpus-typical 0xFF density | ~0.4 % | n/a (different rule) |
| 4-batch fast-path hit-rate (uniform random) | ~99 % | ~10 % |
| DX 2800×2288 in-process wall Δ | **−3.70 ms (5.9 %)** ✓ | **±0–2.5 ms (noise)** ✗ |

The SWAR fast-path's amortisation depends on the predicate firing in nearly every batch. MagSgn's 0xFF detect clears that bar; VLC's `> 0x8F` detect doesn't, because the predicate becomes "**all 4 bytes** must be ≤ 0x8F", which on real entropy streams happens an order of magnitude less often than the equivalent "all 4 bytes ≠ 0xFF" condition.

The slow path is the same per-byte cost as scalar — so when fast-path hit-rate is low, the batched path is effectively scalar code with a SWAR-detect overhead dominating. The microbench captures that overhead being roughly compensated by the rare fast-path wins; the wall benchmark sits inside DX's run-to-run variance.

---

## 7. What lands in this PR

- **Refactor** — `VLCReverseReader.refill` split into `refillScalar` (v7.3 production, untouched semantics) + `refillBatched` (Phase 3 SWAR prototype) + dispatcher.
- **Public flag** — `VLCReverseReaderTesting.batchedRefillEnabled: Bool = false` (default OFF). Test-only toggle for A/B comparison.
- **Parity gate** — `Tests/J2KCodecTests/V740NeonVlcRefillParityTests.swift`, 5 sweeps × {bit-depths, densities, block sizes, 64 random seeds, 6-fixture corpus}, 0 failures.
- **Microbench** — `Tests/J2KCodecTests/V740NeonVlcRefillMicrobench.swift`, per-density and per-block-size A/B reporting per-block µs and speedup.
- **DX wall A/B** — `Tests/J2KCodecTests/V740NeonVlcRefillDXWallBenchmark.swift`, end-to-end 5-run-median DX in-process wall comparison.
- **This finding doc** — captured rejection rationale + measurements + reproduction commands.

What does **not** land:
- Any change to the production VLC refill path (the dispatcher routes to `refillScalar` by default exactly as v7.3.0 did).
- Any change to Phase 2's MagSgn batched refill (still default ON, unaffected).

---

## 8. What's next

Per the v7.4 staged-NEON discipline, Phase 3's rejection ends the "easy" SWAR refill candidates. The remaining v7.4 levers are structurally harder:

- **MEL adaptive run-length decoder** — single-state machine over a single byte stream; not a refill problem. Would need a different optimisation shape.
- **`readQuadSamples` SIMD reconstruction (Phase 1, rejected)** — could be re-evaluated now that MagSgn refill is faster. Phase 1's measured Δ was 0.90 ms; reconstruction's relative cost share has increased modestly with refill faster, but probably not enough to clear the 3 ms gate without an algorithmic change.
- **Full prefix-scan SIMD MagSgn refill** — would propagate the chained `0xFF`-unstuff state across vector lanes via a bit-parallel scan rather than the current "fast common case + scalar fallback" split. Significant complexity for an uncertain incremental win on top of Phase 2's already-shipped 5.9 %.

None of these is the obvious-next-card play. Phase 3's honest rejection means **v7.4 is now content-complete** at Phase 1 (rejected NEON reconstruction, default scalar) + Phase 2 (accepted SWAR MagSgn refill, default ON) + Phase 3 (rejected SWAR VLC refill, default OFF). The branch can be merged as the v7.4.0 release.

The v7.4.0 DX trajectory expectation:

| stage | DX in-process decode |
|---|---:|
| v7.3.0 release (frozen baseline) | 54.34 ms |
| v7.4 Phase 1 (NEON reconstruction → scalar default) | 55.24 ms (+0.90 ms regression accepted per spec) |
| v7.4 Phase 2 (batched MagSgn refill default ON) | ~51.5 ms (estimated; final measure on merged main) |
| v7.4 Phase 3 (this PR, batched VLC refill default OFF) | ~51.5 ms (no change vs Phase 2) |

The net v7.4.0 win over v7.3.0 is **~2.8 ms (5 %)** carried entirely by Phase 2.

---

## 9. Reproduction

```bash
# Build
swift build -c release --product j2k

# Mandatory gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix (12/12 bit-exact)
swift test -c release --filter HTTileParityMatrixTests

# v7.4 Phase 3 VLC refill parity gate (5/5 must pass)
swift test -c release --filter V740NeonVlcRefillParityTests

# v7.4 Phase 3 VLC refill microbench
swift test -c release --filter V740NeonVlcRefillMicrobench

# v7.4 Phase 3 VLC refill DX in-process A/B
swift test -c release --filter V740NeonVlcRefillDXWallBenchmark
```
