# V8.3.0 — GPU multi-tile-per-tile 5/3 IDWT root cause + fix

**Status**: FIXED. Two distinct bugs in the GPU multi-tile-per-tile reversible 5/3 IDWT path identified and fixed independently. Verified bit-exact via the v8.3 diagnostic with the v8.2 routing fix bypassed (i.e. running the GPU IDWT explicitly on the failing fixtures).
**Date**: 2026-05-10
**Branch**: `v8.3-gpu-mt-pertile-idwt-rootcause`
**Diagnostic**: [`Tests/J2KCodecTests/V8_3_GPUIDWTRootCauseDiagnostic.swift`](Tests/J2KCodecTests/V8_3_GPUIDWTRootCauseDiagnostic.swift)

## Problem

`V8_2_0_MG_CORRUPTION_ROOT_CAUSE.md` documented that the GPU multi-tile-per-tile IDWT corrupted output on certain dimensions. The v8.2 fix routed AROUND the bug by forcing CPU IDWT whenever the cross-tile batched-entropy short-circuit was active. The underlying GPU IDWT bug remained as a follow-up.

## Per-tile mismatch localisation (V8_3 diagnostic)

Bypassing the v8.2 routing fix on the smallest reproducer (1760×2392 split 2x2, tiles 880×1196):

| tile | image origin | tcx0 | tcy0 | mismatches (pre-v8.3) |
|---|---|---:|---:|---:|
| (0, 0) | (0, 0) | 0 | 0 | **clean** |
| (0, 1) | (880, 0) | 880 | 0 | **1,048,207** |
| (1, 0) | (0, 1196) | 0 | 1196 | 48,128 |
| (1, 1) | (880, 1196) | 880 | 1196 | **1,049,385** |

Two failure modes — tiles with non-zero canvas X origin had wholesale corruption (≈ entire tile). Tiles with non-zero canvas Y origin had bottom-edge corruption (≈ 4.5 % of pixels, all near tile bottom).

## Bug #1 — naive-recursion `levelSizes` (the X-axis cliff)

`applyInverseWaveletTransformGPU` (line 4037 pre-fix) computed per-level subband dimensions using naive ceil-div recursion:

```swift
var levelSizes: [(width: Int, height: Int)] = [(compW, compH)]
for _ in 0..<levels {
    let (pw, ph) = levelSizes.last!
    levelSizes.append(((pw + 1) / 2, (ph + 1) / 2))   // ← WRONG for non-zero canvas origin
}
```

The CPU path's `applyInverseWaveletTransform` (line 3454) used the canvas-anchored ISO/IEC 15444-1 Eq. B-15 spec formula:

```swift
for d in 0...levels {
    let denom = 1 << d
    let bandX0 = ceilDiv(tcx0, denom)
    let bandX1 = ceilDiv(tcx0 + compW, denom)
    let bandY0 = ceilDiv(tcy0, denom)
    let bandY1 = ceilDiv(tcy0 + compH, denom)
    levelSizes.append((bandX1 - bandX0, bandY1 - bandY0))
}
```

For tile (0, 1) of 1760×2392 split 2x2 — tcx0=880, compW=880 — at depth 5:
- Naive: `(((((880+1)/2 +1)/2 +1)/2 +1)/2 +1)/2` = 28
- Spec:  `ceil(1760/32) − ceil(880/32)` = 55 − 28 = **27**

The encoder produces the spec dimension (27). The GPU IDWT treated the input as if it had 28 elements — feeding the wrong data through the H lifting and corrupting the entire tile. Over half of the smallest reproducer's mismatches (1.05 M of 2.14 M) lived in this single bug.

**Fix**: replace the naive recursion with the spec formula. Single 9-line edit in `J2KDecoderPipeline.swift:4034`.

After Fix #1: `(0, 1)` clean, `(1, 1)` clean, `(1, 0)` still 47 K mismatches. Confirmed the X-axis case was wholly the levelSizes bug.

## Bug #2 — `halfHH = H / 2` instead of `H − llH` (the Y-axis residual)

After Fix #1, the residual ~47 K mismatches in tiles with non-zero canvas Y origin still corrupted bottom rows. Localised to depths where `outOriginY` is ODD, where the parity-aware kernel runs.

`encodeInverse2DInt32` (and `inverse2DInt32MultiLevelFused`) computed the LH/HH band row count as:

```swift
let halfHH = originalHeight / 2   // ← WRONG for odd V origin
```

For canvas-anchored partitioning at an ODD V origin: LL = `floor(H/2)` rows, LH/HH = `ceil(H/2)` rows. `H/2` is `floor(H/2)` — under-counts the H band by 1 row when `H` is odd.

