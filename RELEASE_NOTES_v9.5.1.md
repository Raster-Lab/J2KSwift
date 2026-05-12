# J2KSwift v9.5.1 — vImage dangling-pointer crash fix (hotfix)

**Release date:** 2026-05-12
**Base:** `release/v9.5.0` (`beaf5e1`)
**Type:** Patch hotfix per `RELEASING.md` (cherry-picked from `v10.0-research` `748b054`).

## Fixed

### Production runtime crash: `vImage_Buffer` dangling pointer in scale + resample

Two production-source paths built `vImage_Buffer` structs whose `data`
pointer came from `&localArray` (or `UnsafeMutableRawPointer(mutating:
&localArray)`). That captures a pointer valid only for the duration of
the `&` expression; once stored on the heap-resident `vImage_Buffer`
struct the pointer dangles, and `vImageScale_PlanarF` writes into
freed/wrong memory.

Affected APIs (both used for thumbnail / preview generation):
- `J2KAccelerateDeepIntegration.scale16Bit`
- `J2KVImageIntegration.resample`

**Symptom:** silent corruption (destination buffer never actually
written) and occasional crashes when the freed memory was reused by
another allocator. Reproducible with the `testScale16Bit` unit test
(4×4 → 2×2 uniform-16384 input produced identically-zero output instead
of the expected uniform-32768).

**Additionally:** `kvImageHighQualityResampling` selects a Lanczos
kernel that reads zero outside the input rectangle; for inputs smaller
than the kernel width (e.g. 4×4) the output is dominated by zero-
padded reads. `vImageScale_PlanarF` does NOT honour
`kvImageEdgeExtend`. Both functions are switched to bilinear
(`kvImageNoFlags`, 2×2 kernel, always inside the input).

**Fix:** wrap `vImageScale` calls in
`withUnsafeMutableBufferPointer { src in dst.with...{ dst in
vImageScale_PlanarF(...) } }` so the pointers are scoped to the call.

Production callers that need Lanczos-quality resampling should call
vImage directly with a sufficiently large input.

### Crash: `J2KConcurrencyTuning.ScalabilityReport.description` SIGSEGV

`String(format: "%-8s %-12s ...", "Cores", "Time (ms)", ...)` calls
passed Swift string literals through the C variadic calling convention.
`%s` expects a `CChar*` (C string); passing a Swift `String` via
`CVarArg` is undefined behaviour and SIGSEGVs at runtime under Swift 6.x.

Affected: any caller of `J2KConcurrencyBenchmark.measureScalability`
that prints / logs the returned `ScalabilityReport`. The bundled
`testScalabilityMeasurement` test was crashing the test bundle whenever
it invoked `report.description`.

**Fix:** replace the format-string column layout with Swift string
interpolation + `padding(toLength:withPad:startingAt:)` for the column
alignment. Numeric formatters (`%-.4f`, `%.2f`) still use
`String(format:)` since `CVarArg` conformance is well-defined for
numerics.

## Correctness gate (release mode)

```
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'
```

All 7/7 mandatory pre-release tests pass on the hotfix branch
(release mode, Apple M2). Codestream bytes on the default lossless HT
configuration are bit-identical to v9.5.0 — these fixes touch
preview/thumbnail and benchmark-reporting paths, not the codec core.

## Backward compatibility

- **No public API breaks.**
- **No codestream byte changes** on any default configuration.
- **`kvImageHighQualityResampling` → `kvImageNoFlags`** is a behavioural
  change for callers of `scale16Bit` / `resample` that relied on the
  Lanczos kernel. The Lanczos output was already incorrect on small
  inputs due to zero-padded edge reads; the new bilinear output is
  correct on every input size. Callers needing Lanczos quality on
  large inputs should call vImage directly with explicit
  `kvImageEdgeExtend` handling.

## Files changed

```
Sources/J2KAccelerate/J2KVImageIntegration.swift
Sources/J2KCore/J2KConcurrencyTuning.swift
Sources/J2KCore/J2KCore.swift                              (version → 9.5.1)
Tests/J2KCodecTests/J2KEncoderPipelineTests.swift          (regression cover)
RELEASE_NOTES_v9.5.1.md                                    (this doc)
```

## Reproducing

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product j2k --product j2kd
.build/release/j2k version
# Expect: J2KSwift version 9.5.1
```

## Acknowledgements

The vImage dangling-pointer bug was discovered while running v9.9
research tests on the `v10.0-research` branch. Cherry-picked back to
`release/v9.5.0` per the `RELEASING.md` hotfix flow.
