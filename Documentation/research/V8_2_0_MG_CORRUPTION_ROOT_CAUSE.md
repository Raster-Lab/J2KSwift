# V8.2.0 — mg silent-corruption root cause + fix

**Status**: FIXED. `_multiTileBatchedEntropyEnabled` re-enabled by default; v7.2.0's cross-tile entropy amortisation restored without the v7.5.1 corruption.
**Date**: 2026-05-10
**Branch**: `v8.2-phase-1-mg-batched-rootcause`
**Diagnostic**: [`Tests/J2KCodecTests/V8_2_MgBatchedDiagnostic.swift`](Tests/J2KCodecTests/V8_2_MgBatchedDiagnostic.swift)
**Regression test**: [`Tests/J2KCodecTests/MgRegressionTriageTest.swift`](Tests/J2KCodecTests/MgRegressionTriageTest.swift)

## Problem

PR #356 (v7.2.0 phase-e) added `decodeMultiTileGPUBatched` to amortise per-tile MTLCommandBuffer overhead by aggregating all tiles' eligible HT codeblocks into ONE shared GPU dispatch. The path silently corrupted decode output on certain multi-tile codestreams; surfaced 2026-05-09 by an external 4-codec eval matrix on mammography (mg) DICOM fixtures (3520×4784 = 16.84 M px). External decoders (OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1) decode the same J2KSwift-encoded bytes bit-exactly — encoder is correct.

The v7.5.1 hotfix disabled `_multiTileBatchedEntropyEnabled` by default, sacrificing the v7.2.0 phase-e perf win (3 % on DX 2x2) until root cause was located.

## Triage data (V8_2_MgBatchedDiagnostic)

A scripted sweep of multi-tile dimensions reveals the bug fires at predictable points:

| dimension | tiles | trigger? | first divergence |
|---|---|---:|---|
| 3520×4784 (mg fixture) | 1760×2392 | YES | tile (1,0), row 4737 col 0 |
| 3520×4783 | 1760×2391 | YES | tile (1,0), row 4737 col 0 |
| 3520×4785 | 1760×2393 | NO | — |
| 3521×4784 | 1761×2392 | YES | tile (1,0), row 4737 col 2 |
| 3519×4784 | 1759×2392 | YES | tile (1,0), row 4737 col 0 |
| 1760×4784 | 880×2392 | YES | tile (0,1), row 0 col 1697 |
| 3520×2392 | 1760×1196 | YES | tile (1,0), row 2337 col 0 |
| 1760×2392 (smallest) | 880×1196 | YES | tile (0,1), row 0 col 1697 |
| 3520×9568 | 1760×4784 | YES | tile (1,0), row 9505 col 0 |
| 4097×4097 | 2049×2049 | NO | — |
| 4608×4608 | 2304×2304 | NO | — |

The "2^24 sample threshold" claim from the v7.5.1 hotfix was a red herring — the 1760×2392 case (4.21 M total samples) reproduces the bug with 4× fewer samples than the original mg fixture, and several >2^24 cases (4097×4097, 4608×4608, 5120×5120) don't trigger.

## Root cause

The bug was NOT in the entropy decode itself. It was in the **GPU IDWT path being incorrectly invoked when entropy was batched**.

In `decodeTilePayloadGPU`, the routing through `applyInverseWaveletTransformGPU` evaluates this gate (excerpted from line 3918):

```swift
let hasFusedFromCodeblocksPlan = gpuBatch?.plansByComponent.isEmpty == false
    || (gpuBatch?.floatPlansByComponent?.isEmpty == false)
...
if !isReversible || hasFusedFromCodeblocksPlan || belowPerTileThreshold {
    return try await applyInverseWaveletTransform(...)  // CPU IDWT
}
// else: GPU multi-tile-per-tile IDWT runs
```

Two routing branches:

