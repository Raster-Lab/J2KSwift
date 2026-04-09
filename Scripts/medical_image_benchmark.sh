#!/bin/bash
###############################################################################
# medical_image_benchmark.sh
#
# Comprehensive JPEG 2000 Benchmark: J2KSwift vs OpenJPEG 2.5.4
# Tests real medical imaging phantoms (CT, MRI, Ultrasound, Mammogram, Retinal)
# at multiple bit depths and compression modes.
#
# Usage:
#   ./Scripts/medical_image_benchmark.sh [--runs N] [--output DIR]
###############################################################################

set -euo pipefail

# ------- Configuration -------
RUNS=${1:-5}
WARMUP=2
IMG_DIR="/tmp/j2k_medical_benchmark/images"
OUT_DIR="/tmp/j2k_medical_benchmark/results"
J2K_BIN="$(cd "$(dirname "$0")/.." && swift build -c release --show-bin-path 2>/dev/null)/j2k"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
CSV_FILE="${OUT_DIR}/benchmark_${TIMESTAMP}.csv"
REPORT_FILE="${OUT_DIR}/benchmark_report_${TIMESTAMP}.md"

# Fallback if show-bin-path doesn't find the binary
if [[ ! -x "$J2K_BIN" ]]; then
    J2K_BIN="$(dirname "$0")/../.build/release/j2k"
fi

# ------- Validate prerequisites -------
echo "=================================================================="
echo "  J2KSwift vs OpenJPEG Medical Imaging Benchmark"
echo "  Date: $(date)"
echo "=================================================================="
echo ""

if [[ ! -x "$J2K_BIN" ]]; then
    echo "ERROR: J2KSwift binary not found. Run 'swift build -c release' first."
    exit 1
fi

if ! command -v opj_compress &>/dev/null; then
    echo "ERROR: opj_compress not found. Install OpenJPEG: brew install openjpeg"
    exit 1
fi

if ! command -v opj_decompress &>/dev/null; then
    echo "ERROR: opj_decompress not found."
    exit 1
fi

echo "J2KSwift: $("$J2K_BIN" version 2>&1 || echo 'unknown')"
echo "OpenJPEG: $(opj_compress -h 2>&1 | grep 'openjp2 library' | head -1 || echo 'unknown')"
echo "Platform: $(uname -m) / $(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r)"
echo "Runs: $RUNS (warmup: $WARMUP)"
echo ""

mkdir -p "$OUT_DIR"

# ------- CSV Header -------
echo "Image,Modality,Width,Height,BitDepth,Mode,Rate,J2K_EncTime_ms,J2K_DecTime_ms,J2K_Size_bytes,J2K_Ratio,OPJ_EncTime_ms,OPJ_DecTime_ms,OPJ_Size_bytes,OPJ_Ratio,Speedup_Enc,Speedup_Dec,J2K_PSNR_dB,J2K_MAE" > "$CSV_FILE"

# ------- Utility Functions -------

# Measure J2KSwift encode time (median of N runs)
j2k_encode() {
    local input="$1" output="$2" mode="$3" rate="$4"
    local times=()
    
    # Build encode args
    local args=("-i" "$input" "-o" "$output")
    case "$mode" in
        lossless) ;; # default is lossless
        lossy)
            args+=("--quality" "$rate")
            ;;
        rate)
            args+=("--rate" "$rate")
            ;;
    esac

    # Warmup
    for ((w=0; w<WARMUP; w++)); do
        "$J2K_BIN" encode "${args[@]}" &>/dev/null || true
    done
    
    # Timed runs
    for ((r=0; r<RUNS; r++)); do
        local start end elapsed
        start=$(python3 -c "import time; print(time.time())")
        "$J2K_BIN" encode "${args[@]}" &>/dev/null || true
        end=$(python3 -c "import time; print(time.time())")
        elapsed=$(python3 -c "print(($end - $start) * 1000)")
        times+=("$elapsed")
    done
    
    # Return median
    printf '%s\n' "${times[@]}" | sort -n | awk "NR == int(($RUNS+1)/2) { print }"
}

