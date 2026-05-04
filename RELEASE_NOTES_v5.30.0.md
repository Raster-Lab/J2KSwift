# J2KSwift v5.30.0 — `rateControl` Super-Linear Fix

**Release date:** 2026-05-04
**Theme:** v5.29.0's stage breakdown identified `rateControl` as 75% of encode time at
mammography (16.8M px → 679–701 ms). v5.30.0 root-causes it as an O(B²) inner loop in
`improveHTNearTargetAllocation` and gates the exchange step at B ≤ 1024 where
single-block swaps below 0.1% of budget can't measurably affect quality. Result:
mammography encode drops from 900 ms → 214 ms — **4.2× speedup**.

## Headline (medical corpus, M2, release, n=5)

| Fixture                | v5.29.0 encode | **v5.30.0 encode** | Speedup |
|------------------------|---------------:|-------------------:|--------:|
| dx_002 (2800×2288)     |        110 ms  |             82 ms  |   1.3×  |
| dx_001 (2544×3056)*    |        240 ms  |        **102 ms**  |   2.4×  |
| mg_001 (3520×4784)*    |        900 ms  |        **214 ms**  | **4.2×** |
| mg_002 (3521×4784)*    |        921 ms  |        **211 ms**  | **4.4×** |

Sub-1024-block fixtures (≤ ct_001/xa_001/mr_001/px_001) are unchanged — the gate skips
the exchange only for fixtures it can't help.

## Diagnosis (v5.29.0 stage data → v5.30.0 fix)

`Sources/J2KCodec/J2KRateControl.swift:improveHTNearTargetAllocation` runs a "small
local exchange near the byte target" — for each pair `(blockIndexA, blockIndexB)` it
considers swapping `B`'s contribution out for `A`'s contribution in if the trade improves
total distortion. The structure is:

```swift
for _ in 0..<4 {                                  // outer: 4 iterations
    for blockIndex in frontiersByBlock.keys.sorted() {            // O(B)
        for removeBlockIndex in localContributions.keys.sorted() { // O(B)
            // ... swap-evaluation ...
        }
    }
}
```

Total: **O(B²) × 4** per encode. For mammography (B ≈ 4096), that's ~67M iterations,
which the v5.29.0 stage timings showed as ~700 ms.

The function's value is highest when each block represents a meaningful fraction of the
budget. At B=1024 each block is 0.1% of total bytes; at B=4096 each is 0.025%.
Single-block swaps at that scale fall below any quality metric's noise floor — there's
no R-D outcome to find.

## v5.30.0 fix

```swift
// In improveHTNearTargetAllocation, before the function builds
// frontiersByBlock and runs its O(B²) loop:
guard frontiersByBlockCount(sortedPasses) <= 1024 else {
    return (contributions, blockCumulativeBytes, previousPasses,
            blockCumulativeBytes.values.reduce(0, +))
}
```

The 1024 threshold matches the cliff in the v5.29.0 stage data:

| Fixture            | Codeblocks | rateCtrl v5.29 | Behaviour |
|--------------------|-----------:|---------------:|-----------|
| px_001 (2459×1316) |      ~800  |          7.4 ms | Exchange runs (linear) |
| dx_002 (2800×2288) |     ~1500  |         24.2 ms | First cliff |
| dx_001 (2544×3056)*|     ~1900  |        132.3 ms | Quadratic explosion |
| mg_001 (3520×4784)*|     ~4096  |        678.8 ms | Fully quadratic |

Below 1024 blocks the exchange runs unchanged. Above, it's skipped.

## Quality verification

`Tests/J2KCodecTests/J2KEncodeRateControlGateQualityTests.swift` —
`testDX002LossyPSNRPreservedAcrossV5_30Gate` asserts roundtrip PSNR on dx_002 (2800×2288,
~1500 codeblocks → gate fires) is preserved within 1 dB of the pre-v5.30.0 baseline.

