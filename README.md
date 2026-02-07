# J2KSwift

A pure Swift 6.2 implementation of JPEG 2000 (ISO/IEC 15444) encoding and decoding with strict concurrency support.

## 🎯 Project Goals

J2KSwift aims to provide a modern, safe, and performant JPEG 2000 implementation for Swift applications with the following objectives:

- **Swift 6.2 Native**: Built from the ground up with Swift 6.2's strict concurrency model
- **Cross-Platform**: Support for macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, and visionOS 1+
- **Standards Compliant**: Full implementation of JPEG 2000 Part 1 (ISO/IEC 15444-1)
- **Performance**: Hardware-accelerated operations using platform-specific frameworks
- **Network Streaming**: JPIP (JPEG 2000 Interactive Protocol) support for efficient image streaming
- **Modern API**: Async/await based APIs with comprehensive error handling
- **Well Documented**: Extensive documentation with examples and tutorials

## 🚀 Quick Start

### Requirements

- Swift 6.2 or later
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+ / visionOS 1+

### Installation

Add J2KSwift to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "1.0.0")
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

#### Encoding an Image

> **Note**: The top-level `J2KEncoder.encode()` pipeline is not yet implemented. Individual codec components (wavelet transform, quantization, entropy coding, color transform) are available for direct use. The example below shows the planned API.

```swift
import J2KCore
import J2KCodec

let image = J2KImage(width: 512, height: 512, components: 3)
let config = J2KConfiguration(quality: 0.9, lossless: false)
let encoder = J2KEncoder(configuration: config)

do {
    let encodedData = try encoder.encode(image)
    // Use encoded data...
} catch {
    print("Encoding failed: \(error)")
}
```

#### Decoding an Image

> **Note**: The top-level `J2KDecoder.decode()` pipeline is not yet implemented. The example below shows the planned API.

```swift
import J2KCore
import J2KCodec

let decoder = J2KDecoder()

do {
    let image = try decoder.decode(jpegData)
    print("Decoded image: \(image.width)x\(image.height)")
} catch {
    print("Decoding failed: \(error)")
}
```

#### File I/O

> **Note**: Full JP2 box parsing is planned for Phase 5. Basic file format detection and reader/writer scaffolding is available.

```swift
import J2KFileFormat

let reader = J2KFileReader()
let writer = J2KFileWriter(format: .jp2)

do {
    let image = try reader.read(from: inputURL)
    try writer.write(image, to: outputURL)
} catch {
    print("File operation failed: \(error)")
}
```

#### Network Streaming with JPIP

