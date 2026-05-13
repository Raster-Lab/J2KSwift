# JPIP Protocol Implementation

This document describes the JPIP (JPEG 2000 Interactive Protocol) implementation in J2KSwift.

## Overview

JPIP (ISO/IEC 15444-9) enables efficient interactive access to JPEG 2000 images over networks. It allows clients to request specific portions of an image (regions, resolutions, quality layers) without downloading the entire file.

## Architecture

### Core Components

#### JPIPRequest
Represents a JPIP request with parameters for:
- `target`: Image identifier
- `fsiz`: Full size (width, height)
- `rsiz`: Region size (width, height)
- `roff`: Region offset (x, y)
- `layers`: Number of quality layers
- `cid`: Channel ID for stateful sessions
- `cnew`: Request new channel
- `len`: Maximum response length
- `comps`: Component indices (Week 72-74) ✅
- `reslevels`: Resolution level (Week 72-74) ✅
- `metadata`: Metadata-only flag (Week 72-74) ✅

#### JPIPResponse
Represents a JPIP response containing:
- `channelID`: Session/channel identifier from JPIP-cnew header
- `data`: Response data
- `statusCode`: HTTP status code
- `headers`: HTTP response headers

#### JPIPSession
Manages a JPIP session with:
- Session ID tracking
- Channel ID management
- Target image association
- Cache model for received data bins with LRU eviction
- Precinct-based cache for fine-grained data management
- Cache statistics tracking (hits, misses, size)
- Selective cache invalidation
- Session lifecycle (active/closed)

#### JPIPTransport
HTTP transport layer providing:
- URLSession-based HTTP client
- Request URL building
- Response parsing
- Persistent connection support

#### JPIPClient
High-level client actor providing:
- Session creation and management
- Image requests
- Region of interest requests
- Automatic session handling

#### JPIPServer (Week 78-80) ✅
Server-side JPIP implementation:
- Image registration and serving
- Request queue with priority-based scheduling
- Bandwidth throttling using token bucket algorithm
- Multi-client support with concurrent session handling
- Session management and timeout detection
- Server statistics tracking

#### JPIPServerSession (Week 78-80) ✅
Server-side session management:
- Session ID and channel ID tracking
- Client cache model tracking
- Request and bandwidth statistics
- Session timeout detection
- Metadata storage

#### JPIPRequestQueue (Week 78-80) ✅
Priority-based request queue:
- Priority-based request ordering
- Queue size limits
- Target-specific operations
- Queue statistics

#### JPIPBandwidthThrottle (Week 78-80) ✅
Bandwidth management:
- Token bucket algorithm for rate limiting
- Global and per-client bandwidth limits
- Burst capacity support
- Bandwidth statistics tracking

## Usage Examples

### Basic Image Request

```swift
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com")!)

// Create a session
let session = try await client.createSession(target: "image.jp2")

// Request the full image
let image = try await client.requestImage(imageID: "image.jp2")
```

### Region of Interest Request

```swift
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com")!)

// Request a specific region
let region = try await client.requestRegion(
    imageID: "large-image.jp2",
    region: (x: 1000, y: 500, width: 800, height: 600)
)
```

### Progressive Quality Request (Week 72-74) ✅

```swift
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com")!)

// Request progressive quality layers (e.g., start with low quality, increase progressively)
let image = try await client.requestProgressiveQuality(
    imageID: "image.jp2",
    upToLayers: 5  // Request up to 5 quality layers
)
```

### Resolution Level Request (Week 72-74) ✅

```swift
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com")!)

// Request a lower resolution level for preview (0 = full resolution, higher = lower)
let thumbnail = try await client.requestResolutionLevel(
    imageID: "high-res-image.jp2",
    level: 3,      // Lower resolution level
    layers: 2      // With 2 quality layers
)
```

### Component Selection Request (Week 72-74) ✅

```swift
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com")!)

// Request only specific components (e.g., Red and Green channels)
let rgImage = try await client.requestComponents(
    imageID: "rgb-image.jp2",
    components: [0, 1],  // Components 0 (R) and 1 (G)
    layers: 3
)
```

### Metadata Request (Week 72-74) ✅

```swift
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com")!)

// Request only metadata without image data
let metadata = try await client.requestMetadata(imageID: "image.jp2")
print("Image metadata: \(metadata)")
```

### Cache Management (Week 75-77) ✅

