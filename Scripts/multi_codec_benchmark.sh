#!/bin/bash
#
# Multi-Codec JPEG 2000 Benchmark
# Compares: J2KSwift, OpenJPEG v2.5.4, Grok JPEG 2000, ImageMagick 7, Pillow
#
# System: Apple M2, 24GB RAM, macOS 15.7.5
#

set -euo pipefail

J2K=".build/release/j2k"
OPJ_C="/opt/homebrew/bin/opj_compress"
OPJ_D="/opt/homebrew/bin/opj_decompress"
GRK_C="/opt/homebrew/bin/grk_compress"
GRK_D="/opt/homebrew/bin/grk_decompress"
MAGICK="/opt/homebrew/bin/magick"

OUTDIR="/tmp/bench_output"
RESULTS_CSV="/tmp/bench_results.csv"
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

WARMUP=1
RUNS=3

echo "codec,mode,image,size,time_ms,output_bytes" > "$RESULTS_CSV"

# Timing helper: runs command $RUNS times, returns average ms
bench() {
    local label="$1"; shift
    local total=0

    # warmup
    for ((i=0; i<WARMUP; i++)); do
        "$@" >/dev/null 2>&1 || true
    done

    for ((i=0; i<RUNS; i++)); do
        local start=$(python3 -c "import time; print(int(time.time()*1000))")
        "$@" >/dev/null 2>&1 || true
        local end=$(python3 -c "import time; print(int(time.time()*1000))")
        total=$((total + end - start))
    done
    echo $((total / RUNS))
}

echo ""
echo "============================================================"
echo "  MULTI-CODEC JPEG 2000 BENCHMARK"
echo "  System: Apple M2, 24GB, macOS 15.7.5"
echo "  Date: $(date)"
echo "============================================================"
echo ""

#--------------------------------------------------------------------
# LOSSLESS ENCODE BENCHMARKS
#--------------------------------------------------------------------
echo "=== LOSSLESS ENCODE (5/3 Reversible) ==="
echo ""
printf "%-20s %-14s %-14s %-14s %-14s\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)" "Magick(ms)"
printf "%-20s %-14s %-14s %-14s %-14s\n" "--------------------" "--------------" "--------------" "--------------" "--------------"

for img in /tmp/bench_gray_256.pgm /tmp/bench_gray_512.pgm /tmp/bench_gray_1024.pgm /tmp/bench_gray_2048.pgm /tmp/bench_color_512.ppm /tmp/bench_color_1024.ppm; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    
    # J2KSwift lossless
    j2k_out="$OUTDIR/${dims}_j2k_lossless.j2k"
    j2k_ms=$(bench "j2k" "$J2K" encode "$img" "$j2k_out" --lossless)
    j2k_sz=$(stat -f%z "$j2k_out" 2>/dev/null || echo 0)
    echo "j2kswift,lossless_encode,$name,$dims,$j2k_ms,$j2k_sz" >> "$RESULTS_CSV"
    
    # OpenJPEG lossless
    opj_out="$OUTDIR/${dims}_opj_lossless.j2k"
    opj_ms=$(bench "opj" "$OPJ_C" -i "$img" -o "$opj_out" -r 1)
    opj_sz=$(stat -f%z "$opj_out" 2>/dev/null || echo 0)
    echo "openjpeg,lossless_encode,$name,$dims,$opj_ms,$opj_sz" >> "$RESULTS_CSV"
    
    # Grok lossless
    grk_out="$OUTDIR/${dims}_grk_lossless.j2k"
    grk_ms=$(bench "grk" "$GRK_C" -i "$img" -o "$grk_out" -r 1)
    grk_sz=$(stat -f%z "$grk_out" 2>/dev/null || echo 0)
    echo "grok,lossless_encode,$name,$dims,$grk_ms,$grk_sz" >> "$RESULTS_CSV"
    
    # ImageMagick (uses OpenJPEG internally)
    mag_out="$OUTDIR/${dims}_magick_lossless.j2k"
    mag_ms=$(bench "magick" "$MAGICK" "$img" -quality 100 "$mag_out")
    mag_sz=$(stat -f%z "$mag_out" 2>/dev/null || echo 0)
    echo "imagemagick,lossless_encode,$name,$dims,$mag_ms,$mag_sz" >> "$RESULTS_CSV"
    
    printf "%-20s %-14s %-14s %-14s %-14s\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms" "$mag_ms"
