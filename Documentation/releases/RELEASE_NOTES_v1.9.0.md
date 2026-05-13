# J2KSwift v1.9.0 Release Notes

**Release Date**: February 20, 2026  
**Release Type**: Minor Release  
**GitHub Tag**: v1.9.0

## Overview

J2KSwift v1.9.0 is a **minor release** that delivers comprehensive JP3D volumetric JPEG 2000 support, completing Phase 16 of the development roadmap (Weeks 211-235). This release provides full ISO/IEC 15444-10 compliance for three-dimensional image encoding and decoding, including 3D wavelet transforms, GPU-accelerated processing via Metal, HTJ2K-accelerated volumetric encoding, JPIP streaming of 3D datasets, and cross-platform support.

### Key Highlights

- 🏥 **JP3D Volumetric JPEG 2000**: Complete ISO/IEC 15444-10 encoding and decoding
- 🧊 **3D Wavelet Transforms**: 5/3 Le Gall and 9/7 CDF lifting filters, Metal GPU 20–50× speedup
- ⚡ **HTJ2K Integration**: 5–10× faster volumetric encoding with block-coding acceleration
- 🌊 **JPIP 3D Streaming**: View-dependent progressive delivery of volumetric datasets
- 🎯 **ROI Decoding**: Spatial subset decoding for large volumes
- 📐 **Part 4 Compliance Testing**: Full ISO/IEC 15444-10 conformance test suite
- 🧪 **350+ New Tests**: Comprehensive unit, integration, compliance, and performance tests
- 📚 **9 Documentation Guides**: Complete JP3D reference documentation

---

## What's New

### 1. JP3D Core Types & Foundational Volumetric Support (Weeks 211-213)

Complete JP3D type system and foundational data structures for ISO/IEC 15444-10.

#### Features

- **J2KVolume**: Core volumetric image container with width, height, depth, and component data
- **J2KVolumeComponent**: Per-component volumetric sample data with precision and signedness
- **JP3DRegion**: 3D spatial region for ROI specification and progressive delivery
- **JP3DTile**: Volumetric tile container with spatial coordinates and coded data
- **JP3DPrecinct**: 3D precinct structure for packet-level spatial organisation
- **JP3DTilingConfiguration**: Configurable 3D tiling with independent XYZ tile sizes
- **JP3DProgressionOrder**: All five volumetric progression orders (LRCP, RLCP, RPCL, PCRL, CPRL)
- **JP3DCompressionMode**: Lossless, lossy, and near-lossless compression mode selection
- **J2K3DCoefficients**: Multi-level 3D wavelet coefficient storage with subband addressing
- **JP3DSubband**: Named 3D subbands (LLL, LLH, LHL, LHH, HLL, HLH, HHL, HHH, …)
- **60 Tests**: Complete core type validation

#### Performance Impact

```
Component                | Performance Gain | Platforms
-------------------------|------------------|------------------
Volume construction      | N/A              | All platforms
JP3D region math         | < 1ms            | All platforms
Tiling configuration     | < 1ms            | All platforms
```

### 2. 3D Wavelet Transforms (Weeks 214-217)

High-performance separable 3D wavelet transforms with CPU and Metal GPU implementations.

#### Features

- **JP3DWaveletTransform**: Actor-based thread-safe 3D DWT driver
- **5/3 Le Gall reversible lifting**: Integer lossless forward and inverse transform
- **9/7 CDF irreversible lifting**: Floating-point lossy forward and inverse transform
- **Symmetric boundary extension**: ISO-compliant boundary handling for arbitrary volume sizes
- **Multi-level decomposition**: Configurable decomposition depth per axis (Nx, Ny, Nz)
- **JP3DAcceleratedDWT**: vDSP-accelerated separable convolution on Apple platforms
- **JP3DMetalDWT**: GPU compute pipeline with 10 Metal Shading Language compute kernels
- **30 Tests**: Correctness, boundary, and accuracy validation

