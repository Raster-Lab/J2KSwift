# JP3D (JPEG 2000 Part 10) Implementation Plan

This document outlines the implementation plan for JP3D (ISO/IEC 15444-10) support in J2KSwift, providing volumetric (3D) JPEG 2000 encoding and decoding with streaming capabilities for both client and server use cases.

## Overview

JP3D extends JPEG 2000 to three-dimensional image data, enabling efficient compression and progressive delivery of volumetric datasets. J2KSwift will implement comprehensive JP3D support optimized for Apple Silicon with pure Swift implementation, ensuring symmetrical functionality for both client-side consumption and server-side generation.

## Standards Compliance

- **ISO/IEC 15444-10**: JPEG 2000 Part 10 - Extensions for three-dimensional data
- **ISO/IEC 15444-1**: JPEG 2000 Part 1 - Core coding system (foundation)
- **ISO/IEC 15444-4**: JPEG 2000 Part 4 - Compliance testing (mandatory validation)
- **ISO/IEC 15444-9**: JPEG 2000 Part 9 - JPIP (extended for 3D streaming)
- **ISO/IEC 15444-15**: JPEG 2000 Part 15 - HTJ2K (optional integration)

### Mandatory Compliance Testing

All JP3D implementations **must** undergo comprehensive compliance validation:

- **Part 4 Compliance**: Verify adherence to ISO/IEC 15444-4 conformance requirements
- **Pre-Release Validation**: Perform and document compliance testing before every release
- **Test Suite Integration**: Automated compliance checks in CI/CD pipeline
- **Documentation**: Maintain compliance verification reports in `Documentation/Compliance/`
- **Release Checklist**: Explicit compliance verification as mandatory release gate

**Compliance Artifacts**:
- `Tests/J2KComplianceTests/JP3DComplianceTests.swift` - Automated compliance tests
- `Documentation/Compliance/JP3D_CONFORMANCE_REPORT.md` - Detailed compliance report
- `Scripts/validate-jp3d-compliance.sh` - Compliance validation script
- Test vectors from ISO/IEC 15444-4 compliance testing suite

## Architecture Principles

### Pure Swift Native Implementation

- **100% Swift**: No mandatory C/C++ dependencies
- **Swift 6 Concurrency**: Full strict concurrency compliance with actors and `async`/`await`
- **Type Safety**: Leverage Swift's type system for correctness and maintainability
- **Memory Safety**: No unsafe operations without clear documentation and justification
- **Cross-Platform Core**: Foundation-based implementation works across all Swift platforms

### Apple-First Platform Strategy

**Primary Target**: Apple Silicon (M-series and A-series) processors running modern Apple operating systems (macOS 14+, iOS 17+, visionOS 1+, tvOS 17+, watchOS 10+)

**Optimization Focus**:
- Apple Silicon architecture (ARM64 only for Apple platforms)
- Unified memory architecture exploitation
- Apple Neural Engine for potential ML-based operations
- Power efficiency for mobile and battery-powered devices

**x86-64 Code Isolation**:
- All x86-64 specific code **must** be in `Sources/J2KAccelerate/x86/` directory
- Use `#if arch(x86_64)` guards for x86-64 paths
- Add `@available(*, deprecated, message: "x86-64 support will be removed in future versions")` warnings
- Clearly document x86-64 code for potential removal
- Retain for Linux compatibility only; Apple platforms use ARM64 exclusively

### Apple Framework Integration

**Accelerate Framework** (Primary for CPU operations):
- `vDSP`: Vectorized signal processing for wavelet transforms
- `vImage`: Image format conversions and color transforms
- `vForce`: Mathematical operations for quantization
- `BNNS`: Neural network operations for ML-enhanced encoding
- `BLAS/LAPACK`: Matrix operations for multi-component transforms
- `AMX`: Apple Matrix coprocessor (automatic via Accelerate on Apple Silicon)
- `NEON`: ARM SIMD optimizations (128-bit vectors)

**Metal Framework** (Primary for GPU operations):
- GPU-accelerated 3D wavelet transforms
- Parallel entropy coding operations
- Volume rendering and visualization
- 3D texture processing pipelines
- Compute shaders for volumetric operations
- Metal Performance Shaders (MPS) for convolution and transforms
- Async compute queues for concurrent CPU-GPU execution

**Network.framework** (Modern networking):
- QUIC protocol support for JPIP streaming
- HTTP/3 for improved delivery performance
- Efficient TLS with Network.framework
- Low-latency streaming optimizations
- Background transfer service integration (iOS)
- Network path monitoring for adaptive delivery

**Additional Apple Frameworks**:
- `Compression`: Native compression for auxiliary data
- `os.log`: Unified logging with privacy-preserving logging
- `os.signpost`: Performance instrumentation and profiling
- `Dispatch`: Grand Central Dispatch for concurrent operations

## Implementation Phases

### Phase 16: JP3D Core Implementation (v1.9.0, Weeks 211-235)

**Goal**: Implement foundational 3D JPEG 2000 encoding and decoding with Part 10 compliance.

This phase builds upon the complete Part 1 (Core), Part 2 (Extensions), Metal GPU acceleration (Phase 14), and Motion JPEG 2000 (Phase 15) implementations.

## Feature 1: JP3D Core Encoding and Decoding

### Overview

Enable encoding and decoding of volumetric (3D) JPEG 2000 data with support for streaming and scalable decoding, designed for symmetrical use on both client and server.

### Architecture

```
3D Volume Data → JP3DEncoder → JP3D File/Stream
                       ↓
                 Configuration
                 - 3D tiling
                 - Z-dimension handling
                 - Progression order
                 - Scalability modes

JP3D File/Stream → JP3DDecoder → 3D Volume Data
                        ↓
                  Decoding Options
                  - Spatial region
                  - Resolution level
                  - Quality layers
                  - Progressive delivery
```

### Key Components

#### JP3D Volume Representation

