# J2KSwift CLI Enhancement Milestones

A phased development roadmap for building a comprehensive command-line interface for J2KSwift, serving as both a testing and demonstration tool for the library. The CLI extends the existing `j2k` executable and shares the same version number as J2KSwift for consistency.

## Overview

This document outlines the phased approach for enhancing the J2KSwift CLI (`j2k`) into a full-featured command-line tool that exercises every major capability of the library: 2D compression/decompression across all codec variants, lossless transcoding, 3D volumetric imaging, and JPIP network streaming. The CLI is designed with cross-library syntax consistency in mind so that sister compression libraries in the Raster-Lab repository can adopt the same command patterns.

The work is organised as **Phase 21** of the J2KSwift project, targeting version **2.4.0**, and builds directly upon the existing `J2KCLI` target and its current commands (`encode`, `decode`, `info`, `transcode`, `validate`, `benchmark`, `testapp`).

### Design Principles

1. **Built on the library** — every operation delegates to public APIs in J2KCore, J2KCodec, J2KFileFormat, J2K3D, and JPIP; the CLI contains no independent codec logic.
2. **Cross-library syntax consistency** — the command structure (`<tool> <verb> [options]`) and common flags (`-i`, `-o`, `--lossless`, `--quality`, `--format`, `--verbose`, `--json`, `--timing`, `--quiet`, `--progress`) are designed to be reusable across future compression CLIs (e.g., for JPEG XS, DICOM-specific tools).
3. **Shared version** — the CLI reports the same version as the library (`VERSION` file).
4. **British/American spelling parity** — all long flags accept both spellings (e.g., `--colour-space` / `--color-space`, `--no-colour` / `--no-color`), consistent with the existing `normaliseKey` mechanism in `Commands.swift`.
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

- [x] Extend argument parser to support multiple input files
  - [x] Comma-separated paths: `-i file1.pgm,file2.pgm,file3.pgm`
  - [x] Glob patterns: `-i "images/*.pgm"`
  - [x] Directory input: `-i ./input_dir/` (process all supported files)
  - [x] File list from stdin: `--input-list -` (one path per line)
  - [x] File list from file: `--input-list paths.txt`
- [x] Add `--output-dir DIR` for multi-file output directory
- [x] Add `--output-suffix SUFFIX` for automatic output naming (e.g., `--output-suffix .j2k`)
- [x] Add `--recursive` flag for directory traversal
- [x] Implement parallel multi-file processing with `--threads N` (default: system core count)
- [x] Add `--progress` flag for multi-file progress reporting
- [x] Add summary statistics for batch operations (total files, total time, average ratio)
- [x] Testing
  - [x] Unit tests for argument parsing with multiple inputs
  - [x] Unit tests for glob pattern expansion
  - [x] Integration tests for directory traversal

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — enhanced argument parser with multi-file support
- New `Sources/J2KCLI/MultiFileProcessor.swift` — parallel file processing infrastructure
- `Tests/J2KCLITests/MultiFileInputTests.swift`

#### Week 338–339: Full Codec Variant Support for Encode

- [x] Add `--codec` flag with explicit variant selection
  - [x] `--codec j2k-lossless` — JPEG 2000 Part 1 lossless (5/3 DWT, reversible)
  - [x] `--codec j2k-lossy` — JPEG 2000 Part 1 lossy (9/7 DWT, irreversible)
  - [x] `--codec htj2k-lossless` — HTJ2K (Part 15) lossless
  - [x] `--codec htj2k-lossy` — HTJ2K (Part 15) lossy
  - [x] `--codec htj2k-lossless-rpcl` — HTJ2K lossless with RPCL progression order
