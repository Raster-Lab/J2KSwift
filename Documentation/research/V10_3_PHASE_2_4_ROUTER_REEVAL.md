# v10.3 Phase 2-4 — MG router re-eval (closed wash)

**Branch:** `v10.3-research`
**Status:** Phase 2-4 closed wash. `recommendedDecodeAPI` ≥15 MP → `.cpu` threshold stays correct after tiled Metal iDWT default-on.

## Question

Phase 1B (commit `0d68836`) measured forcing `.decodeGPU` on MG regressed by 27 ms vs the default `.cpu` pick — under the **scalar Metal iDWT** kernel. Now that Phase 2-2-tiled flipped the tiled kernel default-on (commit `0694b3d`), making the Metal iDWT 1.5× faster on the isolated microbench, **does the router decision flip on MG?**

## Measurement

DICOMKit substitute driver, M2 release, `J2K_METAL_IDWT_TILED=1` (default-on).

| MG router config | `.auto` ms | `.cpu` ms | `.decodeGPU` ms |
|---|---:|---:|---:|
| Default (router picks `.cpu` for ≥15 MP) | 114.35 | **110.07** | 115.63 |
| Forced `.decodeGPU` via `J2K_AUTO_DECODE_API=decodeGPU` | 119.53 | 107.95 | 124.40 |

**Same-run `.cpu` vs `.decodeGPU` comparison on MG:**
- Default run: `.cpu` 110.07 vs `.decodeGPU` 115.63 → **`.cpu` wins by 5.56 ms**
- Forced run: `.cpu` 107.95 vs `.decodeGPU` 124.40 → `.cpu` wins by 16.45 ms

CPU iDWT path consistently beats GPU iDWT path on MG, even after tiled Metal iDWT default-on.

## Why CPU still wins on MG

Recall Phase 0 stage profile (post-D1.5-D, post-Phase-1A) attributed ~78% of MG `.decodeGPU` wall to iDWT (90+ ms isolated GPU iDWT stage). Tiled Metal iDWT cut that by 1.5× → expected MG `.decodeGPU` wall drop of ~26 ms. Measured: MG `.decodeGPU` actually dropped from ~127 ms (v9.5.2 baseline) to 115.6 ms (current with tiled) = −11 ms. The win is real but smaller than the isolated microbench projects.

CPU iDWT on MG is around 80-85 ms — still faster than tiled Metal iDWT's ~60-65 ms PLUS the upload/dispatch/readback overhead of the GPU path. On M2's unified-memory architecture, the GPU path doesn't have a memory-locality advantage on a 16.8 MP fixture.

## Decision

**Phase 2-4 closes wash.** Router `recommendedDecodeAPI` keeps `pixels ≥ 15_000_000 → .cpu`. No code change.

## What was tested

- `J2K_AUTO_DECODE_API=decodeGPU` forcing the router to pick GPU for MG → measured regression vs default.
- Default router behaviour with tiled Metal iDWT on → measured win vs v10.0.0 (-17 ms MG `.auto` row from earlier Phase 2-2-tiled gate run).

## What's next

Phase 2-5 — release candidate v10.1.0 (decoder-only optimisation). Mandatory warm cross-codec bench citation, RELEASE_NOTES, README + OPTIMAL_PERFORMANCE_GUIDE updates, then standard RELEASING.md flow to main.
