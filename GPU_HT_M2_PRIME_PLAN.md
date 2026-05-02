# GPU HT decoder — M2-prime plan (production integration)

**Branch:** `gpu-ht-prod-integration`
**Target release:** v5.5.0
**Predecessor:** v5.4.0 (`gpu-ht-phase3` merged to `main`)

## Goal

Wire `J2KMetalHTCleanup` (kernel-level bit-exact, 1.14× CPU as of v5.4.0) into the production decoder so that end-user `j2k decode` on HTJ2K codestreams can opt in to GPU entropy decode. After M2-prime, the kernel-level wins from phase-3 actually reach users.

## Why this is the right next milestone

v5.4.0 shipped a kernel that's bit-exact and modestly faster than CPU on a synthetic 777×64×64 benchmark, but **the production decoder still routes HT entropy decode entirely to CPU**. The phase-3 perf wins are kernel-level only — invisible to anyone running `j2k decode`. M2-prime closes that gap.

It's also the prerequisite for any future cb-fusion work (the original M2 in the phase-3 plan): once HT cleanup is in the pipeline, the natural next step is collapsing HT-cleanup → dequant → DWT into one command buffer.

## Scope

### In scope

1. **Tile-level GPU HT batch dispatch**: collect all conformant HT cleanup-only codeblocks of a tile into one `J2KMetalHTCleanup.run(...)` call, instead of decoding one block at a time CPU-side.
2. **Opt-in flag** in `J2KConfiguration` (e.g. `useGPUHT: Bool = false`) and a CLI surface (`--gpu-ht`) so the existing CPU path stays default.
3. **Bit-exact parity** with the CPU HT path on the cross-codec fixture set (7 DICOM PGMs in `Tests/Fixtures/CrossCodec/`).
4. **Graceful fallback** when Metal isn't available, when the codestream isn't pure cleanup-only conformant HT (e.g. has refinement passes), or when the tile has no HT blocks.
5. **Module wiring**: `J2KCodec` will need to import `J2KMetal` (currently doesn't). Add the dependency in `Package.swift`.

### Out of scope (deferred)

- **GPU dequantisation kernel.** Dequant per sample is `let shift = 30 - missingMSBs; if sign { -mag } else { mag }` — trivial. CPU-side after readback is fine for v5.5.0; promote to GPU in a later release if profiling justifies it.
- **GPU subband scatter / regroup.** Codeblocks already decode into independent buffers; placing them into subband grids is per-CB memcpy. CPU-side is fine.
- **Refinement-pass HT** (`useConformant == false` path). Rare in practice; CPU-only.
- **HT-cleanup → DWT command-buffer fusion** (the original phase-3 M2). Becomes feasible once the integration shape stabilises in v5.5.0.

## Integration map

The CPU HT decode lives in two parallel-loop branches in `J2KDecoderPipeline.swift`:

- [J2KDecoderPipeline.swift:1402-1428](Sources/J2KCodec/J2KDecoderPipeline.swift#L1402-L1428) — chunked parallel path
- [J2KDecoderPipeline.swift:1507-1530](Sources/J2KCodec/J2KDecoderPipeline.swift#L1507-L1530) — sequential fallback

Both call `htDecoder.decodeCleanupConformant(rawBytes:missingMSBs:)`, which routes to:

- [J2KHTConformantDispatch.swift:92-107](Sources/J2KCodec/J2KHTConformantDispatch.swift#L92-L107) → `HTBlockDecoderConformant.decode(...)` returning `[UInt32]` in OpenJPH sign-magnitude.

The dequantisation step that lands lines 100-106 of that file is the only "post-processing" needed: shift right by `(30 - missingMSBs)`, apply sign.

GPU integration replaces the per-block `htDecoder.decodeCleanupConformant` calls with a tile-level batch:

```swift
// Filter the chunk's blocks down to conformant cleanup-only HT
let gpuEligible = blocks.filter { $0.isConformantCleanupOnly }
let cpuFallback = blocks.filter { !$0.isConformantCleanupOnly }

// CPU path for non-eligible (refinement, custom-format)
let cpuResults = try cpuFallback.parallelMap { ... }

// GPU batch for eligible
var pool: [UInt8] = []
var descriptors: [J2KMetalHTCleanupBlockDescriptor] = []
var blockOutputOffsets: [Int] = []

for block in gpuEligible {
    guard let parsed = HTBlockLayoutConformant.parse(block: [UInt8](block.data))
    else { /* fallback to CPU for this block */ continue }

    let magsgnOffset = UInt32(pool.count)
    pool.append(contentsOf: parsed.magsgn)
    let melVlcOffset = UInt32(pool.count)
    pool.append(contentsOf: parsed.melVlc)

    descriptors.append(J2KMetalHTCleanupBlockDescriptor(
        magsgnOffset: magsgnOffset,
        magsgnLength: UInt32(parsed.magsgn.count),
        melVlcOffset: melVlcOffset,
        melVlcLength: UInt32(parsed.scup),
        outputOffset: UInt32(blockOutputOffsets.last ?? 0),
        width: UInt32(block.width),
        height: UInt32(block.height),
        missingMSBs: UInt32(block.zeroBitPlanes)
    ))
    blockOutputOffsets.append(blockOutputOffsets.last! + block.width * block.height)
}

let (gpuOutput, _) = try await metalHTCleanup.run(
    descriptors: descriptors,
    codestreamPool: pool,
    vlcTable0: vlcDecoderTable0Conformant,
    vlcTable1: vlcDecoderTable1Conformant,
    outputSampleCount: totalSamples)

// CPU-side dequant per block
for (i, block) in gpuEligible.enumerated() {
    let shift = 30 - block.zeroBitPlanes
    let start = blockOutputOffsets[i]
    let end = start + block.width * block.height
    coeffs[i] = gpuOutput[start..<end].map { uint in
        let sign = (uint & 0x8000_0000) != 0
        let mag = Int32((uint & 0x7FFF_FFFF) >> shift)
        return sign ? -mag : mag
    }
}
```

The reusable encapsulation goes in a new file:

**`Sources/J2KCodec/J2KGPUHTDispatch.swift`** — owns the eligibility check, the descriptor batch builder, the GPU run, and the dequant loop. Keeps `J2KDecoderPipeline.swift` lean.

## Sequencing and milestones

| Milestone | Scope | Wall-clock | Validation |
|---|---|---|---|
| **M2P-1** | Add `J2KMetal` to `J2KCodec` Package deps; new `J2KGPUHTDispatch.swift` skeleton with eligibility + batch builder; no pipeline integration yet; unit test that the batch builder produces the same descriptors the manual test code produces | 1 day | New unit tests pass |
| **M2P-2** | Wire into `J2KDecoderPipeline.swift` parallel + sequential paths behind `useGPUHT` flag (default `false`); CPU path unchanged when flag is off | 1–2 days | Existing tests pass with flag off |
| **M2P-3** | Bit-exact parity gate: with `--gpu-ht`, decode every `Tests/Fixtures/CrossCodec/*.j2k` and `*.jph` and confirm pixel output matches CPU path byte-for-byte | 1 day | New gate test passes |
| **M2P-4** | CLI surface (`--gpu-ht` flag in `j2k decode`); cross-codec matrix updated to add `--gpu-ht` columns and confirm 7×N×2 cells match baseline; release notes | 1 day | Cross-codec matrix passes |
| **M2P-5** | Perf measurement: end-to-end `j2k decode` with `--gpu-ht` vs without on full DICOM corpus; report wall-clock delta. Set realistic expectations — savings depend on what fraction of decode time is HT entropy | 1 day | Perf report committed |

Total: ~5–6 days of focused work. Each milestone independently mergeable.

## Risks and unknowns

- **The fraction of decode time spent in HT entropy decode is not yet measured.** It's possible that DWT, file I/O, and component combination dominate, in which case M2-prime's user-visible win is small. We accept this risk: the integration is independently valuable as a foundation for fusion work in v5.6.
- **Refinement-pass HT blocks** (non-conformant cleanup-only) and **custom-format HT** stay on CPU. The eligibility filter must be conservative; misclassifying a block sends garbage to GPU. Default to CPU-fallback when in doubt.
- **VLC tables visibility**: `vlcDecoderTable0Conformant` is currently `internal` in `J2KCodec`. The new dispatch file lives in the same module, so this works without API surface changes. If we ever extract HT to a separate module, the tables would need to become `public`.
- **Module dependency change**: `J2KCodec` adding a `J2KMetal` dependency is a non-trivial Package.swift edit. Verify Linux builds still work (Metal is `#if canImport(Metal)`-gated inside J2KMetal — should already be safe).
- **Buffer pool lifetime**: the `J2KMetalHTCleanup` instance should be created per-pipeline (not per-tile) so its `bufferPool` can amortise across tiles. The existing struct is `Sendable` and lightweight to construct, but the pool's hit rate matters for perf.

## Verification gates (every milestone)

1. **Bit-exactness**: existing `J2KMetalHTCleanupTests` continue to pass; new GPU-vs-CPU pipeline test passes pixel-by-pixel on the DICOM corpus.
2. **No-flag regression**: with `useGPUHT: false` (default), all existing tests pass byte-for-byte the same as v5.4.0. `Scripts/run_cross_matrix.sh --check` stays green.
3. **Linux build**: `swift build` on Linux (no Metal) compiles cleanly with the flag accessible but always falling through to CPU.

## Out-of-scope-but-tracked follow-ups

- **GPU dequant kernel** — small scope, fits in v5.6.
- **HT-cleanup → DWT cb fusion** — the original phase-3 M2 idea, now feasible because the chain exists in code.
- **HT custom-format on GPU** — only if user demand surfaces.
- **GPU HT encode** — different problem; not on the critical path.
