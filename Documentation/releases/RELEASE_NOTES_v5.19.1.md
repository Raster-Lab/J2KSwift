# J2KSwift v5.19.1 — Faster qstep search (probe + cache + early-exit)

**Release date:** 2026-05-04
**Theme:** Cut `.constantBitrateViaQstep`'s overhead from ~5× single-encode to ~4× cold / ~1×
warm via three optimizations: probe-based first-iteration refinement, optional qstep cache for
batch workflows, and early-exit on bracket-narrowing convergence.

## What v5.19.1 changes

### 1. Probe-based first-iteration refinement

The first iteration of the search loop now ALSO acts as a probe: after observing the achieved
bytes vs target, the encoder multiplicatively scales qstep by the ratio (in log space) and
restarts the binary search with a tighter bracket [refined/8, refined×8].

Empirical analysis ([V5_19_1_CALIBRATION.md](../research/V5_19_1_CALIBRATION.md)) showed the qstep ↔ bpp
relationship is content-dependent — single-static-calibration can't be accurate across all
inputs. A 1-iteration probe outperforms any fixed table.

### 2. Tighter initial bracket

Initial search range [guess/16, guess×16] (was 64×). Saves ~1 iteration on average even before
the probe refinement kicks in.

### 3. Optional `J2KQstepCache` for batch workflows

```swift
public actor J2KQstepCache {
    public func lookup(_ key: Key) -> Double?
    public func store(_ key: Key, qstep: Double)
    public func clear()
}
```

Wire one cache instance into multiple `J2KEncodingConfiguration`s for a batch run. After the
first image converges, the cache stores the converged qstep keyed by `(bitDepth,
componentCount, targetBpp)`. Subsequent encodes of similar images consult the cache — the cached
qstep replaces the calibration-table fallback as the initial guess.

For DICOMKit-style workflows encoding many similar images, warm-cache convergence drops from
4–6 iterations to **1 iteration** in the typical case.

### 4. Early-exit when bracket narrowing stalls

If `[lower, upper]` ratio falls below 1.05 AND iterations ≥ 3, the search returns the closest-
achieved iteration. Avoids wasted iterations on content where the bytes/qstep curve is nearly
flat at the target (16-bit medical content can have α as low as 0.13 — qstep changes barely
move bpp).

### 5. New diagnostic API: `encodeWithQstepStats`

```swift
public struct J2KEncodeQstepStats: Sendable {
    public let iterations: Int
    public let initialQstep: Double
    public let convergedQstep: Double
    public let achievedBpp: Double
    public let targetBpp: Double
    public let cacheHit: Bool
    public let convergedWithinTolerance: Bool
}

extension J2KEncoder {
    public func encodeWithQstepStats(_ image: J2KImage)
        async throws -> (data: Data, stats: J2KEncodeQstepStats)
}
```

Useful for batch workflows to measure cache hit rate, average iterations, etc.

## Verification — measured speedup

`Tests/J2KCodecTests/J2KQstepSearchEfficiencyTests.swift`:

| Test | Iterations |
|---|---:|
| `testColdCacheConvergesIn5OrFewerIterations` | 4 |
| `testWarmCacheConvergesIn2OrFewerIterations` (cold) | 4 |
| `testWarmCacheConvergesIn2OrFewerIterations` (warm) | **1** |
| `testStatsAreCoherent` | 3 |
| `testCacheSharingAcrossEncoders` | (cold: 3) (warm: 1) |

Pre-v5.19.1 (v5.19.0 baseline): typical cold-cache cost was 4–6 iterations. With v5.19.1:

- **Cold cache**: 3–5 iterations (probe refinement saves 1–2 vs v5.19.0)
- **Warm cache**: 1–2 iterations (cache eliminates 3–4 iterations vs v5.19.0)

For batch workflows (DICOMKit pipeline encoding a CT slice series), the practical effect is:
- First image: ~4× single-encode cost (was ~5×).
- Subsequent images: **~1× single-encode cost** (was ~5×).

## Carryover from v5.14–v5.19

All regression gates remain green. New v5.19.1 gates added:
- `testColdCacheConvergesIn5OrFewerIterations` — caps cold-cache at 5 iterations.
- `testWarmCacheConvergesIn2OrFewerIterations` — caps warm-cache at 2 iterations + asserts
  warm < cold.
- `testStatsAreCoherent` — sanity-checks the diagnostic stats output.
- `testCacheSharingAcrossEncoders` — verifies the `J2KQstepCache` actor is shared correctly.

## API additions (back-compat preserved)

- `J2KEncodingConfiguration.qstepCache: J2KQstepCache?` — new optional property, default nil.
  Preserving back-compat: existing initializer signatures default the new param to nil.
- `J2KEncoder.encodeWithQstepStats(_:)` — new method. Existing `encode(_:)` unchanged.
- `J2KQstepCache` — new public actor. Standalone, opt-in.
- `J2KEncodeQstepStats` — new public struct returned by `encodeWithQstepStats`.

No breaking changes to v5.19.0's `.constantBitrateViaQstep` mode.

## Reproducing

```bash
# Efficiency regression gate (~0.6 s):
swift test --filter J2KQstepSearchEfficiency

# Manual demo of cache speedup:
swift build -c release
# (Use Swift API; the CLI doesn't expose qstepCache yet.)
```

## Lesson

Three independent improvements compose multiplicatively. Probe refinement on its own would save
~1 iteration. Cache on its own would save ~2-3 iterations on warm. Early-exit on its own ~0.5
iterations on flat-curve content. Combined: 4–6 iterations → 1 (warm) or 3–5 (cold).

The cache hit rate is the practical multiplier for batch workflows. A medical-imaging archive
encoding 1000 CT slices at the same target bpp will see ~1 iteration per image after the first,
which closes the encode-time gap with `.constantBitrate` for that use case.
