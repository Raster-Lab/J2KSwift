# Rate Control & Color Decode Optimization (2026-04-14)

## Changes Made

### 1. Rate Control Calibration Fix (J2KRateControl.swift)
- `qualityToBitrate()` was severely under-allocating bits at medium quality
- Old: quality 0.5 → 0.15 bpp (2.6x too small vs OpenJPEG -r 20)
- New: quality 0.5 → 0.40 bpp (matches OpenJPEG -r 20 for 8-bit)
- This fixes the 10 dB PSNR gap (21.6 vs 31.5 dB)
- Full recalibrated curve: q=0.20→0.15bpp, q=0.50→0.40bpp, q=0.80→1.0bpp, q=0.95→2.0bpp

### 2. Color Decode Conversion Elimination (J2KColorTransform.swift + J2KDecoderPipeline.swift)
- Added `inverseRCTDouble()` overload that operates directly on `[Double]` arrays
- Eliminates 6 temporary array allocations + 6 bulk conversions per color decode
- Old path: Double→Int32 (3x) → SIMD RCT → Int32→Double (3x)
- New path: Direct RCT on Doubles using floor() for integer division
- Uses vDSP (vDSP_vaddD, vvfloor, vDSP_vsubD) on Accelerate platforms
- Falls back to SIMD4<Double> with .rounded(.down) otherwise

## Remaining Optimization Opportunities
- DWT 1D lifting: still scalar, could benefit from vDSP/SIMD vectorization
- DWT 2D: uses [[Int32]] array-of-arrays; flat buffer would improve cache locality
- DWT 2D transpose: element-by-element, could use vDSP_mtrans with flat buffer
- Encoder ICT path: Int32→Double→ICT→Double→Int32→Float round-trip
