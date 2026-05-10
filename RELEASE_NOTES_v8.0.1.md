# J2KSwift v8.0.1 — silent-corruption hotfix + GPU IDWT root cause

**Tag**: `v8.0.1`
**Released**: 2026-05-10
**Headline**: Fixes the v7.5.1 mg silent-corruption (cross-tile batched HT entropy decode) and root-causes / fixes the underlying GPU multi-tile-per-tile 5/3 IDWT defect that produced the corruption. `_multiTileBatchedEntropyEnabled` is back default-on; the v7.2.0 cross-tile entropy CB amortisation is restored.

---

## What's fixed

### v8.2 — mg silent-corruption resolved (PR #399)

PR #356 (v7.2.0 phase-e) shipped `decodeMultiTileGPUBatched` to amortise per-tile MTLCommandBuffer overhead by aggregating all tiles' eligible HT codeblocks into one shared GPU dispatch. The path silently corrupted output on certain multi-tile codestreams; surfaced 2026-05-09 by an external 4-codec eval matrix on mammography (mg) DICOM fixtures (3520×4784 = 16.84 M px). External decoders (OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1) decode the same J2KSwift-encoded bytes bit-exactly — encoder is correct.

The v7.5.1 hotfix worked around it by disabling `_multiTileBatchedEntropyEnabled` by default, sacrificing the v7.2.0 cross-tile amortisation (3 % DX 2x2) until root-caused.

**Root cause**: NOT in the entropy decode itself. In `decodeTilePayloadGPU`, the routing through `applyInverseWaveletTransformGPU` checks `gpuBatch?.plansByComponent.isEmpty == false` to decide CPU vs GPU IDWT:

| path | entropy | `gpuBatch` returned | IDWT |
|---|---|---|---|
| **per-tile** | `decodeBatchGPUResident` per tile | non-nil (`buildGPUHTBatchFromResult`) | CPU ✓ |
| **batched (pre-fix)** | `decodeBatch` once + per-tile short-circuit via `preBatchedGPUCoefficients` | **nil** | **GPU** ✗ |

Per-tile path: entropy returns non-nil fused batch → CPU IDWT. Batched path: pre-batched short-circuit returns no batch → GPU IDWT runs, and the GPU multi-tile-per-tile IDWT silently corrupts on certain dimensions.

**Smallest reproducer**: 1760×2392 split 2x2 (880×1196 per tile, 4.21 M total samples). The "2^24 samples threshold" claim from v7.5.1 was a red herring — the diagnostic sweep shows several >2^24 cases that DON'T trigger (4097², 4608², 5120²) and several <2^24 cases that DO (1760×2392 = 4.21M; 3520×2392 = 8.4M).

**Fix**: in `decodeTilePayloadGPU`, when `preBatchedGPUCoefficients` is set, call `applyInverseWaveletTransform` (CPU) directly instead of going through `applyInverseWaveletTransformGPU`'s threshold-gated route. Matches the per-tile path's effective behaviour. `_multiTileBatchedEntropyEnabled` flipped back to `true` by default.

### v8.3 — GPU multi-tile-per-tile 5/3 IDWT root cause + fix (PR #400)

The v8.2 fix routed AROUND the GPU IDWT bug. v8.3 root-causes and fixes that bug — actually **two distinct bugs**, both surfacing only on tiles with non-zero canvas origin.

**Bug #1 — naive-recursion `levelSizes` (the X-axis cliff)**

`applyInverseWaveletTransformGPU` used `(pw + 1) / 2` ceil-div recursion for per-level subband dimensions. For non-zero canvas X origin, this disagrees with the encoder's canvas-anchored ISO/IEC 15444-1 Eq. B-15 partition.

Example: tile (0, 1) at depth 5 — naive gives 28, spec gives `ceil(1760/32) − ceil(880/32) = 27`. Encoder produces 27. GPU treated input as 28 → entire tile corrupts.

Fix: switch the GPU path to the same spec formula (`bandX1 − bandX0`) the CPU path's `applyInverseWaveletTransform` already uses.

**Bug #2 — `halfHH = H/2` instead of `H − llH` (the Y-axis residual)**

