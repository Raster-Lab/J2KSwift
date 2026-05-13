# v7.2.0 — Phase E Empirical Finding (Plan Revision)

**Captured**: 2026-05-08, Apple M2 (24G624 / Darwin 24.6.0), release builds, median of 5.

This document captures an empirical refutation of the original Phase E plan and the pivot it triggered.

---

## What the original plan said

From `V7_2_0_PROFILE.md` § 4 (Plan revision based on Phase 0 findings, Option 3):

> **Phase E — Decode entropy GPU routing widening**: Lower
> `_gpuHTEntropyMultiTilePerTilePixelThreshold` from 1 MP → ~256 K to fire on
> DX 4x4 (400 K/tile), AND wire multi-tile per-tile GPU IDWT (v6.3.0 E1.2
> deferred work). Each is its own PR. Bit-exact gate enforced.

The plan was based on the assumption that **the GPU paths are faster than CPU on small per-tile sizes once they fire** — i.e., that the v7.1.1 hotfix was over-conservative and the real crossover was somewhere below 1 MP per tile.

## What the empirical sweep showed

`V720PhaseEThresholdSweepTests.testPhaseEThresholdSweep_DX4x4` decodes a DX 4x4 multi-tile codestream (per-tile pixels = 700 × 572 = **400 400**) at threshold values {256K, 512K, 1M, 2M, ∞}. A threshold ≤ 400 400 routes that stage to GPU; otherwise it stays on CPU.

### Both stages on GPU together

| threshold | DX 4x4 decode ms | entropy on GPU | IDWT on GPU |
|---|---:|:---:|:---:|
| **256K** | **134.08** | ✓ | ✓ |
| 512K | 79.83 | ✗ | ✗ |
| 1M (current) | 74.64 | ✗ | ✗ |
| 2M | 74.84 | ✗ | ✗ |
| ∞ | 80.97 | ✗ | ✗ |

### Isolated entropy GPU contribution

| entropy threshold (IDWT pinned to CPU) | DX 4x4 decode ms | entropy on GPU |
|---|---:|:---:|
| **256K** | **132.35** | ✓ |
| 512K | 77.79 | ✗ |
| 1M | 77.34 | ✗ |
| 2M | 84.96 | ✗ |
| ∞ | 72.72 | ✗ |

GPU entropy at 400K/tile = **1.82× SLOWER than CPU entropy** (132 / 73).

### Isolated IDWT GPU contribution

| IDWT threshold (entropy pinned to CPU) | DX 4x4 decode ms | IDWT on GPU |
|---|---:|:---:|
| **256K** | **90.37** | ✓ |
| 512K | 88.66 | ✗ |
| 1M | 70.41 | ✗ |
| 2M | 69.43 | ✗ |
| ∞ | 79.13 | ✗ |

GPU IDWT at 400K/tile = **1.28× SLOWER than CPU IDWT** (90 / 70).

## Conclusion

The v7.1.1 hotfix was correct: per-tile GPU dispatch overhead on the current code structure makes GPU 1.3–1.8× slower than CPU at ~400 K pixels per tile. **Lowering the threshold the way the original Phase E said would cause a 1.8× regression on the headline DX 4x4 fixture, not an improvement**.

The 62.6% entropy bottleneck on DX decode that Phase 0 identified is **CPU entropy**, not GPU dispatch overhead. Routing it to GPU at small per-tile sizes makes it worse.

## Why the GPU is slow at small per-tile sizes (root cause)

Each call to `decodeTilePayloadGPU` constructs its own MTLCommandBuffer (or several — once per `applyEntropyDecoding`, once per `applyInverseWaveletTransformGPU`, etc.) and waits for it to complete. CB construction + submission + completion has a fixed per-CB cost. For a 4x4 multi-tile decode that's 16 tiles × N CBs each = 16N command buffers. The compute work in each CB is small (400 K-pixel tile takes ~2-3 ms of GPU time); the CB overhead dominates.

`withThrowingTaskGroup` parallelism in `decodeMultiTileGPU` runs up to 8 tiles concurrently, but each task still pays its own per-CB overhead independently — they don't share infrastructure.

## Plan revision (Option B, user-approved)

**Original Phase E** (lower threshold) — **withdrawn** based on this finding.

**Phase E (revised)** — Attack the per-tile CB amortization. Batch all tiles' GPU work into a single MTLCommandBuffer per stage (one CB encodes all 16 tiles' entropy work, one CB encodes all 16 tiles' IDWT, etc.). Once the fixed per-CB overhead is paid once instead of 16 times, the GPU-vs-CPU crossover should move down — making the original "lower threshold" plan safe.

This is the same architectural pattern as v5.30.0 → v5.4.0 phase-3 dispatch amortization on the encoder forward DWT. The decoder side has not had this treatment applied yet.

If the CB amortization works (≥ 25% improvement on DX 4x4 vs current 75 ms), then a follow-up PR can lower the per-tile thresholds and route DX 4x4 fully through GPU.

If the CB amortization doesn't work (< 10% improvement or regression), declare the per-tile-dispatch ceiling structural and fall back to **Phase D** (CPU SIMD audit on the entropy stage — the 62.6% wedge is on CPU regardless).

## Reproduction

```bash
RUNS=5 swift test -c release --filter testPhaseEThresholdSweep_DX4x4
```

The test will print three tables (combined sweep, entropy-only, IDWT-only) on stdout.
