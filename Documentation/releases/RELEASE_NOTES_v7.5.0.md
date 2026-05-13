# J2KSwift v7.5.0 — Release Notes

**Tag**: `v7.5.0`
**Released**: 2026-05-09
**Headline**: Perf-wash release — closes v7.1.0's deferred forward-HT-GPU-entropy promise with measurements. The path is correctness-shipped but **slower than CPU on every corpus fixture** on Apple M2; per-block GPU cost is ~6.7× CPU per-block, structurally so. Workstream closed; flag stays default OFF; codestream bytes byte-identical to v7.4.0.

---

## Summary

v7.5.0 is a **perf-wash release** in the v6-alpha6 sense: empirical data is the deliverable, not a wall-time win. Per RELEASING.md §3, releases of this shape are explicitly acceptable when no actionable lever exists and the measurement closes a previously-deferred promise.

The promise being closed is from v7.1.0 (May 8 2026):

> the I phase ships GPU forward HT entropy approach C end-to-end behind the existing opt-in flag (default OFF; correctness shipped per the user directive, **perf optimisation is v7.2.x**).

v7.2 → v7.4 went elsewhere — UMA encode boundaries, decoder hot-loop wedge elimination, and CPU NEON respectively. The promised v7.2.x perf work never landed. v7.5 picks it back up, runs the A/B, and concludes honestly.

---

## What's New — Phase 0 measurement

`Tests/J2KMetalTests/V750ForwardHTGPUEntropyPhase0Bench.swift` toggles `EncoderPipeline._gpuForwardHTEntropyEnabled` between runs, encodes the full medical corpus end-to-end via the public `J2KEncoder` API, and captures `J2KGPUForwardHTEntropyTelemetry` snapshots per run for a dispatch / emit / other-ms breakdown. Median of 5, Apple M2, release builds.

### A/B table

| fixture | bytes | CPU ms | GPU ms | Δ ms | Δ % | dispatch ms | emit ms | other ms | fires | blocks/fire |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 45 224 | 0.80 | 13.08 | **−12.27** | **−1526.6 %** | 2.32 | 9.61 | 1.15 | 1 | 25 |
| CT 512² | 436 460 | 3.52 | 17.16 | **−13.63** | **−387.0 %** | 3.31 | 10.54 | 3.30 | 1 | 70 |
| MR 886² | 169 709 | 2.95 | 10.83 | **−7.88** | **−267.2 %** | 7.19 | 18.68 | −15.04 | 4 | 37 |
| XA 1024² | 1 621 712 | 7.68 | 21.73 | **−14.05** | **−182.9 %** | 15.41 | 41.19 | −34.86 | 4 | 68 |
| PX 2459×1316 | 6 453 588 | 22.96 | 57.43 | **−34.47** | **−150.2 %** | 75.17 | 231.24 | −248.98 | 16 | 101 |
| **DX 2800×2288** | **12 705 470** | **50.15** | **72.52** | **−22.37** | **−44.6 %** | 97.91 | 244.07 | −269.46 | 16 | 156 |

**Δ ms / Δ %** are CPU − GPU. Negative = GPU slower. **Every fixture is negative.**

`other ms = gpuMed − dispatchMs − emitMs`. Negative values on multi-fire rows = GPU dispatches running in parallel via the encoder's task-group concurrency; aggregated dispatch+emit wall-time exceeds serialised encode wall-time when fires partially overlap. Correct measurement, not a bug.

### Root cause — per-block GPU cost is ~6.7× CPU on M2

Single-fire fixtures isolate the per-block compute cost cleanly:

| fixture | GPU per-block | CPU per-block | ratio |
|---|---:|---:|---:|
| MR-small (25 blocks) | 0.477 ms | 0.032 ms | 14.9× |
| CT 512² (70 blocks) | 0.198 ms | 0.050 ms | 4.0× |
| **DX 2800×2288 (156 blocks/fire avg, 16 fires)** | **0.135 ms** | **0.020 ms** | **6.7×** |

Even with infinite cross-tile batching, the per-block GPU cost remains ~7× CPU. The classifier + cleanup-pass emit kernels do per-sample chained-state work (MagSgn unstuff, MEL run-length, VLC bit-stream cursor) that is structurally CPU-friendly on Apple M2: cache-resident 4 KB codeblock data, vector-strong CPU, sequential dependency chain.

