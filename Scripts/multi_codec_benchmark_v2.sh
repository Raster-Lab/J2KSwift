#!/bin/bash
#
# Multi-Codec JPEG 2000 Benchmark (Corrected)
# Compares: J2KSwift, OpenJPEG v2.5.4, Grok JPEG 2000, Pillow
#
# System: Apple M2, 24GB RAM, macOS 15.7.5
#

set -euo pipefail

J2K=".build/release/j2k"
OPJ_C="/opt/homebrew/bin/opj_compress"
OPJ_D="/opt/homebrew/bin/opj_decompress"
GRK_C="/opt/homebrew/bin/grk_compress"
GRK_D="/opt/homebrew/bin/grk_decompress"

OUTDIR="/tmp/bench_output"
RESULTS_CSV="/tmp/multi_codec_results.csv"
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

WARMUP=1
RUNS=5

echo "codec,mode,image,dimensions,time_ms,output_bytes" > "$RESULTS_CSV"

# High-res timing: returns avg ms over $RUNS
bench() {
    local total=0

    # warmup
    for ((i=0; i<WARMUP; i++)); do
        "$@" >/dev/null 2>&1 || true
    done

    for ((i=0; i<RUNS; i++)); do
        local start=$(python3 -c "import time; print(time.time()*1000)")
        "$@" >/dev/null 2>&1 || true
        local end=$(python3 -c "import time; print(time.time()*1000)")
        total=$(python3 -c "print($total + $end - $start)")
    done
    python3 -c "print(f'{$total / $RUNS:.1f}')"
}

echo ""
echo "=================================================================="
echo "  MULTI-CODEC JPEG 2000 BENCHMARK"
echo "  System: Apple M2 (8-core), 24GB, macOS 15.7.5"
echo "  Codecs: J2KSwift | OpenJPEG v2.5.4 | Grok J2K | Pillow 11.3"
echo "  Runs per test: $RUNS (+ $WARMUP warmup)"
echo "  Date: $(date)"
echo "=================================================================="
echo ""

IMAGES=(/tmp/bench_gray_256.pgm /tmp/bench_gray_512.pgm /tmp/bench_gray_1024.pgm /tmp/bench_gray_2048.pgm /tmp/bench_color_512.ppm /tmp/bench_color_1024.ppm)

#--------------------------------------------------------------------
# LOSSLESS ENCODE
#--------------------------------------------------------------------
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│                    LOSSLESS ENCODE (5/3 DWT)                   │"
echo "├──────────────────┬──────────────┬──────────────┬──────────────┤"
printf "│ %-16s │ %12s │ %12s │ %12s │\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)"
echo "├──────────────────┼──────────────┼──────────────┼──────────────┤"

for img in "${IMAGES[@]}"; do
    name=$(basename "$img")
    dims="${name%.p?m}"

    j2k_out="$OUTDIR/${dims}_j2k_lossless.j2k"
    j2k_ms=$(bench "$J2K" encode -i "$img" -o "$j2k_out" --lossless --quiet)
    j2k_sz=$(stat -f%z "$j2k_out" 2>/dev/null || echo 0)
    echo "j2kswift,lossless_encode,$name,$dims,$j2k_ms,$j2k_sz" >> "$RESULTS_CSV"

    opj_out="$OUTDIR/${dims}_opj_lossless.j2k"
    opj_ms=$(bench "$OPJ_C" -i "$img" -o "$opj_out" -r 1)
    opj_sz=$(stat -f%z "$opj_out" 2>/dev/null || echo 0)
    echo "openjpeg,lossless_encode,$name,$dims,$opj_ms,$opj_sz" >> "$RESULTS_CSV"

    grk_out="$OUTDIR/${dims}_grk_lossless.j2k"
    grk_ms=$(bench "$GRK_C" -i "$img" -o "$grk_out" -r 1)
    grk_sz=$(stat -f%z "$grk_out" 2>/dev/null || echo 0)
    echo "grok,lossless_encode,$name,$dims,$grk_ms,$grk_sz" >> "$RESULTS_CSV"

    printf "│ %-16s │ %12s │ %12s │ %12s │\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms"
done
echo "└──────────────────┴──────────────┴──────────────┴──────────────┘"
echo ""

#--------------------------------------------------------------------
# LOSSY ENCODE (compression ratio ~20:1)
#--------------------------------------------------------------------
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│                 LOSSY ENCODE (9/7 DWT, ~20:1)                  │"
echo "├──────────────────┬──────────────┬──────────────┬──────────────┤"
printf "│ %-16s │ %12s │ %12s │ %12s │\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)"
echo "├──────────────────┼──────────────┼──────────────┼──────────────┤"

