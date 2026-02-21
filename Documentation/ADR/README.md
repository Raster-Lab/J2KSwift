# Architecture Decision Records

This directory contains Architecture Decision Records (ADRs) for J2KSwift.

An ADR is a short document that captures an important architectural decision,
the context that led to it, and the consequences of adopting it. ADRs are
immutable once accepted — if a decision is later reversed, a new ADR is
created that supersedes the original.

## Format

Each ADR follows this structure:

```
# ADR-NNN — Title

**Status**: Proposed | Accepted | Deprecated | Superseded by ADR-NNN

**Date**: YYYY-MM-DD

## Context

What situation or problem prompted this decision?

## Decision

What was decided?

## Consequences

What are the positive and negative outcomes of this decision?
```

## ADR Index

| ADR | Title | Status |
|-----|-------|--------|
| [ADR-001](ADR-001-swift6-strict-concurrency.md) | Swift 6 Strict Concurrency | Accepted |
| [ADR-002](ADR-002-value-types-cow.md) | Value Types with Copy-on-Write Storage | Accepted |
| [ADR-003](ADR-003-modular-gpu-backends.md) | Modular GPU Backends | Accepted |
| [ADR-004](ADR-004-no-dicom-dependency.md) | No DICOM Library Dependencies | Accepted |
| [ADR-005](ADR-005-british-english.md) | British English in Documentation and Comments | Accepted |

## Creating a New ADR

1. Pick the next sequential number.
2. Create a file named `ADR-NNN-short-descriptive-title.md`.
3. Fill in all sections; set status to `Proposed`.
4. Open a pull request; the status changes to `Accepted` after review.

## See Also

- `Documentation/ARCHITECTURE.md` — full architecture overview
- `CONTRIBUTING.md` — contribution guidelines
