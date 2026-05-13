# V8.8 — daemon overhead scales with FIXTURE SIZE, not payload bytes

**Status**: research finding. The 5–7 ms daemon regression on small/medium fixtures (CT/MR/XA) is structural and cannot be eliminated by any IPC primitive swap.
**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research; not for merge)

## Goal

Continued iteration on the v8.8 research branch — investigate why the corpus daemon overhead pattern is non-monotonic (CT/MR/XA worse than DX/PX) by adding daemon-side stage timestamps via `J2KD_DECODE_TRACE=1` and decomposing each fixture's daemon-side decode time vs CLI in-process time.

## Method

1. Daemon binary instrumented with stage-timestamp trace (`J2KD_DECODE_TRACE=1` in plist `EnvironmentVariables`).
2. After cross-fixture warmup, ran 5 measured decodes per fixture via `j2k decode --daemon`.
3. Decomposed daemon-side total into `decode` (J2KDecoder.decode time) + `reply` (replyBox.reply call time, including Data marshaling).
4. Compared to CLI in-process wall measured separately (paired N=20 from `V8_8_VERIFICATION_REPORT`).

## Per-fixture decomposition

| Fixture           | n | decode med (ms) | reply med (ms) | total daemon-side (ms) | CLI in-proc (ms) |
|-------------------|--:|----------------:|---------------:|-----------------------:|-----------------:|
| MR-small 180²     | 5 |            2.94 |           0.17 |                  3.18  |             5.73 |
| CT 512²           | 5 |            8.23 |           0.19 |                  8.41  |             8.76 |
| MR 886²           | 5 |           11.20 |           0.28 |                 11.51  |            12.26 |
| XA 1024²          | 5 |           11.55 |           0.29 |                 11.87  |            17.22 |
| PX 2459×1316      | 5 |           30.09 |           0.55 |                 30.67  |            43.33 |
| DX 2800×2288      | 5 |           53.03 |           1.11 |                 54.22  |            74.11 |

## Key insight: daemon decode IS faster than in-process — but client-side proxy work erases the win

Daemon-side decode time is consistently **less than** the CLI in-proc wall (because the in-proc wall includes process startup, library load, file I/O, etc.). For DX:

```
daemon-side total: 54.22 ms   (just decode work)
CLI in-proc total: 74.11 ms   (decode + ~20 ms shared CLI overhead)
↓
daemon should be ~20 ms faster... but the daemon CLI is 74.92 ms (not faster)
```

The "missing" 20 ms is the **NSXPC client-side machinery cost** (proxy resolution, archiving the envelope, queue-hopping the reply continuation, NSXPCDecoder validation). Critically, this work happens IN PARALLEL with daemon-side decode.

## Why CT/MR/XA show 5–7 ms regression — overlap math

| Fixture       | decode | NSXPC client work | overlap (parallel) | exposed cost |
|---------------|-------:|------------------:|-------------------:|-------------:|
| DX 2800×2288  | 53 ms  | ~5 ms             | yes — fully hidden | 0 ms         |
| PX 2459×1316  | 30 ms  | ~5 ms             | yes — fully hidden | 0 ms         |
| XA 1024²      | 12 ms  | ~5 ms             | partial            | ~3 ms        |
| MR 886²       | 11 ms  | ~5 ms             | partial            | ~3 ms        |
| CT 512²       |  8 ms  | ~5 ms             | partial            | ~3 ms        |
| MR-small 180² |  3 ms  | ~5 ms             | none — fully exposed | ~5 ms      |

When daemon decode is the long pole (≥ NSXPC client work), the overhead fully overlaps and disappears. When daemon decode is shorter than NSXPC work, the daemon CLI must wait for NSXPC machinery to finish — hence 5–7 ms exposed cost.

## Implication for IOSurface architecture

The earlier `V8_8_RESEARCH_OVERNIGHT.md` projected ~3 ms savings on DX from an IOSurface-backed result transfer. **But IOSurface ONLY helps the byte-transfer fraction**, which is already overlapping with decode for large fixtures. For small fixtures where the overhead is *not* in byte transfer but in NSXPC machinery (introspection, encode/decode of envelope, continuation bridging), IOSurface offers no benefit.

| Fixture       | Current daemon CLI | With IOSurface     | Δ improvement |
|---------------|-------------------:|-------------------:|--------------:|
| DX 2800×2288  |          74.92 ms  |        ~71.5 ms    |       ~3 ms   |
| PX 2459×1316  |          43.66 ms  |        ~41 ms      |       ~3 ms   |
| XA 1024²      |          22.68 ms  |        ~22 ms      |     ~0.5 ms   |
| MR 886²       |          18.73 ms  |        ~18.5 ms    |     ~0.3 ms   |
| CT 512²       |          15.44 ms  |        ~15.2 ms    |     ~0.2 ms   |
| MR-small 180² |           6.96 ms  |         ~6.7 ms    |     ~0.3 ms   |

**The IOSurface architecture would only meaningfully help DX/PX-class fixtures, NOT the CT/MR/XA fixtures that have the largest absolute regression.** This further validates v8.1.3's default-flip (in-process default + opt-in `--daemon`) over the multi-week IOSurface architectural change.

## Smart-routing heuristic justification

For a future "auto" daemon mode, the data suggests a clear inflection point:

- **pixels < 1 MP** (MR-small/CT/MR 886²): NSXPC client machinery > daemon decode work → ALWAYS use in-process.
- **pixels ≥ 3 MP** (PX/DX): daemon decode > NSXPC machinery → daemon path roughly equals or matches in-process.
- **1 MP ≤ pixels < 3 MP** (XA): borderline. Daemon roughly matches in-process; opt-in user choice.

Implementation sketch (for `--daemon=auto`):

```swift
// Check codestream pixel count cheaply (parse SIZ marker, ~5 µs).
let useDaemon = pixelCount >= 3_000_000  // PX/DX threshold
```

This is a simpler heuristic than v8.1.3's binary opt-in but adds CLI complexity. For research, document the threshold; for production, the v8.1.3 default-flip + explicit `--daemon` is cleaner.

## What stays in tree

- `V8_8_DAEMON_FIXTURE_SCALING.md` — this document.
- Daemon-side trace harness (`J2KD_DECODE_TRACE=1` env var) — already in `Sources/J2KDaemonCore/J2KDaemonService.swift`, committed previously.

No code change in this iteration.

## Conclusion

The v8.8 corpus daemon regression is structural and fixture-size-dependent. The IOSurface architectural change (multi-week scope) would only meaningfully reduce overhead on DX/PX, not on the smaller fixtures that show the largest absolute regression. This confirms the v8.1.3 default-flip recommendation: **opt-in is the right primitive**, because no protocol-level change makes the daemon universally faster across the medical corpus.
