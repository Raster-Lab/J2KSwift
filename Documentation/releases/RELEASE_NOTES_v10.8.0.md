# J2KSwift v10.8.0 — `decodePartial` umbrella API (combined partial decode)

**Release date:** 2026-05-20
**Base:** `v10.7.0`
**Type:** MINOR per RELEASING.md — `decodePartial` was a `notImplemented` stub and now works; the only signature change is `throws` → `async throws` (the method always threw, so there were no real callers); codestream bytes byte-identical to v10.7.0; decoder-only.

## Summary

Arc C ("partial-resolution / ROI decode") exposed four public
partial-decode entry points. Three are now implemented:

| API | Shipped |
|---|---|
| `decodeResolution` | v10.4.0 + v10.5.0 — true partial-resolution decode, 3-8× |
| `decodeRegion` | v10.6.0 + v10.7.0 — ROI decode (entropy-skip + tile-skip) |
| **`decodePartial`** | **v10.8.0 — this release** |
| `decodeQuality` | still `notImplemented` (the decoder is single-layer) |

`decodePartial(_:options:)` is the **umbrella** API: a single call
taking `J2KPartialDecodingOptions` that composes resolution-level
decode, region-of-interest decode, and component-subset selection —
and supports combining them.

## What's New — `decodePartial`

`decodePartial` takes `J2KPartialDecodingOptions` (`maxResolutionLevel`,
`region`, `components`, `maxLayer`, `earlyStop`) and:

- **`maxResolutionLevel`** → routes to the v10.5.0 true
  partial-resolution decode (code-block filter + inverse-DWT
  truncation; 3-8× faster than full decode).
- **`region`** → routes to the v10.6.0 / v10.7.0 ROI decode
  (entropy-skip for off-region code-blocks + whole-tile skip),
  interpreted in full-image pixel coordinates.
- **`components`** → returns exactly the requested image components,
  in the requested order. This is genuinely new — `decodeResolution`
  and `decodeRegion` carry a `components` field that was never
  honoured.
- **`maxResolutionLevel` + `region` together** → decodes at the
  resolution level, then crops the region mapped onto the
  reduced-resolution grid.
- **`maxLayer`** is guarded: the decoder's packet loop is single-layer,
  so a `maxLayer` that keeps every layer is a no-op, while one that
  would exclude layers throws `notImplemented`.
- **`earlyStop`** is advisory (partial decode inherently skips work)
  and has no effect on the result.

`decodePartial()` with default (all-nil) options is exactly `decode()`.

## API

```swift
let decoder = J2KDecoder()

// Thumbnail — lowest resolution level.
let thumb = try await decoder.decodePartial(
    data, options: J2KPartialDecodingOptions(maxResolutionLevel: 0))

// Region of interest, full resolution.
let roi = try await decoder.decodePartial(
    data, options: J2KPartialDecodingOptions(
        region: J2KRegion(x: 1024, y: 1024, width: 512, height: 512)))

// A single component of a multi-component image.
let oneChannel = try await decoder.decodePartial(
    data, options: J2KPartialDecodingOptions(components: [0]))

// Combined — a region at quarter resolution.
let preview = try await decoder.decodePartial(
    data, options: J2KPartialDecodingOptions(
        maxResolutionLevel: 3,
        region: J2KRegion(x: 0, y: 0, width: 2048, height: 2048)))
```

## Backward compatibility

- **Codestream bytes byte-identical to v10.7.0** on the default `decode()` path.
- `decode()`, `decodeGPU()`, `decodeWithGPUHT()`, `decodeResolution()`,
  `decodeRegion()` behaviour unchanged.
- `decodePartial`'s signature changed `throws` → `async throws`. The
  method was a `notImplemented` stub since v6.x, so there are no real
  callers; test-only callers add `await`.
- `decodePartial` reuses the perf wins already shipped in v10.5.0 /
  v10.6.0 / v10.7.0 — no new codec hot-path work, no default-path change.

## Correctness

`V10_14_DecodePartialTests` (7/7 PASS) asserts `decodePartial` is
consistent with the single-axis APIs it delegates to:

- `decodePartial(maxResolutionLevel:)` byte-identical to
  `decodeResolution(level:)` — CT 512², levels 0 / 2 / 4
