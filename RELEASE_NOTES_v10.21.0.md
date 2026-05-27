# J2KSwift v10.21.0

**`J2KDICOMHelpers` Phase 3 — DICOM file parser.** Library consumers can
now parse `.dcm` file bytes natively in J2KSwift to extract Transfer
Syntax UID + Image Pixel Module metadata + (for J2K-tagged transfer
syntaxes) the encapsulated Pixel Data byte stream. Completes the
DICOM read-side story: combined with v10.17.0 (Phase 1 UID-and-config
bridge) + v10.19.0 (Phase 2 Pixel Data encapsulation), consumers can go
from raw `.dcm` bytes to decoded `J2KImage` without leaving J2KSwift.

MINOR per RELEASING.md — entirely additive: new public types in the
existing `J2KDICOMHelpers` library, no signature changes elsewhere,
codestream bytes byte-identical to v10.20.0, **no DICOM library
dependency added anywhere** (ADR-004 compliant).

## Summary

Before v10.21.0, consumers parsing `.dcm` files had to use their own
DICOM library (pydicom, DICOMKit, dcm4che) to extract the J2K codestream
out of the DICOM container before feeding it to `J2KDecoder` — even
though J2KSwift's CLI has had the file-parsing logic since v8 (private
to the CLI target). v10.21.0 lifts the J2K-relevant subset of that
parser into the `J2KDICOMHelpers` library product so the end-to-end
read flow is self-contained:

```swift
import J2KDICOMHelpers
import J2KCodec

let dcmBytes = try Data(contentsOf: URL(fileURLWithPath: "study.dcm"))

let file = try J2KDICOMFileParser.parse(dcmBytes)

switch file {
case .j2kCompressed(let metadata, let pixelDataBytes):
    print("\(metadata.transferSyntaxUID) — \(metadata.rows)×\(metadata.columns), \(metadata.numberOfFrames) frame(s)")
    let frames = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelDataBytes)
    for frameBytes in frames {
        let img = try await J2KDecoder().decode(frameBytes)
        // …
    }

case .uncompressed(let metadata):
    // Not a J2K-tagged DICOM — consumer's own DICOM library reads the
    // pixel data; metadata still available here.
    print("Uncompressed: \(metadata.transferSyntaxUID)")
}
```

## What's New — production-default

| Public API | v10.20.0 | v10.21.0 |
|---|---|---|
| `J2KDICOMFileParser.parse(_:)` | _not present_ | **NEW** — parses a `.dcm` file's bytes; returns `.j2kCompressed` or `.uncompressed` based on Transfer Syntax UID |
| `J2KDICOMFile` enum | _not present_ | **NEW** — discriminated union (`.j2kCompressed(metadata, pixelDataBytes)`, `.uncompressed(metadata)`) with `var metadata` + `var isJ2KCompressed` convenience accessors |
| `J2KDICOMFileMetadata` struct | _not present_ | **NEW** — image-pixel-module attributes (rows, columns, bits, photometric interpretation, etc.) + derived properties (`bytesPerSample`, `effectiveBitsStored`, `frameSizeInBytes`) |
| `J2KDICOMFileError` enum | _not present_ | **NEW** — Sendable, Equatable error type: `.invalidPreamble`, `.missingDICMMagic`, `.missingPixelDataTag`, `.truncatedFile`, `.invalidTransferSyntax`, `.sequenceParsingFailed` |
| `getVersion()` | 10.20.0 | 10.21.0 |
| Every other public API | unchanged | unchanged |

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.20.0. Encoder + decoder
  paths unchanged.
- **Existing libraries**: zero behaviour change. All previously-shipped
  `J2KDICOMHelpers` types (`J2KDICOMTransferSyntax`,
  `J2KDICOMCodestreamDetector`, `J2KDICOMPhotometricInterpretation`,
  `J2KDICOMPixelDataEncapsulator`, `J2KDICOMPixelDataDecapsulator`) and
  every JP3D / J2KCodec / J2KCore API are unchanged.
- **ADR-004 compliant**: no DICOM library dependency added anywhere.
  The file-parsing logic is pure byte inspection per DICOM PS3.5 §7
  (File Meta Information) + §6 (Data Element Structure) + PS3.3 §C.7.6.3.1
  (Image Pixel Module).

## Scope discipline — what Phase 3 deliberately does NOT include

- **Uncompressed pixel-data extraction** — `.uncompressed` carries
  metadata only. Consumers wanting to read raw pixel data should use
  their own DICOM library. Phase 3.1 / v10.22 candidate.
- **Compressed-non-J2K transfer syntaxes** (RLE, JPEG baseline, etc.)
  — these stay CLI-only; the CLI handles them via a Python helper
  (macOS-only) that's not portable into the helpers library.
