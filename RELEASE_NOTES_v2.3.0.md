# J2KSwift v2.3.0 Release Notes

**Release Date**: 2026-11-29  
**Phase**: Phase 20 — JPEG XS Core Codec (Weeks 326–335)  
**Previous Version**: 2.2.0

---

## Headline Feature: JPEG XS Core Codec (ISO/IEC 21122)

> **⚠️ Important**: JPEG XS (ISO/IEC 21122) is a **separate compression standard** from JPEG 2000 (ISO/IEC 15444). It is a lightweight, visually lossless codec designed for low-latency broadcast and production workflows. It is distinct from JPEG 2000 in the same way that JPEG XL (ISO/IEC 18181) is a separate standard. The `J2KXS` module was added to J2KSwift as a companion codec, but it does **not** implement any part of the JPEG 2000 standard.

v2.3.0 adds a new `J2KXS` module implementing the foundational JPEG XS encode/decode pipeline with slice-based DWT, uniform scalar quantisation, prefix-code entropy coding, and binary codestream packetisation.

---

## What's New

### New Module: `J2KXS`

A self-contained JPEG XS codec library depending only on `J2KCore`.

#### Image Types (`J2KXSImageTypes`)

| Type | Description |
|------|-------------|
| `J2KXSPixelFormat` | 5 pixel formats: `.yuv420`, `.yuv422`, `.yuv444`, `.rgb`, `.rgba`; each reports `planeCount` (3 or 4) |
| `J2KXSImage` | Planar image with width, height, pixel format, and per-plane `[Float]` sample data; dimensions clamped to ≥ 1 |
| `J2KXSError` | 5 error cases for invalid dimensions, plane count mismatches, empty data, codestream corruption, and configuration errors |
| `J2KXSEncodeResult` | Wraps encoded codestream `Data`, source dimensions, pixel format, and encoded size in bytes |
| `J2KXSDecodeResult` | Wraps decoded `J2KXSImage`, source codestream size, and decoded sample count |

#### Slice-Based DWT Engine (`J2KXSDWTEngine`)

| Feature | Description |
|---------|-------------|
| **Actor-based** | Thread-safe DWT with `async` forward and inverse transforms |
| **Haar lifting** | Horizontal Haar-like lifting scaffold for slice processing |
| **Orientation subbands** | `J2KXSDWTOrientation` — `.ll`, `.lh`, `.hl`, `.hh` with labels and `isApproximation` flag |
| **Subband type** | `J2KXSSubband` wrapping orientation, coefficient data, and dimensions |
| **Decomposition result** | `J2KXSDecompositionResult` containing all subbands from a slice DWT |

#### Quantiser (`J2KXSQuantiser`)

| Feature | Description |
|---------|-------------|
| **Actor-based** | Thread-safe quantisation and dequantisation |
| **Uniform scalar** | Configurable step size (Δ) with dead-zone offset (0–1) |
| **Parameters** | `J2KXSQuantisationParameters` — step size and dead-zone expansion factor |
| **Quantised output** | `J2KXSQuantisedCoefficients` — integer coefficients with associated parameters |
| **Mid-point reconstruction** | Dequantisation uses mid-point of quantisation intervals |

#### Entropy Coder and Packetiser (`J2KXSPacketiser`)

| Feature | Description |
|---------|-------------|
| **Entropy modes** | `J2KXSEntropyMode` — `.significanceRange` and `.varianceAdaptive` with packet header IDs |
| **Encoded slices** | `J2KXSEncodedSlice` wrapping component index, slice index, entropy mode, and payload |
| **Packet headers** | `J2KXSPacketHeader` — magic `0xFF10`, component/slice indices, payload length, entropy mode |
| **Binary codestream** | Packs slices into a sequential binary codestream; unpacks back into `J2KXSEncodedSlice` arrays |

#### Encoder (`J2KXSEncoder`)

| Feature | Description |
|---------|-------------|
| **Actor-based** | Full encode pipeline: validate → slice → DWT → quantise → serialise → packetise |
| **Profile validation** | Checks plane count against `J2KXSProfile.maxComponents` |
| **Configurable** | Uses `J2KXSConfiguration` (profile, level, slice height, target bpp) |
| **Pipeline stages** | `J2KXSDWTEngine` → `J2KXSQuantiser` → `J2KXSPacketiser` |
| **Tracking** | `encodedImageCount` for throughput monitoring |

#### Decoder (`J2KXSDecoder`)

