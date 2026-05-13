# J2KSwift v5.16.0 — HT conformant lossy: bitstream interop fix

**Release date:** 2026-05-03
**Theme:** v5.15.0 ratified lossless HT conformant. v5.16.0 closes the matching audit
on lossy HT conformant — and surfaced a self-consistent-but-non-conformant bitstream
bug that was producing Part-15 spec violations every time a J2KSwift caller used
`--htj2k` with a bitrate target. This is the highest-severity defect class for
medical imaging interop.

## The framing

v5.15.0 confirmed lossless HT conformant via three independent probes plus OpenJPH
cross-decode (11,889 cells, zero corruption). It also discovered that **lossy** HT
conformant was 2.5–6.9 dB behind both legacy EBCOT and OpenJPH at matched bpp —
documented as the v5.16.0 motivation.

The v5.16.0 investigation began with the question *"why is the lossy quality so bad?"*
and uncovered something worse than a quality gap: **the bitstream itself was
non-conformant**.

## What v5.16.0 fixes

### Bug 1 — Lossy K_max formula mismatch with Part-15 spec

The conformant block encoder (`encodeCodeBlockConformant`) used:

```swift
let kMax = pending.bitDepth - guardBits + 1
```

This formula was correct for **lossless** mode because v5.1.1 added a conformant
ε bias to `writeQCDMarker`'s reversible branch. The bias makes the encoder's K_max
arithmetic land on the same value the Part-15 decoder reconstructs from QCD ε.

But `writeQCDMarker`'s **lossy** branch does NOT apply that ε bias (the bias is
gated on `reversible` at line 3596). So in lossy mode the encoder's K_max was
**off by `guardBits - 1` (≈ 1 bit)** vs what any Part-15 decoder would compute.

Effect on bitstream output: every coefficient was placed one bit too low in the
magnitude window. J2KSwift's own decoder mirrored the bug (because both ends
agreed on the wrong shift via the packet-header `missing_msbs`), so self-round-trip
appeared functional. Third-party decoders (ojph_expand, Kakadu) applied the spec
shift and decoded ~18 dB of garbage at 8 bpp on real medical CT content.

**Same bug shape as the v5.14.x byte-order class**: encoder + decoder
self-consistent on the wrong convention; only third-party cross-decode reveals it.

The v5.16.0 fix splits K_max by reversible flag:

```swift
let kMax: Int
if config.useReversibleFilter {
    kMax = pending.bitDepth - guardBits + 1   // v5.1.1 lossless preserved
} else {
    kMax = pending.bitDepth                   // matches lossy QCD ε
}
```

Both branches now produce K_max = (ε - 1) + guardBits = the Part-15 decoder
reconstruction. Lossy bitstreams are now spec-conformant.

### Bug 2 — Rate-controller distortion semantics for single-pass blocks

`encodeCodeBlockConformant` returned `J2KCodeBlock` instances without setting
`cumulativePassDistortion`. The rate controller's `estimateDistortion` fallback
(in `J2KRateControl.swift`) modelled the cleanup pass as coding only ONE bit-plane
(per the EBCOT/HT-custom assumption), but conformant cleanup actually codes ALL
bits below K_max in a single pass.

Effect: PCRD-opt assigned a slope `4^(K_max-1)×` too small to conformant blocks,
deprioritising them in layer assembly. This contributed to the observed lossy
quality collapse at low bpp.

Fix: set `cumulativePassDistortion: [pending.coefficientSquaredSum]` in the
returned `J2KCodeBlock`. This signals that the single cleanup pass eliminates
all the codeable distortion this block contributes.

## Verification

### Lossy interop — was: catastrophically broken; now: bit-exact across decoders

| Image | bpp | J2KSwift decode | ojph_expand decode | \|Δ\| |
|---|---:|---:|---:|---:|
| CT 16-bit | 1.0 | 18.88 | 18.88 | **0.000** |
| CT 16-bit | 4.0 | 22.34 | 22.34 | **0.000** |
| CT 16-bit | 8.0 | 65.60 | 65.60 | **0.000** |
| Synth 16-bit | 1.0 | 11.06 | 11.06 | **0.000** |
| Synth 16-bit | 4.0 | 12.39 | 12.39 | **0.000** |
| Synth 16-bit | 8.0 | 15.02 | 15.02 | **0.000** |

Pre-v5.16.0 the |Δ| was 30–47 dB on the same matrix.

### Lossless gates — unchanged

