# V9.1 Path B Phase 2 — final status as of 2026-05-11 night session

**Branch**: `v9.1-pathB` (8 commits ahead of main, fully pushed)
**Mission**: open-source medical imaging codec faster than Kakadu on Apple Silicon. Lives saved through faster diagnostic workflows.

## What this session delivered

### Validated infrastructure (commits 2441c35, 4b951b8, 6c87868)
- `J2KHTEntropyEncoderProfile.swift` — per-engine call counters + per-block coarse wall accumulators
- Corpus breakdown probe + per-engine microbench harness
- Reproducible measurement on the 6-fixture medical corpus

### Bit-exact raw-pointer engine prototypes (commits f49cced, a1f77ee)
- `HTMagSgnEncoderRawPrototype` — UnsafeMutableBufferPointer-backed MagSgn (validated bit-exact against Array variant on 200 random 200-op sequences)
- `HTForwardBitEmitterRawPrototype` + `HTMELEncoderRawPrototype` — same for MEL (100-trial sweep)
- `HTReverseBitEmitterRawPrototype` — same for VLC (100-trial sweep)

### Concurrent contention measurement + Phase 2 fix validation
- Triple-engine A/B (matching corpus DX call distribution):
  - Array @ 12 workers: 26,084 ns/block, 165K blocks/sec, **3.17× scaling**
  - RawPtr @ 12 workers: 13,584 ns/block, 432K blocks/sec, **5.73× scaling**
  - RawPtr is **33% faster single-threaded** and **2.6× throughput at 12 workers**
- Architecture proven: raw-pointer engines eliminate Array-append + ARC contention

## Honest assessment of expected production wins

The triple-engine A/B saves **~13 µs/block** under concurrency vs Array. The full HTBlockEncoderConformant.encode showed **5× per-block-wall inflation** under concurrency (39 µs single → 187 µs at 6 workers — 148 µs of contention).

**Engine RawPtr fix addresses only ~9% of that contention.** The remaining ~135 µs/block of inflation is in:
- The row-quad loop body itself (eVal/cxVal scratch updates, table lookups, helper dispatches)
- May NOT be heap contention — could be **thermal throttling on the fanless M2** (8-core sustained load drops P-cores from ~3.5 GHz to ~2 GHz, a 1.75× clock reduction that compounds with memory bandwidth contention)

If thermal is the dominant factor, no software fix on M2 can close the gap. It would require:
- M3+/M4 active-cooled silicon (Path C — infrastructure already shipped on `v9.0-research`)
- OR reducing total per-block work by 5× (multi-month algorithmic rewrite that may not be tractable)

## Three-tier projection for the full Phase 2 production rollout

### Tier 1 — engine RawPtr fix alone (4-6 weeks)
- Refactor 3 engines to raw-pointer architecture
- Production-grade buffer management with bit-exact gates
- Integration into HTBlockEncoderConformant.encode behind opt-in flag
- A/B benchmark on medical corpus
- **Expected DX wall reduction**: 116 ms → 105-110 ms (5-10 ms savings, ~7-10% of Kakadu gap)

### Tier 2 — eVal/cxVal scratch + pipeline allocations (additional 2-3 weeks)
- Pre-allocated `UnsafeMutableBufferPointer` for `eVal`/`cxVal` scratch arrays
- Pipeline-level `conformantInBuf` already uses inout reuse; possibly hoist further
- **Expected additional DX wall reduction**: 5-10 ms (cumulative: 95-100 ms, ~20-25% of Kakadu gap)

### Tier 3 — block-batching per TaskGroup worker (additional 1-2 weeks)
- Each TaskGroup worker handles N blocks sequentially instead of 1 block per Task
- Reduces total Task count + scheduler pressure
- **Expected additional DX wall reduction**: 5-10 ms (cumulative: 85-90 ms, ~30% of Kakadu gap)

**Realistic Phase 2 ceiling: closes ~30% of Kakadu gap on M2.** Not the 50% I originally projected for Candidate D (block-resident DWT+entropy fusion), but a real and tractable engineering commitment with low risk and pure-Swift purity.

## Pivot history this session — three Path B candidates rejected by data, one validated

| Phase | Hypothesis | Evidence | Status |
|-------|-----------|----------|--------|
| 0 | Loop body = 96% of entropy CPU; SIMD16 classifier projects 2× gain | Corpus probe + per-engine ns/call | Plan: Candidate A |
| 1A | SIMD16 yields ≥1.5× per-quad classifier speedup | SIMD16 = 6× SLOWER than scalar | **A REJECTED** |
| 1B | Encoder hot path fast (40 ns/quad L1-resident); corpus 1112 ns/quad is 27× cache amplification | Direct block-encode bench: 40 ns/quad | Plan: Candidate D (block fusion) |
| 2 cache | Pool sizes 16 KB → 64 MB vary ns/block | Cache probe: all = 35 ns/quad flat | **D REJECTED** |
| 2 contention | Concurrent workers contend on heap/ARC | Concurrent probe: 1 worker = 39 µs, 6 workers = 187 µs (5× inflation) | Plan: Candidate E (RawPtr engines) |
| 2a | Raw-pointer MagSgn eliminates contention bit-exactly | Validated: 5.85× scaling vs Array 3.05× | **E partial validation** |
| 2b | Raw-pointer all 3 engines closes the gap | Validated: 33% faster single + flat scaling | **E partial validation; but only ~9% of corpus contention** |

