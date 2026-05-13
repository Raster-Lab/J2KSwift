# J2KSwift v5.10.0 — Storage-mode pass

**Release date:** 2026-05-02
**Branch:** `gpu-uma-optimization` → `main`
**Theme:** Second milestone of the UMA optimization detour.

## What's in this release

v5.9.0 made the rule that arrays only live at API boundaries — never inside the pipeline. v5.10.0 enforces the next rule on top of it: any buffer the GPU writes and reads without CPU touching it allocates as `.storageModePrivate`. The Metal stack picks faster memory layouts and skips implicit coherency syncs for those allocations.

Migrated to `.private`:

- **`colLowBuffer`, `colHighBuffer`** in `inverse2DInt32FullFusedFromCodeblocks`. Per-iteration scratch between the horizontal and vertical IDWT encoders.
- **Per-level subband buffers** `lhBuffer`, `hlBuffer`, `hhBuffer`, and the innermost-level `llBuffer` (when `initialLL == nil`, i.e. the v5.9 fast lane). The CPU `memset` zero-init was replaced with `MTLBlitCommandEncoder.fill(buffer:range:value:)` running in the same cb, before the scatter encoder reads the buffers.
- **Per-iteration `outputBuffer`** for non-final IDWT levels. Intermediate output becomes the next level's LL via `currentLLBuffer = outputBuffer`. The final iteration's output stays `.shared` because the caller's readback path calls `.contents()` on it.
- **`sgnMagBuffer`** in both `runIntegerMagnitude` and `runIntegerMagnitudeReturningBuffer`. Cleanup-kernel writes, dequant-kernel reads, never CPU.

Stays `.shared` (correctly):

- Descriptor uploads, codestream pool, scatter `descBuffer`, VLC tables — all CPU-written at the API boundary.
- Final IDWT output buffer (last `levelsPlan` iteration) — read back via `.contents()` at the caller.
- HT cleanup `outputBuffer` — slow paths slice per-block coefficients via `.contents()`.

## Buffer pool prerequisite fix

`J2KMetalBufferPool` previously bucketed pooled buffers by **size only**. Mixing storage modes in one bucket would silently swap a shared buffer for a same-sized private request (or vice versa) at acquire time — undefined behaviour. The pool now keys on `(size, storageMode)`, with the storage mode pulled from the allocation strategy at acquire and from `MTLBuffer.storageMode` at return. No caller change required; existing `.shared` callers stay in the shared bucket.

## Perf

| fixture | size | v5.9.0 | v5.10.0 |
| --- | ---:| ---:| ---:|
| ct_001 | 512×512 | 1.59× | 1.57× |
| ct_003 | 512×512 | 1.49× | 1.46× |
| dx_002 | 2800×2288 | 2.27× | **2.51× (+10%)** |
| mr_001 | 886×886 | 1.49× | 1.45× |
| mr_002 | 180×180 | 1.14× | 1.25× |
| px_001 | 2459×1316 | 1.86× | 1.79× |
| xa_001 | 1024×1024 | 1.49× | 1.52× |

dx_002 (the largest fixture) clears the plan's "≥5% warm speedup" gate. The smaller fixtures are within run-to-run noise — `.private` storage's win compounds with allocation size, and dx_002's per-tile working set is the only one where the layout/coherency-sync cost crosses the threshold cleanly. v5.11's heap-backed pool is the next compounding win.

## Bit-exactness

- `testFullDICOMCorpus_GPUHTMatchesCPUHT` (7/7) ✓
- `testCorpusSessionAndSessionlessAgreeBitExact` ✓
- `testSessionAndSessionlessAgreeBitExact` ✓
- All scatter / dispatcher unit tests ✓

## What this release does not change

- **Sessionless path is byte-for-byte identical to v5.9.0.** v5.10 changes are scoped to the fast-lane / fused-IDWT path.
- **Codeblock buffer (HT cleanup `outputBuffer`)** stays `.shared` because slow-path callers slice it via `.contents()`. Splitting the entry points to give the fast lane a `.private` codeblock buffer is a v5.12+ optimization.

## Next

v5.11.0 — `MTLHeap`-backed buffer pool. v5.10's `(size, storageMode)` segregation already creates per-mode buckets; v5.11 heap-allocates within each.