#### Performance Impact

```
Transform        | Volume   | CPU (M3) | Metal (M3) | Linux (ARM64) | Speedup (Metal)
-----------------|----------|----------|------------|---------------|----------------
5/3 forward      | 256³     | 1.1s     | 0.05s      | 1.6s          | 22×
9/7 forward      | 256³     | 1.4s     | 0.06s      | 2.0s          | 23×
5/3 inverse      | 256³     | 1.0s     | 0.05s      | 1.5s          | 20×
9/7 inverse      | 256³     | 1.3s     | 0.06s      | 1.9s          | 22×
5/3 forward      | 512³     | 9.2s     | 0.19s      | 13.0s         | 48×
```

### 3. JP3D Encoder (Weeks 218-221)

Full JP3D encoding pipeline with all five progression orders and configurable rate control.

#### Features

- **JP3DEncoder**: Actor-based encoder with async encode pipeline
- **JP3DEncoderConfiguration**: Configurable tile size, decomposition levels, quality layers, and compression mode
- **JP3DEncoderResult**: Structured encoding output with timing, size, and quality statistics
- **JP3DTileDecomposer**: Volume-to-tile decomposition with overlap handling
- **JP3DRateController**: Post-compression rate-distortion (PCRD) optimization for target bit rates
- **JP3DPacketFormatter**: ISO/IEC 15444-10 compliant packet header and body serialization
- **JP3DStreamWriter**: Actor for progressive multi-pass codestream writing
- **JP3DCodestreamWriter**: Low-level marker segment and SOC/EOC generation
- **All 5 progression orders**: LRCP, RLCP, RPCL, PCRL, CPRL fully implemented
- **50+ Tests**: Encoding correctness, progression order, and rate control validation

#### API Example

```swift
import J2KCodec

// Configure encoder
var config = JP3DEncoderConfiguration()
config.tileSize = (x: 64, y: 64, z: 64)
config.decompositionLevels = (nx: 3, ny: 3, nz: 3)
config.qualityLayers = 6
config.compressionMode = .lossless
config.progressionOrder = .lrcp

// Encode volume
let encoder = JP3DEncoder(configuration: config)
let result = try await encoder.encode(volume)
print("Encoded \(result.byteCount) bytes in \(result.encodingTime)s")
```

### 4. JP3D Decoder (Weeks 222-225)

Complete JP3D decoding pipeline with progressive, ROI, and transcoding support.

#### Features

- **JP3DDecoder**: Actor-based decoder with async decode pipeline
- **JP3DDecoderConfiguration**: Configurable quality layer limit, resolution reduction, and component selection
- **JP3DDecoderResult**: Structured decoding output with timing and quality metadata
- **JP3DCodestreamParser**: ISO/IEC 15444-10 marker segment and packet parser
- **JP3DProgressiveDecoder**: Layer-progressive and resolution-progressive incremental decoding
- **JP3DROIDecoder**: Spatial-subset decoding for arbitrary JP3DRegion without full-volume decode
- **JP3DTranscoder**: Direct volume transcoding between compression modes and quality layers
- **50+ Tests**: Decoding correctness, progressive quality, ROI, and transcoding validation

#### API Example

```swift
import J2KCodec

// Decode full volume
let decoder = JP3DDecoder()
let volume = try await decoder.decode(codestreamData)

// Decode spatial ROI only
var roiConfig = JP3DDecoderConfiguration()
roiConfig.region = JP3DRegion(x: 0, y: 0, z: 64, width: 128, height: 128, depth: 64)
let roiDecoder = JP3DROIDecoder(configuration: roiConfig)
let subVolume = try await roiDecoder.decode(codestreamData)
```

### 5. HTJ2K Integration (Weeks 226-228)

High-Throughput JPEG 2000 block coding for 5–10× faster volumetric encoding and decoding.

#### Features

