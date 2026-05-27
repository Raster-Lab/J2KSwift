# J2KSwift v10.24.0

**`J2KDICOMHelpers` Phase 3.1 — uncompressed pixel extraction.**
v10.21.0's Phase 3 file parser returned pixel data ONLY for
J2K-tagged transfer syntaxes (`.j2kCompressed(metadata, pixelDataBytes)`);
non-J2K transfer syntaxes returned metadata-only
(`.uncompressed(metadata)`). v10.24.0 ships the sibling
`parseExtractingPixelData(_:)` method that also returns pixel data
for the uncompressed case — for consumers who'd rather get all the
bytes in one call than reach for a separate DICOM library.

MINOR per RELEASING.md — entirely additive: a new sibling type
(`J2KDICOMFileWithPixelData`) and a new parser method
(`parseExtractingPixelData(_:)`). Existing
``J2KDICOMFile`` + ``J2KDICOMFileParser/parse(_:)`` are unchanged.
Codestream bytes byte-identical to v10.23.0.

## Summary

The Phase 3.1 candidate from v10.21.0's "Known limitations" section.
Phase 3 (v10.21.0) shipped the file parser but deliberately left
uncompressed pixel extraction out — the original framing was "consumers
should use their own DICOM library for non-J2K pixel data." On further
consideration this asymmetry is awkward: consumers parsing a `.dcm`
file via `J2KDICOMFileParser.parse(_:)` get pixel bytes for J2K-tagged
files but not for uncompressed ones, so they end up shipping two
parsers (J2KSwift's + their DICOM library's) just to read both kinds
uniformly.

v10.24.0 adds a SIBLING method (not a modification of the existing
one) that returns the richer shape:

```swift
import J2KDICOMHelpers

let bytes = try Data(contentsOf: someDICOMFileURL)

// Phase 3 path (v10.21.0): metadata only for uncompressed
let viaParse = try J2KDICOMFileParser.parse(bytes)
switch viaParse {
case .j2kCompressed(let m, let pixelData):
    // pixelData present — pass to v10.19's decapsulator
case .uncompressed(let m):
    // metadata only — use your DICOM library for the pixel data
}

// Phase 3.1 path (v10.24.0): pixel data for BOTH cases
let viaExtract = try J2KDICOMFileParser.parseExtractingPixelData(bytes)
switch viaExtract {
case .j2kCompressed(let m, let pixelData):
    // pixelData = encapsulated Item sequence; same bytes as parse(_:)
case .uncompressed(let m, let pixelData):
    // pixelData = raw bytes (rows × cols × samples × bytes × frames)
    //              in SOURCE byte order; no endianness conversion
}
```

The bytes returned for `.uncompressed` are exactly what the DICOM
file's `(7FE0,0010)` element contained — raw, no endianness swap, no
mosaic / planar-config interpretation. Consumers' DICOM library /
image-construction code handles those layout concerns.

## What's New — production-default

| Public API | v10.23.0 | v10.24.0 |
|---|---|---|
| `J2KDICOMFileWithPixelData` enum | _not present_ | **NEW** — `.j2kCompressed(metadata, pixelDataBytes)` + `.uncompressed(metadata, pixelDataBytes)` with `var metadata` / `var pixelDataBytes` / `var isJ2KCompressed` accessors |
| `J2KDICOMFileParser.parseExtractingPixelData(_:Data)` | _not present_ | **NEW** — sibling to existing `parse(_:)`; returns `J2KDICOMFileWithPixelData` (richer shape) |
| `J2KDICOMFile` (v10.21.0) | unchanged | unchanged |
| `J2KDICOMFileParser.parse(_:)` (v10.21.0) | unchanged | unchanged |
| `getVersion()` | 10.23.0 | 10.24.0 |
| Every other public API | unchanged | unchanged |

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.23.0 on every input. The
  encoder + decoder hot paths are unchanged.
- **Existing parser API contract**: `J2KDICOMFileParser.parse(_:)`
  continues to return `J2KDICOMFile` with the v10.21.0 shape. Consumers
  who pattern-match on `.j2kCompressed(metadata, pixelDataBytes)` /
  `.uncompressed(metadata)` are unaffected.
- **Two different return types** is intentional: forking would have
  required adding a new case to `J2KDICOMFile` (e.g.,
  `.uncompressedWithPixelData(metadata, pixelDataBytes)`) which then
  warns on every exhaustive switch in consumer code without an
  unreachable default — disruptive without source-code changes by the
  consumer. The sibling-type approach keeps both APIs pure-additive.

## Why the truncation detection matters

