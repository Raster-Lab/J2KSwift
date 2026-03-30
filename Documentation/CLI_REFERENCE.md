# J2KSwift CLI Command Reference

Complete reference for all `j2k` CLI commands, flags, and options (v2.4.0).

## Global Flags

These flags are accepted by all commands:

| Flag | Description |
|------|-------------|
| `--verbose` | Verbose output |
| `--quiet` | Suppress non-error output |
| `--json` | Machine-readable JSON output |
| `--timing` | Show timing breakdown |
| `--progress` | Show progress bar/percentage |
| `--no-colour` / `--no-color` | Disable ANSI colour output |
| `--version` | Print version and exit |
| `--help` | Show help for command |

---

## encode

Compress an image to JPEG 2000 / HTJ2K.

```
j2k encode -i <input> -o <output> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i, --input PATH` | Input image file (PGM, PPM, PNM, RAW) | Required |
| `-o, --output PATH` | Output JPEG 2000 file | Required |
| `--codec VARIANT` | `j2k-lossless`, `j2k-lossy`, `htj2k-lossless`, `htj2k-lossy` | `j2k-lossless` |
| `--lossless` | Shorthand for `--codec j2k-lossless` | |
| `--htj2k` | Shorthand for `--codec htj2k-lossless` | |
| `-q, --quality FLOAT` | Quality factor 0.0–1.0 | `1.0` |
| `--compression-ratio N:1` | Target compression ratio | |
| `--compression-percent N` | Target size reduction percentage | |
| `--target-size BYTES` | Exact output size target | |
| `--psnr VALUE` | Target PSNR (dB) | |
| `--levels N` | DWT decomposition levels (0–10) | `5` |
| `--blocksize WxH` | Code-block size | `64x64` |
| `--layers N` | Quality layers (1–20) | `1` |
| `--format j2k\|jp2\|jpx\|jph` | Output container format | auto |
| `--progression ORDER` | `LRCP`, `RLCP`, `RPCL`, `PCRL`, `CPRL` | `LRCP` |
| `--tile-size WxH` | Tile size | none |
| `--roi x,y,w,h` | Region of interest | |
| `--roi-file PATH` | ROI mask from external file | |
| `--roi-priority LEVEL` | `HIGH`, `MEDIUM`, `LOW` | |
| `--mct / --no-mct` | Multi-component transform | `--mct` |
| `--colour-space CS` | Colour space (`srgb`, `ycbcr`, `gray`) | auto |
| `--threads N` | Parallel threads | system |
| `--gpu / --no-gpu` | GPU acceleration | auto |
| `--estimate` | Estimate output without encoding | |
| `--memory-limit BYTES` | Peak memory cap | |
| `--profile` | Internal profiling output | |

### Examples

```bash
# Lossless JPEG 2000 encode
j2k encode -i photo.ppm -o photo.j2k --lossless

# HTJ2K lossy at 20:1 compression
j2k encode -i photo.ppm -o photo.jph --codec htj2k-lossy --compression-ratio 20:1

# Encode with target PSNR
j2k encode -i scan.pgm -o scan.jp2 --codec j2k-lossy --psnr 45
```

---

## decode

Decompress a JPEG 2000 / HTJ2K image.

```
j2k decode -i <input> -o <output> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i, --input PATH` | Input JPEG 2000 file | Required |
| `-o, --output PATH` | Output image file | Required |
| `--region x,y,w,h` | Decode specific region | full |
| `--scale N` | Resolution reduction (1, 2, 4, 8) | `1` |
| `--level N` | Resolution level | max |
| `--layer N` | Quality layer | all |
| `--strip-alpha` | Discard alpha channel | |
| `--output-format FMT` | `pgm`, `ppm`, `pnm`, `raw` | auto |
| `--bit-depth N` | Output bit depth (8, 16) | source |
| `--color-convert` | Colour space conversion | |
| `--header-only` | Print info without decode | |
| `--threads N` | Parallel threads | system |

### Examples

```bash
# Basic decode
j2k decode -i photo.j2k -o photo.pgm

# Decode a region at half resolution
j2k decode -i large.jp2 -o region.pgm --region 0,0,512,512 --scale 2

# Header-only inspection
j2k decode -i file.j2k --header-only --json
```

---

## transcode