```swift
import J2KCore
import J2KFileFormat

/// Represents a 3D volumetric image with multiple components
public struct J2KVolume: Sendable {
    /// Width of the volume (X dimension)
    public let width: Int
    
    /// Height of the volume (Y dimension)
    public let height: Int
    
    /// Depth of the volume (Z dimension)
    public let depth: Int
    
    /// Number of components (e.g., 1 for grayscale, 3 for RGB, N for multi-spectral)
    public let componentCount: Int
    
    /// Volume components
    public let components: [J2KVolumeComponent]
    
    /// Voxel spacing (physical dimensions)
    public let voxelSpacing: (x: Double, y: Double, z: Double)?
    
    /// Volume origin in physical space
    public let origin: (x: Double, y: Double, z: Double)?
    
    /// Metadata (patient info, acquisition parameters, etc.)
    public let metadata: J2KVolumeMetadata
}

/// Individual component of a 3D volume
public struct J2KVolumeComponent: Sendable {
    /// Bit depth (1-38 bits per sample)
    public let bitDepth: Int
    
    /// Whether samples are signed
    public let isSigned: Bool
    
    /// Raw voxel data (Z × Y × X order)
    public let data: Data
    
    /// Subsampling factors (dx, dy, dz)
    public let subsampling: (dx: Int, dy: Int, dz: Int)
}
```

#### JP3DEncoder

```swift
/// Encodes 3D volumetric data to JP3D format
public actor JP3DEncoder: Sendable {
    /// Configuration for JP3D encoding
    public struct Configuration: Sendable {
        /// 3D tiling configuration
        public var tiling: JP3DTilingConfiguration
        
        /// Wavelet transform type
        public var waveletTransform: J2KWaveletType
        
        /// Decomposition levels (X, Y, Z)
        public var decompositionLevels: (x: Int, y: Int, z: Int)
        
        /// Compression mode
        public var compressionMode: JP3DCompressionMode
        
        /// Quality layers configuration
        public var qualityLayers: [J2KQualityLayer]
        
        /// Progression order (3D-specific)
        public var progressionOrder: JP3DProgressionOrder
        
        /// Enable HTJ2K encoding (Part 15)
        public var enableHTJ2K: Bool
        
        /// Color transform
        public var colorTransform: J2KColorTransform?
        
        /// Rate control
        public var rateControl: J2KRateControlConfiguration?
        
        /// Enable Metal GPU acceleration
        public var enableMetalAcceleration: Bool
    }
    
    /// Encode volumetric data to JP3D format
    /// - Parameters:
    ///   - volume: The 3D volume to encode
    ///   - configuration: Encoding configuration
    /// - Returns: Encoded JP3D data
    /// - Throws: `J2KError` if encoding fails
    public func encode(
        _ volume: J2KVolume,
        configuration: Configuration
    ) async throws -> Data
    
    /// Stream-based encoding for large volumes
    /// - Parameters:
    ///   - configuration: Encoding configuration
    ///   - outputURL: Output file URL
    /// - Returns: Stream writer for incremental encoding
    /// - Throws: `J2KError` if initialization fails
    public func beginStream(
        configuration: Configuration,
        outputURL: URL
    ) async throws -> JP3DStreamWriter
}

/// Streaming writer for large JP3D volumes
public actor JP3DStreamWriter: Sendable {
    /// Add a single slice (XY plane at Z position)
    public func addSlice(
        _ slice: J2KImage,
        atDepth z: Int
    ) async throws
    
    /// Add multiple slices in batch
    public func addSlices(
        _ slices: [J2KImage],
        startingAtDepth z: Int
    ) async throws
    
    /// Finalize and close the JP3D file
    public func finalize() async throws
}
```

#### JP3DDecoder

```swift
/// Decodes JP3D volumetric data
public actor JP3DDecoder: Sendable {
    /// Configuration for JP3D decoding
    public struct Configuration: Sendable {
        /// Spatial region to decode (ROI)
        public var region: JP3DRegion?
        
        /// Resolution level (0 = highest)
        public var resolutionLevel: Int?
        
        /// Quality layers to decode
        public var qualityLayers: Int?
        
        /// Enable progressive decoding
        public var enableProgressiveDecoding: Bool
        
        /// Enable Metal GPU acceleration
        public var enableMetalAcceleration: Bool
    }
    
    /// Decode complete volume
    /// - Parameters:
    ///   - data: JP3D encoded data
    ///   - configuration: Decoding configuration
    /// - Returns: Decoded 3D volume
    /// - Throws: `J2KError` if decoding fails
    public func decode(
        _ data: Data,
        configuration: Configuration
    ) async throws -> J2KVolume
    
    /// Decode specific slice range
    /// - Parameters:
    ///   - data: JP3D encoded data
    ///   - sliceRange: Range of Z slices to decode
    ///   - configuration: Decoding configuration
    /// - Returns: Array of decoded slices
    /// - Throws: `J2KError` if decoding fails
    public func decodeSlices(
        _ data: Data,
        sliceRange: Range<Int>,
        configuration: Configuration
    ) async throws -> [J2KImage]
    
    /// Progressive decoding with callbacks
    /// - Parameters:
    ///   - data: JP3D encoded data
    ///   - configuration: Decoding configuration
    ///   - progressHandler: Called with partial volume updates
    /// - Throws: `J2KError` if decoding fails
    public func decodeProgressively(
        _ data: Data,
        configuration: Configuration,
        progressHandler: @escaping @Sendable (J2KVolume, Double) async -> Void
    ) async throws
}
```

### 3D-Specific Configuration

#### JP3DTilingConfiguration

```swift
/// Configuration for 3D tiling
public struct JP3DTilingConfiguration: Sendable {
    /// Tile size in X dimension
    public var tileSizeX: Int
    
    /// Tile size in Y dimension
    public var tileSizeY: Int
    
    /// Tile size in Z dimension
    public var tileSizeZ: Int
    
    /// Default: 256×256×16 (optimized for medical imaging)
    public static let `default` = JP3DTilingConfiguration(
        tileSizeX: 256,
        tileSizeY: 256,
        tileSizeZ: 16
    )
    
    /// Small tiles for fine-grained streaming
    public static let streaming = JP3DTilingConfiguration(
        tileSizeX: 128,
        tileSizeY: 128,
        tileSizeZ: 8
    )
    
    /// Large tiles for batch processing
    public static let batch = JP3DTilingConfiguration(
        tileSizeX: 512,
        tileSizeY: 512,
        tileSizeZ: 32
    )
}
```

#### JP3DCompressionMode

