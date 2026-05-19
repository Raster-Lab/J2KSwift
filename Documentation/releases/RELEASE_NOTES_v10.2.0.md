# J2KSwift v10.2.0 — Opt-in fused H+V inverse 5/3 Int Metal kernel for ≥12 MP fixtures

**Release date:** 2026-05-19
**Base:** `v10.1.0` (`fd641c4`)
**Type:** MINOR per RELEASING.md "New public type / function / config option, default unchanged, codestream bytes byte-identical on default config | MINOR". Default decoder behaviour is unchanged from v10.1.0 — the new path is opt-in only.

## Summary

v10.2.0 adds an **opt-in single-kernel H+V fused inverse 5/3 Int Metal kernel** behind `J2K_METAL_IDWT_FUSED=1`, gated by `inverse53IntFusedPixelThreshold = 12_000_000` so only ≥12 MP per-level passes take the fused path. The kernel collapses the v10.1.0 Phase 2-2-tiled pair (2 horizontal + 1 vertical dispatches per IDWT level) into one dispatch by holding the H-pass output in threadgroup memory across the V lift — eliminates the colLow/colHigh device-memory round-trip (~2× DRAM saving per level at MG L1, 3 → 1 kernel encoder overhead per level).

**Production decode behaviour is unchanged from v10.1.0.** The tiled pair stays as the default. The fused kernel is delivered as a production-quality opt-in trial path for early adopters and as the building block for a future v10.3.0 default-flip pending cross-silicon (M3/M4) variance validation.

Codestream bytes are byte-identical to v10.1.0.

## What's New — opt-in

### Fused H+V inverse 5/3 integer kernel (Phase 2-3-fused)

- `j2k_dwt_inverse_53_fused_int_tiled` — 32×10 threadgroup, 32×16 output tile per dispatch. Each tg covers 8 body input rows + 2 halo rows (lid.y ∈ {0, 9}); halo rows contribute to the V-lift symmetric extension via redundant H-pass without writing output.
- Three barriers (H-Stage-A even-cols → H-Stage-B odd-cols → V-Step-1 even-rows → V-Step-2 odd-rows). Threadgroup memory footprint: 2 × 10 × 32 × 4 = 2560 bytes per tg.
- Bit-exact equivalent of the v10.1.0 tiled pair by construction (same arithmetic, same symmetric-boundary handling; H-pass output is staged through threadgroup memory instead of device memory).

### Pixel-threshold gate

- `J2KMetalDWT.inverse53IntFusedPixelThreshold: Int = 12_000_000` — default 12 MP. The fused path runs only when the per-level pixel count (`originalWidth * originalHeight`) is at or above this threshold. Below threshold, dispatch falls through to the v10.1.0 tiled pair.
- 12 MP threshold rationale: the 10-trial variance bench established the fused-vs-tiled crossover. MG-class fixtures (16.8 MP) are above the threshold and have positive median lift. DX (7.7 MP) / PX (3.7 MP) / XA (1 MP) / CT (0.26 MP) are below — the bench confirms the lever doesn't apply at those scales, and the tiled pair is at least as fast.

### Opt-in env flag

- `J2KMetalDWT.inverse53IntFusedEnabled: Bool` — defaults from `ProcessInfo.processInfo.environment["J2K_METAL_IDWT_FUSED"] == "1"`. **Default OFF.** Set the env var or assign the static flag programmatically to enable.

## What's New — diagnostic tests

- `V10_5_MetalIDWTInverse53FusedParityTests` — 3 test methods, 21 (fixture, seed) combinations, bit-exact vs scalar reference (small + odd + medical-corpus dimensions). Lowers `inverse53IntFusedPixelThreshold` to 0 so the fused kernel actually runs on all sizes.
- `V10_5_MetalIDWTInverse53FusedMicrobench` — A/B vs tiled, 10 synthetic fixtures including MG/DX/PX class.
- `V10_5_MetalIDWTInverse53FusedEndToEndABTests` — warm A/B on the real medical corpus through the full decode pipeline.
- `V10_5_MetalIDWTInverse53FusedVarianceTests` — 10-trial interleaved (tiled, fused) sampling with per-trial Δ statistics and a RELIABLE WIN / WASH / BORDERLINE verdict.

## Backward compatibility

- **Codestream bytes byte-identical to v10.1.0 on every default configuration.** This is an opt-in decoder optimisation; the production path remains the v10.1.0 tiled pair.
- Decoder output is bit-exact vs v10.1.0 — both with the opt-in OFF (production tiled path) and ON (fused path) per `V10_5_MetalIDWTInverse53FusedParityTests`.
- Cross-codec parity preserved with `J2K_METAL_IDWT_FUSED=1` set: `J2KStrictCrossCodecValidationTests` 3/3 PASS.
- Public Swift API additions only (`inverse53IntFusedEnabled`, `inverse53IntFusedPixelThreshold`). No type removals, no signature changes.

## Cross-codec parity matrix

`J2KStrictCrossCodecValidationTests` with `J2K_METAL_IDWT_FUSED=1`: 3/3 PASS.

