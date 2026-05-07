# J2KSwift v7.0.0 Release Notes

**Release Date**: 2026-05-07
**Release Type**: **MAJOR** — production-default tile mode flips from `.single` to `.auto`
**Previous Version**: 6.3.0
**Branch**: main

---

## Summary

v7.0.0 ships the **production-default flip from single-tile to auto-multi-tile encoding** for HT-conformant lossless 5/3 codestreams. The empirical encode-wall wins measured at +30 to +50 % on MR/XA/PX (Apple M2) reach default-config consumers without env-var twiddling. **MR 886² flips from being 1.6× behind Kakadu to 1.21× ahead** on the same medical fixture corpus — the biggest single-release Kakadu-gap closure since the v6 series began.

**Bytes change vs v6.x for default-config users.** Pixels remain bit-exact (HTTileParityMatrixTests 48/48, HTGPUForward53CrossCodecTests 21/21). Lossy 9/7 codestream bytes are **unchanged** (lossy is out of scope per the lossless-only product target). v6.x consumers can pin v6.3.0 codestream bytes by setting `J2K_HT_TILE_MODE=single`.

The infrastructure has been in production since v6-alpha3 step 9 (`encodeNativeMultiTile` uses `withThrowingTaskGroup` for per-tile parallelism); only the routing default needed to flip — a single-line change. The v6.4.0 plan ([#328](https://github.com/Raster-Lab/9J2KSwift/pull/328)) G1 audit ([#329](https://github.com/Raster-Lab/J2KSwift/pull/329)) revealed this and G1.2 ([#330](https://github.com/Raster-Lab/J2KSwift/pull/330)) surfaced the SemVer Path 2 decision; v7.0.0 PR ([#331](https://github.com/Raster-Lab/J2KSwift/pull/331)) executed the flip.

---

## What's New — production-default

### M1 — Multi-tile encoding production-default ([#331](https://github.com/Raster-Lab/J2KSwift/pull/331))

`J2KHTTileMode.from(envValue: nil)` returns `.auto` instead of `.single`. The `.auto` planner picks the optimal tile grid per fixture pixel count:

```
pixels < 500K  → single-tile     (small fixtures: per-tile dispatch overhead exceeds gain)
500K ≤ px <3M  → 2x2 tiles       (mid-tier: MR/XA)
pixels ≥ 3M    → 4x4 tiles       (large: PX/DX/MG)
```

The decomposition floor (each tile ≥ `2^decompositionLevels`) still gates multi-tile out for small images that can't support per-tile DWT depth.

### Per-fixture wall-time impact (Apple M2, release mode)

Comparison of v6.3.0 production default (`.single`) vs v7.0.0 production default (`.auto`):

| Modality | Shape | px | v6.3.0 wall | v7.0.0 wall | Δ |
|---|---|---:|---:|---:|---:|
| MR-small | 180×180 | 32K | unchanged | unchanged | — (gated to single) |
| CT | 512×512 | 262K | unchanged | unchanged | — (gated to single) |
| **MR** | **886×886** | **785K** | **6.07 ms** | **3.05 ms** | **+50 %** |
| **XA** | **1024×1024** | **1.05M** | **12.09 ms** | **7.86 ms** | **+35 %** |
| **PX** | **2459×1316** | **3.24M** | **34.80 ms** | **24.26 ms** | **+30 %** |
| **DX** | **2800×2288** | **6.41M** | **56.42 ms** | **52.79 ms** | **+6 %** |

### Kakadu encode-wall gap closure

Comparison of v7.0.0 J2KSwift vs Kakadu 8.4.1 demo on the medical corpus:

| Modality | v6.3.0 J2KSwift | v7.0.0 J2KSwift | Kakadu | v6.3 gap | v7.0 gap |
|---|---:|---:|---:|---:|---:|
| MR-small 180² | 1.0 | 1.0 | 2.8 | we win 2.8× | **we win 2.8×** |
| CT 512² | 3.3 | 3.3 | 3.6 | tie | tie |
| MR 886² | 6.07 | **3.05** | 3.7 | +1.6× behind | **we win 1.21×** ← *flipped* |
| XA 1024² | 12.09 | 7.86 | 5.1 | +2.4× behind | +1.5× behind |
| PX 2459×1316 | 34.80 | 24.26 | 11.2 | +3.1× behind | +2.2× behind |
| DX 2800×2288 | 56.42 | 52.79 | 18.9 | +3.0× behind | +2.8× behind |

**MR 886² flips from being 1.6× behind Kakadu to 1.21× ahead.** XA / PX gaps narrow materially. DX gap remains the big lever for v7.x — the v6.4.0-deferred E1.3 GPU multi-tile compute correctness + I-series GPU forward HT entropy approach C/D are still actionable in subsequent v7.x MINOR releases.

---

## What's New — opt-in (default-OFF)

No new opt-in features in v7.0.0. The opt-out env vars from v6.x carry forward, plus the new opt-out for the v7.0.0 flip:

- `J2K_HT_TILE_MODE=single` — **NEW opt-out** for v6.x byte-stability (restores v6.3.0 codestream bytes verbatim)
- `J2K_GPU_FORWARD_53=0` — force legacy CPU forward DWT path
- `J2K_GPU_INVERSE_53=0` — force legacy CPU decode path
- `J2K_GPU_HT_ENTROPY_DECODE=0` — disable GPU HT entropy on the routed GPU decode path

---

## Backward compatibility — codestream bytes change vs v6.x

**Per-fixture byte deltas** (HT-conformant lossless 5/3, M2 release):

| Modality | Shape | px | v6.3.0 bytes (single) | v7.0.0 bytes (auto) | Δ bytes | Δ % | mode picked |
|---|---|---:|---:|---:|---:|---:|---|
| MR-small | 180×180 | 32,400 | 45,224 | 45,224 | 0 | 0.000 % | single (gated) |
| CT | 512×512 | 262,144 | 436,460 | 436,460 | 0 | 0.000 % | single (gated) |
| CT | 512×512 | 262,144 | 406,187 | 406,187 | 0 | 0.000 % | single (gated) |
| **MR** | 886×886 | 784,996 | 167,728 | **169,709** | **+1,981** | **+1.18 %** | **2x2** |
| **XA** | 1024×1024 | 1,048,576 | 1,621,219 | **1,621,712** | **+493** | **+0.03 %** | **2x2** |
| **PX** | 2459×1316 | 3,236,044 | 6,431,507 | **6,453,588** | **+22,081** | **+0.34 %** | **4x4** |
| **DX** | 2800×2288 | 6,406,400 | 12,683,182 | **12,705,470** | **+22,288** | **+0.18 %** | **4x4** |

**Storage overhead is negligible** (≤1.18 % per fixture) — the byte deltas come from per-tile SOT/SOD markers (~10 bytes per tile) plus per-tile codestream-header artefacts.

### What does NOT change

- **Decoded pixel data**: byte-identical to v6.3.0 across the full corpus. DICOM consumers reading our codestreams see different bytes but **identical images**. Verified by `HTTileParityMatrixTests` (12/12 cells × OpenJPH/Grok/Kakadu/self-RT = 48 bit-exact pixel-diff cells) and `HTGPUForward53CrossCodecTests` (7/7 cells bit-exact).
- **Lossy 9/7 encoding**: out of scope per `feedback_lossless_only_v5_38.md`; routing unchanged.
- **Decoding behaviour**: unchanged. v6.x consumers can decode v7.0.0 codestreams; v7.0.0 can decode v6.x codestreams.
- **Public Swift API surface**: no removals, no signature changes. Only the default fallback value of `J2KHTTileMode.from(envValue: nil)` changed.

### What v6.x consumers should do

Three options:
1. **Accept the new bytes** — decoded image is byte-identical; storage size grows by ≤1.18 % (recommended for 99 % of consumers)
2. **Pin v6.x bytes** — set `J2K_HT_TILE_MODE=single` env var. Restores v6.3.0 codestream bytes verbatim.
3. **Hash on decoded pixels, not codestream bytes** — the recommended long-term pattern for hash-stability across J2KSwift versions

See [`CROSS_VERSION_DELTA_REPORT.md`](CROSS_VERSION_DELTA_REPORT.md) §"v6.3.0 → v7.0.0" for the full delta documentation.

---

## Cross-codec parity matrix

Fresh measurement on the v7.0.0 release-candidate commit (Apple M2, release mode). Numbers are max-abs-pixel-diff vs the original PGM; **0 = bit-exact**.

### GPU-forward path × external decoders (HTGPUForward53CrossCodecTests)

| Modality | Shape | Bytes | OpenJPH 0.27.0 | Grok 20.3.0 | Kakadu 8.4.1 |
|---|---|---:|---:|---:|---:|
| MR-small | 180×180 | 45,224 | 0 | 0 | 0 |
| CT | 512×512 | 436,460 | 0 | 0 | 0 |
| CT | 512×512 | 406,187 | 0 | 0 | 0 |
| MR | 886×886 | 169,709 | 0 | 0 | 0 |
| XA | 1024×1024 | 1,621,712 | 0 | 0 | 0 |
| PX | 2459×1316 | 6,453,588 | 0 | 0 | 0 |
| DX | 2800×2288 | 12,705,470 | 0 | 0 | 0 |

**21 / 21 cells bit-exact** on the v7.0.0 default-routed codestream bytes (which are now multi-tile for ≥500K-px fixtures). External decoders correctly reconstruct the original pixels.

### Multi-tile parity matrix (HTTileParityMatrixTests)

| Modality | Shape | Mode | Parity | Self RT | OpenJPH | Grok | Kakadu |
|---|---|---|---|---:|---:|---:|---:|
| MR | 886×886 | 2x2 / 4x4 / strips4 | mixed | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| XA | 1024×1024 | 2x2 / 4x4 / strips4 | all-even | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| PX | 2459×1316 | 2x2 / 4x4 / strips4 | mixed | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |
| DX | 2800×2288 | 2x2 / 4x4 / strips4 | all-even | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 | 0 / 0 / 0 |

**48 / 48 cells max-abs-pixel-diff = 0** (12 multi-tile combinations × OpenJPH/Grok/Kakadu + self-roundtrip).

---

## Medical-corpus benchmarks

### Encode wall-time (Apple M2, release, median of 5)

`HTMultiTilePerfProbeTests.testMultiTilePerfProbeOnLargeFixtures` baseline showing the auto-routed wins:

| Modality | Shape | px | single ms | best multi-tile ms | mode | Δ |
|---|---|---:|---:|---:|---|---:|
| MR | 886×886 | 785K | 6.07 | **3.05** | 2x2 | +50 % |
| XA | 1024×1024 | 1.05M | 12.09 | **7.86** | 2x2 | +35 % |
| PX | 2459×1316 | 3.24M | 34.80 | **24.26** | 4x4 | +30 % |
| DX | 2800×2288 | 6.41M | 56.42 | **52.79** | 4x4 | +6 % |

DX's smaller relative gain reflects content-imbalance across tiles (max-tile dominates the parallel wall, per [`docs/V6_4_0_G1_0_INVESTIGATION.md`](docs/V6_4_0_G1_0_INVESTIGATION.md) finding). Future v7.x work targets this via E1.3 GPU multi-tile compute and the I-series GPU forward HT entropy approach C/D from the deferred v6.4.0 plan.

### Decode wall-time — unchanged from v6.3.0

v7.0.0 changes encode routing only. Single-tile decode wins from v6.2.0 (DX +46.2 % iDWT, +40.5 % iDWT + GPU HT entropy) carry forward unchanged. Multi-tile decode routing widening from v6.3.0 E1.2 with CPU per-tile compute fallback also carries forward; E1.3 GPU per-tile compute correctness is deferred to a future v7.x release.

---

## Test Suite Results (v7.0.0 release-candidate, 2026-05-07)

Mandatory pre-release commit gate, release mode (Apple M2 / Sonoma 14.0):

| Suite | Tests | Passed | Failed | Notes |
|---|---:|---:|---:|---|
| J2KMedicalCorpusEncodePerformanceTests | 2 | 2 | 0 | release exit 0 |
| J2KMedicalCorpusPerformanceTests | 2 | 2 | 0 | release exit 0 |
| J2KStrictCrossCodecValidationTests | 3 | 3 | 0 | OpenJPH / OpenJPEG / Grok all decode strict-truncated |
| HTTileParityMatrixTests | 36 | 36 | 0 | 12 multi-tile cells × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| HTGPUForward53CrossCodecTests | 21 | 21 | 0 | 7 fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| HTMultiTilePerfProbeTests | 1 | 1 | 0 | wall-time A/B baseline captured |
| GPUForward53DefaultOnTests | 4 | 4 | 0 | bit-exact + PX route assertion + A/B |

All v6.x validation suites continue to pass unchanged.

---

## API surface — additions only, no breaks

All v6.3.0 public Swift API preserved. **Default behaviour change in exactly one routing**: HT-conformant lossless 5/3 encodes with no `J2K_HT_TILE_MODE` env var route through `.auto` instead of `.single`. Pixels unchanged; codestream bytes change per the table above.

No public Swift API additions, removals, or signature changes.

`J2KHTTileMode.from(envValue:)` keeps the same signature; only the default fallback changed:

```swift
// v6.x:
guard let v = envValue?.lowercased() else { return .single }

// v7.0.0:
guard let v = envValue?.lowercased() else { return .auto }
```

---

## Known limitations

- **DX 2800×2288 multi-tile gain is small (+6 %)** — content-imbalance across the 4×4 tiles caps the parallel speedup. Per [`docs/V6_4_0_G1_0_INVESTIGATION.md`](docs/V6_4_0_G1_0_INVESTIGATION.md), tile times span 32 % within a single fixture; the slowest tile dominates the wall. Future v7.x work via E1.3 GPU multi-tile compute correctness + GPU forward DWT in the multi-tile per-tile path can re-attack DX.
- **Multi-tile decode per-tile GPU compute is on CPU** — v6.3.0 E1.2 routed multi-tile decode through the GPU dispatch infrastructure but per-tile entropy + IDWT compute fall back to CPU pending Defects A + B fix. v7.x deferred items.
- **Lossy 9/7 encoding unchanged** — out of scope per `feedback_lossless_only_v5_38.md` (parked 2026-05-05). v7.0.0 does not flip the lossy default.
- **Threshold for GPU forward 5/3 INT (3 MP from v6.3.0 E2)** is an Apple M2 number. Newer Apple Silicon may shift the crossover; the threshold is `var`-overridable via `EncoderPipeline._gpuForward53PixelThreshold`.

---

## Reproducing the headline numbers

```bash
# Mandatory pre-release gate (release mode)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrices (multi-tile 12/12 + GPU-forward 7/7)
swift test -c release \
  --filter 'HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures|HTGPUForward53CrossCodecTests'

# Multi-tile encode A/B (single vs multi-tile per-mode)
swift test -c release --filter HTMultiTilePerfProbeTests

# E2 lossless 5/3 wall-time A/B (encoder GPU/CPU forward DWT, post-v6.3.0 threshold)
swift test -c release \
  --filter GPUForward53DefaultOnTests/testDefaultOn_WallTimeAB_AcrossCorpus

# Pin v6.x byte-stable mode (set env var first)
J2K_HT_TILE_MODE=single swift test -c release --filter HTGPUForward53CrossCodecTests
```

---

## Companion documents

- [`RELEASING.md`](RELEASING.md) — branching model + release flow + SemVer rules (this release follows the §"Codestream bytes are part of the public contract" MAJOR-bump rule)
- [`CROSS_VERSION_DELTA_REPORT.md`](CROSS_VERSION_DELTA_REPORT.md) §"v6.3.0 → v7.0.0" — codestream byte-delta documentation
- [`docs/V6_4_0_PLAN.md`](docs/V6_4_0_PLAN.md) — v6.4.0 Kakadu-deadline-driven plan that surfaced the v7.0.0 SemVer Path 2 decision
- [`docs/V6_4_0_G1_0_INVESTIGATION.md`](docs/V6_4_0_G1_0_INVESTIGATION.md) — audit revealing v6-alpha3 step 9 already shipped per-tile parallelism
- [`docs/V6_4_0_G1_2_INVESTIGATION.md`](docs/V6_4_0_G1_2_INVESTIGATION.md) — SemVer decision tree for the default flip
- [`RELEASE_NOTES_v6.3.0.md`](RELEASE_NOTES_v6.3.0.md) — multi-tile decode correctness + PX encode +10.9 % (v6.3.0 baseline this release builds on)
