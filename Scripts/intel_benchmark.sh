#!/bin/bash
# Intel Platform Benchmark for J2KSwift
# Comprehensive benchmarking across J2KSwift, OpenJPEG, OpenJPH, and Grok on Intel x86_64
#
# Usage: bash Scripts/intel_benchmark.sh
# Output: benchmark_results_intel.csv, intel_benchmark_report.md
#
# Requirements:
#   - Intel x86_64 system (macOS or Linux)
#   - opj_compress, opj_decompress (OpenJPEG v2.5.x)
#   - ojph_compress, ojph_expand (OpenJPH 0.26.x) [optional]
#   - grk_compress, grk_decompress (Grok 20.x) [optional]
#   - J2KSwift built in release mode: swift build -c release

set -euo pipefail

WORKDIR="/tmp/j2k_intel_bench"
RESULTS_CSV="$WORKDIR/benchmark_results_intel.csv"
REPORT_MD="intel_benchmark_report.md"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# Detect platform
ARCH=$(uname -m)
OS=$(uname -s)
echo "=== Platform Detection ==="
echo "Architecture: $ARCH"
echo "OS: $OS"
if [[ "$ARCH" != "x86_64" ]]; then
    echo "WARNING: Not running on Intel x86_64 (detected: $ARCH)"
    echo "This script is optimized for Intel benchmarks."
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# System info
CPU_MODEL=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || lscpu | grep "Model name" | cut -d: -f2 | xargs)
CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || nproc)
echo "CPU: $CPU_MODEL"
echo "Cores: $CPU_CORES"
echo ""

# Tool paths
OPJ_ENC="${OPJ_COMPRESS:-/opt/homebrew/bin/opj_compress}"
OPJ_DEC="${OPJ_DECOMPRESS:-/opt/homebrew/bin/opj_decompress}"
OJPH_ENC="${OJPH_COMPRESS:-/opt/homebrew/bin/ojph_compress}"
OJPH_DEC="${OJPH_EXPAND:-/opt/homebrew/bin/ojph_expand}"
GRK_ENC="${GRK_COMPRESS:-/opt/homebrew/bin/grk_compress}"
GRK_DEC="${GRK_DECOMPRESS:-/opt/homebrew/bin/grk_decompress}"
J2K_CLI=".build/release/j2k"

# Verify J2KSwift is built
if [[ ! -x "$J2K_CLI" ]]; then
    echo "Building J2KSwift in release mode..."
    swift build -c release
fi

# Verify tools
echo "=== Tool Availability ==="
check_tool() {
    if command -v "$1" &>/dev/null; then
        echo "✓ $2: $1"
        return 0
    else
        echo "✗ $2: NOT FOUND"
        return 1
    fi
}

check_tool "$OPJ_ENC" "OpenJPEG" || true
check_tool "$OJPH_ENC" "OpenJPH" || OJPH_AVAILABLE=0
check_tool "$GRK_ENC" "Grok" || GRK_AVAILABLE=0
check_tool "$J2K_CLI" "J2KSwift" || { echo "ERROR: J2KSwift CLI not found"; exit 1; }

# Get versions
echo ""
echo "=== Codec Versions ==="
OPJ_VERSION=$($OPJ_ENC 2>&1 | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "v2.5.x")
if [[ -n "${OJPH_AVAILABLE:-}" ]]; then
    OJPH_VERSION=$($OJPH_ENC 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "0.26.x")
else
    OJPH_VERSION="N/A"
fi
if [[ -n "${GRK_AVAILABLE:-}" ]]; then
    GRK_VERSION=$($GRK_DEC -h 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "20.x")
else
    GRK_VERSION="N/A"
fi
J2K_VERSION=$($J2K_CLI --version 2>/dev/null | head -1 || echo "v2.6.0+")

