# J2KSwift v5.4.0 — GPU HTJ2K decoder phase-3

**Release date:** 2026-05-02
**Branch:** `gpu-ht-phase3` → `main`
**Companion:** continuation of v5.3.0; the cross-codec verification harness, comparisons, and codestream output are unchanged.

## What's in this release

A perf-focused follow-up to v5.3.0's GPU HTJ2K cleanup-pass decoder prototype. The MSL kernel itself is byte-identical to v5.3.0 and remains bit-exact with `HTBlockDecoderConformant.decode` on CPU. What changed is **how the kernel is dispatched and how its auxiliary buffers are managed**.

Three pieces:

1. **Buffer pool integration.** `J2KMetalHTCleanup` and `J2KMetalHTMagSgn` now acquire per-frame buffers from `J2KMetalBufferPool` and explicitly return them after readback. Static VLC tables (2 × 1024 UInt16) are uploaded once into a cached MTLBuffer on `J2KMetalShaderLibrary` and reused thereafter.

2. **Warp-packing dispatch.** The HT cleanup dispatch changed from `dispatchThreadgroups((blockCount,1,1), (1,1,1))` — one threadgroup per codeblock, 31 of 32 SIMD lanes idle on every warp — to `dispatchThreads((blockCount,1,1), (min(blockCount,64),1,1))`. Apple's SIMD scheduler now packs 64 codeblocks (two warps) into each threadgroup. The kernel uses only thread-private state and per-thread offset reads, so no shared memory or barriers are required.

3. **Readback pattern fix.** The MagSgn readback was using the deprecated-pattern `Array.withUnsafeMutableBytes { copyBytes(from: MTLBuffer.contents()) }`, which is known to deadlock in release builds (the HT cleanup readback was switched away from this in v5.3.0). The buffer pool's actor hop shifted timing enough to start triggering the same deadlock path here, so MagSgn was switched to the safe `Array(unsafeUninitializedCapacity:) + memcpy` pattern as well.

## Measured impact

Release builds, Apple M-series, 777 × 64×64 codeblocks:

| version | cpu (ms) | gpu_kernel (ms) | gpu_wall (ms) | speedup vs CPU |
| --- | ---: | ---: | ---: | ---: |
| v5.3.0 (phase-2) | 6.69 | 6.14 | 7.15 | 0.93× |
| v5.4.0 (phase-3) | 6.76 | 4.93 | 5.94 | **1.14×** |

Cumulative since the original phase-2 release-mode measurement (where GPU was ~0.5× CPU): **0.5× → 1.14×, all bit-exact, all gates green.**

The remaining gap between observed (1.14×) and theoretical (deep-SIMD ≫1×) speedup comes from **branch divergence between codeblocks of different sizes/densities** within a SIMD warp. Threads in a warp execute the most divergent control-flow path, so utilisation depends on the workload's CB-size uniformity. Pushing further would require either size-binning before dispatch or restructuring the per-CB algorithm to expose intra-CB parallelism past the sequential MEL/VLC/MagSgn bit readers — the original "Phase A/B split" idea in `GPU_HT_PHASE3_PLAN.md` turned out to be infeasible because the per-quad e_q recovery feeds back into the next-row state machine.

## What end users will see

**No functional change.** The GPU HT cleanup decoder is still **tests-only** — the production decoder (`J2KDecoderPipeline.applyMetalDWT`) routes HT entropy decode to the CPU path and uses the GPU only for the inverse DWT. The wins above are kernel-level and are a prerequisite for, but not a substitute for, production integration.

The natural next milestone — provisionally tagged **M2-prime** in `GPU_HT_PHASE3_PLAN.md` — wires `J2KMetalHTCleanup` into `J2KDecoderPipeline` behind an opt-in flag, alongside the dequantisation and subband-regrouping kernels needed to turn HT cleanup output into DWT input. That's the release that would actually deliver GPU HT decode to users.

## Comparison framing

This release **does not change** any of the v5.3.0 cross-library numbers. OpenJPEG and OpenJPH remain the well-established reference C/C++ implementations of JPEG 2000 Part 1 and Part 15 respectively, and v5.3.0's positioning notes — including the explicit acknowledgement that OpenJPH is faster than J2KSwift on HTJ2K wall-clock — still apply. v5.4.0's wins are J2KSwift-internal (CPU vs GPU on the same algorithm); they do not redraw any of the cross-codec comparisons.

## Verification

- `J2KMetalHTCleanupTests`: 7/7 release-mode pass — `testAllZeroBlock`, `testFullCodeblock`, `testGPUvsCPUSpeedup`, `testManyBlocksDispatch`, `testShaderLoadOnly`, `testSmallBlock`, `testTinyBlock`. Every codeblock matches CPU reference byte-for-byte.
- `J2KMetalHTMagSgnTests`: 4/4 release-mode pass.
- `Scripts/run_cross_matrix.sh --check`: 126/126 cells match v5.3.0 baseline byte-for-byte. (Exercises the production CPU-HT decoder; serves as a regression check for unrelated systems but does not directly exercise the M3 changes.)

## Caveats and known limits

- **Numbers are configuration-specific.** Apple GPU divergence behaviour varies across M1/M2/M3/M4 generations and across workloads with different codeblock-size distributions. The 1.14× number is a single representative point, not a guarantee.
- **No new public-facing API.** `J2KMetalBufferPool` and `J2KMetalShaderLibrary.vlcTableBuffers` are existing/internal; their callers — `J2KMetalHTCleanup` and `J2KMetalHTMagSgn` — already had public structs in v5.3.0. The bufferPool init parameter is additive (defaults to a fresh pool), so existing callers compile unchanged.
- **Cross-codec matrix is a "no-break" check, not an M3 perf gate.** Because production HT decode is on CPU, the matrix doesn't observe the M3 dispatch change. The bit-exactness gate that actually exercises M3 is `J2KMetalHTCleanupTests`.

## Acknowledgements

The OpenJPEG project (UCL) and Aous Naman's OpenJPH remain the reference implementations the J2KSwift codestream output is verified against. The v5.3.0 cross-codec interop matrix continues to be the load-bearing correctness check for everything user-facing in this codebase.

## Source

- Branch: `gpu-ht-phase3` (merged to `main` for tagging)
- Plan: [GPU_HT_PHASE3_PLAN.md](GPU_HT_PHASE3_PLAN.md)
- Commits:
  - `cf1c8f5` — phase-3 plan doc
  - `3deed65` — M1: buffer pool + VLC table caching
  - `3f79c6c` — M3: warp-packing dispatch
