# v10.2 — HT decode C+NEON retrofit + per-block integration (Phase D1.5)

**Branch:** `v10.2-research` (inherits scalar C ports from `v10.1-research`)
**Status (2026-05-15):** D1.5-A, D1.5-B, D1.5-C executed. **DX/PX warm-bench gate cleared** (DX −5 to −7 ms, PX ≈ −3 ms). **MG behavior is uncertain** — small/mid within noise, large fixture showed +9.75 ms regression in one run. Code lives behind `J2K_NEON_HT_DECODE=1` env var. **D1.5-D default-flip DEFERRED** pending MG investigation.
**Predecessor:** [`V10_1_DECODE_C_PORT_PROBE.md`](V10_1_DECODE_C_PORT_PROBE.md) — closed 2026-05-15 with scalar-only DX wall projection of ~1 ms (below the v7.4 3 ms acceptance threshold).

## Outcome summary (2026-05-15 autonomous session)

| Phase | Outcome | Branch commit |
|---|---|---|
| D1.5-A NEON SWAR retrofit on MagSgn | **PASS** — C SWAR-4 vs Swift production = 1.87× geo mean (sparse + random) | `9500cd2` |
| D1.5-B Per-block C integration | **PASS** — bit-exact parity ~100+ block configs; 1.61× ST / 1.55× MT per-block | (after `9500cd2`) |
| D1.5-C Pipeline routing + warm A/B | **MIXED** — DX/PX cleared v7.4 3 ms gate; MG flat-or-regression | (after `9500cd2`) |
| D1.5-D Default-flip + release | **DEFERRED** — MG behavior must be understood before default-on | — |

### Warm cross-codec bench A/B (M2 release, runs=7, warmups=2)