```swift
/// Compression modes for JP3D
public enum JP3DCompressionMode: Sendable {
    /// Lossless compression (reversible 5/3 wavelet)
    case lossless
    
    /// Lossy compression with target PSNR
    case lossy(targetPSNR: Double)
    
    /// Lossy compression with target bitrate
    case targetBitrate(bitsPerVoxel: Double)
    
    /// Visually lossless (high quality lossy)
    case visuallyLossless
    
    /// Lossless with HTJ2K high-throughput encoding
    case losslessHTJ2K
    
    /// Lossy with HTJ2K high-throughput encoding
    case lossyHTJ2K(targetPSNR: Double)
}
```

#### JP3DProgressionOrder

```swift
/// 3D-specific progression orders
public enum JP3DProgressionOrder: String, Sendable {
    /// Layer-Resolution-Component-Position-Slice (default for quality-scalable)
    case lrcps = "LRCPS"
    
    /// Resolution-Layer-Component-Position-Slice (resolution-first)
    case rlcps = "RLCPS"
    
    /// Position-Component-Resolution-Layer-Slice (spatial-first)
    case pcrls = "PCRLS"
    
    /// Slice-Layer-Resolution-Component-Position (Z-axis first)
    case slrcp = "SLRCP"
    
    /// Component-Position-Resolution-Layer-Slice (component-first)
    case cprls = "CPRLS"
}
```

#### JP3DRegion

```swift
/// Defines a 3D region of interest
public struct JP3DRegion: Sendable {
    /// X coordinate range (inclusive)
    public let xRange: Range<Int>
    
    /// Y coordinate range (inclusive)
    public let yRange: Range<Int>
    
    /// Z coordinate range (inclusive)
    public let zRange: Range<Int>
    
    /// Create from bounds
    public init(
        x: Range<Int>,
        y: Range<Int>,
        z: Range<Int>
    )
}
```

### 3D Wavelet Transform

JP3D uses 3D wavelet transforms or separable 2D+1D transforms:

```swift
/// 3D Wavelet Transform Implementation
public actor JP3DWaveletTransform: Sendable {
    /// Transform modes
    public enum TransformMode: Sendable {
        /// Full 3D wavelet transform
        case full3D
        
        /// Separable 2D+1D transform (2D spatial, 1D Z-axis)
        case separable2DPlus1D
        
        /// Wavelet packet decomposition
        case waveletPacket
    }
    
    /// Perform forward 3D DWT
    /// - Parameters:
    ///   - volume: Input volume data
    ///   - mode: Transform mode
    ///   - levels: Decomposition levels per axis
    /// - Returns: Transformed coefficients
    /// - Throws: `J2KError` if transform fails
    public func forwardTransform(
        _ volume: J2KVolume,
        mode: TransformMode,
        levels: (x: Int, y: Int, z: Int)
    ) async throws -> J2K3DCoefficients
    
    /// Perform inverse 3D DWT
    /// - Parameters:
    ///   - coefficients: Transformed coefficients
    ///   - mode: Transform mode
    /// - Returns: Reconstructed volume
    /// - Throws: `J2KError` if transform fails
    public func inverseTransform(
        _ coefficients: J2K3DCoefficients,
        mode: TransformMode
    ) async throws -> J2KVolume
}
```

### Metal GPU Acceleration for 3D Operations

JP3D leverages Metal for compute-intensive 3D operations:

```swift
/// Metal-accelerated 3D JPEG 2000 operations
@available(macOS 14.0, iOS 17.0, *)
public actor JP3DMetalAccelerator: Sendable {
    /// 3D wavelet transform using Metal compute shaders
    public func transform3D(
        _ volume: J2KVolume,
        direction: J2KTransformDirection
    ) async throws -> J2K3DCoefficients
    
    /// Parallel entropy coding across multiple code-blocks
    public func parallelEntropyCode(
        _ codeBlocks: [J2KCodeBlock]
    ) async throws -> [J2KEncodedCodeBlock]
    
    /// Volume rendering for preview/visualization
    public func renderVolume(
        _ volume: J2KVolume,
        viewConfiguration: JP3DViewConfiguration
    ) async throws -> MTLTexture
    
    /// 3D color transform (for multi-component volumes)
    public func colorTransform3D(
        _ volume: J2KVolume,
        mode: J2KColorTransformMode
    ) async throws -> J2KVolume
}
```

**Metal Shaders** (`Sources/J2KMetal/Shaders/JP3D.metal`):
- `jp3d_dwt_3d_forward`: 3D forward wavelet transform
- `jp3d_dwt_3d_inverse`: 3D inverse wavelet transform
- `jp3d_separable_dwt`: Separable 2D+1D transform
- `jp3d_entropy_encode`: Parallel entropy encoding
- `jp3d_volume_render`: Volume rendering with ray casting
- `jp3d_color_transform`: 3D color space conversion

**Expected Performance** (Apple Silicon):
- 20-50× speedup for 3D wavelet transforms (vs. CPU)
- 15-35× speedup for parallel entropy coding
- Real-time volume rendering up to 512³ voxels
- Concurrent CPU-GPU pipeline for maximum throughput

## Feature 2: HTJ2K in JP3D (Part 15 Integration)

### Overview

Integrate High-Throughput JPEG 2000 (HTJ2K, Part 15) encoding within JP3D workflows for improved encoding/decoding speed with minimal compression efficiency impact.

### HTJ2K Benefits for Volumetric Data

**Performance Advantages**:
- **5-10× faster encoding** compared to standard JPEG 2000
- **3-7× faster decoding** with block-parallel processing
- Lower latency for real-time streaming applications
- Reduced power consumption on mobile devices

**Trade-offs**:
- Slightly lower compression efficiency (typically 5-15% larger files)
- Reduced rate-distortion optimization flexibility
- May require more bandwidth for streaming

**Ideal Use Cases**:
- Real-time medical imaging (surgical navigation, interventional radiology)
- Interactive 3D visualization with low-latency requirements
- Mobile/edge devices with power constraints
- High-throughput archival systems

### Configuration