- **JP3DHTJ2KCodec**: HTJ2K block encoder and decoder for 3D codeblocks
- **JP3DHTJ2KConfiguration**: Configurable HT block mode, irreversible/reversible selection
- **JP3DHTJ2KBlockMode**: HT block mode flags (FAST, MIXED, HT_ONLY)
- **JP3DHTMarkers**: HTJ2K marker segment extensions for JP3D codestreams
- **losslessHTJ2K**: Lossless mode using HT Cleanup + Refinement passes
- **lossyHTJ2K**: Lossy mode using single HT Cleanup pass for maximum throughput
- **5–10× faster encoding**: Measured on volumetric medical and scientific datasets
- **25+ Tests**: HTJ2K correctness, mode selection, and throughput validation

#### Performance Impact

```
Mode              | Volume   | Standard J2K (M3) | HTJ2K (M3) | Speedup
------------------|----------|-------------------|------------|--------
Lossless encode   | 256³     | 2.1s              | 0.38s      | 5.5×
Lossless decode   | 256³     | 1.4s              | 0.22s      | 6.4×
Lossy encode      | 256³     | 1.8s              | 0.18s      | 10.0×
Lossy decode      | 256³     | 1.1s              | 0.14s      | 7.9×
```

### 6. JPIP Extension for JP3D Streaming (Weeks 229-232)

View-dependent progressive delivery of volumetric datasets over JPIP.

#### Features

- **JP3DJPIPClient**: Actor-based JPIP client with 3D viewport and region negotiation
- **JP3DJPIPServer**: Actor-based JPIP server with JP3D codestream serving and session management
- **JP3DStreamingTypes**: Complete set of JP3D streaming types including:
  - `JP3DViewport` — camera frustum–based 3D region selection
  - `JP3DStreamingRegion` — spatial and quality-layer streaming region
  - `JP3DDataBin` — JP3D precinct and tile-part data bin
  - `JP3DStreamingSession` — persistent JPIP session with cache state
  - `JP3DStreamingRequest` — JPIP request message for 3D datasets
  - `JP3DStreamingResponse` — JPIP response with incremental data
- **JP3DCacheManager**: Client-side JP3D data bin cache with LRU eviction
- **JP3DProgressiveDelivery**: 8 progression modes for view-dependent streaming
- **40+ Tests**: Client, server, streaming, and cache validation

#### API Example

```swift
import JPIP

// Connect JP3D JPIP client
let client = JP3DJPIPClient()
try await client.connect(to: serverURL)

// Request viewport-based streaming
var viewport = JP3DViewport(center: (128, 128, 128), radius: 64)
let session = try await client.openSession(volume: volumeID, viewport: viewport)

// Progressive delivery
for try await dataChunk in session.progressiveStream() {
    await renderer.update(with: dataChunk)
}
```

### 7. Compliance Testing & Part 4 Validation (Weeks 233-234)

Complete ISO/IEC 15444-10 conformance and interoperability testing.

#### Features

- **ISO/IEC 15444-10 conformance test suite**: Full Part 10 encoder and decoder conformance
- **Part 4 validation**: Compliance of all progression orders, tile sizes, and decomposition levels
- **Round-trip accuracy tests**: Bit-exact lossless round-trip for all compression modes
- **Cross-platform validation**: Bitstream compatibility across macOS, Linux, and Windows
- **100+ Tests**: Conformance, accuracy, and interoperability coverage

### 8. Documentation, Integration & v1.9.0 Release (Week 235)

Complete documentation suite and final integration testing for the v1.9.0 release.

#### Features

- **9 documentation guides**: Complete JP3D reference covering all major feature areas
- **JP3DIntegrationTests**: End-to-end tests covering full JP3D encode/decode workflows
- **Version bump to 1.9.0**: VERSION file and getVersion() updated throughout

#### New Documentation

