# Extended Format Support

This document describes J2KSwift's support for extended image formats including 16-bit images, HDR content, extended precision modes, and alpha channels.

## Overview

J2KSwift provides comprehensive support for modern image formats that exceed the traditional 8-bit SDR (Standard Dynamic Range) limitations. This includes:

- **16-bit Images**: Full support for 16-bit per component images
- **HDR (High Dynamic Range)**: Support for HDR content with extended luminance ranges
- **Extended Precision**: Support for 10-bit, 12-bit, and 14-bit precision
- **Alpha Channels**: Complete alpha channel support with premultiplied and straight alpha modes
- **Variable Bit Depths**: Support for any bit depth from 1 to 38 bits per component

## Supported Bit Depths

J2KSwift supports the full range of bit depths specified in the JPEG 2000 standard (ISO/IEC 15444-1):

### Common Bit Depths

| Bit Depth | Description | Typical Use Case |
|-----------|-------------|------------------|
| 1-bit | Binary images | Black and white documents, masks |
| 4-bit | Low color depth | Indexed color, simple graphics |
| 8-bit | Standard precision | SDR photos, web images |
| 10-bit | Extended precision | HDR10, broadcast video |
| 12-bit | High precision | Medical imaging, RAW photos |
| 14-bit | Very high precision | Scientific imaging, high-end cameras |
| 16-bit | Maximum common | Professional photography, HDR images |

### Extended Range

The JPEG 2000 standard supports bit depths up to **38 bits per component**, enabling extreme precision for specialized applications.

## 16-Bit Image Support

### Creating 16-Bit Images

```swift
import J2KCore

// 16-bit grayscale image
let grayscale16 = J2KImage(
    width: 4096,
    height: 4096,
    components: 1,
    bitDepth: 16,
    signed: false
)

// 16-bit RGB image
let rgb16 = J2KImage(
    width: 4096,
    height: 4096,
    components: 3,
    bitDepth: 16,
    signed: false
)

// 16-bit RGBA image
let rgba16 = J2KImage(
    width: 4096,
    height: 4096,
    components: 4,
    bitDepth: 16,
    signed: false
)
```

### Working with 16-Bit Buffers

```swift
// Create a 16-bit image buffer
let buffer = J2KImageBuffer(width: 512, height: 512, bitDepth: 16)
var mutableBuffer = buffer

// Set pixel values (0-65535 range)
mutableBuffer.setPixel(at: 0, value: 32768)  // Mid-gray
mutableBuffer.setPixel(at: 1, value: 65535)  // White

// Retrieve values
let gray = mutableBuffer.getPixel(at: 0)  // 32768
let white = mutableBuffer.getPixel(at: 1) // 65535
```

### Benefits of 16-Bit

- **Higher precision**: 65,536 distinct values vs 256 for 8-bit
- **Reduced banding**: Smoother gradients in processed images
- **Greater dynamic range**: Better representation of shadows and highlights
- **Professional workflows**: Standard for photography and cinematography

## HDR Image Support

J2KSwift includes specialized support for High Dynamic Range (HDR) images with extended luminance values.

### HDR Color Spaces

```swift
// HDR with standard transfer function (e.g., Rec. 2020, PQ, HLG)
case hdr

// HDR with linear light encoding
case hdrLinear
```

### Creating HDR Images

```swift
// HDR10 (10-bit HDR)
let components10 = [
    J2KComponent(index: 0, bitDepth: 10, width: 1920, height: 1080),
    J2KComponent(index: 1, bitDepth: 10, width: 1920, height: 1080),
    J2KComponent(index: 2, bitDepth: 10, width: 1920, height: 1080)
]

let hdr10Image = J2KImage(
    width: 1920,
    height: 1080,
    components: components10,
    colorSpace: .hdr
)

// HDR12 (12-bit HDR)
let hdr12Image = J2KImage(
    width: 3840,
    height: 2160,
    components: 3,
    bitDepth: 12,
    signed: false
)

let hdr12 = J2KImage(
    width: hdr12Image.width,
    height: hdr12Image.height,
    components: hdr12Image.components,
    colorSpace: .hdr
)

// HDR with 16-bit precision
let hdr16Image = J2KImage(
    width: 4096,
    height: 2160,
    components: 3,
    bitDepth: 16,
    signed: false
)

let hdr16 = J2KImage(
    width: hdr16Image.width,
    height: hdr16Image.height,
    components: hdr16Image.components,
    colorSpace: .hdr
)
```

### HDR with Alpha Channel