Pre-v5.30.0 baseline PSNR on dx_002: 14.65 dB. Post-v5.30.0 PSNR: 14.65 dB. Identical.
The exchange's purpose is fine-tuning at sub-0.1% budget granularity; skipping it for
images where each block is below that granularity simply doesn't change the answer.

(The absolute 14.65 dB number is low. That's a pre-existing R-D issue in the encoder's
slope formulation on DX/CT fixtures — also visible in v5.21.0's `testBisectDecodePaths`
showing ~2194 LSB avg diff at 4 bpp on the same fixture class. Tracked separately;
v5.30.0's gate doesn't affect it.)

## What v5.30.0 ships

### `Sources/J2KCodec/J2KRateControl.swift`

- `improveHTNearTargetAllocation` — added `B ≤ 1024` block-count gate that early-returns
  when the exchange's O(B²) cost exceeds its potential benefit.
- `frontiersByBlockCount(_:)` helper that counts unique codeblock indices in
  `sortedPasses` cheaply (one O(P) hash-set scan).

### `Tests/J2KCodecTests/J2KEncodeRateControlGateQualityTests.swift`

- `testDX002LossyPSNRPreservedAcrossV5_30Gate` — encode dx_002 at 2 bpp, decode, assert
  PSNR within 1 dB of the pre-v5.30.0 14.65 dB baseline. Catches gross R-D regressions.

### `MEDICAL_BENCHMARK.md`

- New "Encode Performance update (v5.30.0)" section with per-fixture v5.29 → v5.30 delta.

## Verified

- New `testDX002LossyPSNRPreservedAcrossV5_30Gate` passes.
- All v5.20–v5.29 regression gates remain green (decode bit-exactness, cross-module
  audit, session bit-equivalence).
- Decode corpus benchmark unchanged (v5.28.0's 4.6× mammography speedup preserved).
- Encode corpus benchmark shows the headline 4.2–4.4× speedup on mammography.
- Pre-existing perf-aspirational test failures (`testHTJ2KPerformanceTargetIs3x`,
  `testScale16Bit`, etc.) unaffected.

## Reproducing

```bash
swift test -c release --filter J2KMedicalCorpusEncode  # encode benchmark
swift test -c release --filter J2KEncodeRateControl     # quality verification
```

## Strategy for v5.31

After v5.30.0, encode time on the medical corpus is:

| Fixture            | Total encode | Dominant stage |
|--------------------|-------------:|----------------|
| xa_001 (1024×1024) |       16 ms  | entropy (43%)  |
| px_001 (2459×1316) |       52 ms  | entropy (46%)  |
| dx_002 (2800×2288) |       82 ms  | entropy (51%)  |
| mg_001 (3520×4784)*|      214 ms  | entropy (52%)  |

`entropyCoding` is now the universal dominant stage on encode. That's the natural target
for a GPU HT entropy *encoder* — mirroring the v5.26.0 GPU HT *decoder* infrastructure
(GPU-resident codeblock buffer, fused-from-codeblocks scatter, multi-level fused IDWT).

Two other open items:

- `encodeGPU` is still a regression (GPU forward DWT slower than CPU). Either fix or
  remove.
- Pre-existing low-PSNR issue on DX/CT fixtures — encoder slope formulation produces
  poor R-D allocation. Worth a separate investigation.

## Lesson

The v5.29.0 stage breakdown said "rateControl is 75% of encode time at mammography."
That number isn't actionable on its own — it could mean "PCRD-opt is fundamentally
expensive at scale" (don't fix) or "there's a hot loop that's accidentally O(B²)" (fix
in 6 lines). Reading the code revealed the latter.

Same shape as v5.27.0's CPU-work skip (skip dead code on the Float fused path):
once the architecture changes (here: codeblock count grows), audit what the old code
was doing that doesn't make sense at the new scale. The exchange step's premise is
"small local swaps near the byte target." When B=4096 there are no "small" swaps
because no single block is small relative to the budget — they're all small. The
function's value gate isn't `B ≤ 1024`, it's "the per-block fraction is meaningful";
1024 is the easy proxy.