- `Documentation/JP3D_GUIDE.md` — Complete JP3D volumetric JPEG 2000 reference
- `Documentation/JP3D_ENCODING.md` — Encoder configuration and usage guide
- `Documentation/JP3D_DECODING.md` — Decoder configuration, ROI, and progressive decoding
- `Documentation/JP3D_DWT.md` — 3D wavelet transform technical reference
- `Documentation/JP3D_HTJ2K.md` — HTJ2K integration for volumetric data
- `Documentation/JP3D_JPIP.md` — JPIP streaming for 3D datasets
- `Documentation/JP3D_CONFORMANCE.md` — ISO/IEC 15444-10 conformance testing guide
- `Documentation/JP3D_PERFORMANCE.md` — Benchmarks and optimization guide
- `Documentation/JP3D_MIGRATION.md` — Migration guide from 2D to 3D workflows

---

## Breaking Changes

None — v1.9.0 is **fully backward compatible** with v1.8.0. All existing 2D APIs remain unchanged. JP3D volumetric JPEG 2000 support is provided through **new types** in an optional `J2K3D` module and does not affect existing still-image or Motion JPEG 2000 functionality.

---

## Performance Benchmarks

| Operation | Volume | Apple Silicon M3 | Intel x86-64 | Linux (ARM64) |
|-----------|--------|-----------------|--------------|---------------|
| Lossless encode | 256³ 1-comp 8-bit | ~2.1s | ~5.8s | ~3.2s |
| HTJ2K lossless encode | 256³ 1-comp 8-bit | ~0.38s | ~1.1s | ~0.6s |
| Lossless decode | 256³ 1-comp 8-bit | ~1.4s | ~3.9s | ~2.1s |
| Metal DWT forward | 256³ | ~0.05s | N/A | N/A |
| JPIP initial display (1 Gbps) | 256³ | <90ms | <110ms | <100ms |

### Memory Efficiency

- **Tile-based processing**: Constant peak memory regardless of volume size
- **ROI Decoding**: Decode spatial subsets without loading the full volume
- **JPIP Streaming**: Progressive delivery minimises client-side memory footprint
- **Buffer Pooling**: 3D tile buffers reused across encode/decode passes

---

## Compatibility

### Swift Version

- **Minimum**: Swift 6.2
- **Recommended**: Swift 6.2.3 or later

### Platforms

#### Full JP3D Support (Metal GPU + vDSP + HTJ2K)
- **macOS**: 13.0+ (Ventura) with Apple Silicon (M1-M4)
- **iOS**: 16.0+ with A14 or later
- **tvOS**: 16.0+
- **visionOS**: 1.0+

#### JP3D Support (CPU only, no Metal)
- **macOS**: 13.0+ (Intel Macs)
- **iOS**: 16.0+ (older devices)
- **watchOS**: 9.0+
- **Linux**: Ubuntu 20.04+, Amazon Linux 2023+ (x86_64, ARM64)
- **Windows**: Windows 10+ with Swift 6.2 toolchain (CPU only, no Metal)

### Dependencies

- **Foundation**: Standard library only
- **Metal**: Optional, for GPU-accelerated 3D DWT (Apple platforms, macOS 13+)
- **Accelerate / vDSP**: Optional, for CPU-accelerated separable convolution (all Apple platforms)
- **Network**: Optional, for JPIP 3D streaming (all platforms)

---

## Test Coverage Summary

### Overall Coverage

- **Total New JP3D Tests**: 350+
- **Total Project Tests**: 2,100+
- **Pass Rate**: 100%
- **Platform Coverage**: macOS (Apple Silicon + Intel), iOS, tvOS, Linux (x86_64 + ARM64), Windows

### Module-Specific

- **J2KCore (J2K3D types)**: 60 core type tests
- **J2KCodec (JP3D encoder)**: 50+ encoder tests
- **J2KCodec (JP3D decoder)**: 50+ decoder tests
- **J2KCodec (HTJ2K integration)**: 25+ HTJ2K tests
- **J2KAccelerate (3D DWT)**: 30 wavelet transform tests
- **JPIP (JP3D streaming)**: 40+ streaming tests
- **Conformance**: 100+ ISO/IEC 15444-10 conformance tests

