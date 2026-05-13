# v5.18.0 Design — Closing the HT conformant lossy R-D gap

**Date:** 2026-05-03 (overnight investigation)
**Status:** Design phase only. No code changes yet — work pending user review.
**Predecessor:** v5.16.0 surfaced this gap; v5.17.0 added orthogonal medical-grade hardening.

## TL;DR

Three viable approaches, with very different scopes:

| Option | Scope | Effort | R-D delta | Risk |
|---|---|---:|---:|---:|
| **A. Multi-pass conformant emission** | Medium | 3–5 days | Closes most of the 7 dB gap | Medium — adds a new bitstream variant |
| **B. Intra-block byte-level truncation** | Large | 5–8 days | Likely closes 5+ dB | High — touches PCRD-opt + tier-2 |
| **C. Fixed-qstep mode (OpenJPH-style)** | Small | 1–2 days | Matches OpenJPH directly when bitrate target isn't strict | Low — additive behind a flag |

Recommendation: ship **Option A** as v5.18.0 (best quality outcome). Implement **Option C** as v5.17.x if a quick interim is needed before v5.18.0 lands. Defer **Option B** unless A can't close the gap.

## Investigation findings (overnight)

### Finding 1 — OpenJPH HEAD has NO rate control
Inspected `/tmp/openjph_src/src/core/codestream/`. `ojph_compress` only takes `-qstep` for lossy, no
`-bitrate`. The encoder picks one quantization step, encodes once, achieves whatever bpp falls out.
Quality matches J2KSwift-EBCOT in our R-D matrix because OpenJPH's qstep choice happens to land near
the optimal R-D operating point for natural images.

This means: **OpenJPH's good R-D performance isn't the result of clever rate control. It's the
result of skipping rate control entirely and using a well-calibrated qstep.**

### Finding 2 — J2KSwift's HT-conformant single-cleanup-pass cannot match EBCOT's PCRD-opt granularity
At 2.0 bpp on 8-bit synth (rd_benchmark.py):
- J2KSwift-EBCOT: 38.57 dB (PCRD picks partial passes per block)
- J2KSwift-HTcustom: 35.81 dB (multi-pass HT, PCRD picks full passes per block)
- J2KSwift-HT: 31.48 dB (single cleanup pass per block, PCRD all-or-nothing)
- OpenJPH: 38.26 dB (no rate control, fixed qstep)

The HT-conformant single-pass model loses ~7 dB to multi-pass alternatives. The cause is granularity,
not bitstream conformance.

### Finding 3 — Part-15 spec ALLOWS multi-pass conformant blocks
Reading `ojph_precinct.cpp:430-465` confirms OpenJPH's bitstream supports `num_passes` from 1 to 100+.
Single cleanup is just the OpenJPH encoder default for FBCOT scalar mode. The spec does NOT mandate
single-pass; it mandates that whatever passes are emitted follow the Part-15 layout.

This is the crux. **J2KSwift can emit conformant multi-pass blocks** (the way `.custom` already
does), it just currently chooses not to.

## Options in detail

### Option A — Multi-pass conformant emission (recommended for v5.18.0)

Currently J2KSwift has two HT paths:
- `.conformant` — single cleanup pass; OpenJPH-decodable; `passeCount = 1`.
- `.custom` — cleanup + refinement passes (J2KSwift-private layout); NOT OpenJPH-decodable.

Option A merges the multi-pass emission of `.custom` into the `.conformant` path:
1. Emit cleanup pass exactly as today (already conformant).
2. Optionally append SigProp / MagRef refinement passes per bit-plane below `topBitPlane`.
3. Update tier-2 packet header to write `num_passes > 1` when refinement was emitted.

This is what OpenJPH's bitstream expects. The decoder side (J2KSwift's own + OpenJPH) already
handles `num_passes > 1` in conformant mode (verified: `ojph_codeblock_fun.h:74-78`).

Code touchpoints:
- `J2KEncoderPipeline.swift:encodeCodeBlockConformant` — extend to emit refinement.
  Reuse the refinement code from `encodeCodeBlockHTJ2K` (the `.custom` path uses
  `htEncoder.encodeFusedRefinementDirect` already).
- `J2KEncoderPipeline.swift:writePacketHeader` (or similar tier-2 surface) — encode
  `num_passes` per the spec UVLC tree (already implemented for `.custom`).
