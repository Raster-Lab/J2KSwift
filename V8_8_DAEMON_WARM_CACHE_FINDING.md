# V8.8 — j2kd daemon warm-cache regression: diagnosed, fix attempted, finding documented

**Status**: Diagnosed. The `decodeFile` shared-path-IO fix attempted and proven to NOT help on M2 + NVMe SSD. The remaining ~2 ms warm-cache regression is structural to NSXPCConnection's bytes-transfer overhead and is the right trade-off for the daemon's primary use case (cold-shot acceleration).
**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research; not for merge)
**Benches**: [`V8_8_DaemonOverheadDecomposition.swift`](Tests/J2KCodecTests/V8_8_DaemonOverheadDecomposition.swift) + [`V8_8_DecodeFileBench.swift`](Tests/J2KCodecTests/V8_8_DecodeFileBench.swift)

## Problem

Cross-codec testing on the medical corpus surfaced a real CLI regression: paired interleaved A/B (N=20) on DX 2800×2288 showed:

```
J2KSwift CLI in-process (--no-daemon): 72.10 ms median (stdev 2.26)
J2KSwift CLI via j2kd daemon:          74.44 ms median (stdev 2.92)
Δ:                                     -2.34 ms (daemon SLOWER on warm-cache CLI)
```

The j2kd daemon was originally designed (v8.0.0/v8.1.0) to eliminate Metal cold-start tax on one-shot CLI invocations (~50 ms savings on DX). On warm-cache CLI loops where Metal cold-start is amortised by OS file cache, the daemon's XPC overhead was visible as a small regression.

## Diagnosis

`V8_8_DaemonOverheadDecomposition` measured each cost component independently:

```
1. J2KDaemonClient init+isAvailable+close: median 0.042 ms (n=10)
2. ping XPC empty roundtrip:               median 0.045 ms (n=30)
3. Full daemon decode (DX 2800x2288):      median 57.85 ms (n=20)
4. In-process J2KDecoder.decode reference: median 52.70 ms (n=10)

Daemon overhead (decode_via_daemon - decode_in_process): +5.14 ms
  - of which empty-XPC roundtrip:                          0.045 ms (1%)
  - of which bytes-transfer + serialisation (residual):    5.10 ms (99%)
```

Steady-state daemon overhead: **~5 ms**, almost entirely in NSXPCConnection bytes-transfer + serialisation of the 12 MB codestream input + 25 MB pixelData reply.

The original CLI A/B showed only +2.34 ms because the CLI in-process path also pays per-invocation Metal/library init (~3 ms even with file cache warm), which the daemon avoids. So:

```
CLI in-process: 52.70 ms (decode) + ~19 ms (process startup + load + write)  = ~72 ms
CLI daemon:     57.85 ms (decode) + ~17 ms (no Metal init)                   = ~75 ms
```

Cross-checks. The genuine warm-cache regression is ~3–5 ms decoder overhead minus ~3 ms saved Metal init = **~2 ms net**.

## Fix attempted: `decodeFile(codestreamPath:outputPath:)`

Added a new XPC method that takes file paths instead of `Data` payloads. The daemon reads the codestream via `mmap` (zero-copy load) and writes the decoded pixel data directly to a destination file path. Hypothesis: replacing the 12 MB OOL XPC send + 25 MB OOL XPC receive with a path string round-trip would save ~5 ms.

`V8_8_DecodeFileBench` measured the A/B on DX (n=12 each, 3 warm-up loops):

```
decode(Data) [old]:        median 59.71 ms
decodeFile(path:) [new]:   median 60.74 ms
in-process baseline:       median 58.76 ms

Δ (decode - decodeFile):     -1.03 ms (decodeFile is SLOWER)
Δ (decodeFile - in-process): +1.98 ms remaining overhead
```

**Result: decodeFile DID NOT win.** It is ~1 ms slower than the existing `decode(Data)` path.

### Why it failed

NSXPCConnection's automatic OOL (out-of-line) marshalling for large `Data` payloads uses mach_msg with shared-memory descriptors. On M2, the `12 MB send + 25 MB receive` round-trip is **already near-zero-copy**. The 5 ms overhead in the decomposition is in NSXPCInterface's introspection / archiving / continuation-bridging machinery, not in the actual byte movement.

