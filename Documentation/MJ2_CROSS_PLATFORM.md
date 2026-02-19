# MJ2 Cross-Platform Transcoding Guide

## Overview

This guide explains how to use Motion JPEG 2000 video transcoding across different platforms, including Apple platforms with VideoToolbox hardware acceleration and non-Apple platforms with software fallbacks.

## Platform Support

### Apple Platforms (macOS, iOS, tvOS, visionOS)

**Hardware Acceleration**: VideoToolbox provides hardware-accelerated H.264/H.265 encoding and decoding.

**Supported Codecs**:
- H.264 (AVC)
- H.265 (HEVC)

**Performance**: 60-120+ fps at 1080p on Apple Silicon

### Non-Apple Platforms (Linux, Windows)

**Software Fallbacks**:
1. FFmpeg (recommended if installed)
2. Basic software encoder (minimal features)

**Supported Codecs**:
- H.264 (via FFmpeg or software fallback)
- H.265 (via FFmpeg only)

**Performance**: 10-30 fps at 1080p with FFmpeg, 1-5 fps with basic software encoder

## Architecture Support

### Apple Silicon (ARM64) - Recommended

- Full hardware acceleration via VideoToolbox
- Metal GPU preprocessing
- AMX matrix coprocessor support
- Best performance and power efficiency

### x86-64 (Intel)

⚠️ **Deprecation Notice**: x86-64 support will be removed in a future major version (v2.0.0 or later).

**Current Support**:
- Software encoding only on non-Apple platforms
- VideoToolbox available on Intel Macs
- AVX/AVX2 SIMD optimizations
- Consider using Rosetta 2 for ARM64 builds on Intel Macs

**Migration Path**:
1. Use Apple Silicon hardware for best performance
2. Run ARM64 builds via Rosetta 2 on Intel Macs
3. Use FFmpeg for software encoding on non-Apple x86-64 platforms

## Quick Start

### Automatic Encoder Selection

The easiest way to use video transcoding is with automatic encoder selection:

```swift
import J2KCodec

// Create encoder with automatic selection
let encoder = try await MJ2EncoderFactory.createEncoder(
    codec: .h264,
    quality: .medium,
    performance: .balanced
)

print("Using \(encoder.encoderType) encoder")
print("Hardware accelerated: \(encoder.isHardwareAccelerated)")

// Encode frames
try await encoder.startEncoding()
for frame in frames {
    let data = try await encoder.encode(frame)
    // Process encoded data
}
let finalData = try await encoder.finishEncoding()
```

### Check Available Encoders

```swift
// Detect available encoders
let encoders = MJ2EncoderFactory.detectAvailableEncoders()
print("Available encoders: \(encoders)")

// Get detailed capabilities
let capabilities = MJ2EncoderFactory.detectCapabilities()
for (type, caps) in capabilities {
    print("\(type): \(caps.supportedCodecs)")
}

// Print full capability report
MJ2EncoderFactory.printCapabilityReport()
```

### Platform-Specific Usage

#### Apple Platforms (VideoToolbox)

```swift
#if canImport(VideoToolbox)
import VideoToolbox

let config = MJ2VideoToolboxEncoderConfiguration(
    codec: .h265,
    bitrate: 5_000_000,
    frameRate: 30.0,
    useHardwareAcceleration: true
)

let encoder = MJ2VideoToolboxEncoder(configuration: config)
try await encoder.startEncoding()
// ... encode frames
#endif
```

#### Non-Apple Platforms (Software)

```swift
// Use FFmpeg if available
let config = MJ2SoftwareEncoderConfiguration(
    codec: .h264,
    quality: .medium,
    performance: .balanced
)

let encoder = MJ2SoftwareEncoder(configuration: config)

// Check if FFmpeg is available
if encoder.encoderType == .ffmpeg {
    print("Using FFmpeg for encoding")
} else {
    print("Using basic software fallback")
}

try await encoder.startEncoding()
// ... encode frames
```

## Configuration

### Quality Presets

```swift
// High quality (slow, best for archival)
let high = MJ2TranscodingQuality.high

// Medium quality (balanced)
let medium = MJ2TranscodingQuality.medium

// Low quality (fast, good for previews)
let low = MJ2TranscodingQuality.low

// Bitrate-based (for streaming)
let streaming1080p = MJ2TranscodingQuality.bitrate1080p  // 5 Mbps
let streaming720p = MJ2TranscodingQuality.bitrate720p   // 3 Mbps
```

### Performance Presets

```swift
// Real-time (prioritize speed)
let realtime = MJ2PerformanceConfiguration.realtime

// Balanced (default)
let balanced = MJ2PerformanceConfiguration.balanced

// High quality (prioritize quality over speed)
let highQuality = MJ2PerformanceConfiguration.highQuality
```