- `decodePartial(region:)` byte-identical to `decodeRegion(.direct)` —
  DX 2800×2288
- `decodePartial()` (empty options) byte-identical to `decode()`
- `decodePartial(maxResolutionLevel:region:)` — output dimensions =
  region mapped onto the reduced grid; data = `decodeResolution` then
  the same crop
- component selection — grayscale `[0]` equals `decode()`'s component 0;
  synthetic 3-component `[2, 0]` returns exactly components 2 and 0 of
  a full decode, in that order
- `maxLayer: 0` on a single-layer codestream is a no-op equal to `decode()`

## Cross-codec parity

`J2KStrictCrossCodecValidationTests`: 3/3 PASS — full-decode behaviour
preserved against OpenJPH / Grok / Kakadu (`decodePartial` is an opt-in
path; full decode is unaffected).

## Mandatory commit gate

7/7 PASS:
- `J2KMedicalCorpusEncodePerformanceTests` 2/2
- `J2KMedicalCorpusPerformanceTests` 2/2
- `J2KStrictCrossCodecValidationTests` 3/3

## Cross-codec warm benchmark (regression check)

v10.8.0 does not change the full `decode()` / `encode()` path —
`decodePartial` is an opt-in API composing already-shipped partial-
decode paths. The canonical warm cross-codec benchmark is run as a
**regression check**.

`cross_codec_warm_bench.py --in-proc`, M2, medical-real corpus (mid
fixtures), median ms. Full results: `benchmark-results-arm64-v10.8.0-20260520.json`.

Decode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.26 | 11.20 | 11.23 | 5.20 |
| MR 512² | 2.30 | 11.19 | 11.23 | 5.21 |
| XA 1024² | 6.56 | 23.22 | 11.25 | 11.21 |
| PX 2793×1316 | 28.01 | 47.43 | 22.48 | 23.33 |
| DX 2800×2288 | 45.10 | 85.95 | 46.95 | 47.33 |
| MG 3518×4784 | 84.23 | 143.68 | 84.54 | 89.56 |

Encode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.16 | 11.18 | 11.22 | 5.20 |
| MR 512² | 2.15 | 11.19 | 11.22 | 5.21 |
| XA 1024² | 4.91 | 23.20 | 22.55 | 5.19 |
| PX 2793×1316 | 15.88 | 89.35 | 44.07 | 11.36 |
| DX 2800×2288 | 34.17 | 149.31 | 46.70 | 23.16 |
| MG 3518×4784 | 39.66 | 146.52 | 89.76 | 22.81 |

Decode/encode walls are consistent with v10.7.0 (within measurement
noise) — no regression. Across the full 38-fixture run, J2KSwift+inproc
wins (median ≤ every measured codec) on 30/38 PGM decode and 29/38 PGM
encode fixtures.

## Migration notes

- **No action required** for `decode()` consumers — full decode unchanged.
- DICOM thumbnail / viewport-zoom integrations can now use the single
  `decodePartial` entry point instead of choosing between
  `decodeResolution` and `decodeRegion`, and can select a component
  subset in the same call.

## Known limitations / future work

- `decodeQuality` (quality-layer progressive decode) remains
  `notImplemented` — the decoder's LRCP packet loop is hardcoded
  single-layer and the medical archive corpus is single-layer
  lossless, so quality-layer truncation has no test surface here. It
  is a separate arc.
- ROI Stage 3 (windowed inverse DWT — sub-tile iDWT truncation) is
  research on `v10.13-research`; `decodePartial`'s `region` path uses
  the shipped Stage 1 + 2 ROI decode.

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `V10_14_DecodePartialTests` | 7 | PASS |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |

## Companion documents

- [`Documentation/research/V10_14_DECODE_PARTIAL.md`](../research/V10_14_DECODE_PARTIAL.md) — `decodePartial` design + validation
- [`Documentation/releases/RELEASE_NOTES_v10.7.0.md`](RELEASE_NOTES_v10.7.0.md) — ROI decode Stage 2
- [`Documentation/releases/RELEASE_NOTES_v10.5.0.md`](RELEASE_NOTES_v10.5.0.md) — true partial-resolution decode