```swift
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com")!)
let session = try await client.createSession(target: "image.jp2")

// Get cache statistics
let stats = await session.getCacheStatistics()
print("Cache hits: \(stats.hits), misses: \(stats.misses)")
print("Hit rate: \(stats.hitRate * 100)%")
print("Cache size: \(stats.totalSize) bytes, entries: \(stats.entryCount)")

// Check if data is already cached
let isCached = await session.hasDataBin(binClass: .mainHeader, binID: 1)
if isCached {
    // Retrieve from cache
    let dataBin = await session.getDataBin(binClass: .mainHeader, binID: 1)
}

// Invalidate specific bin class
await session.invalidateCache(binClass: .precinct)

// Invalidate old cache entries
let cutoffDate = Date().addingTimeInterval(-3600) // 1 hour ago
await session.invalidateCache(olderThan: cutoffDate)

// Work with precinct cache
let precinctID = JPIPPrecinctID(
    tile: 0,
    component: 0,
    resolution: 2,
    precinctX: 1,
    precinctY: 1
)

// Add precinct data
let precinctData = JPIPPrecinctData(
    precinctID: precinctID,
    data: Data([1, 2, 3, 4, 5]),
    isComplete: true,
    receivedLayers: [0, 1, 2]
)
await session.addPrecinct(precinctData)

// Check precinct cache
let hasPrecinct = await session.hasPrecinct(precinctID)

// Get precinct statistics
let precinctStats = await session.getPrecinctStatistics()
print("Total precincts: \(precinctStats.totalPrecincts)")
print("Complete: \(precinctStats.completePrecincts)")
print("Completion rate: \(precinctStats.completionRate * 100)%")

// Merge partial precinct data
let merged = await session.mergePrecinct(
    precinctID,
    data: Data([6, 7, 8]),
    layers: [3, 4],
    isComplete: true
)

// Invalidate precincts by tile or resolution
await session.invalidatePrecincts(tile: 0)
await session.invalidatePrecincts(resolution: 1)
```

### Custom Request

```swift
// Create a custom request with all parameters
var request = JPIPRequest(target: "image.jp2")
request.fsiz = (width: 1024, height: 768)    // Desired resolution
request.layers = 3                            // 3 quality layers
request.roff = (x: 0, y: 0)                  // Top-left corner
request.rsiz = (width: 512, height: 384)     // Half-size region
request.reslevels = 2                         // Resolution level (Week 72-74)
request.comps = [0, 1, 2]                    // RGB components (Week 72-74)
request.metadata = false                      // Request image data (Week 72-74)

// Build query items
let queryItems = request.buildQueryItems()
// Returns: ["target": "image.jp2", "fsiz": "1024,768", "layers": "3", ...]
```

### Advanced Request Examples (Week 72-74) ✅

```swift
// Request low-resolution preview with only 2 color channels
var request = JPIPRequest.resolutionLevelRequest(target: "image.jp2", level: 2)
request.comps = [0, 1]  // Red and Green only
request.layers = 2       // Low quality for fast preview

// Request specific region at a specific resolution level
var request = JPIPRequest.regionRequest(
    target: "image.jp2",
    x: 100, y: 100,
    width: 400, height: 300
)
request.reslevels = 1   // One level down from full resolution
request.layers = 4       // Medium quality

// Metadata-only request for image properties
let metaRequest = JPIPRequest.metadataRequest(target: "image.jp2")
```

## Server Usage Examples (Week 78-80) ✅

### Basic Server Setup

```swift
import JPIP

// Create a JPIP server
let server = JPIPServer(port: 8080)

// Register images for serving
try await server.registerImage(name: "sample.jp2", at: imageURL)
try await server.registerImage(name: "photo.jp2", at: photoURL)

// Start the server
try await server.start()

// Server is now accepting requests...

// Stop when done
try await server.stop()
```

### Server with Configuration

```swift
let config = JPIPServer.Configuration(
    maxClients: 100,
    maxQueueSize: 1000,
    globalBandwidthLimit: 10_000_000,    // 10 MB/s global
    perClientBandwidthLimit: 1_000_000,  // 1 MB/s per client
    sessionTimeout: 300                   // 5 minutes
)

let server = JPIPServer(port: 8080, configuration: config)
```

### Handling Requests

```swift
// The server automatically handles incoming JPIP requests
// Requests are prioritized:
// - Session creation (highest priority)
// - Metadata requests (high priority)
// - Small region requests (medium-high priority)
// - Regular requests (normal priority)

// Check server statistics
let stats = await server.getStatistics()
print("Total requests: \(stats.totalRequests)")
print("Active clients: \(stats.activeClients)")
print("Total bytes sent: \(stats.totalBytesSent)")
print("Queued requests: \(stats.queuedRequests)")
```

### Managing Sessions