for img in "${IMAGES[@]}"; do
    name=$(basename "$img")
    dims="${name%.p?m}"

    j2k_out="$OUTDIR/${dims}_j2k_lossy.j2k"
    j2k_ms=$(bench "$J2K" encode -i "$img" -o "$j2k_out" --irreversible --quality 0.5 --quiet)
    j2k_sz=$(stat -f%z "$j2k_out" 2>/dev/null || echo 0)
    echo "j2kswift,lossy_encode,$name,$dims,$j2k_ms,$j2k_sz" >> "$RESULTS_CSV"

    opj_out="$OUTDIR/${dims}_opj_lossy.j2k"
    opj_ms=$(bench "$OPJ_C" -i "$img" -o "$opj_out" -r 20)
    opj_sz=$(stat -f%z "$opj_out" 2>/dev/null || echo 0)
    echo "openjpeg,lossy_encode,$name,$dims,$opj_ms,$opj_sz" >> "$RESULTS_CSV"

    grk_out="$OUTDIR/${dims}_grk_lossy.j2k"
    grk_ms=$(bench "$GRK_C" -i "$img" -o "$grk_out" -r 20)
    grk_sz=$(stat -f%z "$grk_out" 2>/dev/null || echo 0)
    echo "grok,lossy_encode,$name,$dims,$grk_ms,$grk_sz" >> "$RESULTS_CSV"

    printf "│ %-16s │ %12s │ %12s │ %12s │\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms"
done
echo "└──────────────────┴──────────────┴──────────────┴──────────────┘"
echo ""

#--------------------------------------------------------------------
# LOSSLESS DECODE (decode OpenJPEG-encoded files for fairness)
#--------------------------------------------------------------------
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│                       LOSSLESS DECODE                          │"
echo "├──────────────────┬──────────────┬──────────────┬──────────────┤"
printf "│ %-16s │ %12s │ %12s │ %12s │\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)"
echo "├──────────────────┼──────────────┼──────────────┼──────────────┤"

for img in "${IMAGES[@]}"; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    ext="pgm"
    [[ "$name" == *color* ]] && ext="ppm"

    # Use OpenJPEG-encoded lossless file as input (fair baseline)
    j2k_in="$OUTDIR/${dims}_opj_lossless.j2k"
    [[ ! -f "$j2k_in" ]] && { printf "│ %-16s │ %12s │ %12s │ %12s │\n" "$dims" "SKIP" "SKIP" "SKIP"; continue; }

    j2k_dec="$OUTDIR/${dims}_j2k_dec.$ext"
    j2k_ms=$(bench "$J2K" decode -i "$j2k_in" -o "$j2k_dec" --quiet)
    echo "j2kswift,lossless_decode,$name,$dims,$j2k_ms,0" >> "$RESULTS_CSV"

    opj_dec="$OUTDIR/${dims}_opj_dec.$ext"
    opj_ms=$(bench "$OPJ_D" -i "$j2k_in" -o "$opj_dec")
    echo "openjpeg,lossless_decode,$name,$dims,$opj_ms,0" >> "$RESULTS_CSV"

    grk_dec="$OUTDIR/${dims}_grk_dec.$ext"
    grk_ms=$(bench "$GRK_D" -i "$j2k_in" -o "$grk_dec")
    echo "grok,lossless_decode,$name,$dims,$grk_ms,0" >> "$RESULTS_CSV"

    printf "│ %-16s │ %12s │ %12s │ %12s │\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms"
done
echo "└──────────────────┴──────────────┴──────────────┴──────────────┘"
echo ""

#--------------------------------------------------------------------
# LOSSY DECODE
#--------------------------------------------------------------------
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│                        LOSSY DECODE                            │"
echo "├──────────────────┬──────────────┬──────────────┬──────────────┤"
printf "│ %-16s │ %12s │ %12s │ %12s │\n" "Image" "J2KSwift(ms)" "OpenJPEG(ms)" "Grok(ms)"
echo "├──────────────────┼──────────────┼──────────────┼──────────────┤"

