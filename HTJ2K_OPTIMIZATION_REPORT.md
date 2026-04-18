# HTJ2K Optimization Report

**Date:** 2026-04-11  
**Platform:** Apple M2 (arm64e), macOS, Metal GPU  
**Branch:** `docs/compliance-update-2026-04-10`  
**Methodology:** 5 iterations per configuration, 1 warmup run, release build (`-c release`)

## Summary

J2KSwift's HTJ2K (High Throughput JPEG 2000, ISO/IEC 15444-15) encoder and decoder have been optimized across multiple dimensions: correctness, speed, and GPU acceleration. All configurations produce **lossless** (PSNR = ∞) output verified across 5 test images in 3 coding modes (15 total configurations).

## Benchmark Results

### Grayscale Images (1 component)

| Image | Mode | Encode (ms) | Decode (ms) | Encode MP/s | Decode MP/s | Size (KB) | Ratio |
|-------|------|-------------|-------------|-------------|-------------|-----------|-------|
| 512×512 | CPU EBCOT | 53.2 | 39.8 | 4.93 | 6.59 | 229.9 | 1.11:1 |
| 512×512 | CPU HTJ2K | 43.8 | 36.4 | 5.99 | 7.20 | 239.3 | 1.07:1 |
| 512×512 | GPU HTJ2K | 41.6 | 33.2 | 6.30 | 7.90 | 239.3 | 1.07:1 |
| 1024×1024 | CPU EBCOT | 129.4 | 78.4 | 8.10 | 13.37 | 909.6 | 1.13:1 |
| 1024×1024 | CPU HTJ2K | 94.0 | 60.0 | 11.16 | 17.48 | 950.1 | 1.08:1 |
| 1024×1024 | GPU HTJ2K | 95.4 | 70.4 | 10.99 | 14.89 | 950.1 | 1.08:1 |
| 2048×2048 | CPU EBCOT | 445.4 | 236.4 | 9.42 | 17.74 | 3583.7 | 1.14:1 |
| 2048×2048 | CPU HTJ2K | 308.2 | 162.2 | 13.61 | 25.86 | 3750.0 | 1.09:1 |
| 2048×2048 | GPU HTJ2K | 326.8 | 173.6 | 12.83 | 24.16 | 3750.0 | 1.09:1 |

### RGB Images (3 components)

| Image | Mode | Encode (ms) | Decode (ms) | Encode MP/s | Decode MP/s | Size (KB) | Ratio |
|-------|------|-------------|-------------|-------------|-------------|-----------|-------|
| 512×512 | CPU EBCOT | 118.4 | 109.2 | 2.21 | 2.40 | 691.9 | 1.11:1 |
| 512×512 | CPU HTJ2K | 92.0 | 95.0 | 2.85 | 2.76 | 725.1 | 1.06:1 |
| 512×512 | GPU HTJ2K | 93.4 | 97.4 | 2.81 | 2.69 | 725.1 | 1.06:1 |
| 1024×1024 | CPU EBCOT | 395.6 | 355.0 | 2.65 | 2.95 | 2729.0 | 1.13:1 |
| 1024×1024 | CPU HTJ2K | 296.4 | 309.6 | 3.54 | 3.39 | 2858.8 | 1.07:1 |
| 1024×1024 | GPU HTJ2K | 298.6 | 317.4 | 3.51 | 3.30 | 2858.8 | 1.07:1 |

### HTJ2K vs EBCOT Speedup (Grayscale)

| Image | Encode Speedup | Decode Speedup |
|-------|----------------|----------------|
| 512×512 | **1.22×** | **1.09×** |
| 1024×1024 | **1.38×** | **1.31×** |
| 2048×2048 | **1.45×** | **1.46×** |

HTJ2K encoding speedup scales with image size — larger images benefit more from the simplified entropy coding.

### Quality Validation

All 15 configurations: **PSNR = ∞ (lossless)**

| Mode | Images Tested | PSNR | MSE | MAE |
|------|---------------|------|-----|-----|
| CPU EBCOT | 5 | Inf | 0.0 | 0.0 |
| CPU HTJ2K | 5 | Inf | 0.0 | 0.0 |
| GPU HTJ2K | 5 | Inf | 0.0 | 0.0 |

