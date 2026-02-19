# Motion JPEG 2000 VideoToolbox Integration

This document provides comprehensive guidance on using VideoToolbox integration for hardware-accelerated transcoding between Motion JPEG 2000 and modern video codecs (H.264/H.265) on Apple platforms.

## Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Hardware Capabilities](#hardware-capabilities)
- [Encoder Integration](#encoder-integration)
- [Decoder Integration](#decoder-integration)
- [Metal Preprocessing](#metal-preprocessing)
- [Performance Optimization](#performance-optimization)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

## Overview

The MJ2VideoToolbox module provides seamless integration with Apple's VideoToolbox framework, enabling:

- **Hardware-accelerated encoding** of J2KImage frames to H.264/H.265
- **Hardware-accelerated decoding** of H.264/H.265 to J2KImage frames
- **Metal-accelerated preprocessing** for color conversion and scaling
- **Zero-copy buffer sharing** when possible for optimal performance
- **Automatic fallback** to software encoding/decoding when hardware is unavailable

### Key Features

- ✅ H.264 (AVC) encoding and decoding
- ✅ H.265 (HEVC) encoding and decoding
- ✅ Hardware encoder capability detection
- ✅ Quality and bitrate control
- ✅ Frame rate configuration
- ✅ B-frame support
- ✅ Profile and level selection
- ✅ Metal-accelerated color space conversion
- ✅ GPU-based image scaling
- ✅ Efficient pixel format conversion

## Requirements

### Platform Support

- **macOS**: 13.0+
- **iOS**: 16.0+
- **tvOS**: 16.0+
- **visionOS**: 1.0+

### Hardware Requirements

- **Encoding**: Apple Silicon (M1+) or Intel with dedicated GPU recommended
- **Decoding**: Most modern Apple devices support hardware-accelerated H.264/H.265 decoding
- **Metal**: Required for GPU-accelerated preprocessing

### Framework Dependencies

```swift
import VideoToolbox  // Hardware video encoding/decoding
import CoreMedia     // Media sample buffers and timing
import CoreVideo     // Pixel buffer management
import Metal         // GPU-accelerated preprocessing
```

## Hardware Capabilities

### Detecting Capabilities

Before encoding or decoding, query available hardware capabilities:

```swift
import J2KCodec

let capabilities = MJ2VideoToolboxCapabilityDetector.detectCapabilities()

print("H.264 Hardware Encoder: \(capabilities.h264HardwareEncoderAvailable)")
print("H.265 Hardware Encoder: \(capabilities.h265HardwareEncoderAvailable)")
print("H.264 Hardware Decoder: \(capabilities.h264HardwareDecoderAvailable)")
print("H.265 Hardware Decoder: \(capabilities.h265HardwareDecoderAvailable)")
print("Max Resolution: \(capabilities.maxResolution.width)x\(capabilities.maxResolution.height)")
print("Supported Pixel Formats: \(capabilities.supportedPixelFormats.count)")
```

### Hardware Support Matrix

| Device | H.264 Encode | H.265 Encode | H.264 Decode | H.265 Decode |
|--------|--------------|--------------|--------------|--------------|
| Apple Silicon (M1+) | ✅ | ✅ | ✅ | ✅ |
| Intel Mac (2016+) | ✅ | ⚠️ | ✅ | ✅ |
| iPhone (A10+) | ✅ | ✅ | ✅ | ✅ |
| iPad (A10+) | ✅ | ✅ | ✅ | ✅ |

⚠️ = May not be available on all configurations

## Encoder Integration

### Basic H.264 Encoding

```swift
import J2KCodec
import CoreMedia

// Create encoder with default H.264 configuration
let config = MJ2VideoToolboxEncoderConfiguration.defaultH264(
    bitrate: 5_000_000,  // 5 Mbps
    frameRate: 24.0
)

let encoder = MJ2VideoToolboxEncoder(configuration: config)

// Initialize for 1920x1080 video
try await encoder.initialize(width: 1920, height: 1080)

// Encode a J2KImage frame
let presentationTime = CMTime(value: 0, timescale: 24)
let duration = CMTime(value: 1, timescale: 24)

let sampleBuffer = try await encoder.encode(
    image: myJ2KImage,
    presentationTime: presentationTime,
    duration: duration
)

// Finish encoding and flush pending frames
try await encoder.finish()
```

### Advanced H.265 Encoding

```swift
// Custom H.265 configuration
let config = MJ2VideoToolboxEncoderConfiguration(
    codec: .h265,
    bitrate: 3_000_000,                    // 3 Mbps (H.265 is more efficient)
    frameRate: 30.0,
    useHardwareAcceleration: true,
    profileLevel: kVTProfileLevel_HEVC_Main_AutoLevel as String,
    maxKeyFrameInterval: 120,               // Keyframe every 4 seconds at 30fps
    allowBFrames: true,                     // Enable B-frames for better compression
    quality: 0.85,
    multiPass: false
)

let encoder = MJ2VideoToolboxEncoder(configuration: config)
try await encoder.initialize(width: 3840, height: 2160)  // 4K

// Encode multiple frames
for (index, image) in frames.enumerated() {
    let time = CMTime(value: Int64(index), timescale: 30)
    let duration = CMTime(value: 1, timescale: 30)
    
    let buffer = try await encoder.encode(
        image: image,
        presentationTime: time,
        duration: duration
    )
    
    // Process encoded buffer (write to file, stream, etc.)
}

try await encoder.finish()
```

### Quality-Based Encoding

For quality-based encoding (instead of bitrate), set `bitrate` to 0:

```swift
let config = MJ2VideoToolboxEncoderConfiguration(
    codec: .h264,
    bitrate: 0,              // Use quality instead
    frameRate: 24.0,
    useHardwareAcceleration: true,
    profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
    maxKeyFrameInterval: 60,
    allowBFrames: true,
    quality: 0.9,            // 0.0 = low quality, 1.0 = high quality
    multiPass: false
)
```

### Profile and Level Selection

Choose appropriate profiles for your use case:

**H.264 Profiles:**
- `kVTProfileLevel_H264_Baseline_AutoLevel` - Maximum compatibility, simple encoding
- `kVTProfileLevel_H264_Main_AutoLevel` - Balanced features and compatibility
- `kVTProfileLevel_H264_High_AutoLevel` - Best compression, advanced features

**H.265 Profiles:**
- `kVTProfileLevel_HEVC_Main_AutoLevel` - Standard 8-bit encoding
- `kVTProfileLevel_HEVC_Main10_AutoLevel` - 10-bit encoding for HDR

## Decoder Integration

### Basic H.264 Decoding

```swift
import J2KCodec
import CoreMedia

// Create decoder with default configuration
let config = MJ2VideoToolboxDecoderConfiguration.default()
let decoder = MJ2VideoToolboxDecoder(configuration: config)

// Initialize with format description from encoded stream
let formatDescription: CMFormatDescription = ... // From encoded data
try await decoder.initialize(formatDescription: formatDescription)

// Decode sample buffer
let image = try await decoder.decode(sampleBuffer: sampleBuffer)

// image is now a J2KImage ready for further processing
print("Decoded: \(image.width)x\(image.height)")

// Cleanup
await decoder.finish()
```

### Custom Decoder Configuration

```swift
let config = MJ2VideoToolboxDecoderConfiguration(
    useHardwareAcceleration: true,
    deinterlace: false,
    outputColorSpace: .yCbCr  // Output in YCbCr color space
)

let decoder = MJ2VideoToolboxDecoder(configuration: config)
```

## Metal Preprocessing

### Color Space Conversion

Use Metal for efficient GPU-accelerated color space conversion:

```swift
import J2KMetal
import Metal

// Get Metal device
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal not available")
}

// Create preprocessing engine
let config = MJ2MetalPreprocessingConfiguration(
    pixelFormat: .bgra32,
    scalingMode: .bilinear,
    enableZeroCopy: true,
    maxTextureSize: 8192
)

let preprocessing = try MJ2MetalPreprocessing(
    device: device,
    configuration: config
)

// Convert J2KImage to CVPixelBuffer for VideoToolbox
let pixelBuffer = try await preprocessing.convertToPixelBuffer(
    image: myJ2KImage,
    outputFormat: .bgra32
)

// Or convert CVPixelBuffer back to J2KImage
let image = try await preprocessing.convertToJ2KImage(
    pixelBuffer: decodedPixelBuffer,
    targetColorSpace: .sRGB
)
```

### GPU-Accelerated Scaling

```swift
// Scale image using Metal
let scaledImage = try await preprocessing.scale(
    image: originalImage,
    targetWidth: 1920,
    targetHeight: 1080,
    scalingMode: .lanczos  // High-quality Lanczos interpolation
)
```

### Scaling Modes

- **`.nearest`** - Fastest, lowest quality (pixelated)
- **`.bilinear`** - Balanced speed and quality (default)
- **`.lanczos`** - Best quality, slower (sharp, minimal artifacts)

### Zero-Copy Buffer Sharing

Enable zero-copy for optimal performance when possible:

```swift
let config = MJ2MetalPreprocessingConfiguration(
    pixelFormat: .bgra32,
    scalingMode: .bilinear,
    enableZeroCopy: true,  // Enable zero-copy when possible
    maxTextureSize: 8192
)
```

This creates a `CVMetalTextureCache` for direct Metal-to-CoreVideo buffer sharing without CPU copies.

## Performance Optimization

### Asynchronous Pipeline

For maximum throughput, process frames asynchronously:

```swift
actor FrameEncoder {
    private let encoder: MJ2VideoToolboxEncoder
    
    init(config: MJ2VideoToolboxEncoderConfiguration) {
        self.encoder = MJ2VideoToolboxEncoder(configuration: config)
    }
    
    func encodeFrames(_ frames: [J2KImage]) async throws -> [CMSampleBuffer] {
        var encoded: [CMSampleBuffer] = []
        
        for (index, frame) in frames.enumerated() {
            let time = CMTime(value: Int64(index), timescale: 30)
            let duration = CMTime(value: 1, timescale: 30)
            
            let buffer = try await encoder.encode(
                image: frame,
                presentationTime: time,
                duration: duration
            )
            
            encoded.append(buffer)
        }
        
        return encoded
    }
}
```

### Parallel Frame Processing

Process multiple frames in parallel using structured concurrency:

```swift
// Process frames in batches
let batchSize = 4
let batches = frames.chunked(into: batchSize)

for batch in batches {
    try await withThrowingTaskGroup(of: CMSampleBuffer.self) { group in
        for (index, frame) in batch.enumerated() {
            group.addTask {
                let time = CMTime(value: Int64(index), timescale: 30)
                let duration = CMTime(value: 1, timescale: 30)
                
                return try await encoder.encode(
                    image: frame,
                    presentationTime: time,
                    duration: duration
                )
            }
        }
        
        // Collect results
        for try await buffer in group {
            // Process encoded buffer
        }
    }
}
```

### Memory Management

Manage memory efficiently during batch encoding:

```swift
// Use autoreleasepool for batch processing
for batch in batches {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for frame in batch {
            group.addTask {
                // Process frame
                let buffer = try await encoder.encode(...)
                
                // Explicitly release references
                CVBufferRemoveAllAttachments(buffer)
            }
        }
        
        try await group.waitForAll()
    }
}
```

## Best Practices

### 1. Check Hardware Availability

Always check hardware capabilities before encoding/decoding:

```swift
let capabilities = MJ2VideoToolboxCapabilityDetector.detectCapabilities()

guard capabilities.h265HardwareEncoderAvailable else {
    // Fall back to H.264 or software encoding
    print("H.265 encoder not available, using H.264")
}
```

### 2. Choose Appropriate Bitrates

Recommended bitrates for different resolutions:

| Resolution | H.264 Bitrate | H.265 Bitrate |
|------------|---------------|---------------|
| 640x480 (SD) | 1-2 Mbps | 0.5-1 Mbps |
| 1280x720 (HD) | 2-4 Mbps | 1-2 Mbps |
| 1920x1080 (Full HD) | 4-8 Mbps | 2-4 Mbps |
| 3840x2160 (4K) | 15-25 Mbps | 8-12 Mbps |

### 3. Configure Keyframe Intervals

Balance seek performance with compression efficiency:

```swift
// For streaming: shorter intervals (better seek, larger file)
maxKeyFrameInterval: 30  // Keyframe every 1 second at 30fps

// For storage: longer intervals (better compression)
maxKeyFrameInterval: 120  // Keyframe every 4 seconds at 30fps
```

### 4. Use Metal for Preprocessing

Offload color conversion and scaling to GPU:

```swift
// Create Metal preprocessing engine once
let preprocessing = try MJ2MetalPreprocessing(device: device)

// Reuse for all frames
for image in images {
    let pixelBuffer = try await preprocessing.convertToPixelBuffer(
        image: image,
        outputFormat: .bgra32
    )
    // Encode pixelBuffer...
}
```

### 5. Profile Your Pipeline

Use Instruments to identify bottlenecks:

```bash
# Record performance trace
xcrun xctrace record --template 'Time Profiler' \
  --launch MyApp \
  --output trace.trace

# View in Instruments
open trace.trace
```

### 6. Handle Errors Gracefully

```swift
do {
    let buffer = try await encoder.encode(image: frame, ...)
    // Success
} catch MJ2VideoToolboxError.hardwareNotAvailable {
    // Fall back to software encoding
} catch MJ2VideoToolboxError.encodingFailed(let status) {
    print("Encoding failed with status: \(status)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Troubleshooting

### Hardware Encoder Not Available

**Problem**: `hardwareNotAvailable` error

**Solutions**:
1. Check hardware capabilities with `detectCapabilities()`
2. Disable hardware acceleration: `useHardwareAcceleration: false`
3. Try H.264 instead of H.265
4. Check system resources (other apps using encoder)

### Poor Quality Output

**Problem**: Encoded video has artifacts or low quality

**Solutions**:
1. Increase bitrate: `bitrate: 10_000_000`
2. Use quality mode: `bitrate: 0, quality: 0.9`
3. Try H.265 for better compression
4. Disable B-frames for simpler encoding: `allowBFrames: false`

### Memory Issues

**Problem**: High memory usage during encoding

**Solutions**:
1. Process frames in smaller batches
2. Use `autoreleasepool` for batch processing
3. Enable zero-copy: `enableZeroCopy: true`
4. Release encoded buffers promptly

### Frame Rate Issues

**Problem**: Cannot achieve target frame rate

**Solutions**:
1. Use hardware acceleration: `useHardwareAcceleration: true`
2. Reduce resolution or quality
3. Use Metal preprocessing for color conversion
4. Process frames in parallel with structured concurrency

### Color Space Conversion Issues

**Problem**: Incorrect colors after encoding/decoding

**Solutions**:
1. Ensure correct color space in configuration
2. Use Metal preprocessing for accurate conversion
3. Check pixel format compatibility
4. Verify J2KImage color space matches expected format

## Example: Complete Transcoding Pipeline

```swift
import J2KCodec
import J2KMetal
import Metal

class MJ2VideoTranscoder {
    private let device: MTLDevice
    private let preprocessing: MJ2MetalPreprocessing
    private let encoder: MJ2VideoToolboxEncoder
    
    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MJ2VideoToolboxError.notAvailable
        }
        self.device = device
        
        let metalConfig = MJ2MetalPreprocessingConfiguration.default()
        self.preprocessing = try MJ2MetalPreprocessing(
            device: device,
            configuration: metalConfig
        )
        
        let encoderConfig = MJ2VideoToolboxEncoderConfiguration.defaultH265(
            bitrate: 5_000_000,
            frameRate: 30.0
        )
        self.encoder = MJ2VideoToolboxEncoder(configuration: encoderConfig)
    }
    
    func transcodeFrames(_ frames: [J2KImage]) async throws -> [CMSampleBuffer] {
        // Initialize encoder
        let firstFrame = frames.first!
        try await encoder.initialize(
            width: firstFrame.width,
            height: firstFrame.height
        )
        
        var encoded: [CMSampleBuffer] = []
        
        // Process frames
        for (index, frame) in frames.enumerated() {
            // Convert to pixel buffer using Metal
            let pixelBuffer = try await preprocessing.convertToPixelBuffer(
                image: frame,
                outputFormat: .bgra32
            )
            
            // Encode with VideoToolbox
            let time = CMTime(value: Int64(index), timescale: 30)
            let duration = CMTime(value: 1, timescale: 30)
            
            let buffer = try await encoder.encode(
                image: frame,
                presentationTime: time,
                duration: duration
            )
            
            encoded.append(buffer)
        }
        
        // Finish encoding
        try await encoder.finish()
        
        return encoded
    }
}

// Usage
let transcoder = try MJ2VideoTranscoder()
let frames: [J2KImage] = ...  // Your frames
let encoded = try await transcoder.transcodeFrames(frames)
```

## API Reference

For detailed API documentation, see:
- `MJ2VideoToolboxEncoder` - Hardware video encoding
- `MJ2VideoToolboxDecoder` - Hardware video decoding
- `MJ2MetalPreprocessing` - GPU preprocessing
- `MJ2VideoToolboxCapabilityDetector` - Hardware capability detection

## See Also

- [Motion JPEG 2000 Implementation Plan](MOTION_JPEG2000.md)
- [Metal API Guide](Documentation/METAL_API.md)
- [Apple Silicon Optimization](Documentation/APPLE_SILICON_OPTIMIZATION.md)
- [Performance Guide](PERFORMANCE.md)
