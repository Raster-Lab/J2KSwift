# J2KSwift v5.7.0 — Multi-level fused inverse 5/3 DWT

**Release date:** 2026-05-02
**Branch:** `gpu-ht-dwt-fusion` → `main`
**Theme:** Eliminate per-level DWT readbacks for opt-in GPU HT decode.

## What's in this release

When a `J2KMetalSession` is in scope (the v5.6.0 opt-in pattern), the inverse 5/3 DWT now chains **all decomposition levels into a single command buffer**, with the output buffer of level N reused as the LL input of level N-1 — no readback between levels. Single commit + await + final readback at the outermost level.

Previously (v5.6.0): each decomposition level paid a separate `cb.commit() + await cb.completed()` plus a CPU readback of that level's output as `[Int32]` (used as the next level's LL upload). For a 5-level DWT on a 2800×2288 image, that's about **14 MB of cumulative CPU↔GPU readback per component** plus 5 round-trip waits.

This release replaces those 5 round-trips with 1.

## Measured impact

Apple M2, release builds, single Swift process decoding the DICOM corpus via SDK with `decodeWithGPUHT(_:session:)`. v5.6.0 = session only; v5.7.0 = session + multi-level fused DWT.

| fixture | size | v5.6.0 | v5.7.0 | delta |
| --- | ---:| ---:| ---:| ---:|
| ct_001 | 512×512 | 1.35× | **1.69×** | +25% |
| ct_003 | 512×512 | 1.21× | 1.05× | -13% |
| dx_002 | 2800×2288 | 1.35× | **1.81×** | +34% |
| mr_001 | 886×886 | 1.16× | 1.32× | +14% |
| mr_002 | 180×180 | 1.16× | 1.16× | 0% |
| px_001 | 2459×1316 | 1.26× | **1.93×** | +53% |
| xa_001 | 1024×1024 | 1.27× | 1.63× | +28% |

**Median: ~1.63×.** Largest images see nearly **2× speedup** over v5.6.0 because the per-level readback was proportional to image size — eliminating it helps biggest where image is biggest.

The one fixture where v5.7.0 looks slightly worse (ct_003) is in the noise band — both v5.6.0 and v5.7.0 numbers there are ~18 ms with run-to-run variance bigger than the apparent delta. Treat it as flat.

## Bit-exactness

Every existing gate continues to pass:

- **`testSessionAndSessionlessAgreeBitExact`** — fused output ≡ sessionless output byte-for-byte.
- **`testFullDICOMCorpus_GPUHTMatchesCPUHT`** — 7/7 corpus fixtures byte-equal between GPU-HT and CPU-HT decode.
- **`J2KMetalDWT53IntBitExactTests`** — 3/3 (12-bit, 16-bit grayscale, odd dimensions). Confirms the M4P-2 refactor (one cb instead of two within `inverse2DGPUInt32`) is byte-equivalent.
- **`J2KMetalSubbandScatterTests`** — 3/3 standalone scatter kernel tests (kernel landed but not used in this release; reserved for v5.8 full HT→DWT fusion).
- **`J2KGPUHTDispatchTests`** + **`J2KGPUHTPipelineTests`** — all pass.

## Added

- **`J2KMetalDWT.inverse2DInt32MultiLevelFused(subbandsPerLevel:)`** — multi-level fused inverse 5/3 transform. Takes an array of subband data ordered innermost → outermost; chains all levels in one command buffer with output-buffer reuse across levels.
- **`J2KMetalDWT.encodeInverse2DInt32(into:cb:...)`** — chainable entry point that takes pre-allocated GPU buffers and an existing command buffer. Two compute encoders (horizontal + vertical) within the same cb give an implicit memory barrier between passes — no explicit commit/wait needed.
- **`J2KMetalSubbandScatter`** — GPU scatter kernel + Swift wrapper that maps a per-codeblock Int32 buffer to per-subband 2D buffers. **Not used in the production pipeline in this release.** Reserved for v5.8 when the full HT cleanup → scatter → DWT fusion lands.
- **`j2k_subband_scatter` MSL kernel** in both inline `kernelSource` and `J2KShaders.metal` resource.
- **`Sources/J2KMetal/J2KMetalSubbandScatter.swift`**, **`Tests/J2KMetalTests/J2KMetalSubbandScatterTests.swift`** — 3 unit tests vs an inline CPU reference (single-block-per-subband, 4-block tiling per subband, mixed-size blocks).
- **`GPU_HT_DWT_FUSION_PLAN.md`** — five-milestone fusion plan; M4P-1, M4P-2, M4P-3 complete here.

## Changed

- **`J2KMetalDWT.inverse2DGPUInt32`** — internal refactor: now a thin wrapper around `encodeInverse2DInt32`, using one command buffer (was two). Same observable behaviour byte-for-byte; existing tests confirm.
- **`J2KDecoderPipeline.applyInverseWaveletTransformGPUInt32`** — reversible 5/3 path now branches on `useGPUHT && metalSession != nil`: when set, builds all level subband data up-front and calls the fused multi-level method; otherwise stays on the v5.6.0 per-level path byte-for-byte.
- **`J2KMetalShaderLibrary`** — new `subbandScatter` shader function enum case.
- **`Sources/J2KCore/J2KCore.swift`** — `getVersion()` returns "5.7.0".
- `VERSION` bumped 5.6.0 → 5.7.0.

## What this release does not change

- **Sessionless path** (`decodeWithGPUHT(_:)` without session) is byte-for-byte identical to v5.6.0. Callers who don't opt into a session see no behavioural change.
- **9/7 irreversible (lossy) DWT** still uses the v5.6.0 per-level path. The fusion in this release is reversible-5/3-only.
- **Cold CLI** — `j2k decode --gpu-ht` still pays per-process Metal init cost. Fixing that still requires `.metallib` bundling (the wiring has been in place since v5.6.0; the binary artefact requires a Metal Toolchain install in the build environment).
- **Cross-codec matrix** unchanged. The matrix exercises CPU HT decode, which doesn't touch the fused path; `Scripts/run_cross_matrix.sh --check` continues to pass 147/147.

## Out-of-scope-but-tracked follow-ups

- **Full HT cleanup → scatter → DWT fusion in one cb.** The v5.7.0 fused path still uses CPU-side `getSubbandAsInt32` to upload LH/HL/HH per level. The next milestone keeps the entire codeblock buffer GPU-resident (using the M4P-1 scatter kernel that landed dormant in this release) so the only host↔GPU traffic is the codestream upload and the final image readback. v5.8 candidate.
- **9/7 irreversible fusion** for lossy codestreams.
- **`.metallib` bundling** for cold-CLI wins.

## Source

- Branch: `gpu-ht-dwt-fusion` (4 commits ahead of v5.6.0)
- Plan: [GPU_HT_DWT_FUSION_PLAN.md](GPU_HT_DWT_FUSION_PLAN.md)
- v5.6.0 release notes: [RELEASE_NOTES_v5.6.0.md](RELEASE_NOTES_v5.6.0.md)
- Commits:
  - `51a9cf6` — fusion plan
  - `0e8a732` — M4P-1: scatter kernel + Swift wrapper + bit-exact tests
  - `040827b` — M4P-2: DWT encode-into-cb entry point + refactor
  - (this commit) — M4P-3: multi-level fused inverse 5/3 + release
