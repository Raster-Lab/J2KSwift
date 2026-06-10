# J2KSwift v10.6.0 — true ROI decode (entropy-skip for off-region code-blocks)

**Release date:** 2026-05-20
**Base:** `v10.5.0`
**Type:** MINOR per RELEASING.md — new working behaviour for the `decodeRegion` `.direct` strategy; codestream bytes byte-identical to v10.5.0 on the default `decode()` path; decoder-only change, no public signature change.

## Summary

v10.6.0 delivers the **ROI half** of the partial-decode arc. v10.4.0 +
v10.5.0 shipped the *resolution* half (`decodeResolution` — 3-8×
thumbnail decode). ROI decode — extracting a spatial sub-rectangle of a
large image, e.g. DICOM viewport zoom on a 16 MP mammogram — was still a
`notImplemented` stub: `decodeRegion` supported only `.fullImageExtraction`
(decode the whole image, then crop).

`decodeRegion` with the `.direct` strategy now does **true ROI decode**:
a spatial code-block filter drops every code-block whose inverse-DWT
footprint cannot influence an in-region pixel, skipping the dominant
entropy decode stage for them. The inverse DWT still runs full-tile, then
the result is cropped to the region.

This release also fixes a latent bug: the `extractRegion` crop helper was
8-bit-only, so `decodeRegion(.fullImageExtraction)` had been silently
corrupting output for every 16-bit medical image.

## Benchmark — ROI decode A/B

`V10_11_DecodeRegionDirectTests` (M2 release, DX 2800×2288, 256² centre
region, 7 trials):

| Strategy | Wall | Note |
|---|---:|---|
| `.fullImageExtraction` | 46.05 ms | full decode + crop |
| `.direct` | **33.21 ms** | entropy-skip for off-region blocks |
| **Δ** | **12.83 ms (1.39×)** | |

The win is the entropy stage skipped for off-region code-blocks. The
inverse DWT runs full-tile regardless, which bounds the speedup — a
Stage 2 iDWT / precinct truncation (future work) would lift it further,
the same way v10.5.0 Stage B.2 lifted the resolution win past B.1.

## What's New — true ROI decode

### ROI spatial code-block filter (`extractTileData`)

`DecoderPipeline` gains `regionOfInterest: J2KRegion?` (full-image pixel
coordinates) and `extractTileData` a matching parameter. After parsing
all code-blocks for a tile, blocks whose inverse-DWT spatial footprint
does not overlap the region are dropped — entropy decode is skipped for
them. This mirrors the v10.5.0 Stage B.1 resolution filter; the keep
predicate is spatial instead of level-based.

A code-block at decomposition depth `d` holds band samples that upsample
to full-image pixels at scale `2^d`. Its footprint is the band rect
scaled by `2^d`, anchored at the tile origin, expanded by a conservative
synthesis-filter halo (`8 · 2^d` per side — a generous bound on the
`ρ · 2^d` inverse-DWT influence radius). The LL band is always kept.
Because every block influencing an in-region pixel is retained, the
cropped output is bit-identical to a full decode + crop.

### `extractRegion` 16-bit fix

`extractRegion` allocated `width × height` bytes and indexed component
data one byte per pixel — correct only for 8-bit images. Every medical
fixture is 16-bit, so `decodeRegion(.fullImageExtraction)` produced
half-width, byte-misaligned output. The fix copies `bytesPerSample`
bytes per pixel and preserves `sampleByteOrder`.

### Routing

ROI decode works on both the CPU and GPU decode paths — the filter runs
at `extractTileData` (the parse stage common to all paths), and the
inverse DWT is unaffected (it simply transforms a tile whose off-region
coefficients are zero). No path is forced.

## API

`decodeRegion(_:options:)` (async, unchanged signature):

```swift
let decoder = J2KDecoder()
let region = J2KRegion(x: 1024, y: 1024, width: 512, height: 512)

// True ROI decode — entropy-skip for off-region code-blocks.
let roi = try await decoder.decodeRegion(
    data, options: J2KROIDecodingOptions(region: region, strategy: .direct))

// Decode-everything-then-crop — no entropy saving, but useful when
// several regions will be pulled from one decode.
let roi2 = try await decoder.decodeRegion(
    data, options: J2KROIDecodingOptions(region: region,
                                         strategy: .fullImageExtraction))
```

## Backward compatibility

- **Codestream bytes byte-identical to v10.5.0** on the default `decode()` path.
- `decode()`, `decodeGPU()`, `decodeWithGPUHT()`, `decodeResolution()` behaviour unchanged.
- No public Swift API signature change — `decodeRegion` was already `async throws`.
- ROI decode is opt-in — callers explicitly choose the `.direct` strategy.
- `.fullImageExtraction` now produces **correct** output for 16-bit images
  (it was previously corrupt — see the `extractRegion` fix).

## Correctness

`.direct` ROI decode keeps every code-block whose inverse-DWT footprint
overlaps the region, so the cropped output is the mathematically exact
region — identical to a full decode followed by the same crop, no
approximation.