done

echo ""

#--------------------------------------------------------------------
# LOSSY ENCODE BENCHMARKS (rate 20:1)
#--------------------------------------------------------------------
echo "=== LOSSY ENCODE (9/7 Irreversible, rate ~20:1) ==="
echo ""
printf "%-20s %-14s %-14s %-14s %-14s\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)" "Magick(ms)"
printf "%-20s %-14s %-14s %-14s %-14s\n" "--------------------" "--------------" "--------------" "--------------" "--------------"

for img in /tmp/bench_gray_256.pgm /tmp/bench_gray_512.pgm /tmp/bench_gray_1024.pgm /tmp/bench_gray_2048.pgm /tmp/bench_color_512.ppm /tmp/bench_color_1024.ppm; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    
    # J2KSwift lossy
    j2k_out="$OUTDIR/${dims}_j2k_lossy.j2k"
    j2k_ms=$(bench "j2k" "$J2K" encode "$img" "$j2k_out" --quality 50)
    j2k_sz=$(stat -f%z "$j2k_out" 2>/dev/null || echo 0)
    echo "j2kswift,lossy_encode,$name,$dims,$j2k_ms,$j2k_sz" >> "$RESULTS_CSV"
    
    # OpenJPEG lossy
    opj_out="$OUTDIR/${dims}_opj_lossy.j2k"
    opj_ms=$(bench "opj" "$OPJ_C" -i "$img" -o "$opj_out" -r 20)
    opj_sz=$(stat -f%z "$opj_out" 2>/dev/null || echo 0)
    echo "openjpeg,lossy_encode,$name,$dims,$opj_ms,$opj_sz" >> "$RESULTS_CSV"
    
    # Grok lossy
    grk_out="$OUTDIR/${dims}_grk_lossy.j2k"
    grk_ms=$(bench "grk" "$GRK_C" -i "$img" -o "$grk_out" -r 20)
    grk_sz=$(stat -f%z "$grk_out" 2>/dev/null || echo 0)
    echo "grok,lossy_encode,$name,$dims,$grk_ms,$grk_sz" >> "$RESULTS_CSV"
    
    # ImageMagick lossy
    mag_out="$OUTDIR/${dims}_magick_lossy.j2k"
    mag_ms=$(bench "magick" "$MAGICK" "$img" -quality 50 "$mag_out")
    mag_sz=$(stat -f%z "$mag_out" 2>/dev/null || echo 0)
    echo "imagemagick,lossy_encode,$name,$dims,$mag_ms,$mag_sz" >> "$RESULTS_CSV"
    
    printf "%-20s %-14s %-14s %-14s %-14s\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms" "$mag_ms"
done

echo ""

#--------------------------------------------------------------------
# LOSSLESS DECODE BENCHMARKS
#--------------------------------------------------------------------
echo "=== LOSSLESS DECODE ==="
echo ""
printf "%-20s %-14s %-14s %-14s %-14s\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)" "Magick(ms)"
printf "%-20s %-14s %-14s %-14s %-14s\n" "--------------------" "--------------" "--------------" "--------------" "--------------"

