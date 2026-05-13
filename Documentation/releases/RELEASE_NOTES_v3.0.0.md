# J2KSwift v3.0.0 Release Notes

**Release Date**: 2026-04-18  
**Phase**: Phase 22 — HTJ2K Rate Control, CT Volume Loading & Intel Benchmarking  
**Previous Version**: 2.4.0

---

## Headline Features

v3.0.0 delivers three major capability areas built on top of the comprehensive CLI introduced in v2.4.0:

1. **HTJ2K Rate Control Tuning** — improved throughput and compression quality for High Throughput JPEG 2000 via a major overhaul of the bit-plane coder and context modelling
2. **CT Volume Loading & Real JP3D Viewer** — end-to-end volumetric imaging from DICOM/raw CT data through a fully functional 3D rendering viewer
3. **Intel x86_64 Benchmark Infrastructure** — automated multi-codec benchmarking framework comparing J2KSwift against OpenJPEG, OpenJPH, and Grok across Intel CPU generations

---

## What's New

### HTJ2K Rate Control Improvements

- Tuned rate control delivers more consistent compression ratios at all quality settings
- `J2KBitPlaneCoder` — major performance and correctness overhaul
- `J2KDWT1DOptimized` — significantly expanded optimised 1-D DWT paths (lifting, SIMD)
- `J2KContextModeling` — refined context label assignments for improved entropy coding
- `J2KAcceleratedEncoder` — accelerated encoder path enhancements
- `J2KColorTransform` — additional colour transform paths
- Benchmark validation accuracy improvements documented in `HTJ2K_OPTIMIZATION_REPORT.md`

### CT Volume Loading & Real JP3D Viewer

- Full DICOM/raw CT dataset ingestion via expanded `DICOMSupport.swift`
- Real JP3D volumetric viewer (`VolumetricTestView.swift`) with 3D rendering pipeline
- Medical dataset regression test suite (`Scripts/real_medical_dataset_regression.py`)
- Clinical validation results documented in `VALIDATION_REPORT.md`
- Medical real-data testing plan in `Documentation/medical-real-data-testing-plan.md`

### Intel x86_64 Benchmark Infrastructure

- `Scripts/intel_benchmark.sh` — automated benchmark script
  - Auto-detects Intel CPU specs (generation, core count, SIMD capabilities)
  - Generates synthetic test images from 256×256 to 2048×2048
  - Compares J2KSwift vs OpenJPEG / OpenJPH / Grok
  - Tests lossless and multiple lossy compression rates
  - Outputs CSV data and Markdown report
- `Scripts/multi_codec_benchmark.sh` / `multi_codec_benchmark_v2.sh` — multi-codec benchmark suite
- `HTJ2K_PERFORMANCE.md` — Intel vs Apple M2 performance comparison framework with AVX2/AVX-512 projections
- `BENCHMARK_REPORT.md`, `MULTI_CODEC_BENCHMARK.md`, `PERFORMANCE_RESULTS.md` — detailed benchmark results

### Extended Test Coverage

#### JP3D Tests (new)
| Test Suite | Description |
|-----------|-------------|
| `JP3DIntegrationTests` | End-to-end JP3D encode/decode integration |
| `JP3DMultiSpectralTests` | Multi-spectral volumetric imaging |
| `JP3DStreamingTests` | Streaming JP3D data delivery |
| `JP3DWaveletTests` | 3D wavelet transform verification |

#### JPIP Tests (new)
| Test Suite | Description |
|-----------|-------------|
| `JPIPBandwidthAwareDeliveryTests` | Bandwidth-adaptive delivery |
| `JPIPCacheTests` | Client-side cache behaviour |
| `JPIPClientCacheManagerTests` | Cache manager internals |
| `JPIPClientServerIntegrationTests` | Client-server integration |
| `JPIPDataBinGeneratorTests` | Data-bin generation |
| `JPIPEndToEndTests` | Full JPIP workflow |
| `JPIPHTJ2KSupportTests` | HTJ2K stream delivery over JPIP |
| `JPIPNetworkFrameworkTests` | Network transport layer |
| `JPIPProgressiveStreamingTests` | Progressive image delivery |
| `JPIPServerComponentTests` | Server component isolation |
| `JPIPServerPushTests` | Server-push data delivery |
| `JPIPServerTests` | Server lifecycle |
| `JPIPSessionPersistenceTests` | Session state persistence |
| `JPIPTranscodingServiceTests` | On-the-fly transcoding |
| `JPIPWebSocketTests` | WebSocket transport |

#### Performance Tests (new)
| Test Suite | Description |
|-----------|-------------|
| `OpenJPEGBenchmark` | J2KSwift vs OpenJPEG head-to-head |
| `PerformanceValidationTests` | Pipeline performance regression |

---

## CLI Improvements

- `Encode3D` / `Decode3D` — extended 3D encoding/decoding options
- `Compare` — additional comparison metrics
- `Batch` — improved error handling and progress reporting
- `Convert` — additional format support
- `ImageIO` — extended image I/O including expanded TIFF support
- `DICOMSupport` — full CT volume loading

---

## Documentation

| Document | Description |
|----------|-------------|
| `BENCHMARK_REPORT.md` | Comprehensive benchmark results |
| `MULTI_CODEC_BENCHMARK.md` | Multi-codec comparison results |
| `PERFORMANCE_RESULTS.md` | Detailed performance measurements |
| `VALIDATION_REPORT.md` | Clinical and conformance validation |
| `WAVELET_TRANSFORM.md` | DWT implementation reference |
| `HTJ2K_OPTIMIZATION_REPORT.md` | HTJ2K rate control tuning report |
| `HTJ2K_PERFORMANCE.md` | Intel vs Apple M2 performance guide |
| `Documentation/medical-real-data-testing-plan.md` | Medical dataset testing plan |
| `INTEL_BENCHMARK_GUIDE.md` | Intel benchmark setup and usage |
| `INTEL_QUICK_START.md` | Intel benchmark quick reference |

---

## Breaking Changes

None. v3.0.0 is fully backward compatible with v2.4.0. All existing public APIs remain unchanged.

---

## Migration

No migration required. All existing code and CLI invocations continue to work without modification.

---

## Requirements

- Swift 6.2 or later
- macOS 15+ / iOS 17+ / tvOS 17+ / watchOS 10+ / visionOS 1+ / Linux / Windows

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "3.0.0")
]
```

---

## What's Next

Phase 23 planning is underway. See `MILESTONES.md` for details.
