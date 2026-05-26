# J2KSwift v10.18.0

**JP3D AsyncSequence progress reporting — `progressStream()` extensions on
`JP3DDecoder` / `JP3DROIDecoder` / `JP3DEncoder` / `JP3DStreamWriter`.**
Modern Swift concurrency progress API alongside the existing
`setProgressCallback(_:)` closure surface (which remains supported).
Closes the deferred Phase 3 from v10.17.0's plan with a focused MINOR
scope so the AsyncStream lifecycle is implemented cleanly.

MINOR per RELEASING.md — pure additive surface: 4 new public extensions,
zero existing API change, codestream bytes byte-identical to v10.17.0,
no perf change on warm or cold paths.

## Summary

Consumers using Swift's structured-concurrency `for await ... in stream`
pattern previously had to wrap `setProgressCallback(_:)` themselves in
an `AsyncStream.makeStream(of:)` adapter. v10.18.0 ships that adapter
inside the JP3D module so it composes cleanly with the existing
async-await encode/decode methods:

```swift
import J2K3D

let decoder = JP3DDecoder()
let progressStream = await decoder.progressStream()

// Spawn a child task to drive progress UI updates:
async let progressDisplay: Void = {
    for await progress in progressStream {
        print("\(progress.stage): \(Int(progress.overallProgress * 100))%")
    }
}()

// Decode produces progress events that flow through the stream:
let result = try await decoder.decode(data)
_ = await progressDisplay  // join the progress task
```

The relay closure is installed on the actor BEFORE `progressStream()`
returns (the method is `async`), so there's no race window where early
progress events get missed.

## What's New — production-default

