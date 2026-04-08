# J2KSwift CLI Reference Guide

A comprehensive reference for the `j2k` command-line tool.

---

## Overview

`j2k` is the command-line interface for J2KSwift, a pure-Swift JPEG 2000 encoder/decoder. It provides commands for encoding, decoding, transcoding, validating, and benchmarking JPEG 2000 images.

```
j2k <command> [options]
```

---

## Global Flags

| Flag | Description |
|------|-------------|
| `--version` | Print version and exit |
| `--help` / `-h` | Show help message |

---

## Commands

### `encode`

Encode a raster image into JPEG 2000 format.

```
j2k encode -i <input> -o <output> [options]
```

#### Input / Output Options

| Option | Description |
|--------|-------------|
| `-i`, `--input PATH` | Input image file (PGM, PPM, PNM, TIFF, PNG, DICOM, RAW) |
| `-o`, `--output PATH` | Output file (`.j2k`, `.jp2`, `.jpx`) |
| `--format j2k\|jp2\|jpx` | Output container format (default: `j2k`) |

#### Quality Modes (mutually exclusive)

| Option | Description |
|--------|-------------|
| `--lossless` | Lossless compression (reversible wavelet + no quantisation) |
| `--quality FLOAT` | Lossy quality, 0.0–1.0 (default: `1.0`) |
| `--bitrate BPP` | Target bit-rate in bits per pixel |
| `--psnr VALUE` | Target PSNR in dB |
| `--visually-lossless` | Near-lossless preset (quality ≈ 0.99) |

#### Structural Options

| Option | Description |
|--------|-------------|
| `--preset fast\|balanced\|quality` | Encoding preset |
| `--levels N` | DWT decomposition levels, 0–10 (default: `5`) |
| `--blocksize WxH` | Code-block size, e.g. `64x64` (default: `64x64`) |
| `--layers N` | Quality layers, 1–20 (default: `5`) |
| `--progression ORDER` | `LRCP` · `RLCP` · `RPCL` · `PCRL` · `CPRL` |
| `--tile-size WxH` | Tile dimensions, e.g. `256x256` |
| `--precincts WxH` | Precinct size, e.g. `128x128` |
| `--roi x,y,w,h` | Region of interest |
| `--htj2k` | Enable HTJ2K (Part 15) block coder |
| `--codec VARIANT` | Codec variant: `j2k-lossless`, `j2k-lossy`, `htj2k-lossless`, `htj2k-lossy`, `htj2k-lossless-rpcl` |
| `--mct` / `--no-mct` | Enable / disable multi-component transform |
| `--compression-ratio N` | Target compression ratio (e.g. `20` for 20:1) |
| `--compression-percent N` | Target compression as a percentage |
| `--target-size BYTES` | Target compressed size in bytes |

#### Platform / Output Options

| Option | Description |
|--------|-------------|
| `--gpu` / `--no-gpu` | GPU acceleration (platform-dependent) |
| `--colour-space CS` | Set colour space (synonym: `--color-space`) |
| `--verbose` | Verbose output |
| `--quiet` | Suppress non-error output |
| `--timing` | Show timing breakdown |
| `--json` | JSON output |

#### Dual-spelling support

`--colour` and `--color` are synonyms; `--optimise` and `--optimize` are synonyms.

---

### `decode`

Decode a JPEG 2000 file to a raster image.

```
j2k decode -i <input> -o <output> [options]
```

#### Options

| Option | Description |
|--------|-------------|
| `-i`, `--input PATH` | Input JPEG 2000 file (`.j2k`, `.jp2`, `.jpx`) |
| `-o`, `--output PATH` | Output image file (`.pgm`, `.ppm`, `.tiff`, `.png`) |
| `--level N` | Resolution level (0 = full; higher = lower resolution) |
| `--layer N` | Maximum quality layer to decode |
| `--component N` | Decode a single component by index |
| `--components N,M,...` | Comma-separated component indices |
| `--header-only` | Print codestream header information without decoding |
| `--bit-depth N` | Override output bit depth |
| `--strip-alpha` | Remove alpha channel from output |
| `--colour-space` | Perform colour-space conversion |
| `--gpu` / `--no-gpu` | GPU acceleration |
| `--verbose` | Verbose output |
| `--quiet` | Suppress non-error output |
| `--timing` | Show timing breakdown |
| `--json` | JSON output |

---

### `info`

Display metadata about a JPEG 2000 file.

```
j2k info <file> [options]
```

#### Options

| Option | Description |
|--------|-------------|
| `--markers` | List all codestream marker segments |
| `--boxes` | List JP2/JPX file-format boxes |
| `--capabilities` | Show supported features and platform capabilities |
| `--json` | Output as JSON |
| `--validate` | Quick conformance check (exits 0 if valid, 1 if not) |

#### Example output

