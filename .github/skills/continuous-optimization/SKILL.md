---
name: continuous-optimization
description: 'Continuous multi-agent optimization loop. Use when the user wants a "fix → run report → iterate" workflow driven to convergence: HTJ2K quality tuning, PCRD rate/quality balancing, benchmark regression closure, compliance gap closure, any iterative optimization where specialist subagents should be dispatched until target metrics are met.'
---

# Continuous Optimization Loop

Drive an automated fix/report/analyze cycle across J2KSwift specialist agents until explicit target metrics are met or the iteration budget is exhausted.

## When to Use

- User describes a loop pattern ("fix one task, run report, repeat").
- A test or benchmark has a numeric gap to a target (PSNR, size, throughput, MAE).
- Multiple domains may be touched across iterations (codec, perf, compliance, GPU).
- Prior `/memories/repo/` entries indicate the problem is non-trivial and multi-attempt.

## Prerequisites

Collect before starting (ask once if missing):

| Item | Example |
|------|---------|
| Target metrics (stop condition) | `PSNR > 65 dB AND ht_size ≤ j2k_size × 1.10` |
| Report command | `swift test --filter testHTJ2KNearLosslessQualityStaysCloseToStandardJ2K` |
| Must-not-regress suites | `J2KHTBlockCoderRoundtripTest`, `J2KRateControlTests` |
| Iteration budget | 8 iterations or user-specified |
| Scope | `Sources/J2KCodec/**` unless user widens it |

## Procedure

### 1. Invoke Orchestrator

Use the `@optimization-loop` agent (`.github/agents/optimization-loop.agent.md`). It manages the loop and delegates to specialists.

### 2. Baseline

```bash
# Run the target report
<REPORT_COMMAND> | tail -n 200

# Run must-not-regress suites
swift test --filter '<SUITES>' | tail -n 40

# Review prior lessons
ls /memories/repo/ | grep -Ei '<topic-keywords>'
```

Record baseline metrics in `/memories/session/optimization-loop.md`.

### 3. Iteration Template

Each iteration is exactly one variable change delegated to the most appropriate specialist:

| Gap type | Specialist |
|----------|------------|
| Codec pipeline (PCRD, DWT, MQ, HT block coder, quant) | `codec-dev` |
| Throughput / memory / concurrency | `perf-dev` |
| ISO/IEC 15444-4 conformance | `compliance` |
| Cross-codec (OpenJPEG) deltas | `benchmark` |
| Test harness / coverage / flakiness | `testing` |
| Metal / Vulkan / Accelerate / SIMD | `gpu-dev` |
| JP3D volumetric | `jp3d-dev` |
| JP2 / JPX / MJ2 boxes | `file-format-dev` |
| JPIP streaming | `jpip-dev` |
| CLI / image I/O | `cli-dev` |

Subagent prompt MUST include:
1. Target metric, current value, goal.
2. Specific hypothesis and suspect file paths (absolute).
3. Must-not-regress suites the subagent must run before returning.
4. Instruction to return diff summary and new metric values.

### 4. Verification

After subagent returns, re-run the report command **yourself**. Do not trust subagent-reported numbers.

```bash
<REPORT_COMMAND> | tail -n 200
swift test --filter '<MUST_NOT_REGRESS>' | tail -n 40
```

### 5. Decide

- All targets pass + regressions green → **STOP, success.**
- Progress (closer) + regressions green → continue next priority.
- No progress → revert (`git restore <files>`), record failed hypothesis in `/memories/repo/`, pivot.
- Regression introduced → revert, pivot.

### 6. Budget Exhaustion

Summarize:
- Best-known config (metrics + diff summary).
- Failed hypotheses (already recorded to memory).
- 2–3 fresh hypotheses for the next session.

Write a durable lesson to `/memories/repo/<topic>-optimization-loop.md`.

## Iteration Record Format

```
### Iteration <n>
Target: <metric>  current=<v>  goal=<g>  Δ=<delta>
Hypothesis: <one sentence>
Delegated: @<agent>
Files touched: <paths>
Result: <pass|progress|no-change|regression>
Next: <continue|pivot|stop>
```

## Common Pitfalls

- **Stacking changes.** Each iteration touches exactly one conceptual knob. Multi-knob edits destroy signal.
- **Trusting subagent metrics.** Always re-run the report locally.
- **Leaving failed diffs in place.** Revert immediately; partial "almost worked" state contaminates the next iteration.
- **Retrying dead hypotheses.** Check `/memories/repo/` first.
- **Silent scope creep.** If the fix needs files outside the stated scope, stop and ask.
- **Creating report `.md` files.** Use session memory; do not litter the repo with status docs unless asked.

## Stop Conditions

Any one of:
1. All target metrics pass AND all must-not-regress suites pass.
2. Iteration budget reached.
3. Two consecutive no-progress iterations with no viable pivot.
4. User interrupts or revises target.

## Related

- Agent: `.github/agents/optimization-loop.agent.md`
- Skills: `performance-profiling`, `conformance-testing`, `cross-codec-testing`, `release-checklist`
- Memory: `/memories/repo/` for durable lessons, `/memories/session/optimization-loop.md` for active loop trace.
