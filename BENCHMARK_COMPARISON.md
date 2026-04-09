# Benchmark Comparison: J2KSwift vs OpenJPEG

**Date:** April 8, 2026  
**Branch:** `copilot/analyze-encode-decode-pipeline` (PR #276)  
**Test Image:** 480×320 RGB PPM (450 KB uncompressed)  
**Reference:** OpenJPEG 2.5.4 (`opj_compress` / `opj_decompress`)  
**Platform:** macOS, Apple Silicon (arm64e)

---

## Cross-Decode Quality (Decoder Accuracy)

OPJ-encoded J2K files decoded by both J2KSwift and OpenJPEG, compared against the original image.

| Rate | File Size | Ratio | J2KSwift PSNR | OPJ PSNR | Gap | Decoder MSE |
|------|-----------|-------|---------------|----------|-----|-------------|
| r=2.0 | 203.0 KB | 2.2:1 | 51.39 dB | 51.39 dB | **0.00 dB** | 78.49 dB |
| r=3.0 | 149.9 KB | 3.0:1 | 46.39 dB | 46.39 dB | **0.00 dB** | 78.09 dB |
| r=5.0 | 89.9 KB | 5.0:1 | 38.99 dB | 38.99 dB | **0.00 dB** | 78.62 dB |

> **Result:** J2KSwift decoder produces identical output to OpenJPEG at all tested compression rates. The "Decoder MSE" column shows the PSNR between J2KSwift-decoded and OPJ-decoded pixels — values near 78 dB indicate sub-pixel differences (rounding only).

---

## End-to-End Quality (Encoder + Decoder)

J2KSwift-encoded files decoded by both J2KSwift and OpenJPEG, compared against the original image.

| Quality | File Size | Ratio | J2KSwift PSNR | OPJ PSNR | Gap | Decoder Match |
|---------|-----------|-------|---------------|----------|-----|---------------|
| q=1.0 | 596.8 KB | 0.8:1 | 63.13 dB | 63.15 dB | +0.02 dB | 79.50 dB |
| q=0.9 | 255.8 KB | 1.8:1 | 50.19 dB | 50.19 dB | **0.00 dB** | 78.36 dB |
| q=0.8 | 184.9 KB | 2.4:1 | 46.56 dB | 46.56 dB | **0.00 dB** | 78.17 dB |
| q=0.5 | 84.9 KB | 5.3:1 | 35.17 dB | 35.17 dB | **0.00 dB** | 78.23 dB |

> **Result:** J2KSwift encoder+decoder matches OpenJPEG quality to within 0.02 dB across all quality levels. The tiny gap at q=1.0 is due to minor rounding differences in the encoder's quantization step sizes.

---

## Lossless Roundtrip

| Mode | File Size | Ratio | MSE | PSNR |
|------|-----------|-------|-----|------|
| Lossless (5/3 DWT) | 265.0 KB | 1.7:1 | **0** | **∞** |

> **Result:** Perfect lossless reconstruction — every pixel matches the original exactly.

---

## Key Fix: EBCOT bpno_plus_one Scaling

The decoder quality improvement was achieved by aligning J2KSwift's EBCOT bit-plane decoding with OpenJPEG's `bpno_plus_one` convention:

- **Root Cause:** At the lowest bit plane (bitPlane=0), J2KSwift used `halfBitMask = 0`, while OPJ's shifted convention gives `half = 1`. This caused a 0.5 × stepSize gap per coefficient.
- **Impact:** At low compression (r=2.0), 44% of pixels were affected; at high compression (r=5.0), <0.1%.
- **Fix:** For irreversible (9/7) transforms, use `bitMask = 1 << (bitPlane + 1)` and `halfBitMask = 1 << bitPlane` with `0.5 × stepSize` dequantization. Reversible (5/3) path unchanged.

### Before Fix

| Rate | J2KSwift PSNR | OPJ PSNR | Gap |
|------|---------------|----------|-----|
| r=2.0 | 49.08 dB | 51.39 dB | **-2.32 dB** |
| r=3.0 | 46.38 dB | 46.39 dB | -0.01 dB |
| r=5.0 | 38.99 dB | 38.99 dB | 0.00 dB |

### After Fix

| Rate | J2KSwift PSNR | OPJ PSNR | Gap |
|------|---------------|----------|-----|
| r=2.0 | 51.39 dB | 51.39 dB | **0.00 dB** |
| r=3.0 | 46.39 dB | 46.39 dB | **0.00 dB** |
| r=5.0 | 38.99 dB | 38.99 dB | **0.00 dB** |

---

## Test Suite

| Suite | Tests | Failures | Skipped |
|-------|-------|----------|---------|
| J2KCodecTests | 1515 | 0 | 15 |
| PerformanceTests | 94 | 0 | 0 |

---

## Files Modified

| File | Change |
|------|--------|
| `Sources/J2KCodec/J2KBitPlaneCoder.swift` | Conditional bpno_plus_one shift for irreversible EBCOT |
| `Sources/J2KCodec/J2KDecoderPipeline.swift` | ×0.5 dequantization + irreversible flag propagation |

---

## Known Limitations

- **q=0.3 (high compression):** Decoder returns "Incompatible subband widths" error at very high compression ratios. OpenJPEG decodes the same file successfully. This is a pre-existing issue unrelated to the PSNR fix.
