# J2KSwift Usage Guide

A practical guide to encoding, decoding, and working with JPEG 2000 images
using J2KSwift v2.4.0.

---

## Contents

- [Overview](#overview)
- [Swift API](#swift-api)
  - [Encoding](#encoding)
  - [Decoding](#decoding)
  - [Configuration Presets](#configuration-presets)
  - [Custom Configuration](#custom-configuration)
  - [File I/O](#file-io)
  - [Progress Reporting](#progress-reporting)
- [CLI Quick Reference](#cli-quick-reference)
  - [Encoding](#cli-encoding)
  - [Decoding](#cli-decoding)
  - [Recommended Presets](#recommended-presets)
  - [Best-Practice Commands](#best-practice-commands)
  - [Piping & Scripting](#piping--scripting)
- [Choosing the Right Settings](#choosing-the-right-settings)
- [Troubleshooting](#troubleshooting)

---

## Overview

J2KSwift is a pure Swift implementation of the JPEG 2000 standard
(ISO/IEC 15444). It provides:

| Feature | Detail |
|---------|--------|
| Codec | Part 1 (J2K) and Part 15 (HTJ2K) |
| Modes | Lossless (5/3 RCT) and lossy (9/7 ICT) |
| Containers | `.j2k`, `.jp2`, `.jpx`, `.jph` |
| Raster I/O | PGM, PPM, TIFF, PNG, DICOM, RAW |
| Presets | `fast`, `balanced`, `quality` |
| Platforms | macOS 15+, iOS 17+, tvOS 17+, watchOS 10+, visionOS 1+ |

---

## Swift API

### Encoding

```swift
import J2KCore
import J2KCodec

// Minimal encode — balanced defaults
let encoder = J2KEncoder()
let data = try encoder.encode(image)

// Lossless encode
let losslessEncoder = J2KEncoder(configuration: .lossless)
let losslessData = try losslessEncoder.encode(image)
```

### Decoding

```swift
import J2KCodec

let decoder = J2KDecoder()
let image = try decoder.decode(codestreamData)
```

### Configuration Presets

J2KSwift provides two layers of configuration:

1. **`J2KConfiguration`** — simple quality/lossless toggle (in `J2KCore`)
2. **`J2KEncodingConfiguration`** — full control over all parameters (in `J2KCodec`)

#### Quick presets via `J2KConfiguration`

| Preset | Quality | Use case |
|--------|---------|----------|
| `.lossless` | 1.0 (lossless) | Archival, medical, pixel-exact |
| `.highQuality` | 0.95 | Professional photography |
| `.balanced` | 0.85 | General-purpose |
| `.fast` | 0.70 | Web, previews |
| `.maxCompression` | 0.50 | Bandwidth-constrained |

```swift
let encoder = J2KEncoder(configuration: .balanced)
```

#### Detailed presets via `J2KEncodingPreset`

| Preset | Levels | Block size | Layers | Notes |
|--------|--------|------------|--------|-------|
| `.fast` | 3 | 64×64 | 3 | Single-threaded, no visual weighting |
| `.balanced` | 5 | 64×64 | 5 | Auto-threads, precinct ladder |
| `.quality` | 6 | 64×64 | 10 | Auto-threads, precinct ladder |

```swift
let config = J2KEncodingPreset.quality.configuration(quality: 0.95)
let encoder = J2KEncoder(encodingConfiguration: config)
```

### Custom Configuration

```swift
var config = J2KEncodingConfiguration(
    quality: 0.9,
    lossless: false,
    decompositionLevels: 5,
    codeBlockSize: (64, 64),
    qualityLayers: 5,
    progressionOrder: .rpcl,
    tileSize: (512, 512),
    useHTJ2K: true,
    precinctSizes: [(64, 64), (128, 128), (256, 256)]
)
let encoder = J2KEncoder(encodingConfiguration: config)
let data = try encoder.encode(image)
```

#### Key parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `quality` | `Double` | `0.9` | 0.0 (max compression) – 1.0 (lossless) |
| `lossless` | `Bool` | `false` | Reversible 5/3 wavelet + RCT |
| `decompositionLevels` | `Int` | `5` | DWT levels (0–10) |
| `codeBlockSize` | `(Int,Int)` | `(64,64)` | Entropy-coding block (4–1024) |
| `qualityLayers` | `Int` | `5` | Progressive quality layers (1–20) |
| `progressionOrder` | `J2KProgressionOrder` | `.lrcp` | Packet ordering |
| `tileSize` | `(Int,Int)` | `(0,0)` | Tile dimensions; `(0,0)` = single tile |
| `useHTJ2K` | `Bool` | `false` | Part 15 fast block coder |
| `bitrateMode` | `J2KBitrateMode` | `.constantQuality` | Rate-control strategy |
| `precinctSizes` | `[(Int,Int)]` | `[]` | Per-level precinct sizes (lowest first) |
| `mctConfiguration` | `J2KMCTEncodingConfiguration` | `.disabled` | Multi-component transform |

### File I/O

Read and write JP2 container files:

```swift
import J2KFileFormat

// Write
let writer = J2KFileWriter(format: .jp2)
try writer.write(image, to: fileURL)

// Read
let reader = J2KFileReader()
let loaded = try reader.read(from: fileURL)
```

### Progress Reporting

```swift
let encoder = J2KEncoder(encodingConfiguration: config)
let data = try encoder.encode(image) { update in
    print("\(update.stage): \(Int(update.overallProgress * 100))%")
}
```

---

## CLI Quick Reference

Build the CLI:

```bash
swift build --product J2KCLI
```

Run via Swift:

```bash
swift run J2KCLI <command> [options]
# or, once installed:
j2k <command> [options]
```

### CLI Encoding

```bash
# Lossless Part 1
j2k encode -i photo.ppm -o photo.j2k --lossless

# Lossy at quality 0.85
j2k encode -i photo.ppm -o photo.j2k --quality 0.85

# HTJ2K lossless
j2k encode -i photo.ppm -o photo.jph --htj2k --lossless

# Target bit-rate (bits per pixel)
j2k encode -i photo.ppm -o photo.j2k --bitrate 0.5

# Target compression ratio
j2k encode -i photo.ppm -o photo.jp2 --compression-ratio 20:1

# Target file size
j2k encode -i photo.ppm -o photo.jp2 --target-size 50000

# JP2 container
j2k encode -i photo.ppm -o photo.jp2 --format jp2

# Codec shorthand
j2k encode -i photo.ppm -o photo.jph --codec htj2k-lossy --quality 0.9
```

#### Output path auto-derivation

When `-o` is omitted, the output file name is derived from the input:

| Input | Flags | Output |
|-------|-------|--------|
| `photo.ppm` | `--lossless` | `photo.j2k` |
| `photo.ppm` | `--htj2k` | `photo.jph` |
| `photo.ppm` | `--format jp2` | `photo.jp2` |

### CLI Decoding

```bash
# Decode to PGM/PPM (auto-detected)
j2k decode -i photo.j2k

# Explicit output format
j2k decode -i photo.j2k -o photo.tiff --output-format tiff

# Header-only inspection
j2k decode -i photo.j2k --header-only --json

# Partial decode — resolution level
j2k decode -i photo.j2k -o thumb.pgm --level 2

# Partial decode — quality layer
j2k decode -i photo.j2k -o preview.ppm --layer 1
```

### Recommended Presets

#### Archival / medical imaging (lossless)

```bash
j2k encode -i scan.dcm -o scan.jp2 --lossless --format jp2 --levels 6
```

- Reversible 5/3 wavelet, RCT colour transform
- Pixel-exact reconstruction guaranteed
- Typical ratio: 2–3:1

#### Professional photography

```bash
j2k encode -i photo.ppm -o photo.jp2 --preset quality --quality 0.95 \
    --progression RPCL --format jp2
```

- 9/7 irreversible wavelet, 10 quality layers
- Visually transparent compression, ~8–12:1
- RPCL progression for streaming

#### Web delivery

```bash
j2k encode -i photo.ppm -o photo.jph --codec htj2k-lossy --quality 0.85 \
    --preset balanced
```

- HTJ2K for fast decode in browsers
- Good quality/size balance, ~15–25:1

#### Batch preview generation

```bash
j2k batch encode -i ./originals/ --output-dir ./previews/ \
    --preset fast --quality 0.7 --recursive
```

- Fast encoding, acceptable quality
- 2–3× faster than balanced

#### High-throughput pipeline (HTJ2K)

```bash
j2k encode -i frame.ppm -o frame.jph --codec htj2k-lossless
```

- High Throughput JPEG 2000 (Part 15)
- 5–10× faster decode than Part 1
- Lossless: ideal for ingest pipelines

#### Digital cinema (DCI 2K)

```bash
j2k encode -i frame.ppm -o frame.j2k --levels 5 \
    --blocksize 32x32 --progression CPRL \
    --bitrate 1.302 --tile-size 2048x1080
```

#### Large images with tiling

```bash
j2k encode -i satellite.ppm -o satellite.jp2 --tile-size 512x512 \
    --preset balanced --format jp2
```

### Best-Practice Commands

#### Lossless round-trip verification

```bash
j2k encode -i original.ppm -o encoded.j2k --lossless
j2k decode -i encoded.j2k -o decoded.ppm
j2k compare --reference original.ppm --distorted decoded.ppm --bit-exact
```

#### Quality comparison across presets

```bash
for preset in fast balanced quality; do
    j2k encode -i test.ppm -o "test_${preset}.j2k" --preset "$preset" --quiet
done
for f in test_*.j2k; do
    echo -n "$f: "; j2k info "$f" | head -3
done
```

#### Encode + validate + benchmark

```bash
j2k encode -i input.ppm -o output.jp2 --preset quality --format jp2
j2k validate output.jp2 --part1
j2k benchmark -i input.ppm --preset quality -r 5 --format csv -o bench.csv
```

#### Transcode Part 1 → HTJ2K with verification

```bash
j2k transcode -i legacy.j2k -o modern.jph --to-htj2k --verify
```

#### JSON-formatted encode for CI/CD

```bash
j2k encode -i test.ppm -o test.j2k --lossless --json --timing 2>/dev/null
```

### Piping & Scripting

Use `-` for stdin/stdout:

```bash
# Decode → re-encode via pipe
j2k decode -i input.j2k -o - | j2k encode -i - -o output.jph --htj2k

# Pipe from external tool
convert photo.jpg pgm:- | j2k encode -i - -o photo.j2k --lossless

# Pipe to external tool
j2k decode -i photo.j2k -o - | display -
```

When piping, diagnostic output goes to stderr.

---

## Choosing the Right Settings

| Scenario | Lossless? | Preset | HTJ2K? | Notes |
|----------|-----------|--------|--------|-------|
| Medical archival | Yes | — | No | Regulatory requirement |
| Satellite imagery | Yes | quality | No | Preserves radiometric data |
| Professional photo | No | quality | Optional | quality ≥ 0.95 |
| Web gallery | No | balanced | Yes | HTJ2K for fast decode |
| Video ingest | Yes | fast | Yes | Throughput matters |
| Thumbnails | No | fast | Optional | quality 0.5–0.7 |
| Digital cinema | No | — | No | DCI spec: CPRL, 1.3 bpp |

### Progression order guide

| Order | Best for |
|-------|----------|
| LRCP | Quality-first streaming |
| RLCP | Resolution-first viewing |
| RPCL | Network streaming / JPIP |
| PCRL | Spatial locality / ROI |
| CPRL | Per-component processing / DCI |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| "unsupported marker" on decode | Corrupt or non-J2K file | Run `j2k validate` first |
| Large lossless output | Expected — J2K lossless ≈ 2–3:1 | Use lossy if size matters |
| Slow encode | Large image, quality preset | Try `--preset fast` or `--tile-size 512x512` |
| Decoded colours differ | MCT mismatch | Check `--mct` / `--no-mct` |
| "invalid parameter" error | Out-of-range value | Check `j2k encode --help` for ranges |

---

*See also:*
[CLI_GUIDE.md](CLI_GUIDE.md) ·
[CLI_REFERENCE.md](CLI_REFERENCE.md) ·
[CLI_EXAMPLES.md](CLI_EXAMPLES.md) ·
[TUTORIAL_ENCODING.md](../TUTORIAL_ENCODING.md) ·
[TUTORIAL_DECODING.md](../TUTORIAL_DECODING.md)
