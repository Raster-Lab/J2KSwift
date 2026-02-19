# Part 2 File Format Extensions — ISO/IEC 15444-2

## Overview

J2KSwift provides complete support for the JPEG 2000 Part 2 (ISO/IEC 15444-2) extended file format, known as JPX. Part 2 extends the baseline JP2 file format with additional box types for metadata, compositing, animation, digital signatures, and external references. These extensions enable richer file structures for applications such as geospatial imaging, medical imaging, animation, and digital rights management.

The JPX file format builds on the JP2 superbox hierarchy, adding new box types that can be placed at the top level or nested inside association boxes. J2KSwift supports reading, writing, and validating all Part 2 box types through a consistent API.

## Features

- **Extended Box Types** — IPR, Label, Association, Number List, Cross-Reference, Digital Signature, ROI Description, Data Entry URL
- **Reader Requirements** — rreq box for signaling decoder capabilities
- **Decoder Capability Negotiation** — Validate files against decoder support
- **JPX Animation** — Frame-based animation with timing and looping
- **Multi-Layer Compositing** — Position and blend multiple codestreams
- **Composition Layer Headers** — Per-layer color, opacity, and registration
- **Part 2 XML Metadata** — GML, JPX, and custom schema support
- **Feature Compatibility** — Validate feature combinations and dependencies

## Extended JPX Box Types

Part 2 defines several new box types beyond the baseline JP2 format. Each box type is registered on `J2KBoxType` as a static property.

### IPR Box (`jp2i`)

The Intellectual Property Rights box stores arbitrary binary data representing rights management information. The content is opaque and its interpretation depends on the rights management system in use.

```swift
import J2KFileFormat

// Create an IPR box with rights data
let iprData = Data("Copyright 2024 Example Corp.".utf8)
let ipr = J2KIPRBox(data: iprData)

// Serialize
let encoded = try ipr.write()

// Deserialize
var decoded = J2KIPRBox()
try decoded.read(from: encoded)
```

### Label Box (`lbl `)

The Label box contains a UTF-8 encoded string providing a human-readable label for associated content. Labels are commonly used inside association boxes to name groups of related boxes.

```swift
// Create a label
let label = try J2KLabelBox(label: "Layer 0 – Background")

// Serialize
let data = try label.write()

// Read back
var readLabel = try J2KLabelBox(label: "")
try readLabel.read(from: data)
print(readLabel.label) // "Layer 0 – Background"
```

### Association Box (`asoc`)

The Association box is a super-box that groups related boxes together. It typically contains an optional label box followed by content boxes such as XML metadata, number lists, or nested associations.

```swift
// Create an association with a label and XML metadata
let label = try J2KLabelBox(label: "GeoTIFF Metadata")
let xml = try J2KXMLBox(xmlString: "<gml:FeatureCollection/>")

let association = J2KAssociationBox(
    label: label,
    children: [.xmlContent(xml)]
)

let data = try association.write()
```

#### Associated Content Types

The `AssociatedContent` enum defines the types of content that can be placed inside an association:

| Case | Description |
|------|-------------|
| `.xmlContent(J2KXMLBox)` | XML metadata content |
| `.labelContent(J2KLabelBox)` | Nested label |
| `.numberList(J2KNumberListBox)` | Entity associations |
| `.rawContent(J2KBoxType, Data)` | Unrecognized box content |

### Number List Box (`nlst`)

The Number List box associates numbered entities (codestreams, compositing layers, or rendered results) with a parent. It is used inside association boxes to identify which entities the associated metadata applies to.

```swift
let associations = [
    J2KNumberListBox.Association(
        entityType: .codestream,
        entityIndex: 0
    ),
    J2KNumberListBox.Association(
        entityType: .compositingLayer,
        entityIndex: 1
    )
]

let box = J2KNumberListBox(associations: associations)
let data = try box.write()
```

#### Entity Types

| Type | Value | Description |
|------|-------|-------------|
| `.codestream` | 0 | A codestream within the file |
| `.compositingLayer` | 1 | A compositing layer |
| `.rendered` | 2 | A rendered result |

### Cross-Reference Box (`cref`)

The Cross-Reference box references external resources identified by a URL, fragment, or UUID.

```swift
let box = try J2KCrossReferenceBox(
    referenceType: .url,
    reference: "https://example.com/metadata.xml"
)
let data = try box.write()
```

#### Reference Types

| Type | Value | Description |
|------|-------|-------------|
| `.url` | 0 | URL reference |
| `.fragment` | 1 | Fragment identifier |
| `.uuid` | 2 | UUID-based reference |

### Digital Signature Box (`dsig`)

The Digital Signature box provides content integrity verification. It stores the hash algorithm, the list of signed box types, and the raw signature bytes.

