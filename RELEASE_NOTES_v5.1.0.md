# J2KSwift v5.1.0 Release Notes

**Release Date**: 2026-04-24
**Release Type**: Minor
**Previous Version**: 5.0.0

---

## Summary

v5.1.0 makes `.conformant` HTJ2K a fully round-trippable path through
J2KSwift's own public API and fixes a latent multi-row decoder bug in
the Part-15 block coder. Two releases were previously deferred to
v5.1 scope:

- **Decoder-side Part-15 dispatch** — v5.0 could emit standards-
  compliant `.conformant` codestreams but could not decode them back
  through its own decode API. v5.1 wires up the dispatch so that
  round-trip works.
- **Multi-row UVLC bug** — the block decoder desynced on the VLC
  stream whenever any quad produced `u_q > 2`. Small blocks masked
  the bug; larger blocks garbled samples.

Default `htj2kBlockFormat` **remains `.custom`** in v5.1.0 (see
"Known limitations" for why).

---

## Highlights

### Decoder-side Part-15 dispatch

The encoder now emits a `J2KSWIFT-HT:conformant` signature inside a
standard `COM` (comment) marker segment whenever
`htj2kBlockFormat == .conformant`. Standards-compliant decoders
(OpenJPH, Kakadu, PACS viewers) ignore unrecognized `COM` payloads,
so the on-wire codestream stays strictly ISO/IEC 15444-15 conformant.
J2KSwift's own decoder parses the marker, promotes
`DecoderConfiguration.htj2kBlockFormat`, and at both HT block decode
sites routes to `HTBlockDecoder.decodeCleanupConformant` instead of
the legacy `decodeFromCodestreamDetailed`.

Codestreams without the signature (anything produced by J2KSwift
≤ 5.0.x and third-party encoders) continue to route through the
v4.x `.custom` block decoder. Backwards compatibility is preserved.

### Part-15 block decoder multi-row UVLC fix

`HTBlockEncoderConformant` writes UVLC pair data as `pre0, pre1,
suf0, suf1` — both prefixes together, then both suffixes. The
decoder was reading prefix-and-suffix interleaved per quad
(`pre0, suf0, pre1, suf1`). When every `u_q` was ≤ 2 the suffixes
were 0-length and the mismatch was invisible; once any `u_q`
exceeded 2 the VLC stream desynced mid-row, garbling the rest of
the block (or tripping a `MagSgn read width > 32` precondition).

Both `decodeUVLCPairInitial` and `decodeUVLCPairSubsequent` now
mirror the encoder's emission order. The initial-row
`u_q0 > 2 && u_q1 > 0` branch additionally reads `u_q1`'s 1-bit
marker before `suf0`, matching the encoder at
`J2KHTConformantBlockEncoder.swift:224-227`.

---

## Fixed

- v5.0 decoder pipeline could not decode its own `.conformant` HTJ2K
  output — block dispatch sites at
  [J2KDecoderPipeline.swift:1280-1291](Sources/J2KCodec/J2KDecoderPipeline.swift#L1280-L1291)
  and [:1372-1386](Sources/J2KCodec/J2KDecoderPipeline.swift#L1372-L1386)
  unconditionally invoked the v4.x custom block decoder.
- `HTBlockDecoderConformant` corrupted samples (or tripped a
  `MagSgn read width > 32` precondition) whenever any code block
  spanned enough quad rows to produce a `u_q > 2` value in the UVLC
  stream. Fix rewrites both `decodeUVLCPair{Initial,Subsequent}`
  to match the encoder's on-wire ordering.
- `writeQCDMarker` reversible branch now checks
  `config.useHTJ2K && config.htj2kBlockFormat == .conformant`
  rather than just the block-format flag. Prevents the Part-15 QCD
  epsilon bias from leaking into legacy EBCOT encodes if a caller
  flips `htj2kBlockFormat` without also enabling HTJ2K.

---

## Added

- `DecoderConfiguration.htj2kBlockFormat: HTBlockFormat` — internal
  field, promoted to `.conformant` when the codestream carries the
  J2KSwift block-format `COM` marker.
- `HTBlockFormatCOMSignature.conformant` — shared ASCII signature
  bytes used by encoder emission and decoder parse.
- `writeHTBlockFormatCOM` encoder helper (emits `COM` between `QCD`
  and `SOT`) and `parseHTBlockFormatCOM` decoder helper (matches the
  signature byte-for-byte, skipping the `COM` as a regular comment
  otherwise).
- `J2KHTConformantSelfRoundTripTests` — 10 tests covering 4×4
  through 32×32 code blocks, uniform + noise, both block formats,
  plus an OpenJPH interop probe confirming that the encoder's
  output still decodes in `ojph_expand`.

---

## Changed

- `VERSION` bumped from `5.0.0` to `5.1.0`.

---

## Test coverage

- 10 new self round-trip tests exercising 4×4 through 32×32.
- Existing 82 Conformant block-level tests, 3 end-to-end OpenJPH
  cross-codec tests, 17 HT block coder optimization tests continue
  to pass.
- Full J2KCodec suite: 1701 tests, 15 skipped, green after the
  UVLC and QCD-gating fixes landed.

---

## Known limitations

- **Default `htj2kBlockFormat` stays `.custom`.** Flipping the
  default to `.conformant` is conditionally ready on the decoder
  side, but the encoder side has a pre-existing non-power-of-2
  subband geometry issue that corrupts samples at arbitrary image
  dimensions with multi-level decomposition (e.g. 37×53, 79×61 with
  ≥ 1 DWT level and default code block sizes). The same corruption
  reproduces when the encoder's output is handed to OpenJPH's
  `ojph_expand`, so the bug is in the shared block-coder geometry,
  not the newly wired decoder dispatch. Fix is tracked for v5.1.1.
  Callers encoding power-of-2 dimensions or opting in to larger
  single code blocks are unaffected.
- 8-bit reversible `.conformant`: pixel value 0 decodes back as 128
  when the block uses `K_max = 7` — the magnitude `|DC-shift(0)| =
  128 = 2^7` exceeds the 7-bit range. OpenJPH has identical
  behavior.
- Fused MEL/VLC terminate byte optimization (~1 byte/block) not yet
  applied.
- SIMD block coder (SSSE3/AVX2/AVX512) not yet ported.

---

## Upgrade recommendation

Drop-in replacement for v5.0. Callers that were already passing
`htj2kBlockFormat = .conformant` explicitly now get decoder-side
round-trip for free. Legacy callers using the default remain
unchanged.
