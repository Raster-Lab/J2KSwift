# v9.5 Plan — Aggressive C optimization arc to beat Kakadu on M4

**Date:** 2026-05-11
**Target branch:** `v9.5-research` (will be created off v9.4.0 = main @ 5c90704)
**Mission:** drive the M4 warm-encode Kakadu gap below 1.0× — i.e., **J2KSwift faster than Kakadu** on DX/MG fixtures. Honest assessment: requires v9.5 + v9.6 in sequence; v9.5 targets ~2× gap closure.

## Honest current state (v9.4.0, M4 Mac16,10)

| Metric (DX 2800×2288)             | v9.4.0   | Kakadu HT | Gap     |
|-----------------------------------|---------:|----------:|--------:|
| Warm in-proc CPU encode (lossy)   |  94.9 ms |   ~21 ms  | **4.5×** |
| Daemon path (lossless)            |  72.2 ms |   20.6 ms | **3.5×** |
| CLI cold-shot in-proc (lossless)  | ~76 ms   |   20.6 ms | **3.7×** |

**Closing 3.5× to 1.0× requires ~71% wall reduction.** No single optimization gets there. Three sequential releases are realistic; v9.5 targets the first ~30-40% closure.

## Per-stage cost breakdown (v9.4.0, DX warm in-proc 94.9 ms)

Per v8.4 stage breakdown extrapolated to v9.4.0:

| Stage                         | v9.3 share | v9.4.0 estimate | Optimizable? |
|-------------------------------|-----------:|----------------:|--------------|
| Pre-process (color, DC shift) |        2%  |       ~2 ms     | Marginal     |
| DWT (forward 9/7 lifting)     |       12%  |      ~11 ms     | Yes (DWT C+NEON) |
| Quantization                  |        5%  |       ~5 ms     | Marginal     |
| **HT entropy (block encode)** |    **57%** |    **~54 ms**   | **Yes** (this release) |
| Rate-control + PCRD-opt       |       12%  |      ~11 ms     | Yes (M4-aware tuning) |
| Codestream emit + packets     |        8%  |       ~8 ms     | Yes (Data-direct) |
| Misc / orchestration          |        4%  |       ~4 ms     | Marginal     |

**Where each release lives:**
- **v9.5 (this plan):** push HT entropy from 54 ms → ~22 ms (entropy-only 2.5× win). Total DX wall: ~62 ms. Gap to Kakadu: ~3.0×.
- **v9.6:** rewrite DWT in C+NEON. 11 → 3 ms. Plus rate-control + codestream. Total DX wall: ~40 ms. Gap: ~2×.
- **v9.7:** GPU-pre-classified-tuples integration + cross-stage fusion. Total DX wall: ~25 ms. Gap: 1.2×.
- **v9.8 / v10.0:** algorithmic micro-optimizations + parity with Kakadu's deepest hand-tuned paths. Target: parity or better.

## v9.5 attack plan — push entropy from 54 ms → 22 ms

The HT entropy stage in v9.4.0 spends ~635 ns/quad (corpus average). To
hit a 22 ms wall, we need ~250 ns/quad. **2.5× speedup on the entropy
hot path.** Split into 5 phases, each with measurable bit-exact gate.

### Phase 5A — Per-row 16-quad NEON classifier (~3 work-days)

**Current state:** v9.4.0 NEON classifier handles **4 samples per quad
(1 quad)** at a time. The 4 boundary-check + scalar-load setup costs
per quad don't amortize.

**Change:** load **16 samples (8 quads → 4 rows of 2 quads)** into 4
NEON registers in one strided load sequence, classify all 16 in
parallel, then scalar-extract per-quad rho/eQMax/payload.

