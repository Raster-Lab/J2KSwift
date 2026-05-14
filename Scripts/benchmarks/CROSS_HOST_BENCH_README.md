# Cross-host warm cross-codec benchmark — automation

Two scripts that turn a one-line invocation on each Apple Silicon host into a
release-quality cross-host comparison report (e.g. M2 vs M4).

## Files

- `run_canonical_bench.sh` — one-command runner: builds release, ensures
  j2kd daemon is installed, runs the canonical warm cross-codec benchmark
  in **all three measurement modes** (in-proc + sustained + isolated),
  writes three host-labeled JSONs to `Documentation/Benchmarks/data/`.
- `compare_hosts.py` — given two (or more) host JSONs, emits a markdown
  report with per-codec aggregate speedup matrix, winner-pattern delta,
  and full per-fixture timing tables.

Both scripts cover **every measured codec** (J2KSwift, Kakadu, OpenJPH,
Grok) — not just J2KSwift.

## Workflow: M2 → M4 comparison

### 1. On the **M2** host (already done as of 2026-05-14)

```bash
Scripts/benchmarks/run_canonical_bench.sh
```

Produces:

```
Documentation/Benchmarks/data/benchmark-results-Mac142-9.5.2-warm-inproc-20260514.json
Documentation/Benchmarks/data/benchmark-results-Mac142-9.5.2-warm-sustained-20260514.json
Documentation/Benchmarks/data/benchmark-results-Mac142-9.5.2-warm-isolated-20260514.json
```

### 2. On the **M4** host

Same one-line invocation:

```bash
git pull --ff-only origin main
Scripts/benchmarks/run_canonical_bench.sh
```

`hw.model` differs (e.g. `Mac16,10` for M4 mini), so the output files land
beside the M2 ones with a different host tag. Total run time ≈ 15 min on M4.

Required local installs on the M4 host:
- Kakadu CLI (`/usr/local/bin/kdu_compress` + `kdu_expand`)
- OpenJPH (`brew install openjph` → `/opt/homebrew/bin/ojph_compress` + `ojph_expand`)
- Grok (`brew install grok-jpeg2000` → `/opt/homebrew/bin/grk_compress` + `grk_decompress`)

The runner installs the j2kd daemon automatically if not present.

### 3. Generate the comparison report

After the M4 JSONs are pulled back to the comparison machine (or generated
on a host that has both):

```bash
python3 Scripts/benchmarks/compare_hosts.py \
    Documentation/Benchmarks/data/benchmark-results-Mac142-9.5.2-warm-inproc-20260514.json \
    Documentation/Benchmarks/data/benchmark-results-Mac1610-9.5.2-warm-inproc-YYYYMMDD.json \
    --output Documentation/Benchmarks/CROSS_HOST_M2_M4_inproc.md
```

Repeat for the other two modes:

```bash
python3 Scripts/benchmarks/compare_hosts.py \
    .../benchmark-results-Mac142-9.5.2-warm-sustained-20260514.json \
    .../benchmark-results-Mac1610-9.5.2-warm-sustained-YYYYMMDD.json \
    --output Documentation/Benchmarks/CROSS_HOST_M2_M4_sustained.md

python3 Scripts/benchmarks/compare_hosts.py \
    .../benchmark-results-Mac142-9.5.2-warm-isolated-20260514.json \
    .../benchmark-results-Mac1610-9.5.2-warm-isolated-YYYYMMDD.json \
    --output Documentation/Benchmarks/CROSS_HOST_M2_M4_isolated.md
```

## What the report contains

Per direction (encode + decode):

1. **Aggregate speedup matrix** — for each codec, the median, min, and max
   `other_host ms ÷ baseline_host ms` ratio across all fixtures. >1× means
   the *other* host is faster.
2. **Winner pattern by host** — for each host, how many fixtures each codec
   wins outright. Surfaces shifts in the competitive landscape (e.g. if
   Kakadu's lead on M2 mammography fixtures evaporates on M4).
3. **Per-fixture detail** — full ms × codec × host table with per-codec
   speedup column for every one of the 38 fixtures. The release-quote
   evidence layer.

## Why three modes?

Each measurement mode answers a different consumer question (corrected
methodology per `Documentation/Benchmarks/DAEMON_OVERHEAD_METHODOLOGY_FINDING.md`):

| Mode | What it measures | When to cite |
|---|---|---|
| **in-proc** | Pure J2KSwift SDK call (no CLI, no XPC) — what an iOS/macOS app pays | Marketing claims for SDK consumers |
| **sustained** | Daemon CLI under back-to-back batch load | Claims for batch-pipeline / CLI users |
| **isolated** | Daemon CLI with cool-downs (best-case CLI) | Methodology cross-check; not for marketing |

External codecs (Kakadu, OpenJPH, Grok) are CLI-only on this benchmark
because we don't link their libraries in-process. Their numbers are
identical across in-proc and sustained modes (the J2KSwift column is the
only one that changes); the modes only matter for J2KSwift's CLI vs SDK
overhead distinction.
