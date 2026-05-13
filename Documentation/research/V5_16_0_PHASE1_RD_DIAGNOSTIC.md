# v5.16.0 Phase 1 — Lossy HT conformant R-D diagnostic

**Date:** 2026-05-03
**Scope:** Investigate the lossy HT R-D gap surfaced in v5.15.0
([V5_15_0_PHASE3_RD_PARITY.md](V5_15_0_PHASE3_RD_PARITY.md)).

## TL;DR

There were **two stacked bugs**, not one:

1. **Bitstream conformance bug** in lossy K_max computation. Root caused. Fixed in v5.16.0.
   J2KSwift's lossy HT conformant codestreams were **non-conformant with Part-15** —
   any third-party decoder (ojph_expand, Kakadu) would decode them as ~18 dB garbage
   on real medical content while J2KSwift's own decoder mirrored the bug and reported
   ~65 dB. This is a critical interop defect for medical imaging where outputs must
   be readable by any spec-compliant decoder.

2. **Rate-control granularity gap** for single-cleanup-pass blocks. Root caused.
   Deferred to v5.17.0 — needs intra-block byte-level truncation, multi-day work.
   Even with the conformance fix, J2KSwift HT-conf lossy is ~14 dB behind EBCOT and
   ~7 dB behind OpenJPH on the synth corpus at 1 bpp because PCRD-opt can only
   select-or-skip whole single-pass blocks, while EBCOT and OpenJPH support partial
   truncation within a block.

## Investigation trail

### Initial measurement (v5.15.0 Phase 3 baseline)

| Image | bpp | J2KSwift-EBCOT | J2KSwift-HT (conformant) | OpenJPH |
|---|---:|---:|---:|---:|
| synth_8b_512 | 2.00 | 38.57 | 31.48 | 38.26 |
| synth_12b_512 | 2.00 | 34.30 | 27.40 | 34.20 |

Gap: 6–7 dB. Hypothesised cause: rate-control issue.

### Diagnostic 1 — bpp ceiling on real CT (16-bit medical)

Tested at 0.5 / 1 / 2 / 4 / 8 bpp:

| bpp | EBCOT | HT-conf | HT-cust |
|---|---:|---:|---:|
| 0.5 | 25.14 | 18.08 | 22.81 |
| 1.0 | 32.62 | 18.88 | 29.40 |
| 2.0 | 41.14 | 20.04 | 38.51 |
| 4.0 | 53.51 | 22.34 | 49.72 |
| 8.0 | 75.68 | 65.60 | 74.43 |

HT-conf curve was nearly **flat** (18 → 22 dB across 0.5 → 4 bpp) before exploding to
65 dB at 8 bpp. EBCOT and HT-cust monotonically improved. This wasn't a quality
ceiling — output sizes were target-matched. So allocation was wrong somewhere.

### Diagnostic 2 — Cross-codec encode/decode

Encoded a CT image with J2KSwift HT-conf @ 8 bpp, then decoded with both J2KSwift
and `ojph_expand`:

| Pipeline | PSNR @ 8 bpp |
|---|---:|
| J2KSwift HT-conf encode → J2KSwift decode | **65.60 dB** |
| J2KSwift HT-conf encode → `ojph_expand` decode | **18.41 dB** |
| OpenJPH `ojph_compress` → J2KSwift decode | **69.82 dB** |

**Smoking gun.** J2KSwift's encoder produced a bitstream that ONLY J2KSwift's own
decoder could decode. ojph_expand applied a different shift and read garbage.
This was the v5.14.x byte-order bug shape applied to HT lossy: encoder and decoder
self-consistent on the wrong convention.

### Diagnostic 3 — Pinpointing the K_max formula

The encoder at `encodeCodeBlockConformant` used:

```swift
let kMax = pending.bitDepth - guardBits + 1   // (line 2823 pre-v5.16)
let shift = 31 - kMax
let missingMSBs = kMax - 1
```

This formula was added in v5.1.1 to fix the K_max=B+G-1 pixel-0 rollover for **lossless**
inputs. It works because `writeQCDMarker`'s reversible branch emits a conformant ε bias:

```swift
let conformant = config.useHTJ2K && config.htj2kBlockFormat == .conformant
let epsilonBias = conformant ? guardBits : 0
let epsilonConformantAdjust = conformant ? 1 : 0
// ... ε_b = bitDepth + 1 - guardBits  (for conformant lossless)
```

Decoder formula: `K_max = (ε - 1) + guardBits = bitDepth`. Since `pending.bitDepth =
B + G + guardBits - 1`, the encoder's `bitDepth - guardBits + 1` arithmetic lands on
`B + G` — the v5.1.1 widened K_max. **Symmetric, correct, ratified by v5.15.0**.

But the **lossy / irreversible** branch of `writeQCDMarker` does NOT apply the ε bias
(line 3596 gates it on `if reversible`). It writes ε from the actual stepsize:

```swift
let (epsilon, _) = Self.encodeJ2KStepSize(step, rangeBits: rangeBits)
// ...
bandKb = epsilon + guardBits - 1
// (where bandKb = pending.bitDepth)
```