`V10_11_DecodeRegionDirectTests` (4/4 PASS):
- `.direct` bit-identical to full-decode-then-crop — CT 512² (single-tile)
- `.direct` bit-identical to full-decode-then-crop — DX 2800×2288 (single-tile)
- `.direct` bit-identical to full-decode-then-crop — MG 3518×4784 (2×2 multi-tile)
- entropy-skip A/B (`.direct` not slower than `.fullImageExtraction`)

Each fixture is verified at 7 region positions — full, four corners,
horizontal / vertical thin strips, a 32² tiny region — 21 `.direct`
decodes total, all byte-identical to the reference crop. Centre / strip
regions cross tile boundaries on the multi-tile MG fixture.

## Cross-codec parity

`J2KStrictCrossCodecValidationTests`: 3/3 PASS — full-decode behaviour
preserved against OpenJPH / Grok / Kakadu (ROI decode is an opt-in path;
full decode is unaffected).

## Mandatory commit gate

7/7 PASS:
- `J2KMedicalCorpusEncodePerformanceTests` 2/2
- `J2KMedicalCorpusPerformanceTests` 2/2
- `J2KStrictCrossCodecValidationTests` 3/3

## Cross-codec warm benchmark (regression check)

v10.6.0 does not change the full `decode()` / `encode()` path, so the
canonical warm cross-codec benchmark is run here as a **regression
check** — confirming the additive ROI work did not perturb the default
decode path.

`cross_codec_warm_bench.py --in-proc`, M2, medical-real corpus (mid
fixtures), median ms. Full results: `Documentation/Benchmarks/data/benchmark-results-arm64-v10.6.0-20260520.json`.

Decode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.27 | 9.42 | 9.44 | 4.44 |
| MR 512² | 2.31 | 9.43 | 9.45 | 4.47 |
| XA 1024² | 6.40 | 19.47 | 9.47 | 9.47 |
| PX 2793×1316 | 27.85 | 76.67 | 19.68 | 19.64 |
| DX 2800×2288 | 44.95 | 131.78 | 39.79 | 39.71 |
| MG 3518×4784 | 82.59 | 131.61 | 74.98 | 76.80 |

Encode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.14 | 9.46 | 9.48 | 4.48 |
| MR 512² | 2.00 | 9.47 | 9.45 | 4.46 |
| XA 1024² | 4.92 | 19.53 | 19.56 | 9.52 |
| PX 2793×1316 | 16.41 | 75.05 | 39.86 | 9.51 |
| DX 2800×2288 | 34.29 | 131.44 | 74.04 | 19.73 |
| MG 3518×4784 | 38.31 | 131.77 | 130.56 | 38.78 |

The ROI spatial filter activates only when `regionOfInterest` is set
(`decodeRegion(.direct)`); the full `decode()` / `encode()` path is
structurally untouched. Walls are consistent with v10.5.0 — no
regression. Across the full 38-fixture run, J2KSwift+inproc wins
(median ≤ every measured codec) on 27/38 PGM decode and 30/38 PGM
encode fixtures.

## Migration notes

- **No action required** for `decode()` consumers — full decode unchanged.
- DICOM viewport-zoom integrations should switch from `decode()` + manual
  crop to `decodeRegion(.direct)` for the entropy-skip on large images.
- Callers already using `decodeRegion(.fullImageExtraction)` on 16-bit
  images were receiving corrupt output and should re-run — the crop is
  now correct.

## Known limitations / future work

- **iDWT still runs full-tile** for ROI decode. Off-region code-blocks
  are dropped (their coefficients stay zero) but the inverse DWT is not
  truncated, so the speedup is bounded by the entropy stage's share of
  the wall. A Stage 2 — iDWT / precinct truncation around the region —
  would convert this into a much larger win, the way v10.5.0 B.2 did for
  resolution decode.
- `decodeQuality` (quality-layer progressive decode) remains
  `notImplemented`. The decoder's packet loop is hardcoded single-layer
  (LRCP iterates resolution × component × precinct only) and the medical
  archive corpus is single-layer lossless, so quality-layer truncation
  has no test surface and little product value here — it is a separate
  arc, not a half-measure bolted onto this release.
- `decodePartial` (the combined resolution + region + components umbrella)
  remains `notImplemented`; `decodeResolution` and `decodeRegion` cover
  the individual axes.

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `V10_11_DecodeRegionDirectTests` | 4 (21 ROI decodes + A/B) | PASS |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |

## Companion documents

- [`Documentation/research/V10_11_ROI_DECODE.md`](../research/V10_11_ROI_DECODE.md) — ROI decode design + validation
- [`Documentation/releases/RELEASE_NOTES_v10.5.0.md`](RELEASE_NOTES_v10.5.0.md) — partial-resolution decode
- [`Documentation/releases/RELEASE_NOTES_v10.4.0.md`](RELEASE_NOTES_v10.4.0.md) — partial-resolution decode Phase 1