NEON intrinsics needed (Apple Silicon supports all):
- `vld1q_u32_x2` — load 8 UInt32 per call; two calls cover 16 samples
- `vshlq_u32 + vbicq_u32` — already used; lane-parallel `(t+t) >> p & ~1`
- `vclzq_u32` — already used; key NEON intrinsic for eQ
- `vceqzq_u32 + vmvnq_u32` — significance mask, already used
- `vmaxvq_u32` — horizontal max for eQMax aggregation (NEW use)
- `vpaddlq_u32` — pairwise add for rho construction (NEW use)

**Projected gain:** classifier 50 ns/quad → 15 ns/quad (-70% on
classifier). 4 quads' worth of NEON ops amortize 4× the setup cost.

**Bit-exact gate:** extend `V94NEONHotPathParityTests` to a new
`V95Row16ClassifierParityTests` with 1000-trial random sweep.

### Phase 5B — 64-bit MagSgn accumulator + SWAR FF-detect (~3 work-days)

**Current state:** `magsgn_encode64` uses a 32-bit accumulator + byte-
by-byte emit loop with per-byte FF-stuffing check.

**Change:** widen to 64-bit accumulator. When the accumulator has ≥
8 bits AND no 0xFF byte in the next 8 bytes (SWAR-detected), emit 8
bytes at once via `vst1_u8` + UInt64 store. Fall back to byte-by-byte
on FF-detected.

SWAR FF-detect on 64-bit accumulator:
```c
uint64_t x = accumulator;
uint64_t inv = x ^ 0xFFFFFFFFFFFFFFFFu;
uint64_t has_ff = (inv - 0x0101010101010101u) & ~inv & 0x8080808080808080u;
if (has_ff == 0) {
    // Fast path: write 8 bytes via vst1_u8.
}
```

On medical fixtures (<0.5% FF density per v7.4 measurement), the fast
path fires on >99% of 8-byte windows.

**Projected gain:** MagSgn 200 ns/quad → 50 ns/quad (-75%).

**Bit-exact gate:** the SWAR fast-path is bit-exact equivalent of the
byte-by-byte loop when no FF is present. Extend
`V94NEONHotPathParityTests` with high-density dummy data to force the
slow path; also dense-FF synthetic tests.

### Phase 5C — VLC reverse-emitter SWAR optimization (~2 work-days)

**Current state:** `vlc_encode` uses 8-bit accumulator with per-byte
reverse-FF-stuffing check.

**Change:** widen to 32-bit accumulator with 4-byte-at-a-time emit
when reverse-FF-stuffing predicate is clean. The reverse FF rule
("byte > 0x8F"): high-bit-only check, easy SWAR.

**Projected gain:** VLC tuple+UVLC 275 ns/quad → 100 ns/quad.

### Phase 5D — Stage fusion: per-row 2-quad batched emit (~3 work-days)

**Current state:** each `processQuad` call does its own setup, return-
tuple unpacking, then emits via separate calls. Per-quad overhead is
~100 ns of "everything except the actual emit work".

**Change:** restructure the encode body to process a full row (16
quads on 64-wide block) as a single tight loop. The 16 quads from
Phase 5A's classifier batch flow directly into a 16-quad batched
emit pass that:
- Pre-computes all 16 (tuple0, tuple1) VLC indices in one NEON shuffle
- Pre-computes all 16 Uq values
- Emits MagSgn + VLC + MEL + UVLC for all 16 quads in a tight inner
  loop without per-quad function-call boundary

**Projected gain:** per-quad overhead 100 ns → 25 ns (-75%).

### Phase 5E — Per-worker C-buffer hoisting via J2KEncoderPipeline (~2 work-days)

**Current state:** `encodeViaNEONHotPath` allocates 3×16 KB buffers
per block via `UnsafeMutablePointer.allocate`. For DX (1584 blocks),
that's ~9500 mallocs/frees per encode = ~1-2 ms accumulated CPU.

**Change:** mirror the v9.1 Phase 2d raw-engine buffer hoisting
pattern. The 4 worker scopes in `J2KEncoderPipeline` hoist 3 NEON-
output pointers once per worker; pass them through
`encodeCodeBlockConformant` to the NEON path. Eliminates per-block
allocs.

