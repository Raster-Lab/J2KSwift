# Benchmark results

Captures of `J2KMedicalCorpus*` benchmark output, by processor and release.

## Files

- `M2_run1.txt`, `M2_run2.txt`, `M2_run3.txt` — three independent runs on Apple M2 at
  v5.30.0 baseline (post-rateControl-fix). Captured 2026-05-04.
- `M4_run1.txt`, `M4_run2.txt`, `M4_run3.txt` — to be captured on Apple M4 (see
  "Capturing on a different processor" below).

## Capturing on a different processor

To produce a directly-comparable result file:

```bash
swift test -c release --filter "J2KMedicalCorpus" 2>&1 \
  | grep -E "^(=== |Processor:|Image:|Synthetic|Skipped|\| |Per-fixture|Cold session|preWarm|Warm session|Cold-start|Total cost)" \
  > benchmarks/M4_run1.txt
```

Repeat 3× for variance. The benchmark auto-tags with `Processor: <brand string>` from
`sysctlbyname("machdep.cpu.brand_string", ...)` — so each file is self-identifying.

The medical fixtures need to be present at `Tests/Fixtures/CrossCodec/`. The 3
mammography-class fixtures (`dx_001`, `mg_001`, `mg_002`) are not in-repo (~32 MB each
PGM); the benchmark synthesizes LCG-noise images at the same dimensions when they're
missing. Marked with `*` in output.

## Comparing M2 vs M4

The processor-specific summary table in
[MEDICAL_BENCHMARK.md](../MEDICAL_BENCHMARK.md) "Per-Processor Performance" section
distills the per-fixture medians from each processor's run files. Update both when
adding a new processor.

## Build / runtime

| Setting          | Value |
|------------------|-------|
| Build mode       | release (`swift test -c release`) |
| Sample count `n` | 5 per fixture per API |
| Bitrate          | 2 bpp HT-conformant lossy 9/7 |
| Warm-up          | 1 decode per API per fixture before timing |
| OS               | macOS 14+ (`canImport(Metal)` required for GPU paths) |

Variance across 3 runs on the same machine is typically ±5-15% for end-to-end times,
±20% for sub-stage times.
