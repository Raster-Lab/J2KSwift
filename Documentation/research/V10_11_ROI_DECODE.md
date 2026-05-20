# v10.11-research — true ROI decode (`decodeRegion .direct`)

**Branch:** `v10.11-research`
**Status:** implemented + validated; v10.6.0 release candidate
**Date:** 2026-05-20

## Context

Arc **C** ("partial-resolution / ROI decode") had two halves. v10.4.0 +
v10.5.0 delivered the **resolution** half: `decodeResolution` filters
code-blocks by decomposition level (Stage B.1) and truncates the inverse
DWT (Stage B.2), giving 3-8× thumbnail decode. The **ROI** half —
decoding a spatial sub-rectangle of a large image (DICOM viewport zoom on
a 16 MP mammogram) — was still a `notImplemented` stub: `decodeRegion`
supported only the `.fullImageExtraction` strategy (decode everything,
then crop).

v10.11 implements the `.direct` strategy: **true ROI decode** — skip the
dominant entropy decode stage for every code-block that cannot influence
an in-region pixel.

## Design — code-block spatial filter

This mirrors the v10.5.0 Stage B.1 resolution filter exactly, but the
keep predicate is spatial instead of level-based.

`DecoderPipeline` gains `regionOfInterest: J2KRegion?` (full-image pixel
coordinates). `extractTileData` gains a matching `regionOfInterest`
parameter; after parsing all code-blocks for the tile (parsing keeps the
bit-reader in sync) it drops every block whose inverse-DWT spatial
footprint does not overlap the region.

### Footprint geometry

A `CodeBlockInfo` carries `level` (decomposition depth; `0` = LL),
`subband`, and a tile-band-relative rect `(x, y, width, height)` in
**subband-sample** coordinates — the same coordinates the dequant / iDWT
scatter uses to place the block into its subband buffer.

A subband at decomposition depth `d` holds samples that upsample to
full-image pixels at scale `2^d` (the LL band sits at depth `levels`).
A band sample at 0-based subband index `s` reconstructs to image pixel
`≈ tileOrigin + s · 2^d`. So a block's image-space footprint is its band
rect scaled by `2^d`, anchored at the tile origin:

```
scale = 1 << d
fpX0 = tileOriginX + block.x              * scale - halo
fpX1 = tileOriginX + (block.x+block.width)* scale + halo
fpY0 = tileOriginY + block.y              * scale - halo
fpY1 = tileOriginY + (block.y+block.height)*scale + halo
keep iff [fpX0,fpX1) overlaps the region in x AND [fpY0,fpY1) in y
```

The LL band (`level == 0`) feeds every resolution level and is always
kept — cheap and provably safe (it is the smallest band).

### Synthesis-filter halo

One band sample does not reconstruct to exactly `2^d` pixels: the inverse
DWT spreads its influence by the synthesis filter's support at every
level. The influence radius is bounded by `ρ · 2^d` for filter half-width
`ρ` (`ρ ≈ 2` for the reversible 5/3, `≈ 4` for the 9/7). The filter uses
`halo = 8 · 2^d` per side — a deliberately generous bound (4× the 5/3
requirement). Over-keeping costs a little entropy work; under-keeping
would corrupt the region, so the filter errs toward keeping. The
bit-exact validation below is the backstop that proves the halo is
sufficient.

### Why the inverse DWT still runs full-tile

`.direct` does **not** truncate the iDWT. Off-region code-blocks are
simply dropped, so their coefficients stay zero; the full-tile iDWT then
reconstructs a full-dimension image where the off-region areas are
approximate (missing detail) but the **in-region pixels are exact** —
every block influencing them was retained. `decodeRegion` crops the
full-dimension image to the region afterwards.

This is the same honest staging the resolution arc used: v10.5.0 B.1
shipped entropy-skip with the iDWT still running all levels; B.2 later
truncated it. ROI iDWT / precinct truncation is the analogous Stage 2
(future work) — it would convert the modest entropy-only win into the
large win seen for resolution decode.

## `extractRegion` 16-bit fix

The crop helper `extractRegion` was 8-bit-only — it allocated
`region.width * region.height` bytes and indexed `component.data` by a
single byte per pixel. Every medical fixture is 16-bit, so
`decodeRegion(.fullImageExtraction)` had been silently producing
corrupt (half-width, byte-misaligned) output. The fix copies
`bytesPerSample` bytes per pixel and preserves `sampleByteOrder`. This
was a latent pre-existing bug surfaced by building an ROI validation
oracle on top of the crop.

## Validation — `V10_11_DecodeRegionDirectTests`

Correctness contract: a cropped `.direct` decode must be **bit-identical**
to a full `decode()` followed by the same crop.

| Fixture | Tiling | Regions | Result |
|---|---|---|---|
| CT 512² | single-tile | 7 | bit-exact ✓ |
| DX 2800×2288 | single-tile | 7 | bit-exact ✓ |
| MG 3518×4784 | 2×2 multi-tile | 7 | bit-exact ✓ |

Each fixture is tested at 7 region positions — full, the four corners,
horizontal / vertical thin strips, and a 32² tiny region. Centre and
strip regions cross tile boundaries on the multi-tile MG fixture. All 21
`.direct` decodes are byte-identical to the reference crop, and
`.fullImageExtraction` is too (validating the 16-bit `extractRegion`
fix).

### A/B — entropy-skip win

`.direct` vs `.fullImageExtraction`, DX 2800×2288, 256² centre region,
M2 release, 7 trials:

```
.direct              33.21 ms
.fullImageExtraction 46.05 ms
Δ                    12.83 ms   (1.39×)
```

Δ 12.83 ms is well above the 3 ms acceptance threshold. The win is the
entropy stage skipped for off-region code-blocks; the iDWT (full-tile)
is unchanged, which bounds the speedup — a Stage 2 iDWT truncation would
lift it further.

## `decodeQuality` — deliberately left `notImplemented`

The third partial-decode stub, `decodeQuality` (quality-layer
progressive decode), is **not** implemented. The decoder's packet loop is
hardcoded single-layer (`"Single layer for now"` — LRCP iterates
resolution × component × precinct only), and the medical archive corpus
is single-layer lossless, so quality-layer truncation has no test
surface and little product value here. Implementing it requires
multi-layer packet parsing — a separate arc, not a half-measure bolted
onto this one.

## Public API

```swift
let decoder = J2KDecoder()
let region = J2KRegion(x: 1024, y: 1024, width: 512, height: 512)

// True ROI decode — entropy-skip for off-region code-blocks.
let roi = try await decoder.decodeRegion(
    data, options: J2KROIDecodingOptions(region: region, strategy: .direct))

// Decode-everything-then-crop — no entropy saving, useful when several
// regions will be pulled from one decode.
let roi2 = try await decoder.decodeRegion(
    data, options: J2KROIDecodingOptions(region: region,
                                         strategy: .fullImageExtraction))
```

`decode()` / `decodeGPU()` / `decodeWithGPUHT()` are untouched;
codestream bytes are byte-identical to v10.5.0. ROI decode is opt-in.
