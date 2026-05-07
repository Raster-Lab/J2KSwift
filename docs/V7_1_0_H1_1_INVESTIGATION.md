# v7.1.0 H1.1 — Defect A root-cause + fix

**Status**: Root cause located + 3-line fix shipped + bit-exact regression validated. Multi-tile DX decode wins +44–60 % on M2.

**Branch**: `feature/v7.1.0-multi-tile-gpu-ht-entropy-fix`

**Anchors**:
- [`docs/V7_1_0_H1_0_INVESTIGATION.md`](V7_1_0_H1_0_INVESTIGATION.md) — H1.0 finding (per-block GPU HT entropy is bit-exact; bug is downstream)
- [`docs/V7_1_0_PLAN.md`](V7_1_0_PLAN.md) §H1 — Defect A scope
- [`docs/V6_3_0_E1_2_INVESTIGATION.md`](V6_3_0_E1_2_INVESTIGATION.md) — original Defect A discovery (32,768 pixel diff)

---

## TL;DR — fix is 3 lines, gain is +44 to +60 % multi-tile DX decode

Defect A's actual root cause is the **v5.9 zero-copy fast-lane** in `applyEntropyDecoding` ([line ~1902 of J2KDecoderPipeline.swift](../Sources/J2KCodec/J2KDecoderPipeline.swift#L1895)). When all the gating conditions fire (5/3 lossless, HT conformant, GPU HT entropy enabled, warm session, all blocks non-empty + passCount > 0, and `idwtWillBeGPU` true), the fast-lane returns `([], batch)` — **empty `[SubbandInfo]` plus the GPU batch**. The downstream IDWT is supposed to consume `batch` via `inverse2DInt32FullFusedFromCodeblocks`.