| Feature | Description |
|---------|-------------|
| **Actor-based** | Reverse pipeline: unpack → dequantise → inverse DWT → reassemble planes |
| **Codestream input** | Accepts `J2KXSEncodeResult` from the encoder |
| **Reconstruction** | Reassembles per-component planes into a `J2KXSImage` |
| **Tracking** | `decodedImageCount` for throughput monitoring |

### Updated Capabilities

`J2KXSCapabilities.current` updated from exploration to production status:

| Property | v2.2.0 (Phase 19) | v2.3.0 (Phase 20) |
|----------|-------------------|-------------------|
| `isAvailable` | `false` | `true` |
| `supportedProfiles` | `[.light, .main]` | `[.light, .main, .high]` |
| `version` | `"exploration-2.2.0"` | `"2.3.0"` |

---

## Source Files

### New Files

| File | Module | Lines | Description |
|------|--------|-------|-------------|
| `J2KXSImageTypes.swift` | J2KXS | 190 | Pixel formats, image type, error cases, encode/decode result types |
| `J2KXSDWTEngine.swift` | J2KXS | 367 | Slice-based forward and inverse DWT with Haar lifting scaffold |
| `J2KXSQuantiser.swift` | J2KXS | 217 | Uniform scalar quantisation and mid-point dequantisation |
| `J2KXSEntropyCoder.swift` | J2KXS | 253 | Entropy coding modes, encoded slices, packet headers, packetiser actor |
| `J2KXSEncoder.swift` | J2KXS | 216 | Full JPEG XS encode pipeline actor |
| `J2KXSDecoder.swift` | J2KXS | 219 | Full JPEG XS decode pipeline actor |

### Modified Files

| File | Change |
|------|--------|
| `J2KXSTypes.swift` | `J2KXSCapabilities.current` — `isAvailable` set to `true`, `supportedProfiles` extended to `[.light, .main, .high]`, `version` updated to `"2.3.0"` |
| `Package.swift` | Added `J2KXS` library product, `J2KXS` target (depends on `J2KCore`), and `J2KXSTests` test target |

---

## Testing

### New Tests: 52 tests, 0 failures

| Test Suite | Tests | Description |
|-----------|-------|-------------|
| `J2KXSTests` | 52 | Pixel formats, image construction, DWT forward/inverse, quantisation/dequantisation, entropy modes, packet headers, packetiser round-trip, encoder/decoder pipeline, error paths, round-trip encode/decode |

All tests cover:
- Type construction and computed properties
- Actor-based DWT forward and inverse transforms
- Quantisation and mid-point dequantisation accuracy
- Entropy mode packet header IDs
- Codestream packing and unpacking round-trips
- Full encode → decode pipeline round-trips
- Error paths (invalid dimensions, plane count mismatches, empty data)

---

## Package Changes

```swift
// New product
.library(name: "J2KXS", targets: ["J2KXS"])

// New target
.target(name: "J2KXS", dependencies: ["J2KCore"])

// New test target
.testTarget(name: "J2KXSTests", dependencies: ["J2KXS", "J2KCore"])
```

---

## Documentation

### Updated Documentation

- `CHANGELOG.md` — v2.3.0 entry (Phase 20)
- `MILESTONES.md` — Phase 20 marked complete
- `README.md` — Updated with JPEG XS module and v2.3.0 status

---

## Breaking Changes

None. v2.3.0 is fully backward compatible with v2.2.0.

---

## Migration

No migration required. All existing APIs remain unchanged. The new `J2KXS` module is a separate library product that must be explicitly imported.

The `getVersion()` function now returns `"2.3.0"`.

---

## Known Limitations

- The JPEG XS DWT uses a Haar-like lifting scaffold; the full ISO/IEC 21122 multi-level asymmetric wavelet is not yet implemented.
- Entropy coding uses a simplified prefix-code approach; the full JPEG XS rate-control algorithm is not yet integrated.
- The codec does not yet support the bitstream syntax required for interoperability with other JPEG XS implementations.
- **JPEG XS is a separate standard from JPEG 2000.** The `J2KXS` module is included in J2KSwift as a companion codec but may be extracted into a standalone package in a future release.

---

## Requirements

- Swift 6.2 or later
- macOS 15+ / iOS 17+ / tvOS 17+ / watchOS 10+ / visionOS 1+ / Linux / Windows

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "2.3.0")
]
```

---

## What's Next

Phase 21 delivers comprehensive CLI enhancements including 3D volumetric commands, JPIP network streaming, batch processing, and shell completions. See `MILESTONES.md` for details.

---

*J2KSwift is a pure Swift 6 implementation of JPEG 2000 (ISO/IEC 15444).*  
*JPEG XS (ISO/IEC 21122) support is provided as a companion codec.*  
*© 2026 Raster Lab. All rights reserved.*
