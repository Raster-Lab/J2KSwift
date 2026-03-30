# 3D Volumetric CLI Guide

Encoding and decoding 3D volumetric (JP3D) data with the `j2k` CLI.

## Overview

The `j2k` CLI provides `encode3d` and `decode3d` commands for JPEG 2000 Part 10 (JP3D) volumetric data — commonly used in medical imaging (DICOM), scientific datasets, and geospatial applications.

## Encoding 3D Volumes

### From a directory of slices

```bash
j2k encode3d -i ./slices/ -o volume.jp3d --slice-order ascending
```

Each file in the directory is treated as one Z-slice. Supported input formats: PGM, PPM, raw.

### With compression parameters

```bash
j2k encode3d -i ./slices/ -o volume.jp3d \
    --compression-ratio 10 \
    --tile-size 256,256,32 \
    --decomposition-levels 5 \
    --wavelet 9/7
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i PATH` | Input directory of slices or raw volume | Required |
| `-o FILE` | Output JP3D file | Required |
| `--width N` | Slice width (for raw input) | Detect |
| `--height N` | Slice height (for raw input) | Detect |
| `--depth N` | Number of slices (for raw input) | Detect |
| `--bit-depth N` | Bits per sample | `8` |
| `--signed` | Signed sample data | `false` |
| `--compression-ratio N` | Target compression ratio | `1` (lossless) |
| `--tile-size W,H,D` | 3D tile dimensions | `256,256,256` |
| `--decomposition-levels N` | DWT decomposition levels | `5` |
| `--wavelet 5/3\|9/7` | Wavelet filter | `5/3` |
| `--slice-order ascending\|descending` | Z-slice ordering | `ascending` |
| `--progression LRCP\|RLCP\|RPCL\|PCRL\|CPRL` | Progression order | `LRCP` |
| `--codeblock-size W,H,D` | 3D codeblock size | `64,64,64` |
| `--roi REGION` | Region of interest (`x,y,z,w,h,d`) | |
| `--quality-layers N` | Number of quality layers | `1` |
| `--verbose` | Verbose output | `false` |
| `--json` | JSON output | `false` |

### Raw Volume Input

For raw binary volumes with no headers:

```bash
j2k encode3d -i volume.raw -o volume.jp3d \
    --width 512 --height 512 --depth 128 \
    --bit-depth 16 --signed
```

### Lossless 3D Encoding

```bash
j2k encode3d -i ./slices/ -o volume.jp3d --wavelet 5/3
```

The reversible 5/3 wavelet ensures exact reconstruction of every voxel.

## Decoding 3D Volumes

### To a directory of slices

```bash
j2k decode3d -i volume.jp3d -o ./output_slices/
```

### Selected slices only

```bash
j2k decode3d -i volume.jp3d -o ./output_slices/ --slice-range 10-20
```

### To raw binary volume

```bash
j2k decode3d -i volume.jp3d -o volume.raw --format raw
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i FILE` | Input JP3D file | Required |
| `-o PATH` | Output directory or raw file | Required |
| `--format pgm\|ppm\|raw` | Output format | `pgm` |
| `--slice-range START-END` | Decode specific Z-range | All |
| `--resolution-level N` | Resolution reduction level | `0` (full) |
| `--quality-layers N` | Number of quality layers | All |
| `--region x,y,z,w,h,d` | Decode a 3D sub-region | Full |
| `--verbose` | Verbose output | `false` |
| `--json` | JSON output | `false` |

## Common Workflows

### Medical Imaging (DICOM)

```bash
# Convert DICOM slices to JP3D
j2k encode3d -i ./dicom_slices/ -o scan.jp3d \
    --bit-depth 16 --signed --wavelet 5/3

# Extract specific anatomy
j2k decode3d -i scan.jp3d -o ./region/ --region 100,100,20,256,256,40
```

### Progressive Exploration

```bash
# Quick low-resolution preview
j2k decode3d -i volume.jp3d -o ./preview/ --resolution-level 3

# Medium quality
j2k decode3d -i volume.jp3d -o ./medium/ --quality-layers 2

# Full quality, specific slices
j2k decode3d -i volume.jp3d -o ./slices/ --slice-range 50-75
```

### Batch Processing Multiple Volumes

```bash
j2k batch encode3d --input-dir ./volumes/ --output-dir ./compressed/ \
    --compression-ratio 10 --parallel 4
```

## Streaming 3D Data with JPIP

```bash
# Serve 3D volume
j2k jpip server --data-dir ./volumes/ --mode 3d --port 8080

# Stream specific slices
j2k jpip client --server http://localhost:8080 --target volume.jp3d \
    --mode 3d --slice-range 10-20 -o ./slices/
```

## JSON Output

```bash
j2k encode3d -i ./slices/ -o volume.jp3d --json
```

```json
{
  "input": "./slices/",
  "output": "volume.jp3d",
  "dimensions": { "width": 512, "height": 512, "depth": 128 },
  "compression": {
    "wavelet": "5/3",
    "ratio": 1.0,
    "lossless": true
  },
  "outputSize": 16777216,
  "timing": {
    "encoding": 4.123,
    "total": 4.567
  }
}
```

## Validation

```bash
j2k validate volume.jp3d --strict
```

Validates JP3D file structure, marker segments, and tile-part headers.
