# J2KSwift v5.25.0 — Float Multi-Level Fused IDWT (9/7 lossy)

**Release date:** 2026-05-04
**Theme:** v5.24.0's stage breakdown identified per-level upload/readback in the 9/7
lossy IDWT as the next lever — `inverseWaveletTransform` cost ~15.2 ms on `decodeGPU` vs
~10.6 ms on `decodeWithGPUHT` (which had partial fusion). v5.25.0 closes that gap by
adding `J2KMetalDWT.inverse2DMultiLevelFused` (Float variant) — mirrors the existing
Int32 5/3 fused path: chains all decomposition levels into a single command buffer with
the output of level N reused as the LL input of level N-1, single readback at the end.

## Headline

| Path                                          | v5.24.0 | v5.25.0 | Δ |
|-----------------------------------------------|--------:|--------:|--:|
| `decode` (CPU)                                | 25.6 ms | 26.6 ms | (noise) |
| `decodeGPU(_:session:)` (CPU HT + GPU IDWT)   | 17.8 ms | **10.0 ms** | **−7.8 ms** |
| `decodeWithGPUHT(_:session:)` (GPU HT + IDWT) | 24.0 ms | 26.5 ms | (noise) |

| Path | v5.24.0 speedup | **v5.25.0 speedup** |
|---|---:|---:|
| `decodeGPU(_:session:)` | 1.43× | **2.64–3.13×** |
| `decodeWithGPUHT(_:session:)` | 1.07× | 1.00–1.36× |

`decodeGPU` is now a real, large win on warm session. `decodeWithGPUHT` remains a wash
because its 11–16 ms `gpuHTDispatch` overhead is unrelated to the IDWT lever and was not
addressed in this release.

## Per-stage breakdown (typical post-v5.25.0 run)

```
Stage                            CPU   gpuIDWT    GPU-HT
extractTileData                  0.2       0.2       0.1
entropyDecoding                  1.5       1.4      15.8
  ├─ gpuHTDispatch               0.0       0.0      15.3
  └─ regroup (CPU)               1.5       1.4       0.4
dequantization                   0.5       0.5       0.4
inverseWaveletTransform         23.4       7.4      10.8  ← v5.25.0 win
inverseColorTransform            0.0       0.0       0.0
dcLevelUnshift                   0.4       0.2       0.2
reconstructImage                 0.6       0.5       0.6
─────                            ───   ───────    ──────
instrumented total              26.6      10.1      27.9
```

`inverseWaveletTransform` on the gpuIDWT path: **15.2 → 7.4 ms** — 50% drop.

## What v5.25.0 ships

### `J2KMetalDWT.inverse2DMultiLevelFused` (Float)

`Sources/J2KMetal/J2KMetalDWT.swift` — new public method mirroring the existing
`inverse2DInt32MultiLevelFused`. Takes `[J2KMetalDWTSubbands]` (CPU-uploaded LH/HL/HH per
level + LL on the innermost level) and produces the outermost-level Float output via:

- One `MTLCommandBuffer` for all levels (was: one cb per level).
- Output buffer of level N becomes the LL input of level N-1 (no readback).
- Single commit + await + final readback.
- Buffers acquired via `bufferPool` (was: `device.makeBuffer` direct).

### `J2KMetalDWT.encodeInverse2D` (Float, chainable)

New chainable encode method analogous to `encodeInverse2DInt32`. Takes an existing
`MTLCommandBuffer` and adds vertical-then-horizontal Float kernel encoders. Caller owns
the buffer + cb lifecycle. Used by the multi-level fused method.

### Wiring in `J2KDecoderPipeline.applyInverseWaveletTransformGPU`

The 9/7 lossy branch now routes through `inverse2DMultiLevelFused` whenever
`metalSession != nil` (which is true for both `decodeGPU(_:session:)` and
`decodeWithGPUHT(_:session:)`). The sessionless path keeps the v5.7-era per-level
`inverse2D` loop (no behavioural change for sessionless callers).

## What v5.25.0 does NOT do

- **Does not address the 15.3 ms `gpuHTDispatch` overhead.** That's a separate per-tile
  dispatch / kernel-launch / memory-transfer cost on the GPU HT entropy path; reducing it
  requires a different optimisation (smaller envelope, indirect command buffers, or
  workload-size routing). Until that lands, `decodeWithGPUHT` remains a wash on this
  workload size.
- **Does not extend the GPU-resident scatter path to 9/7 lossy.** The Int32 fused
  `inverse2DFullFusedFromCodeblocks` consumes a GPU-resident codeblock buffer via the
  scatter kernel and skips the per-level CPU upload of LH/HL/HH. Adding a Float scatter
  kernel + Float `FullFusedFromCodeblocks` would close the remaining per-level upload —
  but only `decodeWithGPUHT` benefits (the entropy stage is what produces the codeblock
  buffer). Tracked as next increment after the dispatch-overhead fix.

## Verified

| Test suite                            | Cells | Failed | Notes |
|---------------------------------------|------:|-------:|-------|
| `J2KGPULossy97DivergenceTests`        |     1 |      0 | v5.21.0 IDWT correctness — fused path is bit-equivalent |
| `J2KMetalSingleLevel97Tests`          |     1 |      0 | v5.21.0 single-level — unchanged |
| `J2KWaveletConventionAuditTests`      |     4 |      0 | v5.22.0 cross-module audit — unchanged |
| `J2KGPULossy97PerformanceTests`       |     1 |      0 | New v5.25.0 numbers in stage breakdown |
| HT conformant suites (v5.15–v5.20)    | various |    0 | All carryover gates green |

Three pre-existing failures (`testHTJ2KPerformanceTargetIs3x`, `testScale16Bit`,
`testNEONPerformanceBenefit`) are unaffected by this work.

## Reproducing

```bash
swift test -c release --filter J2KGPULossy97Performance
```

## Lesson

v5.24.0's stage breakdown predicted that closing per-level upload/readback would yield
about 2-3 ms IDWT improvement. Reality: 7.8 ms — bigger than predicted, because the
per-level commit + await cycle was costing more than just the data transfer. The way to
ship perf claims that don't decay: instrument first, optimise the dominant stage, measure
after, ship the change with the new numbers.
