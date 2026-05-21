# J2KSwift v10.9.1

**Decoder correctness hotfix — GPU multi-tile inverse 5/3 DWT.**
Decoder-only; encoder and codestream bytes byte-identical to v10.9.0.

## Summary

v10.9.1 fixes a latent decoder correctness defect in the GPU multi-tile
per-tile inverse 5/3 DWT. The bug corrupted the bottom edge of decoded
images for sub-3-megapixel tiles at an odd tile-component canvas origin
— e.g. a DX 2800×2288 image decoded as 2×2 tiles (observed max abs diff
≈ 9823). It has been latent since v10.3.0, where the `_gpuHTEntropyEnabled`
routing change made the affected per-level IDWT path reachable for these
dimensions.

Single-tile decode, even-origin multi-tile decode, the encoder, and
codestream bytes are all unaffected.

## Fixed

- **GPU multi-tile IDWT high-band dimensions.** `inverse2DGPUInt32` and
  `inverse2DCPUInt32` (`Sources/J2KMetal/J2KMetalDWT.swift`) computed the
  LH/HH high-band size as `height / 2` (the CPU variant also `width / 2`)
  instead of the canvas-anchored `height − llH` / `width − llW`. At an
  odd tile-component canvas origin the ISO/IEC 15444-1 band partition is
  uneven (LL = ⌊·/2⌋, LH/HH = ⌈·/2⌉), so `/2` under-sizes the
  column-high buffer and drops the final high-band row/column —
  bottom-edge corruption. The v8.3 fix (`cc33313`) corrected this in
  `inverse2DInt32MultiLevelFused` and `encodeInverse2DInt32` but missed
  these two per-level functions. Pure Swift host-code fix — the Metal
  kernels were never wrong; `default.metallib` is unchanged.

## Backward compatibility

Codestream bytes byte-identical to v10.9.0 — the encoder is untouched.
Decoder output is unchanged for every input except the previously-corrupt
sub-3 MP odd-origin multi-tile GPU-decode case, which now decodes
bit-exactly.

## Validation

All on a clean release-mode build:

- `V8_3_GPUIDWTRootCauseDiagnostic` 3/3 — the regression test for this
  exact defect.
- IDWT parity / bit-exact suites — `J2KMetalDWT53IntBitExactTests`,
  `J2KMetalDWT53IntOddOriginBitExactTests`,
  `V10_3_MetalIDWTInverse53TiledParityTests`,
  `V10_3_MetalIDWTInverse532DParityTests`,
  `V10_5_MetalIDWTInverse53FusedParityTests` — all pass.
- `HTNativeMultiTileSelfRoundtripTests` 5/5 — including
  `testDX2x2SelfRoundtripBitExact`.
- **Mandatory commit gate** (`J2KMedicalCorpusEncodePerformanceTests` +
  `J2KMedicalCorpusPerformanceTests` + `J2KStrictCrossCodecValidationTests`)
  — 7/7, 0 failures.
- **Cross-codec parity** — `J2KStrictCrossCodecValidationTests`,
  `HTCrossCodecConformantTests`, `HTEndToEndCrossCodecTests`,
  `HTGPUForward53CrossCodecTests`, `V10_3_V82BypassCrossCodecCheck` —
  14/14, exercising OpenJPEG / OpenJPH / Grok / Kakadu.

## Performance

No performance change — the fix is a buffer-sizing correction. The
canonical warm cross-codec benchmark (`cross_codec_warm_bench.py`,
in-process, Apple M2, median-of-7) is within run-to-run noise of v10.9.0
on all 38 fixtures for both encode and decode. J2KSwift wins 28/38
encode and 31/38 decode against OpenJPH / Grok / Kakadu. Full data:
`benchmark-results-arm64-v10.9.1-20260521.json`.

## Test maintenance

Bundled, test-only (no product impact):

- 8 stale-constant tests updated — version-string assertions made
  semantic-version-format-agnostic (no longer pinned to `2.0.0`); Metal
  shader-function count 48/43 → 72; HTJ2K performance-target constants
  3×/1.5× → 10×/8×.
- 19 tests for de-scoped or parked features deleted — lossy R-D PSNR
  (lossless-only since v5.38), the multi-layer encoder (a separate
  lossy / rate-allocation arc), GPU-forward-encode research telemetry,
  and weak / deadlocking research-probe tests.

## Known limitations

Unchanged from v10.9.0. The J2KSwift encoder still cannot produce
genuine multi-layer codestreams (a separate lossy / rate-allocation arc).

## Reproducing

```bash
# The fix's regression test:
swift test -c release --filter V8_3_GPUIDWTRootCauseDiagnostic

# Mandatory commit gate:
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Canonical warm cross-codec benchmark:
python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc \
  --output benchmark-results-$(uname -m)-v10.9.1-$(date +%Y%m%d).json
```
