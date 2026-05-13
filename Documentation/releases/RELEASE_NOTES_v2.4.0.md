# J2KSwift v2.4.0 Release Notes

**Release Date**: 2027-03-30  
**Phase**: Phase 21 — Comprehensive CLI Enhancement (Weeks 336–365)  
**Previous Version**: 2.3.0

---

## Headline Feature: Comprehensive CLI Enhancement

v2.4.0 transforms the `j2k` command-line tool into a full-featured interface that exercises every major capability of the J2KSwift library: 2D codec variants, lossless transcoding, 3D volumetric imaging (JP3D), JPIP network streaming, batch processing, image comparison, format conversion, and shell completions. The CLI is designed with cross-library syntax consistency so that sister tools in the Raster-Lab repository can adopt the same patterns.

---

## What's New

### New Commands

| Command | Description |
|---------|-------------|
| `encode3d` | Compress volumetric / 3D data to JP3D format |
| `decode3d` | Decompress JP3D volumetric data to slices or raw volumes |
| `jpip server` | Start a JPIP streaming server for JPEG 2000 images |
| `jpip client` | Connect to a JPIP server and retrieve image data interactively |
| `batch` | Batch encode, decode, or transcode entire directories |
| `compare` | Compare two images with PSNR, SSIM, and MSE metrics |
| `convert` | Convert between image formats (PGM, PPM, raw, JP2, J2K, JPH) |
| `completions` | Generate shell completions for Bash, Zsh, and Fish |

### Enhanced Existing Commands

- **`encode`** — new `--htj2k` / `--format jph` shortcuts for High Throughput JPEG 2000, multi-spectral support, improved `--json` output with timing breakdown
- **`decode`** — enhanced region-of-interest decoding, component selection, marker inspection output
- **`transcode`** — lossless J2K ↔ HTJ2K transcoding with `--lossless` flag, batch support
- **`info`** — deeper codestream inspection, JP3D metadata, JPIP capability reporting
- **`validate`** — `--strict` mode, JP3D and HTJ2K validation support
- **`benchmark`** — JPIP benchmarking mode, 3D volumetric benchmarks, comparison against baseline

### 3D Volumetric CLI (JP3D)

- Encode directories of 2D slices into JP3D volumes
- Decode JP3D volumes to individual slices or raw binary
- Support for medical imaging (DICOM) workflows
- Configurable 3D tile sizes, codeblock sizes, and slice ordering
- Region-based 3D decoding with `--region x,y,z,w,h,d`

### JPIP Network Streaming

- **Server**: Serve JP2/J2K/JPH/JP3D files with session management, configurable concurrency, and graceful shutdown
- **Client**: Single-request and interactive modes with progressive delivery, region/resolution/quality selection
- Signal handling for clean server shutdown (SIGINT, SIGTERM)
- 3D streaming mode for volumetric data

### Batch Processing

- Parallel encoding, decoding, and transcoding of entire directories
- Configurable worker count (defaults to CPU core count)
- `--continue-on-error` for resilient production pipelines
- `--dry-run` for previewing operations
- Recursive directory scanning with `--recursive`
- Progress tracking with `--verbose` and JSON summary with `--json`

### Cross-Library Syntax Consistency

- Unified flag naming conventions (GNU-style long options, kebab-case)
- Reserved short aliases (`-i`, `-o`, `-v`, `-q`, `-h`) consistent across all commands
- Standard exit codes (0–7) for scripted pipelines
- Stdin/stdout piping support (`-i -` / `-o -`)
- Shell completion generation for Bash, Zsh, and Fish

### Source Files

| File | Lines | Description |
|------|-------|-------------|
| `Encode3D.swift` | 239 | 3D volumetric encoding command |
| `JPIPClient.swift` | 277 | JPIP client with interactive mode |
| `JPIPServer.swift` | 172 | JPIP server with signal handling |
| `MultiFileProcessor.swift` | 342 | Parallel batch file processing engine |

---

## Testing

### New Tests: 193 tests, 0 failures

| Test Suite | Tests | Description |
|-----------|-------|-------------|
| `Batch3DTests` | Volumetric batch processing |
| `BatchCommandTests` | Batch encode/decode/transcode |
| `CodecVariantTests` | HTJ2K, lossless, lossy codec modes |
| `CompareCommandTests` | Image comparison (PSNR/SSIM/MSE) |
| `CompletionTests` | Shell completion generation |
| `ConvertCommandTests` | Format conversion |
| `Decode3DTests` | 3D volumetric decoding |
| `DecodeEnhancedTests` | Enhanced decode features |
| `DiagnosticsTests` | Diagnostic and info output |
| `Encode3DTests` | 3D volumetric encoding |
| `ErrorHandlingTests` | Error paths and invalid inputs |
| `JPIPClientTests` | JPIP client operations |
| `JPIPEndToEndTests` | JPIP client-server integration |
| `JPIPServerTests` | JPIP server operations |
| `MultiFileInputTests` | Multi-file and glob input |
| `MultiSpectralCLITests` | Multi-spectral CLI workflows |
| `TranscodeBatchTests` | Batch transcoding |
| `TranscodeLosslessTests` | Lossless transcoding verification |

---

## Documentation

### New Documentation

| Document | Description |
|----------|-------------|
| `CLI_REFERENCE.md` | Complete command reference for all `j2k` commands |
| `CLI_JPIP_GUIDE.md` | JPIP server and client usage guide |
| `CLI_3D_GUIDE.md` | 3D volumetric CLI guide |
| `CLI_BATCH_GUIDE.md` | Batch processing guide |
| `CLI_CROSS_LIBRARY_SYNTAX.md` | Cross-library syntax specification |

### Updated Documentation

- `CHANGELOG.md` — v2.4.0 entry
- `MILESTONES.md` — Phase 21 completion
- `README.md` — Updated CLI section with new commands

---

## Bug Fixes

- **Swift 6 Sendable fix**: Redesigned `J2KUnifiedMemoryManager` to use `MemoryHandle` (a `Sendable` struct wrapping address as `UInt`) instead of passing `UnsafeMutableRawPointer` across actor boundaries, resolving strict concurrency errors

---

## Breaking Changes

None. v2.4.0 is fully backward compatible with v2.3.0.

---

## Migration

No migration required. All existing APIs remain unchanged. The new CLI commands are additive.

---

## Requirements

- Swift 6.2 or later
- macOS 15+ / iOS 17+ / tvOS 17+ / watchOS 10+ / visionOS 1+ / Linux / Windows

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/Raster-Lab/J2KSwift.git", from: "2.4.0")
]
```

---

## What's Next

Phase 22 planning is underway. See `MILESTONES.md` for details.