```swift
// HDR10 with alpha
let hdrAlphaComponents = [
    J2KComponent(index: 0, bitDepth: 10, width: 1920, height: 1080),  // R
    J2KComponent(index: 1, bitDepth: 10, width: 1920, height: 1080),  // G
    J2KComponent(index: 2, bitDepth: 10, width: 1920, height: 1080),  // B
    J2KComponent(index: 3, bitDepth: 10, width: 1920, height: 1080)   // A
]

let hdrAlphaImage = J2KImage(
    width: 1920,
    height: 1080,
    components: hdrAlphaComponents,
    colorSpace: .hdr
)
```

### HDR Standards Support

J2KSwift's HDR support is compatible with:

- **Rec. 2020**: Wide color gamut for UHDTV
- **Rec. 2100 (HLG)**: Hybrid Log-Gamma for broadcast
- **Rec. 2100 (PQ)**: Perceptual Quantization for streaming
- **SMPTE ST 2084**: PQ transfer function
- **ARIB STD-B67**: HLG transfer function

### Linear HDR

For compositing and VFX work, use linear HDR encoding:

```swift
let linearComponents = [
    J2KComponent(index: 0, bitDepth: 16, width: 1920, height: 1080),
    J2KComponent(index: 1, bitDepth: 16, width: 1920, height: 1080),
    J2KComponent(index: 2, bitDepth: 16, width: 1920, height: 1080)
]

let linearHDR = J2KImage(
    width: 1920,
    height: 1080,
    components: linearComponents,
    colorSpace: .hdrLinear
)
```

## Extended Precision Modes

### 10-Bit Precision

10-bit images provide 1,024 levels per component, ideal for HDR10 and broadcast video:

```swift
let image10bit = J2KImage(
    width: 1920,
    height: 1080,
    components: 3,
    bitDepth: 10,
    signed: false
)

// Value range: 0-1023
let buffer10 = J2KImageBuffer(width: 100, height: 100, bitDepth: 10)
var mutable10 = buffer10
mutable10.setPixel(at: 0, value: 512)  // Mid-value
```

### 12-Bit Precision

12-bit images provide 4,096 levels, common in medical imaging and RAW photography:

```swift
let image12bit = J2KImage(
    width: 2048,
    height: 2048,
    components: 3,
    bitDepth: 12,
    signed: false
)

// Value range: 0-4095
let buffer12 = J2KImageBuffer(width: 100, height: 100, bitDepth: 12)
var mutable12 = buffer12
mutable12.setPixel(at: 0, value: 2048)  // Mid-value
```

### 14-Bit Precision

14-bit images provide 16,384 levels, used in high-end cameras and scientific imaging:

```swift
let image14bit = J2KImage(
    width: 4096,
    height: 4096,
    components: 3,
    bitDepth: 14,
    signed: false
)

// Value range: 0-16383
let buffer14 = J2KImageBuffer(width: 100, height: 100, bitDepth: 14)
var mutable14 = buffer14
mutable14.setPixel(at: 0, value: 8192)  // Mid-value
```

## Alpha Channel Support

J2KSwift provides complete support for alpha channels (transparency) in images.

### RGBA Images

```swift
// 8-bit RGBA
let rgba8Components = [
    J2KComponent(index: 0, bitDepth: 8, width: 512, height: 512),  // R
    J2KComponent(index: 1, bitDepth: 8, width: 512, height: 512),  // G
    J2KComponent(index: 2, bitDepth: 8, width: 512, height: 512),  // B
    J2KComponent(index: 3, bitDepth: 8, width: 512, height: 512)   // A
]

let rgba8Image = J2KImage(
    width: 512,
    height: 512,
    components: rgba8Components,
    colorSpace: .sRGB
)

// 16-bit RGBA
let rgba16Image = J2KImage(
    width: 1024,
    height: 768,
    components: 4,
    bitDepth: 16,
    signed: false
)
```

### Grayscale with Alpha

```swift
let grayAlphaComponents = [
    J2KComponent(index: 0, bitDepth: 8, width: 640, height: 480),  // Gray
    J2KComponent(index: 1, bitDepth: 8, width: 640, height: 480)   // Alpha
]

let grayAlphaImage = J2KImage(
    width: 640,
    height: 480,
    components: grayAlphaComponents,
    colorSpace: .grayscale
)
```

### Mixed Bit Depth Alpha

You can use different bit depths for color and alpha channels:

```swift
let mixedComponents = [
    J2KComponent(index: 0, bitDepth: 8, width: 256, height: 256),   // R (8-bit)
    J2KComponent(index: 1, bitDepth: 8, width: 256, height: 256),   // G (8-bit)
    J2KComponent(index: 2, bitDepth: 8, width: 256, height: 256),   // B (8-bit)
    J2KComponent(index: 3, bitDepth: 16, width: 256, height: 256)   // A (16-bit)
]

let mixedImage = J2KImage(
    width: 256,
    height: 256,
    components: mixedComponents
)
```

### Alpha Modes

J2KSwift supports both standard alpha modes:

1. **Straight Alpha**: Color and alpha are independent
2. **Premultiplied Alpha**: Color values are pre-multiplied by alpha

The alpha mode is determined by the file format metadata (e.g., JP2 channel definition box).

## Signed Values

J2KSwift supports signed component values for specialized applications:

```swift
// Signed 8-bit (range: -128 to 127)
let signed8 = J2KImage(
    width: 256,
    height: 256,
    components: 1,
    bitDepth: 8,
    signed: true
)

// Signed 16-bit (range: -32768 to 32767)
let signed16 = J2KImage(
    width: 512,
    height: 512,
    components: 3,
    bitDepth: 16,
    signed: true
)
```

Signed values are useful for:
- Differential images
- Displacement maps
- Error maps
- Scientific data

## Complex Multi-Component Images

J2KSwift supports arbitrary multi-component images:

```swift
// Example: RGB + Alpha + Depth
let complexComponents = [
    J2KComponent(index: 0, bitDepth: 10, width: 1920, height: 1080),  // R
    J2KComponent(index: 1, bitDepth: 10, width: 1920, height: 1080),  // G
    J2KComponent(index: 2, bitDepth: 10, width: 1920, height: 1080),  // B
    J2KComponent(index: 3, bitDepth: 8, width: 1920, height: 1080),   // A
    J2KComponent(index: 4, bitDepth: 16, width: 1920, height: 1080)   // Depth
]

let complexImage = J2KImage(
    width: 1920,
    height: 1080,
    components: complexComponents
)
```

This flexibility enables:
- RGBD images (color + depth)
- Multi-spectral imagery
- Custom channel configurations
- Scientific data formats

## Buffer Size Calculations

The buffer size for extended formats is automatically calculated:

```swift
let buffer = J2KImageBuffer(width: 512, height: 512, bitDepth: 16)

// Pixels in buffer
let pixelCount = buffer.count  // 512 * 512 = 262,144

// Bytes per pixel
let bytesPerPixel = (16 + 7) / 8  // 2 bytes for 16-bit

// Total size in bytes
let sizeInBytes = buffer.sizeInBytes  // 524,288 bytes (512 KB)
```

### Storage Requirements

| Bit Depth | Bytes per Pixel | 1920×1080 Image | 4096×2160 Image |
|-----------|-----------------|-----------------|-----------------|
| 8-bit | 1 | 2.07 MB | 8.85 MB |
| 10-bit | 2 | 4.15 MB | 17.7 MB |
| 12-bit | 2 | 4.15 MB | 17.7 MB |
| 16-bit | 2 | 4.15 MB | 17.7 MB |

*Note: Actual JPEG 2000 compressed sizes will be significantly smaller due to compression.*

## Performance Considerations

### Memory Usage

Extended formats require more memory:

- **16-bit**: 2× memory vs 8-bit
- **10/12/14-bit**: Also use 2 bytes per pixel (rounded up)
- **Alpha channels**: Add 25-33% more memory (RGBA vs RGB)

### Processing Speed

- Processing time scales roughly linearly with bit depth
- Hardware acceleration (via J2KAccelerate) works with all bit depths
- Alpha channel processing adds minimal overhead

### Recommendations

1. **Use appropriate precision**: Don't use 16-bit if 10-bit suffices
2. **Consider compression**: JPEG 2000 compresses extended formats efficiently
3. **Enable hardware acceleration**: Significant speedup on Apple platforms
4. **Use tiling**: For large extended format images, tiling improves memory efficiency

## File Format Support

### JP2 Box Support

Extended formats are fully supported in JP2 files:

- **Bits Per Component Box (bpcc)**: Stores variable bit depths
- **Color Specification Box (colr)**: Defines color space (including HDR)
- **Channel Definition Box (cdef)**: Defines alpha and other channels
- **Component Mapping Box (cmap)**: Maps components to channels

### Example JP2 Structure

```
JP2 File
├── Signature Box (jP)
├── File Type Box (ftyp)
└── JP2 Header Box (jp2h)
    ├── Image Header Box (ihdr)
    ├── Bits Per Component Box (bpcc)  ← Variable bit depths
    ├── Color Specification Box (colr) ← HDR color space
    └── Channel Definition Box (cdef)  ← Alpha channel
```

