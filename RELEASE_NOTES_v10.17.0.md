# J2KSwift v10.17.0

**`J2KDICOMHelpers` Phase 1 — new SwiftPM product for DICOM-bridge ergonomics.**
A long-standing product-layer gap for library consumers using their own DICOM
parser (DICOMKit, pydicom-via-XPC, etc.): the consumer gets a DICOM Transfer
Syntax UID + Pixel Data bytes, then has to manually map the UID to a
`J2KEncodingConfiguration` to encode through J2KSwift. v10.17.0 ships a
public, ADR-004-compliant `J2KDICOMHelpers` library that closes that gap:

- `J2KDICOMTransferSyntax` enum — public, `CaseIterable`, mirrors all seven
  DICOM Part 5 Annex A JPEG 2000 / HTJ2K UIDs with `init?(uid:)` /
  `var uid` round-trip + `isLossless` / `isHTJ2K` / `isPart2` flags.
- `J2KDICOMTransferSyntax.encodingConfiguration(bitDepth:psnrTarget:)` —
  builds a matching `J2KEncodingConfiguration` (lossless/HTJ2K flags +
  `htj2kBlockFormat: .conformant` for DICOM interop).
- `J2KDICOMCodestreamDetector.detect(_:)` — sniffs SOC + CAP markers to
  classify a raw codestream as Part 1 vs HTJ2K (returns `.j2kLossless`
  / `.htj2kLossless` respectively when present, `nil` when not J2K).
- `J2KDICOMPhotometricInterpretation` enum mirror — `CaseIterable`, all
  seven DICOM PhotometricInterpretation values relevant to J2K-encoded
  pixel data, with bidirectional `J2KColorSpace` mapping.

MINOR per RELEASING.md — entirely additive: new product, zero touch to
existing libraries, codestream bytes byte-identical to v10.15.0, **no DICOM
library dependency anywhere in J2KSwift**.

## Summary

Per [ADR-004](Documentation/ADR/ADR-004-no-dicom-dependency.md), J2KSwift
core libraries don't depend on any DICOM library. The CLI ships a
`DICOMSupport.swift` for `.dcm` file loading (uses a Python fallback for
compressed transfer syntaxes), but the `DICOMTransferSyntax` /
`DICOMTransferSyntaxInfo` types there are CLI-private — not surfaced to
library consumers. v10.17.0 lifts the UID-bridge layer into a new public
`J2KDICOMHelpers` SwiftPM library so consumers parsing DICOM with their
own libraries can stop hand-rolling the UID-to-`J2KEncodingConfiguration`
map.

```swift
import J2KDICOMHelpers
import J2KCodec

// 1. Consumer reads a DICOM dataset with their own DICOM library and
//    extracts (Transfer Syntax UID, Pixel Data bytes).
let uid = dicomDataset.transferSyntaxUID  // e.g., "1.2.840.10008.1.2.4.201"
let pixelData = dicomDataset.pixelData

// 2. Bridge to J2KSwift via the helpers product:
guard let ts = J2KDICOMTransferSyntax(uid: uid) else {
    // Not a JPEG 2000 / HTJ2K UID — fall back to whatever non-J2K path
    return
}

// 3. For encode workflows: get a matching configuration.
let cfg = ts.encodingConfiguration(bitDepth: 16)
let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)

// 4. For detect workflows: sniff a codestream to identify the Transfer Syntax.
if let detected = J2KDICOMCodestreamDetector.detect(codestream) {
    print("Codestream classifies as: \(detected.uid)")  // e.g., "1.2.840.10008.1.2.4.201"
}
```

## What's New — production-default

| Public API | v10.16.0 | v10.17.0 |
|---|---|---|
| `J2KDICOMHelpers` SwiftPM product | _not present_ | **NEW** — separate library, opt-in import |
| `J2KDICOMTransferSyntax` enum | _not present_ | **NEW** — 7 DICOM UID cases + UID round-trip + classification flags |
| `J2KDICOMTransferSyntax.encodingConfiguration(bitDepth:psnrTarget:)` | _not present_ | **NEW** — produces a `J2KEncodingConfiguration` whose codestream matches the UID's wire format |
| `J2KDICOMCodestreamDetector.detect(_:)` | _not present_ | **NEW** — SOC + CAP sniff returns matching `J2KDICOMTransferSyntax` or nil |
| `J2KDICOMPhotometricInterpretation` enum | _not present_ | **NEW** — 7 DICOM photometric values + bidirectional `J2KColorSpace` mapping |
| `getVersion()` constant | 10.16.0 | 10.17.0 |
| Every other public API | unchanged | unchanged |

Existing libraries are not modified. The new product depends only on
`J2KCore` + `J2KCodec` (transitively `J2KMetal` for Metal support) — no
new external dependencies introduced.

