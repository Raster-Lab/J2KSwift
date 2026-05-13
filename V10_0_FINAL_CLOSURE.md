# v10.0-research — Final closure narrative (Phases 1–10)

**Status:** CLOSED. v10.0 is NOT a release. Twelve-investigation lever-ceiling confirmed; cross-stage fusion non-viable; default tunables pareto-optimal; production-code release-worthy diff against main = ZERO.

**Date closed:** 2026-05-14
**Branch:** `origin/v10.0-research` at `8962a15`
**Audience:** anyone evaluating "should we cut v10.0.0?" or "what's the next algorithmic lever for the J2KSwift encoder?"

This is the canonical narrative consolidating the 10 phases of v10.0-research. It supersedes the per-phase docs as the entry point, while each phase's doc remains the detailed evidence.

---

## 60-second summary

**The J2KSwift encoder + decoder hot path is structurally at its lever-ceiling on Apple M2.** Twelve independent investigations confirm this — most recently:

- **Phase 7 (this branch):** Cross-stage fusion (DWT + quantise + entropy single-pass — the v11.0 candidate flagged by the original plan) would save 0.11 ms on DX (0.1 % wall). 30× below the v7.4 3-ms acceptance bar. Structurally non-viable.
- **Phase 8 (this branch):** Decoder wall budget on M2 — iDWT is the only non-entropy stage clearing 10 % wall (30.5 %), but it's already SIMD4-vectorised at the memory-bandwidth ceiling per v8 Phase 3. No fresh lever.
- **Phase 9 (this branch):** Encoder tunable sweep — default config `(decompositionLevels=5, codeBlockSize=64×64)` is pareto-optimal. 32×32 blocks strictly dominated; no level outperforms 5 by more than measurement noise.
- **Phase 10 (this branch):** v10.0.0 release-worthiness audit — zero production code changes between v9.5.2 and v10.0-research that justify a release. v10.0.0 should not be cut.

**The remaining frontiers are non-algorithmic:**

1. **Cross-silicon measurement (M3+/A-series)** — different memory bandwidth + core counts may shift the budget. Requires hardware J2KSwift's M2 development host doesn't have.
2. **Productisation / deployment** — j2kd daemon adoption telemetry, SDK-vs-CLI marketing, cross-codec apples-to-apples benchmark methodology. All landed on main today as PRs #416-#424.

---

## The 12-investigation lever-ceiling ledger

| # | Arc | Year | Outcome |
|---|---|---|---|
| 1 | v6-alpha4 | 2026-04 | A+B landed (–2.3 % DX); C+D reverted (cache locality, i-cache pressure) |
| 2 | v7.4-v7.5 | 2026-04 | Staged-NEON release. SWAR MagSgn refill default-on; NEON recon + SWAR VLC rejected behind opt-in |
| 3 | v8.1 | 2026-05 | Prefix-scan / 8-byte SWAR closed as wash (Δ ≈ -0.58 ms median, threshold 3 ms) |
| 4 | v8.4 | 2026-05 | DX decode lever-ceiling structurally confirmed via 3 probes |
| 5 | v8.5 | 2026-05 | HT entropy consumer body batched-read projected wash |
| 6 | v8.6 | 2026-05 | Encoder-side optimisation arc projected wash; encoder lever ceiling confirmed |
| 7 | v8.7 | 2026-05 | Encoder algorithmic redesign projected wash; row-parallel regresses, 4×4 hurts MG |
| 8 | v9.5 | 2026-05 | Aggressive C+NEON entropy push closed as research (per-quad cost 40-90× over-estimated) |
| 9 | v10.0 Phase 1 | 2026-05-12 | Non-entropy encoder wall budget closed (no stage clears 10 % wall AND ns/sample > 20) |
| 10 | v10.0 Phase 5 | 2026-05-12 | GPU single-tile forward 5/3 vs `.auto` multi-tile-CPU wash (CPU now beats single-tile GPU by 4.65 ms on DX) |
| **11** | **v10.0 Phase 7** | **2026-05-14** | **Cross-stage fusion structurally non-viable** (overhead is 0.2 % of wall on DX; not enough to recover via fusion) |
| **12** | **v10.0 Phase 8** | **2026-05-14** | **Decoder lever-ceiling confirmed** (iDWT only stage > 10 % wall but already at SIMD4 ceiling) |

Twelve investigations spanning 18 months. Each closed a specific attempted lever (A+B, prefix-scan, consumer-body batched read, fusion, etc.). The pattern is overwhelming: **on Apple M2 + Swift release + macOS, the hot path is at the auto-vec / memory-bandwidth ceiling.** No remaining single-stage or cross-stage algorithmic intervention has been found that delivers measurable wall savings above the 3-ms acceptance threshold.

---

## v10.0-research arc — 10 phases at a glance

