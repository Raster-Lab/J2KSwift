# J2K Compression Studio — Plan & Milestones

**Last Updated**: March 30, 2026
**Status**: Planning
**Target Version**: v3.0.0
**Prerequisite**: J2KSwift v2.3.0+ (current)

---

## Executive Summary

The **J2K Compression Studio** is a planned application layer built on top of J2KSwift
that provides a complete, production-ready DICOM JPEG 2000 codec toolkit. While
J2KSwift is intentionally DICOM-independent (it implements ISO/IEC 15444 only),
the Codec Studio adds the DICOM-aware convenience layer that medical imaging
vendors, PACS developers, and clinical software teams need to integrate JPEG 2000
compression into their DICOM pipelines with minimal effort.

### Goals

1. **Zero-configuration DICOM codec** — accept a DICOM dataset, return compressed
   pixel data (or vice versa), with all Transfer Syntax negotiation handled
   automatically.
2. **Full Transfer Syntax coverage** — support all five JPEG 2000 Transfer
   Syntaxes defined in DICOM PS3.5 (`.90`, `.91`, `.201`, `.202`, `.203`).
3. **Validation & conformance** — built-in DICOM pixel-data validation, bit-depth
   checks, photometric interpretation mapping, and round-trip fidelity tests.
4. **Streaming & batch processing** — efficient multi-frame encoding/decoding,
   JPIP integration for progressive retrieval, and batch CLI tooling.
5. **Cross-platform** — macOS, Linux (x86_64 + ARM64), with optional Metal/Vulkan
   GPU acceleration.

---

## Architecture

```
┌──────────────────────────────────────────────────────┐
│               J2K Compression Studio                 │
│  ┌──────────────┐  ┌────────────┐  ┌──────────────┐ │
│  │ DICOMCodec   │  │ Validation │  │ CLI / Batch  │ │
│  │   Manager    │  │   Engine   │  │   Processor  │ │
│  └──────┬───────┘  └─────┬──────┘  └──────┬───────┘ │
│         │                │                │          │
│  ┌──────┴────────────────┴────────────────┴───────┐  │
│  │          Transfer Syntax Router                │  │
│  │  (.90  .91  .201  .202  .203)                  │  │
│  └──────────────────┬─────────────────────────────┘  │
│                     │                                │
├─────────────────────┼────────────────────────────────┤
│  J2KSwift Engine    │                                │
│  ┌─────────┐  ┌─────┴────┐  ┌───────────┐           │
│  │J2KCodec │  │J2KAccel. │  │ JPIP      │           │
│  │Encoder/ │  │DWT/Color │  │ Streaming │           │
│  │Decoder  │  │Metal/GPU │  │ Client    │           │
│  └─────────┘  └──────────┘  └───────────┘           │
└──────────────────────────────────────────────────────┘
```

---

## Transfer Syntax Support Matrix

| UID | Name | Direction | Priority |
|-----|------|-----------|----------|
| `1.2.840.10008.1.2.4.90`  | JPEG 2000 Lossless            | Encode + Decode | P0 (Phase 1) |
| `1.2.840.10008.1.2.4.91`  | JPEG 2000 Lossy               | Encode + Decode | P0 (Phase 1) |
| `1.2.840.10008.1.2.4.201` | HTJ2K Lossless                | Encode + Decode | P0 (Phase 1) |
| `1.2.840.10008.1.2.4.202` | HTJ2K Lossy                   | Encode + Decode | P0 (Phase 1) |
| `1.2.840.10008.1.2.4.203` | HTJ2K Lossless RPCL           | Encode + Decode | P0 (Phase 1) |

---

## Milestones

### Phase 1 — Core Codec Manager (Weeks 1–6)

**Goal**: Build the central `DICOMCodecManager` that maps DICOM metadata to
J2KSwift encoding/decoding configurations and handles all five Transfer Syntaxes.

#### Week 1–2: Transfer Syntax Router

- [ ] Define `DICOMTransferSyntax` enum with all five JPEG 2000 UIDs
- [ ] Implement `TransferSyntaxRouter` that selects the correct
      `J2KEncodingConfiguration` based on the requested TS
