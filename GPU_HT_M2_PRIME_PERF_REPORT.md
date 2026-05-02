# GPU HT decode — end-to-end wall-clock report (M2P-5)

**Branch:** `gpu-ht-prod-integration` · **Date:** 2026-05-02 ·
**Hardware:** arm64 (Apple M2) ·
**Build:** `swift build -c release` ·
**Method:** 3 warmup runs + 5 timed runs per backend, median reported.

This is the production-decode-pipeline equivalent of v5.4.0's
kernel-level measurement. It compares `j2k decode` wall-clock
(decode-only, excluding file I/O) with and without `--gpu-ht` on
every PGM fixture committed under `Tests/Fixtures/CrossCodec/`.

| fixture | size | CPU HT (ms) | GPU HT (ms) | speedup | notes |
| --- | ---:| ---:| ---:| ---:| --- |
| ct_study_001_instance_000001 | 512x512 | 3.966 | 71.363 | 0.06x |  |
| ct_study_003_instance_000050 | 512x512 | 3.951 | 68.280 | 0.06x |  |
| dx_study_002_instance_000001 | 2800x2288 | 79.758 | 164.863 | 0.48x |  |
| mr_study_001_instance_000001 | 886x886 | 6.499 | 78.008 | 0.08x |  |
| mr_study_002_instance_000100 | 180x180 | 1.562 | 60.168 | 0.03x |  |
| px_study_001_instance_000001 | 2459x1316 | 40.334 | 118.817 | 0.34x |  |
| xa_study_001_instance_000001 | 1024x1024 | 16.126 | 87.469 | 0.18x |  |

## Headline finding

GPU HT is currently **slower** than CPU HT end-to-end on the
`j2k decode` CLI on every fixture in the corpus. The slowdown is
worst on small images (50×, sub-second images) and shrinks with
size — at the largest fixture (2800×2288) GPU HT reaches ~50% of
CPU HT throughput.

This is in tension with v5.4.0's kernel-level measurement
(1.14× CPU on a 777-block synthetic benchmark). Two things explain
the gap:

1. **Per-process Metal init cost** — every CLI invocation pays a
   ~50–60 ms baseline for Metal device init + shader compile +
   command queue setup. On the 180×180 fixture (the smallest in
   the corpus) the CPU path completes in ~1.5 ms total; this fixed
   cost is ~40× the actual decode work. CLI usage of `j2k decode`
   is the worst case for amortising this cost. Long-running SDK
   processes that decode many images in one process run see the
   cost paid once — the M2P-3 test (which decodes all 7 fixtures
   in one Swift process) finishes the full corpus in 0.79 s.
2. **Other pipeline stages still on CPU.** Even with `--gpu-ht`,
   the dequantisation, subband regrouping, colour transform, and
   DC offset run CPU-side. The CPU HT path benefits from these
   stages being CPU-co-located (no GPU↔CPU handoff). The
   kernel-level 1.14× win was measured in isolation and does not
   carry through end-to-end.

**What this release ships:** the integration shape and the
CLI surface, gated behind `--gpu-ht`. Default behaviour is
unchanged.

**What this release does not ship:** an end-user perf win for
single-shot CLI decodes. That requires reducing per-process
Metal init cost (cached pipeline state, persistent device) and/or
moving more pipeline stages onto the GPU.

## Method notes

- **CPU HT** column = `j2k decode -i fixture.jph` (default —
  HT entropy decode on CPU, inverse DWT also on CPU since `--gpu`
  is not auto-enabled by `j2k decode`).
- **GPU HT** column = `j2k decode -i fixture.jph --gpu-ht`. The
  `--gpu-ht` flag implies GPU inverse DWT (uses
  `J2KDecoder.decodeWithGPUHT` internally).
- "Speedup" is `CPU HT median / GPU HT median`. Numbers > 1.0×
  mean GPU HT is faster end-to-end; numbers < 1.0× mean CPU is
  faster on this fixture (typically because dispatch overhead
  exceeds the entropy-decode work for very small images).
- Reported number is the **median of 5 timed runs after 3 warmup
  runs**. Min/mean omitted from the table for readability.
- Decode-only wall-clock — file load and PGM write times are
  separated by the CLI's own timing breakdown and not included.

## Caveats

- **Single-machine measurement.** Apple M-series only. Numbers will
  shift on different generations (M1 / M2 / M3 / M4) and under
  different thermal load. The relative shape (which fixtures
  benefit, which don't) is more informative than the absolute
  speedups.
- **Apple GPU divergence ceiling.** Per the v5.4.0 release notes,
  variable-sized codeblocks within a SIMD warp limit lane
  utilisation. Fixtures with more uniform codeblock distributions
  see better speedups.
- **Other pipeline stages on CPU.** Even with `--gpu-ht`, the
  dequantisation, subband regrouping, colour transform, and DC
  offset still run CPU-side. Promoting any of those to GPU
  would amplify wins; treat the current numbers as a floor on
  what production GPU HT can deliver.
