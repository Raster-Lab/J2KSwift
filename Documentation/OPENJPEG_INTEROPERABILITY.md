# OpenJPEG Interoperability

This document describes the bidirectional interoperability testing infrastructure
between J2KSwift and OpenJPEG (ISO/IEC 15444 reference implementation).

## Overview

J2KSwift provides comprehensive interoperability testing with OpenJPEG to ensure
that codestreams produced by either implementation can be correctly decoded by the
other. This is a critical requirement for JPEG 2000 conformance and real-world
deployment.

## Architecture

The interoperability infrastructure consists of the following components:

### OpenJPEG Availability Detection

`OpenJPEGAvailability` automatically detects whether OpenJPEG command-line tools
(`opj_compress`, `opj_decompress`) are available on the system, determines the
installed version, and checks for HTJ2K support (OpenJPEG 2.5+).

```swift
let availability = OpenJPEGAvailability.check()
if availability.isBidirectionalTestingAvailable {
    print("Both encoder and decoder available")
}
```

### CLI Wrapper

`OpenJPEGCLIWrapper` provides a type-safe Swift interface around the OpenJPEG
command-line tools, supporting all standard options:

- Output formats: J2K, JP2, JPX
- Progression orders: LRCP, RLCP, RPCL, PCRL, CPRL
- Quality modes: lossless, target bitrate, target PSNR
- Tile sizes, code-block sizes, decomposition levels
- HTJ2K mode (OpenJPEG 2.5+)

```swift
let config = OpenJPEGCLIWrapper.EncodeConfiguration(
    outputFormat: .jp2,
    lossless: true,
    progressionOrder: .lrcp
)
let args = OpenJPEGCLIWrapper.buildEncodeArguments(
    inputPath: "input.pgm",
    outputPath: "output.jp2",
    configuration: config
)
```

### Interoperability Pipeline

`OpenJPEGInteropPipeline` implements the automated encode-with-one/decode-with-other
testing pipeline in both directions:

- **J2KSwift → OpenJPEG**: Encode with J2KSwift, decode with OpenJPEG
- **OpenJPEG → J2KSwift**: Encode with OpenJPEG, decode with J2KSwift

### Test Image Corpus

`OpenJPEGTestCorpus` generates a standardised corpus of synthetic test images
covering:

| Category | Description | Examples |
|----------|-------------|----------|
| Synthetic | Test patterns | Gradient, checkerboard, zone plate |
| Medical | Medical imaging | 12-bit, 16-bit greyscale |
| Satellite | Remote sensing | Multi-component, large format |
| Photography | General images | RGB, random noise |
| Edge Cases | Boundary conditions | 1×1 pixel, 32-bit, signed |

### Corrupt Codestream Generator

`CorruptCodestreamGenerator` creates intentionally corrupt codestreams to test
error handling in both implementations:

- Truncated codestreams
- Bit-flipped data
- Missing EOC markers
- Corrupt SIZ/SOT segments
- Invalid marker codes
- Empty codestreams

### Interoperability Report

`OpenJPEGInteropReport` generates Markdown reports with test results, pass rates,
direction breakdowns, and failure analysis.

## Test Suite

The interoperability test suite contains 100+ test cases organised into four
categories:

### 1. Harness Tests

Validate the testing infrastructure itself:
- OpenJPEG availability detection
- Version parsing
- CLI argument building
- Test image generation (PGM, PPM)
- Corpus generation
- Report generation
- Corrupt codestream generation

### 2. J2KSwift → OpenJPEG Tests

Validate that J2KSwift-encoded codestreams can be decoded by OpenJPEG:
- All 5 progression orders (LRCP, RLCP, RPCL, PCRL, CPRL)
- Quality layer configurations (1, 2, 3, 5, 10 layers)
- Lossless round-trip validation
- Lossy encoding within PSNR tolerance (30–50 dB)
- File format compatibility (J2K, JP2, JPX)
- RGB and multi-component images
- Decomposition level variants
- Code-block size variants
- Compression ratio variants

### 3. OpenJPEG → J2KSwift Tests

Validate that OpenJPEG-encoded codestreams can be decoded by J2KSwift:
- All OpenJPEG encoder configurations
- Multi-tile images (32×32, 64×64, 128×128)
- ROI decoding
- Progressive decoding
- HTJ2K interoperability (OpenJPEG 2.5+)
- Multi-component images
- Lossy and lossless modes
- All output formats

### 4. Edge Cases

Test boundary conditions and error handling:
- Single-pixel images (1×1)
- Maximum-dimension images
- Unusual bit depths (1, 12, 16, 24, 32)
- Signed vs unsigned component data
- Non-standard tile sizes (7×7, 13×17, 3×5)
- Corrupt/truncated codestreams (7 corruption types)
- Non-square images
- Wide (256×1) and tall (1×256) images

## Setup

### Installing OpenJPEG

Use the provided setup script:

```bash
./Scripts/setup-openjpeg.sh
```

Options:
- `--version 2.5.0` — Specify OpenJPEG version
- `--prefix /usr/local` — Installation directory
- `--skip-if-present` — Skip if already installed
- `--clean` — Remove build files after installation

### Running Tests

```bash
# Run all interoperability tests
swift test --filter J2KInteroperabilityTests

# Run specific test categories
swift test --filter OpenJPEGAvailabilityTests
swift test --filter OpenJPEGCLIWrapperTests
swift test --filter OpenJPEGInteropTestSuiteTests
```

## CI Integration

The conformance CI workflow includes an interoperability job that:

1. Checks for OpenJPEG availability
2. Runs all interoperability tests
3. Reports results as part of the conformance gate

Tests that require OpenJPEG are designed to gracefully skip when the tools
are not available, ensuring CI stability regardless of host configuration.

## Related Documentation

- [Conformance Testing](../CONFORMANCE_TESTING.md)
- [HTJ2K Conformance Report](../HTJ2K_CONFORMANCE_REPORT.md)
- [Compliance Matrix](Compliance/CONFORMANCE_MATRIX.md)