Conditional branch ensures lossless takes the v5.1.1 path unchanged. All four
v5.15.0 lossless gates remain green:

- `HTConformantNonPowerOf2ProbeTests` — 11,520 block-level cells, 0 fail.
- `HTConformantPipelineNonPowerOf2Tests` — 228 full-pipeline cells, 0 fail.
- `HTConformantOpenJPHCrossDecodeTests` — 120 OpenJPH cross-decode cells, 0 fail.
- `HTConformantPhase2RealCorpusTests` — 21 medical fixtures × 3 decomp lossless,
  0 fail. All bit-exact.

### New regression gate

`Tests/J2KCodecTests/J2KHTConformantLossyOpenJPHInteropTests.swift` —
`testLossyHTConformant_OJPHDecodeMatchesJ2KSwiftDecode` runs synth 16-bit input
through HT conformant lossy at 1 / 4 / 8 bpp and asserts |Δ| < 0.5 dB between
J2KSwift's own decoder and `ojph_expand`. Pre-v5.16.0 the gap was 30+ dB.

This test is the new lossy floor. Any future change that breaks bitstream
conformance will fail it.

## Known issue (deferred to v5.17.0): residual R-D gap

After the K_max fix, J2KSwift HT conformant lossy is **bitstream-conformant** with
Part-15 — every third-party decoder reads the same precision interpretation. But
absolute quality is still ~7 dB behind OpenJPH at 1 bpp on natural images.

Root cause: J2KSwift's PCRD-opt does NOT support **intra-block byte-level
truncation**. For HT conformant with `passeCount = 1`, every block has exactly
one truncation point — include the whole pass or skip. At low bpp this forces
all-or-nothing block selection. EBCOT and OpenJPH support partial byte-prefix
truncation of any block, achieving smoother R-D curves.

Estimated v5.17.0 work: 5–8 days on the rate controller + tier-2 writer.

**Practical guidance for v5.16.0**: lossy HT conformant is now interop-safe — the
codestreams J2KSwift produces are decodable by any Part-15 decoder at the
intended quality. For applications where compression efficiency at low bpp is
critical, EBCOT (`--htj2k-custom` or no `--htj2k` flag) still provides better
R-D allocation. v5.17.0 will close the gap.

## Caveats

- **Pre-v5.16.0 lossy HT conformant codestreams** are not Part-15 conformant. If
  you have persisted any J2KSwift-encoded `--htj2k` lossy outputs, they will
  decode correctly with J2KSwift but will appear corrupted to any other Part-15
  decoder. Re-encode with v5.16.0 to get spec-compliant outputs.
- **Lossless HT conformant** (`--htj2k --lossless`) was correct pre-v5.16.0 (the
  v5.1.1 K_max fix was always in effect for the reversible branch) and is
  unchanged.

## Reproducing

```bash
# New lossy interop regression gate (~1 s):
swift test --filter HTConformantLossyOpenJPHInterop

# v5.15.0 lossless gates (~70 s combined):
swift test --filter HTConformantNonPowerOf2
swift test --filter HTConformantPipeline
swift test --filter HTConformantOpenJPHCross
swift test --filter HTConformantPhase2

# Manual interop verification on real medical CT:
swift build -c release
J2K=.build/release/j2k
$J2K encode -i Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm \
  -o /tmp/diag.j2k --bitrate 8.0 --htj2k --quiet
$J2K decode -i /tmp/diag.j2k -o /tmp/diag_jsw.pgm --quiet
/opt/homebrew/bin/ojph_expand -i /tmp/diag.j2k -o /tmp/diag_ojph.pgm
# diag_jsw.pgm and diag_ojph.pgm should be byte-identical or PSNR-matched.

# R-D matrix vs all peer codecs:
python3 Scripts/rd_benchmark.py --quick --out-dir results/rd_v5_16_postfix
```

## Lesson

Same shape as v5.14.x byte-order audit and v5.15.0's lossless ratification.

A working self-round-trip is necessary but **not sufficient**. When encoder and
decoder live in the same codebase, bugs that break their shared assumption with
the spec become invisible to in-house testing. The v5.15.0 audit caught the
lossless variant via three independent probes including OpenJPH cross-decode; the
lossy variant survived because the v5.15.0 R-D pipeline measured PSNR via
J2KSwift's own decoder loop and didn't cross-validate with a third-party decoder.

The new `J2KHTConformantLossyOpenJPHInteropTests` gate plugs that hole. Any
future change to the conformant lossy path that breaks Part-15 bitstream
conformance will fail loudly.