- [ ] Map DICOM Photometric Interpretation → `J2KColorSpace`
- [ ] Map BitsAllocated / BitsStored / HighBit → `J2KComponent.bitDepth`
- [ ] Map PixelRepresentation → `J2KComponent.signed`
- [ ] Unit tests for all TS routing paths (≥ 20 tests)

#### Week 3–4: DICOMCodecManager API

- [ ] Design public `DICOMCodecManager` API:
  - `encode(pixelData:metadata:transferSyntax:) throws -> Data`
  - `decode(compressedData:transferSyntax:) throws -> DICOMPixelResult`
  - `transcode(from:to:data:) throws -> Data`
- [ ] Implement single-frame encode path (grayscale + RGB)
- [ ] Implement single-frame decode path
- [ ] Handle signed pixel data (CT Hounsfield units, PET SUV)
- [ ] Handle high bit-depth data (12-bit, 16-bit)
- [ ] Unit tests for encode/decode round-trip (≥ 30 tests)

#### Week 5–6: Multi-Frame Support

- [ ] Implement multi-frame (cine) encoding — per-frame J2K compression
- [ ] Implement multi-frame decoding with frame indexing
- [ ] Support NumberOfFrames > 1 with encapsulated pixel data framing
- [ ] Add parallel multi-frame encoding (using Swift concurrency)
- [ ] Performance benchmark: multi-frame throughput (target: ≥ 30 fps @ 512×512)
- [ ] Integration tests with synthetic multi-frame datasets (≥ 15 tests)

**Phase 1 Exit Criteria**:
- All five Transfer Syntaxes encode and decode correctly
- Round-trip fidelity: lossless modes produce bit-exact output
- ≥ 65 unit/integration tests, 100% pass rate

---

### Phase 2 — Validation & Conformance Engine (Weeks 7–12)

**Goal**: Build a validation layer that catches DICOM pixel-data errors before
they reach the codec and verifies output conformance.

#### Week 7–8: Input Validation

- [ ] Validate pixel data length vs Rows × Columns × SamplesPerPixel × (BitsAllocated / 8)
- [ ] Check BitsStored ≤ BitsAllocated
- [ ] Validate HighBit = BitsStored − 1 (most common case)
- [ ] Check Photometric Interpretation compatibility with SamplesPerPixel
- [ ] Validate PlanarConfiguration for multi-component images
- [ ] Produce structured `DICOMValidationReport` with warnings and errors
- [ ] Unit tests for every validation rule (≥ 25 tests)

#### Week 9–10: Output Conformance

- [ ] Verify encoded codestream starts with SOC marker (0xFF4F)
- [ ] Validate SIZ marker parameters match DICOM metadata
- [ ] Check progression order matches TS requirements (RPCL for `.203`)
- [ ] Verify lossless modes produce reversible (5/3) wavelet
- [ ] Verify lossy modes produce irreversible (9/7) wavelet
- [ ] Round-trip validation: decode encoded data, compare to original
- [ ] Conformance tests against DICOM WG-04 test images (≥ 20 tests)

#### Week 11–12: Bit-Depth & Color Conformance

- [ ] Test all supported bit depths: 8, 10, 12, 16 (unsigned + signed)
- [ ] Test color space round-trips: MONOCHROME1/2, RGB, YBR_FULL, YBR_ICT, YBR_RCT
- [ ] Verify ICT/RCT is applied correctly per Transfer Syntax
- [ ] Edge-case testing: 1×1 images, max-size images, empty frames
- [ ] Generate conformance report (markdown + JSON)
- [ ] Documentation: conformance matrix and known limitations

**Phase 2 Exit Criteria**:
- Zero false negatives in validation (no invalid data passes through)
- Conformance report covers all five TS × all bit depths × all color spaces
- ≥ 45 additional tests, cumulative ≥ 110 tests

---

### Phase 3 — JPIP Integration for DICOM (Weeks 13–18)

**Goal**: Enable progressive retrieval of DICOM JPEG 2000 images via JPIP,
supporting both legacy J2K and HTJ2K codestreams.

#### Week 13–14: JPIP-DICOM Bridge

- [ ] Create `DICOMJPIPAdapter` that wraps `JPIPClient` with DICOM metadata
- [ ] Map DICOM Window/Level to JPIP quality layers
- [ ] Map DICOM frame numbers to JPIP view windows
- [ ] Support JPIP session creation with Transfer Syntax negotiation
- [ ] Unit tests for adapter logic (≥ 15 tests)