## Backward compatibility

- **Codestream bytes**: byte-identical to v10.16.0 on every input. Encoder
  unchanged.
- **Existing libraries**: zero behaviour change. J2KCore, J2KCodec,
  J2K3D, J2KROI, JPIP, etc. are bit-equivalent to v10.16.0.
- **API surface**: additive only — new product `J2KDICOMHelpers` ships
  alongside the existing 9. Consumers not importing `J2KDICOMHelpers`
  are unaffected.
- **ADR-004 compliant**: no DICOM library dependency added anywhere.
  The new helpers product depends only on `J2KCore` + `J2KCodec`.

## Why the scope is intentionally narrow (Phase 1)

This release **does not** include:

- DICOM file parsing — the consumer must parse `.dcm` files with their
  own library (or use the macOS-only CLI path via `Sources/J2KCLI/DICOMSupport.swift`).
- DICOM pixel-data extraction (encapsulated pixel data demarshalling
  from `(7FE0,0010)`).
- Encapsulated-Pixel-Data writer (J2K codestream → DICOM Pixel Data byte
  layout).
- DICOM Information Object Definition (IOD) helpers (Photometric
  Interpretation auto-detection from sample values, etc.).

These belong to Phase 2 (likely v10.18.0) and would either extract more
of the CLI's `DICOMSupport.swift` logic into the helpers product, or ship
a thin DICOMKit adapter as an opt-in sibling product so ADR-004 stays
intact for consumers who don't want the DICOM library dep.

Phase 1 is the **smallest viable shape** of the helpers product — just the
UID-and-config bridge — so the API surface stabilises early and consumers
can start using it before Phase 2 lands.

## Test Suite Results

| Suite | Tests | Result | Coverage |
|---|---:|---|---|
| `V10_29_TransferSyntaxRoundTripTests` | 9/9 | PASS | UID round-trip per case + unique UIDs + isLossless/isHTJ2K/isPart2 truth tables + lenient parsing (NUL/whitespace) + unknown UID returns nil + CaseIterable covers all 7 |
| `V10_29_EncodingConfigurationParityTests` | 5/5 | PASS | Lossless UIDs set `lossless = true` + `useReversibleFilter = true` + `quality = 1.0`; lossy UIDs do not; HTJ2K UIDs set `useHTJ2K = true` + `htj2kBlockFormat = .conformant`; Part-1 UIDs do not; end-to-end bit-exact round-trip for `.j2kLossless` + `.htj2kLossless` |
| `V10_29_CodestreamDetectionTests` | 6/6 | PASS | `.j2kLossless` codestream detected as `.j2kLossless` (no CAP); `.htj2kLossless` codestream detected as `.htj2kLossless` (CAP present); empty/truncated data returns nil; JPEG/PNG/random bytes do NOT misdetect as J2K |
| `V10_29_PhotometricInterpretationTests` | 6/6 | PASS | Raw values match DICOM PS3.3 §C.7.6.3.1.2; `.colorSpace` total mapping; reverse from `J2KColorSpace` returns nil for `.hdr`/`.hdrLinear`/`.iccProfile`/`.unknown`; rawValue round-trip |
| **`V10_29_*` total** | **26/26** | **PASS** | |
| `swift test --filter JP3D` (full regression) | 528/528 | PASS | All 519 pre-existing JP3D tests still green + 9 new (V10_27 probe + V10_28 parity from v10.16.0) + 1 pre-existing skip |
| Mandatory commit gate (release mode) | 7/7 | PASS | `J2KMedicalCorpusEncodePerformanceTests` 2/2 + `J2KMedicalCorpusPerformanceTests` 2/2 + `J2KStrictCrossCodecValidationTests` 3/3 |

## API surface — additions only

