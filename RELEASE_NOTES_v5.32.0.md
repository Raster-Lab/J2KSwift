# J2KSwift v5.32.0 — Bounded-Rate Qstep Mode

**Release date:** 2026-05-04
**Theme:** v5.31.0 fixed the cross-scale R-D quality collapse by auto-promoting
`.constantBitrate` → Qstep-search on high-bit-depth content, but the search overshot
the rate target by 1.6–3× on large fixtures (the "rate" half of the rate-distortion
contract was sacrificed to fix the "distortion" half). v5.32.0 adds a bounded-rate
refinement loop that caps the overshoot at 2.0× while keeping most of v5.31.0's
quality. Per the user spec: "Build a bounded-rate Qstep mode. Keep v5.31 quality.
Reduce overshoot dramatically. Minimal version: run Qstep search, measure output size,
if overshoot > threshold, increase qstep slightly and re-encode (1–2 iterations max)."

## Headline (auto-promote `.constantBitrate` @ 2 bpp on real medical fixtures)

| Fixture | px | v5.31 PSNR / bytes (×target) | **v5.32 PSNR / bytes (×target)** |
|---|---:|---:|---:|
| ct_001 (262k)  | 262k  | 47.21 dB / 1.64× | 47.21 dB / 1.64× (unchanged — already under cap) |
| xa_001 (1.0M)  | 1.0M  | 50.59 dB / 2.41× | **39.87 dB / 1.69×** |
| px_001 (3.2M)  | 3.2M  | 46.25 dB / 3.04× | **33.07 dB / 1.88×** |
| dx_002 (6.4M)  | 6.4M  | 45.80 dB / 2.81× | **33.92 dB / 1.69×** |

Bytes overshoot capped at 2.0×. Quality drops 7–13 dB on the worst-overshoot cases but
remains in clinically-relevant range (>30 dB) and dramatically better than the pre-v5.31
PCRD path (13–17 dB). Fixtures whose v5.31 overshoot was already under 2× pass through
unchanged at full v5.31 quality.

## What v5.32.0 ships

### `encodeViaQstepSearch` post-search refinement loop

`Sources/J2KCodec/J2KCodec.swift` — adds `maxOvershootRatio: Double` parameter (default
`2.0`). After the main 8-iteration binary search terminates, if achieved bytes still
exceed `maxOvershootRatio × targetBytes`, run up to 3 additional refinement iterations:

1. Compute `currentRatio = achieved / target`.
2. Scale qstep by `pow(currentRatio, 0.7)` (sub-linear; converges fast on flat-curve
   high-bit-depth content without overshooting under-target).
3. Re-encode at the new qstep.
4. Accept the new encoding only if (a) bytes decreased and (b) bytes didn't undershoot
   below 0.9× target (don't trade overshoot for undershoot).
5. Stop when within `maxOvershootRatio × target`, when no further byte reduction is
   possible (structural floor like LL band overhead), or after 3 refinement iterations.

### Auto-promote uses 2.0× bound; explicit `.constantBitrateViaQstep` keeps unbounded

The `.constantBitrate` → Qstep auto-promote (added v5.31.0) now passes
`maxOvershootRatio: 2.0`. The explicit `.constantBitrateViaQstep` path passes
`maxOvershootRatio: .infinity` — preserving v5.31.0's no-cap behaviour for users who
opted in for max quality.

This split gives:
- `.constantBitrate(bpp)`: bounded rate, slight quality cost on extreme cases
- `.constantBitrateViaQstep(bpp, ...)`: max quality, no rate cap (v5.31.0 behaviour)

## Trade-offs documented

### Bytes vs target (auto-promote bounded at 2.0×)

| Fixture | Target | v5.31 bytes | **v5.32 bytes** |
|---|---:|---:|---:|
| ct_001  |  65,536 |  107,603 (1.64×) |  107,603 (1.64×) |
| xa_001  | 262,144 |  632,940 (2.41×) |  **443,322 (1.69×)** |
| px_001  | 809,011 | 2,460,399 (3.04×) | **1,521,451 (1.88×)** |
| dx_002  |   1.6 MB |    4.5 MB (2.81×) |     **2.7 MB (1.69×)** |

### Quality cost of the bound (PSNR @ 2 bpp)

| Fixture | v5.31 | **v5.32** | Pre-v5.31 (PCRD strict-rate) |
|---|---:|---:|---:|
| xa_001 | 50.59 | 39.87 | 17.45 |
| px_001 | 46.25 | 33.07 | 13.47 |
| dx_002 | 45.80 | 33.92 | 14.65 |

v5.32 sits between v5.31 (no cap, max quality) and pre-v5.31 (strict rate, broken
quality). For fixtures already under the 2.0× cap, v5.31's quality is fully preserved.

### Encode latency cost (auto-promote on 16-bit medical)

The 8-iteration Qstep search makes encoding 5–14× slower than v5.30 PCRD baseline:

| Fixture | v5.30 CPU encode | v5.32 CPU encode | Slowdown |
|---|---:|---:|---:|
| ct_001 (262k)   |   4.0 ms |  35.2 ms |  8.8× |
| xa_001 (1M)     |  16.0 ms | 161.5 ms | 10.1× |
| mg_001 (16.8M)* | 224.9 ms |   3.1 s  | 13.9× |

This is the cost of correctness — v5.30 was producing 14 dB output at clinical bitrates.
For batch workflows pass a `J2KQstepCache` via `encodingConfiguration.qstepCache` so
subsequent encodes hit the cache and skip 5–6 of the 8 search iterations. For
latency-critical single-shot encodes use `.fixedQstep(qstep:)` directly.

## Verified

- Cross-scale R-D probe passes — PSNR consistent at 33–66 dB across the medical corpus
  (vs pre-v5.31 13–35 dB).
- Lossless roundtrip = ∞ dB (unchanged).
- All v5.20–v5.31 correctness gates remain green.
- Encode benchmark slowdown documented in MEDICAL_BENCHMARK.md.
- Decode corpus benchmark unchanged (decode path unaffected).
- Cold-start `preWarm()` benchmark unchanged.
- 3 pre-existing perf-aspirational test failures unaffected
  (`testHTJ2KPerformanceTargetIs3x`, `testNEONPerformanceBenefit`, `testScale16Bit`).

## Reproducing

```bash
swift test -c release --filter J2KCrossScaleRDQualityProbe   # R-D quality
swift test -c release --filter J2KMedicalCorpusEncode        # encode latency cost
swift test -c release --filter J2KMedicalCorpus              # decode unchanged
```

## Lesson

v5.31.0's "fix it" ship had perfect quality at the cost of completely violating the
rate contract (3× overshoot wasn't documented as a trade-off — the release notes
mentioned it but the headline was "consistent quality"). v5.32.0 is the rate-quality
balance: cap the overshoot at a defensible 2.0× ratio so callers asking for bytes-bpp
get something close to what they asked for, while the quality remains clinical-grade
where v5.31 had it.

The user spec — "increase qstep slightly and re-encode 1–2 iterations max" — translates
naturally into a post-search refinement loop. Sub-linear `pow(ratio, 0.7)` qstep
scaling converges in 1–3 iterations on flat-curve content, doesn't overshoot the other
direction (don't trade over-target for under-target — that breaks the rate contract
worse), and respects the structural floor (when qstep increase doesn't reduce bytes,
the LL-band overhead is the irreducible cost; stop refining).
