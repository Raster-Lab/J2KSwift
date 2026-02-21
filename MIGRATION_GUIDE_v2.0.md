# Migration Guide: v1.9.0 → v2.0.0

## Overview

J2KSwift v2.0.0 is a **major release** focused on performance, conformance, and tooling. It delivers Swift 6.2 strict concurrency across all eight modules, hardware-specific SIMD and GPU optimisations, full ISO/IEC 15444-4 conformance, a complete CLI toolset, and comprehensive documentation.

**Most public APIs are unchanged** — existing encoding and decoding code works without modification. The breaking changes are limited to:

- **Swift 6.2 minimum requirement** (previously Swift 6.0)
- **Strict concurrency mode** enabled across all modules
- **Internal synchronisation** migrated from `NSLock` to `Mutex`

If your project already uses value types for configuration and does not subclass internal types, the upgrade should be straightforward.

---

## Table of Contents

- [Breaking Changes](#breaking-changes)
  - [1. Swift 6.2 Minimum Requirement](#1-swift-62-minimum-requirement)
  - [2. Strict Concurrency Mode](#2-strict-concurrency-mode)
  - [3. Package Dependencies Update](#3-package-dependencies-update)
- [New Modules and Types (Non-Breaking)](#new-modules-and-types-non-breaking)
  - [Concurrency Tuning (J2KCore)](#concurrency-tuning-j2kcore)
  - [ARM Neon SIMD (J2KCodec / J2KAccelerate)](#arm-neon-simd-j2kcodec--j2kaccelerate)
  - [Accelerate Framework Deep Integration](#accelerate-framework-deep-integration)
  - [Metal GPU Compute Improvements](#metal-gpu-compute-improvements)
  - [Vulkan GPU Backend (J2KVulkan)](#vulkan-gpu-backend-j2kvulkan)
  - [Intel x86-64 SIMD (J2KCodec / J2KAccelerate)](#intel-x86-64-simd-j2kcodec--j2kaccelerate)
  - [CLI Tools (J2KCLI)](#cli-tools-j2kcli)
  - [Conformance Testing Infrastructure](#conformance-testing-infrastructure)
  - [OpenJPEG Interoperability](#openjpeg-interoperability)
- [Performance Improvements](#performance-improvements)
- [Documentation Improvements](#documentation-improvements)
- [Step-by-Step Migration](#step-by-step-migration)
- [Common Migration Issues](#common-migration-issues)
- [FAQ](#faq)
- [Getting Help](#getting-help)

---

## Breaking Changes

### 1. Swift 6.2 Minimum Requirement

v1.9.0 required Swift 6.0; v2.0.0 requires **Swift 6.2** (6.2.3 or later recommended).

Update your `Package.swift` swift-tools-version declaration:

**Before (v1.9.0):**

```swift
// swift-tools-version: 6.0
```

**After (v2.0.0):**

```swift
// swift-tools-version: 6.2
```

If you are using Xcode, update to the version that ships with Swift 6.2 or later.

---

### 2. Strict Concurrency Mode

All eight modules now compile under Swift 6.2 **strict concurrency**. This may surface new diagnostics in your code if you pass J2KSwift types across isolation boundaries.

#### Sendable conformance

Value types such as `J2KConfiguration` and `J2KEncoderConfiguration` are already `Sendable` (structs are implicitly `Sendable` when all stored properties are `Sendable`). No changes are needed for typical usage.

If you have custom wrapper types that hold J2KSwift objects and pass them across `Task` or actor boundaries, you may need to add explicit `Sendable` conformance.

**Before (v1.9.0) — implicit, no compiler diagnostic:**

```swift
class MyImageProcessor {
    var config = J2KEncoderConfiguration()

    func process() {
        Task {
            // config captured across isolation boundary — no warning in v1.9.0
            let encoder = J2KEncoder(configuration: config)
            let data = try encoder.encode(image)
        }
    }
}
```

**After (v2.0.0) — compiler requires Sendable safety:**

```swift
// Option A: Use a struct (recommended)
struct MyImageProcessor: Sendable {
    let config = J2KEncoderConfiguration()

    func process() async throws {
        let encoder = J2KEncoder(configuration: config)
        let data = try encoder.encode(image)
    }
}

// Option B: Use an actor for mutable state
actor MyImageProcessor {
    var config = J2KEncoderConfiguration()

    func process() throws {
        let encoder = J2KEncoder(configuration: config)
        let data = try encoder.encode(image)
    }
}
```

#### NSLock replaced with Mutex

All internal synchronisation primitives have been migrated from `NSLock` to `Mutex`. If you subclassed or extended internal types that used `NSLock`, update your code:

**Before (v1.9.0):**

```swift
let lock = NSLock()
lock.lock()
defer { lock.unlock() }
// mutate shared state
```

**After (v2.0.0):**

```swift
let mutex = Mutex(initialValue: state)
mutex.withLock { value in
    // mutate value safely
}
```

> **Note:** `Mutex` is available in the Swift 6.2 standard library (via the `Synchronization` module). It provides better diagnostics and is compatible with strict concurrency checking.

---

### 3. Package Dependencies Update

Update your `Package.swift` dependency to require v2.0.0:

**Before (v1.9.0):**

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/J2KSwift.git", from: "1.9.0")
]
```

**After (v2.0.0):**

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/J2KSwift.git", from: "2.0.0")
]
```

---

## New Modules and Types (Non-Breaking)

All of the features below are **additive** — they do not affect existing APIs and can be adopted incrementally.

### Concurrency Tuning (J2KCore)

New types for advanced concurrency control and profiling:

| Type | Purpose |
|------|---------|
| `J2KConcurrencyLimits` | Configure maximum parallelism for encode/decode pipelines |
| `J2KActorContentionAnalyzer` | Detect and report actor isolation contention hotspots |
| `J2KWorkStealingQueue` | Lock-free work-stealing queue for balanced task distribution |
| `J2KConcurrentPipeline` | Composable concurrent pipeline for multi-stage processing |
| `J2KConcurrencyBenchmark` | Micro-benchmark harness for concurrency overhead measurement |

**Example usage:**

```swift
import J2KCore

// Limit pipeline parallelism to 4 concurrent tiles
let limits = J2KConcurrencyLimits(maxConcurrentTiles: 4)
let pipeline = J2KConcurrentPipeline(limits: limits)

let result = try await pipeline.run { stage in
    stage.add { try encoder.encode(tile1) }
    stage.add { try encoder.encode(tile2) }
    stage.add { try encoder.encode(tile3) }
    stage.add { try encoder.encode(tile4) }
}
```

---

### ARM Neon SIMD (J2KCodec / J2KAccelerate)

SIMD-accelerated entropy coding, wavelet lifting, and colour transforms on ARM64 (Apple Silicon and ARM64 Linux). This is **automatic and transparent** — no API changes required.

The implementation uses `#if arch(arm64)` guards with automatic scalar fallback on non-ARM platforms:

```swift
#if arch(arm64)
    // Neon SIMD vectorised path
    return neonAcceleratedDWT(coefficients)
#else
    // Scalar fallback
    return scalarDWT(coefficients)
#endif
```

You do not need to call any new APIs. If your application runs on Apple Silicon or ARM64 Linux, it will automatically benefit from 2.5–2.7× speedups in core codec operations.

---

### Accelerate Framework Deep Integration

Improved integration with Apple's Accelerate framework (vDSP, vImage, BLAS/LAPACK) on all Apple platforms. This is **automatic** — no API changes required.

Highlights:

- vDSP-accelerated quantisation and dequantisation (3.8–4.2× faster)
- vImage 16-bit↔float conversion for medical imaging (5.3× faster)
- BLAS/LAPACK eigendecomposition for multi-component transform optimisation
- Cache-aligned memory allocation for optimal vDSP throughput

---

### Metal GPU Compute Improvements

Refactored Metal compute pipelines with optimised DWT shaders and reduced register pressure. This is **automatic** for existing Metal users.

Improvements:

- 2× faster 2D DWT and end-to-end pipeline latency
- Metal 3 mesh shader support for M3/M4 GPUs
- Indirect command buffers for GPU-driven multi-tile dispatch
- Async compute with double-buffered submission

**New profiling APIs** are available for performance analysis:

```swift
import J2KMetal

let profiler = J2KMetalProfiler()
let report = try await profiler.captureTimeline(for: encodingTask)
print(report.gpuOccupancy)       // e.g. 0.87
print(report.bottleneck)         // e.g. .memoryBound
```

---

### Vulkan GPU Backend (J2KVulkan)

A new **optional** module providing GPU-accelerated compute on Linux and Windows via SPIR-V shaders. This module is not imported by default.

**Adding the module to your Package.swift:**

```swift
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [
            .product(name: "J2KCodec", package: "J2KSwift"),
            .product(name: "J2KVulkan", package: "J2KSwift"),
        ]
    )
]
```

**Example usage:**

```swift
import J2KCodec
import J2KVulkan

// Select the optimal GPU backend automatically
let backend = try J2KGPUBackend.auto()  // Metal on macOS, Vulkan on Linux

let encoder = J2KEncoder(configuration: config, gpuBackend: backend)
let data = try encoder.encode(image)
```

The Vulkan backend uses `#if canImport(CVulkan)` guards and falls back to CPU automatically on platforms without Vulkan support.

---

### Intel x86-64 SIMD (J2KCodec / J2KAccelerate)

SIMD-accelerated codec operations using SSE4.2, AVX2, and FMA on Intel and AMD processors. This is **automatic and transparent** — no API changes required.

Features include runtime CPUID-based feature detection, cache-oblivious DWT, and NUMA-aware allocation.

> **Note:** x86-64 SIMD code is located in `Sources/*/x86/` directories and is **marked for removal in v3.0** as part of the Apple-first strategy. If you depend on x86-64 performance, plan accordingly.

---

### CLI Tools (J2KCLI)

A new command-line interface module providing production-ready tools for all JPEG 2000 operations:

| Command | Description |
|---------|-------------|
| `j2k encode` | Encode images to JPEG 2000 |
| `j2k decode` | Decode JPEG 2000 codestreams |
| `j2k info` | Inspect codestream structure and metadata |
| `j2k transcode` | Transcode between compression modes and formats |
| `j2k validate` | Validate conformance against ISO/IEC 15444 parts |
| `j2k benchmark` | Run performance benchmarks |

The CLI supports **dual British/American spelling** for flags: `--colour`/`--color`, `--optimise`/`--optimize`, `--serialise`/`--serialize`.

**Example commands:**

```bash
# Encode with lossless compression
j2k encode --input photo.png --output photo.j2k --mode lossless

# Decode with a specific quality layer
j2k decode --input photo.j2k --output photo.png --layer 3

# Inspect codestream structure (JSON output)
j2k info --input photo.j2k --format json

# Validate conformance against Part 1 Class 1
j2k validate --input photo.j2k --part 1 --class 1

# Run benchmarks with CSV output
j2k benchmark --size 4096x4096 --iterations 10 --format csv
```

Shell completions are auto-generated for bash, zsh, and fish.

---

### Conformance Testing Infrastructure

New types in the `J2KConformance` module for ISO/IEC 15444-4 conformance validation:

```swift
import J2KConformance

// Validate a codestream against Part 1 Class 1
let validator = J2KConformanceValidator()
let result = try validator.validate(
    codestream: data,
    part: .part1,
    conformanceClass: .class1
)

print(result.passed)            // true
print(result.testedMarkers)     // [.soc, .siz, .cod, .qcd, ...]
print(result.failures)          // []
```

The conformance runner script `Scripts/run_conformance.sh` is available for CI/CD gating.

---

### OpenJPEG Interoperability

New testing infrastructure for bidirectional validation with the OpenJPEG reference implementation:

- 165 interoperability tests covering format × mode × resolution combinations
- Corrupt codestream generator for robustness testing
- Automated benchmarking suite from 256×256 to 8192×8192

This infrastructure is primarily useful for contributors and library validation; end users benefit from the verified interoperability without needing to adopt any new APIs.

---

## Performance Improvements

v2.0.0 delivers significant performance gains across all platforms:

### Encoding and Decoding Performance vs v1.9.0

| Platform | Lossless Encode | Lossy Encode | HTJ2K Encode | Decode (all modes) |
|----------|----------------|--------------|--------------|-------------------|
| Apple M1 | 1.6× faster | 2.1× faster | 3.2× faster | 1.5× faster |
| Apple M3 | 1.8× faster | 2.4× faster | 3.8× faster | 1.5× faster |
| Apple M4 | 1.9× faster | 2.6× faster | 4.1× faster | 1.5× faster |
| Apple Silicon + Metal | — | — | — | ≥10× faster |
| Intel Xeon (AVX2) | 1.0× (parity) | 1.3× faster | N/A | 1.0× (parity) |

### GPU Compute Performance vs v1.9.0

| Operation | Metal v1.9.0 | Metal v2.0.0 | Improvement |
|-----------|-------------|-------------|-------------|
| 2D DWT forward (4096×4096) | 1.8 ms | 0.9 ms | 2.0× |
| 3D DWT forward (256³) | 50 ms | 28 ms | 1.8× |
| Multi-tile encode (8 tiles) | 12.4 ms | 5.1 ms | 2.4× |
| Pipeline latency (end-to-end) | 18 ms | 9.2 ms | 2.0× |

### Memory Efficiency

- **Cache-aligned allocations**: Aligned buffers for optimal SIMD and vDSP throughput
- **Copy-on-write buffers**: COW semantics for large coefficient arrays, reducing allocations
- **GPU buffer pooling**: Size-bucketed buffer reuse for Metal and Vulkan backends
- **NUMA-aware allocation**: Memory placement respecting NUMA topology on multi-socket systems

---

## Documentation Improvements

v2.0.0 includes a comprehensive documentation overhaul:

- **DocC catalogues** for all 8 modules (J2KCore, J2KCodec, J2KAccelerate, J2KFileFormat, JPIP, J2K3D, J2KCLI, J2KConformance)
- **8 new usage guides** in `Documentation/Guides/` covering Getting Started, Encoding, Decoding, HTJ2K, Metal GPU, JPIP, JP3D, and DICOM integration
- **8 runnable examples** in `Examples/` for all major workflows
- **Architecture Decision Records** (ADRs) in `Documentation/ADR/`
- **British English consistency** across all 109+ documentation files

---

## Step-by-Step Migration

### Step 1: Update Swift Version

Ensure your Swift toolchain is 6.2 or later:

```bash
swift --version
# Swift version 6.2.3 (or later)
```

Update the swift-tools-version in your `Package.swift`:

```swift
// swift-tools-version: 6.2
```

### Step 2: Update Package Dependency

Update the J2KSwift dependency version:

```swift
dependencies: [
    .package(url: "https://github.com/anthropics/J2KSwift.git", from: "2.0.0")
]
```

Then resolve dependencies:

```bash
swift package resolve
```

### Step 3: Fix Sendable Conformance Issues

Build your project and address any new strict concurrency diagnostics:

```bash
swift build 2>&1 | grep -i sendable
```

Common fixes:

- Convert `class` wrappers to `struct` where possible
- Add `Sendable` conformance to types that cross isolation boundaries
- Use `actor` for types with mutable shared state
- Replace `NSLock` with `Mutex` from the `Synchronization` module

### Step 4: Adopt New Features (Optional)

New features are additive and can be adopted at your own pace:

- **Vulkan GPU**: Add `J2KVulkan` to your target dependencies
- **CLI tools**: Build and install the `J2KCLI` executable target
- **Conformance testing**: Import `J2KConformance` for validation workflows
- **Concurrency tuning**: Use `J2KConcurrencyLimits` to control pipeline parallelism

### Step 5: Run Tests

Run your full test suite to verify the migration:

```bash
swift test
```

If you have performance-sensitive code, run benchmarks to confirm the expected speedups:

```bash
swift test --filter Performance
```

---

## Common Migration Issues

### Issue 1: Sendable conformance errors

**Symptom:**

```
error: type 'MyProcessor' does not conform to protocol 'Sendable'
```

**Cause:** A type that captures J2KSwift objects is passed across an isolation boundary (e.g., into a `Task` or to an actor).

**Fix:** Make the type `Sendable` by converting it to a `struct`, ensuring all stored properties are `Sendable`, or using an `actor`:

```swift
// Convert class to struct
struct MyProcessor: Sendable {
    let config: J2KEncoderConfiguration  // struct, already Sendable
}
```

---

### Issue 2: NSLock deprecation warnings

**Symptom:**

```
warning: 'NSLock' is deprecated in favour of 'Mutex'
```

**Cause:** Your code uses `NSLock` for synchronisation. While `NSLock` still compiles, v2.0.0 internal types now use `Mutex` and you may see warnings if you interact with internal synchronisation patterns.

**Fix:** Migrate to `Mutex`:

```swift
import Synchronization

let mutex = Mutex(initialValue: MyState())
mutex.withLock { state in
    state.counter += 1
}
```

---

### Issue 3: Minimum platform version changes

**Symptom:**

```
error: package 'J2KSwift' is using Swift tools version 6.2 which is newer than ...
```

**Cause:** Your Swift toolchain is older than 6.2.

**Fix:** Update your Swift toolchain to 6.2 or later. If using Xcode, update to the version that includes Swift 6.2.

---

## FAQ

### Is v2.0.0 backward-compatible with v1.9.0?

The **public API surface is unchanged** — encoding and decoding code works without modification. The breaking changes are limited to the Swift version requirement (6.2), strict concurrency enforcement, and internal synchronisation primitives. If your code compiles cleanly under Swift 6.2 strict concurrency, the upgrade is seamless.

### Do I need to change my encoding/decoding code?

**No.** The `J2KEncoder`, `J2KDecoder`, `J2KImage`, and `J2KConfiguration` APIs are identical. Existing encode/decode workflows work without modification.

### How do I use the new GPU acceleration?

- **Metal (Apple platforms):** Automatic — no code changes required. v2.0.0 includes optimised shaders that are used transparently.
- **Vulkan (Linux/Windows):** Add `J2KVulkan` as a dependency, then use `J2KGPUBackend.auto()` to select the optimal backend.

### How do I use the CLI tools?

Build the CLI target and run the `j2k` command:

```bash
swift build --product J2KCLI
.build/debug/j2k encode --input photo.png --output photo.j2k --mode lossless
```

Alternatively, install it system-wide:

```bash
swift build -c release --product J2KCLI
cp .build/release/j2k /usr/local/bin/
```

---

## Getting Help

- **Documentation:** [API_REFERENCE.md](API_REFERENCE.md), [GETTING_STARTED.md](GETTING_STARTED.md)
- **Tutorials:** [TUTORIAL_ENCODING.md](TUTORIAL_ENCODING.md), [TUTORIAL_DECODING.md](TUTORIAL_DECODING.md)
- **Troubleshooting:** [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Release Notes:** [RELEASE_NOTES_v2.0.0.md](RELEASE_NOTES_v2.0.0.md)
- **Issues:** [GitHub Issues](https://github.com/anthropics/J2KSwift/issues)
- **Discussions:** [GitHub Discussions](https://github.com/anthropics/J2KSwift/discussions)

---

**Status**: Migration Guide for v1.9.0 → v2.0.0  
**Last Updated**: 2026-02-21