- **DICOM file writing** — read-only Phase 3. Phase 4 candidate.
- **DICOM tag dictionary / IOD validation** — consumer's responsibility;
  their DICOM library covers this.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_33_FileParserPreambleTests` | 5/5 | PASS | empty / too-short / 131-byte / missing-DICM / garbage-after-DICM rejected with right typed error |
| `V10_33_FileParserUncompressedFixtureTests` | 3/3 | PASS | Iterates the 13 synthetic `.dcm` fixtures (CT/MR/DX/XA/PX/MG/CR/NM modalities); all classify as `.uncompressed` with valid metadata; derived properties (bytesPerSample, frameSizeInBytes) compute correctly |
| `V10_33_FileParserJ2KSynthesisTests` | 5/5 | PASS | End-to-end synthesis (J2KEncoder → J2KDICOMPixelDataEncapsulator → hand-built DICOM header) → parse → metadata round-trip → decapsulate → byte-identical recovery of original codestream(s). HTJ2K Lossless single + multi-frame with BOT, J2K Lossless, non-J2K UID classification, missing-Pixel-Data error |
| **`V10_33_*` total** | **13/13** | **PASS** | |
| `swift test --filter J2KDICOMHelpers` (full regression) | 51/51 | PASS | 26 V10_29 (Phase 1) + 12 V10_31 (Phase 2) + 13 V10_33 (Phase 3) |
| `swift test --filter JP3D` (regression) | 539/539 | PASS | 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
import J2KDICOMHelpers

public enum J2KDICOMFileParser {
    /// Parse a DICOM file's bytes; return Transfer Syntax UID +
    /// Image Pixel Module metadata + (for J2K-tagged files) the
    /// encapsulated Pixel Data byte stream.
    public static func parse(_ data: Data) throws -> J2KDICOMFile
}

public enum J2KDICOMFile: Sendable, Equatable {
    case j2kCompressed(metadata: J2KDICOMFileMetadata, pixelDataBytes: Data)
    case uncompressed(metadata: J2KDICOMFileMetadata)

    public var metadata: J2KDICOMFileMetadata { get }
    public var isJ2KCompressed: Bool { get }
}

public struct J2KDICOMFileMetadata: Sendable, Equatable, Hashable {
    public let transferSyntaxUID: String
    public let rows: Int
    public let columns: Int
    public let bitsAllocated: Int
    public let bitsStored: Int                // 0 ⇒ same as bitsAllocated
    public let pixelRepresentation: Int       // 0 = unsigned, 1 = signed
    public let samplesPerPixel: Int
    public let photometricInterpretation: String
    public let numberOfFrames: Int            // ≥ 1
    public let planarConfiguration: Int       // 0 = interleaved, 1 = planar

    // Derived properties
    public var effectiveBitsStored: Int { get }
    public var bytesPerSample: Int { get }
    public var frameSizeInBytes: Int { get }
}

public enum J2KDICOMFileError: Error, Sendable, Equatable {
    case invalidPreamble(size: Int)
    case missingDICMMagic(actual: String)
    case missingPixelDataTag
    case truncatedFile(expectedAtLeast: Int, got: Int)
    case invalidTransferSyntax(uid: String)
    case sequenceParsingFailed(offset: Int, reason: String)
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2KDICOMHelpers
import J2KCodec
import J2K3D

// === Single-frame J2K-tagged read ===
let bytes = try Data(contentsOf: URL(fileURLWithPath: "image.dcm"))
let file = try J2KDICOMFileParser.parse(bytes)

if case .j2kCompressed(_, let pixelData) = file {
    let codestream = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelData)[0]
    let image = try await J2KDecoder().decode(codestream)
    // → use image
}

// === Multi-frame: decode every frame ===
guard case .j2kCompressed(let meta, let pixelData) = file else { return }
let frames = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelData)
let images = try await withThrowingTaskGroup(of: J2KImage.self) { group in
    for f in frames {
        group.addTask { try await J2KDecoder().decode(f) }
    }
    var collected: [J2KImage] = []
    for try await img in group { collected.append(img) }
    return collected
}
```

## Known limitations / process debt

- **DocC docs site staleness** — the `documentation.yml` workflow was
  deleted 2026-05-27 as part of the cloud-cost reduction. The
  `gh-pages` site is currently frozen at v10.17. Restoring the workflow
  with a tag-push-only trigger (~$0.50 per release) would address it,
  but that reverses an explicit user decision. Mention here for
  visibility; no action taken in v10.21.0.
- **DICOMKit downstream verification** — the `dicomkit-downstream.yml`
  workflow was also deleted in the same reduction. v10.21.0 (like
  v10.20.0 before it) ships without an automated downstream build
  check against the DICOMKit consumer.
- **Phase 3 doesn't extract uncompressed pixel data** — for non-J2K
  transfer syntaxes, only metadata is returned. A consumer's own
  DICOM library handles pixel parsing for those cases. Phase 3.1 / v10.22
  candidate adds the uncompressed-pixel-bytes case.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_33"
```

13 tests across 3 suites (preamble + uncompressed-fixture + J2K-synthesis) —
all PASS in ~0.07 s release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.21.0"`. The
new types are strictly additive; existing code using `J2KDICOMHelpers`
types (`J2KDICOMTransferSyntax`, `J2KDICOMCodestreamDetector`,
`J2KDICOMPhotometricInterpretation`, `J2KDICOMPixelDataEncapsulator`,
`J2KDICOMPixelDataDecapsulator`) continues to work without modification.

## Companion — Next release candidates

After v10.21.0 ships:

1. **`J2KDICOMHelpers` Phase 3.1** — uncompressed pixel extraction
   (`case .uncompressed(metadata, pixelDataBytes)` variant). ~65 LOC.
2. **Decoder file/URL convenience** — `J2KDecoder.decodeFile(_ url: URL)`
   + auto-format detection (JP2 boxes vs raw codestream). ~80 LOC.
3. **JPIP Phase 1** — `requestMetadata` response parser closes one
   notImplemented in the JPIP module. ~150 LOC.
4. **`IncrementalJ2KDecoder` Phase 1** — header-only probe; returns
   nil if pixel payload incomplete. ~200 LOC.