## Optimizations Applied

### 1. HTJ2K Block Coder Correctness Fixes

The FBCOT (Fast Block Coder with Optimized Truncation) implementation in `J2KHTBlockCoder.swift` required multiple interrelated fixes to achieve lossless encode/decode symmetry.

#### 1.1 VLC Encoder-Decoder Asymmetry
- **Problem:** Encoder wrote VLC (Variable Length Code) decisions for ALL quad-pairs; decoder only read VLC for pairs with at least one significant coefficient.
- **Fix:** Encoder now skips VLC output when no coefficient in the pair is significant (`pattern == 0`), matching the decoder's reading behavior.
- **Impact:** Eliminated systematic bit-stream desynchronization.

#### 1.2 MEL Decoder Pending Significance
- **Problem:** When a MEL (Modular Embedded signalling) run terminated, the decoder never delivered the trailing "significant" decision that terminates the run.
- **Fix:** Added `pendingSignificant` flag to `HTMELCoder` that tracks when a run has just completed and a significant decision needs to be delivered.
- **Impact:** Decoder now correctly reconstructs significance patterns for all code blocks.

#### 1.3 MEL Decode Priority (Critical Fix)
- **Problem:** `pendingSignificant` was checked BEFORE `run > 0` in `HTMELCoder.decode()`. A terminated MEL run encodes N zeros followed by 1 significant. The decoder was delivering the significant decision before consuming all run zeros.
- **Fix:** Swapped priority — check `run > 0` before `pendingSignificant` to ensure all N run zeros are consumed before the trailing significant is delivered.
- **Impact:** This was the root cause of catastrophic failures in large code blocks (64×64). Small blocks (8×8) passed because their short runs masked the bug. PSNR went from ~20.5 dB to ∞.

#### 1.4 MEL Flush Edge Case
- **Problem:** `HTMELCoder.flush()` called `emitBit(0)` for partial trailing runs, injecting a false run into the bitstream.
- **Fix:** Removed `emitBit(0)` — only `flushBits()` is needed to pad the final byte.
- **Impact:** Eliminated spurious significance decisions at end of code blocks.

#### 1.5 Refinement Significance State
- **Problem:** Decoder updated coefficient significance state between SigProp and MagRef passes, but encoder used the pre-SigProp state for both.
- **Fix:** Save significance state before SigProp pass; use saved state for MagRef pass in both encoder and decoder.
- **Impact:** Correct refinement coding for multi-pass blocks.

#### 1.6 Cleanup Decode VLC Fallback
- **Problem:** `decodeCleanup` read VLC for insignificant pairs when `melReader.bytesRemaining == 0`, assuming MEL exhaustion meant VLC should be consulted.
- **Fix:** Removed this fallback — MEL coder can have buffered bits even when `bytesRemaining == 0`. Trust the MEL decoder's run state.
- **Impact:** Eliminated spurious VLC reads that corrupted pair significance.

#### 1.7 Missing 6-Byte Headers in Variant Encoders
- **Problem:** Lightweight (`[Int]`) and pooled (async) encoder variants omitted the 6-byte stream header `[melLen:2 | vlcLen:2 | magsgnLen:2]`.
- **Fix:** Added header writing to both `J2KHTBlockCoderOptimizations.swift` and `J2KHTBlockCoderPooled.swift`.
- **Impact:** Decoder can now parse encoded blocks from all three encoder variants.

### 2. EBCOT Unsafe Pointer Optimization

Eliminated Swift array bounds-checking overhead in all EBCOT coding passes by converting to `UnsafePointer`/`UnsafeMutablePointer` access patterns.

**Files modified:**
- `J2KMQCoder.swift` — `Data` → `[UInt8]` for faster subscript
- `J2KContextModeling.swift` — `calculateUnsafe()` with `UnsafePointer` params
- `J2KBitPlaneCoder.swift` — All 4 coding passes rewritten with `withUnsafeMutableBufferPointer`

