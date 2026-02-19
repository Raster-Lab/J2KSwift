# Motion JPEG 2000 Performance Guide

This document provides comprehensive guidance on optimizing Motion JPEG 2000 (MJ2) encoding, decoding, and playback performance in J2KSwift.

## Table of Contents

1. [Performance Overview](#performance-overview)
2. [Encoding Optimization](#encoding-optimization)
3. [Decoding Optimization](#decoding-optimization)
4. [Playback Optimization](#playback-optimization)
5. [I/O Optimization](#io-optimization)
6. [Memory Management](#memory-management)
7. [Hardware Requirements](#hardware-requirements)
8. [Benchmarking](#benchmarking)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

## Performance Overview

J2KSwift's MJ2 implementation is designed for real-time performance on modern hardware. Key performance characteristics include:

### Baseline Performance (Reference Hardware)

On modern multi-core systems (4+ cores, 8GB+ RAM):

| Operation | Resolution | Target FPS | Typical Performance |
|-----------|------------|------------|---------------------|
| Encoding (Sequential) | 640×480 | 30 fps | 1-5 fps |
| Encoding (Parallel) | 640×480 | 30 fps | 3-15 fps |
| Encoding (Sequential) | 1920×1080 | 30 fps | 0.2-2 fps |
| Encoding (Parallel) | 1920×1080 | 30 fps | 1-8 fps |
| Decoding (Sequential) | 640×480 | 30 fps | 5-20 fps |
| Decoding (Parallel) | 640×480 | 30 fps | 15-60 fps |
| Playback (Cached) | 640×480 | 30 fps | 30+ fps |

**Note**: Performance varies significantly based on content complexity, quality settings, and hardware capabilities.

### Performance Factors

The following factors significantly impact MJ2 performance:

1. **Image Resolution**: Higher resolutions require exponentially more processing
2. **Quality Settings**: Higher quality requires more complex encoding
3. **Parallelization**: Multi-core systems benefit from parallel encoding/decoding
4. **Hardware Acceleration**: Metal/GPU acceleration can provide 2-10x speedup (Apple platforms)
5. **I/O Performance**: SSD vs HDD can impact file operations by 5-100x
6. **Memory**: Caching requires sufficient RAM (typical: 256MB-2GB for 1080p)

## Encoding Optimization

### Parallel Frame Encoding

Enable parallel encoding for multi-frame sequences:

```swift
let config = MJ2CreationConfiguration.from(
    frameRate: 30.0,
    profile: .simple
)

var customConfig = MJ2CreationConfiguration(
    profile: config.profile,
    timescale: config.timescale,
    encodingConfiguration: config.encodingConfiguration,
    metadata: config.metadata,
    audioTrack: config.audioTrack,
    use64BitOffsets: config.use64BitOffsets,
    maxFrameBufferCount: config.maxFrameBufferCount,
    enableParallelEncoding: true,  // Enable parallel encoding
    parallelEncodingCount: 4        // Use 4 threads
)

let creator = MJ2Creator(configuration: customConfig)
try await creator.create(from: frames, outputURL: outputURL)
```

### Optimal Parallel Thread Count

The optimal thread count depends on your hardware:

```swift
// Auto-detect optimal thread count
let processorCount = ProcessInfo.processInfo.processorCount
let optimalThreads = min(processorCount, 8)  // Cap at 8 for diminishing returns

// Or use specific counts:
// - Mobile devices: 2-4 threads
// - Desktop systems: 4-8 threads
// - Workstations: 8-16 threads
```

### Quality vs Performance Tradeoffs

Different quality settings impact encoding speed:

```swift
// Fast encoding (lower quality, ~3x faster)
let fastConfig = MJ2CreationConfiguration.from(
    frameRate: 30.0,
    profile: .simple,
    quality: 0.7,    // Lower quality
    lossless: false
)

// Balanced encoding (good quality, moderate speed)
let balancedConfig = MJ2CreationConfiguration.from(
    frameRate: 30.0,
    profile: .general,
    quality: 0.9,    // High quality
    lossless: false
)

// High quality encoding (best quality, slowest)
let highQualityConfig = MJ2CreationConfiguration.from(
    frameRate: 30.0,
    profile: .cinema,
    quality: 1.0,    // Maximum quality
    lossless: true   // Lossless compression
)
```

### Memory-Efficient Encoding

Limit frame buffering to reduce memory usage:

```swift
var config = MJ2CreationConfiguration.from(frameRate: 30.0)
config = MJ2CreationConfiguration(
    profile: config.profile,
    timescale: config.timescale,
    encodingConfiguration: config.encodingConfiguration,
    metadata: config.metadata,
    audioTrack: config.audioTrack,
    use64BitOffsets: config.use64BitOffsets,
    maxFrameBufferCount: 5,  // Limit buffered frames
    enableParallelEncoding: config.enableParallelEncoding,
    parallelEncodingCount: config.parallelEncodingCount
)
```

## Decoding Optimization

### Parallel Frame Decoding

Enable parallel decoding for extracting multiple frames:

```swift
var options = MJ2ExtractionOptions()
options.decodeFrames = true
options.parallel = true  // Enable parallel decoding

let extractor = MJ2Extractor()
let frames = try await extractor.extract(
    from: fileURL,
    options: options
)
```

### Selective Frame Extraction

Extract only needed frames to improve performance:

```swift
// Extract only sync frames (key frames)
options.strategy = .syncOnly

// Extract specific range
options.strategy = .range(start: 10, end: 50)

// Extract every Nth frame
options.strategy = .skip(interval: 5)

// Extract single frame
options.strategy = .single(index: 25)
```

### Decode Without Frame Conversion

Skip decoding to J2KImage for faster metadata extraction:

```swift
var options = MJ2ExtractionOptions()
options.decodeFrames = false  // Skip image decoding
options.outputStrategy = .files(
    directory: outputDir,
    naming: { index in "frame_\(index).j2k" }
)
```

## Playback Optimization

### Frame Caching

Configure intelligent frame caching for smooth playback:

```swift
let playbackConfig = MJ2PlaybackConfiguration(
    maxCacheSize: 60,           // Cache up to 60 frames (2 seconds @ 30fps)
    prefetchCount: 10,           // Prefetch 10 frames ahead
    memoryLimit: 512 * 1024 * 1024,  // 512MB cache limit
    enablePredictivePrefetch: true,  // Enable smart prefetching
    timingTolerance: 16.67           // Tolerance in ms (~60fps)
)

let player = MJ2Player(configuration: playbackConfig)
```

### Cache Size Guidelines

Recommended cache sizes based on content:

| Resolution | Frame Size | Recommended Cache | Memory Usage |
|------------|------------|-------------------|--------------|
| 640×480 | ~100KB | 30-60 frames | 3-6 MB |
| 1280×720 | ~300KB | 30-60 frames | 9-18 MB |
| 1920×1080 | ~800KB | 20-40 frames | 16-32 MB |
| 3840×2160 | ~3MB | 10-20 frames | 30-60 MB |

### Predictive Prefetching

The player automatically prefetches frames based on playback direction:

```swift
// Prefetching adapts to playback mode
try await player.play()  // Prefetches forward

try await player.setPlaybackMode(.reverse)  // Prefetches backward

try await player.setPlaybackSpeed(2.0)  // Increases prefetch distance
```

### Memory Pressure Handling

The player automatically manages memory under pressure:

1. **LRU Eviction**: Least recently used frames are evicted first
2. **Memory Limits**: Respects configured memory limits
3. **Dynamic Adjustment**: Reduces cache size under memory pressure

```swift
// Monitor memory usage
let stats = await player.getStatistics()
print("Memory usage: \(stats.memoryUsage / 1_000_000) MB")
print("Cache hit rate: \(stats.cacheHitRate * 100)%")
```

## I/O Optimization

### Asynchronous File Operations

All file operations use async I/O for better performance:

```swift
// Non-blocking file creation
let creator = MJ2Creator(configuration: config)
try await creator.create(from: frames, outputURL: outputURL)

// Non-blocking file loading
let player = MJ2Player(configuration: playbackConfig)
try await player.load(from: fileURL)

// Non-blocking frame extraction
let extractor = MJ2Extractor()
try await extractor.extract(from: fileURL, options: options)
```

### Buffered Reading

For optimal read performance:

```swift
// Load entire file for random access (small to medium files)
let data = try Data(contentsOf: fileURL)
let player = MJ2Player(configuration: config)
try await player.load(from: data)

// For large files, use direct file access
try await player.load(from: fileURL)  // Streams from disk
```

### Progressive Loading

For large files or streaming scenarios:

```swift
// Extract frames progressively
var processedFrames = 0

try await extractor.extract(from: fileURL, options: options) { current, total in
    processedFrames = current
    print("Progress: \(current)/\(total)")
}
```

## Memory Management

### Memory Usage Patterns

Different operations have different memory profiles:

#### Encoding Memory Usage

```
Base Memory: ~50MB
Per-frame overhead: resolution × components × 4 bytes × buffer count

Example (1920×1080 RGB, 10 frame buffer):
50MB + (1920 × 1080 × 3 × 4 × 10) / 1024 / 1024 ≈ 285MB
```

#### Playback Memory Usage

```
Base Memory: ~20MB
Cache memory: frame_size × cache_count

Example (1920×1080, 30 frame cache, 800KB per frame):
20MB + (800KB × 30) / 1024 ≈ 43MB
```

### Memory Optimization Techniques

1. **Reduce Cache Size**: Lower `maxCacheSize` in playback configuration
2. **Limit Parallel Operations**: Reduce `parallelEncodingCount`
3. **Process in Batches**: Split large frame sequences into smaller batches
4. **Stream from Disk**: Use file-based operations instead of in-memory

```swift
// Example: Memory-efficient batch processing
let batchSize = 10
for batchStart in stride(from: 0, to: frames.count, by: batchSize) {
    let batchEnd = min(batchStart + batchSize, frames.count)
    let batch = Array(frames[batchStart..<batchEnd])
    
    try await processBatch(batch)
    
    // Allow memory to be released between batches
    try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s
}
```

## Hardware Requirements

### Minimum Requirements

- **CPU**: Dual-core processor (2+ GHz)
- **RAM**: 4GB
- **Storage**: SSD recommended for optimal I/O
- **OS**: macOS 12+, iOS 15+, Linux (Ubuntu 20.04+)

### Recommended Requirements

- **CPU**: Quad-core processor (3+ GHz) or Apple Silicon
- **RAM**: 8GB+ (16GB for 4K content)
- **Storage**: NVMe SSD
- **GPU**: Metal-capable GPU (Apple platforms) for hardware acceleration
- **OS**: Latest stable OS version

### Performance by Platform

| Platform | Encoding | Decoding | Hardware Accel |
|----------|----------|----------|----------------|
| Apple Silicon (M1+) | Excellent | Excellent | Yes (VideoToolbox) |
| macOS Intel | Good | Good | Limited |
| iOS/iPadOS | Good | Excellent | Yes (VideoToolbox) |
| Linux (x86_64) | Good | Good | No |
| Linux (ARM64) | Fair | Good | No |

## Benchmarking

### Running Performance Tests

J2KSwift includes comprehensive performance tests:

```bash
# Run all performance tests
swift test --filter MJ2PerformanceTests

# Run specific performance test
swift test --filter MJ2PerformanceTests.testEncodingThroughput
swift test --filter MJ2PerformanceTests.testDecodingThroughput
swift test --filter MJ2PerformanceTests.testParallelEncodingSpeedup
```

### Interpreting Results

Performance test output includes:

```
Encoding throughput: 1.18 fps
Total time: 4.24 seconds
Average time per frame: 848.07 ms
```

Key metrics:

- **Throughput (fps)**: Frames processed per second
- **Total time**: End-to-end processing time
- **Average time per frame**: Consistent frame processing time indicates stable performance

### Custom Benchmarks

Create custom benchmarks for your use case:

```swift
let startTime = Date()

// Your operation here
try await creator.create(from: frames, outputURL: outputURL)

let elapsed = Date().timeIntervalSince(startTime)
let fps = Double(frames.count) / elapsed

print("Processing rate: \(fps) fps")
print("Time per frame: \(elapsed / Double(frames.count) * 1000) ms")
```

## Best Practices

### For Real-Time Encoding

1. **Enable Parallel Encoding**: Always use parallel encoding for multi-core systems
2. **Adjust Quality Settings**: Lower quality (0.7-0.8) for real-time requirements
3. **Use Simple Profile**: Simpler profiles encode faster
4. **Limit Resolution**: Consider downscaling for real-time needs
5. **Pre-allocate Buffers**: Reuse buffers where possible

### For High-Quality Offline Encoding

1. **Use Cinema Profile**: Best quality and features
2. **Enable Lossless**: When quality is critical
3. **Maximize Parallel Threads**: Use all available cores
4. **Increase Buffer Count**: Allow more frames in flight
5. **Use 64-bit Offsets**: For files >4GB

### For Smooth Playback

1. **Adequate Cache Size**: Cache at least 1-2 seconds of content
2. **Enable Predictive Prefetch**: Improves seek performance
3. **Monitor Cache Hit Rate**: >80% hit rate indicates good caching
4. **Set Memory Limits**: Prevent excessive memory usage
5. **Use SSD Storage**: Faster disk access improves cache miss handling

### For Memory-Constrained Environments

1. **Reduce Cache Size**: Lower frame cache count
2. **Sequential Processing**: Disable parallel operations if needed
3. **Batch Processing**: Process in smaller chunks
4. **Stream from Disk**: Avoid loading entire files
5. **Monitor Memory Usage**: Use performance statistics

## Troubleshooting

### Poor Encoding Performance

**Symptoms**: Encoding much slower than expected

**Solutions**:
1. Verify parallel encoding is enabled
2. Check CPU usage (should be near 100% when encoding)
3. Reduce quality settings if acceptable
4. Ensure adequate free RAM
5. Check for thermal throttling on mobile devices

### Playback Stuttering

**Symptoms**: Dropped frames, inconsistent playback

**Solutions**:
1. Increase cache size
2. Enable predictive prefetching
3. Check cache hit rate (aim for >80%)
4. Verify I/O performance (use SSD)
5. Reduce playback speed temporarily
6. Pre-decode frames in background

### High Memory Usage

**Symptoms**: Excessive RAM consumption

**Solutions**:
1. Reduce cache size
2. Lower parallel encoding count
3. Process in smaller batches
4. Set explicit memory limits
5. Monitor and profile memory usage

### Slow I/O Operations

**Symptoms**: File operations taking longer than expected

**Solutions**:
1. Use SSD instead of HDD
2. Reduce file size with higher compression
3. Use asynchronous operations
4. Batch multiple small operations
5. Consider in-memory processing for small files

## Performance Comparison with H.264/H.265

MJ2 (Motion JPEG 2000) has different performance characteristics compared to H.264/H.265:

### Advantages of MJ2

- **Frame-Level Access**: No GOP dependencies, instant frame access
- **Intra-frame Compression**: Better for editing workflows
- **Scalability**: ROI and resolution scalability
- **No Blocking Artifacts**: Wavelet-based compression
- **Parallel Processing**: Each frame can be processed independently

### Disadvantages of MJ2

- **Compression Efficiency**: Typically 2-5x larger files than H.264/H.265
- **Encoding Speed**: Generally slower than hardware-accelerated H.264
- **Decoder Support**: Less widespread than H.264/H.265

### Use Cases

**Choose MJ2 when**:
- Frame-accurate editing is required
- Random access to any frame is needed
- High quality at all resolutions is important
- Archival with future scalability is desired

**Choose H.264/H.265 when**:
- File size is critical
- Streaming over networks
- Playback-only (no editing)
- Maximum compatibility is required

## Conclusion

Optimizing MJ2 performance requires balancing quality, speed, and resource usage. The key strategies are:

1. **Enable Parallelization**: Use all available CPU cores
2. **Configure Caching**: Cache enough frames for smooth playback
3. **Optimize I/O**: Use SSDs and async operations
4. **Monitor Performance**: Use built-in statistics and benchmarks
5. **Match Settings to Use Case**: Real-time vs offline, quality vs speed

For most applications, the default configurations provide good balance. Adjust based on your specific requirements using the guidance in this document.

## Additional Resources

- **MJ2 Cross-Platform Guide**: See `MJ2_CROSS_PLATFORM.md` for platform-specific optimizations
- **VideoToolbox Integration**: See `MJ2_VIDEOTOOLBOX.md` for hardware acceleration on Apple platforms
- **Performance Tests**: See `Tests/J2KCodecTests/MJ2PerformanceTests.swift` for benchmarking examples
- **Motion JPEG 2000 Specification**: See `MOTION_JPEG2000.md` for format details
