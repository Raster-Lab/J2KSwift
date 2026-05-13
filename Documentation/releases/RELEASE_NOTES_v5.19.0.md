# J2KSwift v5.19.0 — Constant-bitrate via qstep search

**Release date:** 2026-05-04
**Theme:** Close the v5.16.0 R-D gap for `.constantBitrate` callers without modifying the
decoder. New mode `.constantBitrateViaQstep` builds on v5.18.0's `.fixedQstep` by adding an
outer binary-search loop on the quantization step. Hits target bpp within tolerance with
`.fixedQstep`'s R-D quality.

## The framing

v5.16.0 surfaced the lossy HT conformant R-D gap. v5.18.0 shipped `.fixedQstep` as the
medical-grade-safe path for users willing to pick a qstep. v5.19.0 was originally planned as
**Option B** (intra-block byte-level truncation in PCRD-opt), but investigation
([V5_19_0_OPTION_B_INVESTIGATION.md](../research/V5_19_0_OPTION_B_INVESTIGATION.md)) revealed Option B
requires decoder-side changes that risk the v5.16.0 ojph_expand interop gate. Pivoted to
**Option D** (binary-search-on-qstep) — bounded scope, no decoder changes, gives users target-bpp
convenience with fixed-qstep quality.

## What v5.19.0 adds

### `J2KBitrateMode.constantBitrateViaQstep(bitsPerPixel:tolerance:maxIterations:)` case

```swift
public enum J2KBitrateMode: Sendable, Equatable {
    case constantQuality
    case constantBitrate(bitsPerPixel: Double)
    case variableBitrate(minQuality: Double, maxBitsPerPixel: Double)
    case lossless
    case fixedQstep(qstep: Double)
    case constantBitrateViaQstep(            // v5.19.0
        bitsPerPixel: Double,
        tolerance: Double = 0.05,
        maxIterations: Int = 8)
}
```

Semantics:
- Outer loop binary-searches `qstep` in log space until achieved bpp matches target within
  tolerance.
- Each iteration is a full encode at a candidate `.fixedQstep` — typically converges in 4–6
  iterations.
- Returns the best-matching iteration's encoded data if `maxIterations` is exhausted.
- Initial qstep guess from a calibrated table per bit-depth, then geometric-mean narrowing of
  [lower, upper] bounds.

### CLI flag `--bitrate-via-qstep BPP`

```bash
j2k encode -i input.pgm -o output.j2k --htj2k --irreversible --bitrate-via-qstep 2.0
```

Same target as `--bitrate 2.0` but uses qstep search internally. ~5× slower than `--bitrate`
but produces R-D matching `--qstep`.

### Implementation (J2KCodec.swift)

`J2KEncoder.encode` checks the mode at entry. For `.constantBitrateViaQstep`, it dispatches to
`encodeViaQstepSearch`:
- Computes target bytes from (totalSamples × targetBpp / 8).
- Initial qstep from `initialQstepGuess(targetBpp:bitDepth:)` calibration table:
  - 8-bit: `qstep ≈ 80 / targetBpp`
  - 12-bit: `qstep ≈ 50 / targetBpp`
  - 16-bit: `qstep ≈ 30 / targetBpp`
- Wide initial bracket `[qstep / 64, qstep × 64]` — log-search narrows quickly.
- Each iteration encodes with `.fixedQstep`, measures bytes, adjusts the bracket.
- Tracks the closest-achieved iteration as fallback if `maxIterations` is exhausted.

## Verification — measured R-D improvement

`Tests/J2KCodecTests/J2KHTConformantConstantBitrateViaQstepTests.swift`:

- `testConstantBitrateViaQstep_HitsTargetAndBeatsPCRDOpt` runs synth 8-bit at target=2.0 bpp:
  - Asserts achieved bpp within tolerance of target.
  - Asserts PSNR ≥ 3 dB above `.constantBitrate` at the same target.
  - **Currently measures Δ = +6.64 dB**, achieved bpp 2.033 vs 2.0 target (1.6% off).
