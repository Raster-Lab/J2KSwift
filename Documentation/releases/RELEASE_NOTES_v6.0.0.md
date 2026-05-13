# J2KSwift v6.0.0 Release Notes

**Release Date**: 2026-05-06
**Release Type**: Major
**Previous Version**: 5.38.0
**Branch**: main

---

## Summary

v6.0.0 lands two new fast paths on top of the v5.38.0 lossless-medical archival baseline — a **production-default `.auto` multi-tile encode** and an **opt-in GPU-forward 5/3 INT DWT** — without changing any defaults that affect existing single-tile users. Codestream bytes on the v5.38.0 production single-tile path remain **byte-identical**: drop-in upgrade with no observable encode-output change for anyone who doesn't opt in.

For users who do opt in:
- **`.auto` multi-tile** (production default, available on every fixture ≥ 500 K pixels): **1.32× DX, 1.55× PX, 1.30× XA, 1.94× MR** encode speedup vs v5.38.0 single-tile.
- **`J2K_GPU_FORWARD_53=1`** (env-gated, single-tile ≥ 4 MP): an additional **+19 % at 4 MP, +24 % at 16 MP** wall-time win on top of the CPU-best path. Setup amortised to 0 ms after the first warm fire via a shared `J2KMetalSession`.

The headline correctness gate is **57 new cross-codec parity cells** added with **0 regressions**: 36 / 36 multi-tile fixture × {OpenJPH, Grok, Kakadu} cells bit-exact, 21 / 21 GPU-forward fixture × {OpenJPH, Grok, Kakadu} cells bit-exact, and the full v5.38.0 lossless gate continues to pass (28 / 28 cells, 11 fixtures with MAE = 0).

The 39 commits since v5.38.0 cluster into seven phases — v5.39 M1–M3 (parked SIMD experiments), v6-alpha1 (parked multi-tile prototype), v6-alpha2 (correctness-clean planner), v6-alpha3 (parity-aware DWT + native multi-tile + parallel encode), v6-alpha4 (`.auto` thresholds + Lever A/B), and v6-alpha5 (GPU forward 5/3 INT, phases 0–9). Memory-resident scope ledger: lossless-only since 2026-05-05 — every commit in this window honours that.

---

## What's New — production-default

### M1 — Native multi-tile encode pipeline (`.auto` mode)

A genuine native multi-tile encode path: one main header, N tile-parts, in-place encoder pipeline that doesn't require materialising N independent codestreams and concatenating. Per-tile components share a J2KEncodingConfiguration; the codestream assembler emits exactly one SOC + SIZ + CAP/CPF + COD + QCD + COM, then `[SOT|SOD|tile-data]` once per tile, then EOC.

The `.auto` resolver picks the tile grid from image pixel count:
- < 3 MP → `2x2`
- ≥ 3 MP → `4x4`

The two thresholds were tuned against the medical corpus (v6-alpha4 step 10): below 3 MP, 4-tile dispatch overhead exceeds the per-tile parallelism win; above 3 MP, the 16-tile `4x4` grid keeps every available core saturated.

| Fixture | shape | px | v5.38.0 single | `.auto` multi | speedup | mode picked |
|---|---|---:|---:|---:|---:|:---:|
| MR | 886×886 | 0.78 M | 5.26 ms | **2.61 ms** | **1.94×** | 2x2 |
| XA | 1024×1024 | 1.05 M | 10.85 ms | **8.16 ms** | **1.30×** | 2x2 |
| PX | 2459×1316 | 3.24 M | 37.20 ms | **23.72 ms** | **1.55×** | 4x4 |
| DX | 2800×2288 | 6.41 M | 72.01 ms | **54.40 ms** | **1.32×** | 4x4 |

(Numbers from `BENCHMARK_REPORT_v6_alpha5_phase9.md` §3 / §5; release median of 5 on Apple M2.)

### M2 — Parity-aware DWT primitives (correctness fix for odd-origin tiles)

Per ISO/IEC 15444-1 Eq. B-15, sub-band trajectories on tiles whose canvas origin is odd require a parity-aware origin formula: `origin' = (origin + 1) >> 1` rather than the naïve `origin / 2`. v5.38.0's single-tile encode was self-consistent (origin always 0) so this never surfaced. The native multi-tile pipeline exposed the issue: tiles 1+ in any row or column have non-zero canvas-relative origin, and a fraction of those origins are odd. Code-block partitioning (F.4.4) and DWT band sizes both depend on the same parity bit.

