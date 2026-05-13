# J2KSwift v5.11.0 — `MTLHeap`-backed buffer pool

**Release date:** 2026-05-02
**Branch:** `gpu-uma-optimization` → `main`
**Theme:** Third and final milestone of the UMA optimization detour.

## What's in this release

The v5.10.0 buffer pool already amortised allocations after warmup — same-size buckets get reused across decodes. v5.11.0 makes the *allocator side* cheaper too: pool misses now go to a per-storage-mode `MTLHeap` instead of `device.makeBuffer`. Heap sub-allocations consolidate Metal's per-buffer driver bookkeeping into one resident resource — the driver tracks lifetime, residency, and hazard metadata for the heap as a whole, not for ~15 transient buffers per (tile, component) the v5.8 fused dispatch creates.

How it works:

- One `MTLHeap` per storage mode (`.shared` and `.private`), lazily created on first miss for that mode and reused across decodes.
- Default heap size 96 MB per storage mode, sized for the largest fixture in the DICOM corpus (dx_002 2800×2288, ~32 MB single-component peak; ~96 MB for a 3-component frame). Configurable on `J2KMetalBufferPoolConfiguration.heapSize`.
- Heap creation gated on `device.supportsFamily(.apple4)` — M-series Macs only. Intel-Mac hardware skips the heap and falls through to `device.makeBuffer`. Same correctness on both — just no driver-bookkeeping savings on the older path.
- Fallback to `device.makeBuffer` when the heap is full (via `heap.maxAvailableSize(alignment: 16K)` check) or when `heap.makeBuffer` returns `nil`. Heap-only would create cliff-edge failures on out-of-spec inputs.

## Perf

| fixture | size | v5.10.0 | v5.11.0 |
| --- | ---:| ---:| ---:|
| ct_001 | 512×512 | 1.57× | **1.89× (+20%)** |
| ct_003 | 512×512 | 1.46× | **1.78× (+22%)** |
| dx_002 | 2800×2288 | 2.51× | 2.53× (saturated) |
| mr_001 | 886×886 | 1.45× | **1.91× (+32%)** |
| mr_002 | 180×180 | 1.25× | **1.93× (+54%)** |
| px_001 | 2459×1316 | 1.79× | 2.03× (+13%) |
| xa_001 | 1024×1024 | 1.52× | **1.92× (+26%)** |

Smaller fixtures gain disproportionately — they were the ones where allocator + driver bookkeeping was the dominant cost, since the per-decode compute work fits in a few hundred microseconds and any constant overhead skews the ratio. dx_002 was already saturated (compute-dominant) so heap brings little additional delta; that's the expected shape.

## UMA detour summary (v5.7.0 → v5.11.0)

The three-milestone detour started after v5.8.0 wrapped up the architectural fusion work. Final state:

| metric | v5.7.0 | v5.11.0 |
| --- | ---:| ---:|
| median warm speedup | 1.63× | **~1.92×** |
| peak warm speedup | 1.93× | **2.53×** (dx_002) |
| hot-path memcpy / decode | varies | **1** (final readback only) |
| hot-path .contents() / decode | varies | **1** (final readback only) |
| hot-path makeBuffer / decode | varies | **0** on most fixtures |

The plan's headline counter targets:

- ✓ v5.9: `memcpyCount` → 0 on hot path (final API readback excluded). Achieved.
- ✓ v5.10: `.contents()` count = 0 on `.private` buffers. Achieved by construction (no `.contents()` call on any `.private` buffer in the codebase).
- ✓ v5.11: `makeBufferCount` drops by ≥10× per decode. Achieved on warmup (heap absorbs first-decode allocations); steady-state at ~0 makeBuffer calls per decode for most fixtures.

## Bit-exactness

- `testFullDICOMCorpus_GPUHTMatchesCPUHT` (7/7) ✓
- `testCorpusSessionAndSessionlessAgreeBitExact` ✓
- `testSessionAndSessionlessAgreeBitExact` ✓
- `testHTJ2KLossless512_GPUHTMatchesCPUHT`, `testHTJ2KLossless_GPUHTMatchesCPUHT` ✓
- All scatter / dispatcher / DWT unit tests ✓

## What this release does not change

- **Sessionless path is byte-for-byte identical to v5.10.0.**
- **Final IDWT readback** is still memcpy=1, contents=1. That's the API-boundary copy out to `[Double]` for the colour transform stage. Closes naturally with v5.13's GPU colour transform fusion (queued).

## Next: v5.12+ resumes the queued roadmap

The UMA detour is complete. Per the original plan, v5.12+ resumes:

1. **v5.12** — Multi-tile in-flight command buffers (overlap CPU prep of tile N+1 with GPU decode of tile N)
2. **v5.13** — GPU colour transform / DC offset fusion (also drops the final memcpy=1 / contents=1)
3. **v5.14** — 9/7 irreversible (lossy) DWT fusion
4. **v5.15** — `.metallib` bundling for cold-CLI wins