v7.3.0's HT decoder hot-loop wedge elimination already showed how aggressively the CPU side has been tuned (62.5 → 54.3 ms on DX decode in one release); the forward-encode path benefits from the same CPU-side optimisations, leaving the GPU side without a structural win to capture.

---

## Recommendation — workstream closed

Per the v6-alpha4 lever-ceiling lesson and the v7.4 staged-NEON acceptance discipline:

1. **Keep the flag.** Correctness is shipped (`HTGPUForwardHTEntropyOrchestratorTests/testOrchestrator_GateOnVsOff_BytesIdentical_AllFixtures` proves byte-equality at every fixture). Future hardware (M3/M4/M5 or non-Apple GPUs) may invert the per-block cost curve.
2. **Land the regression-detection benchmark** (Phase 0). If anyone in future tries to flip the default ON on M2, they'll see the negative Δ values immediately.
3. **Close the workstream out** — no further v7.5.x sub-phases. The Phase 0 finding is the deliverable.

This is the same shape as the v7.4 Phase 1 (NEON reconstruction, Δ 0.90 ms) and Phase 3 (SWAR VLC refill, Δ noise-bound) outcomes: empirical rejection is the deliverable.

---

## Backward compatibility

- **Codestream bytes byte-identical to v7.4.0** — no production code changes, only new test infrastructure.
- **No public API changes.** No additions, no removals, no signatures changed.
- **SemVer rule: MINOR** (release artefacts + new test file + version bump).

`getVersion()` returns `"7.5.0"`.

---

## Cross-codec parity (re-run on v7.5.0)

`HTTileParityMatrixTests.testTileParityMatrixOnLargeFixtures` — 12 cells × {OpenJPH 0.27.0, Grok 20.3.0, Kakadu 8.4.1 demo}, all bit-exact. **33/33 external decoder cross-decodes pass** (9/9 ALL-EVEN × 3 decoders, 3/3 ANY-ODD × 2 decoders since Kakadu doesn't support odd tile origins). Unchanged from v7.4.0 as expected.

---

## Test Suite Results (release mode, 0 failures)

| suite | tests | result |
|---|---:|:-:|
| `J2KMedicalCorpusEncodePerformanceTests` | 2/2 | ✓ |
| `J2KMedicalCorpusPerformanceTests` | 2/2 | ✓ |
| `J2KStrictCrossCodecValidationTests` | 3/3 | ✓ |
| `HTTileParityMatrixTests` | 1/1 (12 cells, 33/33 cross-decode bit-exact) | ✓ |
| `V750ForwardHTGPUEntropyPhase0Bench` | 1/1 | ✓ |
| All v7.4 phase parity gates (carried) | 21 sweeps (5+11+5) | ✓ |

---

## API surface

### Added

- `Tests/J2KMetalTests/V750ForwardHTGPUEntropyPhase0Bench.swift` — test-only, non-public.

### Removed / changed

None. No public surface change.

---

## Known limitations

- The forward HT GPU entropy path remains correctness-shipped but measurably slower than CPU on Apple M2 across the full production corpus. The flag is preserved so consumers on different hardware (or future Apple Silicon revisions) can re-measure.
- The Kakadu gap on DX in-process decode (~2.10× post-v7.4) is structural per the v7.4 Phase 3 finding. Closing it further requires algorithmic redesign (bit-parallel prefix-scan SIMD on chained-unstuff state) or different hardware. **Not** in v7.5 scope.
- The "easy" SWAR / batched-dispatch levers on Apple M2 + Swift release + macOS appear exhausted across both the encode (this release) and decode (v7.4) hot paths. The next codec-perf workstream — if one is opened — will need a fundamentally different approach (algorithmic, or different hardware target).

---

## Reproducing the headline numbers

```bash
# Build
swift build -c release --product j2k

# Mandatory pre-release gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Cross-codec parity (12/12 cells)
swift test -c release --filter HTTileParityMatrixTests

# v7.5.0 Phase 0 forward HT GPU entropy A/B
swift test -c release --filter V750ForwardHTGPUEntropyPhase0Bench
```

Apple Silicon required (Metal). On non-Metal hosts the Phase 0 bench skips via `XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, ...)`.

---

## Companion documents

- [V7_5_0_PHASE_0_FINDING.md](V7_5_0_PHASE_0_FINDING.md) — full per-block cost analysis + recommendation + reproduction.
- [RELEASE_NOTES_v7.4.0.md](RELEASE_NOTES_v7.4.0.md) — prior release (staged-NEON arc).
- [RELEASING.md](RELEASING.md) — canonical release process.
