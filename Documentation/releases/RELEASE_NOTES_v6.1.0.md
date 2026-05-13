# J2KSwift v6.1.0 Release Notes

**Release Date**: 2026-05-07
**Release Type**: Minor
**Previous Version**: 6.0.0
**Branch**: main

---

## Summary

v6.1.0 promotes the v6.0.0 opt-in **GPU forward 5/3 INT DWT path** to **production-default** for ≥4 MP fixtures. The path was already shipping as opt-in via `J2K_GPU_FORWARD_53=1`; v6.1.0 flips the default so users on Apple Silicon automatically get the 17–24% wall-time reduction at 4-16 MP without setting an env var. The pre-existing 4 MP threshold predicate keeps small fixtures on CPU where Phase 5 measured GPU loses on dispatch overhead, so default behaviour for users below the threshold is unchanged.

**Bytes are byte-identical to v6.0.0 / v5.38.0 / every prior tag.** This is a routing-only change: the GPU and CPU DWT paths produce the same coefficients to the same precision (the Phase-8 byte-identical guarantee from v6.0.0 applies unchanged). Per [`RELEASING.md`](RELEASING.md) SemVer rules, this qualifies as MINOR — no API change, no codestream-byte change, no default-flip on the wire.

The bulk of the release also lands the v6-alpha6 entropy arc (4 PRs of GPU + CPU-SIMD entropy work — opt-in only, all kept default-off after empirical wash), the v6-alpha7 tier-2 arc (2 PRs of allocation-reduction + sub-stage profiling), a canonical lossless stage breakdown, and an updated [`RELEASING.md`](RELEASING.md) requiring fresh cross-codec + medical-corpus benchmarks inline in every release notes from this version forward.

---

## What's New — production-default

### M1 — GPU forward 5/3 INT DWT default-ON for ≥4 MP (PR #310)

`EncoderPipeline._gpuForward53Enabled` initial value flipped from `false` → `true`. The 4 MP threshold predicate (`_gpuForward53PixelThreshold = 4_000_000`, unchanged from v6.0.0) gates small fixtures out where dispatch overhead dominates and CPU wins. On Apple M2:

| fixture | px | CPU forward ms | GPU(default) ms | Δ % | route on default |
|---|---:|---:|---:|---:|:---|
| MR-small 180² | 32,400 | 1.01 | 1.17 | −15.4 | CPU (gated) |
| CT 512² | 262,144 | 3.84 | 3.23 | +15.8 | CPU (gated) |
| MR 886² | 784,996 | 6.00 | 5.43 | +9.5 | CPU (gated) |
| XA 1024² | 1,048,576 | 11.67 | 10.50 | +10.0 | CPU (gated) |
| PX 2459×1316 | 3,236,044 | 35.44 | 38.31 | −8.1 | CPU (gated) |
| **DX 2800×2288** | **6,406,400** | **69.80** | **54.94** | **+21.3** | **GPU** |

(Apple M2, release mode, median of 3 — `GPUForward53DefaultOnTests.testDefaultOn_WallTimeAB_AcrossCorpus`.)

Sub-4 MP fixtures route to CPU on **both** paths (threshold predicate fires before the flag is consulted), so deltas there are M2 wall-time jitter — the route column confirms the threshold gate is doing its job. **DX +21.3%** is the headline; matches the v6-alpha5 Phase 9 published curve (+19.4% at 4 MP, +20.8% at 12 MP — DX 2800×2288 sits at ~6.4 MP between those points).

**Opt out** for hosts where the GPU dispatch curve hasn't been re-validated (x86/Linux with Metal-via-MoltenVK, future Apple Silicon generations):

```bash
export J2K_GPU_FORWARD_53=0     # or false / no
```

Or programmatically: `EncoderPipeline._gpuForward53Enabled = false`.

### M2 — Tier-2 tag-tree allocation reduction (PR #307)

`J2KTagTree` (used by `writePacket` for inclusion + zero-bit-plane encoding) gained a per-tree reusable `pathScratch: [Int]` buffer. The previous implementation allocated a fresh `[Int]` per `encode`/`decode` call via `rootToLeafPath`; v6.1.0 walks leaf-to-root into the scratch buffer instead. ~3,200 fewer `[Int]` allocations per DX 12 MP encode.

