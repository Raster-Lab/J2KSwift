# Motion JPEG 2000 Implementation Plan

This document outlines the implementation plan for Motion JPEG 2000 (ISO/IEC 15444-3) support in J2KSwift, including creation, extraction, and interoperability features with modern video codecs.

## Overview

Motion JPEG 2000 (MJ2) extends JPEG 2000 still image compression to motion sequences, providing high-quality video compression with frame-level access and editing capabilities. J2KSwift will implement comprehensive MJ2 support optimized for Apple platforms with cross-platform compatibility.

## Standards Compliance

- **ISO/IEC 15444-3**: Motion JPEG 2000 file format
- **ISO/IEC 14496-12**: Base media file format (ISO base format)
- **ITU-T T.802**: Information technology – JPEG 2000 image coding system: Motion JPEG 2000

## Implementation Phases

### Phase 15: Motion JPEG 2000 Core (v1.8.0, Weeks 191-210)

**Goal**: Implement foundational Motion JPEG 2000 creation and extraction capabilities.

This phase builds upon the complete Part 1 (Core) and Part 2 (Extensions) implementations, leveraging the Metal GPU acceleration from Phase 14 to provide high-performance video encoding and decoding.

## Feature 1: Motion JPEG 2000 Creation

### Overview

Enable creation of Motion JPEG 2000 files from sequences of JPEG 2000 images with full control over encoding parameters and output format.

### Architecture

```
J2KImage Sequence → MJ2Creator → Motion JPEG 2000 File
                          ↓
                    Configuration
                    - Frame rate
                    - Timescale
                    - Profile/level
                    - Metadata
```

### Key Components

#### MJ2Creator

Primary interface for Motion JPEG 2000 creation:

```swift
import J2KCore
import J2KFileFormat

/// Creates Motion JPEG 2000 files from JPEG 2000 image sequences
public actor MJ2Creator: Sendable {
    /// Configuration for Motion JPEG 2000 creation
    public struct Configuration: Sendable {
        /// Frame rate (frames per second)
        public var frameRate: Double
        
        /// Timescale (time units per second)
        public var timescale: UInt32
        
        /// MJ2 profile
        public var profile: MJ2Profile
        
        /// Video encoding parameters
        public var encoding: J2KEncodingConfiguration
        
        /// Optional audio tracks
        public var audioTracks: [MJ2AudioTrack]
        
        /// Metadata
        public var metadata: MJ2Metadata
    }
    
    /// Create Motion JPEG 2000 from image sequence
    public func create(
        from images: [J2KImage],
        configuration: Configuration
    ) async throws -> Data
    
    /// Create Motion JPEG 2000 by streaming frames
    public func beginStream(
        configuration: Configuration,
        outputURL: URL
    ) async throws -> MJ2StreamWriter
}

/// Streaming writer for large Motion JPEG 2000 files
public actor MJ2StreamWriter: Sendable {
    /// Add frame to stream
    public func addFrame(_ image: J2KImage) async throws
    
    /// Add frame with specific timestamp
    public func addFrame(
        _ image: J2KImage,
        timestamp: CMTime
    ) async throws
    
    /// Finalize and close the MJ2 file
    public func finalize() async throws
}
```

#### MJ2Profile

Defines Motion JPEG 2000 profiles for interoperability:

```swift
/// Motion JPEG 2000 profiles
public enum MJ2Profile: Sendable {
    /// Simple profile (baseline)
    case simple
    
    /// Broadcast profile
    case broadcast
    
    /// Cinema 2K profile (DCI)
    case cinema2K
    
    /// Cinema 4K profile (DCI)
    case cinema4K
    
    /// Custom profile with parameters
    case custom(MJ2ProfileParameters)
}

public struct MJ2ProfileParameters: Sendable {
    public var maxBitrate: UInt64
    public var maxFrameSize: (width: Int, height: Int)
    public var colorSpace: J2KColorSpace
    public var bitDepth: Int
}
```

#### MJ2Metadata

Container for Motion JPEG 2000 metadata:

```swift
/// Metadata for Motion JPEG 2000 files
public struct MJ2Metadata: Sendable {
    /// Title
    public var title: String?
    
    /// Author/creator
    public var author: String?
    
    /// Copyright information
    public var copyright: String?
    
    /// Creation date
    public var creationDate: Date?
    
    /// Description
    public var description: String?
    
    /// Custom metadata
    public var customMetadata: [String: String]
}
```

### Encoding Parameters

Full access to JPEG 2000 encoding parameters for each frame:

- **Compression**: Lossless or lossy with configurable quality
- **Wavelet**: 5/3 reversible or 9/7 irreversible filters
- **Tile size**: Configurable tiling for parallel processing
- **Progression order**: LRCP, RLCP, RPCL, PCRL, CPRL
- **Layers**: Multiple quality layers for progressive streaming
- **Color transform**: RCT (reversible) or ICT (irreversible)
- **Bit depth**: 8, 10, 12, 16-bit per component
- **Resolution levels**: Configurable DWT decomposition levels

