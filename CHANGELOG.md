# Changelog

All notable changes to J2KSwift are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [5.1.0] — 2026-04-24

**Minor Release — HTJ2K `.conformant` round-trip + UVLC bug fix**

### Added
- `DecoderConfiguration.htj2kBlockFormat` — internal field set by parsing a J2KSwift-private `COM` marker in the main header.
- `HTBlockFormatCOMSignature.conformant` — shared `"J2KSWIFT-HT:conformant"` ASCII signature used by the encoder to flag Part-15 codestreams and by the decoder to recognize them.
- `writeHTBlockFormatCOM` / `parseHTBlockFormatCOM` helpers in the encoder / decoder pipelines.
- `J2KHTConformantSelfRoundTripTests` — 10 tests covering 4×4 through 32×32 code blocks, uniform and noise, both block formats, plus an OpenJPH interop probe.

### Changed
- Decoder pipeline block-decode dispatch (parallel and sequential paths) routes to `HTBlockDecoder.decodeCleanupConformant(rawBytes:missingMSBs:)` when the codestream carries the COM signature; otherwise continues to use the legacy `.custom` decoder.
- `VERSION` bumped from `5.0.0` to `5.1.0`.

### Fixed
- v5.0 decoder pipeline could not decode its own `.conformant` HTJ2K output — block dispatch unconditionally called the v4.x custom-format decoder.
- `HTBlockDecoderConformant` UVLC pair decode was interleaved (`pre0, suf0, pre1, suf1`) but the encoder writes `pre0, pre1, suf0, suf1`; the mismatch desynced the VLC stream and garbled samples whenever any quad had `u_q > 2`. Both `decodeUVLCPairInitial` and `decodeUVLCPairSubsequent` now mirror the encoder's emission order.
- Initial-row UVLC `u_q0 > 2 && u_q1 > 0` branch now reads `u_q1`'s 1-bit marker before `suf0`, matching `J2KHTConformantBlockEncoder.swift:224-227`.
- `writeQCDMarker` reversible branch now gates its Part-15 epsilon bias on `config.useHTJ2K` as well as `htj2kBlockFormat == .conformant`, preventing the bias from leaking into legacy EBCOT encodes when a caller sets `.conformant` without enabling HTJ2K.

### Known limitations
- Default `J2KEncodingConfiguration.htj2kBlockFormat` stays `.custom`. Flipping to `.conformant` awaits a fix for a pre-existing non-power-of-2 subband geometry issue in the shared Part-15 block coder (confirmed with `ojph_expand` decoding the same bytes, so the bug is upstream of decoder dispatch). Tracked for v5.1.1.
- 8-bit reversible `.conformant` encodes of pixel value 0 decode back as 128 — `|DC-shift(0)| = 128 = 2^7` overflows the 7-bit magnitude range signaled by `K_max = 7`. OpenJPH has identical behavior.
- Fused MEL/VLC terminate byte optimization (~1 byte/block) and SIMD block coder (SSSE3/AVX2/AVX512) not yet applied.

## [5.0.0] — 2026-04-24

**Major Release — HTJ2K Part-15 conformance (encoder-side)**

### Added
- `J2KEncodingConfiguration.htj2kBlockFormat: HTBlockFormat` — new encoder flag selecting `.custom` (v4.x private) or `.conformant` (ISO/IEC 15444-15) HT block wire format.
- `HTBlockEncoderConformant`, `HTBlockDecoderConformant` — scalar Part-15 block coder port from OpenJPH 0.26.
- 82 block-level conformant tests + 3 end-to-end OpenJPH cross-codec tests.
- `CAP` (0xFF50) and `CPF` (0xFF63) marker emission for HTJ2K codestreams.

### Changed
- `writeQCDMarker` reversible branch emits `SPqcd = (B + G - guardBits) << 3` when `htj2kBlockFormat == .conformant` to match OpenJPH's encoder convention.
- `VERSION` bumped from `4.0.0` to `5.0.0`.

### Known limitations (addressed in 5.1.0)
- Decoder-side Part-15 block dispatch pending; reading J2KSwift-produced `.conformant` codestreams back through J2KSwift's own decoder was not supported in 5.0.0.
- `.custom` remained the default `htj2kBlockFormat` in 5.0.0.

## [4.0.0] — 2026-04-24

**Major Release — Medical-grade production readiness**

