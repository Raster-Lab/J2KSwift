# J2KSwift v5.8.0 — End-to-end fused HT cleanup → scatter → DWT

**Release date:** 2026-05-02
**Branch:** `gpu-ht-full-fusion` → `main`
**Theme:** Architectural milestone, not a perf headline.

## What's in this release

The v5.7.0 release landed a **GPU subband scatter kernel** but kept it dormant — the production pipeline still did CPU-side regrouping of HT codeblock output into 2D subband buffers per level. v5.8.0 wires it in. When the v5.6.0 session opt-in is active and the codestream is HTJ2K conformant cleanup-only reversible 5/3:

- **One** `decodeBatchGPUResident` call decodes all eligible codeblocks into a GPU-resident buffer, sliced into per-block `[Int32]` arrays from the same shared-memory storage (so the existing `[SubbandInfo]` regroup path keeps working byte-for-byte without a second GPU dispatch).
- **One** `inverse2DInt32FullFusedFromCodeblocks` call chains GPU scatter (codeblock buffer → per-subband 2D buffers) and multi-level inverse 5/3 in a single command buffer, with the output of level N reused as the LL input of level N-1.
- **One** final readback at the outermost level. No host↔GPU traffic in the middle.

The end-to-end fused HT decode → DWT GPU path that's been the goal of v5.6 → v5.7 → v5.8 is now in place.

## Honest perf story

Median warm-process speedup is **~1.5×** in v5.8 vs **~1.6×** in v5.7.0. Within run-to-run variance — they're effectively equivalent on this hardware:

| fixture | size | sessionless (ms) | v5.8 fused (ms) | speedup |
| --- | ---:| ---:| ---:| ---:|
| ct_001 | 512×512 | 14.01 | 10.06 | 1.39× |
| ct_003 | 512×512 | 14.66 | 9.71 | 1.51× |
| dx_002 | 2800×2288 | 106.98 | 62.00 | 1.73× |
| mr_001 | 886×886 | 16.31 | 12.00 | 1.36× |
| mr_002 | 180×180 | 6.43 | 5.28 | 1.22× |
| px_001 | 2459×1316 | 56.14 | 33.23 | 1.69× |
| xa_001 | 1024×1024 | 22.92 | 14.51 | 1.58× |

**Why v5.8 isn't a clear win over v5.7.0:** the per-level CPU upload of LH/HL/HH that the GPU scatter kernel replaces was already cheap on Apple Silicon's unified memory. v5.7.0 captured most of the achievable warm-process speedup; v5.8 makes the path architecturally cleaner without moving the perf needle.

**Why ship it anyway:** it's the foundation. The full GPU-resident pipeline shape is now in production. Future milestones (multi-tile in-flight, GPU colour transform, GPU dequantisation rewiring, 9/7 lossy fusion) all build on this shape. v5.8 gets the architecture in place without regressing v5.7.0.

## Bit-exactness

Every gate that passed in v5.7.0 continues to pass:

- **`testSessionAndSessionlessAgreeBitExact`** — fused output byte-equal to sessionless output.
- **`testFullDICOMCorpus_GPUHTMatchesCPUHT`** — 7/7 corpus fixtures byte-equal between GPU-HT and CPU-HT decode.
- **`J2KMetalDWT53IntBitExactTests`** — 3/3 (12-bit, 16-bit, odd dimensions).
- **`J2KMetalSubbandScatterTests`** — 3/3 unit tests for the now-active scatter kernel.
- **`J2KGPUHTDispatchTests`** + **`J2KGPUHTPipelineTests`** — all pass.
- **`J2KMetalSessionTests.testWarmProcessSpeedup`** — passes (1.50× on 512×512 fixture).

## What this release does not change

- **Sessionless path is byte-for-byte identical to v5.7.0.** Callers using `decodeWithGPUHT(_:)` (no session) get exactly the same behaviour as v5.7.0.
- **9/7 irreversible (lossy) DWT** stays on the v5.6.0 per-level path. v5.8 fusion is reversible-5/3 only.
- **Cold CLI** numbers from v5.5.0 are unchanged. `.metallib` bundling stays wired but dormant.
- **Cross-codec matrix** unaffected — exercises CPU HT decode, doesn't touch the fused path.

## What landed (M5P-1..4 of the v5.8 plan)

- **M5P-1a**: `J2KMetalHTCleanup.runIntegerMagnitudeReturningBuffer` — buffer-keeping variant of v5.6.0's `runIntegerMagnitude`.
- **M5P-1b**: `J2KGPUHTBatch` Sendable struct + `J2KGPUHTDispatch.decodeBatchGPUResident` entry that produces both per-block `[Int32]` and the GPU buffer in one decode (the dedupe).
- **M5P-2**: `J2KMetalDWT.inverse2DInt32FullFusedFromCodeblocks` + `LevelScatterPlan` — the end-to-end fused DWT method.
- **M5P-3**: pipeline plumbing — `applyEntropyDecoding` returns the optional batch, `applyInverseWaveletTransformGPU` consumes it.
- **M5P-4**: dedupe — collapses the duplicate GPU decode that the first M5P-3 cut introduced. Drives perf back to v5.7.0 parity from a regression.

The five-milestone plan in `GPU_HT_FULL_FUSION_PLAN.md` originally scoped M5P-4 as a separate milestone. The v5.8 first cut shipped a regression on small images (duplicate GPU decode cost > per-level upload savings); the dedupe reverts that.

## Out-of-scope-but-tracked follow-ups

- **9/7 irreversible fusion.**
- **Multi-tile in-flight cbs** to overlap CPU prep of tile N+1 with GPU decode of tile N.
- **GPU colour transform / DC offset fusion** to keep the full decode pipeline GPU-resident.
- **`.metallib` bundling** for cold-CLI wins (still wired but dormant; needs Metal Toolchain in build env).

## Source

- Branch: `gpu-ht-full-fusion` (5 commits ahead of v5.7.0)
- Plan: [GPU_HT_FULL_FUSION_PLAN.md](GPU_HT_FULL_FUSION_PLAN.md)
- v5.7.0 release notes: [RELEASE_NOTES_v5.7.0.md](RELEASE_NOTES_v5.7.0.md)
- Commits:
  - `22ae542` — fusion plan
  - `2bdfe76` — M5P-2: full-fused DWT method
  - `7ce25c7` — M5P-1a: buffer-returning HT cleanup
  - `b376e67` — M5P-1b + M5P-3: pipeline plumbing (had regression — fixed by next commit)
  - `57c4ad3` — M5P-4: dedupe GPU decode
  - (this commit) — release wrap-up
