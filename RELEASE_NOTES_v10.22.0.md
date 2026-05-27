# J2KSwift v10.22.0

**Decoder format-flexibility — `J2KDecoder.decodeAnyFormat(_:)` +
`decodeFile(at:)` + public `J2KFileReader.extractCodestream(from:)`.**
Before v10.22.0, `J2KDecoder.decode(_:)` only accepted raw J2K
codestream bytes — most `.jp2` / `.jph` / `.jpx` files in the wild
are JP2-box-wrapped (the codestream lives inside a `jp2c` Contiguous
Codestream box), so consumers had to roll their own box walker or
use the read-only `J2KFileReader.read(from:)` (which returns
header-only metadata, not decoded pixels). v10.22.0 closes both gaps.

MINOR per RELEASING.md — additive only: two new `J2KDecoder`
extensions in the existing `J2KFileFormat` library + one
visibility change (`private → public`) on a helper that's been
shipping since v5.x. No signature changes elsewhere; codestream
bytes byte-identical to v10.21.0.

## Summary

The end-to-end "I have a file on disk, give me a `J2KImage`" flow used
to require:

```swift
// Before v10.22.0 — three indirection steps
let data = try Data(contentsOf: url)
// (consumer rolls their own JP2 box walker, or...)
let reader = J2KFileReader()
// (which only returns header metadata, not decoded pixels)
let image = try reader.read(from: url)  // metadata-only J2KImage
// To get actual decoded pixels, consumer extracts codestream
// themselves + calls decoder
```

After v10.22.0:

```swift
import J2KFileFormat
import J2KCodec

// One-line decode from a URL — auto-handles JP2/JPX/JPH boxes
let image = try await J2KDecoder().decodeFile(at: url)

// Or from in-memory bytes (raw codestream OR box-wrapped)
let bytes = try Data(contentsOf: url)
let image2 = try await J2KDecoder().decodeAnyFormat(bytes)

// Or extract just the codestream for downstream use (DICOM re-wrap,
// JPIP, decodeRegion, etc.):
let codestream = try J2KFileReader().extractCodestream(from: jp2Bytes)
```

## What's New — production-default

| Public API | v10.21.0 | v10.22.0 |
|---|---|---|
| `J2KDecoder.decodeAnyFormat(_:Data)` | _not present_ | **NEW** — auto-detects format (raw J2K vs JP2/JPX/JPM/JPH) and decodes (extension in `J2KFileFormat`) |
| `J2KDecoder.decodeFile(at:URL)` | _not present_ | **NEW** — reads bytes from URL + calls `decodeAnyFormat` (extension in `J2KFileFormat`) |
| `J2KFileReader.extractCodestream(from:Data)` | `private` | **`public`** — walk box hierarchy, return `jp2c` contents |
| `J2KDecoder.decode(_:Data)` | unchanged | unchanged (still raw-codestream-only — strict semantics preserved) |
| `getVersion()` | 10.21.0 | 10.22.0 |
| Every other public API | unchanged | unchanged |

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.21.0 on every input. Encoder
  + decoder hot paths unchanged.
- **Existing API contracts**: `J2KDecoder.decode(_:)` semantics
  preserved — still throws if given JP2-boxed bytes (consumers who
  rely on this for input validation continue to work). The new
  `decodeAnyFormat(_:)` is an opt-in additive surface; no consumer
  is forced into the auto-detection path.
- **`J2KFileReader.extractCodestream(from:)` visibility change**:
  the method was previously `private` and an implementation detail of
  `J2KFileReader.read(from:)`. Making it public formalises the contract
  but doesn't change behaviour. Callers that previously walked JP2 boxes
  themselves can switch to this helper without semantic difference.

## Why this is genuinely useful

Most J2K files on disk follow the JP2 box format (PS3-15441-2). The
`jp2c` Contiguous Codestream box wraps the raw codestream alongside
metadata boxes (signature, file-type, JP2 header). Before v10.22.0
the `J2KDecoder` API surface implicitly required consumers to know
which format they had and unwrap themselves — a real friction point
for "I just want to decode this file" use cases.

