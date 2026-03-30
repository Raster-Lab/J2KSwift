# Cross-Library CLI Syntax Specification

A unified syntax specification for `j2k` CLI arguments and conventions, designed for consistency across all J2KSwift modules.

## Overview

This document specifies the naming conventions, flag syntax, and output formatting shared across all `j2k` CLI commands (encode, decode, transcode, encode3d, decode3d, jpip, batch, compare, convert, info, validate, benchmark, completions, version). Adherence to these conventions ensures a predictable and scriptable user experience.

## General Conventions

### Flag Naming

All flags use **GNU-style long options** with short aliases for common flags.

| Convention | Example |
|-----------|---------|
| Long form | `--compression-ratio 10` |
| Short alias | `-i input.pgm` |
| Kebab-case | `--quality-layers`, `--tile-size` |
| Boolean (positive) | `--verbose`, `--lossless` |
| Boolean (negative) | `--no-color`, `--no-progress` |

### Short Aliases

The following short aliases are reserved and consistent across all commands:

| Short | Long | Meaning |
|-------|------|---------|
| `-i` | `--input` | Input file or directory |
| `-o` | `--output` | Output file or directory |
| `-v` | `--verbose` | Verbose output |
| `-q` | `--quiet` | Suppress non-error output |
| `-h` | `--help` | Show help text |

### Value Syntax

| Type | Syntax | Examples |
|------|--------|---------|
| Integer | `N` | `--decomposition-levels 5` |
| Float | `N.N` | `--compression-ratio 10.0` |
| String | `VALUE` | `--format jp2` |
| Dimensions (2D) | `WxH` or `W,H` | `--tile-size 256x256` or `--tile-size 256,256` |
| Dimensions (3D) | `W,H,D` | `--tile-size 256,256,32` |
| Region (2D) | `x,y,w,h` | `--region 0,0,512,512` |
| Region (3D) | `x,y,z,w,h,d` | `--region 0,0,0,256,256,64` |
| Range | `START-END` | `--slice-range 10-20` |
| Enum | `value` | `--wavelet 9/7`, `--progression LRCP` |
| Path | `PATH` | `-i ./images/img.pgm` |
| URL | `URL` | `--server http://localhost:8080` |

### Enumerations

#### Wavelet Filter

| Value | Meaning |
|-------|---------|
| `5/3` | Reversible 5/3 (lossless) |
| `9/7` | Irreversible 9/7 (lossy) |

#### Output Format

| Value | Context |
|-------|---------|
| `jp2` | JPEG 2000 Part 1 (JP2 container) |
| `j2k` / `j2c` / `jpc` | JPEG 2000 codestream |
| `jph` | HTJ2K (Part 15) |
| `jp3d` | 3D volumetric (Part 10) |
| `pgm` | Portable Graymap (decode output) |
| `ppm` | Portable Pixmap (decode output) |
| `raw` | Raw binary (decode output) |

#### Progression Order

| Value | Name |
|-------|------|
| `LRCP` | Layer-Resolution-Component-Position |
| `RLCP` | Resolution-Layer-Component-Position |
| `RPCL` | Resolution-Position-Component-Layer |
| `PCRL` | Position-Component-Resolution-Layer |
| `CPRL` | Component-Position-Resolution-Layer |

## Cross-Module Flag Mapping

These flags share the same name and semantics wherever they appear:

| Flag | Commands | Type | Description |
|------|----------|------|-------------|
| `--compression-ratio` | encode, encode3d, batch | Float | Target compression ratio |
| `--wavelet` | encode, encode3d, transcode, batch | Enum | Wavelet filter |
| `--decomposition-levels` | encode, encode3d, batch | Int | DWT decomposition levels |
| `--quality-layers` | encode, decode, encode3d, decode3d, batch | Int | Quality layers |
| `--tile-size` | encode, encode3d, batch | Dims | Tile dimensions |
| `--progression` | encode, encode3d, transcode | Enum | Progression order |
| `--codeblock-size` | encode, encode3d | Dims | Codeblock size |
| `--resolution-level` | decode, decode3d | Int | Resolution reduction |
| `--region` | decode, decode3d | Region | Decode region |
| `--format` | encode, decode, batch, convert | Enum | Output format |
| `--parallel` | batch | Int | Concurrent workers |
| `--recursive` | batch | Bool | Search subdirectories |
| `--overwrite` | batch | Bool | Overwrite existing |
| `--continue-on-error` | batch | Bool | Skip failed files |
| `--dry-run` | batch | Bool | Preview only |
| `--verbose` | all | Bool | Verbose output |
| `--json` | all | Bool | JSON output |
| `--quiet` | all | Bool | Suppress output |

## Output Formatting

### Standard Output

Human-readable by default:

```
Encoded image.pgm → image.jp2 (4096×4096, 3 components, ratio 10.2:1, 0.34s)
```

### JSON Output (`--json`)

Machine-readable JSON to stdout:

```json
{
  "status": "success",
  "input": "image.pgm",
  "output": "image.jp2",
  "width": 4096,
  "height": 4096,
  "components": 3,
  "compressionRatio": 10.2,
  "timing": { "total": 0.34 }
}
```

### Verbose Output (`--verbose`)

Extended human-readable to stderr:

```
[INFO] Reading input: image.pgm (4096×4096, 3 components, 8-bit)
[INFO] Applying ICT color transform
[INFO] DWT: 5 levels, 9/7 filter
[INFO] Tier-1 coding: 256 codeblocks
[INFO] Tier-2 packaging: LRCP progression
[INFO] Writing JP2 container: image.jp2
[INFO] Done: 4.0 MB → 392 KB (ratio 10.2:1) in 0.34s
```

### Error Output

All errors go to stderr:

```
Error: Cannot read input file: missing.pgm (No such file or directory)
```

JSON errors:

```json
{
  "status": "error",
  "message": "Cannot read input file: missing.pgm",
  "code": "FILE_NOT_FOUND"
}
```

## Exit Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error |
| `2` | Invalid arguments / usage error |
| `3` | Input file error (not found, permission, corrupt) |
| `4` | Output file error (permission, disk full) |
| `5` | Codec error (encoding/decoding failure) |
| `6` | Network error (JPIP) |
| `7` | Validation failure |

## Shell Completion

```bash
# Generate completions
j2k completions --shell bash > /etc/bash_completion.d/j2k
j2k completions --shell zsh > ~/.zsh/completions/_j2k
j2k completions --shell fish > ~/.config/fish/completions/j2k.fish
```

## Piping and Scripting

### stdin/stdout

```bash
cat image.pgm | j2k encode -i - -o - --format j2k > output.j2k
cat input.jp2 | j2k decode -i - -o - --format pgm > output.pgm
```

### Scripting with JSON

```bash
j2k info image.jp2 --json | jq '.width, .height'
j2k batch encode --input-dir ./raw/ --output-dir ./out/ --json | jq '.succeeded'
```

## Version Compatibility

The CLI syntax follows semantic versioning:
- **Patch** (2.4.x): No flag changes
- **Minor** (2.x.0): New flags may be added; existing flags are not removed or changed
- **Major** (x.0.0): Flags may be renamed, removed, or have changed semantics

Deprecated flags emit a warning for one minor version before removal.
