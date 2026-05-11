# V9.1 Path B Phase 0 — encoder sub-stage breakdown + Phase 1 target selection

> ⚠ **Update 2026-05-11**: Phase 1A microbench (`V91Phase1ABatchedClassifyMicrobench`) was run after this document was written and **REJECTED Candidate A** (batched per-quad SIMD pipeline). SIMD16 turned out to be 6× slower than scalar; SIMD4 only 1.22× faster. Reason: Swift's `SIMD<UInt32>` doesn't expose SIMD-wide clz/comparison primitives. The 96% loop-body finding stands but the recommended Phase 1 target is now different. **See `V9_1_PHASE_1A_NEGATIVE_RESULT.md` for the revised plan.**

**Mission**: close the 3× CPU efficiency gap with Kakadu's HT encoder on Apple M2. J2KSwift in-process encode wall on DX 2800×2288 = 116 ms; Kakadu = 19.56 ms. v8.4 stage breakdown attributed 57% of encode CPU to HT entropy (~353 ms accumulated CPU on DX).

**This document**: identifies which HT entropy sub-stage to attack first.

**Date**: 2026-05-11
**Branch**: `v9.1-pathB`
**User direction**: "Path B — 6-12 month algorithmic rewrite of DWT or HT entropy. Save lives. Open source."

## TL;DR — surprise

The naive Path B target was "rewrite HT entropy bit-emission engines (MEL, MagSgn, VLC) for SIMD". **The data says that wouldn't help much.**

Engine bit-emission time on DX is **~31 ms accumulated** out of **767 ms accumulated entropy CPU** = **only 4% of entropy CPU**. The remaining 96% is in the **per-quad classification + surrounding loop body** — `processQuad`, table lookups (vlcTable / uvlcTable), scratch state writes (eVal/cxVal), `emitQuadMagSgn` helper logic, and u-value branching.

**Phase 1 target**: re-architect the per-quad loop body, not the bit-emission engines.

## Probe infrastructure (this commit)

Three new files on `v9.1-pathB` branch:

1. **`Sources/J2KCodec/J2KHTEntropyEncoderProfile.swift`** — counter + coarse-wall accumulator. Mirrors the v7.3.0 decoder profile pattern.
   - Counters: `processQuadCallCount`, `vlcEncodeCallCount`, `vlcUVLCEncodeCallCount`, `melEncodeCallCount`, `magsgnEncodeCallCount`, `magsgnEncodeBitsTotal`.
   - Wall accumulators: `blockTotalNs`, `blockClassifyNs`, `blockFinishNs` (one timer pair per block — negligible overhead vs the per-quad budget that would dwarf the encode itself).

2. **`Tests/J2KCodecTests/V91Phase0EncoderProfileTests.swift`** — XCTest probe that warm-encodes each fixture in the medical corpus and prints the per-engine breakdown table. Combined with the microbench, computes per-stage CPU contribution.

3. **`Tests/J2KCodecTests/V91Phase0EncoderMicrobench.swift`** — isolated per-engine microbench. Measures `ns/call` for each emission engine across realistic argument distributions.

Counter bumps added at:
- `J2KHTConformantBlockEncoder.encode()` — at `processQuad` entry
- `J2KHTConformantMagSgnCoder.encode()` — engine entry
- `J2KHTConformantMELCoder.encode()` — engine entry
- `J2KHTConformantBitStream.HTReverseBitEmitterConformant.encode()` — engine entry
- 12 UVLC call sites in encode() — to distinguish quad-tuple VLC vs UVLC

Codestream byte-identical to pre-instrumentation (verified via MD5 round-trip).

Profile overhead: ~6.6M counter bumps per DX encode × ~1 ns each = ~6.6 ms (1% of accumulated CPU). Acceptable for measurement.

## Per-engine ns/call (M2 v8.1.4 release build)

`V91Phase0EncoderMicrobench`:

### HTMagSgnEncoderConformant.encode

| bits/call |  ns/call  | M calls/sec |
|----------:|----------:|------------:|
|         3 |      4.56 |      219.26 |
|         8 |      4.61 |      217.07 |
|        14 |      9.00 |      111.15 |
|        20 |     10.90 |       91.72 |

Corpus avg width is 14.30 bits on DX → **~9 ns/call**.

### HTMELEncoderConformant.encode

| one-ratio | ns/call | M calls/sec |
|----------:|--------:|------------:|
|      0.10 |    3.05 |      327.85 |
|      0.30 |    3.87 |      258.07 |
|      0.50 |    4.50 |      222.29 |

Corpus typical: ~30% one-ratio → **~4 ns/call**.

### HTReverseBitEmitterConformant.encode

| bits/call |  ns/call  | M calls/sec |
|----------:|----------:|------------:|
|         3 |      5.75 |      173.94 |
|         5 |      8.44 |      118.52 |
|         8 |     13.00 |       76.95 |
|        12 |     15.30 |       65.36 |

