# V8.9 — Daemon batch RPC: in-process batch already amortises everything

**Status**: PROJECTED WASH for the typical user pattern. The in-process batch path (`j2k batch decode/encode`) is already dramatically better than any daemon-based batch alternative. Daemon batch RPC would yield ~14-50 ms savings per batch invocation, only on cold-cache scenarios.
**Date**: 2026-05-10
**Branch**: `v8.9-research` (on main; not for merge as production change)

## Goal

After v8.1.3 shipped the encoder daemon (−40% encode wall corpus-wide), the next-most-promising candidate from the v8.8 deferred list was a **daemon batch RPC** (`batchDecode([Data])`, `batchEncode([J2KImage])`). Hypothesis: a single XPC call processes N files in the daemon, amortising the ~5 ms per-call NSXPC overhead. For DICOM-viewer thumbnail loops issuing 50+ decodes back-to-back, this could save ~250 ms.

## Method

Three patterns measured on a 30-file medical-corpus subset (15× MR-small + 15× CT 512², small fixtures where per-call overhead dominates):

A. `N × j2k {encode|decode} --daemon` — N CLI invocations, each pays its own process startup + XPC handshake.
A'. `N × j2k {encode|decode} --no-daemon` — N CLI invocations, no daemon.
B. `j2k batch {encode|decode}` — single CLI invocation using the existing in-process batch path (`processFilesInParallel` + Metal `preWarm()`).

C (projected; not implemented): hypothetical `j2k batch ... --daemon` routing the batch through a single XPC call that processes N files in the daemon.

## Headline data

### Decode (30 small fixtures)

| Pattern                                | total ms | ms/file |
|----------------------------------------|---------:|--------:|
| A. N × `j2k decode --daemon`           |   299.88 |   10.00 |
| A'. N × `j2k decode --no-daemon`       |   210.38 |    7.01 |
| **B. `j2k batch decode`** (in-proc)    | **113.16**| **3.77** |
| C. (projected) `batch decode --daemon` |  ~104.16 |  ~3.47  |

**Δ B→C: +9 ms** (saves only the one-time Metal `preWarm()` cost in the client process).

### Encode (30 small fixtures)

| Pattern                                  | total ms | ms/file |
|------------------------------------------|---------:|--------:|
| A. N × `j2k encode --daemon`             |   368.71 |   12.29 |
| A'. N × `j2k encode --no-daemon`         |  1183.06 |   39.44 |
| **B. `j2k batch encode`** (in-proc)      | **135.24**| **4.51** |
| C. (projected) `batch encode --daemon`   |  ~85-121 | ~2.84-4.04 |

**Δ B→C: +14 to +50 ms** (saves Metal preWarm, possibly some library-load amortisation).

## Why in-process batch is already so good

`j2k batch encode/decode` does:
1. **One** process startup (paid once)
2. **One** library load (paid once)
3. **One** Metal `preWarm()` (paid once, ~14 ms warm-cache / ~50 ms cold)
4. **N parallel** decode/encode operations via `processFilesInParallel` (concurrentPerform across cores)

This already amortises the per-process overheads that the daemon would amortise. The remaining costs (per-file Foundation/Swift work, the actual decode/encode) cannot be eliminated — they have to happen somewhere.

## Why daemon batch RPC won't help much

The hypothetical `j2k batch decode --daemon` would route through the daemon, but:
- The daemon **serialises requests today** (no concurrent dispatch). N parallel client calls would queue. So `batch --daemon` (sequential daemon calls) would be **slower** than the current in-process batch (which is parallel).
- Even with concurrent dispatch added, the per-call NSXPC overhead (~5 ms × N) would partially cancel the parallelism win.
- The only definite saving: the one-time in-process Metal preWarm (~14 ms warm-cache, ~50 ms cold-cache) — modest.

**Even the optimistic projection** (daemon eliminates per-call library loads and Metal init entirely) gives ~50 ms savings on a 30-file batch. That's 1.6 ms per file — below the 3 ms wall threshold per-call (though above it for the entire batch).

## Implementation cost vs benefit

To realise the projected savings would require:

1. **Daemon concurrent dispatch** — multiple clients in parallel within the daemon. ~3-5 days. Touches the listener delegate, request queue, decoder pool.
2. **`batchDecode([Data]) → [J2KImage]` and `batchEncode([J2KImage]) → [Data]` RPCs** — protocol additions + daemon impl + client wrappers. ~2-3 days.
3. **CLI bindings** — `j2k batch decode --daemon` etc. ~1 day.
4. **Testing** — bit-exact parity for batch'd output across all 6 fixtures, ~1 day.
5. **Documentation + release notes** — ~half day.

Total: ~7-10 days for a borderline-threshold win on a narrow audience (cold-cache batch users).

## Decision: defer; document the v8.1.3 batch story

The current v8.1.3 batch story is already strong:
- For one-shot decode/encode: `j2k {decode|encode} --daemon` (smart-routed via `--daemon auto`) saves up to −40% wall.
- For batch: `j2k batch {decode|encode}` (in-process, parallel) is dramatically better than N × CLI invocations. For 30 small files: 135 ms vs 1183 ms = 8.7× faster.

Users running batch workflows should use `j2k batch ...`. The daemon adds value primarily for one-shot CLI usage where the client process can't amortise startup costs.

## What WOULD justify revisiting

1. **A direct customer requirement** for batch via the daemon (e.g., a multi-process DICOM viewer architecture where the client can't keep a warm batch process alive). Currently no such consumer exists.
2. **Daemon concurrent dispatch** added for other reasons (e.g., supporting `xargs -P N` patterns on multi-tenant servers). With concurrent dispatch in place, batch RPC becomes ~free to add.
3. **A bigger fixture class** where the per-call NSXPC overhead becomes a smaller fraction (e.g., a 500-file thumbnail batch with very small fixtures). Even then, in-process batch handles it via `concurrentPerform`.

## What stays in tree

- `V8_9_BATCH_DAEMON_FINDING.md` — this document.

No code changes. The Phase 0 measurement was sufficient to make the close decision.

## Lever-ceiling pattern (now 13 investigations on M2)

| Direction              | Wash count                                                     |
|------------------------|----------------------------------------------------------------|
| Decode codec           | 6 (v6-alpha4, v7.4, v7.5, v8.1, v8.4×3, v8.5)                 |
| Encode codec           | 3 (v8.6 forward DWT, v8.6 HT classifier, v8.7 algorithmic)    |
| Dispatch               | 1 (GCD vs TaskGroup)                                           |
| Accelerate             | 1 (vDSP/vImage/BLAS)                                           |
| AMX                    | 1 (corsix/dougallj review)                                     |
| IPC primitives         | 1 (file mmap, IOSurface, mach_vm_remap, xpc_shmem)             |
| Metal pipeline cache   | 1 (MTLBinaryArchive)                                           |
| **Daemon batch RPC**   | **1 (this — in-process batch already amortises)**              |

The codec hot-path AND the IPC layer are at structural ceiling on M2 + Swift release. Further optimisation requires either:
- Physical M3+/A-series hardware (cache topology / ISA generation differences may shift the curve)
- Multi-week architectural changes (IOSurface-backed decoder, JP3D ROI decoder, lazy encoder init, custom raw `xpc_connection_t` protocol)

Both are out of scope for autonomous-overnight research probes.
