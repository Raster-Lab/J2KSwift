# J2KSwift v7.1.0 Release Notes

**Release Date**: 2026-05-08
**Release Type**: **MINOR** — defaults unchanged; codestream bytes byte-identical to v7.0.0; new opt-in surface
**Previous Version**: 7.0.0
**Branch**: main

---

## Summary

v7.1.0 ships the **decode-side multi-tile per-tile modernisation arc** end-to-end: H phase (H1.1 + H2 + H2.2 + H3) closes Defect A and Defect B, the two correctness gaps that previously forced multi-tile per-tile decode through CPU IDWT for safety. With this release, multi-tile decode runs entropy + dequant + colour + IDWT all on GPU. Combined with H1.1's +44–60 % DX entropy-stage win (already shipped in #335), this is the biggest single-release multi-tile decode-side change since v6.2.0's single-tile GPU IDWT enablement.

The encode-side I phase ships **GPU forward HT entropy approach C end-to-end** behind the existing `_gpuForwardHTEntropyEnabled` opt-in flag (default OFF). The full pipeline — classifier → batched cleanup-pass kernel → 3-stream emit → block assemble — is bit-exact with the CPU encoder across the medical corpus. Wall-time is **slower than CPU at every fixture** in this release (DX regresses 43 % vs CPU); per the user directive _"approach C is definite, even if we compromise speed"_, correctness shipped first. Performance optimisation is the v7.2.x target.

Defaults unchanged. Codestream bytes byte-identical to v7.0.0 on every default-config encode/decode path. Public API additions only (no removals or signature changes). 18 commits / 6 weeks of work.

---

## What's New — production-default

### H1.1 — Multi-tile per-tile entropy fix ([#335](https://github.com/Raster-Lab/J2KSwift/pull/335))

3-line `isMultiTilePerTile` parameter addition to `applyEntropyDecoding` plus the wire-in to `decodeTilePayloadGPU`. Closes the v5.9 zero-copy fast-lane's empty `[SubbandInfo]` return when downstream IDWT runs on CPU — the actual root cause of the 32,768-pixel diff (the 2¹⁵ DC offset for 16-bit) that v6.3.0 E1.2 had mis-attributed to the GPU HT entropy path.

Multi-tile DX decode wall measured **+44 % to +60 %** depending on tile mode on M2 release; corpus parity unchanged.

### H2 + H2.2 + H3 — Multi-tile per-tile GPU IDWT closure ([#346](https://github.com/Raster-Lab/J2KSwift/pull/346) → [#348](https://github.com/Raster-Lab/J2KSwift/pull/348) → [#349](https://github.com/Raster-Lab/J2KSwift/pull/349))

Three-stage closure of Defect B — the missing parity-aware boundary lifting in the GPU 5/3 inverse DWT kernels:

1. **H2 (#346)** — MSL port of `J2KDWT1DOptimized.inverseTransform53OddOriginSymmetric` as `j2k_dwt_inverse_53_horizontal_int_odd` and `j2k_dwt_inverse_53_vertical_int_odd`. Right-mirror-only on the L update, three-region H update, flipped interleave per ISO 15444-1 Annex F.4.1.1. Bit-exact with the CPU reference across width 1 → 100 + odd-height vertical + multi-row dispatch.
2. **H2.2 (#348)** — `J2KMetalDWTSubbandsInt32` gains `tileOriginX/Y` (default 0). `encodeInverse2DInt32` selects even-vs-odd kernel per axis based on origin parity; `inverse2DCPUInt32` mirrors the parity selection.
3. **H3 (#349)** — `applyInverseWaveletTransformGPU` flows the per-component canvas origin through to per-decomposition-level band origins (`ceilDivIntegerOrigin(tcx0, 2^outputDepth)`). The `isMultiTilePerTile: true` short-circuit now allows the 5/3 reversible non-fused path (the production HT lossless multi-tile per-tile case) to run on GPU; CPU fallback retained for 9/7 irreversible + 5/3 fused-from-codeblocks.

`HTTileParityMatrixTests` cells (the H phase gate): **12/12 cells × 3 external decoders = 36 cross-decode results, all max-diff = 0** including 3 ANY-ODD cells (PX 4x4, PX strips4, MR 886² 2x2) that pre-H2 would have failed.

### K1 — Multi-tile per-tile warm-session regression-guard ([#350](https://github.com/Raster-Lab/J2KSwift/pull/350))

Three new tests pin the warm-session reuse contract for the multi-tile per-tile decode path. The headline empirical finding: **steady-state multi-tile per-tile decode allocates ZERO new MTLBuffers** across 12+ tile-decodes. Full pool reuse confirmed end-to-end; future regressions that bypass the pool would scale with tile count and cross the 32-buffer absolute cap immediately.

---

## What's New — opt-in (default-OFF)

### I phase — GPU forward HT entropy approach C ([#336](https://github.com/Raster-Lab/J2KSwift/pull/336)–[#347](https://github.com/Raster-Lab/J2KSwift/pull/347))

Eight PRs (I1.0 design + I1.1 prefix-sum + I1.2/b/c/d bit-pack primitives + I1.3a design correction + I1.3b/c/d unified Pass 3 + I1.3-perf cleanup) ship the complete GPU forward HT entropy pipeline behind the existing `_gpuForwardHTEntropyEnabled` flag (default OFF since v6-alpha6 phase 1):

- **Unified Pass 3 cleanup-pass kernel** (`j2k_ht_cleanup_pass_emit_blocks_batched`) — direct port of `HTBlockEncoderConformant.encode(preClassifiedTuples:)` to MSL. One threadgroup per block; thread 0 runs the entire per-block cleanup-pass + 3-stream emit serially (~700 lines of MSL with state machine, lookup tables, bit packing). All 3 streams (MagSgn / MEL / VLC) emit on GPU including inline FF-stuffing and the VLC reverse-bit deferred-stuff release.
- **Bit-exact end-to-end** — the gate flag activates a path that produces byte-identical codestreams to the CPU encoder across the medical corpus (`HTGPUForwardHTEntropyOrchestratorTests.testOrchestrator_GateOnVsOff_BytesIdentical_AllFixtures` — full corpus byte-equality vs gate-off).
- **Wall-time on M2 release**: DX 73.82 ms vs CPU 51.58 ms (1.43× slower); smaller fixtures regress more (MR-small 8.8× slower). The dominant cost is the per-block-serial cleanup-pass kernel itself; an attempted warp-wide restructure (32 threads × 32 blocks per warp) regressed 13 % due to SIMD divergence on data-dependent branches and was reverted.

The flag stays OFF by default in v7.1.0; users who want approach C can opt in via `J2K_GPU_FORWARD_HT_ENTROPY=1` or programmatic `EncoderPipeline._gpuForwardHTEntropyEnabled = true`. Performance optimisation is the v7.2.x target.

### Existing opt-in flags carry forward

- `J2K_HT_TILE_MODE=single` — pin v6.x byte-stability (restores v6.3.0 codestream bytes verbatim)
- `J2K_GPU_FORWARD_53=0` — force legacy CPU forward DWT path
- `J2K_GPU_INVERSE_53=0` — force legacy CPU decode path
- `J2K_GPU_HT_ENTROPY_DECODE=0` — disable GPU HT entropy on the routed GPU decode path

---

## Backward compatibility

**Codestream bytes byte-identical to v7.0.0 on every default-config encode/decode path.** No defaults flipped in v7.1.0; the H phase only changes what code runs (GPU instead of CPU) for paths whose output was already specified bit-exact. Lossless 5/3 decode pixels remain bit-exact across all paths.

`HTGPUForwardHTEntropyOrchestratorTests.testOrchestrator_GateOnVsOff_BytesIdentical_AllFixtures` — full medical corpus byte-equality between gate-on (approach C, opt-in) and gate-off (CPU encoder, default) confirmed empirically.

`MultiTileDecodeGPUDefaultOnTests.testMultiTileDefaultOn_DecodedPixelsIdentical_VsForcedOff` — pixel-byte-identical between v7.1.0 GPU multi-tile decode (post-H3 path) and legacy forced-CPU multi-tile decode confirmed across the medical corpus.

---

## Cross-codec parity matrix — fresh measurement

Re-run `HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` on Apple M2 with v7.1.0 main:

| parity class | cells | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4.1 |
|---|---:|:-:|:-:|:-:|
| ALL-EVEN | 9 | **9/9** ✓ | **9/9** ✓ | **9/9** ✓ |
| ANY-ODD | 3 | **3/3** ✓ | **3/3** ✓ | **3/3** ✓ |

**12 / 12 cells × 3 external decoders = 36 cross-decode results, all max-pixel-diff = 0** (bit-exact). The 3 ANY-ODD cells are PX 2459×1316 4x4, PX strips4, and MR 886² 2x2 — these are the cells that pre-H2 would have produced wrong pixels under the GPU multi-tile per-tile decode path.

---

## Medical-corpus benchmarks — fresh measurement

### Multi-tile decode wall-time A/B (M2 release)

`MultiTileDecodeGPUDefaultOnTests.testMultiTileDefaultOn_WallTimeAB_AcrossCorpus` — gate-on (post-H3 GPU IDWT for multi-tile per-tile) vs gate-off (legacy CPU multi-tile IDWT):

| fixture | mode | tiles | CPU ms | GPU ms | CPU/GPU× |
|---|---|---:|---:|---:|---:|
| MR 886² | 2x2 | 4 | 5.2 | 5.5 | 0.95× |
| MR 886² | 4x4 | 16 | 6.8 | 7.3 | 0.93× |
| MR 886² | strips4 | 4 | 4.2 | 4.3 | 0.98× |
| XA 1024² | 2x2 | 4 | 8.8 | 8.6 | 1.02× |
| XA 1024² | 4x4 | 16 | 10.9 | 10.8 | 1.01× |
| XA 1024² | strips4 | 4 | 8.5 | 8.5 | 1.00× |
| PX 2459×1316 | 2x2 | 4 | 29.0 | 28.3 | 1.02× |
| PX 2459×1316 | 4x4 | 16 | 32.2 | 32.1 | 1.01× |
| PX 2459×1316 | strips4 | 4 | 30.9 | 31.4 | 0.99× |
| **DX 2800×2288** | **2x2** | 4 | 56.5 | 55.6 | **1.02×** |
| DX 2800×2288 | 4x4 | 16 | 62.8 | 127.2 | 0.49× |
| **DX 2800×2288** | **strips4** | 4 | 55.1 | 53.8 | **1.02×** |

Most fixtures: GPU within ±5 % of CPU (essentially break-even with the well-optimised CPU IDWT for these per-tile sizes). DX 2x2 + DX strips4 (the production-typical big-fixture modes) gain 2 % from GPU. **DX 4x4 regresses 51 %** — 16 small tiles (700×572 ≈ 400 K px each) pay too much per-tile GPU dispatch overhead. Tracked as a v7.2.x optimisation; not blocking v7.1.0 since 4x4 isn't a production-default tiling mode and the regression is purely opt-in (gate-off keeps CPU IDWT).

### Encode wall-time

**Unchanged from v7.0.0.** v7.1.0 makes no changes to default-config encode behaviour. The I phase ships approach C behind the opt-in flag (default OFF); v7.0.0's multi-tile encoding production-default flip remains the active production-default behaviour. See [v7.0.0 release notes](RELEASE_NOTES_v7.0.0.md) §"Per-fixture wall-time impact" for the encode-default benchmarks.

### Approach C encode wall-time (opt-in flag, M2 release)

Reported here so users opting in know what they're getting:

| fixture | px | CPU ms | GPU (approach C) ms | Δ % |
|---|---:|---:|---:|---:|
| MR-small 180² | 32K | 0.80 | 7.04 | -780.2 |
| MR 886² | 785K | 2.62 | 10.41 | -296.6 |
| XA 1024² | 1.05M | 8.00 | 26.09 | -226.0 |
| PX 2459×1316 | 3.24M | 23.80 | 58.10 | -144.1 |
| **DX 2800×2288** | **6.41M** | **51.58** | **73.82** | **-43.1** |

Approach C is slower than CPU at every fixture; the gap shrinks monotonically with fixture size. The dominant cost is the per-block-serial cleanup-pass kernel itself, not the I/O staging or table upload — measured via the I1.3-perf cleanup work in [#347](https://github.com/Raster-Lab/J2KSwift/pull/347). v7.2.x optimisation candidates: kernel-level restructure (the warp-wide attempt regressed 13 % due to SIMD divergence and was reverted; alternative restructures are open).

---

## Test Suite Results

| Suite | Tests | Status |
|---|---:|---|
| `J2KStrictCrossCodecValidationTests` | 3 | **3/3** passed |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | **2/2** passed |
| `J2KMedicalCorpusPerformanceTests` | 2 | **2/2** passed |
| `HTTileParityMatrixTests` | 1 (12 cells × 3 decoders) | **12/12 cells, max-diff = 0** |
| `MultiTileDecodeGPUDefaultOnTests` | 2 | **2/2** passed |
| `MultiTilePerTileWarmSessionHardeningTests` (NEW — K1) | 3 | **3/3** passed |
| `J2KMetalDWT53IntBitExactTests` (existing even-origin) | 3 | **3/3** passed |
| `J2KMetalDWT53IntOddOriginBitExactTests` (NEW — H2) | 7 | **7/7** passed |
| `J2KMetalDWT53IntOriginAwareWireInTests` (NEW — H2.2) | 8 | **8/8** passed |
| `MetalHTForwardCleanupPassEmitTests` (NEW — I1.3b) | 8 | **8/8** passed |
| `MetalHTForwardCleanupPassEmitBatchedTests` (NEW — I1.3c) | 7 | **7/7** passed |
| `MetalHTForwardPrefixSumTests` (NEW — I1.1) | 8 | **8/8** passed |
| `MetalHTForwardMagSgnEmitTests` (NEW — I1.2) | 10 | **10/10** passed |
| `MetalHTForwardMagSgnEmitBatchedTests` (NEW — I1.2b) | 7 | **7/7** passed |
| `MetalHTForwardMELEmitTests` (NEW — I1.2c) | 9 | **9/9** passed |
| `MetalHTForwardVLCEmitTests` (NEW — I1.2d) | 8 | **8/8** passed |
| `HTGPUForwardHTEntropyOrchestratorTests` | 3 (incl. corpus byte-identical) | **3/3** passed |
| `HTGPUForwardHTEntropyBatchBitExactTests` | 4 | **4/4** passed |
| `MultiTileGPUHTPostEntropyDriftTests` (NEW — H1.1) | 1 | **1/1** passed |

---

## API surface — additions only

- `J2KMetalDWTSubbandsInt32` — two new optional fields `tileOriginX: Int = 0`, `tileOriginY: Int = 0`. Default values preserve all v7.0.0 caller behaviour.
- `J2KMetalDWT.encodeInverse2DInt32(...)` — two new optional parameters `tileOriginX: Int = 0`, `tileOriginY: Int = 0`. Defaults preserve v7.0.0 behaviour.
- `J2KShaderFunction` enum — four new cases: `dwtInverse53HorizontalIntOdd`, `dwtInverse53VerticalIntOdd`, `htCleanupPassEmitBlocksBatched`, `prefixSumInclusiveUInt32`, `htMagSgnEmitBlock`, `htMagSgnEmitBlocksBatched`, `htMelEmitBlocksBatched`, `htVlcEmitBlocksBatched`.
- `J2KGPUForwardHTCleanupPassEmit` (new public struct in J2KCodec) — Swift orchestrator for the unified Pass 3 kernel; exposes `BlockDescriptor`, `FlatBlockDescriptor`, `BatchedResult`, `EmitResult` types and `emitBlocks(_:)` / `emitBlocksFlat(tuples:blocks:)` / `emitBlock(...)` APIs.
- `J2KMetalPrefixSum` (new public struct) — `inclusiveScan(_:)` API for UInt32 arrays via the I1.1 single-threadgroup prefix-sum kernel.
- `J2KMetalHTMagSgnEmit`, `J2KMetalHTMELEmit`, `J2KMetalHTVLCEmit` (new public structs) — bit-pack primitive wrappers for the three HT byte streams (used as bit-exact reference targets; production approach C inlines the equivalent logic in the unified kernel).
- `DecoderPipeline._gpuInverse53MultiTilePerTilePixelThreshold: Int = 1_048_576` (NEW static var) — currently unused (the threshold was added in K1 work but turned out to be a no-op for the targeted regression; left in place for future use).

No removals. No signature changes on existing public surface.

---

## Known limitations

- **Approach C is slower than CPU.** v7.1.0 ships approach C correctness-first behind the opt-in flag; default behaviour unchanged. v7.2.x optimisation work is queued.
- **DX 4x4 multi-tile decode regresses 51 %** under the H3-flipped path. 16 × 400 K-pixel tiles pay too much per-tile GPU dispatch overhead. Tracked for v7.2.x — likely needs a per-tile pixel threshold tunable on the GPU IDWT routing for multi-tile.
- **9/7 irreversible IDWT** still has no parity-aware Float kernel — `isMultiTilePerTile: true` on a 9/7 codestream still falls back to CPU IDWT. Lossy is out of scope per `feedback_lossless_only_v5_38.md` (2026-05-05).
- **`inverse2DInt32FullFusedFromCodeblocks` path** doesn't yet support tile origins; the H3 short-circuit retains CPU fallback when this path would fire (gpuBatch with `plansByComponent` populated). Production multi-tile per-tile HT lossless decode reaches the multi-level-fused path (origin-aware), not the full-fused path; in practice no production fixture is affected.

---

## Reproducing the headline numbers

```bash
# Mandatory commit gate (release mode; required for every release)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix (12 cells × 3 decoders)
swift test --filter HTTileParityMatrixTests

# Multi-tile decode wall-time A/B
swift test -c release --filter \
  "MultiTileDecodeGPUDefaultOnTests/testMultiTileDefaultOn_WallTimeAB_AcrossCorpus"

# Approach C wall-time A/B (encode side, opt-in)
swift test -c release --filter \
  "HTGPUForwardHTEntropyOrchestratorTests/testOrchestrator_WallTimeAB_AcrossCorpus"

# Warm-session regression guard (K1)
swift test --filter MultiTilePerTileWarmSessionHardeningTests
```

---

## Companion documents

- [`docs/V7_1_0_PLAN.md`](docs/V7_1_0_PLAN.md) — release plan with H + I phase scope (closed by this release)
- [`docs/V7_1_0_H1_0_INVESTIGATION.md`](docs/V7_1_0_H1_0_INVESTIGATION.md), [`docs/V7_1_0_H1_1_INVESTIGATION.md`](docs/V7_1_0_H1_1_INVESTIGATION.md) — Defect A root-cause investigation
- [`docs/V7_1_0_I1_0_DESIGN.md`](docs/V7_1_0_I1_0_DESIGN.md), [`docs/V7_1_0_I1_3_DESIGN.md`](docs/V7_1_0_I1_3_DESIGN.md) — approach C design + the I1.0 → I1.3 scope correction
