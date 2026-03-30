# J2KSwift CLI Enhancement Milestones

A phased development roadmap for building a comprehensive command-line interface for J2KSwift, serving as both a testing and demonstration tool for the library. The CLI extends the existing `j2k` executable and shares the same version number as J2KSwift for consistency.

## Overview

This document outlines the phased approach for enhancing the J2KSwift CLI (`j2k`) into a full-featured command-line tool that exercises every major capability of the library: 2D compression/decompression across all codec variants, lossless transcoding, 3D volumetric imaging, and JPIP network streaming. The CLI is designed with cross-library syntax consistency in mind so that sister compression libraries in the Raster-Lab repository can adopt the same command patterns.

The work is organised as **Phase 21** of the J2KSwift project, targeting version **2.4.0**, and builds directly upon the existing `J2KCLI` target and its current commands (`encode`, `decode`, `info`, `transcode`, `validate`, `benchmark`, `testapp`).

### Design Principles

1. **Built on the library** — every operation delegates to public APIs in J2KCore, J2KCodec, J2KFileFormat, J2K3D, and JPIP; the CLI contains no independent codec logic.
2. **Cross-library syntax consistency** — the command structure (`<tool> <verb> [options]`) and common flags (`-i`, `-o`, `--lossless`, `--quality`, `--format`, `--verbose`, `--json`, `--timing`, `--quiet`, `--progress`) are designed to be reusable across future compression CLIs (e.g., for JPEG XS, DICOM-specific tools).
3. **Shared version** — the CLI reports the same version as the library (`VERSION` file).
4. **British/American spelling parity** — all long flags accept both spellings (e.g., `--colour-space` / `--color-space`, `--optimise` / `--optimize`).
5. **Machine-readable output** — every command supports `--json` for scripted pipelines.
6. **Progressive disclosure** — simple tasks require few flags; advanced features are opt-in.

### Unified CLI Syntax Reference

The following syntax is designed for reuse across Raster-Lab compression tools. Tool-specific verbs (e.g., `jpip`) are nested under the same binary.

```
j2k <command> [subcommand] [options]

COMMANDS (existing — enhanced in this milestone):
    encode          Compress image(s) to JPEG 2000 / HTJ2K
    decode          Decompress JPEG 2000 / HTJ2K image(s)
    transcode       Lossless transcoding between J2K ↔ HTJ2K
    info            Display codestream / file-format metadata
    validate        Conformance validation
    benchmark       Performance benchmarking

COMMANDS (new):
    encode3d        Compress volumetric / 3D data (JP3D)
    decode3d        Decompress volumetric / 3D data (JP3D)
    jpip server     Start a JPIP streaming server
    jpip client     Connect to a JPIP server and retrieve data
    batch           Batch-process files in a directory
    convert         Convert between image formats (utility)
    compare         Compare two images (PSNR, SSIM, MSE)

COMMON FLAGS (all commands):
    -i, --input PATH|GLOB      Input file(s) or directory
    -o, --output PATH|DIR      Output file or directory
    --verbose                   Verbose output
    --quiet                     Suppress non-error output
    --json                      Machine-readable JSON output
    --timing                    Show timing breakdown
    --progress                  Show progress bar / percentage
    --log-level LEVEL           Log level: error, warn, info, debug, trace
    --dry-run                   Validate arguments without executing
    --version                   Print version and exit
    --help                      Show help for command
```

---

## Phase 21: Comprehensive CLI Enhancement (v2.4.0, Weeks 336–365)

**Goal**: Transform the existing `j2k` CLI into a comprehensive testing and demonstration tool that exercises all J2KSwift library capabilities — multi-file 2D compression/decompression across all codec variants, lossless transcoding, 3D volumetric imaging, JPIP network streaming, and batch processing — with cross-library-consistent syntax.

---

### Sub-phase 21a: Enhanced 2D Compression & Decompression (Weeks 336–343)

**Goal**: Extend the existing `encode` and `decode` commands to support all codec variants, multi-file input, folder input, and compression percentage control.

#### Week 336–337: Multi-File Input Infrastructure

- [ ] Extend argument parser to support multiple input files
  - [ ] Comma-separated paths: `-i file1.pgm,file2.pgm,file3.pgm`
  - [ ] Glob patterns: `-i "images/*.pgm"`
  - [ ] Directory input: `-i ./input_dir/` (process all supported files)
  - [ ] File list from stdin: `--input-list -` (one path per line)
  - [ ] File list from file: `--input-list paths.txt`
- [ ] Add `--output-dir DIR` for multi-file output directory
- [ ] Add `--output-suffix SUFFIX` for automatic output naming (e.g., `--output-suffix .j2k`)
- [ ] Add `--recursive` flag for directory traversal
- [ ] Implement parallel multi-file processing with `--threads N` (default: system core count)
- [ ] Add `--progress` flag for multi-file progress reporting
- [ ] Add summary statistics for batch operations (total files, total time, average ratio)
- [ ] Testing
  - [ ] Unit tests for argument parsing with multiple inputs
  - [ ] Unit tests for glob pattern expansion
  - [ ] Integration tests for directory traversal

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — enhanced argument parser with multi-file support
- New `Sources/J2KCLI/MultiFileProcessor.swift` — parallel file processing infrastructure
- `Tests/J2KCLITests/MultiFileInputTests.swift`

