# J2KSwift v10.10.0

**JP3D true partial-resolution + ROI footprint-skip.** Closes the
long-standing JP3D follow-up: the resolution-level field on
`JP3DDecoderConfiguration` was wired but never consulted; the
ROI decoder was decode-then-crop. Both are now true-selective.

Decoder-only release; codestream bytes are byte-identical to v10.9.3.
Encoder unchanged. The MINOR bump reflects new functional behaviour
on existing public APIs (`JP3DDecoderConfiguration.resolutionLevel`
and `JP3DROIDecoder.decode(_:region:)`).

## Summary

Three coordinated changes inside `Sources/J2K3D/`:

1. **`JP3DDecoderConfiguration.resolutionLevel` becomes functional.**
   The field has shipped since v5.x but the decoder ignored it —
   `JP3DDecoder(configuration: JP3DDecoderConfiguration(resolutionLevel: K)).decode(data)`
   silently returned the full-resolution volume. v10.10.0 routes each
   per-slice 2D codestream inside `JP3DSliceStackCodec` through the
   2D codec's existing `decodeResolution(_:options:)` (v10.5.0); the
   returned volume's dimensions are now `⌈W / 2^K⌉ × ⌈H / 2^K⌉ × D`.
   M2 release: **2.2–3.1× faster decode at `resolutionLevel = 1`**.

2. **`JP3DROIDecoder` swaps decode-then-crop for true ROI footprint-
   skip.** The per-tile path was: decode entire intersecting tile via
   slice-stack → triple-loop crop the intersection into the ROI
   buffer. v10.10.0 passes the per-tile in-tile sub-region into
   `JP3DSliceStackCodec`, which in turn routes the per-slice 2D
   decode through `decodeRegion(_:options:)` with `.direct` strategy
   (v10.6.0 — code-blocks whose inverse-DWT cone-of-influence misses
   the region skip entropy decode entirely) and returns Float buffers
   sized exactly for the region rather than the whole tile.

3. **Z-narrow ROI skip.** `JP3DSliceStackCodec.decode` pre-scans
   slice headers (flags + length, no decode), finds the latest
   non-residual slice ≤ `zRange.lowerBound`, and starts decoding
   from there — completely skipping out-of-Z-range slices that
   precede the request. Slices in `[z_start, zRange.lowerBound)`
   decode purely to keep the Z-delta residual chain intact; their
   output is discarded. M2 release: **ROI 1/4 decode 3.4–4.1× faster
   than full decode** when combined with the per-tile XY footprint-
   skip above.

