# Part 2 Metadata — ISO/IEC 15444-2

## Overview

J2KSwift provides comprehensive metadata support for JPEG 2000 Part 2 (ISO/IEC 15444-2) files. Part 2 extends the baseline JP2 metadata model with boxes for intellectual property rights, digital signatures, human-readable labels, entity associations, external references, region of interest descriptions, and extended XML schemas. These metadata boxes can be used independently or grouped together inside association boxes to create rich, structured metadata hierarchies.

All metadata box types conform to the `J2KBox` protocol and are `Sendable`, enabling safe use across concurrent tasks.

## IPR Box

The Intellectual Property Rights box (`jp2i`) stores arbitrary binary data representing rights management information. The content is opaque — J2KSwift reads and writes the raw bytes without interpreting them, leaving rights enforcement to the consuming application.

### Usage

```swift
import J2KFileFormat

// Create from raw rights data
let rightsData = Data("Copyright 2024 Example Corp. All rights reserved.".utf8)
let ipr = J2KIPRBox(data: rightsData)

// Serialize to box content
let encoded = try ipr.write()

// Deserialize
var decoded = J2KIPRBox()
try decoded.read(from: encoded)
print(String(data: decoded.data, encoding: .utf8)!)
// "Copyright 2024 Example Corp. All rights reserved."
```

### Embedding DRM Data

```swift
// XrML or ODRL rights expression
let xrml = loadRightsExpression("license.xrml")
let ipr = J2KIPRBox(data: xrml)

// The IPR box is typically placed at the top level of the JPX file
```

### Box Structure

| Field | Size | Description |
|-------|------|-------------|
| IPR data | N bytes | Arbitrary binary rights data |

## Digital Signatures

The Digital Signature box (`dsig`) provides content integrity verification by storing a cryptographic hash over one or more boxes in the file.

### Supported Algorithms

| Algorithm | Enum | Digest Size |
|-----------|------|-------------|
| MD5 | `.md5` | 128-bit |
| SHA-1 | `.sha1` | 160-bit |
| SHA-256 | `.sha256` | 256-bit |
| SHA-512 | `.sha512` | 512-bit |

### Creating a Signature

```swift
import J2KFileFormat

// Compute hash externally (J2KSwift stores signatures, not computes them)
let sha256Digest = computeSHA256(over: boxData)

let signature = J2KDigitalSignatureBox(
    signatureType: .sha256,
    signatureData: sha256Digest,
    signedBoxTypes: [.jp2h, .jp2c]
)

let encoded = try signature.write()
```

### Reading and Verifying

```swift
var sig = J2KDigitalSignatureBox()
try sig.read(from: signatureBoxData)

for boxType in sig.signedBoxTypes {
    print("Signed box: \(boxType)")
}

// Verify externally
let isValid = sig.signatureData == computeHash(
    algorithm: sig.signatureType,
    over: extractSignedBoxContent(sig.signedBoxTypes)
)
```

### Box Structure

| Field | Size | Description |
|-------|------|-------------|
| Signature type | 1 byte | Hash algorithm (0–3) |
| Signed box count | 2 bytes | Number of box types covered |
| Signed box types | M × 4 bytes | Four-byte type codes |
| Signature data | N bytes | Raw signature bytes |

## Labels and Associations

### Label Box

The Label box (`lbl `) contains a UTF-8 string providing a human-readable annotation. Labels are most commonly placed inside association boxes to name groups of related content.

```swift
// Create a label
let label = try J2KLabelBox(label: "Band 4 – Near Infrared")

// Serialize
let data = try label.write()

// Read back
var readLabel = try J2KLabelBox(label: "")
try readLabel.read(from: data)
print(readLabel.label) // "Band 4 – Near Infrared"
```

Labels must be valid UTF-8. Attempting to create a label with invalid encoding throws `J2KError.fileFormatError`.

### Association Box

The Association box (`asoc`) groups related metadata boxes together, typically starting with an optional label followed by content boxes.

```swift
let label = try J2KLabelBox(label: "Geospatial Metadata")
let xml = try J2KXMLBox(xmlString: """
    <?xml version="1.0" encoding="UTF-8"?>
    <gml:FeatureCollection xmlns:gml="http://www.opengis.net/gml">
      <gml:boundedBy>
        <gml:Envelope srsName="EPSG:4326">
          <gml:lowerCorner>-90 -180</gml:lowerCorner>
          <gml:upperCorner>90 180</gml:upperCorner>
        </gml:Envelope>
      </gml:boundedBy>
    </gml:FeatureCollection>
    """)
let nlst = J2KNumberListBox(associations: [
    .init(entityType: .codestream, entityIndex: 0)
])

let association = J2KAssociationBox(
    label: label,
    children: [.xmlContent(xml), .numberList(nlst)]
)
let data = try association.write()
```

### Number List Box

The Number List box (`nlst`) associates numbered entities with metadata:

```swift
let nlst = J2KNumberListBox(associations: [
    .init(entityType: .codestream, entityIndex: 0),
    .init(entityType: .compositingLayer, entityIndex: 0)
])
let data = try nlst.write()

var decoded = J2KNumberListBox()
try decoded.read(from: data)
```

#### Entity Types

| Type | Value | Description |
|------|-------|-------------|
| `.codestream` | 0 | A codestream within the file |
| `.compositingLayer` | 1 | A compositing layer |
| `.rendered` | 2 | A rendered result |

### Nested Associations

Associations can be nested for hierarchical metadata:

```swift
let bandLabel = try J2KLabelBox(label: "Band 1 – Red")
let bandXml = try J2KXMLBox(xmlString: "<band><wavelength>620-750nm</wavelength></band>")
let bandAssoc = J2KAssociationBox(
    label: bandLabel,
    children: [.xmlContent(bandXml)]
)

let outerLabel = try J2KLabelBox(label: "Spectral Bands")
let outerAssoc = J2KAssociationBox(
    label: outerLabel,
    children: [.rawContent(.asoc, try bandAssoc.write())]
)
```

## XML Metadata

Part 2 extends the baseline XML box with well-known schema families for structured metadata. The `J2KPart2XMLMetadata` helper wraps a standard `J2KXMLBox` with schema detection and convenience methods.

### Schema Types

| Schema | Value | Description |
|--------|-------|-------------|
| `.generic` | 0 | General-purpose or unrecognized XML |
| `.gml` | 1 | Geography Markup Language (GMLJP2) |
| `.jpx` | 2 | JPX file format metadata |
| `.custom` | 3 | Application-specific schema |

### Creating Part 2 XML Metadata

```swift
// GML metadata for geospatial imagery
let gml = J2KPart2XMLMetadata(
    schema: .gml,
    content: """
        <?xml version="1.0" encoding="UTF-8"?>
        <gml:FeatureCollection xmlns:gml="http://www.opengis.net/gml">
          <gml:featureMember>
            <gml:Point srsName="EPSG:4326">
              <gml:pos>48.8566 2.3522</gml:pos>
            </gml:Point>
          </gml:featureMember>
        </gml:FeatureCollection>
        """
)

// Convert to standard XML box for serialization
let xmlBox = try gml.toXMLBox()
let data = try xmlBox.write()
```

### Converting from XML Boxes

```swift
let xmlBox = try J2KXMLBox(xmlString: "<gml:Point/>")
if let metadata = J2KPart2XMLMetadata.fromXMLBox(xmlBox) {
    print(metadata.schemaType) // .gml
}
```

### Feature Description XML

Generate minimal Part 2 feature descriptions:

```swift
let xml = J2KPart2XMLMetadata.featureXML(
    featureName: "Multi-Component Transform",
    description: "Custom 5x5 decorrelation matrix for spectral imagery"
)
```

## Cross-References

The Cross-Reference box (`cref`) links to external resources identified by a URL, fragment, or UUID. This allows metadata or supplementary content to be stored outside the JPEG 2000 file.

### Reference Types

| Type | Value | Description |
|------|-------|-------------|
| `.url` | 0 | URL reference |
| `.fragment` | 1 | Fragment identifier |
| `.uuid` | 2 | UUID-based reference |

### Usage

```swift
// URL reference to external metadata
let urlRef = try J2KCrossReferenceBox(
    referenceType: .url,
    reference: "https://example.com/metadata/scene-42.xml"
)

// Fragment reference within the same document
let fragRef = try J2KCrossReferenceBox(
    referenceType: .fragment,
    reference: "#band-metadata-section"
)

let data = try urlRef.write()
var decoded = try J2KCrossReferenceBox(referenceType: .url, reference: "")
try decoded.read(from: data)
```

## ROI Descriptions

The ROI Description box (`roid`) describes regions of interest within the image at the file format level. Each region specifies a bounding rectangle and a priority level for preferential decoding or display.

### ROI Types

| Type | Value | Description |
|------|-------|-------------|
| `.rectangular` | 0 | Axis-aligned rectangle |
| `.elliptical` | 1 | Ellipse inscribed in bounding rectangle |
| `.polygonal` | 2 | Polygon derived from bounding rectangle |

### Creating ROI Descriptions

```swift
let roi = J2KROIDescriptionBox(
    roiType: .rectangular,
    regions: [
        .init(x: 200, y: 100, width: 300, height: 400, priority: 0),
        .init(x: 50, y: 800, width: 700, height: 100, priority: 1)
    ]
)
let data = try roi.write()
```

### Reading ROI Descriptions

```swift
var roi = J2KROIDescriptionBox()
try roi.read(from: roiData)
for region in roi.regions {
    print("Region at (\(region.x), \(region.y)) size \(region.width)×\(region.height)")
}
```

### Associating ROIs with Codestreams

Use an association box to link ROI descriptions to specific codestreams:

```swift
let label = try J2KLabelBox(label: "Face Detection ROIs")
let nlst = J2KNumberListBox(associations: [
    .init(entityType: .codestream, entityIndex: 0)
])
let roi = J2KROIDescriptionBox(
    roiType: .rectangular,
    regions: [.init(x: 200, y: 100, width: 300, height: 400, priority: 0)]
)
let association = J2KAssociationBox(
    label: label,
    children: [
        .numberList(nlst),
        .rawContent(.roid, try roi.write())
    ]
)
```

## Data Entry URLs

The Data Entry URL box (`url `) contains a URL pointing to an external resource, following the ISO base media file format full-box convention.

```swift
let urlBox = try J2KDataEntryURLBox(
    version: 0,
    flags: 0,
    url: "https://example.com/supplementary-data.bin"
)
let data = try urlBox.write()

var decoded = try J2KDataEntryURLBox(url: "")
try decoded.read(from: data)
print(decoded.url) // "https://example.com/supplementary-data.bin"
```

## Best Practices

### Metadata Organization

1. **Use association boxes** — Group related metadata inside `J2KAssociationBox` for logical structure
2. **Label everything** — Provide descriptive `J2KLabelBox` labels for associations
3. **Link metadata to entities** — Use `J2KNumberListBox` to bind metadata to codestreams or layers

### Security

4. **Prefer SHA-256** — Use `.sha256` for digital signatures unless interoperability mandates otherwise
5. **Sign critical boxes** — At minimum, sign `jp2h` and `jp2c` boxes
6. **Validate signatures early** — Check digital signatures before processing file content

### Interoperability

7. **Include rreq** — Files using Part 2 metadata should include a reader requirements box
8. **Use standard schemas** — Prefer GML or JPX schemas over custom XML when possible
9. **Validate UTF-8** — All string-bearing boxes require valid UTF-8

## Code Examples

### Complete Metadata Suite

```swift
import J2KFileFormat

let ipr = J2KIPRBox(data: Data("© 2024 Example Corp".utf8))
let sig = J2KDigitalSignatureBox(
    signatureType: .sha256,
    signatureData: sha256Hash,
    signedBoxTypes: [.jp2h, .jp2c]
)

let gmlLabel = try J2KLabelBox(label: "Geographic Extent")
let gmlXml = J2KPart2XMLMetadata(
    schema: .gml, content: "<gml:Envelope srsName=\"EPSG:4326\"/>"
)
let gmlAssoc = J2KAssociationBox(
    label: gmlLabel,
    children: [.xmlContent(try gmlXml.toXMLBox())]
)

let roi = J2KROIDescriptionBox(
    roiType: .rectangular,
    regions: [.init(x: 0, y: 0, width: 1920, height: 1080, priority: 0)]
)

let extRef = try J2KCrossReferenceBox(
    referenceType: .url,
    reference: "https://example.com/full-metadata.json"
)
```

### Geospatial Imagery Metadata

```swift
let gml = J2KPart2XMLMetadata(
    schema: .gml, content: "<gml:Envelope srsName=\"EPSG:4326\"/>"
)
let label = try J2KLabelBox(label: "GMLJP2 Coverage")
let nlst = J2KNumberListBox(associations: [
    .init(entityType: .codestream, entityIndex: 0)
])
let assoc = J2KAssociationBox(
    label: label,
    children: [.xmlContent(try gml.toXMLBox()), .numberList(nlst)]
)
```

### Multi-Band Metadata with ROI

```swift
// Label each spectral band
for (index, bandName) in ["Red", "Green", "Blue", "NIR"].enumerated() {
    let label = try J2KLabelBox(label: "Band \(index) – \(bandName)")
    let nlst = J2KNumberListBox(associations: [
        .init(entityType: .codestream, entityIndex: UInt32(index))
    ])
    let assoc = J2KAssociationBox(
        label: label,
        children: [.numberList(nlst)]
    )
    let data = try assoc.write()
}
```

## Error Handling

All metadata box operations throw `J2KError.fileFormatError` with descriptive messages:

```swift
do {
    let label = try J2KLabelBox(label: invalidString)
} catch J2KError.fileFormatError(let message) {
    print("Format error: \(message)")
}
```

Common error conditions:
- **Invalid UTF-8**: Label, URL, and cross-reference strings
- **Truncated data**: Box content shorter than minimum required length
- **Unknown enum values**: Invalid entity types, reference types, or signature algorithms

## See Also

- [ISO/IEC 15444-2:2004](https://www.iso.org/standard/33160.html) — JPEG 2000 Part 2 Extensions
- [PART2_FILE_FORMAT.md](PART2_FILE_FORMAT.md) — Part 2 File Format Extensions
- [PART2_MCT.md](PART2_MCT.md) — Multi-Component Transform
- [PART2_NLT.md](PART2_NLT.md) — Non-Linear Point Transforms
- [PART2_EXTENDED_ROI.md](PART2_EXTENDED_ROI.md) — Extended ROI