#### Week 338–339: Full Codec Variant Support for Encode

- [ ] Add `--codec` flag with explicit variant selection
  - [ ] `--codec j2k-lossless` — JPEG 2000 Part 1 lossless (5/3 DWT, reversible)
  - [ ] `--codec j2k-lossy` — JPEG 2000 Part 1 lossy (9/7 DWT, irreversible)
  - [ ] `--codec htj2k-lossless` — HTJ2K (Part 15) lossless
  - [ ] `--codec htj2k-lossy` — HTJ2K (Part 15) lossy
  - [ ] `--codec htj2k-lossless-rpcl` — HTJ2K lossless with RPCL progression order
- [ ] Add `--compression-ratio N:1` for target compression ratio (e.g., `--compression-ratio 20:1`)
- [ ] Add `--compression-percent N` for percentage-based compression (e.g., `--compression-percent 95` = 95% size reduction)
- [ ] Enhance `--bitrate` to accept both bpp and total size (e.g., `--bitrate 1.5bpp` or `--bitrate 500KB`)
- [ ] Add `--target-size BYTES` for exact output size targeting
- [ ] Add `--psnr-target DB` as alias for existing `--psnr`
- [ ] Add `--roi-file PATH` for ROI mask from external file
- [ ] Add `--roi-priority HIGH|MEDIUM|LOW` for ROI quality differentiation
- [ ] Verify existing flags work correctly with all codec variants
- [ ] Testing
  - [ ] Encode tests for each codec variant
  - [ ] Compression ratio / percentage accuracy tests
  - [ ] Round-trip tests for all variants (encode → decode → compare)

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — codec variant flag parsing and configuration mapping
- `Tests/J2KCLITests/CodecVariantTests.swift`

#### Week 340–341: Enhanced Decode Command

- [ ] Add multi-file decoding support (matching encode multi-file infrastructure)
  - [ ] `-i file1.j2k,file2.jp2` or `-i ./encoded_dir/`
  - [ ] `--output-dir DIR` and `--output-suffix .pgm`
- [ ] Add `--region x,y,w,h` for region-of-interest decoding
- [ ] Add `--scale N` for resolution reduction (power-of-2 scaling: 1, 2, 4, 8)
- [ ] Add `--strip-alpha` to discard alpha channel on decode
- [ ] Add `--output-format pgm|ppm|pnm|raw|tiff` for explicit output format
- [ ] Add `--bit-depth N` for output bit depth conversion (e.g., 16-bit to 8-bit)
- [ ] Add `--color-convert` for colour space conversion on decode (e.g., YCbCr → sRGB)
- [ ] Add partial decoding support via `--level` and `--layer` (enhance existing)
- [ ] Add `--header-only` to print codestream info without full decode
- [ ] Testing
  - [ ] Decode tests for all supported input formats (j2k, jp2, jpx, jph)
  - [ ] Region-of-interest decode accuracy tests
  - [ ] Multi-resolution decode tests
  - [ ] Multi-file decode integration tests

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — enhanced decode command
- `Tests/J2KCLITests/DecodeEnhancedTests.swift`

#### Week 342–343: Batch Command & Image Comparison

- [ ] Implement standalone `batch` command
  - [ ] `j2k batch encode -i ./input/ -o ./output/ --codec htj2k-lossless --recursive`
  - [ ] `j2k batch decode -i ./encoded/ -o ./decoded/ --output-format ppm`
  - [ ] `j2k batch transcode -i ./legacy/ -o ./htj2k/ --to-htj2k`
  - [ ] Support `--filter GLOB` for selective processing (e.g., `--filter "*.jp2"`)
  - [ ] Support `--exclude GLOB` for skipping files
  - [ ] Support `--continue-on-error` for fault-tolerant batch processing
  - [ ] Batch summary report: files processed, failed, skipped, total time, average compression ratio
- [ ] Implement `compare` command
  - [ ] `j2k compare -i original.pgm -r reconstructed.pgm`
  - [ ] PSNR calculation
  - [ ] MSE (Mean Squared Error) calculation
  - [ ] MAE (Mean Absolute Error) calculation
  - [ ] Maximum absolute error
  - [ ] Bit-exact comparison for lossless verification
  - [ ] Per-component comparison for multi-component images
  - [ ] `--json` output for scripted quality validation
- [ ] Implement `convert` command (format conversion utility)
  - [ ] `j2k convert -i input.pgm -o output.ppm`
  - [ ] Support PGM ↔ PPM ↔ PNM ↔ RAW conversions
  - [ ] Bit depth conversion (8-bit ↔ 16-bit)
- [ ] Testing
  - [ ] Batch command integration tests
  - [ ] Compare command accuracy tests (known PSNR values)
  - [ ] Convert command round-trip tests
  - [ ] Error handling tests (missing files, permission errors, corrupt data)