# Measure J2KSwift decode time (median of N runs)
j2k_decode() {
    local input="$1" output="$2"
    local times=()
    
    # Warmup
    for ((w=0; w<WARMUP; w++)); do
        "$J2K_BIN" decode -i "$input" -o "$output" &>/dev/null || true
    done
    
    # Timed runs
    for ((r=0; r<RUNS; r++)); do
        local start end elapsed
        start=$(python3 -c "import time; print(time.time())")
        "$J2K_BIN" decode -i "$input" -o "$output" &>/dev/null || true
        end=$(python3 -c "import time; print(time.time())")
        elapsed=$(python3 -c "print(($end - $start) * 1000)")
        times+=("$elapsed")
    done
    
    printf '%s\n' "${times[@]}" | sort -n | awk "NR == int(($RUNS+1)/2) { print }"
}

# Measure OpenJPEG encode (median of N runs)
opj_encode() {
    local input="$1" output="$2" mode="$3" rate="$4"
    local times=()
    
    local args=("-i" "$input" "-o" "$output")
    case "$mode" in
        lossless) ;; # default
        lossy|rate)
            args+=("-r" "$rate")
            ;;
    esac
    
    # Warmup
    for ((w=0; w<WARMUP; w++)); do
        opj_compress "${args[@]}" &>/dev/null || true
    done
    
    # Timed runs
    for ((r=0; r<RUNS; r++)); do
        local start end elapsed
        start=$(python3 -c "import time; print(time.time())")
        opj_compress "${args[@]}" &>/dev/null || true
        end=$(python3 -c "import time; print(time.time())")
        elapsed=$(python3 -c "print(($end - $start) * 1000)")
        times+=("$elapsed")
    done
    
    printf '%s\n' "${times[@]}" | sort -n | awk "NR == int(($RUNS+1)/2) { print }"
}

# Measure OpenJPEG decode (median of N runs)
opj_decode() {
    local input="$1" output="$2"
    local times=()
    
    for ((w=0; w<WARMUP; w++)); do
        opj_decompress -i "$input" -o "$output" &>/dev/null || true
    done
    
    for ((r=0; r<RUNS; r++)); do
        local start end elapsed
        start=$(python3 -c "import time; print(time.time())")
        opj_decompress -i "$input" -o "$output" &>/dev/null || true
        end=$(python3 -c "import time; print(time.time())")
        elapsed=$(python3 -c "print(($end - $start) * 1000)")
        times+=("$elapsed")
    done
    
    printf '%s\n' "${times[@]}" | sort -n | awk "NR == int(($RUNS+1)/2) { print }"
}

# Compute PSNR between two PGM files
compute_psnr() {
    local original="$1" decoded="$2"
    python3 << PSNREOF
import struct, math, sys

def read_pgm(path):
    with open(path, 'rb') as f:
        magic = f.readline().strip()
        while True:
            line = f.readline().strip()
            if not line.startswith(b'#'):
                break
        w, h = map(int, line.split())
        maxval = int(f.readline().strip())
        if maxval > 255:
            data = []
            for _ in range(h * w):
                data.append(struct.unpack('>H', f.read(2))[0])
        else:
            raw = f.read(h * w)
            data = list(raw)
    return w, h, maxval, data

try:
    w1, h1, m1, d1 = read_pgm("$original")
    w2, h2, m2, d2 = read_pgm("$decoded")
    
    if w1 != w2 or h1 != h2:
        print("N/A")
        sys.exit(0)
    
    n = len(d1)
    mse = sum((a - b) ** 2 for a, b in zip(d1, d2)) / n
    mae = sum(abs(a - b) for a, b in zip(d1, d2)) / n
    
    if mse == 0:
        print("inf,0.00")
    else:
        psnr = 10 * math.log10((m1 ** 2) / mse)
        print(f"{psnr:.2f},{mae:.4f}")
except Exception as e:
    print(f"N/A,N/A")
PSNREOF
}