for img in "${IMAGES[@]}"; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    ext="pgm"
    [[ "$name" == *color* ]] && ext="ppm"

    j2k_in="$OUTDIR/${dims}_opj_lossy.j2k"
    [[ ! -f "$j2k_in" ]] && { printf "│ %-16s │ %12s │ %12s │ %12s │\n" "$dims" "SKIP" "SKIP" "SKIP"; continue; }

    j2k_dec="$OUTDIR/${dims}_j2k_lossy_dec.$ext"
    j2k_ms=$(bench "$J2K" decode -i "$j2k_in" -o "$j2k_dec" --quiet)
    echo "j2kswift,lossy_decode,$name,$dims,$j2k_ms,0" >> "$RESULTS_CSV"

    opj_dec="$OUTDIR/${dims}_opj_lossy_dec.$ext"
    opj_ms=$(bench "$OPJ_D" -i "$j2k_in" -o "$opj_dec")
    echo "openjpeg,lossy_decode,$name,$dims,$opj_ms,0" >> "$RESULTS_CSV"

    grk_dec="$OUTDIR/${dims}_grk_lossy_dec.$ext"
    grk_ms=$(bench "$GRK_D" -i "$j2k_in" -o "$grk_dec")
    echo "grok,lossy_decode,$name,$dims,$grk_ms,0" >> "$RESULTS_CSV"

    printf "│ %-16s │ %12s │ %12s │ %12s │\n" "$dims" "$j2k_ms" "$opj_ms" "$grk_ms"
done
echo "└──────────────────┴──────────────┴──────────────┴──────────────┘"
echo ""

#--------------------------------------------------------------------
# COMPRESSED FILE SIZES
#--------------------------------------------------------------------
echo "┌──────────────────────────────────────────────────────────────────────────┐"
echo "│                       COMPRESSED FILE SIZES (bytes)                     │"
echo "├──────────────────┬──────────┬──────────────┬──────────────┬─────────────┤"
printf "│ %-16s │ %-8s │ %12s │ %12s │ %11s │\n" "Image" "Mode" "J2KSwift" "OpenJPEG" "Grok"
echo "├──────────────────┼──────────┼──────────────┼──────────────┼─────────────┤"

for img in "${IMAGES[@]}"; do
    name=$(basename "$img")
    dims="${name%.p?m}"
    raw_sz=$(stat -f%z "$img")
    
    for mode in lossless lossy; do
        j2k_sz=$(stat -f%z "$OUTDIR/${dims}_j2k_${mode}.j2k" 2>/dev/null || echo "N/A")
        opj_sz=$(stat -f%z "$OUTDIR/${dims}_opj_${mode}.j2k" 2>/dev/null || echo "N/A")
        grk_sz=$(stat -f%z "$OUTDIR/${dims}_grk_${mode}.j2k" 2>/dev/null || echo "N/A")
        printf "│ %-16s │ %-8s │ %12s │ %12s │ %11s │\n" "$dims" "$mode" "$j2k_sz" "$opj_sz" "$grk_sz"
    done
done
echo "└──────────────────┴──────────┴──────────────┴──────────────┴─────────────┘"
echo ""

#--------------------------------------------------------------------
# CROSS-CODEC INTEROPERABILITY
#--------------------------------------------------------------------
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│            CROSS-CODEC INTEROPERABILITY (1024x1024)            │"
echo "├───────────────────┬───────────────┬───────────────────────────┤"
printf "│ %-17s │ %-13s │ %-25s │\n" "Encoded By" "Decoded By" "Result"
echo "├───────────────────┼───────────────┼───────────────────────────┤"

