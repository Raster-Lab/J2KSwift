# ADR-002 — Value Types with Copy-on-Write Storage

**Status**: Accepted

**Date**: 2024-09-01

## Context

JPEG 2000 images can be large. A single 8K RGB image at 16 bits per channel
occupies approximately 400 MB. If `J2KImage` and its component buffers were
implemented as classes (reference types), two problems would arise:

1. **Unintentional aliasing**: callers holding a reference to an image could
   observe mutations made by the encoder or decoder, breaking the principle of
   least surprise.
2. **Thread safety**: a shared mutable reference type requires manual
   synchronisation every time it crosses a concurrency boundary, conflicting
   with the Swift 6 strict concurrency model (ADR-001).

Using structs (value types) everywhere avoids aliasing entirely — each
assignment produces an independent copy — but naïve copying of a 400 MB buffer
on every assignment is prohibitively expensive.

## Decision

J2KSwift uses **value types with copy-on-write (CoW) storage** for all large
data containers:

- `J2KImage`, `J2KComponent`, `J2KTile`, and `J2KBuffer` are Swift `struct`
  types. They conform to `Sendable` by synthesis.
- Internally, each struct holds a reference to a private storage class
  (e.g. `J2KBuffer.Storage`, `J2KImageBuffer.Storage`). The storage class
  manages a raw memory buffer.
- Before any mutation, the struct calls `isKnownUniquelyReferenced` on the
  storage object. If the reference is shared, a copy of the storage is made
  first (copy-on-write). If the reference is unique, the mutation proceeds
  in place.

This pattern means that passing a `J2KImage` to a function is O(1) — only a
pointer is copied — and a physical copy of the pixel data only occurs when a
second owner tries to mutate it.

```swift
// No physical copy — only the struct (pointer) is copied
let a = J2KImage(...)
let b = a              // O(1)

// CoW triggers here — b gets its own storage before mutation
var c = a
c.components[0] = ...  // physical copy occurs here, not at assignment
```

The storage classes are marked `@unchecked Sendable` because they manage raw
`UnsafeMutableRawBufferPointer` memory. Thread safety is guaranteed by the CoW
pattern: only one owner can mutate storage at a time (Swift enforces exclusive
access), and shared storage is immutable by construction.

## Consequences

### Positive

- `J2KImage` and friends are safe to pass across concurrency domains without
  copying pixel data unnecessarily.
- The API surface is simple and value-semantic: callers reason about images as
  values, not object graphs.
- `Sendable` conformance is synthesised automatically; no actors or locks are
  needed for the data types themselves.
- In practice, the encoder and decoder receive an image, never mutate it, and
  produce a new output — zero copies of pixel data occur in the typical case.

### Negative / Trade-offs

- The `@unchecked Sendable` storage classes require careful manual review; an
  incorrect mutation inside the storage class could cause a data race.
- The CoW pattern adds a branch (`isKnownUniquelyReferenced`) on every mutating
  operation. For micro-benchmarks that mutate in a tight loop, this branch is
  measurably present (though branch-predictable and typically negligible).
- Xcode's memory debugger shows the storage class as the allocation rather than
  the outer struct, which can be confusing when profiling.

## See Also

- `Documentation/CONCURRENCY_AUDIT.md` — lists all `@unchecked Sendable` types
- `Documentation/ARCHITECTURE.md#memory-architecture`
- `ADR-001-swift6-strict-concurrency.md`