**Results:**
- 10–12% speedup across all image sizes for EBCOT encoding
- 47% improvement in decode throughput for medical images
- All inner loop index math uses overflow operators (`&*`, `&+`)
- `@inline(__always)` on hot-path functions

### 3. HTJ2K Int32 Pipeline Optimization

Converted the HTJ2K encoding pipeline from `[Int]` (64-bit) to `[Int32]` (32-bit) coefficient buffers.

**Key changes:**
- `encodeCleanup()` primary overload accepts `[Int32]`, uses `SIMD4<Int32>` (single 128-bit NEON register vs 2 for `SIMD4<Int>`)
- Eliminated 2 × O(n) array allocations per code block (`map { Int($0) }` and `map { abs($0) }`)
- Cleanup pass returns `absMags` and significance state, eliminating post-cleanup rebuild
- Added early termination for trivial blocks (`maxMag == 0`)
- Refinement pass cap: max 3 SigProp+MagRef pairs, preventing wasted work on bit-planes that rate control truncates

### 4. Metal GPU DWT Acceleration

Fixed and optimized all 9 Metal compute shaders for discrete wavelet transforms.

**Shaders fixed:**
- CDF 9/7 (lossy): forward/inverse, horizontal/vertical
- Le Gall 5/3 (lossless): forward/inverse, horizontal/vertical
- 9/7 lifting order corrected (split→lift→scale), missing lifting steps added
- 5/3 buffer types fixed from `int*` to `float*`

**Performance (isolated DWT, not full pipeline):**

| Size | CPU (ms) | GPU (ms) | Speedup |
|------|----------|----------|---------|
| 512×512 (9/7) | 339.2 | 4.21 | **80.6×** |
| 1024×1024 (9/7) | 1447.0 | 11.0 | **131.7×** |
| 2048×2048 (9/7) | 5463.6 | 32.0 | **170.5×** |
| 512×512 (5/3) | 157.7 | 2.28 | **69.3×** |
| 1024×1024 (5/3) | 711.6 | 5.44 | **130.9×** |
| 2048×2048 (5/3) | 2563.5 | 16.5 | **155.0×** |

**Correctness:** CDF 9/7 CPU-GPU max error = 0.00024; Le Gall 5/3 exact match (0.0).

### 5. Metal Actor Boundary Deadlock Fix

Resolved GPU encoder pipeline hangs during Metal DWT operations.

**Root cause:** After `await MTLCommandBuffer.completed()` inside the `J2KMetalDWT` actor, subsequent `await bufferPool.acquireBuffer()` calls (crossing to `J2KMetalBufferPool` actor) would deadlock due to Swift concurrency cooperative thread pool exhaustion.

**Fix:** Pre-allocate all Metal buffers via `device.makeBuffer()` and fetch all compute pipelines from `shaderLibrary` BEFORE any command buffer dispatch. This eliminates actor boundary crossings after `cb.completed()` calls.

### 6. Encoder Quality Improvements (Lossy Mode)

#### 6.1 Near-Target HTJ2K Truncation Refinement (April 16, 2026)
- **Problem:** strict PCRD could leave HTJ2K noticeably under target when the next useful truncation frontier slightly overshot the byte budget.
- **Fix:** preserve the best small overshoot candidate and use it only when it lands closer to the target than the final undershoot.
- **Additional improvement:** cap HT refinement planes adaptively from target bitrate, subband class, and block energy, and stop once both refinement streams emit zero bytes.
- **Verification:** a dedicated HT regression now covers the undershoot case, and the focused HTJ2K validation run completed with **42 tests, 0 failures**.

#### 6.2 Medical Compression-Efficiency Retuning (April 16, 2026)
- **Problem:** the earlier single-component HTJ2K matched-rate allowance was intentionally quality-biased, but the fresh real-medical corpus confirmed that it was also causing a systematic file-size overspend versus standard J2K.
- **Fix:** narrow the HT matched-rate compensation to a smaller rate-dependent window so the encoder keeps the medical quality guard while avoiding the previous blanket overshoot.
- **Verification:** the focused HT medical regression remains green, including the new compression-efficiency guard, and the fresh release-mode medical rerun confirmed that lossy HTJ2K average encoded size dropped from **1.30 MB** to **1.18 MB** while encode throughput stayed in the same high-speed range at roughly **0.64 s** per sampled study.
- **Measured impact:** aggregate lossy HTJ2K compression ratio improved from **15.58×** to **16.55×** on the sampled medical corpus, with the biggest focus-modality gains appearing in PX (**13.75× → 15.19×**), DX (**14.51× → 15.76×**), and XA (**6.94× → 7.67×**).

