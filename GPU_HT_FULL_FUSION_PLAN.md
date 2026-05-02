# GPU HT cleanup → scatter → DWT full fusion plan (v5.8.0)

**Branch:** `gpu-ht-full-fusion` (local only until the v5.7.0 release pipeline completes — avoiding runner contention)
**Predecessor:** v5.7.0 (multi-level fused inverse 5/3 DWT)
**Theme:** keep the entire HT decode → scatter → DWT pipeline GPU-resident from end to end. The only host↔GPU traffic is codestream upload at the start and final image readback at the end.

## Why this is the right next milestone

v5.7.0 ships:
- HT cleanup + dequant in one cb (per-tile)
- Multi-level inverse 5/3 DWT in one cb (per-tile per-component) with output GPU-resident across levels

The leftover overhead per tile per component:
- **CPU regroup**: `getSubbandAsInt32` scans `subbandBlocks` and copies per-codeblock coefficients into 2D subband arrays. For a 2800×2288 image with 5 decomp levels that's hundreds of MB of memory copies CPU-side per component.
- **Per-level CPU→GPU upload**: each level's LH/HL/HH still uploaded from `[Int32]` arrays in the v5.7.0 fused path. ~3–4 MB per component aggregated across 5 levels.

The v5.7.0 plan landed the **scatter MSL kernel** (M4P-1) dormant — it's bit-exact with the CPU regroup but isn't yet wired into the production pipeline. v5.8 lights that wire up.

After v5.8, the only host↔GPU transfers in a fused decode are:
1. Codestream bytes (the input)
2. Per-block placement descriptors (~32 bytes per codeblock)
3. Final image Int32 readback (the output)

Everything in between — HT cleanup, dequant, subband regroup, all 5 DWT levels — happens GPU-resident in a single command buffer per (tile, component).

## Scope

### In scope (v5.8.0)

1. **Per-codeblock placement metadata extraction** in `applyEntropyDecoding` — for the GPU-fusion-eligible path, compute placement descriptors (component, level, subband, dst-x, dst-y, target-subband-stride) alongside the existing per-block decode.
2. **GPU-resident HT decode entry point** on `J2KGPUHTDispatch` that returns the codeblock-output `MTLBuffer` (Int32) + per-block placement descriptors instead of `[Int32]` arrays. Used only on the fused path; keeps the existing array-based API for the v5.5.0/v5.6.0/v5.7.0 paths.
3. **Per-tile fused dispatch** that chains: HT cleanup + dequant (existing `runIntegerMagnitude`) → subband scatter (M4P-1 kernel) → multi-level inverse 5/3 DWT, all in one command buffer per (tile, component). Single commit + await + final readback.
4. **Bit-exactness gates** — the new path must produce byte-identical output to v5.7.0's session+fused-DWT path on the full DICOM corpus.
5. **Perf measurement** — extend the warm-process benchmark to add a "v5.8 full-fused" column alongside v5.7.0's "session+fused-DWT".

### Out of scope (deferred)

- **9/7 irreversible (lossy) DWT.** Stays on v5.6.0 per-level path.
- **Multi-tile / multi-component fusion.** Each tile-component still gets its own command buffer (tile-level decoupling preserved). Cross-tile pool reuse via session is unchanged.
- **GPU codeblock decode for refinement-pass HT** or **custom-format HT.** Continue to fall back to CPU.
- **GPU colour transform / DC offset.** These run after DWT and are separately fusable in a later release.
- **`.metallib` bundling** for cold CLI. Wiring still dormant.

## Integration map

The v5.7.0 fused path inside `applyInverseWaveletTransformGPUInt32`:

```swift
for level in (1...levels).reversed() {
    let lhInt = getSubbandAsInt32(...)  // CPU regroup + upload
    let hlInt = getSubbandAsInt32(...)
    let hhInt = getSubbandAsInt32(...)
    subbandsPerLevel.append(J2KMetalDWTSubbandsInt32(ll: ..., lh: lhInt, hl: hlInt, hh: hhInt, ...))
}
currentLL = try await metalDWT.inverse2DInt32MultiLevelFused(subbandsPerLevel: subbandsPerLevel)
```

The v5.8 fused path replaces the CPU regroup with GPU scatter:

```swift
// 1. Per level, build placement descriptors (no data copy)
let descriptorsPerLevel = (1...levels).reversed().map { level in
    buildScatterDescriptors(compSubbands, level: level, levelSizes: levelSizes)
}

// 2. One cb per component:
//    - Acquire per-level subband buffers (LL/LH/HL/HH/colLow/colHigh/output)
//    - Encode scatter dispatch from codeblockBuffer to LH/HL/HH for each level
//    - Encode inverse 5/3 DWT for each level (output → next LL)
//    - Single commit + await + final readback
let result = try await metalDWT.inverse2DInt32FullFusedFromCodeblocks(
    codeblockBuffer: gpuCodeblockBuffer,
    descriptorsPerLevel: descriptorsPerLevel,
    levelSizes: levelSizes,
    initialOutermostLL: currentLL)
```

The codeblock buffer (HT decode output) flows from `applyEntropyDecoding` to `applyInverseWaveletTransform`. v5.8 introduces a typed wrapper around the existing `[SubbandInfo]` to carry the optional GPU buffer + placement metadata when the fused path is active.

## Sequencing and milestones

| Milestone | Scope | Wall-clock |
|---|---|---|
| **M5P-1** | Add `J2KGPUHTBatch` Sendable wrapper around `(MTLBuffer, [J2KMetalSubbandScatterDescriptor])`. Add `J2KGPUHTDispatch.decodeBatchGPUResident(...)` that returns this wrapper instead of `[GPUHTBlockResult]`. Plumb through `DecoderPipeline.applyEntropyDecoding`. | 1 day |
| **M5P-2** | Add `J2KMetalDWT.inverse2DInt32FullFusedFromCodeblocks(...)` that takes a codeblock buffer + per-level scatter descriptors + level sizes and runs scatter + multi-level DWT in one cb. Reuses `J2KMetalSubbandScatter` (already landed in v5.7.0). | 1 day |
| **M5P-3** | Wire the full-fused path into `applyInverseWaveletTransformGPUInt32` behind the existing `useGPUHT && session && reversible53` gate, plus a new `useFullFusion` flag (default `true` once tests pass). | 1 day |
| **M5P-4** | Bit-exactness gate (corpus-wide test that v5.8 fused == v5.7.0 fused) + perf measurement. | 1 day |
| **M5P-5** | v5.8.0 release notes + tag. | ½ day |

Total: ~4–5 days of focused work.

## Risks and unknowns

- **Dequantisation stage.** For reversible 5/3 lossless, dequantisation is a no-op (stepSize == 1). The fused path skips it entirely. Need to verify this holds for all corpus fixtures.
- **CodeBlockInfo placement data.** The existing `CodeBlockInfo` struct has (component, level, subband, x, y, width, height) but those are codeblock-relative. The scatter kernel needs subband-relative placement, which requires per-subband 2D dimensions known at descriptor-build time. Need to plumb subband dimensions back into the descriptor build step.
- **Multi-component decoding.** Each component runs its own fused dispatch. The scatter kernel takes 4 buffer bindings (LL/LH/HL/HH) — multi-component means re-allocating per-component. Pool memory pressure increases.
- **Buffer pool peak memory.** With 5 decomp levels × per-level buffers + intermediate + output, plus the codeblock buffer kept alive across all levels, peak buffer count per tile is high. Pool config may need tuning for very large images.
- **Correctness regression risk.** The fused path produces the same Int32 output as v5.7.0; the bit-exactness gate is the safety net.

## Verification gates

1. **Bit-exactness preserved** — every existing test passes byte-for-byte. The new full-fused path output ≡ v5.7.0 fused output ≡ CPU output.
2. **Cross-codec matrix unaffected** — the matrix exercises CPU HT, so it shouldn't see this change. Verify with `--check`.
3. **Warm-process speedup measurable** — full-fused path should beat v5.7.0's 1.63× median by a non-trivial margin. Target: ≥2.0× median over sessionless. If we don't see it, surface honestly in the release notes.

## Out-of-scope-but-tracked follow-ups

- **9/7 irreversible fusion.**
- **Multi-tile in-flight cbs.**
- **GPU colour transform fusion.**
- **`.metallib` bundling** for cold CLI.

## Process notes

- Branch starts local-only to avoid runner contention with the queued v5.7.0 release pipeline. Push to origin once the v5.7.0 release lands.
- All commits stay on `gpu-ht-full-fusion` until M5P-4 passes; main stays at v5.7.0 throughout.
