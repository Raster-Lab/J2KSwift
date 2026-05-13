# v10.0 Phase 10 — Release-worthiness audit: is v10.0.0 a release?

**Status:** **NO. v10.0.0 should not be cut as a release.** Phase 10 audit finds zero release-worthy production code changes since v9.5.2. The v9.6.0 marketing-grade benchmark infrastructure already landed on main via #416-#424 today. The v10.0-research branch is pure measurement + research artefacts.

**Date:** 2026-05-14
**Branch:** `v10.0-research`
**Method:** git log audit between v9.5.2 tag and `origin/main` head + cross-reference with `v10.0-research` branch + check production-source diff.

## What's on main since v9.5.2

main is at `bde5744` (PR #424 merged). Today's commits between v9.5.2 and main:

| Commit | Type | What |
|---|---|---|
| #416 (e5c8576) | feature | Warm cross-codec benchmark + 26 synth fixtures |
| #417 (1fe10d5) | docs | Repo organization (250 root .md → Documentation/) |
| #418 (1a80a6f) | docs | Repo-org link follow-up |
| #419 (28633ee) | feature | 18 real-medical PGM fixtures (PHI-safe) |
| #420 (278e779) | docs | Cross-codec research report v9.5.2 |
| #421 (cc61780) | docs | J2KSwift optimal vs Kakadu |
| #422 (bbcd9b4) | docs | Optimal performance guide |
| #423 (140713a) | fix(docs) | Daemon-overhead correction (2-9 ms isolated) |
| #424 (c1a6131) | docs+bench | J2K Part 1 vs HTJ2K Part 15 |

**Zero source code changes to `Sources/` in any of these.** All v9.6-prep work is benchmark scripts, fixtures, and documentation. The Swift codec itself is bit-identical to v9.5.2.

## What's on v10.0-research not on main

```
99e6f3f v10.0 Phase 9: encoder tunable sweep — default config is pareto-optimal
a83a26f v10.0 Phase 8: decode wall budget on M2 — 12th lever-ceiling
2fb1a44 v10.0 Phase 7: cross-stage fusion structurally not viable on M2
eda2116 v10.0 Phase 6: daemon-encode win decomposed
f0836a4 v10.0 Phase 5: GPU single-tile forward 5/3 wash
d901c93 v10.0-research: no-merge-to-main policy alignment
f276e52 v10.0-research Phase 4: closure doc + isolation table
9b04938 v10.0 Phase 1c: DWT + extract16 isolation cross-check
8b41555 v10.0-research Phase 1: non-entropy wall budget
b2d5ea3 v10.0-research: plan
b15ede6 v9.9: fix pre-existing test failures (telemetry, thresholds, UB)
748b054 v9.9: fix pre-existing production runtime crashes [cherry-picked to main as 6f8ad15 in v9.5.1]
33cb20b v9.9: fix pre-existing HTJ2KBenchmarkTests stale threshold
4863d4a v9.9: fix pre-existing HTJ2K medical/near-lossless PSNR test thresholds
cb96ed6 v9.9: qstep-search bracket widening + corpus calibration data
```

### Classification

| Commit | Class | v10.0.0 release-worthy? |
|---|---|---|
| Phase 1-9 docs + tests (10 commits) | **research** | NO — research stays on branch per `feedback_research_no_main_merge` |
| b15ede6 | test-infra + envMode `let→var` | LOW (PATCH-eligible at best — no production behaviour) |
| 748b054 | production crash fix | **already shipped as v9.5.1** |
| 33cb20b | test threshold fix | LOW (PATCH-eligible at best — test-only) |
| 4863d4a | test threshold fix | LOW (PATCH-eligible at best — test-only) |
| cb96ed6 | LOSSY 9/7 qstep work | **OUT OF SCOPE** — violates lossless-only directive (`feedback_lossless_only_v5_38.md`) |

**Zero production code changes** in the eligible bucket. The `J2KEncodeTilePlanner.envMode let→var` change in b15ede6 is test-infrastructure (changes the field's mutability to enable test override without subprocess). No runtime user-observable difference.

## v10.0.0 release criteria check (per RELEASING.md)

| Criterion | Status |
|---|---|
| Public API removed/signature-changed/default-flipped | NO |
| New public type/function/config option (default unchanged) | NO |
| Codestream bytes change vs prior tag | NO (bit-identical to v9.5.2) |
| Production code path changes since v9.5.2 | NO |
| Cross-codec parity matrix re-run with bit-exactness | Not relevant — no code change |
| Medical-corpus benchmark wall change | Not relevant — no code change |
| Warm cross-codec benchmark output | Done today as PR #420 (cited v9.5.2 binary; no v10 binary differs) |

**Per RELEASING.md's SemVer guardrails: v10.0.0 is not justified.** The criteria for a major bump are:
- "Public API removed, signature changed, or default behaviour flipped" → none of these
- "Codestream bytes are part of the public contract. A bytes-changing default flip is automatically MAJOR even if no Swift API changed." → no bytes change

Per the same guardrails, even a MINOR (v9.6.0) bump is unjustified because there are no production code changes to ship. Today's deliverables on main are all benchmark infrastructure + documentation — they're additive but don't change the codec.

## What COULD justify v10.0.0 in the future

For a future v10.0.0 to be release-worthy, ONE of:

1. **Cross-silicon production code change** — e.g., M3+/A-series-specific routing fixes once that hardware is available + measured (12-investigation lever-ceiling on M2 is complete; the next frontier is genuinely different silicon).
2. **Architectural rewrite that's NOT cross-stage fusion** — Phase 7 closed fusion; remaining options are slower-but-cleaner refactors (e.g., async/await everywhere, Sendable strict-mode shipping, library structure rationalisation). These could be MAJOR-eligible if defaults change.
3. **A bytes-changing default** — e.g., switching the default HT block format from `.conformant` to a newly-optimised variant. None planned.
4. **Drop platform support** — e.g., x86_64 macOS support removal. Per `feedback_apple_only_v8` we're already Apple-Silicon-only; nothing more to drop.

None of these are imminent. The honest assessment is that v10.0.0 is **not a useful release marker**.

## Phase 10 recommendation: skip v10.0.0; cherry-pick test fixes as optional v9.5.3 patch

**Option A (recommended):** Cherry-pick `b15ede6` (test fixes + planner mutability), `33cb20b` (HTJ2KBenchmarkTests threshold), `4863d4a` (HTJ2K PSNR thresholds) into a v9.5.3 patch hotfix. Use the RELEASING.md hotfix flow. Doc-light release.

**Option B:** Skip a release entirely. The test fixes only matter to test maintenance; CI on main currently passes per yesterday's gate runs. The fixes can sit on `v10.0-research` until a future release picks them up incidentally.

**Option C (NOT recommended):** Tag v10.0.0 anyway. Per `feedback_no_half_releases`, this would violate the no-empty-release rule and waste the v10 version slot.

## Why this is a useful audit

Phase 10 closes the v10.0 arc's release narrative honestly. The encoder lever-ceiling pattern (12 investigations deep) means there's **nothing left to ship algorithmically on M2**. The v10.0-research arc produced:

- 4 finding docs that conclusively close v10.0 as research
- 4 measurement test harnesses for future re-runs (Phase 1, Phase 5, Phase 6, Phase 7, Phase 8, Phase 9 → 6 reusable tests)
- 2 cross-silicon prep deliverables (the warm bench script + corpus, on main as PR #416/#419)
- 0 production code changes worth a version bump

The remaining open frontiers are **deployment** (j2kd daemon adoption telemetry, SDK marketing) and **hardware** (M3+/A-series). Neither is a code change.

## v10.0 final closure recommendation

After Phase 10's audit, the v10.0-research arc should:

1. **Stay on the `v10.0-research` branch.** No merge to main. (Per `feedback_research_no_main_merge`.)
2. **NOT spawn a v10.0.0 tag.** The audit shows no justification.
3. **Spawn an optional v9.5.3 patch IF the test fixes are deemed worth shipping.** User judgement call.
4. **Be summarised in a final closure doc** (`V10_0_FINAL_CLOSURE.md`, Phase 11 of this branch) that consolidates the 12-investigation lever-ceiling narrative + the cross-silicon-is-the-next-frontier conclusion.

## Reproducing the audit

```bash
# What's on main since v9.5.2
git log v9.5.2..origin/main --oneline

# What's on v10.0-research not on main
git log origin/main..origin/v10.0-research --oneline

# Is each commit production code or test-only?
for commit in <commits>; do
  git show $commit --stat | grep -E "Sources/|Tests/"
done
```

## Files added in Phase 10

```
V10_0_PHASE10_RELEASE_AUDIT.md  (this doc — audit only, no test)
```

Stays on `v10.0-research` per the no-merge policy.

## Companion documents

- [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md) — the plan whose Phase 4 gate this audit honours
- [`V10_0_PHASE7_FUSION_FEASIBILITY.md`](V10_0_PHASE7_FUSION_FEASIBILITY.md) — 11th lever-ceiling
- [`V10_0_PHASE8_DECODE_WALL_BUDGET.md`](V10_0_PHASE8_DECODE_WALL_BUDGET.md) — 12th lever-ceiling
- [`V10_0_PHASE9_TUNABLE_SWEEP.md`](V10_0_PHASE9_TUNABLE_SWEEP.md) — default config is pareto-optimal