```swift
let signature = J2KDigitalSignatureBox(
    signatureType: .sha256,
    signatureData: sha256Bytes,
    signedBoxTypes: [.jp2h, .jp2c]
)
let data = try signature.write()
```

#### Signature Types

| Algorithm | Value | Digest Size |
|-----------|-------|-------------|
| `.md5` | 0 | 128-bit |
| `.sha1` | 1 | 160-bit |
| `.sha256` | 2 | 256-bit |
| `.sha512` | 3 | 512-bit |

### ROI Description Box (`roid`)

The ROI Description box describes regions of interest within the image. Each region specifies a bounding rectangle (or ellipse/polygon) and a priority level.

```swift
let region = J2KROIDescriptionBox.ROIRegion(
    x: 100, y: 200, width: 300, height: 400, priority: 0
)
let box = J2KROIDescriptionBox(
    roiType: .rectangular,
    regions: [region]
)
let data = try box.write()
```

#### ROI Types

| Type | Value | Description |
|------|-------|-------------|
| `.rectangular` | 0 | Axis-aligned rectangle |
| `.elliptical` | 1 | Ellipse inscribed in bounding rectangle |
| `.polygonal` | 2 | Polygon derived from bounding rectangle |

### Data Entry URL Box (`url `)

The Data Entry URL box contains a URL pointing to an external resource. It follows the ISO base media file format full-box convention with version and 24-bit flags fields.

```swift
let box = try J2KDataEntryURLBox(
    version: 0,
    flags: 0,
    url: "https://example.com/resource"
)
let data = try box.write()
```

## Reader Requirements

The reader requirements box (`rreq`) signals which features a reader must support to fully understand or properly display a JPX file. It is defined in ISO/IEC 15444-2 Annex I.7.2.

### Standard Features

J2KSwift defines all standard JPEG 2000 features through the `J2KStandardFeature` enum. Features with values >= 18 are Part 2 extensions.

```swift
let feature = J2KStandardFeature.multiComponentTransform
print(feature.featureName)    // "Multi-Component Transform (Part 2)"
print(feature.isPart2Feature) // true
```

Key features include: `.noExtensions` (1), `.multipleCompositionLayers` (2), `.needsJPXReader` (5), `.compositing` (12), `.animation` (16), `.multiComponentTransform` (18), `.nonLinearTransform` (20), `.arbitraryWavelets` (21), `.extendedROI` (24), `.dcOffset` (26), `.perceptualEncoding` (29).

### Building a Reader Requirements Box

```swift
var box = J2KReaderRequirementsBox(
    maskLength: 1,
    fullyUnderstandMask: 0xFF,
    displayMask: 0x00,
    standardFeatures: [.init(feature: .noExtensions, mask: 0x80)],
    vendorFeatures: []
)
let data = try box.write()
```

### Suggested Requirements

Use `J2KFeatureCompatibility` to automatically generate a reader requirements box and validate feature combinations:

```swift
let features: Set<J2KStandardFeature> = [
    .needsJPXReader,
    .multiComponentTransform,
    .nonLinearTransform
]

let rreq = J2KFeatureCompatibility.suggestedReaderRequirements(for: features)
let data = try rreq.write()

// Validate for incompatible combinations
let issues = J2KFeatureCompatibility.validateFeatureCombination(features)
for issue in issues {
    print("\(issue.severity): \(issue.issue)")
}
```

## Decoder Capability Negotiation

The `J2KDecoderCapability` type checks whether a decoder implementation supports the features required by a particular JPX file.

### Creating Decoder Capabilities

```swift
// Part 1-only decoder
let basic = J2KDecoderCapability.part1Decoder()

// Full Part 2 decoder
let full = J2KDecoderCapability.part2Decoder()

// Custom decoder
let custom = J2KDecoderCapability(
    supportedFeatures: [
        .noExtensions,
        .needsJPXReader,
        .multiComponentTransform
    ]
)
```

### Validating Compatibility

```swift
let decoder = J2KDecoderCapability.part1Decoder()
let result = decoder.validate(requirements)

switch result {
case .compatible:
    print("File is fully supported")
case .partiallyCompatible(let missing):
    print("Missing features: \(missing.map(\.featureName))")
case .incompatible(let missing):
    print("Cannot decode: \(missing.map(\.featureName))")
}
```

### Checking Specific Capabilities

```swift
let decoder = J2KDecoderCapability.part2Decoder()
let canUnderstand = decoder.canFullyUnderstand(requirements)
let canDisplay = decoder.canDisplay(requirements)
let missing = decoder.missingFeatures(requirements)
```

## JPX Animation

J2KSwift provides high-level APIs for building frame-based JPX animation sequences as defined in ISO/IEC 15444-2 Annex M.

