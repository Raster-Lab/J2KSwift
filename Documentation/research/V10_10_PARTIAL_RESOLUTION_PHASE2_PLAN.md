# v10.10-research Phase 2 plan — true partial-resolution decode

**Status**: PLANNED (Phase 1 already shipped as v10.4.0)
**Scope**: multi-session (2-3 sprints estimated)
**Projected win**: ~13× speedup on thumbnail decode (MG-class fixtures)

---

## Phase 1 vs Phase 2

| | Phase 1 (v10.4.0 shipped) | Phase 2 (planned) |
|---|---|---|
| `decodeResolution` returns | correctly-dimensioned image | correctly-dimensioned image |
| Implementation | full decode + power-of-2 downsample | code-block filter + iDWT truncation |
| Thumbnail decode time | ~85 ms (MG, full-decode cost) | ~5 ms (projected) |
| API stability | ✓ stable | ✓ same API (internal change only) |

Phase 1 → Phase 2 transition is purely internal: downstream callers don't need code changes.

## Implementation strategy — three landing options

The Phase 2 work spans multiple stages. Three possible ways to land it:

### Option A: monolithic single PR

One large PR that touches all 15+ call sites at once. High review burden, but the change-set is internally consistent.

### Option B: staged landing — entropy filter then iDWT truncation (recommended)

Land in two PRs as separate v10.5.0 + v10.5.1 (or v10.5.0 + v10.6.0):

**Stage B.1**: code-block filter only.
- Add `maxResolutionLevel` parameter to `extractTileData`.
- Filter blocks: keep `block.level == 0 || block.level > (N - r)`.
- Entropy decode runs on the filtered subset — saves the dominant decode stage.
- iDWT still runs all levels (with zero LH/HL/HH for filtered levels — produces full-dim output that's then downsampled by Phase 1).
- Drop-in: keep Phase 1's downsample as fallback for non-decodeResolution code paths.
- **Estimated win**: ~50-70 % of full speedup (entropy is the dominant stage; iDWT is ~half of remaining).

**Stage B.2**: iDWT truncation.
- Add `maxResolutionLevel` parameter to `applyInverseWaveletTransform`.
- Truncate `levelSubbands53` to first `r` elements before calling `inverseTransformMultiLevel53`.
- The existing iDWT naturally does fewer steps with fewer levels.
- Output reduced-dim spatial data; thread dims through reconstructImage.
- Drop the Phase 1 downsample fallback.
- **Estimated win**: completes the projected ~13× speedup.

### Option C: feature-flag staged landing

Same code as Option B, but behind opt-in env flag (`J2K_PARTIAL_DECODE_TRUE=1`). Default OFF. Lets early adopters validate before flipping default.

**Recommendation**: Option B. Phased commits land win incrementally; B.1 alone gets most of the benefit.

## Detailed file touch list

### Stage B.1 (entropy filter)

| File | Change |
|---|---|
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | `extractTileData` gains `maxResolutionLevel: Int?` param; filter blocks before return |
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | `decodeSingleTile` accepts + forwards param |
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | `decodeSingleTileGPU` accepts + forwards param (GPU path) |
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | `decodeMultiTile` + `decodeMultiTileGPU` + `decodeMultiTileGPUBatched` accept + forward param |
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | top-level `pipeline.decode` accepts + forwards (internal API) |
| `Sources/J2KCodec/J2KCodec.swift` | `J2KDecoder.decodeResolution` calls internal partial-decode path |
| `Sources/J2KCodec/J2KAdvancedDecoding.swift` | replace `decodeResolution` body to call internal partial path |
| `Tests/J2KCodecTests/V10_10_PartialDecodeEntropySkipTests.swift` (NEW) | parity gate vs decode-then-downsample reference + perf bench |

### Stage B.2 (iDWT truncation)

| File | Change |
|---|---|
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | `applyInverseWaveletTransform` accepts `maxResolutionLevel`; truncates `levelSubbands53` |
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | `applyInverseWaveletTransformGPU` same |
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | `reconstructImage` accepts reduced dims |
| `Sources/J2KCodec/J2KAdvancedDecoding.swift` | remove Phase 1 downsample fallback; output already correctly sized |
| `Tests/J2KCodecTests/V10_10_PartialDecodeIDWTTruncationTests.swift` (NEW) | parity gate vs Stage B.1 reference + perf bench (target ~13× MG thumbnail) |

## Bit-exact contract (critical)

A TRUE partial-resolution decode at level r is **NOT equivalent to full
decode + downsample**. It produces the LL band at decomposition level
(N-r), which is the mathematically correct partial reconstruction per
ISO/IEC 15444-1 §F.4.

The Phase 1 downsample is a CONVENIENT-BUT-WRONG approximation that
matches in DC content but differs in high-frequency content.

For Phase 2 to ship, the bit-exact contract should be established
against:

1. **OpenJPEG** `opj_decompress -r <reduction-factor>` — most common
   reference; `-r N` means decode at full / 2^N.
2. **OpenJPH** `ojph_expand` — recent versions support resolution-level
   arguments.
3. **Kakadu** `kdu_expand` with `-resolution_level` or `-reduce`.

Cross-codec parity at each resolution level (0..N) is the gate for
Phase 2 default-on shipment. If implementations disagree (likely on
boundary rounding), document the convention J2KSwift chose and the
delta vs each reference.

## Projected win confirmation strategy

Before shipping each Stage, re-run the v10.10 simulation
(`V10_9_PartialResolutionPotentialBench`) to confirm the actual
speedup vs the projection. If Stage B.1 lands only 20-30 % (instead
of 50-70 %), reconsider Stage B.2 architecture.

## Phase 3 — beyond partial-resolution decode

Once Phase 2 lands, the same threading enables:

- `decodeRegion` with `.direct` strategy (ROI without full decode).
- `decodePartial` with combined region + resolution + components.
- `decodeQuality` with `maxLayer` (skip refinement passes).

Each is its own arc but the foundation (parameter threading through
the decoder pipeline) is shared.

## Sequencing options for the user

1. **Commit to Phase 2 now**: dedicated 2-3 sprint arc starting next
   session. Other work pauses.
2. **Phase 2 in parallel with other work**: lower velocity but keeps
   other arcs moving. Phase 2 ships in 4-6 sessions.
3. **Defer Phase 2**: v10.4.0 unblocks the API surface today; Phase 2
   stays planned for when explicit user demand justifies the
   investment.

The Phase 1 → Phase 2 API stability guarantee means deferring carries
no downstream-breaking cost.

---

## Files added (this session)

- `Documentation/research/V10_10_PARTIAL_RESOLUTION_PHASE2_PLAN.md` (this file)

## Status

**v10.4.0** (Phase 1) shipped to main 2026-05-20 at commit `6518b58`.
GitHub release live, `release/v10.4.0` branch created, release.yml
workflow SUCCESS.

**Phase 2** is planned but not started. The v10.10-research branch
holds Phase 1 (`ef1ab53`) + this plan doc. A future session will
branch from v10.10-research, implement Stage B.1, ship as v10.5.0,
then Stage B.2 as v10.6.0.
