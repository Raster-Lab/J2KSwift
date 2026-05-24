# J2KSwift

[![CI](https://github.com/Raster-Lab/J2KSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/ci.yml)
[![Code Quality](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml)
[![Documentation](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A pure Swift 6.2 implementation of JPEG 2000 (ISO/IEC 15444) encoding and decoding with strict concurrency support.

**Current Version**: 10.11.0
**Status**: Apple Silicon-first JPEG 2000 / HTJ2K (Part-15) implementation. v10.11.0 ships **JP3D batched GPU iDWT**: a new single-dispatch Metal kernel amortises per-slice GPU overhead across the whole volume. `JP3DSliceStackCodec.decode` now runs ONE batched iDWT dispatch across all slices of a tile instead of N per-slice dispatches. M2 release JP3D full decode wins **−5 ms on small CT to −115 ms on 16M-voxel CT** (1.07–1.17× faster, 5/6 fixtures cross the 3 ms acceptance threshold). Decoder-only; codestream bytes byte-identical to v10.10.0.
**Previous Release**: 10.10.0 (JP3D true partial-resolution + ROI footprint-skip + Z-narrow)
**Release process**: see [RELEASING.md](RELEASING.md). Every release MUST update this README (Current Version line + new Release Status paragraph) — see the Release artefacts checklist for the full requirements.

## 📦 Release Status

**v10.11.0** ships **JP3D batched GPU iDWT** — the production landing of a multi-week research arc that splits the JP3D per-tile decode pipeline at the dequant↔iDWT boundary and submits one batched Metal dispatch across the whole z-range instead of N per-slice dispatches. A new opaque-payload bridge SPI on `J2KDecoder` (`_jp3dDecodeToCoefficients` / `_jp3dIDWTAndFinalize` / `_jp3dIDWTAndFinalizeBatched`) is the architectural surface; two new Metal kernels (`j2k_dwt_inverse_53_horizontal_int_tiled_batched`, `..._vertical_..._batched`) extend the v10.3 tiled threadgroup-memory kernels with a Z-dim grid axis, processing N slices in one dispatch. `JP3DSliceStackCodec` now runs **parallel `_jp3dDecodeToCoefficients` across `[zStart, zUpper)` via a TaskGroup, then ONE batched iDWT call** before the existing sequential Z-delta residual chain. Per-slice GPU dispatch overhead amortises across the volume; the gain scales with slice count × per-slice work. **M2 release, J2KBenchMac --jp3d, in-process, 7 timed runs / 2 warmups**: ct_3d_small **−5.12 ms** (1.13×), us_3d_small −4.15 ms (1.07×), mr_3d_mid **−9.50 ms** (1.12×), ct_3d_mid **−53.25 ms** (1.17×), **ct_3d_large 16M-voxel CT −114.57 ms** (1.17×). 5/6 fixtures clear the 3 ms acceptance threshold; the wash (mr_3d_small @ 13 ms wall) is the smallest fixture where per-slice overhead dominates anyway. Kernel-level bench (16 slices × 256×256 × 3 levels): **5.93 → 2.06 ms = 2.4× faster GPU dispatch**. Eligibility gate: only `K=0 + no ROI` routes through the batched path; `K>0` keeps the per-slice `decodeResolution` loop and ROI keeps `decodeRegion` (bridging those is future work). Opt-out via `J2K_JP3D_BATCHED_BRIDGE=0`. **`V10_20_BatchedBridgeParityTests` 5/5 PASS, `V10_20_BatchedInverseInt32ParityTests` 12/12 PASS, `V10_20_JP3DBridgeParityTests` 5/5 PASS, full `swift test --filter JP3D` regression sweep 519/519 PASS, mandatory commit gate 7/7 PASS**. Codestream bytes byte-identical to v10.10.0; encoder unchanged. See [RELEASE_NOTES_v10.11.0.md](RELEASE_NOTES_v10.11.0.md) and the bench JSONs in [Documentation/Benchmarks/data/](Documentation/Benchmarks/data/).

**v10.10.0** ships **JP3D true partial-resolution + ROI footprint-skip + Z-narrow ROI skip** — three coordinated decoder-side changes inside `Sources/J2K3D/` that close the long-standing follow-up on JP3D's selective-decode story. **`JP3DDecoderConfiguration.resolutionLevel`** has been wired into the struct since v5.x but the decoder ignored it (silently returned full resolution); v10.10.0 routes each per-slice 2D codestream inside `JP3DSliceStackCodec` through the existing v10.5.0 `J2KDecoder.decodeResolution(_:options:)`, producing a volume sized `⌈W / 2^K⌉ × ⌈H / 2^K⌉ × D` as documented. **`JP3DROIDecoder`** swaps decode-then-crop for true ROI footprint-skip — the per-tile in-tile XY sub-region is passed through to the slice-stack codec, which routes the per-slice 2D decode through v10.6.0 `decodeRegion(_:options:)` with `.direct` strategy (code-blocks whose inverse-DWT cone-of-influence misses the region skip entropy decode entirely). **Z-narrow ROI skip** pre-scans slice headers (no decode), finds the latest non-residual slice ≤ `zRange.lowerBound`, and starts decoding from there — completely skipping the unused Z-prefix while keeping Z-delta residual chain integrity via the restart anchor. M2 release: **`resolutionLevel = 1` is 2.2–3.1× faster than full decode** (mr_3d_small 2.22×, ct_3d_small 3.05×, mr_3d_mid 3.01×); **ROI 1/4 is 3.4–4.1× faster than full decode** (mr_3d_small 3.37×, ct_3d_small 4.14×, mr_3d_mid 3.96×). Combined `resolutionLevel + ROI` throws loud (was silently ignored previously). `V10_18_TrueSelectiveParityTests` 9/9 PASS, existing `JP3DDecoderTests` 61/61 PASS, mandatory commit gate clean. Encoder unchanged. Codestream bytes byte-identical to v10.9.3. See [RELEASE_NOTES_v10.10.0.md](RELEASE_NOTES_v10.10.0.md) and [V10_18_JP3D_TRUE_SELECTIVE_DECODE.md](Documentation/research/V10_18_JP3D_TRUE_SELECTIVE_DECODE.md).

**v10.9.3** is a packaging hotfix that makes J2KSwift unconditionally URL-consumable. v10.9.2 attempted CWD-conditional dependency resolution (sibling path if present, else URL) but `FileManager.fileExists` is evaluated with CWD set to the consuming root package — any consumer with a `CompressionFamily` directory beside its own root caused J2KSwift to fall back to the path form, and stable-version consumers may not transitively depend on path/branch packages ("unstable-version package" error). v10.9.3 drops the probe and always uses the public Git URL; local co-development uses `swift package edit CompressionFamily --path ../CompressionFamily`. Single-file Package.swift change; no codec change, codestream bytes byte-identical to v10.9.2.

**v10.9.2** is a stability + packaging patch. It fixes two latent `SIGSEGV` crashes and a packaging defect. **HTJ2K encoder crash (#439):** the fused HT entropy path force-unwrapped an empty buffer's `baseAddress` and trapped on degenerate / zero-coefficient code-blocks — observed crashing parallel code-block workers during the DICOMKit v1.1.0 integration; the five force-unwraps across the three coefficient-extraction sites are now `guard let` (an empty buffer falls through to the existing zero-block path). **Report-generator crash:** `ValidationReportGenerator.textReport` passed Swift `String` values to `String(format:)` `%s` specifiers — `%s` requires a C string, so the argument was `strlen`'d as a bogus tagged pointer; the 14 `%s` sites are replaced with Swift column padding + interpolation (this defect had also been silently aborting full `swift test` runs). **SwiftPM URL consumption (#438):** `Package.swift`'s `CompressionFamily` dependency is now conditional — local path for co-development, public Git URL otherwise — making J2KSwift resolvable via `.package(url:)` once the public `CompressionFamily` repo is published. Also: CI restructured Apple-only, the SwiftLint gate fixed (288 error-level findings → 0, kept as warnings), and the `J2KMetalDWT` band geometry consolidated into one `BandGeometry` helper (output-identical). Codestream bytes byte-identical to v10.9.1 — the encoder fix only alters the previously-crashing path. Validated: mandatory commit gate + HT cross-codec suites 22/22, 0 failures; a full `swift test` (6148 tests) now runs to completion where the report crash previously aborted it. See [RELEASE_NOTES_v10.9.2.md](Documentation/releases/RELEASE_NOTES_v10.9.2.md).

**v10.9.1** is a decoder correctness hotfix. The GPU multi-tile per-tile inverse 5/3 DWT corrupted the bottom edge of decoded images for sub-3-megapixel tiles at an odd tile-component canvas origin — e.g. a DX 2800×2288 image decoded as 2×2 tiles (observed max abs diff ≈ 9823). Root cause: `inverse2DGPUInt32` and `inverse2DCPUInt32` sized the LH/HH high-band as `height/2` (and `width/2`) instead of the canvas-anchored `height − llH` / `width − llW` — at an odd canvas origin the ISO/IEC 15444-1 band partition is uneven. The v8.3 fix corrected the multi-level-fused path but missed these two per-level functions; v10.3.0's `_gpuHTEntropyEnabled` routing change then made them reachable. Pure Swift host-code fix — the Metal kernels were never wrong; `default.metallib` is unchanged. Validated: `V8_3_GPUIDWTRootCauseDiagnostic` 3/3, all IDWT parity/bit-exact suites, the 5 multi-tile self-roundtrips, mandatory commit gate 7/7, cross-codec parity 14/14 (OpenJPEG/OpenJPH/Grok/Kakadu), and the warm cross-codec benchmark within run-to-run noise of v10.9.0 (J2KSwift wins 28/38 encode, 31/38 decode). Encoder and codestream bytes byte-identical to v10.9.0; decoder-only. Also bundles test maintenance — 8 stale-constant test updates and 19 dead-test deletions for de-scoped/parked features (test-only). See [RELEASE_NOTES_v10.9.1.md](Documentation/releases/RELEASE_NOTES_v10.9.1.md).

**v10.9.0** closes the partial-decode arc and fixes a conformance defect. `decodeQuality` was the last of four `notImplemented` partial-decode stubs (after `decodeResolution` v10.4/v10.5, `decodeRegion` v10.6/v10.7, `decodePartial` v10.8). Implementing it uncovered — and fixes — a real bug: `extractTileData`'s packet loop was hardcoded single-layer, so J2KSwift **silently mis-decoded any multi-layer codestream** (confirmed with Kakadu 8.4.1: a 4-layer lossless codestream decoded to wrong pixels, no error raised). v10.9.0 adds `extractTileDataMultiLayer` — the layer-aware packet decode per ISO/IEC 15444-1 B.10 (layer loop, persistent per-precinct inclusion/zero-bit-plane tag-trees, per-block `Lblock`+pass+data accumulation across layers); `extractTileData` routes to it when `qualityLayers > 1`, the single-layer path a separate byte-exact-unchanged branch. **`decodeQuality(layer:L)`** decodes quality layers `0...L` (a lower-bitrate preview); `layer == last` equals `decode()`; `cumulative:false` throws `notImplemented`. `V10_15_MultiLayerDecodeTests` 3/3 PASS: `decode()` of Kakadu 2/3/4-layer lossless codestreams **bit-identical to the original** (the conformance fix); `decodeQuality(layer:L)` **bit-identical to `kdu_expand -layers(L+1)`** for every layer — full cross-codec conformance including lossy truncated reconstructions. Single-layer regression: gate 7/7 + the v10.5–v10.8 partial-decode suites 16/16 PASS — single-layer decode untouched. Codestream bytes byte-identical to v10.8.0; encoder unchanged. `decodeResolution` + `decodeRegion` + `decodePartial` + `decodeQuality` — all four partial-decode APIs now implemented. See [RELEASE_NOTES_v10.9.0.md](Documentation/releases/RELEASE_NOTES_v10.9.0.md) and [V10_15_QUALITY_LAYER_DECODE.md](Documentation/research/V10_15_QUALITY_LAYER_DECODE.md).

**v10.8.0** ships the **`decodePartial` umbrella API**. Arc C exposed four public partial-decode entry points; `decodeResolution` shipped in v10.4.0/v10.5.0 and `decodeRegion` in v10.6.0/v10.7.0, but `decodePartial` was still a `notImplemented` stub. v10.8.0 implements it as the umbrella: one `decodePartial(_:options:)` call taking `J2KPartialDecodingOptions` that composes — `maxResolutionLevel` → true partial-resolution decode (code-block filter + inverse-DWT truncation, 3-8×); `region` → ROI decode (entropy-skip + tile-skip); `components` → component-subset selection (genuinely new — `decodeResolution`/`decodeRegion` never honoured their `components` field); and `maxResolutionLevel` + `region` together → decode at the level, crop the region mapped onto the reduced grid. `maxLayer` is guarded (the decoder packet loop is single-layer — a `maxLayer` that would exclude layers throws `notImplemented`); `earlyStop` is advisory; `decodePartial()` with default options equals `decode()`. Signature changed `throws` → `async throws` (the method was a stub — no real callers). `V10_14_DecodePartialTests` 7/7 PASS — `decodePartial` byte-identical to the single-axis API it delegates to (resolution-only ≡ `decodeResolution`, region-only ≡ `decodeRegion(.direct)`, empty ≡ `decode()`), resolution+region dims/data correct, component selection picks exactly the requested components in order. Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.7.0; decoder-only, no codec hot-path change. `decodeQuality` stays `notImplemented` (single-layer decoder — separate arc). See [RELEASE_NOTES_v10.8.0.md](Documentation/releases/RELEASE_NOTES_v10.8.0.md) and [V10_14_DECODE_PARTIAL.md](Documentation/research/V10_14_DECODE_PARTIAL.md).

**v10.7.0** ships **ROI decode Stage 2 — tile-granular skip**. v10.6.0 Stage 1 skipped the entropy stage for off-region code-blocks but still ran the inverse DWT full-tile. Stage 2: JPEG 2000 tiles decode independently (no inverse-DWT halo crosses a tile boundary), so `decodeRegion(.direct)` now short-circuits any tile whose image rectangle does not overlap the region — `decodeTilePayload` / `decodeTilePayloadGPU` return a zero `DecodedTile`, skipping that tile's entropy, dequant, inverse DWT, colour transform and DC shift entirely. The marquee case is the 16.8 MP MG fixture (encoded as 2×2 tiles): a viewport-zoom ROI within one quadrant skips the other three tiles wholesale. **A/B (M2 release, MG 3518×4784, 256² corner region, 3 of 4 tiles skipped, 7 trials): `.fullImageExtraction` 84.70 ms → `.direct` 49.32 ms (Δ 35.38 ms, 1.72×)** — 1.72× rather than ~4× because the four tiles already decode concurrently, so the win is removed CPU work + reduced core contention. Single-tile fixtures (CT / DX / PX / MR) keep the v10.6.0 Stage 1 entropy-skip win unchanged; sub-tile windowed inverse DWT for them is Stage 3 (future work). `V10_12_ROITileSkipTests` 2/2 PASS (bit-exact across MG at 6 quadrant-placed regions, 1/2/4-tile coverage) + `V10_11_DecodeRegionDirectTests` 4/4 PASS re-run. Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.6.0; decoder-only change, no public signature change. See [RELEASE_NOTES_v10.7.0.md](Documentation/releases/RELEASE_NOTES_v10.7.0.md) and [V10_12_ROI_TILE_SKIP.md](Documentation/research/V10_12_ROI_TILE_SKIP.md).

**v10.6.0** delivers the **ROI half** of the partial-decode arc (v10.4.0 + v10.5.0 shipped the *resolution* half). `J2KDecoder.decodeRegion(_:options:)` with the `.direct` strategy — previously a `notImplemented` stub — now does **true ROI decode**: `DecoderPipeline` gains a `regionOfInterest` and `extractTileData` drops every code-block whose inverse-DWT spatial footprint (band rect scaled by 2^depth + a conservative `8·2^depth` synthesis-filter halo) cannot influence an in-region pixel, skipping the dominant entropy decode stage for them. Mirrors the v10.5.0 Stage B.1 resolution filter with a spatial keep predicate. The inverse DWT still runs full-tile (off-region coefficients stay zero, cropped away); in-region pixels are exact because every block influencing them is retained. **A/B (M2 release, DX 2800×2288, 256² centre region, 7 trials): `.fullImageExtraction` 46.05 ms → `.direct` 33.21 ms (Δ 12.83 ms, 1.39×)**. Also fixes `extractRegion`, which was 8-bit-only — `decodeRegion(.fullImageExtraction)` had been silently corrupting output for every 16-bit medical image. `V10_11_DecodeRegionDirectTests` 4/4 PASS — `.direct` bit-identical to full-decode-then-crop across CT 512² / DX 2800×2288 / MG 3518×4784 (2×2 multi-tile), 7 region positions each (21 ROI decodes). Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. `decodeQuality` stays `notImplemented` (the decoder packet loop is single-layer — a separate arc). Codestream bytes byte-identical to v10.5.0; decoder-only change, no public signature change. See [RELEASE_NOTES_v10.6.0.md](Documentation/releases/RELEASE_NOTES_v10.6.0.md) and [V10_11_ROI_DECODE.md](Documentation/research/V10_11_ROI_DECODE.md).

**v10.5.0** completes the partial-resolution decode arc that v10.4.0 (Phase 1) started. `J2KDecoder.decodeResolution(_:options:)` now does **true partial-resolution decode**: Stage B.1 filters code-blocks by decomposition level before entropy decode (`extractTileData` gains a `maxResolutionLevel` parameter; a level-0 thumbnail of a 16.8 MP MG fixture drops ~99 % of code-blocks); Stage B.2 truncates the inverse DWT at the target level (`levelSubbands53` truncated to the deepest `r` decomposition levels, producing reduced-dimension LL output directly — no downsample step). **Thumbnail decode is 3-8× faster than full decode** (M2 release, 7-trial bench): CT 512² 2.55 → 0.33 ms (7.69×), PX 2459×1316 26.62 → 5.12 ms (5.20×), DX 2800×2288 47.08 → 9.59 ms (4.91×), MG mid 3518×4784 82.48 → 26.81 ms (3.08×). Clean resolution gradient across all 6 levels. Partial decode forces the CPU iDWT path (GPU iDWT truncation is future work); `decode()` / `decodeGPU()` / `decodeWithGPUHT()` unchanged. `decodeResolution(level: 5)` byte-identical to `decode()`. Partial output at level r is the mathematically exact LL band at decomposition level (N − r) per ISO/IEC 15444-1 §F. Smoke tests 3/3 PASS, cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.4.0. See [RELEASE_NOTES_v10.5.0.md](Documentation/releases/RELEASE_NOTES_v10.5.0.md).

**v10.4.0** lands **Phase 1 of partial-resolution decode**: `J2KDecoder.decodeResolution(_:options:)` (previously a `notImplemented` stub since v6.x) now returns a correctly-dimensioned `J2KImage` at the requested resolution level. Phase 1 implementation is decode-then-downsample — runs the full decode pipeline and power-of-2 block-averages the output to the target resolution. Provides a working API surface for downstream consumers (DICOM thumbnail / viewport-zoom workflows) without yet realising the perf upgrade (thumbnail decode still pays full-decode time). The method signature changed from `throws` to `async throws` — existing callers (test-only, since the stub always threw) need to add `await`. **Phase 2** (true partial decode with code-block filter + iDWT truncation, ~13× projected thumbnail speedup) is the next multi-session investment; the API contract stays stable across the Phase 1 → Phase 2 transition. Smoke tests 3/3 PASS (dimensions correct at all 6 levels, `level=5` byte-identical to `decode()`, `upscale: true` reconstructs original dims). Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS. Codestream bytes byte-identical to v10.3.0; decoder-only API addition. See [RELEASE_NOTES_v10.4.0.md](Documentation/releases/RELEASE_NOTES_v10.4.0.md) and [V10_10_PARTIAL_RESOLUTION_PHASE1.md](Documentation/research/V10_10_PARTIAL_RESOLUTION_PHASE1.md).

**v10.3.0** closes the M2 MG mammography decode gap to Kakadu via two coordinated default-flips, both backed by 10-trial variance benches showing reliable wins on MG and pure wash elsewhere. **(1) `DecoderPipeline._gpuHTEntropyEnabled`** flipped ON → OFF — `V10_7_GPUHTEntropyFlagFlipVarianceTests`: **100% of 10 MG trials show flag-OFF winning by +19-27 ms median**, with DX/PX/XA/CT sitting inside ±0.06 ms median (single-tile decode never engages this multi-tile code path). The v6.2.0 D4 default-on was correct at the time but the CPU+NEON HT entropy path got significantly faster post-v10.0.0 D1.5-D — the GPU HT entropy multi-tile path is now slower on MG-class workloads. Opt-in via `J2K_GPU_HT_ENTROPY_DECODE=1` preserved. **(2) `J2KMetalDWT.inverse53IntFusedEnabled`** flipped OFF → ON with the v10.2.0 `inverse53IntFusedPixelThreshold = 12_000_000` retained — only MG-class (≥12 MP per-level) takes the fused single-dispatch H+V IDWT path. Combined v10.3.0 production impact on MG decode: MG small ~76 ms vs Kakadu ~73 ms (**1.04× — tied**), MG mid ~76 ms vs Kakadu ~75 ms (**1.01× — tied**), MG large ~82 ms vs Kakadu ~76 ms (1.08×). Codestream bytes byte-identical to v10.2.0. Cross-codec parity 3/3 PASS, mandatory commit gate 7/7 PASS, `GPUHTEntropyDecodeDefaultOnTests` 2/2 PASS (bit-exact across flag toggle). Full migration notes in [RELEASE_NOTES_v10.3.0.md](Documentation/releases/RELEASE_NOTES_v10.3.0.md).

**v10.2.0** ships an **opt-in fused H+V inverse 5/3 Int Metal kernel** (`j2k_dwt_inverse_53_fused_int_tiled`) gated behind `J2K_METAL_IDWT_FUSED=1` and pixel-threshold `inverse53IntFusedPixelThreshold = 12_000_000`. The kernel collapses the v10.1.0 Phase 2-2-tiled pair (2 horizontal + 1 vertical dispatches per IDWT level) into a single dispatch by holding the H-pass output in threadgroup memory across the V lift — eliminates the colLow/colHigh device-memory round-trip (~2× DRAM saving per level at MG L1). Bit-exact equivalent of the tiled pair (`V10_5_MetalIDWTInverse53FusedParityTests`: 3/3 PASS across small / odd / medical-corpus dimensions including MG 3520×4784). 10-trial interleaved variance bench on M2: MG small +4.68 ms median (70% positive — RELIABLE WIN), MG mid +2.64 ms median (70% positive), MG large +7.67 ms median (50% positive — high std, coin flip per trial). Smaller fixtures (DX/PX/XA/CT) are wash; the 12 MP threshold routes them back through the tiled pair, so the opt-in is safe for production trials. **Default decode behavior unchanged from v10.1.0** — production code path uses the tiled pair unless the env var is set. Codestream bytes byte-identical to v10.1.0. Future v10.3.0 may flip the default to ON pending cross-silicon (M3/M4) variance validation. Cross-codec parity (OpenJPH/Grok/Kakadu) preserved with `J2K_METAL_IDWT_FUSED=1` set (`J2KStrictCrossCodecValidationTests`: 3/3 PASS). Full data set in [V10_5_METAL_IDWT_FUSED_FINDING.md](Documentation/research/V10_5_METAL_IDWT_FUSED_FINDING.md).

**v10.1.0** ships **tiled Metal inverse 5/3 DWT kernels** as the production default — closes the iDWT bottleneck Phase 0 of v10.3-research identified (iDWT became 63% DX / 78% MG of decode wall after v10.0.0's NEON HT entropy default-on). Two new Metal kernels (`j2k_dwt_inverse_53_{horizontal,vertical}_int_tiled`) fuse step 1 + step 2 of the 5/3 lifting in one dispatch per pass via threadgroup memory + barrier, closing the kernel-boundary cost the prior split-step prototype regressed on. Bit-exact equivalent of the scalar kernel by construction. Warm cross-codec bench A/B (M2): every fixture clears v7.4's ≥3 ms acceptance threshold; **MG 3521×4784 large drops 138.91 → 109.58 ms (−21 %)**, **DX 2544×3056 large drops 64.53 → 56.78 ms (−12 %)**, all PX/DX/MG fixtures 7-25% faster. Cross-codec parity (OpenJPH/Grok/Kakadu) preserved. Codestream bytes byte-identical to v10.0.0 (decoder-only optimisation). Opt-out via `J2K_METAL_IDWT_TILED=0`. Full migration notes in [RELEASE_NOTES_v10.1.0.md](RELEASE_NOTES_v10.1.0.md).

**v10.0.0** ships three coordinated wins on Apple M2: (1) **`recommendedDecodeAPI` recalibrated for v9.5.2 post-NEON** — `<500K → .cpu, 500K-15M → .decodeGPU, ≥15M → .cpu`; `.decodeWithGPUHT` removed from auto-routing; substitute-corpus `.auto` row drops 75-80 % on CT/PX/DX; (2) **MG-only 2x2 tile override in `J2KEncodeTilePlanner.auto`** — gate on `(pixels ≥ 12 MP AND min(w, h) ≥ 2400)`; MG encode wall drops 12-25 %; **MG codestream bytes change (MAJOR bump trigger)**; (3) **C+NEON HT decoder default-on** — new `j2knhd_decode_block_ht32` C entry; SWAR-4 MagSgn refill; per-block 1.61× single-thread / 1.55× 12-worker; cross-codec parity preserved; opt-out via `J2K_NEON_HT_DECODE=0`. Full bench numbers and migration notes in [RELEASE_NOTES_v10.0.0.md](RELEASE_NOTES_v10.0.0.md).

**v9.5.2** is a doc-only patch correcting misleading `j2k daemon-install --help` text. The previous help implied the j2kd daemon is the right path for any consumer wanting warm-process speed; v10.0-research Phase 6 measurement on Apple M2 shows that's only true for CLI consumers. SDK consumers calling `J2KEncoder.encode(_:)` / `J2KDecoder.decode(_:)` directly already pay zero cold-start after the first call, while the daemon adds avoidable IPC and result-transfer overhead: about 2-9 ms in isolated measurements and 8-50 ms under sustained batch load. The help text spells out **when to use the daemon (CLI / scripts / PACS tooling)** and **when not to (SDK / in-process consumers)**. Zero codec-core changes; codestream bytes byte-identical to v9.5.1. See [RELEASE_NOTES_v9.5.2.md](RELEASE_NOTES_v9.5.2.md).

**v9.5.1** hotfixes two pre-existing production runtime crashes: (1) `vImage_Buffer.data` dangling-pointer write in `J2KAccelerateDeepIntegration.scale16Bit` + `J2KVImageIntegration.resample` (silent corruption + occasional crash on thumbnail/preview paths); (2) SIGSEGV in `J2KConcurrencyTuning.ScalabilityReport.description` (`%s` + Swift String CVarArg UB under Swift 6.x). Codestream bytes byte-identical to v9.5.0 on every default configuration. See [RELEASE_NOTES_v9.5.1.md](RELEASE_NOTES_v9.5.1.md).

**v9.5.0** closes the v9.5–v9.8 research arc with three production wins: (1) daemon-encode large-fixture closure (DX warm via `j2k --daemon` 146 → 57 ms on M2 — 2.5× vs v9.4.0 warm, 1.8× vs cold same-binary); (2) process-default `J2KQstepCache.shared` for lossy 9/7 batches (M4 DX 99 → 29 ms, –71 %); (3) SIGTRAP fix in `encodeViaQstepSearch` refinement loop. Cross-codec parity matrix all-pass vs OpenJPH 0.27.0 / OpenJPEG / Kakadu HT. See [RELEASE_NOTES_v9.5.0.md](RELEASE_NOTES_v9.5.0.md).

**v9.4.0** ships the first **custom C+NEON HT block encoder** as the production default on Apple Silicon — `J2KCodecNEON` SwiftPM C target, 4-sample-per-quad NEON classifier, batched MagSgn emit. DX warm in-proc 104.5 → 94.9 ms on M4 (–9 %); per-block 20,584 → 7,083 ns (2.91× single-thread). 548+ bit-exact assertions PASS including codestream byte-identity vs OpenJPH/OpenJPEG/Kakadu reference encoders. See [RELEASE_NOTES_v9.4.0.md](RELEASE_NOTES_v9.4.0.md).

**v9.3.0** lands Path B encoder closure on Apple Silicon — 4 production wins (counter false-sharing removal, stack-resident scratch, Data-direct emit, MagSgn batched 4-sample emit). DX warm in-proc 124 → 104.5 ms on M4; Kakadu gap on daemon DX 4.39× → 3.69×. See [RELEASE_NOTES_v9.3.0.md](RELEASE_NOTES_v9.3.0.md).

**v8.1.0** turns the v8.0.0 manual 5-step `j2kd` daemon install into a single command (`j2k daemon-install`). End-to-end CLI gap on DX 2800×2288 closes from 72 ms cold-shot → ~55 ms with the daemon installed (–24 % wall). Codestream bytes byte-identical to v8.0.1; no decoder change. See [RELEASE_NOTES_v8.1.0.md](RELEASE_NOTES_v8.1.0.md) for the full deployment-push details.

**v8.0.1** was a silent-corruption hotfix + GPU multi-tile-per-tile 5/3 IDWT root cause. Fixes the v7.5.1 mg silent-corruption (cross-tile batched HT entropy decode on 16+ MP mammography DICOM fixtures) AND root-causes / fixes the underlying GPU IDWT defect that produced the corruption — two distinct bugs in the GPU multi-tile-per-tile path, both surfacing only on tiles with non-zero canvas origin. `_multiTileBatchedEntropyEnabled` is back default-on; the v7.2.0 cross-tile entropy CB amortisation is restored. **Codestream bytes byte-identical to v8.0.0.** See [RELEASE_NOTES_v8.0.1.md](RELEASE_NOTES_v8.0.1.md) for the full root-cause analysis and the per-tile mismatch progression table.

**v8.0.0** was a major-version product pivot. v7.x targeted cross-platform performance and got within 25 % of OpenJPH and 2× of Kakadu globally. v8.0.0 narrows the product to **Apple Silicon (M-series macOS + A-series iOS/iPadOS)** and uses platform-native primitives (Metal, NSXPCConnection, launchd) to make the Swift SDK path fast for warm-process Apple applications. This is not a universal Kakadu-beating claim: Kakadu still leads sustained CLI runs, decode, and large-image batch workloads.

### Benchmark position — SDK encode vs Kakadu CLI (Apple M2/M4, release mode)

J2KSwift has two different performance shapes:

- **SDK / in-process**: app code calls `J2KEncoder.encode(_:)` or `J2KDecoder.decode(_:)` directly after process warmup. This is the shape DICOMKit and DICOM Studio use for their native codec path.
- **CLI / daemon**: scripts invoke `j2k` once per file. This shape includes process, daemon IPC, and file I/O overhead.

The focused M2 report shows J2KSwift in-process HT-conformant-lossless **encode** beating Kakadu CLI on 4 of 7 medical-corpus fixtures, mostly at <= 1 MP. The sustained cross-host CLI report shows J2KSwift+daemon winning **0 of 38** encode fixtures on both M2 and M4. Decode remains weaker: Kakadu leads the focused decode comparison by about 1.9-4.5x. See [J2KSWIFT_OPTIMAL_VS_KAKADU.md](Documentation/Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md), [CROSS_HOST_M2_M4_inproc.md](Documentation/Benchmarks/CROSS_HOST_M2_M4_inproc.md), [CROSS_HOST_M2_M4_sustained.md](Documentation/Benchmarks/CROSS_HOST_M2_M4_sustained.md), and [DICOM_STUDIO_CLAIM_SCOPE_FINDING.md](Documentation/Benchmarks/DICOM_STUDIO_CLAIM_SCOPE_FINDING.md).

### CLI cold-shot progression — DX 2800×2288 (ms, median of 5)

| version | DX CLI cold | Kakadu gap |
|---|---:|---:|
| v7.5.1 baseline | 134 ms | 4.0× |
| v8 Phase 1 (cold-start elimination) | 91 ms | 2.7× |
| v8 Phase 2 (default-CPU routing) | 103 ms | 2.8× |
| v8 Phase 3 (SIMD CPU IDWT) | 91 ms | 2.7× |
| **v8 Phase 4 (NEON reconstruction default ON)** | **89 ms** | **2.47×** |
| **v8 with `j2kd` XPC daemon installed** | **~55 ms** | **~1.5×** |

The Phase 1-4 CPU optimisations cumulatively close the CLI gap from 4.0× to 2.47×. Installing the optional `j2kd` daemon (Phases 6.3-6.6) closes it further to ~1.5× by amortising Metal cold-start across CLI invocations.

### `j2kd` XPC daemon — warm-CLI single-shot (one-command install)

```bash
swift build -c release --product j2k --product j2kd
.build/release/j2k daemon-install      # one shot: copies binary, writes plist, loads launchd
.build/release/j2k daemon-status       # verify everything is ✓
```

To remove later: `j2k daemon-uninstall`. The install layout is per-user (no sudo) — binary at `~/Library/Application Support/J2KSwift/j2kd`, plist at `~/Library/LaunchAgents/com.raster.j2kd.plist`.

Idle timeout default 10 min; SIGTERM/SIGINT handled cleanly; launchd re-spawns on next client connection. Opt-out per call via `j2k decode --no-daemon`.

See [RELEASE_NOTES_v8.1.0.md](RELEASE_NOTES_v8.1.0.md) for the daemon adoption push details. [RELEASE_NOTES_v8.0.1.md](RELEASE_NOTES_v8.0.1.md) for the silent-corruption hotfix. [RELEASE_NOTES_v8.0.0.md](RELEASE_NOTES_v8.0.0.md) covers the v8.0.0 major-version pivot and the 14 phase-finding documents (`V8_0_0_PHASE_0_BASELINE.md` through `V8_0_0_PHASE_6_6_FINDING.md`). Prior release notes: [v7.5.0](RELEASE_NOTES_v7.5.0.md), [v7.4.0](RELEASE_NOTES_v7.4.0.md), [v7.3.0](RELEASE_NOTES_v7.3.0.md).

## 🖥️ J2KTestApp — GUI Testing Application

J2KTestApp is a native macOS SwiftUI application that provides a complete graphical environment for testing every feature of J2KSwift.

### Building and Running J2KTestApp

```bash
# Build J2KTestApp
swift build --target J2KTestApp

# Run J2KTestApp
swift run J2KTestApp
```

Or open `Package.swift` in Xcode, select the **J2KTestApp** scheme, and press **⌘R**.

### GUI Screens

| Screen | Description |
|--------|-------------|
| **Encode** | Drag-and-drop encoding with configuration panel, presets, and DICOM support |
| **Decode** | File-based decoding with ROI selector, resolution stepper, marker inspector |
| **Round-Trip** | One-click encode/decode/compare with real PSNR/SSIM/MSE metrics |
| **Conformance** | Part 1/2/3/10/15 conformance matrix dashboard |
| **Validation** | Codestream syntax and file format validators |
| **Performance** | Benchmark runner with live charts and regression detection |
| **GPU** | Metal pipeline testing with GPU vs CPU comparison |
| **SIMD** | ARM Neon/Intel SSE verification with utilisation gauges |
| **JPIP** | Progressive streaming canvas with network metrics |
| **Volumetric** | JP3D slice navigation with encode/decode comparison |
| **MJ2** | Motion JPEG 2000 frame playback and quality inspection |
| **Report** | Summary dashboard, trend charts, heatmap, and export |

See [Documentation/TESTING_GUIDE.md](Documentation/TESTING_GUIDE.md) for a complete guide to using J2KTestApp.

## 🎯 Project Goals

J2KSwift provides a modern, safe, and performant JPEG 2000 implementation for Swift applications:

- **Swift 6.2 Native**: Built with Swift 6.2's strict concurrency model — zero data races
- **Fully Functional**: Complete encoder and decoder pipelines with JP3D, MJ2, and HTJ2K
- **Apple-Silicon-First (v8.0.0+)**: macOS 15+ (M-series), iOS 18+ / iPadOS 18+ (A-series). Cross-platform builds (tvOS, watchOS, visionOS, Linux, Windows) still compile but performance is no longer a measurement criterion.
- **Standards Compliant**: Full ISO/IEC 15444-4 conformance across Parts 1, 2, 3, 10, and 15
- **Hardware Accelerated**: ARM Neon SIMD, Intel SSE/AVX, Metal GPU, Vulkan GPU, and Accelerate framework paths where the workload benefits
- **Network Streaming**: JPIP protocol support for efficient 2D and 3D image streaming
- **Modern API**: Async/await based APIs with comprehensive error handling
- **Well Documented**: DocC catalogues for 8 modules, 50+ guides, tutorials, and API documentation
- **High Quality**: broad conformance, interoperability, regression, and GUI test coverage; release claims should cite the exact suite and host that were run
- **CLI Toolset**: Complete command-line tools for encoding, decoding, transcoding, 3D volumetric, JPIP streaming, batch processing, image comparison, format conversion, validation, and benchmarking

## 🚀 Quick Start

### Requirements

- Swift 6.2 or later
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+ / visionOS 1+

### Installation

Add J2KSwift to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "2.1.0")
]
```

Then add the specific modules you need to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2KCodec", package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),
        // Optional: add J2K3D for volumetric JP3D support
        .product(name: "J2K3D", package: "J2KSwift"),
    ]
)
```

### Basic Usage

#### Simple Encoding (v1.2.0)

```swift
import J2KCodec

// Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)

// Encode with default settings
let encoder = J2KEncoder()
let j2kData = try encoder.encode(image)

// Or use a preset
let encoder = J2KEncoder(encodingConfiguration: .lossless)
let losslessData = try encoder.encode(image)
```

#### Simple Decoding (v1.2.0)

```swift
import J2KCodec

// Decode a JPEG 2000 file
let decoder = J2KDecoder()
let image = try decoder.decode(j2kData)

// Access decoded data
print("Decoded image: \(image.width)×\(image.height)")
print("Components: \(image.componentCount)")
```

#### Advanced Encoding with Progress (v1.2.0)

```swift
import J2KCodec

let config = J2KEncodingConfiguration.quality
let encoder = J2KEncoder(encodingConfiguration: config)

let data = try encoder.encode(image) { progress in
    print("\(progress.stage): \(progress.percentage)% complete")
}
```

#### Progressive Decoding (v1.2.0)

```swift
import J2KCodec

// Decode progressively to target quality
let options = J2KProgressiveDecodingOptions(
    mode: .quality,
    targetQuality: 0.8
)
let image = try decoder.decode(j2kData, options: options)

// Or decode a region of interest
let roiOptions = J2KROIDecodingOptions(
    region: CGRect(x: 100, y: 100, width: 200, height: 200),
    strategy: .fullQuality
)
let roiImage = try decoder.decode(j2kData, options: roiOptions)
```

#### HTJ2K Encoding (v1.3.0 - NEW)

```swift
import J2KCodec

// Create encoder with HTJ2K configuration
let config = EncodingConfiguration(
    codingStyle: .htj2k,  // Use High Throughput JPEG 2000
    quality: .highQuality
)

let encoder = J2KEncoder(configuration: config)
let htj2kData = try encoder.encode(image)

// HTJ2K is 57-70× faster than legacy JPEG 2000!
```

#### JP3D Volumetric Encoding (v1.9.0 - NEW)

```swift
import J2KCore
import J2K3D

// Build a J2KVolume from component data
let component = J2KVolumeComponent(
    index: 0, bitDepth: 16, signed: false,
    width: 256, height: 256, depth: 128,
    data: rawVoxelData
)
let volume = J2KVolume(width: 256, height: 256, depth: 128, components: [component])

// Encode losslessly
let encoder = JP3DEncoder(configuration: .lossless)
let result = try await encoder.encode(volume)
print("Encoded \(result.data.count) bytes, \(result.tileCount) tiles")

// Or use HTJ2K for high throughput
let htConfig = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
let htEncoder = JP3DEncoder(configuration: htConfig)
let htResult = try await htEncoder.encode(volume)
// ~5-10× faster than standard JP3D
```

#### JP3D Volumetric Decoding (v1.9.0 - NEW)

```swift
import J2KCore
import J2K3D

let decoder = JP3DDecoder(configuration: .default)
let decoded = try await decoder.decode(encodedData)
let volume = decoded.volume
print("Decoded volume: \(volume.width)×\(volume.height)×\(volume.depth)")
print("Components: \(volume.components.count), voxels: \(volume.voxelCount)")
```

#### Lossless Transcoding (v1.3.0 - NEW)

```swift
import J2KCodec

// Transcode legacy JPEG 2000 to HTJ2K (bit-exact, zero quality loss)
let transcoder = J2KTranscoder()

let legacyCodestream = try Data(contentsOf: legacyFileURL)
let htj2kCodestream = try transcoder.transcode(
    legacyCodestream,
    from: .legacy,
    to: .htj2k
)

// Convert back to verify bit-exact round-trip
let roundTrip = try transcoder.transcode(
    htj2kCodestream,
    from: .htj2k,
    to: .legacy
)
// roundTrip == legacyCodestream (bit-exact!)

// Parallel transcoding for multi-tile images (1.05-2× speedup)
let config = TranscodingConfiguration.default  // Parallel enabled
let parallelTranscoder = J2KTranscoder(configuration: config)
let fastResult = try parallelTranscoder.transcode(multiTileData, from: .legacy, to: .htj2k)
```

#### Writing to JP2 File (v1.2.0)

```swift
import J2KCore
import J2KCodec
import J2KFileFormat

// Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
// ... fill with image data ...

// Write as JP2 file (recommended - includes metadata)
let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: outputURL, configuration: .init(quality: 0.95))

// Or write as raw J2K codestream
let j2kWriter = J2KFileWriter(format: .j2k)
try j2kWriter.write(image, to: codestreamURL)
```

#### Decoding (v1.0 - Fully Functional)

```swift
import J2KCore
import J2KCodec

// Decode from codestream data
let decoder = J2KDecoder()
let decodedImage = try decoder.decode(codestreamData)
```

#### Reading from File (v1.0 - Fully Functional)

```swift
import J2KCore
import J2KFileFormat

// Read any JPEG 2000 format (JP2, J2K, JPX, JPM)
let reader = J2KFileReader()
let image = try reader.read(from: fileURL)

// Access image data
print("Image: \(image.width)x\(image.height), \(image.components.count) components")
```

#### Using Component APIs (Advanced)

For advanced use cases, you can also use individual components directly:

```swift
import J2KCore
import J2KCodec

// 1. Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)

// 2. Apply wavelet transform
let dwt = J2KDWT2D()
let transformed = try dwt.forwardDecomposition(
    image.data,
    width: image.width,
    height: image.height,
    levels: 5
)

// 3. Quantization
let quantizer = J2KQuantizer()
let quantized = try quantizer.quantize(transformed, stepSize: 0.05)

// 4. Entropy coding
let mqCoder = J2KMQCoder()
let encoded = try mqCoder.encode(quantized)

// Result: encoded JPEG 2000 coefficient data
```

## 🔧 Command-Line Interface (CLI)

J2KSwift includes a comprehensive CLI tool (`j2k`) for encoding, decoding, transcoding, and analysing JPEG 2000 images. It also provides OpenJPEG-compatible commands for drop-in replacement.

### Installation

```bash
swift build -c release
# Binary at .build/release/j2k
```

### Command Reference

| Command | Description |
|---------|-------------|
| `encode` | Compress image(s) to JPEG 2000 / HTJ2K |
| `decode` | Decompress JPEG 2000 / HTJ2K image(s) |
| `transcode` | Lossless transcoding between J2K ↔ HTJ2K |
| `info` | Display codestream / file-format metadata |
| `validate` | ISO/IEC 15444-4 conformance validation |
| `benchmark` | Performance benchmarking |
| `encode3d` | Compress volumetric / 3D data (JP3D) |
| `decode3d` | Decompress volumetric / 3D data (JP3D) |
| `jpip server` | Start a JPIP streaming server |
| `jpip client` | Start a JPIP streaming client |
| `batch` | Batch-process files in a directory |
| `compare` | Compare two images (PSNR, MSE, MAE) |
| `convert` | Convert between image formats |
| `compress` | OpenJPEG-compatible compress (opj_compress) |
| `decompress` | OpenJPEG-compatible decompress (opj_decompress) |
| `dump` | OpenJPEG-compatible info/dump (opj_dump) |
| `completions` | Generate shell completions (bash/zsh/fish) |
| `version` | Print version information |

### Encoding

```bash
# Lossless encoding with 5/3 wavelet
j2k encode -i input.png -o output.j2k --lossless

# Lossy encoding with quality factor
j2k encode -i input.png -o output.j2k -q 0.85

# HTJ2K encoding for fast decoding
j2k encode -i input.png -o output.jph --htj2k

# Tiled encoding with custom parameters
j2k encode -i input.tif -o output.j2k --tile-size 512x512 --levels 6 --layers 5

# Encode from DICOM
j2k encode -i scan.dcm -o scan.j2k -q 0.95
```

### Decoding

```bash
# Decode to PNG
j2k decode -i input.j2k -o output.png

# Decode at reduced resolution (half size)
j2k decode -i input.j2k -o output.png --reduce 1

# Decode a specific region
j2k decode -i input.j2k -o region.png --region 100,100,400,400

# Decode specific quality layers
j2k decode -i input.j2k -o output.png --layers 3
```

### Transcoding

```bash
# Transcode J2K to HTJ2K (lossless)
j2k transcode -i input.j2k -o output.jph

# Transcode HTJ2K back to J2K
j2k transcode -i input.jph -o output.j2k
```

### Inspection and Validation

```bash
# Show codestream metadata
j2k info -i image.j2k

# Validate conformance
j2k validate -i image.j2k --profile baseline

# Compare two images
j2k compare -a original.png -b decoded.png

# Run benchmarks
j2k benchmark -i image.png --iterations 10
```

### 3D Volumetric (JP3D)

```bash
# Encode a volume from slice directory
j2k encode3d -i slices/ -o volume.jp3d --slices 128

# Decode and extract specific slices
j2k decode3d -i volume.jp3d -o output_dir/ --slice-range 10-20
```

### JPIP Streaming

```bash
# Start a JPIP server
j2k jpip server --port 8080 --image-dir ./images

# Connect with JPIP client
j2k jpip client --url http://localhost:8080/image.jp2
```

### Batch Processing

```bash
# Batch encode all images in a directory
j2k batch -i ./images/ -o ./encoded/ --mode encode -q 0.9

# Batch decode with parallel processing
j2k batch -i ./encoded/ -o ./decoded/ --mode decode --threads 8
```

### OpenJPEG-Compatible Commands

For users migrating from OpenJPEG, J2KSwift provides drop-in replacements:

```bash
# Compress (same flags as opj_compress)
j2k compress -i input.png -o output.j2k -r 20,10,1 -n 6 -b 64,64

# Decompress (same flags as opj_decompress)
j2k decompress -i input.j2k -o output.png -r 1 -l 3

# Dump codestream info (same flags as opj_dump)
j2k dump -i input.j2k -v
```

#### Compress Flags

| Flag | Description |
|------|-------------|
| `-i` | Input file (PNG, TIFF, BMP, PGM, PPM, RAW, DICOM) |
| `-o` | Output file (J2K, JP2, JPH) |
| `-r` | Compression ratios (e.g., `20,10,1`) |
| `-q` | PSNR values per layer |
| `-n` | Number of resolution levels (default: 6) |
| `-b` | Code-block size (default: 64,64) |
| `-c` | Precinct size |
| `-t` | Tile size |
| `-p` | Progression order (LRCP, RLCP, RPCL, PCRL, CPRL) |
| `-I` | Use irreversible 9/7 wavelet |
| `--htj2k` | Use HTJ2K (Part 15) encoding |
| `-SOP` | Insert SOP markers |
| `-EPH` | Insert EPH markers |
| `-PLT` | Insert PLT markers |
| `-TLM` | Insert TLM markers |

#### Decompress Flags

| Flag | Description |
|------|-------------|
| `-i` | Input file (J2K, JP2, JPH) |
| `-o` | Output file (PNG, TIFF, PGM, PPM, BMP, RAW) |
| `-r` | Reduce factor (0 = full, 1 = half, etc.) |
| `-l` | Number of quality layers to decode |
| `-d` | Decode area (x0,y0,x1,y1) |
| `-t` | Tile index to decode |
| `-force-rgb` | Force output to RGB |
| `-threads` | Number of threads |

### Piping and Stdin/Stdout

```bash
# Pipe from stdin to stdout
cat image.png | j2k encode -i - -o - --format j2k > encoded.j2k

# Chain encode and decode
j2k encode -i image.png -o - | j2k decode -i - -o decoded.png
```

### Shell Completions

```bash
# Generate Bash completions
j2k completions bash > /usr/local/etc/bash_completion.d/j2k

# Generate Zsh completions
j2k completions zsh > ~/.zfunc/_j2k

# Generate Fish completions
j2k completions fish > ~/.config/fish/completions/j2k.fish
```

## 🖥️ J2KTestApp User Manual

J2KTestApp is a native macOS SwiftUI application for testing, validating, and inspecting JPEG 2000 encoding/decoding.

### Running

```bash
swift run J2KTestApp
```

Or open `Package.swift` in Xcode → select the **J2KTestApp** scheme → **⌘R**.

### Encode Screen

1. **Select Input** — drag-and-drop an image (PNG, TIFF, BMP, DICOM) or click **Browse**.
2. **Choose Preset** — select Lossless, Lossy High Quality, Visually Lossless, or Maximum Compression.
3. **Configure** — adjust quality, wavelet type, tile size, decomposition levels, quality layers, progression order, MCT, and HTJ2K toggles.
4. **Encode** — click the **Encode** button (⌘↵). Progress is shown per-stage.
5. **Inspect Results** — view encoded size, compression ratio, encoding time, and per-stage timing.
6. **Compare** — see original vs. encoded side-by-side, overlay, or difference views.
7. **Save** — export the encoded J2K/JP2 file.

Tabs:
- **Single** — encode one image at a time.
- **Compare** — add multiple configurations and compare outputs side-by-side.
- **Batch** — select a folder and encode all images with the current configuration.

### Decode Screen

1. **Open File** — click **Open File…** and select a JP2, J2K, JPX, JPH, or JHC file.
2. **Configure** — set resolution level, quality layer, component channel, and optional ROI.
3. **Decode** — click **Decode** (⌘↵). The decoded image is displayed with actual dimensions.
4. **Inspect Markers** — toggle the **Markers** panel to see all parsed codestream markers (SOC, SIZ, COD, QCD, SOT, etc.) with offsets and descriptions.

### Round-Trip Validation

1. **Generate Test Image** — choose from Gradient, Checkerboard, Noise, Solid Colour, or Lena-Style patterns.
2. **Or Drop Image** — drag-and-drop a real image onto the encode input.
3. **Run Round-Trip** — click **Run Round-Trip** (⌘↵). The pipeline:
   - Encodes the image using the current configuration.
   - Decodes the encoded output back to pixels.
   - Computes PSNR, SSIM, and MSE metrics.
   - Shows pass/fail badges based on quality thresholds.
4. **Compare** — toggle Difference view to see pixel-level discrepancies.
5. **Bit-Exact Badge** — for lossless configurations, verifies exact reconstruction.

### DICOM Support

J2KTestApp can directly load uncompressed DICOM (.dcm) files for encoding to JPEG 2000. This is useful for medical imaging workflows:

1. Drop a DICOM file onto the Encode input area, or use **Browse**.
2. The app extracts pixel data from the DICOM file (supports 8-bit and 16-bit, grayscale and RGB).
3. 16-bit data is automatically windowed and scaled to 8-bit for encoding.
4. Encode as usual — the output J2K/JP2 file is suitable for PACS and DICOM systems.


## ✨ Features

### Implemented in v1.0.0 ✅

#### Core Components
- **Image Representation**: Multi-component images with arbitrary bit depths (1-38 bits)
- **Tiling**: Configurable tile dimensions with boundary handling
- **Memory Management**: Zero-copy buffers, memory pools, optimized allocators
- **I/O Infrastructure**: Bit-level reading/writing, marker parsing, format detection

#### Wavelet Transform (Phase 2 Complete)
- **Filters**: 5/3 reversible (lossless), 9/7 irreversible (lossy)
- **Decomposition**: 1D and 2D transforms, multi-level (up to 32 levels)
- **Tiling Support**: Tile-by-tile processing with proper boundary handling
- **Test Coverage**: 96.1% pass rate (32 known issues in bit-plane decoder)

#### Entropy Coding (Phase 1 Complete)
- **EBCOT**: Embedded Block Coding with Optimized Truncation
- **MQ-Coder**: Arithmetic entropy coding (18,800+ ops/sec)
- **Bit-Plane Coding**: Three coding passes with context modeling
- **Bypass Mode**: Selective arithmetic coding bypass
- **Performance**: Optimized hot paths with inline hints

#### Quantization & Rate Control (Phase 3 Complete)
- **Quantization**: Scalar and deadzone quantization
- **Rate Control**: PCRD-opt algorithm for optimal rate-distortion
- **ROI**: MaxShift method with arbitrary shapes (rectangle, ellipse, polygon)
- **Quality Layers**: Multi-layer generation for progressive decoding

#### Color Transforms (Phase 4 Complete)
- **RCT**: Reversible Color Transform for lossless compression
- **ICT**: Irreversible Color Transform for lossy compression
- **Color Spaces**: RGB, YCbCr, Greyscale, CMYK support
- **Subsampling**: Component-level subsampling

#### File Format (Phase 5 Complete)
- **Formats**: JP2, J2K, JPX, JPM file formats
- **Boxes**: 15+ box types including header, color, palette, resolution
- **Metadata**: ICC profiles, XML, UUID boxes
- **Composition**: Multi-page and animation support (JPX/JPM)
- **Test Coverage**: 100% pass rate for file format operations

#### JPIP Protocol (Phase 6 Complete - Infrastructure)
- **Session Management**: HTTP transport, session lifecycle
- **Request/Response**: Protocol messaging framework
- **Caching**: Client-side precinct-based caching
- **Server**: Multi-client support with bandwidth throttling
- **Note**: Streaming operations await codec integration (v1.1)

#### Advanced Features (Phase 7 Complete)
- **Visual Weighting**: CSF-based perceptual modeling
- **Quality Metrics**: PSNR, SSIM, MS-SSIM
- **Encoding Presets**: Fast, balanced, quality presets
- **Progressive Modes**: SNR, spatial, layer-progressive
- **Extended Formats**: 16-bit images, HDR support, alpha channels

#### Codec Integration (v1.0 Complete ✅)
- **Encoding**: Full `J2KEncoder.encode()` pipeline
- **Decoding**: Full `J2KDecoder.decode()` pipeline
- **File I/O**: `J2KFileReader.read()` and `J2KFileWriter.write()`
- **Round-Trip**: Complete encode→decode workflows
- **Test Coverage**: 1,498 tests, 98.3% passing (25 skipped)

### Future Releases
- **v2.2**: Multi-spectral JP3D, Vulkan JP3D DWT, JPEG XS exploration (complete)
- **v2.3**: JPEG XS full implementation, DICOM metadata enhancements
- **v3.0**: x86-64 SIMD code removal (Apple-first architecture), JPEG XS support

## 📚 Documentation

### Getting Started
- **[README.md](README.md)**: This file — quick start and overview
- **[CHANGELOG.md](CHANGELOG.md)**: Complete version history
- **[RELEASE_NOTES_v2.1.0.md](RELEASE_NOTES_v2.1.0.md)**: Complete v2.1.0 release notes
- **[RELEASE_NOTES_v2.0.0.md](RELEASE_NOTES_v2.0.0.md)**: Complete v2.0.0 release notes
- **[GETTING_STARTED.md](GETTING_STARTED.md)**: Comprehensive introduction
- **[TUTORIAL_ENCODING.md](TUTORIAL_ENCODING.md)**: Step-by-step encoding guide
- **[TUTORIAL_DECODING.md](TUTORIAL_DECODING.md)**: Step-by-step decoding guide
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)**: Migrating from OpenJPEG
- **[MIGRATION_GUIDE_v2.0.md](MIGRATION_GUIDE_v2.0.md)**: Migrating from v1.9.0 to v2.0.0

### API Reference
- **[API_REFERENCE.md](API_REFERENCE.md)**: Complete API documentation
- **[API_ERGONOMICS.md](API_ERGONOMICS.md)**: API design principles
- **Swift-DocC**: Generated documentation (see [DOCUMENTATION_GUIDE.md](DOCUMENTATION_GUIDE.md))

### Technical Documentation
- **[WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md)**: DWT implementation details
- **[ENTROPY_CODING.md](ENTROPY_CODING.md)**: EBCOT and MQ-coder
- **[QUANTIZATION.md](QUANTIZATION.md)**: Quantization strategies
- **[RATE_CONTROL.md](RATE_CONTROL.md)**: PCRD-opt algorithm
- **[COLOR_TRANSFORM.md](COLOR_TRANSFORM.md)**: Color space conversions
- **[JP2_FILE_FORMAT.md](JP2_FILE_FORMAT.md)**: File format specification
- **[HTJ2K.md](HTJ2K.md)**: High-Throughput JPEG 2000 (ISO/IEC 15444-15)
- **[JPIP_PROTOCOL.md](JPIP_PROTOCOL.md)**: Streaming protocol
- **[EXTENDED_FORMATS.md](EXTENDED_FORMATS.md)**: JPX, JPM support
- **[BYPASS_MODE_ISSUE.md](BYPASS_MODE_ISSUE.md)**: Known bypass mode limitation and workarounds

### JP3D Volumetric JPEG 2000 (v1.9.0)
- **[Documentation/JP3D_GETTING_STARTED.md](Documentation/JP3D_GETTING_STARTED.md)**: Quick start guide for JP3D
- **[Documentation/JP3D_ARCHITECTURE.md](Documentation/JP3D_ARCHITECTURE.md)**: Architecture overview (J2K3D, JPIP, Metal, Accelerate)
- **[Documentation/JP3D_API_REFERENCE.md](Documentation/JP3D_API_REFERENCE.md)**: Complete API reference for all JP3D public types
- **[Documentation/JP3D_STREAMING_GUIDE.md](Documentation/JP3D_STREAMING_GUIDE.md)**: JPIP 3D streaming guide
- **[Documentation/JP3D_PERFORMANCE.md](Documentation/JP3D_PERFORMANCE.md)**: Performance tuning guide with benchmark tables
- **[Documentation/JP3D_HTJ2K_INTEGRATION.md](Documentation/JP3D_HTJ2K_INTEGRATION.md)**: HTJ2K usage guide for volumetric encoding
- **[Documentation/JP3D_MIGRATION.md](Documentation/JP3D_MIGRATION.md)**: Migration from 2D JPEG 2000 to JP3D
- **[Documentation/JP3D_TROUBLESHOOTING.md](Documentation/JP3D_TROUBLESHOOTING.md)**: Common issues and solutions
- **[Documentation/JP3D_EXAMPLES.md](Documentation/JP3D_EXAMPLES.md)**: Comprehensive usage examples

### Advanced Topics
- **[ADVANCED_ENCODING.md](ADVANCED_ENCODING.md)**: Encoding techniques
- **[ADVANCED_DECODING.md](ADVANCED_DECODING.md)**: Decoding optimizations
- **[HARDWARE_ACCELERATION.md](HARDWARE_ACCELERATION.md)**: Performance optimization
- **[PARALLELIZATION.md](PARALLELIZATION.md)**: Multi-threading strategy
- **[PERFORMANCE.md](PERFORMANCE.md)**: Benchmarking and profiling

### Development & Testing
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Development guidelines
- **[CONFORMANCE_TESTING.md](CONFORMANCE_TESTING.md)**: Standards compliance
- **[REFERENCE_BENCHMARKS.md](REFERENCE_BENCHMARKS.md)**: Performance baselines
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: Common issues and solutions

### Project Management
- **[DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md)**: Current development status with visual progress
- **[NEXT_PHASE.md](NEXT_PHASE.md)**: Next phase development roadmap (HTJ2K codec & transcoding)
- **[MILESTONES.md](MILESTONES.md)**: 100-week development roadmap (complete!)
- **[ROADMAP_v1.1.md](ROADMAP_v1.1.md)**: Next version plans
- **[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)**: Release process

## 🗺️ Development Roadmap

### Completed: 100-Week Milestone
        print("Cache hit rate: \(cacheStats.hitRate * 100)%")
        print("Cache size: \(cacheStats.totalSize) bytes, entries: \(cacheStats.entryCount)")
        
        // Check if data is cached
        if await session.hasDataBin(binClass: .mainHeader, binID: 1) {
            let dataBin = await session.getDataBin(binClass: .mainHeader, binID: 1)
            print("Retrieved from cache: \(dataBin?.data.count ?? 0) bytes")
        }
        
        // Get precinct cache statistics
        let precinctStats = await session.getPrecinctStatistics()
        print("Precincts: \(precinctStats.totalPrecincts) total")
        print("Completion rate: \(precinctStats.completionRate * 100)%")
        
        // Invalidate cache by bin class
        await session.invalidateCache(binClass: .precinct)
        
        print("Received image: \(image.width)x\(image.height)")
    } catch {
        print("Request failed: \(error)")
    }
}
```

## 📦 Modules

### J2KCore
Core types, protocols, and utilities used by all other modules.

### J2KCodec
Encoding and decoding functionality for JPEG 2000 images.

### J2KAccelerate
Hardware-accelerated operations using platform-specific frameworks (Accelerate on Apple platforms). On non-Apple platforms, software fallback implementations are used automatically.

### J2KFileFormat
File format support for JP2, J2K, JPX, and other JPEG 2000 container formats, including Motion JPEG 2000 (MJ2) creation, extraction, and playback.

### J2KMetal
Metal GPU acceleration for Apple Silicon processors, providing 10–40× performance improvements for wavelet transforms, colour transforms, ROI processing, and quantisation.

### J2KVulkan
Vulkan GPU compute backend for Linux and Windows platforms, with SPIR-V compute shaders and automatic CPU fallback.

### JPIP
JPEG 2000 Interactive Protocol implementation for efficient network streaming, including JP3D 3D streaming with view-dependent progressive delivery.

### J2K3D
JP3D volumetric JPEG 2000 (ISO/IEC 15444-10) encoding, decoding, and streaming. Provides `JP3DEncoder`, `JP3DDecoder`, 3D wavelet transforms, HTJ2K integration, and JPIP 3D streaming. This is an optional module — existing 2D workflows are unaffected.

## 🗓️ Development Roadmap

See [MILESTONES.md](MILESTONES.md) for the detailed 100-week development roadmap tracking all features and implementation phases.

### Current Status: v2.2.0 — Production Ready

> **Encoder Status**: The high-level `J2KEncoder.encode()` API is **fully functional** with ARM Neon SIMD, Intel SSE/AVX, and Metal GPU acceleration.
> 
> **Decoder Status**: The high-level `J2KDecoder.decode()` API is **fully functional** with full ISO/IEC 15444-4 conformance and verified OpenJPEG interoperability.
> 
> **Phase 19 Status**: Multi-spectral JP3D encoding/decoding, Vulkan 3D DWT, and JPEG XS exploration types are **complete**.


**All Phases Complete** (325 weeks):
- ✅ Phase 0–8: Foundation through Production Ready (Weeks 1–100)
- ✅ Phase 9–12: vDSP, JPIP, HTJ2K, Extended Formats (Weeks 101–154)
- ✅ Phase 13–14: Part 2 Extensions, Motion JPEG 2000 (Weeks 155–210)
- ✅ Phase 15–16: JP3D Volumetric Support (Weeks 211–235)
- ✅ Phase 17: Performance Refactoring & Conformance (Weeks 236–295)
- ✅ Phase 18: GUI Testing Application (Weeks 296–315)
- ✅ Phase 19: Multi-Spectral JP3D and Vulkan JP3D Acceleration (Weeks 316–325)

**Current**: v2.2.0 — see [CHANGELOG.md](CHANGELOG.md) for details

## 🧪 Testing

### Test Statistics
- **Total Tests**: 3,100+ across the current project history
- **Passing**: use the latest CI or local run for an exact pass rate; do not treat older README counts as a release guarantee
- **Conformance Tests**: 304 (ISO/IEC 15444-4, Parts 1, 2, 3, 10, 15)
- **Interoperability Tests**: 165 (OpenJPEG bidirectional)
- **Integration Tests**: 200+ (end-to-end, stress, regression)
- **GUI Tests**: 309 (J2KTestApp models and view models)
- **Phase 19 Tests**: 55+ (multi-spectral JP3D, Vulkan JP3D DWT, JPEG XS types)

### Test Coverage by Module
- **J2KCore**: public API and conformance coverage
- **J2KCodec**: codec, ARM Neon, Intel SSE/AVX, and interoperability coverage
- **J2KFileFormat**: JP2/JPH/JHC/MJ2 file-format coverage
- **J2KAccelerate**: vDSP/vImage/BLAS integration coverage
- **J2KMetal**: GPU compute regression coverage
- **J2KVulkan**: SPIR-V compute shader coverage where enabled
- **JPIP**: 2D and 3D streaming coverage
- **J2K3D**: JP3D volumetric coverage

### Running Tests
```bash
# Run all tests
swift test

# Run specific module tests
swift test --filter J2KCoreTests
swift test --filter J2KCodecTests
swift test --filter J2KFileFormatTests
swift test --filter J2KTestAppTests

# Run with coverage
swift test --enable-code-coverage

# Performance tests
swift test --filter J2KBenchmarkTests
```

### J2KTestApp GUI Testing
```bash
# Build and run the GUI testing application (macOS only)
swift run J2KTestApp

# Headless CI mode
j2k testapp --headless --playlist "Quick Smoke Test" --output report.html --format html
```

See [CONFORMANCE_TESTING.md](CONFORMANCE_TESTING.md) for details on testing strategy.

## 🚀 Performance

### Performance vs OpenJPEG (v2.0.0)

| Metric | Apple Silicon | Intel x86-64 |
|--------|--------------|--------------|
| Lossless encode | ≥1.5× faster | ≥1.0× (parity) |
| Lossy encode | ≥2.0× faster | ≥1.2× faster |
| HTJ2K encode | ≥3.0× faster | N/A |
| Decode (all modes) | ≥1.5× faster | ≥1.0× (parity) |
| GPU-accelerated (Metal) | ≥10× faster | N/A |

### Hardware Acceleration
- **ARM Neon SIMD**: Vectorised entropy coding, wavelet lifting, colour transforms
- **Intel SSE/AVX**: SSE4.2 and AVX2 for entropy, wavelets, quantisation
- **Metal GPU**: Optimised DWT shaders, tile-based dispatch, async compute
- **Vulkan GPU**: Cross-platform SPIR-V compute for Linux/Windows
- **Accelerate Framework**: Deep vDSP, vImage, BLAS/LAPACK integration

See [PERFORMANCE.md](PERFORMANCE.md), [Documentation/PERFORMANCE_COMPARISON.md](Documentation/PERFORMANCE_COMPARISON.md), and [Documentation/PERFORMANCE_VALIDATION.md](Documentation/PERFORMANCE_VALIDATION.md) for detailed metrics.

## 🤝 Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For information about our CI/CD workflows and automated testing, see [CI_CD_GUIDE.md](CI_CD_GUIDE.md).

### Areas Needing Help
1. **JPEG XS full implementation** (v2.3 target)
2. **DICOM metadata enhancements** (v2.3 target)
3. **Cross-platform testing** (Windows, Linux ARM64)
4. **Community feedback and real-world usage reports**
5. **Hyperspectral remote-sensing datasets for JP3D validation**

### Development Process
```bash
# Clone the repository
git clone https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift

# Build the project
swift build

# Run tests
swift test

# Run SwiftLint
swiftlint

# Format code (if swift-format installed)
swift format --in-place --recursive Sources Tests
```

## 📄 License

J2KSwift is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

This project represents a 295-week development effort following a comprehensive milestone-based roadmap. Special thanks to:

- The JPEG committee for the JPEG 2000 standard (ISO/IEC 15444)
- Apple's Swift team for Swift 6.2 and the concurrency model
- The open-source community for testing and feedback

## 📞 Support

### Getting Help
- 📖 **Documentation**: Start with [GETTING_STARTED.md](GETTING_STARTED.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/Raster-Lab/J2KSwift/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/Raster-Lab/J2KSwift/discussions)
- 📧 **Security**: Contact maintainers for security issues

### Project Links
- **Repository**: https://github.com/Raster-Lab/J2KSwift
- **Releases**: https://github.com/Raster-Lab/J2KSwift/releases
- **Milestones**: [MILESTONES.md](MILESTONES.md)
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- **Release Notes**: [RELEASE_NOTES_v2.1.0.md](RELEASE_NOTES_v2.1.0.md)

## 📊 Project Status

| Component | Status | Test Coverage | Notes |
|-----------|--------|---------------|-------|
| Core Types | ✅ Complete | 100% | Production ready |
| Wavelet Transform | ✅ Complete | 100% | ARM Neon + Intel SSE/AVX SIMD |
| Entropy Coding | ✅ Complete | 100% | SIMD-accelerated MQ-coder |
| Quantisation | ✅ Complete | 100% | Vectorised quantise/dequantise |
| Colour Transforms | ✅ Complete | 100% | ICT/RCT with SIMD acceleration |
| File Format | ✅ Complete | 100% | JP2/JPX/JPM/J2K/JPH support |
| JPIP Protocol | ✅ Complete | 100% | 2D and 3D streaming |
| Encoder API | ✅ Complete | 100% | ≥1.5–3× faster than OpenJPEG |
| Decoder API | ✅ Complete | 100% | Full Part 4 conformance |
| Hardware Accel | ✅ Complete | 100% | Metal, Vulkan, Accelerate, Neon, SSE/AVX |
| HTJ2K Codec | ✅ Complete | 100% | ≥3× faster on Apple Silicon |
| JP3D Volumetric | ✅ Complete | 100% | ISO/IEC 15444-10 compliant |
| Motion JPEG 2000 | ✅ Complete | 100% | ISO/IEC 15444-3 compliant |
| CLI Tools | ✅ Complete | 100% | Dual British/American spelling |
| **CLI Enhancement** | ✅ Complete | 193 tests | 8 new commands, 3D/JPIP/batch (Phase 21) |
| Conformance | ✅ Complete | 304 tests | Parts 1, 2, 3, 10, 15 |
| **J2KTestApp** | ✅ Complete | 309 tests | GUI testing application (Phase 18) |
| **Multi-Spectral JP3D** | ✅ Complete | 30+ tests | Spectral bands, encoder, decoder (Phase 19) |
| **Vulkan JP3D DWT** | ✅ Complete | 15+ tests | 3D DWT with spectral axis (Phase 19) |
| **JPEG XS Exploration** | ✅ Scaffolded | 10+ tests | ISO/IEC 21122 exploration types (Phase 19) |
| **JPEG XS Codec** | ✅ Complete | 52 tests | J2KXS module, full pipeline (Phase 20) |

---

**J2KSwift** — A standards-focused Swift implementation of JPEG 2000 / HTJ2K
**Status**: See the current-version and benchmark-position sections at the top of this README for the active performance and interoperability claims.
**Next Release**: See [MILESTONES.md](MILESTONES.md) for roadmap

For detailed information, see [CHANGELOG.md](CHANGELOG.md)
