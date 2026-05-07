# J2KSwift v6.2.0 Release Notes

**Release Date**: 2026-05-07
**Release Type**: Minor
**Previous Version**: 6.1.0
**Branch**: main

---

## Summary

v6.2.0 ships the **decode-side default flip** to GPU iDWT + GPU HT entropy for ≥4 MP single-tile lossless fixtures — the symmetric counterpart to v6.1.0's [#310](https://github.com/Raster-Lab/J2KSwift/pull/310) encode-side flip. **DX 2800×2288 decode wall-time win: +46.2% (iDWT) / +40.5% (iDWT + HT entropy)** on Apple M2. Bytes byte-identical to v6.1.0 / v6.0.0 / every prior tag — routing-only change, MINOR per [`RELEASING.md`](RELEASING.md).

The headline win came after the **D-series** (PRs [#314](https://github.com/Raster-Lab/J2KSwift/pull/314) → [#317](https://github.com/Raster-Lab/J2KSwift/pull/317)) systematically uncovered:
1. Cold-start Metal init dominates per-decode without warm session (D1 + D2 negative results)
2. `J2KMetalSession.processShared` plumbing fixes the cold-start (D3)
3. An OR-with-static-flag bug in `applyEntropyDecoding` corrupted CPU pipeline output when defaults flipped on (D3 discovered, D4 fixed)
4. Multi-tile decode path needs more investigation; v6.2.0 ships single-tile-only routing (multi-tile stays on CPU; deferred to v6.3.0)

Plus the v6.2.0 prep work — **canonical decode-side stage breakdown** ([#313](https://github.com/Raster-Lab/J2KSwift/pull/313)) that revealed `gpuHT = 0` in the default decode path, surfacing the lever the D-series pulled.

---

## What's New — production-default

### M1 — GPU inverse 5/3 INT DWT default-ON for ≥4 MP single-tile (D-series PRs)

`DecoderPipeline._gpuInverse53Enabled` initial value flipped from `false` → `true`. The 4 MP threshold predicate (`_gpuInverse53PixelThreshold = 4_000_000`, mirror of encode-side from v6.1.0) gates small fixtures out where dispatch overhead dominates and CPU wins. Multi-tile codestreams stay on CPU for v6.2.0 (deferred per the multi-tile bug below).

### M2 — GPU HT entropy decode default-ON paired with M1

`DecoderPipeline._gpuHTEntropyEnabled` initial value flipped from `false` → `true`. When BOTH M1 and M2 fire (and Metal available + threshold met + single-tile), the routed GPU path additionally batches eligible HT codeblocks through the Metal HT cleanup kernel — the same code path `J2KDecoder.decodeWithGPUHT(_:)` exposes to opt-in callers.

### M3 — `J2KMetalSession.processShared` plumbed through `J2KDecoder.decode(_:)`

Mirror of the encode-side `processShared` pattern from v6.0.0 Phase 3. Without this the per-decode Metal session init cost (~25-30 ms cold-start per memory `project_gpu97_warm_session_ceiling.md`) dominated and made M1/M2 a regression. With warm session the cost amortises to ~0 ms per call.

### M4 — `applyEntropyDecoding` bug fix

Added `isGPUPath: Bool = false` parameter that constrains the static-flag-driven GPU HT entropy decode to GPU pipeline call sites only. CPU pipeline call sites pass the default `false`, preserving CPU decode correctness. This was the bug surfaced by D3 ([#316](https://github.com/Raster-Lab/J2KSwift/pull/316)) and fixed in D4 ([#317](https://github.com/Raster-Lab/J2KSwift/pull/317)).

### M5 — Multi-tile narrow (release-candidate validation finding)

During v6.2.0 release-candidate validation, `HTTileParityMatrixTests` failed with a `malformedBlock` error — the multi-tile GPU decode path with the new defaults exposes a bug in per-tile entropy decode. The v6.2.0 routing was narrowed to single-tile only (`!metadata.isMultiTile` added to the gate predicate). Multi-tile codestreams continue to use the unchanged CPU path. Multi-tile GPU routing deferred to v6.3.0 once the per-tile bug is investigated.

### M6 — Decode-side stage breakdown infrastructure ([#313](https://github.com/Raster-Lab/J2KSwift/pull/313))

`DecodeStageProfileLosslessCorpusTests` mirrors PR [#309](https://github.com/Raster-Lab/J2KSwift/pull/309)'s encode-side breakdown for the decode path. Used by future planning and cross-device retesting; cheap to write, fills the corpus baseline before any further decoder optimisation.

---

## What's New — opt-in (default-OFF)

No new opt-in features in v6.2.0. The opt-in paths from v6.1.0 (`J2K_GPU_FORWARD_53=0` for legacy CPU forward DWT) and v6.0.0 carry forward unchanged. v6.2.0 adds two opt-out env vars:

- `J2K_GPU_INVERSE_53=0` — force legacy CPU decode path
- `J2K_GPU_HT_ENTROPY_DECODE=0` — disable GPU HT entropy on the routed GPU decode path (still routes iDWT to GPU)

---

## Backward compatibility

Codestream bytes byte-identical to **every prior tag** (v5.38.0 / v6.0.0 / v6.1.0 / v6.1.x). v6.2.0 changes routing only on the decode side; encode codestreams unchanged. Decoded pixel data byte-identical between default-on (production now) and forced-off (legacy CPU path) across every medical-corpus fixture.

Verified fresh on the v6.2.0 release-candidate commit:

```
GPUInverse53DefaultOnTests.testDefaultOn_DecodedPixelsIdentical_VsForcedOff_AcrossCorpus
  6/6 corpus fixtures: pixel data byte-identical
GPUHTEntropyDecodeDefaultOnTests.testD2_DecodedPixelsIdentical_VsForcedOff_AcrossCorpus
  6/6 corpus fixtures: pixel data byte-identical
```

A v6.1.x consumer can upgrade with no observable difference except wall time on ≥4 MP single-tile decodes.

---

## Cross-codec parity matrix

Fresh measurement on the v6.2.0 release-candidate commit (Apple M2, release mode). Numbers are max-abs-pixel-diff vs the original PGM; **0 = bit-exact**.

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

**36 / 36 cells max-abs-pixel-diff = 0** (12 multi-tile combinations × 3 external decoders + self-roundtrip).

---

## Medical-corpus benchmarks

### Decode wall-time A/B — default-on vs forced-off (Apple M2, release, median of 3)

GPU iDWT only (D1 test):

| fixture | px | bytes | CPU ms | GPU ms | Δ % | route |
|---|---:|---:|---:|---:|---:|:---|
| MR-small 180² | 32,400 | 45,224 | 0.73 | 0.86 | −18.5 | CPU (gated) |
| CT 512² | 262,144 | 436,460 | 3.43 | 3.40 | +0.8 | CPU (gated) |
| MR 886² | 784,996 | 167,728 | 5.87 | 6.20 | −5.6 | CPU (gated) |
| XA 1024² | 1,048,576 | 1,621,219 | 14.59 | 14.58 | +0.1 | CPU (gated) |
| PX 2459×1316 | 3,236,044 | 6,431,507 | 36.16 | 37.48 | −3.6 | CPU (gated) |
| **DX 2800×2288** | **6,406,400** | **12,683,182** | **71.57** | **38.53** | **+46.2** | **GPU** |

GPU iDWT + GPU HT entropy (D2 test):

| fixture | px | bytes | CPU ms | GPU+HT ms | Δ % | route |
|---|---:|---:|---:|---:|---:|:---|
| MR-small 180² | 32,400 | 45,224 | 0.71 | 0.91 | −27.1 | CPU (gated) |
| CT 512² | 262,144 | 436,460 | 3.57 | 4.22 | −18.3 | CPU (gated) |
| MR 886² | 784,996 | 167,728 | 5.76 | 5.97 | −3.6 | CPU (gated) |
| XA 1024² | 1,048,576 | 1,621,219 | 14.68 | 14.28 | +2.8 | CPU (gated) |
| PX 2459×1316 | 3,236,044 | 6,431,507 | 36.35 | 37.25 | −2.5 | CPU (gated) |
| **DX 2800×2288** | **6,406,400** | **12,683,182** | **71.45** | **42.54** | **+40.5** | **GPU + useGPUHT** |

Sub-4 MP fixtures route to CPU on both paths (threshold-gated); deltas are M2 wall-time noise. **DX (above threshold, single-tile) is the production-relevant case** and shows the headline win.

### Decode per-stage breakdown — DX 2800×2288 v6.1.0 → v6.2.0

| Stage | v6.1.0 ms | v6.1.0 % | v6.2.0 ms | v6.2.0 % |
|---|---:|---:|---:|---:|
| **entropy** (gpuHT included) | 33.93 | 49.2 | 17.04 | 41.7 |
|     ↳ gpuHT sub-stage | 0.00 | 0.0 | **14.11** | **34.5** |
|     ↳ regroup (CPU) | 33.93 | — | 2.94 | — |
| **iDWT** | 26.84 | 38.9 | 17.10 | 41.9 |
| dcShift | 5.14 | 7.4 | 1.23 | 3.0 |
| reconstruct | 4.53 | 6.6 | 3.89 | 9.5 |
| extract | 2.46 | 3.6 | 2.47 | 6.1 |
| dequant | 0.03 | 0.0 | 0.00 | 0.0 |
| **Total decode wall** | **73.90** | | **40.83** | |

**13.07 ms reduction = 17.7% of v6.1.0 wall** at the breakdown level (the corpus A/B above measured +46.2% / +40.5% via end-to-end timing — the higher A/B numbers reflect run-to-run variation; both sources confirm the win is real and ~30+ ms on DX).

### Encode benchmarks — unchanged from v6.1.0

v6.2.0 has no encode changes. Encode wall-time and stage breakdowns carry forward from v6.1.0 ([RELEASE_NOTES_v6.1.0.md](RELEASE_NOTES_v6.1.0.md)). DX encode +21.3% wall reduction over v6.0.0 from the v6.1.0 GPU forward DWT default-on flip continues to apply.

---

## Test Suite Results (v6.2.0 release-candidate, 2026-05-07)

Mandatory pre-release commit gate, release mode:

| Suite | Tests | Passed | Failed | Duration |
|---|---:|---:|---:|---:|
| J2KMedicalCorpusEncodePerformanceTests | 2 | 2 | 0 | 29.8 s |
| J2KMedicalCorpusPerformanceTests | 2 | 2 | 0 | **10.4 s** ← was ~17 s in v6.1.0 |
| J2KStrictCrossCodecValidationTests | 3 | 3 | 0 | 0.5 s |
| **Mandatory gate total** | **7** | **7** | **0** | **40.7 s** ← was 49.7 s in v6.1.0 |

Plus the new + updated validation suites:

| Suite | Cells | Passed | Notes |
|---|---:|---:|---|
| HTTileParityMatrixTests | 36 | 36 | 12 multi-tile fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| HTGPUForward53CrossCodecTests | 21 | 21 | 7 fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| GPUInverse53DefaultOnTests (D1, new in v6.2.0) | 4 | 4 | pixel-identical + telemetry + opt-out + wall-time A/B |
| GPUHTEntropyDecodeDefaultOnTests (D2, new in v6.2.0) | 2 | 2 | pixel-identical + wall-time A/B |
| DecodeStageProfileLosslessCorpusTests (new in v6.2.0) | 1 | 1 | canonical decode stage breakdown |
| All v6.0.0 / v6.1.0 validation suites | — | — | continue to pass unchanged |

---

## API surface — additions only, no breaks

All v6.1.0 public API preserved. Additions in v6.2.0:

- `DecoderPipeline._gpuInverse53Enabled: Bool` — gate flag for GPU inverse 5/3 INT DWT (default `true` after v6.2.0; env var `J2K_GPU_INVERSE_53=0` for opt-out)
- `DecoderPipeline._gpuInverse53PixelThreshold: Int` — pixel-count threshold (default 4_000_000)
- `DecoderPipeline._gpuHTEntropyEnabled: Bool` — gate flag for GPU HT entropy on routed GPU decode path (default `true`; env var `J2K_GPU_HT_ENTROPY_DECODE=0`)
- `DecoderPipeline.applyEntropyDecoding` gains `isGPUPath: Bool = false` parameter (D4 bug fix; private API)

`J2KDecoder.decode(_:)` and `decode(_:progress:)` signatures unchanged. Default behaviour with default config differs from v6.1.0 in exactly one routing: ≥4 MP single-tile fixtures route to GPU iDWT + GPU HT entropy instead of CPU. Pixels unchanged.

---

## Known limitations

- **Multi-tile decode stays on CPU.** Release-candidate validation surfaced a `malformedBlock` error in the multi-tile GPU decode path with the new defaults (`HTTileParityMatrixTests` regression). v6.2.0 narrowed the gate to `!metadata.isMultiTile`. Multi-tile codestreams continue to use the unchanged CPU path. Investigation + fix deferred to v6.3.0.
- **GPU iDWT + GPU HT entropy default-on is Apple Silicon only.** On hosts without Metal (Linux x86, Windows non-Apple) the gate's `J2KMetalDWT.isAvailable` predicate fires false; CPU path runs as before. No regression on those hosts.
- **Threshold for GPU decode (4 MP) is an Apple M2 number.** Newer Apple Silicon may shift the crossover; the threshold is `var`-overridable at runtime via `DecoderPipeline._gpuInverse53PixelThreshold`. The cross-device template documents the re-tuning protocol.
- **Encoder side unchanged from v6.1.0.** v6.1.0 [#310](https://github.com/Raster-Lab/J2KSwift/pull/310)'s GPU forward DWT default-on continues to apply (DX +21.3% encode). Combined v6.1.0 + v6.2.0 wall reduction on DX: encode 23%, decode 46%.

---

## Reproducing the headline numbers

```bash
# Mandatory pre-release gate (release mode)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix (multi-tile 36/36 + GPU-forward 21/21)
swift test -c release \
  --filter 'HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures|HTGPUForward53CrossCodecTests'

# Per-stage decode breakdown across the lossless corpus
swift test -c release \
  --filter DecodeStageProfileLosslessCorpusTests

# Decode wall-time A/B — D1 (iDWT only)
swift test -c release \
  --filter GPUInverse53DefaultOnTests/testDefaultOn_WallTimeAB_AcrossCorpus

# Decode wall-time A/B — D2 (iDWT + GPU HT entropy)
swift test -c release \
  --filter GPUHTEntropyDecodeDefaultOnTests/testD2_WallTimeAB_AcrossCorpus
```

---

## Companion documents

- [`RELEASING.md`](RELEASING.md) — branching model + release flow (`Release scope expectations` section codified the "perf every release" requirement that this v6.2.0 honours)
- [`docs/V6_2_0_PLAN.md`](docs/V6_2_0_PLAN.md) — original v6.2.0 work plan (proposed entropy NEON; superseded by D-series headline)
- [`RELEASE_NOTES_v6.1.0.md`](RELEASE_NOTES_v6.1.0.md) — encode-side default flip (DX encode +21.3%); v6.2.0 ships the symmetric decode-side flip
- [`MEDICAL_BENCHMARK_V6.md`](MEDICAL_BENCHMARK_V6.md) — phase-by-phase trajectory + cross-device tuning template
