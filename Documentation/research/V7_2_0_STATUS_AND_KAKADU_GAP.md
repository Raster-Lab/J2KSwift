# v7.2.0 Status + Honest Path to Beating Kakadu

**As of**: 2026-05-08, end of overnight autonomous session.

This document is for the user to read first thing on resuming the session. It summarises what v7.2.0 has actually delivered against the directive "we need beat Kakadu," what was tried and didn't work, and what the honest next move is.

---

## 1. What's in v7.2.0 (PRs that landed or are awaiting merge)

| PR | Phase | What it does | Wall improvement |
|---|---|---|---|
| #354 (merged) | Phase 0 | Decoder per-tile timing instrumentation fix + UMA counter baseline + plan revision (Option 3) | Diagnostic only |
| #355 (merged) | Phase A | Encode-side UMA boundary elimination (20 → 0 memcpys per encode when GPU forward DWT fires) | 0% in default routing (gate doesn't fire on multi-tile per-tile); foundation |
| #356 (open) | Phase E | Cross-tile batched HT entropy decode (1 MTLCommandBuffer instead of N) | DX 2x2 -3% (only fixture where per-tile threshold ≥ 1 MP fires) |
| (abandoned) | Phase E threshold-lower | Lower per-tile threshold from 1 MP → 256 K | **Refuted by data** — 1.8× regression. v7.1.1 was correct. |
| (abandoned) | Phase F planner pivot 4x4→2x2 for DX | Make decoder 2x2-default | Within noise on probe; encode side neutral; not worth the codestream-layout blast radius |

**Cumulative DX decode improvement on default routing: 0%**.

The Kakadu gap on DX decode (J2KSwift 65 ms vs Kakadu ~25 ms = 2.7×) is **not closed** by v7.2.0.

## 2. What was tried tonight and didn't pan out

1. **Lowering the per-tile thresholds to 256 K** — `V720PhaseEThresholdSweepTests` empirically showed 1.8× regression. Documented in `V7_2_0_PHASE_E_FINDING.md`.
2. **Forcing GPU entropy unconditionally on all multi-tile fixtures** — `V720PhaseEABTest` showed +14% to +65% regressions on small-per-tile fixtures (PX 4x4, XA 2x2). The per-tile-threshold gate was correctly added back.
3. **Planner default change DX 4x4 → 2x2** — `V720PhaseFPlannerProbe` showed encode/decode walls within noise; the case for changing the default is too weak to justify the codestream-layout change.
4. **IDWT batching as a follow-on to entropy batching** — sweep test showed IDWT GPU at 256 K threshold = 78 ms vs CPU 64 ms. Even with full CB amortisation, GPU IDWT compute on small per-tile sizes is genuinely slower than CPU on Apple M2. Same architectural lesson as entropy.

The recurring lesson: **on Apple M2, GPU compute on small per-tile workloads (≤ 1 MP) is genuinely slower than CPU compute, regardless of how cleverly we amortise dispatch overhead**. The only fixtures where the GPU paths win are large per-tile sizes (DX 2x2 = 1.6 M/tile; single-tile DX = 6.4 MP), and even there, the win is marginal (within ±5 % of CPU).

## 3. Why we're behind Kakadu (root cause)

Per the V7_2_0_PROFILE.md DX decode breakdown:
- **entropy**: 62.6 % of CPU work
- **iDWT**: 34.1 % of CPU work
- everything else: 3.3 %

Kakadu does **CPU-only HT decoding with hand-tuned SIMD**. Their entropy stage is ~3× faster than ours, not because they use the GPU but because their inner loops are NEON-vectorised.

J2KSwift's HT entropy decoder uses Swift's auto-vectoriser, which is good for simple loops but doesn't fully exploit NEON for the bit-twiddling-heavy MEL/VLC/MagSgn inner loops. The compiler can't auto-vectorise variable-length bit decoding.

The v6-alpha4 step 12 lever-ceiling memo flagged this:

> A+B landed (-2.3% DX), C+D reverted (cache locality, i-cache pressure); residual Kakadu gap is structural, don't retry these levers on Apple M2 + Swift release + macOS

The "structural" framing was right: cache and locality levers are exhausted. **The remaining lever is hand-coded SIMD on the entropy decoder hot loop**. That's a multi-week effort and was explicitly outside v7.2.0's plan-revised scope.

## 4. Honest options for the user when resuming

**Option Z1 — Ship v7.2.0 as a foundational release**. PRs #354, #355, #356 = decoder timing fix + encode UMA infrastructure + decode entropy CB amortisation foundation. Honest framing in release notes: "no default-routing wall change vs v7.1.1; foundation for the v7.3 SIMD audit." Kakadu gap explicitly deferred. Tag v7.2.0 today.

**Option Z2 — Don't tag v7.2.0 yet; pivot directly to Phase D (CPU SIMD entropy audit)**. The honest path to actually beating Kakadu. Multi-week effort. Risk: getting stuck on a long-running branch. v7.2.0 stays unreleased meanwhile.

**Option Z3 — Tag a small v7.2.0 with PRs #354 + #355 only** (skip Phase E). Phase E delivers 3 % on one fixture; if we want a clean release-note story, dropping Phase E might be cleaner.

**Option Z4 — Tag v7.2.0 with current scope AND start Phase D as v7.3.0 work in parallel**. Best of both: ship what we have, plan the SIMD work as a separate multi-week arc.

My recommendation: **Z4**. Ship the foundation as v7.2.0 (honest about what it is), open a v7.3.0 plan for CPU SIMD on entropy as the actual Kakadu-beat arc. Let the user decide release timing on Z4 or Z2.

## 5. What the v7.3.0 SIMD arc would look like

Sketched, not committed:

- **Probe** (1 session): instrument the HT decoder's MagSgn / MEL / VLC inner loops with cycle counters via `mach_absolute_time`. Identify which inner loop is the bottleneck.
- **Bench harness** (1 session): standalone mini-bench that runs just the entropy decode on captured DX 4x4 codeblocks, timed in ms. Decouples optimisation from full-pipeline noise.
- **NEON port** (3-5 sessions per inner loop): rewrite the dominant inner loop using Swift `simd_*` types or Builtin.SIMD (or Accelerate vDSP). Bit-level MagSgn inner loop is the hardest because of variable-length codes; might need a partial NEON / partial scalar approach.
- **Validation gate** (per port): bit-exact corpus + cross-codec + 1000-decode lifetime test.
- **Compounding** (1-2 sessions): once entropy is faster, the parallelism factor changes; re-tune the per-tile threshold accordingly. Phase E batched-entropy + faster CPU compute may compound on DX 2x2.

Realistic timeline: 8-15 sessions = 2-4 weeks of focused work. Realistic outcome: close DX decode gap from 2.7× → 1.5-2.0× behind Kakadu (will not fully close it without further lever discovery).

To FULLY beat Kakadu probably requires also attacking the IDWT stage with similar SIMD work, or finding architectural changes Kakadu doesn't do (e.g., whole-image GPU pipeline that bypasses the per-tile structure entirely — but that's a bigger rewrite).

---

## 6. State of the working tree

- main: clean. PR #354, #355 merged.
- v7.2/phase-e-decode-widening: PR #356 open, awaiting review.
- v7.2/phase-z-strategy-memo (this commit): doc-only.

No other work in progress. Safe to merge or hold any of these as you direct.
