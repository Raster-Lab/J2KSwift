# Changelog

All notable changes to J2KSwift are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.2.0] — 2026-09-15

**Phase 19 — Multi-Spectral JP3D and Vulkan JP3D Acceleration**

### Added
- `JP3DMultiSpectralTypes` — spectral band definitions, wavelength mapping, multi-spectral volume type, and spectral configuration for JP3D multi-spectral/hyperspectral imaging
- `JP3DMultiSpectralEncoder` — actor-based encoder for multi-spectral volumetric data with inter-band prediction and per-band quality layers
- `JP3DMultiSpectralDecoder` — actor-based decoder with selective band loading and spectral pixel classification
- `JP3DSpectralAnalysis` — spectral index computation (NDVI, NDWI, NDBI) and inter-band correlation matrix analysis
- `J2KVulkanJP3DDWT` — Vulkan-accelerated 3D discrete wavelet transform with spectral-axis support, GPU/CPU auto-selection, and transform statistics
- `J2KXSTypes` — JPEG XS (ISO/IEC 21122) exploration types: profiles, levels, slice heights, configuration presets, and capabilities discovery
- 30+ new tests in `JP3DMultiSpectralTests`, `J2KVulkanJP3DDWTTests`, and `J2KXSTypesTests` covering all new types and actors

### Changed
- `VERSION` bumped from `2.1.0` to `2.2.0`
- `getVersion()` now returns `"2.2.0"`
- `README.md` updated with Phase 19 features and v2.2.0 status
- `MILESTONES.md` Phase 19 added and marked complete

## [2.1.0] — 2026-07-15

**Phase 18 — Native macOS GUI Testing Application (J2KTestApp)**

### Added
- `J2KTestApp` — native macOS SwiftUI application with 13 dedicated test screens
- `EncodeView`, `DecodeView`, `RoundTripView` — encoding/decoding workflows with visual comparison
- `ConformanceView`, `InteropView`, `ValidationView` — standards and interoperability dashboards
- `PerformanceView`, `GPUTestView`, `SIMDTestView` — performance profiling screens with live charts
- `JPIPTestView`, `VolumetricTestView`, `MJ2TestView` — streaming and volumetric test screens
- `ReportView` — trend charts, coverage heatmap, and HTML/JSON/CSV export
- `PlaylistView` — named test playlists with preset and custom sections
- Headless CLI mode (`j2k testapp --headless --playlist --output --format`) for CI/CD
- GitHub Actions workflow (`interactive-testing.yml`) for automated headless test runs
- `J2KDesignSystem` — spacing, corner radius, icon size, and typography design tokens
- `WindowPreferences` — `UserDefaults`-backed window size and sidebar selection persistence
- `AboutViewModel` — version, copyright, tagline, repository/docs links, acknowledgements
- `AboutView` — application icon and About screen accessible from Help menu
- `AccessibilityIdentifiers` — string constants for all interactive controls (VoiceOver, UI testing)
- `ErrorStateModel` — identifiable error state with factory methods for common conditions
- `SettingsSceneView` — native macOS `Settings` scene (⌘,)
- 309 tests in `J2KTestAppTests` covering all view models and GUI models
- `Documentation/TESTING_GUIDE.md` — complete guide with Quick Start, Troubleshooting, Extending, Keyboard Shortcuts, Conformance Matrix, Performance Targets, and Glossary sections
- `RELEASE_NOTES_v2.1.0.md`

### Changed
- `VERSION` bumped from `2.0.0` to `2.1.0`
- `getVersion()` now returns `"2.1.0"`
- `README.md` updated with J2KTestApp section, GUI screen table, and v2.1.0 status
- `MILESTONES.md` Phase 18 Week 314–315 marked complete; footer updated



**Major Release — Performance Refactoring & Full ISO/IEC 15444-4 Conformance**

### Added
- Swift 6.2 strict concurrency across all 8 modules with Mutex-based synchronisation
- ARM Neon SIMD optimisation for entropy coding, wavelet lifting, and colour transforms
- Accelerate framework deep integration (vDSP, vImage 16-bit, BLAS/LAPACK)
- Metal GPU compute refactoring with Metal 3 mesh shader support and async compute
- Vulkan GPU compute backend for Linux/Windows with SPIR-V shaders and CPU fallback
- Intel x86-64 SSE4.2/AVX2/FMA SIMD optimisations with runtime CPUID detection
- 304 ISO/IEC 15444-4 conformance tests across Parts 1, 2, 3, 10, and 15
- 165 bidirectional OpenJPEG interoperability tests with performance benchmarking
- Complete CLI toolset: `j2k encode`, `decode`, `info`, `transcode`, `validate`, `benchmark`
- Shell completions for Bash, Zsh, and Fish
- DocC catalogues for all 8 library modules
- 8 usage guides (Getting Started, Encoding, Decoding, HTJ2K, Metal GPU, JPIP, JP3D, DICOM)
- 8 runnable Swift example files
- Architecture Decision Records (ADR-001 through ADR-005)
- `ARCHITECTURE.md`, `CONTRIBUTING.md` updates, `MIGRATION_GUIDE_v2.0.md`
- End-to-end pipeline tests, regression tests, and extended stress tests
- 800+ new tests (2,900+ total)

### Changed
- All NSLock-based synchronisation replaced with `Mutex` for improved safety
- TaskGroup-based pipeline for parallel tile encoding/decoding (1.3–1.8× throughput)
- British English consistency verified across all documentation and help text
- CLI options accept both British and American spellings (dual-spelling support)
- `README.md` updated with v2.0.0 features, badges, and examples