### Animation Timing

The `J2KAnimationTiming` type describes temporal characteristics:

```swift
let timing = J2KAnimationTiming.milliseconds(duration: 5000, loops: 3)
let timing2 = J2KAnimationTiming.seconds(duration: 2.5, loops: 0)
let infinite = J2KAnimationTiming.infinite()

// Custom timescale (e.g. 24 fps)
let film = J2KAnimationTiming(
    timescale: 24, duration: 240, loopCount: 1, autoReverse: false
)
print(film.durationSeconds) // 10.0
```

### Animation Frames

Each frame references a codestream and composition layer with positioning, sizing, and opacity:

```swift
let frame = J2KAnimationFrame(
    codestreamIndex: 0,
    compositionLayerIndex: 0,
    duration: 100,
    width: 800, height: 600
)
```

### Building an Animation Sequence

```swift
var animation = J2KJPXAnimationSequence(
    width: 800, height: 600,
    timing: .milliseconds(duration: 3000, loops: 0)
)
animation.addFrame(codestreamIndex: 0, duration: 100)
animation.addFrame(codestreamIndex: 1, duration: 100)
animation.addFrame(codestreamIndex: 2, duration: 100)

try animation.validate()
let compositionBox = animation.toCompositionBox()
let instructionBox = animation.toInstructionSetBox()
```

### Instruction Set Box

The instruction set box (`inst`) contains rendering instructions for composition and animation:

```swift
let entry = J2KInstructionSetBox.InstructionEntry(
    layerIndex: 0,
    horizontalOffset: 100,
    verticalOffset: 50,
    persistenceFlag: true
)

let instBox = J2KInstructionSetBox(
    instructionType: .animate,
    repeatCount: 3,
    tickDuration: 100,
    instructions: [entry]
)

let data = try instBox.write()
```

#### Instruction Types

| Type | Value | Description |
|------|-------|-------------|
| `.compose` | 0 | Static layer composition |
| `.animate` | 1 | Animated frame sequence |
| `.transform` | 2 | Geometric transformation |

### Composition Layer Headers

The `J2KCompositionLayerHeaderBox` is a super-box containing layer-specific metadata:

```swift
let header = J2KCompositionLayerHeaderBox(
    colorSpecs: [J2KColorSpecificationBox(
        method: .enumerated(.sRGB), precedence: 0, approximation: 0
    )],
    opacity: J2KOpacityBox(opacityType: .globalValue, opacity: 200),
    labels: [try J2KLabelBox(label: "Background")]
)
let data = try header.write()
```

## Multi-Layer Compositing

The `J2KMultiLayerCompositor` provides a high-level interface for positioning and blending multiple codestreams on a shared canvas.

### Basic Usage

```swift
var compositor = J2KMultiLayerCompositor(
    canvasWidth: 1920,
    canvasHeight: 1080
)

// Add a full-canvas background layer
compositor.addLayer(
    codestreamIndex: 0,
    x: 0, y: 0,
    width: 1920, height: 1080,
    opacity: 255,
    compositingMode: .replace
)

// Add a semi-transparent overlay
compositor.addLayer(
    codestreamIndex: 1,
    x: 960, y: 0,
    width: 960, height: 1080,
    opacity: 200,
    compositingMode: .alphaBlend
)

// Validate
try compositor.validate()

// Convert to boxes
let compositionBox = compositor.toCompositionBox()
let layerHeaders = compositor.toLayerHeaders()
```

### Using CompositorLayer Directly

```swift
let layer = J2KMultiLayerCompositor.CompositorLayer(
    codestreamIndex: 0,
    x: 100,
    y: 100,
    width: 640,
    height: 480,
    opacity: 255,
    compositingMode: .replace,
    label: "Main Content"
)

var compositor = J2KMultiLayerCompositor(
    canvasWidth: 1920,
    canvasHeight: 1080
)
compositor.addLayer(layer)
```

## Code Examples

### Complete JPX File with Metadata

```swift
import J2KFileFormat

// Build reader requirements
let features: Set<J2KStandardFeature> = [
    .needsJPXReader,
    .multipleCompositionLayers,
    .compositing
]
let rreq = J2KFeatureCompatibility.suggestedReaderRequirements(for: features)

// Create metadata association
let label = try J2KLabelBox(label: "Scene Description")
let xml = try J2KXMLBox(xmlString: "<scene><title>Satellite Composite</title></scene>")
let association = J2KAssociationBox(
    label: label,
    children: [.xmlContent(xml)]
)
```

### Checking Decoder Compatibility Before Decoding