- [x] Add `--compression-ratio N:1` for target compression ratio (e.g., `--compression-ratio 20:1`)
- [x] Add `--compression-percent N` for percentage-based compression (e.g., `--compression-percent 95` = 95% size reduction)
- [x] Enhance `--bitrate` to accept both bpp and total size (e.g., `--bitrate 1.5bpp` or `--bitrate 500KB`)
- [x] Add `--target-size BYTES` for exact output size targeting
- [x] Add `--psnr-target DB` as alias for existing `--psnr`
- [x] Add `--roi-file PATH` for ROI mask from external file
- [x] Add `--roi-priority HIGH|MEDIUM|LOW` for ROI quality differentiation
- [x] Verify existing flags work correctly with all codec variants
- [x] Testing
  - [x] Encode tests for each codec variant
  - [x] Compression ratio / percentage accuracy tests
  - [x] Round-trip tests for all variants (encode → decode → compare)

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — codec variant flag parsing and configuration mapping
- `Tests/J2KCLITests/CodecVariantTests.swift`

#### Week 340–341: Enhanced Decode Command

- [x] Add multi-file decoding support (matching encode multi-file infrastructure)
  - [x] `-i file1.j2k,file2.jp2` or `-i ./encoded_dir/`
  - [x] `--output-dir DIR` and `--output-suffix .pgm`
- [x] Add `--region x,y,w,h` for region-of-interest decoding
- [x] Add `--scale N` for resolution reduction (power-of-2 scaling: 1, 2, 4, 8)
- [x] Add `--strip-alpha` to discard alpha channel on decode
- [x] Add `--output-format pgm|ppm|pnm|raw|tiff` for explicit output format
- [x] Add `--bit-depth N` for output bit depth conversion (e.g., 16-bit to 8-bit)
- [x] Add `--color-convert` for colour space conversion on decode (e.g., YCbCr → sRGB)
- [x] Add partial decoding support via `--level` and `--layer` (enhance existing)
- [x] Add `--header-only` to print codestream info without full decode
- [x] Testing
  - [x] Decode tests for all supported input formats (j2k, jp2, jpx, jph)
  - [x] Region-of-interest decode accuracy tests
  - [x] Multi-resolution decode tests
  - [x] Multi-file decode integration tests

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — enhanced decode command
- `Tests/J2KCLITests/DecodeEnhancedTests.swift`

#### Week 342–343: Batch Command & Image Comparison

- [x] Implement standalone `batch` command
  - [x] `j2k batch encode -i ./input/ -o ./output/ --codec htj2k-lossless --recursive`
  - [x] `j2k batch decode -i ./encoded/ -o ./decoded/ --output-format ppm`
  - [x] `j2k batch transcode -i ./legacy/ -o ./htj2k/ --to-htj2k`
  - [x] Support `--filter GLOB` for selective processing (e.g., `--filter "*.jp2"`)
  - [x] Support `--exclude GLOB` for skipping files
  - [x] Support `--continue-on-error` for fault-tolerant batch processing
  - [x] Batch summary report: files processed, failed, skipped, total time, average compression ratio
- [x] Implement `compare` command
  - [x] `j2k compare -i original.pgm -r reconstructed.pgm`
  - [x] PSNR calculation
  - [x] MSE (Mean Squared Error) calculation
  - [x] MAE (Mean Absolute Error) calculation
  - [x] Maximum absolute error
  - [x] Bit-exact comparison for lossless verification
  - [x] Per-component comparison for multi-component images
  - [x] `--json` output for scripted quality validation
- [x] Implement `convert` command (format conversion utility)
  - [x] `j2k convert -i input.pgm -o output.ppm`
  - [x] Support PGM ↔ PPM ↔ PNM ↔ RAW conversions
  - [x] Bit depth conversion (8-bit ↔ 16-bit)
- [x] Testing
  - [x] Batch command integration tests
  - [x] Compare command accuracy tests (known PSNR values)
  - [x] Convert command round-trip tests
  - [x] Error handling tests (missing files, permission errors, corrupt data)

