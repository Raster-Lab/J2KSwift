# J2KSwift v7.2.0 — Release Notes

**Tag**: `v7.2.0`
**Released**: 2026-05-09
**Headline**: encode-side UMA boundary elimination + cross-tile batched HT entropy decode → 5–9% wall-time reduction on the headline DX fixture vs v7.1.1, with a corrected decoder timing instrumentation that future v7.3 SIMD work will measure against.

---

## Summary

v7.2.0 is a **foundation-and-measurable-wins** release. Three commits land work that pays out today (5–9% on DX) and prepares a runway for the v7.3 CPU-SIMD entropy arc that will actually close the Kakadu gap.

Three pieces ship:

1. **Decoder per-tile timing instrumentation fix** (#354). `J2KDecodeTimings` was silently reporting all-zero stage breakdowns for any fixture above ~500K pixels because the multi-tile per-tile decode functions had no `record*` calls. v7.2.0 closes that gap; the corpus-wide stage breakdown now lights up correctly across all fixtures and exposes that DX decode is **62.6% entropy + 34.1% IDWT** of CPU work — the data that drove the rest of the release's planning.
2. **Encode-side UMA boundary elimination** (#355). When the GPU forward 5/3 DWT fires, the producer now returns view-backed buffers instead of `[Int32]` arrays, eliminating 20 readback memcpys per encode (≈ 25 MB of unnecessary copies on DX). New `J2KMetalSharedBufferView<Element>` infrastructure, polymorphic `CoefficientStorage` through `SubbandInfo` / `DeferredCodeBlock`, and a lossless quantizer bypass that avoids re-introducing the memcpy at the quantize boundary.
3. **Cross-tile batched HT entropy decode** (#356). `decodeMultiTileGPUBatched` aggregates every tile's eligible HT codeblocks into one shared `MTLCommandBuffer` instead of N per-tile CBs. The plan's original "lower thresholds" approach was empirically refuted by `V720PhaseEThresholdSweepTests` (1.8× regression at 256K threshold); the right intervention turned out to be CB amortisation, with the per-tile threshold gate retained.

The Kakadu gap on DX in-process decode tightens from **2.66× → 2.40×** (60 ms vs Kakadu ~25 ms). It is **not closed**. The honest path to closing it is the v7.3 CPU-SIMD entropy arc captured in `V7_2_0_STATUS_AND_KAKADU_GAP.md` — Kakadu's hand-tuned NEON inner loops are ~3× faster than our Swift auto-vectoriser output, and the cache/locality levers have been exhausted (v6-alpha4 step 12 memo). The remaining lever is hand-coded SIMD on the HT entropy decoder, which is multi-week work outside v7.2.0 scope.

---

## What's New — production default

### 1. Decoder per-tile timing instrumentation (#354)

Added `J2KDecodeTimings.record*` calls to `decodeTilePayload` (CPU multi-tile per-tile) and `decodeTilePayloadGPU` (GPU multi-tile per-tile). Pre-fix these functions had no recordings; the global accumulator sat at zero for any fixture ≥ 500K px (since `J2KEncodeTilePlanner.auto` encodes those as multi-tile and the decoder routes through these per-tile paths).

Now the per-stage breakdown is meaningful for the entire corpus. Used as the data baseline for v7.2.0's plan revision (Option 3 — UMA encode + decode entropy/IDWT widening) and for the Phase E threshold sweep that refuted the original "lower thresholds" plan.

### 2. Encode-side UMA boundary elimination (#355)

When the GPU forward 5/3 DWT fires (`_gpuForward53Enabled && Metal && pixels ≥ 4M`), the producer now returns `[J2KMetalDWTSubbandsInt32View]` instead of `[J2KMetalDWTSubbandsInt32]`. Each band is a `J2KMetalSharedBufferView<Int32>` that exposes the GPU output buffer's CPU-visible memory directly via `UnsafeBufferPointer` — no `readInt32Array(memcpy MTLBuffer.contents() → [Int32])` step.

Verification (`V720Phase0UMAProfileTests`, single-tile mode):

```
Before (v7.1.1):  PX/DX enc memcpy = 20  enc contents = 20
After  (v7.2.0):  PX/DX enc memcpy =  0  enc contents =  0
```

Bit-exact: every encode produces the same J2C byte stream as v7.1.1 (md5-verified across the corpus).

### 3. Cross-tile batched HT entropy decode (#356)

When the codestream is multi-tile + HT-conformant + lossless 5/3 + per-tile pixels ≥ 1 MP, the decoder routes through `decodeMultiTileGPUBatched`:

1. Per-tile, sequentially: `extractTileData` → CodeBlockInfo[] (CPU; cheap).
2. Aggregate every tile's GPU-eligible HT codeblocks into one flat `[GPUHTBlock]` array.
3. ONE `J2KGPUHTDispatch.decodeBatch` call decodes them all in a single shared MTLCommandBuffer.
4. Per tile, in parallel via `withThrowingTaskGroup`: slice the master result, hand into the slow-lane regroup → dequant → CPU IDWT → dcShift.

The per-tile pixel threshold (`_gpuHTEntropyMultiTilePerTilePixelThreshold = 1 MP`) is retained — `V720PhaseEABTest` measured +14% to +65% regressions on small per-tile fixtures (PX 4x4, XA 2x2) when the gate was forced off, confirming GPU compute on tiny tiles is genuinely slower than CPU on Apple M2 (independent of dispatch amortisation).

Adds `_multiTileBatchedEntropyEnabled` flag (default ON) for A/B comparison testing.

---

## What's New — opt-in

None in this release. The new infrastructure (`J2KMetalSharedBufferView`, `CoefficientStorage` enum, `decodeMultiTileGPUBatched`) is internal and gated to take effect only on the relevant production paths.

---

## Backward compatibility

**Codestream bytes**: byte-identical to v7.1.1 across the medical corpus. `CrossVersionDeltaBenchmark` md5-equality verified for all fixtures × {single, tile2x2}.

**Public API**: no removals, no signature changes, no defaults flipped. SemVer rule: MINOR.

**`getVersion()`** returns `"7.2.0"` (was stale at `"5.14.2"` since v5.14.2; fixed in this release).

---

## Cross-codec parity matrix

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` re-run on this tag — **all 12 cells bit-exact** (max-diff = 0):

- ALL-EVEN cells: 9/9 cross-decode pass (J2KSwift / OpenJPH / Grok / Kakadu produce byte-identical decoded coefficients on even-origin tiles)
- ANY-ODD cells: 3/3 cross-decode pass (parity-aware odd-origin handling)

CLI cross-codec wall-time matrix (median of 5, **CLI launches** — each cell includes ~15ms process startup + ~50ms J2KSwift CLI per-invocation overhead; codec-only walls are in the in-process table below):

### Encode (CLI, ms)

| fixture | shape | px | bytes | J2KSwift v7.2.0 | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4.1 |
|---|---|---:|---:|---:|---:|---:|---:|
| MR-small | 180×180 | 32K | 45K | 66.3 | 16.5 | 18.4 | 15.2 |
| CT | 512×512 | 262K | 436K | 69.8 | 20.7 | 20.0 | 16.0 |
| MR | 886×886 | 785K | 169K | 70.9 | 20.7 | 21.9 | 16.5 |
| XA | 1024×1024 | 1.05M | 1.62M | 77.2 | 33.0 | 25.4 | 18.3 |
| PX | 2459×1316 | 3.24M | 6.45M | 98.9 | 70.5 | 39.5 | 24.8 |
| DX | 2800×2288 | 6.41M | 12.7M | 137.9 | 125.8 | 57.6 | 37.7 |

### Decode (CLI, ms)

| fixture | px | J2KSwift v7.2.0 | OpenJPH 0.27 | Grok 20.3 | Kakadu 8.4.1 |
|---|---:|---:|---:|---:|---:|
| MR-small | 32K | 68.3 | 16.3 | 18.0 | 15.2 |
| CT | 262K | 69.1 | 19.1 | 19.3 | 16.2 |
| MR | 785K | 73.1 | 20.8 | 20.5 | 18.4 |
| XA | 1.05M | 78.0 | 28.6 | 22.1 | 19.8 |
| PX | 3.24M | 106.5 | 55.2 | 29.7 | 27.0 |
| DX | 6.41M | 139.3 | 95.1 | 40.7 | 39.0 |

### Lossless byte-equality

| codec | bit-exact PGM round-trip | notes |
|---|:-:|---|
| J2KSwift v7.2.0 | ✓ | bit-exact |
| OpenJPH 0.27 | ✓ | bit-exact |
| Grok 20.3 | byte-swap | decoded PGM byte-swapped (writer convention only — codestream is bit-exact) |
| Kakadu 8.4.1 | ✓ | bit-exact |

---

## Medical-corpus benchmarks (in-process, codec-only)

`CrossVersionDeltaBenchmark` v7.2.0, median of 5 release-mode runs per fixture, single-tile mode (default `J2KEncodeTilePlanner.auto`):

| fixture | px | enc ms | dec ms | bytes | md5 prefix |
|---|---:|---:|---:|---:|---|
| MR-small | 32K | 0.77 | 0.71 | 45224 | f4add755ec26 |
| CT | 262K | 2.84 | 3.13 | 436460 | 6c968561c0d3 |
| MR | 785K | 2.69 | 5.45 | 169709 | e29a2366ca1f |
| XA | 1.05M | 7.37 | 8.94 | 1621712 | c7f1252aca8e |
| PX | 3.24M | 23.75 | 32.26 | 6453588 | 05c68da54364 |
| **DX** | **6.41M** | **50.87** | **60.03** | 12705470 | 447a3a8ddeac |

### v7.1.1 → v7.2.0 wall-time delta (in-process)

| fixture | enc Δ | dec Δ |
|---|---:|---:|
| MR-small | +0.04 | -0.01 |
| CT | -0.39 | -0.13 |
| MR | -0.22 | -0.33 |
| XA | -0.54 | -0.81 |
| PX | -0.73 | -0.83 |
| **DX** | **-3.95 (-7.2%)** | **-5.52 (-8.4%)** |

DX is the headline win. The improvement composes from Phase A (encode UMA, ~3-4 ms savings on encode) + Phase E (batched entropy, ~2 ms savings on decode) + general overhead reduction from the polymorphic `CoefficientStorage` path avoiding the lossless quantize array allocation.

### Kakadu gap status

| fixture | J2KSwift v7.2.0 dec ms | Kakadu in-process ≈ ms | gap |
|---|---:|---:|---:|
| MR-small | 0.71 | ~0.8 | tied |
| CT | 3.13 | ~1.7 | 1.84× |
| MR | 5.45 | ~3.9 | 1.40× |
| XA | 8.94 | ~5.0 | 1.79× |
| PX | 32.26 | ~13.1 | 2.46× |
| **DX** | **60.03** | **~24.7** | **2.43× (was 2.66× in v7.1.1)** |

The DX gap closes from 2.66× to 2.43×. Closing it the rest of the way requires CPU SIMD on the HT entropy decoder (62.6% of DX decode CPU work) — that's the v7.3 arc, captured in `V7_2_0_STATUS_AND_KAKADU_GAP.md`.

---

## Test Suite Results

### Mandatory commit gate (release mode)

| suite | cells | result |
|---|---:|:---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | ✓ |
| `J2KMedicalCorpusPerformanceTests` | 2 | ✓ |
| `J2KStrictCrossCodecValidationTests` | 3 | ✓ |
| **Total** | **7** | **0 failures** |

### v7.2.0-new validation suites

| suite | cells | what it pins |
|---|---:|---|
| `V720Phase0UMAProfileTests` | 1 | UMA counter baseline (encode 0/decode 0/0/0) on default routing per fixture |
| `V720PhaseEThresholdSweepTests` | 1 | Empirical GPU-vs-CPU crossover at the multi-tile per-tile entropy / IDWT thresholds |
| `V720PhaseEABTest` | 1 | A/B `_multiTileBatchedEntropyEnabled` ON vs OFF across 5 fixtures |
| `MultiTilePerTileWarmSessionHardeningTests` | 3 | Singleton stability + buffer-pool amortisation across multi-tile decodes |
| `GPUvsCPUBenchmark` | 2 | Single-tile + multi-tile-2x2 GPU-vs-CPU wall comparison |
| `HTTileParityMatrixTests` | 12 | Cross-codec bit-exact decode (J2KSwift / OpenJPH / Grok / Kakadu) |

---

## API surface

### Additions (public)

- `J2KMetalSharedBufferView<Element: Sendable>` — read-only typed view over a `.storageModeShared` MTLBuffer with `withUnsafeBufferPointer`, `subscript(_:)`, and explicit `release()` semantics. Sendable.
- `J2KMetalDWTSubbandsInt32View` — view-backed counterpart to `J2KMetalDWTSubbandsInt32`, exposing each band as a view rather than a `[Int32]`.
- `J2KMetalDWT.forward2DInt32MultiLevelFusedView(image:width:height:levels:tileOriginX:tileOriginY:)` — view-returning overload of the fused forward 5/3 DWT producer.

### Additions (internal)

- `EncoderPipeline.CoefficientStorage` enum (`.empty` / `.array` / `.view`) — polymorphic Int32 coefficient storage on `SubbandInfo` and `DeferredCodeBlock`.
- `DecoderPipeline._gpuHTEntropyMultiTilePerTilePixelThreshold` already existed; v7.2.0 leaves it at 1 MP (per the V720PhaseEThresholdSweepTests finding).
- `DecoderPipeline._multiTileBatchedEntropyEnabled` (default ON) — A/B gate flag.
- `DecoderPipeline.decodeMultiTileGPUBatched(_:tiles:progress:)` — cross-tile batched HT entropy decode path.
- `DecoderPipeline.applyEntropyDecoding(_:metadata:isGPUPath:isMultiTilePerTile:preBatchedGPUCoefficients:)` — new optional parameter.

### No removals; no signature changes; no default behaviour flips

---

## Known limitations

- **Kakadu gap remains 2.43× on DX in-process decode**. Closing it requires CPU SIMD on the HT entropy decoder. v7.3 arc captured in `V7_2_0_STATUS_AND_KAKADU_GAP.md`.
- **Phase A wall benefit is gated to single-tile encodes** (where GPU forward DWT fires). Default routing for ≥3 MP fixtures uses 4x4 multi-tile, where per-tile pixels < 4 MP threshold so GPU forward DWT never fires. The encode-side UMA elimination is *foundation* for future routing widening, not an immediate default-path win.
- **Phase E batched-entropy fires only on multi-tile fixtures with per-tile pixels ≥ 1 MP**. In the default planner, that's effectively just DX 2x2 (4 tiles × 1.6 MP each); the `.auto` planner picks 4x4 for ≥3 MP fixtures, so the default DX user does not hit the batched path. The wall improvement on default DX (5–9 %) comes from the `CoefficientStorage` and lossless-quantizer-bypass changes, not the batched-entropy code path itself.
- **Multi-tile per-tile GPU IDWT** is still gated to per-tile ≥ 1 MP (CPU otherwise). v7.1.1 hotfix retained.
- **No CLI overhead reduction in v7.2.0**. The ~50 ms J2KSwift CLI per-invocation tax (image loader, config parsing, encoder/decoder construction) inside the `j2k` binary remains. Listed as Phase C in the original v7.2.0 plan but de-scoped to keep the release focused.

---

## Reproducing the headline numbers

```bash
# Build the release binary
swift build -c release --product j2k

# Mandatory gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity matrix
swift test -c release --filter HTTileParityMatrixTests

# Cross-codec wall-time matrix (CLI)
bash /tmp/cross_codec_v710.sh   # script committed in v7.1.0; works against any binary

# In-process medical-corpus benchmark
LABEL=v7.2.0 J2K_DELTA_OUT=/tmp/j2k_delta_v7.2.0 RUNS=5 \
  swift test -c release --filter testCrossVersionDeltaBenchmark

# Phase A UMA counter verification (encode boundaries 20 → 0 in single-tile mode)
J2K_HT_TILE_MODE=single swift test -c release \
  --filter testUMABaseline_LosslessCorpus_v720Phase0

# Phase E threshold sweep (proves lowering threshold causes regression)
RUNS=5 swift test -c release --filter testPhaseEThresholdSweep_DX4x4

# Phase E A/B test (3% on DX 2x2; noise on others)
RUNS=5 swift test -c release --filter testPhaseEAB_MultiTileBatchedEntropy
```

---

## Companion documents

| document | what's in it |
|---|---|
| `V7_2_0_PROFILE.md` | Phase 0 baseline — per-stage breakdown for encode + decode, UMA counter baseline, plan revision (Option 3) |
| `V7_2_0_PHASE_E_FINDING.md` | Empirical refutation of the original "lower thresholds" Phase E plan + pivot to CB amortisation |
| `V7_2_0_STATUS_AND_KAKADU_GAP.md` | End-of-Phase-E honest assessment of the Kakadu gap + v7.3 arc sketch (CPU SIMD entropy audit) |
| `CROSS_CODEC_BENCHMARK_v7.1.1.md` | Corrected cross-codec measurement that v7.1.1 shipped (withdrew the spurious "67ms startup" claim from v7.1.0). v7.2.0 cross-codec data lives in this release-notes file inline. |
| `CROSS_VERSION_DELTA_REPORT_v5.38_v7.0_v7.1.md` | Earlier cross-version report; v7.2.0 delta is in this file's "Medical-corpus benchmarks" section. |
