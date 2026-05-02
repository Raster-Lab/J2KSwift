# GPU HT cleanup → DWT command-buffer fusion plan (v5.7.0)

**Branch:** `gpu-ht-dwt-fusion`
**Predecessor:** v5.6.0 (persistent Metal session + GPU dequant)
**Theme:** keep the Int32 dequantised HT output GPU-resident across the boundary into the inverse DWT, eliminating the CPU subband regrouping and per-level DWT readbacks that v5.6.0 still pays.

## Why this is the right next milestone

v5.6.0 ships:
- **GPU HT cleanup → GPU dequant** chained in one command buffer per tile (1.26× warm-process median).
- **Multi-level DWT** still runs per-level on GPU but with array-in/array-out: each level's input subbands upload from CPU, output reads back to CPU before becoming next level's LL.

The leftover overhead per tile per component:
1. HT output → CPU scatter into per-subband 2D arrays — **CPU-side**, scales with image size.
2. Each DWT level: upload 4 subband arrays (LL + LH + HL + HH) → run → readback output into `[Int32]` to feed next level's LL.
3. Cumulative readback bytes ≈ image-size × (1 + sum-of-LH+HL+HH-areas across levels).

For a 2800×2288 image with 5 decomp levels, that's roughly **64 MiB of CPU↔GPU transfer** per tile per component, all of which is avoidable.

## Scope

### In scope (v5.7.0)

1. **GPU scatter kernel** — `j2k_subband_scatter`. Takes the v5.6.0 codeblock-output buffer + a per-block placement descriptor (subband ID + 2D position within subband) → writes into per-subband 2D GPU buffers. One kernel handles all 4 subbands of one decomposition level.
2. **DWT entry point that takes existing GPU buffers** — new `J2KMetalDWT.inverse2DInt32EncodeIntoCB(...)` that takes pre-allocated GPU input buffers (LL/LH/HL/HH) + an output buffer + an existing command buffer, and adds the horizontal + vertical DWT dispatches without committing or waiting. Exists alongside the existing `inverse2DInt32(subbands:)` array-in/array-out API.
3. **Fused per-tile dispatch** in `J2KDecoderPipeline.applyInverseWaveletTransform...`: when `useGPUHT && session && filter == reversible53`, replace the CPU-side scatter + per-level upload/readback loop with one command buffer per (tile, component) that:
   - Allocates LL/LH/HL/HH buffers per level upfront
   - Encodes HT cleanup + dequant (already done by `runIntegerMagnitude`)
   - For each level (innermost → outermost):
     - Encodes scatter (codeblock buffer → that level's LH/HL/HH; LL is either previous level's output or CPU-uploaded outermost-LL)
     - Encodes DWT (level output → buffer that's reused as next level's LL)
   - Single `cb.commit() + await cb.completed()`
   - Final readback: outermost-level DWT output (image space)
4. **Bit-exactness gates** at every layer (scatter unit test, fused-dispatch corpus test, cross-codec matrix unaffected).
5. **Perf measurement** — extend the warm-process benchmark to compare v5.6.0 path vs fused path on the same corpus.

### Out of scope (deferred)

- **9/7 irreversible (lossy) DWT.** The reversible 5/3 Int32 path is the lossless gate this codebase exists to ship. Float-9/7 is more numerically forgiving and lower-priority for fusion; keep it on the v5.6.0 path.
- **Multi-tile fusion.** Each tile still gets its own command buffer. Cross-tile pool reuse is already in place via `J2KMetalSession`.
- **Multi-component fusion.** Each component still runs its own dispatch.
- **GPU codeblock decode for refinement-pass HT** or **custom-format HT.** Both already fall back to CPU per v5.5.0; they continue to do so, bypassing fusion.
- **GPU colour transform / DC offset.** Those stages run after DWT and are out-of-band for this milestone.

## Integration map