| Public API | v10.17.0 | v10.18.0 |
|---|---|---|
| `JP3DDecoder.progressStream()` | _not present_ | **NEW** — `async`, returns `AsyncStream<JP3DDecoderProgress>` |
| `JP3DROIDecoder.progressStream()` | _not present_ | **NEW** — `async`, returns `AsyncStream<JP3DDecoderProgress>` (surface available; upstream decoder body doesn't currently fire progress events — see Known limitations) |
| `JP3DEncoder.progressStream()` | _not present_ | **NEW** — `async`, returns `AsyncStream<JP3DEncoderProgress>` |
| `JP3DStreamWriter.progressStream()` | _not present_ | **NEW** — `async`, returns `AsyncStream<JP3DStreamProgress>` |
| `setProgressCallback(_:)` on all of the above | unchanged | unchanged |
| `getVersion()` | 10.17.0 | 10.18.0 |
| Every other public API | unchanged | unchanged |

The new extensions install their stream-relay closure as the actor's
progress callback. If a prior `setProgressCallback(_:)` closure was
registered, `progressStream()` overwrites it. Calling `progressStream()`
a second time also overwrites the first stream's writer; the first
stream's continuation receives no further events but isn't explicitly
finished (subsequent `yield` calls are no-ops on a finished continuation).

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.17.0 on every input.
  Encoder unchanged.
- **Existing libraries**: zero behaviour change. The four `setProgressCallback`
  methods continue to work exactly as before — consumers using closures
  are unaffected.
- **API surface**: additive only. Four new extension methods, no
  existing signatures changed.

## Why this is a focused MINOR

v10.17.0's original plan included AsyncSequence progress streams as
"Phase 3". They were cut from that release per scope discipline
because the AsyncStream-vs-actor-stored-callback lifecycle had
correctness questions that warranted dedicated attention:

1. **Setup race**: if `progressStream()` were synchronous and the
   callback installation deferred to a `Task`, the consumer could
   start iterating before the relay was installed and early progress
   events would be missed. v10.18.0's `async` method installs the
   closure on the actor before returning the stream — race-free.

2. **Termination cleanup**: when the consumer stops iterating (loop
   ends, task cancellation), `AsyncStream.Continuation.yield(_:)` on
   a finished continuation is a no-op. The actor's stored closure
   remains but its yields are silently dropped. The next call to
   `progressStream()` or `setProgressCallback(_:)` overwrites the
   closure. This is documented in the extension header.

3. **Concurrent streams**: a second `progressStream()` call overwrites
   the first stream's writer; the first stream's continuation isn't
   explicitly finished but stops receiving events. Documented.

These properties are now codified in V10_30 parity tests.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_30_ProgressStreamParityTests` | 4/4 | PASS | JP3DDecoder + JP3DEncoder both deliver progress events during real operations; JP3DROIDecoder stream surface is available + safe (upstream body doesn't currently fire events — documented); setProgressCallback overwriting progressStream's relay still fires |
| `swift test --filter JP3D` (full regression) | 532/532 | PASS | 528 pre-existing + 4 new V10_30 + 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
extension JP3DDecoder {
    /// v10.18.0 — modern AsyncSequence progress reporting.
    public func progressStream() async -> AsyncStream<JP3DDecoderProgress>
}

extension JP3DROIDecoder {
    /// v10.18.0 — modern AsyncSequence progress reporting.
    public func progressStream() async -> AsyncStream<JP3DDecoderProgress>
}

extension JP3DEncoder {
    /// v10.18.0 — modern AsyncSequence progress reporting.
    public func progressStream() async -> AsyncStream<JP3DEncoderProgress>
}

extension JP3DStreamWriter {
    /// v10.18.0 — modern AsyncSequence progress reporting.
    public func progressStream() async -> AsyncStream<JP3DStreamProgress>
}
```

No removals. No existing signatures changed. The four `setProgressCallback`
closure-based APIs continue to exist alongside.

## Recommended usage

```swift
import J2K3D

let decoder = JP3DDecoder()

// Set up the stream BEFORE the operation that fires progress.
let stream = await decoder.progressStream()

// Spawn a sibling task to drive the UI / log progress events.
async let observer: Void = {
    for await progress in stream {
        // Update UI on the main actor as needed
        await MainActor.run {
            updateProgressBar(progress.overallProgress)
        }
    }
}()

// The decode call fires progress events as it runs.
let result = try await decoder.decode(data)
_ = await observer
```

## Known limitations

- **JP3DROIDecoder progress events**: the surface
  `JP3DROIDecoder.progressStream()` is available and safe to consume,
  but the underlying decoder body does NOT currently invoke its stored
  `progressCallback` during a region decode (pre-existing upstream
  limitation at `Sources/J2K3D/JP3DROIDecoder.swift` — the storage at
  line 67 exists but no call sites fire). The V10_30 parity test
  documents this as the surface contract. When a later release wires up
  ROI-decoder progress reporting, the stream will start delivering
  events automatically — no API change needed here.

- **Stream finishing**: the `progressStream()` extension intentionally
  does NOT auto-finish the stream when the underlying operation
  completes. This keeps the extension free of operation-completion
  inspection (the decoder doesn't expose a "decode finished" event
  separate from `decode(_:)`'s return). Consumers should `break` out
  of their `for await` loop based on observed progress, or rely on
  `Task` cancellation to terminate iteration.

- **Two-stream concurrency**: calling `progressStream()` twice on the
  same actor instance overwrites the first stream's writer with the
  second's; the first stream stops receiving events but isn't
  explicitly finished. A consumer model with multiple observers should
  fan out from a single stream (`stream.share()` via a custom
  `AsyncSequence` adaptor, etc.) rather than calling `progressStream()`
  twice.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_30_ProgressStreamParityTests"
```

Four tests across JP3DDecoder + JP3DROIDecoder + JP3DEncoder + the
overwrite-by-setProgressCallback regression check — all PASS in ~0.3 s
release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.18.0"`. No
source changes required for consumers — the new `progressStream()`
methods are strictly additive. Code that uses `setProgressCallback(_:)`
continues to work without modification.

## Companion — Next release candidates

After v10.18.0 ships, the listed candidates from v10.17.0's planning
remain:
1. **J2KDICOMHelpers Phase 2** — DICOM file parser extraction from
   `J2KCLI/DICOMSupport.swift` into the helpers product; potentially
   with a DICOMKit / pydicom-via-XPC adapter as an opt-in sibling
   product.
2. **JPIP Phase 1 response parser** — 2-3 weeks, closes the
   notImplemented-across-all-public-methods state of the JPIP module.
3. **IncrementalJ2KDecoder completion** — 2-3 weeks, closes a
   notImplemented stub at
   `Sources/J2KCodec/J2KAdvancedDecoding.swift:430`.