So in lossy mode, decoder reconstructs `K_max = (ε - 1) + guardBits = bandKb`. But
encoder used `K_max = bandKb - guardBits + 1`. **Off by `guardBits - 1` bits — typically 1 bit.**

A 1-bit shift mismatch on every coefficient means the decoder reads each magnitude
half (or double) of what the encoder intended. PSNR pattern matches: ~6 dB per
binary-precision-bit on natural images.

### v5.16.0 fix

Split the K_max formula by reversible flag:

```swift
let kMax: Int
if config.useReversibleFilter {
    kMax = pending.bitDepth - guardBits + 1     // v5.1.1 lossless fix preserved
} else {
    kMax = pending.bitDepth                      // matches lossy QCD ε
}
```

Fix scoped to `encodeCodeBlockConformant` only. `writeQCDMarker`'s lossy branch is
unchanged. J2KSwift's decoder reads `missing_msbs` from the packet header (which
the encoder writes as `kMax - 1`), so self-consistency is preserved.

## Verification

### Interop matrix (after fix)

| Image | bpp | J2KSwift decode | ojph_expand decode | \|Δ\| |
|---|---:|---:|---:|---:|
| CT 16-bit | 1.0 | 18.88 | 18.88 | 0.000 |
| CT 16-bit | 4.0 | 22.34 | 22.34 | 0.000 |
| CT 16-bit | 8.0 | 65.60 | 65.60 | 0.000 |
| Synth 16-bit | 1.0 | 11.06 | 11.06 | 0.000 |
| Synth 16-bit | 8.0 | 15.02 | 15.02 | 0.000 |

**Δ = 0.000 dB** across every cell. Bitstream is now Part-15 conformant for lossy
HT conformant.

### v5.15.0 lossless gates (after fix)

All four passed unchanged:
- `HTConformantNonPowerOf2ProbeTests` — 11,520 block-level cells, 0 fail.
- `HTConformantPipelineNonPowerOf2Tests` — 228 full-pipeline cells, 0 fail.
- `HTConformantOpenJPHCrossDecodeTests` — 120 OpenJPH cross-decode cells, 0 fail.
- `HTConformantPhase2RealCorpusTests` — 21 medical fixtures × 3 decomp lossless,
  0 fail. All bit-exact.

### New regression gate

`Tests/J2KCodecTests/J2KHTConformantLossyOpenJPHInteropTests.swift` —
`testLossyHTConformant_OJPHDecodeMatchesJ2KSwiftDecode` asserts |Δ| < 0.5 dB
between J2KSwift's own decoder and ojph_expand at 1 / 4 / 8 bpp on a 256×256
16-bit synth image. Pre-fix the gap was 30+ dB.

## Remaining R-D gap (deferred to v5.17.0)

After the K_max fix, J2KSwift HT conformant lossy is **bitstream-conformant** with
Part-15 — every third-party decoder reads the same precision interpretation. But
absolute quality is still ~7 dB behind OpenJPH at 1 bpp on natural images.

Root cause for the residual gap: J2KSwift's PCRD-opt does NOT support **intra-block
byte-level truncation**. For HT conformant with `passeCount = 1`, every block has
exactly one truncation point — include the whole pass or skip. At low bpp this
forces all-or-nothing block selection, where EBCOT and OpenJPH can pick partial
byte-prefixes of any block.

OpenJPH's tier-2 packet writer supports byte-level codeblock truncation via
`block_decoder::trim_to`. Porting equivalent logic to J2KSwift is the v5.17.0
motivation. Estimated 5–8 days of work on the rate controller + tier-2 writer.

For v5.16.0, the interop fix is the medical-grade-critical defect; the R-D gap
is a quality concern that affects compression ratio at low bpp targets and is
documented as a known issue.

## Reproducing

```bash
# Full diagnostic flow:
swift build -c release

# Confirm interop on real CT image:
J2K=.build/release/j2k
$J2K encode -i Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm \
  -o /tmp/diag.j2k --bitrate 8.0 --htj2k --quiet
$J2K decode -i /tmp/diag.j2k -o /tmp/diag_jsw.pgm --quiet
/opt/homebrew/bin/ojph_expand -i /tmp/diag.j2k -o /tmp/diag_ojph.pgm
# Verify diag_jsw.pgm and diag_ojph.pgm are byte-identical (or PSNR-matched).

# Run the full lossy interop regression gate:
swift test --filter HTConformantLossyOpenJPHInterop

# Confirm v5.15.0 gates still green:
swift test --filter HTConformantNonPowerOf2
swift test --filter HTConformantPipeline
swift test --filter HTConformantOpenJPHCross
swift test --filter HTConformantPhase2
```

## Lesson

Same-shape lesson as v5.14.x byte-order audit: when encoder and decoder are both
in-house, "self-round-trip works" is a false-positive signal. The third-party
cross-decode test catches what mirror-bugs hide. Lossless conformant got this
audit in v5.15.0 (three independent probes, OpenJPH cross-decode); lossy
conformant didn't, and the bug survived for years until v5.15.0's R-D matrix
forced the question.

The new `J2KHTConformantLossyOpenJPHInteropTests` gate prevents the lossy variant
from regressing into the same shape of bug — any future change that breaks
J2KSwift-encoded → ojph-decoded parity will fail loudly.