# Get file size
file_size() {
    stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo "0"
}

# Get image dimensions from PGM/PPM header
get_image_info() {
    python3 << INFOEOF
with open("$1", 'rb') as f:
    magic = f.readline().strip()
    while True:
        line = f.readline().strip()
        if not line.startswith(b'#'):
            break
    parts = line.split()
    w, h = int(parts[0]), int(parts[1])
    maxval = int(f.readline().strip())
    import math
    bd = int(math.ceil(math.log2(maxval + 1)))
    comps = 3 if magic in (b'P6', b'P3') else 1
    print(f"{w},{h},{bd},{comps}")
INFOEOF
}

# ------- Define test matrix -------
# Format: filename|modality|mode|rate_label|opj_rate
declare -a TEST_CASES=(
    # CT Chest 512x512 12-bit
    "ct_chest_512_12bit.pgm|CT|lossless|lossless|"
    "ct_chest_512_12bit.pgm|CT|lossy|0.9|10"
    "ct_chest_512_12bit.pgm|CT|rate|2bpp|20"
    "ct_chest_512_12bit.pgm|CT|rate|1bpp|40"
    "ct_chest_512_12bit.pgm|CT|rate|0.5bpp|80"
    
    # CT Chest 512x512 16-bit
    "ct_chest_512_16bit.pgm|CT|lossless|lossless|"
    "ct_chest_512_16bit.pgm|CT|lossy|0.9|10"
    "ct_chest_512_16bit.pgm|CT|rate|1bpp|40"
    
    # CT Chest 1024x1024 12-bit
    "ct_chest_1024_12bit.pgm|CT|lossless|lossless|"
    "ct_chest_1024_12bit.pgm|CT|lossy|0.9|10"
    "ct_chest_1024_12bit.pgm|CT|rate|2bpp|20"
    "ct_chest_1024_12bit.pgm|CT|rate|1bpp|40"
    
    # CT Chest 1024x1024 16-bit
    "ct_chest_1024_16bit.pgm|CT|lossless|lossless|"
    "ct_chest_1024_16bit.pgm|CT|rate|1bpp|40"
    
    # MRI Brain 512x512 12-bit
    "mri_brain_512_12bit.pgm|MRI|lossless|lossless|"
    "mri_brain_512_12bit.pgm|MRI|lossy|0.9|10"
    "mri_brain_512_12bit.pgm|MRI|rate|2bpp|20"
    "mri_brain_512_12bit.pgm|MRI|rate|1bpp|40"
    "mri_brain_512_12bit.pgm|MRI|rate|0.5bpp|80"
    
    # MRI Brain 512x512 16-bit
    "mri_brain_512_16bit.pgm|MRI|lossless|lossless|"
    "mri_brain_512_16bit.pgm|MRI|lossy|0.9|10"
    
    # MRI Brain 1024x1024 12-bit
    "mri_brain_1024_12bit.pgm|MRI|lossless|lossless|"
    "mri_brain_1024_12bit.pgm|MRI|rate|2bpp|20"
    "mri_brain_1024_12bit.pgm|MRI|rate|1bpp|40"
    
    # Ultrasound 512x512 8-bit
    "ultrasound_512_8bit.pgm|US|lossless|lossless|"
    "ultrasound_512_8bit.pgm|US|lossy|0.9|10"
    "ultrasound_512_8bit.pgm|US|rate|2bpp|20"
    "ultrasound_512_8bit.pgm|US|rate|1bpp|40"
    
    # Ultrasound 512x512 12-bit
    "ultrasound_512_12bit.pgm|US|lossless|lossless|"
    "ultrasound_512_12bit.pgm|US|lossy|0.9|10"
    
    # Mammogram 1024x1024 12-bit
    "mammogram_1024_12bit.pgm|Mammo|lossless|lossless|"
    "mammogram_1024_12bit.pgm|Mammo|lossy|0.9|10"
    "mammogram_1024_12bit.pgm|Mammo|rate|2bpp|20"
    "mammogram_1024_12bit.pgm|Mammo|rate|1bpp|40"
    
    # Mammogram 2048x2048 12-bit
    "mammogram_2048_12bit.pgm|Mammo|lossless|lossless|"
    "mammogram_2048_12bit.pgm|Mammo|rate|1bpp|40"
    
    # Retinal 512x512 8-bit
    "retinal_512_8bit.pgm|Retinal|lossless|lossless|"
    "retinal_512_8bit.pgm|Retinal|lossy|0.9|10"
    
    # Retinal 1024x1024 12-bit
    "retinal_1024_12bit.pgm|Retinal|lossless|lossless|"
    "retinal_1024_12bit.pgm|Retinal|rate|2bpp|20"
    
    # USC-SIPI Standard Test Images (256x256, 8-bit)
    "usc_5109.pgm|Aerial|lossless|lossless|"
    "usc_5112.pgm|Natural|lossless|lossless|"
    
    # USC-SIPI 512x512 variants
    "usc_5208.pgm|Aerial|lossless|lossless|"
    "usc_5208.pgm|Aerial|rate|1bpp|40"
    
    # USC-SIPI 1024x1024 variants
    "usc_5301.pgm|Natural|lossless|lossless|"
    "usc_5301.pgm|Natural|rate|2bpp|20"
    "usc_5301.pgm|Natural|rate|1bpp|40"
    
    # Bretagne (real photograph, RGB)
    "bretagne1.ppm|Photo|lossless|lossless|"
)

