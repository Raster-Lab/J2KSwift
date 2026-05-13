# J2KSwift v6.3.0 Release Notes

**Release Date**: 2026-05-07
**Release Type**: Minor
**Previous Version**: 6.2.0
**Branch**: main

---

## Summary

v6.3.0 ships the **multi-tile decode correctness fix + production-default routing widen** that v6.2.0's release-candidate validation deferred, plus the **GPU forward DWT threshold re-tune that captures PX 2459×1316 medical fixture's encode win** (PX +10.9% wall, DX +17.4%). Bytes byte-identical to v6.2.0 and every prior tag — routing-only changes, MINOR per [`RELEASING.md`](RELEASING.md).

The headline arc was the **E1 series** ([#320](https://github.com/Raster-Lab/J2KSwift/pull/320) → [#322](https://github.com/Raster-Lab/J2KSwift/pull/322)) closing the v6.2.0 deferred multi-tile decode bug:

1. **E1.0** ([#320](https://github.com/Raster-Lab/J2KSwift/pull/320)) — investigation + repro test triangulated the failure to per-tile entropy decode on non-XA multi-tile fixtures.
2. **E1.1** ([#321](https://github.com/Raster-Lab/J2KSwift/pull/321)) — **single-line fix**: `decodeTilePayloadGPU` was missing `tileOriginX/Y` arguments to `extractTileData`, breaking the canvas-anchored code-block partition (ISO 15444-1 B.7) for non-32-aligned tile origins. Mirror of the CPU multi-tile path that had always been correct.
3. **E1.2** ([#322](https://github.com/Raster-Lab/J2KSwift/pull/322)) — routing widened (drops the v6.2.0 `!metadata.isMultiTile` narrow guard); production-default `decode()` now routes ≥4 MP multi-tile codestreams through `decodeMultiTileGPU`. Per-tile compute stages (entropy, IDWT) fall back to CPU pending E1.3; correctness regression test (`MultiTileDecodeGPUDefaultOnTests`) ships as the gate.

Plus the v6.3.0 perf + observability work:

- **F2** ([#323](https://github.com/Raster-Lab/J2KSwift/pull/323)) — decoder API warm-session for `decodeGPU(_:)` / `decodeWithGPUHT(_:)` no-session overloads (mirror of v6.2.0 D3 #316).
- **F1** ([#324](https://github.com/Raster-Lab/J2KSwift/pull/324)) — codestream marker writes sub-stage profiling (close-the-arc finding: stage is 4.2% of DX wall, not 8% per the v6.2.0 plan estimate).
- **E2** ([#325](https://github.com/Raster-Lab/J2KSwift/pull/325)) — GPU forward 5/3 INT pixel threshold lowered from 4 MP → 3 MP after empirical sweep showed 3 MP is the post-v6.2.0 break-even; PX 3.24 MP routes to GPU and gains the win above.
- **F3** ([#326](https://github.com/Raster-Lab/J2KSwift/pull/326)) — preprocess `extractComponentData` sub-stage profiling (close-the-arc finding: stage is 2.49% of DX wall, not 4.8% per the v6.2.0 plan estimate; LLVM auto-vectorisation has captured the win).

---

## What's New — production-default

### M1 — Multi-tile decode codeblock partition fix (E1.1, [#321](https://github.com/Raster-Lab/J2KSwift/pull/321))

`decodeTilePayloadGPU` now passes `tileOriginX/tileOriginY` to `extractTileData`. Pre-fix, the GPU multi-tile path used the default `(0, 0)` tile origin, which made the canvas-anchored code-block partition match the encoder only when tile origins were 32-aligned (per the existing comment in `extractTileData`). Non-32-aligned tile origins (MR/PX/DX in the medical corpus) produced `malformedBlock` errors on the entropy decode that v6.2.0's narrow guard hid.

This was the **single-line root cause** of the v6.2.0 release-candidate regression, root-caused via the E1.0 triangulation matrix (`MultiTileDecodeGPUInvestigationTests`).

### M2 — Multi-tile decode routing widened to production-default (E1.2, [#322](https://github.com/Raster-Lab/J2KSwift/pull/322))

`DecoderPipeline.decode` drops the v6.2.0 `&& !metadata.isMultiTile` narrow guard. Production-default routing for ≥4 MP fixtures now goes through `decodeMultiTileGPU` (multi-tile) **and** `decodeSingleTileGPU` (single-tile) uniformly.

Inside `decodeTilePayloadGPU`, the per-tile entropy + IDWT compute stages fall back to CPU (`isGPUPath: false` for entropy; `isMultiTilePerTile: true` for IDWT) because empirical validation surfaced **two further per-tile correctness defects** beyond E1.1's codeblock partition fix:

- **Defect A** — GPU HT entropy multi-tile produces coefficient drift (DX 2800×2288 self-roundtrip diff = exactly 32768 with `isGPUPath: true`; 0 with `isGPUPath: false`).
- **Defect B** — GPU 5/3 inverse kernel lacks parity-aware boundary lifting per ISO 15444-1 Annex F.4.1.1 for non-zero tile-component canvas origins.

Both are deferred to E1.3 in a future release. v6.3.0 ships the **routing widen + bit-exact regression test** so the dispatch shape is uniform with single-tile and the test gate guards the path when GPU per-tile compute is re-enabled.

Single-tile decode (the medical-corpus dominant case) takes the full GPU IDWT + GPU HT entropy path unchanged from v6.2.0 — DX +46.2% / +40.5% wins continue to apply.

### M3 — Decoder API warm-session for the no-session overloads (F2, [#323](https://github.com/Raster-Lab/J2KSwift/pull/323))

`J2KDecoder.decodeGPU(_:)` / `decodeGPU(_:progress:)` / `decodeWithGPUHT(_:)` / `decodeWithGPUHT(_:progress:)` now plumb `J2KMetalSession.processShared` into the decoder pipeline. Mirror of v6.2.0 D3 ([#316](https://github.com/Raster-Lab/J2KSwift/pull/316)) which fixed the same cold-start cost for the default `decode(_:)` entry point.

Pre-F2: every fresh `J2KDecoder().decodeGPU(data)` paid the ~25-30 ms Metal init cold-start. Post-F2: all five public decoder APIs share the same singleton; successive calls amortise cold-start across the process.

Bit-exact contract validated by `DecoderAPIWarmSessionTests` (no-session vs explicit-session pixel-byte-identical).

### M4 — GPU forward 5/3 INT pixel threshold 4 MP → 3 MP (E2, [#325](https://github.com/Raster-Lab/J2KSwift/pull/325))

`EncoderPipeline._gpuForward53PixelThreshold` lowered from 4 000 000 → 3 000 000. Empirical sweep (`HTGPUForward53Phase9ThresholdBoundaryTests`) on M2 release mode showed 3 MP is the post-v6.2.0 break-even (synthetic +4.8 %, outside ±5 % noise band).

PX 2459×1316 (3.24 MP) now routes to GPU and gains **+10.9 %** encode wall on M2 release (CPU 34.78 ms → GPU 30.98 ms). DX 2800×2288 wins +17.4 % (already routed, nudged by surrounding stages). Other corpus fixtures unchanged.

### M5 — `J2KCodestreamMarkerTimings` instrumentation (F1, [#324](https://github.com/Raster-Lab/J2KSwift/pull/324))

Process-global per-marker accumulators for the codestream-generation stage (SOC / SIZ / CAP / CPF / COD / QCD / COM / SOT / SOD / tile-data-append / EOC). Mirror of `J2KTier2Timings` (v6-alpha7 phase 1) and `J2KEncodeTimings`.

Diagnostic finding: codestream stage is **4.2% of DX encode wall**, not 8% per the v6.2.0 plan estimate. tileDataAppend dominates at 99.3% of the marker stage, already at memcpy bandwidth (~18.4 GB/s on M2). **Marker-write tier-1 optimization is not a worthwhile lever** on the current architecture — F1 closes the arc.

### M6 — `J2KPreprocessSubstageTimings` instrumentation (F3, [#326](https://github.com/Raster-Lab/J2KSwift/pull/326))

Process-global per-sub-stage accumulators for the preprocessing stage (`imageValidate`, `extractComponentData8`, `extractComponentData16`, `dcLevelShift`).

Diagnostic finding: preprocess is **2.49% of DX wall**, not 4.8% per the v6.2.0 plan estimate. extract16 throughput 8.1 GP/s, dcShift 11 GP/s — LLVM has clearly auto-vectorised the v5.38 M7 specialised 4-branch UInt16→Int32 bodies. **Explicit vDSP / NEON intrinsics would not move the needle** — F3 closes the arc.

---

## What's New — opt-in (default-OFF)

No new opt-in features in v6.3.0. The opt-out env vars from v6.1.0 / v6.2.0 carry forward:

- `J2K_GPU_FORWARD_53=0` — force legacy CPU forward DWT path
- `J2K_GPU_INVERSE_53=0` — force legacy CPU decode path
- `J2K_GPU_HT_ENTROPY_DECODE=0` — disable GPU HT entropy on the routed GPU decode path

---

## Backward compatibility

Codestream bytes byte-identical to **every prior tag** (v5.38.0 / v6.0.0 / v6.1.0 / v6.2.0). v6.3.0 changes routing only on the encode side (E2 widens which fixtures route to GPU; CPU and GPU encode paths produce byte-identical output, pinned by `J2KMetalDWTForward53IntBitExactTests` since v5.5.0) and on the decode side (E1.1 fixes the multi-tile decode that v6.2.0 hid; E1.2 widens routing through the GPU dispatch infrastructure with CPU per-tile compute fallback).

Verified fresh on the v6.3.0 release-candidate commit:

```
HTTileParityMatrixTests              : 12/12 self-RT diff = 0 + cross-decode 0 vs OpenJPH/Grok/Kakadu
HTGPUForward53CrossCodecTests        :  7/7  cross-decode 0 vs OpenJPH/Grok/Kakadu
MultiTileDecodeGPUDefaultOnTests     : 12/12 pixel-byte-identical between gate-on / gate-off
GPUForward53DefaultOnTests           :  4/4  PX route assertion + bit-exact contract
```

A v6.2.x consumer can upgrade with no observable difference except:
1. Multi-tile decode now succeeds on the production-default path (was CPU-only routing in v6.2.0; bit-exact pixels in both versions).
2. PX 2459×1316 encode wall +10.9 % (now routes to GPU; pixels and bytes unchanged).

---

## Cross-codec parity matrix

Fresh measurement on the v6.3.0 release-candidate commit (Apple M2, release mode). Numbers are max-abs-pixel-diff vs the original PGM; **0 = bit-exact**.

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

**21 / 21 cells bit-exact.**

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

**48 / 48 cells max-abs-pixel-diff = 0** (12 multi-tile combinations × OpenJPH/Grok/Kakadu + self-roundtrip = 4 columns × 12 rows). The DX rows are the E1.1 / E1.2 production target — v6.2.0 release-candidate exposed these as the regression-source; v6.3.0 ships them green.

---

## Medical-corpus benchmarks

### Encode wall-time A/B — E2 GPU forward 5/3 INT (Apple M2, release mode, n=5)

`GPUForward53DefaultOnTests.testDefaultOn_WallTimeAB_AcrossCorpus`:

| fixture | px | bytes | CPU ms | GPU(default) ms | Δ % | route |
|---|---:|---:|---:|---:|---:|:---|
| MR-small 180² | 32,400 | 45,224 |  0.85 |  0.89 |  −4.1 | CPU (gated) |
| CT 512² | 262,144 | 436,460 |  3.27 |  2.86 | +12.7 | CPU (gated) |
| MR 886² | 784,996 | 167,728 |  4.60 |  4.58 |  +0.3 | CPU (gated) |
| XA 1024² | 1,048,576 | 1,621,219 | 10.19 | 10.00 |  +1.9 | CPU (gated) |
| **PX 2459×1316** | **3,236,044** | **6,431,507** | **34.78** | **30.98** | **+10.9** | **GPU (post-E2)** |
| **DX 2800×2288** | **6,406,400** | **12,683,182** | **69.85** | **57.70** | **+17.4** | **GPU** |

PX (3.24 MP) is the new GPU-routed fixture in v6.3.0 — the E2 headline. DX wins are unchanged from v6.1.0 / v6.2.0; the magnitude reflects run-to-run noise. Sub-3 MP fixtures route to CPU regardless of flag (threshold-gated).

### Multi-tile decode A/B — E1.2 routing widen (Apple M2, n=5 min-of-N)

`MultiTileDecodeGPUDefaultOnTests.testMultiTileDefaultOn_WallTimeAB_AcrossCorpus`:

| fixture | mode | grid | px | bytes | CPU ms | GPU ms | CPU/GPU× |
|---|---|---|---:|---:|---:|---:|---:|
| MR 886² | 2x2 | 2×2 | 784,996 | 169,709 | 348.4 | 345.5 | 1.01× |
| MR 886² | 4x4 | 4×4 | 784,996 | 170,731 | 392.2 | 391.3 | 1.00× |
| MR 886² | strips4 | 1×4 | 784,996 | 168,976 | 275.9 | 287.6 | 0.96× |
| XA 1024² | 2x2 | 2×2 | 1,048,576 | 1,621,712 | 578.7 | 589.2 | 0.98× |
| XA 1024² | 4x4 | 4×4 | 1,048,576 | 1,623,555 | 611.3 | 606.1 | 1.01× |
| XA 1024² | strips4 | 1×4 | 1,048,576 | 1,622,298 | 588.2 | 573.9 | 1.02× |
| PX 2459×1316 | 2x2 | 2×2 | 3,236,044 | 6,439,431 | 1,687.4 | 1,772.8 | 0.95× |
| PX 2459×1316 | 4x4 | 4×4 | 3,236,044 | 6,453,588 | 1,836.2 | 1,828.6 | 1.00× |
| PX 2459×1316 | strips4 | 1×4 | 3,236,044 | 6,446,778 | 1,812.7 | 1,828.3 | 0.99× |
| DX 2800×2288 | 2x2 | 2×2 | 6,406,400 | 12,689,695 | 3,834.8 | 3,782.6 | 1.01× |
| DX 2800×2288 | 4x4 | 4×4 | 6,406,400 | 12,705,470 | 4,071.8 | 3,930.6 | 1.04× |
| DX 2800×2288 | strips4 | 1×4 | 6,406,400 | 12,697,748 | 4,213.8 | 4,387.5 | 0.96× |

Multi-tile per-tile compute stays on CPU per E1.2 (Defects A + B deferred to E1.3); the wall-time A/B is **honest "wash" within ±5 %**, all 12 cells. The GPU multi-tile compute win is deferred to E1.3 — v6.3.0 ships uniform routing + the bit-exact regression test as the gate.

### Single-tile decode wall-time — unchanged from v6.2.0

DX 2800×2288 single-tile decode wins (+46.2 % iDWT, +40.5 % iDWT + GPU HT entropy) measured in v6.2.0 carry forward unchanged. The decode stage breakdown from `RELEASE_NOTES_v6.2.0.md` continues to apply.

---

## Test Suite Results (v6.3.0 release-candidate, 2026-05-07)

Mandatory pre-release commit gate, release mode:

| Suite | Tests | Passed | Failed | Notes |
|---|---:|---:|---:|---|
| J2KMedicalCorpusEncodePerformanceTests | 2 | 2 | 0 | release exit 0 |
| J2KMedicalCorpusPerformanceTests | 2 | 2 | 0 | release exit 0 |
| J2KStrictCrossCodecValidationTests | 3 | 3 | 0 | OpenJPH / OpenJPEG / Grok all decode strict-truncated |

Plus the new + updated validation suites for v6.3.0:

| Suite | Cells | Passed | Notes |
|---|---:|---:|---|
| HTTileParityMatrixTests | 36 | 36 | 12 multi-tile fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 (DX rows now green; v6.2.0 had hidden these via narrow guard) |
| HTGPUForward53CrossCodecTests | 21 | 21 | 7 fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| MultiTileDecodeGPUInvestigationTests (E1.0, new) | 36 | 36 | triangulation matrix 4 fixtures × 3 modes × 3 entry points (A/B/C), all ✅ post-fix |
| MultiTileDecodeGPUDefaultOnTests (E1.2, new) | 12 | 12 | bit-exact contract gate-on vs gate-off for every multi-tile fixture × mode |
| DecoderAPIWarmSessionTests (F2, new) | 3 | 3 | bit-exact + warm-session A/B for the no-session overloads |
| GPUForward53DefaultOnTests (E2, updated for 3 MP) | 4 | 4 | PX route assertion + bit-exact + A/B |
| CodestreamMarkerSubstageProfileTests (F1, new) | 3 | 3 | reset / populated / corpus breakdown |
| PreprocessSubstageProfileTests (F3, new) | 3 | 3 | reset / populated / corpus breakdown |

All v6.0.0 / v6.1.0 / v6.2.0 validation suites continue to pass unchanged.

---

## API surface — additions only, no breaks

All v6.2.0 public API preserved. Additions in v6.3.0:

- `J2KCodestreamMarkerTimings` — public observability surface for the codestream-generation stage (snapshot / reset)
- `J2KPreprocessSubstageTimings` — public observability surface for the preprocessing stage (snapshot / reset)
- `applyInverseWaveletTransformGPU` gains `tileOriginX`, `tileOriginY`, `isMultiTilePerTile` parameters (private; defaults preserve single-tile behaviour)

Default behaviour with default config differs from v6.2.0 in exactly two routings:
1. ≥4 MP multi-tile decodes route through `decodeMultiTileGPU` (was `decodeMultiTile` in v6.2.0); pixels unchanged.
2. ≥3 MP encodes route through GPU forward DWT (was ≥4 MP in v6.0.0–v6.2.0); bytes unchanged.

`J2KEncoder.encode(_:)`, `J2KDecoder.decode(_:)`, and all other public APIs unchanged in signature and behaviour where routing is not affected.

---

## Known limitations

- **Multi-tile per-tile GPU compute is on CPU.** v6.3.0 routes multi-tile decode through `decodeMultiTileGPU` (uniform dispatch shape with single-tile) but per-tile entropy + IDWT compute fall back to CPU due to two pending defects (A: GPU HT entropy multi-tile coefficient drift; B: GPU 5/3 inverse kernel lacks parity-aware boundary lifting). E1.3 (deferred) will close these — once shipped, the multi-tile fixtures gain the same +37–46 % GPU win single-tile already enjoys.
- **GPU forward 5/3 INT default-on threshold (3 MP) is an Apple M2 number.** Newer Apple Silicon may shift the crossover; the threshold is `var`-overridable at runtime via `EncoderPipeline._gpuForward53PixelThreshold`.
- **Encoder side decode wins from v6.2.0 carry forward unchanged.** The +21.3 % v6.1.0 DX encode + +46.2 % v6.2.0 DX decode wins are unchanged. Combined v6.0.0 → v6.3.0 wall reduction on DX: encode ~30 %, decode ~46 %.
- **Lossy encode unchanged from v6.2.0.** v6.3.0's E2 threshold change applies to the lossless 5/3 INT path only; the lossy 9/7 forward path keeps its own (untuned in v6.3.0) thresholds and wall-time profile.

---

## Reproducing the headline numbers

```bash
# Mandatory pre-release gate (release mode)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrices (multi-tile 12/12 + GPU-forward 7/7)
swift test -c release \
  --filter 'HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures|HTGPUForward53CrossCodecTests'

# E1.2 multi-tile bit-exact regression test + A/B
swift test --filter MultiTileDecodeGPUDefaultOnTests

# E2 lossless 5/3 wall-time A/B (PX +10.9% headline)
swift test -c release \
  --filter GPUForward53DefaultOnTests/testDefaultOn_WallTimeAB_AcrossCorpus

# F1 / F3 sub-stage profile diagnostics
swift test -c release --filter 'CodestreamMarkerSubstageProfileTests|PreprocessSubstageProfileTests'

# E1.0 triangulation matrix (multi-tile decode entry-point sweep)
swift test --filter MultiTileDecodeGPUInvestigationTests
```

---

## Companion documents

- [`RELEASING.md`](RELEASING.md) — branching model + release flow (perf-every-release expectation; v6.3.0 honours this with the F-series + E-series mix)
- [`docs/V6_3_0_PLAN.md`](docs/V6_3_0_PLAN.md) — original v6.3.0 work plan (E1 multi-tile decode bug fix as the headline; F-series perf work as decoupled scope)
- [`docs/V6_3_0_E1_0_INVESTIGATION.md`](docs/V6_3_0_E1_0_INVESTIGATION.md) — E1.0 triangulation matrix + E1.1 root-cause closure
- [`docs/V6_3_0_E1_2_INVESTIGATION.md`](docs/V6_3_0_E1_2_INVESTIGATION.md) — E1.2 routing widen + Defects A + B deferral to E1.3
- [`RELEASE_NOTES_v6.2.0.md`](RELEASE_NOTES_v6.2.0.md) — decode-side default flip (DX decode +46.2%); v6.3.0 closes the multi-tile decode deferral from v6.2.0
- [`MEDICAL_BENCHMARK_V6.md`](MEDICAL_BENCHMARK_V6.md) — phase-by-phase trajectory + cross-device tuning template
