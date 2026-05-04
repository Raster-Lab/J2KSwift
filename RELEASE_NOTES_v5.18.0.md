# J2KSwift v5.18.0 — Fixed-qstep mode for HT conformant lossy R-D

**Release date:** 2026-05-04
**Theme:** Bypass PCRD-opt for HT conformant lossy. The single-cleanup-pass FBCOT block model
intrinsically defeats PCRD-opt's per-pass truncation strategy, producing 7+ dB worse R-D than
EBCOT or OpenJPH at matched bitrates. v5.18.0 adds an opt-in mode that matches OpenJPH's
encoder model — fixed quantization step, every block included unchanged.

## The framing

v5.16.0 surfaced the lossy HT conformant R-D gap. v5.16.0's design doc proposed three options:
- **A. Multi-pass conformant emission** — append SigProp/MagRef refinement to the cleanup pass.
- **B. Intra-block byte-level truncation** — extend PCRD-opt to truncate inside a block's bytes.
- **C. Fixed-qstep mode** — bypass PCRD-opt entirely; every block included unchanged.

v5.18.0 ships **Option C** as the safest first iteration. Investigation during implementation
([V5_18_0_DESIGN.md](V5_18_0_DESIGN.md)) revealed Option A doesn't actually help: J2KSwift's
conformant cleanup pass already codes ALL bits per coefficient (FBCOT 1-pass — same as OpenJPH's
default), so refinement passes would be redundant. Option B remains a v5.19.0+ candidate.

Option C is 50 lines of code, additive (new bitrate-mode case), and produces R-D parity with
OpenJPH's encoder when the user supplies a calibrated qstep. It's the right fit for medical
workflows that have known qstep/quality requirements per modality.

## What v5.18.0 adds

### `J2KBitrateMode.fixedQstep(qstep:)` case

```swift
public enum J2KBitrateMode: Sendable, Equatable {
    case constantQuality
    case constantBitrate(bitsPerPixel: Double)
    case variableBitrate(minQuality: Double, maxBitsPerPixel: Double)
    case lossless
    case fixedQstep(qstep: Double)   // v5.18.0
}
```

Semantics:
- Bypasses PCRD-opt rate control entirely.
- `qstep` becomes the encoder's `baseStepSize`; per-subband steps derive via
  `J2KStepSizeCalculator` (LL/HL/LH/HH gain weighting).
- Every codeblock is included unchanged in the output.
- Achieved bpp varies per image — there is no target bitrate.
- Only applies when `useReversibleFilter == false` (lossy 9/7).

### CLI flag `--qstep STEP`

```bash
j2k encode -i input.pgm -o output.j2k --htj2k --irreversible --qstep 40
```

Replaces `--bitrate` for users who want OpenJPH-style deterministic-quality encoding.

### Pipeline integration

Three switch cases in `J2KEncoderPipeline.swift` updated for exhaustiveness:
- `lossyQuantizationParameters` — short-circuits to user-supplied qstep, skipping bpp-aware scaleFactor heuristics.
- `applyRateControl` — fast-path the same way `.lossless` does (every block included).
- `effectiveHTTargetBitsPerPixel` — returns `Double.greatestFiniteMagnitude` (refinement cap disabled).
- `recommendedEBCOTPassLimit` — returns nil (no PCRD pass cap).

Plus `J2KBitrateMode.description` gets a `case .fixedQstep` arm.

## Verification — measured R-D improvement

`Tests/J2KCodecTests/J2KHTConformantFixedQstepRDTests.swift` —
`testFixedQstep_BeatsPCRD_AtMatchedBpp` runs the same image through:
1. Fixed-qstep mode at qstep=40 → measure achieved bpp + PSNR
2. PCRD-opt mode at `.constantBitrate(bitsPerPixel: <achieved>)` → measure PSNR

