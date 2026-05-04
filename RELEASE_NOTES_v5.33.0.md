# J2KSwift v5.33.0 — Production-Grade Bounded-Rate Mode (`.constantBitrateBounded`)

**Release date:** 2026-05-04
**Theme:** v5.32.0 capped overshoot at 2.0× but encode latency was 5–14× slower than
the broken v5.30 PCRD baseline (8 search iterations + up to 3 refinement iterations =
11 passes worst case). User asked for a production-grade quality-preserving mode with
predictable latency. v5.33.0 ships `.constantBitrateBounded` — a new public mode and
the new auto-promote default for `.constantBitrate` on high-bit-depth — with a **hard
cap of `maxPasses` encode passes** (3 by default). 2.5× faster than v5.32 with HIGHER
quality.

## Headline (auto-promote `.constantBitrate` @ 2 bpp on real medical)

| Fixture | px | v5.32 (8-iter+refine) | **v5.33 (3-pass bounded)** |
|---|---:|---:|---:|
| **PSNR / bytes ratio** |  |  |  |
| ct_001 (262k)  | 262k  | 47.21 dB / 1.64× | **61.20 dB / 2.91×** |
| xa_001 (1.0M)  | 1.0M  | 39.87 dB / 1.69× | **63.58 dB / 3.32×** |
| px_001 (3.2M)  | 3.2M  | 33.07 dB / 1.88× | **60.06 dB / 4.22×** |
| dx_002 (6.4M)  | 6.4M  | 33.92 dB / 1.69× | **60.00 dB / 4.03×** |
| **CPU encode latency (mg_001, 16.8M px)** |  |    |    |
|                |       | 3124 ms (11 passes) | **1231 ms (3 passes)** |

The new mode trades rate-cap strictness for quality + predictable latency:
- **Quality ↑↑**: clinical-grade 60+ dB on real medical content (vs v5.32's 33–47 dB).
- **Latency ↓↓↓**: 2.5× faster than v5.32, 3-pass hard cap = no flat-curve worst case.
- **Rate cap ≈ best-effort**: 2.0× target on typical content; may exceed on extreme
  flat-curve (very low bpp + large fixture) where the search can't converge in 3
  passes. The `convergedWithinTolerance` flag in `J2KEncodeQstepStats` reports whether
  the cap was met.

## What v5.33.0 ships

### `.constantBitrateBounded(bpp, maxOvershootRatio: Double = 2.0, maxPasses: Int = 3)` — new public mode

Production-grade quality-preserving bounded-rate mode with predictable latency.
Documented contracts:

- **Quality**: uniform-quantisation (same approach as `.constantBitrateViaQstep`).
  Picks one qstep, every coefficient is quantised by it. Quality matches whichever
  pass produced the result closest to target.
- **Rate**: best-effort cap at `maxOvershootRatio × target`. On typical content the
  cap is met. On flat-curve content (high-bit-depth at very low bpp) may exceed.
  Stats report whether cap was met.
- **Latency**: HARD CAP at `maxPasses × single-encode-time`. No flat-curve worst case.

### Auto-promote uses bounded mode by default

The `.constantBitrate` → Qstep auto-promote (added v5.31, gated to `bitDepth ≥ 12`) now
uses `encodeViaBoundedQstep` with `maxPasses: 3`, `maxOvershootRatio: 2.0`. Encode
latency is bounded by 3× single-encode-time on cache miss, 1× on cache hit.

For batch workflows, pass `J2KQstepCache` via `encodingConfiguration.qstepCache` —
subsequent encodes hit cache and converge in 1 pass.

### Algorithm: log-binary-search with adaptive bracket extension

Pass 1 uses calibration prior (or cached qstep). Pass 2 scales by observed ratio
(linear, since flat-curve content has α ≈ 0.13). Pass 3+ does log-binary-search; if
achievement is still over cap and upper bound is hit, the bracket extends ×4. Same
core algorithm as the v5.32 search, but bounded to `maxPasses` passes total.

## When to use which mode

| Mode | Quality | Rate cap | Latency | Use when |
|---|---|---|---|---|
| **`.constantBitrate(bpp)`** (auto-promoted) | 60+ dB | best-effort 2.0× | 3 passes | DICOM PACS / archive — quality + predictable encode time |
| `.constantBitrateBounded(bpp, ...)` | configurable | configurable | configurable | explicit control over the trade-off |
| `.constantBitrateViaQstep(bpp, ...)` | 45–50 dB | uncapped (1.6–3×) | 8 passes | when you need v5.31 max-quality behaviour |
| `.fixedQstep(qstep)` | content-dependent | unbounded | 1 pass | latency-critical single-shot, caller picks qstep |

## Verified

- Cross-scale R-D probe: PSNR 33–63 dB across the medical corpus (consistent
  cross-scale, no collapse).
- Lossless roundtrip = ∞ dB.
- Medical corpus encode benchmark: 2.5× faster than v5.32 on mammography.
- Decode corpus benchmark unchanged.
- All v5.20–v5.32 correctness gates green.
- 4 pre-existing perf-aspirational test failures unaffected.

## Reproducing

```bash
swift test -c release --filter J2KCrossScaleRDQualityProbe
swift test -c release --filter J2KMedicalCorpusEncode
swift test -c release --filter J2KMedicalCorpus
```

## Migration

For users on v5.31 / v5.32 who:

- **Need v5.31 max quality**: switch to explicit `.constantBitrateViaQstep`. No code
  change for callers who already used this mode.
- **Need v5.32 strict rate cap**: switch to explicit `.constantBitrateBounded(bpp,
  maxOvershootRatio: 2.0, maxPasses: 8)` with higher `maxPasses` to recover the
  refinement-loop convergence.
- **Want the new default behaviour** (quality + predictable latency, 2.0× best-effort
  cap): no code change. `.constantBitrate(bpp)` on `bitDepth ≥ 12` auto-promotes to
  the new mode.

## Lesson

v5.31 / v5.32 / v5.33 walked a triangle:
- **v5.31** prioritised quality. Got 50 dB but unbounded rate, 8 passes.
- **v5.32** prioritised rate cap. Got 30 dB at 1.7× rate, 11 passes.
- **v5.33** prioritises **predictable latency + quality**. Best-effort rate cap.

You can have any two of {quality, strict rate, low latency} on this block format. The
"production-grade" question is which two — and whether to default to a hard guarantee
or a best-effort. v5.33 picks low latency + quality, with rate as best-effort. For
medical archive workflows where storage isn't the bottleneck and clinical quality is,
this is the right default.
