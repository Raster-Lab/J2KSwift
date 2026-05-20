# J2KSwift v10.7.0 — ROI decode Stage 2 (tile-granular skip)

**Release date:** 2026-05-20
**Base:** `v10.6.0`
**Type:** MINOR per RELEASING.md — internal optimisation of the `decodeRegion` `.direct` strategy; codestream bytes byte-identical to v10.6.0 on the default `decode()` path; decoder-only change, no public signature change.

## Summary

v10.6.0 shipped **ROI decode Stage 1** — `decodeRegion(.direct)` skips
the entropy decode stage for code-blocks outside the requested region,
but the inverse DWT still ran full-tile.

v10.7.0 ships **Stage 2 — tile-granular skip**. JPEG 2000 tiles decode
independently (no inverse-DWT halo crosses a tile boundary), so a tile
lying entirely outside the region contributes nothing to any in-region
pixel. `decodeRegion(.direct)` now skips the **entire decode** —
entropy, dequantisation, inverse DWT, inverse colour transform and DC
level shift — for every such tile.

The marquee case is the 16.8 MP MG mammography fixture, which the
encoder lays out as **2×2 tiles**: a viewport-zoom ROI within one
quadrant skips the other three tiles wholesale.

## Benchmark — ROI tile-skip A/B

`V10_12_ROITileSkipTests` (M2 release, MG 3518×4784, 256² corner region,
3 of 4 tiles skipped, 7 trials):

| Strategy | Wall | Note |
|---|---:|---|
| `.fullImageExtraction` | 84.70 ms | full 4-tile decode + crop |
| `.direct` | **49.32 ms** | 3 of 4 tiles skipped |
| **Δ** | **35.38 ms (1.72×)** | |

The win is 1.72×, not ~4×, because the four MG tiles already decode
**concurrently** — the full-decode wall is bounded by the slowest tile
plus core contention, not the sum of four tile walls. Tile-skip removes
three tiles' CPU work and the contention; the surviving tile then gets
the whole machine. Δ 35.38 ms is an order of magnitude above the 3 ms
acceptance threshold.

## What's New — tile-granular skip

`decodeTilePayload` and `decodeTilePayloadGPU` (the two per-tile decode
entry points every multi-tile orchestrator funnels through) gain an
early ROI check. When `regionOfInterest` is set and the tile's image
rectangle does not overlap the region, the function returns a
correctly-shaped zero `DecodedTile` immediately:

```
overlap iff  tileX < roi.x+roi.w  &&  tileX+tileW > roi.x
          && tileY < roi.y+roi.h  &&  tileY+tileH > roi.y
```

The half-open interval logic is exact — a region starting on a tile's
right/bottom edge does not overlap that tile. Both the CPU and GPU
per-tile paths are covered.

## Scope

- **Multi-tile fixtures** (MG, 2×2 tiles) — off-region tiles skipped
  entirely. The tile(s) the region touches are still decoded fully,
  with v10.6.0 Stage 1 entropy-skip applying within them.
- **Single-tile fixtures** (CT, MR, XA, PX, DX in the medical corpus)
  — exactly one tile, always overlapping the region, so tile-skip is a
  no-op. These keep the v10.6.0 Stage 1 entropy-skip win unchanged.
  Sub-tile inverse-DWT truncation for them is **Stage 3** (a windowed
  ROI transform — future work; see Known limitations).

## API

Unchanged from v10.6.0 — tile-skip is an internal optimisation of the
`.direct` strategy:

```swift
let decoder = J2KDecoder()
let region = J2KRegion(x: 1024, y: 1024, width: 512, height: 512)
let roi = try await decoder.decodeRegion(
    data, options: J2KROIDecodingOptions(region: region, strategy: .direct))
```

## Backward compatibility

- **Codestream bytes byte-identical to v10.6.0** on the default `decode()` path.
- `decode()`, `decodeGPU()`, `decodeWithGPUHT()`, `decodeResolution()` behaviour unchanged.
- No public Swift API signature change.
- ROI decode is opt-in — callers explicitly choose the `.direct` strategy.

## Correctness

A skipped tile produces only off-region pixels, which `decodeRegion`
crops away. Tiles decode independently per ISO/IEC 15444-1 — no
inverse-DWT synthesis halo crosses a tile boundary — so skipping a
fully-off-region tile cannot affect any in-region pixel.

