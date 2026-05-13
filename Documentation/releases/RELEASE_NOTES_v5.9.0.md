# J2KSwift v5.9.0 — Zero-copy CPU↔GPU boundary

**Release date:** 2026-05-02
**Branch:** `gpu-uma-optimization` → `main`
**Theme:** First milestone of the UMA optimization detour.

## What's in this release

The v5.8.0 release landed the end-to-end fused HT decode → scatter → DWT GPU path, but stages still communicated via owned `Array` types — `[Int32]` from HT decode, `[[Double]]` from DWT output, etc. On Apple Silicon UMA every `MTLBuffer.contents()` is already CPU-addressable, so copying bytes into an owned `Array` just to satisfy a Swift lifetime contract is wasted work. v5.9.0 removes those copies on the session opt-in fast lane:

- **`runZeroCopyFastLane`** in `DecoderPipeline` skips the CPU regroup loop entirely when the v5.8 fused IDWT will run downstream. Returns `([], batch)` — no `[SubbandInfo]` allocated for any subband. The fused IDWT consumes LL/LH/HL/HH directly from the GPU codeblock buffer via the scatter kernel.
- **LL on the GPU scatter path.** v5.8 had LL flowing through `initialLL: [Int32]` from CPU; v5.9 includes target=0 LL descriptors in the innermost-level scatter plan and passes `initialLL: nil`. The scatter kernel zero-fills via `MTLBlitCommandEncoder.fillBuffer` and writes the LL cells before the IDWT encoder reads them.
- **`vDSPConvert.int32sToDoubles`** replaces the per-element Swift closure for the post-DWT [Int32] → [Double] step.

The `J2KMetalUMACounters` instrumentation that landed alongside this release tracks `memcpyCount`, `bufferContentsAccessCount`, and `makeBufferCount` — they're surfaced in the existing `testCorpusWarmProcessPerf` table so every release-cycle measurement reports them.

## Honest perf story

The wall-clock improvement is modest. v5.8.0's median warm-process speedup was ~1.5×; v5.9.0's is ~1.7×:

| fixture | size | v5.8 fused | v5.9.0 |
| --- | ---:| ---:| ---:|
| ct_001 | 512×512 | 1.39× | 1.59× |
| ct_003 | 512×512 | 1.51× | 1.49× |
| dx_002 | 2800×2288 | 1.73× | 2.27× |
| mr_001 | 886×886 | 1.36× | 1.49× |
| mr_002 | 180×180 | 1.22× | 1.14× |
| px_001 | 2459×1316 | 1.69× | 1.86× |
| xa_001 | 1024×1024 | 1.58× | 1.49× |

The headline isn't the wall-clock number — it's the **counter** number. Per-decode `memcpyCount` drops from 17–1619 (varies by fixture, dominated by per-block coefficient slicing) to **1** — the single final-output readback. That's the prerequisite for v5.10's storage-mode pass: when no pipeline stage allocates an `Array` from buffer contents, no pipeline stage is reading those contents on CPU, and the buffer is safe to mark `.storageModePrivate`.

## Five iterations on the way

This release shipped through five iterations on a feature branch (v5.9a → v5.9e), with two intermediate states that were rolled back after tests caught regressions. The git log preserves the working journal:

- **v5.9a** — zero-copy fast lane with LL still uploaded as `initialLL` from CPU.
- **v5.9b** — attempted to route LL through the GPU scatter; produced all-zero output on the synthetic 384×384 fixture. Rolled back in v5.9c.
- **v5.9c** — gated off the fast lane after a test surfaced a *separate* regression on `mr_002` (180×180); shipped vDSPConvert + the corpus session/sessionless gate.
- **v5.9d** — re-enabled the fast lane with the correct downstream-IDWT precondition (`mr_002` falls back to CPU IDWT because `pixelCount < 256²`; the fast lane must skip itself).
- **v5.9e** — root-caused v5.9b's regression (a `compSubbands.isEmpty` short-circuit in `applyInverseWaveletTransformGPU` predating the fast lane, not a memory-model issue) and shipped LL-on-GPU-scatter for real.

The new `testCorpusSessionAndSessionlessAgreeBitExact` is the regression floor for any future change touching the entropy → IDWT pipeline.

## Bit-exactness

- `testFullDICOMCorpus_GPUHTMatchesCPUHT` — 7/7 corpus fixtures byte-equal between GPU-HT and CPU-HT decode.
- `testCorpusSessionAndSessionlessAgreeBitExact` — every PGM in CrossCodec/, session and sessionless decode produce byte-identical output.
- `testSessionAndSessionlessAgreeBitExact` — synthetic 384×384, byte-equal.
- `testHTJ2KLossless512_GPUHTMatchesCPUHT`, `testHTJ2KLossless_GPUHTMatchesCPUHT` ✓
- `J2KMetalSubbandScatterTests`, `J2KGPUHTDispatchTests`, `J2KGPUHTPipelineTests` ✓

## What this release does not change

- **Sessionless path is byte-for-byte identical to v5.8.0.** Callers using `decodeWithGPUHT(_:)` (no session) get exactly the same behaviour as v5.8.0.
- **9/7 irreversible (lossy) DWT** stays on the v5.6.0 per-level path. The fast lane is reversible-5/3 only.
- **Small-image path** (`pixelCount < 256*256`, e.g. mr_002 180×180) takes the slow lane — the GPU IDWT bails out to CPU there and the fast lane skips itself.

## Next

v5.10.0 — storage-mode pass. v5.9's zero-copy invariant makes `.storageModePrivate` mechanically enforceable on GPU-only intermediates: when no pipeline stage allocates an `Array` from buffer contents, no buffer needs to stay CPU-coherent.
