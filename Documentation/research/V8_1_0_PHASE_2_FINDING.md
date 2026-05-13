# V8.1.0 Phase 2 — DX wall A/B; workstream closes as measurement wash

**Status**: WASH — `swarRefill8Enabled` stays default OFF; v8.1 prefix-scan / 8-byte SWAR workstream closes here.
**Date**: 2026-05-10
**Branch**: `v8.1-phase-2-dx-wall-ab`

## Goal

End-to-end DX 2800×2288 in-process decode wall A/B with `swarRefill8Enabled` toggled. Acceptance: Δ (v7.4 → v8.1) must be ≥ 3 ms median to justify flipping the default to ON in Phase 3.

## Method

Same `J2KDecoder().decode()` end-to-end path as v7.4's `V740NeonRefillDXWallBenchmark`. Three legs measured per run, median of 5:
- **Scalar**: `swarRefill8Enabled = false`, `neonRefillEnabled = false` → `refillScalar`
- **v7.4 4-byte**: `swarRefill8Enabled = false`, `neonRefillEnabled = true` → `refillBatched`
- **v8.1 8-byte**: `swarRefill8Enabled = true` → `refillBatched8`

DX fixture: `Tests/Fixtures/CrossCodec/dx_study_002_instance_000001.pgm` (2800 × 2288, 16-bit, 12.7 MB codestream HT-conformant lossless).

## Headline data — three independent runs

| run | scalar ms | v7.4 ms | v8.1 ms | Δ (v7.4 → v8.1) |
|---|---:|---:|---:|---:|
| 1 | 64.29 | 53.63 (oddly cached) | 76.69 | **-7.11 ms** |
| 2 | 54.91 | 53.63 | 54.21 | -0.58 ms |
| 3 | 59.03 | 53.76 | 53.23 | +0.53 ms |

**Median Δ across runs: ≈ -0.58 ms.** The variance (-7.11 to +0.53 ms) is wider than the headline 3 ms threshold; even discarding the outlier, the central tendency sits within ±1 ms of zero.

Per v7.4's discipline + the v6-alpha4 lever-ceiling memory: this is a measurement wash. Δ ≥ 3 ms is not achievable.

## Why the microbench projection didn't materialize

| measurement | predicted Δ | realised Δ |
|---|---:|---:|
| Phase 1A prototype (synthetic, 14-bit reads, corpus density) | 1.35 ns/call ≈ ~34 ms DX wall | n/a (test-only struct) |
| Phase 1B production microbench (synthetic, 14-bit reads, corpus density) | 0.71 ns/call ≈ ~17 ms DX wall | -0.58 ms (wash) |

The synthetic microbench measures `dec.read(count: 14)` ns/call in isolation, with no dependency chain on the read result. Real DX entropy decode (`J2KHTConformantBlockDecoder.decode`) consumes each `read()` result into bit-position tracking, sign extraction, refinement passes — a deeply pipelined dependency graph where the result of one read drives the address of the next.

In that real context, the saved cycles inside `read()` are absorbed by the surrounding latency rather than translating into wall-time saving. This is the same pattern v6-alpha4 step 12 saw with its C+D refactors (cache locality / i-cache pressure invalidating the per-op gain) — the measurement wash documented in [`feedback_v6_alpha4_lever_ceiling.md`](../memory/feedback_v6_alpha4_lever_ceiling.md).

## Decision

1. **`swarRefill8Enabled` stays `false` by default**. Production users get the v7.4 path unchanged; the v8.1 8-byte refill is preserved as opt-in for future investigators.
2. **No flag flip in a "Phase 3"** — the acceptance criterion was Δ ≥ 3 ms; the measurement wash means there is no Phase 3 default flip.
3. **Code stays in production**. Cost on the default path is ~0 (one branch on a `useSwar8` field, predictor 100 % accurate since the value is stable for the decoder's lifetime). Removing it would lose the bench infrastructure that's now in place.
4. **Workstream closes here**. The v8 known-limitation called out two paths: (1) bit-parallel prefix-scan SIMD on chained-unstuff state, and (2) different hardware (M3/M4/A-series ratification). Path (1) is documented as a wash on M2; path (2) requires hardware J2KSwift doesn't yet have access to.

## Future-investigator notes

- The 8-byte SWAR fast path itself is sound — Phase 1A parity confirmed bit-equivalence across 16,520 cells. The wash is in the cost-vs-savings ratio at the read() callsite, not in the algorithm.
- A NEON full-vector prefix-scan over 16-byte batches with a 192-bit accumulator was the original "ambitious" path proposed in Phase 0. Phase 1A scoped down to 8-byte for tractability. The 16-byte version may eke out additional savings — but the DX wall variance observed in Phase 2 (±7 ms) suggests any < 5 ms gain would be lost to noise on Apple M2 + Swift release.
- Apple A-series (iPhone 17 Pro, iOS 26.x) was ratified in v8.0.0 Phase 6.2 but not yet measured on the entropy hot path. A-series may have a different cycle-cost profile that makes the field-branch + 128-bit shift cheaper. If a future v8.1.x targets iPad / iPhone fixtures specifically, re-measure with `swarRefill8Enabled = true` on those devices.

## Mandatory commit gate (release mode)

Phase 2 adds the bench file only — no production code change beyond Phase 1B (already gate-clean). Re-running for completeness on this branch:

```
J2KMedicalCorpusEncodePerformanceTests   2/2   (release mode)
J2KMedicalCorpusPerformanceTests         2/2   (release mode)
J2KStrictCrossCodecValidationTests       3/3   (release mode)
                                         ─────
                                         7/7   0 failures
```

## Reproducing

```bash
swift test -c release --filter 'V8_1_Phase2_DXWallAB'
```

Expect: 1-second runtime, three-leg breakdown, median-Δ verdict. The runtime variance is high (Phase 2's three runs differed by 7+ ms on the same machine) — single-run results are not load-bearing.
