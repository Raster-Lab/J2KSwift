---
description: "Use when editing JPEG 2000 codec pipeline files: encoder pipeline, decoder pipeline, DWT transforms, MQ coder, EBCOT coding, quantization, rate control, color transforms, HTJ2K. Apply to J2KCodec source files."
applyTo: "Sources/J2KCodec/**"
---

# JPEG 2000 Codec Implementation Guidelines

## Pipeline Architecture

The encoder and decoder are 7-stage symmetric pipelines. Changes to one stage often require symmetric changes in the other.

### Encoder stages: DC shift → Color transform → DWT → Quantize → Tier-1 → Tier-2 → Rate control
### Decoder stages: Parse → Tier-2 → Tier-1 → Dequantize → Inverse DWT → Inverse color → DC shift

## Key Invariants
- Multi-tile support: decoder must handle all SOT/SOD pairs, not just the first
- Edge tiles may have empty subbands — always check for zero-length before DWT
- Lossless mode uses 5/3 reversible DWT with integer arithmetic
- Lossy mode uses 9/7 irreversible DWT with floating point
- MQ coder carry propagation must handle 0xFF byte sequences correctly
- Rate control uses PCRD (Post-Compression-Rate-Distortion) optimization

## Common Pitfalls
- Forgetting to handle edge tiles with dimensions < code block size
- Off-by-one in subband coordinate calculations
- MQ coder state not properly reset between coding passes
- Quantization step sizes must match between encoder and decoder
- Tile component offsets must account for SIZ marker parameters
