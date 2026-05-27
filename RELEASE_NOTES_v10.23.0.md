# J2KSwift v10.23.0

**Encoder format-flexibility — `J2KEncoder.encodeFile(_:to:format:)` +
`encodeToFormat(_:format:)` + public `J2KFileWriter.wrap(codestream:headerForImage:)`.**
Write-side counterpart to v10.22.0's decoder-side ship. Before
v10.23.0, consumers using `J2KEncoder` with its rich
`J2KEncodingConfiguration` (HTJ2K, multi-tile, custom quality layers,
etc.) had to write to disk through `J2KFileWriter.write` which **re-
encodes** via the simpler `J2KConfiguration` (quality + lossless
only). The rich encoding choices made via `J2KEncoder` were discarded
at write time. v10.23.0 closes the gap.

MINOR per RELEASING.md — additive only: two new `J2KEncoder`
extensions in the existing `J2KFileFormat` library + one new method
on `J2KFileWriter`. No signature changes elsewhere; codestream bytes
byte-identical to v10.22.0.

## Summary

Before v10.23.0 the encode + write story had this awkward fork:

```swift
// Path A: Rich encoding via J2KEncoder, write codestream-only via Data.write
let cfg = J2KEncodingConfiguration(
    quality: 1.0, lossless: true,
    useHTJ2K: true, htj2kBlockFormat: .conformant)
let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
try codestream.write(to: rawURL)
// → wrote a .j2k codestream file; can't wrap as .jp2 / .jph without
//   hand-rolling the box bytes

// Path B: JP2/JPH wrapping via J2KFileWriter, with simpler config
let writer = J2KFileWriter(format: .jp2)
try await writer.write(image, to: jp2URL, configuration: .lossless)
// → writes a .jp2 file, BUT re-encodes via J2KConfiguration (quality
//   + lossless only) — discards HTJ2K, tile-mode, custom-quality-layer
//   choices a consumer might have wanted to make.
```

After v10.23.0 it's one path:

```swift
import J2KCodec
import J2KFileFormat

let cfg = J2KEncodingConfiguration(
    quality: 1.0, lossless: true,
    useHTJ2K: true, htj2kBlockFormat: .conformant)
let encoder = J2KEncoder(encodingConfiguration: cfg)

// One-line encode + box-wrap + write to disk
try await encoder.encodeFile(image, to: url, format: .jph)

// Or get the bytes (e.g., for network upload, attachment, etc.)
let bytes = try await encoder.encodeToFormat(image, format: .jp2)

// Or wrap a pre-encoded codestream (no re-encode)
let codestream = try await encoder.encode(image)
let jp2Bytes = try J2KFileWriter(format: .jp2)
    .wrap(codestream: codestream, headerForImage: image)
```

Symmetric counterpart to v10.22.0's decoder ship.

## What's New — production-default