**Projected gain:** ~0.5-1 ms wall reduction on DX (small but free).

### Combined v9.5 projection

| Phase            | Per-quad win  | Cumulative ns/quad |
|------------------|--------------:|-------------------:|
| v9.4.0 baseline  |             — |              635   |
| 5A classifier    |      −35 ns   |              600   |
| 5B MagSgn SWAR   |     −150 ns   |              450   |
| 5C VLC SWAR      |     −175 ns   |              275   |
| 5D stage fusion  |      −75 ns   |              200   |
| 5E buffer hoist  |  ~marginal    |              200   |

**Target v9.5 per-quad cost: 200 ns/quad** (vs Kakadu's estimated ~80
ns/quad — still 2.5× behind on per-quad cost, but the gap closes
significantly).

**Target v9.5 DX wall:** entropy stage 54 ms × (200/635) = 17 ms.
Plus non-entropy 41 ms = **~58 ms total DX wall**.

**Target v9.5 Kakadu gap on DX:** 58 / 21 = **2.76×** (was 4.5× on
v9.4.0). **~38% gap closure in one release.**

## Beyond v9.5 — the path to actually beating Kakadu

The remaining 2.76× gap after v9.5 requires:

1. **v9.6: DWT + rate-control + codestream C+NEON port** (~3-4 weeks).
   Brings non-entropy stages from 41 ms → ~15 ms. New DX wall: 32 ms.
   Gap to Kakadu: ~1.5×.
2. **v9.7: GPU-pre-classified-tuples integration** (~2 weeks).
   Offloads the per-quad classifier (still ~15 ns/quad in v9.5) to
   Metal compute kernel, leveraging M4's 10-core GPU. New entropy
   stage: 8 ms. Total DX: 23 ms. Gap: ~1.1×.
3. **v9.8 / v10.0: parity sprint** (~4 weeks).
   Memory-layout-aware coefficient ordering, prefetch hints,
   coalesced VLC table accesses. Target: DX ≤ 21 ms = **parity with
   Kakadu** or marginally better.

The full arc: **v9.5 → v9.8, ~3-4 months**, with bit-exact gates at
every release, ending with J2KSwift at parity-or-better with Kakadu
on M4 daemon-path DX encode.

## Decision matrix for v9.5 ship vs research-close

After Phase 5E measurement on the v9.5-research branch:

| Outcome                                              | Decision |
|------------------------------------------------------|----------|
| Bit-exact gate fails (any of the 5 phases)           | Block, diagnose phase; do not ship |
| DX warm in-proc ≤ 50 ms (≥1.9× speedup over v9.4 94.9 ms) | **Graduate to v9.5.0 default-on**, like v9.4.0 |
| DX warm in-proc 50-70 ms (1.35-1.9× speedup)         | Ship v9.5.0 with each phase as opt-in env var |
| DX warm in-proc 70-85 ms (1.1-1.35× speedup)         | Ship the working phases default-on, hold the wash phases as opt-in |
| DX warm in-proc > 85 ms (less than 1.1× speedup)     | Close as research artifact (24th lever ceiling); v9.5 entry skipped on main |
| Any phase regresses below v9.4.0 baseline            | Revert that phase only; ship the rest |

## Bit-exact validation strategy

Every phase must pass the **existing 548+ assertion suite** before
its commit lands on the v9.5-research branch:
- `V94NEONHotPathParityTests` (500-trial random sweep + 11 corner
  cases + table identity)
- `HTBlockEncoderConformantTests`
- `HTSIMDIntegrationTests` (180K random sweep)
- `V91Phase2cArrayVsRawParityTests` (200-trial Array-vs-Raw parity)
- `HTCrossCodecConformantTests` (byte-identity vs OpenJPH + OpenJPEG
  + Kakadu)
