# J2KSwift v10.20.0

**JP3D `preWarm()` symmetric completion — discoverable from every JP3D
type.** v10.15.0 shipped `JP3DDecoder.preWarm` + `JP3DROIDecoder.preWarm`;
six sibling JP3D types (encoder, multi-spectral encoder/decoder, progressive
decoder, stream writer, transcoder) lacked the equivalent wrapper. v10.20.0
closes that gap. Pure additive surface — six 2-line static wrappers
delegating to the same underlying `J2KDecoder.preWarm` that warms the
process-wide `J2KMetalSession.processShared`.

MINOR per RELEASING.md — additive only, no signature changes elsewhere,
codestream bytes byte-identical to v10.19.0.

## Summary

Today consumers using e.g. `JP3DMultiSpectralEncoder` had to know to
import `J2KCodec` separately and call `J2KDecoder.preWarm` themselves
(or call `JP3DDecoder.preWarm` from v10.15, which warms the same
shared session but is named for the wrong primary type). v10.20.0 makes
preWarm discoverable from every JP3D actor's own API surface:

```swift
import J2K3D  // just this — no need for J2KCodec

await JP3DEncoder.preWarm(includeWarmupDispatch: true)
await JP3DMultiSpectralDecoder.preWarm(includeWarmupDispatch: true)
await JP3DMultiSpectralEncoder.preWarm(includeWarmupDispatch: true)
await JP3DProgressiveDecoder.preWarm(includeWarmupDispatch: true)
await JP3DStreamWriter.preWarm(includeWarmupDispatch: true)
await JP3DTranscoder.preWarm(includeWarmupDispatch: true)

// Subsequent first operation through ANY JP3D type runs warm.
```

All six wrappers are 2-line statics that `await
J2KDecoder.preWarm(includeWarmupDispatch:)`. The shared
`J2KMetalSession.processShared` means warming once via any wrapper
covers every subsequent JP3D operation in the process; the discoverability
is the value.

## What's New — production-default

| Public API | v10.19.0 | v10.20.0 |
|---|---|---|
| `JP3DEncoder.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — thin wrapper around `J2KDecoder.preWarm` |
| `JP3DMultiSpectralDecoder.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — same |
| `JP3DMultiSpectralEncoder.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — same |
| `JP3DProgressiveDecoder.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — same |
| `JP3DStreamWriter.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — same |
| `JP3DTranscoder.preWarm(includeWarmupDispatch:)` | _not present_ | **NEW** — same |
| `getVersion()` | 10.19.0 | 10.20.0 |
| Every other public API | unchanged | unchanged |

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.19.0 on every input.
- **Existing APIs**: zero behaviour change. `JP3DDecoder.preWarm` and
  `JP3DROIDecoder.preWarm` from v10.15.0 continue to work identically;
  the six new wrappers all delegate to the same `J2KDecoder.preWarm`
  + warm the same shared session.
- **API surface**: additive only — six new public static functions, no
  existing signatures changed.

## Why this is honest discoverability, not a perf claim

Per V10_27's v10.16-research probe, the encoder-side cold cost beyond
what `JP3DDecoder.preWarm(includeWarmupDispatch: true)` already amortises
is below the 3 ms acceptance threshold (+0.10 ms / −1.25 ms on 128×128×16
and 256×256×16 lossless HTJ2K fixtures). So calling `JP3DEncoder.preWarm()`
delivers the same cold-start savings as `JP3DDecoder.preWarm()` — the
underlying warmup is shared.

The value of v10.20.0 is **discoverability + API symmetry**: consumers
using any one of the six previously-uncovered types no longer have to
know to look at `JP3DDecoder` for the preWarm entry point. The release
notes do NOT claim new perf savings on warm paths.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_32_PreWarmSymmetricCompletionTests` | 7/7 | PASS | All 6 new wrappers callable from `import J2K3D` alone, accept `includeWarmupDispatch:` parameter, don't throw or crash; cross-type warm test verifies `JP3DEncoder.preWarm(includeWarmupDispatch: true)` + subsequent decode end-to-end |
| `swift test --filter JP3D` (full regression) | 539/539 | PASS | 532 pre-existing + 7 new V10_32 + 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
extension JP3DEncoder {
    public static func preWarm(includeWarmupDispatch: Bool = false) async
}
extension JP3DMultiSpectralDecoder {
    public static func preWarm(includeWarmupDispatch: Bool = false) async
}
extension JP3DMultiSpectralEncoder {
    public static func preWarm(includeWarmupDispatch: Bool = false) async
}
extension JP3DProgressiveDecoder {
    public static func preWarm(includeWarmupDispatch: Bool = false) async
}
extension JP3DStreamWriter {
    public static func preWarm(includeWarmupDispatch: Bool = false) async
}
extension JP3DTranscoder {
    public static func preWarm(includeWarmupDispatch: Bool = false) async
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2K3D

// In your app / SDK startup (any one preWarm call covers all subsequent
// JP3D operations through the shared J2KMetalSession.processShared):
await JP3DEncoder.preWarm(includeWarmupDispatch: true)

// Later, anywhere — first operation through ANY JP3D type runs warm:
let result = try await JP3DMultiSpectralEncoder().encode(...)
```

## Known limitations

- Calling `preWarm` on multiple JP3D types is idempotent — the shared
  session is warmed once on the first call. Subsequent calls are
  cheap (Metal init is one-shot per process) but don't add additional
  savings.
- On Linux (`J2KMetalSession.isAvailable == false`), all six wrappers
  silently no-op via the underlying `J2KDecoder.preWarm`'s
  Linux-safe fallback. JP3D operations on Linux take the CPU path
  which doesn't pay the Metal init cost in the first place.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_32_PreWarmSymmetricCompletionTests"
```

Seven tests covering surface availability per type + cross-type shared-
session verification — all PASS in ~0.1 s release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.20.0"`. No
source changes required for consumers — the new wrappers are strictly
additive. Existing code calling `JP3DDecoder.preWarm()` or
`J2KDecoder.preWarm()` continues to work unchanged.