| Public API | v10.22.0 | v10.23.0 |
|---|---|---|
| `J2KEncoder.encodeToFormat(_:format:)` | _not present_ | **NEW** — encode + wrap in `.j2k`/`.jp2`/`.jph`/`.jpx`/`.jpm` bytes (extension in `J2KFileFormat`) |
| `J2KEncoder.encodeFile(_:to:format:)` | _not present_ | **NEW** — encode + wrap + write to disk (extension in `J2KFileFormat`) |
| `J2KFileWriter.wrap(codestream:headerForImage:)` | _not present_ | **NEW** — wrap a pre-encoded codestream in box format (no re-encoding) |
| `J2KFileWriter.write(_:to:configuration:)` | unchanged | unchanged (still re-encodes via `J2KConfiguration` — that's the documented behaviour) |
| `getVersion()` | 10.22.0 | 10.23.0 |
| Every other public API | unchanged | unchanged |

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.22.0 on every input. The
  encoder hot path is unchanged.
- **Existing API contracts**: `J2KFileWriter.write(_:to:configuration:)`
  semantics preserved — still re-encodes the image via the simpler
  `J2KConfiguration`. Consumers calling that method are unaffected; the
  new `wrap` method + `J2KEncoder` extensions are the opt-in additive
  paths for richer control.
- **Module placement**: the new `J2KEncoder` extensions live in the
  `J2KFileFormat` module (not `J2KCodec`) for the same reason as
  v10.22's decoder extensions — `J2KFileFormat` already depends on
  `J2KCodec`, so extensions that bridge encoder ↔ box wrappers belong
  here to avoid a J2KCodec → J2KFileFormat cycle.

## Why this matters in practice

A medical-imaging consumer (typical J2KSwift use case) wants HTJ2K
lossless encoding for diagnostic archive — that means:
- `useHTJ2K: true` (Part-15 block coding, 1.5-2× faster than EBCOT)
- `useReversibleFilter: true` (5/3 DWT, bit-exact reconstruction)
- `htj2kBlockFormat: .conformant` (interoperable with OpenJPH 0.26+)
- Often custom decomposition levels, code-block sizes, or quality
  layers depending on the modality

None of these knobs are reachable via `J2KConfiguration` (which only
exposes `quality` + `lossless`). Before v10.23.0, getting any of them
into a `.jp2` / `.jph` file required either:
1. Encoding via `J2KEncoder` then hand-rolling the box bytes, OR
2. Writing via `J2KFileWriter` and accepting whatever the re-encoded
   codestream looks like.

v10.23.0's `encodeFile(_:to:format:)` gives consumers the rich
encoder configuration AND the file-format wrapper in one call.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_35_EncoderFileFormatTests` | 11/11 | PASS | `wrap` for `.j2k` returns codestream unchanged; for `.jp2`/`.jph` prepends correct signature box; rejects invalid (zero-dim) image; wrap → extractCodestream round-trip; `encodeToFormat(.j2k)` matches `encode(_:)`; `.jp2` / `.jph` encodeToFormat round-trips bit-exact through `decodeAnyFormat`; `encodeFile` writes to temp disk + `decodeFile` reads back bit-exact; default format is `.jp2`; unwritable path throws I/O error |
| `swift test --filter J2KFileFormatTests` (regression) | 376/376 | PASS | 365 pre-existing + 11 new V10_35 + 10 pre-existing skips |
| `swift test --filter JP3D` (regression) | 539/539 | PASS | 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
// In J2KFileFormat library — import J2KFileFormat to gain these.
import J2KFileFormat

extension J2KEncoder {
    /// v10.23.0 — encode + wrap in target format's box structure.
    public func encodeToFormat(
        _ image: J2KImage,
        format: J2KFormat = .jp2
    ) async throws -> Data

    /// v10.23.0 — encode + wrap + write to disk.
    public func encodeFile(
        _ image: J2KImage,
        to url: URL,
        format: J2KFormat = .jp2
    ) async throws
}

extension J2KFileWriter {
    /// v10.23.0 — wrap a pre-encoded codestream (no re-encode).
    public func wrap(
        codestream: Data,
        headerForImage image: J2KImage
    ) throws -> Data
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2KCodec
import J2KFileFormat

// Configure encoder with rich options
var cfg = J2KEncodingConfiguration(
    quality: 1.0,
    lossless: true,
    useHTJ2K: true,
    useReversibleFilter: true,
    htj2kBlockFormat: .conformant)
cfg.bitrateMode = .constantQuality
let encoder = J2KEncoder(encodingConfiguration: cfg)

// Direct to file
try await encoder.encodeFile(image, to: outputURL, format: .jph)

// Or to bytes (e.g., upload to cloud / attach to network response)
let jp2Bytes = try await encoder.encodeToFormat(image, format: .jp2)

// Or split: encode separately, wrap separately (e.g., reuse codestream
// for multiple targets)
let codestream = try await encoder.encode(image)
let jpxBytes = try J2KFileWriter(format: .jpx)
    .wrap(codestream: codestream, headerForImage: image)
let dicomPixelData = J2KDICOMPixelDataEncapsulator
    .encapsulateFrames([codestream])
```

## Round-trip with v10.22's decoder side

```swift
import J2KCodec
import J2KFileFormat

let encoder = J2KEncoder(...)
let decoder = J2KDecoder()

// Encode + write
try await encoder.encodeFile(image, to: url, format: .jph)
// Read + decode (auto-detects JPH wrapping)
let decoded = try await decoder.decodeFile(at: url)

// For lossless HTJ2K: decoded.components[0].data == image.components[0].data (bit-exact)
```

## Known limitations

- **`encodeFile` is one-shot** — encodes + writes serially. For very
  large images where you want to overlap encode + I/O, use
  `encodeToFormat` + your own async file-write. Not a real concern for
  typical medical-image sizes (1-10 MP).
- **JPX / JPM** formats currently use the same box layout as JP2 with
  brand differences. Full Part 2 extensions (multi-layer images, ICC
  profiles, etc.) and Part 6 multi-page support are existing
  limitations of `J2KFileWriter`, not introduced by v10.23.
- **`wrap(codestream:headerForImage:)` reads only image header
  metadata** (dimensions, components, bit depth) — not pixel data. The
  codestream is the source of truth for actual content; the image
  parameter just populates the JP2 Header box's `ihdr` sub-box. Pass
  any valid `J2KImage` whose header matches the codestream's encoded
  geometry.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_35_EncoderFileFormatTests"
```

Eleven tests covering `wrap` per format + `encodeToFormat` + `encodeFile`
with round-trip via v10.22's decoder side — all PASS in ~0.07 s release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.23.0"`. To use
the new convenience methods on `J2KEncoder`, add `J2KFileFormat` to the
consuming target's product list (the methods live in extensions there;
same pattern as v10.22's decoder extensions):

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "J2KCodec",      package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),  // for encode/decodeFile
    ])
```

Consumers not adding `J2KFileFormat` are completely unaffected.

## Companion — Next release candidates

After v10.23.0 ships:

1. **JPIP Phase 1 — `requestMetadata` response parser** (~150 LOC, 2 days):
   closes one notImplemented in the JPIP module.
2. **`IncrementalJ2KDecoder` Phase 1** (~200 LOC, 3 days): header-only
   probe; returns `nil` if pixel payload incomplete.
3. **`J2KDICOMHelpers` Phase 3.1** — uncompressed pixel extraction
   variant on `J2KDICOMFile`.
4. **Format-specific extensions to `encodeToFormat`** — multi-layer JP2
   (`jpch` codestream profile boxes), JPX extended brands, JPM multi-page.
