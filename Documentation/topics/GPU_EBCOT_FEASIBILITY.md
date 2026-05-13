# GPU EBCOT Decoder — Feasibility Investigation

**Status:** investigation, not implementation. Captures the architecture sketch, the per-codeblock cost model, the divergence/memory analysis, and the recommended path forward.

**Branch:** `gpu-lossless-bit-exact`. The work below would land on a follow-up branch `gpu-ebcot-prototype`.

---

## TL;DR

| Path                              | Verdict | Why |
| --------------------------------- | ------- | --- |
| **GPU Part 1 EBCOT decode**       | **Marginal — high risk** | MQ decoder is 8-deep nested branches per symbol. SIMT branch divergence within a warp could erase the parallelism win. CPU path is at 1.07× of OpenJPEG already. |
| **GPU Part 15 HT decode**         | **Promising** | HT cleanup pass has no MQ; MagSgn is much more uniform. OpenJPH ships an experimental MSL HT decoder. We already win HT decode by 2-9× on CPU; GPU could push to 5-20×. |
| **Recommended next step**         | **Prototype HT GPU first**, defer EBCOT GPU until data shows the dispatch+divergence overhead is acceptable on real medical workloads. |

---

## Why EBCOT is hard on GPU

### The MQ decoder is fundamentally branchy

Per coded symbol, `MQDecoder.decode` runs through up to five conditional branches before returning:

```swift
if (c >> 16) < qe {                       // ① LPS-region check
    if a < qe { ... }                     // ② conditional exchange
    else {
        if mqSwitchMPS != 0 { mps.toggle() }   // ③ MPS toggle
    }
    renormalizeDecoder()                  // ④ may loop 0-7 times
} else {                                  // MPS region
    c -= qe << 16
    if (a & 0x8000) == 0 {                // ⑤ renormalize gate
        if a < qe { ... }                 // ⑥ MPS exchange
        renormalizeDecoder()              // ④ again
    }
}
```

In Apple SIMT (32-thread warps), if codeblocks A and B at the same instruction index take different branches, the warp serialises both paths — effectively halving throughput per divergent decision. With ~5 divergent branches per symbol and ~30 symbols per coefficient × 4096 coefficients per codeblock, the divergence cost is the dominant uncertainty.

**Realistic estimate**: warp efficiency 30-50% on EBCOT decode. Going from 8-core CPU (with branch prediction + speculative execution) to ~1500-ALU GPU at 30% efficiency yields a parallelism ratio of `(1500 × 0.3) / 8 ≈ 56×`. But each GPU thread is ~5-8× slower per branch than a CPU thread (no branch prediction, narrower issue width). Net: maybe 7-11× speedup if it works at all.

### Per-codeblock state size limits parallelism

Per 64×64 codeblock, the decoder needs four arrays:

| Array       | Type            | Size     |
| ----------- | --------------- | -------- |
| magnitudes  | UInt32 [4096]   | 16 KB    |
| signs       | Bool [4096]     |  4 KB    |
| states      | UInt8 [4096]    |  4 KB    |
| halfBits    | UInt32 [4096]   | 16 KB    |
| **Total**   |                 | **40 KB** per codeblock |

Threadgroup memory on Apple GPUs is 32 KB on M1/M2 (64 KB on M3+). One codeblock per threadgroup forces:

- Either threadgroup memory (fast but limited to ~6 codeblocks per SM at once)
- Or device memory (much more capacity, but ~10× slower per access)

Packed layout (1 UInt32 per coef encoding mag + sign + state + halfBit): **16 KB per codeblock** → 2 codeblocks fit in threadgroup memory comfortably, or 4 packed.

### Apple GPU dispatch overhead is non-trivial for small batches

Metal command buffer commit + completion: ~50-200 µs of fixed overhead per dispatch. For 777 codeblocks per 1024×1024 RGB Part 1 lossless decode, you must run them in **one dispatch** (one kernel handling all blocks via grid dimensions). Per-codeblock kernel launches would cost 38-155 ms in dispatch overhead alone — instantly losing the entire CPU runtime.

This is achievable: encode the per-block input offsets / sizes into a single `MTLBuffer<BlockDescriptor>` and launch a 1D grid of `block_count` threads, one per codeblock. But the kernel must self-schedule and self-synchronise across blocks of the same image (no cross-block dependencies — fortunately EBCOT is per-block independent).

---

## Architecture sketch — IF we proceed

### Data layout

```
struct GPUCodeBlockDescriptor {        // 32 bytes
    uint32_t  dataOffset;              // byte offset into shared codestream pool
    uint32_t  dataLength;
    uint32_t  outputOffset;            // sample offset into shared output pool
    uint16_t  width, height;
    uint16_t  bitDepth;                // 4-bit packed (max 32)
    uint16_t  zeroBitPlanes;
    uint8_t   passCount;
    uint8_t   subbandKind;             // 0=LL/LH, 1=HL, 2=HH
    uint16_t  componentIndex;
    // ... + per-pass segment lengths inline if useSelectiveBypass
}

// Shared pools (single MTLBuffer each):
// codestreamPool : UInt8[Σ blockBytes]
// outputPool     : Int32[Σ width × height]
// scratchPool    : UInt32[Σ width × height]   (packed mag/sign/state/halfBit)
```

### Kernel skeleton

