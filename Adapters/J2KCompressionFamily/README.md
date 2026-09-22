# J2KCompressionFamily

The [CompressionFamily](https://github.com/Raster-Lab/CompressionFamily) protocol conformances for J2KSwift's public types (`J2KImage`, `J2KError`, `J2KEncoder`, `J2KDecoder`), as a package of their own.

## Why this is a separate package

Contract 0.8.0 §4 of the Swift Image Compression Suite requires the J2KSwift core library to resolve without CompressionFamily in its package graph, so that the codec can migrate into [SwiftJ2K](https://github.com/Raster-Lab/SwiftJ2K) alone (POL-01, POL-02). Before this package existed the conformances lived in `Sources/J2KCore` and `Sources/J2KCodec`, which made CompressionFamily a mandatory dependency of every J2KSwift consumer. They were not deleted: CompressionFamily stays available to predecessor consumers under POL-04, and this package is where the J2K side of it lives.

## Use

This package depends on the J2KSwift package at the repository root by path, so it is consumable from a checkout:

```swift
.package(path: "../J2KSwift/Adapters/J2KCompressionFamily")
```

```swift
import J2KCompressionFamily   // makes J2KEncoder a CompressionEncoder, etc.
```

The conformances are retroactive, so a module must import `J2KCompressionFamily` for them to apply. If a consumer ever needs them by URL, publish this directory as its own repository and replace the path dependency on J2KSwift with a versioned URL; nothing here assumes that has happened.

## Verify

```bash
cd Adapters/J2KCompressionFamily && swift build && swift test
```
