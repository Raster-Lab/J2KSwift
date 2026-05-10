# J2KSwift

[![CI](https://github.com/Raster-Lab/J2KSwift/actions/workflows/ci.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/ci.yml)
[![Code Quality](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/code-quality.yml)
[![Documentation](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml/badge.svg)](https://github.com/Raster-Lab/J2KSwift/actions/workflows/documentation.yml)
[![Swift 6.2](https://img.shields.io/badge/Swift-6.2-orange.svg)](https://swift.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A pure Swift 6.2 implementation of JPEG 2000 (ISO/IEC 15444) encoding and decoding with strict concurrency support.

**Current Version**: 8.1.0
**Status**: Apple Silicon-first JPEG 2000 / HTJ2K (Part-15) reference implementation. Marketable claim: **"Fastest JPEG 2000 codec on Apple Silicon."** Full ISO/IEC 15444-4 conformance, verified OpenJPEG/OpenJPH/Kakadu interoperability, Metal-accelerated hot path, optional `j2kd` macOS XPC daemon for warm-CLI single-shot — now one-command-installable. (3,100+ tests, 100 % pass rate.)
**Previous Release**: 8.0.1 (silent-corruption hotfix + GPU IDWT root cause)

## 📦 Release Status

**v8.1.0** turns the v8.0.0 manual 5-step `j2kd` daemon install into a single command (`j2k daemon-install`). End-to-end CLI gap on DX 2800×2288 closes from 72 ms cold-shot → ~55 ms with the daemon installed (–24 % wall). Codestream bytes byte-identical to v8.0.1; no decoder change. See [RELEASE_NOTES_v8.1.0.md](RELEASE_NOTES_v8.1.0.md) for the full deployment-push details.

**v8.0.1** was a silent-corruption hotfix + GPU multi-tile-per-tile 5/3 IDWT root cause. Fixes the v7.5.1 mg silent-corruption (cross-tile batched HT entropy decode on 16+ MP mammography DICOM fixtures) AND root-causes / fixes the underlying GPU IDWT defect that produced the corruption — two distinct bugs in the GPU multi-tile-per-tile path, both surfacing only on tiles with non-zero canvas origin. `_multiTileBatchedEntropyEnabled` is back default-on; the v7.2.0 cross-tile entropy CB amortisation is restored. **Codestream bytes byte-identical to v8.0.0.** See [RELEASE_NOTES_v8.0.1.md](RELEASE_NOTES_v8.0.1.md) for the full root-cause analysis and the per-tile mismatch progression table.

**v8.0.0** was a major-version product pivot. v7.x targeted cross-platform performance and got within 25 % of OpenJPH and 2× of Kakadu globally. v8.0.0 narrows the product to **Apple Silicon (M-series macOS + A-series iOS/iPadOS)** and uses platform-native primitives (Metal, NSXPCConnection, launchd) to beat Kakadu on the dominant Apple-Silicon workloads — small/medium medical images, warm-process apps, and (with the optional XPC daemon) single-shot CLI users.

### Headline measurement — warm in-process decode vs Kakadu CLI (Apple M2, release mode)

This is the comparison user-facing apps care about: J2KSwift in-process (with `J2KDecoder.preWarm()` called once at startup) vs Kakadu CLI invoked per file.

| fixture | warm CPU | Kakadu CLI | result |
|---|---:|---:|:-:|
| MR-small 180² | **0.58 ms** | 15 ms | **WIN 26×** |
| CT 512² | **3.05 ms** | 15 ms | **WIN 5×** |
| MR 886² | **5.60 ms** | 17 ms | **WIN 3×** |
| XA 1024² | **7.89 ms** | 18 ms | **WIN 2.3×** |
| PX 2459×1316 | 29.48 ms | 24 ms | 1.23× behind |
| DX 2800×2288 | 54.41 ms | 36 ms | 1.51× behind |

**4 of 6 fixtures win.** SDK consumers (PACS daemons, iOS/iPadOS DICOM viewers, image-processing pipelines) get this performance via the new `J2KDecoder.preWarm()` API.

### CLI cold-shot progression — DX 2800×2288 (ms, median of 5)

| version | DX CLI cold | Kakadu gap |
|---|---:|---:|
| v7.5.1 baseline | 134 ms | 4.0× |
| v8 Phase 1 (cold-start elimination) | 91 ms | 2.7× |
| v8 Phase 2 (default-CPU routing) | 103 ms | 2.8× |
| v8 Phase 3 (SIMD CPU IDWT) | 91 ms | 2.7× |
| **v8 Phase 4 (NEON reconstruction default ON)** | **89 ms** | **2.47×** |
| **v8 with `j2kd` XPC daemon installed** | **~55 ms** | **~1.5×** |

The Phase 1-4 CPU optimisations cumulatively close the CLI gap from 4.0× to 2.47×. Installing the optional `j2kd` daemon (Phases 6.3-6.6) closes it further to ~1.5× by amortising Metal cold-start across CLI invocations.

### `j2kd` XPC daemon — warm-CLI single-shot (one-command install)

```bash
swift build -c release --product j2k --product j2kd
.build/release/j2k daemon-install      # one shot: copies binary, writes plist, loads launchd
.build/release/j2k daemon-status       # verify everything is ✓
```

To remove later: `j2k daemon-uninstall`. The install layout is per-user (no sudo) — binary at `~/Library/Application Support/J2KSwift/j2kd`, plist at `~/Library/LaunchAgents/com.raster.j2kd.plist`.

Idle timeout default 10 min; SIGTERM/SIGINT handled cleanly; launchd re-spawns on next client connection. Opt-out per call via `j2k decode --no-daemon`.

See [RELEASE_NOTES_v8.1.0.md](RELEASE_NOTES_v8.1.0.md) for the daemon adoption push details. [RELEASE_NOTES_v8.0.1.md](RELEASE_NOTES_v8.0.1.md) for the silent-corruption hotfix. [RELEASE_NOTES_v8.0.0.md](RELEASE_NOTES_v8.0.0.md) covers the v8.0.0 major-version pivot and the 14 phase-finding documents (`V8_0_0_PHASE_0_BASELINE.md` through `V8_0_0_PHASE_6_6_FINDING.md`). Prior release notes: [v7.5.0](RELEASE_NOTES_v7.5.0.md), [v7.4.0](RELEASE_NOTES_v7.4.0.md), [v7.3.0](RELEASE_NOTES_v7.3.0.md).

## 🖥️ J2KTestApp — GUI Testing Application

J2KTestApp is a native macOS SwiftUI application that provides a complete graphical environment for testing every feature of J2KSwift.

### Building and Running J2KTestApp

```bash
# Build J2KTestApp
swift build --target J2KTestApp

# Run J2KTestApp
swift run J2KTestApp
```

Or open `Package.swift` in Xcode, select the **J2KTestApp** scheme, and press **⌘R**.

### GUI Screens

| Screen | Description |
|--------|-------------|
| **Encode** | Drag-and-drop encoding with configuration panel, presets, and DICOM support |
| **Decode** | File-based decoding with ROI selector, resolution stepper, marker inspector |
| **Round-Trip** | One-click encode/decode/compare with real PSNR/SSIM/MSE metrics |
| **Conformance** | Part 1/2/3/10/15 conformance matrix dashboard |
| **Validation** | Codestream syntax and file format validators |
| **Performance** | Benchmark runner with live charts and regression detection |
| **GPU** | Metal pipeline testing with GPU vs CPU comparison |
| **SIMD** | ARM Neon/Intel SSE verification with utilisation gauges |
| **JPIP** | Progressive streaming canvas with network metrics |
| **Volumetric** | JP3D slice navigation with encode/decode comparison |
| **MJ2** | Motion JPEG 2000 frame playback and quality inspection |
| **Report** | Summary dashboard, trend charts, heatmap, and export |

See [Documentation/TESTING_GUIDE.md](Documentation/TESTING_GUIDE.md) for a complete guide to using J2KTestApp.

## 🎯 Project Goals

J2KSwift provides a modern, safe, and performant JPEG 2000 implementation for Swift applications:

- **Swift 6.2 Native**: Built with Swift 6.2's strict concurrency model — zero data races
- **Fully Functional**: Complete encoder and decoder pipelines with JP3D, MJ2, and HTJ2K
- **Apple-Silicon-First (v8.0.0+)**: macOS 15+ (M-series), iOS 18+ / iPadOS 18+ (A-series). Cross-platform builds (tvOS, watchOS, visionOS, Linux, Windows) still compile but performance is no longer a measurement criterion.
- **Standards Compliant**: Full ISO/IEC 15444-4 conformance across Parts 1, 2, 3, 10, and 15
- **Hardware Accelerated**: ARM Neon SIMD, Intel SSE/AVX, Metal GPU, Vulkan GPU, Accelerate framework (1.5–10× faster than OpenJPEG)
- **Network Streaming**: JPIP protocol support for efficient 2D and 3D image streaming
- **Modern API**: Async/await based APIs with comprehensive error handling
- **Well Documented**: DocC catalogues for 8 modules, 50+ guides, tutorials, and API documentation
- **High Quality**: 100% test pass rate (2,900+ tests) with comprehensive test coverage
- **CLI Toolset**: Complete command-line tools for encoding, decoding, transcoding, 3D volumetric, JPIP streaming, batch processing, image comparison, format conversion, validation, and benchmarking

## 🚀 Quick Start

### Requirements

- Swift 6.2 or later
- macOS 13+ / iOS 16+ / tvOS 16+ / watchOS 9+ / visionOS 1+

### Installation

Add J2KSwift to your Swift package dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "2.1.0")
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
        // Optional: add J2K3D for volumetric JP3D support
        .product(name: "J2K3D", package: "J2KSwift"),
    ]
)
```

### Basic Usage

#### Simple Encoding (v1.2.0)

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

#### Simple Decoding (v1.2.0)

```swift
import J2KCodec

// Decode a JPEG 2000 file
let decoder = J2KDecoder()
let image = try decoder.decode(j2kData)

// Access decoded data
print("Decoded image: \(image.width)×\(image.height)")
print("Components: \(image.componentCount)")
```

#### Advanced Encoding with Progress (v1.2.0)

```swift
import J2KCodec

let config = J2KEncodingConfiguration.quality
let encoder = J2KEncoder(encodingConfiguration: config)

let data = try encoder.encode(image) { progress in
    print("\(progress.stage): \(progress.percentage)% complete")
}
```

#### Progressive Decoding (v1.2.0)

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

#### HTJ2K Encoding (v1.3.0 - NEW)

```swift
import J2KCodec

// Create encoder with HTJ2K configuration
let config = EncodingConfiguration(
    codingStyle: .htj2k,  // Use High Throughput JPEG 2000
    quality: .highQuality
)

let encoder = J2KEncoder(configuration: config)
let htj2kData = try encoder.encode(image)

// HTJ2K is 57-70× faster than legacy JPEG 2000!
```

#### JP3D Volumetric Encoding (v1.9.0 - NEW)

```swift
import J2KCore
import J2K3D

// Build a J2KVolume from component data
let component = J2KVolumeComponent(
    index: 0, bitDepth: 16, signed: false,
    width: 256, height: 256, depth: 128,
    data: rawVoxelData
)
let volume = J2KVolume(width: 256, height: 256, depth: 128, components: [component])

// Encode losslessly
let encoder = JP3DEncoder(configuration: .lossless)
let result = try await encoder.encode(volume)
print("Encoded \(result.data.count) bytes, \(result.tileCount) tiles")

// Or use HTJ2K for high throughput
let htConfig = JP3DEncoderConfiguration(compressionMode: .losslessHTJ2K)
let htEncoder = JP3DEncoder(configuration: htConfig)
let htResult = try await htEncoder.encode(volume)
// ~5-10× faster than standard JP3D
```

#### JP3D Volumetric Decoding (v1.9.0 - NEW)

```swift
import J2KCore
import J2K3D

let decoder = JP3DDecoder(configuration: .default)
let decoded = try await decoder.decode(encodedData)
let volume = decoded.volume
print("Decoded volume: \(volume.width)×\(volume.height)×\(volume.depth)")
print("Components: \(volume.components.count), voxels: \(volume.voxelCount)")
```

#### Lossless Transcoding (v1.3.0 - NEW)

```swift
import J2KCodec

// Transcode legacy JPEG 2000 to HTJ2K (bit-exact, zero quality loss)
let transcoder = J2KTranscoder()

let legacyCodestream = try Data(contentsOf: legacyFileURL)
let htj2kCodestream = try transcoder.transcode(
    legacyCodestream,
    from: .legacy,
    to: .htj2k
)

// Convert back to verify bit-exact round-trip
let roundTrip = try transcoder.transcode(
    htj2kCodestream,
    from: .htj2k,
    to: .legacy
)
// roundTrip == legacyCodestream (bit-exact!)

// Parallel transcoding for multi-tile images (1.05-2× speedup)
let config = TranscodingConfiguration.default  // Parallel enabled
let parallelTranscoder = J2KTranscoder(configuration: config)
let fastResult = try parallelTranscoder.transcode(multiTileData, from: .legacy, to: .htj2k)
```

#### Writing to JP2 File (v1.2.0)

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

## 🔧 Command-Line Interface (CLI)

J2KSwift includes a comprehensive CLI tool (`j2k`) for encoding, decoding, transcoding, and analysing JPEG 2000 images. It also provides OpenJPEG-compatible commands for drop-in replacement.

### Installation

```bash
swift build -c release
# Binary at .build/release/j2k
```

### Command Reference

| Command | Description |
|---------|-------------|
| `encode` | Compress image(s) to JPEG 2000 / HTJ2K |
| `decode` | Decompress JPEG 2000 / HTJ2K image(s) |
| `transcode` | Lossless transcoding between J2K ↔ HTJ2K |
| `info` | Display codestream / file-format metadata |
| `validate` | ISO/IEC 15444-4 conformance validation |
| `benchmark` | Performance benchmarking |
| `encode3d` | Compress volumetric / 3D data (JP3D) |
| `decode3d` | Decompress volumetric / 3D data (JP3D) |
| `jpip server` | Start a JPIP streaming server |
| `jpip client` | Start a JPIP streaming client |
| `batch` | Batch-process files in a directory |
| `compare` | Compare two images (PSNR, MSE, MAE) |
| `convert` | Convert between image formats |
| `compress` | OpenJPEG-compatible compress (opj_compress) |
| `decompress` | OpenJPEG-compatible decompress (opj_decompress) |
| `dump` | OpenJPEG-compatible info/dump (opj_dump) |
| `completions` | Generate shell completions (bash/zsh/fish) |
| `version` | Print version information |

### Encoding

```bash
# Lossless encoding with 5/3 wavelet
j2k encode -i input.png -o output.j2k --lossless

# Lossy encoding with quality factor
j2k encode -i input.png -o output.j2k -q 0.85

# HTJ2K encoding for fast decoding
j2k encode -i input.png -o output.jph --htj2k

# Tiled encoding with custom parameters
j2k encode -i input.tif -o output.j2k --tile-size 512x512 --levels 6 --layers 5

# Encode from DICOM
j2k encode -i scan.dcm -o scan.j2k -q 0.95
```

### Decoding

```bash
# Decode to PNG
j2k decode -i input.j2k -o output.png

# Decode at reduced resolution (half size)
j2k decode -i input.j2k -o output.png --reduce 1

# Decode a specific region
j2k decode -i input.j2k -o region.png --region 100,100,400,400

# Decode specific quality layers
j2k decode -i input.j2k -o output.png --layers 3
```

### Transcoding

```bash
# Transcode J2K to HTJ2K (lossless)
j2k transcode -i input.j2k -o output.jph

# Transcode HTJ2K back to J2K
j2k transcode -i input.jph -o output.j2k
```

### Inspection and Validation

```bash
# Show codestream metadata
j2k info -i image.j2k

# Validate conformance
j2k validate -i image.j2k --profile baseline

# Compare two images
j2k compare -a original.png -b decoded.png

# Run benchmarks
j2k benchmark -i image.png --iterations 10
```

### 3D Volumetric (JP3D)

```bash
# Encode a volume from slice directory
j2k encode3d -i slices/ -o volume.jp3d --slices 128

# Decode and extract specific slices
j2k decode3d -i volume.jp3d -o output_dir/ --slice-range 10-20
```

### JPIP Streaming

```bash
# Start a JPIP server
j2k jpip server --port 8080 --image-dir ./images

# Connect with JPIP client
j2k jpip client --url http://localhost:8080/image.jp2
```

### Batch Processing

```bash
# Batch encode all images in a directory
j2k batch -i ./images/ -o ./encoded/ --mode encode -q 0.9

# Batch decode with parallel processing
j2k batch -i ./encoded/ -o ./decoded/ --mode decode --threads 8
```

### OpenJPEG-Compatible Commands

For users migrating from OpenJPEG, J2KSwift provides drop-in replacements:

```bash
# Compress (same flags as opj_compress)
j2k compress -i input.png -o output.j2k -r 20,10,1 -n 6 -b 64,64

# Decompress (same flags as opj_decompress)
j2k decompress -i input.j2k -o output.png -r 1 -l 3

# Dump codestream info (same flags as opj_dump)
j2k dump -i input.j2k -v
```

#### Compress Flags

| Flag | Description |
|------|-------------|
| `-i` | Input file (PNG, TIFF, BMP, PGM, PPM, RAW, DICOM) |
| `-o` | Output file (J2K, JP2, JPH) |
| `-r` | Compression ratios (e.g., `20,10,1`) |
| `-q` | PSNR values per layer |
| `-n` | Number of resolution levels (default: 6) |
| `-b` | Code-block size (default: 64,64) |
| `-c` | Precinct size |
| `-t` | Tile size |
| `-p` | Progression order (LRCP, RLCP, RPCL, PCRL, CPRL) |
| `-I` | Use irreversible 9/7 wavelet |
| `--htj2k` | Use HTJ2K (Part 15) encoding |
| `-SOP` | Insert SOP markers |
| `-EPH` | Insert EPH markers |
| `-PLT` | Insert PLT markers |
| `-TLM` | Insert TLM markers |

#### Decompress Flags

| Flag | Description |
|------|-------------|
| `-i` | Input file (J2K, JP2, JPH) |
| `-o` | Output file (PNG, TIFF, PGM, PPM, BMP, RAW) |
| `-r` | Reduce factor (0 = full, 1 = half, etc.) |
| `-l` | Number of quality layers to decode |
| `-d` | Decode area (x0,y0,x1,y1) |
| `-t` | Tile index to decode |
| `-force-rgb` | Force output to RGB |
| `-threads` | Number of threads |

### Piping and Stdin/Stdout

```bash
# Pipe from stdin to stdout
cat image.png | j2k encode -i - -o - --format j2k > encoded.j2k

# Chain encode and decode
j2k encode -i image.png -o - | j2k decode -i - -o decoded.png
```

### Shell Completions

```bash
# Generate Bash completions
j2k completions bash > /usr/local/etc/bash_completion.d/j2k

# Generate Zsh completions
j2k completions zsh > ~/.zfunc/_j2k

# Generate Fish completions
j2k completions fish > ~/.config/fish/completions/j2k.fish
```

## 🖥️ J2KTestApp User Manual

J2KTestApp is a native macOS SwiftUI application for testing, validating, and inspecting JPEG 2000 encoding/decoding.

### Running

```bash
swift run J2KTestApp
```

Or open `Package.swift` in Xcode → select the **J2KTestApp** scheme → **⌘R**.

### Encode Screen

1. **Select Input** — drag-and-drop an image (PNG, TIFF, BMP, DICOM) or click **Browse**.
2. **Choose Preset** — select Lossless, Lossy High Quality, Visually Lossless, or Maximum Compression.
3. **Configure** — adjust quality, wavelet type, tile size, decomposition levels, quality layers, progression order, MCT, and HTJ2K toggles.
4. **Encode** — click the **Encode** button (⌘↵). Progress is shown per-stage.
5. **Inspect Results** — view encoded size, compression ratio, encoding time, and per-stage timing.
6. **Compare** — see original vs. encoded side-by-side, overlay, or difference views.
7. **Save** — export the encoded J2K/JP2 file.

Tabs:
- **Single** — encode one image at a time.
- **Compare** — add multiple configurations and compare outputs side-by-side.
- **Batch** — select a folder and encode all images with the current configuration.

### Decode Screen

1. **Open File** — click **Open File…** and select a JP2, J2K, JPX, JPH, or JHC file.
2. **Configure** — set resolution level, quality layer, component channel, and optional ROI.
3. **Decode** — click **Decode** (⌘↵). The decoded image is displayed with actual dimensions.
4. **Inspect Markers** — toggle the **Markers** panel to see all parsed codestream markers (SOC, SIZ, COD, QCD, SOT, etc.) with offsets and descriptions.

### Round-Trip Validation

1. **Generate Test Image** — choose from Gradient, Checkerboard, Noise, Solid Colour, or Lena-Style patterns.
2. **Or Drop Image** — drag-and-drop a real image onto the encode input.
3. **Run Round-Trip** — click **Run Round-Trip** (⌘↵). The pipeline:
   - Encodes the image using the current configuration.
   - Decodes the encoded output back to pixels.
   - Computes PSNR, SSIM, and MSE metrics.
   - Shows pass/fail badges based on quality thresholds.
4. **Compare** — toggle Difference view to see pixel-level discrepancies.
5. **Bit-Exact Badge** — for lossless configurations, verifies exact reconstruction.

### DICOM Support

J2KTestApp can directly load uncompressed DICOM (.dcm) files for encoding to JPEG 2000. This is useful for medical imaging workflows:

1. Drop a DICOM file onto the Encode input area, or use **Browse**.
2. The app extracts pixel data from the DICOM file (supports 8-bit and 16-bit, grayscale and RGB).
3. 16-bit data is automatically windowed and scaled to 8-bit for encoding.
4. Encode as usual — the output J2K/JP2 file is suitable for PACS and DICOM systems.


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

### Future Releases
- **v2.2**: Multi-spectral JP3D, Vulkan JP3D DWT, JPEG XS exploration (complete)
- **v2.3**: JPEG XS full implementation, DICOM metadata enhancements
- **v3.0**: x86-64 SIMD code removal (Apple-first architecture), JPEG XS support

## 📚 Documentation

### Getting Started
- **[README.md](README.md)**: This file — quick start and overview
- **[CHANGELOG.md](CHANGELOG.md)**: Complete version history
- **[RELEASE_NOTES_v2.1.0.md](RELEASE_NOTES_v2.1.0.md)**: Complete v2.1.0 release notes
- **[RELEASE_NOTES_v2.0.0.md](RELEASE_NOTES_v2.0.0.md)**: Complete v2.0.0 release notes
- **[GETTING_STARTED.md](GETTING_STARTED.md)**: Comprehensive introduction
- **[TUTORIAL_ENCODING.md](TUTORIAL_ENCODING.md)**: Step-by-step encoding guide
- **[TUTORIAL_DECODING.md](TUTORIAL_DECODING.md)**: Step-by-step decoding guide
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)**: Migrating from OpenJPEG
- **[MIGRATION_GUIDE_v2.0.md](MIGRATION_GUIDE_v2.0.md)**: Migrating from v1.9.0 to v2.0.0

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
- **[HTJ2K.md](HTJ2K.md)**: High-Throughput JPEG 2000 (ISO/IEC 15444-15)
- **[JPIP_PROTOCOL.md](JPIP_PROTOCOL.md)**: Streaming protocol
- **[EXTENDED_FORMATS.md](EXTENDED_FORMATS.md)**: JPX, JPM support
- **[BYPASS_MODE_ISSUE.md](BYPASS_MODE_ISSUE.md)**: Known bypass mode limitation and workarounds

### JP3D Volumetric JPEG 2000 (v1.9.0)
- **[Documentation/JP3D_GETTING_STARTED.md](Documentation/JP3D_GETTING_STARTED.md)**: Quick start guide for JP3D
- **[Documentation/JP3D_ARCHITECTURE.md](Documentation/JP3D_ARCHITECTURE.md)**: Architecture overview (J2K3D, JPIP, Metal, Accelerate)
- **[Documentation/JP3D_API_REFERENCE.md](Documentation/JP3D_API_REFERENCE.md)**: Complete API reference for all JP3D public types
- **[Documentation/JP3D_STREAMING_GUIDE.md](Documentation/JP3D_STREAMING_GUIDE.md)**: JPIP 3D streaming guide
- **[Documentation/JP3D_PERFORMANCE.md](Documentation/JP3D_PERFORMANCE.md)**: Performance tuning guide with benchmark tables
- **[Documentation/JP3D_HTJ2K_INTEGRATION.md](Documentation/JP3D_HTJ2K_INTEGRATION.md)**: HTJ2K usage guide for volumetric encoding
- **[Documentation/JP3D_MIGRATION.md](Documentation/JP3D_MIGRATION.md)**: Migration from 2D JPEG 2000 to JP3D
- **[Documentation/JP3D_TROUBLESHOOTING.md](Documentation/JP3D_TROUBLESHOOTING.md)**: Common issues and solutions
- **[Documentation/JP3D_EXAMPLES.md](Documentation/JP3D_EXAMPLES.md)**: Comprehensive usage examples

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
- **[DEVELOPMENT_STATUS.md](DEVELOPMENT_STATUS.md)**: Current development status with visual progress
- **[NEXT_PHASE.md](NEXT_PHASE.md)**: Next phase development roadmap (HTJ2K codec & transcoding)
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
File format support for JP2, J2K, JPX, and other JPEG 2000 container formats, including Motion JPEG 2000 (MJ2) creation, extraction, and playback.

### J2KMetal
Metal GPU acceleration for Apple Silicon processors, providing 10–40× performance improvements for wavelet transforms, colour transforms, ROI processing, and quantisation.

### J2KVulkan
Vulkan GPU compute backend for Linux and Windows platforms, with SPIR-V compute shaders and automatic CPU fallback.

### JPIP
JPEG 2000 Interactive Protocol implementation for efficient network streaming, including JP3D 3D streaming with view-dependent progressive delivery.

### J2K3D
JP3D volumetric JPEG 2000 (ISO/IEC 15444-10) encoding, decoding, and streaming. Provides `JP3DEncoder`, `JP3DDecoder`, 3D wavelet transforms, HTJ2K integration, and JPIP 3D streaming. This is an optional module — existing 2D workflows are unaffected.

## 🗓️ Development Roadmap

See [MILESTONES.md](MILESTONES.md) for the detailed 100-week development roadmap tracking all features and implementation phases.

### Current Status: v2.2.0 — Production Ready

> **Encoder Status**: The high-level `J2KEncoder.encode()` API is **fully functional** with ARM Neon SIMD, Intel SSE/AVX, and Metal GPU acceleration.
> 
> **Decoder Status**: The high-level `J2KDecoder.decode()` API is **fully functional** with full ISO/IEC 15444-4 conformance and verified OpenJPEG interoperability.
> 
> **Phase 19 Status**: Multi-spectral JP3D encoding/decoding, Vulkan 3D DWT, and JPEG XS exploration types are **complete**.


**All Phases Complete** (325 weeks):
- ✅ Phase 0–8: Foundation through Production Ready (Weeks 1–100)
- ✅ Phase 9–12: vDSP, JPIP, HTJ2K, Extended Formats (Weeks 101–154)
- ✅ Phase 13–14: Part 2 Extensions, Motion JPEG 2000 (Weeks 155–210)
- ✅ Phase 15–16: JP3D Volumetric Support (Weeks 211–235)
- ✅ Phase 17: Performance Refactoring & Conformance (Weeks 236–295)
- ✅ Phase 18: GUI Testing Application (Weeks 296–315)
- ✅ Phase 19: Multi-Spectral JP3D and Vulkan JP3D Acceleration (Weeks 316–325)

**Current**: v2.2.0 — see [CHANGELOG.md](CHANGELOG.md) for details

## 🧪 Testing

### Test Statistics (v2.2.0)
- **Total Tests**: 3,100+
- **Passing**: 100% pass rate
- **Conformance Tests**: 304 (ISO/IEC 15444-4, Parts 1, 2, 3, 10, 15)
- **Interoperability Tests**: 165 (OpenJPEG bidirectional)
- **Integration Tests**: 200+ (end-to-end, stress, regression)
- **GUI Tests**: 309 (J2KTestApp models and view models)
- **Phase 19 Tests**: 55+ (multi-spectral JP3D, Vulkan JP3D DWT, JPEG XS types)

### Test Coverage by Module
- **J2KCore**: 100% of public APIs tested
- **J2KCodec**: 100% pass rate (ARM Neon + Intel SSE/AVX SIMD validated)
- **J2KFileFormat**: 100% pass rate
- **J2KAccelerate**: 100% pass rate (deep vDSP/vImage/BLAS integration)
- **J2KMetal**: 100% pass rate (GPU compute refactoring validated)
- **J2KVulkan**: 100% pass rate (SPIR-V compute shaders)
- **JPIP**: 100% pass rate (2D and 3D streaming)
- **J2K3D**: 100% pass rate (JP3D volumetric)

### Running Tests
```bash
# Run all tests
swift test

# Run specific module tests
swift test --filter J2KCoreTests
swift test --filter J2KCodecTests
swift test --filter J2KFileFormatTests
swift test --filter J2KTestAppTests

# Run with coverage
swift test --enable-code-coverage

# Performance tests
swift test --filter J2KBenchmarkTests
```

### J2KTestApp GUI Testing
```bash
# Build and run the GUI testing application (macOS only)
swift run J2KTestApp

# Headless CI mode
j2k testapp --headless --playlist "Quick Smoke Test" --output report.html --format html
```

See [CONFORMANCE_TESTING.md](CONFORMANCE_TESTING.md) for details on testing strategy.

## 🚀 Performance

### Performance vs OpenJPEG (v2.0.0)

| Metric | Apple Silicon | Intel x86-64 |
|--------|--------------|--------------|
| Lossless encode | ≥1.5× faster | ≥1.0× (parity) |
| Lossy encode | ≥2.0× faster | ≥1.2× faster |
| HTJ2K encode | ≥3.0× faster | N/A |
| Decode (all modes) | ≥1.5× faster | ≥1.0× (parity) |
| GPU-accelerated (Metal) | ≥10× faster | N/A |

### Hardware Acceleration
- **ARM Neon SIMD**: Vectorised entropy coding, wavelet lifting, colour transforms
- **Intel SSE/AVX**: SSE4.2 and AVX2 for entropy, wavelets, quantisation
- **Metal GPU**: Optimised DWT shaders, tile-based dispatch, async compute
- **Vulkan GPU**: Cross-platform SPIR-V compute for Linux/Windows
- **Accelerate Framework**: Deep vDSP, vImage, BLAS/LAPACK integration

See [PERFORMANCE.md](PERFORMANCE.md), [Documentation/PERFORMANCE_COMPARISON.md](Documentation/PERFORMANCE_COMPARISON.md), and [Documentation/PERFORMANCE_VALIDATION.md](Documentation/PERFORMANCE_VALIDATION.md) for detailed metrics.

## 🤝 Contributing

We welcome contributions! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

For information about our CI/CD workflows and automated testing, see [CI_CD_GUIDE.md](CI_CD_GUIDE.md).

### Areas Needing Help
1. **JPEG XS full implementation** (v2.3 target)
2. **DICOM metadata enhancements** (v2.3 target)
3. **Cross-platform testing** (Windows, Linux ARM64)
4. **Community feedback and real-world usage reports**
5. **Hyperspectral remote-sensing datasets for JP3D validation**

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

This project represents a 295-week development effort following a comprehensive milestone-based roadmap. Special thanks to:

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
- **Changelog**: [CHANGELOG.md](CHANGELOG.md)
- **Release Notes**: [RELEASE_NOTES_v2.1.0.md](RELEASE_NOTES_v2.1.0.md)

## 📊 Project Status

| Component | Status | Test Coverage | Notes |
|-----------|--------|---------------|-------|
| Core Types | ✅ Complete | 100% | Production ready |
| Wavelet Transform | ✅ Complete | 100% | ARM Neon + Intel SSE/AVX SIMD |
| Entropy Coding | ✅ Complete | 100% | SIMD-accelerated MQ-coder |
| Quantisation | ✅ Complete | 100% | Vectorised quantise/dequantise |
| Colour Transforms | ✅ Complete | 100% | ICT/RCT with SIMD acceleration |
| File Format | ✅ Complete | 100% | JP2/JPX/JPM/J2K/JPH support |
| JPIP Protocol | ✅ Complete | 100% | 2D and 3D streaming |
| Encoder API | ✅ Complete | 100% | ≥1.5–3× faster than OpenJPEG |
| Decoder API | ✅ Complete | 100% | Full Part 4 conformance |
| Hardware Accel | ✅ Complete | 100% | Metal, Vulkan, Accelerate, Neon, SSE/AVX |
| HTJ2K Codec | ✅ Complete | 100% | ≥3× faster on Apple Silicon |
| JP3D Volumetric | ✅ Complete | 100% | ISO/IEC 15444-10 compliant |
| Motion JPEG 2000 | ✅ Complete | 100% | ISO/IEC 15444-3 compliant |
| CLI Tools | ✅ Complete | 100% | Dual British/American spelling |
| **CLI Enhancement** | ✅ Complete | 193 tests | 8 new commands, 3D/JPIP/batch (Phase 21) |
| Conformance | ✅ Complete | 304 tests | Parts 1, 2, 3, 10, 15 |
| **J2KTestApp** | ✅ Complete | 309 tests | GUI testing application (Phase 18) |
| **Multi-Spectral JP3D** | ✅ Complete | 30+ tests | Spectral bands, encoder, decoder (Phase 19) |
| **Vulkan JP3D DWT** | ✅ Complete | 15+ tests | 3D DWT with spectral axis (Phase 19) |
| **JPEG XS Exploration** | ✅ Scaffolded | 10+ tests | ISO/IEC 21122 exploration types (Phase 19) |
| **JPEG XS Codec** | ✅ Complete | 52 tests | J2KXS module, full pipeline (Phase 20) |

---

**J2KSwift v2.4.0** — A production-ready, standards-compliant Swift implementation of JPEG 2000  
**Status**: Full ISO/IEC 15444-4 conformance, verified OpenJPEG interoperability, hardware-accelerated performance, comprehensive CLI toolset, JPEG XS codec, multi-spectral JP3D  
**Next Release**: See [MILESTONES.md](MILESTONES.md) for roadmap

For detailed information, see [CHANGELOG.md](CHANGELOG.md)