Wall-time impact on M2 medical corpus: **wash within ±5% noise band** — modern Swift `Array<Int>` allocations are well-optimised. Reduction matters more on memory-constrained hosts (older iOS, embedded). Bytes byte-identical (verified by 6/6 corpus determinism + cross-codec gate).

### M3 — Profiling infrastructure (PR #308 + #309)

Two new always-on accumulators (mirror the v5.29.0 `J2KEncodeTimings` pattern) so future perf work has data to reason about:

- **`J2KTier2Timings`** — six sub-stage accumulators inside `writePacket` (tagTreeBuild, tagTreeInclusionEncode, tagTreeZBPEncode, passesEncoding, lengthSignaling, rawDataAppend) + writePacketCount + includedBlockCount counters
- **Lossless-corpus stage table** — first canonical breakdown of `J2KEncodeTimings` for the lossless 5/3 HT-conformant production path; the existing corpus profile only covered lossy 9/7

The data corrected two stale stage estimates that had been guiding perf-arc planning:
- `writePacket` is **2.5% of DX wall, not 9%** (the cited 9% included codestream marker writes outside `writePacket`)
- DWT is **39.7% of DX wall, not 8%** — and is exactly the lever this release pulls (M1 above)

---

## What's New — opt-in (default-OFF)

### M4 — GPU forward HT entropy path (`J2K_GPU_FORWARD_HT_ENTROPY=1`, PRs #300–#305)

The v6-alpha6 entropy arc landed a complete GPU forward HT entropy implementation (per-sample classifier kernel, Swift wrapper, encoder consume path, batched API, orchestrator wire-in, telemetry). All bytes byte-identical to CPU; full bit-exact validation through 73,728 random samples + the medical corpus.

**Default OFF** because Phase 1.3's empirical wall-time A/B (#305) measured the GPU classify + CPU emit pipeline as a **regression at every corpus scale on Apple M2** (−141% to −249%). The dispatch + readback overhead exceeds the per-sample classification work moved to GPU (sampleInfo is <5% of per-block emit cost; the rest stays on CPU).

The code ships behind the gate flag for cross-device retesting on M3 / M4 / M4 Pro / M4 Max — newer Apple Silicon may shift the dispatch curve enough to flip the decision. See `HTGPUForwardHTEntropyOrchestratorTests.testOrchestrator_WallTimeAB_AcrossCorpus` for the reusable measurement harness.

### M5 — CPU-SIMD per-quad classifier (`J2K_HT_SIMD=1`, PR #306)

Approach E from the v6-alpha6 plan — promote the v5.39 M1 SIMD per-quad classifier to production. Phase 1.4 measured this as a **statistical wash** on M2 (4/6 fixtures within ±3%, 1 wins +10%, 1 regresses −7% in opposite directions at the same block count — content-dependent, not population-level). Default left OFF; `_htSIMDClassificationEnabled` is now `var` (was `let`) so future cross-device sweeps can re-test without recompile.

---

## Backward compatibility

Codestream bytes byte-identical to **every prior tag** (v5.38.0 / v6.0.0 / v6.0.x) on the production-default path. The v6.1.0 default flip routes ≥4 MP fixtures through the GPU DWT kernel that was already byte-identical to the CPU DWT in v6.0.0 (verified by Phase 8: 21/21 cross-codec cells through OpenJPH 0.27.0 / Grok 20.3.0 / Kakadu 8.4.1 demo). The threshold predicate keeps sub-4 MP fixtures on the same CPU path they used in v6.0.0.

Verified fresh on the v6.1.0 release-candidate commit:

```
GPUForward53DefaultOnTests.testDefaultOn_BytesIdentical_VsForcedOff_AcrossCorpus
  6/6 corpus fixtures: codestream bytes byte-identical between
  default-on (production now) and forced-off (legacy CPU path)
```

Any v6.0.x consumer can upgrade with no observable difference except wall time on ≥4 MP fixtures. v5.38.0 consumers get the cumulative byte-identical guarantee for the production single-tile + small-image paths, plus all the post-v5.38 features (`.auto` multi-tile from v6.0.0 + GPU forward DWT default-on from v6.1.0).

---

## Cross-codec parity matrix

Fresh measurement on the v6.1.0 release-candidate commit (Apple M2, release mode). Numbers are max-abs-pixel-diff vs the original PGM; **0 = bit-exact**.

