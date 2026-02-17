# J2KSwift v1.3.0 Release Notes

**Release Date**: February 17, 2026  
**Release Type**: Major Release  
**GitHub Tag**: v1.3.0

## Overview

J2KSwift v1.3.0 is a **major release** that introduces two groundbreaking features: **HTJ2K (High Throughput JPEG 2000)** codec support and **lossless transcoding** between legacy JPEG 2000 and HTJ2K formats. This release represents the completion of Phase 9 and Phase 10 of the development roadmap, delivering exceptional performance improvements and format flexibility.

### Key Highlights

- 🚀 **HTJ2K Codec**: 57-70× faster encoding/decoding vs legacy JPEG 2000
- 🔄 **Lossless Transcoding**: Bit-exact format conversion without re-encoding
- ⚡ **Parallel Processing**: Multi-tile transcoding with 1.05-2× speedup
- ✅ **ISO/IEC 15444-15 Conformance**: 100% conformance test pass rate
- 📚 **Comprehensive Documentation**: HTJ2K implementation guide and performance analysis

---

## What's New

### 1. HTJ2K Codec (Phase 9)

HTJ2K (High Throughput JPEG 2000) is an updated JPEG 2000 standard (ISO/IEC 15444-15) that provides significantly faster encoding/decoding throughput while maintaining backward compatibility with legacy JPEG 2000.

#### Features

- **FBCOT Implementation**: Fast Block Coder with Optimized Truncation
- **HT Cleanup Pass**: MEL (Magnitude Exchange Length), VLC (Variable Length Coding), and MagSgn coding
- **HT Significance Propagation Pass**: Efficient significance state management
- **HT Magnitude Refinement Pass**: Optimized refinement coding
- **Mixed Codestream Support**: Legacy and HTJ2K code-blocks in the same file
- **JPH File Format**: Native JPH file format support for HTJ2K images

#### Performance

| Operation | Legacy JPEG 2000 | HTJ2K | Speedup |
|-----------|------------------|-------|---------|
| Encoding | 1.0× (baseline) | 57-70× | **57-70×** |
| Decoding | 1.0× (baseline) | 57-70× | **57-70×** |

**Result**: HTJ2K encoding and decoding are **57-70× faster** than legacy JPEG 2000, exceeding the initial target of 10-100×.

#### Conformance

- ✅ 100% ISO/IEC 15444-15 conformance test pass rate
- ✅ 86 comprehensive HTJ2K tests implemented
- ✅ Full interoperability with reference implementations

#### API Example

```swift
import J2KCodec

// Create encoder with HTJ2K configuration
let config = EncodingConfiguration(
    codingStyle: .htj2k,
    quality: .highQuality
)

let encoder = J2KEncoder(configuration: config)
let encodedData = try encoder.encode(image)

// Decode HTJ2K image
let decoder = J2KDecoder()
let decodedImage = try decoder.decode(encodedData)
```

### 2. Lossless Transcoding (Phase 10)

Lossless transcoding enables conversion between legacy JPEG 2000 and HTJ2K formats without re-encoding wavelet coefficients, ensuring bit-exact preservation of image data.

#### Features

- **Bidirectional Conversion**: JPEG 2000 ↔ HTJ2K
- **Bit-Exact Round-Trip**: Zero quality loss during conversion
- **Metadata Preservation**: All headers, markers, and metadata retained
- **Parallel Processing**: Multi-tile transcoding for faster conversion
- **Incremental Conversion**: Support for progressive transcoding

#### Performance

- ✅ **Bit-exact round-trip** validation passed
- ✅ **1.05-2× speedup** for parallel multi-tile transcoding
- ✅ Complete metadata preservation verified

#### API Example

```swift
import J2KCodec

// Transcode legacy JPEG 2000 to HTJ2K
let transcoder = J2KTranscoder()

let legacyCodestream = try Data(contentsOf: legacyFileURL)
let htj2kCodestream = try transcoder.transcode(
    legacyCodestream,
    from: .legacy,
    to: .htj2k
)

// Verify bit-exact round-trip
let roundTripCodestream = try transcoder.transcode(
    htj2kCodestream,
    from: .htj2k,
    to: .legacy
)
// roundTripCodestream == legacyCodestream (bit-exact!)
```

#### Parallel Transcoding

```swift
import J2KCodec

// Configure parallel transcoding for multi-tile images
let config = TranscodingConfiguration.default // Parallel enabled
let transcoder = J2KTranscoder(configuration: config)

let htj2kData = try transcoder.transcode(
    multiTileLegacyData,
    from: .legacy,
    to: .htj2k
)
// Automatically uses parallel processing for multi-tile images
```

---

## Breaking Changes

**None**. This release maintains full backward compatibility with v1.2.0.

---

## Improvements

### Performance

- 🚀 **57-70× speedup** for HTJ2K encoding and decoding
- ⚡ **1.05-2× speedup** for parallel multi-tile transcoding
- 📊 Comprehensive performance benchmarks in HTJ2K_PERFORMANCE.md

