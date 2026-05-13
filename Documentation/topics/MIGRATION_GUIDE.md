# Migration Guide: From OpenJPEG to J2KSwift

A comprehensive guide for migrating from OpenJPEG (or other JPEG 2000 libraries) to J2KSwift.

## Table of Contents

- [Introduction](#introduction)
- [Key Differences](#key-differences)
- [API Comparison](#api-comparison)
- [Code Migration Examples](#code-migration-examples)
- [Feature Mapping](#feature-mapping)
- [Performance Considerations](#performance-considerations)
- [Common Pitfalls](#common-pitfalls)
- [Migration Checklist](#migration-checklist)

## Introduction

This guide helps you migrate from OpenJPEG (or similar C-based JPEG 2000 libraries) to J2KSwift's modern Swift 6 API.

### Why Migrate to J2KSwift?

**Advantages:**
- **Type Safety**: Swift's strong type system prevents common errors
- **Memory Safety**: No manual memory management
- **Concurrency**: Built-in async/await support
- **Modern API**: Intuitive, Swift-native design
- **Cross-Platform**: Works on all Apple platforms + Linux

**Considerations:**
- **Maturity**: J2KSwift is newer than OpenJPEG
- **Feature Parity**: Some advanced features may not be available yet
- **Performance**: Comparable performance with hardware acceleration

## Key Differences

### Language and Philosophy

| Aspect | OpenJPEG | J2KSwift |
|--------|----------|----------|
| Language | C | Swift 6 |
| Memory | Manual (`malloc`/`free`) | Automatic (ARC) |
| Error Handling | Error codes | Swift `throws` |
| Concurrency | Manual threading | `async`/`await`, actors |
| Type Safety | Weak (C pointers) | Strong (Swift types) |
| Nullability | Implicit | Explicit (`Optional`) |

### API Design

| Aspect | OpenJPEG | J2KSwift |
|--------|----------|----------|
| Configuration | Function calls | Structs with defaults |
| Image Data | Pointers to structs | Value types |
| Streams | Callbacks | Swift I/O |
| Threading | Manual | Built-in parallelization |

## API Comparison

### Basic Types

#### OpenJPEG
```c
opj_image_t *image;
opj_cparameters_t parameters;
opj_dparameters_t dparameters;
opj_codec_t *codec;
opj_stream_t *stream;
```

#### J2KSwift
```swift
let image: J2KImage
let config: J2KConfiguration
let encoder: J2KEncoder
let decoder: J2KDecoder
```

### Creating an Image

#### OpenJPEG
```c
opj_image_cmptparm_t cmptparm[3];
opj_image_t *image;

// Setup component parameters
for (int i = 0; i < 3; i++) {
    cmptparm[i].dx = 1;
    cmptparm[i].dy = 1;
    cmptparm[i].w = width;
    cmptparm[i].h = height;
    cmptparm[i].prec = 8;
    cmptparm[i].bpp = 8;
    cmptparm[i].sgnd = 0;
}

// Create image
image = opj_image_create(3, &cmptparm[0], OPJ_CLRSPC_SRGB);
image->x0 = 0;
image->y0 = 0;
image->x1 = width;
image->y1 = height;
```

#### J2KSwift
```swift
// Simple creation
let image = J2KImage(
    width: width,
    height: height,
    components: 3,
    bitDepth: 8
)

// Or with explicit components
let components = [
    J2KComponent(index: 0, bitDepth: 8, width: width, height: height),
    J2KComponent(index: 1, bitDepth: 8, width: width, height: height),
    J2KComponent(index: 2, bitDepth: 8, width: width, height: height)
]
let image = J2KImage(
    width: width,
    height: height,
    components: components,
    colorSpace: .sRGB
)
```

### Encoding

#### OpenJPEG
```c
opj_codec_t *codec = opj_create_compress(OPJ_CODEC_JP2);
opj_cparameters_t parameters;
opj_stream_t *stream;

// Set default parameters
opj_set_default_encoder_parameters(&parameters);

// Customize
parameters.tcp_numlayers = 1;
parameters.cp_disto_alloc = 1;
parameters.tcp_rates[0] = 10;
parameters.cp_comment = (char *)"Created by OpenJPEG";

// Setup codec
opj_setup_encoder(codec, &parameters, image);

// Create stream
stream = opj_stream_create_default_file_stream(output_file, OPJ_FALSE);

// Encode
opj_start_compress(codec, image, stream);
opj_encode(codec, stream);
opj_end_compress(codec, stream);

// Cleanup
opj_stream_destroy(stream);
opj_destroy_codec(codec);
opj_image_destroy(image);
```

#### J2KSwift
```swift
// Configure
let config = J2KConfiguration(
    quality: 0.9,
    compressionRatio: 10
)

// Encode
let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)

// Save to file
try data.write(to: outputURL)

// No manual cleanup needed!
```

### Decoding

#### OpenJPEG
```c
opj_codec_t *codec = opj_create_decompress(OPJ_CODEC_JP2);
opj_dparameters_t parameters;
opj_stream_t *stream;
opj_image_t *image = NULL;

// Set default parameters
opj_set_default_decoder_parameters(&parameters);

// Setup codec
opj_setup_decoder(codec, &parameters);

// Create stream
stream = opj_stream_create_default_file_stream(input_file, OPJ_TRUE);

// Decode header
opj_read_header(stream, codec, &image);

// Decode image
opj_decode(codec, stream, image);
opj_end_decompress(codec, stream);

// Use image...

// Cleanup
opj_stream_destroy(stream);
opj_destroy_codec(codec);
opj_image_destroy(image);
```

#### J2KSwift
```swift
// Load data
let data = try Data(contentsOf: inputURL)

// Decode
let decoder = J2KDecoder()
let image = try decoder.decode(data)

// Use image...

// No manual cleanup needed!
```

## Code Migration Examples

### Example 1: Basic Encoding

#### Before (OpenJPEG)
```c
#include <openjpeg.h>

void encode_image(const char *output_file, 
                  unsigned char *rgb_data, 
                  int width, int height) {
    opj_cparameters_t parameters;
    opj_image_cmptparm_t cmptparm[3];
    opj_image_t *image = NULL;
    opj_codec_t *codec = NULL;
    opj_stream_t *stream = NULL;
    
    // Initialize parameters
    opj_set_default_encoder_parameters(&parameters);
    parameters.cp_disto_alloc = 1;
    parameters.tcp_rates[0] = 10.0f;
    parameters.tcp_numlayers = 1;
    
    // Setup components
    memset(&cmptparm[0], 0, sizeof(cmptparm));
    for (int i = 0; i < 3; i++) {
        cmptparm[i].prec = 8;
        cmptparm[i].bpp = 8;
        cmptparm[i].sgnd = 0;
        cmptparm[i].dx = 1;
        cmptparm[i].dy = 1;
        cmptparm[i].w = width;
        cmptparm[i].h = height;
    }
    
    // Create image
    image = opj_image_create(3, &cmptparm[0], OPJ_CLRSPC_SRGB);
    image->x0 = 0;
    image->y0 = 0;
    image->x1 = width;
    image->y1 = height;
    
    // Fill image data
    for (int i = 0; i < width * height; i++) {
        image->comps[0].data[i] = rgb_data[i * 3 + 0];  // R
        image->comps[1].data[i] = rgb_data[i * 3 + 1];  // G
        image->comps[2].data[i] = rgb_data[i * 3 + 2];  // B
    }
    
    // Create codec
    codec = opj_create_compress(OPJ_CODEC_JP2);
    opj_setup_encoder(codec, &parameters, image);
    
    // Create stream
    stream = opj_stream_create_default_file_stream(output_file, OPJ_FALSE);
    
    // Encode
    opj_start_compress(codec, image, stream);
    opj_encode(codec, stream);
    opj_end_compress(codec, stream);
    
    // Cleanup
    opj_stream_destroy(stream);
    opj_destroy_codec(codec);
    opj_image_destroy(image);
}
```

#### After (J2KSwift)
```swift
import J2KCore
import J2KCodec

func encodeImage(outputURL: URL, rgbData: [UInt8], width: Int, height: Int) throws {
    // Create image
    let image = J2KImage(width: width, height: height, components: 3, bitDepth: 8)
    
    // Fill image data
    for i in 0..<(width * height) {
        image.components[0].buffer.setValue(Int32(rgbData[i * 3 + 0]), at: i)  // R
        image.components[1].buffer.setValue(Int32(rgbData[i * 3 + 1]), at: i)  // G
        image.components[2].buffer.setValue(Int32(rgbData[i * 3 + 2]), at: i)  // B
    }
    
    // Configure and encode
    let config = J2KConfiguration(compressionRatio: 10)
    let encoder = J2KEncoder(configuration: config)
    let data = try encoder.encode(image)
    
    // Save
    try data.write(to: outputURL)
    
    // Automatic cleanup via ARC!
}
```

### Example 2: Decoding with ROI

#### Before (OpenJPEG)
```c
// OpenJPEG doesn't have built-in ROI decoding
// You need to decode the full image and extract the region

opj_image_t *decode_roi(const char *input_file, 
                        int x, int y, int w, int h) {
    opj_codec_t *codec = opj_create_decompress(OPJ_CODEC_JP2);
    opj_dparameters_t parameters;
    opj_stream_t *stream;
    opj_image_t *image = NULL;
    opj_image_t *roi_image = NULL;
    
    opj_set_default_decoder_parameters(&parameters);
    
    // Set decode area (if supported by version)
    parameters.DA_x0 = x;
    parameters.DA_y0 = y;
    parameters.DA_x1 = x + w;
    parameters.DA_y1 = y + h;
    
    opj_setup_decoder(codec, &parameters);
    stream = opj_stream_create_default_file_stream(input_file, OPJ_TRUE);
    
    opj_read_header(stream, codec, &image);
    opj_set_decode_area(codec, image, x, y, x + w, y + h);
    opj_decode(codec, stream, image);
    opj_end_decompress(codec, stream);
    
    // Manually extract ROI...
    
    opj_stream_destroy(stream);
    opj_destroy_codec(codec);
    
    return roi_image;
}
```

#### After (J2KSwift)
```swift
import J2KCodec

func decodeROI(inputURL: URL, x: Int, y: Int, width: Int, height: Int) throws -> J2KImage {
    // Load data
    let data = try Data(contentsOf: inputURL)
    
    // Define ROI
    let roi = J2KDecodingROI(x: x, y: y, width: width, height: height)
    
    // Decode directly
    let decoder = J2KAdvancedDecoding()
    return try decoder.decodeROI(data: data, roi: roi, strategy: .direct)
    
    // Automatic cleanup!
}
```

### Example 3: Progressive Decoding

#### Before (OpenJPEG)
```c
// OpenJPEG doesn't easily support progressive decoding
// You typically decode all at once

opj_image_t *decode_progressive(const char *input_file) {
    // Standard decode - all or nothing
    // ...
}
```

#### After (J2KSwift)
```swift
import J2KCodec

func decodeProgressive(inputURL: URL) async throws {
    let data = try Data(contentsOf: inputURL)
    let decoder = J2KAdvancedDecoding()
    let info = try decoder.getImageInfo(data: data)
    
    // Decode progressively through layers
    for layer in 0..<info.qualityLayers {
        let image = try decoder.decodeQuality(data: data, upToLayer: layer)
        
        // Update display with each layer
        await updateDisplay(image)
        
        try await Task.sleep(nanoseconds: 100_000_000)
    }
}
```

## Feature Mapping

### Encoding Features

| Feature | OpenJPEG | J2KSwift |
|---------|----------|----------|
| Lossless | `irreversible=false` | `lossless: true` |
| Quality | `tcp_rates[]` | `quality: 0.0-1.0` |
| Compression Ratio | `tcp_distoratio[]` | `compressionRatio: Int` |
| Progression Order | `prog_order` | `progressionOrder` |
| Tile Size | `cp_tdx`, `cp_tdy` | `tileWidth`, `tileHeight` |
| Code Block Size | `cblockw_init`, `cblockh_init` | `codeBlockSize` |
| Layers | `tcp_numlayers` | `layers` |
| Wavelet Levels | `numresolution` | `decompositionLevels` |
| ROI | `roi_compno`, `roi_shift` | `regionOfInterest` |

### Decoding Features

| Feature | OpenJPEG | J2KSwift |
|---------|----------|----------|
| Basic Decode | `opj_decode()` | `decoder.decode()` |
| Partial Decode | `opj_set_decode_area()` | `partialDecode()` |
| ROI Decode | Limited support | `decodeROI()` |
| Resolution Levels | `cp_reduce` | `decodeResolution()` |
| Layer Selection | `cp_layer` | `decodeQuality()` |
| Progressive | Not directly supported | `decodeQuality()`, `decodeResolution()` |
| Incremental | Not supported | `createIncrementalDecoder()` |

## Performance Considerations

### Memory Management

**OpenJPEG:**
```c
// Manual allocation
opj_image_t *image = opj_image_create(...);
// ... use image ...
opj_image_destroy(image);  // Must remember!
```

**J2KSwift:**
```swift
// Automatic memory management
let image = J2KImage(...)
// ... use image ...
// Automatically cleaned up by ARC
```

### Threading

**OpenJPEG:**
```c
// Manual threading with pthreads or platform APIs
pthread_t threads[4];
for (int i = 0; i < 4; i++) {
    pthread_create(&threads[i], NULL, encode_tile, &data[i]);
}
```

**J2KSwift:**
```swift
// Built-in parallelization
await withTaskGroup(of: Data.self) { group in
    for tile in tiles {
        group.addTask {
            return try! encoder.encode(tile)
        }
    }
}
```

### Hardware Acceleration

**OpenJPEG:**
- No built-in hardware acceleration
- Must use external libraries

**J2KSwift:**
```swift
// Automatic hardware acceleration on Apple platforms
let encoder = J2KEncoder(configuration: config)
// Automatically uses Accelerate framework when available
```

## Common Pitfalls

### 1. Error Handling

**Pitfall:**
```swift
// Don't ignore errors!
let data = try? encoder.encode(image)
// data is nil on error, but you don't know why
```

**Solution:**
```swift
do {
    let data = try encoder.encode(image)
} catch J2KError.encodingFailed(let message) {
    print("Encoding failed: \(message)")
} catch {
    print("Error: \(error)")
}
```

### 2. Memory for Large Images

**Pitfall:**
```swift
// Loading entire 100MP image at once
let image = J2KImage(width: 10000, height: 10000, components: 3)
// High memory usage!
```

**Solution:**
```swift
// Use tiling for large images
let image = J2KImage(
    width: 10000,
    height: 10000,
    components: 3,
    tileWidth: 512,
    tileHeight: 512
)
// Tiles processed independently
```

### 3. Coordinate Systems

**Pitfall:**
```swift
// OpenJPEG uses x0, y0, x1, y1 (bounds)
// J2KSwift uses x, y, width, height (rect)
```

**Migration:**
```c
// OpenJPEG
parameters.DA_x0 = 100;
parameters.DA_y0 = 100;
parameters.DA_x1 = 300;
parameters.DA_y1 = 300;
```

```swift
// J2KSwift
let roi = J2KDecodingROI(
    x: 100,
    y: 100,
    width: 200,  // x1 - x0
    height: 200  // y1 - y0
)
```

### 4. Color Space Conversion

**Pitfall:**
```swift
// Assuming RGB when it might be YCbCr
let r = image.components[0]  // Might be Y!
```

**Solution:**
```swift
// Check color space
switch image.colorSpace {
case .sRGB:
    let r = image.components[0]
    let g = image.components[1]
    let b = image.components[2]
case .yCbCr:
    let y = image.components[0]
    let cb = image.components[1]
    let cr = image.components[2]
    // Convert if needed
default:
    print("Unknown color space")
}
```

## Migration Checklist

### Pre-Migration

- [ ] Audit current OpenJPEG usage
- [ ] Identify required features
- [ ] List performance requirements
- [ ] Document current error handling
- [ ] Measure current performance benchmarks

### During Migration

- [ ] Install J2KSwift package
- [ ] Create J2K wrapper layer (if needed)
- [ ] Migrate data structures
- [ ] Convert encoding logic
- [ ] Convert decoding logic
- [ ] Update error handling
- [ ] Add tests for each component
- [ ] Verify output compatibility

### Post-Migration

- [ ] Run performance benchmarks
- [ ] Compare output with OpenJPEG
- [ ] Test edge cases
- [ ] Update documentation
- [ ] Remove OpenJPEG dependency
- [ ] Code review
- [ ] User acceptance testing

### Testing Checklist

- [ ] Encoding produces valid JP2 files
- [ ] Decoding handles all supported formats
- [ ] ROI encoding/decoding works correctly
- [ ] Progressive modes function properly
- [ ] Error handling is comprehensive
- [ ] Memory usage is acceptable
- [ ] Performance meets requirements
- [ ] Cross-platform compatibility verified

## Migration Strategy

### Gradual Migration

1. **Parallel Implementation**
   - Keep OpenJPEG code
   - Add J2KSwift alongside
   - Compare outputs

2. **Feature-by-Feature**
   - Migrate one feature at a time
   - Test thoroughly
   - Keep fallback to OpenJPEG

3. **Complete Migration**
   - Replace all OpenJPEG calls
   - Remove OpenJPEG dependency
   - Finalize tests

### Wrapper Approach

Create a wrapper to ease migration:

```swift
class JPEG2000Wrapper {
    private let encoder = J2KEncoder()
    private let decoder = J2KDecoder()
    
    // OpenJPEG-like interface
    func compress(
        rgbData: [UInt8],
        width: Int,
        height: Int,
        quality: Float
    ) throws -> Data {
        let image = J2KImage(width: width, height: height, components: 3)
        
        // Fill data...
        
        let config = J2KConfiguration(quality: Double(quality))
        let encoder = J2KEncoder(configuration: config)
        return try encoder.encode(image)
    }
    
    func decompress(_ data: Data) throws -> (rgb: [UInt8], width: Int, height: Int) {
        let image = try decoder.decode(data)
        
        // Extract RGB...
        
        return (rgb: rgbData, width: image.width, height: image.height)
    }
}
```

## Next Steps

- [Getting Started Guide](GETTING_STARTED.md)
- [Encoding Tutorial](TUTORIAL_ENCODING.md)
- [Decoding Tutorial](TUTORIAL_DECODING.md)
- [API Reference](API_REFERENCE.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)

---

**Status**: Migration Guide for Phase 8 (Production Ready)  
**Last Updated**: 2026-02-07