**Deliverables**:
- New `Sources/J2KCLI/Batch.swift` — batch processing command
- New `Sources/J2KCLI/Compare.swift` — image comparison command
- New `Sources/J2KCLI/Convert.swift` — format conversion command
- `Tests/J2KCLITests/BatchCommandTests.swift`
- `Tests/J2KCLITests/CompareCommandTests.swift`
- `Tests/J2KCLITests/ConvertCommandTests.swift`

**Sub-phase 21a Status**: Complete

---

### Sub-phase 21b: Lossless Transcoding Enhancement (Weeks 344–347)

**Goal**: Enhance the existing `transcode` command to fully support all lossless transcoding paths between JPEG 2000 Part 1 and HTJ2K without generational loss, with verification and reporting.

#### Week 344–345: Lossless Transcoding Paths

- [x] Enhance `transcode` command with explicit transcoding paths
  - [x] `j2k transcode -i input.j2k -o output.jph --to-htj2k` (existing — verify lossless)
  - [x] `j2k transcode -i input.jph -o output.j2k --from-htj2k` (existing — verify lossless)
  - [x] `j2k transcode -i input.j2k -o output.j2k --progression RPCL` (re-order without re-encode)
  - [x] `j2k transcode -i input.j2k -o output.jp2 --format jp2` (wrap in JP2 container)
  - [x] `j2k transcode -i input.jp2 -o output.j2k --format j2k` (strip JP2 container)
- [x] Add `--verify` flag for automatic lossless verification
  - [x] Decode both input and output, compare pixel-by-pixel
  - [x] Report bit-exact match or per-component error statistics
  - [x] Exit with non-zero code if verification fails
- [x] Add `--verify-mode exact|statistical` for verification granularity
  - [x] `exact` — bit-exact comparison (default for lossless)
  - [x] `statistical` — PSNR / MSE comparison (for re-encoded lossy)
- [x] Add `--preserve-metadata` flag (default: on) to carry forward JP2 metadata boxes
- [x] Add `--strip-metadata` flag to remove non-essential metadata
- [x] Testing
  - [x] Lossless round-trip tests: J2K → HTJ2K → J2K (bit-exact)
  - [x] Container conversion tests: J2K → JP2 → J2K
  - [x] Progression order change tests
  - [x] Verification flag accuracy tests

**Deliverables**:
- Updated `Sources/J2KCLI/Transcode.swift` — enhanced transcoding with verification
- `Tests/J2KCLITests/TranscodeLosslessTests.swift`

#### Week 346–347: Multi-File Transcoding & Reporting

- [x] Extend transcoding with multi-file and directory support
  - [x] `j2k transcode --batch ./legacy_j2k/ --output-dir ./htj2k/ --to-htj2k --verify`
  - [x] Parallel transcoding with `--threads N`
  - [x] `--continue-on-error` for fault-tolerant batch transcoding
- [x] Add transcoding report
  - [x] Per-file: input size, output size, transcoding time, verification result
  - [x] Summary: total files, total time, average size change, all-pass verification
  - [x] `--report PATH` to save report to file (text, JSON, or CSV)
- [x] Add `--format-detect` to auto-detect optimal transcoding direction
- [x] Testing
  - [x] Batch transcoding integration tests
  - [x] Report generation tests (all output formats)
  - [x] Mixed-format directory transcoding tests

**Deliverables**:
- Updated `Sources/J2KCLI/Transcode.swift` — multi-file transcoding and reporting
- `Tests/J2KCLITests/TranscodeBatchTests.swift`

**Sub-phase 21b Status**: Complete

---

### Sub-phase 21c: 3D Volumetric Compression & Decompression (Weeks 348–355)

**Goal**: Add `encode3d` and `decode3d` commands that exercise the J2K3D (JP3D) module for volumetric and multi-spectral data compression using both JPEG 2000 and HTJ2K codecs.

#### Week 348–349: 3D Encode Command