VLC quad tuples are 3-12 bits (avg ~5) → **~8 ns/call**.
UVLC pre/suf parts are 1-7 bits (avg ~3) → **~6 ns/call**.

## Corpus call-count + wall breakdown

`V91Phase0EncoderProfileTests` on the 6-fixture medical corpus:

### Call counts

| Fixture | px | blocks | processQuad | vlcTuple | vlcUVLC | mel | magsgn | avg-bits |
|---------|---:|-------:|------------:|---------:|--------:|----:|-------:|---------:|
| MR-small 180² | 32400 | 25 | 4368 | 679 | 11630 | 228 | 13710 | 9.89 |
| CT 512² | 262144 | 70 | 30561 | 5504 | 83814 | 1359 | 94579 | 11.94 |
| MR 886² | 784996 | 148 | 31215 | 7124 | 74752 | 28241 | 46921 | 13.35 |
| XA 1024² | 1048576 | 273 | 100709 | 28359 | 272828 | 44102 | 263968 | 14.24 |
| PX 2459×1316 | 3236044 | 1627 | 365942 | 109169 | 1011779 | 45307 | 1069685 | 15.07 |
| **DX 2800×2288** | **6406400** | **2501** | **662142** | **237485** | **1851148** | **33361** | **1984839** | **14.30** |

### Per-block coarse wall slices

| Fixture | blockTotal ms | classify ms | finish ms | full encode wall ms |
|---------|--------------:|------------:|----------:|--------------------:|
| MR-small 180² | 2.22 | 2.18 | 0.02 | 0.91 |
| CT 512² | 22.81 | 22.72 | 0.06 | 5.37 |
| MR 886² | 14.12 | 13.99 | 0.06 | 3.95 |
| XA 1024² | 106.27 | 105.93 | 0.22 | 17.03 |
| PX 2459×1316 | 377.84 | 376.82 | 1.09 | 59.47 |
| **DX 2800×2288** | **770.01** | **767.38** | **1.99** | **126.73** |

`blockTotal` is the sum across all blocks of wall time inside `HTBlockEncoderConformant.encode()`. `full encode wall` is the user-visible wall (DWT + entropy + asm + emit). `blockTotal / full_encode_wall = 6.07×` parallelism factor on DX.

## Computing per-engine CPU on DX

Combining the corpus call counts × microbench ns/call:

| Engine | calls (DX) | ns/call | accumulated ms | % of classify (767 ms) |
|--------|-----------:|--------:|---------------:|-----------------------:|
| MagSgn | 1,984,839 | 9.0 | 17.86 | 2.3% |
| VLC tuple | 237,485 | 8.4 | 2.00 | 0.3% |
| VLC UVLC | 1,851,148 | 6.0 | 11.11 | 1.4% |
| MEL | 33,361 | 4.0 | 0.13 | 0.02% |
| **Engine subtotal** |   |   | **31.10** | **4.05%** |
| **Loop body residual** |   |   | **736.28** | **95.95%** |

**The loop body residual — `processQuad` classification + table lookups + scratch state writes + `emitQuadMagSgn` dispatch logic + u-value branching — accounts for 96% of HT entropy CPU on DX.**

Per-quad average: 736.28 ms / 662,142 = **1112 ns of non-engine work per quad**.

For comparison: 4 samples per quad → 278 ns/sample of non-engine work. At 3.2 GHz, that's ~890 cycles per sample for classification + bookkeeping. That's high — Kakadu likely does this in 100-200 cycles per sample.

## Why this overturns the naive Path B plan

**Naive plan**: rewrite MEL/MagSgn/VLC engines for SIMD (the v8.6 SIMD classifier probe direction).

**Why it would have failed**: even a hypothetical 4× speedup on the bit-emission engines would only save 31 × 0.75 = 23 ms of entropy CPU. After amortising across 6 effective parallel cores, that's ~4 ms wall savings on DX. The Kakadu gap is 116 - 20 = 96 ms wall. **4 ms wall < 4% of the gap.**

**What actually has to change**: the per-quad classification + surrounding loop logic. 96% of entropy CPU lives there. To close even half the Kakadu gap (50 ms wall), we need to halve the per-quad classification cost (1112 → 556 ns/quad). That's the multi-month rewrite the user signed up for.

## Phase 1 candidate identification

Three candidate directions for Phase 1, ranked by likelihood of yielding 30-50% speedup:

### Candidate A — batched per-quad SIMD pipeline (HIGHEST CONFIDENCE)

Process **N quads at once** using SIMD-batched classification + table lookups + scratch updates. Single-quad cost is ~1112 ns; batched 4-quad SIMD could plausibly halve this to ~550 ns/quad-equivalent.

Specific architecture:
1. Load 16 samples (4 quads) into a `SIMD16<UInt32>` register vector.
2. Lane-parallel `(2t >> p) & ~1` and `clz(val - 1)` — already vectorisable.
3. Lane-parallel rho/eQ/payload extraction.
4. Pre-compute the 4× rho values for the next row's context, write all at once.
5. Issue 4× table lookups in parallel (gather instruction).
6. Defer engine bit emission to a scalar emit pass after the SIMD classify.