**Deliverables**:
- New `Sources/J2KCLI/Batch.swift` — batch processing command
- New `Sources/J2KCLI/Compare.swift` — image comparison command
- New `Sources/J2KCLI/Convert.swift` — format conversion command
- `Tests/J2KCLITests/BatchCommandTests.swift`
- `Tests/J2KCLITests/CompareCommandTests.swift`
- `Tests/J2KCLITests/ConvertCommandTests.swift`

**Sub-phase 21a Status**: Planned

---

### Sub-phase 21b: Lossless Transcoding Enhancement (Weeks 344–347)

**Goal**: Enhance the existing `transcode` command to fully support all lossless transcoding paths between JPEG 2000 Part 1 and HTJ2K without generational loss, with verification and reporting.

#### Week 344–345: Lossless Transcoding Paths

- [ ] Enhance `transcode` command with explicit transcoding paths
  - [ ] `j2k transcode -i input.j2k -o output.jph --to-htj2k` (existing — verify lossless)
  - [ ] `j2k transcode -i input.jph -o output.j2k --from-htj2k` (existing — verify lossless)
  - [ ] `j2k transcode -i input.j2k -o output.j2k --progression RPCL` (re-order without re-encode)
  - [ ] `j2k transcode -i input.j2k -o output.jp2 --format jp2` (wrap in JP2 container)
  - [ ] `j2k transcode -i input.jp2 -o output.j2k --format j2k` (strip JP2 container)
- [ ] Add `--verify` flag for automatic lossless verification
  - [ ] Decode both input and output, compare pixel-by-pixel
  - [ ] Report bit-exact match or per-component error statistics
  - [ ] Exit with non-zero code if verification fails
- [ ] Add `--verify-mode exact|statistical` for verification granularity
  - [ ] `exact` — bit-exact comparison (default for lossless)
  - [ ] `statistical` — PSNR / MSE comparison (for re-encoded lossy)
- [ ] Add `--preserve-metadata` flag (default: on) to carry forward JP2 metadata boxes
- [ ] Add `--strip-metadata` flag to remove non-essential metadata
- [ ] Testing
  - [ ] Lossless round-trip tests: J2K → HTJ2K → J2K (bit-exact)
  - [ ] Container conversion tests: J2K → JP2 → J2K
  - [ ] Progression order change tests
  - [ ] Verification flag accuracy tests

**Deliverables**:
- Updated `Sources/J2KCLI/Transcode.swift` — enhanced transcoding with verification
- `Tests/J2KCLITests/TranscodeLosslessTests.swift`

#### Week 346–347: Multi-File Transcoding & Reporting

- [ ] Extend transcoding with multi-file and directory support
  - [ ] `j2k transcode --batch ./legacy_j2k/ --output-dir ./htj2k/ --to-htj2k --verify`
  - [ ] Parallel transcoding with `--threads N`
  - [ ] `--continue-on-error` for fault-tolerant batch transcoding
- [ ] Add transcoding report
  - [ ] Per-file: input size, output size, transcoding time, verification result
  - [ ] Summary: total files, total time, average size change, all-pass verification
  - [ ] `--report PATH` to save report to file (text, JSON, or CSV)
- [ ] Add `--format-detect` to auto-detect optimal transcoding direction
- [ ] Testing
  - [ ] Batch transcoding integration tests
  - [ ] Report generation tests (all output formats)
  - [ ] Mixed-format directory transcoding tests

**Deliverables**:
- Updated `Sources/J2KCLI/Transcode.swift` — multi-file transcoding and reporting
- `Tests/J2KCLITests/TranscodeBatchTests.swift`

**Sub-phase 21b Status**: Planned

---

### Sub-phase 21c: 3D Volumetric Compression & Decompression (Weeks 348–355)

**Goal**: Add `encode3d` and `decode3d` commands that exercise the J2K3D (JP3D) module for volumetric and multi-spectral data compression using both JPEG 2000 and HTJ2K codecs.

#### Week 348–349: 3D Encode Command

- [ ] Add `J2K3D` module dependency to `J2KCLI` target in `Package.swift`
- [ ] Implement `encode3d` command
  - [ ] `j2k encode3d -i ./slices/ -o volume.jp3d --codec j2k-lossless`
  - [ ] Accept input as directory of 2D slices (ordered by filename)
  - [ ] Accept input as single multi-frame file with `--frames N`
  - [ ] Accept input as raw volumetric data with `--dimensions WxHxD --bit-depth N`
  - [ ] Support all codec variants:
    - [ ] `--codec j2k-lossless` — JP3D with reversible 3D DWT
    - [ ] `--codec j2k-lossy` — JP3D with irreversible 3D DWT
    - [ ] `--codec htj2k-lossless` — JP3D with HTJ2K entropy coding (lossless)
    - [ ] `--codec htj2k-lossy` — JP3D with HTJ2K entropy coding (lossy)
  - [ ] Add `--compression-ratio N:1` and `--compression-percent N` for lossy 3D
  - [ ] Add `--tile-size WxHxD` for 3D tiling
  - [ ] Add `--decomposition-levels X,Y,Z` for per-axis DWT levels
  - [ ] Add `--progression ORDER` for 3D progression order
  - [ ] Add `--parallel` / `--no-parallel` for parallel slice encoding
