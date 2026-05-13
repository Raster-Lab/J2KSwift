# J2KSwift v5.26.0 — Float Scatter + GPU-Resident Dispatch (9/7 lossy)

**Release date:** 2026-05-04
**Theme:** v5.25.0 closed the per-level readback in the 9/7 lossy IDWT (Float multi-level
fused). v5.26.0 closes the remaining levers for `decodeWithGPUHT` 9/7 lossy:
GPU-resident codeblock buffer (no host readback after entropy), Float scatter+dequant
kernel (no CPU per-level upload of LH/HL/HH, no separate dequantisation pass), and
fused-from-codeblocks IDWT (one command buffer for scatter + all levels of IDWT).

## Headline

| Path                                          | v5.25.0 | v5.26.0 | Speedup vs v5.25.0 |
|-----------------------------------------------|--------:|--------:|-------------------:|
| `decode` (CPU)                                | 26.6 ms | 25.7 ms | (noise)            |
| `decodeGPU(_:session:)` (CPU HT + GPU IDWT)   | 10.0 ms |  9.8 ms | (noise)            |
| `decodeWithGPUHT(_:session:)` (GPU HT + IDWT) | 26.5 ms | **14.0 ms** | **1.89×**       |

| Path | v5.25.0 speedup | **v5.26.0 speedup** |
|---|---:|---:|
| `decodeGPU(_:session:)` | 2.64–3.13× | 2.55–3.07× |
| `decodeWithGPUHT(_:session:)` | 1.00–1.36× | **1.81–1.86×** |

`decodeWithGPUHT` jumped from a wash to almost-2×. `decodeGPU` is still the absolute
winner on this workload — CPU HT entropy at ~1.3 ms is still cheaper than even the
v5.26.0-reduced GPU HT dispatch (~7 ms) — but the gap closed materially.

## Per-stage breakdown (typical run post-v5.26.0)

```
Stage                            CPU   gpuIDWT    GPU-HT
extractTileData                  0.2       0.1       0.2
entropyDecoding                  1.3       1.3       7.5
  ├─ gpuHTDispatch               0.0       0.0       7.1   ← v5.26.0: was 15+
  └─ regroup (CPU)               1.3       1.3       0.4
dequantization                   0.5       0.4       0.5
inverseWaveletTransform         22.7       7.0       5.0   ← v5.26.0: was 10+
inverseColorTransform            0.0       0.0       0.0
dcLevelUnshift                   0.4       0.2       0.2
reconstructImage                 0.5       0.5       0.5
─────                            ───   ───────    ──────
instrumented total              25.7      10.0      14.1
```

`gpuHTDispatch` and `inverseWaveletTransform` on the GPU-HT path each dropped by ~50%.

## What v5.26.0 ships

### `j2k_subband_scatter_float_dequant` Metal kernel

`Sources/J2KMetal/J2KShaders.metal` (and the embedded fallback in
`Sources/J2KMetal/J2KMetalShaderLibrary.swift`). Mirror of `j2k_subband_scatter` but:

- Reads Int32 codeblock samples (the GPU HT cleanup output).
- Applies HTJ2K conformant cleanup-only dequantisation
  (`(coeff ± 0.5) * stepSize`, or zero if coeff == 0).
- Writes Float to per-subband 2D buffers.
- Per-block `stepSize` carried in the descriptor (replaces `_pad` slot).

### `J2KMetalSubbandScatterDescriptorFloat` — Float descriptor type

Same 32-byte layout as the Int32 descriptor, with `stepSize: Float` in the trailing slot.

### `J2KMetalDWT.inverse2DFullFusedFromCodeblocks` (Float overload)

Mirror of the Int32 `inverse2DInt32FullFusedFromCodeblocks`. Takes a GPU-resident
codeblock buffer + per-level `LevelScatterPlanFloat`, runs Float scatter+dequant kernel
+ multi-level Float IDWT in one command buffer, single readback at the outermost level.

### Pipeline wiring in `J2KDecoderPipeline`

- `applyEntropyDecoding`'s fused-batch gate dropped `!isIrreversibleFilter`. 9/7 lossy now
  also routes through `decodeBatchGPUResident` (no host readback of the codeblock buffer)
  when `metalSession != nil`. The `J2KGPUHTBatch` struct gained an optional
  `floatPlansByComponent` field; populated for 9/7 lossy via the new
  `buildGPUHTBatchFromResultFloat` helper (which looks up per-block stepSize via the same
  QCD-key convention as `applyDequantization`).
- `applyInverseWaveletTransformGPU`'s 9/7 branch routes to the new Float fused-from-
  codeblocks path when `gpuBatch.floatPlansByComponent` is populated; falls back to
  v5.25.0 multi-level fused (CPU-uploaded subbands) when no batch is available.

### Regenerated metallib

`Sources/J2KMetal/default.metallib` is rebuilt from the updated `J2KShaders.metal`.

## Verified

| Test suite                            | Cells | Failed | Notes |
|---------------------------------------|------:|-------:|-------|
| `J2KGPULossy97DivergenceTests`        |     2 |      0 | Includes new `testSessionPathBitEquivalentToNoSessionPath` |
| `J2KMetalSingleLevel97Tests`          |     1 |      0 | Carryover |
| `J2KWaveletConventionAuditTests`      |     4 |      0 | Carryover |
| `J2KGPULossy97PerformanceTests`       |     1 |      0 | New v5.26.0 numbers |
| HT conformant suites (v5.15–v5.20)    | various |    0 | All carryover gates green |

The new `testSessionPathBitEquivalentToNoSessionPath` exercises the v5.26.0 fused-from-
codeblocks path (only fires for session-based decode) and asserts pixel-equivalence with
the no-session path within 4 LSB at 16-bit. Observed residual: max diff = 1 LSB,
avg = 0 (Float-precision noise, well under tolerance).

Pre-existing perf-aspirational test failures unaffected by this work.

## Reproducing

```bash
swift test -c release --filter J2KGPULossy97Performance
```

## What's still open

`decodeGPU(_:session:)` remains the fastest API on this workload because CPU HT entropy
beats even the v5.26.0-reduced GPU HT dispatch on small/medium images. `decodeWithGPUHT`
becomes the right choice when the dispatch amortises — likely on much larger images,
where the GPU's parallelism wins versus the fixed CPU HT cost. That crossover hasn't
been characterised yet; tracked for a future release.

## Lesson

The original framing of item 1's milestone was "extend GPU-resident batch path to 9/7
lossy: scatter + fused float IDWT, remove CPU regroup + per-level upload/readback." The
expected gain was modest — closing per-level upload was thought to save ~1-2 ms. Reality:
the bigger latent win was switching the entropy dispatch from `decodeBatch` (full
readback) to `decodeBatchGPUResident` (no readback), which alone saved ~8 ms.

When the original gate `!isIrreversibleFilter` excluded 9/7 lossy from the fused batch
path, it didn't just lock 9/7 lossy out of the Float IDWT optimisation — it also kept it
on the slower entropy dispatch. Removing the gate compounded both wins. Same shape as
v5.25.0's lesson: the dominant cost was where you weren't looking.