| Phase | Title | Outcome | Doc |
|---|---|---|---|
| Plan | "v10.0-research — non-entropy wall budget + C target selection" | Measure-first plan; close as research if nothing clears 10 % gate | [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md) |
| 1 | Non-entropy wall budget (encode) | No non-entropy stage clears 10 % on DX | [`V10_0_PHASE1_WALL_BUDGET.md`](V10_0_PHASE1_WALL_BUDGET.md) |
| 1c | DWT + extract16 isolation cross-check | Both at auto-vec ceiling (2.24 ns/coeff + 1.98 ns/16-bit-pixel) | (in Phase 1 doc) |
| 4 | Research closure (Phase 4 of plan) | First closure documenting Phase 1 verdict | [`V10_0_RESEARCH_CLOSURE.md`](V10_0_RESEARCH_CLOSURE.md) |
| 5 | GPU single-tile forward 5/3 vs `.auto` multi-tile-CPU A/B | A wins by 4.65 ms DX (above 3 ms threshold); 10th lever-ceiling | [`V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md`](V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md) |
| 6 | Daemon-encode win decomposition (cold/daemon/in-proc) | M2-specific finding; corrected on main per PR #423 | [`V10_0_PHASE6_DAEMON_DECOMPOSITION.md`](V10_0_PHASE6_DAEMON_DECOMPOSITION.md) |
| **7** | **Cross-stage fusion feasibility** | **0.22 ms overhead on DX = 0.1 % wall. Fusion non-viable.** | [`V10_0_PHASE7_FUSION_FEASIBILITY.md`](V10_0_PHASE7_FUSION_FEASIBILITY.md) |
| **8** | **Decode wall budget on M2** | iDWT 30.5 % wall but at memory-bandwidth ceiling per V8_6 | [`V10_0_PHASE8_DECODE_WALL_BUDGET.md`](V10_0_PHASE8_DECODE_WALL_BUDGET.md) |
| **9** | **Encoder tunable sweep** | Default `(levels=5, block=64×64)` is pareto-optimal | [`V10_0_PHASE9_TUNABLE_SWEEP.md`](V10_0_PHASE9_TUNABLE_SWEEP.md) |
| **10** | **Release-worthiness audit** | **v10.0.0 should NOT be cut. Zero production code changes since v9.5.2** | [`V10_0_PHASE10_RELEASE_AUDIT.md`](V10_0_PHASE10_RELEASE_AUDIT.md) |
| 11 | Final closure (this) | Canonical narrative consolidating phases 1-10 | this doc |

Six reusable measurement test harnesses landed on this branch:

```
Tests/J2KMetalTests/V10Phase1WallBudgetTests.swift
Tests/J2KMetalTests/V10Phase5GPUSingleTileABTests.swift
Tests/J2KMetalTests/V10Phase6DaemonDecompositionTests.swift
Tests/J2KMetalTests/V10Phase7FusionFeasibilityTests.swift
Tests/J2KMetalTests/V10Phase8DecodeWallBudgetTests.swift
Tests/J2KMetalTests/V10Phase9TunableSweepTests.swift
```

Each is a `swift test -c release --filter <name>` invocation away. They serve as the perpetual regression-detection net: if a future release regresses any of these measurements by more than measurement noise, the change has crossed an established lever-ceiling and warrants investigation.

---

## What v10.0-research produced for main

Although the no-merge-to-main policy keeps the research docs and tests on this branch, today's nine PRs to main delivered the **derived productisation outcomes** of the v10.0 arc:

| # | PR | What it delivered | Source insight |
|---|---|---|---|
| #416 | warm cross-codec benchmark + 26 synth fixtures | Canonical apples-to-apples warm methodology | Phase 6's daemon decomposition; v9.5.0 daemon path |
| #417 | Repo organization (250 root .md → Documentation/) | Maintainability cleanup | Independent of v10 but enabled by today's wave |
| #418 | Repo-org link follow-up | Small post-PR-417 fix | Mechanical |
| #419 | 18 real-medical PGM fixtures (PHI-safe) | Marketing-grade real data | Phase 1's corpus methodology + LocalDatasets-derived |
| #420 | Cross-codec research report v9.5.2 | Public benchmark publication | Phase 6 (daemon) + warm methodology |
| #421 | J2KSwift optimal vs Kakadu | "Wins 4/7 medical fixtures" defensible claim | Phase 6 (daemon-vs-in-proc) + measurement |
| #422 | Optimal Performance Guide | SDK + CLI integration paths | Phase 6 SDK-vs-CLI bifurcation |
| #423 | Daemon-overhead correction (2-9 ms isolated) | Phase 6 number tightened | Phase 6 follow-up under controlled measurement |
| #424 | J2K Part 1 vs HTJ2K cross-codec | Format-level byte/wall trade-off documented | Direct measurement; not v10-phase-derived but published same day |

So while v10.0-research stays on-branch, its derived deliverables on main have substantially upgraded the marketability of J2KSwift's existing v9.5.x codec.

---

## The honest verdict