- [ ] Testing
  - [ ] 3D encode with synthetic volume data (each codec variant)
  - [ ] Slice directory input tests
  - [ ] Raw volumetric input tests
  - [ ] Argument validation tests

**Deliverables**:
- New `Sources/J2KCLI/Encode3D.swift` — 3D encoding command
- Updated `Package.swift` — J2K3D dependency for J2KCLI
- `Tests/J2KCLITests/Encode3DTests.swift`

#### Week 350–351: 3D Decode Command

- [ ] Implement `decode3d` command
  - [ ] `j2k decode3d -i volume.jp3d -o ./slices/ --output-format pgm`
  - [ ] Output as directory of 2D slices (one file per z-plane)
  - [ ] Output as raw volumetric data with `--output-format raw`
  - [ ] Add `--slice-range START:END` for partial volume extraction
  - [ ] Add `--region x,y,z,w,h,d` for 3D region-of-interest extraction
  - [ ] Add `--scale N` for multi-resolution 3D decoding
  - [ ] Add `--slice-naming PATTERN` for output filename pattern (e.g., `slice_%04d.pgm`)
- [ ] Testing
  - [ ] 3D decode for all codec variants
  - [ ] Round-trip tests (encode3d → decode3d → compare)
  - [ ] Partial volume extraction tests
  - [ ] Slice naming pattern tests

**Deliverables**:
- New `Sources/J2KCLI/Decode3D.swift` — 3D decoding command
- `Tests/J2KCLITests/Decode3DTests.swift`

#### Week 352–353: Multi-Spectral 3D Support

- [ ] Add multi-spectral encoding/decoding options
  - [ ] `--spectral-bands N` — number of spectral bands
  - [ ] `--spectral-type visible|nir|hyperspectral` — spectral classification
  - [ ] `--inter-band-prediction` / `--no-inter-band-prediction` — enable/disable inter-band prediction
  - [ ] `--band-weights W1,W2,...` — per-band quality weights for lossy compression
- [ ] Add `--spectral-info` flag to `info` command for 3D/spectral metadata display
- [ ] Testing
  - [ ] Multi-spectral encode/decode round-trip tests
  - [ ] Inter-band prediction accuracy tests
  - [ ] Per-band quality weight tests

**Deliverables**:
- Updated `Sources/J2KCLI/Encode3D.swift` — multi-spectral options
- Updated `Sources/J2KCLI/Decode3D.swift` — multi-spectral options
- `Tests/J2KCLITests/MultiSpectralCLITests.swift`

#### Week 354–355: 3D Batch Processing & Benchmarking

- [ ] Add 3D batch processing
  - [ ] `j2k batch encode3d -i ./volumes/ -o ./compressed/ --codec htj2k-lossless`
  - [ ] Process multiple volume directories
  - [ ] `--volume-pattern GLOB` to match volume directories
- [ ] Add 3D benchmarking to `benchmark` command
  - [ ] `j2k benchmark -i ./volume_slices/ --mode 3d --runs 3`
  - [ ] 3D encode/decode throughput (voxels/second)
  - [ ] Comparison between J2K and HTJ2K 3D performance
- [ ] Add `j2k compare --mode 3d` for volumetric comparison
  - [ ] Per-slice PSNR and overall volume PSNR
  - [ ] 3D structural similarity metrics
- [ ] Testing
  - [ ] 3D batch processing integration tests
  - [ ] 3D benchmark accuracy tests
  - [ ] 3D comparison accuracy tests

**Deliverables**:
- Updated `Sources/J2KCLI/Batch.swift` — 3D batch support
- Updated `Sources/J2KCLI/Benchmark.swift` — 3D benchmarking
- Updated `Sources/J2KCLI/Compare.swift` — 3D comparison
- `Tests/J2KCLITests/Batch3DTests.swift`

**Sub-phase 21c Status**: Planned

---

### Sub-phase 21d: JPIP Network Streaming (Weeks 356–361)

**Goal**: Add `jpip server` and `jpip client` subcommands that exercise the JPIP module, enabling interactive JPEG 2000 streaming between terminal windows or machines.

#### Week 356–357: JPIP Server Command

- [ ] Add `JPIP` module dependency to `J2KCLI` target in `Package.swift`
- [ ] Implement `jpip server` command
  - [ ] `j2k jpip server --port 8080 --data-dir ./images/`
  - [ ] Serve JPEG 2000 files from a directory via JPIP protocol
  - [ ] `--port N` — listening port (default: 8080)
  - [ ] `--host ADDRESS` — bind address (default: 0.0.0.0)
  - [ ] `--data-dir DIR` — directory containing JPEG 2000 files to serve
  - [ ] `--single-file PATH` — serve a single file
  - [ ] `--max-sessions N` — maximum concurrent sessions (default: 10)
  - [ ] `--session-timeout SECONDS` — session idle timeout (default: 300)
  - [ ] `--transport http|websocket` — transport protocol
  - [ ] `--tls-cert PATH --tls-key PATH` — TLS configuration (optional)
  - [ ] `--access-log PATH` — access log file
  - [ ] Server status display: active sessions, bytes transferred, request count
  - [ ] Graceful shutdown on SIGINT / SIGTERM
