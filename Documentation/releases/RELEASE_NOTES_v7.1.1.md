# J2KSwift v7.1.1 Release Notes

**Release Date**: 2026-05-08
**Release Type**: **PATCH** — hotfix on `release/v7.1.0`. Defaults unchanged; codestream bytes unchanged; opt-in surface unchanged.
**Previous Version**: 7.1.0
**Branch**: release/v7.1.0

---

## Fixed

### DX 4×4 multi-tile decode regression — H1.1's GPU entropy gate now bounded by per-tile pixel count

v7.1.0 H1.1 ([#335](https://github.com/Raster-Lab/J2KSwift/pull/335)) flipped multi-tile per-tile entropy decode from `isGPUPath: false` (the v6.3.0 E1.2 / v7.0.0 default) to `isGPUPath: true` unconditionally. The intent was to recover the +37–60 % entropy stage win the single-tile GPU HT path already enjoyed. The win materialised on **big-per-tile** fixtures (DX 2x2 = 1.6 M px/tile gained 44 %), but for **small-per-tile** fixtures the GPU HT dispatch overhead × N tiles dominates and the change regresses.

Cross-version delta benchmark, **DX 2800×2288 multi-tile decode wall (M2 release, median of 5)**:

| version | DX decode ms | mode |
|---|---:|---|
| v7.0.0 | **59.75** | CPU entropy + CPU IDWT (forced) |
| v7.1.0 | **127.83** ⚠ | GPU entropy + CPU IDWT — regressed 2.14× |
| **v7.1.1** | **68.35** ✓ | per-tile threshold gate restores v7.0.0 path for sub-1 MP/tile |

The hotfix adds a per-tile pixel threshold (default 1 048 576 = 1024×1024 = 1 MP) to the H1.1 routing in `decodeTilePayloadGPU`. Below the threshold, multi-tile per-tile decode falls back to CPU entropy (the v7.0.0 behaviour) for that tile; above, it runs GPU entropy (the v7.1.0 behaviour, which wins at scale). DX `.auto` (= 4x4 = 16 × 700×572 ≈ 400 K-pixel tiles) falls back to CPU. DX 2x2 (= 1.6 M-pixel tiles) keeps GPU.

A second per-tile threshold (`_gpuInverse53MultiTilePerTilePixelThreshold`, also defaulting to 1 MP) is added for the H3 ([#349](https://github.com/Raster-Lab/J2KSwift/pull/349)) IDWT routing as a defensive guard — empirically the H3 path already falls back to CPU IDWT for the production multi-tile per-tile case via the existing `hasFusedFromCodeblocksPlan` check, but the explicit threshold protects against future regressions where that path doesn't fire.

Both thresholds are tunable via the static vars `DecoderPipeline._gpuHTEntropyMultiTilePerTilePixelThreshold` and `DecoderPipeline._gpuInverse53MultiTilePerTilePixelThreshold` — tests can lower them to exercise the GPU code path on smaller per-tile sizes.

## Other fixtures (no change)

Per-fixture decode wall (M2 release, median of 5):

| fixture | px | v7.0.0 | v7.1.0 | v7.1.1 |
|---|---:|---:|---:|---:|
| MR-small 180² | 32K | 0.71 | 0.71 | 0.66 |
| CT 512² | 262K | 3.24 | 3.71 | 3.08 |
| MR 886² | 785K | 5.45 | 5.52 | 5.49 |
| XA 1024² | 1.05M | 8.78 | 8.83 | 9.03 |
| PX 2459×1316 | 3.24M | 32.37 | 34.02 | 32.92 |
| **DX 2800×2288** | **6.41M** | **59.75** | **127.83** | **68.35** ← **fixed** |

Smaller fixtures stay below the 1 MP per-tile threshold (their .auto layouts produce tiles smaller than 1 MP) and route through the CPU entropy path — same as v7.0.0 — so wall-time matches v7.0.0 within noise.

## Validation

- `MultiTileDecodeGPUDefaultOnTests.testMultiTileDefaultOn_DecodedPixelsIdentical_VsForcedOff` — pixel-byte-identical between gate-on (v7.1.1 hotfix path) and gate-off (legacy CPU multi-tile) across the medical corpus. **Strongest correctness gate, 1/1 passed (49.7s)**.
- Mandatory commit gate (release mode, per RELEASING.md):
  - `J2KStrictCrossCodecValidationTests` — 3/3 passed (0.5s)
  - `J2KMedicalCorpusPerformanceTests` — 2/2 passed (10.0s)
  - `J2KMedicalCorpusEncodePerformanceTests` — 2/2 passed (30.0s)

## Codestream bytes

Unchanged vs v7.1.0 / v7.0.0. Every fixture's codestream MD5 in `CrossVersionDeltaBenchmark` matches v7.0.0/v7.1.0 byte-for-byte. The hotfix is decode-side only.

## Known limitations (carried from v7.1.0)

- Approach C still ships behind the opt-in flag (default OFF); v7.2.x is the perf optimisation target.
- 9/7 irreversible IDWT still falls back to CPU on multi-tile per-tile (no parity-aware Float kernels yet; lossy is out of scope per `feedback_lossless_only_v5_38.md`).

## Reproducing

```bash
# Mandatory pre-release gate
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-version DX wall-time on the v7.1.1 hotfix branch
LABEL=v7.1.1 J2K_DELTA_OUT=/tmp/j2k_delta_v7.1.1 RUNS=5 \
  swift test -c release --filter testCrossVersionDeltaBenchmark
```

---

## Companion document

- [`CROSS_VERSION_DELTA_REPORT_v5.38_v7.0_v7.1.md`](CROSS_VERSION_DELTA_REPORT_v5.38_v7.0_v7.1.md) — measurement that surfaced this regression
- [`CROSS_CODEC_BENCHMARK_v7.1.0.md`](CROSS_CODEC_BENCHMARK_v7.1.0.md) — J2KSwift vs OpenJPH/Grok/Kakadu cross-codec comparison
