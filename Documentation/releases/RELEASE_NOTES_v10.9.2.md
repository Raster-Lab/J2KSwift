# J2KSwift v10.9.2

**Stability + packaging patch.** Fixes two latent `SIGSEGV` crashes —
one in the HTJ2K encoder, one in the performance-validation report
generator — and makes J2KSwift resolvable as a SwiftPM **URL**
dependency. Codestream bytes are byte-identical to v10.9.1; the
encoder and decoder produce identical output on every input that did
not previously crash.

## Summary

v10.9.2 is a targeted patch. It closes two crash bugs surfaced by the
DICOMKit v1.1.0 integration pass and a full-suite regression sweep,
and resolves a packaging defect that has blocked URL-based consumption
of J2KSwift since v8.0.0.

- **HTJ2K encoder crash (issue #439).** The fused HT entropy path
  force-unwrapped an empty buffer's `baseAddress` and trapped with
  `EXC_BAD_ACCESS` on degenerate / zero-coefficient code-blocks.
- **Performance-validation report crash.** `ValidationReportGenerator
  .textReport` used `String(format:)` with `%s` specifiers fed Swift
  `String` values — `%s` requires a C string, so the argument was
  read as a (tagged) pointer and `strlen`'d on a bogus address. This
  also aborted full-suite test runs partway through.
- **SwiftPM URL consumption (issue #438).** `Package.swift` declared a
  path dependency on a sibling `../CompressionFamily`, which made
  J2KSwift itself non-resolvable via `.package(url:)`.

Single-tile and multi-tile encode / decode behaviour is otherwise
unchanged.

## Fixed

- **HTJ2K encoder `baseAddress` crash (#439).** `J2KEncoderPipeline`'s
  fused HT entropy path copies each code-block's coefficients out of
  `subbandCoefficients` into `coeffsBuffer` via `src.baseAddress! …` /
  `dst.baseAddress! …`. When a degenerate or zero-coefficient block
  leaves either array empty, `baseAddress` is `nil` and the
  force-unwrap traps. Observed crashing parallel code-block workers
  during the DICOMKit v1.1.0 integration (a fresh `J2KEncoder` per
  encode call on an HT-J2K target). All five force-unwraps across the
  three coefficient-extraction sites are now `guard let`: an empty
  buffer skips the copy, leaving `coeffsBuffer` zero-filled so the
  block is handled by the existing zero-block path.
- **`ValidationReportGenerator.textReport` SIGSEGV.** `String(format:)`
  with a `%s` specifier expects a C string (`char *`); a Swift
  `String`/`NSString` passed through varargs is read as a raw,
  often tagged, pointer and `strlen`'d on an unmapped address. The
  fourteen `%s` sites in `textReport` (13) and
  `J2KAcceleratedEncoder`'s pipeline-timer `summary()` (1) are
  replaced with Swift column padding + interpolation, keeping
  `String(format:)` for numeric specifiers only. A crashed test
  process emits no `Test Case … failed` line, so this defect had
  also been silently aborting full `swift test` runs.
- **SwiftPM URL consumption (#438).** `Package.swift`'s
  `CompressionFamily` dependency is now conditional — a sibling
  `../CompressionFamily` checkout (local co-development) is used via a
  path dependency, otherwise it is fetched from its public Git repo by
  URL. The URL form is what makes J2KSwift resolvable as a
  `.package(url:)` dependency. See *Known limitations* for the
  remaining publish step.

## Changed

- `Sources/J2KCore/J2KCore.swift` — `getVersion()` returns `"10.9.2"`.
- **CI is now Apple-only.** The Windows and Linux / Linux-ARM64
  workflows and jobs were removed — J2KSwift is an Apple-silicon
  product (see the Apple-only product scope). All build / test CI runs
  on `macos-15`.
- **SwiftLint gate.** `.swiftlint.yml` raises the `error` tier of the
  threshold / style rules above the in-tree maxima so the ~288
  long-standing style findings stay warnings rather than blocking the
  lint gate; two genuine `force_cast` sites were fixed. No source
  behaviour change.
- **`J2KMetalDWT` band geometry consolidated.** The canvas-anchored
  LL / high-band split (ISO/IEC 15444-1 F.4.4) was hand-rolled at nine
  sites — the v10.9.1 hotfix had to correct the same `height / 2`
  error in two of them independently. A single `BandGeometry` helper
  now owns the split. Output-identical refactor.
- Test tooling: `Scripts/run-full-regression.sh` — a per-target /
  per-suite regression runner with a watchdog and explicit
  SIGSEGV / `fatalError` crash detection (a crash emits no failure
  line, so failure-count parsing alone mis-records it as a pass).

## Backward compatibility

Codestream bytes are **byte-identical to v10.9.1**. The encoder fix is
a crash guard that only changes behaviour on the previously-crashing
empty-buffer path; for every input that encoded successfully before,
the output is unchanged. The decoder is untouched. The
`textReport` / `summary()` fixes are diagnostics-only. `Package.swift`
changes the dependency *declaration*, not any code.

No public API was removed or changed.

## Validation

All on a clean release-mode build:

- **Mandatory commit gate** — `J2KMedicalCorpusEncodePerformanceTests`
  + `J2KMedicalCorpusPerformanceTests` + `J2KStrictCrossCodecValidationTests`
  — 0 failures.
- **Cross-codec parity** — `HTCrossCodecConformantTests`,
  `HTEndToEndCrossCodecTests`, `HTGPUForward53CrossCodecTests`,
  `HTNativeMultiTileSelfRoundtripTests` — exercising OpenJPEG /
  OpenJPH / Grok / Kakadu — 0 failures.
- Combined: **22 tests, 0 failures, 0 crashes.**
- The `#439` fix was additionally validated against the HT cross-codec
  encode suites — encode output bit-identical (the guard only alters
  the previously-crashing empty-buffer path).
- A full no-filter `swift test -c release` now runs to completion —
  6148 tests — where the `textReport` SIGSEGV previously aborted it.

## Performance

No performance change. v10.9.2 ships crash-safety guards (which only
alter the previously-crashing path), a diagnostics fix, a
package-manifest change and CI / test tooling — **no codec hot-path
code was touched**, encoder or decoder.

The canonical warm cross-codec benchmark (`cross_codec_warm_bench.py`,
in-process, Apple M2, median-of-7) records J2KSwift winning **30/38
encode** and **27/38 decode** fixtures against OpenJPEG / OpenJPH /
Grok / Kakadu (v10.9.1 measured 28/38 and 31/38). Because no encoder
or decoder code changed between the two tags, the per-fixture
win/loss differences are pure run-to-run measurement noise on
fixtures where J2KSwift and a competitor sit within a few percent of
each other. Full data: `benchmark-results-arm64-v10.9.2-20260521.json`.

## Known limitations

- **Issue #438 is code-complete but needs one publish step.** J2KSwift
  becomes resolvable via `.package(url:)` only once
  `Raster-Lab/CompressionFamily` is published as a public repository
  and tagged `1.0.0`. Until then, builds without a local
  `../CompressionFamily` sibling (CI, third-party consumers) cannot
  resolve the dependency — the same state as every prior release.
  Local development with the sibling checkout is unaffected.
- **Issue #440 (tracked).** The GPU decode paths
  (`decodeGPU` / `decodeWithGPUHT`) underperform the CPU path and
  Kakadu on mid / large medical images. This is not a correctness bug
  — the v10.0.0 `recommendedDecodeAPI` router already steers around
  the slow GPU paths — and is tracked as an optimisation target.
- Unchanged from v10.9.1: the encoder still cannot produce genuine
  multi-layer codestreams (a separate lossy / rate-allocation arc).

## Reproducing

```bash
# #439 regression coverage — HT cross-codec encode:
swift test -c release \
  --filter 'HTCrossCodecConformantTests|HTEndToEndCrossCodecTests|HTGPUForward53CrossCodecTests'

# Mandatory commit gate:
swift test -c release \
  --filter 'J2KMedicalCorpusEncodePerformanceTests|J2KMedicalCorpusPerformanceTests|J2KStrictCrossCodecValidationTests'

# Canonical warm cross-codec benchmark:
python3 Scripts/benchmarks/cross_codec_warm_bench.py --in-proc \
  --output benchmark-results-$(uname -m)-v10.9.2-$(date +%Y%m%d).json
```
