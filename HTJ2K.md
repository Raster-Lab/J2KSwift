# HTJ2K (High-Throughput JPEG 2000) Implementation

**ISO/IEC 15444-15 Support in J2KSwift**

## Overview

HTJ2K (High-Throughput JPEG 2000) is an updated JPEG 2000 standard defined in ISO/IEC 15444-15 that provides significantly faster encoding and decoding throughput while maintaining compatibility with the JPEG 2000 codestream structure. J2KSwift includes comprehensive HTJ2K support starting from v1.1.0.

## Key Features

### 1. Fast Block Coding (FBCOT)

HTJ2K replaces the traditional EBCOT (Embedded Block Coding with Optimized Truncation) Tier-1 coding with the FBCOT (Fast Block Coder with Optimized Truncation) algorithm, which uses three distinct coding primitives:

- **MEL (Magnitude Exchange Length)**: Run-length coding for significance context
- **VLC (Variable Length Coding)**: Fixed-to-variable coding for significance/sign
- **MagSgn (Magnitude and Sign)**: Raw magnitude and sign bits

This results in 10-100× faster encoding/decoding throughput compared to legacy JPEG 2000.

### 2. HT Set Extensions

HTJ2K introduces HT set parameters in codestream markers to signal HTJ2K-specific configuration. These are encoded in the COD and COC markers:

#### Scod Byte (COD Marker)

Bits 3-4 of the Scod byte signal HT set presence:

| Bits 3-4 | Meaning |
|----------|---------|
| `00` | No HT sets (legacy JPEG 2000) |
| `01` | HT set A (default for HTJ2K) |
| `10` | HT set B |
| `11` | HT sets C and D |

When HTJ2K mode is enabled, J2KSwift uses HT set A (`01`) as the default configuration.

#### HT Set Configuration Byte

When HT sets are present, an additional configuration byte follows the wavelet transform type in the COD/COC markers:

| Bit | Function |
|-----|----------|
| 0-3 | Reserved (set to 0) |
| 4 | Lossless flag (0 = lossy, 1 = lossless) |
| 5-7 | Reserved (set to 0) |

### 3. JPH File Format

HTJ2K files use the JPH file format, which is a JP2-based container with the `'jph '` brand in the file type box:

```
JP2 Signature Box (jP\x20\x20\x0D\x0A\x87\x0A)
File Type Box (ftyp)
  ├─ Brand: 'jph ' (HTJ2K)
  ├─ Minor Version: 0
  └─ Compatible Brands: ['jph ', 'jp2 ']
JP2 Header Box (jp2h)
  ├─ Image Header (ihdr)
  ├─ Color Specification (colr)
  └─ ... other boxes
Contiguous Codestream Box (jp2c)
  └─ HTJ2K codestream with CAP marker
```

## Usage

### Encoding with HTJ2K

Use the internal `J2KEncodingConfiguration` with `useHTJ2K: true`:

```swift
import J2KCodec
import J2KCore

// Create HTJ2K configuration
let config = J2KEncodingConfiguration(
    quality: 0.95,
    lossless: false,
    decompositionLevels: 5,
    codeBlockSize: (64, 64),
    qualityLayers: 1,
    useHTJ2K: true
)

// Create encoder pipeline
let encoder = EncoderPipeline(config: config)

// Encode image
let image = try createTestImage(width: 512, height: 512, components: 3)
let codestreamData = try encoder.encode(image)
```

### Writing JPH Files

Use the `J2KFileWriter` with `.jph` format:

```swift
import J2KFileFormat
import J2KCore

// Create file writer for JPH format
let writer = J2KFileWriter(format: .jph)

// Write HTJ2K file
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
// ... fill image data ...

let config = J2KConfiguration(quality: 0.95, lossless: false)
try writer.write(image, to: fileURL, configuration: config)
```

### Detecting JPH Files

The format detector automatically identifies JPH files by their brand:

```swift
import J2KFileFormat

let detector = J2KFormatDetector()
let format = try detector.detect(at: fileURL)

if format == .jph {
    print("HTJ2K (JPH) file detected")
}
```

### Reading JPH Files

JPH files are read transparently like JP2 files:

```swift
import J2KFileFormat

let reader = J2KFileReader()
let image = try reader.read(from: fileURL)
```

## Codestream Structure

### HTJ2K Marker Segments

HTJ2K codestreams include additional marker segments:

1. **CAP (0xFF50)**: Extended capabilities marker
   - Signals HTJ2K support (Part 15 capability bit)
   - Must appear in main header before COD marker
   - 4-byte Pcap field with capability flags

2. **CPF (0xFF59)**: Corresponding profile marker
   - Specifies conformance profile
   - Includes Part 15 HTJ2K profiles

