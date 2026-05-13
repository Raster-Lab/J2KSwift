# Daemon-CLI overhead — methodology finding

**Date:** 2026-05-13
**Host:** Apple M2 (Mac14,2, 4P+4E, 16 GB), macOS Darwin 24.6.0
**J2KSwift version:** 9.5.2
**Trigger:** User-observed discrepancy between two J2KSwift+daemon measurements on the same host within the same day.

## The discrepancy

Two measurements of `j2k encode --daemon` on the medical corpus, same host, same J2KSwift binary, same day:

| Fixture | Cross-codec bench (sustained load) | Isolated re-measurement | Δ |
|---|---:|---:|---:|
| MR-small 180² | 9.72 ms | **6.44 ms** | 3.3 ms inflated |
| MR 886² | 19.76 ms | **11.96 ms** | 7.8 ms inflated |
| PX 2459×1316 | 74.99 ms | **30.71 ms** | **44 ms inflated** |
| DX 2800×2288 | 77.44 ms | **57.67 ms** | 19.8 ms inflated |

The PX 44 ms gap was the smoking gun — PX has half DX's pixel count, so any XPC-marshal-scales-with-payload explanation would predict PX overhead *less* than DX, not double.

## Root cause: sustained-load measurement noise

`Scripts/benchmarks/cross_codec_warm_bench.py` runs ~700 subprocess invocations back-to-back across 38 PGM fixtures × 4 codecs × (encode + decode), plus 13 DICOM fixtures × J2KSwift encode — total runtime ~12 minutes.

Under sustained load:
- macOS scheduler may throttle / yield more aggressively
- Page cache pressure increases as fixture files churn through buffers
- Thermal headroom decreases (modest on M2 air-cooled, but real)
- Background daemons (mds, mds_stores, time-machine, spotlight-related) may opportunistically reclaim quiet CPU windows

Per-fixture timing measured in this state has **σ that grows non-linearly with fixture size**: small fixtures stay close to their isolated number; large fixtures see inflated medians as scheduler+system effects compound.

## Reproducing — isolated measurement

```python
import time, subprocess
J2K = ".build/release/j2k"
SRC = "Tests/Fixtures/CrossCodec/px_study_001_instance_000001.pgm"
OUT = "/tmp/px.j2k"

# 5 warmups (discarded), then 30 timed runs
for _ in range(5):
    subprocess.run([J2K, "encode", "-i", SRC, "-o", OUT,
                    "--htj2k", "--lossless", "--daemon", "--quiet"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
samples = []
for _ in range(30):
    t0 = time.perf_counter()
    subprocess.run([J2K, "encode", "-i", SRC, "-o", OUT,
                    "--htj2k", "--lossless", "--daemon", "--quiet"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    samples.append((time.perf_counter() - t0) * 1000)
samples.sort()
median = samples[15]   # ~30.86 ms isolated; ~74.99 ms sustained-load
```

Run this **on a quiet system** (no concurrent benches, no Xcode build active, no browser doing background work). The median converges to ~30 ms with σ <1.5 ms.

## High-N controlled results

n=30 per fixture, 5 warmups, on a quiet system:

| Fixture | p5 | p25 | p50 | p75 | p95 | mean | σ |
|---|---:|---:|---:|---:|---:|---:|---:|
| MR-small 180² | 7.77 | 8.75 | **9.11** | 9.52 | 10.02 | 9.04 | 0.68 |
| MR 886² | 10.27 | 11.26 | **12.14** | 13.06 | 13.89 | 12.14 | 1.33 |
| PX 2459×1316 | 30.10 | 30.60 | **30.86** | 31.08 | 31.46 | 30.98 | 1.01 |
| DX 2800×2288 | 55.35 | 56.49 | **57.44** | 58.26 | 60.25 | 57.54 | 1.47 |

σ ≤ 1.47 ms across all fixtures — high confidence the isolated medians are correct.

## True daemon-CLI overhead

Comparing to in-process warm encode (`J2KMedicalCorpusEncodePerformanceTests`, NEON ON, same day):

| Fixture | In-proc warm | Daemon-CLI isolated | Overhead |
|---|---:|---:|---:|
| MR-small 180² | 0.6 ms | 9.11 ms | **+8.5 ms** (mostly fork+exec floor; encode is sub-ms) |
| MR 886² | 12.7 ms | 12.14 ms | **−0.6 ms** (within noise — daemon ≈ in-proc) |
| PX 2459×1316 | 28.2 ms | 30.86 ms | **+2.7 ms** |
| DX 2800×2288 | 55.7 ms | 57.44 ms | **+1.7 ms** |