### Added
- `J2KComponent.ByteOrder` — new public `Sendable` enum (`.littleEndian`, `.bigEndian`)
- `J2KComponent.sampleByteOrder: ByteOrder?` property and init parameter for deterministic 16-bit sample byte-order handling
- `J2KCodeBlock.quantizationStep: Double?` public getter used by PCRD
- `testHDRAndColorCoverage` — 19 configurations (8/10/12/14/16-bit × grayscale/RGB at 512²–2048²)
- `testDICOMWholeSlideImaging` — 10 tile configurations (256²–4096² at 8/16-bit RGB) with synthetic H&E pathology generator, lossless round-trip and lossy rate-distortion measurement
- `testHTJ2KvsOpenJPH` — 7 configurations benchmarking HTJ2K path against OpenJPH
- `testDecodeHotspotProfile` — per-configuration decode timing with 10-run medians (including 256² lossy configs)

### Changed
- PCRD subband weights derived from theoretical 9/7 L2 norms × stepsize² with HVS-aware refinement across resolution levels
- HVS subband refinement (LL×1.25, HH×0.55, etc.) now applies to multi-component lossy (RGB) as well as grayscale
- 16-bit byte-order inferencer uses a strided 4096-sample sweep and defaults to big-endian on tie, restoring correct MG/MR modality output
- IDWT: skip-memset optimization on multi-level 9/7 and 5/3 inverse transforms when all cells are written
- WSI lossy-RGB benchmark OpenJPEG ratio formula corrected from `24 / (bpp * 3)` to `24 / bpp`, removing a phantom 3–8 dB PSNR deficit in benchmark output
- DICOMKit Phase 1 integration regressions addressed
- `J2KCore` and `J2KCodec` release builds enable `-O -whole-module-optimization`
- `VERSION` bumped from `3.0.1` to `4.0.0`

### Fixed
- 1024²+ 16-bit lossless corruption where the heuristic byte-order inferencer tied between LE/BE interpretations
- MG/MR modality byte-order inferencer scope (was too narrow on strided samples)

### Known limitations
- HTJ2K block format in this release is a non-standard custom layout used by the J2KSwift fast path; not bit-compatible with OpenJPH or other Part-15 conformant decoders. Full Part-15 conformance is tracked as a follow-up work item.
- 256² lossy decode is ~0.73× of OpenJPEG in absolute throughput (1.36 ms median vs ~1.0 ms); the gap is in the Swift MQ-coder hot loop and is not addressed in this release.

## [3.0.1] — 2026-04-18

**Patch Release — Version bump to 3.0.1**

### Changed
- `VERSION` bumped from `3.0.0` to `3.0.1`

## [3.0.0] — 2026-04-18

**Phase 22 — HTJ2K Rate Control, CT Volume Loading & Intel Benchmarking**

### Added
- CT volume loading with real DICOM/raw data support in `DICOMSupport.swift`
- Real JP3D volumetric viewer in `VolumetricTestView.swift` (full 3D rendering pipeline)
- Intel x86_64 benchmark infrastructure (`Scripts/intel_benchmark.sh`)
- Intel vs Apple M2 performance comparison framework (`HTJ2K_PERFORMANCE.md`)
- Comprehensive multi-codec benchmark suite (`Scripts/multi_codec_benchmark.sh`, `Scripts/multi_codec_benchmark_v2.sh`)
- Real medical dataset regression testing (`Scripts/real_medical_dataset_regression.py`)
- Extended test suites: JP3D integration, multi-spectral, streaming, wavelet tests
- JPIP extended test coverage: bandwidth-aware delivery, cache, client-server integration, HTJ2K support, network framework, progressive streaming, server push, session persistence, WebSocket transport
- OpenJPEG benchmark comparisons (`Tests/PerformanceTests/OpenJPEGBenchmark.swift`)
- Performance validation test suite (`Tests/PerformanceTests/PerformanceValidationTests.swift`)
- GitHub issue templates and agent configuration files
- `BENCHMARK_REPORT.md`, `MULTI_CODEC_BENCHMARK.md`, `PERFORMANCE_RESULTS.md`, `VALIDATION_REPORT.md`, `WAVELET_TRANSFORM.md`
- `Documentation/medical-real-data-testing-plan.md`

### Changed
- HTJ2K rate control tuned for improved throughput and compression quality
- `J2KBitPlaneCoder.swift` — major overhaul for performance and correctness
- `J2KDWT1DOptimized.swift` — significantly expanded optimised 1-D DWT paths
- `J2KDecoderPipeline.swift` — decoder pipeline improvements
- `J2KContextModeling.swift` — context modelling refinements
- `J2KAcceleratedEncoder.swift` — accelerated encoder enhancements
- `J2KColorTransform.swift` — additional colour transform paths
- `DICOMSupport.swift` — expanded DICOM support with CT volume loading
- `Encode3D.swift` / `Decode3D.swift` — 3D CLI enhancements
- `Compare.swift`, `Batch.swift`, `Convert.swift` — CLI improvements
- `ImageIO.swift` — extended image I/O
- `TIFFSupport.swift` — TIFF support improvements
- `CodecService.swift` — test app codec service updates
- `VolumetricTestView.swift` — fully implemented 3D viewer
- `VERSION` bumped from `2.4.0` to `3.0.0`