- [ ] Add 3D/volumetric JPIP serving
  - [ ] `j2k jpip server --data-dir ./volumes/ --mode 3d`
  - [ ] Progressive 3D delivery with JP3D JPIP extensions
- [ ] Testing
  - [ ] Server startup and shutdown tests
  - [ ] Single-file serving tests
  - [ ] Directory serving tests
  - [ ] Session management tests

**Deliverables**:
- New `Sources/J2KCLI/JPIPServer.swift` — JPIP server command
- Updated `Package.swift` — JPIP dependency for J2KCLI
- `Tests/J2KCLITests/JPIPServerTests.swift`

#### Week 358–359: JPIP Client Command

- [ ] Implement `jpip client` command
  - [ ] `j2k jpip client --server http://localhost:8080 --target image.jp2 -o output.pgm`
  - [ ] `--server URL` — JPIP server URL
  - [ ] `--target NAME` — target image name on server
  - [ ] `-o, --output PATH` — output file for decoded image
  - [ ] `--region x,y,w,h` — request specific region (window)
  - [ ] `--resolution-level N` — request specific resolution level
  - [ ] `--quality-layers N` — request specific quality layers
  - [ ] `--progressive` — progressive rendering (save intermediate results)
  - [ ] `--progressive-dir DIR` — directory for progressive rendering frames
  - [ ] `--max-bandwidth BPS` — bandwidth throttling for testing
  - [ ] `--session-type stateless|stateful` — JPIP session type
  - [ ] `--transport http|websocket` — transport protocol
  - [ ] Connection status display: latency, bytes received, cache hit rate
- [ ] Add interactive mode
  - [ ] `j2k jpip client --server URL --target NAME --interactive`
  - [ ] Interactive commands: `region x,y,w,h`, `zoom N`, `pan dx,dy`, `quality N`, `save PATH`, `quit`
  - [ ] Real-time status updates
- [ ] Testing
  - [ ] Client connection tests (with test server)
  - [ ] Region request tests
  - [ ] Progressive delivery tests
  - [ ] Interactive mode tests

**Deliverables**:
- New `Sources/J2KCLI/JPIPClient.swift` — JPIP client command
- `Tests/J2KCLITests/JPIPClientTests.swift`

#### Week 360–361: JPIP End-to-End & 3D Streaming

- [ ] End-to-end JPIP testing
  - [ ] Automated test: start server → client request → verify output → shutdown
  - [ ] Cross-terminal demonstration script
  - [ ] Cross-machine demonstration documentation
  - [ ] Latency and throughput benchmarking
- [ ] Add 3D JPIP client support
  - [ ] `j2k jpip client --server URL --target volume.jp3d --mode 3d --slice-range 10:20 -o ./slices/`
  - [ ] Progressive 3D volume delivery
  - [ ] Slice-by-slice streaming
- [ ] Add JPIP benchmarking
  - [ ] `j2k benchmark --mode jpip --server URL --target NAME --runs N`
  - [ ] Measure: connection setup time, first-byte latency, transfer time, total throughput
  - [ ] Compare: full download vs progressive delivery
- [ ] Documentation
  - [ ] JPIP CLI usage guide with examples
  - [ ] Network setup guide (ports, firewall, TLS)
  - [ ] Demonstration scripts for common workflows
- [ ] Testing
  - [ ] End-to-end integration tests
  - [ ] 3D streaming tests
  - [ ] Benchmark accuracy tests

**Deliverables**:
- Updated `Sources/J2KCLI/JPIPServer.swift` — 3D serving support
- Updated `Sources/J2KCLI/JPIPClient.swift` — 3D client and interactive mode
- New `Sources/J2KCLI/JPIPBenchmark.swift` — JPIP performance benchmarking
- `Tests/J2KCLITests/JPIPEndToEndTests.swift`
- `Documentation/CLI_JPIP_GUIDE.md`

**Sub-phase 21d Status**: Planned

---

### Sub-phase 21e: Additional Commands & Polish (Weeks 362–365)

**Goal**: Add supplementary commands, shell completions, cross-platform validation, comprehensive documentation, and release preparation.

#### Week 362: Additional Options & Diagnostics

- [ ] Add `--estimate` flag to `encode` / `encode3d`
  - [ ] Estimate output size without performing full encode
  - [ ] Display estimated compression ratio, encoding time, and memory usage
- [ ] Add `--memory-limit BYTES` to cap peak memory usage
  - [ ] Fallback to tiled processing when limit would be exceeded
- [ ] Add `--gpu` / `--no-gpu` / `--gpu-device N` for GPU acceleration control
  - [ ] List available GPU devices: `j2k info --list-gpus`
  - [ ] Select specific device for Metal or Vulkan backend
- [ ] Add `--simd` / `--no-simd` for SIMD acceleration control
- [ ] Add `--profile` flag for internal profiling output
  - [ ] Per-stage timing: I/O, colour transform, DWT, quantisation, entropy coding
  - [ ] Memory allocation statistics
  - [ ] SIMD/GPU utilisation percentage