- `cumulativePassDistortion` — set per-pass (not the v5.16.0 single-entry hack).
  Reuse the refinement-distortion tracking from the `.custom` path.

Tests:
- Existing `HTConformantLossyOpenJPHInteropTests` verifies cross-decode matches J2KSwift decode at
  matched bpp targets. This stays as the conformance gate.
- New: lossy R-D regression matrix asserting J2KSwift-HT lossy ≥ OpenJPH − 0.3 dB at 0.5 / 1.0 /
  2.0 bpp on synth + medical corpus.

Pros:
- Closes the main R-D gap (likely brings HT-conformant lossy up to ~36 dB on synth at 2 bpp,
  within ~2 dB of EBCOT).
- No encoder semantics change for lossless conformant — only adds refinement to lossy path.
- Spec-conformant — OpenJPH and other Part-15 decoders read it without modification.

Cons:
- 3–5 days of work touching the encoder pipeline + tier-2 writer.
- Risk of regressing the v5.16.0 lossy interop gate if `num_passes > 1` packet-header encoding
  has bugs; mitigation is to test `ojph_expand` decode at every bit-rate.
- Does NOT match OpenJPH's PSNR exactly (OpenJPH uses single cleanup; multi-pass + PCRD-opt is
  technically a different operating point).

### Option B — Intra-block byte-level truncation

Originally proposed in v5.15.0 → v5.16.0 plan, before discovering the K_max bitstream bug.

In OpenJPH's *spec*, codeblock data within a packet can be truncated mid-stream — the decoder
will simply read fewer bytes and ignore later bit-planes. Implementing this in J2KSwift PCRD-opt
would let it choose any byte prefix of any block as a truncation point.

Code touchpoints:
- `J2KRateControl.swift:formLayerPCRDOpt` — extend the slope iteration to consider partial-block
  byte counts, not just whole-pass counts.
- Tier-2 writer — emit truncated block bytes and update the per-block byte count.
- `cumulativePassDistortion` — needs per-byte (or per-coefficient-row) granularity, not per-pass.

Pros:
- Could match EBCOT's PCRD-opt R-D quality.
- Still only one pass per block (no bitstream extension).

Cons:
- 5–8 days of work in the rate controller's hot path.
- Distortion modeling for partial-cleanup-pass truncation is non-trivial — need either an
  empirical model or a way to compute actual per-byte distortion reduction.
- Risk of regressing every existing PCRD-opt code path.

### Option C — Fixed-qstep mode (OpenJPH-style)

Add a new bitrate mode `.fixedQstep(Double)` that bypasses PCRD-opt entirely and uses the user-
provided quantization step directly. Mirrors OpenJPH's encoder model.

Code touchpoints:
- `J2KEncodingConfiguration` — add `.fixedQstep(qstep: Double)` case to `J2KBitrateMode`.
- `J2KEncoderPipeline.swift:applyRateControl` — short-circuit for `.fixedQstep`; include all
  blocks unconditionally with their natural full-precision encoding.
- `lossyStepSize` — return the user-provided qstep when `.fixedQstep` is active.

Pros:
- Smallest possible scope. Additive — existing rate-control paths unchanged.
- Matches OpenJPH's R-D operating point exactly when calibrated qsteps are used.
- Useful for downstream consumers (DICOMKit) that already know the right qstep for their content.

Cons:
- Doesn't help users who specify `--bitrate X` (they still go through PCRD-opt).
- Per-image qstep calibration is the user's responsibility, or J2KSwift's if it implements a
  qstep-search outer loop (which would be Option C+).

## v5.18.0 recommendation

Ship Option A as v5.18.0. The work is bounded (3–5 days), the deliverable is concrete (close the
R-D gap to within 2 dB of EBCOT/OpenJPH), and it doesn't touch the rate controller (which has
many test consumers).

Option C can ride along in v5.18.0 as a side item if there's spare day — it's small and useful.

Option B is reserved for v5.19.0 in case Option A's gap-closure isn't sufficient for low-bpp
workloads (~0.5 bpp regime).

## Implementation skeleton for Option A