for img in /tmp/bench_gray_256.pgm /tmp/bench_gray_512.pgm /tmp/bench_gray_1024.pgm /tmp/bench_gray_2048.pgm /tmp/bench_color_512.ppm /tmp/bench_color_1024.ppm; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    
    # Use OpenJPEG-encoded lossless files as standard input
    j2k_in="$OUTDIR/${dims}_opj_lossless.j2k"
    
    if [ ! -f "$j2k_in" ]; then
        printf "%-20s %-14s %-14s %-14s %-14s\n" "$dims" "SKIP" "SKIP" "SKIP" "SKIP"
        continue
    fi
    
    # Determine output extension
    ext="pgm"
    [[ "$name" == *color* ]] && ext="ppm"
    
    # J2KSwift decode
    j2k_dec="$OUTDIR/${dims}_j2k_dec_lossless.$ext"
    j2k_ms=$(bench "j2k" "$J2K" decode "$j2k_in" "$j2k_dec")
    echo "j2kswift,lossless_decode,$name,$dims,$j2k_ms,0" >> "$RESULTS_CSV"
    
    # OpenJPEG decode
    opj_dec="$OUTDIR/${dims}_opj_dec_lossless.$ext"
    opj_ms=$(bench "opj" "$OPJ_D" -i "$j2k_in" -o "$opj_dec")
    echo "openjpeg,lossless_decode,$name,$dims,$opj_ms,0" >> "$RESULTS_CSV"
    
    # Grok decode
    grk_dec="$OUTDIR/${dims}_grk_dec_lossless.$ext"
    grk_ms=$(bench "grk" "$GRK_D" -i "$j2k_in" -o "$grk_dec")
    echo "grok,lossless_decode,$name,$dims,$grk_ms,0" >> "$RESULTS_CSV"
    
    # ImageMagick decode
    mag_dec="$OUTDIR/${dims}_mag_dec_lossless.$ext"
    mag_ms=$(bench "magick" "$MAGICK" "$j2k_in" "$mag_dec")
    echo "imagemagick,lossless_decode,$name,$dims,$mag_ms,0" >> "$RESULTS_CSV"
    
    printf "%-20s %-14s %-14s %-14s %-14s\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms" "$mag_ms"
done

echo ""

#--------------------------------------------------------------------
# LOSSY DECODE BENCHMARKS
#--------------------------------------------------------------------
echo "=== LOSSY DECODE ==="
echo ""
printf "%-20s %-14s %-14s %-14s %-14s\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)" "Magick(ms)"
printf "%-20s %-14s %-14s %-14s %-14s\n" "--------------------" "--------------" "--------------" "--------------" "--------------"

for img in /tmp/bench_gray_256.pgm /tmp/bench_gray_512.pgm /tmp/bench_gray_1024.pgm /tmp/bench_gray_2048.pgm /tmp/bench_color_512.ppm /tmp/bench_color_1024.ppm; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    
    j2k_in="$OUTDIR/${dims}_opj_lossy.j2k"
    
    if [ ! -f "$j2k_in" ]; then
        printf "%-20s %-14s %-14s %-14s %-14s\n" "$dims" "SKIP" "SKIP" "SKIP" "SKIP"
        continue
    fi
    
    ext="pgm"
    [[ "$name" == *color* ]] && ext="ppm"
    
    j2k_dec="$OUTDIR/${dims}_j2k_dec_lossy.$ext"
    j2k_ms=$(bench "j2k" "$J2K" decode "$j2k_in" "$j2k_dec")
    echo "j2kswift,lossy_decode,$name,$dims,$j2k_ms,0" >> "$RESULTS_CSV"
    
    opj_dec="$OUTDIR/${dims}_opj_dec_lossy.$ext"
    opj_ms=$(bench "opj" "$OPJ_D" -i "$j2k_in" -o "$opj_dec")
    echo "openjpeg,lossy_decode,$name,$dims,$opj_ms,0" >> "$RESULTS_CSV"
    
    grk_dec="$OUTDIR/${dims}_grk_dec_lossy.$ext"
    grk_ms=$(bench "grk" "$GRK_D" -i "$j2k_in" -o "$grk_dec")
    echo "grok,lossy_decode,$name,$dims,$grk_ms,0" >> "$RESULTS_CSV"
    
    mag_dec="$OUTDIR/${dims}_mag_dec_lossy.$ext"
    mag_ms=$(bench "magick" "$MAGICK" "$j2k_in" "$mag_dec")
    echo "imagemagick,lossy_decode,$name,$dims,$mag_ms,0" >> "$RESULTS_CSV"
    
    printf "%-20s %-14s %-14s %-14s %-14s\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms" "$mag_ms"
done

echo ""