- `HTSampleInfoSIMDPrototypeTests`
- `HTMagSgnCoderConformantTests`

PLUS new phase-specific bit-exact tests:
- `V95Row16ClassifierParityTests` — 1000-trial sweep on the new
  16-quad classifier (Phase 5A)
- `V95MagSgn64SWARParityTests` — synthetic high-FF-density data to
  force the slow path; mid-density to exercise fast path; corpus
  fixtures end-to-end (Phase 5B)
- `V95VLC32SWARParityTests` — same pattern (Phase 5C)
- `V95RowFusionParityTests` — fused-row vs unfused-row byte equality
  (Phase 5D)
- `V95BufferHoistParityTests` — hoisted-buffer path vs per-call-alloc
  path (Phase 5E)

## Risk register

1. **NEON-intrinsic-vs-auto-vec wash repeat** — v9.4 Day 6a found that
   explicit NEON `vclzq_u32` was within thermal noise of auto-vec
   scalar C. Phases 5A-D have explicit SIMD code; clang auto-vec
   might already be at parity. **Mitigation:** measure each phase
   independently with explicit-NEON vs scalar-fallback A/B; commit
   only when explicit NEON wins are ≥ 10% above noise floor. Phases
   that wash get reverted; the structural reorganization (5D) is
   kept regardless since it sets up for v9.6.

2. **Bit-exact regression on edge cases** — wider accumulators have
   more shift/mask boundary conditions; SWAR FF-detect has the
   `0x80808080` carry-edge corner case to handle. **Mitigation:**
   1000-trial sweep per phase + targeted corner-case tests
   (all-zeros, all-FF, mid-byte alignments, max-precision Uq=30).

3. **Phase 5D refactor risk** — restructuring the per-quad loop into
   per-row processing touches ~400 lines of the C encoder body. This
   is the highest-risk phase. **Mitigation:** keep the v9.4 per-quad
   path in tree behind a compile-time `#define` so we can A/B even
   in production builds.

4. **Stack-allocated scratch overflow in row-fusion** — Phase 5D may
   need larger scratch (16-quad context arrays vs 4-quad). **Mitigation:**
   compute the stack footprint upfront; if > 4 KB, switch to caller-
   owned buffers (continues the per-worker hoisting pattern from
   Phase 5E).

5. **Worker-buffer hoisting plumbing** — Phase 5E touches 5 files in
   J2KEncoderPipeline + adds 3 new optional parameters down the
   encodeCodeBlockConformant call chain. Existing v9.1 Phase 2d raw-
   engine plumbing is the template. **Mitigation:** strict mirror of
   the existing pattern; CI catches misrouting via 37 cross-codec
   tests.

## Implementation order rationale

Phases are ordered by:
- **Risk** (low → high): 5E hoisting is mechanical; 5A classifier is
  contained; 5B MagSgn is the next-most-important; 5C VLC is similar
  shape to 5B; 5D fusion is highest-risk last.
- **Win amortization**: 5B alone gives ~25 ns/quad; combined with 5A
  and 5C the structural wins compound.
- **Bit-exact gate independence**: each phase's gate is independent;
  if Phase 5B fails parity, we still ship 5A.

Suggested commit cadence:
- Day 1-2: Phase 5E + V95BufferHoistParityTests (warm-up; structural)
- Day 3-5: Phase 5A + V95Row16ClassifierParityTests
- Day 6-8: Phase 5B + V95MagSgn64SWARParityTests
- Day 9-10: Phase 5C + V95VLC32SWARParityTests
- Day 11-14: Phase 5D + V95RowFusionParityTests
- Day 15-16: Full corpus A/B measurement + cross-codec + contention
- Day 17: V9_5_BEAT_KAKADU_RESEARCH.md + decision per matrix
- Day 18: Squash-merge to main + tag v9.5.0 + push (if graduating)

Total: ~3.5 work-weeks for the v9.5 arc.