- [x] Add `J2K3D` module dependency to `J2KCLI` target in `Package.swift`
- [x] Implement `encode3d` command
  - [x] `j2k encode3d -i ./slices/ -o volume.jp3d --codec j2k-lossless`
  - [x] Accept input as directory of 2D slices (ordered by filename)
  - [x] Accept input as single multi-frame file with `--frames N`
  - [x] Accept input as raw volumetric data with `--dimensions WxHxD --bit-depth N`
  - [x] Support all codec variants:
    - [x] `--codec j2k-lossless` — JP3D with reversible 3D DWT
    - [x] `--codec j2k-lossy` — JP3D with irreversible 3D DWT
    - [x] `--codec htj2k-lossless` — JP3D with HTJ2K entropy coding (lossless)
    - [x] `--codec htj2k-lossy` — JP3D with HTJ2K entropy coding (lossy)
  - [x] Add `--compression-ratio N:1` and `--compression-percent N` for lossy 3D
  - [x] Add `--tile-size WxHxD` for 3D tiling
  - [x] Add `--decomposition-levels X,Y,Z` for per-axis DWT levels
  - [x] Add `--progression ORDER` for 3D progression order
  - [x] Add `--parallel` / `--no-parallel` for parallel slice encoding
- [x] Testing
  - [x] 3D encode with synthetic volume data (each codec variant)
  - [x] Slice directory input tests
  - [x] Raw volumetric input tests
  - [x] Argument validation tests

**Deliverables**:
- New `Sources/J2KCLI/Encode3D.swift` — 3D encoding command
- Updated `Package.swift` — J2K3D dependency for J2KCLI
- `Tests/J2KCLITests/Encode3DTests.swift`

#### Week 350–351: 3D Decode Command

- [x] Implement `decode3d` command
  - [x] `j2k decode3d -i volume.jp3d -o ./slices/ --output-format pgm`
  - [x] Output as directory of 2D slices (one file per z-plane)
  - [x] Output as raw volumetric data with `--output-format raw`
  - [x] Add `--slice-range START:END` for partial volume extraction
  - [x] Add `--region x,y,z,w,h,d` for 3D region-of-interest extraction
  - [x] Add `--scale N` for multi-resolution 3D decoding
  - [x] Add `--slice-naming PATTERN` for output filename pattern (e.g., `slice_%04d.pgm`)
- [x] Testing
  - [x] 3D decode for all codec variants
  - [x] Round-trip tests (encode3d → decode3d → compare)
  - [x] Partial volume extraction tests
  - [x] Slice naming pattern tests

**Deliverables**:
- New `Sources/J2KCLI/Decode3D.swift` — 3D decoding command
- `Tests/J2KCLITests/Decode3DTests.swift`

#### Week 352–353: Multi-Spectral 3D Support

- [x] Add multi-spectral encoding/decoding options
  - [x] `--spectral-bands N` — number of spectral bands
  - [x] `--spectral-type visible|nir|hyperspectral` — spectral classification
  - [x] `--inter-band-prediction` / `--no-inter-band-prediction` — enable/disable inter-band prediction
  - [x] `--band-weights W1,W2,...` — per-band quality weights for lossy compression
- [x] Add `--spectral-info` flag to `info` command for 3D/spectral metadata display
- [x] Testing
  - [x] Multi-spectral encode/decode round-trip tests
  - [x] Inter-band prediction accuracy tests
  - [x] Per-band quality weight tests

**Deliverables**:
- Updated `Sources/J2KCLI/Encode3D.swift` — multi-spectral options
- Updated `Sources/J2KCLI/Decode3D.swift` — multi-spectral options
- `Tests/J2KCLITests/MultiSpectralCLITests.swift`

#### Week 354–355: 3D Batch Processing & Benchmarking

- [x] Add 3D batch processing
  - [x] `j2k batch encode3d -i ./volumes/ -o ./compressed/ --codec htj2k-lossless`
  - [x] Process multiple volume directories
  - [x] `--volume-pattern GLOB` to match volume directories
