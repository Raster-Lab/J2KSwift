# v7.1.0 H1.0 — Defect A root-cause investigation

**Status**: Investigation + diagnostic probe only. No production code change. **Major root-cause finding** that pivots H1.1 fix scope.

**Branch**: `feature/v7.1.0-multi-tile-gpu-ht-entropy-investigation`

**Anchors**:
- [`docs/V7_1_0_PLAN.md`](V7_1_0_PLAN.md) §H1 — Defect A scope (was hypothesised at GPU HT entropy)
- [`docs/V6_3_0_E1_2_INVESTIGATION.md`](V6_3_0_E1_2_INVESTIGATION.md) — original Defect A discovery (32768 pixel diff in production multi-tile decode)

---

## TL;DR — Defect A is NOT in GPU HT entropy

The v7.1.0 plan (and the v6.3.0 E1.2 investigation that surfaced Defect A) attributed the 32768 pixel diff to *"GPU HT entropy multi-tile produces incorrect coefficients"*. **The H1.0 diagnostic probe disproves this hypothesis**:

- **Probe 1** — `J2KGPUHTDispatch.decodeBatch` (no-session path) on tiles 0/1/2/3 of DX 2x2: **1,881 blocks total, 0 drift cells** vs CPU `HTBlockDecoderConformant.decode`.
- **Probe 2** — `J2KGPUHTDispatch.decodeBatchGPUResident` (warm-session production path) on tile 1 of DX 2x2: **470 blocks, 0 drift coefficients** vs CPU.

**The GPU HT entropy decoder produces bit-exact per-block output in every multi-tile per-tile context tested.** The 32768 pixel diff observed in production multi-tile decode (E1.2 measurement) must originate **downstream** of the per-block coefficient stage.

H1.1 fix scope pivots from *"fix per-tile GPU HT entropy descriptors"* to *"fix gpuBatch fused-from-codeblocks IDWT per-tile semantics"*.

---

## What the probe does

[`Tests/J2KMetalTests/MultiTileGPUHTEntropyDriftTests.swift`](../Tests/J2KMetalTests/MultiTileGPUHTEntropyDriftTests.swift) — `testDefectA_PerBlockDriftOnFailingDXTile`:

1. Encodes DX 2800×2288 multi-tile (2x2 mode, HT-conformant lossless 5/3) via `J2KMultiTileEncoder`.
2. For each of the 4 tiles, extracts codeblocks via `pipeline.extractTileData` (the same path `decodeTilePayloadGPU` uses).
3. **Probe 1**: runs `J2KGPUHTDispatch.decodeBatch(blocks:)` (no session) → per-block Int32 coefficients.
4. For each block, runs `HTBlockDecoderConformant.decode(...)` (CPU) → UInt32 sign-magnitude → applies the same shift conversion the no-session GPU path does → per-block Int32 coefficients.
5. Compares per-block GPU vs CPU Int32 arrays element-by-element. Reports drift cells (block-index, mismatch count, max abs diff, first-10-coeff diff).
6. **Probe 2**: same shape, but uses `decodeBatchGPUResident(blocks:session:)` (the production warm-session path) and validates per-block coefficients via `decodedBlockCoefficients`.

Diagnostic only — does not assert; the data is the input to H1.1's fix scope.

---

## Empirical findings (M2 release, DX 2800×2288 2x2)

### Probe 1 — `decodeBatch` (no session)

| Tile | Origin | Codeblocks | Eligible | Drift cells |
|---|---|---:|---:|---:|
| 0 | (0, 0) | 430 | 430 | **0 / 430** |
| 1 | (1400, 0) | 470 | 470 | **0 / 470** |
| 2 | (0, 1144) | 467 | 467 | **0 / 467** |
| 3 | (1400, 1144) | 514 | 514 | **0 / 514** |
| **Total** | | **1,881** | **1,881** | **0 / 1,881** |

### Probe 2 — `decodeBatchGPUResident` (warm-session production path)

| Tile | Eligible | GPU-decoded | Fallbacks | outputSampleCount | Drift coefficients |
|---|---:|---:|---:|---:|---:|
| 1 | 470 | 470 | 0 | 1,601,600 | **0** |

Both paths produce per-block coefficients **bit-exact identical to CPU** for every multi-tile per-tile invocation tested.

---

## What this means for the production 32768 pixel diff

The v6.3.0 E1.2 investigation measured DX 2800×2288 multi-tile decode self-roundtrip:
- `isGPUPath = true`, `isMultiTilePerTile = true` → diff = 65,535+ (Defect A + B both firing)
- `isGPUPath = true`, `isMultiTilePerTile = false` (CPU IDWT fallback) → diff = **32,768** (Defect A only)
- `isGPUPath = false` (CPU entropy), `isMultiTilePerTile = true` (CPU IDWT) → diff = 0

