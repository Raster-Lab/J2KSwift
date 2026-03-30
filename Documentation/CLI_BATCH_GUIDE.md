# Batch Processing CLI Guide

Efficient batch encoding, decoding, and transcoding with the `j2k` CLI.

## Overview

The `j2k` CLI supports batch operations through the `batch` subcommand and the `--input-dir` / `--output-dir` pattern. Batch mode processes multiple files concurrently with configurable parallelism, progress tracking, and error handling.

## Quick Start

```bash
# Encode all PGM/PPM files in a directory
j2k batch encode --input-dir ./images/ --output-dir ./compressed/ --format jp2

# Decode all JP2 files
j2k batch decode --input-dir ./compressed/ --output-dir ./decoded/

# Transcode (e.g., JP2 → JPC)
j2k batch transcode --input-dir ./jp2/ --output-dir ./jpc/ --format j2k
```

## Batch Encoding

### Basic

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./compressed/
```

### With Compression Options

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./compressed/ \
    --format jp2 \
    --compression-ratio 20 \
    --wavelet 9/7 \
    --decomposition-levels 5 \
    --quality-layers 3
```

### Lossless Batch

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./lossless/ \
    --wavelet 5/3 --format jp2
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--input-dir DIR` | Source directory | Required |
| `--output-dir DIR` | Destination directory | Required |
| `--format jp2\|j2k\|jph` | Output format | `jp2` |
| `--compression-ratio N` | Target compression ratio | `1` |
| `--wavelet 5/3\|9/7` | Wavelet filter | `5/3` |
| `--decomposition-levels N` | DWT levels | `5` |
| `--quality-layers N` | Quality layers | `1` |
| `--tile-size WxH` | Tile dimensions | `256x256` |
| `--parallel N` | Number of concurrent jobs | CPU count |
| `--recursive` | Search subdirectories | `false` |
| `--overwrite` | Overwrite existing outputs | `false` |
| `--dry-run` | List files without processing | `false` |
| `--continue-on-error` | Skip failed files | `false` |
| `--verbose` | Verbose progress | `false` |
| `--json` | JSON output | `false` |

## Batch Decoding

```bash
j2k batch decode --input-dir ./compressed/ --output-dir ./decoded/ \
    --format pgm --parallel 8
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--input-dir DIR` | Source directory | Required |
| `--output-dir DIR` | Destination directory | Required |
| `--format pgm\|ppm\|raw` | Output format | `pgm` |
| `--resolution-level N` | Resolution reduction | `0` |
| `--quality-layers N` | Quality layers | All |
| `--region x,y,w,h` | Decode region | Full |
| `--parallel N` | Concurrent jobs | CPU count |
| `--recursive` | Search subdirectories | `false` |
| `--overwrite` | Overwrite existing | `false` |
| `--continue-on-error` | Skip failed files | `false` |

## Batch Transcoding

```bash
j2k batch transcode --input-dir ./jp2/ --output-dir ./jpc/ \
    --format j2k --lossless --parallel 4
```

Transcoding allows changing file formats, compression parameters, or progression orders without full decode-encode round-trips (where possible).

## Parallelism

### Automatic

By default, the `batch` command uses all available CPU cores:

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./out/
# Uses ProcessInfo.processInfo.activeProcessorCount workers
```

### Manual

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./out/ --parallel 4
```

### Memory-Constrained Environments

For very large images, limit concurrency to control peak memory:

```bash
j2k batch encode --input-dir ./large/ --output-dir ./out/ --parallel 2
```

## Progress Tracking

### Terminal Progress

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./out/ --verbose
```

```
[  1/100] Encoding image001.pgm → image001.jp2 ... done (0.23s, 4.2x)
[  2/100] Encoding image002.pgm → image002.jp2 ... done (0.19s, 5.1x)
...
[100/100] Encoding image100.pgm → image100.jp2 ... done (0.21s, 4.6x)

Summary: 100/100 succeeded, 0 failed, total 18.7s
```

### JSON Summary

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./out/ --json
```

```json
{
  "operation": "encode",
  "totalFiles": 100,
  "succeeded": 100,
  "failed": 0,
  "skipped": 0,
  "timing": {
    "total": 18.7,
    "average": 0.187,
    "fastest": 0.12,
    "slowest": 0.34
  },
  "compression": {
    "inputSize": 104857600,
    "outputSize": 22020096,
    "averageRatio": 4.76
  }
}
```

## Error Handling

### Stop on First Error (Default)

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./out/
```

### Continue on Error

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./out/ --continue-on-error
```

Failed files are reported at the end:

```
Summary: 97/100 succeeded, 3 failed

Failed:
  corrupt.pgm: Invalid PGM header
  truncated.pgm: Unexpected end of file
  zero.pgm: Invalid image dimensions (0×0)
```

### Dry Run

Preview what would be processed:

```bash
j2k batch encode --input-dir ./raw/ --output-dir ./out/ --dry-run
```

```
Would process 100 files:
  image001.pgm → image001.jp2
  image002.pgm → image002.jp2
  ...
```

## Filtering

### By Extension

Only files with recognized extensions are processed:
- Encoding: `.pgm`, `.ppm`, `.raw`
- Decoding: `.jp2`, `.j2k`, `.j2c`, `.jpc`, `.jph`, `.jp3d`

### Recursive

```bash
j2k batch encode --input-dir ./dataset/ --output-dir ./out/ --recursive
```

Preserves subdirectory structure in the output.

## Multi-File Input

The main `encode`, `decode`, and `transcode` commands also support multi-file patterns:

```bash
# Glob patterns
j2k encode -i "*.pgm" -o ./out/ --format jp2

# Multiple input files
j2k encode -i a.pgm -i b.pgm -i c.pgm -o ./out/ --format jp2
```

## 3D Batch Processing

```bash
j2k batch encode3d --input-dir ./volumes/ --output-dir ./compressed/ \
    --tile-size 256,256,32 --compression-ratio 10 --parallel 2
```

## Performance Tips

1. **Use `--parallel`** appropriate for your system — CPU-bound workloads benefit from core count, I/O-bound from 2×.
2. **SSD storage** significantly improves batch performance for many small files.
3. **`--dry-run` first** to estimate job size before committing.
4. **`--continue-on-error`** for production pipelines to avoid halting on a single bad file.
5. **Lower `--parallel`** for very large images to control peak memory.
