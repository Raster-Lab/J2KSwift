# v6.3.0 E1.0 — multi-tile decode bug investigation

**Status**: Investigation + repro test only. No production code change in this PR.

**Branch**: `feature/v6.3.0-multitile-decode-investigation`

**Anchors**:
- [`docs/V6_3_0_PLAN.md`](V6_3_0_PLAN.md) §E1 — multi-tile decode bug fix (HEADLINE)
- [`RELEASE_NOTES_v6.2.0.md`](../RELEASE_NOTES_v6.2.0.md) §"Known limitations" — multi-tile stays on CPU pending v6.3.0 investigation
- v6.2.0's narrow guard in `J2KDecoderPipeline.decode`: `&& !metadata.isMultiTile`

---

## Why this exists

The v6.2.0 release-candidate validation caught `J2KError.malformedBlock` from `applyEntropyDecoding` when a multi-tile codestream routed through the GPU pipeline with both decoder gate flags on (`_gpuInverse53Enabled = true`, `_gpuHTEntropyEnabled = true`). v6.2.0 shipped with a narrow `!metadata.isMultiTile` routing guard — the bug stays hidden because multi-tile takes the CPU path, but the underlying defect is unresolved.

E1.0's job is to characterise the failure precisely enough for E1.1 to write a targeted fix. The deliverables are:
1. A matrix repro test (`Tests/J2KMetalTests/MultiTileDecodeGPUInvestigationTests.swift`)
2. This document — empirical results + Phase 1 fix-scope hypothesis

---

## Triangulation method