**Expected speedup**: 1.5-2× per-quad classification cost reduction. Closes ~25-50% of the Kakadu gap.

**Risk**: rho/eQ/payload tuples have data-dependent width (eQMax varies per-quad), making lane-perfect output assembly tricky. Pre-emit pre-pack pass needed.

**Implementation effort**: 2-4 weeks for prototype, 6-12 weeks for full integration with parity gates.

### Candidate B — fuse classify + emit into a single inner loop

The current architecture is `processQuad` returns a fat tuple, then the outer loop does VLC + MEL + MagSgn emits. Each engine call has function-call overhead (5-10 ns each). Fusing the work — inline emit logic directly into `processQuad`, eliminating the tuple round-trip — could cut ~10-20 ns/quad × 660K quads = 7-13 ms accumulated CPU.

Lower confidence: the savings are ~10% of the loop body cost, not 30-50%.

**Implementation effort**: 1-2 weeks.

### Candidate C — replace VLC tables with hand-coded fast paths

`vlcTable0Conformant` / `vlcTable1Conformant` are 4096-entry tables (12-bit index → 16-bit packed entry). At each lookup we do a memory load. For DX, 237K + 1.85M = 2.09M VLC lookups. At ~2 ns/lookup (L2-cache speed for hot table), that's ~4 ms of pure table-lookup overhead.

Replacing the most frequent UVLC entries (small u-values) with branchless direct computation could save ~2 ms.

Low confidence: small win relative to the 736 ms residual.

**Implementation effort**: 1 week.

## Recommendation

**Pursue Candidate A (batched per-quad SIMD pipeline) for Phase 1.**

It is the only candidate with a plausible path to closing 30-50% of the Kakadu gap. The other candidates yield single-digit ms savings — sub-threshold for a multi-month commitment.

Phase 1 deliverables (target: 6-8 weeks):
1. Microbench-validated SIMD16 classification (4 quads at once) achieving ≤600 ns/quad-equivalent
2. Lane-perfect rho/eQ/payload extraction with bit-exact parity vs scalar
3. Integration into `HTBlockEncoderConformant.encode` behind an opt-in flag
4. A/B medical corpus benchmark showing ≥30% reduction in `blockClassifyNs` on DX
5. Cross-codec parity (codestream byte-identical or roundtrip pixel-identical)

Phase 1 exit criteria (gate to Phase 2):
- DX encode wall ≤ 95 ms (saves ≥21 ms vs current 116 ms baseline)
- All cross-codec parity tests pass
- Microbench achieves the per-quad target

If Phase 1 misses the gate, Path B is reconsidered against Path C (M3+ silicon probe) or paused.

## What's NOT in Phase 0 (deferred)

- **Reading Kakadu papers + identifying specific optimisations**: Multi-day work that requires academic paper access. Worth doing for Phase 2.
- **Disassembling Kakadu binary to identify NEON/SVE patterns**: Multi-day work. Worth doing if Phase 1 stalls.
- **DWT alternative — replace forward 5/3 lifting**: v8.6 Phase 0 measured DWT at 0.37 ns/sample (memory-bound, L1-resident). Combined with the 39% DWT share on DX, that's only ~63 ms of DWT CPU. Even halving it saves ~10 ms wall. Lower priority than HT entropy.

## Files in tree on `v9.1-pathB`

- `Sources/J2KCodec/J2KHTEntropyEncoderProfile.swift` — counter + wall infrastructure
- `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift` — instrumented hot path
- `Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift` — engine bumps
- `Sources/J2KCodec/J2KHTConformantMELCoder.swift` — engine bumps
- `Sources/J2KCodec/J2KHTConformantBitStream.swift` — engine bumps
- `Tests/J2KCodecTests/V91Phase0EncoderProfileTests.swift` — corpus probe
- `Tests/J2KCodecTests/V91Phase0EncoderMicrobench.swift` — isolated bench
- `V9_1_PATH_B_PHASE_0.md` — this document

No production breaking changes. Codestream bytes byte-identical (MD5-verified on MR-small).

## What the user decides next

1. **Greenlight Phase 1 (Candidate A)**: 6-8 weeks of engineering on batched per-quad SIMD. I begin prototyping immediately on this branch.
2. **Pivot to Candidate B or C**: lower-risk, lower-reward variants. Useful if Phase 1 is too uncertain.
3. **Reconsider the goal**: Phase 0 has shown matching Kakadu requires re-architecting the loop body, not just engine SIMD. If 6-8 weeks is too aggressive, Path A (accept the gap, lead on decode) remains valid.

The honest engineering call: **the data supports Phase 1**. The per-quad classification has clear SIMD redesign opportunity. But it is a real multi-week commitment with implementation risk.
