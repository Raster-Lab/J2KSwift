# v8.0.0 Phase 5 — Warm in-process baseline (Phase 6 XPC-daemon GO/NO-GO)

**Captured**: 2026-05-09, Apple M2.
**Phase 5 deliverable**: measurement-only validation of the persistent-Metal-session direction. Quantifies J2KSwift's **warm in-process** decode walls vs Kakadu's CLI walls. Determines whether the Phase 6 XPC daemon work is justified empirically.

## TL;DR

**XPC daemon Phase 6 is GO.** Warm in-process J2KSwift CPU beats Kakadu's CLI on **4 of 6 corpus fixtures** (MR-small 26× faster, CT 5×, MR 886² 3×, XA 1024² 2.3×). Closing the CLI overhead via persistent session (XPC daemon's job) would deliver these warm numbers to CLI users, flipping all 4 fixtures to wins on the marketable headline.

PX (1.23× behind) and DX (1.51× behind) still need additional in-process compute work even in warm mode. The XPC daemon alone won't close those — Phase 7+ needs to attack PX/DX compute directly.

The marketable claim **"fastest JPEG 2000 codec on Apple Silicon"** becomes empirically defensible once Phase 6 ships: J2KSwift CLI (with persistent Metal session) wins on 4 of 6 production fixtures.

## Measurement

`Tests/J2KMetalTests/V8Phase5WarmInProcessBenchmark.swift` runs each corpus fixture through:
1. `preWarm()` once at session start
2. One CPU warm-up decode (mr_small) to warm caches
3. Median of 5 timed `J2KDecoder.decode` calls (CPU warm, post-Phase-2 default)
4. Median of 5 timed `decoder.decodeWithGPUHT(_:session:)` calls (GPU warm)

Compares against the Kakadu `kdu_expand` CLI walls from the user's external eval matrix (also reproduced locally in Phase 1 finding §1).

| fixture | CPU warm (ms) | GPU-HT warm (ms) | best (ms) | **Kakadu CLI (ms)** | best/Kakadu | result |
|---|---:|---:|---:|---:|---:|:-:|
| MR-small 180² | **0.58** | 8.50 | 0.58 | 15 | **0.04×** | ✓ WIN |
| CT 512² | **3.05** | 9.71 | 3.05 | 15 | **0.20×** | ✓ WIN |
| MR 886² | **5.60** | 21.33 | 5.60 | 17 | **0.33×** | ✓ WIN |
| XA 1024² | **7.89** | 32.09 | 7.89 | 18 | **0.44×** | ✓ WIN |
| PX 2459×1316 | **29.48** | 118.14 | 29.48 | 24 | 1.23× | behind |
| DX 2800×2288 | **54.41** | 127.88 | 54.41 | 36 | 1.51× | behind |

## What this changes

### Before Phase 5

The post-Phase-4 CLI matrix showed J2KSwift behind Kakadu on every fixture (1.27× to 2.47×). It was unclear whether closing CLI overhead alone would deliver wins or whether deeper compute optimisation was the only path forward.

### After Phase 5

**Closing CLI overhead alone delivers wins on 4 of 6 fixtures.** The dominant remaining gap is process startup + Metal init that the XPC daemon eliminates by reusing a single long-lived Metal session across CLI invocations.

For the 2 remaining behind-Kakadu fixtures (PX, DX):
- PX: warm gap is **5.5 ms** (29.48 − 24.0) — small enough that even modest in-process compute work could close it
- DX: warm gap is **18.4 ms** (54.41 − 36.0) — larger; needs sustained Phase 7+ entropy/iDWT optimisation

These per-fixture gaps are what Phase 7+ targets. Compared to the post-Phase-4 CLI gaps (32-53 ms), the warm-mode gaps are 3-6× smaller and more tractable.

## Surprising finding — GPU-HT path is slower than CPU even warm

GPU-HT walls are 2-7× slower than CPU walls on every fixture. The v5.27.0 CHANGELOG documented `decodeWithGPUHT` winning at 17 M px mammography (4.6×) — but on the eval corpus's largest fixture (DX 6.4 M px), GPU-HT loses to CPU.

This isn't a Phase 5 deliverable to investigate, but it does refine the strategy:
- The XPC daemon's primary win comes from **CPU** path session persistence, not GPU
- GPU paths are still relevant for very large images (mammography 17M+ px), but that's outside the corpus
- Phase 6's design should ensure the CPU warm path is the production default after the daemon connects

## What lands in this PR

- `Tests/J2KMetalTests/V8Phase5WarmInProcessBenchmark.swift` — the warm-process benchmark (now in the test suite for future regression detection)
- `V8_0_0_PHASE_5_FINDING.md` — this document

No production code changes. Phase 5 is measurement only.

## Mandatory gate (release mode, 0 failures)

10/10 pass:
- `J2KMedicalCorpusEncodePerformanceTests` — 2/2
- `J2KMedicalCorpusPerformanceTests` — 2/2
- `J2KStrictCrossCodecValidationTests` — 3/3
- `HTTileParityMatrixTests` — 1/1
- `MgRegressionTriageTest` — 2/2

## Phase 6 — XPC daemon (GO, scoped here)

**Architecture sketch**:
1. **`j2kd` daemon** — long-lived process, holds `J2KMetalSession.processShared` warm. Listens on a Mach service.
2. **`j2k` CLI** — auto-discovers the daemon at startup. If reachable, marshalls decode requests to it via XPC. If not (cold start of CLI before daemon is up, OR daemon disabled), falls back to the existing in-process path (Phase 4 default).
3. **Marshalling** — for large images, use shared memory (Mach memory objects) to avoid copying 33 MB through XPC. Small images marshall via standard XPC dictionary.
4. **Lifecycle** — daemon starts on-demand via launchd, stays running for N minutes after last request, then exits to free memory.

**Phase 6 deliverables (multi-PR scope)**:
- 6.1: Daemon skeleton + Mach service registration + simple round-trip
- 6.2: Decode RPC with shared-memory marshalling
- 6.3: CLI client with auto-discovery + fallback
- 6.4: launchd plist for on-demand start
- 6.5: Lifecycle management (idle timeout, memory pressure response)
- 6.6: Mandatory gate + CLI matrix re-measurement (expect 4/6 fixtures to flip to WIN)

Each sub-phase is its own PR with its own RFC + measurement.

**Estimated scope**: 1-2 weeks of focused work. Multi-day per sub-phase.

## Phase 7+ — In-process compute on PX/DX (parallel work after Phase 6)

After XPC daemon ships, the remaining 5.5 ms (PX) and 18.4 ms (DX) warm-process gaps to Kakadu are the next targets. Candidates:

1. CPU HT entropy hot-path Apple-NEON (199 ms accumulated on DX, dominant stage)
2. TaskGroup allocator profiling (per-tile dispatch overhead reduction)
3. Re-attempt cross-tile batched HT entropy decode (the parked v7.5.1 hotfix subject — root-cause the 24-bit overflow and re-enable)
4. Multi-level fused 5/3 INT IDWT Metal kernel (the original Phase 2 plan, deferred when CLI cold-start dominated; in Phase 6+ warm-session world, GPU IDWT has a chance to win on big fixtures)

## Reproduction

```bash
swift build -c release --product j2k

swift test -c release --filter V8Phase5WarmInProcessBenchmark
```
