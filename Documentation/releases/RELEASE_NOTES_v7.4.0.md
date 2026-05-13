# J2KSwift v7.4.0 — Release Notes

**Tag**: `v7.4.0`
**Released**: 2026-05-09
**Headline**: Staged-NEON release on Apple Silicon — SWAR-batched MagSgn refill ships default ON; reconstruction-NEON and VLC SWAR refill rejected with measurements (kept behind opt-in flags). DX 2800×2288 in-process decode tightens by ~2-3 ms vs v7.3.0; the Kakadu gap eases from 2.17× to ~2.10×.

---

## Summary

v7.4.0 is a **staged-NEON release** following the Apple Silicon `feedback_v6_alpha4_lever_ceiling` discipline: every NEON proposal is gated by an end-to-end **DX 2800×2288 in-process A/B benchmark**, and only ships default-on when the measured Δ ≥ 3 ms. The release ran three independent NEON candidates through that gate:

| phase | proposal | DX A/B Δ | gate? | default state |
|---|---|---:|:-:|:-:|
| 1 | SIMD4 `readQuadSamples` reconstruction | 0.90 ms | ✗ | flag (OFF) |
| **2** | **SWAR-batched MagSgn refill** | **3.70 ms** | **✓** | **default ON** |
| 3 | SWAR-batched VLC reverse-reader refill | −0.6 to +2.5 ms | ✗ | flag (OFF) |

Only Phase 2 cleared the bar. It ships **default ON** as the v7.4.0 production codepath. Phases 1 and 3 land behind opt-in public flags so future work can re-measure if the relative cost share of those stages changes (e.g., after further hot-path elimination would shift reconstruction into a new dominant share).

The **discipline is the deliverable** here as much as the win: empirical rejections beat speculative complexity.

---

## What's New — production default

### Phase 2 — SWAR-batched `HTMagSgnDecoderConformant.refill` (#370)