```metal
kernel void j2k_ebcot_decode_part1(
    device const GPUCodeBlockDescriptor* blocks [[buffer(0)]],
    device const uint8_t*  codestream            [[buffer(1)]],
    device int32_t*        output                [[buffer(2)]],
    device uint32_t*       scratch               [[buffer(3)]],
    constant uint& blockCount                    [[buffer(4)]],
    uint tid [[thread_position_in_grid]]
) {
    if (tid >= blockCount) return;
    GPUCodeBlockDescriptor desc = blocks[tid];

    // 1. Bind segment of scratch buffer for this codeblock's
    //    mag/sign/state/halfBit (packed UInt32 per coefficient).
    device uint32_t* myScratch = scratch + desc.outputOffset;
    threadgroup uint32_t mqContexts[19];  // shared per-block context array

    // 2. Reset state, init MQDecoder pointing at codestream + offset.
    MQState mq;
    mq_init(&mq, codestream + desc.dataOffset, desc.dataLength);

    // 3. Bit-plane outer loop, three passes per plane (sigprop / magref / cleanup).
    //    Same logic as the CPU `BitPlaneDecoder.decode` body.
    int activeBitPlanes = desc.bitDepth - desc.zeroBitPlanes;
    int passesDecoded = 0;
    for (int bp = activeBitPlanes - 1; bp >= 0 && passesDecoded < desc.passCount; bp--) {
        decode_sigprop_pass(...);
        decode_magref_pass(...);
        decode_cleanup_pass(...);
    }

    // 4. Reconstruct and write Int32 to output.
    write_signed_coefs(myScratch, desc, output + desc.outputOffset);
}
```

### Files to add

```
Sources/J2KMetal/J2KMetalEBCOT.swift          (~600 LoC Swift dispatch)
Sources/J2KMetal/Shaders/EBCOTKernel.metal    (~1500 LoC MSL — MQ + 3 passes + reconstruction)
Tests/J2KMetalTests/J2KMetalEBCOTTests.swift  (~400 LoC bit-exact tests)
```

### Integration with existing pipeline

In `J2KDecoderPipeline.applyEntropyDecoding`:

```swift
let useGPUEntropy = !useHT
                    && metadata.isLargeEnoughForGPU
                    && J2KMetalEBCOT.isAvailable
                    && blocks.count >= 64

if useGPUEntropy {
    return try await J2KMetalEBCOT.decodeBatch(blocks, metadata: metadata)
}
// fall through to existing CPU task-group dispatch
```

A "size threshold" gates GPU usage so small blocks (where CPU + parallel codeblocks already wins) stay on CPU.

---

## Per-codeblock cost model

| Stage                     | CPU (1024 RGB Part 1 LL Dec) | GPU (estimated) |
| ------------------------- | ---------------------------: | --------------: |
| Total decode time         | 62 ms                        | ?               |
| Entropy decoding          | 102 ms (84%)                 | ~10–30 ms       |
| Per-block work avg        | 80 µs CPU thread             | ~20-40 µs GPU thread |
| Dispatch overhead         | n/a                          | 50-200 µs (one-time) |
| Memory marshaling (in)    | n/a                          | ~1 ms (4 MB) |
| Memory marshaling (out)   | n/a                          | ~3 ms (16 MB)  |

**Best case**: 102 ms entropy → 15-25 ms total entropy. **Worst case (heavy divergence)**: 102 ms → 80-150 ms (worse than CPU).

The risk is real and the upside is bounded.

---

## Recommended path

1. **Don't start with GPU EBCOT.** The branch divergence risk + the 1.07× CPU win makes the ROI questionable.

2. **Prototype GPU HT decode first.** Same dispatch infrastructure, but:
   - HT cleanup uses MagSgn (no MQ state machine, far less branchy).
   - The inner loop is more SIMD-friendly (per-stripe column processing).
   - OpenJPH already proves it works on Apple Metal.
   - Current J2KSwift HT decode at 2-9× CPU vs OpenJPEG → could push to 10-30× with GPU.

3. **Revisit GPU EBCOT only if HT GPU lands successfully** AND there's measurable demand for Part 1 lossless throughput at >1024² that the current 1.07× isn't covering.

4. **If we do EBCOT eventually**, the architecture sketch above is the starting point. Use the existing `J2KMetalShaderLibrary` / `J2KMetalDevice` actor / `J2KMetalBufferPool` infrastructure — all already in place from the existing DWT/MCT/quantizer/ROI kernels.

---

## What investigation revealed about the existing codebase

- `J2KMetal` module already has solid foundations: device manager, async pipeline cache, buffer pool, ~12 kernels for DWT/color/MCT/quantize/ROI. **Adding entropy kernels is a build-on, not a green-field project.**
- The CPU `BitPlaneDecoder.decode` body (line 1752) is structured cleanly enough that translating to MSL is mostly mechanical — the 3 pass functions (`decodeSignificancePropagationPass` / `decodeMagnitudeRefinementPass` / `decodeCleanupPass`) plus `MQDecoder.decode` cover ~90% of what needs porting.
- `mqStatePacked` (the recent perf commit) is GPU-friendly: a 188-byte read-only LUT that fits in MSL constant memory. **Same packed table can be used verbatim in Metal.**
- The cleanup-pass-only path could be a focused first slice (~600 LoC of MSL) — most decode time is in cleanup.

---

## Open questions before commit

1. **What workload demands this?** The cross-codec report shows we already beat OpenJPEG on every Part 1 + HT decode size. Is there a customer pipeline that needs more?
2. **CI cost?** Adding a GPU EBCOT decoder doubles the test surface for entropy decode. Bit-exact tests on synthetic + real DICOM workloads — ~10 min CI extension.
3. **GPU-only requirement?** Can we keep CPU as the default and gate GPU behind a flag (preserving the lossless byte-equality guarantee on platforms without Metal)?
4. **Maintenance?** Two implementations of EBCOT means two codepaths to keep in sync when the spec is amended (rare but happens).

---

**Decision needed**: proceed to GPU HT prototype, defer GPU EBCOT? Or insist on EBCOT first?
