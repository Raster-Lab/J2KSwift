# J2KSwift v10.19.0

**`J2KDICOMHelpers` Phase 2 — DICOM Pixel Data encapsulation helpers.**
Wrap J2K codestreams into DICOM Pixel Data Item bytes (PS3.5 §A.4)
and round-trip them back. Builds directly on v10.17.0's Phase 1 product
without introducing any DICOM library dependency.

MINOR per RELEASING.md — pure additive surface on the existing
`J2KDICOMHelpers` library: 2 new public enums, no signature changes
elsewhere, codestream bytes byte-identical to v10.18.0.

## Summary

v10.17.0 (Phase 1) shipped the UID-and-config bridge:
`J2KDICOMTransferSyntax` + `encodingConfiguration()` +
`J2KDICOMCodestreamDetector` + `J2KDICOMPhotometricInterpretation`.
The natural follow-on is wire-format helpers — turning a J2K codestream
into DICOM Pixel Data bytes and back. v10.19.0 ships exactly that:

```swift
import J2KDICOMHelpers
import J2KCodec

// 1. Encode an image via J2KSwift
let ts = J2KDICOMTransferSyntax.htj2kLossless
let cfg = ts.encodingConfiguration(bitDepth: 16)
let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

// 2. Wrap it as DICOM Pixel Data
let pixelDataBytes = J2KDICOMPixelDataEncapsulator
    .encapsulateFrames([codestream], includeBOT: false)

// 3. Hand pixelDataBytes off to your DICOM writer for insertion at
//    (7FE0,0010) with VR "OB" and undefined length.

// On the round-trip:
let extracted = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelDataBytes)
assert(extracted.count == 1)
assert(extracted[0] == codestream)  // bit-exact
```

For multi-frame data (e.g., a CT volume encoded as one J2K codestream
per slice), pass the frame array and optionally request a populated
Basic Offset Table:

```swift
let frames: [Data] = sliceCodestreams  // one J2K codestream per Z-slice
let pixelDataBytes = J2KDICOMPixelDataEncapsulator
    .encapsulateFrames(frames, includeBOT: true)
```

The BOT contains one little-endian u32 per frame, giving the offset
of that frame's Item header measured from the start of the FIRST
FRAME ITEM (per PS3.5 §A.4) — populated BOTs let downstream consumers
seek directly to frame N without scanning.

## What's New — production-default

| Public API | v10.18.0 | v10.19.0 |
|---|---|---|
| `J2KDICOMPixelDataEncapsulator.encapsulateItem(_:)` | _not present_ | **NEW** — wraps one J2K codestream into a single DICOM Pixel Data Item (8-byte header + payload + optional pad) |
| `J2KDICOMPixelDataEncapsulator.encapsulateFrames(_:includeBOT:)` | _not present_ | **NEW** — wraps multiple frames + (optional) BOT + Sequence Delimitation Item |
| `J2KDICOMPixelDataDecapsulator.extractFrames(_:)` | _not present_ | **NEW** — parses a DICOM Pixel Data sequence back into one `Data` per frame; strips trailing pad bytes |
| `J2KDICOMPixelDataError` | _not present_ | **NEW** — `Sendable, Equatable` error type for decapsulator failures (truncated, itemTagExpected, itemLengthOverrun, malformedSequenceDelimitation) |
| `getVersion()` | 10.18.0 | 10.19.0 |
| Every other public API | unchanged | unchanged |

The new surface is in the `J2KDICOMHelpers` SwiftPM library that
v10.17.0 introduced. Consumers not importing `J2KDICOMHelpers` are
unaffected.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.18.0 on every input.
  Encoder unchanged.
- **Existing libraries**: zero behaviour change. All previously-shipped
  `J2KDICOMHelpers` types (`J2KDICOMTransferSyntax`,
  `J2KDICOMCodestreamDetector`, `J2KDICOMPhotometricInterpretation`)
  unchanged. JP3D / J2KCodec / J2KCore unchanged.
- **API surface**: additive only. Two new public enums + one new error
  type. No existing signatures changed.
- **ADR-004 compliant**: no DICOM library dependency added anywhere.
  The encapsulator/decapsulator codify the byte-layout rules directly
  from DICOM PS3.5 §A.4 / §6.4.

## Why this is the right Phase 2 scope

The original v10.17.0 plan called Phase 2 "DICOM file parser extraction
from `J2KCLI/DICOMSupport.swift`". On closer inspection, full file
parsing pulls in:

- Group 0002 / dataset tag walking (~150 LOC)
- All the byte-reading helpers (`dcmReadU16LE`, `dcmReadString`, etc.,
  ~50 LOC)
- Multi-frame layout + photometric interpretation handling for the
  full uncompressed pixel-data → `J2KImage` conversion (~200 LOC)
- Encapsulated pixel data parsing for the J2K-tagged case (~80 LOC)

The first three are "consumer should use their own DICOM library
anyway" — pydicom, DICOMKit, dcm4che, etc. all do the file parsing
correctly. What consumers actually need from us is the **J2K-specific
wire format** for the Pixel Data element — exactly what v10.19.0
ships. Full file parsing stays in `Sources/J2KCLI/DICOMSupport.swift`
where it's been working since v8.