## What v9.5 does NOT attempt

- **DWT, rate-control, codestream C+NEON port** — deferred to v9.6.
  Each is a multi-week independent project.
- **GPU forward HT entropy default-on** — deferred to v9.7; the M2
  regression risk from V9_2_PHASE_C_M4_SILICON_PROBE.md still applies.
- **Decode-side optimization** — v9.3 positioned decode as marketable
  strength; encoder gap is the priority.
- **Multi-block batching API** — would change the public encode API
  surface; deferred until codec-API redesign discussion.

## Files anticipated to change in v9.5

| Path | Action |
|------|--------|
| `Sources/J2KCodecNEON/j2knhe_encode_block_ht.c` | Major refactor: 16-quad classifier, 64-bit MagSgn, 32-bit VLC, per-row fusion |
| `Sources/J2KCodecNEON/j2knhe_swar.h` | NEW — SWAR FF-detect helpers |
| `Sources/J2KCodec/J2KHTConformantBlockEncoder.swift` | Pass hoisted buffer triple through encodeViaNEONHotPath |
| `Sources/J2KCodec/J2KEncoderPipeline.swift` | Per-worker NEON-buffer hoisting (4 worker scopes) + plumb through encodeCodeBlockConformant |
| `Tests/J2KCodecTests/V95Row16ClassifierParityTests.swift` | NEW |
| `Tests/J2KCodecTests/V95MagSgn64SWARParityTests.swift` | NEW |
| `Tests/J2KCodecTests/V95VLC32SWARParityTests.swift` | NEW |
| `Tests/J2KCodecTests/V95RowFusionParityTests.swift` | NEW |
| `Tests/J2KCodecTests/V95BufferHoistParityTests.swift` | NEW |
| `V9_5_BEAT_KAKADU_RESEARCH.md` | NEW — research finding + decision |
| `RELEASE_NOTES_v9.5.0.md` | NEW — if graduating |
| `Scripts/v95_demo.sh` | NEW — if graduating, updated investor demo |
| `benchmark-results-Mac16_10-9.5.0-*.json` | NEW — cross-codec capture |

## Verification (per phase)

```bash
# Pre-flight
git checkout -b v9.5-research v9.4.0

# Per-phase bit-exact gate (must pass before next phase commits)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter \
  "V95.*ParityTests|V94NEONHotPathParityTests|HTBlockEncoderConformantTests|HTSIMDIntegrationTests|V91Phase2cArrayVsRawParityTests|HTCrossCodecConformantTests|HTSampleInfoSIMDPrototypeTests|HTMagSgnCoderConformantTests"

# Per-phase microbench
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter "V91Phase2ConcurrentContentionProbe"

# Final A/B (before graduation decision):
# v9.4 baseline
J2K_NEON_HOT_PATH=0  # forces legacy Swift; v9.5 default is C+NEON
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release \
  --filter "J2KMedicalCorpusEncodePerformanceTests/testCorpusEncodeAcrossAPIs$"

# v9.5 (default C+NEON with all 5 phases)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release \
  --filter "J2KMedicalCorpusEncodePerformanceTests/testCorpusEncodeAcrossAPIs$"

# Cross-codec position
python3 Scripts/benchmarks/cross_silicon_probe.py
# Saved as benchmark-results-Mac16_10-9.5.0-*.json

# Decision per the matrix above.
```

## Investor-demo updates if v9.5 ships

`Scripts/v95_demo.sh` (parallel to v94_neon_demo.sh) would extend the
investor demo with:
- Side-by-side v9.4.0 vs v9.5.0 wall comparison
- Updated Kakadu-gap closure narrative ("v9.3 6.5×, v9.4 4.5×, v9.5
  2.8× — on track to parity in v9.7")
- Cumulative bit-exact assertions count (548 + new phase tests)
- Updated lever-ceiling pattern (now 5-6 production wins)