```swift
// List registered images
let images = await server.listRegisteredImages()
print("Serving images: \(images)")

// Close a specific session
await server.closeSession("session-id-123")

// Get active session count
let sessionCount = await server.getActiveSessionCount()
print("Active sessions: \(sessionCount)")
```

### Image Management

```swift
// Register a new image
try await server.registerImage(name: "new-image.jp2", at: newImageURL)

// Unregister an image
await server.unregisterImage(name: "old-image.jp2")

// List all registered images
let allImages = await server.listRegisteredImages()
```

## Protocol Details

### Request Format

JPIP requests are sent as HTTP GET requests with query parameters:

```
GET /jpipserver?target=image.jp2&fsiz=800,600&layers=3 HTTP/1.1
Host: jpip.example.com
Accept: application/octet-stream
```

### Response Format

The server responds with a JPIP-cnew header containing the channel ID:

```
HTTP/1.1 200 OK
JPIP-cnew: cid=1942302,path=/image.jp2,transport=http
Content-Type: application/octet-stream
Content-Length: 12345

[binary data]
```

### Session Management

1. **Initial Request**: Client sends request with `cnew=http` to create a new channel
2. **Server Response**: Server returns `JPIP-cnew` header with channel ID (cid)
3. **Subsequent Requests**: Client includes `cid` parameter for stateful communication
4. **Cache Tracking**: Client tracks received data bins to avoid redundant transfers

### Data Bins

JPIP organizes JPEG 2000 data into bins:
- **Main Header (0)**: Main codestream header
- **Tile Header (1)**: Tile headers
- **Precinct (2)**: Precinct data
- **Tile (3)**: Tile data
- **Extended Precinct (4)**: Extended precinct data
- **Metadata (5)**: Metadata bins

## Implementation Status

### Phase 6, Week 69-71: JPIP Client Basics ✅ Complete

- ✅ JPIP request types and parameters
- ✅ HTTP transport layer using URLSession
- ✅ Response parsing (JPIP-cnew headers)
- ✅ Session management
- ✅ Channel ID tracking
- ✅ Cache model for data bins
- ✅ Persistent connection support
- ✅ Comprehensive tests (27 tests, 100% pass rate)

### Future Work

**Phase 6, Week 72-74: Data Streaming** ✅ COMPLETED
- ✅ Progressive quality requests
- ✅ Resolution level requests
- ✅ Component selection
- ✅ Metadata requests
- ✅ Enhanced request builders
- ✅ Comprehensive tests (41 tests, 100% pass rate)

**Phase 6, Week 75-77: Cache Management** ✅ COMPLETED
- ✅ Enhanced cache model with statistics tracking
- ✅ LRU eviction policy implementation
- ✅ Cache size and entry limits
- ✅ Cache invalidation by bin class and age
- ✅ Precinct-based caching with fine-grained tracking
- ✅ Partial precinct data support and merging
- ✅ Cache hit rate optimization
- ✅ Comprehensive tests (71 tests total, 100% pass rate)

**Phase 6, Week 78-80: JPIP Server**
- Server implementation
- Request queue management
- Bandwidth throttling
- Multi-client support

## Standards Compliance

This implementation follows:
- **ISO/IEC 15444-9**: JPEG 2000 Part 9 - Interactivity tools, APIs and protocols
- **ITU-T T.808**: JPIP protocol specification

## Performance Considerations

- Uses Swift 6 actor model for thread-safe concurrent access
- URLSession provides efficient HTTP connection pooling
- **LRU cache eviction** minimizes memory usage while maximizing hit rates
- **Precinct-based caching** enables fine-grained data management
- Cache statistics track performance metrics for optimization
- **Automatic cache size management** prevents unbounded memory growth
- Stateful sessions reduce overhead for multiple requests
- Cache invalidation strategies optimize memory usage

## Testing

Run all JPIP tests:
```bash
swift test --filter JPIPTests
```

Run cache-specific tests:
```bash
swift test --filter JPIPCacheTests
```

All 71 tests verify:
- Request building and parameter encoding (41 tests)
- Response parsing and channel ID extraction
- Session lifecycle management
- Data bin tracking and caching (30 new cache tests)
- Cache eviction policies (LRU)
- Precinct-based caching
- Cache statistics and hit rate tracking
- Cache invalidation strategies
- Transport layer functionality
- Client API usage

## API Documentation

Full API documentation is available in the source code comments. All public APIs include:
- Summary descriptions
- Parameter documentation
- Return value descriptions
- Error conditions
- Usage examples

## Examples

See `Tests/JPIPTests/JPIPTests.swift` for comprehensive usage examples.
