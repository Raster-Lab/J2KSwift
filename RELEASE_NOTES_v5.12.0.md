# J2KSwift v5.12.0 — Bounded multi-tile concurrency

**Release date:** 2026-05-03
**Theme:** Cap in-flight tile decodes; resume the v5.12+ queued roadmap.

## What's in this release

The v5.9 → v5.11 UMA detour wrapped up with `memcpy=1, contents=1, makeBuffer=0` on the hot path for single-tile codestreams. The next planned milestone — multi-tile in-flight command buffers — turned out to need less work than the plan implied: the multi-tile decode paths (`decodeMultiTile` for CPU, `decodeMultiTileGPU` for GPU) already used `withThrowingTaskGroup` to run tile tasks concurrently. The actual gap was that the TaskGroup was *unbounded* — all N tile tasks spawned up front.

For a 100-tile codestream that's a problem. Each tile holds its peak working set of buffers (per-level DWT scratch, subband buffers, output buffer). With v5.11.1's 256 MB heap default per storage mode, tile 14-or-so onward can't fit in the heap and falls through to `device.makeBuffer`. That defeats the v5.11 amortization win.

v5.12 adds chunked-TaskGroup bounding:

```swift
while tileIdx < tiles.count {
    let chunk = Array(tiles[tileIdx..<min(tileIdx + 8, tiles.count)])
    let chunkResults = try await withThrowingTaskGroup(...) { ... }
    decodedTiles.append(contentsOf: chunkResults)
    tileIdx = end
}
```

Tile chunks process sequentially; tiles within a chunk run concurrently. `maxInFlightTilesGPU = 8` keeps peak heap residency bounded. The CPU path uses the same pattern with `maxInFlightTilesCPU = 8`.

## Test coverage

- **`testMultiTileBoundedConcurrencyRoundTrip`** (new) — encodes a synthetic 256×256 grayscale image with 64×64 tiles (16 tiles total — exceeds the 8-tile chunk size, so the chunked-TaskGroup runs at least 2 chunks). Asserts session and sessionless GPU-HT decodes produce identical output.
- **All v5.11.1 corpus gates** continue to pass — single-tile fixtures take exactly one slot and observe identical behaviour to v5.11.1.

## Perf

No measurable change on the existing DICOM corpus (single-tile fixtures = 1 task = 1 chunk). The architectural value is bounded heap residency for multi-tile codestreams.

## Bit-exactness

- `testFullDICOMCorpus_GPUHTMatchesCPUHT` (7/7) ✓
- `testCorpusSessionAndSessionlessAgreeBitExact` ✓
- `testSessionAndSessionlessAgreeBitExact` ✓
- `testMultiTileBoundedConcurrencyRoundTrip` (new) ✓
- All scatter / dispatcher unit tests ✓

## What this release does not change

- **Sessionless path is byte-for-byte identical to v5.11.1.**
- **Session path on single-tile codestreams is unchanged.**
- **True pipelined overlap of CPU prep and GPU decode within a single tile** — would require restructuring stages as async producer-consumer chains. Deferred.

## Notes on the v5.12+ original plan

The plan listed v5.12 as "Multi-tile in-flight command buffers (overlap CPU prep of tile N+1 with GPU decode of tile N)". The existing TaskGroup already provides task-level concurrency; the actual missing piece was the in-flight count bound. The "true pipelined overlap" framing turned out to be either already-present (between tile tasks) or a much larger refactor (within a tile, across stages).