### Performance Optimization

#### Apple Silicon Optimization

- **Metal GPU Acceleration**: Parallel frame encoding using Phase 14 Metal shaders
- **Batch Processing**: Encode multiple frames simultaneously on GPU
- **Hardware Encoders**: VideoToolbox integration when appropriate
- **Accelerate Framework**: vDSP for signal processing, vImage for conversions
- **Unified Memory**: Zero-copy operations on Apple Silicon
- **AMX Coprocessor**: Matrix operations for color transforms
- **NEON SIMD**: Optimized data movement and transformations

#### Cross-Platform Support

- **Linux ARM64**: NEON SIMD optimizations for ARM servers
- **Linux x86-64**: Isolated in `Sources/J2KAccelerate/x86/` (demarcated for removal)
- **Windows x86-64**: Isolated fallback implementations
- **Modular Architecture**: Platform-specific code clearly separated

### File Format Structure

Motion JPEG 2000 files follow the ISO base media file format:

```
MJ2 File Structure
├── ftyp (File Type Box)
├── mdat (Media Data Box) - Contains JPEG 2000 codestreams
└── moov (Movie Box)
    ├── mvhd (Movie Header Box)
    ├── trak (Track Box) - Video track
    │   ├── tkhd (Track Header Box)
    │   ├── mdia (Media Box)
    │   │   ├── mdhd (Media Header Box)
    │   │   ├── hdlr (Handler Reference Box)
    │   │   └── minf (Media Information Box)
    │   │       ├── vmhd (Video Media Header Box)
    │   │       ├── dinf (Data Information Box)
    │   │       └── stbl (Sample Table Box)
    │   │           ├── stsd (Sample Description Box)
    │   │           │   └── mjp2 (MJ2 Sample Entry)
    │   │           │       └── jp2h (JP2 Header Box)
    │   │           ├── stts (Time-to-Sample Box)
    │   │           ├── stsc (Sample-to-Chunk Box)
    │   │           ├── stsz (Sample Size Box)
    │   │           └── stco (Chunk Offset Box)
    │   └── edts (Edit Box) - Optional
    └── udta (User Data Box) - Optional metadata
```

### Example Usage

```swift
import J2KCore
import J2KFileFormat

// Create configuration
let config = MJ2Creator.Configuration(
    frameRate: 24.0,
    timescale: 24000,
    profile: .cinema4K,
    encoding: J2KEncodingConfiguration(
        quality: .lossless,
        compressionRatio: nil,
        waveletFilter: .reversible5x3,
        tileWidth: 1024,
        tileHeight: 1024
    ),
    audioTracks: [],
    metadata: MJ2Metadata(
        title: "Sample MJ2 Video",
        author: "J2KSwift",
        copyright: "2026"
    )
)

// Create MJ2 from image sequence
let creator = MJ2Creator()
let mj2Data = try await creator.create(
    from: imageSequence,
    configuration: config
)

// Save to file
try mj2Data.write(to: URL(fileURLWithPath: "output.mj2"))

// Streaming API for large files
let writer = try await creator.beginStream(
    configuration: config,
    outputURL: URL(fileURLWithPath: "large_output.mj2")
)

for image in imageSequence {
    try await writer.addFrame(image)
}

try await writer.finalize()
```

### Testing Strategy

- Unit tests for MJ2 box structure creation
- Integration tests with various frame counts and sizes
- Conformance tests against reference MJ2 files
- Performance benchmarks for encoding throughput
- Memory usage profiling for large sequences
- Cross-platform validation

## Feature 2: Motion JPEG 2000 Extraction

### Overview

Extract individual JPEG 2000 frames from Motion JPEG 2000 files with flexible naming options.

### Architecture

```
Motion JPEG 2000 File → MJ2Extractor → J2KImage Sequence
                              ↓
                        Naming Options
                        - Sequential numbering
                        - Delta time (ms)
                        - Custom timestamps
```

### Key Components

#### MJ2Extractor

Primary interface for frame extraction:

```swift
import J2KCore
import J2KFileFormat

/// Extracts frames from Motion JPEG 2000 files
public actor MJ2Extractor: Sendable {
    /// Frame naming strategy
    public enum FrameNaming: Sendable {
        /// Sequential numbering (frame_0001.jp2, frame_0002.jp2, ...)
        case sequential(prefix: String, digits: Int)
        
        /// Delta time in milliseconds from first frame
        case deltaTimeMilliseconds(prefix: String)
        
        /// Absolute timestamps
        case timestamp(prefix: String, format: TimestampFormat)
        
        /// Custom naming function
        case custom((Int, CMTime) -> String)
    }
    
    /// Timestamp format options
    public enum TimestampFormat: Sendable {
        case iso8601
        case timecode
        case milliseconds
        case frames
    }
    
    /// Extract all frames to directory
    public func extractAllFrames(
        from mj2Data: Data,
        toDirectory: URL,
        naming: FrameNaming
    ) async throws -> [URL]
    
    /// Extract specific frame
    public func extractFrame(
        from mj2Data: Data,
        index: Int
    ) async throws -> J2KImage
    
    /// Extract frame range
    public func extractFrameRange(
        from mj2Data: Data,
        range: Range<Int>
    ) async throws -> [J2KImage]
    
    /// Get MJ2 file information
    public func getInfo(from mj2Data: Data) async throws -> MJ2Info
}
```

#### MJ2Info

Information about Motion JPEG 2000 file:

```swift
/// Information about Motion JPEG 2000 file
public struct MJ2Info: Sendable {
    /// Total number of frames
    public var frameCount: Int
    
    /// Frame rate
    public var frameRate: Double
    
    /// Duration in seconds
    public var duration: Double
    
    /// Video dimensions
    public var dimensions: (width: Int, height: Int)
    
    /// Timescale
    public var timescale: UInt32
    
    /// Profile
    public var profile: MJ2Profile
    
    /// Bit depth
    public var bitDepth: Int
    
    /// Color space
    public var colorSpace: J2KColorSpace
    
    /// Frame timestamps
    public var timestamps: [CMTime]
    
    /// Metadata
    public var metadata: MJ2Metadata
    
    /// Audio tracks
    public var audioTracks: [MJ2AudioTrackInfo]
}
```

### Frame Naming Options

#### 1. Sequential Numbering (Default)

Standard sequential numbering with configurable padding:

```swift
// Extract with sequential numbering
let extractor = MJ2Extractor()
let urls = try await extractor.extractAllFrames(
    from: mj2Data,
    toDirectory: outputDir,
    naming: .sequential(prefix: "frame_", digits: 4)
)

// Output files:
// frame_0001.jp2
// frame_0002.jp2
// frame_0003.jp2
// ...
```

#### 2. Delta Time (Milliseconds)

Frame naming based on time offset from first frame:

```swift
// Extract with delta time in milliseconds
let urls = try await extractor.extractAllFrames(
    from: mj2Data,
    toDirectory: outputDir,
    naming: .deltaTimeMilliseconds(prefix: "frame_")
)

// Output files (at 24fps):
// frame_0000ms.jp2      (first frame)
// frame_0042ms.jp2      (1/24 second later)
// frame_0083ms.jp2      (2/24 seconds later)
// frame_0125ms.jp2
// ...
```

This option is particularly useful for:
- Variable frame rate video analysis
- Time-based synchronization with other media
- Scientific applications requiring precise timing
- Frame-accurate video editing workflows

#### 3. Absolute Timestamps

Full timestamp information:

```swift
// Extract with ISO 8601 timestamps
let urls = try await extractor.extractAllFrames(
    from: mj2Data,
    toDirectory: outputDir,
    naming: .timestamp(prefix: "frame_", format: .iso8601)
)

// Output files:
// frame_2026-02-18T23:00:00.000Z.jp2
// frame_2026-02-18T23:00:00.042Z.jp2
// ...
```

#### 4. Custom Naming

Flexible custom naming function:

```swift
// Custom naming with frame index and timestamp
let urls = try await extractor.extractAllFrames(
    from: mj2Data,
    toDirectory: outputDir,
    naming: .custom { index, timestamp in
        let seconds = CMTimeGetSeconds(timestamp)
        return String(format: "scene_001_frame_%04d_%.3fs.jp2", 
                     index, seconds)
    }
)
```

### Performance Optimization

#### Apple Silicon Optimization

- **Metal GPU Acceleration**: Parallel frame decoding using GPU
- **Batch Decoding**: Decode multiple frames simultaneously
- **VideoToolbox**: Hardware decoder integration when available
- **Accelerate Framework**: Optimized image processing
- **Memory-Mapped I/O**: Efficient access to large MJ2 files
- **Concurrent Extraction**: Parallel frame extraction with controlled concurrency

#### Memory Management

- **Streaming Extraction**: Process frames one at a time for memory efficiency
- **Lazy Loading**: On-demand frame access without loading entire file
- **Buffer Pooling**: Reuse buffers for multiple frames
- **Progressive Loading**: Load and decode frames in background

### Example Usage