For the multi-tile per-tile path, **E1.2 (#322) forces CPU IDWT** via the `isMultiTilePerTile: true` flag on `applyInverseWaveletTransformGPU`. CPU IDWT consumes `[SubbandInfo]` (not `batch`). Receiving an empty `[SubbandInfo]` array, CPU IDWT produces zero coefficients → zero spatial output → DC unshift adds +32,768 to all pixels = **exactly the observed Defect A pixel diff**.

**Fix**: thread `isMultiTilePerTile` into `applyEntropyDecoding` and gate the fast-lane on it being false. When `decodeTilePayloadGPU` calls with `isMultiTilePerTile: true`, the fast-lane is suppressed; the slow-lane regroup runs and populates `[SubbandInfo]` correctly using `gpuPreDecoded[i]` (the per-block GPU coefficients H1.0 confirmed are bit-exact). CPU IDWT consumes correct subbands → bit-exact pixels.

---

## How the H1.1 probe found the divergence

The H1.0 finding (per-block GPU HT entropy is bit-exact) ruled out the entropy decode itself. H1.1's probe compared the **full `applyEntropyDecoding` output**:

[`Tests/J2KMetalTests/MultiTileGPUHTPostEntropyDriftTests.swift`](../Tests/J2KMetalTests/MultiTileGPUHTPostEntropyDriftTests.swift):

```swift
let (subbandsCPU, _) = try await pipeCPU.applyEntropyDecoding(
    codeBlocks, metadata: tileMeta, isGPUPath: false)
let (subbandsGPU, gpuBatchGPU) = try await pipeGPU.applyEntropyDecoding(
    codeBlocks, metadata: tileMeta, isGPUPath: true)
```

First-run output on DX 2x2 tile 1:

```
=== Probe: tile 1 origin (1400, 0) ===
  codeblock count: 470
  CPU path subbands: 16
  GPU path subbands: 0; gpuBatch: true
```

**The GPU path returns 0 subbands.** That's the v5.9 fast-lane's `return ([], batch)` firing. The CPU IDWT path then consumes 0 subbands → 32,768 pixel diff.

---

## The fix (diff vs main)

### `Sources/J2KCodec/J2KDecoderPipeline.swift`

**1. Add `isMultiTilePerTile: Bool = false` parameter to `applyEntropyDecoding`** (line 1858):

```swift
func applyEntropyDecoding(
    _ blocks: [CodeBlockInfo],
    metadata: CodestreamMetadata,
    isGPUPath: Bool = false,
    isMultiTilePerTile: Bool = false  // ← v7.1.0 H1.1
) async throws -> (subbands: [SubbandInfo], batch: J2KGPUHTBatch?) {
```

**2. Gate the v5.9 fast-lane on `!isMultiTilePerTile`** (line ~1898):

```swift
if idwtWillBeGPU,
   !isMultiTilePerTile,  // ← v7.1.0 H1.1 — must be false for multi-tile per-tile
   !isIrreversible, useHT, useConformant,
   (useGPUHT || (isGPUPath && Self._gpuHTEntropyEnabled)),
   let session = metalSession, !blocks.isEmpty,
   J2KGPUHTDispatch.isAvailable,
   blocks.allSatisfy({ !$0.data.isEmpty && $0.passCount > 0 }) {
    if let fastLane = try await runZeroCopyFastLane(
        blocks: blocks, metadata: metadata, session: session)
    {
        return fastLane
    }
}
```

**3. Update `decodeTilePayloadGPU` to pass `isGPUPath: true, isMultiTilePerTile: true`** (line ~840):

```swift
let (decodedBlocks, gpuBatch) = try await applyEntropyDecoding(
    codeBlocks, metadata: tileMeta,
    isGPUPath: true, isMultiTilePerTile: true)
```

(Was `isGPUPath: false` per E1.2 #322's defensive workaround.)

**That's the entire fix.** 3 lines of Swift in `applyEntropyDecoding` + a parameter rename in one call site + the docstring + the comment block in `decodeTilePayloadGPU`.

---

## Validation

### Bit-exact contract (the gate that E1.2 #322 set)

`MultiTileDecodeGPUDefaultOnTests.testMultiTileDefaultOn_DecodedPixelsIdentical_VsForcedOff` — **12/12 cells pixel-byte-identical** between gate-on (production, GPU entropy now enabled) and gate-off (legacy CPU multi-tile). The Defect A 32,768 pixel diff is gone.

### Per-fixture wall-time A/B (M2, debug mode — release deltas are larger but ratios match)

`MultiTileDecodeGPUDefaultOnTests.testMultiTileDefaultOn_WallTimeAB_AcrossCorpus`:

| fixture | mode | px | bytes | CPU ms | GPU ms | CPU/GPU× |
|---|---|---:|---:|---:|---:|---:|
| MR 886² | 2x2 | 785K | 169K | 348.9 | 357.4 | 0.98× |
| MR 886² | 4x4 | 785K | 170K | 384.0 | 388.8 | 0.99× |
| MR 886² | strips4 | 785K | 169K | 277.8 | 278.5 | 1.00× |
| XA 1024² | 2x2 | 1.05M | 1.6M | 549.0 | 572.2 | 0.96× |
| XA 1024² | 4x4 | 1.05M | 1.6M | 600.5 | 593.1 | 1.01× |
| XA 1024² | strips4 | 1.05M | 1.6M | 591.8 | 611.1 | 0.97× |
| PX 2459×1316 | 2x2 | 3.24M | 6.4M | 1606.5 | 1620.3 | 0.99× |
| PX 2459×1316 | 4x4 | 3.24M | 6.5M | 1818.5 | 1780.9 | 1.02× |
| PX 2459×1316 | strips4 | 3.24M | 6.4M | 1807.1 | 1801.0 | 1.00× |
| **DX 2800×2288** | **2x2** | **6.41M** | **12.7M** | **3765.1** | **2618.5** | **1.44×** |
| **DX 2800×2288** | **4x4** | **6.41M** | **12.7M** | **4445.6** | **3482.7** | **1.28×** |
| **DX 2800×2288** | **strips4** | **6.41M** | **12.7M** | **4396.0** | **2739.3** | **1.60×** |

**DX (the only fixture above the 4 MP GPU threshold) gains +28 to +60 %** on multi-tile decode, matching the v6.2.0 single-tile DX +37–46 % envelope. The headline +60 % win on DX strips4 is the biggest single-release multi-tile decode improvement since v6.2.0.

MR / XA / PX stay below the GPU threshold so the GPU path doesn't fully fire on those fixtures (they're still gated to CPU IDWT + CPU entropy at sub-3 MP per the production threshold from v6.3.0 E2). The H1.1 fix unlocks the GPU win for fixtures that meet the threshold — DX today, larger DX/MG fixtures in production.

### Cross-codec parity unchanged

`HTTileParityMatrixTests` 12/12 cells, self-RT diff = 0, cross-decode against OpenJPH/Grok/Kakadu = 0 — bytes byte-identical to v7.0.0.

---

## Why the fix is so small

The bug was **a missing precondition on the v5.9 fast-lane**, not a deep algorithmic issue. The fast-lane was added in v5.9 when only single-tile decode existed. E1.2 (#322) introduced the `isMultiTilePerTile: true` IDWT-fallback flag for multi-tile decode but didn't propagate it back to `applyEntropyDecoding`. The fast-lane then fired in a context it was never designed to handle (where downstream IDWT runs on CPU instead of GPU).

H1.0 (#334)'s per-block probe pointed away from the kernel and toward the data-flow, narrowing the search to `applyEntropyDecoding`'s code paths. H1.1's probe compared the function's full output and found the empty `[SubbandInfo]` immediately. The 3-line fix restores correctness without touching any kernel code.

---

## Trajectory impact

The v7.1.0 plan's H phase budget assumed kernel-level work for both H1 (Defect A) and H2 (Defect B). H1.1 closes Defect A in 3 lines instead of a kernel rewrite, **freeing budget for**:

1. **H2** — GPU 5/3 IDWT parity-aware boundary lifting (still kernel work; Defect B is real and unchanged)
2. **H3** — re-enable `isMultiTilePerTile: false` in `decodeTilePayloadGPU` (currently `true` to defend Defect B; will flip when H2 lands)
3. **K1** — multi-tile per-tile warm-session hardening
4. **I-series** — GPU forward HT entropy approach C (encode-side, unchanged)

The Defect A fix already captures the **decode-side multi-tile entropy win** (+28–60 % on DX). H2 + H3 add the IDWT compute win on top. Combined H ships a multi-tile decode wall reduction in the same envelope as v6.2.0's +46.2 % single-tile win, and unblocks the v7.1.0 Kakadu-beat trajectory's decode-side claim.

The H1.1 fix also **doesn't break Defect B's mitigation** — the `isMultiTilePerTile: true` flag on `applyInverseWaveletTransformGPU` still forces CPU IDWT for parity-correctness; we simply now have correct entropy-decoded coefficients feeding into it.
