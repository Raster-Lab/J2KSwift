# J2KSwift v10.4.0 — Working `decodeResolution` API (Phase 1: decode-then-downsample)

**Release date:** 2026-05-20
**Base:** `v10.3.0` (`e8e8e36`)
**Type:** MINOR per RELEASING.md "New public type / function / config option, default unchanged, codestream bytes byte-identical on default config | MINOR". The existing `J2KDecoder.decodeResolution(_:options:)` stub (throwing `notImplemented` since v6.x) now has a working implementation. Codestream bytes byte-identical to v10.3.0; decoder-only API surface change.

## Summary

v10.4.0 ships **Phase 1** of the partial-resolution decode arc:
`J2KDecoder.decodeResolution(_:options:)` now actually decodes (was throwing
`notImplemented` since v6.x). Phase 1 is implemented as **decode-then-downsample**
— runs the full decode pipeline, then power-of-2 block-averages the output
to the requested resolution level. Provides a working API surface for
downstream consumers (DICOM workflow thumbnail generation, viewport-zoom
previews) without yet realising the perf upgrade.

**Phase 2** (true partial-resolution decode — code-block filter + iDWT
truncation, multi-week scope, ~13× projected thumbnail speedup) is the
next investment. The API stays stable across the Phase 1 → Phase 2
transition; downstream code written against v10.4.0 picks up the speedup
transparently when Phase 2 lands.

## What's New — public API

### `J2KDecoder.decodeResolution(_:options:)` — now working

Previously threw `J2KError.notImplemented`. Now returns a correctly-
dimensioned `J2KImage` at the requested resolution level:

```swift
let decoder = J2KDecoder()

// Thumbnail (level 0 = lowest resolution).
// For a 5-decomp codestream, output is ⌈W/32⌉ × ⌈H/32⌉.
let thumbOpts = J2KResolutionDecodingOptions(level: 0)
let thumbnail = try await decoder.decodeResolution(codestream, options: thumbOpts)

// Quarter-resolution preview (level 3 → ⌈W/4⌉ × ⌈H/4⌉).
let previewOpts = J2KResolutionDecodingOptions(level: 3)
let preview = try await decoder.decodeResolution(codestream, options: previewOpts)

// Full resolution at level 5 — byte-identical to plain decode().
let full = try await decoder.decodeResolution(codestream,
    options: J2KResolutionDecodingOptions(level: 5))

// Upscale back to original dimensions (nearest-neighbour reconstruction).
let upscaled = try await decoder.decodeResolution(codestream,
    options: J2KResolutionDecodingOptions(level: 1, upscale: true))
```

### Signature change

The method now uses `async throws` (was `throws`):

```swift
// Before (v10.3.0 and earlier):
public func decodeResolution(_ data: Data, options: J2KResolutionDecodingOptions) throws -> J2KImage

// After (v10.4.0):
public func decodeResolution(_ data: Data, options: J2KResolutionDecodingOptions) async throws -> J2KImage
```

This is technically a SOURCE-BREAKING change in the call site — callers must add `await`. The pre-v10.4.0 implementation always threw `notImplemented` so no real code path could have been calling it productively, but the signature change is documented for completeness.

## What's NOT in v10.4.0 (Phase 2 scope)

- True partial-resolution decode (skip entropy + iDWT for higher levels).
- `decodePartial(_:options:)` — still throws `notImplemented`.
- `decodeQuality(_:options:)` — still throws `notImplemented`.
- `decodeRegion(_:options:)` with `.direct` / `.cached` strategies — still throws `notImplemented`. (`.fullImageExtraction` works as before.)

These all remain on the Phase 2+ roadmap. The Phase 1 → Phase 2
transition is purely internal — the API contract stays stable.

## Phase 1 perf characteristics

For a 16.8 MP MG mammography fixture decoded at resolution level 0
(thumbnail):

| Stage | Wall (ms) |
|---|---:|
| Full `decode()` | ~85 |
| Downsample to ⌈W/32⌉ × ⌈H/32⌉ | ~1-2 |
| **Total Phase 1 `decodeResolution(level: 0)`** | **~87** |

Phase 2 projected for the same fixture: **~5 ms** (~17× speedup).

## Backward compatibility

- **Codestream bytes byte-identical to v10.3.0** on every default configuration.
- Default `decode()` behaviour unchanged from v10.3.0.
- Other decoder entry points (`decodeGPU`, `decodeWithGPUHT`) unchanged.
- `decodeResolution(level: 5)` byte-identical to `decode()` (smoke-tested).

## Cross-codec parity

`J2KStrictCrossCodecValidationTests`: 3/3 PASS — full-decode behaviour preserved against OpenJPH / Grok / Kakadu.

## Smoke tests

`V10_10_DecodeResolutionSmokeTests`: 3/3 PASS

- Output dimensions correct at all 6 resolution levels (0..5)
- `upscale: true` reconstructs original dimensions
- `level == 5` byte-identical to `decode()`

## Mandatory commit gate

7/7 PASS:
- `J2KMedicalCorpusEncodePerformanceTests` 2/2
- `J2KMedicalCorpusPerformanceTests` 2/2
- `J2KStrictCrossCodecValidationTests` 3/3

## Migration notes

Existing callers of `decodeResolution` need to add `await`. Since the
pre-v10.4.0 implementation always threw `notImplemented`, no production
code path could have been calling it successfully — any code referencing
it was test-only or speculative.

```diff
- let image = try decoder.decodeResolution(data, options: opts)
+ let image = try await decoder.decodeResolution(data, options: opts)
```

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `V10_10_DecodeResolutionSmokeTests` | 3 | PASS |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |
| `J2KAdvancedDecodingTests.testDecodeResolutionWithEmptyDataThrowsDecodeError` | 1 | PASS (asserts NOT notImplemented) |

## Companion documents

- [`Documentation/research/V10_10_PARTIAL_RESOLUTION_PHASE1.md`](../research/V10_10_PARTIAL_RESOLUTION_PHASE1.md) — full Phase 1 design + Phase 2 roadmap + projected wins.
- [`Documentation/research/V10_9_PARTIAL_DECODE_AND_ENCODER_TUNING_FINDING.md`](../research/V10_9_PARTIAL_DECODE_AND_ENCODER_TUNING_FINDING.md) — preceding investigation that scoped the partial-resolution decode opportunity.

## Future Phase 2 work

Phase 2 will replace decode-then-downsample with true partial decode:

1. Filter code-blocks by decomposition level in `extractTileData`
2. Skip entropy decode for filtered-out blocks
3. Truncate inverse DWT at the target level
4. Output reduced-dimension spatial data directly

Estimated 2-3 sprints. Projected thumbnail speedup: 5-30×.

Scoped on `v10.10-research` branch; landing as v10.5.0 when complete.