- `testConstantBitrateViaQstepConfigurationPersists` — configuration round-trip smoke test.

Pre-v5.19.0 the gap was 0 dB (mode didn't exist). v5.18.0 introduced `.fixedQstep` (variable
achieved bpp) but didn't help users with strict bitrate compliance.

## Comparison — v5.16.0 → v5.18.0 → v5.19.0

| Mode | Behavior | Target bpp accuracy | R-D vs OpenJPH/EBCOT | Encode time |
|---|---|---|---:|---:|
| `.constantBitrate` (v5.16.0) | PCRD-opt all-or-nothing block selection | ✓ exact | **−7 dB** | 1× |
| `.fixedQstep` (v5.18.0) | User picks qstep; every block kept | ✗ varies per image | matches OpenJPH | 1× |
| `.constantBitrateViaQstep` (v5.19.0) | Outer search on qstep | ✓ within tolerance | **closes the gap** | ~4–6× |

`.constantBitrate` remains the right pick for low-encode-time / streaming workflows.
`.constantBitrateViaQstep` is the right pick for archival / batch workflows where total quality
matters more than encode time.

## Carryover from v5.14–v5.18

All regression gates remain green:
- v5.14.x byte-order matrix.
- v5.15.0 lossless conformant non-pow2 (4 test suites).
- v5.16.0 lossy interop gate (ojph_expand cross-decode).
- v5.17.0 RGB non-pow2 + DICOMKit CI + PNG filters.
- v5.17.1 stale-test cleanup.
- v5.18.0 fixed-qstep R-D regression.

No encoder/decoder semantics changed. `.constantBitrateViaQstep` is purely an outer loop on top
of v5.18.0's `.fixedQstep` mode.

## Known issues / future work

- **Convergence on extreme bpp**: at very low (< 0.1 bpp) or very high (> 8 bpp) targets, qstep
  response is non-monotonic at the boundary and the search may not converge within the tolerance.
  In that case the encoder returns the closest-achieved iteration — typically still better R-D
  than `.constantBitrate` for the same target.
- **Calibration tuning**: the initial qstep guess is rough (designed to be within ~50% of
  converged); the search burns 2–3 extra iterations beyond what an ideal calibration would.
  Tuning the calibration table per modality can save iterations for known-content workflows.
- **Encode time**: 4–6× single-encode cost. Not suitable for real-time / streaming.

## Reproducing

```bash
# v5.19.0 R-D regression gate (~1.5 s):
swift test --filter HTConformantConstantBitrateViaQstep

# Manual demo on real medical CT:
swift build -c release
J2K=.build/release/j2k
$J2K encode -i Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm \
  -o /tmp/v19_via_qstep.j2k --htj2k --irreversible --bitrate-via-qstep 2.0
$J2K encode -i Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm \
  -o /tmp/v19_pcrd.j2k --htj2k --irreversible --bitrate 2.0
ls -la /tmp/v19_via_qstep.j2k /tmp/v19_pcrd.j2k
# Decode each and compare PSNR — via_qstep should be 5–10 dB higher.
```

## Lesson

Two design pivots in two releases:
- **v5.18.0**: pivoted from Option A (multi-pass conformant) when investigation showed the
  conformant cleanup pass already codes every magnitude bit per coefficient.
- **v5.19.0**: pivoted from Option B (intra-block truncation) when investigation showed
  decoder-side semantics (0xFF padding, not zero) would corrupt truncated regions.

Both pivots produced honest, shippable, measured wins. v5.18.0 added user-deterministic-qstep
mode (+6.55 dB on natural content vs PCRD-opt). v5.19.0 added user-deterministic-bpp mode with
the same R-D quality (+6.64 dB on synth content vs PCRD-opt).

The remaining v5.16.0 R-D gap is now closed for users willing to either pick a qstep
(v5.18.0) or accept ~5× encode time (v5.19.0). The pure `.constantBitrate` callers who can't
pay either cost retain the v5.16.0 behavior; closing it for them strictly requires Option B's
decoder changes, deferred to v5.20.0+ if user demand justifies it.