Slices that landed:
- **Step 1**: parity-aware 5/3 forward 1D DWT primitive (math, unit-tested). Each tile-component carries its `tileOriginX/tileOriginY` through to the DWT; band-size formulas now branch on `(origin & 1)`.
- **Step 2**: parity-aware 2D 5/3 + multi-level recursion. Ceil-halving per level so band dimensions match the spec at every resolution.
- **Step 6A**: canvas-anchored code-block partition. Block grid is computed against the canvas-relative origin, not the tile-component-relative origin (F.4.4 mandates this, and OpenJPH / Grok / Kakadu all do it).
- **Step 6B (slices 1–4)**: parity-aware 5/3 inverse 1D, parity-aware 2D + multi-level inverse, decoder pipeline IDWT origin wiring, decoder-side roundtrip test updates.

Validation: `HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` exercises 12 fixture × multi-tile-mode pairs through OpenJPH 0.27.0, Grok 20.3.0, and Kakadu 8.4.1 demo. **36 / 36 cells max-abs-pixel-diff = 0.**

### M3 — Parallel native multi-tile encode (Swift Concurrency)

Per-tile encode runs concurrently via `withThrowingTaskGroup`. Each child task owns its tile-component buffers (no aliasing); the codestream assembler serialises only at the SOT/SOD emission step (cheap — a few hundred bytes per tile). Net win: MR 886² beats Kakadu HT-fair encode for the first time in J2KSwift history (Kakadu 4.1 ms → J2KSwift 2.6 ms, **1.58×**). Decode also wins MR (Kakadu 4.8 ms → J2KSwift 4.4 ms, **1.09×**).

Test: `HTFairMultiTileBenchmarkHarness.testHTFairMultiTileBenchmarkPrintTable` (release mode, median of 5).

| Fixture | J2KSwift `.auto` | OpenJPH | Grok | Kakadu | Fastest |
|---|---:|---:|---:|---:|:---|
| MR 886×886 | **2.6 ms** | 10.5 ms | 13.2 ms | 4.1 ms | **J2KSwift (1.58×)** |
| XA 1024×1024 | 8.2 ms | 20.9 ms | 14.1 ms | **5.1 ms** | Kakadu |
| PX 2459×1316 | 23.7 ms | 56.2 ms | 30.2 ms | **11.5 ms** | Kakadu |
| DX 2800×2288 | 54.4 ms | 108.5 ms | 47.8 ms | **19.6 ms** | Kakadu |

XA/PX/DX still trail Kakadu — but the gap roughly halved vs the v5.38.0 baseline (DX gap 5.0× → 2.78×). The structural ceiling is documented in `feedback_v6_alpha4_lever_ceiling.md`; further closure on the CPU side is unlikely without algorithmic changes.

---

## What's New — opt-in

### M4 — GPU forward 5/3 INT DWT path (`J2K_GPU_FORWARD_53=1`)

A Metal-backed forward integer 5/3 DWT for the encode-side wavelet stage. Lands behind a three-predicate gate:

1. `EncoderPipeline._gpuForward53Enabled` (env var `J2K_GPU_FORWARD_53=1` or programmatic `true`)
2. `J2KMetalDWT.isAvailable` (platform predicate — Apple Silicon + Metal)
3. `width * height ≥ _gpuForward53PixelThreshold` (default `4_000_000`)

All three must be true, or the gate routes back to the v5.38.0 CPU path with no observable difference.

**Codestream bytes are byte-identical to the CPU path** at every fixture, every tile mode. The 11-test parity grid in `HTGPUForward53*Tests` confirms: same input → same bytes regardless of which path computed the DWT, regardless of parity, regardless of multi-level depth.

The implementation landed across ten phases:

- **Phase 0** — bit-exact forward 5/3 INT Metal kernels (single-level, single-tile; CPU↔GPU max-abs = 0).
- **Phase 1** — multi-level fused forward 5/3 INT in one kernel + GPU/CPU bench harness.
- **Phase 2** — wired into the encoder; first A/B measurements showed 16× faster MagSgn-only kernel + 26-37× faster cleanup-pass kernel.
- **Phase 3** — `J2KMetalSession.processShared` lazy static singleton amortises Metal init across encodes; setup ms drops from ~25 ms cold to **0 ms warm**, GPU now wins ≥ 6 MP single-tile.
- **Phase 4 slices 1–3** — odd-origin forward 5/3 INT kernels + parity-aware multi-level fused forward + multi-tile encoder wire-in (byte-identical at every parity combination).
- **Phase 5** — multi-tile wall-time sweep + 4 MP threshold ratification (per-tile dispatch regression on 33–43% of multi-tile cases below 4 MP; threshold gates GPU out for those).
- **Phase 6** — per-call `MTLCommandQueue` unblocks GPU command-buffer concurrency; 6+ MP fixtures now scale.
- **Phase 7** — UMA-aware readback (skip bzero on `unsafeUninitializedCapacity` since memcpy will overwrite); release-mode readback deadlock pattern documented in `feedback_metal_readback.md`.
- **Phase 8** — cross-codec validation: 7 medical fixtures × 3 external decoders = **21 / 21 cells bit-exact** (`HTGPUForward53CrossCodecTests`).
- **Phase 9** — routing observability via `J2KGPUForward53Telemetry` (gate-decision counters, setup/dispatch ms accumulators, `J2K_GPU_FORWARD_53_DEBUG=1` per-call diagnostic prints) + threshold-boundary sweep (1, 2, 3, 4, 6, 12, 16 MP synthetic fixtures) confirming 4 MP is the right production threshold.

