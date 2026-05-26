# J2KSwift v10.16.0

**JP3DDecoder partial-decode discoverable overloads — `decode(_:resolutionLevel:)`,
`decode(_:region:)`, `decode(_:region:resolutionLevel:)`.** Closes a
discoverability gap: the v10.18-research partial-resolution pipeline (released as
production in v10.4 / v10.5) and the v10.13.0 K+ROI composition matrix have
been available since 2026-05-20, but the canonical `JP3DDecoder` exposed
only a single `decode(_:)` entry point. Consumers had to know to:

1. Construct a `JP3DDecoderConfiguration(resolutionLevel: K)` for partial
   resolution; OR
2. Switch to `JP3DROIDecoder` for region-of-interest decoding; OR
3. Compose both for K+ROI sub-volume decode.

v10.16.0 surfaces the three options as discoverable convenience overloads
on `JP3DDecoder` itself. Same pipelines, same bit-exact output, same
measured wins; better ergonomics. MINOR per RELEASING.md — additive public
API only, no signature changes, no perf change on existing paths,
codestream bytes byte-identical to v10.15.0.

## Summary

After v10.15.0's `JP3DDecoder.preWarm` ship closed the preWarm
discoverability gap, the obvious next gap is partial-decode. The
underlying capability is mature: v10.4 + v10.5 added true partial-
resolution, v10.6 + v10.7 added ROI, v10.8 added the `decodePartial`
umbrella for the 2D codec, and v10.13.0 closed K+ROI composition for
JP3D. But the only way to reach these from `import J2K3D` was:

```swift
// Today — discoverable only by reading the docs
let cfg = JP3DDecoderConfiguration(resolutionLevel: 1)
let thumbnail = try await JP3DDecoder(configuration: cfg).decode(data)

let roi = try await JP3DROIDecoder().decode(data, region: someRegion)

let cfg2 = JP3DDecoderConfiguration(resolutionLevel: 1)
let combined = try await JP3DROIDecoder(configuration: cfg2).decode(data, region: someRegion)
```

v10.16.0:

```swift
let decoder = JP3DDecoder()
let thumbnail = try await decoder.decode(data, resolutionLevel: 1)        // 2.2-3.1× faster
let roi       = try await decoder.decode(data, region: someRegion)        // 3.4-4.1× faster (1/4 extent)
let combined  = try await decoder.decode(data, region: someRegion, resolutionLevel: 1)
```

The overloads are pure-additive thin wrappers — they construct a transient
inner decoder/ROI-decoder with the requested options and delegate. No
hot-path code changes; the same v10.18-research / v10.13.0 pipelines run
underneath.

## What's New — production-default

| Public API | v10.15.0 | v10.16.0 |
|---|---|---|
| `JP3DDecoder.decode(_:resolutionLevel:)` | _not present_ | **NEW** — partial-resolution decode (level K ⇒ output dims `ceil(D/2^K)`); 2.2-3.1× faster than full decode at K=1 (v10.18-research bench) |
| `JP3DDecoder.decode(_:region:)` | _not present_ | **NEW** — ROI decode, returns `JP3DROIDecoderResult`; 3.4-4.1× faster than full decode for 1/4-extent regions (v10.18-research) |
| `JP3DDecoder.decode(_:region:resolutionLevel:)` | _not present_ | **NEW** — K+ROI composition (downsampled sub-volume); closes the v10.13.0 matrix behind a single API |
| `JP3DDecoder.decode(_:)` | unchanged | unchanged |
| `JP3DDecoder.preWarm(includeWarmupDispatch:)` | unchanged | unchanged |
| `JP3DROIDecoder.decode(_:region:)` | unchanged | unchanged |

All three new overloads forward the actor's `configuration` (`tolerateErrors`,
`maxQualityLayers`) to the transient inner decoder, so existing
configuration semantics propagate cleanly. Negative `resolutionLevel`
values are clamped to `0`; level `0` is bit-exact equivalent to the
no-argument `decode(_:)`.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.15.0 on every input. Encoder
  unchanged.
- **Existing decode paths**: unchanged. `JP3DDecoder.decode(_:)`,
  `JP3DROIDecoder.decode(_:region:)`, the v10.4/v10.5 partial-resolution
  pipeline, the v10.6/v10.7 ROI pipeline, and the v10.13.0 K+ROI composition
  all run the exact same code as v10.15.0.
- **API surface**: additive only. No existing signatures changed. The new
  overloads are method overloads on `JP3DDecoder` and do not collide with
  the existing `decode(_:)`.
- **`getVersion()`**: bumped from the stale `10.9.2` to `10.16.0`
  (the constant had drifted across 8 releases since v10.9.2; this catches
  it up).

## Measured wins (surfaced through the new API)

The overloads expose existing pipelines — no new bench is needed. The
measured wins they surface are from the v10.18-research closure (which
shipped as the production pipeline in v10.4–v10.13):

| Workload | Full `decode(_:)` | New convenience | Pipeline source |
|---|---:|---:|---|
| Thumbnail (level 1) of small-mid JP3D | 1.0× | **2.2-3.1×** faster | v10.18-research P2 |
| ROI ~1/4 spatial extent on small JP3D | 1.0× | **3.4-4.1×** faster | v10.18-research P3 + P6 |
| K=1 + ROI 1/4 extent | 1.0× | combined (both savings stack) | v10.13.0 K+ROI matrix |