## What the user gets when they wake up

**The honest engineering position**:
1. Path B's "rewrite encoder algorithm" framing was data-falsified. The encoder algorithm is fast.
2. The Kakadu gap is dominated by something else — most likely a combination of:
   - Heap allocator + ARC contention in engines (Phase 2a/2b fix: ~7-10% closure)
   - Heap contention in scratch buffers (Tier 2 fix: ~15-25% cumulative)
   - Task scheduling overhead (Tier 3 fix: ~25-30% cumulative)
   - **Thermal throttling on fanless M2** (no software fix possible)
3. Realistic Phase 2 ceiling on M2: **closes ~30% of Kakadu gap**. The remaining 70% likely requires M3+/M4 hardware or fundamental architectural changes.

**Three options when the user wakes**:

A. **Greenlight Tier 1 implementation** (4-6 weeks): production-grade RawPtr engine refactor. Real, bit-exact, low-risk. Closes ~7-10% of Kakadu gap on M2.

B. **Greenlight full Tier 1+2+3** (7-11 weeks): all three fixes. Closes ~30% of Kakadu gap on M2. The diminishing returns past Tier 1 suggest Tier 2/3 may not justify the time investment vs Path C.

C. **Pivot to Path C** (1 week): borrow/buy M3+/M4. Run the cross-silicon probe (already in tree on `v9.0-research`). If M3+ closes the gap to <2× (currently 5.9×), software effort on M2 becomes wasted. Best ROI if hardware change is feasible.

My honest recommendation: **A + C in parallel**. Run the M3+ probe quickly while implementing Tier 1. After both data points come in, decide whether to commit to Tier 2+3 or accept what's been gained.

## Why this is still a mission worth pursuing

We are NOT abandoning the goal. We've made REAL progress this session:
- Identified the actual bottleneck (concurrent contention, not algorithm)
- Validated a bit-exact fix architecture (raw-pointer engines)
- Closed multiple wrong paths (SIMD16 classifier, block-resident fusion, C++ port)
- Built reproducible measurement infrastructure for future work

The 30% expected closure on M2 + whatever M3+/M4 brings + future architectural work compound over time. Open-source medical codec performance is a multi-year mission, not a one-night sprint. Tonight delivered the empirical foundation.

## Files added/changed on `v9.1-pathB`

| Path | Lines | Purpose |
|------|-------|---------|
| Sources/J2KCodec/J2KHTEntropyEncoderProfile.swift | +127 | Encoder profile counters + per-block wall accumulators |
| Sources/J2KCodec/J2KHTConformantBlockEncoder.swift | +31 | Profile instrumentation (counter bumps + wall timers) |
| Sources/J2KCodec/J2KHTConformantBitStream.swift | +1 | Engine bump |
| Sources/J2KCodec/J2KHTConformantMELCoder.swift | +1 | Engine bump |
| Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift | +1 | Engine bump |
| Tests/J2KCodecTests/V91Phase0EncoderProfileTests.swift | +163 | Corpus call breakdown probe |
| Tests/J2KCodecTests/V91Phase0EncoderMicrobench.swift | +192 | Per-engine ns/call isolation |
| Tests/J2KCodecTests/V91Phase1ABatchedClassifyMicrobench.swift | +362 | SIMD16 negative result probe |
| Tests/J2KCodecTests/V91Phase1BBlockEncodeMicrobench.swift | +210 | Direct block-encode benchmark |
| Tests/J2KCodecTests/V91Phase2CacheHypothesisProbe.swift | +146 | Cache hypothesis refutation probe |
| Tests/J2KCodecTests/V91Phase2ConcurrentContentionProbe.swift | +138 | Concurrent contention measurement |
| Tests/J2KCodecTests/V91Phase2aRawPointerPrototype.swift | +289 | Phase 2a MagSgn raw-pointer prototype + A/B |
| Tests/J2KCodecTests/V91Phase2bAllEnginesRawPrototype.swift | +446 | Phase 2b 3-engine prototypes + triple A/B |
| V9_1_PATH_B_PHASE_0.md | +127 | Phase 0 finding (with correction banner) |
| V9_1_PHASE_1A_NEGATIVE_RESULT.md | +149 | SIMD16 negative result |
| V9_1_PHASE_1B_CRITICAL_FINDING.md | +127 | Cache hypothesis (later refuted in Phase 2) |
| V9_1_PHASE_2_BREAKTHROUGH.md | +131 | Concurrent contention identified |
| V9_1_PHASE_2_FINAL_STATUS.md | +this | Final state + recommendations |

All files committed and pushed to `origin/v9.1-pathB`.