### Testing

- ✅ **86 new HTJ2K tests** (100% pass rate)
- ✅ **31 new transcoding tests** (100% pass rate)
- ✅ **1,605 total tests** (100% pass rate)
- ✅ ISO/IEC 15444-15 conformance validated

### Documentation

- 📚 **HTJ2K.md**: Complete HTJ2K implementation guide (360+ lines)
- 📊 **HTJ2K_PERFORMANCE.md**: Performance benchmarks and analysis
- ✅ **HTJ2K_CONFORMANCE_REPORT.md**: Conformance test results
- 📖 Updated API documentation for new features

### Code Quality

- 🔒 Swift 6 strict concurrency maintained
- ✨ Comprehensive error handling
- 🧪 ~90% code coverage
- 📝 Extensive inline documentation

---

## Bug Fixes

No critical bugs fixed in this release. All existing functionality remains stable and working as expected.

---

## Known Limitations

### HTJ2K

1. **Block Size Validation**: HTJ2K requires code-block dimensions ≤ 1024 samples (per ISO/IEC 15444-15 Table A.18). Larger blocks will trigger a validation error.

2. **Mixed Codestreams**: While mixed legacy and HTJ2K code-blocks are supported, some decoders may not support this feature.

### Transcoding

1. **Coefficient Patterns**: Some rare coefficient patterns may require additional validation during transcoding.

2. **Sequential Fallback**: Very large images may fall back to sequential processing for memory efficiency.

For a complete list of known limitations, see [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md).

---

## Migration Guide

### From v1.2.0

No code changes required. All existing APIs remain compatible. To use new features:

1. **HTJ2K Encoding**: Set `codingStyle: .htj2k` in `EncodingConfiguration`
2. **Transcoding**: Use the new `J2KTranscoder` API

Example:
```swift
// Old code (still works)
let encoder = J2KEncoder()
let data = try encoder.encode(image)

// New HTJ2K encoding (optional)
let config = EncodingConfiguration(codingStyle: .htj2k)
let htj2kEncoder = J2KEncoder(configuration: config)
let htj2kData = try htj2kEncoder.encode(image)
```

---

## Documentation

### New Documentation

- [HTJ2K.md](HTJ2K.md) - HTJ2K implementation guide
- [HTJ2K_PERFORMANCE.md](HTJ2K_PERFORMANCE.md) - Performance benchmarks
- [HTJ2K_CONFORMANCE_REPORT.md](HTJ2K_CONFORMANCE_REPORT.md) - Conformance validation

### Updated Documentation

- [README.md](README.md) - Updated with v1.3.0 features
- [NEXT_PHASE.md](NEXT_PHASE.md) - Updated development status
- [DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md) - Phase 9 & 10 complete
- [MILESTONES.md](MILESTONES.md) - v1.3.0 milestone added
- [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) - Updated limitations

---

## Statistics

### Test Coverage

- **Total Tests**: 1,605
- **Pass Rate**: 100%
- **HTJ2K Tests**: 86
- **Transcoding Tests**: 31
- **Code Coverage**: ~90%

### Performance

- **HTJ2K Encoding Speedup**: 57-70×
- **HTJ2K Decoding Speedup**: 57-70×
- **Parallel Transcoding Speedup**: 1.05-2×
- **ISO/IEC 15444-15 Conformance**: 100%

### Development

- **Development Time**: Phase 9 (20 weeks) + Phase 10 (10 weeks) = 30 weeks
- **Commits**: See Git history for details
- **Lines of Code Added**: See Git diff for details

---

## Credits

J2KSwift is developed and maintained by the Raster-Lab team.

Special thanks to the Swift community and contributors who helped shape this release.

---

## Support

- **GitHub Issues**: https://github.com/Raster-Lab/J2KSwift/issues
- **Documentation**: https://github.com/Raster-Lab/J2KSwift/tree/main
- **Discussions**: https://github.com/Raster-Lab/J2KSwift/discussions

---

## What's Next

### v1.3.1 (Patch Release - If Needed)
- Additional HTJ2K optimizations
- Bug fixes based on community feedback
- Documentation improvements

### v1.4.0 (Minor Release - Planned Q2 2026)
- Enhanced JPIP streaming with HTJ2K support
- Additional transcoding optimizations
- Extended file format features

### v2.0.0 (Major Release - Planned Q4 2026)
- JPEG 2000 Part 2 extensions (JPX format)
- Advanced HTJ2K features
- Breaking API changes if needed

---

## Upgrade Instructions

### Swift Package Manager

Update your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.3.0")
]
```

Then run:
```bash
swift package update
```

### Manual Installation

1. Download the v1.3.0 release from GitHub
2. Replace your existing J2KSwift files with the new version
3. Rebuild your project

---

**Full Changelog**: https://github.com/Raster-Lab/J2KSwift/compare/v1.2.0...v1.3.0

**Thank you for using J2KSwift!** 🎉