```swift
import J2KDICOMHelpers

public enum J2KDICOMTransferSyntax: Sendable, Equatable, Hashable, CaseIterable {
    case j2kLossless                  // 1.2.840.10008.1.2.4.90
    case j2kLossy                     // 1.2.840.10008.1.2.4.91
    case j2kPart2MulticompLossless    // 1.2.840.10008.1.2.4.92  (retired in DICOM 2024c)
    case j2kPart2Multicomp            // 1.2.840.10008.1.2.4.93  (retired in DICOM 2024c)
    case htj2kLossless                // 1.2.840.10008.1.2.4.201
    case htj2kLossyConstant           // 1.2.840.10008.1.2.4.202
    case htj2kLossy                   // 1.2.840.10008.1.2.4.203

    public var uid: String { get }
    public init?(uid: String)         // whitespace + trailing-NUL tolerant
    public var isLossless: Bool { get }
    public var isHTJ2K: Bool { get }
    public var isPart2: Bool { get }

    public func encodingConfiguration(
        bitDepth: Int = 16,
        psnrTarget: Double = 40.0
    ) -> J2KEncodingConfiguration
}

public enum J2KDICOMCodestreamDetector {
    public static func detect(_ codestream: Data) -> J2KDICOMTransferSyntax?
}

public enum J2KDICOMPhotometricInterpretation:
    String, Sendable, Equatable, Hashable, CaseIterable
{
    case monochrome1, monochrome2     // greyscale (0=white / 0=black)
    case rgb                          // sRGB
    case yBrFull, yBrFull422          // full-range YCbCr (no chroma subsampling / 4:2:2)
    case yBrRct                       // YCbCr via JPEG 2000 reversible RCT (lossless 5/3)
    case yBrIct                       // YCbCr via JPEG 2000 irreversible ICT (lossy 9/7)

    public var colorSpace: J2KColorSpace { get }
    public init?(colorSpace: J2KColorSpace)  // nil for hdr/hdrLinear/iccProfile/unknown
}
```

No removals. No existing signatures changed.

## Recommended usage

```swift
import J2KDICOMHelpers
import J2KCodec

// Encode an image to a DICOM-compatible HTJ2K lossless codestream:
let ts = J2KDICOMTransferSyntax.htj2kLossless
let cfg = ts.encodingConfiguration(bitDepth: 16)
let codestream = try await J2KEncoder(encodingConfiguration: cfg).encode(image)
// codestream is byte-compatible with DICOM Transfer Syntax UID 1.2.840.10008.1.2.4.201

// Identify an unknown codestream's Transfer Syntax:
let detected = J2KDICOMCodestreamDetector.detect(codestream)
// detected == .htj2kLossless

// Bridge a PhotometricInterpretation tag from a DICOM dataset to J2KColorSpace:
let pi = J2KDICOMPhotometricInterpretation(rawValue: "MONOCHROME2")
let colorSpace = pi?.colorSpace  // .grayscale
```

## Known limitations

- **Sniff ambiguity**: a 5/3 (lossless) codestream is bit-identical
  regardless of whether it was tagged with the Part-1 Lossless UID
  (`...4.90`) or the Part-1 Lossless-or-Lossy UID (`...4.91`) used in
  its lossless mode. Detection alone cannot distinguish — the detector
  reports the canonical lossless variant. Consumers with the source
  Transfer Syntax UID should prefer `J2KDICOMTransferSyntax(uid:)` over
  sniffing.
- **No file parsing**: this Phase 1 does not parse `.dcm` files. CLI
  consumers can use `Sources/J2KCLI/DICOMSupport.swift`'s `loadDICOM(_:)`
  (macOS, with a Python fallback for compressed transfer syntaxes).
  Library consumers should pair `J2KDICOMHelpers` with their own DICOM
  parser.
- **Encapsulated pixel data**: Phase 1 doesn't (de)serialise the DICOM
  `(7FE0,0010)` Pixel Data Item byte layout (BOT, fragment items, etc.).
  Phase 2 territory.
- **Lossy bit-rate control**: `encodingConfiguration(psnrTarget:)` maps
  to the encoder's `quality` field via a rough rule of thumb
  (`psnrTarget / 50.0`). Consumers wanting a precise R-D operating
  point should construct `J2KEncodingConfiguration` directly with
  `bitrateMode = .constantBitrate(...)`.

## Reproducing the test numbers

```bash
swift test -c release --filter "V10_29"
```

26 tests across 4 suites (TransferSyntaxRoundTrip 9 + EncodingConfigurationParity 5
+ CodestreamDetection 6 + PhotometricInterpretation 6) — all PASS in ~0.06 s
release mode.

## Backward upgrade

`swift package update` won't auto-pick this release if your `Package.swift`
pins an exact version; bump the requirement to `from: "10.17.0"`. To use
the new helpers, add `J2KDICOMHelpers` to a target's product list:

```swift
.target(
    name: "YourMedicalApp",
    dependencies: [
        .product(name: "J2KCodec", package: "J2KSwift"),
        .product(name: "J2KDICOMHelpers", package: "J2KSwift"),  // v10.17.0+
    ])
```

Consumers not adding the product are completely unaffected.

## Companion — AsyncSequence progress streams deferred

Phase 3 of the original v10.17.0 plan proposed AsyncSequence progress
streams (`progressStream()` extensions) on `JP3DDecoder` / `JP3DROIDecoder`
/ `JP3DEncoder` as a modern alternative to `setProgressCallback(_:)`.
The lifecycle bridging (continuation termination → clear actor-stored
callback; continuation retention semantics; intermixed-with-closure
edge cases) warrants a dedicated MINOR ship rather than being squeezed
into v10.17.0. Deferred to v10.18.0 or later.