3. **COD/COC with HT Sets**: Standard coding style markers with HT set extensions

### Example Codestream Structure

```
SOC (0xFF4F)                    - Start of Codestream
SIZ (0xFF51)                    - Image and Tile Size
CAP (0xFF50)                    - Extended Capabilities (HTJ2K)
CPF (0xFF59)                    - Corresponding Profile
COD (0xFF52) + HT sets          - Coding Style Default with HT set A
QCD (0xFF5C)                    - Quantization Default
SOT (0xFF90)                    - Start of Tile-part
SOD (0xFF93)                    - Start of Data
[HTJ2K-encoded tile data]
EOC (0xFFD9)                    - End of Codestream
```

## Implementation Status

### ✅ Completed (v1.2.0 - Phase 9, Weeks 101-118)

- [x] CAP marker segment encoding/decoding
- [x] CPF marker segment encoding/decoding
- [x] COD/COC marker HT set extensions (Scod bits 3-4)
- [x] HT set configuration byte
- [x] MEL (Magnitude Exchange Length) coder
- [x] VLC (Variable Length Coding) coder
- [x] MagSgn (Magnitude and Sign) coder
- [x] HTBlockEncoder/Decoder for cleanup pass
- [x] HT significance propagation pass encoder/decoder
- [x] HT magnitude refinement pass encoder/decoder
- [x] Mixed legacy/HTJ2K codestream support
- [x] HTJ2K encoder pipeline integration
- [x] HTJ2K decoder pipeline integration
- [x] JPH file format detection and writing
- [x] Basic HTJ2K test infrastructure (67 tests)

### 🚧 In Progress (Phase 9: Weeks 116-118)

- [ ] Performance profiling and optimization
- [ ] Comprehensive benchmark suite
- [ ] Performance comparison with legacy JPEG 2000

### ⏭️ Planned (Phase 9: Weeks 119-120)

- [ ] ISO/IEC 15444-15 conformance test suite
- [ ] Interoperability testing with reference implementations
- [ ] SIMD optimizations for critical paths
- [ ] Advanced performance tuning

## Performance Characteristics

### Expected Performance Gains

When fully implemented, HTJ2K provides:

- **Encoding**: 10-100× faster than legacy JPEG 2000
- **Decoding**: 10-100× faster than legacy JPEG 2000
- **Memory**: Lower cache pressure due to simpler coding
- **Quality**: Identical compression efficiency to legacy JPEG 2000

### Current Performance (v1.2.0 - Phase 9, Week 118)

HTJ2K infrastructure is fully implemented with all encoding primitives and pipeline integration complete. Performance optimization and benchmarking are the next steps to realize the full 10-100× performance gains.

## Standards Compliance

J2KSwift's HTJ2K implementation follows:

- **ISO/IEC 15444-15**: High-Throughput JPEG 2000 (Part 15)
- **ISO/IEC 15444-1**: JPEG 2000 Part 1 (backward compatibility)

## Known Limitations

1. **Performance Optimization**: HTJ2K implementation is complete but not yet fully optimized
2. **Conformance Testing**: Full ISO/IEC 15444-15 conformance suite not yet run
3. **Benchmarking**: Comprehensive performance comparison pending
4. **SIMD Optimizations**: Advanced SIMD optimizations for critical paths not yet implemented

## Future Development

### Phase 9 Completion (Q2 2026) - 🚧 In Progress

- ✅ Complete HT pass integration
- ✅ Full FBCOT implementation
- ✅ HTJ2K encoder/decoder pipeline integration
- ⏭️ Performance optimization and benchmarking

### Phase 10: Lossless Transcoding (Q3-Q4 2026)

- Bidirectional transcoding: JPEG 2000 ↔ HTJ2K
- Metadata preservation
- Tier-1 only re-encoding (wavelet coefficients unchanged)

## References

1. **ISO/IEC 15444-15**: Information technology — JPEG 2000 image coding system: High-Throughput JPEG 2000
2. **JPEG 2000 HTJ2K White Paper**: [ISO/IEC JTC 1/SC 29/WG 1 Document WG1 N100150](https://www.iso.org/standard/82566.html)
3. **J2KSwift Documentation**: See MILESTONES.md for detailed development roadmap

## Support

For questions or issues related to HTJ2K support in J2KSwift:

1. Check the [Known Limitations](#known-limitations) section
2. Review the [MILESTONES.md](MILESTONES.md) development roadmap
3. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to report issues or contribute

---

**Last Updated**: February 16, 2026  
**Version**: 1.2.0  
**Status**: Phase 9 - HT Passes Complete, Integration 75% Complete