```swift
/// HTJ2K configuration for JP3D
public struct JP3DHTJ2KConfiguration: Sendable {
    /// Enable HTJ2K encoding
    public var enabled: Bool
    
    /// Block coding mode
    public var blockCodingMode: HTJ2KBlockCodingMode
    
    /// Number of encoding passes
    public var encodingPasses: Int
    
    /// Enable HT code-block cleanup
    public var enableCleanup: Bool
    
    /// Parallel processing threads
    public var parallelThreads: Int
    
    /// Default HTJ2K configuration for JP3D
    public static let `default` = JP3DHTJ2KConfiguration(
        enabled: true,
        blockCodingMode: .standard,
        encodingPasses: 1,
        enableCleanup: true,
        parallelThreads: ProcessInfo.processInfo.activeProcessorCount
    )
    
    /// Low-latency configuration
    public static let lowLatency = JP3DHTJ2KConfiguration(
        enabled: true,
        blockCodingMode: .fast,
        encodingPasses: 1,
        enableCleanup: false,
        parallelThreads: ProcessInfo.processInfo.activeProcessorCount
    )
    
    /// High-quality configuration (balanced)
    public static let balanced = JP3DHTJ2KConfiguration(
        enabled: true,
        blockCodingMode: .standard,
        encodingPasses: 2,
        enableCleanup: true,
        parallelThreads: ProcessInfo.processInfo.activeProcessorCount
    )
}
```

### Performance Comparison

Document expected performance characteristics:

| Mode | Encoding Speed | Decoding Speed | Compression Ratio | Latency | Use Case |
|------|---------------|----------------|-------------------|---------|----------|
| Standard JP3D | Baseline | Baseline | 100% | Baseline | Archival, offline processing |
| JP3D + HTJ2K Fast | 7-10× | 5-7× | 85-90% | Very Low | Real-time interactive |
| JP3D + HTJ2K Balanced | 5-7× | 3-5× | 90-95% | Low | Streaming, visualization |
| JP3D Lossless | Baseline | Baseline | 100% | Medium | Medical archive (legal) |
| JP3D + HTJ2K Lossless | 5-8× | 3-6× | 95-100% | Low | Fast medical archive |

### Compatibility Considerations

**Decoder Requirements**:
- HTJ2K-encoded JP3D requires Part 15-compliant decoder
- Provide fallback detection and error messaging
- Support hybrid streams (some tiles HTJ2K, some standard)

**Interoperability**:
- HTJ2K marker segments in JP3D codestream
- Profile/level signaling for compatibility
- Graceful degradation strategies

## Feature 3: JPIP Extension for JP3D Datasets

### Overview

Extend the existing JPIP (Part 9) implementation to support 3D-aware precinct, tile, and resolution handling for progressive delivery of volumetric data.

### 3D-Aware JPIP Architecture

```
Client Request → JPIP Server → JP3D Data Source
     ↓               ↓              ↓
3D Viewport    3D Cache        Volume
Selection      Management      Precincts
     ↓               ↓              ↓
Progressive → Bandwidth → 3D Progressive
Delivery      Adaptation    Decoding
```

### Key Components

#### JP3DJPIPClient

```swift
/// JPIP client for JP3D volumetric streaming
public actor JP3DJPIPClient: Sendable {
    /// Request 3D region of interest
    /// - Parameters:
    ///   - region: 3D spatial region
    ///   - resolutionLevel: Resolution level (0 = highest)
    ///   - qualityLayers: Number of quality layers
    /// - Returns: Async stream of volume data bins
    public func requestRegion(
        _ region: JP3DRegion,
        resolutionLevel: Int,
        qualityLayers: Int
    ) async throws -> AsyncStream<JP3DDataBin>
    
    /// Request slice range with progressive delivery
    /// - Parameters:
    ///   - sliceRange: Z-axis slice range
    ///   - viewportXY: XY plane viewport
    ///   - progressionMode: Delivery order preference
    /// - Returns: Async stream of slice data
    public func requestSlices(
        _ sliceRange: Range<Int>,
        viewportXY: CGRect,
        progressionMode: JP3DProgressionMode
    ) async throws -> AsyncStream<JP3DSliceData>
    
    /// Request volumetric data with view frustum culling
    /// - Parameters:
    ///   - frustum: 3D view frustum
    ///   - lodBias: Level-of-detail bias
    /// - Returns: Async stream of visible volume data
    public func requestViewFrustum(
        _ frustum: JP3DViewFrustum,
        lodBias: Double
    ) async throws -> AsyncStream<JP3DDataBin>
}
```

#### JP3DJPIPServer

```swift
/// JPIP server for JP3D volumetric streaming
public actor JP3DJPIPServer: Sendable {
    /// Configuration for JP3D JPIP server
    public struct Configuration: Sendable {
        /// Maximum concurrent sessions
        public var maxConcurrentSessions: Int
        
        /// Cache size per session (bytes)
        public var sessionCacheSize: Int
        
        /// Enable predictive prefetching
        public var enablePredictivePrefetch: Bool
        
        /// 3D precinct prefetch strategy
        public var prefetchStrategy: JP3DPrefetchStrategy
        
        /// Bandwidth throttling
        public var bandwidthLimit: Int?
        
        /// Enable compression for network transfer
        public var enableCompression: Bool
    }
    
    /// Handle 3D region request
    public func handleRegionRequest(
        _ request: JP3DRegionRequest,
        session: JPIPSession
    ) async throws -> AsyncStream<JP3DDataBin>
    
    /// Handle progressive slice delivery
    public func handleSliceRequest(
        _ request: JP3DSliceRequest,
        session: JPIPSession
    ) async throws -> AsyncStream<JP3DSliceData>
    
    /// Handle view-dependent streaming
    public func handleViewRequest(
        _ request: JP3DViewRequest,
        session: JPIPSession
    ) async throws -> AsyncStream<JP3DDataBin>
}
```

### 3D-Aware Data Structures

#### JP3DPrecinct

```swift
/// 3D precinct for spatial organization
public struct JP3DPrecinct: Sendable {
    /// Precinct indices (X, Y, Z)
    public let indices: (x: Int, y: Int, z: Int)
    
    /// Resolution level
    public let resolutionLevel: Int
    
    /// Component index
    public let componentIndex: Int
    
    /// Spatial bounds in volume space
    public let bounds: JP3DRegion
    
    /// Associated tile index
    public let tileIndex: (x: Int, y: Int, z: Int)
    
    /// Data size (bytes)
    public let dataSize: Int
    
    /// Quality layers available
    public let qualityLayers: Int
}
```

#### JP3DDataBin