```swift
import JPIP

let client = JPIPClient(serverURL: URL(string: "http://example.com/jpip")!)

Task {
    do {
        // Create a session for an image
        let session = try await client.createSession(target: "sample.jp2")
        
        // Request the full image
        let image = try await client.requestImage(imageID: "sample.jp2")
        
        // Or request a specific region
        let region = try await client.requestRegion(
            imageID: "sample.jp2",
            region: (x: 100, y: 100, width: 512, height: 512)
        )
        
        // Progressive quality streaming (Week 72-74) ✅
        let progressiveImage = try await client.requestProgressiveQuality(
            imageID: "sample.jp2",
            upToLayers: 5
        )
        
        // Resolution level request (Week 72-74) ✅
        let thumbnail = try await client.requestResolutionLevel(
            imageID: "sample.jp2",
            level: 3,
            layers: 2
        )
        
        // Component selection (Week 72-74) ✅
        let rgImage = try await client.requestComponents(
            imageID: "sample.jp2",
            components: [0, 1],  // Red and Green channels only
            layers: 3
        )
        
        // Metadata-only request (Week 72-74) ✅
        let metadata = try await client.requestMetadata(imageID: "sample.jp2")
        
        // Cache management (Week 75-77) ✅
        let cacheStats = await session.getCacheStatistics()
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

### Current Status: Phase 6 Complete ✅ - JPIP Protocol

> **Note**: Individual codec components (entropy coding, wavelet transforms, quantization, color transforms) are fully implemented and tested. The top-level `J2KEncoder.encode()` and `J2KDecoder.decode()` integration pipeline is not yet complete — these are planned for a future phase that ties all components together.

**Completed Phases:**
- ✅ Phase 0: Foundation (Weeks 1-10)
- ✅ Phase 1: Entropy Coding (Weeks 11-25)
- ✅ Phase 2: Wavelet Transform (Weeks 26-40)
- ✅ Phase 3: Quantization (Weeks 41-48)
- ✅ Phase 4: Color Transforms (Weeks 49-56)
- ✅ Phase 5: File Format (Weeks 57-68)
- ✅ Phase 6: JPIP Protocol (Weeks 69-80) ✅
  - ✅ Week 69-71: JPIP Client Basics
  - ✅ Week 72-74: Data Streaming (Progressive quality, Resolution levels, Component selection, Metadata requests)
  - ✅ Week 75-77: Cache Management (LRU eviction, Precinct caching, Statistics tracking)
  - ✅ Week 78-80: JPIP Server (Request queue, Bandwidth throttling, Multi-client support)

**Phase 1 Complete** ✅:
- [x] Tier-1 Coding Primitives (Weeks 11-13)
- [x] Code-Block Coding (Weeks 14-16)
- [x] Tier-2 Coding (Weeks 17-19)
- [x] Performance Optimization (Weeks 20-22)
- [x] Testing & Validation (Weeks 23-25)

**Phase 2 Complete** ✅:
- [x] 1D DWT Foundation (Week 26-28)
- [x] 2D DWT Implementation (Week 29-31)
- [x] Tiling Support (Week 32-34)
- [x] Hardware Acceleration (Week 35-37)
- [x] Advanced Features (Week 38-40)

**Phase 3 Complete** ✅:
- [x] Basic Quantization (Week 41-43) ✅
- [x] Region of Interest (Week 44-45) ✅
- [x] Rate Control (Week 46-48) ✅

**Phase 4 Complete** ✅:
- [x] Reversible Color Transform (Week 49-51) ✅
- [x] Irreversible Color Transform (Week 52-54) ✅
- [x] Advanced Color Support (Week 55-56) ✅

**Phase 5 Complete** ✅:
- [x] Basic Box Structure (Week 57-59) ✅
- [x] Essential Boxes (Week 60-62) ✅
- [x] Optional Boxes (Week 63-65) ✅
- [x] Advanced Features: JPX/JPM (Week 66-68) ✅

**Phase 6 Complete** ✅:
- [x] JPIP Client Basics (Week 69-71) ✅
- [x] Data Streaming (Week 72-74) ✅
- [x] Cache Management (Week 75-77) ✅
- [x] JPIP Server (Week 78-80) ✅

**Phase 7 In Progress** 🚀:
- [x] Performance Tuning (Week 81-83) ✅
- [x] Advanced Encoding Features (Week 84-86) ✅
- [ ] Advanced Decoding Features (Week 87-89)
- [ ] Extended Formats (Week 90-92)

## 🌟 Features

### Current Features

- ✅ Swift 6.2 with strict concurrency
- ✅ Basic type system and error handling
- ✅ Module structure for organized development
- ✅ Comprehensive CI/CD pipeline with automated testing and linting
- ✅ Cross-platform support (macOS, iOS, tvOS, watchOS, visionOS, Linux)
- ✅ Efficient memory management with copy-on-write buffers
- ✅ Memory pooling for temporary allocations
- ✅ Memory usage tracking and limits
- ✅ Bitstream reader/writer with bit-level operations
- ✅ JPEG 2000 marker segment parser
- ✅ File format detection (JP2, J2K, JPX, JPM)
- ✅ **Complete Entropy Coding Implementation (Phase 1)**:
  - ✅ Tier-1 coding (bit-plane coding, MQ-coder, context modeling)
  - ✅ Code-block encoding/decoding with EBCOT
  - ✅ Tier-2 coding (packet headers, progression orders, layer formation)
  - ✅ Performance optimization (18,833 ops/sec encoding)
  - ✅ Comprehensive test coverage (360+ tests including test vectors and fuzzing)
  - ✅ Full documentation ([ENTROPY_CODING.md](ENTROPY_CODING.md))
- ✅ **1D Wavelet Transform (Phase 2, Week 26-28)**:
  - ✅ 5/3 reversible filter (integer-to-integer, lossless)
  - ✅ 9/7 irreversible filter (floating-point, lossy)
  - ✅ Three boundary extension modes (symmetric, periodic, zero-padding)
  - ✅ Lifting scheme implementation for efficiency
  - ✅ Perfect reconstruction for 5/3, <1e-6 error for 9/7
  - ✅ Comprehensive test coverage (33 tests, all passing)
  - ✅ Full documentation ([WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md))
- ✅ **2D Wavelet Transform (Phase 2, Week 29-31)**:
  - ✅ Separable 2D transforms (row-then-column)
  - ✅ Four subbands per level (LL, LH, HL, HH)
  - ✅ Multi-level dyadic decomposition
  - ✅ Support for arbitrary image dimensions (including odd sizes)
  - ✅ Both 5/3 and 9/7 filter support
  - ✅ Perfect reconstruction maintained
  - ✅ 28 comprehensive tests covering all scenarios
  - ✅ Full documentation (updated [WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md))
- ✅ **Tile-by-Tile DWT (Phase 2, Week 32-34)**:
  - ✅ Memory-efficient large image processing
  - ✅ Tile extraction and assembly
  - ✅ Independent tile processing (JPEG 2000 compliant)
  - ✅ Tile boundary handling with proper extension
  - ✅ Support for non-aligned tile dimensions (partial tiles)
  - ✅ Perfect reconstruction with tiling
  - ✅ 23 comprehensive tests, 100% pass rate
  - ✅ Up to 64x memory reduction for large images
  - ✅ Full documentation (updated [WAVELET_TRANSFORM.md](WAVELET_TRANSFORM.md))
- ✅ **Hardware Acceleration (Phase 2, Week 35-37)**:
  - ✅ Accelerate framework integration (Apple platforms)
  - ✅ Hardware-accelerated 1D DWT using vDSP
  - ✅ Hardware-accelerated 2D DWT (separable transforms)
  - ✅ Multi-level decomposition acceleration
  - ✅ 2-4x performance improvement on Apple Silicon
  - ✅ Cross-platform support with graceful fallback
  - ✅ Perfect reconstruction maintained (< 1e-6 error)
  - ✅ 22 comprehensive tests, 100% pass rate
  - ✅ SIMD-optimized lifting steps
  - ✅ Parallel tile processing using Swift Concurrency
  - ✅ Full documentation ([HARDWARE_ACCELERATION.md](HARDWARE_ACCELERATION.md))
- ✅ **Basic Quantization (Phase 3, Week 41-43)**:
  - ✅ Scalar (uniform) quantization
  - ✅ Deadzone quantization with configurable width
  - ✅ Expounded mode with explicit step sizes
  - ✅ No quantization mode for lossless compression
  - ✅ Automatic step size calculation per subband
  - ✅ Dynamic range adjustment for different bit depths
  - ✅ Quality-based parameter generation
  - ✅ Step size encoding/decoding for file format
  - ✅ 44 comprehensive tests, 100% pass rate
  - ✅ Full documentation ([QUANTIZATION.md](QUANTIZATION.md))
- ✅ **Region of Interest (Phase 3, Week 44-45)**:
  - ✅ MaxShift ROI method for selective quality encoding
  - ✅ Multiple ROI shape types (rectangle, ellipse, polygon)
  - ✅ ROI mask generation with priority support
  - ✅ Wavelet domain ROI mapping
  - ✅ Multiple overlapping ROI regions
  - ✅ Implicit ROI coding support
  - ✅ ROI statistics and coverage analysis
  - ✅ 47 comprehensive tests, 100% pass rate
- ✅ **Rate Control (Phase 3, Week 46-48)**:
  - ✅ PCRD-opt (Post Compression Rate Distortion Optimization) algorithm
  - ✅ Target bitrate mode for precise file size control
  - ✅ Constant quality mode for quality-driven encoding
  - ✅ Lossless mode with full pass inclusion
  - ✅ Three distortion estimation methods (norm, MSE, simplified)
  - ✅ Strict and non-strict rate matching
  - ✅ Progressive quality layer formation
  - ✅ 58 comprehensive tests (34 functional + 24 benchmark), 100% pass rate
  - ✅ < 50ms optimization time for typical images
- ✅ **Reversible Color Transform (Phase 4, Week 49-51)**:
  - ✅ Integer-to-integer RGB ↔ YCbCr transform for lossless compression
  - ✅ Perfect reversibility (no precision loss)
  - ✅ Support for signed integers and large bit depths
  - ✅ Component subsampling support (4:4:4, 4:2:2, 4:2:0)
  - ✅ Array-based and component-based APIs
  - ✅ Optimized for natural images
  - ✅ 50 comprehensive tests (30 functional + 20 benchmark), 100% pass rate
  - ✅ ~10ms for 512×512 images, ~42ms for 1024×1024 images
- ✅ **Irreversible Color Transform (Phase 4, Week 52-54)**:
  - ✅ Floating-point RGB ↔ YCbCr transform for lossy compression
  - ✅ Better decorrelation than RCT for natural images
  - ✅ ISO/IEC 15444-1 Annex G.3 compliant coefficients
  - ✅ Reconstruction error < 1.0 for 8-bit data
  - ✅ Array-based and component-based APIs
  - ✅ Support for signed and floating-point values
  - ✅ 44 comprehensive tests (14 ICT-specific), 100% pass rate
  - ✅ 40 benchmarks (20 ICT-specific), all passing
  - ✅ ~10ms for 512×512 images, ~42ms for 1024×1024 images
- ✅ **Advanced Color Support (Phase 4, Week 55-56)**:
  - ✅ Grayscale conversion (RGB ↔ Grayscale)
  - ✅ ITU-R BT.601 luminance formula (integer and floating-point)
  - ✅ Palette support (indexed color images)
  - ✅ Palette creation with color quantization (up to 256 colors)
  - ✅ Color space detection and validation
  - ✅ J2KColorSpace enum made Equatable
  - ✅ 26 new tests, 100% pass rate
- ✅ **JP2 Box Framework (Phase 5, Week 57-59)**:
  - ✅ Complete box reader/writer framework
  - ✅ Support for standard and extended length boxes (>4GB)
  - ✅ J2KBox protocol for all box types
  - ✅ J2KBoxReader for lazy, efficient parsing
  - ✅ J2KBoxWriter with automatic length selection
  - ✅ Signature Box ('jP  ') - JP2 file signature
  - ✅ File Type Box ('ftyp') - Brand and compatibility
  - ✅ JP2 Header Box ('jp2h') - Container for header boxes
  - ✅ Image Header Box ('ihdr') - Image dimensions and properties
  - ✅ 29 comprehensive tests, 100% pass rate
  - ✅ Full documentation ([JP2_FILE_FORMAT.md](JP2_FILE_FORMAT.md))
- ✅ **Essential JP2 Boxes (Phase 5, Week 60-62)**:
  - ✅ Bits Per Component Box ('bpcc') - Variable bit depths per component
    - Signed/unsigned support
    - 1-38 bit depth range
    - Per-component bit depth specification
  - ✅ Color Specification Box ('colr') - Color space information
    - Enumerated color spaces (sRGB, Greyscale, YCbCr, CMYK, e-sRGB, ROMM-RGB)
    - ICC profile support (restricted and unrestricted)
    - Vendor color space support
    - Multiple color specification precedence handling
  - ✅ Palette Box ('pclr') - Indexed color support
    - Up to 1024 palette entries
    - Up to 255 components per entry
    - Variable bit depths per component
    - Big-endian multi-byte value encoding
  - ✅ Component Mapping Box ('cmap') - Component channel mapping
    - Direct component mapping
    - Palette-based component mapping
    - Support for indexed color images
  - ✅ Channel Definition Box ('cdef') - Channel type definitions
    - Color/opacity/premultiplied opacity channel types
    - Channel association support
    - Complete RGBA and indexed color support
  - ✅ 50 new comprehensive tests, 100% pass rate
  - ✅ Complete indexed color workflow
  - ✅ Full documentation with examples
- ✅ **Optional JP2 Boxes (Phase 5, Week 63-65)**:
  - ✅ Resolution Box ('res ') - Container for resolution metadata
    - Flexible structure (one or both sub-boxes)
  - ✅ Capture Resolution Box ('resc') - Original capture resolution
    - Numerator/denominator/exponent format for flexible precision
    - Support for pixels per metre and inch units
    - Wide range scaling with exponents
  - ✅ Display Resolution Box ('resd') - Recommended display resolution
    - Same structure as capture resolution
    - Independent scaling support
  - ✅ UUID Box ('uuid') - Vendor-specific extensions
    - 16-byte UUID identifier
    - Application-specific data payload
    - Support for proprietary metadata and extensions
  - ✅ XML Box ('xml ') - Structured metadata
    - UTF-8 encoded XML content
    - XMP metadata support
    - Flexible metadata embedding
  - ✅ 48 new comprehensive tests, 100% pass rate
  - ✅ Full resolution metadata support
  - ✅ Extensibility mechanisms implemented
- ✅ **JPX/JPM Advanced Features (Phase 5, Week 66-68)**:
  - ✅ Fragment Table Box ('ftbl') - Fragmented codestream support
    - Non-contiguous codestream fragments
    - Progressive streaming enablement
  - ✅ Fragment List Box ('flst') - Fragment offset and length tracking
    - Support for 4-byte and 8-byte offsets (files up to petabytes)
    - Efficient fragment reconstruction
  - ✅ Composition Box ('comp') - Multi-layer image composition
    - Layer positioning and blending
    - Animation support with loop control
    - Three compositing modes (replace, alpha blend, pre-multiplied alpha)
  - ✅ Page Collection Box ('pcol') - Multi-page document support (JPM)
    - Container for multiple pages
    - Document imaging applications
  - ✅ Page Box ('page') - Individual page structure
    - Page dimensions and layout
    - Support for mixed page sizes
  - ✅ Layout Box ('lobj') - Object positioning on pages
    - Precise placement control
    - Multi-layer compound documents
  - ✅ 49 new comprehensive tests (127 total), 100% pass rate
  - ✅ Complete JPX/JPM support for advanced use cases
  - ✅ Full documentation with examples
- ✅ **JPIP Client Basics (Phase 6, Week 69-71)**:
  - ✅ JPIP request types (target, fsiz, rsiz, roff, layers, cid)
  - ✅ Request URL builder for HTTP transport
  - ✅ URLSession-based HTTP client with async/await
  - ✅ JPIP response parsing (JPIP-cnew header, channel ID extraction)
  - ✅ Session management (JPIPSession actor)
  - ✅ Channel ID (cid) tracking for stateful communication
  - ✅ Cache model for tracking received data bins
  - ✅ Persistent connection support via URLSession
  - ✅ Region of interest requests
  - ✅ Resolution-based requests
  - ✅ Quality layer selection
  - ✅ 27 comprehensive tests, 100% pass rate
  - ✅ Full documentation ([JPIP_PROTOCOL.md](JPIP_PROTOCOL.md))
  - ✅ ISO/IEC 15444-9 compliant
- ✅ **JPIP Server (Phase 6, Week 78-80)**:
  - ✅ Basic JPIP server implementation (JPIPServer actor)
  - ✅ Image registration and serving
  - ✅ Request queue management with priority-based scheduling
  - ✅ Bandwidth throttling using token bucket algorithm
  - ✅ Multi-client support with concurrent session handling
  - ✅ Session timeout detection
  - ✅ Server statistics tracking
  - ✅ 124 comprehensive tests (100% pass rate)
  - ✅ 9 client-server integration tests
  - ✅ Full documentation
- ✅ **Performance Tuning (Phase 7, Week 81-83)**:
  - ✅ Comprehensive benchmarking framework
  - ✅ MQ-coder optimization (3% speedup)
  - ✅ Parallelization analysis and documentation
  - ✅ Reference benchmark suite vs OpenJPEG
  - ✅ 70-72% of OpenJPEG performance for entropy coding
  - ✅ Full documentation ([PERFORMANCE.md](PERFORMANCE.md), [REFERENCE_BENCHMARKS.md](REFERENCE_BENCHMARKS.md))
- ✅ **Advanced Encoding Features (Phase 7, Week 84-86)**:
  - ✅ Encoding presets (fast, balanced, quality)
    - Fast: 2-3× faster, single-threaded, 3 layers
    - Balanced: Optimal quality/speed, multi-threaded, 5 layers
    - Quality: Best quality, 1.5-2× slower, 10 layers
  - ✅ Progressive encoding support
    - SNR (quality) progressive mode
    - Spatial (resolution) progressive mode
    - Layer-progressive for streaming
    - Combined progressive modes
  - ✅ Variable bitrate control
    - Constant BitRate (CBR) mode
    - Variable BitRate (VBR) mode
    - Constant quality mode
    - Lossless mode
  - ✅ Visual frequency weighting (CSF-based perceptual optimization)
  - ✅ Perceptual quality metrics (PSNR, SSIM, MS-SSIM)
  - ✅ 62 comprehensive tests (100% pass rate)
  - ✅ Full documentation ([ADVANCED_ENCODING.md](ADVANCED_ENCODING.md))

### Planned Features

See [MILESTONES.md](MILESTONES.md) for the complete feature roadmap including:

- ✅ Phase 1: Entropy Coding (Complete)
- ✅ Phase 2: Wavelet Transform (Complete)
- ✅ Phase 3: Quantization (Complete)
- ✅ Phase 4: Color Transforms (Complete)
- ✅ Phase 5: File Format (Complete)
  - ✅ Week 57-59: Basic Box Structure
  - ✅ Week 60-62: Essential Boxes (bpcc, colr, pclr, cmap, cdef)
  - ✅ Week 63-65: Optional Boxes (res, resc, resd, uuid, xml)
  - ✅ Week 66-68: Advanced Features (JPX, JPM, fragment tables, composition)
- ✅ Phase 6: JPIP Protocol (Complete)
  - ✅ Week 69-71: JPIP Client Basics
  - ✅ Week 72-74: Data Streaming
  - ✅ Week 75-77: Cache Management
  - ✅ Week 78-80: JPIP Server
- ⏳ Phase 7: Optimization & Features (Weeks 81-92)
  - ✅ Week 81-83: Performance Tuning
  - ✅ Week 84-86: Advanced Encoding Features
  - ⏳ Week 87-89: Advanced Decoding Features
  - ⏳ Week 90-92: Extended Formats
- ⏳ Phase 8: Production Ready (Weeks 93-100)

## 🧪 Testing

Run tests using Swift Package Manager:

```bash
swift test
```

Run tests with coverage:

```bash
swift test --enable-code-coverage
```

## 🔍 Code Quality

The project uses SwiftLint for code style and quality checks:

```bash
swiftlint
```

### Continuous Integration

J2KSwift uses GitHub Actions for continuous integration with the following workflows:

- **Linting**: SwiftLint checks on all code
- **Building**: Multi-platform builds (macOS, iOS, Linux)
- **Testing**: Comprehensive test suite with code coverage
- **Documentation**: Automated documentation generation
- **Static Analysis**: Build warnings and validation checks

All CI checks run automatically on pull requests and commits to the main and develop branches.

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:

- Code style and standards
- Pull request process
- Development workflow
- Testing requirements
- Documentation standards

## 📄 License

J2KSwift is released under the MIT License. See [LICENSE](LICENSE) for details.

## 📚 Resources

### JPEG 2000 Standards

- [ISO/IEC 15444-1](https://www.iso.org/standard/78321.html) - JPEG 2000 Part 1: Core coding system
- [ISO/IEC 15444-2](https://www.iso.org/standard/33160.html) - JPEG 2000 Part 2: Extensions
- [ISO/IEC 15444-9](https://www.iso.org/standard/66067.html) - JPEG 2000 Part 9: JPIP

### Additional Resources

- [OpenJPEG](https://www.openjpeg.org/) - Reference implementation
- [Kakadu](https://kakadusoftware.com/) - Commercial implementation
- [JPEG 2000 Wikipedia](https://en.wikipedia.org/wiki/JPEG_2000) - Overview and history

## 🙏 Acknowledgments

J2KSwift is inspired by and references:

- OpenJPEG open source implementation
- JPEG 2000 standard specifications
- Swift community best practices

## 📧 Contact

- GitHub Issues: [Report bugs or request features](https://github.com/Raster-Lab/J2KSwift/issues)
- Discussions: [Ask questions and share ideas](https://github.com/Raster-Lab/J2KSwift/discussions)

---

**Status**: 🚀 Active Development - Phase 7 In Progress (Week 84-86 Complete ✅)

This project is in active development. The core codec components (entropy coding, wavelet transforms, quantization, color transforms) are implemented and tested. Advanced encoding features including presets, progressive encoding, and variable bitrate control are now available. The top-level encode/decode pipeline and file format support continue in development. APIs are subject to change. See [MILESTONES.md](MILESTONES.md) for current progress and planned features.