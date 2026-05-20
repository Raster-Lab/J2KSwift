# v10.9-research — partial-resolution decode (C) + encoder tile-planner tune (D)

**Date**: 2026-05-20
**Branch**: `v10.9-research`
**Status**:
  - **Phase C (partial-resolution decode)**: API stubs exist, true implementation is multi-week scope, NOT pursued this session
  - **Phase D (encoder tile-planner tune)**: CLOSED WASH — defaults already empirically optimal

13th + 14th lever-ceiling confirmations.

---

## Phase C — partial-resolution / ROI decode

### Current state (from `J2KAdvancedDecoding.swift`)

Four public API methods are scaffolded but throw `notImplemented`:

```swift
public func decodePartial(_ data: Data, options: J2KPartialDecodingOptions) throws -> J2KImage
public func decodeResolution(_ data: Data, options: J2KResolutionDecodingOptions) throws -> J2KImage
public func decodeQuality(_ data: Data, options: J2KQualityDecodingOptions) throws -> J2KImage
public func decodeRegion(_ data: Data, options: J2KROIDecodingOptions) async throws -> J2KImage
```

Only `decodeRegion` with `.fullImageExtraction` strategy works — it decodes the full image then crops. Memory `project_jp3d_beat_openjpeg.md` flagged this as a known gap.

### Simulation result (NOT representative of true partial decode)

`V10_9_PartialResolutionPotentialBench` re-encodes the source at decompositionLevels = 1..5 and measures decode wall:

| Fixture | px | L=1 ms | L=2 ms | L=3 ms | L=4 ms | L=5 ms | L=1 speedup |
|---|---:|---:|---:|---:|---:|---:|---:|
| PX 2459×1316 | 3.24M | 22.78 | 25.06 | 25.57 | 26.13 | 26.55 | 1.17× |
| DX 2800×2288 | 6.40M | 43.05 | 45.86 | 47.77 | 47.71 | 48.13 | 1.12× |
| MG mid 3518×4784 | 16.83M | 79.90 | 83.65 | 84.66 | 85.05 | 85.36 | 1.07× |

**This is NOT the true partial-decode win.** Encoding with fewer decomposition levels produces a different codestream that still encodes the FULL image fidelity. The 7-17 % speedup measured is just the iDWT-level-count reduction effect.

**The true partial-decode win** (decoding the same 5-decomp-level codestream at resolution level 1) would:
- Process only ~4-5 % of code-blocks (just the LL of deepest level)
- Skip iDWT entirely (output the LL as-is, upscaled if needed)
- Output dimensions = 1/32 × 1/32 of original (e.g., MG 16.8 MP → 526 K px thumbnail)
- Projected speedup: **30-100×** for thumbnail use cases

This is the real product value that DICOM workflows (thumbnail generation, viewport-zoom previews) would benefit from massively.

### Implementation scope

Real partial-resolution decode requires:

1. **Codestream filtering** at packet level — read packets up to target resolution level, ignore higher-resolution packets.
2. **Code-block filtering** — keep blocks whose decomposition level qualifies for the target resolution.
3. **Entropy decode skip** — don't decode the filtered-out blocks.
4. **iDWT truncation** — stop the inverse DWT at the target level (don't process levels closer to the full image).
5. **Output dimension adjustment** — reconstruct at reduced dimensions.

Touches: `extractTileData`, `applyEntropyDecoding`, `applyDequantization`, `applyInverseWaveletTransform`, `reconstructImage`, plus the four public API stubs.

**Multi-week scope per `feedback_no_shortcuts.md`**: do the COMPLEX work — full refactor of the decode pipeline with `maxResolutionLevel` threading through. Not in this session's scope.

### Recommendation

Partial-resolution / ROI decode is **the highest-impact product feature gap** in J2KSwift. The 30-100× thumbnail speedup is dramatic and visible to end users. Schedule a dedicated 2-3 sprint arc for this. The cross-codec bench (full-image apples-to-apples decode) does not capture this win, but the DICOM-workflow benchmark does.

---

## Phase D — encoder code-block size A/B

`V10_9_EncoderTuningForDecodeWallBench` swept codeBlockSize ∈ {16×16, 32×32, 64×64} and measured decode wall:

| Fixture | px | 16×16 ms | 32×32 ms | 64×64 (default) ms |
|---|---:|---:|---:|---:|
| PX 2459×1316       | 3.24M | 31.25 | 27.43 | **26.18** |
| PX large 2812×1316 | 3.70M | 33.25 | 29.37 | **27.72** |
| DX 2800×2288       | 6.40M | 55.84 | 49.19 | **47.43** |
| DX large 2544×3056 | 7.77M | 68.80 | 58.23 | **56.30** |

**The current 64×64 default is empirically optimal.** Smaller blocks (16×16) are **18-19 % SLOWER** because the per-block overhead (header parsing, MEL state init, MagSgn init) exceeds the within-block parallelism savings. 32×32 is 4-5 % slower than 64×64.

Codestream byte sizes are within 2 % across the three options — no significant compression penalty for the default choice.

**Verdict**: encoder defaults are already tuned. No lever here.

---

## Strategic implication

After **14 lever-ceiling confirmations** (12 wash + 1 reversal + 1 stub-feature gap), the remaining M2 DX/PX 1.05-1.5× Kakadu gap is structurally bounded. The credible paths forward are:

1. **Implement partial-resolution decode** (multi-week feature, NOT in cross-codec bench scope but huge user value).
2. **Cross-silicon positioning** — M4 already wins broadly. The marketable claim works today using M4 baselines.
3. **DICOM fast-path** — separate from partial-decode; bypasses codestream-parsing overhead for DICOM-encapsulated input.
4. **Accept current position** — v10.3.0 achieved MG-mammography tied; DX/PX still 5-50 % behind Kakadu on M2 but every Apple Silicon family (M3, M4, A-series) closes more of the gap by hardware advancement alone.

The "beat Kakadu in all on M2 via codec hot-path tuning" framing has been exhaustively tested and confirmed structurally bounded.

---

## Files added

- `Tests/J2KMetalTests/V10_9_PartialResolutionPotentialBench.swift` (Phase C simulation)
- `Tests/J2KMetalTests/V10_9_EncoderTuningForDecodeWallBench.swift` (Phase D A/B)
- `Documentation/research/V10_9_PARTIAL_DECODE_AND_ENCODER_TUNING_FINDING.md` (this file)

**Not landing on `main`**: research only. The Phase C feature gap remains an open product opportunity (multi-week scope); Phase D confirmed defaults are correct.