### Performance
- Lossless encode (Apple Silicon): ≥1.5× faster than OpenJPEG
- Lossy encode (Apple Silicon): ≥2.0× faster than OpenJPEG
- HTJ2K encode (Apple Silicon): ≥3.0× faster than OpenJPEG
- Decode — all modes (Apple Silicon): ≥1.5× faster than OpenJPEG
- GPU-accelerated (Apple Silicon + Metal): ≥10× faster than OpenJPEG

See [`RELEASE_NOTES_v2.0.0.md`](RELEASE_NOTES_v2.0.0.md) for the full changelog.

## [1.9.0] — 2026-02-20

**Minor Release — JP3D Volumetric JPEG 2000**

### Added
- JP3D volumetric JPEG 2000 support (ISO/IEC 15444-10)
- 3D wavelet transforms (5/3 Le Gall and 9/7 CDF lifting)
- Metal GPU-accelerated 3D DWT (20–50× speedup)
- HTJ2K integration for volumetric encoding (5–10× faster)
- JPIP 3D streaming with view-dependent progressive delivery
- JP3D encoder and decoder with all 5 progression orders
- ROI decoding for spatial subsets of volumetric data
- 350+ new tests, 9 documentation guides

See [`RELEASE_NOTES_v1.9.0.md`](RELEASE_NOTES_v1.9.0.md) for the full changelog.

## [1.8.0] — 2026-02-19

**Minor Release — Motion JPEG 2000 (MJ2)**

### Added
- Motion JPEG 2000 (MJ2) support (ISO/IEC 15444-3)
- Real-time playback and profile support (Simple/General/Broadcast/Cinema)
- VideoToolbox transcoding integration
- MJ2 frame-level encoding and decoding

See [`RELEASE_NOTES_v1.8.0.md`](RELEASE_NOTES_v1.8.0.md) for the full changelog.

## [1.7.0] — 2026-02-18

**Minor Release — Metal GPU Acceleration**

### Added
- Metal GPU acceleration on Apple Silicon (15–40× performance gains)
- GPU-accelerated wavelet, colour, and ROI transforms
- vImage integration for efficient image format conversion

See [`RELEASE_NOTES_v1.7.0.md`](RELEASE_NOTES_v1.7.0.md) for the full changelog.

## [1.5.0] — 2026-02-17

**Minor Release — SIMD Acceleration & Extended JPIP**

### Added
- SIMD acceleration for ARM64 and x86-64 (2–4× speedup)
- WebSocket JPIP transport with server push
- Session persistence and multi-resolution streaming
- Windows and ARM64 Linux platform support

See [`RELEASE_NOTES_v1.5.0.md`](RELEASE_NOTES_v1.5.0.md) for the full changelog.

## [1.4.0] — 2026-02-18

**Minor Release — JPIP HTJ2K Support**

### Added
- JPIP HTJ2K support with automatic format detection
- On-the-fly transcoding between standard J2K and HTJ2K
- Data bin generation for progressive delivery
- 199 JPIP tests (100% pass rate)

See [`RELEASE_NOTES_v1.4.0.md`](RELEASE_NOTES_v1.4.0.md) for the full changelog.

## [1.3.0] — 2026-02-17

**Major Release — HTJ2K Support**

### Added
- HTJ2K (High-Throughput JPEG 2000) codec support (57–70× faster)
- Lossless transcoding between standard J2K and HTJ2K
- Parallel multi-tile processing
- 100% ISO/IEC 15444-15 conformance

See [`RELEASE_NOTES_v1.3.0.md`](RELEASE_NOTES_v1.3.0.md) for the full changelog.

## [1.2.0] — 2026-02-16

**Minor Release — Critical Bug Fixes**

### Fixed
- MQDecoder position underflow crash
- Enhanced cross-platform support

See [`RELEASE_NOTES_v1.2.0.md`](RELEASE_NOTES_v1.2.0.md) for the full changelog.

## [1.1.1] — 2026-02-15

**Patch Release — Bug Fixes & Optimisations**

### Fixed
- MQ-coder bypass mode synchronisation bug for code blocks ≥32×32
- Optimised lossless decoding (1.85× DWT speedup) with buffer pooling

See [`RELEASE_NOTES_v1.1.1.md`](RELEASE_NOTES_v1.1.1.md) for the full changelog.

## [1.1.0] — 2026-02-14

**Minor Release — Production-Ready Encoder/Decoder**

### Added
- Complete 7-stage encoder and decoder pipelines
- Round-trip encoding and decoding
- vDSP hardware acceleration
- JPIP streaming support
- Multiple encoding presets

See [`RELEASE_NOTES_v1.1.md`](RELEASE_NOTES_v1.1.md) for the full changelog.

## [1.0.0] — 2026-02-07

**Initial Release — Architecture & Core Components**

### Added
- Complete Swift 6.2 JPEG 2000 type system and architecture
- Core codec components (DWT, quantisation, entropy coding, tier-1/tier-2)
- File format support (JP2, J2K box model)
- JPIP protocol framework
- Accelerate framework integration
- 1,600+ unit tests

See [`RELEASE_NOTES_v1.0.md`](RELEASE_NOTES_v1.0.md) for the full changelog.

[2.0.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.9.0...v2.0.0
[1.9.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.5.0...v1.7.0
[1.5.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/Raster-Lab/J2KSwift/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/Raster-Lab/J2KSwift/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Raster-Lab/J2KSwift/releases/tag/v1.0.0
