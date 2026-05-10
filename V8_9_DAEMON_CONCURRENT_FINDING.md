# V8.9 — Daemon concurrent dispatch: in-process parallel CLI is already faster

**Status**: PROJECTED WASH. Under parallel load (`xargs -P N` patterns), in-process CLI invocations are already faster than daemon for every fixture size and every concurrency level. Implementing concurrent dispatch in the daemon wouldn't help — the bottleneck is structural (per-call NSXPC overhead × N + shared Metal device contention).
**Date**: 2026-05-10
**Branch**: `v8.9-research` (research; not for merge)

## Goal

Probe whether the j2kd daemon should support concurrent dispatch — multiple clients running in parallel through one warm daemon process. Hypothesis: this would benefit `xargs -P N j2k decode ...` patterns (DICOM viewer batch tools, multi-process workers).

## Phase 0a — does the daemon already parallelize?

`ThreadPoolExecutor`-driven concurrent CLI invocations on DX 2800×2288 (single-shot baseline 75.15 ms).

| N concurrent | wall ms | speedup vs serial | parallel efficiency |
|-------------:|--------:|------------------:|--------------------:|
|            1 |   75.15 |             0.96× |              95.8%  |
|            2 |  127.69 |             1.13× |              56.4%  |
|            4 |  218.36 |             1.32× |              33.0%  |
|            8 |  417.35 |             1.38× |              17.2%  |

**The daemon DOES partially parallelize** (1.38× speedup at N=8 for DX), but efficiency degrades fast. Likely bottleneck: shared Metal device + serialized GPU dispatch queue.

## Phase 0b — daemon vs no-daemon under parallel load

The decisive test: under parallel CLI invocations, does the daemon BEAT in-process?

| Fixture           | N  | `--daemon` | `--no-daemon` | Δ (daemon savings) |
|-------------------|---:|-----------:|--------------:|-------------------:|
| MR-small 180²     |  1 |    7.57 ms |       5.79 ms |          −1.78 ms  |
| MR-small 180²     |  4 |   14.59 ms |       8.42 ms |          −6.17 ms  |
| MR-small 180²     |  8 |   16.59 ms |      15.08 ms |          −1.51 ms  |
| CT 512²           |  1 |   16.33 ms |       8.95 ms |          −7.38 ms  |
| CT 512²           |  4 |   20.24 ms |      16.30 ms |          −3.94 ms  |
| CT 512²           |  8 |   32.62 ms |      24.99 ms |          −7.63 ms  |
| XA 1024²          |  1 |   19.93 ms |      16.63 ms |          −3.30 ms  |
| XA 1024²          |  4 |   43.00 ms |      38.68 ms |          −4.32 ms  |
| XA 1024²          |  8 |   77.94 ms |      76.10 ms |          −1.84 ms  |
| DX 2800×2288      |  1 |   75.55 ms |      72.68 ms |          −2.87 ms  |
| DX 2800×2288      |  4 |  222.85 ms |     200.97 ms |         −21.87 ms  |
| **DX 2800×2288**  |  **8** |  **424.58 ms** |   **388.02 ms** |     **−36.56 ms** |

**In-process is FASTER than daemon for EVERY fixture and EVERY N.** Daemon is 1-37 ms slower per batch.

## Why the daemon loses under parallel load

The daemon was designed for cold-shot single-call scenarios where Metal init dominates (~50 ms) and the daemon's warm process amortises it. Under parallel load:

1. **Per-call NSXPC overhead × N** — each client pays ~3–5 ms of NSXPCInterface proxy overhead. N=8 clients pay 8 × ~5 ms = 40 ms of overhead that doesn't exist on the in-proc path.
2. **Shared single Metal device** — all daemon-side decodes serialize through the daemon's single `MTLDevice` + `MTLCommandQueue`. In-process has N independent devices (one per CLI process), better GPU-level parallelism. (Note: Apple's Metal Compiler Service caches across processes, so per-process Metal init is amortised by the OS.)
3. **Daemon's listener delegate queue** — even if accepting concurrent connections, internal request dispatch may serialize through actor or queue boundaries.

For the typical `xargs -P N j2k decode ...` pattern, separate processes with independent Metal devices outperform the daemon's shared resources.

## Implementing "perfect" daemon concurrency wouldn't help

Even if we made the daemon perfectly parallel (eliminating the actor/queue serialization), the structural bottlenecks remain:

- **NSXPC overhead** × N is unavoidable without dropping NSXPCConnection entirely.
- **Single shared Metal device** is the GPU-resource limit — can't be parallelized further without instantiating multiple devices, which kills the daemon's "warm session" advantage.

Best-case projected savings from a hypothetical "perfect concurrent daemon": match the in-proc parallel time (388 ms for DX N=8). That ties at best, doesn't beat. **Below threshold.**

## Decision: defer concurrent dispatch implementation

Recommended user guidance for parallel CLI patterns:

```bash
# Wrong (slow): pays N × NSXPC overhead + GPU serialization
xargs -P 8 -I {} j2k decode --daemon -i {} -o {}.pgm

# Right (fast): N independent processes, each parallel
xargs -P 8 -I {} j2k decode -i {} -o {}.pgm
# (default since v8.1.3 is in-proc, no flag needed)
```

For batch workflows with locality (single command, many files), `j2k batch decode` (in-process parallel via `processFilesInParallel`) is the dramatically-better primitive — see `V8_9_BATCH_DAEMON_FINDING.md`.

## Lever-ceiling pattern (now 14 investigations on M2 + Swift release)

| Direction              | Wash count                                                     |
|------------------------|----------------------------------------------------------------|
| Decode codec           | 6 (v6-alpha4, v7.4, v7.5, v8.1, v8.4×3, v8.5)                 |
| Encode codec           | 3 (v8.6 forward DWT, v8.6 HT classifier, v8.7 algorithmic)    |
| Dispatch               | 1 (GCD vs TaskGroup)                                           |
| Accelerate             | 1 (vDSP/vImage/BLAS)                                           |
| AMX                    | 1 (corsix/dougallj review)                                     |
| IPC primitives         | 1 (file mmap, IOSurface, mach_vm_remap, xpc_shmem)             |
| Metal pipeline cache   | 1 (MTLBinaryArchive)                                           |
| Daemon batch RPC       | 1 (in-process batch already amortises)                         |
| **Daemon concurrent dispatch** | **1 (this — in-process parallel already faster)**     |

The daemon is correctly tuned for **single-call cold-shot scenarios** (where Metal init dominates and the daemon amortises it). For parallel workloads, the daemon is a regression. The v8.1.3 default of in-process + opt-in `--daemon` matches this — users who run parallel jobs should not pass `--daemon`.

## What WOULD justify revisiting

1. **A different IPC framework** that doesn't have NSXPCConnection's per-call proxy overhead. Custom raw `xpc_connection_t` could shave the ~5 ms × N — multi-week scope.
2. **Per-client Metal devices in the daemon** — daemon spawns N MTLDevice instances, one per concurrent client. Eliminates the GPU serialization. But then each MTLDevice pays its own ~14 ms init cost — losing the "warm session" advantage.
3. **A specific high-volume customer pattern** that justifies the engineering investment. Currently no such requirement.

## What stays in tree

- `V8_9_DAEMON_CONCURRENT_FINDING.md` — this document.

No code changes. Phase 0 measurement was sufficient to make the close decision.