```swift
import J2KCore
import J2KFileFormat

let extractor = MJ2Extractor()

// Get file information
let info = try await extractor.getInfo(from: mj2Data)
print("Frames: \(info.frameCount)")
print("Duration: \(info.duration)s")
print("Frame rate: \(info.frameRate)fps")

// Extract all frames with sequential numbering
let urls = try await extractor.extractAllFrames(
    from: mj2Data,
    toDirectory: outputDir,
    naming: .sequential(prefix: "frame_", digits: 4)
)

// Extract with delta time naming
let deltaUrls = try await extractor.extractAllFrames(
    from: mj2Data,
    toDirectory: outputDir,
    naming: .deltaTimeMilliseconds(prefix: "frame_")
)

// Extract specific frames
let firstFrame = try await extractor.extractFrame(
    from: mj2Data,
    index: 0
)

// Extract frame range
let frames = try await extractor.extractFrameRange(
    from: mj2Data,
    range: 0..<10
)
```

### Testing Strategy

- Unit tests for all naming strategies
- Validation of delta time calculations
- Frame accuracy tests
- Large file extraction performance
- Memory usage profiling
- Error handling for corrupted files

## Feature 3: H.264/H.265 Interoperability

### Overview

Enable bidirectional conversion between Motion JPEG 2000 and H.264/H.265 codecs, leveraging platform-native tools for optimal performance.

### Architecture

```
                    ┌─────────────────────────┐
                    │  MJ2VideoConverter      │
                    └───────────┬─────────────┘
                                │
                ┌───────────────┴────────────────┐
                │                                 │
        ┌───────▼────────┐              ┌────────▼───────┐
        │  MJ2 → H.264/5 │              │  H.264/5 → MJ2 │
        └───────┬────────┘              └────────┬───────┘
                │                                 │
    ┌───────────┴────────────┐       ┌───────────┴────────────┐
    │                        │       │                        │
┌───▼────┐          ┌────────▼──┐  ┌─▼────────┐      ┌──────▼─────┐
│VideoTBX│  (Apple) │x264/x265  │  │VideoTBX  │(Apple│x264/x265   │
│(Native)│          │(Fallback) │  │(Native)  │      │(Fallback)  │
└────────┘          └───────────┘  └──────────┘      └────────────┘
```

### Platform Strategy

#### Primary Target: Apple Platforms

**Target Devices**:
- **Apple Silicon**: M1, M2, M3, M4 families (Mac)
- **A-Series**: A12 Bionic and later (iPhone, iPad)
- **Modern Apple OS**: macOS 12+, iOS 15+, tvOS 15+

**Optimization Priority**:
1. **Apple Silicon** (ARM64) - Primary development target
2. **Modern mobile processors** (A-series, Apple Silicon)
3. **Recent Apple operating systems** - Full API access

**Explicit Performance Targets**:
- Hardware-accelerated encoding/decoding using VideoToolbox
- Metal GPU acceleration for preprocessing/postprocessing
- Accelerate framework for color space conversions
- Unified memory architecture exploitation
- Power-efficient encoding for mobile devices
- Real-time encoding/decoding on modern devices

#### x86-64 Code Demarcation

All x86-64-specific code paths must be:

1. **Clearly Isolated**: Separated into dedicated files
   ```
   Sources/
   └── J2KAccelerate/
       └── x86/
           ├── J2KVideoConverter_x86.swift
           └── MJ2VideoToolbox_x86.swift
   ```

2. **Explicitly Guarded**: Use compilation guards
   ```swift
   #if arch(x86_64)
   // x86-64 specific fallback implementation
   // WARNING: This code path is for compatibility only
   // and may be removed in future versions
   #endif
   ```

3. **Modularized**: Separate compilation units for future removal
4. **Documented**: Clear comments indicating deprecation path
   ```swift
   /// x86-64 fallback implementation
   /// 
   /// - Warning: This implementation is provided for compatibility
   ///   with older Intel-based Macs and will be removed in a future
   ///   major version. Primary support is for Apple Silicon.
   @available(*, deprecated, message: "x86-64 support will be removed")
   ```

5. **Optional Retention**: Keep for Linux x86-64 server use cases
   - Clearly marked as non-primary support
   - Limited testing and optimization
   - No performance guarantees on x86-64

### Key Components

#### MJ2VideoConverter

Primary interface for video codec conversion:

```swift
import J2KCore
import J2KFileFormat

#if canImport(VideoToolbox)
import VideoToolbox
#endif

/// Converts between Motion JPEG 2000 and H.264/H.265
public actor MJ2VideoConverter: Sendable {
    /// Video codec types
    public enum VideoCodec: Sendable {
        case h264
        case h265
        case motionJPEG2000
    }
    
    /// Conversion configuration
    public struct ConversionConfiguration: Sendable {
        /// Target codec
        public var targetCodec: VideoCodec
        
        /// Bitrate (bits per second)
        public var bitrate: UInt64?
        
        /// Quality (0.0-1.0)
        public var quality: Double
        
        /// Use hardware acceleration when available
        public var useHardwareAcceleration: Bool
        
        /// Color space
        public var colorSpace: J2KColorSpace
        
        /// Profile (for H.264/H.265)
        public var profile: VideoProfile?
        
        /// Encoder for non-Apple platforms
        public var fallbackEncoder: FallbackEncoder
    }
    
    /// Video profile for H.264/H.265
    public enum VideoProfile: Sendable {
        // H.264 profiles
        case h264Baseline
        case h264Main
        case h264High
        
        // H.265 profiles
        case hevcMain
        case hevcMain10
        case hevcMain422_10
    }
    
    /// Fallback encoder options for non-Apple platforms
    public enum FallbackEncoder: Sendable {
        case systemDefault
        case x264
        case x265
        case custom(String)
    }
    
    /// Convert MJ2 to H.264/H.265
    public func convertFromMJ2(
        mj2Data: Data,
        configuration: ConversionConfiguration
    ) async throws -> Data
    
    /// Convert H.264/H.265 to MJ2
    public func convertToMJ2(
        videoData: Data,
        mj2Configuration: MJ2Creator.Configuration
    ) async throws -> Data
}
```

#### Platform-Specific Implementations

##### Apple Platforms (VideoToolbox)

```swift
#if canImport(VideoToolbox)
import VideoToolbox

/// VideoToolbox-based implementation (Apple platforms)
actor MJ2VideoToolboxConverter: Sendable {
    /// Convert using VideoToolbox hardware encoder
    func encodeWithVideoToolbox(
        frames: [J2KImage],
        configuration: MJ2VideoConverter.ConversionConfiguration
    ) async throws -> Data {
        // Create compression session
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: frames[0].width,
            height: frames[0].height,
            codecType: configuration.targetCodec == .h264 
                ? kCMVideoCodecType_H264 
                : kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            throw J2KError.hardwareAcceleratorUnavailable
        }
        
        // Configure for optimal Apple Silicon performance
        // - Enable hardware acceleration
        // - Use Accelerate for preprocessing
        // - Leverage Metal for color conversion
        // - Optimize for power efficiency on mobile
        
        // ... encoding implementation
    }
    
    /// Decode using VideoToolbox hardware decoder
    func decodeWithVideoToolbox(
        videoData: Data
    ) async throws -> [J2KImage] {
        // Hardware-accelerated decoding
        // ... implementation
    }
}
#endif
```

##### Non-Apple Platforms (Fallback)

```swift
/// Fallback implementation using x264/x265 libraries
/// 
/// This implementation provides basic conversion support for platforms
/// without VideoToolbox. Performance and features are limited compared
/// to Apple platform implementation.
actor MJ2FallbackConverter: Sendable {
    func encodeWithX264(
        frames: [J2KImage],
        configuration: MJ2VideoConverter.ConversionConfiguration
    ) async throws -> Data {
        // x264 encoding for H.264
        // Limited to software encoding
        // ... implementation
    }
    
    func encodeWithX265(
        frames: [J2KImage],
        configuration: MJ2VideoConverter.ConversionConfiguration
    ) async throws -> Data {
        // x265 encoding for H.265
        // Limited to software encoding
        // ... implementation
    }
}

#if arch(x86_64)
/// x86-64 specific optimizations (compatibility only)
///
/// - Warning: This code path is demarcated for future removal.
///   Primary support is for ARM64 (Apple Silicon and ARM servers).
///   x86-64 code is retained optionally for Linux compatibility only.
@available(*, deprecated, message: "x86-64 specific code will be removed in future version")
actor MJ2VideoConverter_x86: Sendable {
    // x86-64 specific SIMD optimizations
    // ... implementation
}
#endif
```

### Performance Optimization Strategy

#### Apple Platform Optimizations

##### 1. VideoToolbox Hardware Acceleration

```swift
/// Apple-optimized video encoding pipeline
actor MJ2AppleEncodingPipeline {
    /// Hardware encoder using VideoToolbox
    let videoToolboxEncoder: VTCompressionSession
    
    /// Metal pipeline for preprocessing
    let metalPreprocessor: MTLComputePipelineState
    
    /// Accelerate for color conversions
    let accelerateConverter: vImage_Buffer
    
    func encodeFrame(_ frame: J2KImage) async throws {
        // 1. Convert pixel format using vImage (Accelerate)
        //    - Optimized for Apple Silicon
        //    - Zero-copy when possible
        
        // 2. Apply preprocessing with Metal
        //    - Color space conversion on GPU
        //    - Scaling/cropping with Metal Performance Shaders
        
        // 3. Hardware encode with VideoToolbox
        //    - H.264/H.265 hardware encoder
        //    - Real-time performance on modern devices
        
        // 4. Optimize for power efficiency
        //    - Quality of Service (QoS) classes
        //    - Thermal-aware encoding
        //    - Battery-aware on iOS
    }
}
```