For batch full-volume workflows, no perf change versus v10.15.0 — these
overloads only fire when the user explicitly requests partial decode.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_28_JP3DDecoderPartialOverloadsParityTests` | 6/6 | PASS | All three overloads byte-identical to existing JP3DDecoderConfiguration + JP3DROIDecoder usage; no-op level (0) bit-exact to `decode(_:)`; negative level clamped; outer-configuration propagation verified |
| `swift test --filter JP3D` (full regression) | 528/528 | PASS | All 519 pre-existing JP3D tests still green + 9 new (V10_27 probe + V10_28 parity); 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
extension JP3DDecoder {
    /// v10.16.0 — partial-resolution convenience overload.
    /// At level 0, identical to `decode(_:)`. At level K > 0, output dims
    /// are `ceil(D / 2^K)` per spatial axis. Backed by the true-partial-
    /// resolution pipeline (v10.18-research): 2.2-3.1× faster than full
    /// decode for K=1 on small-mid JP3D fixtures.
    public func decode(
        _ data: Data,
        resolutionLevel level: Int
    ) async throws -> JP3DDecoderResult

    /// v10.16.0 — ROI convenience overload.
    /// Equivalent to `JP3DROIDecoder(configuration: self.configuration).decode(data, region: region)`.
    /// Tile-granular skip pipeline (v10.13.0): 3.4-4.1× faster than full
    /// decode for ~1/4-extent regions.
    public func decode(
        _ data: Data,
        region: JP3DRegion
    ) async throws -> JP3DROIDecoderResult

    /// v10.16.0 — K+ROI convenience overload.
    /// Returns the in-region sub-volume at `2^level`-down dimensions per
    /// spatial axis. Closes the v10.13.0 K+ROI composition matrix behind
    /// a single discoverable API.
    public func decode(
        _ data: Data,
        region: JP3DRegion,
        resolutionLevel level: Int
    ) async throws -> JP3DROIDecoderResult
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2K3D

let decoder = JP3DDecoder()

// Full decode — unchanged
let full = try await decoder.decode(data)

// Thumbnail at 1/2 resolution (~3x faster on small-mid fixtures)
let thumbnail = try await decoder.decode(data, resolutionLevel: 1)

// Decode just a sub-region (~4x faster for ~1/4-extent regions)
let region = JP3DRegion(x: 64..<192, y: 64..<192, z: 4..<12)
let roi = try await decoder.decode(data, region: region)

// Decode the region at 1/2 resolution (both savings stack)
let combined = try await decoder.decode(data, region: region, resolutionLevel: 1)
```

## Known limitations

- The K+ROI overload returns a `JP3DROIDecoderResult`, which differs in
  shape from `JP3DDecoderResult` (adds `decodedRegion`, `isFullVolume`,
  `tilesSkipped`). This matches the existing `JP3DROIDecoder.decode`
  return type — consumers wanting unified result handling can read
  `.volume` from either type.
- `maxQualityLayers` honoured via configuration propagation, but the
  JP3D decoder is single-layer (per v10.9.0's `decodeQuality` 2D ship
  — the JP3D encoder cannot currently produce genuine multi-layer
  per-slice codestreams). Multi-layer JP3D is a separate arc.
- On Linux (`J2KMetalSession.isAvailable == false`), the overloads
  silently use the CPU pipelines and inherit the same Linux semantics
  as their underlying decoders.

## Reproducing the parity numbers

```bash
swift test -c release --filter "V10_28_JP3DDecoderPartialOverloadsParityTests"
```

Six tests: three overload bit-exact parity tests, no-op level (0) parity,
negative-level clamp, configuration propagation.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.16.0"`. No
source changes required for consumers — the new overloads are strictly
additive. Existing code calling `JP3DDecoder().decode(data)` continues
to work unchanged; switching to the new overloads is opt-in per call site.

## Companion work — encoder preWarm probe (research-only)

The natural symmetric ship to v10.15.0 would have been
`JP3DEncoder.preWarm`. A 2-fixture cold-start probe (V10_27, on the
`v10.16-research` branch, not merged) measured the leftover encoder-
specific cold cost AFTER `JP3DDecoder.preWarm(includeWarmupDispatch: true)`:

| Fixture | Path A (cold) | Path B (after decoder preWarm) | Path C (warm median) | (B - C) |
|---|---:|---:|---:|---:|
| 128×128×16 lossless HTJ2K | 57.56 ms | 8.10 ms | 8.01 ms | **+0.10 ms** |
| 256×256×16 lossless HTJ2K | 77.18 ms | 26.89 ms | 28.14 ms | **−1.25 ms** |

Both fixtures show < 3 ms leftover — the existing decoder preWarm's
warmup-dispatch (a real synthetic 256² encode+decode) already amortises
the encoder Metal init via `J2KMetalSession.processShared`. A
dedicated encoder preWarm would be a no-op API. Per
`feedback_no_half_releases.md`, NOT shipped.
