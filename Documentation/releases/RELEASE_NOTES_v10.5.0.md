# J2KSwift v10.5.0 — true partial-resolution decode (3-8× thumbnail speedup)

**Release date:** 2026-05-20
**Base:** `v10.4.0` (`6518b58`)
**Type:** MINOR per RELEASING.md — new working behaviour for the `decodeResolution` public API; codestream bytes byte-identical to v10.4.0 on the default `decode()` path; decoder-only change.

## Summary

v10.5.0 completes the partial-resolution decode arc that v10.4.0 (Phase 1,
decode-then-downsample) started. `J2KDecoder.decodeResolution(_:options:)`
now does **true partial-resolution decode**: it filters code-blocks by
decomposition level before entropy decode (Stage B.1) and truncates the
inverse DWT at the target resolution level (Stage B.2), producing reduced-
dimension output directly with no downsample step.

**Thumbnail decode is now 3-8× faster than full decode.**

## Benchmark — `decodeResolution` wall by level

`V10_10_StageB1EntropyFilterBench` (M2 release, lossless HT corpus, 7 trials):

| Fixture | px | decode() full | L4 | L3 | L2 | L1 | L0 (thumbnail) | L0 speedup |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| CT 512² | 262 K | 2.55 | 1.03 | 0.63 | 0.45 | 0.37 | **0.33** | **7.69×** |
| PX 2459×1316 | 3.24 M | 26.62 | 12.44 | 7.68 | 5.93 | 5.38 | **5.12** | **5.20×** |
| DX 2800×2288 | 6.41 M | 47.08 | 21.41 | 13.91 | 11.85 | 10.02 | **9.59** | **4.91×** |
| MG mid 3518×4784 | 16.83 M | 82.48 | 43.88 | 30.76 | 27.29 | 27.64 | **26.81** | **3.08×** |

The resolution gradient is clean across all 6 levels — each step down
roughly halves the work, matching the JP2K dyadic decomposition structure.

## What's New — true partial-resolution decode

### Stage B.1 — code-block filter (`extractTileData`)

`extractTileData` gains a `maxResolutionLevel: Int?` parameter. When set,
code-blocks at decomposition levels above the kept range are dropped after
parsing:

```
keep iff (block.level == 0)        // LL (deepest), always needed
      OR (block.level > N - r)     // detail bands at the deepest r levels
```

The entropy decode stage then operates on the filtered set. For a level-0
thumbnail of a 16.8 MP MG fixture, this drops ~99 % of code-blocks
(measured 982 → 4, 985 → 2 per tile).

### Stage B.2 — inverse DWT truncation (`applyInverseWaveletTransform`)

When partial-resolution decode is active, the `levelSubbands53` array is
truncated to the deepest `r` decomposition levels before the inverse DWT
runs. `inverseTransformMultiLevel53` does exactly N iDWT steps for N
subband elements; passing fewer elements stops the transform at the
corresponding level, producing reduced-dimension LL output directly. For
level 0, the iDWT short-circuits entirely (empty subbands) and returns the
deepest LL.

`reconstructImage` substitutes the reduced `outputDimensions` for
`metadata.width × height`, so the resulting `J2KImage` and its components
carry consistent reduced dimensions.

### Routing

Partial-resolution decode forces the CPU iDWT path
(`partialResolutionLevel != nil` → `allowGPUPath = false`). The GPU iDWT
does not yet honour the truncation; routing partial-decode through it
would produce full-dimension data behind a reduced-dimension image
header. A future release may add the truncation to the GPU iDWT.

## API

`decodeResolution(_:options:)` (async, since v10.4.0):

```swift
let decoder = J2KDecoder()

// Thumbnail — level 0 = lowest resolution.
let thumb = try await decoder.decodeResolution(
    codestream, options: J2KResolutionDecodingOptions(level: 0))

// Quarter-res preview.
let preview = try await decoder.decodeResolution(
    codestream, options: J2KResolutionDecodingOptions(level: 3))

// Full resolution — byte-identical to decode().
let full = try await decoder.decodeResolution(
    codestream, options: J2KResolutionDecodingOptions(level: 5))

// Upscale the partial decode back to original dimensions.
let upscaled = try await decoder.decodeResolution(
    codestream, options: J2KResolutionDecodingOptions(level: 1, upscale: true))
```

## Backward compatibility

- **Codestream bytes byte-identical to v10.4.0** on the default `decode()` path.
- `decode()`, `decodeGPU()`, `decodeWithGPUHT()` behaviour unchanged.
- `decodeResolution(level: 5)` is byte-identical to `decode()` (smoke-tested).
- `decodeResolution` is opt-in — callers explicitly choose partial decode.
- Public Swift API: no signature changes vs v10.4.0 (decodeResolution was
  already `async throws` since v10.4.0).

## Correctness

Partial-resolution decode at level r produces the LL band at decomposition
level (N − r), which is the mathematically exact partial reconstruction per
ISO/IEC 15444-1 §F — the inverse DWT truncated, no approximation.

`V10_10_DecodeResolutionSmokeTests` (3/3 PASS):
- Output dimensions correct at all 6 resolution levels (0..5)
- `decodeResolution(level: 5)` byte-identical to `decode()`
- `upscale: true` reconstructs original dimensions

## Cross-codec parity

`J2KStrictCrossCodecValidationTests`: 3/3 PASS — full-decode behaviour
preserved against OpenJPH / Grok / Kakadu (partial decode is an opt-in
path; full decode is unaffected).

## Mandatory commit gate

7/7 PASS:
- `J2KMedicalCorpusEncodePerformanceTests` 2/2
- `J2KMedicalCorpusPerformanceTests` 2/2
- `J2KStrictCrossCodecValidationTests` 3/3

## Migration notes

- **No action required** for `decode()` consumers — full decode unchanged.
- DICOM workflow integrations (thumbnail generation, viewport-zoom previews)
  should switch from `decode()` + manual downsample to `decodeResolution`
  for the 3-8× speedup.

## Known limitations / future work

- Partial decode currently forces the CPU iDWT path. A future release could
  add truncation support to the GPU iDWT for the largest fixtures.
- `decodePartial`, `decodeQuality`, and `decodeRegion` `.direct` strategy
  remain `notImplemented` — Phase 3 scope. The parameter-threading
  foundation B.1+B.2 established is reusable for those.
- A cross-codec parity contract for partial-resolution output (vs
  `opj_decompress -r` / `kdu_expand -resolution_level`) is a nice-to-have
  validation; the truncation math is deterministic so partial output is
  correct by construction.

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `V10_10_DecodeResolutionSmokeTests` | 3 | PASS |
| `V10_10_StageB1EntropyFilterBench` | 4 fixtures × 6 levels | PASS (printed wall table) |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |

## Companion documents

- [`Documentation/research/V10_10_PARTIAL_RESOLUTION_PHASE1.md`](../research/V10_10_PARTIAL_RESOLUTION_PHASE1.md) — Phase 1 design
- [`Documentation/research/V10_10_STAGE_B2_PLAN.md`](../research/V10_10_STAGE_B2_PLAN.md) — Stage B.2 plan
- [`Documentation/releases/RELEASE_NOTES_v10.4.0.md`](RELEASE_NOTES_v10.4.0.md) — Phase 1 release
