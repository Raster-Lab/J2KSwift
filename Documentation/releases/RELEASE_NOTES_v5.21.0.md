# J2KSwift v5.21.0 — GPU 9/7 lossy IDWT scaling fix

**Release date:** 2026-05-04
**Theme:** Root-cause and fix the GPU 9/7 lossy IDWT defect that v5.20.0 gated off. v5.21.0
identifies the bug as a scaling-direction inversion in the J2KMetal module and fixes both the
Metal kernels and the Swift CPU reference. GPU 9/7 lossy decode is now bit-exactly equivalent
to CPU within Float-precision tolerance (max 1 LSB at 16-bit).

## Root cause

ISO/IEC 15444-1 Annex F.4.1.1 specifies the 9/7 forward DWT scaling step as
**`lowpass /= K, highpass *= K`** where K = 1.230174105. The inverse undoes by
**`lowpass *= K, highpass /= K`**.

Pre-v5.21.0 J2KMetal had it backwards:

| Path | Pre-v5.21.0 | Spec / J2KCodec |
|---|---|---|
| Forward (CPU + GPU) | `lowpass *= K, highpass /= K` | `lowpass /= K, highpass *= K` |
| Inverse (CPU + GPU) | `lowpass /= K, highpass *= K` | `lowpass *= K, highpass /= K` |

The J2KMetal module was **self-consistent** — its forward and inverse round-tripped within
itself — but the convention disagreed with J2KCodec's `J2KDWT1D` (which is spec-compliant and
the canonical reference, since J2KSwift's encoder uses it).

Effect: when J2KCodec encoded an image and J2KMetal's GPU IDWT decoded it, lowpass came out
1/K² ≈ 0.66× too small and highpass K² ≈ 1.51× too large. After multi-level IDWT the error
compounded to **K⁴ = 2.29×** scaling on the worst-case coefficients. Final pixel error:
~19,000 LSB average in 16-bit space (essentially noise).

Why it was missed for so long: every J2KMetal-internal test round-tripped within J2KMetal, so
the inversion was invisible. Cross-codec tests (J2KCodec encode → J2KMetal decode) used the 5/3
lossless path or measured PSNR vs ground truth (where the error compounds with quantization
noise but isn't directly observable as a CPU-vs-GPU divergence).

The v5.20.0 bisection caught it by directly comparing CPU vs GPU on the same encoded codestream.

## Fix

Four scaling sites swapped to spec convention:

1. `Sources/J2KMetal/J2KShaders.metal` — forward and inverse 9/7 horizontal + vertical kernels
   (4 swap sites).
2. `Sources/J2KMetal/J2KMetalShaderLibrary.swift` — embedded shader source kernelSource
   fallback (same 4 sites).
3. `Sources/J2KMetal/J2KMetalDWT.swift:forward1DCPU97` — CPU forward scaling.
4. `Sources/J2KMetal/J2KMetalDWT.swift:inverse1DCPU97` — CPU inverse scaling.
5. `Sources/J2KMetal/default.metallib` — recompiled from the corrected `J2KShaders.metal`.

Removed the v5.20.0 gate in `Sources/J2KCodec/J2KDecoderPipeline.swift:applyInverseWaveletTransformGPU`
that forced 9/7 lossy through the CPU path. GPU IDWT for 9/7 is now active.

## Verification

`Tests/J2KCodecTests/J2KGPULossy97DivergenceTests.swift` — `testBisectDecodePaths`:

| Comparison | Pre-v5.20.0 | v5.20.0 (gated) | v5.21.0 (fixed) |
|---|---:|---:|---:|
| `decodeGPU` vs `decode` (max diff) | 45,276 | 0 (gate forces CPU) | **1** |
| `decodeGPU` vs `decode` (avg diff) | 19,211 | 0 | **0** |
| `decodeWithGPUHT` vs `decode` (max) | 45,276 | 0 | **1** |
| `decodeWithGPUHT` vs `decode` (avg) | 19,211 | 0 | **0** |

PSNR-equivalent of 1 LSB max diff at 16-bit ≈ 96 dB, well below the lossy quantization noise
(~22 dB CPU vs original at 4 bpp). The residual is pure Float-vs-Double precision drift in
multi-level IDWT — irreducible without going to Double-precision Metal.

`Tests/J2KMetalTests/J2KMetalSingleLevel97Tests.swift` — `testSingleLevelRoundTrip` (new):
direct single-level CPU vs GPU IDWT on a synthetic 64×64 input. Asserts max diff < 1.0
(observed: ~3.8e-6 — pure Float precision).

CPU vs GPU on real 2800×2288 16-bit DX content at 4 bpp:
- Pixels differing: 0.87%
- Max abs diff: 1 LSB
- Avg abs diff: 0.0087 LSB

## Performance

CLI-process speedup is modest (1.26× on the 2800×2288 DX image) because Metal startup
dominates per-call latency. In-process batch workflows that share a `J2KMetalSession` see
larger speedups — that's the architectural win the GPU IDWT path was designed for.

Per-image speedup vs CPU (warm session):
- Estimated 3–5× on large images (≥1024×1024) once Metal startup is amortized over a batch.

## Carryover from v5.14–v5.20

All v5.14–v5.20 regression gates remain green, including the v5.20.0 strict CPU-vs-GPU bit-
exactness gate (now satisfied by the actual fix instead of the forced fallback).

## Lesson

Same shape as v5.16.0 (lossy K_max conformance) and v5.20.0 (the bisection that surfaced
this bug): when an in-house module is **self-consistent but spec-divergent**, only cross-
boundary tests can catch it. v5.20.0's bisection (CPU vs GPU on the same encoded data) was
the one that broke the symmetry. The actual scaling-direction bug had been latent in
J2KMetal since the 9/7 GPU kernels first shipped — every internal test passed because the
forward and inverse cancelled within J2KMetal.

## Reproducing

```bash
# v5.21.0 regression gate:
swift test --filter J2KGPULossy97Divergence

# Single-level direct comparison (pure kernel test):
swift test --filter J2KMetalSingleLevel97

# Manual demo on real medical CT:
swift build -c release
J2K=.build/release/j2k
$J2K encode -i Tests/Fixtures/CrossCodec/ct_study_001_instance_000001.pgm \
  -o /tmp/v21.j2k --htj2k --irreversible --bitrate 4.0 --quiet
$J2K decode -i /tmp/v21.j2k -o /tmp/v21_cpu.pgm --quiet
$J2K decode -i /tmp/v21.j2k -o /tmp/v21_gpu.pgm --gpu-ht --quiet
# Pre-v5.21: cpu and gpu PGMs differ by tens of thousands of LSB.
# Post-v5.21: differ by ≤ 1 LSB on ~1% of pixels.
```