##### 2. Accelerate Framework Integration

```swift
import Accelerate

/// Accelerate-optimized color space conversions
struct MJ2AccelerateColorConverter {
    /// Convert using vImage
    func convertColorSpace(
        _ image: J2KImage,
        to targetSpace: J2KColorSpace
    ) throws -> vImage_Buffer {
        // vImage conversion optimized for:
        // - NEON SIMD on Apple Silicon
        // - AMX coprocessor for matrix operations
        // - Optimal cache utilization
    }
    
    /// Scale image using vImage
    func scaleImage(
        _ buffer: vImage_Buffer,
        to size: (width: Int, height: Int)
    ) throws -> vImage_Buffer {
        // High-quality scaling with Lanczos
        // Hardware-accelerated on Apple platforms
    }
}
```

##### 3. Metal GPU Acceleration

```swift
import Metal

/// Metal-based video preprocessing
actor MJ2MetalPreprocessor {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let colorConversionPipeline: MTLComputePipelineState
    
    /// GPU-accelerated preprocessing
    func preprocessFrame(_ frame: J2KImage) async throws -> MTLTexture {
        // Metal compute shaders for:
        // - Color space conversion (YCbCr ↔ RGB)
        // - Bit depth conversion
        // - Scaling and cropping
        // - Denoising (optional)
        // 
        // Optimized for Apple Silicon GPUs
    }
}
```

##### 4. Platform-Optimized Networking

```swift
import Network

/// Network-optimized video streaming
actor MJ2NetworkStreamer {
    let connection: NWConnection
    
    /// Stream using Network.framework
    func streamVideo(
        _ videoData: Data,
        to endpoint: NWEndpoint
    ) async throws {
        // Network.framework features:
        // - QUIC protocol support
        // - HTTP/3 integration
        // - Efficient TLS
        // - Optimized for Apple platforms
        // - Better throughput and latency
    }
}
```

### Fallback Options

#### Non-Apple Platforms

When Apple frameworks are unavailable, use:

1. **System Native Tools** (First Priority)
   - Linux: GStreamer, FFmpeg (system installations)
   - Windows: Media Foundation

2. **VideoLAN Libraries** (Second Priority)
   - x264: H.264 encoding
   - x265: H.265 encoding
   - Portable and open source

3. **Software Fallbacks** (Last Resort)
   - Pure Swift implementations (limited performance)

### Example Usage

```swift
import J2KCore
import J2KFileFormat

// Create converter
let converter = MJ2VideoConverter()

// Configure conversion
let config = MJ2VideoConverter.ConversionConfiguration(
    targetCodec: .h265,
    bitrate: 10_000_000, // 10 Mbps
    quality: 0.9,
    useHardwareAcceleration: true,
    colorSpace: .rec2020,
    profile: .hevcMain10,
    fallbackEncoder: .x265
)

// Convert MJ2 to H.265
let h265Data = try await converter.convertFromMJ2(
    mj2Data: mj2FileData,
    configuration: config
)

// Convert H.265 back to MJ2
let mj2Config = MJ2Creator.Configuration(
    frameRate: 24.0,
    timescale: 24000,
    profile: .cinema4K,
    encoding: .lossless,
    audioTracks: [],
    metadata: MJ2Metadata()
)

let newMJ2Data = try await converter.convertToMJ2(
    videoData: h265Data,
    mj2Configuration: mj2Config
)

// Platform-aware encoding
#if canImport(VideoToolbox)
print("Using VideoToolbox hardware acceleration")
// Optimal performance on Apple platforms
#else
print("Using fallback encoder: \(config.fallbackEncoder)")
// Software fallback on other platforms
#endif
```

### Performance Benchmarks

#### Expected Performance (Apple Silicon)

| Operation | Apple Silicon | x86-64 Mac | Notes |
|-----------|--------------|------------|-------|
| MJ2 → H.265 (4K) | 60+ fps | 20-30 fps | Hardware encode |
| H.265 → MJ2 (4K) | 120+ fps | 40-50 fps | Hardware decode |
| MJ2 → H.264 (1080p) | 240+ fps | 100+ fps | Hardware encode |
| Color Conversion | 15-25× faster | 5-10× faster | Metal + Accelerate |

#### x86-64 Performance Notes

- x86-64 performance is **not optimized**
- Provided for compatibility only
- Limited testing and validation
- May be removed in future major versions
- Use ARM64 platforms for production workloads

### Testing Strategy

- Unit tests for conversion accuracy
- Performance benchmarks on target hardware
- Hardware acceleration validation
- Fallback mechanism testing
- Cross-platform compatibility tests
- Round-trip conversion validation
- Quality metrics (PSNR, SSIM)