#### Week 15–16: Progressive Decoding

- [ ] Implement progressive decode callback for rendering partial images
- [ ] Support resolution-level progressive retrieval (thumbnail → full-res)
- [ ] Support quality-layer progressive retrieval (low quality → diagnostic)
- [ ] Add JPIP prefetch hints based on DICOM Series metadata
- [ ] Integration tests with mock JPIP server (≥ 15 tests)

#### Week 17–18: Multi-Frame Streaming

- [ ] Stream individual frames from multi-frame DICOM via JPIP
- [ ] Implement frame-level caching with LRU eviction
- [ ] Support concurrent retrieval of multiple frames
- [ ] Performance: target ≤ 200ms first-frame latency for 512×512 @ HTJ2K
- [ ] End-to-end streaming tests (≥ 10 tests)

**Phase 3 Exit Criteria**:
- Progressive retrieval working for all five Transfer Syntaxes
- Multi-frame streaming with frame-level caching
- ≥ 40 additional tests, cumulative ≥ 150 tests

---

### Phase 4 — CLI & Batch Processing (Weeks 19–24)

**Goal**: Provide command-line tooling for batch DICOM JPEG 2000 operations,
suitable for PACS migration, research pipelines, and CI/CD validation.

#### Week 19–20: CLI Foundation

- [ ] Add `dicom-codec` subcommand to J2KCLI
- [ ] `dicom-codec encode` — compress raw pixel data for a given TS
- [ ] `dicom-codec decode` — decompress JPEG 2000 pixel data
- [ ] `dicom-codec transcode` — convert between Transfer Syntaxes
- [ ] `dicom-codec validate` — run validation engine on pixel data
- [ ] `dicom-codec info` — display codec parameters for a J2K codestream
- [ ] Man page and `--help` documentation

#### Week 21–22: Batch Processing

- [ ] `dicom-codec batch` — process directories of raw pixel data files
- [ ] Support glob patterns for input file selection
- [ ] Parallel batch processing with configurable concurrency
- [ ] Progress reporting (percentage, ETA, throughput)
- [ ] Error log with per-file status (JSON output)
- [ ] Resume support for interrupted batch jobs

#### Week 23–24: Reporting & Integration

- [ ] Generate batch conformance reports (HTML + JSON)
- [ ] Quality metrics output (PSNR, SSIM for lossy modes)
- [ ] Integration with CI/CD pipelines (exit codes, machine-readable output)
- [ ] Shell completion scripts (bash, zsh, fish)
- [ ] End-to-end CLI tests (≥ 20 tests)

**Phase 4 Exit Criteria**:
- All CLI subcommands functional with comprehensive `--help`
- Batch processing handles ≥ 1,000 files without memory issues
- ≥ 20 additional tests, cumulative ≥ 170 tests

---

### Phase 5 — Performance & GPU Acceleration (Weeks 25–30)

**Goal**: Optimize DICOM codec performance with hardware acceleration for
high-throughput clinical workloads.

#### Week 25–26: Performance Profiling

- [ ] Profile encode/decode pipelines for common DICOM modalities:
  - CT (512×512 × 16-bit signed, 100+ frames)
  - MR (256×256 × 16-bit, multi-slice)
  - CR/DX (2048×2560 × 12-bit single frame)
  - US (640×480 × 8-bit, high frame rate)
  - Mammography (4096×5120 × 12-bit)
- [ ] Identify bottlenecks per modality
- [ ] Establish baseline throughput metrics

#### Week 27–28: Metal GPU Acceleration (macOS/iOS)

- [ ] GPU-accelerated DWT for large single-frame images (CR, MG)
- [ ] GPU-accelerated color transform for RGB modalities
- [ ] Automatic CPU/GPU selection based on image size
- [ ] Benchmark: target ≥ 2× speedup for images ≥ 2048×2048
- [ ] Fallback to CPU when Metal is unavailable

#### Week 29–30: ARM Neon & Accelerate Optimization

- [ ] Neon-optimized DWT for Apple Silicon and ARM64 Linux
- [ ] vDSP/Accelerate integration for batch operations
- [ ] Memory-mapped I/O for large single-frame images
- [ ] Final performance benchmarks per modality
- [ ] Performance documentation with modality-specific recommendations

