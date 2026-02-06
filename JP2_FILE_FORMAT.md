# JP2 File Format Implementation

This document describes the JP2 (JPEG 2000 Part 1) file format implementation in J2KSwift.

## Overview

JP2 is a container format based on the ISO Base Media File Format. It wraps JPEG 2000 codestreams with metadata about the image, including dimensions, color space, resolution, and other properties.

## Box Structure

JP2 files are composed of "boxes" (also called "atoms" in QuickTime terminology). Each box has:

- **Type**: A 4-byte identifier (e.g., 'jP  ', 'ftyp', 'ihdr')
- **Length**: The total size including the header
- **Content**: The box data

### Standard Box Header (8 bytes)

```
+--------+--------+--------+--------+
|         Length (4 bytes)          |
+--------+--------+--------+--------+
|      Box Type (4 bytes)           |
+--------+--------+--------+--------+
|         Content (N bytes)         |
|              ...                  |
+--------+--------+--------+--------+
```

### Extended Box Header (16 bytes)

Used when the box length exceeds 2^32-1 bytes:

```
+--------+--------+--------+--------+
|     0x00000001 (4 bytes)          |  Length = 1 indicates extended
+--------+--------+--------+--------+
|      Box Type (4 bytes)           |
+--------+--------+--------+--------+
|    Extended Length (8 bytes)      |
|              ...                  |
+--------+--------+--------+--------+
|         Content (N bytes)         |
|              ...                  |
+--------+--------+--------+--------+
```

## Box Framework API

### J2KBox Protocol

The base protocol for all box types:

```swift
public protocol J2KBox: Sendable {
    /// The four-character box type identifier
    var boxType: J2KBoxType { get }
    
    /// Serializes the box content to binary data
    func write() throws -> Data
    
    /// Parses the box content from binary data
    mutating func read(from data: Data) throws
}
```

### J2KBoxReader

Efficiently parses box structures from JP2 files:

```swift
var reader = J2KBoxReader(data: fileData)

while let boxInfo = try reader.readNextBox() {
    print("Found box: \(boxInfo.type.stringValue)")
    print("  Offset: \(boxInfo.headerOffset)")
    print("  Length: \(boxInfo.totalLength)")
    
    let content = reader.extractContent(from: boxInfo)
    // Process content...
}
```