### GPU-forward path × external decoders (HTGPUForward53CrossCodecTests)

| Modality | Shape | Bytes | OpenJPH 0.27.0 | Grok 20.3.0 | Kakadu 8.4.1 |
|---|---|---:|---:|---:|---:|
| MR-small | 180×180 | 45,224 | 0 | 0 | 0 |
| CT | 512×512 | 436,460 | 0 | 0 | 0 |
| CT | 512×512 | 406,187 | 0 | 0 | 0 |
| MR | 886×886 | 167,728 | 0 | 0 | 0 |
| XA | 1024×1024 | 1,621,219 | 0 | 0 | 0 |
| PX | 2459×1316 | 6,431,507 | 0 | 0 | 0 |
| DX | 2800×2288 | 12,683,182 | 0 | 0 | 0 |

**21 / 21 cells bit-exact.** GPU forward 5/3 INT bytes (now production-default for ≥4 MP) decode pixel-perfect through every external HT-conformant decoder.

### Multi-tile parity matrix (HTTileParityMatrixTests)

| Modality | Shape | Mode | Cols×Rows | Parity | Self RT | OpenJPH | Grok | Kakadu |
|---|---|---|---|---|---:|---:|---:|---:|
| MR | 886×886 | 2x2 | 2×2 | any-odd | 0 | 0 | 0 | 0 |
| MR | 886×886 | 4x4 | 4×4 | all-even | 0 | 0 | 0 | 0 |
| MR | 886×886 | strips4 | 1×4 | all-even | 0 | 0 | 0 | 0 |
| XA | 1024×1024 | 2x2 | 2×2 | all-even | 0 | 0 | 0 | 0 |
| XA | 1024×1024 | 4x4 | 4×4 | all-even | 0 | 0 | 0 | 0 |
| XA | 1024×1024 | strips4 | 1×4 | all-even | 0 | 0 | 0 | 0 |
| PX | 2459×1316 | 2x2 | 2×2 | all-even | 0 | 0 | 0 | 0 |
| PX | 2459×1316 | 4x4 | 4×4 | any-odd | 0 | 0 | 0 | 0 |
| PX | 2459×1316 | strips4 | 1×4 | any-odd | 0 | 0 | 0 | 0 |
| DX | 2800×2288 | 2x2 | 2×2 | all-even | 0 | 0 | 0 | 0 |
| DX | 2800×2288 | 4x4 | 4×4 | all-even | 0 | 0 | 0 | 0 |
| DX | 2800×2288 | strips4 | 1×4 | all-even | 0 | 0 | 0 | 0 |

**36 / 36 cells max-abs-pixel-diff = 0** (12 multi-tile combinations × 3 external decoders, plus self-roundtrip).

---

## Medical-corpus benchmarks

### Per-stage encode breakdown — lossless 5/3 HT-conformant (Apple M2, release, median of 5)

Captures the canonical v6.1.0 stage breakdown so future perf-arc planning has fresh numbers (the v6-alpha6 plan cited estimates that turned out to be off — entropy 45% / DWT 8% became the actual entropy 60.9% / DWT 27.4% on DX after the v6.1.0 default flip).

| Fixture | px | total ms | preproc | DWT | entropy | codestream |
|---|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 32,400 | 0.78 | 0.02 | 0.20 | 0.37 | 0.14 |
| CT 512² | 262,144 | 2.88 | 0.09 | 1.00 | 1.50 | 0.25 |
| MR 886² | 784,996 | 5.05 | 0.25 | 3.21 | 1.28 | 0.25 |
| XA 1024² | 1,048,576 | 10.41 | 0.33 | 3.98 | 5.43 | 0.80 |
| PX 2459×1316 | 3,236,044 | 36.71 | 1.48 | 13.32 | 18.54 | 2.96 |
| **DX 2800×2288** | **6,406,400** | **60.00** | **2.91** | **16.45** | **36.56** | **4.95** |

