# J2KSwift API Reference

Complete API documentation for J2KSwift modules and types.

## Table of Contents

- [J2KCore Module](#j2kcore-module)
- [J2KCodec Module](#j2kcodec-module)
- [J2KAccelerate Module](#j2kaccelerate-module)
- [J2KFileFormat Module](#j2kfileformat-module)
- [JPIP Module](#jpip-module)

## J2KCore Module

The foundation module providing core types, protocols, and utilities.

### J2KImage

Represents a JPEG 2000 image with metadata and pixel data.

```swift
public struct J2KImage: Sendable {
    public let width: Int
    public let height: Int
    public let components: [J2KComponent]
    public let offsetX: Int
    public let offsetY: Int
    public let tileWidth: Int
    public let tileHeight: Int
    public let tileOffsetX: Int
    public let tileOffsetY: Int
    public let colorSpace: J2KColorSpace
}
```

**Initializers:**

```swift
// Basic image
init(width: Int, height: Int, components: Int, bitDepth: Int = 8)

// Full initialization
init(
    width: Int,
    height: Int,
    components: [J2KComponent],
    offsetX: Int = 0,
    offsetY: Int = 0,
    tileWidth: Int = 0,
    tileHeight: Int = 0,
    tileOffsetX: Int = 0,
    tileOffsetY: Int = 0,
    colorSpace: J2KColorSpace = .sRGB
)
```

**Examples:**

```swift
// Simple RGB image
let image = J2KImage(width: 512, height: 512, components: 3)

// Grayscale image with 16-bit depth
let grayImage = J2KImage(width: 1024, height: 768, components: 1, bitDepth: 16)

// Tiled image for large images
let largeImage = J2KImage(
    width: 8192,
    height: 6144,
    components: 3,
    tileWidth: 512,
    tileHeight: 512
)
```

### J2KComponent

Represents a single component (channel) of an image.

```swift
public struct J2KComponent: Sendable {
    public let index: Int
    public let bitDepth: Int
    public let width: Int
    public let height: Int
    public let dx: Int  // Horizontal subsampling
    public let dy: Int  // Vertical subsampling
    public let isSigned: Bool
    public let buffer: J2KImageBuffer
}
```

**Properties:**

- `index`: Component index (0=R/Y, 1=G/Cb, 2=B/Cr, etc.)
- `bitDepth`: Bits per sample (1-38)
- `width`, `height`: Component dimensions
- `dx`, `dy`: Subsampling factors (1=no subsampling)
- `isSigned`: Whether component values are signed
- `buffer`: Pixel data storage

**Examples:**

```swift
// RGB components
let red = J2KComponent(index: 0, bitDepth: 8, width: 512, height: 512)
let green = J2KComponent(index: 1, bitDepth: 8, width: 512, height: 512)
let blue = J2KComponent(index: 2, bitDepth: 8, width: 512, height: 512)

// YCbCr with 4:2:0 subsampling
let y = J2KComponent(index: 0, bitDepth: 8, width: 1920, height: 1080, dx: 1, dy: 1)
let cb = J2KComponent(index: 1, bitDepth: 8, width: 960, height: 540, dx: 2, dy: 2)
let cr = J2KComponent(index: 2, bitDepth: 8, width: 960, height: 540, dx: 2, dy: 2)
```

### J2KColorSpace

Supported color spaces.

```swift
public enum J2KColorSpace: Sendable, Equatable {
    case sRGB          // Standard RGB
    case grayscale     // Grayscale
    case yCbCr         // YCbCr (for JPEG 2000)
    case hdr           // HDR with PQ or HLG
    case hdrLinear     // Linear HDR
    case unknown       // Unknown/unspecified
}
```

**Examples:**

```swift
let rgbImage = J2KImage(width: 512, height: 512, components: 3, colorSpace: .sRGB)
let grayImage = J2KImage(width: 512, height: 512, components: 1, colorSpace: .grayscale)
let hdrImage = J2KImage(width: 3840, height: 2160, components: 3, bitDepth: 10, colorSpace: .hdr)
```

### J2KConfiguration

Configuration for encoding/decoding.

```swift
public struct J2KConfiguration: Sendable {
    public var quality: Double = 0.9            // 0.0-1.0
    public var lossless: Bool = false
    public var decompositionLevels: Int = 5     // Wavelet levels
    public var compressionRatio: Int? = nil
    public var tileSize: (Int, Int)? = nil
    public var codeBlockSize: (Int, Int) = (32, 32)
    public var progressionOrder: J2KProgressionOrder = .lrcp
}
```

**Examples:**

```swift
// Default configuration
let config = J2KConfiguration()

// High quality
let highQuality = J2KConfiguration(quality: 0.95)

// Lossless
let lossless = J2KConfiguration(lossless: true)

// Custom
let custom = J2KConfiguration(
    quality: 0.9,
    decompositionLevels: 6,
    codeBlockSize: (64, 64)
)
```

### J2KError

Error types for J2KSwift operations.

```swift
public enum J2KError: Error, Sendable {
    case invalidParameter(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case unsupportedFeature(String)
    case fileFormatError(String)
    case corruptedData(String)
    case memoryLimitExceeded
    case internalError(String)
}
```

**Usage:**

```swift
do {
    let image = try decoder.decode(data)
} catch J2KError.invalidParameter(let msg) {
    print("Invalid parameter: \(msg)")
} catch J2KError.decodingFailed(let msg) {
    print("Decoding failed: \(msg)")
} catch {
    print("Unexpected error: \(error)")
}
```

### J2KImageBuffer

Efficient pixel data storage.

```swift
public struct J2KImageBuffer: Sendable {
    public let width: Int
    public let height: Int
    public let bitDepth: Int
    
    public func getValue(at index: Int) -> Int32
    public mutating func setValue(_ value: Int32, at index: Int)
    public func getData() -> [Int32]
}
```

**Examples:**

```swift
// Create buffer
let buffer = J2KImageBuffer(width: 512, height: 512, bitDepth: 8)

// Set pixel value
buffer.setValue(255, at: 0)  // Set first pixel to 255

// Get pixel value
let value = buffer.getValue(at: 0)
```

## J2KCodec Module

Encoding and decoding functionality.

### J2KEncoder

Encodes images to JPEG 2000 format.

```swift
public struct J2KEncoder: Sendable {
    public let configuration: J2KConfiguration
    
    public init(configuration: J2KConfiguration = J2KConfiguration())
    public func encode(_ image: J2KImage) throws -> Data
}
```

**Examples:**

```swift
let encoder = J2KEncoder()
let data = try encoder.encode(image)

// With configuration
let config = J2KConfiguration(quality: 0.95)
let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)
```

### J2KDecoder

Decodes JPEG 2000 images.

```swift
public struct J2KDecoder: Sendable {
    public init()
    public func decode(_ data: Data) throws -> J2KImage
}
```

**Examples:**

```swift
let decoder = J2KDecoder()
let image = try decoder.decode(jpegData)
```

### J2KAdvancedDecoding

Advanced decoding features.

```swift
public struct J2KAdvancedDecoding: Sendable {
    // Partial decoding
    public func partialDecode(
        data: Data,
        options: J2KDecodingOptions
    ) throws -> J2KImage
    
    // ROI decoding
    public func decodeROI(
        data: Data,
        roi: J2KDecodingROI,
        strategy: J2KROIDecodingStrategy = .direct
    ) throws -> J2KImage
    
    // Resolution-progressive decoding
    public func decodeResolution(
        data: Data,
        level: Int,
        upscale: Bool = false
    ) throws -> J2KImage
    
    // Quality-progressive decoding
    public func decodeQuality(
        data: Data,
        upToLayer: Int
    ) throws -> J2KImage
    
    // Incremental decoding
    public func createIncrementalDecoder() throws -> J2KIncrementalDecoder
}
```

**Examples:**

```swift
let decoder = J2KAdvancedDecoding()

// Partial decode
let options = J2KDecodingOptions(maxLayers: 3, resolutionLevel: 1)
let partial = try decoder.partialDecode(data: data, options: options)

// ROI decode
let roi = J2KDecodingROI(x: 100, y: 100, width: 200, height: 200)
let region = try decoder.decodeROI(data: data, roi: roi, strategy: .direct)

// Resolution decode
let thumbnail = try decoder.decodeResolution(data: data, level: 2)
```

### Wavelet Transform (J2KDWT1D, J2KDWT2D)

Discrete wavelet transform implementation.

```swift
// 1D DWT
public struct J2KDWT1D: Sendable {
    public func forwardTransform(_ data: [Double], filter: J2KWaveletFilter) throws -> [Double]
    public func inverseTransform(_ data: [Double], filter: J2KWaveletFilter) throws -> [Double]
}

// 2D DWT
public struct J2KDWT2D: Sendable {
    public func forwardTransform(
        data: [Double],
        width: Int,
        height: Int,
        levels: Int,
        filter: J2KWaveletFilter
    ) throws -> J2KSubbandData
    
    public func inverseTransform(
        subbands: J2KSubbandData,
        width: Int,
        height: Int,
        levels: Int,
        filter: J2KWaveletFilter
    ) throws -> [Double]
}
```

### Quantization (J2KQuantization)

Quantization and dequantization.

```swift
public struct J2KQuantization: Sendable {
    public func quantize(
        subbands: J2KSubbandData,
        mode: J2KQuantizationMode,
        baseStepSize: Double
    ) -> [J2KCodeBlock]
    
    public func dequantize(
        codeBlock: J2KCodeBlock,
        stepSize: Double
    ) -> J2KSubbandData
}

public enum J2KQuantizationMode: Sendable {
    case scalar          // Uniform quantization
    case deadzone        // Deadzone quantization
    case expounded       // Explicit step sizes
    case noQuantization  // Lossless mode
}
```

### Color Transform (J2KColorTransform)

Color space transformations.

```swift
public struct J2KColorTransform: Sendable {
    // RGB ↔ YCbCr (Reversible, lossless)
    public func forwardRCT(r: [Int32], g: [Int32], b: [Int32]) -> (y: [Int32], cb: [Int32], cr: [Int32])
    public func inverseRCT(y: [Int32], cb: [Int32], cr: [Int32]) -> (r: [Int32], g: [Int32], b: [Int32])
    
    // RGB ↔ YCbCr (Irreversible, lossy)
    public func forwardICT(r: [Double], g: [Double], b: [Double]) -> (y: [Double], cb: [Double], cr: [Double])
    public func inverseICT(y: [Double], cb: [Double], cr: [Double]) -> (r: [Double], g: [Double], b: [Double])
    
    // RGB ↔ Grayscale
    public func rgbToGrayscale(_ rgb: [Int32], width: Int, height: Int) -> [Int32]
    public func grayscaleToRGB(_ gray: [Int32]) -> (r: [Int32], g: [Int32], b: [Int32])
}
```

### Encoding Presets (J2KEncodingPresets)

Predefined encoding configurations.

```swift
public struct J2KEncodingPresets {
    public static let fast: J2KEncodingPreset      // 2-3× faster
    public static let balanced: J2KEncodingPreset  // Optimal
    public static let quality: J2KEncodingPreset   // Best quality
}

public struct J2KEncodingPreset: Sendable {
    public let name: String
    public let decompositionLevels: Int
    public let codeBlockWidth: Int
    public let codeBlockHeight: Int
    public let layers: Int
    public let quality: Double
    public let parallelization: Bool
}
```

### Quality Metrics (J2KQualityMetrics)

Image quality measurement.

```swift
public struct J2KQualityMetrics: Sendable {
    public func calculatePSNR(
        original: J2KImage,
        reconstructed: J2KImage
    ) throws -> Double
    
    public func calculateSSIM(
        original: J2KImage,
        reconstructed: J2KImage
    ) throws -> Double
    
    public func calculateMSSSIM(
        original: J2KImage,
        reconstructed: J2KImage,
        scales: Int
    ) throws -> Double
}
```

## J2KAccelerate Module

Hardware acceleration using platform-specific frameworks.

### J2KAccelerate

Hardware-accelerated operations.

```swift
public struct J2KAccelerate: Sendable {
    // Check availability
    public static var isAvailable: Bool { get }
    
    // Accelerated DWT
    public func forwardDWT(
        data: [Double],
        width: Int,
        height: Int,
        levels: Int
    ) throws -> J2KSubbandData
    
    public func inverseDWT(
        subbands: J2KSubbandData,
        width: Int,
        height: Int,
        levels: Int
    ) throws -> [Double]
}
```

**Usage:**

```swift
if J2KAccelerate.isAvailable {
    let accelerate = J2KAccelerate()
    let transformed = try accelerate.forwardDWT(
        data: imageData,
        width: width,
        height: height,
        levels: 5
    )
}
```

## J2KFileFormat Module

File format support for JP2, JPX, JPM, etc.

### J2KFormat

Supported file formats.

```swift
public enum J2KFormat: String, Sendable {
    case jp2  // JPEG 2000 Part 1
    case j2k  // Raw codestream
    case jpx  // JPEG 2000 Part 2
    case jpm  // JPEG 2000 Part 6
    
    public var fileExtension: String { get }
    public var mimeType: String { get }
}
```

### J2KFormatDetector

Detect file format from data.

```swift
public struct J2KFormatDetector: Sendable {
    public init()
    public func detect(data: Data) throws -> J2KFormat
    public func detect(url: URL) throws -> J2KFormat
}
```

**Examples:**

```swift
let detector = J2KFormatDetector()
let format = try detector.detect(data: fileData)

switch format {
case .jp2: print("JP2 file")
case .j2k: print("J2K codestream")
case .jpx: print("JPX file")
case .jpm: print("JPM file")
}
```

### J2KFileReader

Read JPEG 2000 files.

```swift
public struct J2KFileReader: Sendable {
    public init()
    public func read(from url: URL) throws -> J2KImage
    public func read(data: Data) throws -> J2KImage
}
```

### J2KFileWriter

Write JPEG 2000 files.

```swift
public struct J2KFileWriter: Sendable {
    public let format: J2KFormat
    
    public init(format: J2KFormat)
    public func write(_ image: J2KImage, to url: URL) throws
    public func write(_ image: J2KImage) throws -> Data
}
```

**Examples:**

```swift
// Write JP2 file
let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: outputURL)

// Write to data
let data = try writer.write(image)
```

### JP2 Box Types

JP2 file format box types.

```swift
// Signature Box
public struct J2KSignatureBox: J2KBox

// File Type Box
public struct J2KFileTypeBox: J2KBox {
    public let brand: String
    public let minorVersion: UInt32
    public let compatibleBrands: [String]
}

// Image Header Box
public struct J2KImageHeaderBox: J2KBox {
    public let width: UInt32
    public let height: UInt32
    public let numComponents: UInt16
    public let bitDepth: UInt8
    public let compressionType: UInt8
}

// Color Specification Box
public struct J2KColorSpecificationBox: J2KBox {
    public let method: ColorMethod
    public let colorSpace: J2KColorSpace
    public let iccProfile: Data?
}

// Resolution Box
public struct J2KResolutionBox: J2KBox {
    public let captureResolution: (hNum: UInt16, hDenom: UInt16, vNum: UInt16, vDenom: UInt16)?
    public let displayResolution: (hNum: UInt16, hDenom: UInt16, vNum: UInt16, vDenom: UInt16)?
}
```

## JPIP Module

JPEG 2000 Interactive Protocol for network streaming.

### JPIPClient

Client for JPIP protocol.

```swift
public actor JPIPClient {
    public init(serverURL: URL)
    
    public func createSession(target: String) async throws -> JPIPSession
    public func requestImage(imageID: String) async throws -> J2KImage
    public func requestRegion(
        imageID: String,
        region: (x: Int, y: Int, width: Int, height: Int)
    ) async throws -> J2KImage
}
```

**Examples:**

```swift
let client = JPIPClient(serverURL: URL(string: "http://example.com/jpip")!)

// Create session
let session = try await client.createSession(target: "sample.jp2")

// Request full image
let image = try await client.requestImage(imageID: "sample.jp2")

// Request region
let region = try await client.requestRegion(
    imageID: "sample.jp2",
    region: (x: 100, y: 100, width: 512, height: 512)
)
```

### JPIPSession

JPIP session management.

```swift
public actor JPIPSession {
    public let channelID: String
    
    public func request(
        region: (x: Int, y: Int, width: Int, height: Int)?,
        layers: Int?,
        components: [Int]?
    ) async throws -> Data
    
    public func getCacheStatistics() async -> JPIPCacheStatistics
    public func invalidateCache() async
}
```

### JPIPServer

JPIP server implementation.

```swift
public actor JPIPServer {
    public init(port: Int = 8080)
    
    public func start() async throws
    public func stop() async
    public func registerImage(id: String, data: Data) async
}
```

**Examples:**

```swift
let server = JPIPServer(port: 8080)

// Register images
await server.registerImage(id: "image1.jp2", data: imageData1)
await server.registerImage(id: "image2.jp2", data: imageData2)

// Start server
try await server.start()
```

## Common Patterns

### Error Handling

```swift
do {
    let image = try decoder.decode(data)
} catch J2KError.invalidParameter(let msg) {
    // Handle invalid parameter
} catch J2KError.decodingFailed(let msg) {
    // Handle decoding failure
} catch {
    // Handle other errors
}
```

### Async/Await

```swift
// JPIP operations are async
let client = JPIPClient(serverURL: url)
let image = try await client.requestImage(imageID: "test.jp2")

// Parallel operations
async let image1 = client.requestImage(imageID: "img1.jp2")
async let image2 = client.requestImage(imageID: "img2.jp2")
let images = try await [image1, image2]
```

### Type Safety

```swift
// All types are Sendable for Swift 6 concurrency
let encoder: J2KEncoder = J2KEncoder()  // Sendable
let image: J2KImage = image              // Sendable
let config: J2KConfiguration = config    // Sendable
```

## Next Steps

- [Getting Started Guide](GETTING_STARTED.md)
- [Encoding Tutorial](TUTORIAL_ENCODING.md)
- [Decoding Tutorial](TUTORIAL_DECODING.md)
- [Migration Guide](MIGRATION_GUIDE.md)

---

**Status**: API Reference for Phase 8 (Production Ready)  
**Last Updated**: 2026-02-07