```swift
/// Data bin for 3D JPIP streaming
public struct JP3DDataBin: Sendable {
    /// Unique identifier
    public let id: JP3DDataBinID
    
    /// Data bin type
    public let type: JP3DDataBinType
    
    /// Associated precinct
    public let precinct: JP3DPrecinct?
    
    /// Data payload
    public let data: Data
    
    /// Quality layer
    public let qualityLayer: Int
    
    /// Completion flag
    public let isComplete: Bool
}

/// Data bin identifier for 3D streaming
public struct JP3DDataBinID: Hashable, Sendable {
    /// Class identifier (precinct, tile-header, etc.)
    public let classID: Int
    
    /// In-class identifier
    public let inClassID: Int64
    
    /// Z-slice identifier (for 3D)
    public let sliceID: Int?
}

/// Types of 3D data bins
public enum JP3DDataBinType: Sendable {
    case mainHeader
    case tileHeader3D
    case precinct3D
    case volumeMetadata
}
```

### 3D Streaming Strategies

#### JP3DProgressionMode

```swift
/// Progression modes for 3D volumetric streaming
public enum JP3DProgressionMode: Sendable {
    /// Resolution-first (coarse to fine)
    case resolutionFirst
    
    /// Quality-first (low to high quality)
    case qualityFirst
    
    /// Slice-by-slice (sequential Z-axis)
    case sliceBySlice(direction: JP3DSliceDirection)
    
    /// View-dependent (based on camera frustum)
    case viewDependent
    
    /// Distance-ordered (near to far from viewpoint)
    case distanceOrdered(viewpoint: (x: Double, y: Double, z: Double))
    
    /// Adaptive (bandwidth and view-aware)
    case adaptive
}

/// Slice ordering direction
public enum JP3DSliceDirection: Sendable {
    case forwardZ  // Z increasing
    case reverseZ  // Z decreasing
    case bidirectional  // From center outward
}
```

#### JP3DPrefetchStrategy

```swift
/// Prefetch strategies for predictive delivery
public enum JP3DPrefetchStrategy: Sendable {
    /// No prefetching
    case none
    
    /// Prefetch adjacent slices
    case adjacentSlices(count: Int)
    
    /// Prefetch based on view direction
    case viewDirection(lookahead: Double)
    
    /// Prefetch based on interaction patterns
    case predictive(model: JP3DPredictionModel)
    
    /// Hybrid approach
    case hybrid
}

/// Prediction model for prefetching
public enum JP3DPredictionModel: Sendable {
    /// Linear motion prediction
    case linearMotion
    
    /// Momentum-based prediction
    case momentum
    
    /// ML-based prediction (uses historical patterns)
    case machineLearning
}
```

### Network Optimization with Network.framework

```swift
/// Network optimizations for JP3D streaming
@available(macOS 14.0, iOS 17.0, *)
public actor JP3DNetworkOptimizer: Sendable {
    /// Configure Network.framework for JP3D streaming
    public func configureConnection(
        _ connection: NWConnection,
        priority: NWParameters.ServiceClass
    ) async throws
    
    /// Enable QUIC for low-latency delivery
    public func enableQUIC(
        _ parameters: inout NWParameters
    )
    
    /// Configure HTTP/3 for improved performance
    public func configureHTTP3(
        _ parameters: inout NWParameters
    )
    
    /// Monitor network path for adaptive streaming
    public func monitorNetworkPath(
        _ monitor: NWPathMonitor
    ) -> AsyncStream<JP3DNetworkConditions>
    
    /// Adapt quality based on network conditions
    public func adaptToNetworkConditions(
        _ conditions: JP3DNetworkConditions
    ) async -> JP3DStreamingConfiguration
}

/// Network conditions for adaptive streaming
public struct JP3DNetworkConditions: Sendable {
    public let bandwidth: Int  // bytes per second
    public let latency: TimeInterval  // seconds
    public let packetLoss: Double  // 0.0 to 1.0
    public let isConstrained: Bool
    public let isExpensive: Bool
}
```

### 3D Cache Management

```swift
/// Cache manager for 3D volumetric data
public actor JP3DCacheManager: Sendable {
    /// Cache policy for 3D data
    public enum CachePolicy: Sendable {
        /// Cache by resolution level
        case byResolution(maxLevel: Int)
        
        /// Cache by spatial proximity
        case bySpatialProximity(center: (x: Int, y: Int, z: Int), radius: Double)
        
        /// Cache by access frequency
        case byFrequency(lruSize: Int)
        
        /// Cache view frustum
        case byViewFrustum(frustum: JP3DViewFrustum)
    }
    
    /// Add precinct to cache
    public func cachePrecinct(
        _ precinct: JP3DPrecinct,
        data: Data
    ) async throws
    
    /// Retrieve precinct from cache
    public func getPrecinct(
        _ precinctID: JP3DPrecinctID
    ) async -> Data?
    
    /// Evict precincts based on policy
    public func evict(
        policy: CachePolicy
    ) async throws -> Int
    
    /// Get cache statistics
    public func getCacheStats() async -> JP3DCacheStatistics
}

/// Cache statistics for 3D data
public struct JP3DCacheStatistics: Sendable {
    public let totalSize: Int
    public let precinctCount: Int
    public let hitRate: Double
    public let missRate: Double
    public let evictionCount: Int
    public let spatialCoverage: Double
}
```

### Progressive Volume Delivery

```swift
/// Progressive volume delivery manager
public actor JP3DProgressiveDelivery: Sendable {
    /// Deliver volume progressively based on priority
    /// - Parameters:
    ///   - volume: Source volume
    ///   - region: Region of interest
    ///   - progression: Progression mode
    ///   - bandwidth: Available bandwidth (bytes/sec)
    /// - Returns: Async stream of progressive updates
    public func deliverVolume(
        _ volume: J2KVolume,
        region: JP3DRegion?,
        progression: JP3DProgressionMode,
        bandwidth: Int
    ) async throws -> AsyncStream<JP3DProgressiveUpdate>
    
    /// Estimate delivery time for region
    public func estimateDeliveryTime(
        _ region: JP3DRegion,
        qualityLayers: Int,
        bandwidth: Int
    ) async throws -> TimeInterval
}

/// Progressive update for streaming
public struct JP3DProgressiveUpdate: Sendable {
    /// Partially decoded volume
    public let partialVolume: J2KVolume
    
    /// Completion percentage (0.0 to 1.0)
    public let completionPercentage: Double
    
    /// Current quality layer
    public let currentQualityLayer: Int
    
    /// Current resolution level
    public let currentResolutionLevel: Int
    
    /// Estimated time remaining
    public let estimatedTimeRemaining: TimeInterval?
}
```

