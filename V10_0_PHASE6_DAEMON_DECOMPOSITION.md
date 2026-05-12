# v10.0 Phase 6 — daemon-encode win decomposition on Apple M2

**Status:** Decisive finding with product implications.
**Date:** 2026-05-12
**Branch:** `v10.0-research`
**Test:** `Tests/J2KMetalTests/V10Phase6DaemonDecompositionTests.swift::testDecomposeDaemonWin_M2`
**Host:** Apple M2, macOS, release-mode, same session (n=5 median per mode, 2 warmups)

## Headline

**The v9.5.0 daemon-encode win on M2 is entirely cold-start avoidance, not codec parallelism or any "warm-process" advantage beyond library init.** The XPC IPC path itself *adds* 20.74 ms of overhead on DX vs encoding directly in-process. The daemon delivers a +50 ms net win over cold CLI only because it amortises a ~70 ms library-init tax across many calls.

This means:

- **SDK / in-process consumers (apps, app extensions, daemons, libraries) should NOT use the daemon path.** Encode directly via `J2KEncoder.encode(_:)`. Saves ~20 ms per call on DX, ~18 ms on PX vs going through `j2k --daemon`.
- **CLI / one-shot consumers (scripts, PACS tooling, batch pipelines) should use the daemon path.** It eliminates the per-process cold-start at the price of ~20 ms IPC overhead, net-positive ~50 ms on DX.

## Three-way wall measurement

| Fixture          | Cold CLI | Warm daemon CLI | Warm in-process |
|------------------|---------:|----------------:|----------------:|
| PX 2459×1316     |  75.77 ms |       36.52 ms |       18.19 ms |
| **DX 2800×2288** | **112.27 ms** |  **62.27 ms** |     **41.53 ms** |

Each row is the median of 5 same-session release-mode encode walls.
Cold CLI is `Process(j2k encode ...)` per call; warm daemon is
`Process(j2k encode ... --daemon)` per call (daemon process already running);
warm in-process is `J2KEncoder().encode(image)` after 2 warmups.

## Decomposition

| Fixture          | cold − inProc (total cold-start) | daemon − inProc (XPC overhead) | cold − daemon (daemon headline) |
|------------------|---------------------------------:|-------------------------------:|--------------------------------:|
| PX 2459×1316     |                      **+57.58 ms** |                  **+18.32 ms** |                    **+39.25 ms** |
| **DX 2800×2288** |                      **+70.75 ms** |                  **+20.74 ms** |                    **+50.01 ms** |

Three quantities:

- **Total cold-start cost** — what every fresh `j2k encode` CLI invocation pays *over and above* the actual encode time. Includes process fork+exec, dynamic-linker symbol resolution, Swift-runtime init, Metal device setup, HT table touch, MCT scratch-pool allocation. **70 ms on DX**.

- **XPC overhead** — what the daemon path adds vs encoding directly in your process. Pixel-data marshal-in + encoded-bytes marshal-out + NSXPC proxy round-trip + remote-call latency. **+20 ms on DX** — daemon is *slower* than warm in-proc.

- **Daemon headline** — what the v9.5.0 release notes quote: how much wall time you save by adding `--daemon` to your CLI invocations. **+50 ms on DX** — real for CLI consumers, real win.

## Why this matters — product narrative correction

The v9.5.0 release notes ([RELEASE_NOTES_v9.5.0.md](RELEASE_NOTES_v9.5.0.md)) lead with: *"Daemon-encode large-fixture closure — DX 2800×2288 warm via j2k --daemon: 146 → 57 ms on M2 (2.5× vs v9.4.0 warm, 1.8× vs cold same-binary)."*

The 2.5×-vs-v9.4 quote is the v9.4 → v9.5 daemon-path improvement (real). The 1.8×-vs-cold quote is the daemon headline (also real). **What was NOT measured** until Phase 6 is whether the daemon also beats *warm in-proc*. It doesn't.

For SDK consumers integrating J2KSwift into a long-lived process (which is most production deployments — PACS servers, imaging viewers, DICOM workflow engines), **the daemon adds a per-call IPC tax with no compensating benefit**. The correct integration is direct `J2KEncoder.encode(_:)` calls; the library's process-shared Metal session amortises cold-start across the first call.

## Why M2 differs from M4