- [x] Add 3D benchmarking to `benchmark` command
  - [x] `j2k benchmark -i ./volume_slices/ --mode 3d --runs 3`
  - [x] 3D encode/decode throughput (voxels/second)
  - [x] Comparison between J2K and HTJ2K 3D performance
- [x] Add `j2k compare --mode 3d` for volumetric comparison
  - [x] Per-slice PSNR and overall volume PSNR
  - [x] 3D structural similarity metrics
- [x] Testing
  - [x] 3D batch processing integration tests
  - [x] 3D benchmark accuracy tests
  - [x] 3D comparison accuracy tests

**Deliverables**:
- Updated `Sources/J2KCLI/Batch.swift` — 3D batch support
- Updated `Sources/J2KCLI/Benchmark.swift` — 3D benchmarking
- Updated `Sources/J2KCLI/Compare.swift` — 3D comparison
- `Tests/J2KCLITests/Batch3DTests.swift`

**Sub-phase 21c Status**: Complete

---

### Sub-phase 21d: JPIP Network Streaming (Weeks 356–361)

**Goal**: Add `jpip server` and `jpip client` subcommands that exercise the JPIP module, enabling interactive JPEG 2000 streaming between terminal windows or machines.

#### Week 356–357: JPIP Server Command

- [x] Add `JPIP` module dependency to `J2KCLI` target in `Package.swift`
- [x] Implement `jpip server` command
  - [x] `j2k jpip server --port 8080 --data-dir ./images/`
  - [x] Serve JPEG 2000 files from a directory via JPIP protocol
  - [x] `--port N` — listening port (default: 8080)
  - [x] `--host ADDRESS` — bind address (default: 0.0.0.0)
  - [x] `--data-dir DIR` — directory containing JPEG 2000 files to serve
  - [x] `--single-file PATH` — serve a single file
  - [x] `--max-sessions N` — maximum concurrent sessions (default: 10)
  - [x] `--session-timeout SECONDS` — session idle timeout (default: 300)
  - [x] `--transport http|websocket` — transport protocol
  - [x] `--tls-cert PATH --tls-key PATH` — TLS configuration (optional)
  - [x] `--access-log PATH` — access log file
  - [x] Server status display: active sessions, bytes transferred, request count
  - [x] Graceful shutdown on SIGINT / SIGTERM
- [x] Add 3D/volumetric JPIP serving
  - [x] `j2k jpip server --data-dir ./volumes/ --mode 3d`
  - [x] Progressive 3D delivery with JP3D JPIP extensions
- [x] Testing
  - [x] Server startup and shutdown tests
  - [x] Single-file serving tests
  - [x] Directory serving tests
  - [x] Session management tests

**Deliverables**:
- New `Sources/J2KCLI/JPIPServer.swift` — JPIP server command
- Updated `Package.swift` — JPIP dependency for J2KCLI
- `Tests/J2KCLITests/JPIPServerTests.swift`

#### Week 358–359: JPIP Client Command

- [x] Implement `jpip client` command
  - [x] `j2k jpip client --server http://localhost:8080 --target image.jp2 -o output.pgm`
  - [x] `--server URL` — JPIP server URL
  - [x] `--target NAME` — target image name on server
  - [x] `-o, --output PATH` — output file for decoded image
  - [x] `--region x,y,w,h` — request specific region (window)
  - [x] `--resolution-level N` — request specific resolution level
  - [x] `--quality-layers N` — request specific quality layers
  - [x] `--progressive` — progressive rendering (save intermediate results)
  - [x] `--progressive-dir DIR` — directory for progressive rendering frames
  - [x] `--max-bandwidth BPS` — bandwidth throttling for testing
  - [x] `--session-type stateless|stateful` — JPIP session type
  - [x] `--transport http|websocket` — transport protocol
  - [x] Connection status display: latency, bytes received, cache hit rate
