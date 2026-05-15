# v10.3 Phase 2-2 — end-to-end A/B finding (DEFAULT-FLIP DEFERRED)

**Branch:** `v10.3-research`
**Status:** Phase 2-2 gates run; **default-flip NOT recommended** because microbench wins do not propagate cleanly to end-to-end product paths on the headline DX/MG fixtures.
**Predecessor:** Phase 2-1 (commit `c34fcc3`) shipped the 2D-thread-layout Metal kernels behind the `J2K_METAL_IDWT_2D` env-opt-in flag.

## What I measured

`J2K_METAL_IDWT_2D=0` (scalar baseline) vs `=1` (2D-layout) on three independent gates:

### Gate A — `J2KStrictCrossCodecValidationTests` with env on

3/3 tests PASS. Cross-codec parity preserved; OpenJPH / Grok / Kakadu decode J2KSwift bytes bit-exactly with the 2D-layout iDWT active. **2D path is production-correct.**

### Gate B — `J2KMedicalCorpusPerformanceTests` A/B (same session, M2 release)

J2KSwift in-process decode wall (median ms):

| Fixture | OFF `.cpu` | ON `.cpu` | Δ | OFF `.decodeGPU` | ON `.decodeGPU` | Δ |
|---|---:|---:|---:|---:|---:|---:|
| mr_001 886² | 21.8 | 21.9 | +0.1 | 16.7 | 16.1 | −0.6 |
| xa_001 1024² | 27.3 | 27.0 | −0.3 | 17.5 | 17.7 | +0.2 |
| px_001 2459×1316 | 86.3 | 86.9 | +0.6 | 25.8 | 25.3 | −0.5 |
| **dx_002 2800×2288** | 41.7 | 53.9 | **+12.2** | 47.6 | 53.4 | +5.8 |
| **dx_001 2544×3056** | 52.5 | 54.7 | +2.2 | 49.3 | 50.7 | +1.4 |
| **mg_001 3520×4784** | 110.8 | 105.9 | **−4.9** | 114.7 | 106.8 | **−7.9** |
| **mg_002 3521×4784** | 111.1 | 110.6 | −0.5 | 111.8 | 111.9 | +0.1 |

(`CPU mode` column shows what the `decode()` API picks for the size; for ≥4 MP this routes through GPU IDWT regardless of mode name.)

Mixed pattern. dx_002 shows large regression, mg_001 shows clean win, dx_001 / mg_002 within noise.

### Gate C — DICOMKit substitute driver A/B

Closer to user product-path. `.auto` row (the Studio default):

| Modality | OFF `.auto` ms | ON `.auto` ms | Δ |
|---|---:|---:|---:|
| CT 512² | 2.34 | 2.23 | −0.11 |
| DX 2544×3056 | 60.25 | **68.43** | **+8.18** |
| MG 3520×4784 | 98.15 | 104.70 | +6.55 |
| MR 128² | 0.58 | 0.61 | +0.03 |
| PX 2793×1316 | 30.40 | 30.09 | −0.31 |
| XA 1024² | 9.79 | 8.52 | −1.27 |

DX 2544 and MG regress by 6-8 ms — **above the v7.4 3 ms threshold backwards.**

## Why microbench wins don't propagate

The Phase 2-1 isolated microbench showed:
- DX 2800×2288: 1.53× speedup
- DX 2544×3056: 1.13× speedup
- MG 3520×4784: 1.33× speedup (after accounting for the thermal-throttled outlier)

The **DX 2544 microbench result was already only 1.13×**, very close to break-even. End-to-end measurement amplifies that into a small regression because:

1. **2D-layout uses MORE encoders per pass** (2 separate encoder dispatches vs 1 in the scalar kernel). Each `makeComputeCommandEncoder()` has ~50 µs setup. The Phase 2-1 dispatch adds 4-6 extra encoder boundaries per multi-level decode — that's 200-300 µs of pure dispatch overhead.
2. **GPU under-utilisation isn't the bottleneck on the largest fixtures.** MG finest level (66 MB Int32) is memory-bandwidth-bound regardless of thread count. Adding 4-8 M threads doesn't help if the GPU is waiting on LPDDR5 fetch.
3. **Variance on large fixtures is large.** A single noisy run can flip a +3 ms result to −3 ms. The substitute test runs 7 samples; the corpus test runs ~5. Neither is enough samples to bring the ±5-10 ms noise floor on MG/DX below the signal.

## Verdict

| Phase 2-2 gate | Status |
|---|---|
| Cross-codec parity (Gate A) | PASS — 2D path is bit-exact |
| Medical corpus perf (Gate B) | MIXED — dx_002 regresses 5.8-12 ms, mg_001 wins 4.9-7.9 ms |
| DICOM Studio substitute (Gate C) | MIXED — DX 2544 +8.18 ms, MG +6.55 ms, others flat-to-favourable |

**Default-flip on v10.3-research DEFERRED.** The 2D-layout path stays env-opt-in via `J2K_METAL_IDWT_2D=1` for users who need the small-fixture wins (XA / CT / MR / PX). DX/MG production wall is best served by the scalar path on M2 v10.0.0 baseline.

## What the data tells the next phase

The Phase 2-2 finding is consistent with the architect's original ranking: **threadgroup-memory tiling** (which Phase 2-1 deliberately did NOT do — it only changed thread layout) is the actual structural lever for the large fixtures. Without threadgroup memory:
- Step 1 and step 2 must hand data through device memory (66 MB on MG, 31 MB on DX).
- The cross-step dependency forces a kernel boundary (extra encoder) that the scalar kernel avoids.
- The thread-layout speedup gets eaten by the extra encoder cost on memory-bandwidth-bound fixtures.

With threadgroup memory:
- Step 1 writes to threadgroup memory (32 KB per threadgroup, on-chip).
- Threadgroup barrier between steps (free, hardware-supported).
- Step 2 reads from threadgroup memory.
- One kernel instead of two.

That's Phase 2-2-threadgroup-tiled in the v10.3 probe doc. The expected DX/MG win from threadgroup tiling alone should be 2-3× (per CUDA/Metal DWT literature), enough to overwhelm the encoder-boundary overhead and clear the v7.4 3 ms gate on every fixture.

## What stays on the branch

- 2D-layout kernels + opt-in flag (`c34fcc3`, `d117dcc`) — kept, env-opt-in.
- Phase 2-1 parity oracle (`V10_3_MetalIDWTInverse532DParityTests`) — permanent regression check.
- Phase 2-1 microbench (`V10_3_MetalIDWTInverse532DMicrobench`) — permanent baseline.
- **This document** (`V10_3_PHASE_2_2_END_TO_END_FINDING.md`) — verdict, kept as the input to Phase 2-2-threadgroup-tiled.

## What's open

| Item | Status |
|---|---|
| 2D-layout opt-in correctness | ✓ closed (parity + cross-codec validated) |
| 2D-layout default-on | ✗ deferred (DX/MG regression on default path) |
| Threadgroup-memory tiled kernel (Phase 2-2-tiled) | open — multi-week next session |
| Release candidate v10.1.0 (Phase 2-5) | open, gated on Phase 2-2-tiled |

## Honest priors going into Phase 2-2-tiled

- Tiled kernel writing is more complex than the 2D-layout split (halo regions, threadgroup memory layout, barrier placement) but the speedup ceiling is much higher.
- The lever-ceiling pattern that washed v6-alpha4 through v10.2 was Swift/C surface; Metal threadgroup memory is a different surface and its own ceiling history (or lack thereof) needs to be established by this work.
- DX 2544 regression is the specific signal to clear — that's the substitute corpus' canonical DX fixture and the user-visible DICOM Studio target.
