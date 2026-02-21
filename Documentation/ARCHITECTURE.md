# J2KSwift Architecture

This document provides a comprehensive overview of the J2KSwift system architecture,
covering module organisation, the concurrency model, performance subsystems, and the
platform abstraction layer.

> **See also**: The DocC article `Sources/J2KCore/J2KCore.docc/Architecture.md` for
> an API-linked version of this content, and `Documentation/CONCURRENCY_AUDIT.md` for
> a detailed audit of actor boundaries and `Sendable` conformances.

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Module Dependency Diagram](#module-dependency-diagram)
3. [Module Descriptions](#module-descriptions)
4. [Concurrency Model](#concurrency-model)
5. [Performance Architecture](#performance-architecture)
6. [Platform Abstraction Layer](#platform-abstraction-layer)
7. [Data Flow](#data-flow)
8. [Key Design Decisions](#key-design-decisions)

---

## System Overview

J2KSwift is a pure Swift 6 implementation of the JPEG 2000 family of standards
(ISO/IEC 15444 Parts 1, 2, 3, and 10). It is structured as a collection of focused
Swift Package Manager modules rather than a monolithic library, so that applications
only link the capabilities they require.

### Goals

- **Correctness** — bit-exact conformance with the ISO/IEC 15444 test vectors.
- **Thread safety** — Swift 6 strict concurrency throughout; no data races.
- **Performance** — hardware acceleration on every supported platform via SIMD,
  Apple Accelerate, Metal, and Vulkan compute.
- **Portability** — identical API surface on macOS, iOS, visionOS, Linux, and Windows;
  platform-specific acceleration is selected automatically at compile time and at runtime.
- **Composability** — modules may be mixed freely; none carry hidden transitive
  dependencies on DICOM libraries, display frameworks, or network stacks.

---

## Module Dependency Diagram

The diagram below shows the compile-time dependency graph. Arrows point from
dependent to dependency (i.e. `A → B` means "A depends on B").

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Applications / SPM consumers                 │
└──────┬──────────┬──────────┬──────────┬──────────┬──────────┬───────┘
       │          │          │          │          │          │
       ▼          ▼          ▼          ▼          ▼          ▼
  J2KCodec   J2KMetal   J2KVulkan  J2KFileFormat  JPIP     J2K3D
       │          │          │          │          │          │
       │          └──────────┘          │          │          │
       │               │                │          │          │
       ▼               ▼                ▼          ▼          ▼
  J2KAccelerate ◄──────────────── J2KCore (foundation) ──────┘
```

### Layered view

```
J2KCore  (foundation – no external dependencies)
  ├─► J2KCodec          (encoding / decoding pipelines)
  │     ├─► J2KAccelerate    (vDSP / vImage / SIMD)
  │     └─► J2KFileFormat    (JP2, JPX, MJ2 box I/O)
  │           └─► JPIP       (interactive streaming protocol)
  ├─► J2KMetal           (Metal GPU acceleration — Apple platforms only)
  ├─► J2KVulkan          (Vulkan GPU acceleration — Linux / Windows)
  └─► J2K3D              (JP3D / volumetric JPEG 2000, Part 10)
```

### Dependency rules

| Rule | Rationale |
|------|-----------|
| No module may depend on its sibling | Prevents circular graphs |
| All modules depend on `J2KCore` | Shared types live in one place |
| `J2KAccelerate` depends only on `J2KCore` | Keeps the SIMD layer portable |
| `J2KMetal` and `J2KVulkan` are parallel alternatives | Runtime dispatch via `J2KGPUBackendSelector` |
| `J2KFileFormat` does not depend on codec stages | Format I/O is independent of transformation pipelines |

---

## Module Descriptions

### J2KCore

**Role**: Foundation layer; no external dependencies beyond the Swift standard library
and Foundation.

**Key public types**:

| Type | Kind | Purpose |
|------|------|---------|
| `J2KImage` | struct | Top-level image container; holds components |
| `J2KComponent` | struct | Single colour channel (Y, Cb, Cr, R, G, B, …) |
| `J2KTile` | struct | Independently compressed rectangular region |
| `J2KCodeBlock` | struct | Smallest independently coded unit (EBCOT) |
| `J2KBuffer` | struct | Copy-on-write byte buffer |
| `J2KConfiguration` | struct | Encoder/decoder parameters |
| `J2KError` | enum | All library error cases |
| `J2KMarker` | enum | JPEG 2000 codestream marker codes |
| `J2KPlatform` | enum | Runtime platform and feature detection |
| `J2KFormat` | enum | File format identifiers (`.jp2`, `.j2k`, `.jpx`, …) |

### J2KCodec

**Role**: Full encoding and decoding pipelines per ISO/IEC 15444-1 and -15 (HTJ2K).

**Key public types**:

| Type | Kind | Purpose |
|------|------|---------|
| `J2KEncoder` | struct | Encodes `J2KImage` to JPEG 2000 codestream |
| `J2KDecoder` | struct | Decodes JPEG 2000 codestream to `J2KImage` |
| `J2KTranscoder` | struct | Converts between JPEG 2000 profiles without full decode |
| `J2KDWT2D` | struct | 2-D discrete wavelet transform (9/7 irreversible, 5/3 reversible) |
| `J2KColorTransform` | struct | ICT and RCT colour transforms |
| `J2KQuantizer` | struct | Scalar and trellis quantisation |
| `J2KRateControl` | struct | PCRD-opt rate–distortion optimisation |

### J2KAccelerate

**Role**: Hardware-accelerated variants of the codec operations.

Provides drop-in replacements for `J2KDWT2D`, `J2KColorTransform`, and
`J2KQuantizer` using:

- **Apple Accelerate** (`vDSP`, `vImage`, `BNNS`) — available on all Apple
  platforms.
- **NEON SIMD** — used automatically on ARM64 (Apple Silicon and Linux/ARM).
- **AVX / AVX-512 SIMD** — used automatically on x86-64 (macOS Intel, Linux, Windows).

`J2KAccelerate` is compiled unconditionally; platform-specific paths are
selected by `#if arch(arm64)` / `#if arch(x86_64)` guards and by
`#if canImport(Accelerate)` for the vDSP/vImage APIs.

### J2KFileFormat

**Role**: Read and write all JPEG 2000 container formats.

| Type | Purpose |
|------|---------|
| `J2KFileReader` | Streaming parser for JP2, J2K, JPX, JPM, and MJ2 files |
| `J2KFileWriter` | Constructs ISO base media file format box trees and writes them |
| `J2KFormatDetector` | Identifies file format from magic bytes / file extension |
| `J2KBoxModel` | Typed representation of JP2 box hierarchy |

The module performs no wavelet or entropy operations; it only handles framing,
marker parsing, and byte-level I/O.

### JPIP

**Role**: JPEG 2000 Interactive Protocol (ISO/IEC 15444-9).

| Type | Kind | Purpose |
|------|------|---------|
| `JPIPClient` | actor | HTTP/WebSocket client; progressive image retrieval |
| `JPIPServer` | actor | Serves JPEG 2000 data with spatial/quality/resolution windowing |
| `JPIPSession` | actor | Session lifecycle, cache management, window negotiation |
| `JPIPCacheManager` | actor | Client-side precinct cache |

All I/O is `async`; network operations use `URLSession` on Apple platforms and
`swift-nio` on Linux.

### J2KMetal

**Role**: GPU-accelerated codec stages for Apple platforms.

| Type | Purpose |
|------|---------|
| `J2KMetalDWT` | DWT / IDWT on Metal compute |
| `J2KMetalQuantizer` | Quantisation / dequantisation on Metal compute |
| `J2KMetalColorTransform` | ICT / RCT on Metal compute |
| `J2KMetalContext` | Device selection and command queue management |

Compiled only when `canImport(Metal)` is true. The module exposes the same
logical interface as `J2KAccelerate` so that `J2KGPUBackendSelector` can
dispatch transparently.

### J2KVulkan

**Role**: GPU-accelerated codec stages for Linux and Windows via Vulkan 1.2+.

| Type | Purpose |
|------|---------|
| `J2KVulkanDWT` | DWT / IDWT via SPIR-V compute shaders |
| `J2KVulkanQuantizer` | Quantisation via SPIR-V compute shaders |
| `J2KVulkanColourTransform` | ICT / RCT via SPIR-V compute shaders |
| `J2KVulkanContext` | Instance, device, and queue management |

Compiled only on Linux and Windows (no Vulkan on Apple platforms; Metal is used
instead).

### J2K3D

**Role**: ISO/IEC 15444-10 (JP3D) volumetric JPEG 2000.

| Type | Purpose |
|------|---------|
| `JP3DEncoder` | Encodes 3-D volumetric data |
| `JP3DDecoder` | Decodes 3-D codestreams |
| `JP3DWaveletTransform` | 3-D separable DWT (adds Z-axis decomposition) |
| `JP3DVolume` | Typed container for voxel data |

---

## Concurrency Model

J2KSwift targets Swift 6 strict concurrency. Enabling `-strict-concurrency=complete`
produces zero warnings and zero errors across the entire codebase.

### Principles

1. **Value types carry no state** — structs and enums are `Sendable` by synthesis;
   they may be freely passed across concurrency domains.
2. **Mutable shared state lives in actors** — any type that owns mutable state
   accessible from multiple tasks is an `actor`, not a `class`.
3. **`@unchecked Sendable` is permitted only for CoW storage** — private storage
   classes that back copy-on-write value types are marked `@unchecked Sendable`
   with documented justification (see `CONCURRENCY_AUDIT.md`).
4. **Long-running operations are `async` and cancellation-aware** — all codec
   pipelines check `Task.isCancelled` at tile boundaries.

### Actor Inventory

The following actors manage mutable shared state across the library:

| Actor | Module | Responsibility |
|-------|--------|----------------|
| `J2KBenchmarkRunner` | J2KCore | Collects and reports benchmark results |
| `J2KPipelineProfiler` | J2KCore | Pipeline stage timing and memory profiling |
| `J2KUnifiedMemoryManager` | J2KCore | Apple Silicon unified memory allocation |
| `J2KMemoryPool` | J2KCore | Buffer pooling and reuse |
| `J2KThreadPool` | J2KCore | Parallel work distribution |
| `J2KThermalStateMonitor` | J2KCore | Thermal state monitoring |
| `J2KAsyncFileIO` | J2KCore | Asynchronous file I/O |
| `JPIPClient` | JPIP | HTTP/WebSocket progressive download |
| `JPIPServer` | JPIP | Interactive image serving |
| `JPIPSession` | JPIP | Window negotiation and session lifecycle |

### Sendable Conformances

All public struct and enum types in `J2KCore` synthesise `Sendable` automatically.
The following types use `@unchecked Sendable` with explicit justification:

| Type | Justification |
|------|---------------|
| `J2KBuffer.Storage` | Private CoW storage; thread safety guaranteed by owning struct |
| `J2KImageBuffer.Storage` | Private CoW storage; thread safety guaranteed by owning struct |
| `J2KSharedBuffer` | Zero-copy slice; immutable after creation |
| `J2KArenaAllocator` | Internal arena; synchronous pointer return required |
| `J2KMemoryMappedFile` | File descriptor lifecycle; Darwin-only |

### Structured Concurrency Integration

Encoding and decoding pipelines integrate with Swift Structured Concurrency:

```swift
// Parallel tile encoding — each tile is an independent child task
try await withThrowingTaskGroup(of: EncodedTile.self) { group in
    for tile in tiles {
        group.addTask {
            try await encoder.encodeTile(tile)
        }
    }
    for try await encoded in group {
        codestream.append(encoded)
    }
}
```

Task cancellation propagates automatically; tile boundaries are checkpoints
where `try Task.checkCancellation()` is called.

### Actor Boundaries Diagram

```
┌─────────────────── Caller (any concurrency domain) ───────────────────┐
│                                                                        │
│  let encoder = J2KEncoder()        ← value type; freely Sendable      │
│  let data = try await encoder.encode(image)  ← async API              │
│                                                                        │
│  ┌─────────── J2KThreadPool (actor) ──────────────────────────────┐   │
│  │  Tile 0 task ──► J2KDWT2D (struct) ──► J2KQuantizer (struct)   │   │
│  │  Tile 1 task ──► J2KDWT2D (struct) ──► J2KQuantizer (struct)   │   │
│  │  Tile N task ──► J2KDWT2D (struct) ──► J2KQuantizer (struct)   │   │
│  └─────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Performance Architecture

### SIMD Paths

The inner loops of the wavelet transform, quantisation, and colour conversion
operations are hand-vectorised using Swift's SIMD types and, where available,
Apple's Accelerate framework.

#### ARM NEON (ARM64)

Compiled when `arch(arm64)` is true. Used on:
- Apple Silicon Macs and iOS/tvOS/visionOS devices
- Linux/ARM64 (Raspberry Pi 4+, AWS Graviton)
- Windows/ARM64

Key operations vectorised with NEON:

| Operation | SIMD width | Throughput gain (vs scalar) |
|-----------|------------|-----------------------------|
| 9/7 lifting steps | SIMD4<Float> | ≈ 3.8× |
| 5/3 lifting steps | SIMD8<Int16> | ≈ 5.2× |
| ICT colour transform | SIMD4<Float> | ≈ 3.6× |
| RCT colour transform | SIMD4<Int32> | ≈ 4.1× |

#### x86 AVX / AVX-512 (x86-64)

Compiled when `arch(x86_64)` is true. Used on:
- Intel and AMD Macs
- Linux/x86-64 (servers, workstations)
- Windows/x86-64

Key operations vectorised with AVX2:

| Operation | SIMD width | Throughput gain (vs scalar) |
|-----------|------------|-----------------------------|
| 9/7 lifting steps | SIMD8<Float> | ≈ 6.2× |
| 5/3 lifting steps | SIMD16<Int16> | ≈ 7.8× |
| ICT colour transform | SIMD8<Float> | ≈ 5.9× |

AVX-512 paths are enabled at runtime when `J2KPlatform.simdLevel` reports
`.avx512`, providing an additional ≈ 1.5× gain over AVX2.

#### Apple Accelerate Framework

When `canImport(Accelerate)` is true, `J2KAccelerate` uses:

- **vDSP** — FFT-based convolution for large kernel operations; vectorised
  floating-point arithmetic for quantisation scaling.
- **vImage** — Colour space conversion (YCbCr ↔ RGB); pixel format resampling.
- **BNNS** — Batch normalisation and convolution used in the neural
  post-processing filter (optional, lossy only).

Accelerate calls are always wrapped in a fallback branch so that the library
compiles and runs correctly on Linux without Accelerate.

### GPU Backends

`J2KGPUBackendSelector` performs runtime dispatch to the best available
backend:

```
J2KGPUBackendSelector
  ├─ canImport(Metal) && MTLDevice.available  →  J2KMetal
  ├─ Vulkan 1.2 device detected              →  J2KVulkan
  └─ (fallback)                              →  J2KAccelerate (CPU + SIMD)
```

Both GPU backends implement the same `J2KGPUBackend` protocol, so the codec
pipeline is unaware of which backend is active.

#### Metal (Apple Platforms)

`J2KMetal` dispatches compute workloads via Metal command queues. Tile
processing is pipelined: while the GPU executes transform pass N, the CPU
prepares entropy coding for pass N-1.

GPU pipeline stages:

```
Colour Transform (Metal)
      │
      ▼
DWT — all levels in a single encoder pass (Metal)
      │
      ▼
Quantisation (Metal)
      │
      ▼
Entropy Coding (CPU — EBCOT is inherently sequential per bit-plane)
```

Performance target: ≥ 500 MP/s (megapixels per second) for lossy encoding
on M2 Pro with 4K images.

#### Vulkan (Linux / Windows)

`J2KVulkan` loads SPIR-V compute shaders at startup and dispatches via Vulkan
compute queues. The shader pipeline mirrors the Metal pipeline.

Performance target: ≥ 300 MP/s on an NVIDIA RTX 3070.

### Memory Architecture

| Technique | Where used | Benefit |
|-----------|-----------|---------|
| Copy-on-write buffers | `J2KBuffer`, `J2KImage` | Free copies until mutation |
| Memory-mapped files | `J2KMemoryMappedFile` | Zero-copy file reading on Darwin |
| Arena allocation | `J2KArenaAllocator` | Eliminates per-tile heap allocations in tight loops |
| Buffer pooling | `J2KMemoryPool` | Reuses tile-sized allocations across frames |
| Zero-copy slices | `J2KBufferSlice` | Subrange views without copying |
| Unified memory (Apple Silicon) | `J2KUnifiedMemoryManager` | Shared CPU/GPU memory; eliminates blit operations |

---

## Platform Abstraction Layer

`J2KPlatform` (in `J2KCore`) is the single point of contact for all
platform-specific runtime information.

### `J2KPlatform` Enum

```swift
public enum J2KPlatform: Sendable {
    case appleSilicon(chip: String)
    case appleIntel
    case linuxARM64
    case linuxX86_64
    case windowsX86_64
    case windowsARM64
    case unknown
}
```

`J2KPlatform.current` returns the detected platform at startup. Subsequent
calls return a cached value; detection is never repeated.

### Feature Detection

`J2KPlatform` also exposes fine-grained feature flags queried at runtime:

| Property | Type | Description |
|----------|------|-------------|
| `simdLevel` | `J2KSIMDLevel` | Highest available SIMD ISA (`.neon`, `.avx2`, `.avx512`, …) |
| `hasUnifiedMemory` | Bool | True on Apple Silicon |
| `hasMetalGPU` | Bool | True when a Metal-capable device is available |
| `hasVulkanGPU` | Bool | True when a Vulkan 1.2-capable device is detected |
| `physicalMemory` | UInt64 | Total physical RAM in bytes |
| `thermalState` | `ProcessInfo.ThermalState` | Current thermal state |

### Conditional Compilation Guards

Platform-specific code uses compile-time guards to ensure zero dead code on
each platform:

```swift
#if canImport(Accelerate)
    // Apple platforms: use vDSP
    import Accelerate
    vDSP_vadd(...)
#else
    // Linux / Windows: use hand-rolled SIMD
    simdAdd(...)
#endif

#if canImport(Metal)
    // Apple platforms: Metal GPU path
    import Metal
    let device = MTLCreateSystemDefaultDevice()
#endif

#if os(Linux) || os(Windows)
    // Vulkan GPU path
    let instance = VulkanInstance()
#endif
```

### Platform Support Matrix

| Platform | Metal | Vulkan | Accelerate | NEON | AVX |
|----------|-------|--------|------------|------|-----|
| macOS 14+ (Apple Silicon) | ✅ | ❌ | ✅ | ✅ | ❌ |
| macOS 14+ (Intel) | ✅ | ❌ | ✅ | ❌ | ✅ |
| iOS 17+ | ✅ | ❌ | ✅ | ✅ | ❌ |
| visionOS 1+ | ✅ | ❌ | ✅ | ✅ | ❌ |
| Linux/ARM64 | ❌ | ✅ | ❌ | ✅ | ❌ |
| Linux/x86-64 | ❌ | ✅ | ❌ | ❌ | ✅ |
| Windows/x86-64 | ❌ | ✅ | ❌ | ❌ | ✅ |

---

## Data Flow

### Encoding Pipeline

```
Raw Image (J2KImage)
       │
       ▼
Colour Transform  — ICT (lossy) or RCT (lossless) via J2KColorTransform
       │
       ▼
Tile Partitioning — J2KTile array; tiles processed in parallel
       │
       ▼
DWT               — 9/7 irreversible (lossy) or 5/3 reversible (lossless)
       │             via J2KDWT2D; levels 1–6 configurable
       ▼
Quantisation      — Scalar deadzone quantiser via J2KQuantizer
       │             (bypassed for lossless)
       ▼
EBCOT Tier-1      — Bit-plane context coding per code block
       │             (HTJ2K: block coder replaced by MEL + VLC)
       ▼
EBCOT Tier-2      — Rate–distortion optimisation (J2KRateControl)
       │             selects coding passes to include per quality layer
       ▼
Packet Formation  — Progression order applied (LRCP, RLCP, RPCL, PCRL, CPRL)
       │
       ▼
Codestream Markers — SOC, SIZ, COD, QCD, SOT, SOD, EOC
       │
       ▼
Container Box     — JP2 file boxes (jP  , ftyp, jp2h, jp2c) via J2KFileFormat
       │
       ▼
Output (Data / file)
```

### Decoding Pipeline

Decoding is the exact reverse of encoding:

```
Input (Data / file)
  → Container parsing (J2KFileFormat)
  → Codestream marker parsing
  → Entropy decoding (EBCOT Tier-1)
  → Dequantisation
  → Inverse DWT (J2KIDWT2D)
  → Inverse colour transform
  → J2KImage
```

---

## Key Design Decisions

For the rationale behind major architectural choices, see the Architecture
Decision Records in `Documentation/ADR/`:

| ADR | Decision |
|-----|----------|
| [ADR-001](ADR/ADR-001-swift6-strict-concurrency.md) | Use Swift 6 strict concurrency |
| [ADR-002](ADR/ADR-002-value-types-cow.md) | Value types with copy-on-write storage |
| [ADR-003](ADR/ADR-003-modular-gpu-backends.md) | Modular GPU backends (Metal + Vulkan) |
| [ADR-004](ADR/ADR-004-no-dicom-dependency.md) | No DICOM library dependencies |
| [ADR-005](ADR/ADR-005-british-english.md) | British English in documentation and comments |

---

## See Also

- `Documentation/CONCURRENCY_AUDIT.md` — detailed actor and `Sendable` audit
- `Documentation/ADR/` — Architecture Decision Records
- `CONTRIBUTING.md` — contribution guidelines including coding style
- `Sources/J2KCore/J2KCore.docc/Architecture.md` — DocC version with API links
