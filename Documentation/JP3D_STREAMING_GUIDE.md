# JP3D JPIP Streaming Guide

## Table of Contents

1. [Overview](#overview)
2. [JPIP 3D Protocol Concepts](#jpip-3d-protocol-concepts)
3. [Setting Up JP3DJPIPClient](#setting-up-jp3djpipclient)
4. [Session Management](#session-management)
5. [Viewport-Based Requests](#viewport-based-requests)
6. [Progressive Delivery](#progressive-delivery)
7. [Progression Modes](#progression-modes)
8. [Slice Range Streaming](#slice-range-streaming)
9. [Cache Management](#cache-management)
10. [Network Configuration](#network-configuration)
11. [Error Handling](#error-handling)
12. [Server-Side Requirements](#server-side-requirements)
13. [Advanced Patterns](#advanced-patterns)
14. [Performance Tips](#performance-tips)

---

## Overview

### What is JPIP?

JPIP (JPEG 2000 Interactive Protocol, ISO/IEC 15444-9) is a client-server protocol for streaming JPEG 2000 data on demand. Rather than downloading an entire compressed file, a client sends window-of-interest requests and receives only the compressed data relevant to the current view.

JP3D extends JPIP with three-dimensional window-of-interest semantics, allowing a medical imaging viewer or scientific visualisation application to:

- Stream individual slices or slab ranges from a large CT/MRI volume
- Progressively refine image quality as bandwidth allows
- Jump to arbitrary Z positions without fetching the full volume
- Prioritise the current viewing region (viewport-driven streaming)

### Why Use JPIP Streaming?

| Scenario | Without JPIP | With JPIP |
|----------|-------------|-----------|
| Open a 4 GB chest CT remotely | Download all 4 GB first | First slice visible in < 1 second |
| Jump to vertebra L4 | Seek in large file | Request only relevant Z range |
| Zoom into lung nodule | Full resolution already downloaded | Request high-res only for ROI |
| Reduce server storage | N/A | Single JP3D file serves all clients |
| Mobile viewer | Impractical at 4 GB | Streams only what is visible |

### J2KSwift JPIP Implementation

The `JPIP` module provides:

- `JP3DJPIPClient` — actor-based client with automatic reconnect
- `JP3DViewport` — spatial window descriptor
- `JP3DStreamingRegion` — region + quality + resolution request
- `JP3DProgressionMode` — delivery strategy selector
- `JPIPSession` — session handle from server

---

## JPIP 3D Protocol Concepts

### Requests and Responses

JPIP uses HTTP as its transport. Each request is an HTTP GET or POST with JPIP-specific query parameters:

```
GET /jp3d/volume?target=CT_CHEST_001&type=jpp-stream&roff=64,64,50&rsiz=128,128,100 HTTP/1.1
```

The server responds with a JPIP data-bin stream containing only the compressed packets that intersect the requested region at the requested quality.

### Data Bins

| Data Bin Type | Contains |
|---------------|---------|
| Main header | Volume dimensions, component info, tiling |
| Tile header | Per-tile coding parameters |
| Precinct | Compressed data for one spatial precinct |
| Tile data | Full tile compressed data |

### Quality Layers and Resolution Levels

A JP3D bitstream is organised in quality layers and resolution levels. JPIP allows the client to request a partial quality layer or reduced resolution, enabling progressive refinement:

```
Resolution level 3  →  1/8 resolution (thumbnail)
Resolution level 2  →  1/4 resolution
Resolution level 1  →  1/2 resolution
Resolution level 0  →  full resolution

Quality layer 1  →  base quality (~25 dB PSNR)
Quality layer 4  →  medium quality (~35 dB PSNR)
Quality layer 8  →  full quality  (~50 dB PSNR)
```

---

## Setting Up JP3DJPIPClient

### Minimal Setup

```swift
import J2KCore
import J2K3D
import JPIP

// Create the client
let serverURL = URL(string: "jpip://imaging.example.com:8080")!
let client = JP3DJPIPClient(serverURL: serverURL)

// Connect (establishes HTTP session, fetches capabilities)
try await client.connect()
print("Connected to JPIP server")
```

### With Custom Configuration

```swift
import JPIP

let config = JPIPClientConfiguration(
    progressionMode: .viewDependent,
    maxConcurrentRequests: 4,
    requestTimeoutSeconds: 30.0,
    cacheCapacityMB: 512,
    enableTLS: true,
    tlsConfiguration: .systemDefault
)

let client = JP3DJPIPClient(
    serverURL: URL(string: "jpips://secure-imaging.example.com")!,
    configuration: config
)
try await client.connect()
```

### Over HTTP vs HTTPS

| Scheme | Port | Use Case |
|--------|------|---------|
| `jpip://` | 8080 | LAN / development |
| `jpips://` | 8443 | Internet / production |
| `http://` with JPIP headers | 80 | Proxy-compatible fallback |

---

## Session Management

### Creating a Session

A JPIP session binds a client to a specific volume on the server. Multiple sessions can be active simultaneously.

```swift
import JPIP

// Create a session for a specific volume
let session = try await client.createSession(volumeID: "CT_CHEST_2024_001")
print("Session created: \(session.sessionID)")
print("Volume size: \(session.volumeWidth)×\(session.volumeHeight)×\(session.volumeDepth)")
print("Components: \(session.componentCount)")
print("Quality layers: \(session.qualityLayers)")
```

### Session Properties

| Property | Type | Description |
|----------|------|-------------|
| `sessionID` | `String` | Opaque server-assigned session identifier |
| `volumeWidth` | `Int` | Full volume width in voxels |
| `volumeHeight` | `Int` | Full volume height |
| `volumeDepth` | `Int` | Full volume depth (slices) |
| `componentCount` | `Int` | Number of components |
| `qualityLayers` | `Int` | Maximum available quality layers |
| `resolutionLevels` | `Int` | Number of DWT decomposition levels |
| `tileWidth` | `Int` | Tile width from server-side encoding |
| `tileHeight` | `Int` | Tile height |
| `tileDepth` | `Int` | Tile depth |

### Lifecycle Management

```swift
// Good pattern: use defer to ensure cleanup
func loadVolume(from volumeID: String) async throws -> J2KVolume {
    try await client.connect()
    defer {
        Task { try? await client.disconnect() }
    }

    let session = try await client.createSession(volumeID: volumeID)
    let region = JP3DRegion(
        x: 0..<session.volumeWidth,
        y: 0..<session.volumeHeight,
        z: 0..<session.volumeDepth
    )
    let data = try await client.requestRegion(region)
    let decoder = JP3DDecoder()
    return try await decoder.decode(data).volume
}
```

### Long-Lived Sessions

For interactive viewers, keep the client connected across requests:

```swift
// Viewer actor holding a persistent JPIP session
actor VolumeViewer {
    private let client: JP3DJPIPClient
    private var session: JPIPSession?

    init(serverURL: URL) {
        self.client = JP3DJPIPClient(
            serverURL: serverURL,
            configuration: JPIPClientConfiguration(
                progressionMode: .adaptive,
                cacheCapacityMB: 256
            )
        )
    }

    func open(volumeID: String) async throws {
        try await client.connect()
        session = try await client.createSession(volumeID: volumeID)
    }

    func close() async throws {
        try await client.disconnect()
        session = nil
    }
}
```

---

## Viewport-Based Requests

### Updating the Viewport

As the user navigates the volume, update the viewport to guide server-side prioritisation:

```swift
// User scrolled to slice 75 and is viewing a 512×512 window
let viewport = JP3DViewport(
    xRange: 0..<512,
    yRange: 0..<512,
    zRange: 70..<80   // current ± 5 slices
)
try await client.updateViewport(viewport)
```

### Viewport + Region Request

Combine a viewport update with an explicit region request for immediate data:

```swift
// Update viewport to focus on a nodule
let noduleViewport = JP3DViewport(
    xRange: 180..<280,
    yRange: 220..<320,
    zRange: 112..<130
)
try await client.updateViewport(noduleViewport)

// Request the data for this exact region at full quality
let noduleRegion = JP3DRegion(
    x: 180..<280,
    y: 220..<320,
    z: 112..<130
)
let data = try await client.requestRegion(noduleRegion)
let result = try await decoder.decode(data)
```

### Viewport-Driven Automatic Prefetch

When using `.viewDependent` or `.adaptive` progression modes, the client automatically issues prefetch requests for data adjacent to the current viewport:

```swift
let config = JPIPClientConfiguration(
    progressionMode: .viewDependent,
    prefetchAdjacentSlices: 5,    // prefetch ±5 slices
    prefetchQualityLayer: 2       // prefetch at low quality
)
```

---

## Progressive Delivery

### Quality-Progressive Display Loop

Display each quality increment as it arrives from the server:

```swift
import J2K3D
import JPIP

let decoder = JP3DDecoder(
    configuration: JP3DDecoderConfiguration(tolerateTruncation: true)
)

// Request region at increasing quality layers
for layer in 1...session.qualityLayers {
    let streamRegion = JP3DStreamingRegion(
        xRange: 0..<256,
        yRange: 0..<256,
        zRange: 50..<80,
        qualityLayer: layer,
        resolutionLevel: 0
    )

    // Each subsequent request adds incremental data
    let data = try await client.requestStreamingRegion(streamRegion)
    let result = try await decoder.decode(data, region: JP3DRegion(
        x: streamRegion.xRange,
        y: streamRegion.yRange,
        z: streamRegion.zRange
    ))

    // Update display with current quality
    await displayVolume(result.volume, qualityLayer: layer)

    // Stop if user has navigated away
    guard isCurrentRegionStillActive(streamRegion) else { break }
}
```

### Resolution-Progressive Thumbnail First

```swift
// Show thumbnail immediately, then refine
let region = JP3DRegion(x: 0..<512, y: 0..<512, z: 0..<256)

// 1. Thumbnail at 1/8 resolution
var thumbData = try await client.requestRegion(region, resolutionLevel: 3)
var thumb = try await decoder.decode(thumbData, resolutionLevel: 3)
await displayThumbnail(thumb.volume)

// 2. Half resolution
var halfData = try await client.requestRegion(region, resolutionLevel: 1)
var half = try await decoder.decode(halfData, resolutionLevel: 1)
await displayHalfResolution(half.volume)

// 3. Full resolution
let fullData = try await client.requestRegion(region)
let full = try await decoder.decode(fullData)
await displayFull(full.volume)
```

---

## Progression Modes

### Mode Selection Guide

| Mode | When to Use | Network Pattern |
|------|-------------|----------------|
| `.adaptive` | General-purpose interactive viewer | Adjusts based on bandwidth |
| `.resolutionFirst` | Initial load — show something fast | Low-res → high-res |
| `.qualityFirst` | All tiles at base quality before refining | Broad coverage first |
| `.sliceBySliceForward` | CT viewer scrolling top → bottom | Z ascending |
| `.sliceBySliceReverse` | CT viewer scrolling bottom → top | Z descending |
| `.sliceBySliceBidirectional` | Jump to a specific slice | Outward from focus Z |
| `.viewDependent` | 3D renderer with current frustum | Only tiles in frustum |
| `.distanceOrdered` | Fly-through animation | Tiles by Z distance |

### Changing Mode at Runtime

```swift
// User switched from scrolling to volume rendering
try await client.setProgressionMode(.viewDependent)

// Update the viewport for the new render perspective
let perspectiveViewport = JP3DViewport(
    xRange: 128..<384,
    yRange: 128..<384,
    zRange: 0..<256
)
try await client.updateViewport(perspectiveViewport)
```

---

## Slice Range Streaming

### Requesting a Contiguous Z Range

```swift
// Request 20 slices starting at slice 100, at quality 75/100
let data = try await client.requestSliceRange(
    zRange: 100..<120,
    quality: 75
)

let result = try await decoder.decode(data, region: JP3DRegion(
    x: 0..<session.volumeWidth,
    y: 0..<session.volumeHeight,
    z: 100..<120
))

print("Received \(result.tilesDecoded) tiles for slice range 100-120")
```

### Streaming a Full Volume Slice by Slice

```swift
let sliceThickness = 10
let totalDepth = session.volumeDepth
var collectedData = Data()

for z in stride(from: 0, to: totalDepth, by: sliceThickness) {
    let zEnd = min(z + sliceThickness, totalDepth)
    let sliceData = try await client.requestSliceRange(
        zRange: z..<zEnd,
        quality: 100
    )
    collectedData.append(sliceData)

    // Decode and display incrementally
    let partialResult = try await decoder.decode(collectedData)
    await updateSliceDisplay(partialResult.volume, upToZ: zEnd)

    print("Progress: \(zEnd)/\(totalDepth) slices loaded")
}
```

---

## Cache Management

### Built-In Tile Cache

`JP3DJPIPClient` maintains an LRU tile cache to avoid redundant server requests:

```swift
// Configure cache size
let config = JPIPClientConfiguration(
    cacheCapacityMB: 512,       // 512 MB tile cache
    cacheEvictionPolicy: .lru   // Least-recently-used eviction
)
```

### Cache Statistics

```swift
let stats = await client.cacheStatistics
print("Cache hits:   \(stats.hits)")
print("Cache misses: \(stats.misses)")
print("Cache size:   \(stats.currentSizeMB) MB / \(stats.capacityMB) MB")
print("Hit rate:     \(String(format: "%.1f", stats.hitRate * 100))%")
```

### Manual Cache Control

```swift
// Evict tiles for a volume no longer in use
await client.evictCache(forVolumeID: "CT_OLD_VOLUME")

// Clear entire cache
await client.clearCache()

// Pin frequently-accessed tiles (prevent eviction)
await client.pinTiles(inRegion: JP3DRegion(x: 200..<300, y: 200..<300, z: 0..<256))
```

### Persistent Disk Cache

```swift
let diskCacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("JP3DCache")

let config = JPIPClientConfiguration(
    cacheCapacityMB: 256,
    diskCacheURL: diskCacheURL,
    diskCacheCapacityMB: 2048  // 2 GB on-disk cache
)
```

---

## Network Configuration

### Timeouts and Retries

```swift
let config = JPIPClientConfiguration(
    requestTimeoutSeconds: 30.0,
    connectionTimeoutSeconds: 10.0,
    maxRetries: 3,
    retryDelaySeconds: 1.0,
    retryBackoffMultiplier: 2.0  // Exponential backoff
)
```

### Bandwidth Limiting

```swift
// Useful for background prefetching to avoid congesting foreground requests
let config = JPIPClientConfiguration(
    prefetchBandwidthLimitKbps: 2048,   // 2 Mbps for background prefetch
    progressionMode: .adaptive
)
```

### Proxy Support

```swift
let config = JPIPClientConfiguration(
    proxyURL: URL(string: "http://proxy.hospital.org:8888"),
    proxyCredentials: URLCredential(
        user: "proxyuser",
        password: "proxypass",
        persistence: .forSession
    )
)
```

### Authentication

```swift
// Bearer token authentication
let config = JPIPClientConfiguration(
    authorizationToken: "eyJhbGciOiJSUzI1NiJ9...",
    tokenRefreshHandler: { expiredToken in
        return try await refreshToken(expiredToken)
    }
)
```

---

## Error Handling

### JPIP-Specific Errors

```swift
import JPIP

do {
    let session = try await client.createSession(volumeID: "MISSING_VOLUME")
} catch JPIPError.volumeNotFound(let volumeID) {
    print("Volume '\(volumeID)' not found on server")
} catch JPIPError.sessionExpired {
    // Session timed out — recreate
    try await client.disconnect()
    try await client.connect()
    let session = try await client.createSession(volumeID: volumeID)
} catch JPIPError.networkError(let underlying) {
    print("Network error: \(underlying.localizedDescription)")
} catch JPIPError.serverError(let statusCode, let message) {
    print("Server error \(statusCode): \(message)")
} catch JPIPError.insufficientData {
    // Server returned less data than expected — may be loading
    print("Server still loading volume, retry in a moment")
}
```

### Automatic Reconnection

```swift
let config = JPIPClientConfiguration(
    enableAutoReconnect: true,
    maxReconnectAttempts: 5,
    reconnectDelaySeconds: 2.0
)
```

### Partial Data Handling

```swift
// Always use tolerateTruncation for streaming contexts
let decoder = JP3DDecoder(
    configuration: JP3DDecoderConfiguration(tolerateTruncation: true)
)

let data = try await client.requestRegion(region)
let result = try await decoder.decode(data)

if result.isPartial {
    // Display what we have, mark pending areas
    await displayPartialVolume(result.volume, coverage: result.tilesDecoded, total: result.tilesTotal)
} else {
    await displayCompleteVolume(result.volume)
}
```

---

## Server-Side Requirements

### Compatible JPIP Servers

The `JP3DJPIPClient` is compatible with JPIP servers that implement:

| Requirement | Version |
|-------------|---------|
| ISO 15444-9 (JPIP) | RFC or IS edition |
| JP3D bitstreams (ISO 15444-10) | Required |
| HTTP/1.1 or HTTP/2 transport | Either |
| `jpp-stream` response type | Required |
| `jppt-stream` response type | Optional |

### Server Configuration Recommendations

Encode volumes with JPIP-friendly configurations for best streaming performance:

```swift
// Encoder configuration optimised for JPIP delivery
let jpipConfig = JP3DEncoderConfiguration(
    compressionMode: .lossy(psnr: 42.0),
    tiling: .streaming,                  // Small tiles for fast random access
    progressionOrder: .lrcps,            // Layer-progressive for quality refinement
    qualityLayers: 10                    // More layers = smoother quality progression
)
```

---

## Advanced Patterns

### Concurrent Multi-Region Loading

```swift
// Load four quadrants of a CT slice in parallel
let regions = [
    JP3DRegion(x: 0..<256,   y: 0..<256,   z: 100..<110),
    JP3DRegion(x: 256..<512, y: 0..<256,   z: 100..<110),
    JP3DRegion(x: 0..<256,   y: 256..<512, z: 100..<110),
    JP3DRegion(x: 256..<512, y: 256..<512, z: 100..<110),
]

let data = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
    for (index, region) in regions.enumerated() {
        group.addTask {
            let d = try await client.requestRegion(region)
            return (index, d)
        }
    }
    return try await group.reduce(into: [(Int, Data)]()) { $0.append($1) }
        .sorted { $0.0 < $1.0 }
        .map { $0.1 }
}
```

### Adaptive Quality Based on Network Speed

```swift
actor AdaptiveQualityStreamer {
    private let client: JP3DJPIPClient
    private var currentQualityLayer = 1

    func streamWithAdaptiveQuality(region: JP3DRegion) async throws {
        while currentQualityLayer <= 8 {
            let start = Date()
            let streamRegion = JP3DStreamingRegion(
                xRange: region.x,
                yRange: region.y,
                zRange: region.z,
                qualityLayer: currentQualityLayer,
                resolutionLevel: 0
            )
            let data = try await client.requestStreamingRegion(streamRegion)
            let elapsed = Date().timeIntervalSince(start)

            // Reduce quality if too slow
            if elapsed > 2.0 {
                currentQualityLayer = max(1, currentQualityLayer - 1)
            } else if elapsed < 0.5 {
                currentQualityLayer = min(8, currentQualityLayer + 1)
            }

            await updateDisplay(with: data, layer: currentQualityLayer)
            currentQualityLayer += 1
        }
    }
}
```

---

## Performance Tips

| Tip | Impact | Implementation |
|-----|--------|---------------|
| Use small tiles for streaming | High | `.streaming` tiling preset |
| Cache frequently-accessed regions | High | Increase `cacheCapacityMB` |
| Request minimal quality for preview | High | `qualityLayer: 1–2` initially |
| Use HTTP/2 for concurrent requests | Medium | Server must support HTTP/2 |
| Pin hot tiles | Medium | `client.pinTiles(inRegion:)` |
| Reduce `decompositionLevelsZ` | Medium | Fewer Z DWT levels on server |
| Prefetch adjacent slices | Medium | `prefetchAdjacentSlices: 5` |
| Compress JPIP responses with gzip | Low | Server-side configuration |

> **Note:** The `JP3DJPIPClient` actor serialises all requests through its actor queue. To maximise throughput on high-bandwidth connections, create multiple `JP3DJPIPClient` instances and balance requests across them, or use the built-in `maxConcurrentRequests` configuration to allow pipelining within a single client.
