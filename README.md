# J2KSwift

[![Swift Build](https://github.com/Raster-Lab/J2KSwift/actions/workflows/swift-build-test.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/swift-build-test.yml)
[![Code Quality](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml)
[![Documentation](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A pure Swift 6.2 implementation of JPEG 2000 (ISO/IEC 15444) encoding and decoding with strict concurrency support.

**Current Version**: 1.1.1 (Production Ready - Fully Functional Codec)  
**Status**: Complete encoder and decoder pipelines with 98.4% test pass rate  
**Release Date**: February 15, 2026

## 📦 Release Status

**v1.1.1** is the latest release with bug fixes, performance optimizations, and cross-platform validation:
- ✅ **Complete 7-Stage Encoder Pipeline** (preprocessing → color → wavelet → quantization → entropy → rate control → codestream)
- ✅ **Complete Decoder Pipeline** with progressive decoding (codestream → entropy → dequantization → inverse transform → image)
- ✅ **Hardware Acceleration** (vDSP integration, SIMD optimizations, parallel DWT)
- ✅ **Round-Trip Functionality** (encode → decode → verify working)
- ✅ **Multiple Encoding Presets** (lossless, fast, balanced, quality)
- ✅ **Advanced Decoding** (ROI, progressive quality/resolution, partial decoding)
- ✅ **Quality Metrics** (PSNR, SSIM, MS-SSIM)
- ✅ **JPIP Streaming** (client/server infrastructure)
- ✅ **Cross-Platform Validated** (Linux Ubuntu x86_64, macOS)
- ✅ **98.4% Test Pass Rate** (1,503 of 1,528 tests passing)

**Notable Achievement**: Full encode/decode round-trip working with comprehensive test coverage!

See [RELEASE_NOTES_v1.1.1.md](RELEASE_NOTES_v1.1.1.md) for complete details.

## 🎯 Project Goals

J2KSwift provides a modern, safe, and performant JPEG 2000 implementation for Swift applications:

- **Swift 6.2 Native**: Built with Swift 6.2's strict concurrency model
- **Fully Functional**: Complete encoder and decoder pipelines (v1.1.1)
- **Cross-Platform**: macOS 12+, iOS 15+, tvOS 15+, watchOS 8+, Linux, Windows
- **Standards Compliant**: ISO/IEC 15444-1 (JPEG 2000 Part 1) core implementation
- **Hardware Accelerated**: vDSP integration with SIMD optimizations (2-8× speedup)
- **Network Streaming**: JPIP protocol support for efficient image streaming
- **Modern API**: Async/await based APIs with comprehensive error handling
- **Well Documented**: 27+ comprehensive guides, tutorials, and API documentation
- **High Quality**: 98.3% test pass rate with comprehensive test coverage

## 🚀 Quick Start

### Requirements

- Swift 6.2 or later
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+ / visionOS 1+

### Installation

Add J2KSwift to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.1.1")
]
```

Then add the specific modules you need to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2KCodec", package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),
    ]
)
```

### Basic Usage

#### Simple Encoding (v1.1.0)

```swift
import J2KCodec

// Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)

// Encode with default settings
let encoder = J2KEncoder()
let j2kData = try encoder.encode(image)

// Or use a preset
let encoder = J2KEncoder(encodingConfiguration: .lossless)
let losslessData = try encoder.encode(image)
```

#### Simple Decoding (v1.1.0)

```swift
import J2KCodec

// Decode a JPEG 2000 file
let decoder = J2KDecoder()
let image = try decoder.decode(j2kData)

// Access decoded data
print("Decoded image: \(image.width)×\(image.height)")
print("Components: \(image.componentCount)")
```

#### Advanced Encoding with Progress (v1.1.0)

```swift
import J2KCodec

let config = J2KEncodingConfiguration.quality
let encoder = J2KEncoder(encodingConfiguration: config)

let data = try encoder.encode(image) { progress in
    print("\(progress.stage): \(progress.percentage)% complete")
}
```

#### Progressive Decoding (v1.1.0)

```swift
import J2KCodec

// Decode progressively to target quality
let options = J2KProgressiveDecodingOptions(
    mode: .quality,
    targetQuality: 0.8
)
let image = try decoder.decode(j2kData, options: options)

// Or decode a region of interest
let roiOptions = J2KROIDecodingOptions(
    region: CGRect(x: 100, y: 100, width: 200, height: 200),
    strategy: .fullQuality
)
let roiImage = try decoder.decode(j2kData, options: roiOptions)
```

#### Writing to JP2 File (v1.1.0)

```swift
import J2KCore
import J2KCodec
import J2KFileFormat

// Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)
// ... fill with image data ...

// Write as JP2 file (recommended - includes metadata)
let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: outputURL, configuration: .init(quality: 0.95))

// Or write as raw J2K codestream
let j2kWriter = J2KFileWriter(format: .j2k)
try j2kWriter.write(image, to: codestreamURL)
```

#### Decoding (v1.0 - Fully Functional)

```swift
import J2KCore
import J2KCodec

// Decode from codestream data
let decoder = J2KDecoder()
let decodedImage = try decoder.decode(codestreamData)
```

#### Reading from File (v1.0 - Fully Functional)

```swift
import J2KCore
import J2KFileFormat

// Read any JPEG 2000 format (JP2, J2K, JPX, JPM)
let reader = J2KFileReader()
let image = try reader.read(from: fileURL)

// Access image data
print("Image: \(image.width)x\(image.height), \(image.components.count) components")
```

#### Using Component APIs (Advanced)

For advanced use cases, you can also use individual components directly:

```swift
import J2KCore
import J2KCodec

// 1. Create an image
let image = J2KImage(width: 512, height: 512, components: 3, bitDepth: 8)

// 2. Apply wavelet transform
let dwt = J2KDWT2D()
let transformed = try dwt.forwardDecomposition(
    image.data,
    width: image.width,
    height: image.height,
    levels: 5
)

// 3. Quantization
let quantizer = J2KQuantizer()
let quantized = try quantizer.quantize(transformed, stepSize: 0.05)

// 4. Entropy coding
let mqCoder = J2KMQCoder()
let encoded = try mqCoder.encode(quantized)

// Result: encoded JPEG 2000 coefficient data
```


## ✨ Features

### Implemented in v1.0.0 ✅

#### Core Components
- **Image Representation**: Multi-component images with arbitrary bit depths (1-38 bits)
- **Tiling**: Configurable tile dimensions with boundary handling
- **Memory Management**: Zero-copy buffers, memory pools, optimized allocators
- **I/O Infrastructure**: Bit-level reading/writing, marker parsing, format detection

#### Wavelet Transform (Phase 2 Complete)
- **Filters**: 5/3 reversible (lossless), 9/7 irreversible (lossy)
- **Decomposition**: 1D and 2D transforms, multi-level (up to 32 levels)
- **Tiling Support**: Tile-by-tile processing with proper boundary handling
- **Test Coverage**: 96.1% pass rate (32 known issues in bit-plane decoder)

#### Entropy Coding (Phase 1 Complete)
- **EBCOT**: Embedded Block Coding with Optimized Truncation
- **MQ-Coder**: Arithmetic entropy coding (18,800+ ops/sec)
- **Bit-Plane Coding**: Three coding passes with context modeling
- **Bypass Mode**: Selective arithmetic coding bypass
- **Performance**: Optimized hot paths with inline hints

#### Quantization & Rate Control (Phase 3 Complete)
- **Quantization**: Scalar and deadzone quantization
- **Rate Control**: PCRD-opt algorithm for optimal rate-distortion
- **ROI**: MaxShift method with arbitrary shapes (rectangle, ellipse, polygon)
- **Quality Layers**: Multi-layer generation for progressive decoding

#### Color Transforms (Phase 4 Complete)
- **RCT**: Reversible Color Transform for lossless compression
- **ICT**: Irreversible Color Transform for lossy compression
- **Color Spaces**: RGB, YCbCr, Greyscale, CMYK support
- **Subsampling**: Component-level subsampling

#### File Format (Phase 5 Complete)
- **Formats**: JP2, J2K, JPX, JPM file formats
- **Boxes**: 15+ box types including header, color, palette, resolution
- **Metadata**: ICC profiles, XML, UUID boxes
- **Composition**: Multi-page and animation support (JPX/JPM)
- **Test Coverage**: 100% pass rate for file format operations

#### JPIP Protocol (Phase 6 Complete - Infrastructure)
- **Session Management**: HTTP transport, session lifecycle
- **Request/Response**: Protocol messaging framework
- **Caching**: Client-side precinct-based caching
- **Server**: Multi-client support with bandwidth throttling
- **Note**: Streaming operations await codec integration (v1.1)

#### Advanced Features (Phase 7 Complete)
- **Visual Weighting**: CSF-based perceptual modeling
- **Quality Metrics**: PSNR, SSIM, MS-SSIM
- **Encoding Presets**: Fast, balanced, quality presets
- **Progressive Modes**: SNR, spatial, layer-progressive
- **Extended Formats**: 16-bit images, HDR support, alpha channels

#### Codec Integration (v1.0 Complete ✅)
- **Encoding**: Full `J2KEncoder.encode()` pipeline
- **Decoding**: Full `J2KDecoder.decode()` pipeline
- **File I/O**: `J2KFileReader.read()` and `J2KFileWriter.write()`
- **Round-Trip**: Complete encode→decode workflows
- **Test Coverage**: 1,498 tests, 98.3% passing (25 skipped)

### Coming in v1.1 (8-12 weeks)
- ⚡ **Hardware Acceleration**: vDSP integration (2-4x speedup)
- 🌐 **JPIP Streaming**: Complete image/region/progressive requests
- 🐛 **Bug Fixes**: Bypass mode optimization (5 skipped tests)
- 🎨 **Advanced Decoding**: ROI, resolution-progressive, quality-progressive
- 🔧 **Performance**: Profiling, optimization, parallelization

### Future Releases
- **v1.2**: HTJ2K codec (ISO/IEC 15444-15, High Throughput JPEG 2000), lossless transcoding between legacy JPEG 2000 and HTJ2K, advanced encoding features, extended format support
- **v2.0**: JPEG 2000 Part 2 extensions, Motion JPEG 2000, JPSEC

## 📚 Documentation

### Getting Started
- **[README.md](README.md)**: This file - quick start and overview
- **[RELEASE_NOTES_v1.0.md](RELEASE_NOTES_v1.0.md)**: Complete v1.0.0 release notes
- **[GETTING_STARTED.md](GETTING_STARTED.md)**: Comprehensive introduction
- **[TUTORIAL_ENCODING.md](TUTORIAL_ENCODING.md)**: Step-by-step encoding guide
- **[TUTORIAL_DECODING.md](TUTORIAL_DECODING.md)**: Step-by-step decoding guide
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)**: Upgrading from other libraries

### API Reference
- **[API_REFERENCE.md](API_REFERENCE.md)**: Complete API documentation
- **[API_ERGONOMICS.md](API_ERGONOMICS.md)**: API design principles
- **Swift-DocC**: Generated documentation (see [DOCUMENTATION_GUIDE.md](DOCUMENTATION_GUIDE.md))

### Technical Documentation
- **[WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md)**: DWT implementation details
- **[ENTROPY_CODING.md](ENTROPY_CODING.md)**: EBCOT and MQ-coder
- **[QUANTIZATION.md](QUANTIZATION.md)**: Quantization strategies
- **[RATE_CONTROL.md](RATE_CONTROL.md)**: PCRD-opt algorithm
- **[COLOR_TRANSFORM.md](COLOR_TRANSFORM.md)**: Color space conversions
- **[JP2_FILE_FORMAT.md](JP2_FILE_FORMAT.md)**: File format specification
- **[JPIP_PROTOCOL.md](JPIP_PROTOCOL.md)**: Streaming protocol
- **[EXTENDED_FORMATS.md](EXTENDED_FORMATS.md)**: JPX, JPM support
- **[BYPASS_MODE_ISSUE.md](BYPASS_MODE_ISSUE.md)**: Known bypass mode limitation and workarounds

### Advanced Topics
- **[ADVANCED_ENCODING.md](ADVANCED_ENCODING.md)**: Encoding techniques
- **[ADVANCED_DECODING.md](ADVANCED_DECODING.md)**: Decoding optimizations
- **[HARDWARE_ACCELERATION.md](HARDWARE_ACCELERATION.md)**: Performance optimization
- **[PARALLELIZATION.md](PARALLELIZATION.md)**: Multi-threading strategy
- **[PERFORMANCE.md](PERFORMANCE.md)**: Benchmarking and profiling

### Development & Testing
- **[CONTRIBUTING.md](CONTRIBUTING.md)**: Development guidelines
- **[CONFORMANCE_TESTING.md](CONFORMANCE_TESTING.md)**: Standards compliance
- **[REFERENCE_BENCHMARKS.md](REFERENCE_BENCHMARKS.md)**: Performance baselines
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**: Common issues and solutions

### Project Management
- **[MILESTONES.md](MILESTONES.md)**: 100-week development roadmap (complete!)
- **[ROADMAP_v1.1.md](ROADMAP_v1.1.md)**: Next version plans
- **[RELEASE_CHECKLIST.md](RELEASE_CHECKLIST.md)**: Release process

## 🗺️ Development Roadmap

### Completed: 100-Week Milestone
        print("Cache hit rate: \(cacheStats.hitRate * 100)%")
        print("Cache size: \(cacheStats.totalSize) bytes, entries: \(cacheStats.entryCount)")
        
        // Check if data is cached
        if await session.hasDataBin(binClass: .mainHeader, binID: 1) {
            let dataBin = await session.getDataBin(binClass: .mainHeader, binID: 1)
            print("Retrieved from cache: \(dataBin?.data.count ?? 0) bytes")
        }
        
        // Get precinct cache statistics
        let precinctStats = await session.getPrecinctStatistics()
        print("Precincts: \(precinctStats.totalPrecincts) total")
        print("Completion rate: \(precinctStats.completionRate * 100)%")
        
        // Invalidate cache by bin class
        await session.invalidateCache(binClass: .precinct)
        
        print("Received image: \(image.width)x\(image.height)")
    } catch {
        print("Request failed: \(error)")
    }
}
```

## 📦 Modules

### J2KCore
Core types, protocols, and utilities used by all other modules.

### J2KCodec
Encoding and decoding functionality for JPEG 2000 images.

### J2KAccelerate
Hardware-accelerated operations using platform-specific frameworks (Accelerate on Apple platforms). On non-Apple platforms, software fallback implementations are used automatically.

### J2KFileFormat
File format support for JP2, J2K, JPX, and other JPEG 2000 container formats.

### JPIP
JPEG 2000 Interactive Protocol implementation for efficient network streaming.

## 🗓️ Development Roadmap

See [MILESTONES.md](MILESTONES.md) for the detailed 100-week development roadmap tracking all features and implementation phases.

### Current Status: Phase 8 Complete - Production Ready (v1.0.0 ✅)

> **Encoder Status**: The high-level `J2KEncoder.encode()` API is **fully functional** in v1.0! All encoding pipeline stages (color transform, wavelet transform, quantization, entropy coding, rate control) are integrated and working.
> 
> **Decoder Status**: The high-level `J2KDecoder.decode()` API is not yet implemented. Individual decoding components are available, and full decoder pipeline integration is planned for v1.1.


**All 8 Phases Complete** (100 weeks):
- ✅ Phase 0: Foundation (Weeks 1-10)
- ✅ Phase 1: Entropy Coding (Weeks 11-25)  
- ✅ Phase 2: Wavelet Transform (Weeks 26-40)
- ✅ Phase 3: Quantization (Weeks 41-48)
- ✅ Phase 4: Color Transforms (Weeks 49-56)
- ✅ Phase 5: File Format (Weeks 57-68)
- ✅ Phase 6: JPIP Protocol (Weeks 69-80)
- ✅ Phase 7: Optimization & Features (Weeks 81-92)
- ✅ Phase 8: Production Ready (Weeks 93-100)

**Next**: Version 1.1 - High-level codec integration (see [ROADMAP_v1.1.md](ROADMAP_v1.1.md))

## 🧪 Testing

### Test Statistics (v1.0.0)
- **Total Tests**: 1,344
- **Passing**: 1,292 (96.1%)
- **Failing**: 32 (bit-plane decoder cleanup pass)
- **Skipped**: 20 (platform-specific)

### Test Coverage by Module
- **J2KCore**: 100% of public APIs tested
- **J2KCodec**: 96.1% pass rate (entropy coding has known issues)
- **J2KFileFormat**: 100% pass rate
- **J2KAccelerate**: Framework tests complete
- **JPIP**: Infrastructure tests complete

### Running Tests
```bash
# Run all tests
swift test

# Run specific module tests
swift test --filter J2KCoreTests
swift test --filter J2KCodecTests
swift test --filter J2KFileFormatTests

# Run with coverage
swift test --enable-code-coverage

# Performance tests
swift test --filter J2KBenchmarkTests
```

See [CONFORMANCE_TESTING.md](CONFORMANCE_TESTING.md) for details on testing strategy.

## 🚀 Performance

### Current Benchmarks (Apple Silicon M1)
- **MQ Encoding**: 18,800+ code-blocks/second
- **Wavelet Transform**: Efficient with SIMD optimization ready
- **Memory Usage**: Zero-copy buffers, memory pooling
- **Build Time**: ~45 seconds clean build, ~5 seconds incremental

### Performance Targets (v1.1)
- **Encoding Speed**: Within 80% of OpenJPEG
- **Decoding Speed**: Within 80% of OpenJPEG
- **Memory Usage**: < 2x compressed file size
- **Thread Scaling**: > 80% efficiency up to 8 cores

See [PERFORMANCE.md](PERFORMANCE.md) and [REFERENCE_BENCHMARKS.md](REFERENCE_BENCHMARKS.md) for detailed metrics.

## 🤝 Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For information about our CI/CD workflows and automated testing, see [CI_CD_GUIDE.md](CI_CD_GUIDE.md).

### Areas Needing Help
1. **High-level codec integration** (v1.1 priority)
2. **Bit-plane decoder bug fix** (32 failing tests)
3. **Hardware acceleration implementation** (vDSP)
4. **JPIP streaming completion**
5. **Cross-platform testing**
6. **Documentation improvements**
7. **ISO test suite validation**

### Development Process
```bash
# Clone the repository
git clone https://github.com/Raster-Lab/J2KSwift.git
cd J2KSwift

# Build the project
swift build

# Run tests
swift test

# Run SwiftLint
swiftlint

# Format code (if swift-format installed)
swift format --in-place --recursive Sources Tests
```

## 📄 License

J2KSwift is released under the MIT License. See [LICENSE](LICENSE) for details.

## 🙏 Acknowledgments

This project represents a 100-week development effort following a comprehensive milestone-based roadmap. Special thanks to:

- The JPEG committee for the JPEG 2000 standard (ISO/IEC 15444)
- Apple's Swift team for Swift 6.2 and the concurrency model
- The open-source community for testing and feedback

## 📞 Support

### Getting Help
- 📖 **Documentation**: Start with [GETTING_STARTED.md](GETTING_STARTED.md)
- 🐛 **Issues**: [GitHub Issues](https://github.com/Raster-Lab/J2KSwift/issues)
- 💬 **Discussions**: [GitHub Discussions](https://github.com/Raster-Lab/J2KSwift/discussions)
- 📧 **Security**: Contact maintainers for security issues

### Project Links
- **Repository**: https://github.com/Raster-Lab/J2KSwift
- **Releases**: https://github.com/Raster-Lab/J2KSwift/releases
- **Milestones**: [MILESTONES.md](MILESTONES.md)
- **Release Notes**: [RELEASE_NOTES_v1.0.md](RELEASE_NOTES_v1.0.md)

## 📊 Project Status

| Component | Status | Test Coverage | Notes |
|-----------|--------|---------------|-------|
| Core Types | ✅ Complete | 100% | Production ready |
| Wavelet Transform | ✅ Complete | 100% | Fully functional |
| Entropy Coding | ✅ Complete | 99.7% | 5 known issues (bypass mode) |
| Quantization | ✅ Complete | 100% | Fully functional |
| Color Transforms | ✅ Complete | 100% | RCT & ICT working |
| File Format | ✅ Complete | 100% | JP2/JPX/JPM support |
| JPIP Protocol | ✅ Infrastructure | 100% | Awaiting decoder integration |
| **Encoder API** | ✅ **Complete** | **100%** | **Fully functional in v1.0!** |
| Decoder API | ⏳ Planned | N/A | Coming in v1.1 |
| Hardware Accel | ⏳ Partial | 100% | DWT acceleration working, more in v1.1 |
| HTJ2K Codec | ⏳ Planned | N/A | Coming in v1.2 (Part 15) |
| Lossless Transcoding | ⏳ Planned | N/A | Coming in v1.2 (JPEG 2000 ↔ HTJ2K) |

---

**J2KSwift v1.0.0** - A modern Swift implementation of JPEG 2000  
**Status**: Encoder Complete, Decoder Planned for v1.1  
**Next Release**: v1.1 (April-May 2026) with full decoder integration

For detailed information, see [RELEASE_NOTES_v1.0.md](RELEASE_NOTES_v1.0.md)