- **Wavelet filter default:** Fixed `useReversibleFilter` default for lossy mode (was incorrectly using 5/3 instead of 9/7): +1.10 dB
- **Base quantization step:** Changed to fixed 1.0, matching OpenJPEG approach where PCRD exclusively controls rate/quality: +0.5 dB
- **PCRD actual distortion:** Modified rate control to use actual per-pass distortion from EBCOT (`cumulativePassDistortion`) instead of model estimates: +0.3–0.4 dB

**Lossy benchmark (1920×1280 RGB, 9/7 irreversible):**

| Quality | J2KSwift PSNR | OpenJPEG PSNR | Gap |
|---------|---------------|---------------|-----|
| q=0.25 | 31.15 dB | 31.35 dB | −0.21 dB |
| q=0.50 | 38.04 dB | 37.95 dB | +0.09 dB |
| q=0.75 | 45.78 dB | 44.04 dB | +1.74 dB |

## Test Coverage

- **9 block-level roundtrip tests** — All passing (8×8, 16×16, 32×8, 64×64 blocks, sparse/dense/deterministic patterns, long MEL runs)
- **63 HTJ2K codec tests** — All passing
- **31 pipeline tests** — All passing
- **330 Metal GPU tests** — All passing
- **1540+ total tests** — All passing, 0 failures

## Files Modified

| File | Changes |
|------|---------|
| `Sources/J2KCodec/J2KHTBlockCoder.swift` | MEL decoder, VLC encode/decode, refinement state, cleanup decode |
| `Sources/J2KCodec/J2KHTBlockCoderOptimizations.swift` | 6-byte header, VLC skip for insignificant patterns |
| `Sources/J2KCodec/J2KHTBlockCoderPooled.swift` | 6-byte header, VLC skip |
| `Sources/J2KCodec/J2KEncoderPipeline.swift` | Int32 path, refinement cap, band-level Kb |
| `Sources/J2KCodec/J2KMQCoder.swift` | Unsafe pointer decode path |
| `Sources/J2KCodec/J2KContextModeling.swift` | `calculateUnsafe()` with UnsafePointer |
| `Sources/J2KCodec/J2KBitPlaneCoder.swift` | Unsafe encoding passes, overflow operators |
| `Sources/J2KCodec/J2KRateControl.swift` | PCRD actual distortion |
| `Sources/J2KCodec/J2KQuantization.swift` | Base step size fix |
| `Sources/J2KMetal/J2KMetalDWT.swift` | 9 shader fixes, buffer pre-allocation |
| `Sources/J2KMetal/J2KMetalColorTransform.swift` | Actor boundary fix |
| `Sources/J2KMetal/J2KMetalMCT.swift` | Actor boundary fix |
| `Tests/J2KCodecTests/J2KHTBlockCoderRoundtripTest.swift` | 9 roundtrip tests |

## Methodology

**Test images:** Natural photographic content at 512×512, 1024×1024, and 2048×2048 in both grayscale (PGM) and RGB (PPM) formats.

**Benchmark procedure:**
1. Build: `swift build -c release`
2. Warmup: 1 encode + 1 decode discarded
3. Timing: 5 iterations with wall-clock millisecond resolution
4. Metrics: Average and minimum times reported
5. Validation: `j2k compare` verifies PSNR after each configuration

**Modes tested:**
- `cpu_ebcot` — Part 1 EBCOT entropy coding (MQ coder), lossless (5/3 DWT)
- `cpu_htj2k` — Part 15 FBCOT entropy coding (MEL + VLC + MagSgn), lossless (5/3 DWT)
- `gpu_htj2k` — Part 15 FBCOT with Metal GPU-accelerated DWT, lossless (5/3 DWT)
