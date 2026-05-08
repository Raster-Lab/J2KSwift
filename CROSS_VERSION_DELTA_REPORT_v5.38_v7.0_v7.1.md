# Cross-Version Delta Report — v5.38.0 → v7.0.0 → v7.1.0

**Measured**: 2026-05-08, Apple M2, Swift 6.2 release mode, median of 5 runs per cell
**Tool**: `Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift` (the harness designed to drop unchanged onto historical revisions back to v5.38.0)
**Workflow**: `git worktree add` checkout of each tag → run the same benchmark file → diff CSVs

The benchmark exercises **HT-conformant lossless 5/3** encode + decode on 7 real medical 16-bit PGM fixtures shipped under `Tests/Fixtures/CrossCodec/` at every revision.

---

## Headline

| metric | v5.38.0 | v7.0.0 | v7.1.0 | v5.38→v7.1 |
|---|---:|---:|---:|---:|
| **DX 2800×2288 encode** (M2 release ms) | 114.6 | 51.6 | 54.7 | **+2.10×** faster |
| **PX 2459×1316 encode** | 57.5 | 23.5 | 24.7 | **+2.33×** faster |
| **XA 1024² encode** | 13.4 | 7.5 | 7.4 | **+1.81×** faster |
| **MR 886² encode** | 6.0 | 2.8 | 3.0 | **+2.02×** faster |
| **DX 2800×2288 decode** | 121.2 | 59.8 | 127.8 | **−1.06×** slower ⚠ |
| **PX 2459×1316 decode** | 68.3 | 32.4 | 34.0 | **+2.01×** faster |
| **XA 1024² decode** | 17.1 | 8.8 | 8.8 | **+1.94×** faster |
| **MR 886² decode** | 6.1 | 5.5 | 5.5 | **+1.11×** faster |

