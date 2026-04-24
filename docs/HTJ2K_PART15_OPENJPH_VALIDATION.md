# M7 — OpenJPH bidirectional cross-codec validation

**Status**: scoped 2026-04-24. Scalar block coder (M1–M5) + config
flag (M6) are done; self round-trip passes across dimensions, sample
densities, and magnitudes. This doc describes how to close the M7
gate before flipping `htj2kBlockFormat` default in M8.

The self round-trip proves that J2KSwift's encoder and decoder agree
on the Part-15 wire format, but does not prove conformance with the
ISO/IEC 15444-15 standard. For v5.0.0's headline claim (OpenJPH
interop), we need the following gates green.

---

## Gate 1: J2KSwift encodes → OpenJPH decodes

1. Wrap J2KSwift's block output in a minimal J2K codestream (SOC,
   SIZ, CAP, COD, QCD, SOT, SOD, codeblock data, EOC). CAP must
   signal HTJ2K. COD's `.codeBlockStyle` must advertise the
   Part-15 cleanup pass.

2. Run `/opt/homebrew/bin/ojph_expand -i out.j2c -o decoded.pgm`.

3. Compare `decoded.pgm` to the original input:
   - Lossless path: bit-exact match required.
   - Lossy path: PSNR ≥ 40 dB (matches OpenJPH's own lossy
     round-trip tolerance on 8-bit grayscale).

## Gate 2: OpenJPH encodes → J2KSwift decodes

1. `ojph_compress -i input.pgm -o in.j2c -block_size "{32,32}"
    -prog_order RPCL -num_decomps 3`.

2. Feed `in.j2c` to J2KSwift's codestream parser, extract the
   codeblock bytes, and run them through `HTBlockDecoderPart15.decode`.

3. Compare decoded coefficients to the original (after applying the
   same DWT / quantization OpenJPH applied).

## Gate 3: Conformance test suite

Run the 7 configurations in `testHTJ2KvsOpenJPH` (from v4.x),
bidirectional, and ensure all pass.

---

## Why this isn't automated yet

Wrapping block bytes into a full J2K codestream requires the encoder
pipeline (marker emission, tile-part assembly, packet header
encoding) — a separate port from the block coder itself. For v5.0.0
the scoped approach is:

- **Scalar block coder**: complete (M1–M6). Ship behind
  `htj2kBlockFormat: .part15`.
- **Codestream wrapping**: already exists in J2KSwift's custom path.
  v5.0.0 route is to dispatch from the existing encoder into the
  Part-15 block coder when the flag is set. That dispatch lands in a
  follow-up commit on this branch before M8.

Until that dispatch exists, M7 is a manual regression run using the
gates above. Once the dispatch is wired, M7 becomes automated via
XCTest + subprocess harnesses similar to
`testHTJ2KvsOpenJPH`.

## Current self-round-trip coverage

Self round-trip (J2KSwift ↔ J2KSwift) is green on:

- All-zero blocks at 1x1, 4x2, 4x4, and 8x4.
- Single bin-centered sample (positive and negative) at 1x1.
- Scattered bin-centered samples at 4x2 and 8x2.
- Two-row samples at 4x4 with inter-row context.
- Dense diagonal pattern at 8x4 (multi-pair, multi-row).
- 50 fuzz trials over random dimensions (1x1 through 16x8) at ~25%
  significant density with varied signs.
- Dense fill at 4x4 through 8x8 with μ_p=1 bin centers.
- Varied μ_p (1..4) driving every UVLC sub-branch, gated by
  `missingMSBs` so the bin center fits in bits 0..30.

68 Part-15 tests pass. Bit-stream, MEL, VLC, UVLC, MagSgn, block
layout, encoder, decoder, config flag, and fuzz harnesses all green.