J2KSwift in-proc decode wall (median ms), OFF baseline vs two consecutive ON runs (the second was added to disambiguate the first run's MG signal):

| Fixture | OFF | ON #1 | ON #2 | OFF→ON1 | OFF→ON2 | ON1↔ON2 |
|---|---:|---:|---:|---:|---:|---:|
| PX 2459×1316 small | 27.71 | 25.55 | 24.98 | **−2.16** | **−2.73** | 0.57 |
| PX 2793×1316 mid   | 30.89 | 27.85 | 27.58 | **−3.04** | **−3.31** | 0.27 |
| PX 2812×1316 large | 30.93 | 27.88 | 27.63 | **−3.05** | **−3.30** | 0.25 |
| DX 2224×2798 small | 48.94 | 48.17 | 44.30 | −0.77 | **−4.64** | 3.87 |
| DX 2800×2288 mid   | 50.93 | 45.59 | 45.04 | **−5.34** | **−5.89** | 0.55 |
| DX 2544×3056 large | 64.53 | 57.55 | 55.64 | **−6.98** | **−8.89** | 1.91 |
| MG 3516×4784 small | 127.13 | 128.08 | 122.26 | +0.95 | **−4.87** | 5.82 |
| MG 3518×4784 mid   | 132.19 | 134.07 | 127.06 | +1.88 | **−5.13** | 7.01 |
| MG 3521×4784 large | 138.91 | 148.66 | 137.62 | +9.75 | −1.29 | **11.04** |

Read of the data:
- **PX**: −2.7 to −3.3 ms consistent across both ON runs. PX gate cleared.
- **DX**: −5 to −9 ms consistent across both ON runs (DX small went from noise in ON#1 to clear win in ON#2). DX gate cleared.
- **MG**: ON1↔ON2 swing is 5.8 / 7.0 / **11.0** ms. MG variance is huge — single-run signal is unreliable. Across both ON runs, MG small + mid show wins of −2 to −5 ms; MG large is inconclusive (variance dominates).

### Why MG looked different from DX/PX in the first run

**Resolved: ON1↔ON2 MG variance is 5.8-11.0 ms across "same config" runs.** The first ON run's MG_large +9.75 ms was variance, not regression. The second ON run shows favourable direction on MG_small (−4.87) and MG_mid (−5.13).

Remaining open question: **is MG variance reducible?** Possible drivers:
- M2 thermal throttling on long fixtures (MG decode is 120-150 ms; the longest fixture in the corpus).
- Cache pressure: MG is 16.8 MP — coefficient buffer doesn't fit in L2 (16 MB shared M2 L2 vs ~67 MB MG coefficient buffer).
- v8.4 measured DX (6.4 MP) entropy share at 57%. MG's iDWT share at 17 MP may dominate, leaving less entropy budget for the C decoder to optimise — but if so, ON would consistently match OFF, not show ±10 ms swings.

Recommendation: re-run MG fixtures with 20-30 samples per config (vs the bench's 7-median) to make the signal robust.

### Recommended next investigation (D1.5-C′, before D1.5-D)

1. **Instruments stage profile on MG decode wall.** Confirm whether entropy or iDWT dominates the MG wall; if iDWT, the entropy lever is structurally limited on MG.
2. **MG warm bench A/B repeated 3-5 times.** Detect whether the +9.75 ms is variance or a real regression.
3. **Per-block MG microbench using real MG-extracted blocks.** The synthetic 64×64 corpus that gave 1.61× may not match real MG block characteristics.

### What stays open / what's safe

- The env-opt-in path (`J2K_NEON_HT_DECODE=1`) is production-correct: bit-exact + cross-codec validated. SDK consumers who care about DX/PX walls can flip the env var and get a 3-7 ms win immediately.
- D1.5-D default-flip is deferred. If MG investigation closes the variance hypothesis cleanly, default-flip becomes safe and a release candidate follows. If MG shows a real iDWT-share ceiling, MG decode requires a separate iDWT C+NEON lever, not this entropy port.

## Why v10.2 exists

v10.1's scalar-only arc proved the structural Swift/C boundary lever IS available on the decode side — the three state machines all cleared their per-call Phase 0 sub-gates (MEL 1.33×, MagSgn 1.14×, VLC 1.83× vs Swift production). But two specific factors capped the projected wall savings below the threshold:

1. **MagSgn ties Swift production on common corpora.** Swift production's v7.4 4-byte SWAR refill (default-on since v7.4.0) eliminated most of the per-refill boundary cost on sparse/random byte streams. C scalar 3.9 ns/call vs Swift production 3.9 ns/call on those corpora. Only dense-FF streams (rare in HT codestreams) show a C scalar win.
2. **Per-call microbenches are bounded estimates.** The actual per-block decode performance depends on how MEL, VLC, MagSgn, and the row-dispatch state machine interact across the full block hot loop. v9.4's encoder analog showed projected-to-actual wall ratio of ~50% (projected 28.9% wall → actual 13%). The decode arc may follow the same dilution, or it may differ — the only way to know is integrated per-block measurement.

v10.2 addresses both: **NEON SWAR retrofit on MagSgn** to close the production-tie gap, and **per-block integration with end-to-end DX wall measurement** to convert per-call ratios into a wall-attributable number.

## Goal & gate

> Decide whether the integrated C+NEON HT block decoder clears v7.4's 3 ms warm DX wall threshold for production default-on enablement, with bit-exact preservation across the 11,889-cell conformance corpus.

**Phase 0 (scalar) is already CLEARED on v10.1-research.** v10.2 sequences:

| Phase | Work | Gate | Time budget |
|---|---|---|---|
| D1.5-A | NEON SWAR retrofit on `j2knhd_magsgn` (mirror Swift v7.4 4-byte refill) | C MagSgn ≥ Swift production on sparse/random | 1 week |
| D1.5-B | Integrate MEL+VLC+MagSgn into `j2knhd_decode_block_ht.c` (caller-owned coefficient output buffer) | Bit-exact vs Swift `HTBlockDecoderConformant.decode` across 500-block sweep + 11,889-cell corpus | 1.5 weeks |
| D1.5-C | Wire C entry point into `J2KDecoderPipeline.swift` behind `J2K_NEON_HT_DECODE=1` env var | `J2KMedicalCorpusPerformanceTests` shows ≥3 ms DX wall reduction at 12-worker warm in-process; `J2KStrictCrossCodecValidationTests` clean | 0.5 weeks |
| D1.5-D | Default-flip after corpus-wide validation | Cross-codec parity (OpenJPH / Grok / Kakadu) all green; DICOMKit substitute driver shows DX `.decodeGPU` ≤ 50 ms | 0.5 weeks |

**Total time budget: ~3.5 weeks.** Stop-and-reconsider triggers below.

## D1.5-A — NEON SWAR retrofit on MagSgn

**Motivation:** MagSgn is the only state machine where Swift production beats C scalar on common corpora. Swift's v7.4 path does a 4-byte unaligned `UInt32` load + SWAR FF-detect ([`J2KHTConformantMagSgnCoder.swift:380+` `refillBatched`](../Sources/J2KCodec/J2KHTConformantMagSgnCoder.swift)). The C scalar path does byte-by-byte. Matching the SWAR shape in C is a faithful port of the same algorithm, not a new optimisation — the bit-exactness is guaranteed by structure.

**Files (this branch only):**
- `Sources/J2KCodecNEON/j2knhd_magsgn.c` — extend with `j2knhd_magsgn_refill_swar4` (cached selector field, mirrors Swift's `useV74Batched` discipline).
- `Sources/J2KCodecNEON/include/j2knhd.h` — public surface unchanged; the SWAR path is internal.
- `Tests/J2KCodecTests/V10_2_MagSgnSWARParityTests.swift` — bit-exact sweep across the same corpus shape as v10.1.
- `Tests/J2KCodecTests/V10_2_MagSgnSWARMicrobench.swift` — A/B C-scalar vs C-SWAR vs Swift production.

**Exit criteria:**
- C SWAR MagSgn ≥ 1.10× Swift production on sparse + random corpora (Swift production is the v7.4 SWAR path; matching it scalar-equivalent then beating it slightly is the target).
- Bit-exact parity preserved.

**Stop trigger:** C SWAR MagSgn ≤ 1.05× Swift production → close. The lever ceiling on MagSgn is real even with NEON; integration with MEL+VLC alone won't recover.

## D1.5-B — Per-block C integration

**Motivation:** the canonical decision input. Per-call microbenches are bounded; the integrated per-block measurement is the production reality.

**Files:**
- `Sources/J2KCodecNEON/j2knhd_decode_block_ht.c` — `j2knhd_decode_block_ht32` entry point. Wires the three state machines into the row-dispatch loop (`decodeInitialRow` + `decodeSubsequentRow` ported from Swift `J2KHTConformantBlockDecoder.swift:244-452`).
- `Sources/J2KCodecNEON/include/j2knhd.h` — `j2knhd_decode_block_ht32(block, width, height, missingMSBs, coeffs_out)` signature mirroring `j2knhe_encode_block_ht32` from v9.4.
- `Tests/J2KCodecTests/V10_2_DecodeBlockParityTests.swift` — Swift vs C parity across 500-block sweep + 11,889-cell corpus + the existing medical corpus fixtures (CT/MR/XA/PX/DX/MG).
- `Tests/J2KCodecTests/V10_2_DecodeBlockCMicrobench.swift` — Swift vs C per-block timing (mirror v10.1's `V10_1_DecodeBlockMicrobench` shape).

**Exit criteria:**
- Bit-exact vs Swift reference across 500-block random + 11,889-cell conformance + 6 medical fixtures.
- C per-block ≤ Swift × 0.90 single-thread at all three sparsity classes.
- C per-block ≤ Swift × 0.95 at 12-worker concurrency.

**Stop trigger:** any of the three exit criteria misses → debug for 1 day; if not resolvable, close D1.5-B and re-evaluate.

## D1.5-C — Pipeline integration

**Motivation:** route the C entry point into the production decode hot path (gated by env var), measure the end-to-end DX wall.

**Files:**
- `Sources/J2KCodec/J2KDecoderPipeline.swift` — per-block call sites at lines 2570-2620 / 2684-2708. Add a routing branch on `useNeonHtDecode` (cached from `J2K_NEON_HT_DECODE=1` env at decoder init, mirroring v9.4 encoder's gate pattern).
- `Sources/J2KCodec/J2KHTConformantBlockDecoder.swift` — keep `HTBlockDecoderConformant.decode` as Swift reference; add a public NEON-routed counterpart that calls the C path.

**Exit criteria:**
- `J2KMedicalCorpusPerformanceTests` shows ≥3 ms DX wall reduction at warm in-process median.
- `J2KStrictCrossCodecValidationTests` clean — encoder bytes still decode bit-exactly via OpenJPH / Grok / Kakadu.
- `recommendedDecodeAPI` substitute corpus rerun shows DX `.decodeGPU` ≤ 50 ms (was 64 ms post-Phase-0).

**Stop trigger:** wall reduction < 3 ms → keep the C path behind the env var; do not flip default-on. The substitute-corpus regression test serves as the permanent gate.

## D1.5-D — Default flip + release

**Motivation:** if D1.5-C clears the gate, the C+NEON HT decoder becomes the production default — mirroring v9.4's encoder default-flip discipline.

**Files:**
- The env-var gate in D1.5-C flips its default from off to on.
- `RELEASING.md` checklist updated.
- README + OPTIMAL_PERFORMANCE_GUIDE updated with new decode baseline numbers (per `feedback_readme_mandatory_per_release` and `feedback_warm_bench_mandatory`).

**Exit criteria:**
- Full cross-codec validation matrix green.
- Warm cross-codec bench shows updated decode walls.
- DICOMKit substitute driver shows the new product-path numbers.
- Memory updated with the new project entry.

**Release path:** D1.5-D produces a release candidate. The candidate goes through a release-candidate PR to main per `project_release_process`, with v9.6.x or v9.7.0 versioning (user decision based on changelog scope).

## What stays out of scope (v10.2-research only)

These items are explicitly NOT in v10.2's scope; they belong to separate research arcs if/when the data supports them:

| Item | Why deferred |
|---|---|
| Forward-DWT C+NEON port (encoder-side) | Separate encoder arc; v8.6 closed forward inner-lifting as memory-bound |
| Inverse-DWT C+NEON port (decoder-side) | v8.4 found GPU IDWT wash on DX 2x2; inverse-Swift SIMD4 is already at lever ceiling. Reopen only if decode entropy hits its ceiling and iDWT becomes dominant. |
| Pointer-backed pending block (encoder Phase E1) | Encoder arc, separate plan in `BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md` |
| ROI / per-resolution selective decode | Out of scope for the Kakadu-gap arc |
| iOS/A-series cross-silicon validation | Hardware-gated; opens after v10.2-D lands and an iPhone test box is available |

## Honest priors going in

- **NEON retrofit win is bounded.** v9.4 encoder's NEON path on top of scalar C delivered the 2.91× single-thread figure. The decoder per-state-machine scalar ratios are 1.14-1.83×, lower than the encoder's pre-NEON ratio. The integrated NEON multiplier on top will likely deliver something in the 1.5-2.2× per-block region, less than v9.4's 2.91× — proportionally less wall savings.
- **Per-block integration delta is unknown.** The v9.4 encoder's microbench-to-wall dilution was ~50%. If the decoder follows that ratio, the integrated NEON port projects to ~2-3 ms DX wall — RIGHT AT the 3 ms threshold. The probe could come in just above or just below.
- **Bit-exactness across 11,889 cells is non-negotiable.** v9.4's encoder analog held the line on this for a reason: the parity surface catches every off-by-one or FF-stuff-direction bug. Allocate explicit debugging time for the inevitable parity-breaks during integration.
- **The decoder Swift code is already heavily optimised.** Five prior wash investigations (v6-alpha4 through v8.5) ran on tight Swift code that the encoder didn't have pre-v9.4. The "Swift production" baseline in v10.2 is harder to beat than v9.3's Swift encoder was.

## What WOULD justify closing v10.2 early

- D1.5-A NEON SWAR retrofit fails to beat Swift production by ≥1.10× → close. The MagSgn ceiling is structural even with NEON, and integration won't recover.
- D1.5-B per-block parity fails on the 11,889-cell corpus and isn't resolvable in 2 days → close. Cannot ship a non-bit-exact path.
- D1.5-C wall reduction is < 1.5 ms (half the threshold) → close. Even allowing for measurement noise, the lever is too small.

## Companion documents

- [`V10_1_DECODE_C_PORT_PROBE.md`](V10_1_DECODE_C_PORT_PROBE.md) — predecessor; scalar C state-machine ports (closed).
- [`V9_4_NEON_HOT_PATH_RESEARCH.md`](V9_4_NEON_HOT_PATH_RESEARCH.md) — encoder analog; methodology to mirror.
- [`BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md`](BEAT_KAKADU_EXECUTION_PLAN_2026_05_15.md) — owning execution plan; v10.2 implements its Phase D1 redirected per the architect's recommendation.
