# Architecture Overview

@Metadata {
    @PageKind(article)
}

An overview of the J2KSwift module architecture, design principles, data flow, and
key JPEG 2000 concepts.

## Module Dependency Graph

J2KSwift is organised into a layered set of modules. Every module depends on
``J2KCore``, the foundation layer that defines shared types, image
representations, configuration, and platform utilities.

```
J2KCore  (foundation – no external deps)
  ├─► J2KCodec        (encoding / decoding pipelines)
  │     ├─► J2KAccelerate   (vDSP / vImage / SIMD)
  │     └─► J2KFileFormat   (JP2, JPX, MJ2 box I/O)
  │           └─► JPIP      (interactive streaming protocol)
  ├─► J2KMetal         (Metal GPU acceleration)
  ├─► J2KVulkan        (Vulkan GPU acceleration)
  └─► J2K3D            (JP3D / volumetric JPEG 2000)
```

- **J2KCore** — ``J2KImage``, ``J2KTile``, ``J2KCodeBlock``, ``J2KError``,
  ``J2KConfiguration``, ``J2KMarker``, ``J2KBuffer``, ``J2KPlatform``.
- **J2KCodec** — ``J2KEncoder``, ``J2KDecoder``, ``J2KTranscoder``, wavelet
  transforms (``J2KDWT2D``), colour transforms (``J2KColorTransform``),
  quantisation (``J2KQuantizer``), and rate control (``J2KRateControl``).
- **J2KAccelerate** — Hardware-accelerated variants of the codec operations
  using the Apple Accelerate framework, with per-architecture SIMD paths for
  ARM (NEON) and x86 (AVX/SSE).
- **J2KFileFormat** — ``J2KFileReader``, ``J2KFileWriter``,
  ``J2KFormatDetector``, and the full JP2 box model.
- **JPIP** — ``JPIPClient``, ``JPIPServer``, progressive streaming, adaptive
  quality, and 3-D streaming.
- **J2KMetal** — ``J2KMetalDWT``, ``J2KMetalQuantizer``,
  ``J2KMetalColorTransform``. Metal shaders for Apple GPUs.
- **J2KVulkan** — ``J2KVulkanDWT``, ``J2KVulkanQuantizer``,
  ``J2KVulkanColourTransform``. SPIR-V compute shaders for Linux and Windows.
- **J2K3D** — ``JP3DEncoder``, ``JP3DDecoder``, ``JP3DWaveletTransform``.
  Volumetric (Part 10) support.

## Design Principles

### Value Types with Copy-on-Write

Most data structures — ``J2KImage``, ``J2KTile``, ``J2KComponent``,
``J2KBuffer`` — are Swift value types (structs). Large backing storage uses
copy-on-write (COW) semantics (see ``J2KCOWBuffer``) so that copies are
virtually free until a mutation occurs.

### Swift 6 Strict Concurrency

Every public type conforms to ``Sendable``. Mutable shared state lives behind
actors (e.g. ``JPIPClient``, ``JPIPServer``). Long-running codec pipelines
are exposed as `async` methods and integrate with Swift structured concurrency
and task cancellation.

### Actor-Based Isolation

Network services, cache managers, and session controllers are implemented as
actors. ``JPIPClientCacheManager`` and ``JPIPServer`` illustrate this pattern:
callers interact through an `async` API and the actor serialises internal
mutations automatically.

### Platform Abstraction

``J2KPlatform`` provides runtime feature detection (SIMD level, thermal state,
available memory). Conditional imports (`#if canImport(Accelerate)`,
`#if canImport(Metal)`) ensure that platform-specific code is only compiled
where it is supported.

## Data Flow — Encoding Pipeline

The encoding path follows the standard JPEG 2000 Part 1 processing order:

```
Raw Image
  │
  ▼
Colour Transform  (ICT / RCT via J2KColorTransform)
  │
  ▼
Wavelet Transform (DWT 9/7 or 5/3 via J2KDWT2D)
  │
  ▼
Quantisation      (scalar / trellis via J2KQuantizer)
  │
  ▼
Entropy Coding    (EBCOT Tier-1 & Tier-2, HTJ2K block coder)
  │
  ▼
Rate Control      (PCRD optimisation via J2KRateControl)
  │
  ▼
Codestream        (markers + packets → JP2 / J2K output)
```

Decoding reverses every stage: codestream parsing → entropy decoding →
dequantisation → inverse wavelet → inverse colour transform.

## GPU Acceleration Strategy

J2KSwift selects the best available GPU back-end at run time via
``J2KGPUBackendSelector``:

| Platform            | Back-end           | Module          |
|---------------------|--------------------|-----------------|
| macOS / iOS / visionOS | Metal 3 / Metal  | ``J2KMetal``    |
| Linux / Windows     | Vulkan 1.2+        | ``J2KVulkan``   |
| Any (fallback)      | CPU + SIMD         | ``J2KAccelerate`` |

Both GPU modules expose the same logical operations — DWT, colour transform,
quantisation — behind a common capability model so that the codec pipeline can
dispatch transparently.

## Key JPEG 2000 Concepts

- **Tile** (``J2KTile``) — A rectangular region of the image that is
  compressed independently. Tiling enables parallel encoding and partial
  decoding.
- **Component** (``J2KComponent``) — A single colour channel (e.g. red, green,
  blue, or luminance).
- **Decomposition Level** — One stage of the discrete wavelet transform. Each
  level halves the resolution and produces four subbands (LL, LH, HL, HH).
- **Subband** (``J2KSubband``) — A frequency band within a decomposition level
  (e.g. the horizontally-detailed LH subband).
- **Precinct** (``J2KPrecinct``) — A spatial partition of a subband that groups
  code blocks for packet formation. Precincts control the spatial granularity
  of progressive delivery.
- **Code Block** (``J2KCodeBlock``) — The smallest independently coded unit.
  Each code block is entropy-coded by the EBCOT block coder and produces a set
  of coding passes that can be truncated for rate control.
- **Quality Layer** — A collection of coding-pass contributions across all code
  blocks. Adding more layers improves image quality.
- **Progression Order** (``J2KProgressionOrder``) — Determines the order in
  which packets are arranged in the codestream (e.g. layer–resolution–
  component–position).

## See Also

- <doc:GettingStarted>
- <doc:MigrationGuide>