Lossless transcoding between JPEG 2000 Part 1 and HTJ2K.

```
j2k transcode -i <input> -o <output> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--to-htj2k` | Transcode to HTJ2K | |
| `--from-htj2k` | Transcode from HTJ2K to Part 1 | |
| `--format FMT` | Output format (`j2k`, `jp2`, `jpx`, `jph`) | auto |
| `--progression ORDER` | Progression order | preserve |
| `--verify` | Verify lossless transcoding | |
| `--verify-mode MODE` | `exact` or `statistical` | `exact` |
| `--preserve-metadata` | Carry forward metadata | on |
| `--strip-metadata` | Remove non-essential metadata | |
| `--batch DIR` | Batch input directory | |
| `--output-dir DIR` | Batch output directory | |
| `--report PATH` | Save transcoding report | |
| `--threads N` | Parallel threads | system |

### Examples

```bash
# Lossless J2K → HTJ2K
j2k transcode -i legacy.j2k -o modern.jph --to-htj2k --verify

# Batch transcode a directory
j2k transcode --batch ./legacy/ --output-dir ./htj2k/ --to-htj2k --verify --threads 4
```

---

## encode3d

Compress volumetric / 3D data using JP3D.

```
j2k encode3d -i <input> -o <output> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i, --input PATH\|DIR` | Input slices directory or raw file | Required |
| `-o, --output PATH` | Output JP3D file | Required |
| `--codec VARIANT` | `j2k-lossless`, `j2k-lossy`, `htj2k-lossless`, `htj2k-lossy` | `j2k-lossless` |
| `--dimensions WxHxD` | Volume dimensions (raw input) | |
| `--bit-depth N` | Input bit depth (raw input) | `8` |
| `--frames N` | Number of frames | |
| `--compression-ratio N:1` | Target compression ratio | |
| `--tile-size WxHxD` | 3D tile size | |
| `--decomposition-levels X,Y,Z` | Per-axis DWT levels | |
| `--progression ORDER` | 3D progression order | |
| `--parallel / --no-parallel` | Parallel slice encoding | `--parallel` |
| `--psnr VALUE` | Target PSNR (dB) | |

### Examples

```bash
# Lossless 3D encode from slice directory
j2k encode3d -i ./slices/ -o volume.jp3d --codec j2k-lossless

# Lossy HTJ2K from raw volume
j2k encode3d -i volume.raw -o volume.jp3d --dimensions 256x256x128 --bit-depth 16 --codec htj2k-lossy --psnr 45
```

---

## decode3d

Decompress volumetric / 3D JP3D data.

```
j2k decode3d -i <input> -o <output> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i, --input PATH` | Input JP3D file | Required |
| `--output-dir DIR` | Output slices directory | |
| `-o, --output PATH` | Output raw file | |
| `--output-format FMT` | `pgm`, `ppm`, `raw` | `pgm` |
| `--slice-range START-END` | Extract slice range | all |
| `--region x,y,z,w,h,d` | 3D region of interest | |
| `--scale N` | Multi-resolution decode | `1` |
| `--slice-pattern PATTERN` | Output filename pattern | `slice_%03d.pgm` |
| `--raw` | Output as raw volumetric data | |

### Examples

```bash
# Decode 3D volume to slices
j2k decode3d -i volume.jp3d --output-dir ./slices/ --output-format pgm

# Extract slice range
j2k decode3d -i volume.jp3d --output-dir ./subset/ --slice-range 10-20
```

---

## jpip server

Start a JPIP streaming server.

```
j2k jpip server [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--port N` | Listening port | `8080` |
| `--host ADDRESS` | Bind address | `0.0.0.0` |
| `--data-dir DIR` | Image directory to serve | |
| `--single-file PATH` | Serve a single file | |
| `--mode 2d\|3d` | Serving mode | `2d` |
| `--max-sessions N` | Max concurrent sessions | `10` |
| `--session-timeout SEC` | Session idle timeout | `300` |
| `--transport PROTO` | `http` or `websocket` | `http` |
| `--tls-cert PATH` | TLS certificate | |
| `--tls-key PATH` | TLS private key | |
| `--access-log PATH` | Access log file | |

### Examples