```
File:         image.jp2
Format:       jp2
File size:    1.23 MB
Dimensions:   1920 × 1080
Components:   3
Colour space: sRGB
HTJ2K:        no

Components:
  [0] 1920×1080, 8-bit unsigned
  [1] 1920×1080, 8-bit unsigned
  [2] 1920×1080, 8-bit unsigned
```

---

### `transcode`

Re-encode a JPEG 2000 file in a different format or quality setting.

```
j2k transcode -i <input> -o <output> [options]
j2k transcode --batch <dir> --output-dir <dir> [options]
```

#### Single-file Options

| Option | Description |
|--------|-------------|
| `-i`, `--input PATH` | Input JPEG 2000 file |
| `-o`, `--output PATH` | Output JPEG 2000 file |
| `--to-htj2k` | Transcode to HTJ2K (Part 15) via coefficient-domain resampling |
| `--from-htj2k` | Transcode from HTJ2K to Part 1 |
| `--verify` | Verify output by decoding and comparing against input |
| `--format j2k\|jp2\|jpx` | Output container format |
| `--quality VALUE` | Output quality (0.0–1.0) |
| `--bitrate BPP` | Target bit-rate |
| `--layers N` | Output quality layers |
| `--progression ORDER` | Progression order |

#### Batch Options

| Option | Description |
|--------|-------------|
| `--batch DIR` | Input directory; processes all `.j2k`, `.jp2`, `.jpx` files |
| `--output-dir DIR` | Output directory (created if it does not exist) |

#### Common Options

| Option | Description |
|--------|-------------|
| `--verbose` | Verbose per-file output |
| `--quiet` | Suppress non-error output |

---

### `validate`

Check a JPEG 2000 file for conformance.

```
j2k validate <file> [options]
```

#### Options

| Option | Description |
|--------|-------------|
| `--part1` | ISO/IEC 15444-1 (Part 1) conformance check |
| `--part2` | ISO/IEC 15444-2 (Part 2) conformance check |
| `--part15` | ISO/IEC 15444-15 (HTJ2K) conformance check |
| `--strict` | Also report warnings |
| `--json` | Output as JSON |
| `--quiet` | Suppress non-error output |

#### Exit codes

| Code | Meaning |
|------|---------|
| `0` | File is valid |
| `1` | File is invalid or an error occurred |

---

### `benchmark`

Measure encoding and decoding throughput.

```
j2k benchmark -i <input> [options]
```

#### Options

| Option | Description |
|--------|-------------|
| `-i`, `--input PATH` | Input image for benchmarking |
| `-r`, `--runs N` | Measurement runs (default: `3`) |
| `--warmup N` | Warm-up runs before measurement (default: `1`) |
| `-o`, `--output PATH` | Save report to file |
| `--format text\|json\|csv` | Output format (default: `text`) |
| `--encode-only` | Only benchmark encoding |
| `--decode-only` | Only benchmark decoding |
| `--preset fast\|balanced\|quality` | Encoder preset |
| `--compare-openjpeg` | Note whether OpenJPEG comparison is available |

#### Statistics reported

- Average, median, min, max, standard deviation (ms)
- Throughput (megapixels per second)
- Compressed size and compression ratio (encode only)

---

### `version`

Print the J2KSwift version.

```
j2k version
j2k --version
```

---

## Input / Output Formats

### Supported input formats (encode)

| Format | Extension | Notes |
|--------|-----------|-------|
| PGM | `.pgm` | 8-bit and 16-bit greyscale |
| PPM | `.ppm` | 8-bit and 16-bit colour |
| PNM | `.pnm` | Auto-detected |
| TIFF | `.tiff`, `.tif` | 8-bit and 16-bit, greyscale and colour |
| PNG | `.png` | 8-bit and 16-bit, greyscale and colour |
| DICOM | `.dcm` | Medical imaging format |
| RAW | `.raw` | Requires explicit dimensions |

### Supported output formats (decode)

| Format | Extension | Notes |
|--------|-----------|-------|
| PGM | `.pgm` | Greyscale output |
| PPM | `.ppm` | Colour output |
| TIFF | `.tiff`, `.tif` | Greyscale and colour output |
| PNG | `.png` | Greyscale and colour output |

### Supported JPEG 2000 formats

| Format | Extension | Description |
|--------|-----------|-------------|
| Raw codestream | `.j2k`, `.jpc` | ISO 15444-1 codestream |
| JP2 container | `.jp2` | JP2 file format with metadata boxes |
| JPX container | `.jpx` | Extended JP2 file format |

---

## Shell Completions

Shell completion scripts are provided in `Scripts/completions/`:

```bash
# Bash
source Scripts/completions/j2k.bash

# Zsh
fpath=(Scripts/completions $fpath)
autoload -Uz compinit && compinit

# Fish
cp Scripts/completions/j2k.fish ~/.config/fish/completions/
```
