# v6.4.0 G1.0 — multi-tile encode parallelism audit

**Status**: Audit + measurement only. No production code change.

**Branch**: `feature/v6.4.0-multi-tile-encode-parallelism-design`

**Anchors**:
- [`docs/V6_4_0_PLAN.md`](V6_4_0_PLAN.md) §G — Multi-tile encode parallelism (HIGH-CONFIDENCE WIN)
- [`MEDICAL_BENCHMARK_V6.md`](../MEDICAL_BENCHMARK_V6.md) §"v6-alpha3 step 9" claim that parallelism was restored (audit confirms)

---

## Why this exists

The v6.4.0 plan ([#328](https://github.com/Raster-Lab/J2KSwift/pull/328)) §G proposed re-adding per-tile parallelism to `encodeNativeMultiTile`, citing `MEDICAL_BENCHMARK_V6.md`'s claim that the native multi-tile encoder was single-threaded across tiles. The audit revealed the doc claim was **stale** — v6-alpha3 step 9 (already in main) restored per-tile parallelism via `withThrowingTaskGroup`. G1.0 measures whether the existing parallelism is delivering wins, identifies bottlenecks, and pivots the G1 trajectory accordingly.

---

## Audit — `encodeNativeMultiTile` is already parallel

[`Sources/J2KCodec/J2KEncoderPipeline.swift:555-586`](../Sources/J2KCodec/J2KEncoderPipeline.swift#L555-L586) (the encodeNativeMultiTile function body):

```swift
let unordered = try await withThrowingTaskGroup(
    of: (Int, NativeTilePartial).self
) { group in
    for k in 0..<layout.tileCount {
        let r = layoutRef.rect(forTile: k)
        group.addTask {
            let subImage = try J2KTileImageSlicer.sliceTile(
                from: imageRef, layout: layoutRef, tileIndex: k)
            ...
            return (k, NativeTilePartial(...))
        }
    }
    var collected: [(Int, NativeTilePartial)] = []
    for try await result in group {
        collected.append(result)
    }
    return collected
}
```

The inline comment confirms: *"v6-alpha3 step 9: restored the per-tile parallelism that the v5.39 M4 wrap-and-stitch path had. Step 5 introduced the native assembler with a sequential loop ('correctness first'); the step-8 measurement showed multi-tile encode was therefore single-threaded across tiles and SLOWER than v5.38 single-tile encode. Step 9 uses `withThrowingTaskGroup` to dispatch all tile encodes concurrently."*

The dispatch is **unbounded** — for an N-tile layout, all N tasks spawn concurrently. There's no `maxInFlightTilesEncode` cap analogous to `maxInFlightTilesGPU = 8` on the decode side.

---

## Measurement — release-mode A/B baseline

`HTMultiTilePerfProbeTests.testMultiTilePerfProbeOnLargeFixtures`, Apple M2, release mode, median of 5:

### Wall-time per fixture × tile mode (ms)

| Modality | Shape | single | 2x2 | 4x4 | strips4 |
|---|---|---:|---:|---:|---:|
| MR | 886×886 | 5.17 | **2.63** (+49%) | 4.01 (+22%) | 3.12 (+40%) |
| XA | 1024×1024 | 13.28 | 7.75 (+42%) | 8.59 (+35%) | **7.67** (+42%) |
| PX | 2459×1316 | 36.10 | 28.75 (+20%) | **25.40** (+30%) | 25.57 (+29%) |
| **DX** | **2800×2288** | **56.57** | 54.76 (+3%) | **52.00 (+8%)** | 54.32 (+4%) |

**MR/XA/PX show clear multi-tile wins** — best modes deliver +30-49 % vs single-tile. **DX is the underperformer** at only +8 % best mode. This matches the v5.39 M4 measured numbers for MR/XA/PX (+28-49 %) but is materially below the v5.39 measured DX +30 %.

### Per-tile load balance (DX 2x2, median run)

| Tile | Pixels | Bytes | Encode ms |
|---:|---:|---:|---:|
| 0 | 1,601,600 | 3,056,261 | **39.00** |
| 1 | 1,601,600 | 3,363,932 | **49.20** |
| 2 | 1,601,600 | 3,001,077 | **51.48** |
| 3 | 1,601,600 | 3,268,243 | **40.82** |

Tile times span 39–51 ms (32 % spread); the largest-tile wall + serial stitch lands the wall at 54.76 ms. **Theoretical-perfect parallel wall** = max-tile = 51.48 ms. Actual = 54.76 ms ⇒ ~6 % parallelism overhead. **Theoretical maximum win for DX 2x2** = single-tile (56.57) − max-tile (51.48) = 5.09 ms = **+9 %**, which closely matches the measured +3 %. The bottleneck is content-dependent encode time imbalance, not parallelism dispatch overhead.

### PX 2x2 load balance for contrast

| Tile | Encode ms |
|---:|---:|
| 0 | 25.91 |
| 1 | 23.49 |
| 2 | 20.74 |
| 3 | 19.60 |

PX tiles are more balanced (max 25.91 vs min 19.60 = 32 % spread but smaller absolute gap). Single = 36.10, max-tile = 25.91, theoretical = +28 %, actual = +20 %. PX captures most of the available parallelism.

---

## What v6-alpha3 step 9 already delivers vs the v6.4.0 G plan estimates

The plan's projection (G1.1):

| Modality | Plan projection | Actual measured (post-v6-alpha3) | Status |
|---|---:|---:|---|
| XA | 11.5 → ~8.3 ms (+28%) | 13.28 → 7.67 ms (+42%) | **already exceeds plan** |
| PX | 31.0 → ~20 ms (+35%) | 36.10 → 25.40 ms (+30%) | **already meets plan** |
| **DX** | **57.7 → ~40 ms (+30%)** | **56.57 → 52.00 ms (+8%)** | **MISSES plan by ~22 percentage points** |

**MR/XA/PX wins are already shipping** — they just aren't routed through the production-default encode path. `J2KEncoder.encode(_:)` only routes to multi-tile when `J2K_HT_TILE_MODE` env var is set; the `auto` planner is gated to fire only on XA-shape fixtures (per v6-alpha2 §"Production default stays single").

---

## Where the v6.4.0 G plan was wrong

The G plan assumed:
1. ❌ Per-tile parallelism needed re-adding → **incorrect; it's been there since v6-alpha3 step 9**
2. ❌ The XA/PX/DX wins were waiting on parallelism → **partially correct: MR/XA/PX wins are real but unrouted; DX win is significantly smaller than projected**
3. ✅ Production-default `auto` should consider promoting → **still correct and actionable**

The plan's projection numbers came from the v5.39 M4 era which used a different (now-removed) wrap-and-stitch path. The v6-alpha3 native multi-tile path's parallel performance differs from the historical wrap-and-stitch numbers, especially on DX where tile-encode-time imbalance dominates.

---

## G1 trajectory pivot

### G1.1 (was: "implement parallelism") → "DX multi-tile underperformance + content-balance investigation"

The remaining gap on DX is content-balance-driven, not parallelism-dispatch-driven:
- DX 2x2 tile times span 39–51 ms (12 ms spread)
- The slowest tile (51 ms) dominates the wall
- Even theoretically perfect dispatch would only deliver max-tile = 51 ms ≈ +9 % vs single
- 4x4 fares better at +8 % because more tiles smooth the imbalance, but the per-tile setup cost rises

**G1.1 candidate work**:
1. **Bounded concurrency** — DX 4x4 spawns 16 unbounded tasks; introduces nested oversubscription against the codeblock-level inner parallelism. Cap at `maxInFlightTilesEncode = 8` (mirror `maxInFlightTilesGPU`); measure A/B.
2. **Tile size-targeted balancing** — large fixtures with content-imbalance tiles (DX) might benefit from smaller tile sizes that spread work more evenly. Re-run the sweep with .tiles8x8 / .tiles16x16 modes (would need new `J2KHTTileMode` cases).
3. **Per-stage profiling within multi-tile** — `J2KEncodeTimings` snapshots are summed across concurrent tiles. Add a per-tile breakdown to identify which stage owns the imbalance.

### G1.2 (was: "production default decision") → unchanged

Re-evaluate whether `auto` planner should promote multi-tile by default. With the data above:
- MR/XA/PX would gain +30-49 % encode wall — significant Kakadu-gap closure
- DX gains +8 % which is small but positive
- But the v6-alpha2 finding "auto-promotion regresses PX (42 ms multi vs 37 ms single)" predates v6-alpha3 step 9; **needs re-measurement** post-step-9 to confirm.

### G1.3 (NEW) — GPU forward DWT in multi-tile path

The current multi-tile path uses CPU forward DWT per-tile. Single-tile DX uses GPU forward DWT (since v6.1.0 / v6.3.0 E2). Plumbing GPU forward DWT into `runEncodeStagesForNativeAssembly` could give DX multi-tile a further boost — currently it's CPU + parallelism only.

**Risk**: medium. The per-tile GPU dispatches add overhead; the v6-alpha5 phase 5 measurement showed multi-tile GPU forward regressed at fine tile sizes due to dispatch cost. Per-tile threshold gating (≥3 MP per tile) would be needed.

---

## Test infrastructure

The diagnostic data lives in `HTMultiTilePerfProbeTests.testMultiTilePerfProbeOnLargeFixtures`. It's been in the codebase since v5.39 M4; the test header still cites the wrap-and-stitch path's cross-decode regression (now resolved by the v6-alpha3 native assembler). The test runs in 2.5 s release mode and is the canonical multi-tile encode A/B baseline going forward.

`MEDICAL_BENCHMARK_V6.md` should be updated to remove the "multi-tile encode is single-threaded" claim — that's the **stale documentation** the v6.4.0 plan was based on.

---

## What G1.0 ships

This PR is **investigation only** — no production code change. The deliverable is this document plus the empirical baseline captured in `HTMultiTilePerfProbeTests`. The data is the input to G1.1's tuning decision.

---

## Decision gate before G1.1 lands

Confirm one of:

- **"Go by your recommendation"** — start G1.1 with **bounded concurrency** (lowest risk; mirrors decode `maxInFlightTilesGPU = 8` cap; quick to test). If the cap improves DX, ship + G1.2 production-default. If it doesn't, pivot to G1.3 (GPU forward DWT in multi-tile path).
- **Skip G1.1 tuning** — go straight to G1.2 (production-default auto-promotion) and accept DX's +8 % as the floor; ship MR/XA/PX wins. The Kakadu DX gap remains 2.75× but PX/XA/MR close materially.
- **Pivot to G1.3** — GPU forward DWT in multi-tile path. Higher risk; could give DX bigger wins by combining v6.1.0 GPU DWT with multi-tile parallelism.

The audit's bigger finding is that **v6-alpha3 step 9's parallelism is already shipping the headline wins**; v6.4.0 G's main contribution is now **production-default routing** (G1.2) and **DX-specific tuning** (G1.1 / G1.3) rather than parallelism implementation.
