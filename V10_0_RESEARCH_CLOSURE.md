# v10.0-research — closure (Phase 4 finding doc)

**Status:** Closed as research artefact. No production code change.
**Decision date:** 2026-05-12
**Branch:** `v10.0-research` (commits `b2d5ea3` → `9b04938`)
**Host:** Apple M2, macOS, Swift release build
**Plan:** [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md)
**Phase 1 data:** [`V10_0_PHASE1_WALL_BUDGET.md`](V10_0_PHASE1_WALL_BUDGET.md)

## Closure statement

The v10.0-research arc set out to identify a non-entropy C target inside
the JPEG 2000 encoder hot path that could close the remaining Kakadu gap on
warm DX encode. **Five independent isolation cross-checks (DWT, entropy,
extract16, tier-2, codestream-marker) confirm that no non-entropy stage
clears the Phase 1 gate** (≥10 % of wall AND ns/sample > 20 AND not already
at a documented ceiling).

The lossless production hot path on Apple M2 is **DWT-and-entropy bound**
with both at their respective optimisation ceilings:

| Stage     | M2 measurement     | Status                                          |
|-----------|--------------------|-------------------------------------------------|
| DWT 5/3 forward | 2.24 ns/coeff (DX) | Memory-bandwidth ceiling per V8_6; auto-vec optimal |
| Entropy   | 17.3 ns/quad (DX mid-density) | C+NEON hot path shipped v9.4.0; v9.5 NEON arc washed |
| extract16 | ~1.98 ns / 16-bit pixel | Auto-vec ceiling (v5.38 M7 closed-form loop) |
| Tier-2    | ~10 % wall, memcpy + branchy bookkeeping | No C/NEON headroom |
| Codestream marker | ~1.5 % wall, memcpy dominates | No optimisation headroom |

