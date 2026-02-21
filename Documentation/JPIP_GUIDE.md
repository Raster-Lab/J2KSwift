# JPIP Streaming Guide

JPIP (JPEG 2000 Interactive Protocol, ISO/IEC 15444-9) enables client-driven,
progressive retrieval of JPEG 2000 imagery from a remote server.  The client
requests only the data needed to render the current view — resolution level,
spatial region, quality layers, and components — minimising bandwidth.

---

## Architecture

```
JPIP Server                      JPIP Client
──────────────────               ──────────────────
JPIPServer (actor)               JPIPClient (actor)
   └── JPIPServerSession             └── createSession()
          └── JPIPRequestQueue              └── requestImage()
                 └── data-bin delivery       └── requestRegion()
                                             └── requestProgressiveQuality()
```

---

## Setting Up a JPIP Client

```swift
import JPIP

// Create a client pointed at a JPIP server
let client = JPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)

// Open a session for a specific target image
let session = try await client.createSession(target: "images/photo.jp2")
print("Session: \(session.sessionID)")

// Request the full image
let image = try await client.requestImage(imageID: "photo")
print("Received: \(image.width)×\(image.height)")
```

---

## Requesting a Spatial Region

```swift
// Only fetch the top-left 512×512 region at resolution level 2
let roi = try await client.requestRegion(
    imageID: "photo",
    regionX: 0,
    regionY: 0,
    regionWidth: 512,
    regionHeight: 512,
    resolutionLevel: 2,
    layers: 4
)
```

---

## Progressive Quality Delivery

```swift
// Receive progressively better quality in successive calls
for layers in [1, 2, 4, 8] {
    let draft = try await client.requestProgressiveQuality(
        imageID: "photo",
        upToLayers: layers
    )
    // Render draft as each quality layer arrives
    renderPreview(draft)
}
```

---

## Resolution-Level Browsing

```swift
// Request a thumbnail (resolution level 4 ≈ 1/16 resolution)
let thumbnail = try await client.requestResolutionLevel(
    imageID: "photo",
    level: 4
)
```

---

## Component Selection

```swift
// Fetch only the luminance component (component 0) for grayscale preview
let gray = try await client.requestComponents(
    imageID: "photo",
    components: [0],
    layers: 4
)
```

---

## Metadata

```swift
let meta = try await client.requestMetadata(imageID: "photo")
print("Width: \(meta["width"] as? Int ?? 0)")
print("Components: \(meta["components"] as? Int ?? 0)")
```

---

## Closing a Session

```swift
try await client.close()
```

---

## WebSocket Transport

J2KSwift includes a WebSocket JPIP transport (`JPIPWebSocketClient`) for
low-latency, bidirectional streaming in browser and native app scenarios.

```swift
import JPIP

let wsClient = JPIPWebSocketClient(url: URL(string: "ws://jpip.example.com/ws")!)
try await wsClient.connect()
let response = try await wsClient.request(target: "photo", channel: "main")
```

---

## Server Push

The `JPIPServerPush` actor enables the server to proactively push quality
improvements and metadata updates to connected clients.

---

## 3D JPIP Streaming

JP3D volumes can also be streamed progressively via JPIP:

```swift
import JPIP
import J2K3D

let jp3dClient = JP3DJPIPClient(serverURL: URL(string: "http://jpip.example.com/")!)
// See JP3D_GUIDE.md for volumetric JPIP examples.
```

---

## See Also

- [JP3D Guide](JP3D_GUIDE.md) — volumetric JPIP streaming
- [CLI Examples](CLI_EXAMPLES.md) — `j2k info` on JPIP targets
- [Examples/JPIPStreaming.swift](../Examples/JPIPStreaming.swift)