## Performance Targets

### Encoding Performance (Apple Silicon M3)

| Volume Size | Lossless | Lossy (40dB PSNR) | HTJ2K Lossless | HTJ2K Lossy |
|-------------|----------|-------------------|----------------|-------------|
| 256³ (16MB) | 2-4 sec | 1-2 sec | 0.4-0.8 sec | 0.2-0.4 sec |
| 512³ (128MB) | 15-25 sec | 8-12 sec | 2-4 sec | 1-2 sec |
| 1024³ (1GB) | 120-180 sec | 60-90 sec | 15-25 sec | 8-15 sec |

**Metal Acceleration**: 20-50× speedup for 3D wavelet transforms

### Decoding Performance (Apple Silicon M3)

| Volume Size | Full Decode | ROI Decode (1/8 volume) | Progressive (first view) |
|-------------|-------------|-------------------------|--------------------------|
| 256³ | 1-2 sec | 0.2-0.4 sec | 0.1-0.2 sec |
| 512³ | 8-12 sec | 1-2 sec | 0.5-1 sec |
| 1024³ | 60-90 sec | 8-12 sec | 2-4 sec |

### Streaming Performance (1 Gbps network)

| Volume Size | Initial Display | Complete Delivery | Latency |
|-------------|----------------|-------------------|---------|
| 256³ | < 100ms | 2-4 sec | < 20ms |
| 512³ | < 150ms | 15-30 sec | < 30ms |
| 1024³ | < 250ms | 2-3 min | < 50ms |

**Network.framework + QUIC**: 30-50% latency reduction vs. TCP

## Platform-Specific Considerations

### Apple Silicon Optimization

- **Unified Memory**: Zero-copy transfers between CPU and GPU
- **AMX Coprocessor**: Automatic matrix acceleration via Accelerate
- **Neural Engine**: ML-based encoding optimizations (future)
- **Power Efficiency**: Up to 3× better performance-per-watt vs. x86-64

### iOS/visionOS Considerations

- Background transfer service for large volumes
- Memory pressure handling with automatic quality reduction
- Thermal management with adaptive encoding parameters
- Battery-aware processing modes

### x86-64 Linux Compatibility

- Isolated x86-64 code paths in `Sources/J2KAccelerate/x86/`
- Use `#if arch(x86_64)` guards exclusively
- SSE/AVX fallbacks for SIMD operations
- Documented as "legacy support" for eventual removal

## Testing Strategy

### Unit Tests

- `Tests/JP3DTests/JP3DEncoderTests.swift` - Encoder validation (50+ tests)
- `Tests/JP3DTests/JP3DDecoderTests.swift` - Decoder validation (50+ tests)
- `Tests/JP3DTests/JP3DWaveletTests.swift` - 3D wavelet correctness (30+ tests)
- `Tests/JP3DTests/JP3DHTJKTests.swift` - HTJ2K integration (25+ tests)

### Integration Tests

- `Tests/JP3DTests/JP3DIntegrationTests.swift` - End-to-end workflows (30+ tests)
- `Tests/JP3DTests/JP3DStreamingTests.swift` - JPIP streaming (40+ tests)
- `Tests/JP3DTests/JP3DMetalTests.swift` - GPU acceleration (25+ tests)

### Compliance Tests

- `Tests/J2KComplianceTests/JP3DComplianceTests.swift` - Part 4 compliance (100+ tests)
- ISO/IEC 15444-4 test vectors validation
- Conformance testing against reference implementations
- Automated compliance checks in CI/CD

### Performance Tests

- `Tests/JP3DTests/JP3DPerformanceTests.swift` - Benchmarking (20+ tests)
- Encoding/decoding speed measurements
- Memory usage profiling
- GPU utilization analysis

### Platform Tests

- `Tests/JP3DTests/JP3DAppleSiliconTests.swift` - Apple Silicon specific (15+ tests)
- `Tests/JP3DTests/JP3DiOSTests.swift` - iOS/mobile specific (10+ tests)
- `Tests/JP3DTests/JP3Dx86Tests.swift` - x86-64 compatibility (10+ tests)

## Documentation Requirements

### Technical Documentation

- `Documentation/JP3D_ARCHITECTURE.md` - Architecture overview
- `Documentation/JP3D_API_REFERENCE.md` - Complete API documentation
- `Documentation/JP3D_STREAMING_GUIDE.md` - JPIP streaming guide
- `Documentation/JP3D_PERFORMANCE.md` - Performance tuning guide
- `Documentation/JP3D_HTJ2K_INTEGRATION.md` - HTJ2K usage guide

### Compliance Documentation

- `Documentation/Compliance/JP3D_CONFORMANCE_REPORT.md` - Detailed compliance report
- `Documentation/Compliance/JP3D_TEST_VECTORS.md` - Test vector validation results
- `Documentation/Compliance/JP3D_PART4_VALIDATION.md` - Part 4 compliance validation

### User Documentation

- `Documentation/JP3D_GETTING_STARTED.md` - Quick start guide
- `Documentation/JP3D_EXAMPLES.md` - Usage examples
- `Documentation/JP3D_MIGRATION.md` - Migration from 2D JPEG 2000
- `Documentation/JP3D_TROUBLESHOOTING.md` - Common issues and solutions

## Release Requirements

### Pre-Release Validation Checklist

All items must be completed and verified before release:

- [ ] **Compliance Testing** (Mandatory)
  - [ ] All Part 4 compliance tests pass
  - [ ] Conformance report generated and reviewed
  - [ ] Test vectors validated against reference implementation
  - [ ] Compliance validation script executed successfully
  - [ ] Results documented in `Documentation/Compliance/`

- [ ] **Functional Testing**
  - [ ] All unit tests pass (250+ tests)
  - [ ] All integration tests pass
  - [ ] JPIP streaming tests pass
  - [ ] HTJ2K integration tests pass

- [ ] **Performance Validation**
  - [ ] Encoding performance meets targets
  - [ ] Decoding performance meets targets
  - [ ] Streaming latency within acceptable range
  - [ ] Memory usage validated
  - [ ] GPU acceleration validated on Apple Silicon