This narrower Phase 2 is also immediately useful for the **write
side**: a consumer who encoded an image via `J2KSwift` and wants to
embed it in a DICOM file uses `encapsulateFrames(_:)`. That use case
didn't exist before v10.19.0; consumers had to hand-roll the byte
layout (the pattern was demonstrated in
`Tests/J2KCodecTests/J2KStrictCrossCodecValidationTests.swift:170-194`
as test scaffolding).

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_31_PixelDataEncapsulationTests` | 12/12 | PASS | encapsulateItem even+odd length, padding correctness; encapsulateFrames single+multi frame with empty and populated BOT; round-trip byte-exact single + multi frame; pad stripping; truncated/invalid input rejection; error type Equatable |
| `swift test --filter J2KDICOMHelpers` (full regression) | 38/38 | PASS | 26 V10_29 (Phase 1) + 12 V10_31 (Phase 2) |
| `swift test --filter JP3D` (full regression) | 532/532 | PASS | 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
public enum J2KDICOMPixelDataEncapsulator {
    /// Wrap one J2K codestream into a single DICOM Pixel Data Item.
    /// 8-byte header (FFFE,E000 tag + LE u32 length) + payload + optional 0x00 pad.
    public static func encapsulateItem(_ codestream: Data) -> Data

    /// Wrap multiple J2K codestreams into a DICOM Pixel Data Item sequence:
    /// BOT (optional contents) + per-frame Items + Sequence Delimitation Item.
    public static func encapsulateFrames(
        _ frames: [Data],
        includeBOT: Bool = false
    ) -> Data
}

public enum J2KDICOMPixelDataDecapsulator {
    /// Parse a DICOM Pixel Data Item sequence into per-frame J2K codestreams.
    /// Strips trailing 0x00 pad bytes when detected via EOC-then-pad pattern.
    public static func extractFrames(_ encapsulated: Data) throws -> [Data]
}

public enum J2KDICOMPixelDataError: Error, Sendable, Equatable {
    case truncated(needed: Int, got: Int)
    case itemTagExpected(offset: Int)
    case itemLengthOverrun(itemOffset: Int, declaredLength: Int)
    case malformedSequenceDelimitation(actualLength: UInt32)
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2KDICOMHelpers
import J2KCodec
import J2K3D

// === Encode-then-embed (write side) ===
let ts = J2KDICOMTransferSyntax.htj2kLossless
let cfg = ts.encodingConfiguration(bitDepth: 16)

// Single frame: 2D image
let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
let pixelData = J2KDICOMPixelDataEncapsulator.encapsulateFrames([codestream])
// → hand pixelData off to your DICOM writer for (7FE0,0010)

// Multi-frame: JP3D volume as one J2K codestream per slice
let sliceData: [Data] = try await encodeJP3DPerSlice(volume)  // your own
let multiFramePixelData = J2KDICOMPixelDataEncapsulator
    .encapsulateFrames(sliceData, includeBOT: true)

// === Extract-then-decode (read side) ===
let pixelDataBytes = readPixelDataFromDICOM(...)  // your DICOM library
let frames = try J2KDICOMPixelDataDecapsulator.extractFrames(pixelDataBytes)
for frameBytes in frames {
    let decoded = try await J2KDecoder().decode(frameBytes)
    // …
}
```

## Known limitations

- **No DICOM file parsing**: Phase 2 still doesn't parse `.dcm` files
  — that stays in `Sources/J2KCLI/DICOMSupport.swift` (or your
  consumer-side DICOM library). Phase 2's encapsulator/decapsulator
  works on the Pixel Data element's BYTES, not the surrounding
  metadata.
- **BOT endianness**: per the current DICOM Standard, BOT entries are
  little-endian u32. Some older interpretations specify big-endian;
  v10.19.0 follows the current (and dcm4che / pydicom-consistent)
  little-endian convention. If you're consuming legacy archives that
  used big-endian BOTs, the BOT contents will be wrong but the
  per-frame extraction (which scans Item-by-Item, not BOT-driven)
  still works correctly — `extractFrames(_:)` doesn't depend on BOT
  contents for correctness.
- **Pad-byte detection**: `extractFrames(_:)` strips one trailing pad
  byte from each frame ONLY when the payload's last three bytes are
  `0xFF 0xD9 0x00` (EOC + pad). This is the canonical layout for J2K
  / HTJ2K codestreams. Codestreams that don't end in EOC (truncated
  or non-standard) retain the trailing byte; this is conservative
  behaviour — strip the byte yourself if you know the source is
  intentionally pad-extended.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_31_PixelDataEncapsulationTests"
```

12 tests covering Item / Frames / BOT layout + round-trip + pad
handling + error paths — all PASS in ~0.003 s release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.19.0"`. No
source changes required for consumers — the new types are strictly
additive. Existing code using `J2KDICOMTransferSyntax`,
`J2KDICOMCodestreamDetector`, or `J2KDICOMPhotometricInterpretation`
continues to work without modification.

## Companion — Next release candidates

After v10.19.0 ships, the remaining v10.x candidates are:

1. **`J2KDICOMHelpers` Phase 3** — full DICOM file parser extraction
   (the larger scope from the original Phase 2 design — pulls in
   group 0002 parsing, dataset tag walking, photometric handling).
2. **JPIP Phase 1 response parser** — 2-3 weeks, closes the
   notImplemented-across-all-public-methods state of the JPIP module.
3. **IncrementalJ2KDecoder completion** — 2-3 weeks, closes a
   notImplemented stub at
   `Sources/J2KCodec/J2KAdvancedDecoding.swift:430`.
4. **JP3DProgressiveDecoder + JP3DMultiSpectralDecoder /
   `…Encoder` surface symmetry** — these JP3D types lack the
   `preWarm`/`progressStream` extensions shipped in v10.15/v10.18 for
   their sibling types. Modest scope.