### Custom Configuration

```swift
// Quality-based encoding
let quality = MJ2TranscodingQuality(
    mode: .quality(0.85),
    allowMultiPass: true
)

// Bitrate-based encoding
let bitrate = MJ2TranscodingQuality(
    mode: .bitrate(8_000_000),  // 8 Mbps
    allowMultiPass: false
)

// Constant QP
let constantQP = MJ2TranscodingQuality(
    mode: .constantQP(22),
    allowMultiPass: false
)

// Performance configuration
let performance = MJ2PerformanceConfiguration(
    priority: .balanced,
    allowHardwareAcceleration: true,
    maxThreads: 8
)
```

## FFmpeg Integration

### Installing FFmpeg

#### macOS
```bash
brew install ffmpeg
```

#### Ubuntu/Debian
```bash
sudo apt-get install ffmpeg
```

#### Windows
Download from [ffmpeg.org](https://ffmpeg.org/) and add to PATH.

### Verifying FFmpeg

```swift
if MJ2SoftwareEncoder.isFFmpegAvailable() {
    print("FFmpeg is installed and available")
} else {
    print("FFmpeg is not available - using basic software fallback")
}
```

### FFmpeg Custom Options

```swift
let config = MJ2SoftwareEncoderConfiguration(
    codec: .h265,
    quality: .high,
    performance: .balanced,
    frameRate: 24.0,
    ffmpegOptions: [
        "-preset", "slow",
        "-crf", "18",
        "-x265-params", "log-level=error"
    ]
)
```

## Platform Detection

### Runtime Detection

```swift
// Detect current platform
let platform = MJ2PlatformCapabilities.currentPlatform
switch platform {
case .apple:
    print("Running on Apple platform")
case .linux:
    print("Running on Linux")
case .windows:
    print("Running on Windows")
case .unix:
    print("Running on Unix-like platform")
case .unknown:
    print("Unknown platform")
}

// Check specific capabilities
print("Architecture: \(MJ2PlatformCapabilities.architecture)")
print("VideoToolbox: \(MJ2PlatformCapabilities.hasVideoToolbox)")
print("Metal: \(MJ2PlatformCapabilities.hasMetal)")
print("ARM64: \(MJ2PlatformCapabilities.isARM64)")
print("x86_64: \(MJ2PlatformCapabilities.isX86_64)")
```

### Conditional Compilation

```swift
#if os(macOS) || os(iOS)
// Apple-specific code
#elseif os(Linux)
// Linux-specific code
#elseif os(Windows)
// Windows-specific code
#endif

#if arch(arm64)
// ARM64-specific code
#elseif arch(x86_64)
// x86-64-specific code
#endif
```

## Error Handling

### Common Errors

```swift
do {
    let encoder = try await MJ2EncoderFactory.createEncoder(
        codec: .h265,
        quality: .high
    )
    try await encoder.startEncoding()
    // ... encode
} catch MJ2VideoEncoderError.notAvailable {
    print("No encoder available on this platform")
} catch MJ2VideoEncoderError.hardwareNotAvailable {
    print("Hardware encoder not available, falling back to software")
} catch MJ2VideoEncoderError.unsupportedCodec(let codec) {
    print("Codec \(codec) not supported by this encoder")
} catch MJ2VideoEncoderError.invalidDimensions(let width, let height) {
    print("Invalid frame dimensions: \(width)x\(height)")
} catch {
    print("Encoding error: \(error)")
}
```

## Performance Considerations

### Hardware vs Software

| Platform | Encoder | 1080p fps | 4K fps | Power |
|----------|---------|-----------|--------|-------|
| Apple Silicon | VideoToolbox | 120+ | 60+ | Low |
| Intel Mac | VideoToolbox | 60+ | 30+ | Medium |
| Linux (FFmpeg) | Software | 20-30 | 5-10 | High |
| Basic Software | Software | 1-5 | <1 | High |

### Optimization Tips

1. **Use Hardware Acceleration**: Always prefer VideoToolbox on Apple platforms
2. **Install FFmpeg**: On non-Apple platforms, install FFmpeg for better performance
3. **Lower Resolution**: Consider encoding at lower resolution for real-time applications
4. **Adjust Quality**: Use lower quality presets for faster encoding
5. **Parallel Encoding**: Encode multiple frames in parallel when possible

### Memory Usage

```swift
// Monitor memory usage
let encoder = try await MJ2EncoderFactory.createEncoder(
    codec: .h264,
    quality: .medium,
    performance: .balanced
)

// Process frames in batches to manage memory
let batchSize = 100
for batch in frames.chunked(into: batchSize) {
    for frame in batch {
        _ = try await encoder.encode(frame)
    }
    // Release batch memory
}
```

## Best Practices

1. **Always check capabilities** before creating encoders
2. **Handle errors gracefully** with appropriate fallbacks
3. **Monitor performance** and adjust quality settings as needed
4. **Use appropriate quality presets** for your use case
5. **Test on target platforms** to ensure compatibility
6. **Consider x86-64 deprecation** in long-term planning

## Migration from x86-64

If you're using x86-64 platforms:

1. **Intel Macs**: 
   - Use VideoToolbox (still supported)
   - Consider running ARM64 builds via Rosetta 2
   - Plan migration to Apple Silicon hardware

2. **Non-Apple x86-64**:
   - Use FFmpeg for software encoding
   - Consider ARM64 Linux servers for better performance
   - Prepare for x86-64 removal in v2.0.0

3. **Timeline**:
   - v1.7.0-v1.x.x: Full x86-64 support with deprecation warnings
   - v2.0.0: x86-64 support removed

## Examples

### Complete Encoding Pipeline

```swift
import J2KCore
import J2KCodec

func transcodeToH265(frames: [J2KImage]) async throws -> Data {
    // Create encoder
    let encoder = try await MJ2EncoderFactory.createEncoder(
        codec: .h265,
        quality: .high,
        performance: .balanced
    )
    
    print("Using \(encoder.encoderType) encoder")
    print("Hardware: \(encoder.isHardwareAccelerated)")
    
    // Start encoding
    try await encoder.startEncoding()
    
    // Encode frames
    var encodedFrames: [Data] = []
    for (index, frame) in frames.enumerated() {
        print("Encoding frame \(index + 1)/\(frames.count)")
        let data = try await encoder.encode(frame)
        encodedFrames.append(data)
    }
    
    // Finish encoding
    let finalData = try await encoder.finishEncoding()
    
    // Combine all data
    var combined = Data()
    for data in encodedFrames {
        combined.append(data)
    }
    combined.append(finalData)
    
    return combined
}
```

### Platform-Aware Encoding

```swift
func createOptimalEncoder() async throws -> any MJ2VideoEncoderProtocol {
    let platform = MJ2PlatformCapabilities.currentPlatform
    
    switch platform {
    case .apple:
        // Use hardware acceleration on Apple platforms
        return try await MJ2EncoderFactory.createEncoder(
            codec: .h265,
            quality: .high,
            performance: .highQuality,
            preferHardware: true
        )
        
    case .linux, .windows:
        // Use software encoding with appropriate settings
        return try await MJ2EncoderFactory.createEncoder(
            codec: .h264,  // H.264 is more widely supported
            quality: .medium,  // Lower quality for faster encoding
            performance: .realtime,  // Prioritize speed
            preferHardware: false
        )
        
    case .unix, .unknown:
        // Conservative settings for unknown platforms
        return try await MJ2EncoderFactory.createEncoder(
            codec: .h264,
            quality: .low,
            performance: .realtime,
            preferHardware: false
        )
    }
}
```

## Troubleshooting

### Encoder Not Available

**Problem**: `MJ2VideoEncoderError.notAvailable`

**Solutions**:
1. Install FFmpeg on the system
2. Use basic software fallback (limited features)
3. Consider running on a different platform

### Poor Performance

**Problem**: Encoding is too slow

**Solutions**:
1. Use hardware acceleration if available
2. Lower encoding quality preset
3. Reduce frame resolution
4. Install FFmpeg if using basic software fallback

### Unsupported Codec

**Problem**: `MJ2VideoEncoderError.unsupportedCodec`

**Solutions**:
1. Check encoder capabilities before creating
2. Use H.264 instead of H.265 for broader support
3. Install FFmpeg for more codec support

## Reference

### Classes

- `MJ2EncoderFactory` - Factory for creating encoders
- `MJ2SoftwareEncoder` - Software-based encoder
- `MJ2VideoToolboxEncoder` - Hardware-accelerated encoder (Apple only)

### Protocols

- `MJ2VideoEncoderProtocol` - Encoder interface
- `MJ2VideoDecoderProtocol` - Decoder interface

### Types

- `MJ2VideoCodec` - Codec types (.h264, .h265, .mj2)
- `MJ2EncoderType` - Encoder implementations
- `MJ2TranscodingQuality` - Quality configuration
- `MJ2PerformanceConfiguration` - Performance settings
- `MJ2PlatformCapabilities` - Platform detection

### Errors

- `MJ2VideoEncoderError` - Encoding errors
- `MJ2VideoDecoderError` - Decoding errors

---

**Last Updated**: 2026-02-19  
**Version**: 1.7.0  
**Maintainer**: J2KSwift Team
