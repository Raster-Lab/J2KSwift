# Complete Motion JPEG 2000 Guide

## Table of Contents

1. [Overview](#overview)
2. [Getting Started](#getting-started)
3. [Creating MJ2 Files](#creating-mj2-files)
4. [Extracting Frames](#extracting-frames)
5. [Playback](#playback)
6. [File Format Details](#file-format-details)
7. [Profiles](#profiles)
8. [Cross-Platform Support](#cross-platform-support)
9. [Performance](#performance)
10. [API Reference Summary](#api-reference-summary)
11. [Known Limitations](#known-limitations)
12. [Migration from v1.7.0](#migration-from-v170)

## Overview

### What is Motion JPEG 2000?

Motion JPEG 2000 (MJ2) is a video format defined by **ISO/IEC 15444-3** that extends JPEG 2000 still image compression to motion sequences. It wraps individually compressed JPEG 2000 frames in an ISO base media file format (ISO/IEC 14496-12) container, providing high-quality video with frame-level independence.

### How MJ2 Differs from H.264/H.265

| Characteristic | MJ2 | H.264/H.265 |
|----------------|-----|-------------|
| Frame independence | Each frame compressed independently | Inter-frame prediction (GOP structure) |
| Random access | Instant access to any frame | Must seek to nearest keyframe |
| Visual quality | No blocking artifacts (wavelet-based) | Potential blocking at low bitrates |
| Compression ratio | Lower (2–5× larger files) | Higher (inter-frame redundancy) |
| Editing | Frame-accurate, no re-encoding needed | Re-encoding required for edits |
| Latency | Single-frame latency | Multi-frame GOP latency |
| Scalability | Resolution and quality scalability | Limited scalability |

### Use Cases

- **Digital Cinema (DCI)**: MJ2 is the basis of Digital Cinema Package (DCP) encoding, where lossless or visually lossless quality is required.
- **Medical Imaging**: Frame independence and lossless support make MJ2 ideal for medical video sequences (DICOM).
- **Archival**: Wavelet-based compression preserves quality over generations; scalability enables future re-use at higher resolutions.
- **Broadcast**: Low-latency intra-frame coding suits live broadcast and contribution workflows.

### J2KSwift Implementation Status

J2KSwift provides comprehensive MJ2 support through the following actors and types:

- ✅ MJ2 file creation with parallel encoding
- ✅ Frame extraction with multiple strategies
- ✅ Real-time playback with LRU caching
- ✅ File format reading and validation
- ✅ Simple, General, Broadcast, and Cinema profiles
- ✅ Cross-platform software encoding
- ✅ VideoToolbox hardware acceleration (Apple platforms)

## Getting Started

### Required Modules

| Module | Purpose |
|--------|---------|
| `J2KFileFormat` | MJ2 file reading, writing, and format detection |
| `J2KCore` | Core image types (`J2KImage`, `J2KError`) |
| `J2KCodec` | JPEG 2000 encoding and decoding |

### Package.swift Dependencies

Add J2KSwift to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/J2KSwift.git", from: "1.8.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "J2KFileFormat", package: "J2KSwift"),
            .product(name: "J2KCore", package: "J2KSwift"),
            .product(name: "J2KCodec", package: "J2KSwift"),
        ]
    )
]
```

### Basic Imports

```swift
import J2KCore
import J2KCodec
import J2KFileFormat
```

## Creating MJ2 Files

### Using MJ2Creator

`MJ2Creator` is an `actor` that produces MJ2 files from a sequence of `J2KImage` frames. All operations are async and thread-safe.

```swift
let config = MJ2CreationConfiguration.from(
    frameRate: 24.0,
    profile: .cinema
)

let creator = MJ2Creator(configuration: config)
let data = try await creator.create(from: frames)
```

### MJ2CreationConfiguration

`MJ2CreationConfiguration` controls every aspect of file creation:

```swift
let config = MJ2CreationConfiguration(
    profile: .general,
    timescale: MJ2TimescaleConfiguration.from(frameRate: 30.0),
    encodingConfiguration: encodingConfig,
    metadata: MJ2Metadata(
        title: "My Video",
        author: "J2KSwift",
        copyright: "© 2026"
    ),
    audioTrack: nil,
    use64BitOffsets: false,
    maxFrameBufferCount: 10,
    enableParallelEncoding: true,
    parallelEncodingCount: 4
)
```

#### Profile Presets

| Profile | Constant | Description |
|---------|----------|-------------|
| Simple | `.simple` | Constrained feature set for basic playback |
| General | `.general` | Full JPEG 2000 features, no constraints |
| Broadcast | `.broadcast` | Optimized for live broadcast workflows |
| Cinema | `.cinema` | DCI-compliant digital cinema encoding |

Use the convenience factory for quick setup:

```swift
// Simple profile at 30 fps
let simple = MJ2CreationConfiguration.from(frameRate: 30.0, profile: .simple)

// Cinema profile at 24 fps with lossless encoding
let cinema = MJ2CreationConfiguration.from(
    frameRate: 24.0,
    profile: .cinema,
    quality: 1.0,
    lossless: true
)
```

### Frame Rate Configuration

`MJ2TimescaleConfiguration` maps frame rates to ISO base media format timescales:

```swift
// Standard frame rates
let config24 = MJ2TimescaleConfiguration.from(frameRate: 24.0)
// timescale = 24000, frameDuration = 1000

let config30 = MJ2TimescaleConfiguration.from(frameRate: 30.0)
// timescale = 30000, frameDuration = 1000

let config60 = MJ2TimescaleConfiguration.from(frameRate: 60.0)
// timescale = 60000, frameDuration = 1000
```

### Creating from an Image Array

```swift
import J2KCore
import J2KCodec
import J2KFileFormat

let frames: [J2KImage] = loadFrames()

let config = MJ2CreationConfiguration.from(
    frameRate: 24.0,
    profile: .general
)
let creator = MJ2Creator(configuration: config)

// Create to Data
let mj2Data = try await creator.create(from: frames)

// Or create to a file URL
try await creator.create(from: frames, outputURL: outputURL)
```

### Creating from a Repeated Image

Generate a test or still-frame video by repeating a single image:

```swift
let stillImage: J2KImage = loadImage()

let creator = MJ2Creator(
    configuration: .from(frameRate: 30.0, profile: .simple)
)

// Create a 5-second video from one image (150 frames at 30 fps)
let data = try await creator.createRepeated(
    image: stillImage,
    frameCount: 150
)
```

### Progress Tracking

Monitor creation progress with `MJ2ProgressUpdate`:

```swift
let creator = MJ2Creator(configuration: config)

let data = try await creator.create(from: frames) { progress in
    // progress.frameNumber   – current frame (1-based)
    // progress.totalFrames   – total frame count
    // progress.estimatedSize – estimated output size in bytes
    print("Frame \(progress.frameNumber)/\(progress.totalFrames)")
}
```

### Lossless vs Lossy Encoding

```swift
// Lossless encoding (larger files, perfect reconstruction)
let lossless = MJ2CreationConfiguration.from(
    frameRate: 24.0,
    profile: .cinema,
    quality: 1.0,
    lossless: true
)

// Lossy encoding (smaller files, visually transparent quality)
let lossy = MJ2CreationConfiguration.from(
    frameRate: 24.0,
    profile: .general,
    quality: 0.85,
    lossless: false
)
```

## Extracting Frames

### Using MJ2Extractor

`MJ2Extractor` is an `actor` that reads MJ2 files and extracts frames according to a configurable strategy.

```swift
let extractor = MJ2Extractor()
let options = MJ2ExtractionOptions()

let sequence = try await extractor.extract(from: fileURL, options: options)
for frame in sequence.frames {
    print("Frame \(frame.metadata.index): \(frame.metadata.size) bytes")
}
```

### Extraction Strategies

Set `options.strategy` to control which frames are extracted:

| Strategy | Description |
|----------|-------------|
| `.all` | Extract every frame in the track |
| `.syncOnly` | Extract only sync (key) frames |
| `.range(start:end:)` | Extract a contiguous range by index |
| `.timestampRange(start:end:)` | Extract frames within a time interval |
| `.skip(interval:)` | Extract every *N*-th frame |
| `.single(index:)` | Extract a single frame by index |

```swift
// Extract frames 10 through 50
var options = MJ2ExtractionOptions()
options.strategy = .range(start: 10, end: 50)

// Extract every 5th frame (thumbnail generation)
options.strategy = .skip(interval: 5)

// Extract a single poster frame
options.strategy = .single(index: 0)

// Extract only sync frames
options.strategy = .syncOnly
```

### Output Strategies

Control where extracted frames are stored:

```swift
// Keep frames in memory (default)
options.outputStrategy = .memory

// Write raw codestream data to individual files
options.outputStrategy = .files(
    directory: outputDir,
    naming: { index in "frame_\(String(format: "%05d", index)).j2k" }
)

// Write decoded images as an image sequence
options.outputStrategy = .imageSequence(
    directory: outputDir,
    naming: { index in "frame_\(String(format: "%05d", index)).png" }
)
```

### Parallel Extraction

Enable parallel decoding on multi-core systems:

```swift
var options = MJ2ExtractionOptions()
options.decodeFrames = true
options.parallel = true

let sequence = try await extractor.extract(from: fileURL, options: options)
// Frames are decoded in parallel and returned in order
```

### Full Extraction Example

```swift
let extractor = MJ2Extractor()

var options = MJ2ExtractionOptions()
options.strategy = .range(start: 0, end: 99)
options.decodeFrames = true
options.parallel = true
options.outputStrategy = .memory

let sequence = try await extractor.extract(from: fileURL, options: options)
print("Extracted \(sequence.frames.count) frames")

for frame in sequence.frames {
    if let image = frame.image {
        print("Frame \(frame.metadata.index): \(image.width)×\(image.height)")
    }
}
```

## Playback

### Using MJ2Player

`MJ2Player` is an `actor` that provides real-time playback with intelligent frame caching, variable speed, and seeking.

```swift
let playbackConfig = MJ2PlaybackConfiguration(
    maxCacheSize: 60,
    prefetchCount: 10,
    memoryLimit: 256 * 1024 * 1024,
    enablePredictivePrefetch: true,
    timingTolerance: 16.67
)

let player = MJ2Player(configuration: playbackConfig)
```

### Loading Content

```swift
// Load from a file URL
try await player.load(from: fileURL)

// Load from in-memory data
try await player.load(from: mj2Data)
```

### Playback Modes

Control playback direction with `MJ2PlaybackMode`:

```swift
try await player.setPlaybackMode(.forward)      // Normal playback
try await player.setPlaybackMode(.reverse)       // Reverse playback
try await player.setPlaybackMode(.stepForward)   // Step one frame forward
try await player.setPlaybackMode(.stepBackward)  // Step one frame backward
```

### Loop Modes

Set looping behavior with `MJ2LoopMode`:

```swift
try await player.setLoopMode(.none)      // Stop at end
try await player.setLoopMode(.loop)      // Restart from beginning
try await player.setLoopMode(.pingPong)  // Alternate forward/reverse
```

### Speed Control

Adjust playback speed from 0.1× to 10×:

```swift
try await player.setPlaybackSpeed(0.5)   // Half speed
try await player.setPlaybackSpeed(1.0)   // Normal speed
try await player.setPlaybackSpeed(2.0)   // Double speed

try await player.play()
try await player.pause()
try await player.stop()
```

### Frame Seeking

Seek to a specific frame by index or timestamp:

```swift
// Seek by frame index
try await player.seek(toFrame: 42)

// Seek by timestamp (seconds)
try await player.seek(toTimestamp: 1.75)
```

### Frame Caching

The player uses an **LRU (Least Recently Used)** eviction strategy. Frames are cached after decoding and evicted when the cache exceeds `maxCacheSize` or `memoryLimit`:

```swift
let config = MJ2PlaybackConfiguration(
    maxCacheSize: 120,                    // Up to 120 frames
    prefetchCount: 15,                    // Decode 15 frames ahead
    memoryLimit: 512 * 1024 * 1024,       // 512 MB hard limit
    enablePredictivePrefetch: true,       // Adapts to playback direction
    timingTolerance: 16.67               // ~60 fps tolerance (ms)
)
```

### Playback Statistics

Monitor performance in real time with `MJ2PlaybackStatistics`:

```swift
let stats = await player.getStatistics()
print("Frames decoded: \(stats.framesDecoded)")
print("Frames dropped: \(stats.framesDropped)")
print("Avg decode time: \(stats.averageDecodeTime) ms")
print("Cache hit rate: \(stats.cacheHitRate * 100)%")
print("Memory usage: \(stats.memoryUsage / 1_048_576) MB")
```

## File Format Details

### MJ2 File Structure

An MJ2 file follows the ISO base media file format (ISO/IEC 14496-12) box hierarchy:

```
MJ2 File
├── ftyp (File Type Box)         – brand: "mjp2" or "mj2s"
├── mdat (Media Data Box)        – raw JPEG 2000 codestreams
└── moov (Movie Box)
    ├── mvhd (Movie Header Box)  – timescale, duration, creation time
    └── trak (Track Box)         – one per video/audio track
        ├── tkhd (Track Header Box) – track ID, dimensions, flags
        └── mdia (Media Box)
            ├── mdhd (Media Header Box) – media timescale, language
            ├── hdlr (Handler Box)      – "vide" for video tracks
            └── minf (Media Information Box)
                └── stbl (Sample Table Box)
                    ├── stsz (Sample Size Box)        – per-frame sizes
                    ├── stco / co64 (Chunk Offset Box) – frame offsets
                    ├── stsc (Sample-to-Chunk Box)     – chunk mapping
                    ├── stts (Time-to-Sample Box)      – frame durations
                    └── stss (Sync Sample Box)         – key frame indices
```

### Reading MJ2 Files

Use `MJ2FileReader` to parse file metadata and structure:

```swift
let reader = MJ2FileReader()
let fileInfo = try await reader.read(from: fileURL)

print("Format: \(fileInfo.format)")
print("Duration: \(fileInfo.duration) seconds")
print("Timescale: \(fileInfo.timescale)")
print("Tracks: \(fileInfo.tracks.count)")

for track in fileInfo.tracks {
    print("  Track \(track.trackID): \(track.dimensions.width)×\(track.dimensions.height)")
    print("  Samples: \(track.sampleCount)")
    print("  Video: \(track.isVideo)")
}
```

### Format Detection

Use `MJ2FormatDetector` to check whether a file is a valid MJ2 container:

```swift
let detector = MJ2FormatDetector()

if detector.isMJ2File(data: fileData) {
    let format = detector.detectFormat(data: fileData)
    print("Format: \(format.brandIdentifier)")   // "mjp2" or "mj2s"
    print("Extension: \(format.fileExtension)")   // "mj2"
    print("MIME: \(format.mimeType)")             // "video/mj2"
}
```

### MJ2FileInfo and MJ2TrackInfo

`MJ2FileInfo` provides top-level metadata; each `MJ2TrackInfo` describes one track:

| Field (MJ2FileInfo) | Description |
|----------------------|-------------|
| `format` | Detected `MJ2Format` |
| `timescale` | Movie-level timescale |
| `duration` | Total duration in seconds |
| `tracks` | Array of `MJ2TrackInfo` |

| Field (MJ2TrackInfo) | Description |
|-----------------------|-------------|
| `trackID` | Unique track identifier |
| `dimensions` | Width × height |
| `sampleCount` | Number of frames/samples |
| `language` | ISO 639-2/T language code |
| `isVideo` | Whether the track is a video track |

## Profiles

### Simple Profile (`mj2s`)

The Simple Profile restricts JPEG 2000 features for maximum interoperability:

- **Brand**: `mj2s`
- **Constraints**: Single tile, restricted marker segments, limited decomposition levels
- **Use cases**: Portable devices, simple playback applications, embedded systems

```swift
let config = MJ2CreationConfiguration.from(
    frameRate: 30.0,
    profile: .simple
)
```

### General Profile (`mjp2`)

The General Profile imposes no restrictions on JPEG 2000 features:

- **Brand**: `mjp2`
- **Constraints**: None — full JPEG 2000 Part 1 and Part 2 features available
- **Use cases**: Professional editing, archival, medical imaging

```swift
let config = MJ2CreationConfiguration.from(
    frameRate: 24.0,
    profile: .general
)
```

### Broadcast Profile

Tuned for live broadcast and contribution workflows:

- **Characteristics**: Low latency, constant bitrate, fixed frame rate
- **Use cases**: Live event production, news contribution, studio feeds

```swift
let config = MJ2CreationConfiguration.from(
    frameRate: 30.0,
    profile: .broadcast
)
```

### Cinema Profile

Designed for DCI (Digital Cinema Initiatives) compliance:

- **Characteristics**: High bitrate, 2K/4K resolution, 24/48 fps, visually lossless or lossless
- **Use cases**: Feature films, digital cinema packages (DCP), post-production mastering

```swift
let config = MJ2CreationConfiguration.from(
    frameRate: 24.0,
    profile: .cinema,
    quality: 1.0,
    lossless: true
)
```

## Cross-Platform Support

### Apple Platforms

On macOS, iOS, tvOS, and visionOS, J2KSwift leverages hardware acceleration:

- **VideoToolbox**: Hardware-accelerated transcoding between MJ2 and H.264/H.265 (see `MJ2_VIDEOTOOLBOX.md`)
- **Metal**: GPU-accelerated color conversion and preprocessing
- **Performance**: 60–120+ fps encoding at 1080p on Apple Silicon

### Linux

- Software-only JPEG 2000 encoding and decoding
- FFmpeg integration for additional codec support
- ARM64 and x86-64 architectures supported
- Performance: 10–30 fps at 1080p with FFmpeg, 1–5 fps with basic software encoder

### Windows

- Software-only encoding and decoding
- FFmpeg integration available
- Performance characteristics similar to Linux

### Platform Detection

Use `MJ2PlatformCapabilities` to query runtime capabilities:

```swift
let platform = MJ2PlatformCapabilities.currentPlatform
print("Platform: \(platform)")
print("Architecture: \(MJ2PlatformCapabilities.architecture)")
print("VideoToolbox: \(MJ2PlatformCapabilities.hasVideoToolbox)")
print("Metal: \(MJ2PlatformCapabilities.hasMetal)")
print("ARM64: \(MJ2PlatformCapabilities.isARM64)")
```

For detailed cross-platform guidance, see `MJ2_CROSS_PLATFORM.md`.

## Performance

### Encoding Performance

| Configuration | 640×480 | 1920×1080 | 3840×2160 |
|---------------|---------|-----------|-----------|
| Sequential | 1–5 fps | 0.2–2 fps | < 1 fps |
| Parallel (4 threads) | 3–15 fps | 1–8 fps | 0.5–3 fps |
| VideoToolbox (Apple Silicon) | 120+ fps | 60+ fps | 30+ fps |

### Decoding Throughput

| Configuration | 640×480 | 1920×1080 |
|---------------|---------|-----------|
| Sequential | 5–20 fps | 2–10 fps |
| Parallel | 15–60 fps | 8–30 fps |
| Cached playback | 30+ fps | 30+ fps |

### Memory Management

Configure cache settings to balance performance and memory:

```swift
let config = MJ2PlaybackConfiguration(
    maxCacheSize: 30,                    // Fewer frames for constrained devices
    prefetchCount: 5,
    memoryLimit: 128 * 1024 * 1024,      // 128 MB limit
    enablePredictivePrefetch: true,
    timingTolerance: 33.33               // ~30 fps
)
```

**Guidelines by resolution:**

| Resolution | Recommended Cache | Memory Usage |
|------------|-------------------|--------------|
| 640×480 | 30–60 frames | 3–6 MB |
| 1280×720 | 30–60 frames | 9–18 MB |
| 1920×1080 | 20–40 frames | 16–32 MB |
| 3840×2160 | 10–20 frames | 30–60 MB |

### Best Practices

**Real-time workflows:**
1. Enable parallel encoding with `enableParallelEncoding: true`
2. Use the Simple profile for fastest encoding
3. Lower quality (0.7–0.8) to meet frame-rate targets
4. Monitor `MJ2PlaybackStatistics.cacheHitRate` — aim for > 80%

**Offline / archival workflows:**
1. Use the Cinema profile with lossless encoding
2. Maximize `parallelEncodingCount` to use all CPU cores
3. Enable `use64BitOffsets` for files larger than 4 GB
4. Increase `maxFrameBufferCount` to keep more frames in flight

For detailed benchmarking guidance, see `MJ2_PERFORMANCE.md`.

## API Reference Summary

### Core Actors

| Type | Purpose |
|------|---------|
| `MJ2Creator` | Creates MJ2 files from image sequences |
| `MJ2Extractor` | Extracts frames from MJ2 files |
| `MJ2Player` | Real-time playback with caching and seeking |
| `MJ2FileReader` | Parses MJ2 file structure and metadata |
| `MJ2SampleTableBuilder` | Generates ISO base media format sample tables |

### Configuration Types

| Type | Purpose |
|------|---------|
| `MJ2CreationConfiguration` | File creation settings (profile, timescale, parallel encoding) |
| `MJ2TimescaleConfiguration` | Frame rate to timescale mapping |
| `MJ2PlaybackConfiguration` | Cache size, prefetch, memory limits |
| `MJ2ExtractionOptions` | Extraction strategy, output, parallelism |
| `MJ2Metadata` | Title, author, copyright, description |

### Enums

| Type | Cases |
|------|-------|
| `MJ2Profile` | `.simple`, `.general`, `.broadcast`, `.cinema` |
| `MJ2ExtractionStrategy` | `.all`, `.syncOnly`, `.range`, `.timestampRange`, `.skip`, `.single` |
| `MJ2OutputStrategy` | `.memory`, `.files`, `.imageSequence` |
| `MJ2PlaybackMode` | `.forward`, `.reverse`, `.stepForward`, `.stepBackward` |
| `MJ2LoopMode` | `.none`, `.loop`, `.pingPong` |
| `MJ2PlaybackState` | `.stopped`, `.playing`, `.paused`, `.seeking` |
| `MJ2Format` | `.mj2s`, `.mj2` |

### Data Types

| Type | Purpose |
|------|---------|
| `MJ2FileInfo` | Top-level file metadata (format, duration, tracks) |
| `MJ2TrackInfo` | Per-track metadata (dimensions, sample count, language) |
| `MJ2FrameSequence` | Container for extracted frames |
| `MJ2FrameMetadata` | Per-frame index, size, offset, timestamp, sync flag |
| `MJ2PlaybackStatistics` | Decoded/dropped frames, decode time, cache hit rate |
| `MJ2ProgressUpdate` | Creation progress (frame number, total, estimated size) |
| `MJ2FormatDetector` | MJ2 file identification and format detection |

### Error Types

| Type | Cases |
|------|-------|
| `MJ2CreationError` | `noFrames`, `inconsistentDimensions`, `inconsistentComponents`, `cancelled`, `encodingFailed` |
| `MJ2ExtractionError` | `invalidFile`, `noVideoTracks`, `trackNotFound`, `invalidFrameRange`, `extractionFailed`, `cancelled` |
| `MJ2PlaybackError` | `invalidFile`, `noVideoTracks`, `notInitialized`, `seekFailed`, `decodeFailed`, `stopped` |

## Known Limitations

### Video Track Detection

In round-trip scenarios (create → read → extract), video track detection depends on the presence of a valid handler box (`hdlr`) with type `"vide"`. Files produced by third-party tools that omit or incorrectly set the handler type may not be recognized as containing video tracks.

### Platform-Specific Limitations

- **Linux / Windows**: No VideoToolbox or Metal acceleration; software encoding only.
- **Older Intel Macs**: H.265 hardware encoding may not be available; H.264 is recommended.
- **iOS**: Background encoding is subject to system resource limits and may be throttled.

### Performance Characteristics

- Pure-Swift JPEG 2000 encoding is CPU-intensive; real-time encoding at 1080p or above typically requires parallel encoding on modern multi-core hardware.
- Lossless encoding produces significantly larger files and is slower than lossy encoding.
- Cache hit rate below 80% during playback may result in dropped frames; increase `maxCacheSize` or `prefetchCount` to compensate.

## Migration from v1.7.0

### New MJ2 APIs in v1.8.0

Version 1.8.0 introduces the complete Motion JPEG 2000 module. The following types are new:

- `MJ2Creator`, `MJ2Extractor`, `MJ2Player`, `MJ2FileReader`
- `MJ2CreationConfiguration`, `MJ2TimescaleConfiguration`, `MJ2PlaybackConfiguration`
- `MJ2ExtractionOptions`, `MJ2ExtractionStrategy`, `MJ2OutputStrategy`
- `MJ2Profile`, `MJ2Format`, `MJ2FormatDetector`
- `MJ2PlaybackMode`, `MJ2LoopMode`, `MJ2PlaybackState`, `MJ2PlaybackStatistics`
- `MJ2FrameSequence`, `MJ2FrameMetadata`, `MJ2ProgressUpdate`
- `MJ2FileInfo`, `MJ2TrackInfo`, `MJ2Metadata`
- `MJ2CreationError`, `MJ2ExtractionError`, `MJ2PlaybackError`
- `MJ2PlatformCapabilities`, `MJ2SampleTableBuilder`

### No Breaking Changes

All existing v1.7.0 APIs remain unchanged. The MJ2 module is purely additive — no migration steps are required for existing code.

## Additional Resources

- **Cross-Platform Guide**: See `MJ2_CROSS_PLATFORM.md` for platform-specific transcoding details.
- **Performance Guide**: See `MJ2_PERFORMANCE.md` for benchmarking and optimization.
- **VideoToolbox Integration**: See `MJ2_VIDEOTOOLBOX.md` for hardware acceleration on Apple platforms.
- **Motion JPEG 2000 Specification**: See `MOTION_JPEG2000.md` for the implementation plan and standards references.

---

**Last Updated**: 2026-02-19
**Version**: 1.8.0
**Maintainer**: J2KSwift Team