### Fixed
- HTJ2K benchmark validation accuracy improvements
- DWT round-trip fidelity refinements
- Codec integration test reliability

## [2.4.0] — 2027-03-30

**Phase 21 — Comprehensive CLI Enhancement**

### Added
- `encode3d` command for compressing volumetric / 3D data to JP3D format
- `decode3d` command for decompressing JP3D volumes to slices or raw binary
- `jpip server` command for JPIP streaming with session management and graceful shutdown
- `jpip client` command with single-request and interactive modes for JPIP streaming
- `batch` command for parallel encoding, decoding, and transcoding of entire directories
- `compare` command for image comparison with PSNR, SSIM, and MSE metrics
- `convert` command for converting between image formats (PGM, PPM, raw, JP2, J2K, JPH)
- `completions` command for generating shell completions (Bash, Zsh, Fish)
- `Encode3D.swift` — 3D volumetric encoding command (239 lines)
- `JPIPClient.swift` — JPIP client with interactive mode (277 lines)
- `JPIPServer.swift` — JPIP server with signal handling (172 lines)
- `MultiFileProcessor.swift` — parallel batch file processing engine (342 lines)
- `MemoryHandle` Sendable struct in `J2KUnifiedMemoryManager` for safe cross-actor memory handle transfer
- 193 new CLI tests across 18 test suites (0 failures)
- Documentation: CLI_REFERENCE.md, CLI_JPIP_GUIDE.md, CLI_3D_GUIDE.md, CLI_BATCH_GUIDE.md, CLI_CROSS_LIBRARY_SYNTAX.md

### Changed
- Enhanced `encode` with `--htj2k` / `--format jph` shortcuts and multi-spectral support
- Enhanced `decode` with region-of-interest, component selection, and marker inspection
- Enhanced `transcode` with lossless J2K ↔ HTJ2K and `--lossless` flag
- Enhanced `info` with JP3D metadata and JPIP capability reporting
- Enhanced `validate` with `--strict` mode, JP3D and HTJ2K validation
- Enhanced `benchmark` with JPIP and 3D volumetric benchmarking modes
- Redesigned `J2KUnifiedMemoryManager` to use `MemoryHandle` instead of raw `UnsafeMutableRawPointer` for Swift 6 Sendable compliance
- `VERSION` bumped from `2.3.0` to `2.4.0`
- `MILESTONES.md` Phase 21 added and marked complete

## [2.3.0] — 2026-11-29

**Phase 20 — JPEG XS Core Codec**

### Added
- New `J2KXS` module — foundational JPEG XS (ISO/IEC 21122) codec library
- `J2KXSImageTypes` — `J2KXSPixelFormat` (5 formats with `planeCount`), `J2KXSImage` (planar image with dimension clamping), `J2KXSError` (5 error cases), `J2KXSEncodeResult`, `J2KXSDecodeResult`
- `J2KXSDWTEngine` actor — slice-based forward and inverse DWT with Haar lifting scaffold, orientation subbands (`J2KXSDWTOrientation`), `J2KXSSubband`, `J2KXSDecompositionResult`
- `J2KXSQuantiser` actor — uniform scalar quantisation and mid-point dequantisation with configurable step size and dead-zone offset (`J2KXSQuantisationParameters`, `J2KXSQuantisedCoefficients`)
- `J2KXSPacketiser` actor — packs/unpacks encoded slices (`J2KXSEncodedSlice`) into a binary codestream with per-slice `J2KXSPacketHeader` (magic `0xFF10`); supports both `significanceRange` and `varianceAdaptive` entropy modes
- `J2KXSEncoder` actor — full slice pipeline: validates profile and plane count, runs per-component slice DWT → quantise → serialise → packetise
- `J2KXSDecoder` actor — unpacks codestream, dequantises, applies inverse DWT, and reassembles component planes
- 52 new tests in `Tests/J2KXSTests/J2KXSTests.swift` covering all types, actors, error paths, and round-trip encode/decode

### Changed
- `J2KXSCapabilities.current` — `isAvailable` updated to `true`, `supportedProfiles` extended to include `.high`, `version` updated to `"2.3.0"`
- `Package.swift` — added `J2KXS` library product, target, and `J2KXSTests` test target
- `VERSION` bumped from `2.2.0` to `2.3.0`
- `MILESTONES.md` Phase 20 added and marked complete

## [2.2.0] — 2026-10-01

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

[2.4.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/Raster-Lab/J2KSwift/compare/v2.0.0...v2.1.0
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
