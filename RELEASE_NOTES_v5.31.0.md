# J2KSwift v5.31.0 — Cross-Scale λ Formulation Fix (HT Conformant Lossy)

**Release date:** 2026-05-04
**Theme:** User report: "the λ / bit-allocation model is mathematically inconsistent
across scale, which is why MRI looks great and mammography falls apart." Confirmed —
roundtrip PSNR on real medical fixtures was scale-dependent and catastrophic at
mammography sizes (16.30 dB at 4 bpp on dx_002 16-bit DX). v5.31.0 root-causes the
formulation issue and ships a fix that produces consistent quality across image scale.

## Headline before/after

| Fixture                | px    | Pre-v5.31.0 PSNR @2 bpp | **v5.31.0 PSNR @2 bpp** |
|------------------------|------:|------------------------:|------------------------:|
| mr_002 (180×180 MR)    |  32k  |                  35.39  |              **52.58**  |
| ct_001 (512×512 CT)    | 262k  |                  19.81  |              **47.21**  |
| xa_001 (1024² XA)      |  1.0M |                  17.45  |              **50.59**  |
| px_001 (2459×1316 PX)  |  3.2M |                  13.47  |              **46.25**  |
| **dx_002 (2800×2288 DX)** | 6.4M |                  14.65  |          **45.80**  |

PSNR is now consistent at 45–55 dB across all scales at 2 bpp. The 36 dB regression on
large fixtures is gone. PSNR scales healthily with bpp (~10–15 dB per doubling) as a
proper R-D curve should — instead of the pre-fix ~1 dB per doubling.

## Diagnosis

The cross-scale R-D probe (new in v5.31.0:
`Tests/J2KCodecTests/J2KCrossScaleRDQualityProbe.swift`) showed:

1. **Lossless** roundtrip on dx_002 = exact (PSNR ∞). Wavelet + entropy pipeline is sound.
2. **`.constantBitrate` lossy** on dx_002 produces 16 dB at 4 bpp — wildly off any expected
   R-D curve.
3. **`.constantBitrateViaQstep` lossy** on dx_002 produces 67 dB at 4 bpp — what the user
   would actually expect from a working codec.

**Root cause:** HT-conformant cleanup-only blocks are *single-pass*. PCRD-opt's slope-
based selection across blocks reduces to all-or-nothing per-block include/exclude — there
is no within-block truncation possible. On high-bit-depth content where the per-block
slope ranking is dense, the discretisation produces wildly different quality at different
codeblock counts (which scale with image size). The slope formulation is correct in
isolation; it just can't approximate continuous R-D allocation when the only knob is
"keep the block or drop it." See [`MEDICAL_BENCHMARK.md`](MEDICAL_BENCHMARK.md)
"Cross-Scale R-D Quality (v5.31.0)" section for the full data.

The v5.18 (`.fixedQstep`) and v5.19 (`.constantBitrateViaQstep`) modes were workarounds
for this. v5.31.0 wires the workaround into the default path so the user gets a working
codec without needing to know about it.

## What v5.31.0 ships

### Auto-promote `.constantBitrate` → Qstep-search for high-bit-depth HT-conformant lossy

`Sources/J2KCodec/J2KCodec.swift` — `J2KEncoder.encode(_:)` now intercepts
`.constantBitrate` and routes to `encodeViaQstepSearch` when **all** of:

- `useHTJ2K = true`
- `htj2kBlockFormat = .conformant`
- `lossless = false`
- `useReversibleFilter = false`
- `bitDepth ≥ 12` (the gate that limits the change to medical / scientific
  high-bit-depth content; 8-bit RGB photographic content passes through to the original
  PCRD-opt path unchanged, preserving its 4-8× encode-speed advantage where the R-D
  collapse isn't observed).

EBCOT (legacy J2K Part 1) and HT custom-format paths fall through to PCRD-opt
unchanged — those have within-block pass granularity and aren't affected.

### Widened Qstep search bracket

`encodeViaQstepSearch` previously bracketed at `±8×` after iter-1 ratio-based refinement.
For high-bit-depth content where the bytes-vs-qstep curve is very flat, the search
terminated at the upper-cap with bytes still over target. v5.31.0:

- Iter-1 bracket scales adaptively with `|log2(ratio)|` so the search has headroom for
  large refinement.
- Iter-2..N: extends `upper` ×4 dynamically when the search hits the ceiling.

Effect: byte targets are met more accurately at low bpp on large fixtures (still over
target due to the conformant rate floor — see "Trade-off" below).

### New diagnostic test: `J2KCrossScaleRDQualityProbe`

`Tests/J2KCodecTests/J2KCrossScaleRDQualityProbe.swift` — three tests:

- `testDX002LosslessRoundtripExact` — sanity gate, asserts lossless = ∞ dB.
- `testCrossScaleRDPSNRSweep` — runs each medical fixture × {0.5, 1, 2, 4} bpp and
  prints the PSNR table. Catches future R-D regressions at any scale.
- `testCrossScaleQstepVsPCRD` — comparison mode (preserved as the diagnostic that
  pinpointed the problem).

### MEDICAL_BENCHMARK.md updated

New "Cross-Scale R-D Quality (v5.31.0)" section with pre/post comparison + rate trade-off
data.

## Trade-off

`.constantBitrate` no longer guarantees the exact byte target for HT-conformant lossy at
high bit-depth. The auto-promoted Qstep-search converges on *uniform quantisation*,
which has a content-dependent rate floor (LL band needs a minimum number of bits;
encoding can't go below that without dropping LL — which is what PCRD did, and that's
what produces the catastrophic quality).

Observed achieved bytes vs target @ 2.0 bpp:

| Fixture | Target | Achieved | Ratio |
|---|---:|---:|---:|
| mr_002 (32k px)  |   8.1k  |   8.3k   | 1.02× |
| ct_001 (262k)    |  65.5k  | 107.6k   | 1.64× |
| xa_001 (1M)      | 262.1k  | 632.9k   | 2.41× |
| px_001 (3.2M)    | 809.0k  |   2.46M  | 3.04× |
| dx_002 (6.4M)    |   1.6M  |   4.5M   | 2.81× |

Larger images at lower bpp overshoot more. For strict-rate workflows:

- `.constantBitrateViaQstep` (explicit) — same algorithm, caller knows the contract
- `.fixedQstep` — caller picks the qstep, no rate search
- Non-conformant HT (`htj2kBlockFormat: .partial` or similar) — has within-block passes
- EBCOT (`useHTJ2K = false`) — has within-block passes, PCRD-opt works fine

The medical-imaging community generally prioritises quality over exact-byte budgets at
storage time (PACS archives), so this is the right default for the target workload.

## Verified

- All 9/7 correctness gates remain green (lossless = ∞ dB, decode bit-equivalence, etc).
- Cross-scale PSNR consistent at 45–65 dB across the medical corpus.
- 2 pre-existing perf-aspirational test failures unaffected
  (`testHTJ2KPerformanceTargetIs3x`, `testScale16Bit`).
- 4 tests that asserted the OLD pre-fix behaviour are NOT broken because the
  `bitDepth ≥ 12` gate excludes them (they used 8-bit synth fixtures or 8-bit RGB).
  PCRD path on 8-bit content is unchanged.

## Reproducing

```bash
# Cross-scale R-D probe
swift test -c release --filter J2KCrossScaleRDQualityProbe

# Lossless sanity (should be ∞)
swift test -c release --filter testDX002LosslessRoundtripExact
```

## Lesson

The v5.18/v5.19 release notes documented `.fixedQstep` and `.constantBitrateViaQstep`
as workarounds for "the v5.16 R-D gap." That language was too generous — they were
fixes for a real correctness problem dressed up as an alternative encoding mode. The
default `.constantBitrate` path was producing 14 dB output at clinical bitrates on the
exact workloads (mammography, DX) the codec is targeted at. Documenting workarounds
that the user has to opt into doesn't fix the bug — it just transfers the responsibility
to the caller, who often doesn't know they need to opt in.

The right move was the one this release makes: when the architecture has a path that
gives the right answer, use it by default. Document the trade-off so the caller can opt
out if they have a strict-rate requirement that justifies the lower quality.