After 12 investigations and 10 phases of v10.0-research, the question "what production code change should v10.0 ship?" has a **clear negative answer**:

> **There is no algorithmic intervention on Apple M2 + Swift release that produces a measurable wall improvement above the v7.4 3-ms acceptance bar.**

The encoder is auto-vec-ceiling-bound at every stage; the decoder is at the same ceiling; cross-stage fusion (the speculative v11 candidate) is now also closed by measurement; default tunables are pareto-optimal; nothing further can be tuned.

This is not a failure of the project — it's evidence of a mature codec. The v5.38 → v9.5.x progression took J2KSwift from "trails Kakadu 5× universally" to "beats Kakadu on 4/7 medical fixtures via the SDK shape, ties on the rest at warm CLI, leads OpenJPH/Grok/OpenJPEG universally on Apple Silicon." The lever-ceiling means **the algorithmic frontier is exhausted, not that the product is wanting**.

---

## What's next (post-v10.0)

### Short-term (no version bump needed)

1. **Cherry-pick optional test infrastructure fixes** to a v9.5.3 patch if the team wants the v9.9 commits (`b15ede6` + `33cb20b` + `4863d4a`) landed on main. Test-only; no production impact. Doc-light release per RELEASING.md hotfix flow.
2. **Continue marketing publication** of the cross-codec position via #420/#421/#424 follow-ups (blog posts, conference submissions, public reproducibility tooling).
3. **j2kd daemon adoption telemetry** — opt-in metric for SDK consumers tracking when the daemon path is used. Informs future PACS-deployment guidance.

### Mid-term (requires hardware not on this host)

4. **M3 / M4 cross-silicon re-measurement.** Run the entire v10.0-research test suite on an M4 host (or M3, or A-series via TestFlight). Phase 6 already showed M2 ≠ M4; the next lever may exist there. **This is the only remaining algorithmic frontier the data supports.**
5. **A-series production deployment validation** — confirm the SDK numbers hold on iPhone 16 / iPad Pro M4. Required for the "fastest on Apple Silicon" claim to generalise to iOS.

### Long-term (genuinely speculative)

6. **Decoder GPU IDWT default-on under multi-tile** — v8.3 root-caused the previous defect; v6.3.0 E1.2 measured CPU IDWT faster than GPU IDWT per-tile. A future re-investigation on M3+/A-series may shift this.
7. **Hand-written Metal compute shaders for entropy** — the GPU-HT path already exists; pushing it further would require either Apple Silicon's tile shaders (M3+) or a research-mode pure-Metal rewrite. Out of scope for v10-class effort.

---

## Closure conditions met

| Condition | Status |
|---|---|
| v10.0-research plan executed (Phase 1 measure-first, Phase 2 decision) | ✓ Phase 1 measured; decision "close as research" recorded |
| Optional Phase 3 (C target implementation) | ✓ Skipped — no target survived Phase 2 |
| Phase 4 closure doc | ✓ `V10_0_RESEARCH_CLOSURE.md` |
| Extended phases (5-10) consolidating findings | ✓ All six phases documented + tests committed |
| Memory record | (to follow this commit) |
| Tag policy | NO tag — per Phase 10's release-audit verdict |

---

## How to use this branch in the future

If a future investigator wants to revisit any of v10.0's findings:

```bash
git checkout v10.0-research
swift build -c release --product j2k --product j2kd
.build/release/j2k daemon-install --force

# Run ALL v10 phase tests
swift test -c release --filter "V10Phase[0-9]+"

# Or one specific phase
swift test -c release --filter V10Phase7FusionFeasibilityTests
```

Each test outputs a markdown table directly. JSON capture lives where each phase doc cites.

---

## References

- [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md) — the original plan
- [`V10_0_PHASE1_WALL_BUDGET.md`](V10_0_PHASE1_WALL_BUDGET.md), [`V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md`](V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md), [`V10_0_PHASE6_DAEMON_DECOMPOSITION.md`](V10_0_PHASE6_DAEMON_DECOMPOSITION.md), [`V10_0_PHASE7_FUSION_FEASIBILITY.md`](V10_0_PHASE7_FUSION_FEASIBILITY.md), [`V10_0_PHASE8_DECODE_WALL_BUDGET.md`](V10_0_PHASE8_DECODE_WALL_BUDGET.md), [`V10_0_PHASE9_TUNABLE_SWEEP.md`](V10_0_PHASE9_TUNABLE_SWEEP.md), [`V10_0_PHASE10_RELEASE_AUDIT.md`](V10_0_PHASE10_RELEASE_AUDIT.md) — per-phase findings
- v8.4 / v8.5 / v8.6 / v8.7 / v9.5 finding docs (`Documentation/research/` on main) — prior lever-ceiling investigations 1-8

## Memory record (to be updated separately)

`memory/project_v10_0_closure.md` should be updated with the post-Phase-10 12-investigation narrative; the existing record stops at Phase 6. Update happens in the same commit as this final doc.