## Implementation Timeline

### Week 191-195: MJ2 Core Foundation
- [ ] MJ2Creator implementation
- [ ] File format structure (boxes, atoms)
- [ ] Basic encoding pipeline
- [ ] Unit tests for MJ2 creation
- [ ] Documentation

### Week 196-200: MJ2 Extraction
- [ ] MJ2Extractor implementation
- [ ] Frame naming strategies
- [ ] Delta time calculation
- [ ] Memory-efficient extraction
- [ ] Unit tests for extraction
- [ ] Documentation

### Week 201-205: VideoToolbox Integration
- [ ] H.264/H.265 conversion (Apple)
- [ ] Hardware acceleration
- [ ] Accelerate framework integration
- [ ] Metal preprocessing
- [ ] Performance optimization
- [ ] Documentation

### Week 206-208: Fallback Implementations
- [ ] x264/x265 integration
- [ ] System tool interfaces
- [ ] x86-64 code isolation
- [ ] Cross-platform testing
- [ ] Documentation

### Week 209-210: Testing & Release
- [ ] Comprehensive test suite
- [ ] Performance benchmarks
- [ ] Documentation review
- [ ] Release preparation (v1.8.0)
- [ ] RELEASE_NOTES_v1.8.0.md
- [ ] RELEASE_CHECKLIST_v1.8.0.md

## Architectural Principles

### Apple-First Design

1. **Primary Target**: Apple Silicon and modern A-series processors
2. **Full API Access**: Leverage complete Apple framework stack
3. **Hardware Acceleration**: VideoToolbox, Metal, Accelerate
4. **Power Efficiency**: Optimize for battery-powered devices
5. **Quality of Service**: Proper QoS classes for background encoding

### Cross-Platform Strategy

1. **Modular Architecture**: Platform-specific modules
2. **Graceful Degradation**: Fallback to software implementations
3. **Clear Interfaces**: Abstract platform differences
4. **Minimal Dependencies**: Reduce external library requirements

### x86-64 Demarcation

1. **Isolation**: Separate directories and compilation units
2. **Guard Clauses**: `#if arch(x86_64)` for all x86-64 code
3. **Deprecation Warnings**: Clear compiler messages
4. **Documentation**: Migration guides for ARM64
5. **Optional Retention**: Linux compatibility consideration

### Performance Philosophy

1. **Hardware First**: Use hardware acceleration when available
2. **Apple Optimization**: Maximize Apple framework usage
3. **Parallel Processing**: Concurrent encoding/decoding
4. **Memory Efficiency**: Streaming and lazy loading
5. **Power Awareness**: Thermal and battery considerations

## Module Structure

```
Sources/
├── J2KCore/
│   ├── MJ2Types.swift              # Core MJ2 types
│   └── MJ2Configuration.swift      # Configuration types
├── J2KFileFormat/
│   ├── MJ2Creator.swift            # MJ2 creation
│   ├── MJ2Extractor.swift          # Frame extraction
│   ├── MJ2FileFormat.swift         # File structure
│   └── MJ2Boxes.swift              # ISO box parsing/writing
├── J2KVideoCodec/                  # New module
│   ├── MJ2VideoConverter.swift     # Main converter
│   ├── Apple/
│   │   ├── MJ2VideoToolbox.swift  # VideoToolbox integration
│   │   ├── MJ2MetalPreproc.swift  # Metal preprocessing
│   │   └── MJ2Accelerate.swift    # Accelerate optimization
│   ├── Fallback/
│   │   ├── MJ2SystemEncoder.swift # System encoder interface
│   │   └── MJ2X264X265.swift      # x264/x265 wrapper
│   └── x86/                        # x86-64 isolation
│       └── MJ2VideoConverter_x86.swift
└── Tests/
    ├── J2KFileFormatTests/
    │   ├── MJ2CreatorTests.swift
    │   └── MJ2ExtractorTests.swift
    └── J2KVideoCodecTests/
        ├── MJ2VideoConverterTests.swift
        └── MJ2PerformanceTests.swift
```

## API Design Principles

### Concurrency

- **Actor-based**: All major components are `actor` types
- **Async/Await**: Modern Swift concurrency throughout
- **Sendable**: All types are `Sendable` for thread safety
- **Structured Concurrency**: Task groups for parallel operations

### Error Handling

```swift
public enum MJ2Error: Error, Sendable {
    case invalidFile(String)
    case unsupportedCodec(String)
    case hardwareEncoderUnavailable
    case conversionFailed(String)
    case insufficientMemory
    case platformNotSupported
}
```

### Type Safety

- Strong typing for all parameters
- Compile-time checks for platform features
- No force unwrapping in public APIs
- Comprehensive documentation

## Integration with Existing Modules

### J2KCore Integration

