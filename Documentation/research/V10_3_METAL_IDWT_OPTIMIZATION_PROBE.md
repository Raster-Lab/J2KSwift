# v10.3 Phase 2 — GPU iDWT Metal shader optimization probe

**Branch:** `v10.3-research`
**Status:** scoping; no production code change planned for this phase.
**Predecessor finding:** [`V10_3_DECODE_STAGE_REPRIORITISATION.md`](V10_3_DECODE_STAGE_REPRIORITISATION.md) — Phase 0 showed iDWT is now 63 % of DX wall / 78 % of MG wall, with GPU iDWT taking 23 ms (DX) and 90+ ms (MG) on the production path. The closing-the-gap arc therefore targets Metal shader optimization, not Swift/C CPU work.

## Why this arc exists

Three independent measurements converge on the same conclusion:

1. **Stage profile (medical corpus perf test, M2 release, lossy 9/7):**
   - DX `decodeSingleTileGPU`: iDWT 23.3 ms (63 %) vs entropy 9.3 ms (25 %).
   - MG `decodeSingleTileGPU`: iDWT 90–99 ms (78 %) vs entropy 14–15 ms (12 %).

2. **Router A/B (Phase 1B):** forcing MG to `.decodeGPU` regresses by 27 ms vs the default router's `.cpu` pick. **CPU iDWT is already faster than GPU iDWT on MG** at 16.84 MP.

3. **Kakadu comparison:** Kakadu does MG decode in 68 ms TOTAL. J2KSwift GPU iDWT alone takes 90+ ms. The gap is concentrated in `applyInverseWaveletTransformGPU`.

This is **not** the structural lever-ceiling pattern of v6-alpha4 through v10.2 (which were all Swift / C / CPU surfaces with documented memory-bound or boundary-cost ceilings). The Metal shader path is **un-probed at the kernel-tile level**.

## What the current Metal kernels look like

[`Sources/J2KMetal/J2KShaders.metal`](../../Sources/J2KMetal/J2KShaders.metal) inverse 5/3 integer kernels (the production path for lossless):

- `j2k_dwt_inverse_53_horizontal_int` (lines 643–686): one thread per row, scalar loop, three sequential passes over device memory.
- `j2k_dwt_inverse_53_vertical_int` (lines 690–731): one thread per column, **strided device-memory access** with stride = width (3520 × 4 = 14 KB stride on MG). No threadgroup-memory tiling, no shared memory.

Concrete inefficiencies (verified by reading the kernels):

| Issue | DX impact | MG impact | Fix pattern |
|---|---:|---:|---|
| One thread per row/column | bounded grid: 4784 / 3056 threads | 3520 / 4784 threads | 2D thread layout with threadgroup tiling |
| No threadgroup memory | every read from device memory | every read from device memory | Cooperative tile load → shared compute |
| Strided vertical access | stride = 2800 × 4 = 11.2 KB | stride = 3520 × 4 = 14 KB | Tile transpose in threadgroup memory |
| RAW hazard between steps | step 2 reads what step 1 wrote in device memory | same | Pass intermediate via threadgroup memory |
| Multi-level dispatch overhead | 5 levels × 2 passes (row+col) × 3 bands = 30 dispatches | 5 × 2 × 3 = 30 dispatches | Fused multi-level kernel (already partially done in `inverse2DInt32MultiLevelFused`, but inner kernels not tiled) |

The standard Metal/CUDA DWT optimisation pattern is **tile-mined cooperative threadgroup-memory lifting** — well-trodden in the literature (cf. NVIDIA's CUDPP DWT, AMD's RocBLAS-like wavelet kernels). None of that pattern is in the current Metal shader.

## Phase sequencing (8-12 week arc)

### Phase 2-0 — Isolated GPU iDWT microbench (1-2 days, no shader change)

Build a harness that times just `applyInverseWaveletTransformGPU` for DX (2800×2288) and MG (3520×4784) Int32 single-component inputs, multi-level (5 levels), 1 component. Mirror the v10.1 microbench pattern: synthetic deterministic input, warmups + median-of-N, separate per-level timing if achievable.

**Files (this commit, on `v10.3-research`)**:
- `Tests/J2KMetalTests/V10_3_MetalIDWTMicrobench.swift` (new)
- This document (already created).

**Exit criteria**: stable per-fixture median ms for the current Metal kernel, broken down per-level. Variance < 5%. Numbers reproducible.

**Probability**: 100% — pure measurement.

### Phase 2-1 — Single-kernel tile-mined prototype (1 week)

Write **one** new Metal kernel: `j2k_dwt_inverse_53_tiled_int` that processes a 32×32 tile in threadgroup memory. Apply both row and column lifting from threadgroup memory before writing back. This is a prototype proving the tile-mining pattern delivers a meaningful per-kernel speedup vs the current scalar-per-row/-column kernels.

**Files**:
- `Sources/J2KMetal/J2KShaders.metal` (add prototype kernel; keep existing kernels)
- `Sources/J2KMetal/J2KMetalDWT.swift` (add A/B routing flag)
- `Tests/J2KMetalTests/V10_3_MetalIDWTTiledParityTests.swift` (new — bit-exact vs current kernel)
- `Tests/J2KMetalTests/V10_3_MetalIDWTTiledMicrobench.swift` (new — A/B timing)

**Parity surface**: every (width, height) combination over the substitute corpus + 100 random sizes. Bit-exact Int32 output.

**Exit criteria**: tiled kernel is bit-exact AND ≥ 1.5× faster than scalar on at least one of DX / MG single-level work.

