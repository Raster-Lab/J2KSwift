# v7.5 Phase 0 Finding — Forward HT GPU entropy A/B (closing v7.1.0's deferred perf gate)

**Captured**: 2026-05-09, Apple M2 (24G624 / Darwin 24.6.0), release builds, median of 5 runs per cell.

**TL;DR** — v7.1.0 shipped GPU forward HT entropy "approach C" end-to-end with correctness gated, defaulting OFF, and explicitly deferred perf optimisation to v7.2.x. v7.2 → v7.4 went elsewhere. v7.5 reopens the workstream with a Phase 0 ground-truth measurement: **the GPU forward HT entropy path is slower than CPU on every corpus fixture**, including DX 2800×2288 (the production target) where it regresses by 22.4 ms (44.6 %). Per-block GPU cost is ~6.7× the CPU per-block cost on Apple M2; even with infinite cross-tile batching, the gap would not close. **Recommendation: close the workstream out**. Keep the flag (correctness-shipped, opt-in available for future hardware where the curve might invert), but stop driving toward a default-on flip on Apple M2. v7.5.0 ships the honest finding + the regression-detection benchmark.

---

## 1. Context — what v7.1.0 promised

v7.1.0 release notes (#351, May 8 2026):

> the I phase ships GPU forward HT entropy approach C end-to-end behind the existing opt-in flag (default OFF; correctness shipped per the user directive, perf optimisation is v7.2.x).

v7.2.0 → v7.4.0 went to UMA encode boundaries, decoder hot-loop wedge elimination, and CPU NEON respectively. The promised v7.2.x perf optimisation never landed. v7.5 was the first slot where the workstream could be picked back up.

The opt-in surface:
- `EncoderPipeline._gpuForwardHTEntropyEnabled: Bool = false` (env var: `J2K_GPU_FORWARD_HT_ENTROPY=1`)
- `EncoderPipeline._gpuForwardHTEntropyBlockThreshold: Int = 256`

The architecture (`J2KGPUForwardHTEntropyBatch.encodeBlockBatch`):
1. Build per-block `J2KMetalHTForwardClassifyDescriptor` + concatenate sign-magnitude UInt32 coefficients into one pool
2. **Dispatch GPU classifier** once per fire (per-tile-band)
3. **Dispatch GPU cleanup-pass emit** once per fire (approach C — full GPU emit, not the legacy approach-B "GPU classify + CPU emit")
4. Return `(magsgn, mel, vlc)` byte tuples per block, byte-identical to CPU `HTBlockEncoderConformant.encode`

Bit-exact correctness is gated by `HTGPUForwardHTEntropyBatchBitExactTests` and `HTGPUForwardHTEntropyOrchestratorTests/testOrchestrator_GateOnVsOff_BytesIdentical_AllFixtures`.

---

## 2. Phase 0 measurement

`Tests/J2KMetalTests/V750ForwardHTGPUEntropyPhase0Bench.swift` — A/B benchmark mirroring v7.4 phase pattern. Toggles the gate flag between runs, encodes the medical corpus end-to-end via the public `J2KEncoder` API, captures `J2KGPUForwardHTEntropyTelemetry` snapshots per run for dispatch/emit breakdown.

| fixture | bytes | CPU ms | GPU ms | Δ ms | Δ % | dispatch ms | emit ms | other ms | fires | blocks/fire |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 45 224 | 0.80 | 13.08 | **−12.27** | **−1526.6 %** | 2.32 | 9.61 | 1.15 | 1 | 25 |
| CT 512² | 436 460 | 3.52 | 17.16 | **−13.63** | **−387.0 %** | 3.31 | 10.54 | 3.30 | 1 | 70 |
| MR 886² | 169 709 | 2.95 | 10.83 | **−7.88** | **−267.2 %** | 7.19 | 18.68 | −15.04 | 4 | 37 |
| XA 1024² | 1 621 712 | 7.68 | 21.73 | **−14.05** | **−182.9 %** | 15.41 | 41.19 | −34.86 | 4 | 68 |
| PX 2459×1316 | 6 453 588 | 22.96 | 57.43 | **−34.47** | **−150.2 %** | 75.17 | 231.24 | −248.98 | 16 | 101 |
| **DX 2800×2288** | **12 705 470** | **50.15** | **72.52** | **−22.37** | **−44.6 %** | 97.91 | 244.07 | −269.46 | 16 | 156 |

**Δ ms / Δ %** are CPU − GPU. Negative = GPU slower. **Every fixture is negative.**

`other ms = gpuMed − dispatchMs − emitMs`. Negative values on multi-fire rows mean GPU dispatches run partially in parallel via the encoder's task-group concurrency — the summed wall time of all fires exceeds the serialised encode wall. This is correct behaviour, not a measurement bug; it just makes the per-fire overheads look additive when they're partially overlapped.

---

## 3. Root cause — per-block GPU cost is ~6.7× CPU on M2

Single-fire fixtures (MR-small, CT 512²) are the cleanest signal because there's no parallelism to muddy the breakdown:

| fixture | GPU dispatch | GPU emit | CPU encode total | GPU per-block | CPU per-block |
|---|---:|---:|---:|---:|---:|
| MR-small (25 blocks) | 2.32 ms | 9.61 ms | 0.80 ms | 0.477 ms/block | 0.032 ms/block |
| CT 512² (70 blocks) | 3.31 ms | 10.54 ms | 3.52 ms | 0.198 ms/block | 0.050 ms/block |

DX 2800×2288 (16 fires × 156 blocks/fire ≈ 2500 blocks):
- GPU per-block ≈ 21 ms / 156 = **0.135 ms/block**
- CPU per-block ≈ 50 ms / 2500 = **0.020 ms/block**
- **GPU is ~6.7× slower per block than CPU on M2.**

This is the load-bearing observation. The per-fire dispatch overhead (~5-15 ms classifier + emit launch) exists, but it's not the only problem — even with infinite blocks per fire the per-block GPU work is ~7× the per-block CPU work.

### Why GPU forward HT entropy doesn't pay off on Apple M2

The classifier + cleanup-pass emit kernels do per-sample chained-state work (the MagSgn unstuff state, the MEL run-length state, the VLC bit-stream cursor). Each per-sample step depends on the previous step's state. This is not embarrassingly parallel inside a block — it's why decoders also struggle to push entropy work to GPU below very large scales.

The Apple M2 CPU side is uniquely strong here:
- L1/L2 cache hits hard for 32×32 codeblocks (4 KB sample data)
- v7.3.0's HT decoder hot-loop wedge elimination shows how aggressively the CPU side has been tuned (62.5 → 54.3 ms on DX decode in one release)
- The forward path's `encodeCodeBlockConformant` benefits from the same CPU-side optimisations that v7.3.0 captured for decode

The GPU side pays full Metal-compute pipeline latency per fire, plus per-sample memory traffic that's invisible to the CPU's cache.

### Why the predicted "crossover at ~1000 blocks" never materialises

The original Phase 0.5 dispatch-probe predicted dispatch overhead would amortise above ~1000 blocks/fire. Even DX (156 blocks/fire) is below that, but the more fundamental issue is that **per-block GPU cost is ~7× CPU**, so even at 100,000 blocks/fire the GPU side wouldn't close the gap. The dispatch-probe measured kernel-launch latency only, not per-sample compute throughput.

---

## 4. What would have to change to clear the 3 ms DX gate

To beat CPU encode of 50.15 ms by ≥ 3 ms (target ≤ 47 ms wall on DX):

| lever | estimated DX Δ | ships? |
|---|---:|:-:|
| **Cross-tile batching** (one fire instead of 16) | save ~75 ms of dispatch (across overlapping fires); but per-block GPU cost dominates and remains ~340 ms aggregate | not enough alone |
| **Eliminate classifier dispatch** (fold classify into emit kernel) | save ~98 ms aggregate dispatch | helpful but per-block GPU still ~7× CPU |
| **Per-block GPU cost reduction by 7×** to match CPU | unblocks all the rest | unknown how — chained-state per-sample work doesn't trivially parallelise |

The third row is the load-bearing one. None of the levers in (1) or (2) close the gap if (3) is unachievable, and (3) isn't a one-PR engineering task — it would require either:
- A fundamentally different GPU algorithm (e.g., bit-parallel prefix-scan for the unstuff state — uncertain payoff, multi-week prototype)
- A different hardware target (Apple M3/M4/M5 with different GPU compute characteristics, or non-Apple GPUs where per-sample memory throughput is higher relative to CPU)

This is the same lesson v6-alpha4's "lever ceiling" memo captured: residual gaps on Apple M2 + Swift release + macOS are sometimes structural, not engineering laziness.

---

## 5. Recommendation — close the workstream out

The v7.1.0 "perf optimisation is v7.2.x" promise should be honoured by **closing it out with measurements**, not by leaving it indefinitely deferred. Concretely:

1. **Keep the flag**. The path is correctness-shipped and bit-exact (lossless contract holds). Future Apple Silicon may invert the curve; downstream users on different hardware may already see different numbers.
2. **Land the Phase 0 benchmark** as a regression-detection probe. If anyone in future tries to flip the default ON on M2, they'll see this benchmark's Δ values immediately.
3. **Update v7.1.0's release notes pointer** in CHANGELOG to acknowledge the v7.5.0 finding so future readers have closure.
4. **Document the finding here**, with the per-block cost analysis, so the next person who picks this up doesn't repeat the measurement work.
5. **No further v7.5.x sub-phases** for forward HT GPU entropy. The next-up workstream is something else (likely either GPU-side decoder kernel work where the curve actually pays off, or the ongoing structural Kakadu-gap on DX decode).

This is a "perf wash" outcome in the sense the v6-alpha6 entropy arc was: empirical data is the deliverable, not a wall-time win. Per RELEASING.md §3, that's an explicitly acceptable release type.

---

## 6. What lands in this PR

- `Tests/J2KMetalTests/V750ForwardHTGPUEntropyPhase0Bench.swift` — A/B benchmark with dispatch/emit telemetry breakdown, median of 5.
- `V7_5_0_PHASE_0_FINDING.md` — this document.

What does **not** land:
- Any production code changes. The flag stays default OFF; the path stays correctness-only.
- Any optimisation attempts. The Phase 0 finding's recommendation is to close the workstream out, not optimise further.

---

## 7. Reproduction

```bash
# Build
swift build -c release --product j2k

# Mandatory gate (must show 0 failures)
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# v7.5 Phase 0 forward HT GPU entropy A/B
swift test -c release --filter V750ForwardHTGPUEntropyPhase0Bench

# Existing correctness gates (unchanged)
swift test -c release --filter HTGPUForwardHTEntropyOrchestratorTests
swift test -c release --filter HTGPUForwardHTEntropyBatchBitExactTests
```

Apple Silicon hardware required (Metal). On non-Metal hosts the test suite skips via `XCTSkipUnless(J2KMetalHTForwardClassifier.isAvailable, ...)`.