- [x] Add interactive mode
  - [x] `j2k jpip client --server URL --target NAME --interactive`
  - [x] Interactive commands: `region x,y,w,h`, `zoom N`, `pan dx,dy`, `quality N`, `save PATH`, `quit`
  - [x] Real-time status updates
- [x] Testing
  - [x] Client connection tests (with test server)
  - [x] Region request tests
  - [x] Progressive delivery tests
  - [x] Interactive mode tests

**Deliverables**:
- New `Sources/J2KCLI/JPIPClient.swift` — JPIP client command
- `Tests/J2KCLITests/JPIPClientTests.swift`

#### Week 360–361: JPIP End-to-End & 3D Streaming

- [x] End-to-end JPIP testing
  - [x] Automated test: start server → client request → verify output → shutdown
  - [x] Cross-terminal demonstration script
  - [x] Cross-machine demonstration documentation
  - [x] Latency and throughput benchmarking
- [x] Add 3D JPIP client support
  - [x] `j2k jpip client --server URL --target volume.jp3d --mode 3d --slice-range 10:20 -o ./slices/`
  - [x] Progressive 3D volume delivery
  - [x] Slice-by-slice streaming
- [x] Add JPIP benchmarking
  - [x] `j2k benchmark --mode jpip --server URL --target NAME --runs N`
  - [x] Measure: connection setup time, first-byte latency, transfer time, total throughput
  - [x] Compare: full download vs progressive delivery
- [x] Documentation
  - [x] JPIP CLI usage guide with examples
  - [x] Network setup guide (ports, firewall, TLS)
  - [x] Demonstration scripts for common workflows
- [x] Testing
  - [x] End-to-end integration tests
  - [x] 3D streaming tests
  - [x] Benchmark accuracy tests

**Deliverables**:
- Updated `Sources/J2KCLI/JPIPServer.swift` — 3D serving support
- Updated `Sources/J2KCLI/JPIPClient.swift` — 3D client and interactive mode
- New `Sources/J2KCLI/JPIPBenchmark.swift` — JPIP performance benchmarking
- `Tests/J2KCLITests/JPIPEndToEndTests.swift`
- `Documentation/CLI_JPIP_GUIDE.md`

**Sub-phase 21d Status**: Complete

---

### Sub-phase 21e: Additional Commands & Polish (Weeks 362–365)

**Goal**: Add supplementary commands, shell completions, cross-platform validation, comprehensive documentation, and release preparation.

#### Week 362: Additional Options & Diagnostics

- [x] Add `--estimate` flag to `encode` / `encode3d`
  - [x] Estimate output size without performing full encode
  - [x] Display estimated compression ratio, encoding time, and memory usage
- [x] Add `--memory-limit BYTES` to cap peak memory usage
  - [x] Fallback to tiled processing when limit would be exceeded
- [x] Add `--gpu` / `--no-gpu` / `--gpu-device N` for GPU acceleration control
  - [x] List available GPU devices: `j2k info --list-gpus`
  - [x] Select specific device for Metal or Vulkan backend
- [x] Add `--simd` / `--no-simd` for SIMD acceleration control
- [x] Add `--profile` flag for internal profiling output
  - [x] Per-stage timing: I/O, colour transform, DWT, quantisation, entropy coding
  - [x] Memory allocation statistics
  - [x] SIMD/GPU utilisation percentage
- [x] Add `j2k info --capabilities` to display library capabilities
  - [x] Supported codecs, formats, acceleration backends
  - [x] Platform information, Swift version, library version
  - [x] Available SIMD instruction sets
  - [x] GPU availability and capabilities
- [x] Testing
  - [x] Estimation accuracy tests
  - [x] Memory limit enforcement tests
  - [x] Capabilities output tests

