# J2KSwift v10.9.0 — multi-layer decode conformance fix + `decodeQuality`

**Release date:** 2026-05-20
**Base:** `v10.8.0`
**Type:** MINOR per RELEASING.md — fixes a decoder conformance defect (multi-layer codestreams previously decoded incorrectly) and implements the `decodeQuality` API (previously a `notImplemented` stub; signature `throws` → `async throws`). Codestream bytes byte-identical to v10.8.0; single-layer `decode()` is byte-exact unchanged; encoder unchanged.

## Summary

v10.9.0 closes the partial-decode arc: `decodeQuality` was the last of
the four `notImplemented` partial-decode stubs. Implementing it
uncovered — and fixes — a **Part-1 conformance defect**: J2KSwift's
decoder silently mis-decoded any multi-layer JPEG 2000 codestream.

| API | Shipped |
|---|---|
| `decodeResolution` | v10.4.0 + v10.5.0 |
| `decodeRegion` | v10.6.0 + v10.7.0 |
| `decodePartial` | v10.8.0 |
| **`decodeQuality`** | **v10.9.0 — this release** |

## The conformance fix — multi-layer packet decode

`extractTileData`'s packet loop was hardcoded single-layer: it read one
packet per `(resolution, component, precinct)`. An LRCP codestream with
more than one quality layer emits `layer × resolution × component ×
precinct` packets, so the decoder read a fraction of them and
desynchronised — producing a **wrong image with no error raised**.

Confirmed with Kakadu 8.4.1: a 4-layer lossless codestream decoded to
the wrong pixels (single-layer decode was bit-correct). J2KSwift could
not correctly decode a multi-layer codestream from *any* encoder.

v10.9.0 adds `extractTileDataMultiLayer` — the layer-aware packet
decode per ISO/IEC 15444-1 B.10: a layer loop, persistent per-precinct
inclusion / zero-bit-plane tag-trees, and per-code-block `Lblock` +
coding-pass + data accumulation across the layers each block
contributes to. `extractTileData` routes to it when `qualityLayers > 1`;
the single-layer path is a **separate branch, byte-exact unchanged**.

## What's New — `decodeQuality`

`decodeQuality(_:options:)` decodes a multi-layer codestream up to a
chosen quality layer:

- `decodeQuality(layer: L)` reconstructs the image from quality layers
  `0...L`, discarding the refinement carried by higher layers — a
  lower-bitrate preview. `layer == qualityLayers - 1` equals `decode()`.
- `components` selects an image-component subset.
- `cumulative` must be `true` (decode layers `0...layer`, the only
  image-meaningful semantics); `cumulative: false` (single-layer
  refinement delta) throws `notImplemented`.
- On a single-layer codestream the only valid `layer` is 0 and the
  result equals `decode()`.

```swift
let decoder = J2KDecoder()

// Full quality (every layer) — same as decode().
let full = try await decoder.decodeQuality(
    data, options: J2KQualityDecodingOptions(layer: lastLayer))

// A low-bitrate preview from the first two quality layers.
let preview = try await decoder.decodeQuality(
    data, options: J2KQualityDecodingOptions(layer: 1))
```

## Backward compatibility

- **Codestream bytes byte-identical to v10.8.0** — encoder unchanged.
- **Single-layer `decode()` is byte-exact unchanged** — the multi-layer
  path is a separate branch entered only when `qualityLayers > 1`.
- Multi-layer `decode()` now produces the **correct** image (it was
  previously wrong). No J2KSwift-produced codestream is multi-layer, so
  no round-trip is affected; the change only corrects decoding of
  multi-layer codestreams from other encoders.
- `decodeQuality`'s signature changed `throws` → `async throws`. It was
  a `notImplemented` stub since v6.x — no real callers.

## Correctness

`V10_15_MultiLayerDecodeTests` (3/3 PASS), against genuine multi-layer
codestreams produced by Kakadu 8.4.1 (`kdu_compress Clayers=N
Creversible=yes`):

- `decode()` of the 2-, 3- and 4-layer lossless codestreams is
  **bit-identical to the original image** — the conformance fix.
