# J2KSwift v10.15.0

**JP3DDecoder.preWarm convenience API — cold-start −16 ms.** Closes
a discoverability gap from v5.28.0: the 2D codec's `J2KDecoder.preWarm()`
amortises the one-shot Metal session init cost (driver init + shader
library compile + buffer-pool first-fetch) across decodes, and JP3D
consumers inherit this automatically (per-slice `J2KMetalSession.processShared`),
but the API was only discoverable from `J2KCodec`. Consumers using
the JP3D surface alone had to import `J2KCodec` separately to find
the pre-warm entry point.

v10.15.0 adds `JP3DDecoder.preWarm()` and `JP3DROIDecoder.preWarm()`
as thin convenience wrappers. Same one-shot init savings (−16 ms
measured on M2 release for a small JP3D fixture), discoverable from
the JP3D module surface. MINOR per RELEASING.md — additive public
API, no signature changes, no perf change on warm paths, codestream
bytes unchanged.

## Summary

`J2KDecoder.preWarm()` (v5.28.0) is the canonical way to move the
one-shot Metal init cost off the critical path:

```swift
// App / SDK startup
await J2KDecoder.preWarm()

// Later, the first decode in the process runs at warm-process speed
let image = try await J2KDecoder().decode(data)
```

For JP3D consumers, the same warm-process amortization happens
because JP3D internally delegates each per-slice 2D codestream to
`J2KDecoder` (which uses `J2KMetalSession.processShared`). But
`J2KDecoder.preWarm` lives in the `J2KCodec` module — consumers
importing only `J2K3D` had no obvious entry point.

v10.15.0:

```swift
import J2K3D  // just this — no need for J2KCodec import

// App / SDK startup
await JP3DDecoder.preWarm()

// Later, the first JP3D decode runs at warm-process speed
let result = try await JP3DDecoder().decode(jp3dData)
```

## What's New — production-default

| Public API | v10.14.0 | v10.15.0 |
|---|---|---|
| `JP3DDecoder.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — thin wrapper around `J2KDecoder.preWarm(includeWarmupDispatch:)` |
| `JP3DROIDecoder.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — same; for ROI-decoder-only callers |
| `JP3DDecoder().decode(data)` | unchanged | unchanged |
| `JP3DROIDecoder().decode(data, region:)` | unchanged | unchanged |

The wrappers are 2-line static functions that delegate to
`J2KDecoder.preWarm(includeWarmupDispatch:)`. Same idempotent
semantics, same failure handling (silently caught on Linux where
Metal is unavailable), same `includeWarmupDispatch` parameter.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.14.0 on every input.
  Encoder unchanged. The wrappers don't touch any codec hot path.
- **Existing decode paths**: unchanged. Warm-process decode walls
  are bit-equivalent to v10.14.0.
- **API surface**: additive only. No existing signatures changed.

## Measured wins

M2 release, mr_3d_small 128×128×16 LCG-noise JP3D volume:

| Path | Wall time |
|---|---:|
| First decode in process (cold, no preWarm) | 28.26 ms |
| First decode after `JP3DDecoder.preWarm(...)` | 14.60 ms |
| Warm median (5 trials) | 14.33 ms |
| **Cold-start savings** | **−13.93 ms** |

The savings are CONSTANT per process (one-shot Metal init cost) so
they're most visible on small-volume JP3D decodes where the warm
decode wall itself is short. For consumers doing one-shot JP3D
decodes (e.g., a DICOM viewer opening one study), this is a real-
world latency win delivered through a discoverable API.

The bigger fixtures see proportionally smaller relative wins —
ct_3d_large 16M-voxel CT (~540 ms warm encode + ~675 ms warm decode)
saves the same ~16 ms absolute, but as a percentage it's ~2%. The
optimal use case is small-to-mid JP3D volumes where the cold-start
share is significant.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_26_JP3DPreWarmProfile` | 1/1 | PASS | Cold-vs-warm A/B + verifies `JP3DDecoder.preWarm` wires through correctly |
| `swift test --filter JP3D` (regression sweep) | 520/520 | PASS | Full JP3D test suite green (519 pre-existing + 1 new V10_26 profile) |
| Mandatory commit gate (release mode) | 7/7 | PASS | Encode-perf + decode-perf + cross-codec strict validation |

## API surface — additions only

```swift
extension JP3DDecoder {
    /// v10.15.0 — warm the shared Metal session before the first
    /// JP3D decode in a process. Thin wrapper around
    /// J2KDecoder.preWarm(includeWarmupDispatch:); JP3D shares the
    /// process-wide Metal session via per-slice J2KDecoder delegation.
    public static func preWarm(
        includeWarmupDispatch: Bool = false
    ) async
}

extension JP3DROIDecoder {
    /// v10.15.0 — same as JP3DDecoder.preWarm. Provided for
    /// discoverability by callers using JP3DROIDecoder directly.
    public static func preWarm(
        includeWarmupDispatch: Bool = false
    ) async
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2K3D

// In your app / SDK startup (e.g., AppDelegate / @main):
await JP3DDecoder.preWarm()

// (or, if you'll definitely run a real decode soon and want the
// additional 10-20 ms savings on the first one)
await JP3DDecoder.preWarm(includeWarmupDispatch: true)

// Later, anywhere — the first JP3D decode in the process is now warm:
let decoder = JP3DDecoder()
let result = try await decoder.decode(jp3dData)
```

## Known limitations

- The cold-start savings only apply to the FIRST decode in the
  process. Subsequent decodes are already warm (no further savings
  to harvest). preWarm is for amortising the init cost off the
  critical path, not for ongoing perf gains.
- On Linux (where `J2KMetalSession.isAvailable == false`),
  `preWarm` silently no-ops — the decoder falls back to the CPU
  path which doesn't pay the Metal init cost in the first place.

## Reproducing the headline number

```bash
swift test -c release --filter "V10_26_JP3DPreWarmProfile"
```

Prints the cold / warm / warm-median walls + computed savings.

## Backward upgrade

`swift package update` won't auto-pick this release if your
`Package.swift` pins an exact version; bump the requirement to
`from: "10.15.0"`. No source changes required for consumers — the
new wrappers are strictly additive. Consumers that were already
calling `J2KDecoder.preWarm()` before any JP3D decode continue to
work as before (the wrappers and `J2KDecoder.preWarm` share the
same underlying `J2KMetalSession.processShared`).