- Use existing `J2KImage` type
- Leverage `J2KComponent` for multi-component video
- Reuse error handling patterns
- Compatible with color space definitions

### J2KCodec Integration

- Share encoding/decoding pipelines
- Reuse wavelet and quantization code
- Common rate-distortion optimization
- Consistent quality metrics

### J2KAccelerate Integration

- Extend GPU acceleration to video
- Share Metal shaders with still image processing
- Unified Accelerate framework usage
- Common SIMD optimizations

### JPIP Integration (Future)

- Streaming MJ2 over JPIP
- Frame-level progressive delivery
- Adaptive quality for video streaming
- Integration with existing JPIP module

## Use Cases

### Professional Video Production

- High-quality intermediate format
- Frame-accurate editing
- Lossless video workflows
- Color grading and VFX

### Digital Cinema

- DCI-compliant encoding
- 2K/4K cinema workflows
- Color space management
- High bit-depth support

### Broadcasting

- Broadcast-quality encoding
- Real-time encoding on Apple hardware
- Network streaming with JPIP
- Multi-resolution encoding

### Archival

- Lossless video archival
- Long-term preservation
- Format migration (H.264/5 to MJ2)
- Frame-level access

### Scientific Imaging

- High-precision video data
- Frame-accurate analysis
- Multi-spectral video
- Uncompressed and lossless options

## Quality Assurance

### Testing Requirements

1. **Unit Tests**: >90% code coverage
2. **Integration Tests**: End-to-end workflows
3. **Performance Tests**: Benchmarks on target hardware
4. **Conformance Tests**: Standards compliance
5. **Cross-Platform Tests**: All supported platforms
6. **Stress Tests**: Large files and long sequences

### Validation

- Reference file validation against ISO standard
- Round-trip conversion accuracy
- Hardware acceleration validation
- Memory leak detection
- Performance regression tracking

### Documentation

- API documentation (100% coverage)
- Usage examples for all features
- Performance tuning guides
- Platform-specific guidelines
- Migration guides

## Future Enhancements

### Phase 16+: Advanced Features (v1.9.0+)

- **Audio Integration**: Complete audio track support
- **JPIP Streaming**: Stream MJ2 over JPIP
- **Advanced Metadata**: Timecode, closed captions, etc.
- **Multi-Track Support**: Multiple video/audio tracks
- **Edit Lists**: Non-linear playback support
- **Fragmented MJ2**: Progressive download support

### Potential Optimizations

- **Machine Learning**: ML-based encoding optimization
- **Adaptive Encoding**: Content-aware parameter selection
- **Cloud Processing**: Distributed encoding for large files
- **Real-Time Preview**: Low-latency preview during encoding

## References

### Standards

- **ISO/IEC 15444-3**: Motion JPEG 2000
- **ISO/IEC 14496-12**: ISO base media file format
- **ITU-T T.802**: Information technology – JPEG 2000 image coding system: Motion JPEG 2000
- **ITU-T H.264**: Advanced video coding (AVC)
- **ITU-T H.265**: High efficiency video coding (HEVC)

### Apple Documentation

- [VideoToolbox Framework](https://developer.apple.com/documentation/videotoolbox)
- [Accelerate Framework](https://developer.apple.com/documentation/accelerate)
- [Metal Framework](https://developer.apple.com/documentation/metal)
- [Network Framework](https://developer.apple.com/documentation/network)
- [Core Media](https://developer.apple.com/documentation/coremedia)

### Related Documentation

- [MILESTONES.md](MILESTONES.md): Development roadmap
- [EXTENDED_FORMATS.md](EXTENDED_FORMATS.md): Extended image format support
- [HARDWARE_ACCELERATION.md](HARDWARE_ACCELERATION.md): Hardware acceleration guide
- [JPIP_PROTOCOL.md](JPIP_PROTOCOL.md): JPIP streaming protocol
- [CROSS_PLATFORM.md](CROSS_PLATFORM.md): Cross-platform support

## Conclusion

Motion JPEG 2000 support in J2KSwift provides:

- **Complete MJ2 Implementation**: Creation and extraction
- **Modern Codec Integration**: H.264/H.265 interoperability
- **Apple-First Performance**: Optimized for Apple Silicon
- **Cross-Platform Support**: Graceful fallbacks for other platforms
- **Production Ready**: Professional workflows and quality
- **Future-Proof**: Clean architecture for future enhancements

This implementation positions J2KSwift as a comprehensive solution for modern video workflows, with exceptional performance on Apple platforms and reliable operation across all supported platforms.

---

**Last Updated**: 2026-02-18  
**Target Version**: 1.8.0 (Phase 15)  
**Status**: Implementation Plan  
**Related Phases**: Phase 13 (Part 2 Extensions), Phase 14 (Metal Acceleration)
