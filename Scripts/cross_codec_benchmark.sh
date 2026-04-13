#!/bin/bash
# Cross-Codec Benchmark: J2KSwift vs OpenJPEG vs OpenJPH vs Grok
# Tests encoding speed, decoding speed, compression ratio, and quality (PSNR)
#
# Usage: bash Scripts/cross_codec_benchmark.sh
# Requires: opj_compress, opj_decompress, ojph_compress, ojph_expand, grk_compress, grk_decompress
# Plus a release-built J2KSwift (swift build -c release)

set -euo pipefail

WORKDIR="/tmp/j2k_cross_codec_bench"
RESULTS_CSV="$WORKDIR/cross_codec_results.csv"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

# Tool paths
OPJ_ENC="/opt/homebrew/bin/opj_compress"
OPJ_DEC="/opt/homebrew/bin/opj_decompress"
OJPH_ENC="/opt/homebrew/bin/ojph_compress"
OJPH_DEC="/opt/homebrew/bin/ojph_expand"
GRK_ENC="/opt/homebrew/bin/grk_compress"
GRK_DEC="/opt/homebrew/bin/grk_decompress"

# Quick version check
echo "=== Codec Versions ==="
echo -n "OpenJPEG: "; $OPJ_ENC 2>&1 | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "v2.5.x"
echo -n "OpenJPH:  "; $OJPH_ENC 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "0.26.x"
echo -n "Grok:     "; $GRK_DEC -h 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "20.x"
echo "J2KSwift: v2.4.0"
echo ""

