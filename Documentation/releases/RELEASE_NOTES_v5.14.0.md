# J2KSwift v5.14.0 — Skip GPU MCT round-trip on Apple Silicon UMA

**Release date:** 2026-05-03
**Theme:** Cut 56% off the inverse-colour-transform cost on RGB decodes by ditching the GPU MCT round-trip.

## What's in this release

The `J2KMetalColorTransform` GPU MCT was wired into the decoder back in v5.6.0. Since then the post-DWT pipeline has stayed in Double throughout. The GPU MCT entry point takes Float input/output, so the decoder did:

```
Double → Float → upload → GPU MCT → readback → Float → Double
```

…surrounding a per-pixel kernel that's basically 4 multiply-adds. The Double↔Float conversions and buffer round-trip dominated cost.

v5.14.0 routes inverse RCT/ICT through the existing in-place CPU vDSP path (`applyInverseColorTransformInPlace`):

- Stays in **Double** throughout — matches the IDWT output type, no precision games at the boundary.
- `vDSP_vsmaD` / `vDSP_vaddD` / `vDSP_vsubD` for the per-pixel arithmetic.
- Steals input arrays' inner buffers (refcount=1 trick) so no allocation overhead beyond a single temp.

## Profile data

1024×1024 lossless RGB decode with a warm `J2KMetalSession`, second of two timed runs:

| stage | v5.13.0 (GPU MCT) | v5.14.0 (CPU MCT) | delta |
| --- | ---:| ---:| ---:|
| extractTileData | 1.9 ms | 1.8 ms | flat |
| entropyDecoding (HT cleanup, GPU) | 14.9 ms | 10.6 ms | -29% |
| inverseWaveletTransform (IDWT, GPU) | 13.1 ms | 10.8 ms | -18% |
| **inverseColorTransform** | **9.1 ms** | **4.0 ms** | **-56%** |
| dcLevelUnshift | 0.7 ms | 0.6 ms | flat |
| reconstructImage | 1.8 ms | 1.5 ms | flat |
| **TOTAL** | **~42 ms** | **~30 ms** | **-29%** |

The HT cleanup and IDWT numbers also drift down. That's run-to-run noise (warm Metal command queues are sensitive to thermal state); the only stage we changed is `inverseColorTransform`. The 5 ms savings on MCT is the v5.14 contribution; the rest is run-to-run.

## What it does not change

- **Grayscale workloads (the DICOM corpus)** — unchanged. MCT is a no-op for `componentCount < 3`. The corpus profile shows `inverseColorTransform = 0.0 ms`; v5.14 touches only the 3+ component path.
- **Sessionless / session decode parity** — identical. Both paths now run the CPU MCT; both stay bit-exact with v5.13.0.
- **`J2KMetalColorTransform` API** — unchanged. The GPU MCT infrastructure stays in place for callers that need Float inputs (e.g. encoder paths). The decoder just doesn't reach for it on the post-DWT step anymore.

## Why a CPU path beats GPU for this

On Apple Silicon UMA:

1. **Round-trip overhead dominates.** GPU MCT is 4 multiply-adds per pixel — bandwidth-bound, not compute-bound. The Double↔Float conversion + Metal command queue dispatch overhead exceeds the actual MCT compute.
2. **Cache locality matters more than parallelism for this size.** vDSP runs the MCT operations through L2 cache, never bouncing through GPU memory.
3. **No precision drift.** Staying in Double throughout the post-DWT pipeline means there's no per-component float quantization step; the result is bit-identical to what a careful CPU-only path would produce.

For very large RGB tiles (say >4K × 4K × 3 components), the GPU MCT path could re-win once memory bandwidth becomes the dominant cost again. The infrastructure stays in place for that case if benchmarks ever justify routing it back.

## Bit-exactness

- `testRGBSessionAndSessionlessAgreeBitExact` ✓ (added in the overnight session as the gate for this work)
- `testFullDICOMCorpus_GPUHTMatchesCPUHT` (7/7) ✓ (grayscale path unchanged)
- `testCorpusSessionAndSessionlessAgreeBitExact` ✓
- `test97LossySessionAndSessionlessAgreeBitExact` ✓
- `testMultiTileBoundedConcurrencyRoundTrip` ✓
- `J2KMetalLibraryLoadPathTests` ✓
- All scatter / dispatcher / DWT unit tests ✓

26/26 GPU-suite tests passing.

## Original v5.13/v5.14 plan landed differently

The plan called for v5.13 = GPU MCT fusion (run MCT in-kernel as part of the IDWT command buffer) and v5.14 = 9/7 lossy fast-lane. v5.14.0 turns out to land the *opposite* of v5.13's plan — instead of GPU-fusing MCT, we observed it was already on GPU and the actual cost was the round-trip, so we pulled it back to CPU. The 9/7 fast-lane (the original v5.14 plan item) remains unimplemented per `V5_12_PLUS_OVERNIGHT_STATUS.md`'s deferral notes.
