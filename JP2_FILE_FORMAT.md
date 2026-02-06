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

## File Structure Example

A minimal valid JP2 file structure:

```
JP2 File
├─ Signature Box ('jP  ')         [Required, first]
├─ File Type Box ('ftyp')         [Required, second]
├─ JP2 Header Box ('jp2h')        [Required]
│  ├─ Image Header Box ('ihdr')   [Required, first in jp2h]
│  └─ Color Specification ('colr')[Required]
└─ Contiguous Codestream ('jp2c') [Required, contains JPEG 2000 codestream]
```

Creating this structure:

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

// 3. JP2 Header
let ihdr = J2KImageHeaderBox(
    width: 1920,
    height: 1080,
    numComponents: 3,
    bitsPerComponent: 8
)
try writer.writeBox(J2KHeaderBox(boxes: [ihdr]))

// 4. Codestream (TODO: implement)
// try writer.writeRawBox(type: .jp2c, content: codestreamData)

let jp2Data = writer.data
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

### Planned (Phase 5, Week 60-62)

- [ ] Bits Per Component Box ('bpcc')
- [ ] Color Specification Box ('colr')
- [ ] Palette Box ('pclr')
- [ ] Component Mapping Box ('cmap')
- [ ] Channel Definition Box ('cdef')

### Future

- [ ] Resolution Box ('res ')
- [ ] Capture Resolution Box ('resc')
- [ ] Display Resolution Box ('resd')
- [ ] UUID Boxes ('uuid')
- [ ] XML Boxes ('xml ')
- [ ] Contiguous Codestream Box ('jp2c') integration

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
**Status**: Week 57-59 Complete ✅
**Next**: Week 60-62 - Essential Boxes