Asserts the gap is at least +3 dB. Currently measures **+18.69 dB** on synth 512×512 (LCG noise).
Pre-v5.18.0 the gap was 0 (mode didn't exist).

Manual benchmark on radial-gradient synth 8b 512×512 (same image as `Scripts/rd_benchmark.py`):

| Mode | Achieved bpp | PSNR (dB) |
|---|---:|---:|
| `--bitrate 2.0` (PCRD-opt) | 1.977 | **23.15** |
| `--qstep 40` (fixed-qstep) | 2.095 | **29.70** |

**+6.55 dB at matched bpp** on natural-style content.

## Calibration — what qstep to use

For target bitrate, the qstep ↔ bpp relationship depends on image content. A starting calibration
(rough, for natural images at decomp=5):

| Target bpp | qstep (8-bit) | qstep (16-bit) |
|---:|---:|---:|
| 4.0 | ~10 | ~5 |
| 2.0 | ~40 | ~20 |
| 1.0 | ~70 | ~50 |
| 0.5 | ~120 | ~100 |

For known-content workflows (DICOMKit pipeline, modality-specific archives), users should
calibrate per their corpus by sweeping qstep and measuring achieved bpp on representative
samples, then pick the qstep that lands at target bpp.

**Note**: J2KSwift's qstep semantics differ from OpenJPH's by approximately 1000× due to
different gain weighting in `J2KStepSizeCalculator` vs OpenJPH's `subband::set_qstep`. A
J2KSwift qstep of 40 corresponds roughly to an OpenJPH qstep of 0.04 (similar achieved bpp).
v5.18.x or v5.19.0 may add an OpenJPH-compatible qstep calibration mode if users request it.

## Carryover from v5.14–v5.17

All regression gates remain green:
- v5.14.x byte-order matrix (10 tests).
- v5.15.0 lossless conformant non-pow2 floors (4 test suites).
- v5.16.0 lossy interop gate.
- v5.17.0 RGB non-pow2 + DICOMKit CI + PNG filters.
- v5.17.1 stale-test cleanup.

No encoder semantics changed for existing modes. `.fixedQstep` is a new opt-in case; default
behavior of `.constantBitrate` / `.constantQuality` / `.lossless` is unchanged.

## Known issues

- **Calibration burden**: users must pick qstep manually. v5.19.0 candidate: add an outer
  binary-search loop that takes a target bpp and finds the matching qstep via 3–5 encode passes.
- **OpenJPH qstep parity**: J2KSwift qstep and OpenJPH qstep produce different bpp at the same
  numeric value (J2KSwift's is ~1000× scaled). Users transitioning from OpenJPH workflows need
  to re-calibrate. Adding a `.fixedQstepOpenJPH` variant is a v5.19.0 candidate.
- **PCRD-opt R-D gap still measurable for default `.constantBitrate` callers**. Users who don't
  switch to `.fixedQstep` still see the v5.16.0 gap. Option B (intra-block byte-level
  truncation) would close it for them but requires multi-day rate-controller work.

## Reproducing

```bash
# v5.18.0 R-D regression gate (~1 s):
swift test --filter HTConformantFixedQstepRD

# Manual R-D demo on natural-style synth:
swift build -c release
J2K=.build/release/j2k
$J2K encode -i Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm \
  -o /tmp/qstep.j2k --htj2k --irreversible --qstep 40 --quiet
ls -la /tmp/qstep.j2k

# Compare PCRD vs fixed-qstep at matched bpp on your corpus:
$J2K encode -i your_image.pgm -o /tmp/pcrd.j2k --htj2k --irreversible --bitrate 2.0
$J2K encode -i your_image.pgm -o /tmp/qstep.j2k --htj2k --irreversible --qstep 40
# Then decode each and compare PSNR.
```

## Lesson

The v5.16.0 design doc proposed a multi-pass conformant emission as the recommended fix.
Investigation during v5.18.0 implementation revealed that the conformant cleanup pass already
codes every magnitude bit per coefficient — refinement passes would code zero new
information. The actual issue isn't bitstream structure but PCRD-opt's all-or-nothing block
selection mismatching FBCOT's all-or-nothing block emission.

Lesson: design docs predict, code measures. The four-hour investigation that surfaced the
"refinement passes would be redundant" finding was time well spent vs the 3–5 days that would
have been wasted implementing a no-op refinement extension.

Option B (intra-block byte-level truncation) remains the only path that closes the R-D gap
for users who can't switch to `.fixedQstep` (deterministic-bitrate workflows). It's still
multi-day work and properly scoped for a future release once the v5.18.0 fixed-qstep mode is
field-tested.
