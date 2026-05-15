# v10.3 — Close the post-v10.0.0 DX/MG decode gap (iDWT-dominated)

**Branch:** `v10.3-research` (off `main` at v10.0.0 tag)
**Status (2026-05-15):** scoping + Phase 0 stage-profile complete; Phase 1A/1B in flight.
**Predecessor:** v10.2-research (default-on C+NEON HT decoder shipped as v10.0.0). The remaining gap is now iDWT-dominated.

## Why this exists

Published v10.0.0 substitute-corpus best-mode-vs-Kakadu shows:

| Modality | J2KSwift ms | Kakadu ms | Gap (ms) | Gap (×) |
|---|---:|---:|---:|---:|
| DX 2544×3056 | 56.48 | 40.22 | **+16.3** | 1.40× |
| MG 3520×4784 | 121.99 | 68.29 | **+53.7** | 1.79× |

D1.5-D's C+NEON entropy port closed the entropy-dominated portion. The remaining gap is in the inverse 5/3 DWT plus downstream marshalling/conversion.

## Phase 0 — Stage profile (DONE 2026-05-15)

`J2K_PROFILE_DECODE=1 swift test -c release --filter J2KMedicalCorpusPerformanceTests` on M2, lossy 9/7 fixtures (lossless 5/3 share will differ slightly but the structural picture holds — production HT-J2K Lossless uses the same `decodeSingleTileGPU` path):

| Stage | DX 2800×2288 (538 blocks) | share | MG 3520×4784 (1212 blocks) | share |
|---|---:|---:|---:|---:|
| extractTileData | 0.5 ms | 1 % | 1.1 ms | 1 % |
| entropyDecoding (GPU HT) | 9.3 ms | 25 % | 14.5 ms | 12 % |
| dequantization | 0.0 ms | — | 0.0 ms | — |
| **inverseWaveletTransform** | **23.3 ms** | **63 %** | **90-99 ms** | **78 %** |
| dcLevelUnshift | 1.2 ms | 3 % | 3.7 ms | 3 % |
| reconstructImage | 3.9 ms | 10 % | 11 ms | 9 % |
| **Total** | ~38 ms | | ~120 ms | |

Note: the corpus perf test uses lossy 9/7 single-tile; substitute corpus runs HT-J2K Lossless with Phase E2's MG-only 2x2 override active. The profile shares above are indicative of the structural picture, not the precise published v10.0.0 wall numbers.

### Phase 0 verdict

- **iDWT is now the dominant stage on both DX (63 %) and MG (78 %).** v8.4's pre-D1.5 measurement of DX iDWT at 39 % is obsolete — post-D1.5-D entropy is much faster, shifting the share to iDWT.
- The architect's recommended levers (L1 SIMD4 retrofit on `inverseLift53InPlace`, L2 GPU IDWT re-probe for MG, L3 cross-tile pipeline on MG 2x2) are all aimed at the right stage.
- Phase 0 gate: **iDWT ≥ 8 ms on DX** — CONFIRMED (23.3 ms). The lever is real-sized.

## Phase 1A — v8.2 IDWT routing fix bypass A/B (MG 2x2)

Per architect's reading of [J2KDecoderPipeline.swift:3937-3947](Sources/J2KCodec/J2KDecoderPipeline.swift), when `gpuBatch?.plansByComponent` is non-empty (the GPU HT entropy batched path), the multi-tile-per-tile IDWT falls back to CPU as the v8.2 corruption workaround. The diagnostic flag `_v82_disableIDWTRoutingFix` is documented as an A/B switch.

**Hypothesis**: the v8.2 corruption was on 1760×2392 lossy 9/7. Under HT-J2K Lossless on MG 2x2 (each tile 1760×2392), the original GPU IDWT path may produce bit-exact output and unlock a much larger MG wall reduction.

**Procedure**:
1. Run substitute driver with `_v82_disableIDWTRoutingFix = false` (current default) — baseline.
2. Toggle to `true`. Re-run substitute driver.
3. Verify bit-exact via `J2KStrictCrossCodecValidationTests` and `HTTileParityMatrixTests`.
4. If bit-exact AND ≥3 ms MG wall reduction, propose default-flip in a tightened predicate that only forces CPU IDWT for lossy 9/7 multi-tile (avoiding the v8.2 corruption surface).

## Phase 1B — `.auto` router 15 → 20 MP threshold A/B

Current router routes MG (16.84 MP) to `.cpu` based on pre-D1.5 measurement. Post-D1.5-D, `.decodeGPU` may now win on MG.

**Procedure**:
1. Run substitute driver as-is (router picks `.cpu` for MG).
2. Run with `J2K_AUTO_DECODE_API=decodeGPU` forced on MG.
3. If `.decodeGPU` beats `.cpu` by ≥3 ms median on MG, raise the threshold from 15 MP to 20 MP (or eliminate) in `J2KCodec.swift:recommendedDecodeAPI`.

## Phase 2 — SIMD4 retrofit on `inverseLift53InPlace` (conditional on Phase 1 outcomes)

Conditional on Phase 1A/1B not closing the gap to ≤1.10× Kakadu on DX. See architect's plan; Swift SIMD4 retrofit on the production scalar lifting body. Project: −2 to −5 ms DX, −0 to −5 ms MG.

## Phase 3+ — Deferred to follow-up sessions

Phase 3 (Int32→Double conversion skip), Phase 4 (deep-level TaskGroup overhead), Phase 5 (selective-resolution API), Phase 6 (C+NEON DWT). Each gated on Phase 1+2 outcomes.

## Stop triggers (codified)

- Phase 1A: bit-exact fails on any seed → revert; do not push the v8.2 bypass into production.
- Phase 1B: <3 ms MG wall delta → don't churn the router.
- Phase 2: <1.5× per-pass SIMD4 speedup on in-L1 deepest level → abandon; the lever ceiling is in gather, not arithmetic. Defer to Phase 6 (C+NEON DWT with `vld2q`).
