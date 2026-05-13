# J2KSwift v5.5.0 — GPU HTJ2K decode in production (opt-in)

**Release date:** 2026-05-02
**Branch:** `gpu-ht-prod-integration` → `main`
**Companion:** continuation of v5.4.0; cross-codec verification + codestream output unchanged.

## What's in this release

The GPU HTJ2K cleanup decoder shipped in v5.3.0 / v5.4.0 (`J2KMetalHTCleanup`) was a self-contained prototype that lived in the test target. v5.5.0 wires it into the production decoder behind an opt-in flag:

- **`J2KDecoder.decodeWithGPUHT(_:)`** — new SDK entry point. When the codestream is HTJ2K conformant cleanup-only AND Metal is available, eligible codeblocks are batched through the Metal HT cleanup kernel. Ineligible blocks (refinement passes, custom format, empty data, parse failure) fall through to the existing CPU HT path automatically. Inert on Part 1 codestreams.
- **`j2k decode --gpu-ht`** — CLI surface. `j2k decode -i input.jph --gpu-ht -o output.pgm` opts into the GPU HT path for that single invocation.

Default behaviour is unchanged. `J2KDecoder().decode(...)` and `j2k decode` without the flag continue to route HT entropy decode entirely to CPU; nothing in this release is on by default.

## What this is not

**This release is not an end-user performance win for `j2k decode` CLI usage.** Per the perf report in [GPU_HT_M2_PRIME_PERF_REPORT.md](GPU_HT_M2_PRIME_PERF_REPORT.md), `j2k decode --gpu-ht` is currently **slower** than the default CPU path on every fixture in the DICOM corpus, ranging from 0.03× (180×180, the smallest fixture) to 0.49× (2800×2288, the largest):

| fixture | size | CPU HT (ms) | GPU HT (ms) | speedup |
| --- | ---:| ---:| ---:| ---:|
| mr_002 | 180×180 | 1.6 | 60.2 | 0.03× |
| ct_001 | 512×512 | 4.0 | 71.4 | 0.06× |
| mr_001 | 886×886 | 6.5 | 78.0 | 0.08× |
| xa_001 | 1024×1024 | 16.1 | 87.5 | 0.18× |
| px_001 | 2459×1316 | 40.3 | 118.8 | 0.34× |
| dx_002 | 2800×2288 | 79.8 | 164.9 | 0.48× |

Two reasons for the gap between v5.4.0's 1.14× kernel-level measurement and this end-to-end CLI measurement:

1. **Per-process Metal initialisation cost.** Each `j2k decode` invocation is a fresh process and pays ~50–60 ms for Metal device init, shader compilation, and command queue setup. On a 180×180 image where the CPU path completes in 1.5 ms total, this fixed cost is ~40× the actual decode work. Long-running SDK processes that decode many images in one process amortise this cost — the M2P-3 test that decodes all 7 fixtures inside a single Swift process completes the entire corpus in 0.79 s.
2. **Other pipeline stages still on CPU.** Even with `--gpu-ht`, dequantisation, subband regrouping, colour transform, and DC offset all run CPU-side. The CPU HT path benefits from being CPU-co-located across the whole pipeline (no GPU↔CPU handoffs). The kernel-level 1.14× win was measured in isolation and does not carry through end-to-end.

So why ship this release? Because **the integration shape is what unblocks future work**. Without `J2KGPUHTDispatch` wired into `J2KDecoderPipeline`, the next milestones — collapsing HT-cleanup → DWT into a single command buffer, persisting Metal pipeline state across decodes, GPU dequantisation — have nothing to plug into. v5.5.0 lays the foundation; subsequent releases turn it into a perf win.

## Bit-exactness

Verified across the entire fixture corpus:

- **`testFullDICOMCorpus_GPUHTMatchesCPUHT`** — encodes every PGM under `Tests/Fixtures/CrossCodec/` to HTJ2K conformant lossless and asserts `decodeWithGPUHT` produces output byte-identical to `decodeGPU` (CPU HT). 7/7 pass in 0.79 s release-mode.
- **Cross-codec matrix** — `Scripts/run_cross_matrix.sh --check` extended with three GPU-HT decode columns (`jcpu_to_jght_ht`, `jgpu_to_jght_ht`, `ojph_to_jght_ht`). Per-fixture cell count: 18 → 21. Total cells per run on the 7-fixture corpus: 126 → 147. All 147 match the new baseline byte-for-byte (or byte-swap-equivalent for the OpenJPH interop case where 16-bit PGM endianness conventions differ).
- **Synthetic gates** — `J2KGPUHTPipelineTests` (3 tests at 384×384 12-bit, 512×512 16-bit, plus the Part 1 inert-flag check), `J2KGPUHTDispatchTests` (3 tests at the dispatcher level). All 6 pass release-mode.

## Added

- **`Sources/J2KCodec/J2KGPUHTDispatch.swift`** — integration shim that batches eligible codeblocks into a single `J2KMetalHTCleanup.run` call and converts the kernel's UInt32 OpenJPH sign-magnitude output to the pipeline's Int32 integer-magnitude convention. Caller-side eligibility filter (conformant cleanup-only, non-empty, parseable) reports `cpuFallbackIndices` separately so callers can round-trip ineligible blocks through CPU.
- **`Sources/J2KCodec/J2KDecoderPipeline.swift`** — `useGPUHT: Bool = false` on `DecoderPipeline`; early GPU pass at the top of `applyEntropyDecoding` that builds a `[Int: [Int32]]` of pre-decoded blocks before the existing parallel + sequential CPU loops run.
- **`Sources/J2KCodec/J2KCodec.swift`** — `J2KDecoder.decodeWithGPUHT(_:)` and progress-callback overload.
- **`Sources/J2KCLI/Commands.swift`** — `j2k decode --gpu-ht` flag.
- **`Tests/J2KCodecTests/J2KGPUHTDispatchTests.swift`** + **`J2KGPUHTPipelineTests.swift`** — dispatcher and pipeline-level bit-exactness gates.
- **`Scripts/measure_gpu_ht_perf.sh`** — perf measurement harness.
- **`GPU_HT_M2_PRIME_PERF_REPORT.md`** — perf report committed alongside the code.
- **`GPU_HT_M2_PRIME_PLAN.md`** — five-milestone plan (M2P-1 through M2P-5, all complete in this release).

## Changed

- **`Scripts/run_cross_matrix.sh`** — adds three GPU-HT decode cells per fixture in the full-matrix mode; new `decode_j2k` "gpuht" backend branch alongside the existing "cpu" / "gpu". The `--cpu-only` mode is unchanged (GPU-HT requires Metal so it's skipped).
- **`Tests/Fixtures/CrossCodec/expected_results.csv`** — baseline updated to include the 21 new cells. The old 126 cells continue to match the v5.4.0 baseline byte-for-byte.

## Acknowledgements

This release is a follow-on to v5.4.0; the OpenJPEG (UCL) and OpenJPH (Aous Naman) reference implementations remain the codestream-correctness anchors that the cross-codec matrix verifies J2KSwift against.

## Source

- Branch: `gpu-ht-prod-integration` (5 commits ahead of v5.4.0)
- Plan: [GPU_HT_M2_PRIME_PLAN.md](GPU_HT_M2_PRIME_PLAN.md)
- Perf: [GPU_HT_M2_PRIME_PERF_REPORT.md](GPU_HT_M2_PRIME_PERF_REPORT.md)
- Commits:
  - `070662f` — M2P-1: scaffold + plan + dispatcher tests
  - `de1ac02` — M2P-2: production pipeline integration
  - `e4585c3` — M2P-3: corpus-wide bit-exactness gate
  - `b9364d4` — M2P-4: CLI flag + matrix coverage
  - (this commit) — M2P-5: perf report + release notes