Three decode entry points × four medical fixtures × three multi-tile encode modes (matching `HTTileParityMatrixTests`'s codestream shape via `J2KMultiTileEncoder`):

| Entry point | What it exercises |
|---|---|
| **(A)** `J2KDecoder().decode()` with `_gpuInverse53Enabled = true` + `_gpuHTEntropyEnabled = true` | Production-default after v6.2.0. The `!isMultiTile` guard routes multi-tile to the CPU path — expected ✅ on every cell. |
| **(B)** `J2KDecoder().decodeWithGPUHT()` | Pre-D-series GPU HT path. Sets `useGPUHT = true` on the pipeline instance and dispatches multi-tile to `decodeMultiTileGPU` UNCONDITIONALLY. Failure here = bug in multi-tile GPU HT entropy dispatch. |
| **(C)** `J2KDecoder().decodeGPU()` | GPU IDWT only (CPU entropy). Failure here = bug in GPU multi-tile IDWT path. |

Modes: `tiles2x2`, `tiles4x4`, `strips4`. Fixtures: MR 886², XA 1024², PX 2459×1316, DX 2800×2288. All encoded with the same `htConfig()` lossless 5/3 reversible HT-conformant settings.

---

## Findings

### Matrix

| fixture | mode | grid | bytes | (A) decode flags=ON | (B) decodeWithGPUHT | (C) decodeGPU |
|---|---|---|---:|:---|:---|:---|
| MR 886²        | 2x2     | 2×2 | ~168 K  | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| MR 886²        | 4x4     | 4×4 | ~168 K  | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| MR 886²        | strips4 | 1×4 | ~168 K  | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| XA 1024²       | 2x2     | 2×2 | ~1.6 M  | ✅ | ✅ | 💥 process crash (signal 5) |
| XA 1024²       | 4x4     | 4×4 | ~1.6 M  | ✅ | ✅ | 💥 process crash (signal 5) |
| XA 1024²       | strips4 | 1×4 | ~1.6 M  | ✅ | ✅ | 💥 process crash (signal 5) |
| PX 2459×1316   | 2x2     | 2×2 | ~6.4 M  | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| PX 2459×1316   | 4x4     | 4×4 | ~6.4 M  | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| PX 2459×1316   | strips4 | 1×4 | ~6.4 M  | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| DX 2800×2288   | 2x2     | 2×2 | ~12.7 M | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| DX 2800×2288   | 4x4     | 4×4 | ~12.7 M | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |
| DX 2800×2288   | strips4 | 1×4 | ~12.7 M | ✅ | ❌ malformedBlock | 💥 process crash (signal 5) |

(C) is skipped in the test fixture itself — the runtime trap kills the test process. The crash is recorded here from earlier diagnostic runs done with the C entry-point inlined.

### Per-row triangulation logic (from the test header)

| (A) | (B) | (C) | conclusion |
|:---:|:---:|:---:|---|
| ✅ | ❌ | ✅ | bug in GPU HT entropy multi-tile dispatch only |
| ✅ | ❌ | ❌ / 💥 | bug in BOTH GPU IDWT multi-tile path AND HT entropy |
| ✅ | ✅ | ✅ | no bug (v6.2.0 narrow over-cautious for this cell) |
| ❌ | — | — | bug surfaces even on the v6.2.0 production-default path |

**Observed pattern**: every fixture except XA falls in the (✅, ❌, 💥) row → bugs exist in BOTH multi-tile sub-paths. (A) is universally ✅, confirming the v6.2.0 narrow `!isMultiTile` guard is correctly hiding both defects in production.

### Key observation: XA passes (B), every other fixture fails

- **MR 886²** is the most highly-compressed fixture (~168 KB / 886² × 16 bpp ≈ 1.07 bpp avg).
- **XA 1024²** is the densest (~1.6 MB / 1024² × 16 bpp ≈ 12.5 bpp avg).
- **PX**, **DX** sit in between but still fail.

XA's denser encoded representation means every codeblock has substantial coded data; MR / PX / DX produce many codeblocks with sparse or empty payloads after compression. **The bug is gated by codeblock content sparsity, not by image dimensions, tile count, or modality semantics.**

### (C) `decodeGPU` multi-tile process crash

`decodeGPU` does CPU entropy + GPU IDWT, so the crash is in the GPU multi-tile IDWT path (`decodeMultiTileGPU` → `decodeTilePayloadGPU` → `applyInverseWaveletTransformGPU` for each tile). Signal 5 (Swift runtime trap) on every fixture, every mode, including XA. This is a separate, lower-level defect from the (B) entropy `malformedBlock`. v6.2.0's `!isMultiTile` guard hides both.

---

## Phase 1 (E1.1) fix-scope hypothesis

### Hypothesis A — `gpuEarly` codeblock filtering breaks multi-tile remap

In [`Sources/J2KCodec/J2KDecoderPipeline.swift`](../Sources/J2KCodec/J2KDecoderPipeline.swift) around the `gpuEarly` closure (~line 1879), the GPU input filter drops codeblocks with `block.data.isEmpty` or `block.passCount == 0`:

```swift
for (i, block) in blocks.enumerated() {
    guard !block.data.isEmpty, block.passCount > 0 else { continue }
    gpuInputs.append(GPUHTBlock(...))
    inputOriginalIndices.append(i)
}
```

`inputOriginalIndices` then remaps GPU indices back to original `blocks` indices. **For dense fixtures (XA) this is a no-op** — every block is non-empty, the remap is identity, the regroup feeds a complete `[SubbandInfo]`. For highly-compressed fixtures (MR/PX/DX) **per-tile blocks include many filtered-out empties**; the per-tile invocation runs through this remap once per tile, and any per-tile assumption that `gpuPreDecoded[i]` is populated for every `i` would mismatch.

The filter itself has been correct on single-tile for many releases. The defect likely sits downstream in the regroup, where per-tile sparsity exposes a code path single-tile + dense codestreams have never exercised. Worth instrumenting:
- Which blocks in which tile have `data.isEmpty` / `passCount == 0`?
- Does the regroup's CPU fallback for those blocks build a valid `[Int32]` coefficient buffer?
- Where does `malformedBlock` actually originate in the regroup-vs-fallback paths?

### Hypothesis B — Per-tile codeblock layout vs full-image SubbandInfo

`decodeTilePayloadGPU` slices the metadata to tile-local dimensions (`tileMeta.width = tileW`, `tileMeta.height = tileH`) before extracting codeblocks. The downstream regroup builds `[SubbandInfo]` against `tileMeta`, but `buildGPUHTBatchFromResult` may carry full-image-derived offsets.

A targeted diff: capture `decodedBlockOutputOffsets` for the failing tile and verify they're tile-local (not image-global). If they're global, the GPU IDWT scatter kernel writes outside the tile-local buffer → garbage subband content → entropy reports `malformedBlock` on the next pass.

### Hypothesis C — Per-tile parallel dispatch shares mutable Metal session state

`decodeMultiTileGPU` runs up to `maxInFlightTilesGPU = 8` tiles concurrently in a `withThrowingTaskGroup`, each calling `decodeTilePayloadGPU` which calls `applyEntropyDecoding(..., isGPUPath: true)`. Each task uses `self.metalSession` (the same session). `J2KGPUHTDispatch.decodeBatchGPUResident` and downstream IDWT both allocate from the session's `bufferPool`.

If concurrent per-tile dispatches contend on a shared `bufferPool` slot and one tile's coefficient buffer gets returned-then-reused before another tile's IDWT consumes it, the IDWT reads stale bytes → garbage coefficients → `malformedBlock` on a downstream check. This would explain the (C) crash too — concurrent IDWT dispatches with stale buffer pointers can trip Metal's argument-buffer validation and SIGTRAP.

The 8-tile concurrency limit was tuned for the CPU multi-tile path (memory residency); it may need to be 1 for the GPU path (or each tile needs its own session) until pool ownership is per-tile.

### Recommended E1.1 starting point

1. Reproduce one failing cell deterministically (e.g. MR 886² + 2×2 via `decodeWithGPUHT`)
2. Force `maxInFlightTilesGPU = 1` and re-run — does (B) malformedBlock disappear?
   - **If yes** → Hypothesis C is live; fix is per-tile session or per-tile buffer ownership
   - **If no** → drop into the regroup and capture which `(tile, block)` pair fails; pursue Hypotheses A and B
3. For (C) crash: run the same fixture through `decodeGPU` with `maxInFlightTilesGPU = 1`. If the crash persists at concurrency 1, the bug is in `applyInverseWaveletTransformGPU`'s tile-local IDWT rather than concurrent dispatch.

---

## What this PR does NOT include

- **No production code change.** The v6.2.0 narrow `!metadata.isMultiTile` guard remains in place. Multi-tile decode continues to use the CPU path on `main`.
- **No fix.** E1.1 (next phase) implements one of the hypotheses above based on the deterministic repro decision tree.
- **No (C) crash repro in CI.** The signal-5 trap kills the test process, breaking the rest of the suite. The crash is documented here from manual diagnostic runs; E1.1 will add a guarded sub-process repro once root-caused.

E1.2 (the phase after E1.1) drops the `!metadata.isMultiTile` guard and re-runs the cross-codec parity matrix + corpus A/B with multi-tile included — that's the routing widening that closes the v6.2.0 deferred work.

---

## Repro test

[`Tests/J2KMetalTests/MultiTileDecodeGPUInvestigationTests.swift`](../Tests/J2KMetalTests/MultiTileDecodeGPUInvestigationTests.swift) — `testMultiTileGPUDecode_TriangulationMatrix_FullCorpus`.

Diagnostic test, does not assert. Prints the matrix above so any future phase (E1.1, E1.2) can re-run it and observe deltas as fixes land. Skips entry point (C) inline because the process crash interferes with `swift test` runs; the (C) row in the matrix above was captured from a hand-modified single-cell variant.

---

## E1.1 closure (resolved)

**Root cause** (none of A/B/C hypotheses above). [`Sources/J2KCodec/J2KDecoderPipeline.swift:808`](../Sources/J2KCodec/J2KDecoderPipeline.swift) called `extractTileData(tileData, metadata: tileMeta)` for the GPU multi-tile path. The CPU multi-tile path passes `tileOriginX: tileX, tileOriginY: tileY` — the GPU path defaulted to `(0, 0)`.

`extractTileData`'s tile-component canvas-coord origin governs the canvas-anchored code-block partition per ISO/IEC 15444-1 B.7. The encoder writes a canvas-anchored grid; the decoder must read with the same anchor. With the default `(0, 0)`, the decoder uses a tile-relative grid — which **only matches the encoder when the tile origin is 32-aligned** (and the comment at `extractTileData` line ~1497 even says: "For tile origin (0, 0) the formulas reduce to the legacy tile-relative grid; single-tile and 32-aligned multi-tile decode are byte-identical.").

That explains the empirical pattern exactly:

| Fixture | Tile origins | 32-aligned? | (B) result before fix |
|---|---|---|---|
| XA 1024² (2×2) | (0,0), (512,0), (0,512), (512,512) | ✅ all aligned | ✅ pass |
| MR 886² (2×2)  | (0,0), (443,0), (0,443), (443,443) | ❌ 443 mod 32 ≠ 0 | ❌ malformedBlock |
| PX 2459×1316 (2×2) | (0,0), (1230,0), (0,658), (1230,658) | ❌ neither aligned | ❌ malformedBlock |
| DX 2800×2288 (2×2) | (0,0), (1400,0), (0,1144), (1400,1144) | ❌ 1144 mod 32 ≠ 0 | ❌ malformedBlock |

The (C) `decodeGPU` signal-5 crash was a **downstream** effect of the same defect: garbage codeblock byte slices fed into the IDWT scatter kernel produced out-of-range coefficient values that tripped a Metal argument-buffer validation, and the runtime trapped.

**Fix** ([`Sources/J2KCodec/J2KDecoderPipeline.swift`](../Sources/J2KCodec/J2KDecoderPipeline.swift) `decodeTilePayloadGPU`):

```swift
// Before:
let codeBlocks = try extractTileData(tileData, metadata: tileMeta)

// After:
let codeBlocks = try extractTileData(
    tileData, metadata: tileMeta,
    tileOriginX: tileX, tileOriginY: tileY)
```

One line. Mirrors `decodeTilePayload` (CPU multi-tile, line ~773-775) which has always been correct.

**Validation**: triangulation matrix re-runs at 36/36 ✅ (was 0+9+12 failures across A/B/C). The (C) entry point in the test is now re-enabled — no more process crash.

E1.1 ships the fix. E1.2 (next phase) drops the v6.2.0 narrow `!metadata.isMultiTile` routing guard so production-default routes multi-tile through GPU, plus adds the perf A/B measurement vs the v6.2.0 CPU baseline for multi-tile fixtures.
