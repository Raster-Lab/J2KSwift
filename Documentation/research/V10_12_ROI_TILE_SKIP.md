# v10.12-research — ROI decode Stage 2 (tile-granular iDWT skip)

**Branch:** `v10.12-research`
**Status:** implemented + validated; v10.7.0 release candidate
**Date:** 2026-05-20

## Context

v10.6.0 shipped **ROI decode Stage 1**: `decodeRegion(.direct)` filters
code-blocks spatially in `extractTileData`, skipping the entropy decode
stage for blocks whose inverse-DWT footprint cannot influence an
in-region pixel. But the inverse DWT still ran **full-tile** — the
honest limitation called out in the v10.6.0 release notes.

Stage 2 attacks the iDWT cost. The general solution — a windowed
inverse DWT that reconstructs only the region's region-of-support — is
a rewrite of the parity-sensitive `inverseTransformMultiLevel53` hot
path and a genuine multi-session effort (it is **Stage 3**, future
work). Stage 2 takes the provably-correct, high-value subset:
**tile-granular skip**.

## Design — tile-granular skip

JPEG 2000 tiles decode **independently**: each tile is entropy-decoded,
dequantised and inverse-transformed on its own, and no inverse-DWT
synthesis halo crosses a tile boundary. Therefore a tile that lies
entirely outside the requested region contributes **nothing** to any
in-region pixel — every pixel it would produce is cropped away by
`decodeRegion`.

`decodeTilePayload` and `decodeTilePayloadGPU` (the two per-tile decode
entry points that every multi-tile orchestrator funnels through) gain
an early check: when `regionOfInterest` is set and the tile's image
rectangle does not overlap the region, the function returns a
correctly-shaped zero `DecodedTile` immediately — skipping `extractTileData`,
`applyEntropyDecoding`, `applyDequantization`, `applyInverseWaveletTransform`,
the inverse colour transform and the DC level shift for that tile.

```
overlap iff  tileX < roi.x+roi.w  &&  tileX+tileW > roi.x
          && tileY < roi.y+roi.h  &&  tileY+tileH > roi.y
skip the tile iff not overlap
```

The half-open interval logic is exact: a region starting exactly on a
tile's right/bottom edge does not overlap that tile.

## Marquee case — MG mammography

The 16.8 MP MG fixture is encoded as **2×2 tiles** (the encoder's
≥12 MP / min-dim ≥2400 override). A viewport-zoom ROI within one
quadrant skips the other **three** tiles wholesale — roughly three
quarters of the entire decode (entropy + dequant + the iDWT-dominated
wall + colour + DC).

This is the highest-value ROI case: DICOM viewport zoom on a large
mammogram is exactly "decode a small region of a 16 MP image".

## Scope — what Stage 2 does and does not cover

- **Multi-tile fixtures** (MG, 2×2): off-region tiles skipped entirely.
  The tile(s) the region *does* touch are still decoded in full (Stage 1
  entropy-skip applies within them; their iDWT runs full-tile).
- **Single-tile fixtures** (CT, MR, XA, PX, DX in the medical corpus):
  there is exactly one tile and the region is always inside it, so
  tile-skip is a no-op. These keep the v10.6.0 Stage 1 entropy-skip
  win. Sub-tile iDWT truncation for them is **Stage 3** (windowed
  inverse DWT — a dedicated ROI transform path, future work).

## Validation — `V10_12_ROITileSkipTests`

Correctness contract is unchanged from Stage 1: a cropped `.direct`
decode must be **bit-identical** to a full `decode()` followed by the
same crop. Tile-skip cannot change the result — it only drops tiles
whose pixels are cropped away — and the bit-exact oracle proves it.

- `testROITileSkip_bitExact_MG` — MG 3518×4784, 6 regions placed by
  quadrant to exercise 1-tile / 2-tile / 4-tile coverage; `.direct`
  bit-identical to the full-decode crop in every case.
- `testROITileSkip_AB_MG` — A/B, 256² corner region (3 of 4 tiles
  skipped): `.direct` vs `.fullImageExtraction`.
- `V10_11_DecodeRegionDirectTests` re-run on this branch — the MG
  multi-tile bit-exact suite re-validates with tile-skip active.

### Results (M2 release)

`V10_12_ROITileSkipTests` 2/2 PASS, `V10_11_DecodeRegionDirectTests`
4/4 PASS (re-run on this branch — MG multi-tile bit-exact preserved).

- **bit-exact** — MG 3518×4784, 6 quadrant-placed regions (1-tile,
  2-tile, 4-tile coverage): every `.direct` decode byte-identical to
  the full-decode crop.
- **A/B** — MG 3518×4784, 256² corner region (3 of 4 tiles skipped),
  7 trials:

  ```
  .direct              49.32 ms
  .fullImageExtraction  84.70 ms
  Δ                    35.38 ms   (1.72×)
  ```

  The win is 1.72×, not ~4×, because the four MG tiles already decode
  **concurrently** (`withThrowingTaskGroup`). The full-decode wall is
  bounded by the slowest tile plus core contention from four tiles
  each spawning internal row-parallel work — not the sum of four tile
  walls. Tile-skip removes three tiles' worth of CPU work and the
  contention; the surviving tile then gets the whole machine. Δ is
  35.38 ms, an order of magnitude above the 3 ms acceptance threshold.

## Public API

Unchanged from v10.6.0 — tile-skip is an internal optimisation of the
`.direct` strategy:

```swift
let roi = try await decoder.decodeRegion(
    data, options: J2KROIDecodingOptions(region: region, strategy: .direct))
```

`decode()` / `decodeGPU()` / `decodeWithGPUHT()` / `decodeResolution()`
are untouched; codestream bytes are byte-identical to v10.6.0.