- [ ] Add `j2k info --capabilities` to display library capabilities
  - [ ] Supported codecs, formats, acceleration backends
  - [ ] Platform information, Swift version, library version
  - [ ] Available SIMD instruction sets
  - [ ] GPU availability and capabilities
- [ ] Testing
  - [ ] Estimation accuracy tests
  - [ ] Memory limit enforcement tests
  - [ ] Capabilities output tests

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — additional flags
- New `Sources/J2KCLI/Capabilities.swift` — capabilities and diagnostics
- `Tests/J2KCLITests/DiagnosticsTests.swift`

#### Week 363: Shell Completions & Error Handling

- [ ] Generate shell completions
  - [ ] Bash completions for all commands and flags
  - [ ] Zsh completions with descriptions
  - [ ] Fish completions
  - [ ] `j2k completions bash|zsh|fish` command to output completion scripts
- [ ] Enhance error messages
  - [ ] Contextual error messages with suggested fixes
  - [ ] "Did you mean?" suggestions for misspelled commands and flags
  - [ ] Exit codes: 0 = success, 1 = general error, 2 = argument error, 3 = I/O error, 4 = codec error
- [ ] Add `--no-colour` / `--no-color` flag for environments without ANSI support
- [ ] Add coloured terminal output for errors (red), warnings (yellow), success (green)
- [ ] Testing
  - [ ] Shell completion generation tests
  - [ ] Error message quality tests
  - [ ] Exit code correctness tests

**Deliverables**:
- New `Sources/J2KCLI/Completions.swift` — shell completion generation
- Updated error handling across all command files
- `Tests/J2KCLITests/CompletionTests.swift`
- `Tests/J2KCLITests/ErrorHandlingTests.swift`

#### Week 364: Documentation & Cross-Platform Validation

- [ ] Comprehensive CLI documentation
  - [ ] `Documentation/CLI_GUIDE.md` — complete CLI user guide
  - [ ] `Documentation/CLI_REFERENCE.md` — command reference (all flags, all examples)
  - [ ] `Documentation/CLI_JPIP_GUIDE.md` — JPIP server/client guide
  - [ ] `Documentation/CLI_3D_GUIDE.md` — 3D volumetric CLI guide
  - [ ] `Documentation/CLI_BATCH_GUIDE.md` — batch processing guide
  - [ ] `Documentation/CLI_CROSS_LIBRARY_SYNTAX.md` — cross-library syntax specification
  - [ ] Man page generation (`j2k.1`)
- [ ] Cross-platform validation
  - [ ] macOS (ARM64 and x86_64) — full feature set
  - [ ] Linux (Ubuntu 22.04+) — all features except Metal GPU
  - [ ] Verify Vulkan GPU support on Linux
  - [ ] CI pipeline for cross-platform CLI testing
- [ ] Testing
  - [ ] Documentation link validation
  - [ ] Cross-platform feature matrix tests
  - [ ] Man page generation tests

**Deliverables**:
- `Documentation/CLI_GUIDE.md`
- `Documentation/CLI_REFERENCE.md`
- `Documentation/CLI_JPIP_GUIDE.md`
- `Documentation/CLI_3D_GUIDE.md`
- `Documentation/CLI_BATCH_GUIDE.md`
- `Documentation/CLI_CROSS_LIBRARY_SYNTAX.md`

#### Week 365: Release Preparation (v2.4.0)

- [ ] Update `Package.swift` with final J2KCLI dependencies (J2KCore, J2KCodec, J2KFileFormat, J2K3D, JPIP)
- [ ] Update `VERSION` file to 2.4.0
- [ ] Update `README.md` CLI section with new commands and examples
- [ ] Update `CHANGELOG.md` with all Phase 21 changes
- [ ] Update `MILESTONES.md` with Phase 21 entry
- [ ] Create `RELEASE_NOTES_v2.4.0.md`
- [ ] Create `RELEASE_CHECKLIST_v2.4.0.md`
- [ ] Full regression test suite
  - [ ] All existing tests pass (2,900+ tests)
  - [ ] All new CLI tests pass
  - [ ] Cross-platform CI green
- [ ] Performance validation
  - [ ] CLI overhead < 5% vs direct library API calls
  - [ ] Multi-file parallel processing scales linearly to 4+ cores
  - [ ] JPIP server handles 10+ concurrent sessions
- [ ] Security review
  - [ ] Path traversal prevention in file operations
  - [ ] Input validation for all user-supplied parameters
  - [ ] TLS certificate validation for JPIP
  - [ ] No sensitive data in logs or error messages
- [ ] Tag and release v2.4.0

**Deliverables**:
- Updated `Package.swift`, `VERSION`, `README.md`, `CHANGELOG.md`, `MILESTONES.md`
- `RELEASE_NOTES_v2.4.0.md`
- `RELEASE_CHECKLIST_v2.4.0.md`
- All tests passing on macOS and Linux

**Sub-phase 21e Status**: Planned

---

### Phase 21 Complete Command Reference

Below is the full command reference for the enhanced CLI after Phase 21 completion.

