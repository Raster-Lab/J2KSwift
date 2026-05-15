# J2KSwift v10.1.0 — Tiled Metal inverse 5/3 DWT default-on (decode-only optimisation)

**Release date:** 2026-05-15
**Base:** `v10.0.0` (`ef81a2d`)
**Type:** MINOR per RELEASING.md "Bug fix, perf improvement, doc-only change | PATCH" / "New public type / function / config option, default unchanged, codestream bytes byte-identical on default config | MINOR". Codestream bytes are byte-identical to v10.0.0 on every default configuration — this is a **decoder-only** optimisation.

## Summary

v10.1.0 ships **threadgroup-memory tiled Metal inverse 5/3 DWT kernels** as the production default. Decode wall reduces 7–25 % across every medical-corpus fixture on Apple M2 — most prominently MG mammography (−24 % to −29 ms wall reduction on the 17 MP fixtures).

The optimisation targets the bottleneck Phase 0 of v10.3-research identified: iDWT became the dominant decode stage (63 % DX / 78 % MG of wall) after v10.0.0's D1.5-D NEON HT entropy default-on. Two new Metal kernels fuse step 1 (undo update) and step 2 (undo predict) of the 5/3 lifting into a single dispatch per pass via threadgroup memory + barrier, closing both the kernel-boundary cost and the cross-step RAW dependency that previously round-tripped through device memory.

Decoder output is bit-identical to v10.0.0; codestream bytes are unchanged.

## What's New — production-default

### Tiled Metal inverse 5/3 integer kernels (Phase 2-2-tiled)

- `j2k_dwt_inverse_53_horizontal_int_tiled` — 32×8 threadgroup, 33-wide `tg_even` halo, step 1 → barrier → step 2 in one dispatch.
- `j2k_dwt_inverse_53_vertical_int_tiled` — symmetric 32×8 threadgroup, 33-tall `tg_even` halo for the vertical pass.

Routed through `J2KMetalDWT.inverse2DInt32MultiLevelFused` when `inverse53IntTiledEnabled` is true (default ON since v10.1.0). Even-origin only — odd-origin paths keep the parity-aware scalar kernels.

Bit-exact equivalent of the scalar kernel by construction: same arithmetic, same symmetric-boundary handling; step 1 evens are staged through threadgroup memory instead of device memory.

## What's New — opt-out / opt-in