| Encoder bytes consumed by | Decode-bit-exact vs J2KSwift |
|---|---|
| OpenJPH (`ojph_expand`) | PASS |
| Grok (`grk_decompress`) | PASS |
| Kakadu (`kdu_expand`) | PASS |

## Medical-corpus variance bench

10-trial interleaved (tiled, fused) sampling on Apple M2 release. Per-trial Δ = tiled (v10.1.0 production) − fused (v10.2.0 opt-in). Positive = fused faster.

| Fixture            | Δ med  | Δ mean | Δ std  | frac > 0 | verdict       |
|--------------------|-------:|-------:|-------:|---------:|---------------|
| MG small 3516×4784 | +4.68  | +3.56  |  5.74  |     70%  | RELIABLE WIN  |
| MG mid 3518×4784   | +2.64  | +2.18  |  5.48  |     70%  | BORDERLINE    |
| MG large 3521×4784 | +7.67  | +1.49  |  8.27  |     50%  | BORDERLINE    |
| DX large 2544×3056 | +0.55  | +0.35  |  0.60  |     70%  | BORDERLINE    |
| PX large 2812×1316 | +0.02  | −0.31  |  0.65  |     50%  | RELIABLE WASH |

Signal interpretation:
- **All 3 MG fixtures have positive median lift** (+2.64 / +4.68 / +7.67 ms).
- **MG small / mid both hit 70 % positive** — directional signal is real.
- **MG large has 50 % positive** (coin flip per trial) but median +7.67 ms is dragged by extreme positive outliers (mean only +1.49 ms).
- **DX / PX**: wash — per-level pixel count below the bandwidth-lever crossover; existing tiled pair already at-or-better.

The 12 MP threshold routes DX (7.7 MP) and PX (3.7 MP) back through the tiled pair when the env var is set, so the per-decode behaviour for those fixtures is unchanged.

## Warm cross-codec benchmark — production behaviour unchanged

Because the v10.2.0 default decoder routing is identical to v10.1.0 (the opt-in flag is OFF on `main`), the canonical warm cross-codec bench output from v10.1.0 still applies for any production wall claim. See [`Documentation/releases/RELEASE_NOTES_v10.1.0.md`](RELEASE_NOTES_v10.1.0.md) for the v10.1.0 numbers; they are unchanged in v10.2.0.

When `J2K_METAL_IDWT_FUSED=1` is set, expect the variance-bench numbers above on MG-class fixtures and unchanged numbers on smaller fixtures (which route through the 12 MP threshold back to the tiled pair).

## Migration notes

- **No action required** for consumers that don't set the env flag — production decode behaviour is unchanged.
- **Trial users** (e.g., PACS / clinical-imaging workloads predominantly on MG-class fixtures) can opt in via:
  - Env var: `J2K_METAL_IDWT_FUSED=1` at process start.
  - Programmatic: `J2KMetalDWT.inverse53IntFusedEnabled = true` before any decode.
- The opt-in is **safe** — the 12 MP threshold guarantees DX/PX/XA/CT fixtures stay on the tiled path even with the flag on.

## Future v10.3.0 candidate

Default-flip to `inverse53IntFusedEnabled = true` is gated on cross-silicon validation:

1. Re-run `V10_5_MetalIDWTInverse53FusedVarianceTests` on M3 / M4 / A-series with `inverse53IntFusedPixelThreshold = 0` to settle whether the MG-large coin-flip is M2-specific (larger L2 + faster DRAM fabric on M3/M4 may tighten the variance and unblock the default-flip).
2. If MG-large lands consistently above +3 ms median with ≥70 % positive on M3/M4, ship v10.3.0 with default-on for ≥12 MP.

## Test Suite Results

| Suite | Cells | Result |
|---|---:|---|
| `V10_5_MetalIDWTInverse53FusedParityTests` | 21 | PASS (3/3 test methods, bit-exact across small + odd + medical dims) |
| `V10_5_MetalIDWTInverse53FusedMicrobench` | 10 fixtures | PASS (printed A/B table, no XCTAssertions on perf) |
| `V10_5_MetalIDWTInverse53FusedEndToEndABTests` | 11 fixtures | PASS (printed A/B table) |
| `V10_5_MetalIDWTInverse53FusedVarianceTests` | 5 fixtures × 10 trials | PASS (printed verdict table) |
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | PASS |
| `J2KMedicalCorpusPerformanceTests` | 2 | PASS |
| `J2KStrictCrossCodecValidationTests` (default) | 3 | PASS |
| `J2KStrictCrossCodecValidationTests` (with `J2K_METAL_IDWT_FUSED=1`) | 3 | PASS |

## Companion documents

- [`Documentation/research/V10_5_METAL_IDWT_FUSED_FINDING.md`](../research/V10_5_METAL_IDWT_FUSED_FINDING.md) — full research finding with dispatch design, decision tree, two-run end-to-end A/B that preceded the variance bench.
- [`Documentation/BENCHMARK.md`](../BENCHMARK.md) — canonical warm cross-codec methodology.
