# Code-block coding modes — interoperability

What the decoder does with the SPcod/SPcoc code-block style byte
(ISO/IEC 15444-1 Table A.19), how it was measured, and what is still wrong.

## The defect

The decoder read the style byte and extracted **only bit 0** (selective bypass) and
**bit 6** (HT). Bits 1–5 were discarded:

| bit | mask | mode | was |
|---|---|---|---|
| 0 | `0x01` | selective arithmetic bypass ("lazy") | parsed, mishandled |
| 1 | `0x02` | reset context probabilities each pass | **dropped** |
| 2 | `0x04` | termination on each pass ("RESTART") | **dropped** |
| 3 | `0x08` | vertically causal context | **dropped** |
| 4 | `0x10` | predictable termination ("PTERM") | **dropped** |
| 5 | `0x20` | segmentation symbols ("SEGMARK") | **dropped** |
| 6 | `0x40` | HTJ2K | parsed |

Each of these changes how the entropy data is segmented, or how context is formed. A
decoder that ignores them does not degrade gracefully — it desynchronises at the first
affected pass and returns a garbage image, with no error.

Measured against 194 conformant reversible codestreams from Kakadu, OpenJPEG, OpenJPH
and Grok: **78 decoded to wrong samples, silently — 40%.** The files were confirmed good
by round-tripping them through `opj_decompress`, which reproduces the source bit-exactly.

## What was wrong, and what fixed it

### 1. The style bits were never parsed

`parseCODMarker` and `parseCOCMarker` now share `applyCodeBlockStyle`, and the flags
reach the entropy decoder through `decodeCodingOptions(for:)`. Previously the decoder's
options were `bypass ? .fastEncoding : .default`, so every other bit stopped at the
configuration.

### 2. RESTART and RESET were conflated

`TerminationMode.predictable` stood for a mixture of bits 1, 2 and 4 — its own
documentation described it as "termination on each coding pass or RESET mode", under a
name that means PTERM. `CodingOptions` now carries `terminateOnEachPass`,
`resetContextOnEachPass`, `verticallyCausalContext` and `segmentationSymbols` as
separate fields, so a stream setting one does not get the others. Context states are
reset at a segment boundary **only** when bit 1 asks for it.

### 3. The packet header signals one length per segment, not per code-block

`decodeDataLength` read exactly one length. Under bypass or termination-on-each-pass,
B.10.7.2 signals a length for **each codeword segment**, so the remaining lengths stayed
in the bit stream and every subsequent code-block in the packet was parsed from the
wrong position — the packet *header* mis-parsed, not just the body. That is why those
streams came out entirely wrong rather than partially correct.

`decodeDataLengths` now reads one length per segment, each with
`Lblock + floor(log2(passes in that segment))` bits.

### 4. The segment shape was wrong

The decode loop advanced one segment per pass. That is right only under
termination-on-each-pass. Under bypass the shape is **10, 2, 1, 2, 1, …**: the first ten
passes are arithmetically coded and share a segment, then each bit-plane contributes a
two-pass raw segment and a one-pass cleanup segment. Advancing per pass ran off the end
of the block's slices partway through the first bit-plane.

`segmentPassCounts` computes the shape; the decode loop opens a new segment only at a
real boundary.

### 5. Half of bypass mode did not exist

Lazy mode codes **both** the significance-propagation and the magnitude-refinement
passes raw; only cleanup stays arithmetically coded. Only the raw magnitude-refinement
pass was implemented. `decodeSignificancePropagationPassBypass` is new.

The bypass trigger was also wrong in kind: `bitPlane < bypassThreshold` compares an
absolute bit-plane index against a constant, where the standard's rule is about the
*pass* index — raw coding begins after the tenth coding pass. The two coincide only when
a block has exactly eight active bit-planes.

### 6. Segmentation symbols were not consumed

The four-symbol `0xA` sentinel at the end of each cleanup pass is part of the codeword
whether or not anyone checks it. Not decoding it desynchronises every subsequent pass.
It is now decoded and verified; a mismatch raises `J2KError.decodingError`.

### 7. A nominal tile larger than the image was not clipped

Eq. B-7 clips a tile to the reference grid. The multi-tile path already clipped per
tile, but a single tile was decoded straight from the SIZ metadata, so a 64×48 image
declaring `XTsiz = YTsiz = 128` had its whole subband grid computed for a 128-wide tile.
Its entropy payload is byte-identical to the untiled encoding of the same image — only
the SIZ fields differ — and it decoded to garbage. `tileSize` is now clamped to the grid
at parse time.

## Result

Scored against the corpus, counting only streams whose samples can be compared exactly
(reversible; lossy and irreversible are excluded since they need not match the source):

| | before | after |
|---|---|---|
| exact | 116 | **204** |
| wrong | 78 | 4 |
| threw | 14 | 0 |
| total | 208 | 208 |

By mode, after:

| mode | exact / total |
|---|---|
| bypass | **24 / 24** |
| segmark | **16 / 16** |
| restart | **16 / 16** |
| allmodes (`BYPASS\|RESTART\|PREDICTABLE\|SEGMARK`) | **16 / 16** |
| byprest (`BYPASS\|RESTART`) | **8 / 8** |
| lossless, L5, cblk32, blk32, rpcl, rev, ht | **112 / 112** |
| tiled | 28 / 32 |

Reproduce with `Scripts/generate-integrity-corpus.sh` and the scoring harness described
in `Documentation/INTEGRITY_CALIBRATION.md`.

## Still wrong

### Partial tiles in the X direction

A tile column cut short by the right image edge decodes wrong. Isolated to the axis:

| image | tile | result |
|---|---|---|
| 512 × 389 | 128 × 128 | **exact** (height partial is fine) |
| 517 × 384 | 128 × 128 | wrong: 1,920 samples = 5 × 384 |
| 517 × 389 | 128 × 128 | wrong: 1,945 samples = 5 × 389 |
| 260 × 260 | 128 × 128 | wrong: 1,040 samples = 4 × 260 |

The wrong region is always exactly the rightmost partial tile column, full height.
Height partials decode correctly, so this is specific to the horizontal axis.

The entropy decode itself desynchronises — those blocks report 78 to 167 bytes of
over-read — so the code-block width for the narrow column is over-computed; it is not
merely a stitching error. The suspect is the interaction between the band canvas origin
and the precinct bounds in `extractTileData`, not `subbandDimensions`, whose Eq. B-15
arithmetic checks out by hand for these cases.

**This is detected, not silent**: strict validation rejects all four cases, so a caller
gets `J2KError.corruptedCodestream` rather than a wrong image.

### Vertically causal context is parsed but not implemented

Bit 3 is decoded into `CodingOptions.verticallyCausalContext` and nothing consumes it.
Context formation still references the stripe below. No encoder in the corpus emits it,
so it is untested in either direction — the flag exists so the plumbing is in place, and
a stream using it will decode wrongly exactly as before.

### Predictable termination is parsed but not verified

Bit 4 is decoded and nothing checks it. PTERM is an error-detection aid, so ignoring it
loses detection but does not desynchronise.

### The encoder still emits no error-detection tools

`writeCODMarker` always writes `Scod = 0`, and the code-block style byte never sets bits
4 or 5. Every codestream this library writes carries zero error-detection redundancy.
This work was decoder-side only.

### Lblock does not persist across layers

`Lblock` is per-code-block state that persists across packets and is initialised to 3
once (B.10.7.1). The single-layer path re-initialises it per packet, which is correct
there because each block is signalled once. The multi-layer path was not audited.
