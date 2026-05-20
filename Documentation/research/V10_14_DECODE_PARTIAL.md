# v10.14-research — `decodePartial` umbrella API

**Branch:** `v10.14-research`
**Status:** implemented + validated; v10.8.0 release candidate
**Date:** 2026-05-20

## Context

Arc C ("partial-resolution / ROI decode") exposed four public
partial-decode entry points, all originally `notImplemented` stubs:

| API | Status before v10.8.0 |
|---|---|
| `decodeResolution` | shipped — v10.4.0 + v10.5.0 (true partial-resolution decode, 3-8×) |
| `decodeRegion` | shipped — v10.6.0 + v10.7.0 (ROI entropy-skip + tile-skip) |
| `decodePartial` | **`notImplemented` stub** |
| `decodeQuality` | `notImplemented` — decoder is single-layer |

`decodePartial` is the **umbrella** API: a single call taking
`J2KPartialDecodingOptions` (`maxResolutionLevel`, `region`,
`components`, `maxLayer`, `earlyStop`). v10.8.0 implements it by
composing the capabilities the resolution and region arcs already
shipped, and adds component-subset selection.

## Design

`decodePartial(_:options:)` becomes `async throws` (was `throws` — the
same signature change `decodeResolution` took in v10.4.0; the method
was a stub so no real callers break). It:

1. **Peeks the codestream metadata** (`DecoderPipeline.peekMetadata`)
   and validates the options against the real image dimensions, level
   count, layer count and component count.

2. **Guards `maxLayer`.** The decoder's packet loop is single-layer.
   A `maxLayer` that keeps every layer (`== layers - 1`) is a harmless
   no-op; one that would *exclude* layers throws `notImplemented` —
   quality-layer truncation needs multi-layer packet decode (the
   `decodeQuality` arc, deliberately out of scope).

3. **Decodes, resolution-aware:**
   - `maxResolutionLevel` set (`< levels`) → `decodePartialResolution`
     (v10.5.0 true partial-resolution decode).
   - else `region` set → `decodeRegionDirect` (v10.6.0/v10.7.0 ROI
     decode — entropy-skip + tile-skip).
   - else → full `decode()`.

4. **Crops to `region`** when set. The region is in **full-image
   coordinates**. With no resolution reduction the crop is direct;
   when `maxResolutionLevel` is also set, the region is mapped onto
   the reduced-resolution grid (divide origin / ceil-divide extent by
   the `2^(levels-level)` factor, clamped).

5. **Selects `components`** when set — returns exactly the requested
   component indices, in the requested order.

`earlyStop` is advisory (partial decode inherently skips work) and has
no effect on the result.

`decodePartial()` with default (all-nil) options is exactly `decode()`.

## What's genuinely new vs. the single-axis APIs

- **Component selection** — `decodeResolution` / `decodeRegion` carry
  a `components` field that was never honoured. `decodePartial`
  implements it.
- **The resolution + region combination** — decode a sub-region at a
  reduced resolution in one call.
- A single umbrella entry point for downstream consumers (DICOM
  thumbnail + viewport workflows) instead of choosing between
  `decodeResolution` and `decodeRegion`.

No new codec hot-path work — `decodePartial` reuses the shipped
v10.5.0 (3-8×) / v10.6.0 / v10.7.0 perf wins; the codestream and the
default `decode()` path are untouched.

## Validation — `V10_14_DecodePartialTests` (7/7 PASS)

`decodePartial` is asserted **consistent with the single-axis API it
delegates to**:

- `decodePartial(maxResolutionLevel:)` byte-identical to
  `decodeResolution(level:)` — CT 512², levels 0 / 2 / 4.
- `decodePartial(region:)` byte-identical to `decodeRegion(.direct)` —
  DX 2800×2288.
- `decodePartial()` (empty options) byte-identical to `decode()`.
- `decodePartial(maxResolutionLevel:region:)` — output dimensions =
  region mapped onto the reduced grid; data = `decodeResolution` then
  the same crop.
- component selection — grayscale `[0]` equals `decode()`'s component
  0; synthetic 3-component `[2, 0]` returns exactly components 2 and 0
  of a full decode, in that order.
- `maxLayer: 0` on a single-layer codestream is a no-op equal to
  `decode()`.

Mandatory commit gate 7/7 PASS.

## `decodeQuality` — still `notImplemented`

The fourth stub, `decodeQuality` (quality-layer progressive decode),
remains unimplemented. The decoder's LRCP packet loop is hardcoded
single-layer and the medical archive corpus is single-layer lossless,
so quality-layer truncation has no test surface and little product
value — a separate arc, not bundled here.