For tile (1, 0) at level 5: `originalHeight = 75`. With Fix #1, `llH = 37`. The kernel was passed `halfHH = 37` — but the LH and HH bands had **38** rows (= `parentH − llH` in the calling code). The kernel only processed 37 of 38 rows in Pass 1 (horizontal IDWT on LH/HH → colHigh). The 38th row of `colHigh` stayed uninitialised.

Pass 2 (vertical IDWT) — with the correctly-selected ODD V kernel that uses `lowCount = H/2 = 37, highCount = 38` — read **all 38 rows** of `colHigh`, picking up the uninitialised garbage on the last row. That garbage propagated into the V IDWT output for the bottom rows.

**Fix**: change `halfHH = originalHeight / 2` to `halfHH = originalHeight − llHeight`. Two 1-line edits in `J2KMetalDWT.swift` (one in `inverse2DInt32MultiLevelFused`, one in `encodeInverse2DInt32`).

After Fix #2: all four tiles clean. Both fixes together produce bit-exact GPU IDWT on the multi-tile-per-tile path.

## Why this didn't show on tile (0, 0)

Tile (0, 0) has tcx0 = tcy0 = 0. Both bugs are no-ops at zero origin:
- Bug #1: spec-formula `bandX1 − bandX0` reduces to `ceil(compW / denom)`, which matches the naive recursion exactly when origins are zero.
- Bug #2: at zero V origin, the V kernel chosen is the EVEN one. The EVEN kernel internally uses `halfWidth = (W+1)/2, halfWidthH = W/2` — and the calling convention passes `llH = ceil(H/2), halfHH = H/2 = floor(H/2)`. When `H` is even (compH = 1196 is even), both bands have `H/2` rows; when `H` is odd, the EVEN kernel's expected dimensions match what's passed. So zero V origin works either way.

That's why every previous test fixture (single-tile / single-component / pre-v7.0 multi-tile bytes-equality) passed: those exercised tile (0, 0)-equivalent paths.

## Why the v8.2 fix is still in place

Removing the v8.2 routing fix would re-enable GPU IDWT on the batched-entropy path. But:
- The per-tile path takes CPU IDWT today (via `hasFusedFromCodeblocksPlan = true`); removing v8.2 would diverge the routing.
- v6.3.0 E1.2 measured GPU IDWT at 400 K/tile to be **1.28× SLOWER than CPU** — for the multi-tile-per-tile range, CPU is the right routing.
- The v8.3 fix is defensive: any code that DOES invoke the GPU IDWT on the multi-tile-per-tile path now produces correct output.

So v8.2 stays in place for routing; v8.3 fixes the underlying GPU IDWT correctness bug.

## Test coverage

| suite | pre-v8.3 | post-v8.3 |
|---|---|---|
| `V8_3_GPUIDWTRootCauseDiagnostic` (3 tests, GPU IDWT bypassing v8.2 fix) | FAIL on (0,1), (1,0), (1,1), mg | **6/6 PASS** |
| `MgRegressionTriageTest` (2 tests, batched flag ON via v8.2 routing) | 2/2 PASS | 2/2 PASS |
| `V8_2_MgBatchedDiagnostic` (10 cases, batched flag ON via v8.2 routing) | 1/1 PASS | 1/1 PASS |
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 | 2/2 |
| `J2KMedicalCorpusPerformanceTests` | 2/2 | 2/2 |
| `J2KStrictCrossCodecValidationTests` | 3/3 | 3/3 |

Mandatory pre-release gate clean in release mode.

## Files changed

- `Sources/J2KCodec/J2KDecoderPipeline.swift`:
  - Fix #1: `applyInverseWaveletTransformGPU` `levelSizes` switched to spec formula (10 lines)
  - Test toggle: added `_v82_disableIDWTRoutingFix` static for v8.3 diagnostic — production default `false`
- `Sources/J2KMetal/J2KMetalDWT.swift`:
  - Fix #2a: `inverse2DInt32MultiLevelFused` `halfHH` computation (1 line)
  - Fix #2b: `encodeInverse2DInt32` `halfHH` computation (1 line)
- `Tests/J2KCodecTests/V8_3_GPUIDWTRootCauseDiagnostic.swift`: 3-test diagnostic
- `V8_3_0_GPU_IDWT_ROOT_CAUSE.md`: this finding doc

## Reproducing

```bash
# v8.3 GPU IDWT bit-exact tests (bypass v8.2 routing fix)
swift test -c release --filter 'V8_3_GPUIDWTRootCauseDiagnostic'

# v8.2 mg regression (still valid via routing fix)
swift test -c release --filter 'V8_2_MgBatchedDiagnostic|MgRegressionTriageTest'

# Mandatory commit gate
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```
