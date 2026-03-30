# JPIP CLI Guide

Interactive JPEG 2000 streaming using the `j2k` CLI's JPIP server and client commands.

## Overview

JPIP (JPEG 2000 Interactive Protocol) enables progressive, region-based streaming of JPEG 2000 images over the network. The `j2k` CLI provides both server and client commands for JPIP.

## Quick Start

### Terminal 1 — Start the Server

```bash
# Serve all JPEG 2000 files from a directory
j2k jpip server --data-dir ./images/ --port 8080 --verbose
```

### Terminal 2 — Connect with the Client

```bash
# Download a full image
j2k jpip client --server http://localhost:8080 --target image.jp2 -o output.pgm

# Request a specific region
j2k jpip client --server http://localhost:8080 --target image.jp2 --region 0,0,512,512 -o region.pgm
```

## Server Configuration

### Basic Options

```bash
j2k jpip server --port 8080 --host 0.0.0.0 --data-dir ./images/
```

| Flag | Description | Default |
|------|-------------|---------|
| `--port N` | Listening port | `8080` |
| `--host ADDRESS` | Bind address | `0.0.0.0` |
| `--data-dir DIR` | Directory of JP2/J2K/JPH files to serve | |
| `--single-file PATH` | Serve a single JPEG 2000 file | |

### Session Management

```bash
j2k jpip server --data-dir ./images/ --max-sessions 20 --session-timeout 600
```

| Flag | Description | Default |
|------|-------------|---------|
| `--max-sessions N` | Maximum concurrent client sessions | `10` |
| `--session-timeout SEC` | Idle session timeout (seconds) | `300` |

### TLS Configuration

```bash
j2k jpip server --data-dir ./images/ --tls-cert cert.pem --tls-key key.pem
```

### 3D / Volumetric Serving

```bash
j2k jpip server --data-dir ./volumes/ --mode 3d
```

The server automatically detects JP3D files and enables 3D streaming extensions.

### Graceful Shutdown

The server handles `SIGINT` (Ctrl+C) and `SIGTERM` for graceful shutdown, closing all active sessions before exiting.

## Client Usage

### Single Request Mode

Download a complete image or a specific portion:

```bash
# Full image
j2k jpip client --server http://localhost:8080 --target image.jp2 -o output.pgm

# Specific region
j2k jpip client --server http://localhost:8080 --target image.jp2 \
    --region 100,200,300,400 -o region.pgm

# Low resolution
j2k jpip client --server http://localhost:8080 --target image.jp2 \
    --resolution-level 3 -o lowres.pgm

# Limited quality
j2k jpip client --server http://localhost:8080 --target image.jp2 \
    --quality-layers 2 -o preview.pgm
```

### Progressive Delivery

```bash
j2k jpip client --server http://localhost:8080 --target image.jp2 \
    --progressive --progressive-dir ./frames/
```

Intermediate results are saved to the specified directory.

### Interactive Mode

The interactive mode provides a REPL for exploring images:

```bash
j2k jpip client --server http://localhost:8080 --target image.jp2 --interactive
```

**Interactive commands:**

| Command | Description |
|---------|-------------|
| `region x,y,w,h` | Request a specific region |
| `zoom N` | Request resolution level N |
| `quality N` | Request N quality layers |
| `save PATH` | Download and save full image |
| `info` | Display image metadata |
| `help` | Show available commands |
| `quit` | Close session and exit |

**Example session:**

```
> region 0,0,256,256
  Received 256×256 image (196.6 KB)
> zoom 2
  Received 2048×2048 (level 2, 3.1 MB)
> quality 3
  Received 4096×4096 (3 quality layers, 8.2 MB)
> save output.pgm
  Saved to: output.pgm
> quit
Session closed.
```

### 3D Client

```bash
j2k jpip client --server http://server:8080 --target volume.jp3d \
    --mode 3d --slice-range 10-20 -o ./slices/
```

## Network Setup

### Firewall

Ensure the JPIP server port is open:

```bash
# macOS
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /path/to/j2k

# Linux (ufw)
sudo ufw allow 8080/tcp
```

### Bandwidth Throttling

For testing progressive delivery over slow networks:

```bash
j2k jpip client --server http://localhost:8080 --target image.jp2 \
    --max-bandwidth 1000000 -o output.pgm
```

## Benchmarking

```bash
j2k benchmark --mode jpip --server http://localhost:8080 --target image.jp2 --runs 5
```

Measures connection setup time, first-byte latency, transfer time, and total throughput.

## JSON Output

Both server and client support `--json` for machine-readable output:

```bash
j2k jpip client --server http://localhost:8080 --target image.jp2 -o out.pgm --json
```

```json
{
  "server": "http://localhost:8080",
  "target": "image.jp2",
  "width": 4096,
  "height": 4096,
  "components": 3,
  "bytesReceived": 12582912,
  "timing": {
    "session": 0.015,
    "request": 0.234,
    "total": 0.249
  }
}
```