**Decision:** close v10.0-research per the plan's Phase 1 gate
("If nothing clears the bar, close as research with a documented
'encoder wall is mature' finding").

## Why this matters

v10.0 is the **ninth independent investigation** confirming the M2 + Swift
release lever-ceiling on the lossless HT 5/3 encode hot path:

1. v6-alpha4 — A+B landed, C+D reverted (i-cache pressure, cache locality)
2. v7.4-7.5 — staged-NEON release; multi-week NEON arc closed
3. v8.1 — prefix-scan / 8-byte SWAR closed as wash
4. v8.4 — DX decode lever-ceiling confirmed via 3 probes
5. v8.5 — HT entropy consumer body batched-read projected wash
6. v8.6 — encoder-side optimisation arc projected wash
7. v8.7 — encoder algorithmic redesign projected wash
8. v9.5 — aggressive C+NEON entropy push closed as research
9. **v10.0 — non-entropy wall budget closed as research** (this doc)

The signal is consistent: on Apple M2 + Swift release + macOS, the
encoder hot path is at the auto-vec / memory-bandwidth ceiling. **Further
single-stage optimisation effort returns no measurable wall savings.**

## Where the actionable levers actually are

1. **Daemon adoption** — v9.5.0 shipped j2kd one-command install. Warm DX
   encode via `j2k --daemon` runs at 57.5 ms vs 104.4 ms cold (1.8×). This
   is the production lever for batch / PACS workloads. **Already deployed.**
2. **M3+ / A-series hardware measurement** — different memory bandwidth +
   core counts may shift the wall budget enough to re-open Phase 2 on
   different silicon. v9.2 Path B M4 capture showed a different daemon win
   profile (74 ms DX vs M2's 57 ms). **Open frontier; requires M3+ hardware.**
3. **Cross-stage fusion** (DWT + quantise + entropy single-pass) — multi-
   week architectural rewrite per the v8.7 finding. **Candidate for a
   future v11.x arc** if the cross-silicon measurement says the M4-class
   ceiling is different.
4. **Decode-side optimisation** — positioned as marketable strength per v9.3
   finding; no need to disturb.

## What landed during v10.0-research

| File                                  | Type                  |
|---------------------------------------|-----------------------|
| `V10_0_RESEARCH_PLAN.md`              | Plan (b2d5ea3)        |
| `Tests/J2KMetalTests/V10Phase1WallBudgetTests.swift` | New corpus × {1,4,12} worker measurement test (8b41555) |
| `V10_0_PHASE1_WALL_BUDGET.md`         | Phase 1a/1b/1c data + decision (8b41555, 9b04938) |
| `V10_0_RESEARCH_CLOSURE.md`           | This finding doc      |

**No production source changes.** The v10.0 arc is pure measurement +
documentation.

**Branching policy (2026-05-12 onwards):** the v10.0 deliverables (plan +
Phase 1 data + this closure doc + scaffolding test) live on the
`v10.0-research` branch and are **not merged to `main`**. Future
research arcs link to commits on this branch directly. See
`feedback_research_no_main_merge.md` for the rationale.

The v9.9 commits on this branch (`748b054` vImage crash fix, `b15ede6`
test-scaffolding fixes, `33cb20b`/`4863d4a` HTJ2K threshold fixes,
`cb96ed6` qstep-search bracket widening) are **separate from the v10.0 arc**.
The vImage production crash fix (`748b054`) shipped via the **v9.5.1
hotfix** released the same day (PR #414, per the RELEASING.md hotfix
flow). The remaining v9.9 commits stay on the research branch; the lossy
qstep-bracket widening (`cb96ed6`) is parked scope per the lossless-only
product directive (memory `feedback_lossless_only_v5_38`).

## Reproducing

```bash
# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product j2k

# Phase 1b corpus sweep (the new test)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter V10Phase1WallBudgetTests

# Phase 1c isolation cross-checks (existing microbenches)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter \
  'V96DWTMicrobenchTests|V95Phase5MicrobenchTests|Tier2WritePacketSubstageProfileTests|CodestreamMarkerSubstageProfileTests'
```

All test outputs are markdown-formatted for direct copy into the
companion data doc.

## Recommendation for the next encoder research arc

**Pause encoder optimisation on M2.** The lever-ceiling pattern is now
nine investigations deep; any tenth attempt on M2 would be churn. Three
follow-ups remain meaningful:

1. **M3 / M4 / A-series cross-silicon measurement** — run the same
   `V10Phase1WallBudgetTests` + isolation microbenches on at least one
   non-M2 device. The v9.2 Path B M4 capture suggests the budget shifts;
   quantify it.
2. **j2kd daemon production adoption telemetry** — v9.5.0 ships the
   daemon; a follow-up release could measure real-world adoption rate and
   shape product narrative around the warm-encode advantage.
3. **Decode arc** — v8.4 measured the decode lever-ceiling; the
   `recommendedDecodeAPI` thresholds were set in v5.27.0. Worth a fresh
   re-measurement on current silicon, but per memory the decode side is
   the marketable strength and shouldn't be disturbed without strong
   signal.

## Companion documents

- [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md) — original plan + appendix
- [`V10_0_PHASE1_WALL_BUDGET.md`](V10_0_PHASE1_WALL_BUDGET.md) — full Phase 1 data
- [`V8_6_FORWARD_DWT_FINDING.md`](V8_6_FORWARD_DWT_FINDING.md) — DWT memory-bandwidth ceiling
- [`V9_4_NEON_HOT_PATH_RESEARCH.md`](V9_4_NEON_HOT_PATH_RESEARCH.md) — entropy C+NEON graduation
- [`V9_5_BEAT_KAKADU_RESEARCH.md`](V9_5_BEAT_KAKADU_RESEARCH.md) — entropy NEON wash
- [`RELEASE_NOTES_v9.5.0.md`](RELEASE_NOTES_v9.5.0.md) — the production-default daemon-encode closure
- [`RELEASE_NOTES_v9.5.1.md`](RELEASE_NOTES_v9.5.1.md) — vImage hotfix from this research branch