| path | entropy | `gpuBatch` returned by `applyEntropyDecoding` | `hasFusedFromCodeblocksPlan` | IDWT |
|---|---|---|---:|---|
| **per-tile** (`decodeMultiTileGPU`) | `decodeBatchGPUResident` per tile | non-nil (`buildGPUHTBatchFromResult`) | `true` | **CPU** ✓ correct |
| **batched** (`decodeMultiTileGPUBatched`, pre-fix) | `decodeBatch` once across all tiles, then per-tile short-circuit via `preBatchedGPUCoefficients` | **nil** (the short-circuit path returns `(coeffs, nil)`) | `false` | **GPU** ✗ corrupts at certain dims |

So the per-tile path always took the CPU IDWT (because the entropy stage produced a non-nil fused batch); the batched path took the GPU IDWT (because the pre-batched short-circuit produced no batch). The GPU multi-tile-per-tile IDWT corrupts on the dimensions in the table above — that pre-existing GPU IDWT bug is NEW lever-territory and stays for a follow-up PR.

## Fix

Force CPU IDWT when `preBatchedGPUCoefficients` is set, mirroring the per-tile path's effective behaviour:

```swift
let spatialData: [[Double]]
if preBatchedGPUCoefficients != nil {
    spatialData = try await applyInverseWaveletTransform(
        dequantizedSubbands, metadata: tileMeta,
        tileOriginX: tileX, tileOriginY: tileY)
} else {
    spatialData = try await applyInverseWaveletTransformGPU(
        dequantizedSubbands, metadata: tileMeta,
        tileOriginX: tileX, tileOriginY: tileY,
        isMultiTilePerTile: true, gpuBatch: gpuBatch)
}
```

This matches the per-tile path's semantics: when the entropy stage is shared across tiles, the IDWT runs on CPU. The cross-tile MTLCommandBuffer amortisation that v7.2.0 measured (3 % DX 2x2) is preserved — the multi-tile-per-tile IDWT runs on CPU in BOTH paths anyway whenever a fused batch is present, so this fix doesn't sacrifice GPU IDWT savings.

`_multiTileBatchedEntropyEnabled` is flipped back to `true` by default.

## Test coverage

| suite | result |
|---|---|
| `MgRegressionTriageTest` (assertion direction flipped — now must PASS bit-exact under flag-ON) | 2/2 ✓ |
| `V8_2_MgBatchedDiagnostic` (10 dimension cases — all dimensions that previously triggered now bit-exact) | 1/1 ✓ |
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 ✓ |
| `J2KMedicalCorpusPerformanceTests` | 2/2 ✓ |
| `J2KStrictCrossCodecValidationTests` | 3/3 ✓ |

Mandatory pre-release gate clean in release mode.

## Open follow-ups

- **GPU multi-tile-per-tile IDWT bug** — separate workstream. The IDWT path that fails on 1760-wide-tile dimensions is also reachable from non-pre-batched routes; the v8.2 fix routes around it but doesn't fix it. A future PR can:
  1. Add a focused IDWT bug-reproducer test (decode the 1760×2392 fixture directly through the GPU multi-tile-per-tile IDWT path),
  2. Bisect to identify which kernel (parity-aware lifting? scatter? boundary handling?) corrupts,
  3. Re-enable GPU IDWT for the batched-entropy path once fixed.
- The cross-tile entropy amortisation could in principle benefit from running the multi-tile-per-tile GPU IDWT too — but the perf win there is small (per-tile GPU IDWT was only ~1.28× CPU at 400K/tile per V720 sweep) and the correctness work is non-trivial. Defer until the IDWT bug is fixed standalone.

## Reproducing

```bash
# Failing dimensions sweep (now all-pass post-fix)
swift test -c release --filter 'V8_2_MgBatchedDiagnostic'

# Permanent regression test (assertion-flipped)
swift test -c release --filter 'MgRegressionTriageTest'

# Mandatory commit gate
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```