#--------------------------------------------------------------------
# COMPRESSED FILE SIZE COMPARISON
#--------------------------------------------------------------------
echo "=== COMPRESSED FILE SIZE (bytes) ==="
echo ""
printf "%-20s %-8s %-14s %-14s %-14s %-14s\n" "Image" "Mode" "J2KSwift" "OpenJPEG" "Grok" "Magick"
printf "%-20s %-8s %-14s %-14s %-14s %-14s\n" "--------------------" "--------" "--------------" "--------------" "--------------" "--------------"

for img in /tmp/bench_gray_256.pgm /tmp/bench_gray_512.pgm /tmp/bench_gray_1024.pgm /tmp/bench_gray_2048.pgm /tmp/bench_color_512.ppm /tmp/bench_color_1024.ppm; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    
    for mode in lossless lossy; do
        j2k_sz=$(stat -f%z "$OUTDIR/${dims}_j2k_${mode}.j2k" 2>/dev/null || echo "N/A")
        opj_sz=$(stat -f%z "$OUTDIR/${dims}_opj_${mode}.j2k" 2>/dev/null || echo "N/A")
        grk_sz=$(stat -f%z "$OUTDIR/${dims}_grk_${mode}.j2k" 2>/dev/null || echo "N/A")
        mag_sz=$(stat -f%z "$OUTDIR/${dims}_magick_${mode}.j2k" 2>/dev/null || echo "N/A")
        printf "%-20s %-8s %-14s %-14s %-14s %-14s\n" "$dims" "$mode" "$j2k_sz" "$opj_sz" "$grk_sz" "$mag_sz"
    done
done

echo ""

#--------------------------------------------------------------------
# CROSS-CODEC VALIDATION (encode with X, decode with Y)
#--------------------------------------------------------------------
echo "=== CROSS-CODEC DECODE VALIDATION (1024x1024 grayscale) ==="
echo ""

test_img="/tmp/bench_gray_1024.pgm"
echo "Testing: encode with codec A, decode with codec B"
echo ""

# Encode with each codec (lossless)
echo "--- Encode with J2KSwift, decode with others ---"
j2k_file="$OUTDIR/bench_gray_1024_j2k_lossless.j2k"
if [ -f "$j2k_file" ]; then
    opj_out="$OUTDIR/xval_j2k_to_opj.pgm"
    "$OPJ_D" -i "$j2k_file" -o "$opj_out" >/dev/null 2>&1 && echo "  OpenJPEG decoded J2KSwift file: OK" || echo "  OpenJPEG decoded J2KSwift file: FAIL"
    
    grk_out="$OUTDIR/xval_j2k_to_grk.pgm"
    "$GRK_D" -i "$j2k_file" -o "$grk_out" >/dev/null 2>&1 && echo "  Grok decoded J2KSwift file: OK" || echo "  Grok decoded J2KSwift file: FAIL"
fi

echo ""
echo "--- Encode with OpenJPEG, decode with others ---"
opj_file="$OUTDIR/bench_gray_1024_opj_lossless.j2k"
if [ -f "$opj_file" ]; then
    j2k_out="$OUTDIR/xval_opj_to_j2k.pgm"
    "$J2K" decode "$opj_file" "$j2k_out" >/dev/null 2>&1 && echo "  J2KSwift decoded OpenJPEG file: OK" || echo "  J2KSwift decoded OpenJPEG file: FAIL"
    
    grk_out="$OUTDIR/xval_opj_to_grk.pgm"
    "$GRK_D" -i "$opj_file" -o "$grk_out" >/dev/null 2>&1 && echo "  Grok decoded OpenJPEG file: OK" || echo "  Grok decoded OpenJPEG file: FAIL"
fi

echo ""
echo "--- Encode with Grok, decode with others ---"
grk_file="$OUTDIR/bench_gray_1024_grk_lossless.j2k"
if [ -f "$grk_file" ]; then
    j2k_out="$OUTDIR/xval_grk_to_j2k.pgm"
    "$J2K" decode "$grk_file" "$j2k_out" >/dev/null 2>&1 && echo "  J2KSwift decoded Grok file: OK" || echo "  J2KSwift decoded Grok file: FAIL"
    
    opj_out="$OUTDIR/xval_grk_to_opj.pgm"
    "$OPJ_D" -i "$grk_file" -o "$opj_out" >/dev/null 2>&1 && echo "  OpenJPEG decoded Grok file: OK" || echo "  OpenJPEG decoded Grok file: FAIL"
