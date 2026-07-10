# J2KSwift v11.0.1

Decoder-only correctness and performance patch for the v11.0.x line.

## Summary

v11.0.1 removes redundant EBCOT decoder state. The decoder previously carried a
separate Boolean sign array even though the canonical sign is already stored in
`CoefficientState`; reconstruction now reads that canonical state. Zero-pass
blocks also return zero coefficients without entering the bit-plane state
machine, including when scratch buffers are reused.

## Fixed

- Reduced EBCOT decoder scratch allocation, clearing, and hot-loop traffic.
- Added a zero-pass fast path that is safe with reused decoder scratch.
- Added regression coverage for both behaviours.

## Backward compatibility

- Public API is unchanged.
- Decoded coefficients are bit-identical; no transform or codestream format
  changes are included.

## Validation

- Focused `J2KBitPlaneDecoderFixTests`: 34/34 passing.
- Release `j2k` build.
- Real TCIA DBT: all 100 lossless 1996×2457 frames decoded with bit-identical
  output.

## Reproducing the release gate

```sh
swift test -c release --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```
