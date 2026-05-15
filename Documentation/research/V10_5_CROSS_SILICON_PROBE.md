# v10.5 — Cross-silicon validation arc (M2 / M3 / M4 / A-series)

**Branch:** `v10.5-research`
**Status:** scoping; M2 v10.1.0 canonical baseline in flight; M3/M4/A-series captures pending hardware access.

## Why this arc exists

Every research arc closed in v10.0-v10.4 carried the same caveat: **measurements are M2 + Swift release + macOS only.** Per `feedback_apple_only_v8` (2026-05-09) J2KSwift targets Apple Silicon only, and the M2 lever-ceiling pattern that washed v6-alpha4 through v10.4 may not generalise to:

- **M3 / M3 Pro / M3 Max / M3 Ultra** — improved NEON, larger L2, different prefetcher.
- **M4 / M4 Pro / M4 Max** — second-gen Apple Silicon-on-N3E, wider GPU, new ANE.
- **A17 Pro / A18 / A18 Pro** — iPhone-class with thermal-throttled sustained workload patterns.
- **A18 Pro on iPad** — sustained-power profile vs phone.

The v10 series shipped two production wins (v10.0.0 + v10.1.0) and four research-only outcomes (v10.2 decode arc closure, v10.3 stage profile finding, v10.4 encoder arc wash on three levers). All measured on **a single M2 MacBook Air** (Mac14,2). Cross-silicon measurement is the only frontier left after the M2 lever-ceiling is reached.

## Existing infrastructure (already committed pre-v10)

Per `Scripts/benchmarks/CROSS_HOST_BENCH_README.md`:

- `Scripts/benchmarks/run_canonical_bench.sh` — one-command runner. Builds release, installs j2kd daemon, runs cross-codec warm bench in **3 modes** (in-proc, sustained, isolated). Writes 3 JSONs labeled `benchmark-results-<hw.model>-<j2k-version>-warm-<mode>-<date>.json` to `Documentation/Benchmarks/data/`.
- `Scripts/benchmarks/compare_hosts.py` — given 2+ host JSONs, emits markdown report with aggregate speedup matrix, winner-pattern delta, per-fixture timing tables across every measured codec (J2KSwift, Kakadu, OpenJPH, Grok).
- `Documentation/Benchmarks/data/` — historical host data:
  - M2 (Mac14,2) v9.5.2: in-proc + sustained + isolated, dated 2026-05-14
  - M4 (Mac16,10) v9.5.2: in-proc + sustained + isolated, dated 2026-05-14
  - M4 progression v8.1.4 → v9.4.0 (May 11): historical, single-mode
- `Documentation/Benchmarks/CROSS_HOST_M2_M4_inproc.md` / `_sustained.md` / `_isolated.md` — v9.5.2 baseline comparison reports.

**Missing**: v10.0.0 + v10.1.0 cross-host data. v10.5 fills this gap.

## Measurement scope

Three modes per the existing canonical script:

| Mode | What it measures | What it isolates |
|---|---|---|
| **In-proc** | SDK direct calls (`J2KEncoder.encode(_:)` / `J2KDecoder.decode(_:)`) | Pure codec hot-path; no fork/exec, no IPC. v8.4 / v10.1.0 wins live here. |
| **Sustained** | Per-call CLI invocation × N fixtures, j2kd daemon warm | Steady-state user workflow. Daemon overhead included. |
| **Isolated** | Single one-off CLI invocation, no daemon | Cold-start sensitivity; "first decode of the day" for SDK consumers. |

Per `feedback_warm_bench_mandatory.md`: every release quoting perf must cite the canonical bench. v10.5 plans extend this to multi-host.

## What we're testing (cross-silicon hypotheses)

The M2 lever-ceiling cluster suggests these levers may flip on different silicon:

| Lever (closed wash on M2) | Hypothesised cross-silicon behaviour |
|---|---|
| v8.5 HT entropy consumer body batched-read (1.32 ms projected, below 3 ms gate) | Wider M3/M4 SIMD lanes may shift the per-quad cost down enough to clear the gate |
| v8.6 forward DWT inner lifting (memory-bound at 0.37 ns/sample) | M4's larger L2 (24 MB vs 16 MB) may move the bandwidth wall up; v10.4 E1D may flip from wash to win |
| v10.4 E1B tiled Metal forward DWT (wash on M2 encode) | M3/M4 GPU has more threadgroup memory + faster dispatch; encoder may flip from wash to win |
| Cross-tile entropy GPU batching (v7.5 wash) | A-series mobile silicon with discrete neural cores may benefit from GPU HT entropy where M2 wasn't |

These are hypotheses, not predictions. The arc's job is to MEASURE, not assume.

## Workflow

### 1. Generate baseline on each host (one-command per host)

```bash
git pull --ff-only origin main
git checkout main  # Or specific release tag for reproducibility
Scripts/benchmarks/run_canonical_bench.sh
```

Produces 3 JSONs in `Documentation/Benchmarks/data/`. Commit and push.

### 2. Cross-host compare on any machine that has the JSONs

```bash
python3 Scripts/benchmarks/compare_hosts.py \
    Documentation/Benchmarks/data/benchmark-results-Mac142-10.1.0-warm-inproc-*.json \
    Documentation/Benchmarks/data/benchmark-results-Mac1610-10.1.0-warm-inproc-*.json \
    --output Documentation/Benchmarks/CROSS_HOST_M2_M4_v10_1_0_inproc.md
```

Same for sustained + isolated modes.

### 3. Decide which wash-on-M2 levers to re-probe on other silicon

Re-run targeted research-branch A/Bs on the larger-silicon hosts to confirm/deny each hypothesis. v8.6 SIMD4 forward DWT is the cheapest re-test (already have `forward53_1D_SIMD4` in source on `v10.4-research`).

## What this commit does

- Drafts the cross-silicon arc plan (this document).
- Generates M2 v10.1.0 canonical baseline (3 modes, all 4 codecs, 38 fixtures × 7-run median).
- Commits all 3 JSONs to `Documentation/Benchmarks/data/` so M4/M3/A-series machines can compare against them.

## What this commit does NOT do

- M3 / M4 / A-series measurement — requires hardware. The canonical runner is one command on each device; the user runs it when hardware is available.
- v10.1.0 cross-host comparison report — pending second-host data.
- Re-test of any individual lever — that's per-arc work; this is infrastructure.

## Open follow-ups (when M4 / M3 data arrives)

1. Run `compare_hosts.py` on M2 + M4 v10.1.0 JSONs → produce 3 comparison reports (inproc + sustained + isolated).
2. Identify per-fixture deltas where M4 > M2 by ≥5% — those are the candidates for re-probing washed levers.
3. Update `feedback_apple_only_v8.md` with the cross-silicon position summary (e.g., "M4 closes Kakadu MG gap to 1.2× vs M2's 1.45×").
4. Decide whether any v10.4 research-only kernel (tiled Metal forward DWT, CPU SIMD4 forward) should be default-flipped on M4-class silicon.

## Critical files

- `Scripts/benchmarks/run_canonical_bench.sh` — one-command runner per host.
- `Scripts/benchmarks/compare_hosts.py` — cross-host comparator (already supports M2+M4 mode).
- `Documentation/Benchmarks/data/` — host JSONs land here per the canonical runner naming.
- `Documentation/Benchmarks/CROSS_HOST_*.md` — existing v9.5.2 reports as templates for v10.1.0 ones.

## Existing comparison baseline (v9.5.2)

`Documentation/Benchmarks/CROSS_HOST_M2_M4_inproc.md` — committed 2026-05-14. Shows M4 generally beats M2 by ~30% on warm in-proc encode/decode (single-thread NEON + Float32) but A-series-style sustained measurement wasn't taken. v10.5 extends the same comparison to v10.1.0 baseline and to iPhone/iPad silicon as hardware becomes available.