**Deliverables**:
- Updated `Sources/J2KCLI/Commands.swift` — additional flags
- New `Sources/J2KCLI/Capabilities.swift` — capabilities and diagnostics
- `Tests/J2KCLITests/DiagnosticsTests.swift`

#### Week 363: Shell Completions & Error Handling

- [x] Generate shell completions
  - [x] Bash completions for all commands and flags
  - [x] Zsh completions with descriptions
  - [x] Fish completions
  - [x] `j2k completions bash|zsh|fish` command to output completion scripts
- [x] Enhance error messages
  - [x] Contextual error messages with suggested fixes
  - [x] "Did you mean?" suggestions for misspelled commands and flags
  - [x] Exit codes: 0 = success, 1 = general error, 2 = argument error, 3 = I/O error, 4 = codec error
- [x] Add `--no-colour` / `--no-color` flag for environments without ANSI support
- [x] Add coloured terminal output for errors (red), warnings (yellow), success (green)
- [x] Testing
  - [x] Shell completion generation tests
  - [x] Error message quality tests
  - [x] Exit code correctness tests

**Deliverables**:
- New `Sources/J2KCLI/Completions.swift` — shell completion generation
- Updated error handling across all command files
- `Tests/J2KCLITests/CompletionTests.swift`
- `Tests/J2KCLITests/ErrorHandlingTests.swift`

#### Week 364: Documentation & Cross-Platform Validation

- [x] Comprehensive CLI documentation
  - [x] `Documentation/CLI_GUIDE.md` — complete CLI user guide
  - [x] `Documentation/CLI_REFERENCE.md` — command reference (all flags, all examples)
  - [x] `Documentation/CLI_JPIP_GUIDE.md` — JPIP server/client guide
  - [x] `Documentation/CLI_3D_GUIDE.md` — 3D volumetric CLI guide
  - [x] `Documentation/CLI_BATCH_GUIDE.md` — batch processing guide
  - [x] `Documentation/CLI_CROSS_LIBRARY_SYNTAX.md` — cross-library syntax specification
  - [x] Man page generation (`j2k.1`)
- [x] Cross-platform validation
  - [x] macOS (ARM64 and x86_64) — full feature set
  - [x] Linux (Ubuntu 22.04+) — all features except Metal GPU
  - [x] Verify Vulkan GPU support on Linux
  - [x] CI pipeline for cross-platform CLI testing
- [x] Testing
  - [x] Documentation link validation
  - [x] Cross-platform feature matrix tests
  - [x] Man page generation tests

**Deliverables**:
- `Documentation/CLI_GUIDE.md`
- `Documentation/CLI_REFERENCE.md`
- `Documentation/CLI_JPIP_GUIDE.md`
- `Documentation/CLI_3D_GUIDE.md`
- `Documentation/CLI_BATCH_GUIDE.md`
- `Documentation/CLI_CROSS_LIBRARY_SYNTAX.md`

#### Week 365: Release Preparation (v2.4.0)

- [x] Update `Package.swift` with final J2KCLI dependencies (J2KCore, J2KCodec, J2KFileFormat, J2K3D, JPIP)
- [x] Update `VERSION` file to 2.4.0
- [x] Update `README.md` CLI section with new commands and examples
- [x] Update `CHANGELOG.md` with all Phase 21 changes
- [x] Update `MILESTONES.md` with Phase 21 entry
- [x] Create `RELEASE_NOTES_v2.4.0.md`
- [x] Create `RELEASE_CHECKLIST_v2.4.0.md`
- [x] Full regression test suite
  - [x] All existing tests pass (2,900+ tests)
  - [x] All new CLI tests pass
  - [x] Cross-platform CI green
- [x] Performance validation
  - [x] CLI overhead < 5% vs direct library API calls
  - [x] Multi-file parallel processing scales linearly to 4+ cores
  - [x] JPIP server handles 10+ concurrent sessions