**Stop trigger**: tiled kernel < 1.2× faster than scalar at any level → close. Metal threadgroup memory may not help if the kernel is memory-bound at the finest level (66 MB working set on MG exceeds all caches).

### Phase 2-2 — Full multi-level fused tiled kernel (2-3 weeks)

If Phase 2-1 clears, extend the tile-mined kernel to handle the multi-level chain in one dispatch (or a tightly-fused per-level dispatch with threadgroup-memory hand-off where possible). The current `inverse2DInt32MultiLevelFused` driver already loops levels in one CB; the inner kernels just need to be the tiled variant.

**Files**: same as 2-1, expanded.

**Exit criteria**:
- `J2KMedicalCorpusPerformanceTests` shows DX `.decodeGPU` wall ≥ 3 ms below v10.0.0 baseline.
- `J2KStrictCrossCodecValidationTests` clean.
- Bit-exact across the full 33-fixture corpus.

**Stop trigger**: wall reduction < 3 ms — drop back to Phase 2-1's narrower scope (just MG, or just deepest levels).

### Phase 2-3 — Pipeline integration + env-gated default flip (1 week)

Mirror D1.5-C's pattern: env var `J2K_METAL_IDWT_TILED=1` defaults on. Opt-out path falls back to current scalar kernels. Cross-codec validation gate clean under both.

**Files**:
- `Sources/J2KMetal/J2KMetalDWT.swift` (default flag flip)
- `Tests/J2KMetalTests/V10_3_*` (regression suite)

**Exit criteria**: 3-run warm cross-codec bench shows DX `.decodeGPU` consistent improvement ≥ 3 ms; MG `.cpu` may not move (the router picks CPU iDWT for MG ≥15 MP; rank-3 of the re-prioritised lever order also matters here — see below).

### Phase 2-4 — MG-specific evaluation (1 week)

The current router puts MG (16.84 MP) on the `.cpu` path. After Phase 2-2 lands, **re-evaluate whether MG should go on `.decodeGPU` again**. The closing condition is `GPU iDWT post-2-2 < CPU iDWT on MG`. If yes, drop the 15 MP threshold accordingly.

**Files**: `Sources/J2KCodec/J2KCodec.swift` recommendedDecodeAPI thresholds.

### Phase 2-5 — Release candidate v10.1.0 or v10.2.0 (1 week)

Standard RELEASING.md flow. Minor bump (no codestream byte change — decoder-only optimisation).

## Honest priors

- **Metal shader work has a different lever-ceiling than Swift/C.** v6-alpha4 through v10.2's 9 wash investigations are not directly informative. The structural ceiling on M2 GPU is memory bandwidth (~100 GB/s LPDDR5 unified) plus dispatch overhead per kernel (~50 µs).
- **Threadgroup memory tiling is a known-good pattern** with documented order-of-magnitude wins on CUDA DWT kernels. Apple M2 GPU is architecturally similar (unified memory + threadgroup memory + SIMD lanes).
- **MG is hardest because its finest level (66 MB Int32 buffer) exceeds all M2 caches.** Even an optimal tiled kernel will hit memory bandwidth at the finest level. The theoretical floor is `66 MB × 2 reads / 70 GB/s = 1.9 ms` per finest-level pass + similar for write. Stacking 5 levels with halving each time gets us a hard floor around 8-12 ms iDWT wall.
- **A 2-3× speedup on Metal iDWT is plausible.** Current MG iDWT is 90 ms; theoretical floor is ~8-12 ms; intermediate target is 30-50 ms. That would drop MG decode wall from 122 ms to 60-80 ms — close to Kakadu's 68 ms.

## What WON'T fix the gap

Verified by reading the Metal code + cross-checking history:

1. **SIMD8 / NEON 256-bit** — Apple GPU is SIMT, not SIMD-vector. Doesn't apply.
2. **More dispatches in parallel** — the current path already serialises per-level (data dependency). Splitting per-band concurrently inside a level may help (separate command buffers per band → coalescing on the row pass) but bounded.
3. **GPU HT entropy** — already on (v8.4 measured wash; v10.0.0 default-on for batched).
4. **Different decode mode** — Phase 1B showed `.decodeGPU` is slower than `.cpu` on MG; the router is right.

## Critical files (for the implementer)

- [`Sources/J2KMetal/J2KShaders.metal`](../../Sources/J2KMetal/J2KShaders.metal) lines 643-731: current inverse 5/3 integer kernels.
- [`Sources/J2KMetal/J2KMetalDWT.swift`](../../Sources/J2KMetal/J2KMetalDWT.swift) line 1408: `inverse2DInt32MultiLevelFused` — the entry point that dispatches the multi-level chain.
- [`Sources/J2KCodec/J2KDecoderPipeline.swift`](../../Sources/J2KCodec/J2KDecoderPipeline.swift) line 3937-3947: `applyInverseWaveletTransformGPU` — the caller from `decodeSingleTileGPU`.
- [`Tests/J2KMetalTests/J2KMedicalCorpusPerformanceTests.swift`](../../Tests/J2KMetalTests/J2KMedicalCorpusPerformanceTests.swift): the corpus-wall measurement gate.

## What I'm doing this session

- **Phase 2-0 only**: write the probe doc (this file) and the isolated GPU iDWT microbench harness. No shader changes. The microbench gives us the reproducible per-level baseline that every subsequent phase will measure against.

The full Metal shader work in Phase 2-1 → 2-5 is a multi-week commitment. Start it once Phase 2-0 baseline is in place.
