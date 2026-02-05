# J2KCore

A pure Swift 6 implementation of JPEG 2000 (ISO/IEC 15444) encoding and decoding with strict concurrency support.

## 🎯 Project Goals

J2KCore aims to provide a modern, safe, and performant JPEG 2000 implementation for Swift applications with the following objectives:

- **Swift 6 Native**: Built from the ground up with Swift 6's strict concurrency model
- **Cross-Platform**: Support for macOS, iOS, tvOS, watchOS, and visionOS
- **Standards Compliant**: Full implementation of JPEG 2000 Part 1 (ISO/IEC 15444-1)
- **Performance**: Hardware-accelerated operations using platform-specific frameworks
- **Network Streaming**: JPIP (JPEG 2000 Interactive Protocol) support for efficient image streaming
- **Modern API**: Async/await based APIs with comprehensive error handling
- **Well Documented**: Extensive documentation with examples and tutorials

## 🚀 Quick Start

### Installation

Add J2KCore to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KCore.git", from: "1.0.0")
]
```

Then add the specific modules you need to your target dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "J2KCore", package: "J2KCore"),
        .product(name: "J2KCodec", package: "J2KCore"),
        .product(name: "J2KFileFormat", package: "J2KCore"),
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

### Current Status: Phase 0 - Foundation (Weeks 1-10)

- [x] Project initialization
- [ ] Core type system
- [ ] Basic entropy coding
- [ ] Tier-1 coding primitives

## 🌟 Features

### Current Features

- ✅ Swift 6 with strict concurrency
- ✅ Basic type system and error handling
- ✅ Module structure for organized development

### Planned Features

See [MILESTONES.md](MILESTONES.md) for the complete feature roadmap including:

- Wavelet transforms (DWT)
- Entropy coding (EBCOT)
- Quantization
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

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on:

- Code style and standards
- Pull request process
- Development workflow
- Testing requirements
- Documentation standards

## 📄 License

J2KCore is released under the MIT License. See [LICENSE](LICENSE) for details.

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

J2KCore is inspired by and references:

- OpenJPEG open source implementation
- JPEG 2000 standard specifications
- Swift community best practices

## 📧 Contact

- GitHub Issues: [Report bugs or request features](https://github.com/Raster-Lab/J2KCore/issues)
- Discussions: [Ask questions and share ideas](https://github.com/Raster-Lab/J2KCore/discussions)

---

**Status**: 🚧 Early Development - Not yet ready for production use

This project is in active development. APIs are subject to change. See [MILESTONES.md](MILESTONES.md) for current progress and planned features.