# ADR-005 — British English in Documentation and Comments

**Status**: Accepted

**Date**: 2024-09-01

## Context

J2KSwift is developed by an internationally distributed team and is used by
developers across the world. Documentation and code comments must be written
in one consistent variant of English to avoid inconsistencies such as mixing
"colour" and "color", "optimisation" and "optimization", or "organised" and
"organized" within the same document.

The choice of British English versus American English has no technical
consequence, but consistency has significant impact on readability and
professionalism. A single style also simplifies automated spell-checking in CI.

## Decision

All **documentation** and **source code comments** in J2KSwift use
**British English**. Examples of affected spellings:

| British English (used) | American English (avoided) |
|------------------------|---------------------------|
| colour | color |
| colour transform | color transform |
| optimisation | optimization |
| optimise | optimize |
| organised | organized |
| recognise | recognize |
| behaviour | behavior |
| analyse | analyze |
| favour | favor |
| modelling | modeling |
| parallelisation | parallelization |
| initialisation | initialization |
| artefact | artifact |

**Exception — Swift API names**: Swift variable names, function names, type
names, and parameter labels use American English spellings (e.g. `colorSpace`,
`optimize`, `initialize`) because the Swift standard library and Apple's
frameworks use American English. Mixing British spelling into API names would
create an inconsistency with the broader Swift ecosystem.

The rule is therefore:

> *Identifiers follow American English; prose follows British English.*

CI lint checks enforce British English spelling in `.md` files.

## Consequences

### Positive

- All documentation is consistently styled, which improves readability and
  reduces the cognitive load of switching between documents.
- Automated spell-checkers can be configured with a single dictionary.
- The `ADR-005-british-english.md` file itself serves as the authoritative
  reference for the spelling convention.

### Negative / Trade-offs

- **Friction for American English speakers**: contributors who default to
  American English must remember to use British spellings in documentation.
  The CI check acts as a safety net, but it adds a small barrier.
- **API / documentation mismatch**: a function named `colorSpace` may be
  documented as "colour space", which some readers find inconsistent. This
  trade-off is accepted because API compatibility with the Swift ecosystem
  takes priority.

## See Also

- `CONTRIBUTING.md` — contribution guidelines including the language rule
- `Documentation/ARCHITECTURE.md`
