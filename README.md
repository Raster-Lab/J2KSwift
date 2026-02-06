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
        let image = try await client.requestImage(imageID: "sample")
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
Hardware-accelerated operations using platform-specific frameworks (e.g., Accelerate on Apple platforms).

### J2KFileFormat
File format support for JP2, J2K, JPX, and other JPEG 2000 container formats.

### JPIP
JPEG 2000 Interactive Protocol implementation for efficient network streaming.

## 🗓️ Development Roadmap

See [MILESTONES.md](MILESTONES.md) for the detailed 100-week development roadmap tracking all features and implementation phases.

### Current Status: Phase 2 In Progress - Wavelet Transform 🚧

**Phase 1 Complete** ✅:
- [x] Tier-1 Coding Primitives (Weeks 11-13)
- [x] Code-Block Coding (Weeks 14-16)
- [x] Tier-2 Coding (Weeks 17-19)
- [x] Performance Optimization (Weeks 20-22)
- [x] Testing & Validation (Weeks 23-25)

**Phase 2 In Progress** 🚧:
- [x] 1D DWT Foundation (Week 26-28) ✅
- [x] 2D DWT Implementation (Week 29-31) ✅
- [x] Tiling Support (Week 32-34) ✅
- [ ] Hardware Acceleration (Week 35-37)
- [ ] Advanced Features (Week 38-40)

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

### Planned Features

See [MILESTONES.md](MILESTONES.md) for the complete feature roadmap including:

- 2D wavelet transforms and multi-level decomposition
- Quantization and rate control
- Color space transformations
- Region of interest (ROI) coding
- Multiple component transformations
- Tiling support
- Full JPIP implementation
- Hardware acceleration
- And much more...

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

**Status**: 🚧 Early Development - Not yet ready for production use

This project is in active development. APIs are subject to change. See [MILESTONES.md](MILESTONES.md) for current progress and planned features.