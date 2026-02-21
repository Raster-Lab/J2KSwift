# ADR-001 — Swift 6 Strict Concurrency

**Status**: Accepted

**Date**: 2024-09-01

## Context

J2KSwift encodes and decodes images in tiles, and those tiles are independent
of one another. This makes the codec naturally parallel: a caller may wish to
encode several tiles concurrently, or run encoding and decoding pipelines
simultaneously on a multi-core CPU.

Without a formal concurrency model, ensuring thread safety requires discipline
(locks, dispatch queues, and manual `@volatile`-equivalent annotations). Such
approaches are error-prone, not composable, and do not integrate with Swift's
structured concurrency features (`async`/`await`, `TaskGroup`, `AsyncStream`).

Swift 6 introduces a strict concurrency checker that, when `-strict-concurrency=complete`
is passed to the compiler, produces an error for every potential data race.
Adopting this mode at the outset forces every type to be explicitly safe.

## Decision

J2KSwift adopts **Swift 6 strict concurrency** throughout the entire codebase:

- The `swift-tools-version` in `Package.swift` is set to `6.0`, which enables
  strict concurrency by default for all targets.
- Every public type is explicitly `Sendable` (or the synthesised `Sendable`
  conformance is verified by the compiler).
- Mutable shared state is isolated behind `actor` types; no raw `class` with
  `NSLock` or `DispatchQueue` manual locking patterns are used.
- Long-running codec operations are exposed as `async` functions and cooperate
  with `Task` cancellation.
- `@unchecked Sendable` is permitted only for private copy-on-write storage
  classes, with documented justification in `Documentation/CONCURRENCY_AUDIT.md`.

## Consequences

### Positive

- The Swift compiler statically verifies the absence of data races across the
  entire codebase at compile time.
- Callers can use `TaskGroup` and `async let` to parallelise tile processing
  without any extra synchronisation on their part.
- Actors replace ad-hoc locking patterns, making concurrency boundaries explicit
  and self-documenting.
- Integration with Swift Structured Concurrency enables automatic cancellation
  propagation and predictable resource cleanup.

### Negative / Trade-offs

- **All types must be `Sendable`**: types that wrap mutable C pointers (arena
  allocators, memory-mapped files) require `@unchecked Sendable` and careful
  manual review.
- **Actors introduce await overhead**: callers interacting with `JPIPClient`,
  `JPIPServer`, and cache actors must use `await` even for in-process calls,
  which adds minor overhead compared to direct method calls.
- **Minimum language version is Swift 6**: contributors must use a recent
  toolchain; older Xcode or Swift snapshots will not compile the project.

## See Also

- `Documentation/CONCURRENCY_AUDIT.md`
- `Documentation/ARCHITECTURE.md#concurrency-model`
