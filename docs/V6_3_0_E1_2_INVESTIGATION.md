# v6.3.0 E1.2 — multi-tile routing widen + deferred GPU per-tile work

**Status**: E1.2 routing widen shipped (correctness-first). GPU per-tile entropy + IDWT correctness deferred to E1.3.

**Branch**: `feature/v6.3.0-multitile-decode-default-on`

**Anchors**:
- [`docs/V6_3_0_PLAN.md`](V6_3_0_PLAN.md) §E1 — multi-tile decode bug fix (HEADLINE)
- [`docs/V6_3_0_E1_0_INVESTIGATION.md`](V6_3_0_E1_0_INVESTIGATION.md) — initial triangulation
- E1.1 (#321) — fixed canvas-anchored codeblock partition

---

## What E1.2 ships

1. Drops the v6.2.0 narrow `&& !metadata.isMultiTile` routing guard in `DecoderPipeline.decode`. Production-default `decode()` now routes ≥4 MP multi-tile codestreams through `decodeMultiTileGPU` instead of `decodeMultiTile` (CPU). Single-tile is unchanged.
2. Inside `decodeTilePayloadGPU`, forces multi-tile per-tile **entropy** to CPU (`isGPUPath: false`) and **IDWT** to CPU (`isMultiTilePerTile: true` flag → `applyInverseWaveletTransformGPU` falls back to `applyInverseWaveletTransform`). The dispatch / chunked task group / shared `J2KMetalSession.processShared` infrastructure runs but the per-tile entropy + IDWT compute is on CPU.
3. Adds [`Tests/J2KMetalTests/MultiTileDecodeGPUDefaultOnTests.swift`](../Tests/J2KMetalTests/MultiTileDecodeGPUDefaultOnTests.swift) — bit-exact regression test (`decoded pixels CPU multi-tile == GPU multi-tile`) + wall-time A/B telemetry on the medical corpus.

The headline win: production-default routing is now **uniform** for multi-tile (same dispatch shape as single-tile), and the bit-exact regression test guards against future regressions when GPU per-tile stages are re-enabled.

## What E1.2 does NOT ship

GPU per-tile entropy + IDWT compute. Both have correctness bugs in the multi-tile per-tile context that surfaced empirically when the routing widen was tried with E1.1's codeblock-partition fix in place.

### Defect A — GPU HT entropy multi-tile produces wrong coefficients

Empirical: with `isGPUPath: true` in `decodeTilePayloadGPU`, DX 2800×2288 multi-tile self-roundtrip diff = exactly **32768** (= 2^15, the DC offset for 16-bit unsigned). With `isGPUPath: false` keeping every other GPU stage in place: diff = 0.

Cross-decode validation (OpenJPH / Grok / Kakadu) all decode the codestream bit-exact to the source, so the codestream is correct — the bug is in the GPU HT decoder's per-tile output.

Hypothesis: `J2KGPUHTDispatch.decodeBatchGPUResident` per-tile invocations produce coefficients whose magnitudes are systematically wrong by a power-of-2 factor that resembles the DC offset. Could be:

- the per-tile `outputSampleCount` / `sampleOffsets` arithmetic mis-counts at tile-local subband sizes
- the `bandKb` per-block encoding is image-global where it should be tile-local
- the kernel's `missingMSBs` interpretation differs between single-tile (full-canvas) and per-tile invocations

Single-tile DX 6.4 MP works bit-exact via the same `decodeBatchGPUResident` API since v5.5.0 — so the bug is per-tile-shape-specific, not a fundamental algorithmic error.

### Defect B — GPU IDWT lacks parity-aware boundary handling

Even with CPU entropy in place (Defect A bypassed), DX still showed 32768 diff before adding the `isMultiTilePerTile` IDWT fallback. The GPU 5/3 inverse kernel applies boundary lifting assuming canvas origin (0, 0); per-tile invocations with non-zero tile-component canvas origin require parity-aware lifting per ISO 15444-1 Annex F.4.1.1 that the GPU kernel doesn't implement. The CPU `applyInverseWaveletTransform` has been parity-aware since v6-alpha3 step 6B slice 3.

Tile origins like (1400, 1144) for DX 2x2 reach **odd band-origins at deep decomposition levels**: 1400/8 = 175 (odd at level 3). For 5 levels of decomp, full parity-correctness requires tile origins to be multiples of 2^levels = 32, which most realistic medical tile sizes don't honor.

## E1.3 fix scope (deferred)

1. **GPU HT entropy per-tile correctness.** Diff per-block GPU vs CPU coefficients on a failing DX tile; identify which block(s) drift and by what magnitude. Compare the per-tile descriptor sequence (`magsgnOffset`, `melVlcOffset`, `outputOffset`, `width`, `height`, `missingMSBs`) against the equivalent single-tile descriptors at the same canvas position. Fix the per-tile invariant.
2. **GPU IDWT parity-aware boundary lifting.** Port `J2KDWT2DOptimizer.inverseTransformMultiLevel53`'s parity-aware lifting into the Metal `inverse2DInt32` kernels. The CPU implementation routes via `tileOriginX/Y` to switch boundary symmetric extension; the GPU kernels need the same parameter and branch.

Empirical gates for E1.3:
- `MultiTileDecodeGPUDefaultOnTests` (this PR) bit-exact contract holds when `isGPUPath: true` is restored
- `HTTileParityMatrixTests` 12/12 self-RT diff = 0 with all GPU stages enabled
- Multi-tile A/B perf measurement shows the GPU win once per-tile compute is on GPU

## E1.2 perf A/B (this PR's measurement)

Multi-tile decode A/B is in `MultiTileDecodeGPUDefaultOnTests.testMultiTileDefaultOn_WallTimeAB_AcrossCorpus`. With this PR, the per-tile entropy + IDWT compute runs on CPU, so the wall-time delta vs the legacy CPU multi-tile path is small (within ±5 % noise). The dispatch infrastructure overhead is amortised by the shared `J2KMetalSession.processShared` warm session — same primitive single-tile uses.

The "GPU multi-tile +X %" win the v6.3.0 plan headlined is deferred to E1.3 once defects A + B above are resolved.

---

## What this means for v6.3.0 release scope

- **E1 series** (multi-tile correctness): E1.0 ✅, E1.1 ✅, **E1.2 ✅ (this PR — routing widen + correctness)**, E1.3 ⏭ (GPU per-tile compute).
- The v6.3.0 release notes' multi-tile A/B measurement is "wash" until E1.3 lands. That's an honest empirical finding per `RELEASING.md` "Release scope expectations" — release notes ship the data even when the wall-time number is zero.
- F-series (general J2K perf) remains independent of E1.3 — F1 (codestream marker writes profiling) and F2 (decoder warm-session for the no-session APIs) can land without waiting on E1.3.