- `decodeQuality(layer: last)` ≡ `decode()`.
- `decodeQuality(layer: L)` for L = 0, 1, 2 is **bit-identical to
  `kdu_expand -layers (L+1)`** — full cross-codec conformance, including
  the lossy layer-truncated reconstructions. Quality is monotonic in L;
  the final layer is lossless.

Single-layer regression: the v10.5–v10.8 partial-decode suites
(`V10_10` resolution, `V10_11`/`V10_12` ROI, `V10_14` decodePartial),
16/16 PASS — single-layer decode is untouched.

## Cross-codec parity

`J2KStrictCrossCodecValidationTests`: 3/3 PASS.

## Mandatory commit gate

7/7 PASS:
- `J2KMedicalCorpusEncodePerformanceTests` 2/2
- `J2KMedicalCorpusPerformanceTests` 2/2
- `J2KStrictCrossCodecValidationTests` 3/3

## Cross-codec warm benchmark (regression check)

v10.9.0 does not change the single-layer `decode()` / `encode()` path —
the multi-layer path is a separate branch. The canonical warm
cross-codec benchmark is run as a **regression check**.

`cross_codec_warm_bench.py --in-proc`, M2, medical-real corpus (mid
fixtures), median ms. Full results: `benchmark-results-arm64-v10.9.0-20260520.json`.

Decode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.30 | 9.46 | 9.47 | 4.48 |
| MR 512² | 2.28 | 9.43 | 9.46 | 4.47 |
| XA 1024² | 6.42 | 19.48 | 9.52 | 9.49 |
| PX 2793×1316 | 27.61 | 76.54 | 19.97 | 19.73 |
| DX 2800×2288 | 47.66 | 128.97 | 39.80 | 39.78 |
| MG 3518×4784 | 80.98 | 131.81 | 77.01 | 76.85 |

Encode wall:

| Fixture | J2KSwift | OpenJPH | Grok | Kakadu |
|---|---:|---:|---:|---:|
| CT 512² | 2.06 | 9.48 | 9.51 | 4.48 |
| MR 512² | 2.16 | 9.50 | 9.47 | 4.48 |
| XA 1024² | 4.87 | 19.46 | 19.61 | 9.52 |
| PX 2793×1316 | 15.96 | 76.69 | 39.78 | 9.57 |
| DX 2800×2288 | 34.87 | 131.78 | 76.99 | 19.73 |
| MG 3518×4784 | 38.29 | 131.55 | 130.15 | 39.97 |

Decode/encode walls are consistent with v10.8.0 (within measurement
noise) — no regression; the single-layer path is structurally
untouched. Across the full 38-fixture run, J2KSwift+inproc wins
(median ≤ every measured codec) on 27/38 PGM decode and 29/38 PGM
encode fixtures.

## Migration notes

- **No action required** for `decode()` consumers of single-layer
  codestreams (every J2KSwift-encoded codestream) — behaviour and bytes
  unchanged.
- Consumers decoding multi-layer codestreams from other encoders now
  get the correct image (previously corrupt). Re-decode if you cached
  earlier (wrong) output.

## Known limitations / future work

- J2KSwift's **encoder** does not produce genuine multi-layer
  codestreams (the production path is single-layer; the legacy
  multi-layer emission writes identical packets per layer). `decodeQuality`
  is therefore validated against external (Kakadu) multi-layer
  codestreams. Genuine progressive multi-layer *encoding* is a separate
  arc (and squarely lossy/rate-allocation territory).
- `decodeQuality` supports cumulative decode (`layers 0...L`) only.

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `V10_15_MultiLayerDecodeTests` | 3 | PASS |
| `V10_10` / `V10_11` / `V10_12` / `V10_14` (single-layer regression) | 16 | PASS |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |

## Companion documents

- [`Documentation/research/V10_15_QUALITY_LAYER_DECODE.md`](../research/V10_15_QUALITY_LAYER_DECODE.md) — multi-layer decode + `decodeQuality` design + validation
- [`Documentation/releases/RELEASE_NOTES_v10.8.0.md`](RELEASE_NOTES_v10.8.0.md) — `decodePartial` umbrella API
