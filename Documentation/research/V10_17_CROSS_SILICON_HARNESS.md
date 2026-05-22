# Cross-silicon comparison harness

**Branch:** `v10.17-research` · **Date:** 2026-05-22 · **Status:** ready
for device readings.

This is the harness for the cross-silicon arc — the one open question
left by v10.16/v10.17: codec-perf research on **M2** is at a structural
ceiling (`V10_16_GPU_DECODE_UNDERPERF.md`, `V10_17_GPU_HT_ENTROPY_REDESIGN.md`),
but M3 / M4 / A-series GPU and CPU cores run serial code faster, so the
CPU↔GPU decode crossover may genuinely differ. This harness ingests
per-device benchmark JSONs and produces the comparison.

## The question

1. **Positioning.** How does J2KSwift decode/encode wall scale across
   Apple silicon (M2 → M4 → A18 Pro …)? Backs the "fastest JPEG 2000
   codec on Apple Silicon" claim.
2. **The v10.17 GPU crossover.** On M2, `decodeGPU`/`decodeWithGPUHT`
   never beat the CPU C+NEON path on lossless (structural — see
   V10_17). Do they on a newer GPU? If a device shows a GPU win,
   `recommendedDecodeAPI` should be re-calibrated for that silicon
   class.

## Data-collection flow

```
J2KBenchApp (v10.5-research)  →  Ad Hoc .ipa  →  Diawi link
        ↓ tester installs, runs the bench, taps "Share Selected"
   benchmark-results-<model>-<version>-warm-inproc-<YYYYMMDD>.json
        ↓ AirDrop / email back
   Documentation/Benchmarks/data/        ← drop the JSON here
        ↓
   python3 Scripts/benchmarks/cross_silicon_compare.py
```

- The Ad Hoc IPA build is the saved procedure in
  [[ipa-for-diawi]] (`feedback_ipa_for_diawi.md`).
- The JSON is the canonical `compare_hosts.py` schema (top-level
  `host` / `encode` / `decode`, `J2KSwift+inproc` codec) — J2KBenchApp's
  "Share Selected" emits exactly this.
- File-name convention `benchmark-results-<model>-<ver>-warm-inproc-<date>.json`
  buckets it for the glob.

## Running the comparison

```bash
# all *warm-inproc*.json under Documentation/Benchmarks/data/
python3 Scripts/benchmarks/cross_silicon_compare.py \
    --output Documentation/Benchmarks/CROSS_SILICON_REPORT.md

# or explicit hosts, choosing the baseline
python3 Scripts/benchmarks/cross_silicon_compare.py \
    data/benchmark-results-Mac142-*-warm-inproc-*.json \
    data/benchmark-results-iPhone17,1-*-warm-inproc-*.json \
    --baseline Mac142
```

It prints a per-fixture decode + encode wall table, one column per
host, plus the speedup of every host against the baseline. Smoke-tested
against the committed M2/M4 baselines (M4 decode is 1.4–1.8× M2).

## M2 baseline anchor

The crossover to beat, measured on Apple M2 (v10.16/v10.17, warm
in-process, lossless HT, median of 7):

| Fixture | px | CPU `decode()` ms | `decodeGPU` ms | `decodeWithGPUHT` ms |
|---|---:|---:|---:|---:|
| xa_001 | 1.05 M | 7.2 | 7.5 | 33.0 |
| px_001 | 3.24 M | 26.6 | 27.4 | 118.8 |
| dx_002 | 6.4 M | 47.8 | 47.8 | 128.7 |

On M2: `decodeGPU` ≈ CPU; `decodeWithGPUHT` is 2.7–4.6× **slower**. A
newer device "moves the crossover" if its `decodeGPU` or
`decodeWithGPUHT` column drops **below** its CPU column.

## The GPU columns

J2KBenchApp's "Share Selected" export carries all three decode lanes
per fixture — `J2KSwift+inproc` (`decode()`), `J2KSwift+gpu`
(`decodeGPU()`) and `J2KSwift+gpuht` (`decodeWithGPUHT()`) — landed on
`v10.5-research` (`BenchStore.exportData`, commit `9f1f139`).
`cross_silicon_compare.py` reads them and emits a per-host
**CPU ↔ GPU decode crossover** table, so a single device JSON answers
both questions above on its own.

Device JSONs must come from a J2KBenchApp build at or past `9f1f139`.
Older JSONs and the macOS `cross_codec_warm_bench.py` baselines carry
only `J2KSwift+inproc`; the harness still produces the positioning
tables for them and notes the crossover table is unavailable.

## What to look for

- **Decode positioning** — A18 Pro / M4 decode wall vs M2; expect
  monotonic improvement with silicon generation.
- **GPU crossover** — the per-host *CPU ↔ GPU decode crossover* table.
  Any device where `decodeGPU` or `decodeWithGPUHT` comes in below
  `decode()` warrants a `recommendedDecodeAPI` re-calibration for that
  silicon class and re-opens the V10_17 question for that hardware.
- **Encode** — secondary; encode is CPU-only, so it is a pure
  CPU-core-speed scaling check.
