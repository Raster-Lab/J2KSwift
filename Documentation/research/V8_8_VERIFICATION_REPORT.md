# V8.8 — cross-codec verification on medical corpus + recommendation

**Date**: 2026-05-10
**Branch**: `v8.8-gcd-vs-taskgroup-phase0` (research; not for merge)
**Goal**: validate the overnight research findings on the full medical corpus (not just DX), and decide whether the multi-week IOSurface architectural change is worth pursuing.

---

## Cross-codec verification: daemon vs in-process per-fixture

Paired interleaved A/B (N=20 paired runs after 4 warmups), Apple M2, release-mode binaries, warm-cache CLI:

| Fixture           |  in-proc ms | daemon ms |  Δ daemon ms | IOSurface fix proj | IOSurface Δ vs in-proc |
|-------------------|------------:|----------:|-------------:|-------------------:|-----------------------:|
| MR-small 180×180  |        5.73 |      6.96 |        −1.23 |               2.46 |              **+3.27** |
| CT 512×512        |        8.76 |     15.44 |        −6.67 |              10.94 |                 −2.17  |
| MR 886×886        |       12.26 |     18.73 |        −6.47 |              14.23 |                 −1.97  |
| XA 1024×1024      |       17.22 |     22.68 |        −5.46 |              18.18 |                 −0.96  |
| PX 2459×1316      |       43.33 |     43.66 |        −0.33 |              39.16 |              **+4.17** |
| DX 2800×2288      |       74.11 |     74.92 |        −0.81 |              70.42 |              **+3.69** |

```
Aggregate (sum across corpus):
  in-process total:    161.41 ms
  daemon total:        182.39 ms (-20.98 ms regression vs in-proc)
  IOSurface projected: 155.39 ms (+6.02 ms savings vs in-proc; +27.00 ms vs current daemon)
```

## Two unexpected findings

### 1. The daemon is actively regressing across the medical corpus

The original v8.8 DX-only A/B showed daemon −2.34 ms. The full-corpus measurement is much worse:

- **Small/medium fixtures (CT/MR/XA): −5 to −7 ms regression** — the NSXPCInterface proxy fixed cost (~5–7 ms) is a large fraction of the small decode time.
- **Large fixtures (PX/DX): roughly equal** — proxy cost is amortised, Metal cold-start partly offsets it.

This is bigger than I originally documented. **End-users running tight CLI loops (DICOM viewer thumbnails, batch convert scripts) are paying 20+ ms across the corpus** without benefit, because the warm-cache scenario is the common case and the daemon was tuned for cold-shot.

### 2. The cold-shot benefit isn't visible in warm-cache testing

The original v8.1.0 measurement of "DX 72 ms → 55 ms with daemon" required dropping the file cache (purge / fresh boot). In typical user flows where the file cache stays warm, **the daemon's only meaningful benefit is on the very first cold-shot per session**.

## Can we take the IOSurface approach?

**Technical viability: YES, but with caveats.** The IOSurface architecture would:
- Project **~27 ms savings vs current daemon** across the corpus (closes the regression entirely)
- Project **~6 ms savings vs in-process** (modest net win)
- Clear the 3 ms wall threshold on **3 of 6 fixtures** (MR-small, PX, DX)
- Wash on the other 3 fixtures (CT, MR 886², XA)

**Engineering cost: 2–3 weeks**, requiring:
- New `J2KDecoder.decode(_:into: UnsafeMutableRawPointer)` API to write directly into a caller-provided buffer (J2KDecoder currently allocates internally)
- Daemon-side IOSurface pool (pre-allocated for common DX/PX sizes — 25 MB × N pre-allocated)
- Client-side IOSurface receive + lock-for-read in `J2KDaemonClient.decode`
- `NSXPCInterface.setXPCType(XPC_TYPE_IOSURFACE, ...)` for the reply slot — Objective-C bridging required since `xpc_type_t` is not Swift-importable
- Cross-codec parity re-validation (the IOSurface-backed Data may have different alignment / lifecycle semantics than the heap-allocated Data)

**Risk: medium.** The IOSurface approach has zero published precedent on GitHub for NSXPCConnection workflows; we would be navigating Apple's documented-but-unused `setXPCType:` opt-in path. Plus J2KDecoder's internal pixel buffer ownership model would need to change.