These compose at the slice-stack boundary; each cell of the
`{resolutionLevel, ROI}` matrix routes to the appropriate existing 2D
API. The combined `resolutionLevel > 0 + ROI` case throws loud rather
than silently producing wrong output (the 2D codec doesn't yet support
"footprint-skip at a downsampled resolution" — that's a separate arc).

## What's New — production-default

| Public API | v10.9.3 behaviour | v10.10.0 behaviour |
|---|---|---|
| `JP3DDecoder(configuration: cfg).decode(data)` with `cfg.resolutionLevel = K, K > 0` | Returns full-resolution volume (field ignored) | Returns volume sized `⌈W / 2^K⌉ × ⌈H / 2^K⌉ × D` |
| `JP3DROIDecoder().decode(data, region: r)` | Per intersecting tile: whole-tile decode + intersection-crop | Per intersecting tile: in-tile XY footprint-skip + Z-start non-residual scan; output assembled directly |
| `JP3DROIDecoder(configuration: cfg).decode(...)` with `cfg.resolutionLevel > 0 AND r` strict sub-volume | Silently ignored `cfg.resolutionLevel`; decoded at full resolution | Throws `J2KError.decodingError("...combining resolutionLevel > 0 with a sub-region is not yet supported...")` |

Existing `JP3DDecoder().decode(data)` with default configuration
(`resolutionLevel = 0`) routes through the same code path it always
did — both encoder and full decoder produce byte-identical output
to v10.9.3.

## What's New — opt-in

None. All changes ship default-on.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.9.3 on every input. The
  encoder is unchanged.
- **`JP3DDecoder().decode(data)`** (default config) is bit-exact
  identical to v10.9.3 on every input. Validated by
  `testResolutionLevel0IsBitExactFullDecode` and the existing
  61-test `JP3DDecoderTests` suite (all pass).
- **`JP3DROIDecoder().decode(data, region:)`** (default config) is
  bit-exact identical to v10.9.3 on every input — the output voxels
  are the same as full-decode-then-crop. Validated by
  `testROIDecodeMatchesFullDecodeCropped`,
  `testROIDecodeMatchesFullDecodeCroppedAtCorner`, and
  `testZNarrowROIBitExactWithFullCropped`.
- **Behaviour change**: previously-silent
  `JP3DROIDecoder(configuration: cfg)` with `cfg.resolutionLevel > 0`
  now throws when given a strict sub-volume region. The case never
  worked correctly pre-v10.10.0 (returned wrong dimensions); the
  throw surfaces the limitation instead of hiding it.

## Measured wins (M2 release, J2KBenchMac --jp3d --quick)

| Fixture | full ms | res-1 ms | res-1 vs full | ROI 1/4 ms | ROI 1/4 vs full |
|---|---:|---:|---:|---:|---:|
| mr_3d_small (128×128×16, 262K vox) | 18.78 | 8.45 | **2.22×** | 5.57 | **3.37×** |
| ct_3d_small (256×256×16, 1 M vox)  | 64.45 | 21.10 | **3.05×** | 15.55 | **4.14×** |
| mr_3d_mid (256×256×32, 2 M vox)    | 130.13 | 43.25 | **3.01×** | 32.84 | **3.96×** |

The `res-1` ratios (~2.2–3.1×) match the 2D v10.5.0 arc's 3-8×
thumbnail finding — JP3D's slice-stack arch means the 3D win is
exactly the 2D win applied per-slice, including the Z-delta residual
path which decodes residual + base at the same downsampled resolution.

The ROI 1/4 ratios (~3.4–4.1×) are the combined effect of the XY
footprint-skip (per-slice 2D `decodeRegion(.direct)`) and the
Z-narrow skip (start at latest non-residual ≤ `zLower`). Encoder
non-residual cadence is the upper bound on Z-narrow savings; the
default `JP3DEncoderConfiguration.zDeltaMode = .auto` produces
non-residuals frequently enough that the bench corpus shows
consistent wins.

## Test Suite Results

| Suite | Tests | Result |
|---|---:|---|
| `V10_18_TrueSelectiveParityTests` (new — v10.10.0 parity oracle) | 9 | 9/9 PASS |
| `JP3DDecoderTests` (existing — 61-test JP3D regression suite) | 61 | 61/61 PASS |
| `J2KStrictCrossCodecValidationTests` (mandatory commit gate) | 3 | 3/3 PASS |
| `J2KMedicalCorpusPerformanceTests` (mandatory commit gate) | — | exit 0 |
| `J2KMedicalCorpusEncodePerformanceTests` (mandatory commit gate) | — | exit 0 |

All 9 tests in the new parity oracle suite are bit-exact assertions
against the reference behaviour:

- `testFullDecodeLosslessRoundTripBaseline` — full encode/decode
  round-trip identity (baseline anchor for the others)
- `testROIDecodeMatchesFullDecodeCropped` — ROI output equals
  full-decode-then-crop voxels (interior region)
- `testROIDecodeMatchesFullDecodeCroppedAtCorner` — same, region
  anchored at (0, 0, 0) (off-by-one guard)
- `testResolutionLevel0IsBitExactFullDecode` — `resolutionLevel = 0`
  collapses to default `decode()` byte-identical
- `testPartialResolutionShape` — dim contract `⌈W/2⌉ × ⌈H/2⌉ × D`
  at `resolutionLevel = 1`
- `testPartialResolutionDeterministic` — two decodes at the same
  level produce byte-identical voxels
- `testPartialResolutionLevel2Shape` — higher-K validity at K=2
  (off-by-one guard on the iteration)
- `testZNarrowROIBitExactWithFullCropped` — Z-narrow ROI output
  equals full-decode-then-crop on a Z-slab that crosses a Z-delta
  residual chain
- `testCombinedResolutionLevelAndROIIsPhase5Future` — tripwire that
  asserts the combined case throws today (flips when the 2D codec
  gains the combined path)

## API surface

No additions, no removals. Two existing public APIs gain functional
behaviour:

- `JP3DDecoderConfiguration.resolutionLevel: Int` — was wired but
  ignored; now consulted.
- `JP3DROIDecoder.decode(_ data: Data, region: JP3DRegion)` — was
  decode-then-crop; now true ROI.

## Known limitations

- **Combined `resolutionLevel + ROI`** — throws loud today. The 2D
  codec doesn't yet implement "footprint-skip at a downsampled
  resolution"; that's a 2D arc, not JP3D, and would need to land
  before this combination can compose.
- **Z-narrow savings are encoder-cadence-bound** — the Z-narrow
  skip starts decoding from the latest non-residual slice
  ≤ `zRange.lowerBound`. When the encoder produces long residual
  chains (rare with default `.auto` Z-delta) the savings shrink.
- **GPU iDWT for JP3D** — `JP3DMetalDWT.swift` exists but isn't
  wired into `JP3DDecoder`. Orthogonal to v10.10.0; would be its
  own arc.

## Reproducing the headline numbers

```bash
# Build the bench CLI (release)
swift build -c release --target J2KBenchMac

# Run the JP3D --quick bench (3 fixtures, 3 runs / 1 warmup):
.build/arm64-apple-macosx/release/J2KBenchMac --jp3d --quick
```

The bench corpus (defined in `Sources/J2KBenchMac/JP3DBench.swift`,
parity with the iOS J2KBenchApp Volumes-tab corpus) writes a
canonical JSON to the repo root with schema `warm-inproc-jp3d-v1`.

## Companion documents

- `Documentation/research/V10_18_JP3D_TRUE_SELECTIVE_DECODE.md` —
  full arc writeup including phase-by-phase rationale, architecture
  diagrams, the COD-marker peek primitive, the Z-delta slice-header
  pre-scan design, and the open follow-ups.

## What did NOT ship to main

The v10.18-research branch also includes a new iOS J2K Bench "Volumes"
tab + 3-plane MPR viewer + 6 anatomical phantom volumes (Shepp-Logan
3D, brain MR, thorax CT, abdomen CT, spine MR sag, knee CT) and a
macOS `J2KBenchMac --jp3d` CLI mode for cross-silicon JP3D benchmarks.
Per the project convention (`feedback_research_no_main_merge.md`)
those bench-app changes stay on `v10.18-research` and are not part of
the main-branch release; only the codec changes ship here.