fi

echo ""

#--------------------------------------------------------------------
# QUALITY METRICS (lossy comparison on 1024x1024 gray)
#--------------------------------------------------------------------
echo "=== QUALITY METRICS (1024x1024 grayscale, lossy) ==="
echo ""

orig="/tmp/bench_gray_1024.pgm"
for codec in j2k opj grk; do
    lossy_file="$OUTDIR/bench_gray_1024_${codec}_lossy.j2k"
    if [ -f "$lossy_file" ]; then
        # Decode with OpenJPEG (common denominator) for comparison
        dec_file="$OUTDIR/quality_${codec}_decoded.pgm"
        "$OPJ_D" -i "$lossy_file" -o "$dec_file" >/dev/null 2>&1 || "$J2K" decode "$lossy_file" "$dec_file" >/dev/null 2>&1 || true
        
        if [ -f "$dec_file" ]; then
            codec_name="$codec"
            [[ "$codec" == "j2k" ]] && codec_name="J2KSwift"
            [[ "$codec" == "opj" ]] && codec_name="OpenJPEG"
            [[ "$codec" == "grk" ]] && codec_name="Grok"
            
            # Use J2KSwift compare tool for metrics
            echo "--- $codec_name ---"
            "$J2K" compare "$orig" "$dec_file" 2>&1 || echo "  (compare not available)"
            echo ""
        fi
    fi
done

#--------------------------------------------------------------------
# PILLOW PYTHON BENCHMARK (separate since it uses different API)
#--------------------------------------------------------------------
echo "=== PILLOW (Python) ENCODE BENCHMARK ==="
echo ""

python3 << 'PYEOF'
import time, os, struct

try:
    from PIL import Image
    
    sizes = [
        ("/tmp/bench_gray_256.pgm", "256x256 gray"),
        ("/tmp/bench_gray_512.pgm", "512x512 gray"),
        ("/tmp/bench_gray_1024.pgm", "1024x1024 gray"),
        ("/tmp/bench_color_512.ppm", "512x512 color"),
    ]
    
    print(f"{'Image':<20} {'Encode(ms)':<14} {'Decode(ms)':<14} {'Size(bytes)':<14}")
    print("-" * 62)
    
    RUNS = 3
    
    for path, label in sizes:
        img = Image.open(path)
        
        out_path = f"/tmp/bench_output/pillow_{os.path.basename(path).replace('.pgm','.j2k').replace('.ppm','.j2k')}"
        
        # Warmup
        img.save(out_path, 'JPEG2000', irreversible=False)
        
        # Encode timing
        total_enc = 0
        for _ in range(RUNS):
            start = time.time()
            img.save(out_path, 'JPEG2000', irreversible=False)
            total_enc += (time.time() - start) * 1000
        avg_enc = int(total_enc / RUNS)
        
        sz = os.path.getsize(out_path)
        
        # Decode timing
        total_dec = 0
        for _ in range(RUNS):
            start = time.time()
            _ = Image.open(out_path).load()
            total_dec += (time.time() - start) * 1000
        avg_dec = int(total_dec / RUNS)
        
        print(f"{label:<20} {avg_enc:<14} {avg_dec:<14} {sz:<14}")
        
        # Write to CSV
        with open("/tmp/bench_results.csv", "a") as f:
            name = os.path.basename(path)
            dims = label.split()[0]
            f.write(f"pillow,lossless_encode,{name},{dims},{avg_enc},{sz}\n")
            f.write(f"pillow,lossless_decode,{name},{dims},{avg_dec},0\n")
    
    print()

except Exception as e:
    print(f"Pillow benchmark failed: {e}")
PYEOF

echo ""
echo "============================================================"
echo "  BENCHMARK COMPLETE"
echo "  Results saved to: $RESULTS_CSV"
echo "============================================================"
echo ""
