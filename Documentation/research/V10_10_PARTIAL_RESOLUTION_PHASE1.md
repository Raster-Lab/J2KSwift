# v10.10-research Phase 1 — partial-resolution decode (decode-then-downsample)

**Date**: 2026-05-20
**Branch**: `v10.10-research`
**Status**: **Phase 1 LANDED** (decode-then-downsample) — working API surface
**Next**: Phase 2+ (true partial-resolution decode — code-block filter + iDWT truncation)

---

## What landed in Phase 1

`J2KDecoder.decodeResolution(_:options:)` now works (was `notImplemented`).
The implementation is **decode-then-downsample**: runs the full decode and
downsamples the output to the target resolution via power-of-2 block-average.

API contract:
- `options.level == 0` → thumbnail (W/32 × H/32 for N=5 decomp)
- `options.level == 5` → full image (byte-identical to `decode()`)
- `options.level == k` (k ∈ 1..4) → intermediate resolution
- `options.upscale == true` → result rescaled to original dimensions

This is the **minimum viable surface** that lets callers use the API
correctly. Phase 2+ will replace the implementation with true partial
decode (skip entropy + iDWT for higher levels) without changing the API.

### Why ship Phase 1 before Phase 2

Per `feedback_no_shortcuts.md`, the complete partial-resolution decode is
multi-week scope (threads `maxResolutionLevel` through 15+ call sites:
extract, entropy, dequant, iDWT, color, reconstruct, GPU paths, multi-
tile paths). Shipping Phase 1 unblocks:

1. **Downstream API consumers** can write code against `decodeResolution`
   today; the perf upgrade lands transparently when Phase 2 ships.
2. **DICOM workflow integrations** can use the API for thumbnail
   generation immediately, with full-decode pace.
3. **Future work scoping** is sharper because the API surface is
   committed; Phase 2 is purely an internal optimisation.

The downside: no perf win for thumbnails *yet*. Full decode time still
paid. Phase 1 → Phase 2 transition will save 5-30× on thumbnail use
cases.

## Phase 2 plan — true partial-resolution decode

### Scope

Implement actual entropy / iDWT skip:

1. **Filter code-blocks** in `extractTileData`:
   ```
   keep block iff (block.level == 0)        // LL (deepest)
              OR  (block.level > N - r)    // detail bands at deepest r levels
   ```
   - r = 0 → keep only LL (4-5% of code-blocks for MG)
   - r = N → keep all
2. **Skip entropy decode** for filtered-out blocks (saves the dominant stage).
3. **Truncate iDWT** at the target level — the existing
   `inverseTransformMultiLevel53` naturally does N iDWT steps for N subband
   levels; passing fewer levels reduces the work proportionally.
4. **Output reduced dimensions** directly from iDWT (no separate downsample
   step).

### Surface area

Code touch (estimate):
- `J2KDecoderPipeline.decodeSingleTile` — accept `maxResolutionLevel` (single-tile CPU)
- `J2KDecoderPipeline.decodeSingleTileGPU` — same (single-tile GPU)
- `J2KDecoderPipeline.decodeMultiTile` — same (multi-tile CPU)
- `J2KDecoderPipeline.decodeMultiTileGPU` — same (multi-tile GPU)
- `J2KDecoderPipeline.decodeMultiTileGPUBatched` — same (batched path)
- `extractTileData` — accept + apply filter
- `applyEntropyDecoding` — receive pre-filtered code-blocks (no-op if already filtered)
- `applyInverseWaveletTransform` — accept `effectiveLevels` parameter
- `reconstructImage` / output buffer sizing — accept reduced dimensions
- `J2KAdvancedDecoding.decodeResolution` — pass `maxResolutionLevel` instead of post-downsample

Estimated 2-3 sprints.

### Projected wins (when Phase 2 lands)

For a 16.8 MP MG codestream decoded at resolution level 0 (thumbnail
525×149 from 3520×4784 source):

| Stage | Full decode | Partial decode at level 0 | Save |
|---|---:|---:|---:|
| extractTileData | ~6 ms | ~3 ms (still parses headers) | ~3 ms |
| entropy | ~25 ms | ~1 ms (only LL blocks) | ~24 ms |
| dequant | ~6 ms | ~0.3 ms | ~6 ms |
| iDWT | ~25 ms | 0 ms (no levels to invert) | ~25 ms |
| color + DC + recon | ~5 ms | ~0.2 ms (small output) | ~5 ms |
| **Total** | **~67 ms** | **~5 ms** | **~62 ms** |

Projected speedup: **~13×** at level 0. At intermediate levels (2-3),
~3-5× speedup. This is the kind of win that materially changes user-
perceived performance in DICOM workflows.

### Bit-exact contract (Phase 2)

True partial-resolution decode at level r is **not equivalent to full
decode + downsample**. It produces the LL band at decomposition level
(N-r), which is the mathematically correct partial reconstruction per
ISO/IEC 15444-1.

A bit-exact contract should be established against:
- **OpenJPH** `ojph_expand` with resolution-level argument (if it supports one)
- **Kakadu** `kdu_expand` with the `-resolution_level` option
- **OpenJPEG** `opj_decompress` with the `-r` flag

Cross-codec parity is the gate for Phase 2 default-on shipment.

## Files added in Phase 1

- `Sources/J2KCodec/J2KAdvancedDecoding.swift` — `decodeResolution` impl
  replaced; helper `downscaleByPowerOf2` + `upscaleByPowerOf2` added
- `Tests/J2KCodecTests/J2KAdvancedDecodingTests.swift` — old `throwsNotImplemented`
  test updated to assert the new working behaviour (any error from empty
  data, but NOT `notImplemented`)
- `Tests/J2KMetalTests/V10_10_DecodeResolutionSmokeTests.swift` — 3 smoke
  tests (dimensions at each level; upscale recovers full dims; level 5
  byte-identical to decode())
- `Documentation/research/V10_10_PARTIAL_RESOLUTION_PHASE1.md` (this file)

## Test results

- `V10_10_DecodeResolutionSmokeTests`: 3/3 PASS
- Mandatory commit gate (`J2KMedicalCorpusEncodePerformanceTests` +
  `J2KMedicalCorpusPerformanceTests` + `J2KStrictCrossCodecValidationTests`):
  7/7 PASS.

## Status

Phase 1 landed on `v10.10-research`. **Not yet shipped to main.**
A v10.4.0 release would bundle Phase 1; the work is small enough that
it could ship as a patch (v10.3.1) since codestream bytes are
byte-identical to v10.3.0 (decoder-only API addition).

Phase 2 (the real perf win) is the next multi-session investment.