The v9.2 Path B M4 measurement ([CROSS_CODEC_REPORT_v9.2_PATH_B.md](CROSS_CODEC_REPORT_v9.2_PATH_B.md)) showed daemon DX = 74.51 ms vs in-proc CPU = 94.9 ms on M4 — i.e., daemon was *faster* than warm in-proc by ~20 ms. Phase 6 on M2 shows daemon = 62.27 ms vs in-proc = 41.53 ms — daemon is *slower* by ~20 ms.

Plausible explanations (untested on M2 + M4 side-by-side here):

1. **Memory-bandwidth differential** — M2 has lower aggregate bandwidth than M4. XPC marshal+copy of a 12.8 MB raw 16-bit pixel buffer costs more on M2 in absolute ms.
2. **Core-count differential** — M4 has 4P+6E; M2 has 4P+4E. The daemon's process-isolated worker pool may parallelise better on M4's wider core array than the test-process workers do.
3. **Mach + XPC microarchitecture changes** — Apple's Darwin runtime evolves per silicon generation; XPC marshalling kernels may be more optimised on M4-class A18-derivative kernels.

Without M4 hardware in this measurement session we can't isolate. The qualitative takeaway is: **don't assume one Apple Silicon generation's daemon-vs-in-proc behaviour generalises**. Re-measure per host class before recommending an integration pattern.

## Implications for the next research arc

1. **v9.5.0 daemon SDK guidance needs a documentation update.** The current `daemon-install` help text says: *"Install the j2kd XPC daemon so subsequent `j2k decode` invocations run at warm-process speed."* — this is correct for CLI consumers but misleading for SDK consumers. Add a paragraph to RELEASE_NOTES + the daemon-install help noting the SDK-vs-CLI distinction.

2. **Cross-silicon measurement is now demonstrably valuable.** Phase 6's M2-vs-M4 divergence is the second concrete data point (after v9.2 Path B) showing the wall budget shifts meaningfully across silicon. M3+/A-series should be measured before any encoder-architecture decision is finalized in v11.

3. **The cross-stage fusion v11.0 candidate becomes more interesting.** Phase 6 shows ~70 ms of cold-start tax + ~40 ms of warm encode wall on DX-M2. If a hypothetical fusion-encoder were 30% faster than warm in-proc (29 vs 41 ms), the SDK-consumer wall would drop from 41 ms to 29 ms — independent of any daemon decision. That's the lever fusion would buy.

## Phase 6 acceptance bar evaluation

| outcome                                       | what it would mean | actual |
|-----------------------------------------------|---------------------|--------|
| Daemon faster than in-proc by ≥3 ms (M4-style)| Daemon is a SDK win too; ship as default integration | ❌ |
| Daemon within ±3 ms of in-proc                | Daemon is neutral for SDK; choose by integration shape | ❌ |
| **Daemon SLOWER than in-proc by ≥3 ms**       | **Daemon is CLI-only; SDK consumers should not use it** | **✓ +20.74 ms on DX** |

## Reproducing

```bash
# Install daemon if not already
.build/release/j2k daemon-install --force

# Run the three-way A/B
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test -c release --filter V10Phase6DaemonDecompositionTests
```

Run time ~2.4 s release-mode on M2.

## Files added

- `Tests/J2KMetalTests/V10Phase6DaemonDecompositionTests.swift` — three-way test
- `V10_0_PHASE6_DAEMON_DECOMPOSITION.md` — this finding doc

Per `feedback_research_no_main_merge.md`, both stay on `v10.0-research`.

## Companion documents

- [`V10_0_RESEARCH_PLAN.md`](V10_0_RESEARCH_PLAN.md) — original plan
- [`V10_0_PHASE1_WALL_BUDGET.md`](V10_0_PHASE1_WALL_BUDGET.md) — Phase 1 wall budget
- [`V10_0_RESEARCH_CLOSURE.md`](V10_0_RESEARCH_CLOSURE.md) — Phase 4 closure
- [`V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md`](V10_0_PHASE5_GPU_SINGLE_TILE_WASH.md) — Phase 5 GPU single-tile wash
- [`CROSS_CODEC_REPORT_v9.2_PATH_B.md`](CROSS_CODEC_REPORT_v9.2_PATH_B.md) — M4 daemon-vs-in-proc reference
- [`RELEASE_NOTES_v9.5.0.md`](RELEASE_NOTES_v9.5.0.md) — daemon-encode headline (CLI-correct, SDK-needs-update)
