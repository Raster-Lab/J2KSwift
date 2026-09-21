# Entropy integrity thresholds — calibration

How `J2KIntegrityThresholds` got its numbers, and what would invalidate them.

## The problem

The MQ arithmetic decoder of ISO/IEC 15444-1 Annex C **cannot fail**. It is a total
function: every bit pattern decodes to some symbol sequence, and once its segment is
exhausted `BYTEIN` is *defined* to feed `0xFF` indefinitely. Corrupt entropy bytes
therefore produce a plausible-looking wrong image, with no error raised anywhere.

Before this work the decoder had three content checks in 5,900 lines — missing `SOC`,
missing `SIZ`, missing `SOD` — all in the main header. Everything past `SOD`, which is
97.7 % of a typical file, was unvalidated.

## The signal

The packet header states how many bytes belong to each code-block. A synchronised
decoder consumes that segment; a desynchronised one stops early and leaves a tail. The
shortfall needs no cooperation from the encoder and costs one comparison per code-block.

Two quantities are measured per block, and aggregated per decode:

| quantity | meaning |
|---|---|
| **under-read** | declared bytes the decoder never consumed |
| **over-read** | reads past the end of the segment, into the specified `0xFF` feed |

## What is deliberately *not* treated as damage

Three legal situations resemble corruption. Conflating them with it would reject valid
files, which is a worse failure than the one being fixed.

- **Over-reading is normal.** Annex C defines the past-the-end `0xFF` feed; a healthy
  block runs a few bytes into it on the flush tail.
- **Truncation is legal and intentional.** JPEG 2000 is designed to be cut at a packet
  boundary and still decode — that is what the progression orders are for. A
  quality-layer-limited decode, a resolution-limited decode and a JPIP prefix all leave
  data unconsumed by design, so `isPartialDecode` suppresses these anomalies entirely.
- **Encoders differ.** T.800 permits dropping trailing `0xFF` bytes, so a conformant
  encoder could in principle hand over a segment a decoder does not fully read.

## Corpus

**310 codestreams from four independent encoders** — Kakadu, OpenJPEG, OpenJPH and Grok
— over ten source images.

- Sources: 8-, 12- and 16-bit greyscale and 8- and 16-bit RGB; 64×48, 128×96, 256×256,
  512×512 and 517×389 (non-power-of-two); gradient, texture, sharp-edge and
  pseudo-random-noise content. Noise matters most: it is incompressible, so it produces
  the largest code-blocks and the longest MQ segments.
- Options: lossless and lossy, single- and multi-layer, tiled and untiled, two
  code-block sizes, RPCL progression, HTJ2K, and — the ones that actually matter —
  the `BYPASS`, `RESTART`, `SEGMARK`, `PREDICTABLE` and `SOP`/`EPH` coding modes, which
  change how a block's data is segmented and terminated.

Regenerate with `Scripts/generate-integrity-corpus.sh`.

## Method, and the correction that mattered

The first pass treated "not corrupted" as "clean" and measured the signal against it.
That gave a maximum single-block under-read of **60,633 bytes** on supposedly clean
streams, which would have made any useful threshold impossible.

The reason turned out not to be encoder variation. **Every stream with a non-zero
under-read was one J2KSwift decodes incorrectly.** Decoded samples were compared against
the source image each encoder was given, and the offending files were independently
confirmed good by round-tripping them through `opj_decompress`, which reproduces the
source bit-exactly.

So the baseline is *verified correctly decoded*, not merely *undamaged* — and calibrating
against the weaker definition would have produced a threshold tuned to this library's own
bugs.

## Measurements

Across **116 verified-correct reversible streams**:

| quantity | maximum observed | distribution |
|---|---|---|
| single-block under-read | **0 bytes** | all zero |
| single-block over-read | **8 bytes** | 0 (×29), 2 (×3), 3 (×80), 8 (×4) |

Threshold sweep, against 78 streams J2KSwift decodes wrongly:

| under-read > | over-read > | detection | false positives |
|---|---|---|---|
| 0 | 8 | 73/78 (93.6 %) | 0/116 |
| 0 | 16 | 73/78 (93.6 %) | 0/116 |
| **4** | **16** | **73/78 (93.6 %)** | **0/116** |
| 4 | 32 | 72/78 (92.3 %) | 0/116 |
| 8 | 16 | 71/78 (91.0 %) | 0/116 |

**Chosen: under-read > 4, over-read > 16.** Detection is flat across under-read
thresholds 0–4 and over-read thresholds 8–16, so the widest margin is free. Both sit
above the observed clean maximum, which is the headroom that protects an encoder whose
flush strategy this corpus did not sample.

## The shipped policy, measured end to end

Strict mode, every check including the `EOC` requirement:

| | streams | accepted | rejected |
|---|---|---|---|
| verified correct, reversible | 116 | **116** | 0 |
| lossy / irreversible | 32 | **32** | 0 |
| decoded wrongly | 78 | 5 | **73** |

**Zero false positives across 148 valid streams.**

## Detection on the original defect

The calibration above measures detection against streams J2KSwift decodes wrongly. The
defect this work was started for is different — *damaged input*, on streams the decoder
otherwise handles correctly — so it is measured separately. The two corpora are disjoint
and neither figure implies the other.

A 16-byte XOR was swept at stride 16 across the entropy payload of six lossless
codestreams from Kakadu, OpenJPEG and Grok:

```
corruptions applied          : 3386
  rejected by existing checks:    4
  decoded, samples identical :    0
  decoded, samples WRONG     : 3382
     caught by strict mode   : 3166
     still silent            :  216
  detection rate             : 93.6%
  missed-case error magnitude: min 1  median 4  max 65235
```

Not one silently-accepted corruption returned correct samples, which matches the earlier
diagnosis. Most surviving cases are negligible — a median error of 4 LSB on a 65,535
scale — but the tail is not: the worst miss reaches 65,235, so this is a strong filter
and not a guarantee.

## What this does not catch

Roughly 6 % of wrong decodes pass every check. That residue is structural rather than a
tuning failure: a corrupted packet header that stays self-consistent leaves every length
adding up, the decoder consumes exactly its segment, and only the coefficients are wrong.
No consumption-based heuristic can see it.

Closing it needs either encoder-written redundancy — segmentation symbols (`SEGMARK`) or
predictable termination (`PTERM`), neither of which this library currently implements —
or an out-of-band digest. Both are out of scope here.

`J2KSwift` also writes `Scod = 0` on every codestream, so it emits no `SOP`/`EPH` markers
and no code-block error-detection tools at all. Every codestream this library has ever
written carries zero error-detection redundancy.

## What would invalidate this

- **A conformant encoder not in the corpus** whose flush strategy leaves more than 4
  bytes of a segment legitimately unread. Add it to
  `Scripts/generate-integrity-corpus.sh` and re-measure.
- **Fixing the decoder's coding-mode handling.** The 78 wrongly-decoded streams are
  wrong because the decoder reads only bits 0 and 6 of the code-block style byte,
  ignoring `RESET`, `RESTART`, vertically-causal context, `PREDICTABLE` and `SEGMARK`.
  When that is fixed those streams will decode correctly and must then be re-measured as
  part of the clean baseline — they are the bulk of today's detection corpus, so the
  detection figure above will change even though the thresholds may not.
- **Wiring a new signal.** Tile residual and declared-versus-decoded block count were
  both considered and left out: neither is calibrated, and an unmeasured check in a
  mechanism whose whole purpose is measured detection is worse than no check.

## Reproducing

```bash
Scripts/generate-integrity-corpus.sh     # needs kdu/opj/ojph/grk on PATH
swift test --filter J2KCodestreamIntegrityTests
```

`J2KCodestreamIntegrityTests.testCalibratedThresholds` pins the two values, so changing
them without updating this document fails the suite.