(Times in ms. `colour` and `quant` stages are 0 across the corpus — no MCT for grayscale, identity quantization for lossless. `rateCtrl` is <0.1 ms (PCRD doesn't run on the lossless path). The "sum" / "accounted %" columns from the diagnostic test are omitted here for brevity; per-stage % can sum to >100% on small fixtures because of `withThrowingTaskGroup` parallelism.)

### DX 2800×2288 stage % (the headline shift between v6.0.0 and v6.1.0)

| Stage | v6.0.0 default-off | v6.1.0 default-on |
|---|---:|---:|
| DWT | 27.39 ms (39.7%) | **16.45 ms (27.4%)** |
| entropy | 33.93 ms (49.2%) | 36.56 ms (60.9%) |
| codestream | 5.53 ms (8.0%) | 4.95 ms (8.2%) |
| preproc | 2.50 ms (3.6%) | 2.91 ms (4.8%) |
| **Total encode wall** | **68.98 ms** | **60.00 ms** |

DWT absolute time drops by 10.94 ms (40% reduction in the stage); total wall drops by 8.98 ms (13% of total). Entropy's relative share goes UP because the absolute denominator shrank — entropy is now even more clearly the largest unaccelerated stage (60.9%) and the natural target for a future v6-alpha8 arc.

### Default-on A/B vs forced-off (PR #310 measurement, fresh on rc commit)

Repeated here for the encode wall A/B (`GPUForward53DefaultOnTests.testDefaultOn_WallTimeAB_AcrossCorpus`). See M1 in *What's New* above for the table.

---

## Test Suite Results (v6.1.0 release-candidate, 2026-05-07)

Mandatory pre-release commit gate, release mode:

| Suite | Tests | Passed | Failed | Duration |
|---|---:|---:|---:|---:|
| J2KMedicalCorpusEncodePerformanceTests | 2 | 2 | 0 | 32.0 s |
| J2KMedicalCorpusPerformanceTests | 2 | 2 | 0 | 17.3 s |
| J2KStrictCrossCodecValidationTests | 3 | 3 | 0 | 0.5 s |
| **Mandatory gate total** | **7** | **7** | **0** | **49.7 s** |

Plus the new + updated validation suites added in v6.1.0:

| Suite | Cells | Passed | Notes |
|---|---:|---:|---|
| HTTileParityMatrixTests | 36 | 36 | 12 multi-tile fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| HTGPUForward53CrossCodecTests | 21 | 21 | 7 fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| GPUForward53DefaultOnTests (new) | 4 | 4 | bytes-identical + telemetry routing + opt-out + wall-time A/B |
| HTGPUForwardEntropyConsumeBitExactTests | 3 | 3 | Phase 1.1 — encoder consume path bit-exact |
| HTGPUForwardEntropyBatchBitExactTests | 4 | 4 | Phase 1.2 — batched API bit-exact |
| HTGPUForwardEntropyOrchestratorTests | 3 | 3 | Phase 1.3 — orchestrator wire-in bit-exact + routing + perf A/B |
| HTApproachECPUSIMDTests | 2 | 2 | Phase 1.4 — CPU-SIMD bit-exact + perf A/B |
| Tier2TagTreePathScratchTests | 3 | 3 | tag-tree determinism + baseline |
| Tier2WritePacketSubstageProfileTests | 3 | 3 | reset + populated + sub-stage breakdown |
| EncodeStageProfileLosslessCorpusTests | 1 | 1 | canonical lossless stage breakdown |
| HTGPUForwardClassifierBitExactTests | 3 | 3 | 73,728 samples bit-exact vs CPU sampleInfo |
| HTGPUForwardEntropyDispatchProbeTests | 1 | 1 | Phase 0.5 — dispatch latency floor |

---

## API surface — additions only, no breaks

All v6.0.0 public API preserved. Additions in v6.1.0:

- `EncoderPipeline._htSIMDClassificationEnabled` — was `let`, now `var` (opt-in mutation surface for cross-device A/B; production default unchanged from v6.0.0)
- `EncoderPipeline._gpuForwardHTEntropyEnabled: Bool` — opt-in flag for GPU forward HT entropy (default `false`, env var `J2K_GPU_FORWARD_HT_ENTROPY=1`)
- `EncoderPipeline._gpuForwardHTEntropyBlockThreshold: Int` — codeblock-count threshold (default 256, opt-in only)
- `J2KGPUForwardHTEntropyTelemetry` enum — snapshot/reset + per-skip-reason counters
- `J2KGPUForwardHTEntropyBatch` — public batched GPU-classify + CPU-emit API
- `J2KGPUForwardHTEntropyBatch.PendingBlock`, `EncodedBlock`
- `J2KMetalHTForwardClassifier`, `J2KMetalHTForwardClassifyDescriptor`, `J2KMetalHTForwardClassifierTuple`
- `J2KMetalHTForwardDispatchProbe`, `J2KMetalHTForwardBlockDescriptor`, `J2KMetalHTForwardDispatchProbeStatistics`
- `J2KTier2Timings` enum — snapshot/reset + 6 sub-stage accumulators
- `HTBlockEncoderConformant.encode(..., preClassifiedTuples: UnsafeBufferPointer<UInt64>?)` — new overload; existing 3-emitter overload preserved as a thin wrapper

Default behaviour with default config differs from v6.0.0 in exactly one routing: ≥4 MP fixtures route to GPU forward DWT instead of CPU. Bytes unchanged.

---

## Known limitations

- **GPU forward DWT default-on is Apple Silicon only.** On hosts without Metal (Linux x86, Windows non-Apple) the gate's `J2KMetalDWT.isAvailable` predicate fires false; CPU path runs as before. No regression on those hosts.
- **GPU forward HT entropy is opt-in only on M2.** Phase 1.3 measured −141% to −249% wall regression at every corpus scale on M2 (#305). Default OFF; cross-device retesting on M3/M4 is the gate to flipping.
- **CPU-SIMD per-quad classifier is opt-in only on M2.** Phase 1.4 measured a wash (#306); default OFF.
- **`release.yml` validate job removed in v6.0.1** because CI can't resolve the sibling `../CompressionFamily` package dep. Manual fallback used for v6.0.0; same fallback applies for v6.1.0 if the GitHub workflow stalls.
- **Threshold for GPU forward DWT (4 MP) is an Apple M2 number.** Newer Apple Silicon (M3/M4/M4 Pro/M4 Max) may shift the crossover; the threshold is `var`-overridable at runtime via `EncoderPipeline._gpuForward53PixelThreshold`. The `MEDICAL_BENCHMARK_V6.md` cross-device template documents the re-tuning protocol.

---

## Reproducing the headline numbers

```bash
# Mandatory pre-release gate (release mode)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix (multi-tile 36/36 + GPU-forward 21/21)
swift test -c release \
  --filter 'HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures|HTGPUForward53CrossCodecTests'

# Per-stage encode breakdown across the lossless corpus
swift test -c release \
  --filter EncodeStageProfileLosslessCorpusTests

# Default-on wall-time A/B (the M1 headline)
swift test -c release \
  --filter GPUForward53DefaultOnTests/testDefaultOn_WallTimeAB_AcrossCorpus

# Tier-2 sub-stage breakdown (M3 measurement)
swift test -c release \
  --filter Tier2WritePacketSubstageProfileTests/testTier2WritePacket_SubstageBreakdown_AcrossCorpus
```

External decoder binaries on PATH for cross-codec tests:
- `ojph_expand` / `ojph_compress` — OpenJPH 0.27.0 (`brew install openjph`)
- `grk_decompress` / `grk_compress` — Grok 20.3.0 (`brew install grokj2k`)
- `kdu_expand` / `kdu_compress` — Kakadu 8.4.1 demo

---

## Companion documents

- [`RELEASING.md`](RELEASING.md) — branching model + release flow (updated this release: cross-codec + medical benchmarks now mandatory inline in every release notes)
- [`BENCHMARK_REPORT_v6_alpha5_phase9.md`](BENCHMARK_REPORT_v6_alpha5_phase9.md) — full HT-fair encode/decode tables + tile parity matrix + Phase 9 threshold-boundary sweep (v6.0.0 era; numbers stand for v6.1.0 since the GPU forward DWT bytes are unchanged)
- [`CROSS_VERSION_DELTA_REPORT.md`](CROSS_VERSION_DELTA_REPORT.md) — v5.38.0 ↔ v6.0.0 byte-equality + per-fixture speed deltas (v6.1.0 preserves the v6.0.0 byte-equality on the unchanged paths and adds the new GPU-default routing on top)
- [`MEDICAL_BENCHMARK_V6.md`](MEDICAL_BENCHMARK_V6.md) — phase-by-phase trajectory across v6-alpha2 → v6-alpha5 + cross-device tuning template
- [`docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md`](docs/V6_ALPHA6_GPU_FORWARD_HT_ENTROPY_PLAN.md) — design doc for the entropy arc that produced the opt-in code now shipped
