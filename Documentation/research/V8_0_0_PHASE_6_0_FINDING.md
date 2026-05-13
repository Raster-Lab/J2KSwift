# v8.0.0 Phase 6.0 — Batch decode preWarm + cold-vs-warm honesty

**Captured**: 2026-05-09, Apple M2.
**Phase 6.0 deliverable**: a small UX/correctness improvement to the existing `j2k batch decode` command (preWarm before parallel dispatch) plus an honest measurement that documents when batch wins, when it doesn't, and what's left for Phase 6.1+ XPC daemon.

## TL;DR

The existing `j2k batch decode` command **already amortises Metal cold-start across files** via the process-shared Metal session. Phase 6.0 adds a `preWarm()` call before the parallel dispatch so the cold-start is paid once up-front (not serialised onto the first file's hot path), and documents the **cold-vs-warm system behaviour**:

- **Cold system** (e.g. fresh login, no recent J2KSwift activity): batch is 4-5× faster than per-file CLI on the corpus
- **Warm system** (CPU caches hot, file content cached, recent process activity): batch is competitive with per-file CLI but no longer dramatically faster — the OS-level caches mask much of the cold-start tax that batch was eliminating

This is a smaller win than the Phase 5 finding implied. The genuine **single-invocation CLI win** (where Phase 5's 4-of-6 win-vs-Kakadu number lives) requires the **Phase 6.1+ XPC daemon** — a daemon eliminates per-CLI-invocation cold-start regardless of system warmth state, which batch can't do because each batch invocation is itself a new process.

## What changed

`Sources/J2KCLI/Batch.swift::batchDecode` adds an explicit `J2KMetalSession.processShared.preWarm(includeWarmupDispatch: false)` before dispatching the per-file `processFilesInParallel` group. Previously the Metal session lazy-initialised on the first file's `J2KDecoder.decode` call, which serialised that init onto the critical path of the first file. Now the init runs before the parallel dispatch begins.

```swift
if J2KMetalSession.isAvailable {
    try? await J2KMetalSession.processShared.preWarm(includeWarmupDispatch: false)
}
return await processFilesInParallel(...)
```

Behaviour:
- Wall-time impact in warm-system steady-state: negligible (~0 ms)
- Wall-time impact on cold-system first batch: pulls ~50 ms init out of the first-file critical path (small structural improvement)
- Correctness: unchanged. preWarm only compiles compute pipelines; no decode work happens.

## Measurement (6-file corpus, M2 release)

### Cold-system (first batch invocation after long idle)

| run | per-file CLI sum (6 files) | batch |
|---|---:|---:|
| 1 (cold) | 889 ms | 193 ms |

Batch wins **4.6×** on the cold case. This is the headline number that motivated Phase 6.

### Warm-system (system already hot from prior CLI activity)

| run | per-file CLI sum (5 runs avg) | batch (5 runs avg) |
|---|---:|---:|
| 2-5 | 182 ms | 195 ms |

Batch is **slightly slower** in warm-system steady state. The per-file CLI catches up because:
- File contents already in OS page cache (free I/O)
- `j2k` binary already in dyld cache + Swift runtime warm
- Kernel-side process spawn fast paths populated

The dramatic 4.6× cold-system win was specific to the first batch invocation after a quiescent system.

## Implication for the Phase 6 strategy

| user workflow | cold system | warm system | XPC daemon Phase 6.1+ would deliver |
|---|---|---|---|
| Per-file CLI loop | 889 ms / 6 = 148 ms each | 182 / 6 = 30 ms each | ~5-10 ms each (Phase 5 warm walls) |
| `j2k batch decode -i dir -o dir` | 193 ms total | 195 ms total | similar to today (batch already amortises within-process) |
| Single `j2k decode -i file -o out` | 64-134 ms | 19-89 ms | ~5-30 ms (Phase 5 warm walls) |

**The batch command is the right answer for multi-file workflows TODAY** — no XPC daemon needed.

**The XPC daemon is the right answer for single-invocation CLI workflows** — where users run `j2k decode` once and exit, paying the ~30 ms warm-system or ~100 ms cold-system overhead per invocation. Phase 5 measured the warm in-process numbers; the XPC daemon delivers those numbers to single-CLI users by holding the Metal session warm across invocations.

## What lands in this PR

- `Sources/J2KCLI/Batch.swift` — `preWarm()` call before parallel dispatch in `batchDecode`. Pulls cold-start out of the first-file critical path.
- `V8_0_0_PHASE_6_0_FINDING.md` — this document, including the cold-vs-warm honesty.

## Recommendation for users

For multi-file workflows TODAY (until Phase 6.1+ XPC daemon ships):

```bash
# Old: per-file CLI loop (1 process per file — cold-start tax × N)
for f in *.j2k; do j2k decode -i "$f" -o "${f%.j2k}.pgm" --output-format pgm; done

# New: batch (1 process — cold-start once, then warm session)
j2k batch decode -i input_dir -o output_dir
```

The user's eval workflow (`eval_4codecs.zsh` which loops `j2k decode` per file) is a candidate for migration to `j2k batch decode` to get Phase 6.0's win.

## Mandatory gate (release mode, 0 failures)

10/10 pass:
- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1
- `MgRegressionTriageTest` — 2/2

## Phase 6.1+ — XPC daemon (the actual Phase 6 work)

Phase 6.0 is a stepping stone. The real Phase 6 — persistent Metal session daemon for single-CLI invocation users — is unchanged from Phase 5's recommendation. Sub-phases:

- 6.1: daemon skeleton + Mach service + minimal round-trip protocol
- 6.2: decode RPC with shared-memory marshalling for large images
- 6.3: CLI client with auto-discovery + fallback to in-process
- 6.4: launchd plist for on-demand activation
- 6.5: lifecycle (idle timeout, memory pressure)
- 6.6: mandatory gate + CLI matrix re-measurement (target: 4-of-6 fixtures flip from "behind Kakadu" to "WIN")

Each sub-phase gets its own RFC PR. Multi-day per sub-phase. Total ~1-2 weeks of focused work.

## Reproduction

```bash
swift build -c release --product j2k

# Cold system (after long idle / first launch of day)
time .build/release/j2k batch decode -i input_dir -o output_dir --quiet

# Compare to per-file CLI loop on the same input
time (for f in input_dir/*.j2k; do .build/release/j2k decode -i "$f" -o "${f%.j2k}.pgm" --quiet; done)
```