# Generate PGM test images via Python
generate_test_images() {
    python3 << 'PYEOF'
import struct, os, math, random

WORKDIR = "/tmp/j2k_cross_codec_bench"

def write_pgm(path, width, height, maxval, pixels):
    """Write a PGM (P5) file."""
    with open(path, 'wb') as f:
        header = f"P5\n{width} {height}\n{maxval}\n".encode('ascii')
        f.write(header)
        if maxval <= 255:
            f.write(bytes(min(maxval, max(0, p)) for p in pixels))
        else:
            for p in pixels:
                v = min(maxval, max(0, p))
                f.write(struct.pack('>H', v))

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

def generate_gradient(width, height, bitdepth, seed=42):
    """Gradient + noise + sharp edges test image."""
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
            # Noise ±12.5%
            noise = (rng.next() % max(maxval // 4, 1)) - maxval // 8
            val = int(max(0, min(maxval, val + noise)))
            pixels.append(val)
    return maxval, pixels

def generate_medical(width, height, bitdepth, seed=314159):
    """CT-like phantom with concentric structures."""
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
                val = maxval * 0.45
            elif dist > radius * 0.3:
                val = maxval * 0.60
            else:
                val = maxval * 0.35
            # Embedded ellipses
            ex1 = (dx - radius*0.2) / (radius*0.15)
            ey1 = (dy + radius*0.1) / (radius*0.1)
            if ex1*ex1 + ey1*ey1 < 1.0:
                val = maxval * 0.75
            ex2 = (dx + radius*0.3) / (radius*0.08)
            ey2 = (dy - radius*0.15) / (radius*0.12)
            if ex2*ex2 + ey2*ey2 < 1.0:
                val = maxval * 0.20
            noise = (int(rng.next()) % max(int(maxval/50), 1)) - int(maxval/100)
            val = int(max(0, min(maxval, val + noise)))
            pixels.append(val)
    return maxval, pixels

# Test images
images = [
    ("Grad-256-8b",  256, 256, 8, "gradient"),
    ("Grad-512-8b",  512, 512, 8, "gradient"),
    ("Grad-1024-8b", 1024, 1024, 8, "gradient"),
    ("Med-512-12b",  512, 512, 12, "medical"),
    ("Med-512-16b",  512, 512, 16, "medical"),
]

for name, w, h, bd, itype in images:
    path = os.path.join(WORKDIR, f"{name}.pgm")
    if itype == "gradient":
        maxval, pixels = generate_gradient(w, h, bd)
    else:
        maxval, pixels = generate_medical(w, h, bd)
    write_pgm(path, w, h, maxval, pixels)
    print(f"  Generated {name}.pgm ({w}x{h}, {bd}-bit, {os.path.getsize(path)} bytes)")

PYEOF
}

echo "=== Generating Test Images ==="
generate_test_images
echo ""

# CSV header
echo "Image,Resolution,BitDepth,Mode,Codec,EncTime_s,DecTime_s,FileSize_bytes,PSNR_dB" > "$RESULTS_CSV"

# Time a command (returns wall-clock seconds)
time_cmd() {
    local start end
    start=$(python3 -c "import time; print(f'{time.time():.6f}')")
    "$@" > /dev/null 2>&1
    end=$(python3 -c "import time; print(f'{time.time():.6f}')")
    python3 -c "print(f'{$end - $start:.4f}')"
}

# Compute PSNR between two PGM files
compute_psnr() {
    local orig="$1" decoded="$2" bitdepth="$3"
    python3 << PYEOF
import struct, sys, math

def read_pgm(path):
    with open(path, 'rb') as f:
        magic = f.readline().strip()
        # Skip comments
        line = f.readline()
        while line.startswith(b'#'):
            line = f.readline()
        dims = line.strip().split()
        w, h = int(dims[0]), int(dims[1])
        maxval = int(f.readline().strip())
        data = f.read()
        if maxval <= 255:
            pixels = list(data[:w*h])
        else:
            pixels = []
            for i in range(0, w*h*2, 2):
                pixels.append(struct.unpack('>H', data[i:i+2])[0])
    return w, h, maxval, pixels

try:
    w1, h1, m1, p1 = read_pgm("$orig")
    w2, h2, m2, p2 = read_pgm("$decoded")
    
    n = min(len(p1), len(p2))
    if n == 0:
        print("0.0")
        sys.exit(0)
    
    maxval = (1 << $bitdepth) - 1
    mse = sum((a - b) ** 2 for a, b in zip(p1[:n], p2[:n])) / n
    if mse == 0:
        print("Inf")
    else:
        psnr = 10 * math.log10(maxval * maxval / mse)
        print(f"{psnr:.2f}")
except Exception as e:
    print(f"0.0", file=sys.stderr)
    print("0.0")
PYEOF
}

# Benchmark configurations
declare -a IMAGES=("Grad-256-8b:256:256:8" "Grad-512-8b:512:512:8" "Grad-1024-8b:1024:1024:8" "Med-512-12b:512:512:12" "Med-512-16b:512:512:16")

# Modes: name:lossless:opj_ratio:ojph_qstep:grk_ratio
# For lossless: ratio=1, reversible=true
# For lossy: ratio = bitdepth / target_bpp
#   q0.9 → ~2bpp for 8-bit = ratio 4, ~2bpp for 12-bit = ratio 6, ~2bpp for 16-bit = ratio 8  
#   2bpp → ratio = bd/2
#   1bpp → ratio = bd/1
#   0.5bpp → ratio = bd/0.5
declare -a MODES=("lossless:1:0:1" "lossy-2bpp:0:2:2" "lossy-1bpp:0:1:1" "lossy-0.5bpp:0:0.5:0.5")

# Number of warmup + measurement runs
WARMUP=2
RUNS=5

echo "=== Running Cross-Codec Benchmarks ==="
echo "   Warmup: $WARMUP, Measurement runs: $RUNS (median reported)"
echo ""

printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "Image" "Mode" "Codec" "Enc(ms)" "Dec(ms)" "Size(B)" "PSNR"
printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "────────────────" "──────────────" "────────────" "────────" "────────" "──────────" "────────"

for img_spec in "${IMAGES[@]}"; do
    IFS=':' read -r name w h bd <<< "$img_spec"
    pgm="$WORKDIR/${name}.pgm"

    for mode_spec in "${MODES[@]}"; do
        IFS=':' read -r mode_name is_lossless target_bpp _ <<< "$mode_spec"

        # Calculate compression ratio for OPJ/Grok
        if [[ "$is_lossless" == "1" ]]; then
            opj_ratio="1"
            grk_ratio=""
            ojph_reversible="true"
            ojph_qstep=""
        else
            # ratio = bitdepth / target_bpp
            opj_ratio=$(python3 -c "print(f'{$bd / $target_bpp:.1f}')")
            grk_ratio="$opj_ratio"
            ojph_reversible="false"
            # Map bpp to qstep: lower bpp → larger qstep
            # 2bpp → 0.005, 1bpp → 0.01, 0.5bpp → 0.02
            ojph_qstep=$(python3 -c "print(f'{1.0 / ($target_bpp * 100):.5f}')")
        fi

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
                enc_t=$(time_cmd $OPJ_ENC -i "$pgm" -o "$opj_j2k" -r "$opj_ratio")
            fi
            dec_t=$(time_cmd $OPJ_DEC -i "$opj_j2k" -o "$opj_dec")
            if ((i >= WARMUP)); then
                enc_times+=("$enc_t")
                dec_times+=("$dec_t")
            fi
        done

        opj_enc_median=$(printf '%s\n' "${enc_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        opj_dec_median=$(printf '%s\n' "${dec_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        opj_size=$(stat -f%z "$opj_j2k" 2>/dev/null || echo 0)
        opj_psnr=$(compute_psnr "$pgm" "$opj_dec" "$bd")
        opj_enc_ms=$(python3 -c "print(f'{$opj_enc_median * 1000:.1f}')")
        opj_dec_ms=$(python3 -c "print(f'{$opj_dec_median * 1000:.1f}')")

        printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "$name" "$mode_name" "OpenJPEG" "$opj_enc_ms" "$opj_dec_ms" "$opj_size" "$opj_psnr"
        echo "${name},${w}x${h},${bd},${mode_name},OpenJPEG,${opj_enc_median},${opj_dec_median},${opj_size},${opj_psnr}" >> "$RESULTS_CSV"

        # === OpenJPH (HTJ2K) ===
        ojph_jph="$WORKDIR/${name}_${mode_name}_ojph.jph"
        ojph_dec="$WORKDIR/${name}_${mode_name}_ojph_dec.pgm"
        enc_times=()
        dec_times=()

        for ((i=0; i<WARMUP+RUNS; i++)); do
            rm -f "$ojph_jph" "$ojph_dec"
            if [[ "$is_lossless" == "1" ]]; then
                enc_t=$(time_cmd $OJPH_ENC -i "$pgm" -o "$ojph_jph" -reversible true -colour_trans false)
            else
                enc_t=$(time_cmd $OJPH_ENC -i "$pgm" -o "$ojph_jph" -reversible false -qstep "$ojph_qstep" -colour_trans false)
            fi
            if [[ -f "$ojph_jph" ]]; then
                dec_t=$(time_cmd $OJPH_DEC -i "$ojph_jph" -o "$ojph_dec")
            else
                dec_t="0"
            fi
            if ((i >= WARMUP)); then
                enc_times+=("$enc_t")
                dec_times+=("$dec_t")
            fi
        done

        ojph_enc_median=$(printf '%s\n' "${enc_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        ojph_dec_median=$(printf '%s\n' "${dec_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        ojph_size=$(stat -f%z "$ojph_jph" 2>/dev/null || echo 0)
        if [[ -f "$ojph_dec" ]]; then
            ojph_psnr=$(compute_psnr "$pgm" "$ojph_dec" "$bd")
        else
            ojph_psnr="N/A"
        fi
        ojph_enc_ms=$(python3 -c "print(f'{$ojph_enc_median * 1000:.1f}')")
        ojph_dec_ms=$(python3 -c "print(f'{$ojph_dec_median * 1000:.1f}')")

        printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "$name" "$mode_name" "OpenJPH" "$ojph_enc_ms" "$ojph_dec_ms" "$ojph_size" "$ojph_psnr"
        echo "${name},${w}x${h},${bd},${mode_name},OpenJPH,${ojph_enc_median},${ojph_dec_median},${ojph_size},${ojph_psnr}" >> "$RESULTS_CSV"

        # === Grok ===
        grk_j2k="$WORKDIR/${name}_${mode_name}_grk.j2k"
        grk_dec="$WORKDIR/${name}_${mode_name}_grk_dec.pgm"
        enc_times=()
        dec_times=()

        for ((i=0; i<WARMUP+RUNS; i++)); do
            rm -f "$grk_j2k" "$grk_dec"
            if [[ "$is_lossless" == "1" ]]; then
                enc_t=$(time_cmd $GRK_ENC -i "$pgm" -o "$grk_j2k" -H 1)
            else
                enc_t=$(time_cmd $GRK_ENC -i "$pgm" -o "$grk_j2k" -r "$grk_ratio" -I -H 1)
            fi
            if [[ -f "$grk_j2k" ]]; then
                dec_t=$(time_cmd $GRK_DEC -i "$grk_j2k" -o "$grk_dec" -H 1)
            else
                dec_t="0"
            fi
            if ((i >= WARMUP)); then
                enc_times+=("$enc_t")
                dec_times+=("$dec_t")
            fi
        done

        grk_enc_median=$(printf '%s\n' "${enc_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        grk_dec_median=$(printf '%s\n' "${dec_times[@]}" | sort -n | sed -n "$((RUNS/2+1))p")
        grk_size=$(stat -f%z "$grk_j2k" 2>/dev/null || echo 0)
        if [[ -f "$grk_dec" ]]; then
            grk_psnr=$(compute_psnr "$pgm" "$grk_dec" "$bd")
        else
            grk_psnr="N/A"
        fi
        grk_enc_ms=$(python3 -c "print(f'{$grk_enc_median * 1000:.1f}')")
        grk_dec_ms=$(python3 -c "print(f'{$grk_dec_median * 1000:.1f}')")

        printf "%-16s %-14s %-12s %8s %8s %10s %8s\n" "$name" "$mode_name" "Grok" "$grk_enc_ms" "$grk_dec_ms" "$grk_size" "$grk_psnr"
        echo "${name},${w}x${h},${bd},${mode_name},Grok,${grk_enc_median},${grk_dec_median},${grk_size},${grk_psnr}" >> "$RESULTS_CSV"

        echo ""
    done
done

echo ""
echo "=== Results written to $RESULTS_CSV ==="
echo ""

# Summary table
echo "=== Summary: Encoding Speed (ms, median of $RUNS runs) ==="
printf "%-16s %-14s %10s %10s %10s\n" "Image" "Mode" "OpenJPEG" "OpenJPH" "Grok"
printf "%-16s %-14s %10s %10s %10s\n" "────────────────" "──────────────" "──────────" "──────────" "──────────"

while IFS=',' read -r img res bd mode codec enc dec sz psnr; do
    [[ "$img" == "Image" ]] && continue
    enc_ms=$(python3 -c "print(f'{float(\"$enc\") * 1000:.1f}')")
    # Store in associative array
    eval "ENC_${img//-/_}_${mode//-/_}_${codec}=$enc_ms"
done < "$RESULTS_CSV"

for img_spec in "${IMAGES[@]}"; do
    IFS=':' read -r name _ _ _ <<< "$img_spec"
    k="${name//-/_}"
    for mode_spec in "${MODES[@]}"; do
        IFS=':' read -r mode_name _ _ _ <<< "$mode_spec"
        mk="${mode_name//-/_}"
        opj_v=$(eval "echo \${ENC_${k}_${mk}_OpenJPEG:-N/A}")
        ojph_v=$(eval "echo \${ENC_${k}_${mk}_OpenJPH:-N/A}")
        grk_v=$(eval "echo \${ENC_${k}_${mk}_Grok:-N/A}")
        printf "%-16s %-14s %10s %10s %10s\n" "$name" "$mode_name" "$opj_v" "$ojph_v" "$grk_v"
    done
done

echo ""
echo "Done. Full CSV: $RESULTS_CSV"