```swift
var rreq = J2KReaderRequirementsBox()
try rreq.read(from: rreqBoxData)

let decoder = J2KDecoderCapability(supportedFeatures: [
    .noExtensions, .needsJPXReader, .multipleCompositionLayers, .compositing
])

switch decoder.validate(rreq) {
case .compatible:
    break // Proceed with decoding
case .partiallyCompatible(let missing):
    print("Warning: missing \(missing.map(\.featureName))")
case .incompatible(let missing):
    print("Error: cannot decode, missing \(missing.map(\.featureName))")
}
```

### Simple Slideshow Animation

```swift
var animation = J2KJPXAnimationSequence(
    width: 1920, height: 1080,
    timing: .seconds(duration: 15.0, loops: 0)
)

for i in 0..<5 {
    animation.addFrame(codestreamIndex: UInt16(i), duration: 3000)
}

try animation.validate()
let composition = animation.toCompositionBox()
```

## API Reference

### Box Types

| Type | Box Code | Description |
|------|----------|-------------|
| `J2KIPRBox` | `jp2i` | Intellectual property rights |
| `J2KLabelBox` | `lbl ` | Human-readable text label |
| `J2KAssociationBox` | `asoc` | Groups related boxes |
| `J2KNumberListBox` | `nlst` | Numbered entity associations |
| `J2KCrossReferenceBox` | `cref` | External resource reference |
| `J2KDigitalSignatureBox` | `dsig` | Content integrity signature |
| `J2KROIDescriptionBox` | `roid` | Region of interest description |
| `J2KDataEntryURLBox` | `url ` | External data URL |

### Reader Requirements and Capability Types

| Type | Description |
|------|-------------|
| `J2KStandardFeature` | Standard JPEG 2000 feature identifiers |
| `J2KReaderRequirementsBox` | The rreq box for signaling requirements |
| `J2KDecoderCapability` | Decoder capability negotiation |
| `J2KFeatureCompatibility` | Feature compatibility validation |

### Animation and Compositing Types

| Type | Description |
|------|-------------|
| `J2KAnimationTiming` | Timing configuration for animations |
| `J2KAnimationFrame` | Single animation frame |
| `J2KJPXAnimationSequence` | High-level animation builder |
| `J2KInstructionSetBox` | Rendering instruction set |
| `J2KCompositionLayerHeaderBox` | Layer-level metadata super-box |
| `J2KMultiLayerCompositor` | Multi-layer compositing builder |

## Performance

Box read/write operations are lightweight and primarily limited by I/O. Small boxes (IPR, Label) serialize in under 0.01 ms. Association and animation boxes scale linearly with child/frame count.

### Optimization Guidelines

1. **Reuse box instances** — Avoid re-creating box objects when only updating content
2. **Batch writes** — Serialize all boxes in a single pass when building a complete file
3. **Lazy validation** — Call `validate()` once before final serialization, not on every mutation
4. **Minimize association depth** — Deeply nested association boxes increase parse time
5. **Pre-compute signatures** — Digital signature computation is external; keep signature data ready

### Thread Safety

All Part 2 box types conform to `Sendable` and can be safely used across concurrent tasks:

```swift
let box = J2KIPRBox(data: iprData)  // Sendable

await withTaskGroup(of: Data.self) { group in
    group.addTask { try! box.write() }
}
```

## Error Handling

All box read/write operations throw `J2KError.fileFormatError` with descriptive messages:

```swift
do {
    var box = J2KNumberListBox()
    try box.read(from: invalidData)
} catch J2KError.fileFormatError(let message) {
    print("Format error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

Common errors:
- **Invalid UTF-8**: Label, URL, and cross-reference strings must be valid UTF-8
- **Truncated data**: Box data shorter than the minimum required length
- **Invalid enum values**: Unknown entity types, reference types, or signature algorithms

## Best Practices

1. **Always include rreq** — Files using Part 2 features should include a reader requirements box
2. **Use associations for metadata** — Group related metadata inside association boxes
3. **Validate before writing** — Call `validate()` on animation sequences and compositors
4. **Prefer SHA-256** — Use `.sha256` for digital signatures
5. **Label your layers** — Provide descriptive labels for composition layers

## See Also

- [ISO/IEC 15444-2:2004](https://www.iso.org/standard/33160.html) — JPEG 2000 Part 2 Extensions
- [PART2_MCT.md](PART2_MCT.md) — Multi-Component Transform
- [PART2_NLT.md](PART2_NLT.md) — Non-Linear Point Transforms
- [PART2_EXTENDED_ROI.md](PART2_EXTENDED_ROI.md) — Extended ROI
- [PART2_METADATA.md](PART2_METADATA.md) — Part 2 Metadata Guide

## Examples

See `Tests/J2KFileFormatTests/` for comprehensive examples covering box serialization round-trips, reader requirements, decoder capability negotiation, animation sequences, multi-layer compositing, and digital signature handling.