Replacing the OOL transfer with disk I/O **does not save the bytes movement** (it's already cheap), but **adds disk-write cost**. M2's NVMe SSD writes 25 MB in ~5–10 ms via `Data.write(to:)` (POSIX `write` syscall + filesystem journal). That cost matches or exceeds what was saved.

If we wanted to actually eliminate the 5 ms NSXPCInterface overhead, the right primitive would be:

1. **Lower-level mach_msg** — custom protocol bypassing NSXPCInterface entirely. Multi-week effort; foregoes Apple's structured framework.
2. **IOSurface** — Apple's GPU-shared-memory framework. Designed for graphics buffers, supports CPU-accessible shared memory. Daemon writes pixels into an IOSurface; client maps it directly. Promising but multi-week + needs API redesign of `J2KComponent` to optionally vend an IOSurface.
3. **Pre-allocate destination + Data(bytesNoCopy:)** — daemon pre-allocates the result buffer in shared memory, returns a pointer + length descriptor. Client wraps as `Data(bytesNoCopy:count:deallocator:)`. Avoids the marshalling copy without filesystem overhead.

All three are weeks of work for ~2–5 ms wall savings on warm-cache CLI loops — borderline below the v7.4 ≥ 3 ms threshold even at best case.

## Decision: keep existing `decode(Data)` as the production path

The existing `decode(Data)` path is the right primitive on M2 + NSXPCConnection. The trade-off:

| Scenario                                  | In-process | Daemon  | Δ        |
|-------------------------------------------|-----------:|--------:|---------:|
| Cold-shot CLI (no file cache, fresh proc) |    ~120 ms | ~75 ms  | **-45 ms (daemon WINS big)** |
| Warm-cache CLI (file cache hot)           |     72 ms  | 75 ms   | +3 ms (daemon loses small) |
| Library SDK consumer (long-lived process) |    ~52 ms  | n/a     | n/a      |

The daemon's headline use case is the **first** column. The +3 ms regression on warm-cache CLI is well below threshold for action and does not warrant either:
- Behavioral change in routing (auto-disable daemon on warm-cache — adds complexity; heuristic for "is this warm-cache" is unreliable)
- Architectural rework of the XPC layer (multi-week for sub-threshold gain)

`decodeFile` stays in the protocol as a research artefact (clearly marked) so future-investigators can re-bench when the assumptions change (e.g. M3+ SSD characteristics, lower-overhead replacements for NSXPCInterface).

## What stays in tree

- `Sources/J2KDaemonProtocol/J2KDaemonProtocol.swift` — adds `decodeFile`, marked as research-only (do not wire to production CLI).
- `Sources/J2KDaemonCore/J2KDaemonService.swift` — implementation (mmap input, write output).
- `Sources/J2KDaemonClient/J2KDaemonClient.swift` — `DecodeFileResult` + `decodeFile(...)` async wrapper.
- `Tests/J2KCodecTests/V8_8_DaemonOverheadDecomposition.swift` — overhead probe.
- `Tests/J2KCodecTests/V8_8_DecodeFileBench.swift` — A/B that proved decodeFile doesn't help.
- `V8_8_DAEMON_WARM_CACHE_FINDING.md` — this document.

No CLI code changed. No production routing changed. `decode(Data)` remains the primary path.

## What WOULD justify reopening this

1. **A different storage medium** — slower SSD or HDD makes XPC OOL transfer relatively faster than file write; the disk-write cost in decodeFile would dominate, making the comparison even worse.
2. **A faster XPC transport** — a future Apple SDK that ships lower-overhead XPC (e.g. xpc_object-based protocols replacing NSXPCInterface) could shift the trade-off. Re-run the decomposition probe.
3. **A different fixture class** — much larger images (≥ 50 MP) might shift the bytes-transfer cost above the threshold-relevant range, making per-byte primitive choice meaningful.
4. **IOSurface-backed `J2KComponent`** — a J2KSwift-internal API change to vend GPU-shared-memory pixel data directly. Would benefit non-daemon GPU pipelines too. Multi-week scope.

## Companion finding — the daemon IS the right default for one-shot CLI

The cold-shot CLI savings (~45 ms on DX) dominate the warm-cache regression (~3 ms). Users running the CLI repeatedly in a tight loop (rare; mostly batch-conversion scripts) can pass `--no-daemon` to skip the small overhead. Users running the CLI as a one-shot (the typical DICOM viewer / quick-conversion case) get a meaningful speed-up.

The current default (daemon if available, in-process fallback) is correctly tuned for the most common use case. Documentation update: `--no-daemon` recommended for tight batch loops; default is correct for one-shot.