- [x] Security review
  - [x] Path traversal prevention in file operations
  - [x] Input validation for all user-supplied parameters
  - [x] TLS certificate validation for JPIP
  - [x] No sensitive data in logs or error messages
- [x] Tag and release v2.4.0

**Deliverables**:
- Updated `Package.swift`, `VERSION`, `README.md`, `CHANGELOG.md`, `MILESTONES.md`
- `RELEASE_NOTES_v2.4.0.md`
- `RELEASE_CHECKLIST_v2.4.0.md`
- All tests passing on macOS and Linux

**Sub-phase 21e Status**: Complete

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

- [x] `Tests/J2KCLITests/MultiFileInputTests.swift` — multi-file argument parsing, glob expansion, directory traversal
- [x] `Tests/J2KCLITests/CodecVariantTests.swift` — all codec variant encode/decode round-trips
- [x] `Tests/J2KCLITests/DecodeEnhancedTests.swift` — region decode, scaling, format conversion
- [x] `Tests/J2KCLITests/BatchCommandTests.swift` — batch encode/decode/transcode, error handling
- [x] `Tests/J2KCLITests/CompareCommandTests.swift` — PSNR, MSE, bit-exact comparison
- [x] `Tests/J2KCLITests/ConvertCommandTests.swift` — format conversion round-trips
- [x] `Tests/J2KCLITests/TranscodeLosslessTests.swift` — lossless transcoding verification
- [x] `Tests/J2KCLITests/TranscodeBatchTests.swift` — batch transcoding
- [x] `Tests/J2KCLITests/Encode3DTests.swift` — 3D encode all variants
- [x] `Tests/J2KCLITests/Decode3DTests.swift` — 3D decode, partial extraction
- [x] `Tests/J2KCLITests/MultiSpectralCLITests.swift` — multi-spectral 3D
- [x] `Tests/J2KCLITests/Batch3DTests.swift` — 3D batch processing
- [x] `Tests/J2KCLITests/JPIPServerTests.swift` — JPIP server lifecycle
- [x] `Tests/J2KCLITests/JPIPClientTests.swift` — JPIP client operations
- [x] `Tests/J2KCLITests/JPIPEndToEndTests.swift` — full server ↔ client pipeline
- [x] `Tests/J2KCLITests/DiagnosticsTests.swift` — capabilities, estimation, profiling
- [x] `Tests/J2KCLITests/CompletionTests.swift` — shell completion generation
- [x] `Tests/J2KCLITests/ErrorHandlingTests.swift` — error messages, exit codes

### Phase 21 Summary

Phase 21 (Weeks 336–365) transforms the `j2k` CLI from a basic encode/decode tool into a comprehensive testing and demonstration interface for the entire J2KSwift library. The enhanced CLI supports multi-file and directory processing with parallel execution, all JPEG 2000 and HTJ2K codec variants with fine-grained compression control, lossless transcoding with automatic verification, JP3D volumetric 3D compression/decompression (including multi-spectral data), and JPIP interactive streaming with both server and client modes. New utility commands (`batch`, `compare`, `convert`, `completions`) round out the feature set. The command syntax follows a cross-library-consistent pattern designed for reuse across Raster-Lab compression tools. The CLI shares the J2KSwift version number (2.4.0) and builds exclusively on the library's public APIs with no independent codec logic.

**Status**: Complete (v2.4.0)

---

**Target Version**: 2.4.0
**Estimated Duration**: 30 weeks (Weeks 336–365)
**Prerequisites**: Phase 20 complete (v2.3.0); all referenced modules must already exist and be functional — J2KCore (Phase 0), J2KCodec (Phases 1–4), J2KFileFormat (Phase 5), J2K3D (Phase 16, v1.9.0), JPIP (Phase 6). No new library modules are created in this phase; all CLI commands build exclusively on existing public APIs.
**Dependencies**: J2KCore, J2KCodec, J2KFileFormat, J2K3D, JPIP (all existing modules)