```
j2k encode -i <input> -o <output> [options]
    --codec j2k-lossless|j2k-lossy|htj2k-lossless|htj2k-lossy|htj2k-lossless-rpcl
    --lossless                          Shorthand for --codec j2k-lossless
    --htj2k                             Shorthand for --codec htj2k-lossless
    -q, --quality FLOAT                 Quality 0.0–1.0
    --compression-ratio N:1             Target compression ratio
    --compression-percent N             Target size reduction percentage
    --bitrate BPP|SIZE                  Target bit-rate or file size
    --target-size BYTES                 Exact output size target
    --psnr VALUE                        Target PSNR (dB)
    --visually-lossless                 Near-lossless preset
    --preset fast|balanced|quality      Encoding preset
    --levels N                          DWT decomposition levels (0–10)
    --blocksize WxH                     Code-block size
    --layers N                          Quality layers (1–20)
    --format j2k|jp2|jpx|jph           Output container format
    --progression LRCP|RLCP|RPCL|PCRL|CPRL
    --tile-size WxH                     Tile size
    --roi x,y,w,h                       Region of interest
    --roi-file PATH                     ROI mask file
    --roi-priority HIGH|MEDIUM|LOW      ROI quality level
    --mct / --no-mct                    Multi-component transform
    --gpu / --no-gpu                    GPU acceleration
    --colour-space / --color-space CS   Colour space
    --threads N                         Parallel threads
    --estimate                          Estimate output without encoding
    --memory-limit BYTES                Peak memory cap
    --profile                           Internal profiling output

j2k decode -i <input> -o <output> [options]
    --region x,y,w,h                    Decode specific region
    --scale N                           Resolution reduction (1, 2, 4, 8)
    --level N                           Resolution level
    --layer N                           Quality layer
    --component N                       Single component
    --components N,M,...                Multiple components
    --strip-alpha                       Discard alpha channel
    --output-format pgm|ppm|pnm|raw    Output format
    --bit-depth N                       Output bit depth
    --color-convert                     Colour space conversion
    --header-only                       Print info without decode
    --gpu / --no-gpu                    GPU acceleration
    --threads N                         Parallel threads

j2k transcode -i <input> -o <output> [options]
    --to-htj2k                          Transcode to HTJ2K
    --from-htj2k                        Transcode from HTJ2K to Part 1
    --format j2k|jp2|jpx|jph           Output format
    --progression ORDER                 Progression order
    --verify                            Verify lossless transcoding
    --verify-mode exact|statistical     Verification granularity
    --preserve-metadata                 Carry forward metadata (default)
    --strip-metadata                    Remove non-essential metadata
    --batch DIR                         Batch input directory
    --output-dir DIR                    Batch output directory
    --report PATH                       Save transcoding report
    --threads N                         Parallel threads

j2k encode3d -i <input> -o <output> [options]
    --codec j2k-lossless|j2k-lossy|htj2k-lossless|htj2k-lossy
    --dimensions WxHxD                  Volume dimensions (for raw input)
    --bit-depth N                       Input bit depth (for raw input)
    --frames N                          Number of frames (multi-frame input)
    --compression-ratio N:1             Target compression ratio
    --compression-percent N             Target size reduction
    --tile-size WxHxD                   3D tile size
    --decomposition-levels X,Y,Z        Per-axis DWT levels
    --progression ORDER                 3D progression order
    --parallel / --no-parallel          Parallel slice encoding
    --spectral-bands N                  Number of spectral bands
    --spectral-type visible|nir|hyperspectral
    --inter-band-prediction             Enable inter-band prediction
    --band-weights W1,W2,...            Per-band quality weights

j2k decode3d -i <input> -o <output> [options]
    --output-format pgm|ppm|raw         Per-slice output format
    --slice-range START:END             Extract slice range
    --region x,y,z,w,h,d               3D region of interest
    --scale N                           Multi-resolution decode
    --slice-naming PATTERN              Output filename pattern

j2k jpip server [options]
    --port N                            Listening port (default: 8080)
    --host ADDRESS                      Bind address (default: 0.0.0.0)
    --data-dir DIR                      Image directory to serve
    --single-file PATH                  Serve a single file
    --mode 2d|3d                        Serving mode
    --max-sessions N                    Max concurrent sessions (default: 10)
    --session-timeout SECONDS           Session idle timeout (default: 300)
    --transport http|websocket          Transport protocol
    --tls-cert PATH                     TLS certificate
    --tls-key PATH                      TLS private key
    --access-log PATH                   Access log file

j2k jpip client [options]
    --server URL                        JPIP server URL
    --target NAME                       Target image on server
    -o, --output PATH                   Output file
    --region x,y,w,h                    Region window
    --resolution-level N                Resolution level
    --quality-layers N                  Quality layers
    --progressive                       Progressive rendering
    --progressive-dir DIR               Progressive output directory
    --mode 2d|3d                        Client mode
    --slice-range START:END             3D slice range
    --max-bandwidth BPS                 Bandwidth throttle
    --session-type stateless|stateful   Session type
    --transport http|websocket          Transport protocol
    --interactive                       Interactive mode

j2k batch <encode|decode|transcode|encode3d|decode3d> [options]
    -i, --input DIR                     Input directory
    -o, --output DIR                    Output directory
    --filter GLOB                       Include filter
    --exclude GLOB                      Exclude filter
    --recursive                         Recursive directory traversal
    --continue-on-error                 Fault-tolerant processing
    --threads N                         Parallel threads
    (plus all options from the underlying command)

j2k compare -i <original> -r <reconstructed> [options]
    --mode 2d|3d                        Comparison mode
    --metrics psnr,mse,mae,maxerr       Metrics to compute
    --bit-exact                         Verify bit-exact match

j2k convert -i <input> -o <output> [options]
    --bit-depth N                       Output bit depth
    --output-format pgm|ppm|pnm|raw    Output format

j2k info <file> [options]
    --markers                           List codestream markers
    --boxes                             List JP2/JPX boxes
    --json                              JSON output
    --validate                          Quick conformance check
    --capabilities                      Display library capabilities
    --list-gpus                         List available GPU devices

j2k validate <file> [options]
    --part1                             Part 1 conformance
    --part2                             Part 2 conformance
    --part15                            Part 15 (HTJ2K) conformance
    --strict                            Strict validation
    --json                              JSON output

j2k benchmark -i <input> [options]
    --mode 2d|3d|jpip                   Benchmark mode
    -r, --runs N                        Measurement runs (default: 3)
    --warmup N                          Warm-up runs (default: 1)
    -o, --output PATH                   Output report file
    --format text|json|csv              Output format
    --encode-only                       Only benchmark encoding
    --decode-only                       Only benchmark decoding
    --preset fast|balanced|quality      Encoding preset
    --compare-openjpeg                  OpenJPEG comparison

j2k completions bash|zsh|fish         Generate shell completions
j2k version                            Print version
j2k help [command]                     Show help
```

