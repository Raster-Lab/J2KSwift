# v10.10-research Stage B.2 plan — iDWT truncation + reduced-dim output

**Status**: PLANNED (Stage B.1 committed as foundation at `8aaf83e`; B.1 alone is wash)
**Scope**: 1-2 sessions
**Projected win**: completes the ~13× thumbnail speedup; B.2 saves the bulk of the wall (~30-45 ms on MG)

---

## Why B.1 alone shipped as wash

Per `V10_10_StageB1EntropyFilterBench` (M2 release, lossless HT, 7 trials):

| Fixture | decode() full | decodeRes L0 (thumb) | Δ |
|---|---:|---:|---:|
| CT 512² | 2.67 | 2.18 | +0.49 (1.22× faster) |
| PX 2459×1316 | 27.89 | 30.25 | −2.36 (0.92× slower) |
| DX 2800×2288 | 46.65 | 55.07 | −8.42 (0.85× slower) |
| MG mid 3518×4784 | 82.37 | 104.08 | −21.71 (0.79× slower) |

The Phase 1 downsample step (full-decode output → reduced-dim block-average) costs 5-25 ms on MG/DX, exceeding the entropy savings from B.1's block filter. Net wash or regression on production-scale fixtures.

**B.1 IS the necessary foundation** — the filter logic + parameter threading is correctly wired through 5 extract sites + smoke-tested bit-exact at level 5. B.2 builds on top of it.

## What Stage B.2 must add

### 1. Truncate `applyInverseWaveletTransform` at target resolution

Current:
```swift
private func applyInverseWaveletTransform(_ subbands: [SubbandInfo], metadata: ...)
    async throws -> [[Double]]
```

Internally builds `levelSubbands53` with N elements (one per decomposition level, deepest-first):

```swift
for level in (1...levels).reversed() {
    let parentW = levelSizes[level - 1].width
    // ... build (lh, hl, hh) tuple for this level
    levelSubbands53.append(...)
}
// Call inverseTransformMultiLevel53 with N elements → N iDWT steps → full output
```

**B.2 modification**: when `pipeline.partialResolutionLevel = r ∈ [0, N]` is set, truncate `levelSubbands53` to first `r` elements before calling `inverseTransformMultiLevel53`:

```swift
let r = partialResolutionLevel ?? levels
let truncated = Array(levelSubbands53.prefix(r))
let result = try await optimizer.inverseTransformMultiLevel53(
    ll: llFlat, llW: expectedLLW, llH: expectedLLH,
    subbands: truncated,  // ← was levelSubbands53 (N elements)
    tileOriginX: tcx0, tileOriginY: tcy0)
```

The existing `inverseTransformMultiLevel53` already handles the empty-subbands case (line 707): `guard !subbands.isEmpty else { return (data: ll, width: llW, height: llH) }` — for r=0, returns the LL directly.

For r=N, no change (passing all N levels = full iDWT, same as today).

### 2. Threading reduced dimensions downstream

`applyInverseWaveletTransform` returns `[[Double]]` where each component's array currently has length `metadata.width × metadata.height`. With truncated iDWT, each array is reduced to `(W >> (N-r)) × (H >> (N-r))`.

Downstream stages must know reduced dims:

- **`applyInverseColorTransformInPlace`**: iterates components at full dims. Needs reduced.
- **DC level unshift**: iterates `metadata.components[i].bitDepth` × full-dim buffer. Needs reduced.
- **`reconstructImage`**: builds `J2KImage` with full dims. Needs reduced.

**Approach**: add `outputDimensions: (width: Int, height: Int)?` to the `DecoderPipeline` instance. When set, all downstream stages substitute it for `metadata.width × metadata.height`.

Compute it once after `partialResolutionLevel` is set:

```swift
if let r = partialResolutionLevel {
    let N = metadata.configuration.decompositionLevels
    let factor = 1 << (N - r)
    let outW = (metadata.width + factor - 1) / factor
    let outH = (metadata.height + factor - 1) / factor
    outputDimensions = (width: outW, height: outH)
}
```

### 3. Remove the Phase 1 downsample step

`J2KDecoder.decodePartialResolution` in `J2KCodec.swift` currently returns the full-dim image; `decodeResolution` in `J2KAdvancedDecoding.swift` then downsamples. With B.2, `decodePartialResolution` returns the reduced-dim image directly, no downsample needed.

```swift
// Before (Phase 1 + B.1):
public func decodeResolution(_ data: Data, options: ...) async throws -> J2KImage {
    let fullImage = try await decodePartialResolution(data: data, level: options.level)
    let halvingsFromFull = max(0, 5 - options.level)
    let downscaleFactor = 1 << halvingsFromFull
    return try Self.downscaleByPowerOf2(image: fullImage, ...)  // ← remove
}

// After (B.2):
public func decodeResolution(_ data: Data, options: ...) async throws -> J2KImage {
    return try await decodePartialResolution(data: data, level: options.level)
}
```

### 4. Smoke test update

`testDecodeResolution_fullLevel_equivalentToFullDecode` should still pass (r=N is full decode, no change). The other smoke tests on output dimensions should still pass naturally.

NEW: add a bit-content sanity check — verify decode at level 1 produces an LL-band-equivalent image that's approximately the same as the Phase 1 downsample (modulo iDWT-vs-block-average differences).

---

## Estimated win after B.2 lands

Per `V10_9_PartialResolutionPotentialBench`, the IDEAL upper bound for level-1 encoding (which approximates true partial decode) is ~17% faster. For TRUE level-0 partial decode (decode only the LL):

- Entropy: ~5% of work (just LL blocks) → save ~95% of entropy stage
- iDWT: 0 work (no levels to invert) → save 100% of iDWT stage
- Downsample: removed → save the 5-25 ms cost

Projected MG L0 thumbnail wall:
- Pre: ~82 ms (decode) + ~22 ms (downsample) = 104 ms (current B.1 path)
- Post: ~20 ms (extract + small entropy + reduced color/recon) = ~20 ms
- **Speedup: ~5× on MG thumbnail (more conservative than the v10.10 Phase 2 plan's ~13× projection)**

The smaller fixtures (CT 512², XA 1024²) see proportionally less savings since iDWT is already small there.

---

## Estimated risk

- Threading reduced dimensions through 4+ downstream stages is the bulk of the work. Each stage has its own assumptions about full-dim buffers.
- Color transform on reduced data: should "just work" since it's per-pixel; the input/output array length just changes.
- DC unshift: same; per-pixel, length-driven.
- reconstructImage: passes `metadata.width × metadata.height` to `J2KImage.init`. Needs to use the reduced dims.

The risk is mostly mechanical (many touch points) rather than algorithmic.

---

## Sequencing

1. Add `outputDimensions: (width: Int, height: Int)?` instance var to `DecoderPipeline`.
2. Compute it in the entry point when `partialResolutionLevel` is set.
3. Truncate `levelSubbands53` in `applyInverseWaveletTransform`.
4. Update downstream stages to read `outputDimensions ?? (metadata.width, metadata.height)`.
5. Remove downsample step in `decodeResolution`.
6. Run smoke tests + benchmark.
7. If win confirmed → ship as v10.5.0 (single-PR cherry-pick of B.1 + B.2 since B.1 alone is wash).

---

## Files added (this session)

- `Tests/J2KMetalTests/V10_10_StageB1EntropyFilterBench.swift` (B.1 perf bench)
- `Documentation/research/V10_10_STAGE_B2_PLAN.md` (this file)

Plus B.1 changes in `Sources/J2KCodec/J2KDecoderPipeline.swift` + `J2KCodec.swift` + `J2KAdvancedDecoding.swift` (commit `8aaf83e`).