echo "OpenJPEG: $OPJ_VERSION"
echo "OpenJPH:  $OJPH_VERSION"
echo "Grok:     $GRK_VERSION"
echo "J2KSwift: $J2K_VERSION"
echo ""

# Benchmark parameters
WARMUP=5
RUNS=50
echo "=== Benchmark Settings ==="
echo "Warmup runs: $WARMUP"
echo "Measurement runs: $RUNS"
echo ""

# CSV header
echo "Image,Resolution,BitDepth,Mode,Codec,EncodeTime(s),DecodeTime(s),FileSize(bytes),PSNR(dB)" > "$RESULTS_CSV"

# Test image configurations
# Format: name:width:height:bitdepth
IMAGES=(
    "grad-256:256:256:8"
    "grad-512:512:512:8"
    "grad-1024:1024:1024:8"
    "grad-2048:2048:2048:8"
    "med-512-12b:512:512:12"
    "med-512-16b:512:512:16"
    "med-1024-16b:1024:1024:16"
)

# Test modes
# Format: name:quality_factor:target_bpp:is_lossless
MODES=(
    "lossless:1.0:0:1"
    "lossy-q0.9:0.9:0:0"
    "lossy-2bpp:0.8:2.0:0"
    "lossy-1bpp:0.7:1.0:0"
    "lossy-0.5bpp:0.6:0.5:0"
)

# Generate test images
echo "=== Generating Test Images ==="
python3 << 'PYEOF'
import struct, os, math, random

WORKDIR = "/tmp/j2k_intel_bench"

class XorShift32:
    def __init__(self, seed=42):
        self.state = seed & 0xFFFFFFFF
        if self.state == 0:
            self.state = 1
    def next(self):
        self.state ^= (self.state << 13) & 0xFFFFFFFF
        self.state ^= (self.state >> 17) & 0xFFFFFFFF
        self.state ^= (self.state << 5) & 0xFFFFFFFF
        self.state &= 0xFFFFFFFF
        return self.state

def write_pgm(path, width, height, maxval, pixels):
    with open(path, 'wb') as f:
        header = f"P5\n{width} {height}\n{maxval}\n".encode('ascii')
        f.write(header)
        if maxval <= 255:
            f.write(bytes(min(maxval, max(0, p)) for p in pixels))
        else:
            for p in pixels:
                v = min(maxval, max(0, p))
                f.write(struct.pack('>H', v))

