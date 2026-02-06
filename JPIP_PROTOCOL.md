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
- Cache model for received data bins
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

### Custom Request

```swift
// Create a custom request
var request = JPIPRequest(target: "image.jp2")
request.fsiz = (width: 1024, height: 768)  // Desired resolution
request.layers = 3                          // 3 quality layers
request.roff = (x: 0, y: 0)                // Top-left corner
request.rsiz = (width: 512, height: 384)   // Half-size region

// Build query items
let queryItems = request.buildQueryItems()
// Returns: ["target": "image.jp2", "fsiz": "1024,768", "layers": "3", ...]
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

**Phase 6, Week 72-74: Data Streaming**
- Progressive quality requests
- Resolution level requests
- Component selection
- Metadata requests

**Phase 6, Week 75-77: Cache Management**
- Advanced cache model
- Cache invalidation
- Precinct-based caching
- Cache hit rate optimization

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
- Cache model minimizes redundant data transfers
- Stateful sessions reduce overhead for multiple requests

## Testing

Run JPIP tests:
```bash
swift test --filter JPIPTests
```

All 27 tests verify:
- Request building and parameter encoding
- Response parsing and channel ID extraction
- Session lifecycle management
- Data bin tracking
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