## Simpler alternative — change the daemon's default

The daemon was **wrongly defaulted to "always-on"** in v8.1.0 based on cold-shot DX measurements that don't reflect warm-cache CLI loop usage. A 1-day fix:

**Option A — flip default to `--no-daemon`, opt-in `--daemon`**:

```bash
j2k decode -i input.j2k -o output.pgm           # in-process (default, no regression)
j2k decode -i input.j2k -o output.pgm --daemon  # daemon (opt-in, cold-shot benefit)
```

- **Cost**: 1 line change in `Sources/J2KCLI/Commands.swift`
- **Win**: corpus-wide regression eliminated (-20.98 → 0 ms)
- **Loss**: cold-shot users have to pass `--daemon` explicitly to get the v8.1.0 behaviour
- **Documentation**: update `Documentation/BENCHMARK.md` and `RELEASE_NOTES_v8.1.x.md` to clarify when to use daemon

**Option B — smart routing heuristic**:

Auto-detect cold-shot via Mach absolute time since last invocation OR file-cache check. Use daemon when cold, in-process when warm.

- **Cost**: 2-3 days to design + test heuristic
- **Win**: best-of-both-worlds without user opt-in
- **Risk**: heuristic mispredicts and degrades user experience

## Recommendation

**Take the SIMPLER alternative (Option A — default to `--no-daemon`)**, NOT the IOSurface approach.

Reasoning:

1. **The daemon's value on warm-cache CLI is essentially zero.** v8.8 cross-codec data shows the daemon saves at most 0.81 ms (DX) and loses up to 6.67 ms (CT). The cold-shot value is real but only on the first invocation per session.

2. **The IOSurface approach projects only +6 ms savings** across the full corpus vs in-process (the realistic "no daemon at all" baseline). 6 ms across 6 fixtures = ~1 ms per fixture average — well below the perception threshold for end-users.

3. **The IOSurface approach is 2-3 weeks of engineering** with multiple risk vectors (J2KDecoder API change, IOSurface XPC plumbing, parity revalidation, undocumented `setXPCType:` path). For ~1 ms per fixture, this is structurally below the v7.4 acceptance gate.

4. **The simpler fix (default flip) is 1 day of work** and eliminates the regression entirely. It also better matches the actual user mental model: "I want fast decode by default, opt into daemon for cold-shot scenarios".

5. **Future work**: if M3+/A-series shifts the curve, or Apple ships a lower-overhead xpc primitive, revisit the IOSurface approach. Until then, the IPC layer is at structural lever-ceiling on M2.

## Cross-codec parity gate (re-validated post-research)

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` + `J2KStrictCrossCodecValidationTests` re-run on the v8.8 research branch after all instrumentation + decodeFile + IPC bench changes:

| Suite | Tests | Result |
|-------|------:|--------|
| `HTTileParityMatrixTests` | 1 | passed (12/12 cells × 3 decoders = 36/36 bit-exact) |
| `J2KStrictCrossCodecValidationTests` | 3 | 3/3 passed |

All v8.8 research instrumentation (J2KD_DECODE_TRACE, decodeFile method, IPC alternative microbenches) preserves correctness invariants. No production code path changes.

## Decision tree

```
Does the daemon provide meaningful warm-cache CLI benefit?
├── YES (cold-shot only, rare per-session)
│   └── Action: flip default to --no-daemon, opt-in --daemon
│       Effort: 1 day. Eliminates -20.98 ms corpus regression.
│
├── NO (warm-cache wash or regression)
│   ├── Take IOSurface approach?
│   │   ├── YES → 2-3 weeks engineering, +6 ms corpus savings, clears 3/6 fixtures
│   │   └── NO  → flip default to --no-daemon (Option A), 1 day, stronger ROI
│
└── ROOT decision: NO meaningful warm-cache benefit; SIMPLER fix wins
    └── Recommend: Option A (default flip).
```

## Files added in this verification

- `V8_8_VERIFICATION_REPORT.md` — this document
- `/tmp/v88_verify_decoded.pgm` — temporary decoded fixture (cleaned up after run)

No code changes. No CLI routing changes (Option A is for a future PR if accepted).