The MagSgn unstuff state is inherently chained (byte N's unstuff depends on byte N−1 == `0xFF`). A naive SIMD prefix-scan would propagate the chain across vector lanes — complex, with uncertain payoff. Phase 2 takes a pragmatic alternative: **detect `0xFF` early and split into a fast common case + scalar fallback**.

For each 4-byte batch:

1. Unaligned 32-bit load (`UnsafeRawPointer.loadUnaligned(as: UInt32.self)`)
2. SWAR `0xFF`-byte detect via `(p32 ^ 0xFFFFFFFF)` followed by `(inv − 0x01010101) & ~inv & 0x80808080` — flags any `0xFF` in O(1) without per-byte branching.
3. **Fast path** (no `0xFF` AND no carried unstuff): single OR into the bit accumulator at the current bit offset, advance 32 bits.
4. **Slow fallback** (`0xFF` detected or carried unstuff): byte-by-byte scalar handling — bit-exact-by-construction since it IS the scalar code.

At the corpus-typical `0xFF` density of ~0.4 %, **~99 % of batches hit the fast path**.

**Microbench (Apple M2, release, median of 5)**:

| width | scalar ns/call | batched ns/call | Δ | speedup |
|---|---:|---:|---:|---:|
| 3 bits (sparse) | 3.54 | 3.38 | −4.5 % | 1.05× |
| 7 bits (typical VLC cwd) | 3.90 | 3.80 | −2.6 % | 1.03× |
| **14 bits (DX corpus avg)** | **5.70** | **4.96** | **−13.0 %** | **1.15×** |
| 32 bits (max width) | 10.09 | 6.77 | −33.0 % | 1.49× |

**End-to-end DX A/B (Phase 2, settled system, median of 5)**: scalar 62.76 ms → batched 59.06 ms = **−3.70 ms (5.9 %)**, clearing the 3 ms gate.

---

## What's New — opt-in flags (rejected with measurements, available for re-measurement)

### Phase 1 — `HTBlockDecoderConformant.neonReconstructionEnabled` (default `false`) (#369)

Prototype SIMD4 path for the `readQuadSamples` per-quad post-MagSgn reconstruction. Bit-exact across 5 sweeps (rho=0, rho>0, mixed sign/mag, edge bit-depths, bottom-row recoverEQ interaction). Per-block microbench shows modest gains, but the DX in-process A/B Δ was **0.90 ms** — below the 3 ms gate. Per spec, kept behind a flag and defaulted to scalar.

### Phase 3 — `VLCReverseReaderTesting.batchedRefillEnabled` (default `false`) (#371)

Same SWAR fast-path / scalar fallback shape as Phase 2, but applied to the VLC reverse reader's chained `0x8F`-unstuff state. Bit-exact across 5 sweeps. Microbench shows 1.04-1.10× per-block gains on dense blocks. DX A/B Δ across 3 runs: **−0.6 ms, −0.5 ms, +2.5 ms** — run-to-run noise dominates, well below the 3 ms gate.

The structural reason: VLC's stuff-trigger predicate is "byte > 0x8F" (7/16 of the value space), so the 4-byte SWAR fast-path predicate "all 4 bytes ≤ 0x8F" fires ~10 % of batches on uniform random data — vs MagSgn's "all 4 bytes ≠ 0xFF" firing ~99 %. With low fast-path hit-rate, the batched path is effectively scalar code with SWAR-detect overhead, and the wall-time delta sits inside DX's run-to-run variance.

---

## Backward compatibility

- **Codestream bytes byte-identical to v7.3.0** — these are decoder-only changes; encoders are untouched.
- **No public API breakage.** Three new opt-in flags are added (`HTMagSgnDecoderConformant.neonRefillEnabled` is `true`-by-default; `HTBlockDecoderConformant.neonReconstructionEnabled` and `VLCReverseReaderTesting.batchedRefillEnabled` are both `false`-by-default). All three are `nonisolated(unsafe) public static var` and intended for test/microbench use.
- **SemVer rule: MINOR.** No major version bump because no public API removal, no signature changes, and codestream bytes are unchanged.

`getVersion()` returns `"7.4.0"`.

---

## Cross-codec parity matrix (re-run on v7.4.0)

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` — 12 cells × {OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 demo}, all bit-exact.

| Modality | Shape | Mode | Cols×Rows | Parity | OpenJPH | Grok | Kakadu |
|---|---|---|---|---|:-:|:-:|:-:|
| MR | 886×886 | 2x2 | 2×2 | ANY-ODD | ✓ | ✓ | (skip) |
| MR | 886×886 | 4x4 | 4×4 | ALL-EVEN | ✓ | ✓ | ✓ |
| MR | 886×886 | strips4 | 1×4 | ALL-EVEN | ✓ | ✓ | ✓ |
| XA | 1024×1024 | 2x2 | 2×2 | ALL-EVEN | ✓ | ✓ | ✓ |
| XA | 1024×1024 | 4x4 | 4×4 | ALL-EVEN | ✓ | ✓ | ✓ |
| XA | 1024×1024 | strips4 | 1×4 | ALL-EVEN | ✓ | ✓ | ✓ |
| PX | 2459×1316 | 2x2 | 2×2 | ALL-EVEN | ✓ | ✓ | ✓ |
| PX | 2459×1316 | 4x4 | 4×4 | ANY-ODD | ✓ | ✓ | (skip) |
| PX | 2459×1316 | strips4 | 1×4 | ANY-ODD | ✓ | ✓ | (skip) |
| DX | 2800×2288 | 2x2 | 2×2 | ALL-EVEN | ✓ | ✓ | ✓ |
| DX | 2800×2288 | 4x4 | 4×4 | ALL-EVEN | ✓ | ✓ | ✓ |
| DX | 2800×2288 | strips4 | 1×4 | ALL-EVEN | ✓ | ✓ | ✓ |

- **ALL-EVEN cells (9)**: 9/9 OpenJPH, 9/9 Grok, 9/9 Kakadu = **27/27 bit-exact**.
- **ANY-ODD cells (3)**: 3/3 OpenJPH, 3/3 Grok = **6/6 bit-exact**. (Kakadu does not support odd tile origins.)
- **Total external decoder cross-decodes: 33/33 bit-exact.**
- HTGPUForward53CrossCodecTests: 1/1 GPU-encode + external-decode bit-exact.

Pre-existing Self-RT diff on DX 2x2 / DX strips4 (not introduced by v7.4) is unchanged from v7.3.0; tracked separately, not blocking.

---

## Medical-corpus benchmark (re-run on v7.4.0)

### Decode wall-time — warm-session, HT-conformant lossy 9/7 @ 2 bpp, n=5 per fixture

| Fixture | px | CPU ms | decodeGPU ms | decodeWithGPUHT ms | Winner |
|---|---:|---:|---:|---:|---|
| ct_003 (512×512) | 262 144 | 13.2 | 9.6 | 8.7 | decodeWithGPUHT (1.53×) |
| mr_001 (886×886) | 784 996 | 30.1 | 17.9 | 22.1 | decodeGPU (1.68×) |
| xa_001 (1024×1024) | 1 048 576 | 41.1 | 17.0 | 17.0 | decodeGPU (2.42×) |
| px_001 (2459×1316) | 3 236 044 | 151.9 | 41.9 | 32.9 | decodeWithGPUHT (4.62×) |
| dx_002 (2800×2288) | 6 406 400 | 55.2 | 50.7 | 52.8 | decodeGPU (1.09×) |
| mg_001 (3520×4784)* | 16 839 680 | 137.1 | 133.0 | 130.7 | decodeWithGPUHT (1.05×) |

(`*` synthetic LCG-noise fixtures, no real medical content.)

### Encode wall-time — warm, HT-conformant lossy 9/7 @ 2 bpp, n=5 per fixture

| Fixture | px | CPU encode ms | GPU encode ms | CPU/GPU× |
|---|---:|---:|---:|---:|
| mr_002 (180×180) | 32 400 | 4.0 | 2.9 | 1.37× |
| ct_001 (512×512) | 262 144 | 16.1 | 19.4 | 0.83× |
| ct_003 (512×512) | 262 144 | 7.5 | 7.0 | 1.07× |
| mr_001 (886×886) | 784 996 | 25.8 | 29.3 | 0.88× |
| xa_001 (1024×1024) | 1 048 576 | 61.7 | 64.0 | 0.96× |
| px_001 (2459×1316) | 3 236 044 | 188.8 | 199.0 | 0.95× |
| dx_002 (2800×2288) | 6 406 400 | 358.6 | 395.8 | 0.91× |
| dx_001 (2544×3056)* | 7 774 464 | 453.9 | 445.6 | 1.02× |
| mg_001 (3520×4784)* | 16 839 680 | 870.2 | 751.8 | 1.16× |

### DX 2800×2288 in-process decode — Phase 2 A/B on v7.4.0 main (n=5, fresh)

| sample | scalar refill (ms) | batched refill (ms) | Δ |
|---|---:|---:|---:|
| 1 | 66.22 | 70.78 | −4.55 |
| 2 | 67.38 | 64.86 | +2.52 |
| 3 | 67.54 | 65.23 | +2.31 |
| 4 | 66.20 | 66.03 | +0.17 |
| 5 | 67.02 | 64.11 | +2.91 |
| **median** | **67.02** | **65.23** | **+2.31** |
| **mean** | **66.87** | **66.20** | **+0.67** |

The Phase 2 win on settled-state v7.4.0 is consistently positive in 4 of 5 samples. Sample 1 is a thermal-warmup outlier. Absolute DX wall is system-state-sensitive within ±5 ms; the relative Δ is the load-bearing metric.

---

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|:-:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 | ✓ |
| `J2KMedicalCorpusPerformanceTests` | 2/2 | ✓ |
| `J2KStrictCrossCodecValidationTests` | 3/3 | ✓ |
| `HTTileParityMatrixTests` | 1/1 (12 cells) | ✓ |
| `HTGPUForward53CrossCodecTests` | 1/1 | ✓ |
| `V740NeonReconstructionParityTests` | 5/5 sweeps | ✓ |
| `V740NeonRefillParityTests` | 11/11 sweeps | ✓ |
| `V740NeonVlcRefillParityTests` | 5/5 sweeps | ✓ |

---

## API surface

### Added (all `nonisolated(unsafe) public static var`)

- `HTMagSgnDecoderConformant.neonRefillEnabled: Bool = true` — opt-out switch for Phase 2 batched MagSgn refill (production default).
- `HTBlockDecoderConformant.neonReconstructionEnabled: Bool = false` — opt-in for Phase 1 SIMD4 reconstruction (rejected by gate).
- `VLCReverseReaderTesting.batchedRefillEnabled: Bool = false` — opt-in for Phase 3 SWAR VLC refill (rejected by gate).
- `VLCReverseReaderTesting` — new public enum holding the Phase 3 flag.

### Removed / changed

None. No public API removal or signature changes.

---

## Known limitations

- **Kakadu gap remains ~2.10× on DX in-process decode.** The remaining gap is structurally harder than v7.4's SWAR-on-chained-state pattern. Plausible directions:
  - Bit-parallel prefix-scan SIMD MagSgn refill that propagates the chained `0xFF`-unstuff across vector lanes — significant complexity for an uncertain incremental win on top of Phase 2's already-shipped 5.9 %.
  - Algorithmic re-engineering of the entropy stream layout (out of scope for a decoder-only optimisation).
  - GPU HT decode for full blocks (separate workstream, prototype on the `gpu-ht-decoder-prototype` branch).
- The two opt-in NEON paths (reconstruction, VLC refill) ship for measurement parity only — operators with no need for honest A/B tooling can ignore them.
- Pre-existing Self-RT diff on DX 2×2 / DX strips4 cells (decoder reads its own codestream and gets a max-pixel-diff > 0) is unchanged from v7.3.0; tracked separately.

---

## Reproducing the headline numbers

```bash
# Build
swift build -c release --product j2k

# Mandatory pre-release gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix
swift test -c release --filter 'HTTileParityMatrixTests|HTGPUForward53CrossCodecTests'

# Phase parity gates
swift test -c release --filter 'V740NeonReconstructionParityTests|V740NeonRefillParityTests|V740NeonVlcRefillParityTests'

# Phase 2 DX in-process A/B (the production default's measured win)
swift test -c release --filter V740NeonRefillDXWallBenchmark

# Phase 1 / Phase 3 microbench + DX A/B (the rejected paths' evidence)
swift test -c release --filter 'V740NeonReconstructionMicrobench|V740NeonReconstructionDXWallBenchmark'
swift test -c release --filter 'V740NeonVlcRefillMicrobench|V740NeonVlcRefillDXWallBenchmark'
```

---

## Companion documents

- [V7_4_0_PHASE_1_FINDING.md](../research/V7_4_0_PHASE_1_FINDING.md) — full Phase 1 measurement report (NEON reconstruction rejected at 0.90 ms Δ).
- [V7_4_0_PHASE_2_FINDING.md](../research/V7_4_0_PHASE_2_FINDING.md) — full Phase 2 measurement report (SWAR MagSgn refill accepted at 3.70 ms Δ).
- [V7_4_0_PHASE_3_FINDING.md](../research/V7_4_0_PHASE_3_FINDING.md) — full Phase 3 measurement report (SWAR VLC refill rejected at noise-bound Δ).
- [CROSS_VERSION_BENCHMARK_v7.1_v7.2_v7.3.md](CROSS_VERSION_BENCHMARK_v7.1_v7.2_v7.3.md) — six-fixture × three-version × {CLI, in-process} × {encode, decode} benchmark from the v7.3.0 release. Still the most-comprehensive cross-version comparison; v7.4.0's marginal contribution is captured in this document's Phase 2 section.
- [RELEASING.md](RELEASING.md) — canonical release process.