- [ ] **Platform Testing**
  - [ ] macOS (Apple Silicon) - All tests pass
  - [ ] macOS (Intel) - All tests pass with x86-64 paths
  - [ ] iOS - All tests pass
  - [ ] visionOS - All tests pass
  - [ ] Linux (x86-64) - Basic functionality validated

- [ ] **Documentation**
  - [ ] All API documentation complete
  - [ ] Architecture documentation reviewed
  - [ ] Compliance report finalized
  - [ ] Migration guide updated
  - [ ] Release notes prepared

- [ ] **Code Quality**
  - [ ] SwiftLint checks pass
  - [ ] No compiler warnings
  - [ ] Code coverage > 85%
  - [ ] Security audit complete

### Continuous Compliance Integration

Automated compliance validation in CI/CD pipeline:

```yaml
# .github/workflows/jp3d-compliance.yml
name: JP3D Compliance Validation

on: [push, pull_request]

jobs:
  compliance:
    runs-on: macos-14  # Apple Silicon runner
    steps:
      - uses: actions/checkout@v4
      - name: Build J2KSwift
        run: swift build
      - name: Run Compliance Tests
        run: swift test --filter J2KComplianceTests.JP3DComplianceTests
      - name: Validate Compliance Script
        run: ./Scripts/validate-jp3d-compliance.sh
      - name: Generate Compliance Report
        run: swift run generate-compliance-report --output Documentation/Compliance/
      - name: Upload Compliance Artifacts
        uses: actions/upload-artifact@v4
        with:
          name: jp3d-compliance-report
          path: Documentation/Compliance/JP3D_CONFORMANCE_REPORT.md
```

### Release Checklist Template

Template for `RELEASE_CHECKLIST_vX.X.X.md`:

```markdown
# Release Checklist vX.X.X (JP3D Support)

## Compliance Validation (MANDATORY)
- [ ] Part 4 compliance tests: ✅ PASS / ❌ FAIL
- [ ] Conformance report generated: [link]
- [ ] Compliance validation script executed: ✅ / ❌
- [ ] Test vectors validated: ✅ / ❌
- [ ] Signed off by: [Name, Date]

## Functional Testing
- [ ] Unit tests (250+ tests): ✅ / ❌
- [ ] Integration tests: ✅ / ❌
- [ ] Performance tests: ✅ / ❌

## Platform Testing
- [ ] macOS (Apple Silicon): ✅ / ❌
- [ ] macOS (Intel): ✅ / ❌
- [ ] iOS: ✅ / ❌
- [ ] visionOS: ✅ / ❌
- [ ] Linux (x86-64): ✅ / ❌

## Documentation
- [ ] API documentation: Complete / Incomplete
- [ ] Compliance report: Finalized / Draft
- [ ] Release notes: Ready / Not Ready

## Final Approval
- [ ] Technical review: Approved by [Name]
- [ ] Compliance review: Approved by [Name]
- [ ] Release authorized: Yes / No
```

## Dependencies and Module Structure

### Module Organization

```
Sources/
├── J2KCore/                  # Foundation types
│   ├── J2KVolume.swift
│   └── J2KVolumeComponent.swift
├── J2KCodec/                 # 2D encoding/decoding
├── J2K3D/                    # NEW: JP3D implementation
│   ├── JP3DEncoder.swift
│   ├── JP3DDecoder.swift
│   ├── JP3DWaveletTransform.swift
│   ├── JP3DTiling.swift
│   ├── JP3DConfiguration.swift
│   └── JP3DHTJ2K.swift
├── J2KMetal/                 # GPU acceleration
│   ├── JP3DMetalAccelerator.swift
│   └── Shaders/
│       └── JP3D.metal
├── JPIP/                     # JPIP protocol
│   ├── JP3DJPIPClient.swift
│   ├── JP3DJPIPServer.swift
│   ├── JP3DCacheManager.swift
│   └── JP3DProgressiveDelivery.swift
└── J2KFileFormat/            # File I/O
    └── JP3DFileFormat.swift

Tests/
├── J2KComplianceTests/
│   └── JP3DComplianceTests.swift
└── JP3DTests/
    ├── JP3DEncoderTests.swift
    ├── JP3DDecoderTests.swift
    ├── JP3DStreamingTests.swift
    ├── JP3DHTJKTests.swift
    └── JP3DPerformanceTests.swift
```

### Dependencies

```swift
// Package.swift
dependencies: [
    // No external dependencies - 100% Swift native
],
targets: [
    .target(
        name: "J2K3D",
        dependencies: ["J2KCore", "J2KCodec", "J2KFileFormat"]
    ),
    .target(
        name: "J2KMetal",
        dependencies: ["J2KCore", "J2K3D"]
    ),
    .target(
        name: "JPIP",
        dependencies: ["J2KCore", "J2K3D", "J2KFileFormat"]
    ),
    .testTarget(
        name: "JP3DTests",
        dependencies: ["J2K3D", "J2KMetal", "JPIP"]
    ),
    .testTarget(
        name: "J2KComplianceTests",
        dependencies: ["J2K3D"],
        resources: [.process("TestVectors")]
    )
]
```

## Security Considerations

### Input Validation

- Strict validation of volume dimensions (prevent integer overflow)
- Maximum volume size limits to prevent memory exhaustion
- Marker segment validation to prevent malformed data attacks
- Tile/precinct index bounds checking

### Memory Safety

- Bounds checking for all buffer access
- Safe integer arithmetic throughout
- Automatic memory management with ARC
- No unsafe pointer operations without clear documentation

### Network Security

- TLS 1.3 required for all JPIP connections
- Certificate validation with pinning option
- Rate limiting to prevent DoS attacks
- Input sanitization for all network data

## Backward Compatibility

### File Format Compatibility

- JP3D files remain compatible with Part 10 specification
- Graceful handling of unknown marker segments
- Version detection and feature negotiation
- Fallback strategies for unsupported features

### API Compatibility

- Semantic versioning (SemVer)
- Deprecation warnings with migration paths
- Minimum one major version deprecation cycle
- Clear breaking changes documentation

## Future Extensions

### Potential Enhancements (Post-v1.9.0)

- **ML-Based Encoding**: Neural network-assisted rate-distortion optimization
- **Advanced Visualization**: Real-time volume rendering with Metal ray tracing
- **Multi-Resolution Editing**: In-place modification of JP3D files
- **Cloud Integration**: Direct streaming from cloud storage (S3, CloudKit)
- **Format Conversions**: DICOM, NIfTI, and other medical imaging formats
- **Annotation Support**: Embedded 3D annotations and measurements

