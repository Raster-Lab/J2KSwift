# ADR-004 — No DICOM Library Dependencies

**Status**: Accepted

**Date**: 2024-09-01

## Context

JPEG 2000 is the compression standard mandated by DICOM for lossless and lossy
medical imaging (transfer syntaxes `1.2.840.10008.1.2.4.90` through
`1.2.840.10008.1.2.4.203`). A significant portion of the project's intended
users work in medical imaging and need to integrate J2KSwift with DICOM
workflows.

Several open-source DICOM libraries exist for Swift (and for C/C++, callable
from Swift). Including one as a dependency of J2KSwift would simplify certain
integration patterns — for example, automatically reading the
`PhotometricInterpretation` tag to select the colour transform.

However, DICOM libraries carry substantial scope: tag dictionaries, network
services (DIMSE, web services), file format parsers, and specialised data
types. This scope is outside the responsibility of a JPEG 2000 codec library.

## Decision

J2KSwift **does not depend on any DICOM library**. The `Package.swift` manifest
lists no DICOM packages. The J2KSwift codebase contains no DICOM tag constants,
no DICOM file format parsing, and no DIMSE protocol code.

Instead:

- J2KSwift implements the JPEG 2000 standard cleanly and completely, exposing
  all parameters that a DICOM library needs to configure (colour transform
  selection, lossless/lossy mode, progression order, etc.) through
  `J2KConfiguration`.
- Integration patterns are documented in `Documentation/DICOM_INTEGRATION.md`,
  which shows how to use J2KSwift alongside DICOM libraries without creating a
  hard dependency.
- Transfer syntax UIDs are listed in the documentation as reference; they are
  not compiled into the library.

## Consequences

### Positive

- J2KSwift remains a focused, composable library: applications that have no
  DICOM requirements do not inherit any DICOM code or its transitive
  dependencies.
- DICOM library selection is left to the application; teams can use any DICOM
  library they choose (DCMTK via Swift, DICOMweb clients, proprietary SDKs,
  etc.).
- The library is easier to audit: there are no DICOM-specific licence terms,
  no DICOM conformance statements to maintain, and no DICOM network services
  to secure.

### Negative / Trade-offs

- **Integration is the caller's responsibility**: callers must read DICOM
  metadata themselves and translate it into `J2KConfiguration` parameters.
  `Documentation/DICOM_INTEGRATION.md` provides worked examples to minimise
  this burden.
- **Potential for misconfiguration**: if a caller does not correctly map the
  DICOM `PhotometricInterpretation` tag to the right colour transform, the
  decoded image will have incorrect colours. The documentation addresses this
  explicitly.

## See Also

- `Documentation/DICOM_INTEGRATION.md` — integration patterns and worked examples
- `Documentation/ARCHITECTURE.md`
