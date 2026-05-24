# J2KSwift v10.13.0

**JP3D K>0 + ROI composition closes the {K, ROI} matrix.** v10.12.0
shipped the batched bridge SPI for the K=0+ROI and K>0+nil lanes but
left K>0+ROI as a known limitation — both `JP3DSliceStackCodec` and
`JP3DROIDecoder` threw on the combination. v10.13.0 removes both
throws and makes `JP3DROIDecoder` K-aware: `JP3DROIDecoder(cfg).decode(data, region:)`
with `cfg.resolutionLevel > 0` now returns a downsampled sub-volume
sized `ceil(region.width / 2^K) × ceil(region.height / 2^K) × region.depth`.

Decoder-only release; codestream bytes are byte-identical to v10.12.0.
Encoder unchanged. MINOR per RELEASING.md — no public API removed or
signature-changed; semantics of the v10.12.0 `JP3DBridgeOptions.regionOfInterest`
clarified as full-image coordinates.

## Summary

Four coordinated changes that close the last open cell of the
{K, ROI} batched-bridge matrix:

1. **Throws removed.** `JP3DSliceStackCodec.decode` no longer
   rejects `regionOfInterest != nil && resolutionLevel > 0`; nor
   does `JP3DROIDecoder.decode` reject the same combination
   upstream. The v10.18 fail-loud guards were specification
   tripwires for the Phase 5 future-work case; v10.13.0 IS that
   Phase 5 wiring.

2. **`JP3DBridgeOptions.regionOfInterest` semantics standardised
   on full-image coordinates.** Matches the convention used by the
   2D codec's `decodeRegion` (v10.6) and `decodePartial` (v10.8).
   The bridge maps the full-coords region onto the reduced grid
   for the crop step via the same formula `decodePartial` uses
   (`J2KAdvancedDecoding.swift:528-543`):
   `region / 2^(N − partialResolutionLevel)` with ceil-up
   width/height + clamp.

3. **`JP3DSliceStackCodec.outTileWidth/outTileHeight` K-aware.**
   When both `K > 0` and a ROI are set, the per-slice 2D codec's
   partial-res output is at the reduced grid; the per-slice output
   shape is therefore `ceil(roi.width / 2^K) × ceil(roi.height / 2^K)`,
   not `roi.width × roi.height`. `outTile*` track that — the
   Z-delta residual chain and per-slice composite read the right
   buffer shape.

4. **`JP3DROIDecoder` K-aware composite.** The output `roiBuffers`
   is now sized for the downsampled output dims when `K > 0`. The
   per-tile composite logic switches to downsampled stride for both
   src (the slice-stack returns downsampled per-slice buffers) and
   dst (`roiBuffers` sized for downsampled output). Z stays full —
   JP3D's `K` is a 2D-only halving; the Z-delta residual chain is
   per-slice.

## What's New — production-default

| Public API | v10.12.0 behaviour | v10.13.0 behaviour |
|---|---|---|
| `JP3DROIDecoder(configuration: cfg).decode(data, region:)` with `cfg.resolutionLevel > 0` | Threw `decodingError("combining ... is not yet supported. Phase 5 wiring task.")` | Returns sub-volume sized `ceil(region.width / 2^K) × ceil(region.height / 2^K) × region.depth`, with voxels bit-identical to `JP3DDecoder(cfg).decode(data)` cropped to the downsampled-mapped region |
| `JP3DDecoder(configuration: cfg).decode(data)` (no ROI) | v10.12.0 batched (unchanged) | Unchanged |
| `JP3DROIDecoder().decode(data, region:)` (default config, ROI only) | v10.12.0 batched (unchanged) | Unchanged |

The `JP3DBridgeOptions` struct (v10.12.0) keeps the same surface
but now explicitly documents `regionOfInterest` as full-image
coordinates with bridge-side reduced-grid mapping when partial-res
is also active.

## What's New — opt-in / opt-out

`J2K_JP3D_BATCHED_BRIDGE=0` (v10.11.0) still applies — disables the
batched bridge across all four {K, ROI} cells, forcing per-slice
serial. Diagnostic-A/B only.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.12.0 on every input.
  Encoder unchanged.
- **Existing decode paths** (full-volume, K-only, ROI-only) are
  byte-identical to v10.12.0 — validated by the full
  `swift test --filter JP3D` regression sweep (519/519 PASS) and
  by `V10_21_BatchedBridgeOptionsParityTests` (7/7 PASS).
- **Behaviour change**: the previously-throwing `K > 0 + ROI`
  combination now returns a valid sub-volume instead of throwing.
  Code that caught the v10.18 "Phase 5 wiring task" error and
  fell back to a workaround should remove the catch.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_18_TrueSelectiveParityTests` | 9/9 | PASS | Includes new `testCombinedResolutionLevelAndROI` (K=1 + ROI on 64×64×8 LCG volume, bit-identical to full-partial-then-crop oracle) |
| `V10_21_BatchedBridgeOptionsParityTests` | 7/7 | PASS | Updated K+ROI composition test now uses full-coords ROI |
| `V10_20_BatchedBridgeParityTests` | 5/5 | PASS | v10.11 full-volume batched bridge unchanged |
| `V10_20_BatchedInverseInt32ParityTests` | 12/12 | PASS | v10.11 batched orchestrator unchanged |
| `V10_20_JP3DBridgeParityTests` | 5/5 | PASS | Phase 1 bridge SPI composition unchanged |
| `swift test --filter JP3D` (regression sweep) | 519/519 | PASS | Full JP3D test suite green |
| Mandatory commit gate (release mode) | 7/7 | PASS | Encode-perf + decode-perf + cross-codec strict validation |

## API surface — no additions, no removals

`JP3DBridgeOptions.regionOfInterest`'s doc comment updates to spell
out full-image coordinates + the internal reduced-grid mapping
formula. No source-breaking change to consumers — code passing a
region in v10.12.0's "downsampled coords" convention was either
crashing or working accidentally for K=0; same code now works
consistently for any K.

## Known limitations

- The bench A/B (`J2KBenchMac --jp3d`) corpus doesn't include a
  K>0 + ROI lane in its current `JP3DBench.swift` matrix (only
  full / res1 / roiq independently). The bridge SPI parity tests
  cover the composition; a future bench update will quantify the
  end-to-end win when it lands.

## Reproducing the K+ROI parity oracle

The new `V10_18_TrueSelectiveParityTests.testCombinedResolutionLevelAndROI`
test is the canonical reference:

```bash
swift test --filter "V10_18_TrueSelectiveParityTests/testCombinedResolutionLevelAndROI"
```

It encodes a 64×64×8 LCG-noise volume, decodes both
`JP3DDecoder(cfg=resolutionLevel:1)` and
`JP3DROIDecoder(cfg=resolutionLevel:1).decode(data, region:)`,
then asserts the ROI voxels are bit-identical to the full-partial
decode cropped to the downsampled-mapped region.

## Backward upgrade

`swift package update` will not auto-pick this release if your
`Package.swift` pins an exact version; bump the requirement to
`from: "10.13.0"`. No source changes required for consumers — the
new behaviour is strictly additive (the throw case is replaced
with a working return).