# ------- Run benchmarks -------
total=${#TEST_CASES[@]}
current=0

echo "Running $total test cases..."
echo ""
printf "%-35s %-10s %-10s %10s %10s %10s %10s %8s\n" \
    "Image" "Modality" "Mode" "J2K(ms)" "OPJ(ms)" "J2K_KB" "OPJ_KB" "Speedup"
echo "-----------------------------------------------------------------------------------------------------------"

for tc in "${TEST_CASES[@]}"; do
    current=$((current + 1))
    IFS='|' read -r fname modality mode rate_label opj_rate <<< "$tc"
    
    input="${IMG_DIR}/${fname}"
    
    if [[ ! -f "$input" ]]; then
        echo "  SKIP: $fname (not found)"
        continue
    fi
    
    # Get image dimensions
    img_info=$(get_image_info "$input")
    IFS=',' read -r width height bitdepth components <<< "$img_info"
    
    # Output file paths
    j2k_out="${OUT_DIR}/j2k_${fname%.*}_${rate_label}.j2k"
    opj_out="${OUT_DIR}/opj_${fname%.*}_${rate_label}.j2k"
    j2k_dec="${OUT_DIR}/j2k_dec_${fname%.*}_${rate_label}.pgm"
    opj_dec="${OUT_DIR}/opj_dec_${fname%.*}_${rate_label}.pgm"
    
    # Set J2K rate parameter
    j2k_rate=""
    case "$mode" in
        lossless) j2k_rate="" ;;
        lossy)    j2k_rate="$rate_label" ;;
        rate)
            case "$rate_label" in
                2bpp)   j2k_rate="0.7" ;;
                1bpp)   j2k_rate="0.5" ;;
                0.5bpp) j2k_rate="0.3" ;;
                *)      j2k_rate="0.5" ;;
            esac
            ;;
    esac
    
    # ------- J2KSwift Encode -------
    j2k_enc_ms=$(j2k_encode "$input" "$j2k_out" "$mode" "$j2k_rate")
    j2k_size=$(file_size "$j2k_out")
    
    # ------- J2KSwift Decode -------
    j2k_dec_ms="N/A"
    if [[ -f "$j2k_out" ]]; then
        # Determine decode output extension
        if [[ "$components" -ge 3 ]]; then
            j2k_dec="${j2k_dec%.pgm}.ppm"
        fi
        j2k_dec_ms=$(j2k_decode "$j2k_out" "$j2k_dec")
    fi
    
    # ------- OpenJPEG Encode -------
    opj_enc_ms=$(opj_encode "$input" "$opj_out" "$mode" "$opj_rate")
    opj_size=$(file_size "$opj_out")
    
    # ------- OpenJPEG Decode -------
    opj_dec_ms="N/A"
    if [[ -f "$opj_out" ]]; then
        if [[ "$components" -ge 3 ]]; then
            opj_dec="${opj_dec%.pgm}.ppm"
        fi
        opj_dec_ms=$(opj_decode "$opj_out" "$opj_dec")
    fi
    
    # ------- Compute PSNR (J2KSwift roundtrip) -------
    psnr_mae="N/A,N/A"
    if [[ -f "$j2k_dec" && "$components" -eq 1 ]]; then
        psnr_mae=$(compute_psnr "$input" "$j2k_dec")
    fi
    IFS=',' read -r j2k_psnr j2k_mae <<< "$psnr_mae"
    
    # ------- Compute ratios -------
    raw_size=$((width * height * components * (bitdepth > 8 ? 2 : 1)))
    j2k_ratio=$(python3 -c "print(f'{$raw_size / max($j2k_size, 1):.1f}')" 2>/dev/null || echo "N/A")
    opj_ratio=$(python3 -c "print(f'{$raw_size / max($opj_size, 1):.1f}')" 2>/dev/null || echo "N/A")
    
    # ------- Encode speedup -------
    speedup="N/A"
    if [[ "$j2k_enc_ms" != "N/A" && "$opj_enc_ms" != "N/A" ]]; then
        speedup=$(python3 -c "
j, o = float('$j2k_enc_ms'), float('$opj_enc_ms')
if j > 0: print(f'{o/j:.1f}x')
else: print('N/A')
")
    fi
    
    dec_speedup="N/A"
    if [[ "$j2k_dec_ms" != "N/A" && "$opj_dec_ms" != "N/A" ]]; then
        dec_speedup=$(python3 -c "
j, o = float('$j2k_dec_ms'), float('$opj_dec_ms')
if j > 0: print(f'{o/j:.1f}x')
else: print('N/A')
")
    fi
    
    j2k_size_kb=$(python3 -c "print(f'{$j2k_size / 1024:.1f}')")
    opj_size_kb=$(python3 -c "print(f'{$opj_size / 1024:.1f}')")
    
    # Print row
    display_name="${fname} (${rate_label})"
    printf "%-35s %-10s %-10s %10s %10s %10s %10s %8s\n" \
        "$display_name" "$modality" "$mode" \
        "${j2k_enc_ms}" "${opj_enc_ms}" \
        "${j2k_size_kb}" "${opj_size_kb}" \
        "$speedup"
    
    # Write CSV
    echo "${fname},${modality},${width},${height},${bitdepth},${mode},${rate_label},${j2k_enc_ms},${j2k_dec_ms},${j2k_size},${j2k_ratio},${opj_enc_ms},${opj_dec_ms},${opj_size},${opj_ratio},${speedup},${dec_speedup},${j2k_psnr},${j2k_mae}" >> "$CSV_FILE"
    
    # Cleanup intermediate files 
    rm -f "${OUT_DIR}/opj_dec_"* "${OUT_DIR}/j2k_dec_"* 2>/dev/null || true
done

echo ""
echo "-----------------------------------------------------------------------------------------------------------"
echo ""

# ------- Generate Markdown Report -------
python3 << REPORTEOF
import csv, sys, os
from datetime import datetime

csv_path = "$CSV_FILE"
report_path = "$REPORT_FILE"

rows = []
with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

if not rows:
    print("No results to report.")
    sys.exit(0)

with open(report_path, 'w') as f:
    f.write("# J2KSwift vs OpenJPEG Medical Imaging Benchmark Report\n\n")
    f.write(f"> **Date**: {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
    f.write(f"> **Platform**: $(uname -m) / $(sw_vers -productName 2>/dev/null || uname -s) $(sw_vers -productVersion 2>/dev/null || uname -r)\n")
    f.write(f"> **J2KSwift**: $("$J2K_BIN" version 2>&1 || echo 'unknown')\n")
    f.write(f"> **OpenJPEG**: 2.5.4\n")
    f.write(f"> **Runs**: $RUNS (warmup: $WARMUP)\n\n")
    f.write("---\n\n")
    
    # Executive Summary
    enc_speedups = []
    for r in rows:
        s = r.get('Speedup_Enc', 'N/A')
        if s and 'x' in s:
            enc_speedups.append(float(s.replace('x', '')))
    
    if enc_speedups:
        avg_speedup = sum(enc_speedups) / len(enc_speedups)
        max_speedup = max(enc_speedups)
        min_speedup = min(enc_speedups)
        
        f.write("## Executive Summary\n\n")
        f.write(f"- **Average Encode Speedup**: {avg_speedup:.1f}x faster than OpenJPEG\n")
        f.write(f"- **Best Encode Speedup**: {max_speedup:.1f}x (")
        best_row = [r for r in rows if r.get('Speedup_Enc', '').replace('x','') and float(r['Speedup_Enc'].replace('x','')) == max_speedup]
        if best_row:
            f.write(f"{best_row[0]['Image']} {best_row[0]['Mode']})\n")
        f.write(f"- **Worst Encode Speedup**: {min_speedup:.1f}x\n")
        
        # Lossless accuracy
        lossless_rows = [r for r in rows if r.get('Mode') == 'lossless' and r.get('J2K_MAE') not in ('N/A', '')]
        if lossless_rows:
            all_perfect = all(float(r['J2K_MAE']) == 0 for r in lossless_rows)
            if all_perfect:
                f.write(f"- **Lossless Accuracy**: MAE = 0 (perfect reconstruction across all {len(lossless_rows)} tests)\n")
            else:
                f.write(f"- **Lossless Accuracy**: Mixed results (see details)\n")
        f.write("\n---\n\n")
    
    # Detailed Results by Modality
    f.write("## Detailed Results\n\n")
    
    modalities = []
    for r in rows:
        m = r.get('Modality', 'Unknown')
        if m not in modalities:
            modalities.append(m)
    
    for mod in modalities:
        mod_rows = [r for r in rows if r.get('Modality') == mod]
        f.write(f"### {mod}\n\n")
        f.write("| Image | Size | Bits | Mode | J2K Enc (ms) | OPJ Enc (ms) | Speedup | J2K Size | OPJ Size | PSNR (dB) | MAE |\n")
        f.write("|-------|------|------|------|-------------|-------------|---------|----------|----------|-----------|-----|\n")
        
        for r in mod_rows:
            w = r.get('Width', '?')
            h = r.get('Height', '?')
            bd = r.get('BitDepth', '?')
            mode = f"{r.get('Mode', '?')} ({r.get('Rate', '')})" if r.get('Rate') != 'lossless' else 'Lossless'
            j2k_enc = r.get('J2K_EncTime_ms', 'N/A')
            opj_enc = r.get('OPJ_EncTime_ms', 'N/A')
            speedup = r.get('Speedup_Enc', 'N/A')
            j2k_sz = r.get('J2K_Size_bytes', '0')
            opj_sz = r.get('OPJ_Size_bytes', '0')
            psnr = r.get('J2K_PSNR_dB', 'N/A')
            mae = r.get('J2K_MAE', 'N/A')
            
            try:
                j2k_kb = f"{int(j2k_sz)/1024:.1f} KB"
            except:
                j2k_kb = "N/A"
            try:
                opj_kb = f"{int(opj_sz)/1024:.1f} KB"
            except:
                opj_kb = "N/A"
            
            if j2k_enc != 'N/A':
                try:
                    j2k_enc = f"{float(j2k_enc):.1f}"
                except:
                    pass
            if opj_enc != 'N/A':
                try:
                    opj_enc = f"{float(opj_enc):.1f}"
                except:
                    pass
            
            if psnr == 'inf':
                psnr = '∞'
            
            f.write(f"| {r.get('Image', '?')[:25]} | {w}×{h} | {bd} | {mode} | {j2k_enc} | {opj_enc} | **{speedup}** | {j2k_kb} | {opj_kb} | {psnr} | {mae} |\n")
        
        f.write("\n")
    
    # Decode Performance
    f.write("## Decode Performance\n\n")
    f.write("| Image | Mode | J2K Dec (ms) | OPJ Dec (ms) | Dec Speedup |\n")
    f.write("|-------|------|-------------|-------------|-------------|\n")
    for r in rows:
        j2k_dec = r.get('J2K_DecTime_ms', 'N/A')
        opj_dec = r.get('OPJ_DecTime_ms', 'N/A')
        dec_sp = r.get('Speedup_Dec', 'N/A')
        rate = r.get('Rate', '')
        mode = f"{r.get('Mode', '?')}" + (f" ({rate})" if rate != 'lossless' else '')
        
        if j2k_dec != 'N/A':
            try:
                j2k_dec = f"{float(j2k_dec):.1f}"
            except:
                pass
        if opj_dec != 'N/A':
            try:
                opj_dec = f"{float(opj_dec):.1f}"
            except:
                pass
        
        f.write(f"| {r.get('Image', '?')[:30]} | {mode} | {j2k_dec} | {opj_dec} | **{dec_sp}** |\n")
    f.write("\n")
    
    # Quality Summary
    f.write("## Quality Summary\n\n")
    f.write("### Lossless Reconstruction\n\n")
    f.write("| Image | Bit Depth | MAE | Status |\n")
    f.write("|-------|-----------|-----|--------|\n")
    for r in rows:
        if r.get('Mode') == 'lossless' and r.get('J2K_MAE') not in ('N/A', ''):
            try:
                mae_val = float(r['J2K_MAE'])
                status = '✅ Perfect' if mae_val == 0 else f'⚠ MAE={mae_val:.4f}'
            except:
                status = '❓'
            f.write(f"| {r.get('Image', '?')[:30]} | {r.get('BitDepth', '?')}-bit | {r.get('J2K_MAE', 'N/A')} | {status} |\n")
    f.write("\n")
    
    f.write("### Lossy Quality\n\n")
    f.write("| Image | Bit Depth | Mode | PSNR (dB) | MAE |\n")
    f.write("|-------|-----------|------|-----------|-----|\n")
    for r in rows:
        if r.get('Mode') != 'lossless' and r.get('J2K_PSNR_dB') not in ('N/A', ''):
            rate = r.get('Rate', '')
            f.write(f"| {r.get('Image', '?')[:30]} | {r.get('BitDepth', '?')}-bit | {r.get('Mode')} ({rate}) | {r.get('J2K_PSNR_dB', 'N/A')} | {r.get('J2K_MAE', 'N/A')} |\n")
    f.write("\n")
    
    f.write("---\n\n")
    f.write("*Report generated by J2KSwift medical imaging benchmark suite.*\n")
    f.write("*Licensed under MIT License. © 2026 Raster-Lab.*\n")

print(f"Report saved to: {report_path}")
REPORTEOF

echo ""
echo "Benchmark complete!"
echo "  CSV:    $CSV_FILE"
echo "  Report: $REPORT_FILE"
echo ""