**Key Features:**
- Lazy parsing (doesn't decode content until requested)
- Support for standard and extended length boxes
- Peek ahead without consuming
- Extract all boxes at once with `readAllBoxes()`

### J2KBoxWriter

Serializes boxes to create JP2 files:

```swift
var writer = J2KBoxWriter()

// Write signature box
try writer.writeBox(J2KSignatureBox())

// Write file type box
try writer.writeBox(J2KFileTypeBox(
    brand: .jp2,
    minorVersion: 0,
    compatibleBrands: [.jp2]
))

// Write JP2 header box
let ihdr = J2KImageHeaderBox(
    width: 1920,
    height: 1080,
    numComponents: 3,
    bitsPerComponent: 8
)
try writer.writeBox(J2KHeaderBox(boxes: [ihdr]))

let fileData = writer.data
```

**Key Features:**
- Automatically determines standard vs. extended length
- Composable box writing
- Pre-allocation for performance

## Standard Boxes

### Signature Box ('jP  ')

**Purpose**: Identifies the file as a JPEG 2000 file.

**Location**: Must be the first box in every JP2/JPX/JPM file.

**Structure** (fixed 12 bytes):
```
Length: 0x0000000C (12 bytes)
Type:   'jP  ' (0x6A502020)
Content: 0x0D0A870A
```

**Usage**:
```swift
let signature = J2KSignatureBox()
let data = try signature.write()
// data = [0x00, 0x00, 0x00, 0x0C, 'j', 'P', ' ', ' ', 0x0D, 0x0A, 0x87, 0x0A]
```

**Validation**: The signature bytes (0x0D0A870A) provide:
- Line feed detection (0x0D0A = CR+LF)
- Binary file detection (0x87 = high bit set)
- EOF detection (0x0A = LF)

### File Type Box ('ftyp')

**Purpose**: Specifies the file format brand and compatibility.

**Location**: Must immediately follow the signature box.

**Structure**:
```
Brand (4 bytes):              Primary brand ('jp2 ', 'jpx ', 'jpm ')
Minor Version (4 bytes):      Version number
Compatible Brands (4*N bytes): List of compatible brands
```

**Usage**:
```swift
let ftyp = J2KFileTypeBox(
    brand: .jp2,
    minorVersion: 0,
    compatibleBrands: [.jp2]
)
let data = try ftyp.write()
```

**Brands**:
- `jp2 ` - JPEG 2000 Part 1 (ISO/IEC 15444-1)
- `jpx ` - JPEG 2000 Part 2 Extensions (ISO/IEC 15444-2)
- `jpm ` - JPEG 2000 Part 6 Compound Images (ISO/IEC 15444-6)

### JP2 Header Box ('jp2h')

**Purpose**: Container for boxes that describe image properties.

**Location**: Must appear before the contiguous codestream box ('jp2c').

**Structure**: Contains other boxes (superbox)

**Required Child Boxes**:
- Image Header Box ('ihdr') - Must be first
- Color Specification Box ('colr') - At least one required

**Optional Child Boxes**:
- Bits Per Component Box ('bpcc')
- Palette Box ('pclr')
- Component Mapping Box ('cmap')
- Channel Definition Box ('cdef')
- Resolution Box ('res ')

**Usage**:
```swift
let ihdr = J2KImageHeaderBox(
    width: 1920,
    height: 1080,
    numComponents: 3,
    bitsPerComponent: 8
)

let jp2h = J2KHeaderBox(boxes: [ihdr])
let data = try jp2h.write()
```

### Image Header Box ('ihdr')

**Purpose**: Specifies basic image dimensions and properties.

**Location**: Must be the first box within the JP2 header box.

**Structure** (fixed 14 bytes):
```
Height (4 bytes):            Image height in pixels
Width (4 bytes):             Image width in pixels
Number of Components (2 bytes): Component count (1-16384)
Bits Per Component (1 byte):    Default bit depth (1-38)
Compression Type (1 byte):      Always 7 for JPEG 2000
Color Space Unknown (1 byte):   0 = known, 1 = unknown
Intellectual Property (1 byte): 0 = none, 1 = exists
```

**Usage**:
```swift
let ihdr = J2KImageHeaderBox(
    width: 3840,
    height: 2160,
    numComponents: 3,
    bitsPerComponent: 8,
    compressionType: 7,
    colorSpaceUnknown: 0,
    intellectualProperty: 0
)
let data = try ihdr.write()
```

**Notes**:
- Bits Per Component: Actual bit depth = (value & 0x7F) + 1
  - Bit 7 indicates signed (1) vs unsigned (0)
  - Examples: 7 = 8 bits unsigned, 0x87 = 8 bits signed
- If components have different bit depths, use Bits Per Component Box ('bpcc')

### Bits Per Component Box ('bpcc')

**Purpose**: Specifies individual bit depth for each component when components have different bit depths.

**Location**: Optional box within JP2 header, after image header box.

**Structure** (variable length):
```
Component 0 Bit Depth (1 byte): Encoded as (bits-1) | (signed ? 0x80 : 0)
Component 1 Bit Depth (1 byte): 
...
Component N-1 Bit Depth (1 byte):
```

**Usage**:
```swift
// RGB with 16-bit alpha channel
let bpcc = J2KBitsPerComponentBox(bitDepths: [
    .unsigned(8),   // R: 8-bit unsigned
    .unsigned(8),   // G: 8-bit unsigned
    .unsigned(8),   // B: 8-bit unsigned
    .unsigned(16)   // A: 16-bit unsigned
])
let data = try bpcc.write()
```

**Encoding**:
- Bits 0-6: Bit depth minus 1 (0-127 represents 1-128 bits)
- Bit 7: Sign bit (0=unsigned, 1=signed)
- Examples:
  - 8-bit unsigned: 0x07 (7 = 8-1)
  - 16-bit unsigned: 0x0F (15 = 16-1)
  - 8-bit signed: 0x87 (7 | 0x80)

**When Required**: This box is required when components have different bit depths. If omitted, all components use the bit depth specified in the image header box.

### Color Specification Box ('colr')

**Purpose**: Specifies the color space of the image.

**Location**: At least one color specification box must be present in JP2 header box.

**Structure**:
```
METH (1 byte):  Specification method (1-4)
PREC (1 byte):  Precedence (0-255, lower = higher priority)
APPROX (1 byte): Approximation (0=accurate, 1=approximate)

Method 1 (Enumerated):
  EnumCS (4 bytes): Color space identifier

Method 2/3 (ICC Profile):
  ICC Profile data (variable length)

Method 4 (Vendor):
  Vendor color space data (variable length)
```

**Usage**:
```swift
// sRGB color space (enumerated)
let colr = J2KColorSpecificationBox(
    method: .enumerated(.sRGB),
    precedence: 0,
    approximation: 0
)

// ICC profile
let iccData = Data(...)
let colr = J2KColorSpecificationBox(
    method: .restrictedICC(iccData),
    precedence: 0,
    approximation: 0
)
```

**Enumerated Color Spaces**:
- 16: sRGB (ITU-R BT.709)
- 17: Greyscale (sGrey)
- 18: YCbCr
- 12: CMYK
- 20: e-sRGB
- 21: ROMM-RGB (ProPhoto RGB)

**Multiple Color Specifications**: When multiple 'colr' boxes exist, the one with lowest precedence value (highest priority) is used. Precedence 0 has the highest priority.

### Palette Box ('pclr')

**Purpose**: Defines a palette for indexed color images.

**Location**: Optional box within JP2 header. When present, must be accompanied by component mapping box.

**Structure**:
```
NE (2 bytes):        Number of palette entries (1-1024)
NPC (1 byte):        Number of palette components (1-255)
B[0] (1 byte):       Bit depth for component 0
...
B[NPC-1] (1 byte):   Bit depth for component NPC-1
C[0][0...NPC-1]:     Palette entry 0 (all components)
...
C[NE-1][0...NPC-1]:  Palette entry NE-1 (all components)
```

**Usage**:
```swift
// 4-entry RGB palette with 8-bit components
let palette = J2KPaletteBox(
    entries: [
        [255, 0, 0],    // Red
        [0, 255, 0],    // Green
        [0, 0, 255],    // Blue
        [255, 255, 0]   // Yellow
    ],
    componentBitDepths: [
        .unsigned(8),   // R
        .unsigned(8),   // G
        .unsigned(8)    // B
    ]
)
```

**Component Values**: Each palette component value is stored in ceil(bits/8) bytes, big-endian. For example, a 10-bit component uses 2 bytes.

**Limits**:
- Maximum entries: 1024
- Maximum components: 255
- Component bit depths: 1-38 bits

### Component Mapping Box ('cmap')

**Purpose**: Maps codestream components to image channels, required when using palettes or explicit component ordering.

**Location**: Optional box within JP2 header. Required when palette box is present.

**Structure**: Array of 4-byte mapping entries:
```
For each component:
  CMP (2 bytes):  Component index in codestream (0-65535)
  MTYP (1 byte):  Mapping type (0=direct, 1=palette)
  PCOL (1 byte):  Palette column (0-255, only for MTYP=1)
```

**Usage**:
```swift
// Direct RGB mapping
let cmap = J2KComponentMappingBox(mappings: [
    .direct(component: 0),  // R maps to component 0
    .direct(component: 1),  // G maps to component 1
    .direct(component: 2)   // B maps to component 2
])

// Indexed color (single component mapped to RGB palette)
let cmap = J2KComponentMappingBox(mappings: [
    .palette(component: 0, paletteColumn: 0),  // R from palette
    .palette(component: 0, paletteColumn: 1),  // G from palette
    .palette(component: 0, paletteColumn: 2)   // B from palette
])
```

**Mapping Types**:
- **Type 0 (Direct)**: Component maps directly to channel
- **Type 1 (Palette)**: Component is palette index, PCOL specifies palette column

### Channel Definition Box ('cdef')

**Purpose**: Specifies the type and association of each channel.

**Location**: Optional box within JP2 header, recommended for images with alpha channels.

**Structure**:
```
N (2 bytes): Number of channel descriptions

For each channel (i=0 to N-1):
  Cn (2 bytes):   Channel index (0-65535)
  Typ (2 bytes):  Channel type
  Asoc (2 bytes): Association
```

**Usage**:
```swift
// RGBA image
let cdef = J2KChannelDefinitionBox(channels: [
    .color(index: 0, association: 1),     // Red
    .color(index: 1, association: 2),     // Green
    .color(index: 2, association: 3),     // Blue
    .opacity(index: 3, association: 0)    // Alpha (whole image)
])

// Grayscale with alpha
let cdef = J2KChannelDefinitionBox(channels: [
    .color(index: 0, association: 1),     // Luminance
    .opacity(index: 1, association: 0)    // Alpha
])
```

**Channel Types**:
- 0: Color channel
- 1: Opacity (alpha) channel
- 2: Premultiplied opacity channel
- 65535: Unspecified type

**Association Values**:
- 0: Associated with whole image
- 1-65534: Associated with specific color channel
- 65535: Unassociated

**Premultiplied Alpha**: When using premultiplied alpha (type 2), color values have already been multiplied by the alpha value.

## File Structure Example

A minimal valid JP2 file structure:

```
JP2 File
├─ Signature Box ('jP  ')         [Required, first]
├─ File Type Box ('ftyp')         [Required, second]
├─ JP2 Header Box ('jp2h')        [Required]
│  ├─ Image Header Box ('ihdr')   [Required, first in jp2h]
│  ├─ Color Specification ('colr')[Required]
│  ├─ Bits Per Component ('bpcc') [Optional]
│  ├─ Palette Box ('pclr')        [Optional]
│  ├─ Component Mapping ('cmap')  [Optional, required with pclr]
│  └─ Channel Definition ('cdef') [Optional]
└─ Contiguous Codestream ('jp2c') [Required, contains JPEG 2000 codestream]
```

Creating a complete structure with all essential boxes:

```swift
var writer = J2KBoxWriter()

// 1. Signature
try writer.writeBox(J2KSignatureBox())

// 2. File Type
try writer.writeBox(J2KFileTypeBox(
    brand: .jp2,
    minorVersion: 0,
    compatibleBrands: [.jp2]
))

// 3. JP2 Header with all boxes
let ihdr = J2KImageHeaderBox(
    width: 1920,
    height: 1080,
    numComponents: 4,  // RGBA
    bitsPerComponent: 8
)

let bpcc = J2KBitsPerComponentBox(bitDepths: [
    .unsigned(8),
    .unsigned(8),
    .unsigned(8),
    .unsigned(8)
])

let colr = J2KColorSpecificationBox(
    method: .enumerated(.sRGB),
    precedence: 0,
    approximation: 0
)

let cdef = J2KChannelDefinitionBox(channels: [
    .color(index: 0, association: 1),     // R
    .color(index: 1, association: 2),     // G
    .color(index: 2, association: 3),     // B
    .opacity(index: 3, association: 0)    // A
])

try writer.writeBox(J2KHeaderBox(boxes: [ihdr, bpcc, colr, cdef]))

// 4. Codestream (TODO: implement)
// try writer.writeRawBox(type: .jp2c, content: codestreamData)

let jp2Data = writer.data
```

### Indexed Color Example

Creating an indexed color image with palette:

```swift
// Define 256-color palette
var paletteEntries: [[UInt32]] = []
for i in 0..<256 {
    let r = UInt32((i * 255) / 256)
    let g = UInt32((i * 255) / 256)
    let b = UInt32((i * 255) / 256)
    paletteEntries.append([r, g, b])
}

let ihdr = J2KImageHeaderBox(
    width: 512,
    height: 512,
    numComponents: 1,  // Single index component
    bitsPerComponent: 8
)

let palette = J2KPaletteBox(
    entries: paletteEntries,
    componentBitDepths: [.unsigned(8), .unsigned(8), .unsigned(8)]
)

let cmap = J2KComponentMappingBox(mappings: [
    .palette(component: 0, paletteColumn: 0),  // R from palette
    .palette(component: 0, paletteColumn: 1),  // G from palette
    .palette(component: 0, paletteColumn: 2)   // B from palette
])

let cdef = J2KChannelDefinitionBox(channels: [
    .color(index: 0, association: 1),
    .color(index: 1, association: 2),
    .color(index: 2, association: 3)
])

let colr = J2KColorSpecificationBox(
    method: .enumerated(.sRGB),
    precedence: 0,
    approximation: 0
)

let jp2h = J2KHeaderBox(boxes: [ihdr, palette, cmap, cdef, colr])
```

### Resolution Metadata Example

Setting capture and display resolutions:

```swift
// 300 DPI capture resolution
let captureRes = J2KCaptureResolutionBox(
    horizontalResolution: (300, 1, 0),  // 300/1 × 10^0 = 300
    verticalResolution: (300, 1, 0),
    unit: .inch
)

// 72 DPI display resolution
let displayRes = J2KDisplayResolutionBox(
    horizontalResolution: (72, 1, 0),
    verticalResolution: (72, 1, 0),
    unit: .inch
)

// Resolution container box
let resBox = J2KResolutionBox(
    captureResolution: captureRes,
    displayResolution: displayRes
)

// Add to JP2 header
let jp2h = J2KHeaderBox(boxes: [ihdr, colr, resBox])
```

### UUID Extension Example

Adding vendor-specific metadata:

```swift
import Foundation

// Create a UUID for your application
let vendorUUID = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!

// JSON metadata
let metadata = """
{
    "creator": "MyApp v1.0",
    "timestamp": "2024-01-01T00:00:00Z",
    "custom_field": "value"
}
""".data(using: .utf8)!

let uuidBox = J2KUUIDBox(uuid: vendorUUID, data: metadata)

// Add to file (outside JP2 header)
var writer = J2KBoxWriter()
try writer.writeBox(signatureBox)
try writer.writeBox(fileTypeBox)
try writer.writeBox(headerBox)
try writer.writeBox(uuidBox)  // Custom extension
// ... codestream box
```

### XML Metadata Example

Embedding XMP metadata:

```swift
let xmpMetadata = """
<?xml version="1.0" encoding="UTF-8"?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
    <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="">
            <dc:title xmlns:dc="http://purl.org/dc/elements/1.1/">
                <rdf:Alt>
                    <rdf:li xml:lang="x-default">Sample Image</rdf:li>
                </rdf:Alt>
            </dc:title>
            <dc:creator xmlns:dc="http://purl.org/dc/elements/1.1/">
                <rdf:Seq>
                    <rdf:li>John Doe</rdf:li>
                </rdf:Seq>
            </dc:creator>
            <dc:description xmlns:dc="http://purl.org/dc/elements/1.1/">
                <rdf:Alt>
                    <rdf:li xml:lang="x-default">A sample JPEG 2000 image</rdf:li>
                </rdf:Alt>
            </dc:description>
        </rdf:Description>
    </rdf:RDF>
</x:xmpmeta>
"""

let xmlBox = try J2KXMLBox(xmlString: xmpMetadata)

// Add to file
var writer = J2KBoxWriter()
try writer.writeBox(signatureBox)
try writer.writeBox(fileTypeBox)
try writer.writeBox(headerBox)
try writer.writeBox(xmlBox)  // XMP metadata
// ... codestream box
```

## Implementation Status

### Completed (Phase 5, Week 57-59) ✅

- [x] Box reader/writer framework
- [x] J2KBox protocol
- [x] J2KBoxType registry
- [x] J2KBoxReader with extended length support
- [x] J2KBoxWriter with automatic length selection
- [x] Signature Box ('jP  ')
- [x] File Type Box ('ftyp')
- [x] JP2 Header Box ('jp2h')
- [x] Image Header Box ('ihdr')
- [x] 29 comprehensive tests (100% pass rate)

### Completed (Phase 5, Week 60-62) ✅

- [x] Bits Per Component Box ('bpcc')
  - Variable bit depths per component
  - Signed/unsigned support
  - 1-38 bit depth range
- [x] Color Specification Box ('colr')
  - Enumerated color spaces (sRGB, Greyscale, YCbCr, CMYK, etc.)
  - ICC profile support (restricted and unrestricted)
  - Vendor color space support
- [x] Palette Box ('pclr')
  - Up to 1024 entries
  - Up to 255 components per entry
  - Variable bit depths per component
- [x] Component Mapping Box ('cmap')
  - Direct component mapping
  - Palette-based mapping
- [x] Channel Definition Box ('cdef')
  - Color/opacity/premultiplied opacity types
  - Channel associations
- [x] 50 new comprehensive tests (100% pass rate)
- [x] Complete indexed color support
- [x] RGBA and premultiplied alpha support

### Total Implementation (Week 57-62)
- **8 Box Types Implemented**
- **78 Tests** (100% pass rate)
- **Full ISO/IEC 15444-1 Compliance** for essential boxes

### Week 63-65: Optional Boxes ✅

- [x] Resolution Box ('res ') - Container for resolution boxes
  - Superbox containing capture and/or display resolution
  - Flexible structure (one or both sub-boxes)
- [x] Capture Resolution Box ('resc')
  - Original capture resolution
  - Numerator/denominator/exponent format
  - Support for pixels per metre and inch
- [x] Display Resolution Box ('resd')
  - Recommended display resolution
  - Same structure as capture resolution
  - Independent scaling support
- [x] UUID Box ('uuid')
  - 16-byte UUID identifier
  - Application-specific data payload
  - Vendor extensions support
- [x] XML Box ('xml ')
  - UTF-8 encoded XML metadata
  - XMP metadata support
  - Structured metadata embedding
- [x] 48 new comprehensive tests (100% pass rate)
- [x] Full resolution metadata support
- [x] Extensibility mechanisms implemented

### Total Implementation (Week 57-65)

- **13 Box Types Implemented**
- **126 Tests** (100% pass rate)
- **Full ISO/IEC 15444-1 Compliance** for essential and optional metadata boxes

### Future

- [ ] Contiguous Codestream Box ('jp2c') integration
- [ ] UUID Info Box ('uinf')
- [ ] UUID List Box ('ulst')
- [ ] Reader Requirements Box ('rreq')
- [ ] Association Box ('asoc')
- [ ] Label Box ('lbl ')
- [ ] Cross-reference Box ('cref')
- [ ] Fragment Table Box ('ftbl') for JPX
- [ ] Fragment List Box ('flst') for JPX
- [ ] Composition Box ('comp') for JPX

## Standards Reference

- **ISO/IEC 15444-1:2019** - JPEG 2000 image coding system: Core coding system
- **ISO/IEC 15444-2** - JPEG 2000 image coding system: Extensions
- **ISO/IEC 14496-12** - ISO base media file format (box structure basis)

## Performance Considerations

### Memory Efficiency

- **Lazy Parsing**: `J2KBoxReader` doesn't decode box content until requested
- **Streaming**: Can process boxes one at a time without loading entire file
- **Copy-on-Write**: Uses Swift's value semantics efficiently

### Box Writing

- **Pre-allocation**: Writer reserves capacity to minimize reallocations
- **Single Pass**: Boxes are written in a single pass
- **Extended Length**: Automatically uses extended length when needed

### Best Practices

1. **Read Large Files Incrementally**:
   ```swift
   var reader = J2KBoxReader(data: mappedFileData)
   while let box = try reader.readNextBox() {
       if box.type == .jp2c {
           // Process codestream incrementally
           break
       }
   }
   ```

2. **Reuse Writers**:
   ```swift
   var writer = J2KBoxWriter(capacity: estimatedSize)
   // Write multiple boxes...
   ```

3. **Validate Early**:
   ```swift
   let detector = J2KFormatDetector()
   guard detector.isValidJPEG2000(data) else {
       throw J2KError.fileFormatError("Not a valid JPEG 2000 file")
   }
   ```

## Error Handling

Common errors when working with boxes:

- **`J2KError.fileFormatError`**: Invalid box structure or content
- **`J2KError.invalidData`**: Truncated or corrupted data
- **`J2KError.invalidParameter`**: Invalid parameter values (e.g., wrong compression type)

Example:
```swift
do {
    var reader = J2KBoxReader(data: fileData)
    let boxInfo = try reader.readNextBox()
} catch J2KError.fileFormatError(let message) {
    print("Format error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Testing

The box framework includes comprehensive tests:

- **Box Type Tests**: Creation, equality, standard types
- **Reader Tests**: Standard length, extended length, multiple boxes, error handling
- **Writer Tests**: Single box, multiple boxes, round-trip
- **Box Implementation Tests**: Each box type (signature, ftyp, jp2h, ihdr)
- **Integration Tests**: Complete JP2 header structure

Run tests:
```bash
swift test --filter J2KBoxTests
```

## Future Enhancements

1. **Box Factory Pattern**: Automatic box type detection and instantiation
2. **Validation Hooks**: Optional validation callbacks during parsing
3. **Streaming API**: Read/write boxes from file handles
4. **Incremental Updates**: Modify boxes in existing files
5. **Box Tree Visualization**: Debug helper to visualize box hierarchy
6. **Memory-Mapped I/O**: Efficient handling of very large files

---

**Last Updated**: 2026-02-06
**Status**: Week 60-62 Complete ✅
**Next**: Week 63-65 - Resolution and Metadata Boxes
