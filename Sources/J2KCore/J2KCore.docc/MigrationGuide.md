# Migration Guide — v1.9 to v2.0

@Metadata {
    @PageKind(article)
}

A step-by-step guide for migrating existing J2KSwift code from version 1.9.x
to version 2.0.

## What's New in v2.0

Version 2.0 is a major release that modernises the library for Swift 6 and
adds several new capabilities:

- **Swift 6 strict concurrency** — every public type is ``Sendable``;
  mutable shared state is managed by actors.
- **GPU acceleration** — Metal (``J2KMetal``) and Vulkan (``J2KVulkan``)
  modules provide hardware-accelerated DWT, colour transform, and
  quantisation.
- **HTJ2K (High Throughput JPEG 2000)** — Part 15 block coder support for
  dramatically faster encoding and decoding.
- **JP3D (Volumetric JPEG 2000)** — ``JP3DEncoder`` and ``JP3DDecoder`` for
  three-dimensional image data.
- **JPIP streaming** — ``JPIPClient`` and ``JPIPServer`` with progressive
  delivery, session persistence, and adaptive quality.
- **New modules** — ``J2KMetal``, ``J2KVulkan``, ``J2K3D``, and ``JPIP`` have
  been added to the package.

## Breaking Changes

### Concurrency Model

The most significant change is the adoption of Swift 6 strict concurrency.
Types that previously relied on `NSLock`, `DispatchQueue`, or
`@unchecked Sendable` have been replaced by actors or restructured as
value types.

| v1.9 Pattern                      | v2.0 Equivalent                        |
|-----------------------------------|----------------------------------------|
| `class Foo: @unchecked Sendable`  | `actor Foo` or `struct Foo: Sendable`  |
| `NSLock` / `os_unfair_lock`       | `Mutex` (from Synchronization) or actor |
| Completion handler callback       | `async throws` method                  |
| `DispatchQueue.global().async`    | Structured `Task` / `TaskGroup`        |

### Renamed Types

Several types have been renamed for consistency with British English spelling
and JPEG 2000 terminology:

| v1.9 Name                      | v2.0 Name                            |
|--------------------------------|--------------------------------------|
| `J2KQuantization`              | ``J2KQuantizer`` (struct, replaces the former class) |
| `J2KQuantizationParameters`    | ``J2KQuantizationParameters`` (now ``Sendable``) |
| `J2KEncoderOptions` (if used)  | ``J2KEncodingConfiguration``         |

> Note: ``J2KColorTransform`` retains its original name in J2KCodec and
> J2KAccelerate. The Vulkan module uses British spelling
> (`J2KVulkanColourTransform`) to align with the Vulkan ecosystem conventions.

### Encoder & Decoder API

The ``J2KEncoder`` and ``J2KDecoder`` initialisers now accept
``J2KEncodingConfiguration`` and optional partial-decoding option types
respectively. Free-function wrappers have been removed in favour of method
calls on the codec structs.

**v1.9:**

```swift
let data = try J2KEncode(image, options: opts)
let image = try J2KDecode(data)
```

**v2.0:**

```swift
let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)

let decoder = J2KDecoder()
let image = try decoder.decode(from: data)
```

## Concurrency Migration

### Replacing NSLock with Mutex

```swift
// v1.9
class Cache: @unchecked Sendable {
    private var lock = NSLock()
    private var store: [String: Data] = [:]

    func get(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }
}

// v2.0
import Synchronization

struct Cache: Sendable {
    private let store = Mutex<[String: Data]>([:])

    func get(_ key: String) -> Data? {
        store.withLock { $0[key] }
    }
}
```

### Replacing @unchecked Sendable with an Actor

```swift
// v1.9
class SessionManager: @unchecked Sendable {
    private let queue = DispatchQueue(label: "session")
    private var sessions: [String: Session] = [:]

    func add(_ session: Session) {
        queue.sync { sessions[session.id] = session }
    }
}

// v2.0
actor SessionManager {
    private var sessions: [String: Session] = [:]

    func add(_ session: Session) {
        sessions[session.id] = session
    }
}
```

### Adopting async/await

```swift
// v1.9
func loadImage(at url: URL,
               completion: @escaping (Result<J2KImage, Error>) -> Void) {
    DispatchQueue.global().async {
        do {
            let data = try Data(contentsOf: url)
            let image = try J2KDecode(data)
            completion(.success(image))
        } catch {
            completion(.failure(error))
        }
    }
}

// v2.0
func loadImage(at url: URL) async throws -> J2KImage {
    let data = try Data(contentsOf: url)
    let decoder = J2KDecoder()
    return try decoder.decode(from: data)
}
```

## New Modules

Add the new module products to your target dependencies as needed:

```swift
// Package.swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "J2KCore", package: "J2KSwift"),
        .product(name: "J2KCodec", package: "J2KSwift"),
        .product(name: "J2KFileFormat", package: "J2KSwift"),
        .product(name: "JPIP", package: "J2KSwift"),       // new
        .product(name: "J2KMetal", package: "J2KSwift"),    // new
        .product(name: "J2KVulkan", package: "J2KSwift"),   // new
        .product(name: "J2K3D", package: "J2KSwift"),       // new
    ]
)
```

## Configuration Changes

``J2KEncodingConfiguration`` replaces the older dictionary-based options.
Properties are strongly typed and documented:

```swift
// v1.9
let opts: [String: Any] = [
    "lossless": true,
    "levels": 5,
    "codeblock": [64, 64],
]
let data = try J2KEncode(image, options: opts)

// v2.0
var config = J2KEncodingConfiguration()
config.isLossless = true
config.waveletLevels = 5
config.codeBlockSize = (width: 64, height: 64)

let encoder = J2KEncoder(configuration: config)
let data = try encoder.encode(image)
```

Presets (``J2KEncodingPreset``) offer convenient defaults:

```swift
let encoder = J2KEncoder(preset: .archivalLossless)
```

## Checklist

- [ ] Update your `Package.swift` dependency to `from: "2.0.0"`.
- [ ] Replace free-function `J2KEncode` / `J2KDecode` calls with
      ``J2KEncoder`` / ``J2KDecoder``.
- [ ] Remove `@unchecked Sendable` from types and use actors or `Mutex`.
- [ ] Convert completion-handler APIs to `async throws`.
- [ ] Adopt ``J2KEncodingConfiguration`` in place of dictionary options.
- [ ] Add new module dependencies (JPIP, J2KMetal, etc.) if needed.
- [ ] Run `swift build` and address any remaining concurrency warnings.

## See Also

- <doc:Architecture>
- <doc:GettingStarted>