The 32,768 diff was attributed to GPU HT entropy. H1.0's per-block probe shows **the entropy stage is bit-exact**. So when `isGPUPath = true` and `isMultiTilePerTile = false`:
- GPU HT entropy produces correct per-block coefficients (verified ✅)
- CPU IDWT runs (forced by `isMultiTilePerTile = true` flag from E1.2 PR #322)
- But the result still diffs by 32,768

The question becomes: **what does `isGPUPath = true` enable downstream of per-block coefficients that introduces the 32,768 diff in CPU IDWT output?**

### Hypothesis — `gpuBatch` interferes with the regroup → CPU IDWT path

`applyEntropyDecoding` returns `(decodedBlocks: [SubbandInfo], gpuBatch: J2KGPUHTBatch?)`. The CPU IDWT (when `isMultiTilePerTile = true`) consumes `decodedBlocks` (the regrouped `[SubbandInfo]`) and **ignores `gpuBatch`**. So if the regroup is correct, CPU IDWT should produce correct output.

But — when `isGPUPath = true` AND warm session is in use, `gpuEarly` runs `decodeBatchGPUResident` which produces:
- `gpuPreDecoded[i]` — per-block Int32 coefficients (verified bit-exact)
- `gpuBatch` — the `J2KGPUHTBatch` with `codeblockBuffer + plansByComponent`

The regroup uses `gpuPreDecoded[i]` to populate `[SubbandInfo]`. If the regroup is correct, downstream CPU IDWT consumes correct subband data.

**There's a v5.27.0 short-circuit at line 1998 of J2KDecoderPipeline.swift**:

```swift
if let batch = gpuBatch, batch.floatPlansByComponent != nil {
    return ([], batch)
}
```

This returns **empty `[SubbandInfo]`** + the batch when `floatPlansByComponent` is set (9/7 lossy fused path). For 5/3 lossless, `floatPlansByComponent` is nil — the short-circuit doesn't fire — so the regroup runs. That should be safe.

### Most likely actual root cause

Given per-block GPU coefficients are correct, the 32,768 diff must come from one of these post-entropy points:

1. **Regroup mis-uses `gpuPreDecoded[i]`** — maybe the per-block coefficient array is inserted at the wrong index in the `[SubbandInfo]`, OR a block's coefficients are duplicated/skipped in the per-component grouping. Per-block data is correct in isolation, but per-tile assembly mismatches.

2. **`gpuBatch.codeblockBuffer` is held by the per-tile session and gets returned to the buffer pool too early** — the CPU IDWT path doesn't read from this buffer (it consumes `[SubbandInfo]`), but if the buffer pool has any side effect on the regroup's [SubbandInfo] coefficient arrays (e.g. shared memory aliasing), corruption could leak in.

3. **`isGPUPath = true` triggers a code-path branch in regroup or `applyDequantization` that's per-tile-incorrect** — the `(useGPUHT || (isGPUPath && Self._gpuHTEntropyEnabled))` static-flag check fires in the gpuEarly closure but might also fire in another consume site that mishandles per-tile state.

### H1.1 fix scope (proposed)

The H1.1 PR should:
1. **Probe the regroup output** — instrument `applyEntropyDecoding` to dump the resulting `[SubbandInfo]` for tile 1 with `isGPUPath = true` vs `isGPUPath = false`. Compare per-subband-per-component.
2. **Probe the dequantization output** — same shape, capture `dequantizedSubbands` for both paths.
3. **Probe the IDWT input** — capture what the CPU IDWT actually consumes when `isMultiTilePerTile = true` flips.
4. Identify the specific stage where the `isGPUPath = true` path diverges from `isGPUPath = false`. Fix the divergence.

---

## Why this finding matters for the v7.1.0 H trajectory

The plan's H1 phases (H1.0 / H1.1) were scoped under the assumption that GPU HT entropy needed a per-tile fix. **Now we know the entropy is fine** — the fix is somewhere in the post-entropy data flow inside `applyEntropyDecoding`'s regroup or the downstream stages. This is potentially:

- **Smaller in scope** — likely a 1-10 line fix in the regroup logic, not a kernel rewrite
- **Lower in risk** — no Metal kernel changes
- **Faster to ship** — no GPU-side debugging round-trip

**The H1 phase budget is now likely smaller than the original v7.1.0 plan estimate.** Once H1.1 lands, K1 (warm-session hardening) and the H2 (Defect B — GPU 5/3 IDWT parity-aware) phases proceed as planned, then I-series.

---

## What this PR ships

**Investigation only** — no production code change.

- `Tests/J2KMetalTests/MultiTileGPUHTEntropyDriftTests.swift` — the diagnostic probe (3 tests pass, including the per-block drift comparison for both GPU dispatch paths).
- `Sources/J2KCodec/J2KDecoderPipeline.swift` — minor visibility change: `parseCodestream` and `extractTileData` promoted from `private` to `internal` (module-scoped) so the diagnostic test can extract per-tile codeblocks. Not part of the public API surface; backward-compatible.
- `docs/V7_1_0_H1_0_INVESTIGATION.md` (this doc) — the finding + H1.1 fix-scope pivot.

H1.1's PR will instrument the regroup / dequant / IDWT-input stages to identify the specific divergence point, then ship the targeted fix.