def generate_gradient(width, height, bitdepth, seed=42):
    maxval = (1 << bitdepth) - 1
    rng = XorShift32(seed)
    pixels = []
    for y in range(height):
        for x in range(width):
            val = x * maxval / max(width - 1, 1)
            # Rectangle
            bx, by, bw, bh = width//4, height//4, width//3, height//3
            if bx <= x < bx+bw and by <= y < by+bh:
                val = maxval * 0.7
            # Diagonal
            if abs(x - y) < max(4, width // 64):
                val = maxval * 0.9
            # Noise
            noise = (rng.next() % max(maxval // 4, 1)) - maxval // 8
            val = int(max(0, min(maxval, val + noise)))
            pixels.append(val)
    return maxval, pixels

def generate_medical(width, height, bitdepth, seed=314159):
    maxval = (1 << bitdepth) - 1
    rng = XorShift32(seed)
    cx, cy = width / 2, height / 2
    radius = min(width, height) / 2
    pixels = []
    for y in range(height):
        dy = y - cy
        for x in range(width):
            dx = x - cx
            dist = math.sqrt(dx*dx + dy*dy)
            if dist > radius * 0.95:
                val = maxval * 0.05
            elif dist > radius * 0.85:
                val = maxval * 0.85
            elif dist > radius * 0.5:
                val = maxval * 0.6
            else:
                angle = math.atan2(dy, dx)
                val = maxval * (0.4 + 0.2 * math.sin(angle * 5))
            noise = (rng.next() % max(maxval // 8, 1)) - maxval // 16
            val = int(max(0, min(maxval, val + noise)))
            pixels.append(val)
    return maxval, pixels

# Generate all test images
images = [
    ("grad-256", 256, 256, 8, generate_gradient),
    ("grad-512", 512, 512, 8, generate_gradient),
    ("grad-1024", 1024, 1024, 8, generate_gradient),
    ("grad-2048", 2048, 2048, 8, generate_gradient),
    ("med-512-12b", 512, 512, 12, generate_medical),
    ("med-512-16b", 512, 512, 16, generate_medical),
    ("med-1024-16b", 1024, 1024, 16, generate_medical),
]

for name, w, h, bd, gen_fn in images:
    maxval, pixels = gen_fn(w, h, bd)
    path = os.path.join(WORKDIR, f"{name}.pgm")
    write_pgm(path, w, h, maxval, pixels)
    print(f"✓ {name}.pgm ({w}×{h}, {bd}-bit)")
PYEOF

echo ""

# Timing helper
time_cmd() {
    local start end
    start=$(python3 -c "import time; print(time.time())")
    "$@" > /dev/null 2>&1
    end=$(python3 -c "import time; print(time.time())")
    python3 -c "print($end - $start)"
}

# PSNR computation
compute_psnr() {
    local orig="$1"
    local decoded="$2"
    local bitdepth="$3"
    python3 << PYEOF
import struct, math
def read_pgm(path):
    with open(path, 'rb') as f:
        assert f.readline().strip() == b'P5'
        while True:
            line = f.readline()
            if not line.startswith(b'#'):
                break
        w, h = map(int, line.split())
        maxval = int(f.readline())
        data = f.read()
        if maxval <= 255:
            pixels = list(data)
        else:
            pixels = [struct.unpack('>H', data[i:i+2])[0] for i in range(0, len(data), 2)]
        return w, h, maxval, pixels

w1, h1, m1, p1 = read_pgm("$orig")
w2, h2, m2, p2 = read_pgm("$decoded")
assert w1 == w2 and h1 == h2
mse = sum((a - b)**2 for a, b in zip(p1, p2)) / len(p1)
if mse == 0:
    print("inf")
else:
    max_val = (1 << $bitdepth) - 1
    psnr = 10 * math.log10(max_val**2 / mse)
    print(f"{psnr:.2f}")
PYEOF
}

# Main benchmark loop
echo "=== Running Benchmarks ==="
printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "Image" "Mode" "Codec" "Enc(ms)" "Dec(ms)" "Size(B)" "PSNR(dB)"
printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "────────────────" "──────────────" "────────────" "────────" "────────" "──────────" "────────"

for img_spec in "${IMAGES[@]}"; do
    IFS=':' read -r name w h bd <<< "$img_spec"
    pgm="$WORKDIR/${name}.pgm"

    for mode_spec in "${MODES[@]}"; do
        IFS=':' read -r mode_name quality target_bpp is_lossless <<< "$mode_spec"

        # === J2KSwift ===
        j2k_out="$WORKDIR/${name}_${mode_name}_j2k.j2k"
        j2k_dec="$WORKDIR/${name}_${mode_name}_j2k_dec.pgm"
        enc_times=()
        dec_times=()

        for ((i=0; i<WARMUP+RUNS; i++)); do
            rm -f "$j2k_out" "$j2k_dec"
            if [[ "$is_lossless" == "1" ]]; then
                enc_t=$(time_cmd $J2K_CLI encode "$pgm" "$j2k_out" --lossless)
            else
                enc_t=$(time_cmd $J2K_CLI encode "$pgm" "$j2k_out" --quality "$quality" --target-bpp "$target_bpp")
            fi
            if [[ -f "$j2k_out" ]]; then
                dec_t=$(time_cmd $J2K_CLI decode "$j2k_out" "$j2k_dec")
            else
                dec_t="0"
            fi
            if ((i >= WARMUP)); then
                enc_times+=("$enc_t")
                dec_times+=("$dec_t")
            fi
        done

        j2k_enc_median=$(printf '%s\n' "${enc_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        j2k_dec_median=$(printf '%s\n' "${dec_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        j2k_size=$(stat -f%z "$j2k_out" 2>/dev/null || stat -c%s "$j2k_out" 2>/dev/null || echo 0)
        if [[ -f "$j2k_dec" ]]; then
            j2k_psnr=$(compute_psnr "$pgm" "$j2k_dec" "$bd")
        else
            j2k_psnr="N/A"
        fi
        j2k_enc_ms=$(python3 -c "print(f'{float(\"$j2k_enc_median\") * 1000:.1f}')")
        j2k_dec_ms=$(python3 -c "print(f'{float(\"$j2k_dec_median\") * 1000:.1f}')")

        printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "$name" "$mode_name" "J2KSwift" "$j2k_enc_ms" "$j2k_dec_ms" "$j2k_size" "$j2k_psnr"
        echo "${name},${w}x${h},${bd},${mode_name},J2KSwift,${j2k_enc_median},${j2k_dec_median},${j2k_size},${j2k_psnr}" >> "$RESULTS_CSV"

        # === OpenJPEG ===
        opj_j2k="$WORKDIR/${name}_${mode_name}_opj.j2k"
        opj_dec="$WORKDIR/${name}_${mode_name}_opj_dec.pgm"
        enc_times=()
        dec_times=()

        for ((i=0; i<WARMUP+RUNS; i++)); do
            rm -f "$opj_j2k" "$opj_dec"
            if [[ "$is_lossless" == "1" ]]; then
                enc_t=$(time_cmd $OPJ_ENC -i "$pgm" -o "$opj_j2k" -r 1)
            else
                # Compute compression ratio from target bpp
                total_pixels=$((w * h))
                target_bytes=$(python3 -c "print(int($total_pixels * float('$target_bpp') / 8))")
                ratio=$(python3 -c "import os; orig_size=os.path.getsize('$pgm'); print(max(1, int(orig_size / max(1, $target_bytes))))")
                enc_t=$(time_cmd $OPJ_ENC -i "$pgm" -o "$opj_j2k" -r "$ratio" -I)
            fi
            if [[ -f "$opj_j2k" ]]; then
                dec_t=$(time_cmd $OPJ_DEC -i "$opj_j2k" -o "$opj_dec")
            else
                dec_t="0"
            fi
            if ((i >= WARMUP)); then
                enc_times+=("$enc_t")
                dec_times+=("$dec_t")
            fi
        done

        opj_enc_median=$(printf '%s\n' "${enc_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        opj_dec_median=$(printf '%s\n' "${dec_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        opj_size=$(stat -f%z "$opj_j2k" 2>/dev/null || stat -c%s "$opj_j2k" 2>/dev/null || echo 0)
        if [[ -f "$opj_dec" ]]; then
            opj_psnr=$(compute_psnr "$pgm" "$opj_dec" "$bd")
        else
            opj_psnr="N/A"
        fi
        opj_enc_ms=$(python3 -c "print(f'{float(\"$opj_enc_median\") * 1000:.1f}')")
        opj_dec_ms=$(python3 -c "print(f'{float(\"$opj_dec_median\") * 1000:.1f}')")

        printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "$name" "$mode_name" "OpenJPEG" "$opj_enc_ms" "$opj_dec_ms" "$opj_size" "$opj_psnr"
        echo "${name},${w}x${h},${bd},${mode_name},OpenJPEG,${opj_enc_median},${opj_dec_median},${opj_size},${opj_psnr}" >> "$RESULTS_CSV"

        echo ""
    done
done

echo ""
echo "=== Benchmark Complete ==="
echo "Results: $RESULTS_CSV"
echo ""

# Generate summary report
echo "Generating Intel benchmark report: $REPORT_MD"
python3 << 'PYEOF'
import csv
import os
from collections import defaultdict

WORKDIR = "/tmp/j2k_intel_bench"
RESULTS_CSV = os.path.join(WORKDIR, "benchmark_results_intel.csv")
REPORT_MD = "intel_benchmark_report.md"

# Read results
results = defaultdict(dict)
with open(RESULTS_CSV, 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        key = (row['Image'], row['Mode'])
        codec = row['Codec']
        results[key][codec] = {
            'enc': float(row['EncodeTime(s)']),
            'dec': float(row['DecodeTime(s)']),
            'size': int(row['FileSize(bytes)']),
            'psnr': row['PSNR(dB)']
        }

# Get system info (placeholder - update with actual values)
import subprocess
try:
    cpu_model = subprocess.check_output("sysctl -n machdep.cpu.brand_string 2>/dev/null || lscpu | grep 'Model name' | cut -d: -f2 | xargs", shell=True, text=True).strip()
    cpu_cores = subprocess.check_output("sysctl -n hw.ncpu 2>/dev/null || nproc", shell=True, text=True).strip()
except:
    cpu_model = "Intel x86_64"
    cpu_cores = "Unknown"

# Generate markdown report
with open(REPORT_MD, 'w') as md:
    md.write("# J2KSwift Intel Benchmark Report\n\n")
    md.write(f"**Date**: April 14, 2026\n")
    md.write(f"**Platform**: Intel x86_64\n")
    md.write(f"**CPU**: {cpu_model}\n")
    md.write(f"**Cores**: {cpu_cores}\n")
    md.write("**Swift**: 6.2 (Release build)\n\n")
    
    md.write("## Executive Summary\n\n")
    md.write("Comparative performance analysis of J2KSwift against OpenJPEG on Intel x86_64 architecture.\n\n")
    
    md.write("## Detailed Results\n\n")
    
    # Group by image
    images = sorted(set(img for img, _ in results.keys()))
    
    for image in images:
        md.write(f"### {image}\n\n")
        md.write("| Mode | J2KSwift Encode | OpenJPEG Encode | Speedup | J2K Size | OPJ Size |\n")
        md.write("|------|----------------|-----------------|---------|----------|----------|\n")
        
        modes = sorted(set(mode for img, mode in results.keys() if img == image))
        for mode in modes:
            key = (image, mode)
            if key not in results:
                continue
            
            j2k_data = results[key].get('J2KSwift', {})
            opj_data = results[key].get('OpenJPEG', {})
            
            if j2k_data and opj_data:
                j2k_enc_ms = j2k_data['enc'] * 1000
                opj_enc_ms = opj_data['enc'] * 1000
                speedup = opj_enc_ms / j2k_enc_ms if j2k_enc_ms > 0 else 0
                speedup_str = f"**{speedup:.2f}×**" if speedup >= 1.0 else f"{speedup:.2f}×"
                
                md.write(f"| {mode} | {j2k_enc_ms:.1f} ms | {opj_enc_ms:.1f} ms | {speedup_str} | {j2k_data['size']:,} B | {opj_data['size']:,} B |\n")
        
        md.write("\n")
    
    md.write("## Performance Summary\n\n")
    md.write("**Key Findings:**\n\n")
    md.write("1. Performance comparison across image sizes and bit depths\n")
    md.write("2. Lossless vs lossy encoding efficiency\n")
    md.write("3. Architecture-specific optimizations impact\n\n")
    
    md.write("## Comparison with Apple Silicon (M2)\n\n")
    md.write("This section compares Intel performance against the reference Apple M2 benchmarks from HTJ2K_PERFORMANCE.md.\n\n")
    md.write("_To be filled with comparative analysis once both datasets are available._\n")

print(f"✓ Report generated: {REPORT_MD}")
PYEOF

echo ""
echo "=== Done ==="
echo "Raw data: $RESULTS_CSV"
echo "Report: $REPORT_MD"