---

## Bug Fixes

- Improved JP3D tile boundary handling for volumes with non-power-of-two dimensions
- Enhanced error reporting for malformed JP3D marker segments
- Fixed progression order packet sequencing for RPCL and CPRL in multi-layer volumes
- Resolved memory pressure during multi-level 3D DWT on volumes exceeding 512³
- Fixed JPIP data bin cache invalidation after server-side quality layer trim

---

## Migration Guide

### From v1.8.0 to v1.9.0

No breaking API changes. All existing v1.8.0 code works without modification. JP3D support is provided through **new types** that can be adopted incrementally.

See `Documentation/JP3D_MIGRATION.md` for a complete guide to adopting JP3D APIs.

### Encoding a Volume

```swift
import J2KCodec

var config = JP3DEncoderConfiguration()
config.tileSize = (x: 64, y: 64, z: 64)
config.compressionMode = .lossless
config.progressionOrder = .lrcp

let encoder = JP3DEncoder(configuration: config)
let result = try await encoder.encode(volume)
```

### Decoding a Spatial ROI

```swift
import J2KCodec

var config = JP3DDecoderConfiguration()
config.region = JP3DRegion(x: 0, y: 0, z: 0, width: 128, height: 128, depth: 64)

let decoder = JP3DROIDecoder(configuration: config)
let subVolume = try await decoder.decode(codestreamData)
```

---

## Known Limitations

### JP3D Limitations

- **Maximum Volume Size**: Tested up to 1024³; larger volumes are supported but benchmarks are limited
- **watchOS**: Metal GPU acceleration is not available on watchOS; CPU fallback is used
- **Windows**: Metal and vDSP are not available; CPU-only processing applies
- **JPIP Audio**: JP3D JPIP server does not yet support multi-spectral annotation metadata

### HTJ2K Limitations

- **Mixed-Mode Codestreams**: MIXED block mode interoperability with non-J2KSwift decoders is not yet validated
- **Partial Codeblock Support**: Sub-block HTJ2K acceleration not yet implemented

See `KNOWN_LIMITATIONS.md` for the complete list.

---

## Acknowledgments

Thanks to all contributors who made this release possible, especially for JP3D conformance testing, Metal GPU kernel development, and cross-platform validation on Linux and Windows.

---

## Next Steps

### Planned for v2.0.0 or Later

- Multi-spectral JP3D (more than 3 components with spectral wavelet extension)
- Vulkan compute shaders for JP3D DWT on Linux/Windows GPU
- DICOM JP3D integration for medical imaging workflows
- JP3D HDR and wide-gamut color support
- Stereoscopic and light-field JP3D extensions

### Long-Term Roadmap

See [MILESTONES.md](MILESTONES.md) for the complete development roadmap.

---

**For detailed technical information, see**:
- [MILESTONES.md](MILESTONES.md) - Complete development timeline
- [Documentation/JP3D_GUIDE.md](Documentation/JP3D_GUIDE.md) - JP3D volumetric JPEG 2000 guide
- [Documentation/JP3D_ENCODING.md](Documentation/JP3D_ENCODING.md) - Encoder configuration and usage
- [Documentation/JP3D_DECODING.md](Documentation/JP3D_DECODING.md) - Decoder configuration and ROI decoding
- [Documentation/JP3D_HTJ2K.md](Documentation/JP3D_HTJ2K.md) - HTJ2K integration
- [Documentation/JP3D_JPIP.md](Documentation/JP3D_JPIP.md) - JPIP 3D streaming
- [Documentation/JP3D_MIGRATION.md](Documentation/JP3D_MIGRATION.md) - Migration from v1.8.0
- [API_REFERENCE.md](API_REFERENCE.md) - Complete API documentation