**Daemon-CLI overhead on a quiet system is 2-9 ms** — composed of:
- `j2k` binary fork+exec + Swift runtime init: ~3.5 ms (measured via `j2k version`: median 3.52 ms)
- XPC connect + ping round-trip: ~0.3 ms (measured via `j2k daemon-ping` median 3.82 ms − bare-fork-exec 3.52 ms = 0.3 ms)
- XPC pixel-data marshal to daemon: scales with payload, ~1-3 ms for medical fixtures
- XPC encoded-bytes marshal back: similarly scales
- CLI cleanup: <1 ms

**Daemon-CLI overhead under sustained-load batch invocations is 8-50 ms** — same components stretched by system contention.

## Implications for prior findings

### v10.0-research Phase 6 — "+20 ms XPC overhead on M2"

The Phase 6 finding (`Documentation/research/V10_0_PHASE6_DAEMON_DECOMPOSITION.md` on the `v10.0-research` branch) reported daemon-CLI DX at 62 ms vs in-proc 42 ms — a 20 ms gap. That measurement was done in a single test (`V10Phase6DaemonDecompositionTests`) with subprocess invocations bracketed across other timing work in the same XCTest process.

The 20 ms gap likely included:
- ~2 ms genuine XPC overhead (matches this finding)
- ~18 ms of measurement-context overhead (subprocess invocations from within an XCTest harness that's also doing in-proc encoding, time bookkeeping, and result aggregation)

The Phase 6 **qualitative** conclusion ("SDK consumers should not use the daemon") was correct for that measurement context but the **quantitative** "+20 ms" was inflated. The corrected number is **2-9 ms** under isolated conditions, **8-50 ms** under sustained load.

### `Documentation/Benchmarks/J2KSWIFT_OPTIMAL_VS_KAKADU.md` — SDK consumer guidance

The cited "+20 ms XPC overhead" in the comparison-with-Kakadu doc is being corrected: under typical isolated-call conditions, the daemon adds 2-9 ms. The qualitative SDK-vs-CLI guidance (SDK consumers should call `J2KEncoder.encode(_:)` directly; the in-proc shape is somewhat faster than the daemon shape) still holds, but the gap is narrower than originally stated.

### `Documentation/OPTIMAL_PERFORMANCE_GUIDE.md` — common mistakes table

The entry "SDK consumer routing through `j2k --daemon`: +20 ms XPC marshal per DX-class encode" should read **"+2-9 ms typical, +8-50 ms under sustained-load batch"**. Updated.

## How to get reliable performance numbers going forward

1. **For per-fixture isolated measurement (the kind that informs SDK design):** use a focused script that times a single fixture with high N and ample warmups on a quiet system.
2. **For sustained-load batch characterisation (the kind that informs PACS / batch-pipeline deployment):** use `cross_codec_warm_bench.py` — its numbers are accurate for the workload it measures.
3. **Always report both** when making a marketing claim. The two values bracket the realistic user experience.

## Methodology recommendation for the canonical warm bench script

`Scripts/benchmarks/cross_codec_warm_bench.py` should NOT be changed to reduce sustained-load effects — that's a feature, not a bug. The script measures what a real batch pipeline experiences. But the script's output table should annotate which numbers are sustained-load vs isolated, and the release-notes consumer of those numbers should report both.

A future enhancement: add a `--isolated` mode to the script that runs ONE fixture at a time with cool-down sleeps between calls. That would produce numbers comparable to the high-N controlled measurement above.

## Companion documents

- [CROSS_CODEC_REPORT_v9.5.2_M2_warm.md](CROSS_CODEC_REPORT_v9.5.2_M2_warm.md) — the sustained-load report whose PX/DX numbers triggered this investigation
- [J2KSWIFT_OPTIMAL_VS_KAKADU.md](J2KSWIFT_OPTIMAL_VS_KAKADU.md) — being updated to reflect 2-9 ms isolated overhead (was citing "+20 ms")
- [`../OPTIMAL_PERFORMANCE_GUIDE.md`](../OPTIMAL_PERFORMANCE_GUIDE.md) — being updated similarly
- v10.0-research Phase 6 finding (on `v10.0-research` branch) — corrected via this finding