`encodeInverse2DInt32` + `inverse2DInt32MultiLevelFused` computed the LH/HH band row count as `originalHeight / 2`. For ODD canvas V origin: LL = `floor(H/2)`, LH/HH = `ceil(H/2)`. `H/2 = floor(H/2)` under-counts H by 1 when H is odd.

For tile (1, 0) at level 5: H=75, llH=37 (post-Fix #1). halfHH was 37 — but LH/HH had 38 rows. Pass 1 H-IDWT processed only 37/38 rows; colHigh's 38th row stayed uninitialised. Pass 2 V-IDWT (with the ODD-V kernel that uses `highCount = ceil(H/2) = 38`) read all 38 rows — picking up garbage, propagating into bottom-row output.

Fix: `halfHH = originalHeight − llHeight`. Two 1-line edits.

**Per-tile mismatch progression on the smallest reproducer (1760×2392)**:

| tile | tcx0, tcy0 | pre-v8.3 | after Fix #1 | after Fix #1+#2 |
|---|---|---:|---:|---:|
| (0, 0) | 0, 0 | 0 | 0 | **0** |
| (0, 1) | 880, 0 | 1,048,207 | 0 | **0** |
| (1, 0) | 0, 1196 | 48,128 | 47,175 | **0** |
| (1, 1) | 880, 1196 | 1,049,385 | 47,357 | **0** |

The v8.2 routing fix stays in place — v6.3.0 E1.2 measured GPU IDWT at 400 K/tile to be 1.28× SLOWER than CPU on M2, so the per-tile-CPU-IDWT routing is the right perf shape. v8.3 is defensive: any future code that DOES invoke the GPU IDWT on multi-tile-per-tile now produces correct output.

## Backward compatibility

- **Codestream bytes byte-identical to v8.0.0** — no encoder change.
- **`_multiTileBatchedEntropyEnabled` default flipped `false` → `true`** — restores v7.2.0 phase-e cross-tile entropy CB amortisation. Decode output is bit-exact to v8.0.0's per-tile path; only the internal routing changes.
- **Public API additions** (test-only):
  - `nonisolated(unsafe) public static var DecoderPipeline._v82_disableIDWTRoutingFix: Bool = false` — diagnostic toggle, must stay `false` in production.
- No public API removals or signature changes.

## SemVer rule

**PATCH** per RELEASING.md — codestream bytes unchanged, no public API breakage. Default-flag flip restores pre-v7.5.1 behaviour for the internal routing, with a new correctness gate.

`getVersion()` returns `"8.0.1"`.

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | 0 failures (29.910 s) |
| `J2KMedicalCorpusPerformanceTests` | 2 | 0 failures (9.672 s) |
| `J2KStrictCrossCodecValidationTests` | 3 | 0 failures (0.460 s) |
| `MgRegressionTriageTest` (assertion flipped — must PASS bit-exact at 16+ MP) | 2 | 0 failures |
| `V8_2_MgBatchedDiagnostic` (10 cases — all 8 triggers + 2 controls) | 1 | 0 failures |
| `V8_3_GPUIDWTRootCauseDiagnostic` (3 tests, GPU IDWT bypassing v8.2 fix) | 3 | 0 failures |
| **total** | **13** | **0 failures** |

## Companion documents

- `V8_2_0_MG_CORRUPTION_ROOT_CAUSE.md` — v8.2 routing fix root cause
- `V8_3_0_GPU_IDWT_ROOT_CAUSE.md` — v8.3 two-bug root cause + per-tile localisation
- `Tests/J2KCodecTests/MgRegressionTriageTest.swift` — permanent regression at the original mg dimensions
- `Tests/J2KCodecTests/V8_2_MgBatchedDiagnostic.swift` — 10-dimension sweep verifying the v8.2 routing fix
- `Tests/J2KCodecTests/V8_3_GPUIDWTRootCauseDiagnostic.swift` — GPU IDWT bit-exact verification via the test-only routing-fix bypass toggle

## Reproducing

```bash
swift build -c release

# Mandatory pre-release gate
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# v8.0.1 regression suites
swift test -c release --filter \
  'MgRegressionTriageTest|V8_2_MgBatchedDiagnostic|V8_3_GPUIDWTRootCauseDiagnostic'
```
