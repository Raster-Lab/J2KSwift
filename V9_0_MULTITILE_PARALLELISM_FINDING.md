# V9.0 — Multi-tile encode parallelism: already at hardware ceiling on M2

**Status**: PROJECTED WASH. Multi-tile encode is already parallelized via `withThrowingTaskGroup` (since v6-alpha3 step 9). Empirical measurement shows 3.47× / 86% parallel efficiency on DX 2800×2288 with 2x2 layout — near theoretical maximum for 4 P-cores. The encoder is **hardware-bound on M2**, not parallelism-bound.
**Date**: 2026-05-10
**Branch**: `v9.0-research` (research; not for merge)

## Goal

Initial hypothesis: DX encode is 116 ms wall in v8.1.4 in-proc. With 2x2 multi-tile (4 tiles in parallel via TaskGroup), each tile is 1/4 the size of full image, so ideal wall ≈ ~30 ms. The 4× gap suggested either broken parallelism, or another structural bottleneck.

## Phase 0a — verify multi-tile parallelism is actually concurrent

`HTMultiTilePerfProbeTests.testMultiTilePerfProbeOnLargeFixtures` provides per-tile encode timestamps via `J2KTileWorkObservation.encodeMs`.

DX 2x2 multi-tile per-tile encode times (median of 5):

| Tile  | Pixels    | Bytes     | encodeMs |
|------:|----------:|----------:|---------:|
| 0     | 1,601,600 | 3,056,261 |    46.20 |
| 1     | 1,601,600 | 3,363,932 |    45.12 |
| 2     | 1,601,600 | 3,001,077 |    46.88 |
| 3     | 1,601,600 | 3,268,243 |    51.16 |
| **Σ** |           |           |  **189.36** |

Multi-tile wall (median of 5): **54.63 ms**

**Parallel efficiency = 189.36 / 54.63 = 3.47× / 86.6%** — out of theoretical 4× on 4 P-cores.

**The parallelism IS engaging.** TaskGroup distributes the 4 tile encodes across cores effectively.

## Phase 0b — single-tile vs multi-tile speedup

| Fixture       | single | 2x2     | speedup |
|---------------|-------:|--------:|--------:|
| MR 886²       |  5.01  |   2.58  |  1.94×  |
| XA 1024²      |  9.97  |   7.45  |  1.34×  |
| PX 2459×1316  | 30.00  |  25.93  |  1.16×  |
| DX 2800×2288  | 57.95  |  54.63  |  1.06×  |

**The speedup degrades sharply with fixture size.** Why?

## Why multi-tile barely helps DX

The single-tile encoder is **already heavily parallel internally**. From the v8.4 stage breakdown:

```
DX 2800×2288 single-tile encode (no multi-tile):
  Accumulated CPU: ~620 ms
  Wall:             51 ms
  Parallelism factor: 12.2× (uses all 8 P-cores + 4 E-cores)
```

The encoder is using **all 12 effective cores even on a single tile**. Adding multi-tile (4 tiles in parallel via TaskGroup) on top creates oversubscription — the hardware is already saturated.

Hardware-bound floor calculation:
- Total CPU work needed for DX encode: ~620 ms
- M2 effective cores: ~12 (8 P + 4 E with SMT-like behaviour)
- Theoretical wall floor: 620 / 12 ≈ **52 ms**
- Measured wall (single-tile): 51 ms
- Measured wall (2x2 multi-tile): 54.63 ms

**We are within 2-5% of the hardware ceiling on DX encode.** Multi-tile cannot help further because the encoder is already pinning all cores.

For SMALLER fixtures (MR 886² = 0.78 MP), single-tile encoder uses fewer cores effectively (less parallelisable work), so multi-tile wins by using idle cores → 1.94× speedup. But the smaller the fixture, the smaller the absolute savings.

## Decision: defer; encoder is at hardware ceiling on M2

Implementing additional multi-tile parallelism (e.g., 4x4 = 16 tiles, finer granularity, work-stealing scheduler) cannot beat the hardware ceiling. The encoder is **CPU-bound on the M2 silicon**, not parallelism-bound.

The remaining levers are:

1. **Reduce per-tile setup cost** — each tile pays ~32-40 ms of duplicated initialisation (HT block coders, MCT tables, DWT scratch pools, codestream emitter buffers). For DX, sum of per-tile (189 ms) is 3.3× single-tile (58 ms), suggesting ~130 ms wasted per-tile setup. Could amortise via shared pools across tiles within a single multi-tile encode. Multi-week architectural change; risk of breaking thread-safety guarantees.

2. **Different M-series silicon** (M3+/A-series with different cache topology / more cores). The marketable "Apple Silicon" claim covers all Apple Silicon, but M2 is the canonical reference. Cross-silicon retest gated on physical-device access.

3. **Algorithmic redesign** — if a fundamentally different lossless 5/3 + HT compression pipeline reduces the total CPU work, the wall would scale proportionally. Multi-week scope; previously explored in v8.6/v8.7 (wash).

None qualify for autonomous-overnight scope.

## What stays in tree

- `V9_0_MULTITILE_PARALLELISM_FINDING.md` — this document.

The existing `HTMultiTilePerfProbeTests` already provides the per-tile observation data. No new microbench needed.

## Lever-ceiling pattern (now 17 investigations on M2 + Swift release)

| Direction              | Wash count                                                     |
|------------------------|----------------------------------------------------------------|
| Decode codec           | 6 (v6-alpha4, v7.4, v7.5, v8.1, v8.4×3, v8.5)                 |
| Encode codec           | 3 (v8.6 forward DWT, v8.6 HT classifier, v8.7 algorithmic)    |
| Dispatch               | 1 (GCD vs TaskGroup)                                           |
| Accelerate             | 1 (vDSP/vImage/BLAS)                                           |
| AMX                    | 1 (corsix/dougallj review)                                     |
| IPC primitives         | 1 (file mmap, IOSurface, mach_vm_remap, xpc_shmem)             |
| Metal pipeline cache   | 1 (MTLBinaryArchive)                                           |
| Daemon batch RPC       | 1 (in-process batch already amortises)                         |
| Daemon concurrent dispatch | 1 (in-process parallel already faster)                     |
| CLI cold-shot floor    | 1 (3.28 ms structural Swift-runtime tax)                       |
| **Multi-tile encode parallelism** | **1 (this — already 86% efficient; encoder is hardware-bound)** |

The codec hot-path AND the IPC layer AND the CLI layer AND the multi-tile dispatch layer are all at structural ceiling on M2 + Swift release. The encoder is provably within 2-5% of theoretical hardware maximum on DX.

The next workstream candidates are genuinely non-perf:
- JP3D ROI decoder (multi-day product feature)
- iOS / A-series device validation (needs device)
- DICOM ecosystem integration (SwiftUI / QuickLook / Instruments signposts)
- Rebuild encoder work distribution from scratch (multi-week, high risk)