Also: this is the natural complement to v10.17 / v10.19 / v10.21's
DICOM-side work — both are "consumers have container-wrapped J2K
bytes; give them a one-call path to a `J2KImage`."

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_34_DecoderFormatFlexibilityTests` | 8/8 | PASS | `extractCodestream` extracts from JP2 + JPH (both start with SOC `0xFF 0x4F`); rejects raw codestream (no jp2c box); `decodeAnyFormat` accepts raw + JP2 + JPH bytes with bit-exact lossless round-trip; `decodeFile` reads + decodes from a temp file URL; missing file throws I/O error |
| `swift test --filter J2KFileFormatTests` (regression) | 365/365 | PASS | 357 pre-existing + 8 new V10_34 + 10 pre-existing skips |
| `swift test --filter JP3D` (regression) | 539/539 | PASS | 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
// In J2KFileFormat library — bring J2KDecoder convenience by importing it.
import J2KFileFormat

extension J2KDecoder {
    /// v10.22.0 — accepts raw J2K codestream OR JP2-box-wrapped bytes.
    public func decodeAnyFormat(_ data: Data) async throws -> J2KImage

    /// v10.22.0 — reads bytes from a file URL and decodes
    /// (auto-detects format).
    public func decodeFile(at url: URL) async throws -> J2KImage
}

// Previously private; now public (signature unchanged).
extension J2KFileReader {
    public func extractCodestream(from data: Data) throws -> Data
}
```

No removals. No existing signatures changed (only visibility on
`extractCodestream`).

## Recommended usage

```swift
import J2KCodec
import J2KFileFormat

let decoder = J2KDecoder()

// Decode a file (any J2K-family format)
let image = try await decoder.decodeFile(at: someURL)

// Decode bytes (any J2K-family format) — e.g., from a network response
let image2 = try await decoder.decodeAnyFormat(networkBytes)

// Strict raw-codestream-only decode (existing API, unchanged)
let image3 = try await decoder.decode(rawCodestreamBytes)

// Extract J2K codestream from JP2-wrapped bytes (re-wrap into DICOM,
// feed to decodeRegion, etc.)
let codestream = try J2KFileReader().extractCodestream(from: jp2Bytes)
```

## Known limitations

- **`decodeFile(at:)` uses `Data(contentsOf:)`** internally —
  loads the whole file into memory. Not appropriate for very large
  files (>1 GB) without explicit memory-mapped variants. For large-
  file streaming, future `IncrementalJ2KDecoder` work is the path.
- **Auto-detection costs ~50 ns** on a typical decode (read first
  12 bytes, classify). Negligible vs the decode itself but worth
  noting for ultra-tight benchmarking loops.
- **JPM (Part 6, multi-page)** files: `decodeAnyFormat` follows the
  same extraction logic as JP2 — returns the first `jp2c` Contiguous
  Codestream box. Multi-page JPM iteration is a separate arc; for now
  consumers needing all pages should iterate boxes themselves.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_34_DecoderFormatFlexibilityTests"
```

Eight tests covering extract / decodeAnyFormat / decodeFile across raw,
JP2, and JPH formats — all PASS in ~0.07 s release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.22.0"`. To use
the new convenience methods on `J2KDecoder`, add `J2KFileFormat` to the
consuming target's product list (the methods live in extensions there):

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "J2KCodec",      package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),  // for decodeFile/decodeAnyFormat
    ])
```

Consumers not adding `J2KFileFormat` are completely unaffected.

## Companion — Next release candidates

After v10.22.0 ships:

1. **`J2KEncoder.encodeFile(_:to:format:)` symmetric file-write convenience** —
   mirror what v10.22.0 does on the decode side. `J2KFileWriter.write`
   already exists but doesn't take a `J2KEncodingConfiguration` directly
   (uses the simpler `J2KConfiguration`). A `J2KEncoder` extension that
   bridges would close the symmetry.
2. **JPIP Phase 1 — `requestMetadata` response parser** (~150 LOC, 2 days):
   closes one notImplemented in the JPIP module.
3. **`IncrementalJ2KDecoder` Phase 1** (~200 LOC, 3 days): header-only
   probe; returns `nil` if pixel payload incomplete.
4. **`J2KDICOMHelpers` Phase 3.1** — uncompressed pixel extraction
   variant on `J2KDICOMFile.uncompressed`.