```swift
// J2KEncoderPipeline.swift — extended conformant encoder
private func encodeCodeBlockConformant(_ pending: PendingCodeBlock) throws -> J2KCodeBlock {
    // ... existing K_max + maxAbs + cleanup-pass code unchanged ...

    let (ms, mel, vlc) = HTBlockEncoderConformant.encode(...)
    let cleanupBlockBytes = try HTBlockLayoutConformant.assemble(magsgn: ms, mel: mel, vlc: vlc)

    // NEW: optionally emit refinement passes for the bit-planes below topBitPlane.
    var allPassData = Data(cleanupBlockBytes)
    var passSegmentLengths = [cleanupBlockBytes.count]
    var cumulativePassBytes = [cleanupBlockBytes.count]
    var cumulativePassDistortion: [Double] = [pending.coefficientSquaredSum]
    var totalPasses = 1

    if !config.lossless {
        let topBitPlane = ...  // computed from maxAbs
        let lowestPlane = max(0, topBitPlane - recommendedRefinementPlanes)
        for bp in stride(from: topBitPlane - 1, through: lowestPlane, by: -1) {
            let (sigPropBytes, magRefBytes, sigPropDistortion, magRefDistortion) =
                HTBlockEncoderConformant.encodeRefinement(
                    coefficients: pending.coefficients,
                    cleanupSigPacked: ...,
                    bitPlane: bp,
                    output: &allPassData)
            guard sigPropBytes > 0 || magRefBytes > 0 else { break }
            totalPasses += 2
            // ... append per-pass byte / distortion tracking ...
        }
    }

    return J2KCodeBlock(
        ...,
        passeCount: totalPasses,
        cumulativePassBytes: cumulativePassBytes,
        cumulativePassDistortion: cumulativePassDistortion,
        ...)
}
```

The `encodeRefinement` static would need to be added to `HTBlockEncoderConformant` (currently
the refinement code lives in `HTBlockEncoder` for `.custom`). Mostly mechanical refactor.

Tier-2 packet writer already handles `num_passes > 1` for `.custom`; just needs to be extended
to apply the same logic for `.conformant`.

## Acceptance criteria for v5.18.0 (Option A)

1. Lossy HT conformant matches OpenJPH within 0.5 dB at matched bpp on synth_8b/12b/16b.
2. Lossy HT conformant matches OpenJPH within 1.0 dB at matched bpp on real medical CT @ 1/2/4 bpp.
3. v5.16.0 lossy interop gate (ojph_expand cross-decode) remains green.
4. v5.15.0 + v5.17.0 lossless gates remain green.
5. Bitstream remains valid Part-15 — OpenJPH `ojph_expand` decodes all v5.18.0 outputs.

## Risks

- **Bitstream conformance at `num_passes > 1`**: J2KSwift's tier-2 writer already handles this
  for `.custom` but with a different layout. Verify the `.conformant` packet header encoding matches
  OpenJPH spec (Part-15 §B.10.7) for the multi-pass case.
- **Distortion model accuracy**: refinement-pass distortion tracking in the `.custom` path uses a
  reconstruction-error model (line 3034-3043). The same model should work for `.conformant` since
  the underlying coding semantics are identical.
- **Hot-path performance regression**: refinement encoding adds CPU work per block. Profile after
  implementation to confirm GPU HT path stays competitive (the GPU work was for `.custom`-style
  blocks; same kernels should apply).

## Files touched (estimated)

| File | Change | Lines (est.) |
|---|---|---:|
| `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift` | Add `encodeRefinement` | +200 |
| `Sources/J2KCodec/J2KEncoderPipeline.swift` | Extend `encodeCodeBlockConformant` | +50 |
| `Sources/J2KCodec/J2KTier2Coding.swift` | Verify `num_passes > 1` packet encoding | +0 to +50 |
| `Tests/J2KCodecTests/J2KHTConformantLossyRDRegressionTests.swift` | New regression matrix | +150 |
| Memory + RELEASE_NOTES | Documentation | +200 |

Total: ~600–700 lines net. Bounded.

## Next steps (overnight)

This document is the deliverable for tonight's investigation. The actual implementation should
happen in a fresh session with the user's confirmation, since:

1. It touches encoder semantics — needs the user's review for correctness vs efficiency tradeoffs.
2. It introduces a new bitstream variant — needs explicit signoff before merging to main.
3. The Part-15 multi-pass packet-header layout is subtle; a fresh-eyes review by the user reduces
   the chance of a same-shape bug as v5.16.0.

Tonight's overnight work after this doc:
- Run extensive verification of v5.17.0 (full test suite minus benchmarks).
- Investigate Option C as a possible v5.17.x patch.
