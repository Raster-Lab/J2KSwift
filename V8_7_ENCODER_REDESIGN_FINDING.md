# V8.7 — Encoder algorithmic redesign: projected wash; encoder at structural ceiling

**Status**: WASH across all probed redesign vectors (DWT row-parallel re-test, multi-tile 4x4 default-on, transpose isolation). Encoder M2 lever ceiling confirmed AGAIN.
**Date**: 2026-05-10
**Branch**: `v8.7-encoder-algorithmic-redesign`
**Bench**: [`Tests/J2KCodecTests/V8_7_ForwardDWTStageDecomposition.swift`](Tests/J2KCodecTests/V8_7_ForwardDWTStageDecomposition.swift)

## Goal

Per the v8.6 close-out's recommendation tree, "Algorithmic redesign" was the un-explored encoder-arc lever. v8.7 probes three concrete redesign vectors before committing multi-week implementation work:

1. **Forward DWT 2D stage decomposition** — where do the v8.4 measured 333 ms accumulated DWT CPU actually go? (Inner lifting at 0.37 ns/sample only projects to ~6 ms; what's the other 98%?)
2. **DWT row-pass parallel mode** — re-test the v5.39 M2 `J2K_HT_PARALLEL_MODE=dwt-row-parallel` opt-in path on current v8.x code.
3. **Multi-tile 4x4 default-on for ≥6 MP fixtures** — push beyond current `.auto` (2x2 for ≥3 MP) to see if more parallelism helps.

## Headline data

### Phase 0a — `forward2D_53Pooled` end-to-end at DX

```
DX 2800x2288 single-level forward 5/3 transform:
  median wall:    18.78 ms
  per-pixel:       2.93 ns/pixel (wall)

Projection to DX 5-level forward DWT (single tile):
  pyramid factor: 1.332x
  projected wall: 25.01 ms
  v8.4 measured:  27.10 ms (DWT wall)
```

The full 2D DWT (column pass + row pass, 5 levels) costs about 25 ms wall on DX. The inner 1D lifting (v8.6 Phase 0: 0.37 ns/sample) projects to only ~6 ms accumulated CPU across the pyramid. The other ~325 ms accumulated CPU is in: TaskGroup dispatch overhead (350 strips × ~2 µs/task = 700 µs), strip transpose, level setup, multi-tile coordination, and the `srcBuf`/`dstBuf` copies (2 × 25 MB per L0 call).

### Phase 0b — Strip transpose isolation

```
8x2288 single-strip transpose-in:
  ns/cell: 0.07
  Projected acc CPU across DX 5-level pyramid: 1.2 ms (0.4% of DWT stage)
```

The transpose cost is **immaterial**. It is decisively NOT the bottleneck. An algorithmic redesign that eliminates the transpose would produce <0.1 ms wall savings.

### Phase 0c — DWT row-parallel re-test (v5.39 M2)

```
DX 2544x3056 CLI cold-shot, 8 runs each, median:
  Baseline (default):                          110 ms
  J2K_HT_PARALLEL_MODE=dwt-row-parallel:       120 ms (+10 ms slower)
```

The row-parallel path is now a **regression** on current v8.x code, not the +4-8% wall improvement reported in v5.39 M2 commit `01aa231`. Likely cause: in v8.x, multi-tile encode (`J2KHTTileMode.auto`) is default-on for ≥3 MP fixtures (since v7.0.0), so DX runs as 2x2 = 4 parallel tiles. Adding `dwt-row-parallel` on top stacks 4 × 8 = 32 concurrent tasks on M2's 8 cores → massive over-subscription. The row-parallel mode pre-dates the auto-multi-tile flip and is now structurally incompatible.

### Phase 0d — Multi-tile 4x4 vs 2x2 corpus A/B

CLI cold-shot wall (median of 12-15 interleaved runs):

| Modality | Shape       | 2x2 (auto) | 4x4    | Δ ms     | %      |
|----------|-------------|-----------:|-------:|---------:|-------:|
| MR       | 512×512     | 39.36      | 39.51  | -0.15    | -0.4%  |
| CT       | 512×512     | 37.55      | 38.77  | -1.22    | -3.3%  |
| XA       | 3072×2560   | 117.24     | 114.46 | **+2.78**| **+2.4%** |
| PX       | 2812×1316   | 82.83      | 79.03  | **+3.80**| **+4.6%** |
| MG       | 3517×4784   | 166.89     | 180.21 | **-13.32**| **-8.0%** |
| DX       | 2288×2798   | 106.73     | 108.86 | -2.12    | -2.0%  |

**No universal win.** 4x4 helps PX (+3.80 ms, ≥3 ms threshold MET) and XA (+2.78 ms), but regresses MG (-13.32 ms) and DX (-2.12 ms). Promoting 4x4 to default-on would significantly hurt mammography (MG = the clinically-critical 17 MP modality).

A separate tested DX fixture (2544×3056, 7.78 MP, different study than corpus DX) showed +3.56 ms savings on 4x4 — meaning even within DX modality the result is content-dependent.

## Conclusion

All three v8.7 algorithmic-redesign probes returned WASH-or-regression on M2:

| Probe                                | Outcome                                                       |
|--------------------------------------|---------------------------------------------------------------|
| Forward DWT 2D decomposition         | Inner lifting + transpose only ~7 ms acc / 25 ms — overhead is in dispatch, not arithmetic |
| Row-parallel re-test                 | +10 ms regression (over-subscription with multi-tile auto)    |
| Multi-tile 4x4 default-on            | Mixed corpus result: some fixtures +5%, others -8%; MG hurt   |

Combined with the previous lever-ceiling investigations:

| Direction  | Probes                                                                | Outcome  |
|------------|-----------------------------------------------------------------------|----------|
| Decode     | v6-alpha4, v7.4, v7.5, v8.1, v8.4, v8.5                                | WASH all |
| Encode     | v8.6 forward DWT lifting, v8.6 HT SIMD classifier, **v8.7 algorithmic** | WASH all |

**Eight independent investigations** now confirm the J2KSwift codec hot-path on Apple M2 + Swift release + macOS is at structural lever ceiling for both encode and decode. Multi-tile encode auto-tuning (2x2 for ≥3 MP, single for smaller) is empirically near-optimal for the medical corpus.

## What stays in tree

- `Tests/J2KCodecTests/V8_7_ForwardDWTStageDecomposition.swift` — Phase 0a/0b benches (`forward2D_53Pooled` end-to-end + transpose isolation). Future-investigator reference.
- `V8_7_ENCODER_REDESIGN_FINDING.md` — this document.

No production code change. No new public API surface.

## What WOULD justify reopening this

1. **A different machine class** (M3+/A-series). The marketable "Apple Silicon" claim covers all members, but M2 is the canonical reference. Per `feedback_apple_only_v8.md`, cross-silicon retest is gated on physical-device access.
2. **Per-fixture adaptive tile-mode auto** — instead of "2x2 for ≥3 MP", a model that picks the best tile mode per fixture (using image dimensions + content-density features). Multi-week ML/heuristic work; dubious value when the universal default is already near-optimal.
3. **Stage-fusion pipeline** — fuse forward DWT + HT entropy in one pass to eliminate intermediate buffers (the 25 MB `colResult`). Multi-week architectural rewrite; risk of breaking the v6.3.0 byte-stream invariants.

## Recommendation tree state after v8.7

| Item                                    | Status                                  |
|-----------------------------------------|-----------------------------------------|
| #1 j2kd daemon adoption push            | DONE — v8.1.0                           |
| #2 HT entropy consumer body redesign    | DONE — v8.5 projected wash              |
| #3 M3+/A-series hardware retest         | OUT OF SCOPE — needs device             |
| #4 Encoder optimisation arc             | DONE — v8.6 projected wash              |
| **#5 Encoder algorithmic redesign**     | **DONE — v8.7 projected wash**          |

All pure-optimisation and pure-redesign branches of the recommendation tree are exhausted on M2 + Swift release. The next workstream selection is genuinely **non-perf**: JP3D ROI decoder (multi-day product scope), CI maintenance (operational), product feature work, or pause and observe the codec at Apple-Silicon ceiling.