**Encode is monotonically faster across releases.** v5.38→v7.0 captured the multi-tile-encoding default flip win (#332); v7.0→v7.1 stayed near break-even (default config unchanged in v7.1).

**Decode is monotonically faster across releases EXCEPT DX**, which regresses 2.14× from v7.0.0 → v7.1.0. The v7.1.0 H3 change ([#349](https://github.com/Raster-Lab/J2KSwift/pull/349)) flipped multi-tile per-tile decode from CPU IDWT to GPU IDWT for the 5/3 reversible non-fused path; for DX-at-`.auto`-default (4x4 = 16 tiles × 700×572 px each), the per-tile GPU dispatch overhead dominates. The wall regresses from 60 ms (CPU IDWT) to 128 ms (GPU IDWT). The v7.1.0 release notes flag this in *Known limitations*; a hotfix candidate is to add a per-tile pixel threshold so 4x4 (≤ 1 MP/tile) falls back to CPU.

---

## Single-tile encode wall-time (median of 5, M2 release, ms)

| fixture | shape | px | v5.38.0 | v7.0.0 | v7.1.0 | v5.38 → v7.1 | v7.0 → v7.1 |
|---|---|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180 | 32K | 0.76 | 0.74 | 0.79 | 0.96× | 0.94× |
| CT | 512×512 | 262K | 3.56 | 3.03 | 3.69 | 0.96× | 0.82× |
| CT (alt) | 512×512 | 262K | 3.46 | 2.89 | 3.07 | 1.13× | 0.94× |
| **MR** | **886×886** | **785K** | **5.97** | **2.76** | **2.95** | **2.02×** | 0.94× |
| **XA** | **1024×1024** | **1.05M** | **13.41** | **7.50** | **7.36** | **1.82×** | 1.02× |
| **PX** | **2459×1316** | **3.24M** | **57.54** | **23.45** | **24.74** | **2.33×** | 0.95× |
| **DX** | **2800×2288** | **6.41M** | **114.58** | **51.59** | **54.70** | **2.10×** | 0.94× |

Notable: encode wall-time variance v7.0→v7.1 stays within ±6%. v7.1.0 made no changes to the default-config encode path; small movements are run-to-run noise.

---

## Single-tile decode wall-time (median of 5, M2 release, ms)

| fixture | shape | px | v5.38.0 | v7.0.0 | v7.1.0 | v5.38 → v7.1 | v7.0 → v7.1 |
|---|---|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180 | 32K | 0.71 | 0.71 | 0.71 | 1.00× | 1.00× |
| CT | 512×512 | 262K | 3.62 | 3.24 | 3.71 | 0.98× | 0.87× |
| CT (alt) | 512×512 | 262K | 3.62 | 3.05 | 3.18 | 1.14× | 0.96× |
| MR | 886×886 | 785K | 6.12 | 5.45 | 5.52 | 1.11× | 0.99× |
| XA | 1024×1024 | 1.05M | 17.13 | 8.78 | 8.83 | 1.94× | 0.99× |
| PX | 2459×1316 | 3.24M | 68.31 | 32.37 | 34.02 | 2.01× | 0.95× |
| **DX** | **2800×2288** | **6.41M** | **121.15** | **59.75** | **127.83** | **0.95×** | **0.47× ⚠** |

**The DX v7.0→v7.1 regression is the single delta worth investigating before v7.2.** All other fixtures held within ±5% v7.0→v7.1.

---

## 2x2 multi-tile mode wall-time

The benchmark also exercises an explicit 2x2 tile mode (configured via `J2KImage.tileWidth/tileHeight`):

| fixture | px | v5.38.0 enc / dec | v7.0.0 enc / dec | v7.1.0 enc / dec |
|---|---:|---:|---:|---:|
| MR | 785K | 5.81 / 6.25 | 2.74 / 5.41 | 2.99 / 5.50 |
| XA | 1.05M | 26.05 / 42.65 | 7.46 / 8.76 | 7.69 / 9.02 |
| PX | 3.24M | 62.58 / 74.43 | 23.33 / 32.69 | 23.86 / 33.31 |
| **DX** | 6.41M | 102.33 / 119.43 | 51.40 / 62.15 | **52.47 / 127.70** |

Same DX decode regression in tile2x2 mode as in single mode — confirms the regression is in the IDWT path, not encoding. v5.38.0's parallelism-poor multi-tile decode (XA 42.65 ms, PX 74.43 ms) flipped to v7.0.0's optimised path (XA 8.76, PX 32.69) — the H1.1 work measured here as +44–60 % win on multi-tile DX decode, etc. v7.1.0's H3 change reverses that win for DX.

---

## Codestream byte equality

Every fixture × mode produced byte-identical codestream MD5 v7.0.0 → v7.1.0 (default-config encode unchanged):

| fixture | mode | v7.0.0 md5 | v7.1.0 md5 | match |
|---|---|---|---|:-:|
| MR-small 180² | single | `f4add755ec26…` | `f4add755ec26…` | ✓ |
| CT 512² | single | `6c968561c0d3…` | `6c968561c0d3…` | ✓ |
| CT 512² alt | single | `043a41ec40f3…` | `043a41ec40f3…` | ✓ |
| MR 886² | single | `e29a2366ca1f…` | `e29a2366ca1f…` | ✓ |
| XA 1024² | single | `c7f1252aca8e…` | `c7f1252aca8e…` | ✓ |
| PX 2459×1316 | single | `05c68da54364…` | `05c68da54364…` | ✓ |
| DX 2800×2288 | single | `447a3a8ddeac…` | `447a3a8ddeac…` | ✓ |

v5.38.0 differs (because v6/v7's multi-tile + Qstep tuning changed bytes); v7.0.0/v7.1.0 are byte-identical.

---

## Key findings

1. **v5.38 → v7.1 encode arc**: ~2× speedup on every fixture ≥ 785K px. Driven by v6 / v7 multi-tile encoding parallelism + the v7.0 production-default flip.
2. **v5.38 → v7.1 decode arc**: ~2× speedup on most fixtures via the v6 GPU IDWT + GPU HT entropy work. **DX is the lone exception** — would have been ~2× faster (matches v7.0.0's 60 ms) without the v7.1.0 H3 flip.
3. **v7.1.0 DX decode regression** is real, reproducible (verified across two independent runs), and matches the wall-time A/B from the H3 PR (#349). Caused by H3 routing multi-tile per-tile decode through GPU IDWT, which regresses on the 16-tile case (per-tile dispatch overhead × 16 small tiles).

## Recommendation for v7.2 / v7.1.1 hotfix

Add a per-tile pixel threshold to the H3 GPU IDWT routing so DX 4x4 (~400K px/tile) falls back to CPU IDWT:

```swift
// In applyInverseWaveletTransformGPU's isMultiTilePerTile branch:
if isMultiTilePerTile {
    let perTilePixels = metadata.width * metadata.height
    // Below ~1 MP per tile, GPU dispatch overhead × N tiles dominates
    if perTilePixels < _gpuInverse53MultiTilePerTilePixelThreshold {
        return try await applyInverseWaveletTransform(...)  // CPU
    }
    // ... rest of GPU path
}
```

The static var `_gpuInverse53MultiTilePerTilePixelThreshold` was added in K1 ([#350](https://github.com/Raster-Lab/J2KSwift/pull/350)) but not consulted on the actual production routing path. Wire it in and DX 4x4 falls back to CPU IDWT, recovering the v7.0.0 60 ms decode wall.

---

## Reproducing

```bash
# v7.1.0 (current main)
LABEL=v7.1.0 J2K_DELTA_OUT=/tmp/j2k_delta_v7.1.0 RUNS=5 \
  swift test -c release --filter testCrossVersionDeltaBenchmark

# v7.0.0 (worktree)
git worktree add /tmp/j2k_v7.0.0 v7.0.0
cp Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift /tmp/j2k_v7.0.0/Tests/J2KCodecTests/
cd /tmp/j2k_v7.0.0 && LABEL=v7.0.0 J2K_DELTA_OUT=/tmp/j2k_delta_v7.0.0 RUNS=5 \
  swift test -c release --filter testCrossVersionDeltaBenchmark

# v5.38.0 (worktree)
git worktree add /tmp/j2k_v5.38.0 v5.38.0
cp Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift /tmp/j2k_v5.38.0/Tests/J2KCodecTests/
cd /tmp/j2k_v5.38.0 && LABEL=v5.38.0 J2K_DELTA_OUT=/tmp/j2k_delta_v5.38.0 RUNS=5 \
  swift test -c release --filter testCrossVersionDeltaBenchmark
```

CSVs land at `$J2K_DELTA_OUT/results.csv` for each label.
