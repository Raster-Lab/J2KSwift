# J2KSwift v8.1.3 — `j2kd` daemon: opt-in default + smart-routing + encoder support; mmap'd CLI input

**Tag**: `v8.1.3`
**Released**: 2026-05-10
**Headline**: Four customer-facing CLI improvements derived from the v8.8 research arc (PR #410). The `j2kd` XPC daemon flips from opt-out to opt-in (eliminating a measured −20.98 ms warm-cache regression); a new `--daemon auto` smart-router picks daemon-vs-in-process per codestream size; encoder daemon support lands (`j2k encode --daemon` saves **−40.2% on encode wall** corpus-wide); and `j2k decode` now mmaps codestream input (saving ~3 ms on cold-shot DX).

---

## Why v8.1.3

The v8.1.0 default routing — "use the daemon if installed, in-process otherwise" — was tuned for cold-shot DX 2800×2288 measurements (72 → 55 ms with the daemon). The v8.8 research arc (kept in PR #410 as a research-only branch) uncovered a different operating point: **warm-cache CLI loops**, where the daemon's NSXPCInterface proxy overhead (~5–7 ms) is a significant fraction of small/medium fixtures' decode time, while Metal cold-start is already amortised by the OS file cache.

Per-fixture daemon-vs-in-process Δ across 6 medical fixtures (paired N=20, before this release):

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

## Changes

### 1. `j2k decode` daemon default flipped to opt-in

| Behaviour                                | v8.1.2 (old)            | v8.1.3 (new)                                                  |
|------------------------------------------|-------------------------|---------------------------------------------------------------|
| `j2k decode -i ... -o ...`               | daemon if reachable     | **in-process** (no proxy tax)                                 |
| `j2k decode -i ... -o ... --daemon`      | (flag did not exist)    | **opt-in** daemon route                                       |
| `j2k decode -i ... -o ... --daemon auto` | (flag did not exist)    | **smart**: daemon for codestream ≥ 3 MB, in-process otherwise |
| `j2k decode -i ... -o ... --no-daemon`   | in-process              | in-process (no-op alias kept for backward-compat)             |

`Sources/J2KCLI/Commands.swift` — toggles the daemon-routing branch from `if !noDaemon` to `if useDaemon`. Falls back transparently to in-process if `--daemon` is set but the daemon is unreachable.

### 2. `--daemon auto` smart routing for decode

3 MB codestream-size threshold derived from v8.8 fixture-scaling research: NSXPC client-side machinery (~5 ms) overlaps with daemon-side decode; when decode takes longer than the proxy overhead (≥ 3 MB ≈ 3 MP at typical lossless compression), the overhead is hidden and the daemon's amortised Metal cold-start avoidance becomes a net win.

Verified on the medical corpus (paired N=15, post-flip):

| Fixture            | codestream | in-proc | `--daemon` | `--daemon auto` | picked |
|--------------------|-----------:|--------:|-----------:|-----------------:|:------:|
| MR-small 180²      |     45 KB |  5.73 ms|     7.60 ms|        **5.75 ms**| in-proc |
| CT 512²            |    436 KB |  8.57 ms|    19.29 ms|        **8.69 ms**| in-proc |
| MR 886²            |    169 KB | 12.20 ms|    24.89 ms|       **12.06 ms**| in-proc |
| XA 1024²           |    1.6 MB | 16.47 ms|    28.59 ms|       **16.84 ms**| in-proc |
| PX 2459×1316       |    6.5 MB | 43.90 ms|    43.52 ms|       **42.16 ms**| daemon  |
| DX 2800×2288       |   12.7 MB | 75.55 ms|    75.21 ms|       **71.44 ms**| daemon  |

**Aggregate corpus wall**: in-proc 162.42 ms / `--daemon` 199.10 ms / `--daemon auto` 156.94 ms. Smart routing is strictly the best across the corpus.

### 3. Encoder daemon support — major win

New `J2KDaemonProtocol.encode(pixelData:width:height:bitDepth:signed:reply:)` method, daemon-side implementation using the default HT-conformant lossless 5/3 config (medical-corpus product target), and CLI flags `j2k encode --daemon` / `--daemon auto`.

The encoder is dominated by per-process codec library load (HT block coders, MCT tables, DWT scratch pools, ~30 ms cold-cache). The daemon amortises that across calls. For encode, `--daemon auto` is effectively always-on (the daemon wins for every fixture size, including 262 K-pixel CT/MR — even small inputs benefit from amortised library load).

Verified on the medical corpus (paired N=8 after 4 warmups):

| Fixture          | pixels    | in-proc   | `--daemon auto` | savings (auto)   |
|------------------|----------:|----------:|----------------:|-----------------:|
| MR-small 512²    |     262 K |  45.09 ms |    **12.74 ms** | **−32.35 (−72%)** |
| CT 512²          |     262 K |  43.45 ms |    **12.17 ms** | **−31.28 (−72%)** |
| XA 3072×2560     |     7.9 M | 116.19 ms |    **74.87 ms** | **−41.32 (−36%)** |
| PX 2812×1316     |     3.7 M |  77.79 ms |    **37.66 ms** | **−40.13 (−52%)** |
| MG 3517×4784     |    16.8 M | 180.95 ms |   **140.25 ms** | **−40.70 (−22%)** |
| DX 2288×2798     |     6.4 M | 108.18 ms |    **64.01 ms** | **−44.16 (−41%)** |
| **Aggregate**    |           |  571.65 ms|   **341.71 ms** | **−229.93 (−40.2%)** |

**Codestream byte parity**: in-process and daemon encode paths produce MD5-matched bytes for all 6 fixtures.

### 4. mmap'd codestream input for decode CLI

`Data(contentsOf:options: [.alwaysMapped])` instead of eager full-file read. The decoder reads bytes lazily as the page-faulted mmap region is touched, saving ~3 ms on cold-shot DX (12 MB codestream).

Verified on the medical corpus:

| Fixture          | pre-mmap | post-mmap |     Δ |
|------------------|---------:|----------:|------:|
| MR-small 180²    |   5.73 ms|   5.63 ms | −0.10 |
| CT 512²          |   8.76 ms|   8.60 ms | −0.16 |
| MR 886²          |  12.26 ms|  12.25 ms | −0.01 |
| XA 1024²         |  17.22 ms|  16.66 ms | −0.56 |
| PX 2459×1316     |  43.33 ms|  42.41 ms | −0.92 |
| **DX 2800×2288** |  74.11 ms|  71.04 ms | **−3.07** |
| **Aggregate**    | 161.41 ms| 156.59 ms | **−5.36** |

Encoder side (`Sources/J2KCLI/ImageIO.swift`) was already using `.mappedIfSafe`.

## Combined v8.1.3 impact

Mixed DX round-trip (decode + encode):
- Pre-v8.8: in-proc decode 74.11 ms + in-proc encode 108.18 ms = 182.29 ms
- v8.1.3 (auto-routing): mmap-decode 71.04 ms + daemon encode 64.01 ms = **135.05 ms (−25.9%)**

CT 512² thumbnail round-trip:
- Pre: 8.76 ms + 43.45 ms = 52.21 ms
- v8.1.3: 8.60 ms + 12.17 ms = **20.77 ms (−60.2%)**

## Backward compatibility

- **Codestream bytes byte-identical to v8.1.2.** No encoder change.
- **Public Swift API**: `J2KDaemonClient.decode(_:)` unchanged. New: `J2KDaemonClient.encode(pixelData:width:height:bitDepth:signed:)`. (`J2KDaemonClient.decodeFile(...)` is on the protocol but documented research-only — not wired into production CLI; do not use.)
- **CLI flags**: `--no-daemon` preserved as no-op alias for backward-compat. Scripts that pass `--no-daemon` continue to work bit-identically. Scripts that depended on the v8.1.x daemon-by-default decode behaviour need to add `--daemon` explicitly.
- `getVersion()` returns `"8.1.3"`.

## SemVer rule

**PATCH** per RELEASING.md — bug fix (v8.1.x daemon-on default was a tuning regression for warm-cache CLI loops); no public API removed; no codestream byte change. The behaviour change is opt-in friendly: users who passed `--no-daemon` see no change; users who didn't pass anything now get faster default behaviour and can opt back into daemon via `--daemon` or `--daemon auto`.

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|---:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2 | 2/2 passed |
| `J2KMedicalCorpusPerformanceTests` | 2 | 2/2 passed |
| `J2KStrictCrossCodecValidationTests` | 3 | 3/3 passed |
| `HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures` | 1 | passed (12/12 cells × 3 decoders = 36/36 bit-exact) |

## Cross-codec parity matrix (re-validated)

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` — 12 cells (4 fixtures × 3 tile modes) × 3 external decoders (OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 demo) = **36/36 cross-decode comparisons bit-exact** (max diff = 0). Codestream bytes preserve the v8.1.2 invariants.

## Research provenance

The v8.1.3 changes are productisation of the v8.8 research arc, kept open as **PR #410** (`v8.8-gcd-vs-taskgroup-phase0` branch). That branch contains 12 lever-ceiling investigations (mmap probes, GCD vs TaskGroup, Accelerate framework sweep, AMX feasibility, IOSurface / mach_vm_remap / xpc_shmem alternatives, MTLBinaryArchive probe, daemon overhead decomposition, fixture-size scaling, cross-codec verification) plus the four production wins shipped here. PR #410 is **not for merge**; it stays open as the research artefact tree for future investigators.

## Reproducing

```bash
# Mandatory release gate (release mode):
swift test -c release --filter \
  'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests|HTTileParityMatrixTests/testTileParityMatrixOnLargeFixtures'

# Decode flag matrix (post-flip):
j2k decode -i input.j2k -o output.pgm                 # in-process (default)
j2k decode -i input.j2k -o output.pgm --daemon        # opt-in daemon
j2k decode -i input.j2k -o output.pgm --daemon auto   # smart router (3 MB threshold)
j2k decode -i input.j2k -o output.pgm --no-daemon     # explicit in-process (alias)

# Encode flag matrix (new):
j2k encode -i input.pgm -o output.j2k --htj2k --lossless                  # in-process (default)
j2k encode -i input.pgm -o output.j2k --htj2k --lossless --daemon         # opt-in daemon
j2k encode -i input.pgm -o output.j2k --htj2k --lossless --daemon auto    # smart router (always-on for encode)
```

## References

- v8.8 research branch (research artefacts, NOT for merge): [PR #410 `v8.8-gcd-vs-taskgroup-phase0`](https://github.com/Raster-Lab/J2KSwift/pull/410)
- v8.1.0 release: [`RELEASE_NOTES_v8.1.0.md`](RELEASE_NOTES_v8.1.0.md) — original daemon-on default rationale
- v8.1.2 release: [`RELEASE_NOTES_v8.1.2.md`](RELEASE_NOTES_v8.1.2.md) — investigation suite (v8.5 + v8.6 + v8.7 phase-0 wash reports)
- Cross-codec parity matrix: [`Documentation/BENCHMARK.md`](Documentation/BENCHMARK.md)