# J2KSwift -> others
j2k_file="$OUTDIR/bench_gray_1024_j2k_lossless.j2k"
if [ -f "$j2k_file" ]; then
    opj_out="$OUTDIR/xval_j2k_to_opj.pgm"
    result=$("$OPJ_D" -i "$j2k_file" -o "$opj_out" >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    printf "│ %-17s │ %-13s │ %-25s │\n" "J2KSwift" "OpenJPEG" "$result"
    
    grk_out="$OUTDIR/xval_j2k_to_grk.pgm"
    result=$("$GRK_D" -i "$j2k_file" -o "$grk_out" >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    printf "│ %-17s │ %-13s │ %-25s │\n" "J2KSwift" "Grok" "$result"
fi

# OpenJPEG -> others
opj_file="$OUTDIR/bench_gray_1024_opj_lossless.j2k"
if [ -f "$opj_file" ]; then
    j2k_out="$OUTDIR/xval_opj_to_j2k.pgm"
    result=$("$J2K" decode -i "$opj_file" -o "$j2k_out" --quiet >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    printf "│ %-17s │ %-13s │ %-25s │\n" "OpenJPEG" "J2KSwift" "$result"

    grk_out="$OUTDIR/xval_opj_to_grk.pgm"
    result=$("$GRK_D" -i "$opj_file" -o "$grk_out" >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    printf "│ %-17s │ %-13s │ %-25s │\n" "OpenJPEG" "Grok" "$result"
fi

# Grok -> others
grk_file="$OUTDIR/bench_gray_1024_grk_lossless.j2k"
if [ -f "$grk_file" ]; then
    j2k_out="$OUTDIR/xval_grk_to_j2k.pgm"
    result=$("$J2K" decode -i "$grk_file" -o "$j2k_out" --quiet >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    printf "│ %-17s │ %-13s │ %-25s │\n" "Grok" "J2KSwift" "$result"

    opj_out="$OUTDIR/xval_grk_to_opj.pgm"
    result=$("$OPJ_D" -i "$grk_file" -o "$opj_out" >/dev/null 2>&1 && echo "OK" || echo "FAIL")
    printf "│ %-17s │ %-13s │ %-25s │\n" "Grok" "OpenJPEG" "$result"
fi
echo "└───────────────────┴───────────────┴───────────────────────────┘"
echo ""

#--------------------------------------------------------------------
# QUALITY METRICS (compare lossy decoded to original)
#--------------------------------------------------------------------
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│          LOSSY QUALITY METRICS (1024x1024 grayscale)           │"
echo "└─────────────────────────────────────────────────────────────────┘"
echo ""

orig="/tmp/bench_gray_1024.pgm"

for codec_tag in j2k opj grk; do
    case "$codec_tag" in
        j2k) codec_name="J2KSwift" ;;
        opj) codec_name="OpenJPEG" ;;
        grk) codec_name="Grok" ;;
    esac
    
    lossy_file="$OUTDIR/bench_gray_1024_${codec_tag}_lossy.j2k"
    if [ -f "$lossy_file" ]; then
        # Decode with its own decoder
        dec_file="$OUTDIR/quality_${codec_tag}_decoded.pgm"
        case "$codec_tag" in
            j2k) "$J2K" decode -i "$lossy_file" -o "$dec_file" --quiet >/dev/null 2>&1 ;;
            opj) "$OPJ_D" -i "$lossy_file" -o "$dec_file" >/dev/null 2>&1 ;;
            grk) "$GRK_D" -i "$lossy_file" -o "$dec_file" >/dev/null 2>&1 ;;
        esac

        if [ -f "$dec_file" ]; then
            echo "--- $codec_name ---"
            "$J2K" compare -i "$orig" -r "$dec_file" 2>&1 || echo "  (compare failed)"
            echo ""
        fi
    fi
done

#--------------------------------------------------------------------
# PILLOW BENCHMARK
#--------------------------------------------------------------------
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│              PILLOW (Python) JPEG 2000 BENCHMARK               │"
echo "└─────────────────────────────────────────────────────────────────┘"
echo ""

python3 << 'PYEOF'
import time, os

try:
    from PIL import Image
    
    sizes = [
        ("/tmp/bench_gray_256.pgm", "256x256 gray"),
        ("/tmp/bench_gray_512.pgm", "512x512 gray"),
        ("/tmp/bench_gray_1024.pgm", "1024x1024 gray"),
        ("/tmp/bench_gray_2048.pgm", "2048x2048 gray"),
        ("/tmp/bench_color_512.ppm", "512x512 color"),
        ("/tmp/bench_color_1024.ppm", "1024x1024 color"),
    ]
    
    RUNS = 5
    
    print(f"{'Image':<20} {'Encode(ms)':<14} {'Decode(ms)':<14} {'Size(bytes)':<14}")
    print("-" * 62)
    
    for path, label in sizes:
        img = Image.open(path)
        out_path = f"/tmp/bench_output/pillow_{os.path.basename(path).replace('.pgm','.j2k').replace('.ppm','.j2k')}"
        
        # Warmup
        img.save(out_path, 'JPEG2000', irreversible=False)
        
        # Encode
        total_enc = 0
        for _ in range(RUNS):
            start = time.perf_counter()
            img.save(out_path, 'JPEG2000', irreversible=False)
            total_enc += (time.perf_counter() - start) * 1000
        avg_enc = total_enc / RUNS
        sz = os.path.getsize(out_path)
        
        # Decode
        total_dec = 0
        for _ in range(RUNS):
            start = time.perf_counter()
            _ = Image.open(out_path).load()
            total_dec += (time.perf_counter() - start) * 1000
        avg_dec = total_dec / RUNS
        
        print(f"{label:<20} {avg_enc:<14.1f} {avg_dec:<14.1f} {sz:<14}")
        
        name = os.path.basename(path)
        dims = label.split()[0]
        with open("/tmp/multi_codec_results.csv", "a") as f:
            f.write(f"pillow,lossless_encode,{name},{dims},{avg_enc:.1f},{sz}\n")
            f.write(f"pillow,lossless_decode,{name},{dims},{avg_dec:.1f},0\n")

except Exception as e:
    print(f"Pillow benchmark error: {e}")
PYEOF

echo ""
echo "=================================================================="
echo "  BENCHMARK COMPLETE"
echo "  Results CSV: $RESULTS_CSV"
echo "=================================================================="