## Testing

J2KSwift includes comprehensive tests for extended formats:

```swift
// Run extended format tests
swift test --filter J2KExtendedFormatsTests
```

Test coverage includes:
- All supported bit depths (1-38 bits)
- 16-bit image operations
- HDR color spaces
- Alpha channel configurations
- Signed and unsigned values
- Buffer size calculations
- Round-trip encoding/decoding

## Best Practices

### Choosing Bit Depth

1. **8-bit**: Web images, SDR content, general photography
2. **10-bit**: HDR10, broadcast video, high-quality video
3. **12-bit**: RAW photography, medical imaging, archival
4. **14-bit**: High-end cameras, scientific imaging
5. **16-bit**: Professional workflows, extreme precision

### Choosing Color Space

1. **sRGB**: Standard web and display content
2. **YCbCr**: Video content, efficient compression
3. **HDR**: High dynamic range content for HDR displays
4. **HDR Linear**: Compositing, VFX, physically-based rendering
5. **ICC Profile**: Custom color spaces, specialized workflows

### Alpha Channel Guidelines

1. Use **straight alpha** for most applications
2. Use **premultiplied alpha** for compositing workflows
3. Match alpha bit depth to color channels for consistency
4. Consider higher precision alpha (16-bit) for VFX work

## Examples

### HDR10 Video Frame

```swift
import J2KCore

let hdr10Frame = J2KImage(
    width: 1920,
    height: 1080,
    components: 3,
    bitDepth: 10,
    signed: false
)

let hdrImage = J2KImage(
    width: hdr10Frame.width,
    height: hdr10Frame.height,
    components: hdr10Frame.components,
    colorSpace: .hdr
)
```

### Professional Photography (16-bit RGB)

```swift
let proPhoto = J2KImage(
    width: 7360,
    height: 4912,
    components: 3,
    bitDepth: 16,
    signed: false
)
```

### Medical Imaging (12-bit Grayscale)

```swift
let medicalImage = J2KImage(
    width: 2048,
    height: 2048,
    components: 1,
    bitDepth: 12,
    signed: false
)
```

### VFX with Linear HDR and Alpha

```swift
let vfxComponents = [
    J2KComponent(index: 0, bitDepth: 16, width: 2048, height: 1556),
    J2KComponent(index: 1, bitDepth: 16, width: 2048, height: 1556),
    J2KComponent(index: 2, bitDepth: 16, width: 2048, height: 1556),
    J2KComponent(index: 3, bitDepth: 16, width: 2048, height: 1556)
]

let vfxImage = J2KImage(
    width: 2048,
    height: 1556,
    components: vfxComponents,
    colorSpace: .hdrLinear
)
```

## Limitations

### Current Limitations

1. **Floating-point values**: Currently stored as fixed-point integers
   - Planned: Native floating-point support for HDR linear
   
2. **Color transforms**: HDR-specific color transforms planned for future releases
   - Current: Standard RCT/ICT transforms work with HDR

3. **Tone mapping**: Not included (application-level concern)

### Future Enhancements

Planned improvements for future releases:
- Native floating-point pixel data (FP16, FP32)
- HDR-specific color transforms
- Advanced alpha blending modes
- ACES color space support
- Display mapping hints

## References

### Standards

- **JPEG 2000 Part 1** (ISO/IEC 15444-1): Core coding system
- **Rec. ITU-R BT.2020**: UHDTV color space
- **Rec. ITU-R BT.2100**: HDR and wide color gamut
- **SMPTE ST 2084**: PQ EOTF for HDR
- **ARIB STD-B67**: HLG for HDR broadcasting

### Related Documentation

- [QUANTIZATION.md](QUANTIZATION.md): Quantization for extended bit depths
- [COLOR_TRANSFORM.md](COLOR_TRANSFORM.md): Color space conversions
- [JP2_FILE_FORMAT.md](JP2_FILE_FORMAT.md): File format support
- [HARDWARE_ACCELERATION.md](HARDWARE_ACCELERATION.md): Performance optimization

## Conclusion

J2KSwift's extended format support enables modern imaging workflows with:
- Complete 16-bit image support
- HDR content with extended dynamic range
- Flexible bit depth options (1-38 bits)
- Full alpha channel support
- Professional-grade precision

This makes J2KSwift suitable for:
- Professional photography
- Video production and streaming
- Medical and scientific imaging
- VFX and compositing
- High-end display technologies

---

**Last Updated**: 2026-02-07  
**Version**: 1.0  
**Status**: Complete ✅