`parseExtractingPixelData(_:)` validates that the file's declared Pixel
Data length is at least as large as the metadata-derived expected size
(`rows × columns × samplesPerPixel × bytesPerSample × numberOfFrames`).
A source where the Image-Pixel-Module metadata says 16×16×2 = 512
bytes but the `(7FE0,0010)` element declares only 100 bytes is malformed
— the v10.24.0 parser throws
``J2KDICOMFileError/truncatedFile(expectedAtLeast:got:)`` rather than
returning a truncated slice that would later mis-decode (mirrors the
CLI's `loadDICOM` truncation check in `J2KCLI/DICOMSupport.swift:187`).

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_36_ParseExtractingPixelDataTests` | 5/5 | PASS | J2K-tagged returns same `.j2kCompressed(metadata, pixelDataBytes)` as `parse(_:)`; uncompressed returns `.uncompressed(metadata, pixelDataBytes)` with byte-identical source recovery; multi-frame uncompressed (3 frames) returns all bytes; truncated source (declared > metadata-expected) throws `.truncatedFile`; convenience accessors work for both variants |
| `swift test --filter J2KDICOMHelpers` (regression) | 56/56 | PASS | 51 pre-existing + 5 new V10_36 |
| `swift test --filter JP3D` (regression) | 539/539 | PASS | 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
import J2KDICOMHelpers

public enum J2KDICOMFileWithPixelData: Sendable, Equatable {
    case j2kCompressed(metadata: J2KDICOMFileMetadata, pixelDataBytes: Data)
    case uncompressed(metadata: J2KDICOMFileMetadata, pixelDataBytes: Data)

    public var metadata: J2KDICOMFileMetadata { get }
    public var pixelDataBytes: Data { get }
    public var isJ2KCompressed: Bool { get }
}

public enum J2KDICOMFileParser {
    /// v10.24.0 — parse + always extract pixel data (even for
    /// non-J2K transfer syntaxes). Sibling to v10.21.0's `parse(_:)`.
    public static func parseExtractingPixelData(
        _ data: Data
    ) throws -> J2KDICOMFileWithPixelData
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2KDICOMHelpers
import J2KCodec

// Read once, branch on transfer syntax:
let bytes = try Data(contentsOf: dicomURL)
let parsed = try J2KDICOMFileParser.parseExtractingPixelData(bytes)

switch parsed {
case .j2kCompressed(let metadata, let pixelData):
    // J2K-tagged: feed to v10.19's decapsulator + decoder
    let frames = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelData)
    for codestream in frames {
        let image = try await J2KDecoder().decode(codestream)
        // …
    }

case .uncompressed(let metadata, let pixelData):
    // Uncompressed: pixelData is the raw bytes (rows × cols × samples ×
    // bytesPerSample × numberOfFrames) in source byte order. Consumer's
    // own DICOM library handles layout (planar configuration, mosaic
    // composition, photometric interpretation, etc.).
    let frameSize = metadata.frameSizeInBytes
    let frames = (0..<metadata.numberOfFrames).map { f in
        pixelData.subdata(in: (f * frameSize)..<((f + 1) * frameSize))
    }
    // … hand frames to your DICOM library / image construction code
}
```

## Known limitations

- **No endianness conversion** — uncompressed pixel bytes are returned
  in source byte order. For Big Endian transfer syntax
  (`1.2.840.10008.1.2.2`, retired but still present in legacy archives)
  with 16-bit samples, consumers must byte-swap to their target byte
  order. The metadata's `transferSyntaxUID` field carries enough info
  to decide.
- **No mosaic / planar-config handling** — the bytes are exactly what
  the `(7FE0,0010)` element contained. Multi-frame data is
  concatenated frames; planar configuration (samples interleaved vs
  planar) is preserved as-is. Consumers handle these layout concerns.
- **Compressed non-J2K transfer syntaxes** (RLE, JPEG baseline, etc.)
  return as `.uncompressed(metadata, pixelDataBytes)` even though the
  bytes are actually a non-J2K compressed payload. Consumers' DICOM
  library handles decoding via the Transfer Syntax UID. This is a
  naming compromise — there's no `.otherCompressed` case to keep the
  enum minimal.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_36_ParseExtractingPixelDataTests"
```

Five tests covering J2K-tagged parity with `parse(_:)`, uncompressed
single-frame + multi-frame extraction, truncation detection, and
convenience accessors — all PASS in ~0.06 s release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.24.0"`. No
source changes required for consumers — the new types + method are
strictly additive. Existing code using `J2KDICOMFile` +
`J2KDICOMFileParser.parse(_:)` continues to work unchanged.

## Companion — Next release candidates

After v10.24.0 ships:

1. **JPIP Phase 1 — `requestMetadata` response parser** (~150-300 LOC):
   closes one notImplemented in the JPIP module. Real JPIP work is
   2-3 weeks; a metadata-only Phase 1 could ship in 2 days.
2. **`IncrementalJ2KDecoder` Phase 1** (~200 LOC, 3 days): header-only
   probe; returns `nil` if pixel payload incomplete.
3. **Format-specific extensions to `encodeToFormat`** (v10.23.0):
   multi-layer JP2 (`jpch` codestream profile boxes), JPX extended
   brands, JPM multi-page.
