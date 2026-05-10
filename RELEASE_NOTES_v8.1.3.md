# J2KSwift v8.1.3 — `j2kd` daemon flipped to opt-in (warm-cache CLI loop fix)

**Tag**: `v8.1.3` (DRAFT — release pending review)
**Released**: TBD
**Headline**: The `j2kd` XPC daemon CLI default is flipped from opt-out (`--no-daemon`) to **opt-in** (`--daemon`). Eliminates a measured −20.98 ms regression across the medical corpus on warm-cache CLI loops, while preserving the cold-shot benefit for users who explicitly opt in.

---

## What v8.1.3 is

The v8.1.0 default routing — "use the daemon if installed, in-process otherwise" — was tuned for cold-shot DX 2800×2288 measurements (72 → 55 ms with the daemon). v8.8's overnight research uncovered a different operating point: **warm-cache CLI loops**, where the daemon's NSXPCInterface proxy overhead (~5–7 ms) is a significant fraction of small/medium fixtures' decode time, while Metal cold-start is already amortised by the OS file cache.

The v8.8 corpus verification (`V8_8_VERIFICATION_REPORT.md`) measured per-fixture daemon-vs-in-process Δ across 6 medical fixtures (paired N=20):

| Fixture          | in-proc ms | daemon ms |    Δ    |
|------------------|-----------:|----------:|--------:|
| MR-small 180²    |       5.73 |      6.96 | **−1.23**|
| CT 512²          |       8.76 |     15.44 | **−6.67**|
| MR 886²          |      12.26 |     18.73 | **−6.47**|
| XA 1024²         |      17.22 |     22.68 | **−5.46**|
| PX 2459×1316     |      43.33 |     43.66 |   −0.33  |
| DX 2800×2288     |      74.11 |     74.92 |   −0.81  |
| **Aggregate**    |     161.41 |    182.39 | **−20.98** |

In typical user flows (DICOM viewer thumbnail loops, batch-convert scripts, IDE-integrated decoders), the file cache stays warm and the daemon's cold-shot value is rare. The daemon-on default was the wrong choice for the common case.

## Changed (default flip)

| Behaviour                         | v8.1.2 (old)            | v8.1.3 (new)                    |
|-----------------------------------|-------------------------|---------------------------------|
| `j2k decode -i ... -o ...`        | daemon if reachable     | **in-process** (no proxy tax)   |
| `j2k decode -i ... -o ... --daemon`   | (flag did not exist)    | **opt-in** daemon route         |
| `j2k decode -i ... -o ... --no-daemon`| in-process              | in-process (no-op alias kept for backward-compat) |

Implementation: `Sources/J2KCLI/Commands.swift` — toggles the daemon-routing branch from `if !noDaemon` to `if useDaemon`. Falls back transparently to in-process if `--daemon` is set but the daemon is unreachable.

The `--daemon` flag is the right primitive for:
- One-shot DICOM viewer launches where Metal would otherwise be cold-started in the client process
- Batch scripts that do EXACTLY ONE decode per invocation
- Cold-shot benchmarking / measurement work

The default (in-process) is the right primitive for:
- Tight loops issuing many decodes in succession
- Any flow where the client process can amortise its own Metal init across multiple decodes (use the in-process `J2KDecoder.preWarm()` API instead of the daemon)

## Backward compatibility

- **Codestream bytes byte-identical to v8.1.2.** No encoder change.
- **Public API**: `J2KDaemonClient.decode(_:)` unchanged. `J2KDaemonClient.decodeFile(...)` added in v8.8 as research-only (do not wire to production CLI).
- **CLI flags**: `--no-daemon` preserved as no-op alias. Scripts that pass `--no-daemon` continue to work bit-identically. Scripts that depended on the v8.1.x daemon-by-default behaviour need to pass `--daemon` explicitly to retain that behaviour.
- `getVersion()` returns `"8.1.3"`.

## SemVer rule

**PATCH** per RELEASING.md — bug fix (the v8.1.x daemon-on default was a tuning regression for the warm-cache CLI use case); no public API removed; no codestream byte change. The behaviour change is opt-in friendly: users who passed `--no-daemon` see no change; users who didn't pass anything now get faster default behaviour.

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | 2/2 passed |
| `J2KMedicalCorpusPerformanceTests` | 2 | 2/2 passed |
| `J2KStrictCrossCodecValidationTests` | 3 | 3/3 passed |
| `HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures` | 1 | passed (12/12 cells × 3 decoders = 36/36 bit-exact) |

## Verification — corpus A/B post-flip

```
default (post-flip):   161.95 ms  (= explicit --no-daemon: 157.60 ms; +4.35 ms within noise)
--daemon (opt-in):     243.08 ms  (Δ vs default: +81.13 ms — daemon overhead, by design)
```

The default and the legacy `--no-daemon` flag produce equivalent timing (both in-process). The opt-in `--daemon` flag still routes to j2kd as before.

Net improvement vs pre-flip default: **+20.44 ms across 6 medical fixtures** for the typical CLI loop user.

## Cross-codec parity matrix (re-validated)

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` — 12 cells (4 fixtures × 3 tile modes) × 3 external decoders (OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 demo) = **36/36 cross-decode comparisons bit-exact** (max diff = 0). Codestream bytes preserve the v8.1.2 invariants.

## What WOULD justify reverting

1. Strong end-user feedback that one-shot CLI users (the original v8.1.0 daemon-on default beneficiary) are surprised by the slower cold-shot behaviour. Add a deprecation-period dual-default with `--daemon-default` env var if needed.
2. A future macOS SDK that ships a lower-overhead NSXPCConnection (or replaces it with a Swift-native xpc primitive) which would close the proxy-overhead gap.
3. Implementation of the IOSurface-backed-decoder architecture (deferred multi-week effort per `V8_8_RESEARCH_OVERNIGHT.md`) which would make the daemon path competitive on warm-cache too.

## Reproducing

```bash
# Mandatory release gate (release mode):
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests|HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures'

# Verify default-flip behavior:
j2k decode -i input.j2k -o output.pgm           # in-process by default (post-flip)
j2k decode -i input.j2k -o output.pgm --daemon  # opt-in daemon
j2k decode -i input.j2k -o output.pgm --no-daemon  # explicit in-process (legacy alias)

# Re-run corpus A/B (paired N=20):
python3 - <<'EOF'
# (see V8_8_VERIFICATION_REPORT.md "Verification — corpus A/B post-flip" section)
EOF
```

## References

- v8.8 verification: [`V8_8_VERIFICATION_REPORT.md`](V8_8_VERIFICATION_REPORT.md) — corpus A/B + recommendation
- v8.8 daemon decomposition: [`V8_8_DAEMON_WARM_CACHE_FINDING.md`](V8_8_DAEMON_WARM_CACHE_FINDING.md) — original diagnosis
- v8.8 overnight research: [`V8_8_RESEARCH_OVERNIGHT.md`](V8_8_RESEARCH_OVERNIGHT.md) — full IPC primitive sweep
- v8.1.0 release: [`RELEASE_NOTES_v8.1.0.md`](RELEASE_NOTES_v8.1.0.md) — original daemon-on default rationale
- Cross-codec parity matrix: [`Documentation/BENCHMARK.md`](Documentation/BENCHMARK.md)
