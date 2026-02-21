# DICOM Integration Guide

J2KSwift is intentionally **DICOM-independent**: it implements ISO/IEC 15444
(JPEG 2000) with no dependency on any DICOM library.  However, it is fully aware
of DICOM's JPEG 2000 Transfer Syntaxes and pixel-data conventions, making it easy
to integrate with existing DICOM toolkits (DCMTK, fo-dicom, cornerstone, etc.).

---

## Transfer Syntax Support Matrix

| Transfer Syntax UID | Name | J2KSwift Support |
|---------------------|------|-----------------|
| 1.2.840.10008.1.2.4.90 | JPEG 2000 Lossless | ✅ Encode + Decode |
| 1.2.840.10008.1.2.4.91 | JPEG 2000 | ✅ Encode + Decode |
| 1.2.840.10008.1.2.4.201 | HTJ2K Lossless | ✅ Encode + Decode |
| 1.2.840.10008.1.2.4.202 | HTJ2K | ✅ Encode + Decode |
| 1.2.840.10008.1.2.4.203 | HTJ2K Lossless RPCL | ✅ Encode + Decode |

---

## Design Philosophy

```
DICOM Toolkit          J2KSwift
──────────────         ──────────────────────────────
PixelData (bytes) ──►  J2KDecoder / J2KEncoder
PhotometricInterp ──►  J2KColorSpace mapping
BitsAllocated     ──►  J2KComponent.bitDepth
NumberOfFrames    ──►  Multiple J2KImage / JP3D volume
```

J2KSwift never reads or writes DICOM tags.  Your DICOM toolkit extracts the raw
pixel-data bytes, passes them to J2KSwift for compression/decompression, and then
reassembles the DICOM dataset.

---

## Decoding DICOM Pixel Data

```swift
import J2KCore
import J2KCodec

// Assume `pixelDataBytes` is the raw value of the DICOM (7FE0,0010) attribute
// after removing the Encapsulated Pixel Data item framing.

let decoder = J2KDecoder()
let image: J2KImage = try decoder.decode(pixelDataBytes)

// Map components back to DICOM attributes:
// image.width        → Columns
// image.height       → Rows
// image.components.count → SamplesPerPixel
// image.components[0].bitDepth → BitsStored
```

---

## Encoding DICOM Pixel Data

```swift
import J2KCore
import J2KCodec

// Build a J2KImage from DICOM metadata and raw pixel values
let component = J2KComponent(
    index: 0,
    bitDepth: 12,    // BitsStored
    signed: false,
    width: 512,      // Columns
    height: 512,     // Rows
    data: pixelValues
)

let image = J2KImage(
    width: 512,
    height: 512,
    components: [component],
    colorSpace: .grayscale
)

// Lossless encode (TS 1.2.840.10008.1.2.4.90)
let encoder  = J2KEncoder(configuration: .lossless)
let j2kBytes = try encoder.encode(image)
// Store j2kBytes back into the DICOM (7FE0,0010) Pixel Data attribute.
```

---

## Photometric Interpretation Mapping

| DICOM PhotometricInterpretation | J2KSwift J2KColorSpace |
|---------------------------------|------------------------|
| `MONOCHROME1`                   | `.grayscale`           |
| `MONOCHROME2`                   | `.grayscale`           |
| `RGB`                           | `.sRGB`                |
| `YBR_FULL`                      | `.yCbCr`               |
| `YBR_FULL_422`                  | `.yCbCr`               |
| `YBR_ICT`                       | decoded as ICT internally |
| `YBR_RCT`                       | decoded as RCT internally |

---

## Multi-Frame (Cine) DICOM

Multi-frame DICOM datasets store each frame as a separate Encapsulated Item.
Decode each item independently:

```swift
import J2KCodec

let decoder = J2KDecoder()
var frames: [J2KImage] = []

for frameBytes in encapsulatedItems {
    let frame = try decoder.decode(frameBytes)
    frames.append(frame)
}
```

For motion JPEG 2000 (MJ2) datasets, see the [MJ2 Guide](MJ2_GUIDE.md).

---

## High-Bit / Signed Pixels

DICOM sometimes uses signed pixel values (e.g., CT Hounsfield units):

```swift
let component = J2KComponent(
    index: 0,
    bitDepth: 16,
    signed: true,   // PixelRepresentation = 1
    width: columns,
    height: rows,
    data: pixelBytes
)
```

---

## HTJ2K for DICOM (Transfer Syntaxes .201/.202/.203)

```swift
import J2KCodec

let htConfig = J2KEncodingConfiguration(
    progressionOrder: .RPCL,   // Required by TS .203
    useHTJ2K: true
)
let encoder  = J2KEncoder(encodingConfiguration: htConfig)
let htBytes  = try encoder.encode(image)
```

---

## No DICOM Dependencies

J2KSwift has zero runtime dependencies on DICOM libraries.  The `J2KCore`,
`J2KCodec`, and `J2KFileFormat` modules import only `Foundation`.  This ensures:

- Clean separation of concerns
- No DICOM licence requirements
- Usable in non-DICOM medical imaging pipelines
- Compatible with any DICOM toolkit on any platform

---

## See Also

- [Encoding Guide](ENCODING_GUIDE.md)
- [Decoding Guide](DECODING_GUIDE.md)
- [HTJ2K Guide](HTJ2K_GUIDE.md)
- [MJ2 Guide](MJ2_GUIDE.md)
- [JP3D Guide](JP3D_GUIDE.md)
- [Examples/DICOMWorkflow.swift](../Examples/DICOMWorkflow.swift)