**Phase 5 Exit Criteria**:
- Measurable speedup for images ≥ 1024×1024
- No performance regression for small images
- Published benchmark results per modality

---

### Phase 6 — Documentation, Testing & Release (Weeks 31–36)

**Goal**: Comprehensive documentation, final conformance testing, and v3.0.0
release preparation.

#### Week 31–32: Documentation

- [ ] API reference for all public J2K Compression Studio types
- [ ] Integration guide: J2KSwift + DCMTK
- [ ] Integration guide: J2KSwift + fo-dicom
- [ ] Integration guide: J2KSwift + cornerstone.js (via WASM)
- [ ] Tutorial: "Compress a DICOM dataset in 5 lines of Swift"
- [ ] Architecture decision records (ADRs) for key design choices

#### Week 33–34: Conformance & Interoperability Testing

- [ ] Test against DICOM WG-04 JPEG 2000 test images
- [ ] Interop testing with OpenJPEG-generated codestreams
- [ ] Interop testing with Kakadu-generated codestreams
- [ ] Test with real-world anonymized DICOM datasets (CT, MR, CR, MG, US)
- [ ] Publish conformance statement (DICOM PS3.2 format)

#### Week 35–36: Release Preparation

- [ ] Final code review and security audit
- [ ] Update MILESTONES.md, CHANGELOG.md, README.md
- [ ] Tag v3.0.0 release
- [ ] Publish release notes with migration guide
- [ ] Archive conformance test results

**Phase 6 Exit Criteria**:
- Complete API documentation with examples
- Conformance statement published
- v3.0.0 released with all milestones met
- ≥ 200 cumulative tests, 100% pass rate

---

## Key Metrics & Targets

| Metric | Target |
|--------|--------|
| Transfer Syntax Coverage | 5/5 (100%) |
| Round-Trip Lossless Fidelity | Bit-exact |
| Test Count | ≥ 200 |
| Test Pass Rate | 100% |
| Encode Throughput (512×512 single frame) | ≥ 4 MP/s |
| HTJ2K Encode Throughput (512×512) | ≥ 50 MP/s |
| Multi-Frame Throughput (512×512) | ≥ 30 fps |
| First-Frame Latency (JPIP + HTJ2K) | ≤ 200 ms |
| Batch Processing (1000 files) | No memory leaks |
| Supported Bit Depths | 8, 10, 12, 16 (signed + unsigned) |
| Supported Color Spaces | MONO1/2, RGB, YBR_FULL, YBR_ICT, YBR_RCT |

---

## Risk Register

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| GPU acceleration unavailable on Linux CI | Medium | High | Provide CPU fallback; test GPU paths on macOS only |
| Large mammography images exceed memory limits | High | Medium | Memory-mapped I/O; streaming decode |
| DICOM toolkit integration complexity | Medium | Medium | Minimal API surface; raw bytes in, raw bytes out |
| HTJ2K interoperability edge cases | Low | Medium | Extensive conformance testing against OpenJPEG/Kakadu |
| Real-world DICOM datasets with non-conforming metadata | Medium | High | Robust validation with configurable strictness levels |

---

## Dependencies

- **J2KSwift v2.3.0+** — core JPEG 2000 codec (current version)
- **Foundation** — standard library (no external runtime dependencies)
- **Metal** (optional) — GPU acceleration on Apple platforms
- **Vulkan** (optional) — GPU acceleration on Linux
- **Swift 6.0+** — strict concurrency support

---

## Non-Goals

The J2K Compression Studio intentionally does **not**:

- Parse or generate DICOM datasets (use DCMTK, fo-dicom, etc.)
- Read or write DICOM tags
- Implement DICOM networking (C-STORE, C-FIND, etc.)
- Provide a DICOM viewer or rendering engine
- Bundle any DICOM test datasets (use external conformance suites)

The Studio operates exclusively on raw pixel data bytes and DICOM metadata
values passed in by the calling application.

---

## See Also

- [DICOM Integration Guide](DICOM_INTEGRATION.md)
- [HTJ2K Guide](HTJ2K_GUIDE.md)
- [JPIP Guide](JPIP_GUIDE.md)
- [Main Milestones](../MILESTONES.md)
- [Examples/DICOMWorkflow.swift](../Examples/DICOMWorkflow.swift)