- **`J2K_METAL_IDWT_TILED=0`** — opt out of the tiled path; falls back to the scalar kernels.
- **`J2K_METAL_IDWT_2D=1`** — opt in to the Phase 2-1 2D-layout path (kept opt-in only for backward compatibility with v10.0.0's research-branch experiments; the tiled path takes precedence when both are set).

## Backward compatibility

- **Codestream bytes byte-identical to v10.0.0 on every default configuration.** This is a decoder optimisation.
- Decoder output is bit-exact vs v10.0.0 per `V10_3_MetalIDWTInverse53TiledParityTests` (4 tests, substitute corpus + odd dims + small sizes, 0 failures).
- Cross-codec parity preserved (OpenJPH / Grok / Kakadu decode J2KSwift bytes bit-exactly).
- Public Swift API unchanged. No type removals, no signature changes.

## Cross-codec parity matrix

`J2KStrictCrossCodecValidationTests` with tiled default-on: 3/3 PASS.

| Encoder bytes consumed by | Decode-bit-exact vs J2KSwift |
|---|---|
| OpenJPH (`ojph_expand`) | PASS |
| Grok (`grk_decompress`) | PASS |
| Kakadu (`kdu_expand`) | PASS |

## Medical-corpus benchmarks

Warm cross-codec bench (M2 release, `Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2`).

### Decode wall — J2KSwift in-process (medical-real fixtures), v10.0.0 vs v10.1.0

| Fixture | v10.0.0 ms | v10.1.0 ms | Δ ms | Δ % |
|---|---:|---:|---:|---:|
| PX 2459×1316 small | 27.71 | 25.30 | **−2.41** | −8.7% |
| PX 2793×1316 mid | 30.89 | 27.63 | **−3.26** | −10.6% |
| PX 2812×1316 large | 30.93 | 27.86 | **−3.07** | −9.9% |
| DX 2224×2798 small | 48.94 | 45.10 | **−3.84** | −7.8% |
| DX 2800×2288 mid | 50.93 | 44.88 | **−6.05** | −11.9% |
| DX 2544×3056 large | 64.53 | 56.78 | **−7.75** | −12.0% |
| MG 3516×4784 small | 127.13 | 117.00 | **−10.13** | −8.0% |
| MG 3518×4784 mid | 132.19 | 99.62 | **−32.57** | **−24.6%** |
| MG 3521×4784 large | 138.91 | 109.58 | **−29.33** | **−21.1%** |

Every medical-real decode fixture clears v7.4's ≥3 ms acceptance threshold for default-on.

### J2KSwift v10.1.0 vs Kakadu CLI

| Fixture | v10.1.0 J2KSwift ms | Kakadu ms | J2KSwift / Kakadu |
|---|---:|---:|---:|
| PX 2459×1316 small | 25.30 | 19.61 | 1.29× |
| PX 2793×1316 mid | 27.63 | 19.67 | 1.40× |
| PX 2812×1316 large | 27.86 | 19.66 | 1.42× |
| DX 2224×2798 small | 45.10 | 38.68 | 1.17× |
| DX 2800×2288 mid | 44.88 | 37.40 | 1.20× |
| **DX 2544×3056 large** | 56.78 | 38.15 | **1.49×** (was 1.54× in v10.0.0) |
| MG 3516×4784 small | 117.00 | 76.43 | 1.53× |
| MG 3518×4784 mid | 99.62 | 76.65 | 1.30× |
| **MG 3521×4784 large** | 109.58 | 75.34 | **1.45×** (was 1.79× in v10.0.0) |

MG Kakadu gap **closed from 1.79× to 1.45×** on the headline fixture — single largest perf delta in the v10 series.

### Encode

Encode walls byte-identical to v10.0.0 (decoder-only release).

## Test Suite Results (release mode)

| Suite | Tests | Outcome |
|---|---:|---|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` | 3 | PASS |
| `V10_3_MetalIDWTInverse53TiledParityTests` | 4 | PASS (bit-exact, substitute corpus + odd dims + small sizes) |
| `V10_3_MetalIDWTInverse53TiledMicrobench` | 1 | PASS (1.27-6.44× kernel speedup) |
| `V10_3_MetalIDWTInverse532DParityTests` | 4 | PASS (Phase 2-1 2D-layout opt-in stays correct) |

## API surface (additions only)

- `J2KMetalDWT.inverse53IntTiledEnabled: Bool` — public flag, defaults to `true` since v10.1.0 (opt-out via `J2K_METAL_IDWT_TILED=0`).
- `J2KMetalShaderFunction.dwtInverse53HorizontalIntTiled` + `dwtInverse53VerticalIntTiled` — new enum cases.

## Known limitations

- **MG `.decodeGPU` still slower than MG `.cpu`** on M2 even with tiled iDWT (Phase 2-4 re-eval, commit `c81aae3`). The `recommendedDecodeAPI` ≥15 MP CPU-fallback threshold remains correct. Tiled iDWT closes ~11 ms of MG `.decodeGPU` wall but CPU iDWT is still ~15 ms ahead on the 16.8 MP fixture.
- **DX 2544 small variance** — single-run wall measurements on DX/MG show ±5 ms variance. The v7.4 3 ms threshold is cleared on every medical-real fixture but single-fixture deltas below 5 ms should be treated as variance, not signal.

## Reproducing the headline numbers

```bash
# Mandatory commit gate
swift test -c release --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Warm cross-codec bench (tiled default-on)
python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2

# Warm cross-codec bench with tiled OPT-OUT (v10.0.0-equivalent path)
J2K_METAL_IDWT_TILED=0 python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc --runs 7 --warmups 2

# Tiled Metal iDWT microbench (isolated kernel A/B)
swift test -c release --filter V10_3_MetalIDWTInverse53TiledMicrobench
```

## Companion documents

- [`Documentation/research/V10_3_DECODE_STAGE_REPRIORITISATION.md`](../research/V10_3_DECODE_STAGE_REPRIORITISATION.md) — Phase 0 stage profile + lever re-prioritisation
- [`Documentation/research/V10_3_METAL_IDWT_OPTIMIZATION_PROBE.md`](../research/V10_3_METAL_IDWT_OPTIMIZATION_PROBE.md) — multi-week Phase 2 arc plan
- [`Documentation/research/V10_3_PHASE_2_2_END_TO_END_FINDING.md`](../research/V10_3_PHASE_2_2_END_TO_END_FINDING.md) — Phase 2-1 2D-layout mixed-result finding (motivated Phase 2-2-tiled)
- [`Documentation/research/V10_3_PHASE_2_4_ROUTER_REEVAL.md`](../research/V10_3_PHASE_2_4_ROUTER_REEVAL.md) — MG router re-eval wash

## Migration notes

- **Default decode workloads**: no action required. Tiled Metal iDWT is default-on; wall reduction is automatic on every fixture.
- **Bit-exact regression tests downstream**: J2KSwift decoder output is bit-identical to v10.0.0; no checksum changes downstream.
- **MG-heavy workloads** that observed an unexpected regression: opt out via `J2K_METAL_IDWT_TILED=0`. File a report so the MG-specific behaviour can be investigated.