Wall-time delta vs CPU-best at each fixture size (release median of 5, single-tile, threshold forced to 1 so every fixture exercises GPU):

| Fixture | px | CPU forward | GPU forward | Δ |
|---|---:|---:|---:|---:|
| 4 MP (2000²) | 4 000 000 | 41.19 ms | **33.21 ms** | **+19.4 %** |
| 6 MP (2449²) | 5 997 601 | 56.75 ms | **45.90 ms** | **+19.1 %** |
| 12 MP (3464²) | 11 999 296 | 106.57 ms | **84.44 ms** | **+20.8 %** |
| 16 MP (4000²) | 16 000 000 | 163.35 ms | **124.97 ms** | **+23.5 %** |

GPU setup time = 0 ms across the board after the first warm fire. Below 4 MP the CPU path wins consistently; the threshold protects opt-in users from the regression zone.

---

## Backward compatibility — single-tile bytes byte-identical

`CrossVersionDeltaBenchmark` (new in this release; lives at `Tests/J2KCodecTests/CrossVersionDeltaBenchmark.swift`) was checked out against the v5.38.0 tag in a separate worktree, run on both versions, and the `.j2c` outputs compared via `cmp`:

| fixture | shape | mode | bytes | v5.38.0 MD5 prefix | v6.0.0 MD5 prefix | identical |
|---|---|:---:|---:|---|---|:---:|
| MR-small | 180×180 | single | 45 224 | `f4add755ec26…` | `f4add755ec26…` | ✓ |
| CT | 512×512 | single | 436 460 | `6c968561c0d3…` | `6c968561c0d3…` | ✓ |
| CT (alt) | 512×512 | single | 406 187 | `043a41ec40f3…` | `043a41ec40f3…` | ✓ |
| MR | 886×886 | single | 167 728 | `98c9b2a02d66…` | `98c9b2a02d66…` | ✓ |
| XA | 1024×1024 | single | 1 621 219 | `bc6adb3ee907…` | `bc6adb3ee907…` | ✓ |
| PX | 2459×1316 | single | 6 431 507 | `6d4c6e4aadfb…` | `6d4c6e4aadfb…` | ✓ |
| DX | 2800×2288 | single | 12 683 182 | `860e357e8462…` | `860e357e8462…` | ✓ |

**13 / 13 codestream MD5s match** (single + 2x2-via-`tileSize`). External decoders confirm bit-exact pixel reconstruction on every fixture × external-decoder pair (21 / 21 cells across OpenJPH 0.27.0 / Grok 20.3.0 / Kakadu 8.4.1).

A v5.38.0 user who upgrades to v6.0.0 and changes nothing sees the same bytes. The only way to observe a different codestream is to flip the new `.auto` / `J2K_GPU_FORWARD_53` opt-ins.

---

## Test Suite Results (v6.0.0 release candidate, 2026-05-06)

Mandatory pre-release commit gate, release mode:

| Suite | Tests | Passed | Failed | Duration |
|---|---:|---:|---:|---:|
| J2KMedicalCorpusEncodePerformanceTests | 2 | 2 | 0 | 30.6 s |
| J2KMedicalCorpusPerformanceTests | 2 | 2 | 0 | 16.6 s |
| J2KStrictCrossCodecValidationTests | 3 | 3 | 0 | 0.5 s |
| **Mandatory gate total** | **7** | **7** | **0** | **47.7 s** |

Plus the new validation suites the v6.0.0 work added:

| Suite | Cells | Passed | Notes |
|---|---:|---:|---|
| HTTileParityMatrixTests | 36 | 36 | 12 fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| HTGPUForward53CrossCodecTests | 21 | 21 | 7 fixtures × OpenJPH/Grok/Kakadu, max-abs-pixel-diff = 0 |
| HTGPUForward53Phase9PolicyTests | 7 | 7 | gate routing + telemetry + byte-identical CPU↔GPU |
| Self-roundtrip (multi-tile) | 5 | 5 | MR/XA/PX 2x2 + DX 2x2/4x4 bit-exact |
| CrossVersionDeltaBenchmark (v5.38↔v6.0.0) | 13 | 13 | codestream MD5s identical |

---

## API surface — additions only, no breaks

Per the lossless-only product target memo (2026-05-05), nothing was removed or repurposed. v6.0.0 adds:

- `J2KEncodingConfiguration.tileLayoutMode: J2KTileLayoutMode` (default `.single`; `.auto`, `.fixed(cols:rows:)` available)
- `J2KGPUForward53Telemetry` enum (snapshot, reset, per-reason counters)
- `EncoderPipeline._gpuForward53Enabled: Bool` (programmatic gate flag; mirrors `J2K_GPU_FORWARD_53` env var)
- `EncoderPipeline._gpuForward53PixelThreshold: Int` (default `4_000_000`)
- `J2KMetalDWT.forward2DInt32MultiLevelFused(...tileOriginX:tileOriginY:)` (parity-aware variant)
- `J2KMetalSession.processShared` (lazy static singleton)

Existing `J2KEncoder(encodingConfiguration:).encode(image)` and `J2KDecoder().decode(bytes)` signatures are unchanged. Default behaviour with default config is byte-for-byte identical to v5.38.0.

---

## Known limitations

- **GPU forward path is opt-in.** Default-off because below 4 MP the CPU path wins on Apple M2; we don't have cross-device perf data yet to widen the gate. Cross-device tuning template in `MEDICAL_BENCHMARK_V6.md` Phase 9 section.
- **GPU multi-tile is intentionally CPU-only.** Phase 5 measured 33–43 % regression for per-tile GPU dispatch on `.auto` `2x2`/`4x4` layouts; the threshold gates GPU out on every multi-tile per-tile dispatch. Re-evaluate when fixture sizes routinely exceed 16 MP per-tile.
- **Kakadu HT-fair encode/decode lead on XA / PX / DX persists.** v6-alpha4 step 11 / 12 explored CPU-side levers; residual gap is structural (Kakadu's hand-rolled NEON entropy coder). Not addressable without algorithmic changes outside the v6.0.0 lossless-medical scope.

---

## Reproducing the headline numbers

```bash
# Mandatory pre-release gate (release mode)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Multi-tile parity matrix vs OpenJPH/Grok/Kakadu (36/36)
swift test --filter HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures

# GPU-forward cross-codec (21/21)
swift test --filter HTGPUForward53CrossCodecTests

# HT-fair multi-tile benchmark vs OpenJPH/Grok/Kakadu (release median of 5)
swift test -c release \
  --filter HTFairMultiTileBenchmarkHarness/testHTFairMultiTileBenchmarkPrintTable

# GPU-forward threshold-boundary sweep (Phase 9)
swift test -c release \
  --filter HTGPUForward53Phase9ThresholdBoundaryTests/testGPUForward53_Phase9_ThresholdBoundarySweep

# Cross-version delta vs v5.38.0 (drop into v5.38.0 worktree, run, byte-diff)
LABEL=v6.0.0 RUNS=5 swift test -c release --filter CrossVersionDeltaBenchmark
```

External decoders required for cross-codec tests (skipped cleanly on hosts without them):
- `ojph_expand` / `ojph_compress` — OpenJPH 0.27.0 (`brew install openjph`)
- `grk_decompress` / `grk_compress` — Grok 20.3.0 (`brew install grokj2k`)
- `kdu_expand` / `kdu_compress` — Kakadu 8.4.1 demo

---

## Companion documents

- `BENCHMARK_REPORT_v6_alpha5_phase9.md` — full HT-fair encode/decode tables + tile parity matrix + Phase 9 threshold-boundary sweep
- `CROSS_VERSION_DELTA_REPORT.md` — v5.38.0 ↔ v6.0.0 byte-equality + per-fixture speed deltas
- `MEDICAL_BENCHMARK_V6.md` — phase-by-phase trajectory across v6-alpha2 → v6-alpha5 (cross-device tuning template at the end)
- `feedback_v6_alpha4_lever_ceiling.md` — why the residual Kakadu encode gap is structural on Apple M2
- `feedback_metal_readback.md` — release-mode Metal readback deadlock pattern (`Array.withUnsafeMutableBytes` → `unsafeUninitializedCapacity + memcpy`)