```bash
# Serve a directory of images
j2k jpip server --data-dir ./images/ --port 8080

# Serve a single file with verbose logging
j2k jpip server --single-file large_image.jp2 --port 9090 --verbose
```

---

## jpip client

Connect to a JPIP server and retrieve image data.

```
j2k jpip client --server URL --target NAME [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--server URL` | JPIP server URL | Required |
| `--target NAME` | Target image on server | Required |
| `-o, --output PATH` | Output file | |
| `--region x,y,w,h` | Region window | full |
| `--resolution-level N` | Resolution level | max |
| `--quality-layers N` | Quality layers | all |
| `--progressive` | Progressive rendering | |
| `--progressive-dir DIR` | Progressive output directory | |
| `--max-bandwidth BPS` | Bandwidth throttle | |
| `--session-type TYPE` | `stateless` or `stateful` | |
| `--interactive` | Interactive mode | |

### Examples

```bash
# Download a region from a JPIP server
j2k jpip client --server http://localhost:8080 --target image.jp2 --region 0,0,256,256 -o region.pgm

# Interactive mode
j2k jpip client --server http://localhost:8080 --target image.jp2 --interactive
```

---

## batch

Batch-process files in a directory.

```
j2k batch <encode|decode|transcode|encode3d|decode3d> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i, --input DIR` | Input directory | Required |
| `-o, --output-dir DIR` | Output directory | Required |
| `--filter GLOB` | Include filter | |
| `--exclude GLOB` | Exclude filter | |
| `--recursive` | Recursive traversal | |
| `--continue-on-error` | Fault-tolerant processing | |
| `--threads N` | Parallel threads | system |
| `--output-suffix EXT` | Output file extension | |

Plus all options from the underlying command.

### Examples

```bash
# Batch encode a directory
j2k batch encode -i ./images/ --output-dir ./encoded/ --codec htj2k-lossless --recursive

# Batch decode with filtering
j2k batch decode -i ./encoded/ --output-dir ./decoded/ --filter "*.jp2" --threads 4
```

---

## compare

Compare two images (PSNR, MSE, MAE, bit-exact).

```
j2k compare --reference <original> --distorted <reconstructed> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--reference PATH` | Reference (original) image | Required |
| `--distorted PATH` | Distorted (decoded) image | Required |
| `--metric METRIC` | `psnr`, `mse`, `mae`, `maxerr`, `all` | `all` |
| `--bit-exact` | Verify bit-exact match | |
| `--mode 2d\|3d` | Comparison mode | `2d` |

---

## convert

Convert between image formats.

```
j2k convert -i <input> -o <output> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i, --input PATH` | Input file | Required |
| `-o, --output PATH` | Output file | Required |
| `--bit-depth N` | Output bit depth | source |
| `--strip-alpha` | Discard alpha channel | |
| `--output-format FMT` | Output format | auto |

---

## info

Display codestream / file-format metadata.

```
j2k info <file> [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--markers` | List codestream markers |
| `--boxes` | List JP2/JPX boxes |
| `--validate` | Quick conformance check |
| `--capabilities` | Display library capabilities |
| `--list-gpus` | List available GPU devices |

---

## validate

Conformance validation.

```
j2k validate <file> [options]
```

### Options

| Flag | Description |
|------|-------------|
| `--part1` | Part 1 conformance |
| `--part2` | Part 2 conformance |
| `--part15` | Part 15 (HTJ2K) conformance |
| `--strict` | Strict validation |

---

## benchmark

Performance benchmarking.

```
j2k benchmark -i <input> [options]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--mode 2d\|3d\|jpip` | Benchmark mode | `2d` |
| `-r, --runs N` | Measurement runs | `3` |
| `--warmup N` | Warm-up runs | `1` |
| `-o, --output PATH` | Output report file | |
| `--format FMT` | `text`, `json`, `csv` | `text` |
| `--encode-only` | Only benchmark encoding | |
| `--decode-only` | Only benchmark decoding | |

---

## completions

Generate shell completions.

```
j2k completions bash|zsh|fish
```

### Examples

```bash
# Bash
j2k completions bash > ~/.local/share/bash-completion/completions/j2k

# Zsh
j2k completions zsh > ~/.zfunc/_j2k

# Fish
j2k completions fish > ~/.config/fish/completions/j2k.fish
```

---

## version

Print version and exit.

```
j2k version
```