## Timeline and Milestones

### Phase 16: JP3D Core Implementation (v1.9.0, Weeks 211-235)

#### Week 211-213: 3D Data Structures and Core Types
- [ ] Implement `J2KVolume` and `J2KVolumeComponent`
- [ ] Create `JP3DRegion` and spatial indexing
- [ ] Implement `JP3DPrecinct` and `JP3DTile`
- [ ] Add volume metadata support
- [ ] Initial unit tests (30+ tests)

#### Week 214-217: 3D Wavelet Transforms
- [ ] Implement 3D forward DWT
- [ ] Implement 3D inverse DWT
- [ ] Separable 2D+1D transform mode
- [ ] Metal GPU acceleration for 3D DWT
- [ ] Wavelet transform tests (25+ tests)

#### Week 218-221: JP3D Encoder
- [ ] Core encoding pipeline
- [ ] 3D tiling implementation
- [ ] Rate control for volumetric data
- [ ] Progression order support
- [ ] Streaming encoder
- [ ] Encoder tests (50+ tests)

#### Week 222-225: JP3D Decoder
- [ ] Core decoding pipeline
- [ ] ROI decoding support
- [ ] Progressive decoding
- [ ] Multi-resolution support
- [ ] Decoder tests (50+ tests)

#### Week 226-228: HTJ2K Integration
- [ ] HTJ2K encoding for JP3D
- [ ] HTJ2K decoding for JP3D
- [ ] Performance benchmarking
- [ ] HTJ2K tests (25+ tests)

#### Week 229-232: JPIP Extension for JP3D
- [ ] `JP3DJPIPClient` implementation
- [ ] `JP3DJPIPServer` implementation
- [ ] 3D cache management
- [ ] Progressive delivery strategies
- [ ] JPIP streaming tests (40+ tests)

#### Week 233-234: Compliance Testing
- [ ] Implement Part 4 compliance tests
- [ ] Validate against test vectors
- [ ] Generate compliance report
- [ ] Compliance validation script
- [ ] Compliance tests (100+ tests)

#### Week 235: Documentation and Release
- [ ] Complete API documentation
- [ ] Write architecture guide
- [ ] Create user documentation
- [ ] Performance tuning guide
- [ ] Release notes and checklist
- [ ] Final compliance validation
- [ ] v1.9.0 release

### Deliverables Summary

**Code** (Weeks 211-235):
- `Sources/J2K3D/` - Complete JP3D implementation (3000+ lines)
- `Sources/J2KMetal/JP3DMetalAccelerator.swift` - GPU acceleration (500+ lines)
- `Sources/J2KMetal/Shaders/JP3D.metal` - Metal compute shaders (800+ lines)
- `Sources/JPIP/JP3D*.swift` - JPIP extensions (1500+ lines)
- `Tests/JP3DTests/` - Comprehensive tests (250+ tests)
- `Tests/J2KComplianceTests/JP3DComplianceTests.swift` - Compliance tests (100+ tests)

**Documentation** (Week 235):
- `Documentation/JP3D_ARCHITECTURE.md` - Architecture guide
- `Documentation/JP3D_API_REFERENCE.md` - API reference
- `Documentation/JP3D_STREAMING_GUIDE.md` - Streaming guide
- `Documentation/JP3D_PERFORMANCE.md` - Performance guide
- `Documentation/JP3D_HTJ2K_INTEGRATION.md` - HTJ2K usage
- `Documentation/Compliance/JP3D_CONFORMANCE_REPORT.md` - Compliance report

**Scripts** (Week 234):
- `Scripts/validate-jp3d-compliance.sh` - Compliance validation
- `Scripts/benchmark-jp3d.sh` - Performance benchmarking

**CI/CD** (Week 234):
- `.github/workflows/jp3d-compliance.yml` - Automated compliance testing

## Success Criteria

### Functional Requirements
- ✅ Encode/decode volumetric data compliant with Part 10
- ✅ Support all progression orders (LRCPS, RLCPS, PCRLS, SLRCP, CPRLS)
- ✅ HTJ2K integration for high-throughput encoding
- ✅ JPIP streaming with 3D-aware delivery
- ✅ ROI decoding for spatial subsets
- ✅ Progressive delivery with multiple strategies

### Performance Requirements
- ✅ 20-50× speedup with Metal GPU acceleration (Apple Silicon)
- ✅ 5-10× faster encoding with HTJ2K
- ✅ < 100ms initial display latency for streaming
- ✅ Real-time volume rendering up to 512³ voxels

### Compliance Requirements
- ✅ 100% pass rate on Part 4 compliance tests
- ✅ Validated against ISO test vectors
- ✅ Documented compliance verification process
- ✅ Automated compliance checks in CI/CD

### Quality Requirements
- ✅ > 85% code coverage
- ✅ Zero compiler warnings
- ✅ All SwiftLint checks pass
- ✅ Comprehensive API documentation

### Platform Requirements
- ✅ Full support for Apple Silicon (macOS, iOS, visionOS)
- ✅ Compatibility with Intel Macs (x86-64 isolated)
- ✅ Basic Linux x86-64 support (marked for deprecation)

## Conclusion

This implementation plan provides a comprehensive roadmap for adding JP3D (ISO/IEC 15444 Part 10) support to J2KSwift with the following key characteristics:

- **Standards Compliance**: Full Part 10 compliance with mandatory Part 4 validation
- **Performance**: Optimized for Apple Silicon with Metal GPU acceleration
- **Pure Swift**: 100% Swift native implementation, no C/C++ dependencies
- **Streaming**: Advanced JPIP extensions for volumetric progressive delivery
- **HTJ2K Integration**: Optional high-throughput encoding for real-time applications
- **Symmetrical Design**: Works equally well for client and server use cases
- **Maintainability**: Clean architecture, comprehensive tests, thorough documentation
- **Future-Proof**: Isolated x86-64 code paths, designed for Apple-first strategy

The implementation leverages Apple's native frameworks (Accelerate, Metal, Network.framework) to deliver world-class performance while maintaining cross-platform compatibility and long-term maintainability.

---

**Document Version**: 1.0  
**Created**: 2026-02-18  
**Next Review**: At start of Phase 16 (Week 211)  
**Status**: Planning Document (Pre-Implementation)