The current GPU HT-using decode path inside `applyInverseWaveletTransformGPUInt32` (at [J2KDecoderPipeline.swift:2484](Sources/J2KCodec/J2KDecoderPipeline.swift#L2484)):

```swift
for level in (1...levels).reversed() {
    let hlInt = getSubbandAsInt32(compSubbands, level: level, subband: .hl, ...)
    let lhInt = getSubbandAsInt32(compSubbands, level: level, subband: .lh, ...)
    let hhInt = getSubbandAsInt32(compSubbands, level: level, subband: .hh, ...)
    let subbandData = J2KMetalDWTSubbandsInt32(ll: currentLL, lh: lhInt, ...)
    currentLL = try await metalDWT.inverse2DInt32(subbands: subbandData, backend: .auto)
}
```

`getSubbandAsInt32` is the CPU-side regroup. Each `inverse2DInt32` call uploads 4 buffers, runs 2 dispatches, and reads back the output. Multiplied by levels.

The fused path replaces this loop with a single command buffer:

```swift
let cb = queue.makeCommandBuffer()!
let codeblockBuffer = ... // already populated by HT cleanup + dequant
var levelOutputBuffer: MTLBuffer = outermostLLBuffer  // CPU-uploaded once
for level in (1...levels).reversed() {
    let llBuffer = levelOutputBuffer  // previous level's output, or outermost-LL
    let lhBuffer = pool.acquireBuffer(...)
    let hlBuffer = pool.acquireBuffer(...)
    let hhBuffer = pool.acquireBuffer(...)
    encodeSubbandScatter(into: cb, codeblockBuffer: codeblockBuffer,
        level: level, lhBuffer: lhBuffer, hlBuffer: hlBuffer, hhBuffer: hhBuffer)
    let outBuffer = pool.acquireBuffer(...)
    metalDWT.encodeInverse2DInt32(into: cb,
        ll: llBuffer, lh: lhBuffer, hl: hlBuffer, hh: hhBuffer, output: outBuffer)
    levelOutputBuffer = outBuffer
}
cb.commit()
await cb.completed()
let finalImageInt32 = readback(levelOutputBuffer)
```

Note: HT cleanup + dequant already happen earlier in the same tile (in `applyEntropyDecoding`), so by the time the DWT loop runs, the codeblock buffer is already populated. We could in principle fuse those into the same cb too, but the current shape has HT in `applyEntropyDecoding` and DWT in `applyInverseWaveletTransform`, separated by other pipeline stages. Keeping them separate cbs is fine for now — the within-DWT fusion is the bigger win.

## Sequencing and milestones

| Milestone | Scope | Wall-clock |
|---|---|---|
| **M4P-1** | New `j2k_subband_scatter` MSL kernel + `J2KMetalSubbandScatter` Swift wrapper. Unit-tested standalone (codeblock buffer + descriptors → per-subband 2D buffers, compare against CPU `getSubbandAsInt32`). | 1 day |
| **M4P-2** | New `J2KMetalDWT.encodeInverse2DInt32(into:cb:ll:lh:hl:hh:output:)` entry point. Adds the horizontal + vertical dispatches to an existing cb without committing. Existing `inverse2DInt32(subbands:)` becomes a thin wrapper that allocates buffers + commits. | 1 day |
| **M4P-3** | Fused per-tile dispatch in `J2KDecoderPipeline`. Gated on `useGPUHT && session && reversible53`. CPU path unchanged when conditions aren't met. The codeblock buffer needs to survive from `applyEntropyDecoding` to `applyInverseWaveletTransform` — plumb through a typed Sendable wrapper. | 2 days |
| **M4P-4** | Bit-exactness gates: scatter unit test, fused-dispatch corpus test, full cross-codec matrix. Perf measurement: extend `J2KMetalSessionTests.testCorpusWarmProcessPerf` with a third column (sessionless / session / fused) so we can directly compare. | 1 day |
| **M4P-5** | Release notes + tag v5.7.0. | ½ day |

Total: ~5–6 days. Each milestone independently mergeable; CPU path stays releasable throughout.

## Risks and unknowns

- **Codeblock buffer plumbing across pipeline stages.** The output of `runIntegerMagnitude` is currently consumed and discarded inside `J2KGPUHTDispatch.decodeBatch`. To keep it GPU-resident through to DWT, we need a typed wrapper that carries the MTLBuffer + per-block placement metadata across stages. Sendability matters since pipeline stages can run on different actors.
- **Padding mismatches.** `getSubbandAsInt32` does CPU-side padding for misaligned subband dimensions. The GPU scatter kernel must replicate this exactly — bit-exactness gate will catch divergence but designing the scatter to match is the careful part.
- **Buffer pool pressure.** Each tile now holds many more buffers in flight (per-level subband + intermediate). With 5 decomp levels and 3 components, that's potentially 15+ buffers active per tile. The pool's existing memory budget may need tuning.
- **9/7 path isn't fused.** Mixed-mode decodes (some lossless, some lossy) need to dispatch on filter type. Document clearly which path is opt-in.

## Verification gates

1. **Bit-exactness preserved** — every existing test passes byte-for-byte with default flags. Fused path output ≡ v5.6.0 path output for `useGPUHT && session && reversible53` codestreams.
2. **Cross-codec matrix unaffected** — the matrix exercises CPU HT, so it shouldn't see this change. Verify with `--check`.
3. **Warm-process speedup measurable** — fused path should beat v5.6.0's 1.26× median by a non-trivial margin. Target: ≥1.5× median over sessionless. If we don't see it, surface that honestly.

## Out-of-scope-but-tracked follow-ups

- **GPU 9/7 inverse DWT fusion** for lossy codestreams.
- **Multi-tile in-flight cbs** to overlap CPU prep of tile N+1 with GPU decode of tile N.
- **GPU colour transform fusion** to keep the full pipeline on GPU.
- **`.metallib` bundling** for cold-CLI wins (still wired but dormant).