`V10_12_ROITileSkipTests` (2/2 PASS):
- `.direct` bit-identical to full-decode crop — MG 3518×4784, 6 regions
  placed by quadrant for 1-tile / 2-tile / 4-tile coverage
- tile-skip A/B (`.direct` faster than `.fullImageExtraction`)

`V10_11_DecodeRegionDirectTests` (4/4 PASS, re-run) — the MG multi-tile
bit-exact suite re-validates with tile-skip active; CT / DX single-tile
ROI unchanged.

## Cross-codec parity

`J2KStrictCrossCodecValidationTests`: 3/3 PASS — full-decode behaviour
preserved against OpenJPH / Grok / Kakadu.

## Mandatory commit gate

7/7 PASS:
- `J2KMedicalCorpusEncodePerformanceTests` 2/2
- `J2KMedicalCorpusPerformanceTests` 2/2
- `J2KStrictCrossCodecValidationTests` 3/3

## Cross-codec warm benchmark (regression check)

v10.7.0 does not change the full `decode()` / `encode()` path — the
tile-skip activates only when `regionOfInterest` is set. The canonical
warm cross-codec benchmark is run as a **regression check**.

`cross_codec_warm_bench.py --in-proc`, M2, medical-real corpus (mid
fixtures), median ms. Full results: `benchmark-results-arm64-v10.7.0-20260520.json`.

Decode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.34 | 11.22 | 11.26 | 5.24 |
| MR 512² | 2.22 | 11.24 | 11.24 | 5.23 |
| XA 1024² | 6.53 | 23.21 | 11.30 | 11.25 |
| PX 2793×1316 | 27.52 | 47.44 | 23.47 | 22.20 |
| DX 2800×2288 | 44.89 | 86.43 | 47.58 | 44.67 |
| MG 3518×4784 | 81.04 | 143.09 | 47.61 | 86.11 |

Encode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.06 | 11.22 | 11.24 | 5.23 |
| MR 512² | 2.02 | 11.24 | 11.26 | 5.23 |
| XA 1024² | 4.80 | 21.93 | 21.67 | 5.24 |
| PX 2793×1316 | 16.11 | 82.18 | 47.41 | 11.32 |
| DX 2800×2288 | 34.19 | 148.68 | 46.51 | 23.45 |
| MG 3518×4784 | 39.49 | 141.51 | 88.88 | 23.52 |

Decode/encode walls are consistent with v10.6.0 (within measurement
noise) — no regression. The tile-skip activates only on the `.direct`
ROI path; the full `decode()` / `encode()` path is structurally
untouched. Across the full 38-fixture run, J2KSwift+inproc wins
(median ≤ every measured codec) on 26/38 PGM decode and 30/38 PGM
encode fixtures.

## Migration notes

- **No action required** for `decode()` consumers — full decode unchanged.
- DICOM viewport-zoom integrations on large mammograms (2×2-tiled)
  benefit automatically — no API change from v10.6.0.

## Known limitations / future work

- **Stage 3 — windowed inverse DWT.** Single-tile fixtures, and the
  tile(s) a multi-tile region *does* touch, still run the inverse DWT
  full-tile. A windowed ROI transform that reconstructs only the
  region's region-of-support would extend the win to single-tile
  images (CT / DX / PX / MR) and shrink the touched-tile cost. It is a
  rewrite of the parity-sensitive `inverseTransformMultiLevel53` hot
  path — a dedicated, well-scoped future arc.
- `decodeQuality` (quality-layer progressive decode) remains
  `notImplemented` — the decoder packet loop is hardcoded single-layer.
- `decodePartial` (the combined resolution + region + components
  umbrella) remains `notImplemented`.

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `V10_12_ROITileSkipTests` | 2 | PASS |
| `V10_11_DecodeRegionDirectTests` | 4 | PASS |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |

## Companion documents

- [`Documentation/research/V10_12_ROI_TILE_SKIP.md`](../research/V10_12_ROI_TILE_SKIP.md) — Stage 2 design + validation
- [`Documentation/releases/RELEASE_NOTES_v10.6.0.md`](RELEASE_NOTES_v10.6.0.md) — ROI decode Stage 1
- [`Documentation/releases/RELEASE_NOTES_v10.5.0.md`](RELEASE_NOTES_v10.5.0.md) — partial-resolution decode