### Phase 21 Test Coverage

- [ ] `Tests/J2KCLITests/MultiFileInputTests.swift` — multi-file argument parsing, glob expansion, directory traversal
- [ ] `Tests/J2KCLITests/CodecVariantTests.swift` — all codec variant encode/decode round-trips
- [ ] `Tests/J2KCLITests/DecodeEnhancedTests.swift` — region decode, scaling, format conversion
- [ ] `Tests/J2KCLITests/BatchCommandTests.swift` — batch encode/decode/transcode, error handling
- [ ] `Tests/J2KCLITests/CompareCommandTests.swift` — PSNR, MSE, bit-exact comparison
- [ ] `Tests/J2KCLITests/ConvertCommandTests.swift` — format conversion round-trips
- [ ] `Tests/J2KCLITests/TranscodeLosslessTests.swift` — lossless transcoding verification
- [ ] `Tests/J2KCLITests/TranscodeBatchTests.swift` — batch transcoding
- [ ] `Tests/J2KCLITests/Encode3DTests.swift` — 3D encode all variants
- [ ] `Tests/J2KCLITests/Decode3DTests.swift` — 3D decode, partial extraction
- [ ] `Tests/J2KCLITests/MultiSpectralCLITests.swift` — multi-spectral 3D
- [ ] `Tests/J2KCLITests/Batch3DTests.swift` — 3D batch processing
- [ ] `Tests/J2KCLITests/JPIPServerTests.swift` — JPIP server lifecycle
- [ ] `Tests/J2KCLITests/JPIPClientTests.swift` — JPIP client operations
- [ ] `Tests/J2KCLITests/JPIPEndToEndTests.swift` — full server ↔ client pipeline
- [ ] `Tests/J2KCLITests/DiagnosticsTests.swift` — capabilities, estimation, profiling
- [ ] `Tests/J2KCLITests/CompletionTests.swift` — shell completion generation
- [ ] `Tests/J2KCLITests/ErrorHandlingTests.swift` — error messages, exit codes

### Phase 21 Summary

Phase 21 (Weeks 336–365) transforms the `j2k` CLI from a basic encode/decode tool into a comprehensive testing and demonstration interface for the entire J2KSwift library. The enhanced CLI supports multi-file and directory processing with parallel execution, all JPEG 2000 and HTJ2K codec variants with fine-grained compression control, lossless transcoding with automatic verification, JP3D volumetric 3D compression/decompression (including multi-spectral data), and JPIP interactive streaming with both server and client modes. New utility commands (`batch`, `compare`, `convert`, `completions`) round out the feature set. The command syntax follows a cross-library-consistent pattern designed for reuse across Raster-Lab compression tools. The CLI shares the J2KSwift version number (2.4.0) and builds exclusively on the library's public APIs with no independent codec logic.

**Status**: Planned (v2.4.0)

---

**Target Version**: 2.4.0
**Estimated Duration**: 30 weeks (Weeks 336–365)
**Prerequisites**: Phase 20 complete (v2.3.0), all modules functional (J2KCore, J2KCodec, J2KFileFormat, J2K3D, JPIP)
**Dependencies**: J2KCore, J2KCodec, J2KFileFormat, J2K3D, JPIP (all existing modules)
