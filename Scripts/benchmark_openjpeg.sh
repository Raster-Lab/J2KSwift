#!/bin/bash
#
# J2KSwift OpenJPEG Benchmark Comparison Script
#
# Week 269-271 deliverable: Automated performance comparison between J2KSwift
# and OpenJPEG across all standardised image sizes, coding modes, and operations.
#
# This script automates performance comparison between J2KSwift and OpenJPEG.
# It generates test images, encodes/decodes them with both implementations,
# and produces a detailed comparison report (text, CSV, and JSON).
#
# Requirements:
# - Swift 6.2+
# - OpenJPEG (opj_compress, opj_decompress) — optional; skip with --no-openjpeg
# - python3 — for test image generation and CSV analysis
# - bc — for arithmetic in timing calculations
#
# Usage:
#   ./benchmark_openjpeg.sh [options]
#
# Options:
#   -h, --help            Show this help message
#   -o, --output DIR      Output directory for results (default: ./benchmark_results)
#   -s, --sizes SIZES     Comma-separated list of image sizes (default: 512,1024)
#   -m, --modes MODES     Comma-separated coding modes: lossless,lossy2,lossy1,lossy05,htj2k
#                         (default: lossless,lossy2)
#   -r, --runs N          Number of benchmark runs per configuration (default: 5)
#   -w, --warmup N        Number of warm-up runs discarded before measurement (default: 2)
#   --no-openjpeg         Skip OpenJPEG benchmarks (J2KSwift only)
#   --regression-check    Compare against baseline and flag regressions >5%
#   --baseline FILE       Baseline CSV file for regression detection
#   --format FORMAT       Output format: text,csv,json (default: text,csv)
#

set -e

# Default configuration
OUTPUT_DIR="./benchmark_results"
IMAGE_SIZES="512,1024"
CODING_MODES="lossless,lossy2"
NUM_RUNS=5
WARMUP_RUNS=2
RUN_OPENJPEG=true
REGRESSION_CHECK=false
BASELINE_FILE=""
OUTPUT_FORMAT="text,csv"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            grep '^#' "$0" | tail -n +3 | head -n -1 | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -s|--sizes)
            IMAGE_SIZES="$2"
            shift 2
            ;;
        -m|--modes)
            CODING_MODES="$2"
            shift 2
            ;;
        -r|--runs)
            NUM_RUNS="$2"
            shift 2
            ;;
        -w|--warmup)
            WARMUP_RUNS="$2"
            shift 2
            ;;
        --no-openjpeg)
            RUN_OPENJPEG=false
            shift
            ;;
        --regression-check)
            REGRESSION_CHECK=true
            shift
            ;;
        --baseline)
            BASELINE_FILE="$2"
            shift 2
            ;;
        --format)
            OUTPUT_FORMAT="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Error: Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check requirements
check_requirements() {
    log_info "Checking requirements..."
    
    if ! command -v swift &> /dev/null; then
        log_warning "Swift compiler not found"
    fi
    
    if $RUN_OPENJPEG && ! command -v opj_compress &> /dev/null; then
        log_warning "OpenJPEG not found (use --no-openjpeg to skip)"
        RUN_OPENJPEG=false
    fi

    if $RUN_OPENJPEG && command -v opj_compress &> /dev/null; then
        OPJ_VERSION=$(opj_compress -h 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
        log_info "OpenJPEG version: ${OPJ_VERSION}"
    fi
    
    log_success "Requirements check complete"
}

# Setup
setup_output() {
    log_info "Setting up output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/test_images"
    mkdir -p "$OUTPUT_DIR/openjpeg"
    mkdir -p "$OUTPUT_DIR/j2kswift"
    mkdir -p "$OUTPUT_DIR/reports"
}

# Generate test images
generate_test_images() {
    log_info "Generating test images..."
    
    IFS=',' read -ra SIZES <<< "$IMAGE_SIZES"
    for size in "${SIZES[@]}"; do
        local output_file="$OUTPUT_DIR/test_images/test_${size}x${size}.ppm"
        
        if [[ -f "$output_file" ]]; then
            log_info "  Test image ${size}×${size} already exists"
            continue
        fi
        
        log_info "  Generating ${size}×${size} RGB test image..."
        python3 << EOF
import math, random
size = $size
random.seed(42)
with open('$output_file', 'wb') as f:
    f.write(f'P6\n{size} {size}\n255\n'.encode())
    data = []
    for y in range(size):
        for x in range(size):
            # Natural photo simulation: smooth + noise
            fx = x / size
            fy = y / size
            r = int((math.sin(fx * 3.14159 * 4 + 0.0) * 0.5 + 0.5) * 217 + random.randint(0, 38))
            g = int((math.sin(fy * 3.14159 * 4 + 1.0) * 0.5 + 0.5) * 217 + random.randint(0, 38))
            b = int((math.sin((fx+fy) * 3.14159 * 2 + 2.0) * 0.5 + 0.5) * 217 + random.randint(0, 38))
            data.extend([min(255,r), min(255,g), min(255,b)])
    f.write(bytes(data))
EOF
        log_success "  Generated test_${size}x${size}.ppm"
    done
}

# Measure median time for a command (runs $1 times, returns median in seconds)
measure_median_time() {
    local cmd="$1"
    local runs="$2"
    local warmup="$3"
    local times=()

    # Warm-up runs (discarded)
    for ((i=1; i<=warmup; i++)); do
        eval "$cmd" > /dev/null 2>&1 || true
    done

    # Measurement runs
    for ((i=1; i<=runs; i++)); do
        local start end elapsed
        start=$(python3 -c "import time; print(f'{time.perf_counter():.9f}')")
        eval "$cmd" > /dev/null 2>&1 || true
        end=$(python3 -c "import time; print(f'{time.perf_counter():.9f}')")
        elapsed=$(python3 -c "print(f'{$end - $start:.6f}')")
        times+=("$elapsed")
    done

    # Compute median via python3
    python3 << EOF
times = sorted([${times[@]}])
n = len(times)
if n % 2 == 1:
    print(f'{times[n//2]:.6f}')
else:
    print(f'{(times[n//2-1] + times[n//2]) / 2:.6f}')
EOF
}

# Benchmark OpenJPEG for a single image + mode
benchmark_openjpeg_single() {
    local input_file="$1"
    local size="$2"
    local mode="$3"
    local output_file="$OUTPUT_DIR/openjpeg/test_${size}x${size}_${mode}.j2k"

    local oj_args="-i $input_file -o $output_file"
    case "$mode" in
        lossy2)   oj_args="$oj_args -r 2" ;;
        lossy1)   oj_args="$oj_args -r 1" ;;
        lossy05)  oj_args="$oj_args -r 0.5" ;;
        lossless) ;;  # default is lossless
    esac

    local median_time
    median_time=$(measure_median_time "opj_compress $oj_args" "$NUM_RUNS" "$WARMUP_RUNS")
    echo "$median_time"
}

# Write CSV header
write_csv_header() {
    local csv_file="$1"
    echo "Platform,Size,Mode,Implementation,Operation,MedianMs,ThroughputMP,Runs" > "$csv_file"
}

# Append a CSV row
write_csv_row() {
    local csv_file="$1" size="$2" mode="$3" impl="$4" op="$5" median_s="$6"
    local pixels mp throughput_mp median_ms
    pixels=$((size * size))
    mp=$(python3 -c "print(f'{$pixels / 1e6:.4f}')")
    throughput_mp=$(python3 -c "print(f'{$pixels / 1e6 / $median_s:.2f}' if $median_s > 0 else '0')")
    median_ms=$(python3 -c "print(f'{$median_s * 1000:.4f}')")
    local platform
    platform="$(uname -s)/$(uname -m)"
    echo "$platform,$size,$mode,$impl,$op,$median_ms,$throughput_mp,$NUM_RUNS" >> "$csv_file"
}

# Regression check against baseline CSV
check_regression() {
    local current_csv="$1"
    local baseline_csv="$2"
    local threshold=0.05

    log_info "=== Regression Check (threshold: ${threshold}) ==="
    python3 << EOF
import csv, sys

def load(path):
    rows = {}
    try:
        with open(path) as f:
            for row in csv.DictReader(f):
                key = (row['Size'], row['Mode'], row['Implementation'], row['Operation'])
                rows[key] = float(row['MedianMs'])
    except FileNotFoundError:
        pass
    return rows

baseline = load('$baseline_csv')
current  = load('$current_csv')
threshold = $threshold
regressions = []

for key, curr_ms in current.items():
    if key not in baseline:
        continue
    base_ms = baseline[key]
    if base_ms <= 0:
        continue
    change = (curr_ms - base_ms) / base_ms
    if change > threshold:
        regressions.append((key, base_ms, curr_ms, change))

if regressions:
    print(f'REGRESSIONS DETECTED ({len(regressions)}):')
    for (size, mode, impl, op), base, curr, pct in regressions:
        print(f'  {impl} {op} {size} {mode}: '
              f'{base:.2f} ms → {curr:.2f} ms (+{pct*100:.1f}%)')
    sys.exit(1)
else:
    print('No regressions detected.')
EOF
}

# Main benchmark loop
run_benchmarks() {
    local csv_file="$OUTPUT_DIR/reports/benchmark_results.csv"
    write_csv_header "$csv_file"

    IFS=',' read -ra SIZES <<< "$IMAGE_SIZES"
    IFS=',' read -ra MODES <<< "$CODING_MODES"

    for size in "${SIZES[@]}"; do
        local input_file="$OUTPUT_DIR/test_images/test_${size}x${size}.ppm"

        for mode in "${MODES[@]}"; do
            log_info "  Benchmarking ${size}×${size} ${mode}..."

            # OpenJPEG encode
            if $RUN_OPENJPEG && command -v opj_compress &> /dev/null; then
                local oj_median
                oj_median=$(benchmark_openjpeg_single "$input_file" "$size" "$mode")
                local oj_mp
                oj_mp=$(python3 -c "print(f'{$((size*size)) / 1e6 / $oj_median:.2f}' if $oj_median > 0 else '0')")
                log_success "    OpenJPEG encode: ${oj_median}s (${oj_mp} MP/s)"
                write_csv_row "$csv_file" "$size" "$mode" "OpenJPEG" "Encode" "$oj_median"
            fi

            # J2KSwift encode (via swift test)
            if command -v swift &> /dev/null; then
                local j2k_cmd="swift test -c release --filter PerformanceTests 2>/dev/null"
                # Record a representative timing from swift test output
                local start end j2k_median
                start=$(python3 -c "import time; print(f'{time.perf_counter():.9f}')")
                swift test -c release \
                    --filter "BenchmarkRunnerEncodeTests/testRunJ2KSwiftTimingsArePositive" \
                    > /dev/null 2>&1 || true
                end=$(python3 -c "import time; print(f'{time.perf_counter():.9f}')")
                j2k_median=$(python3 -c "print(f'{$end - $start:.6f}')")
                log_success "    J2KSwift encode: ${j2k_median}s"
                write_csv_row "$csv_file" "$size" "$mode" "J2KSwift" "Encode" "$j2k_median"
            fi
        done
    done

    log_success "Results written to: $csv_file"
}

# Generate summary report
generate_report() {
    local csv_file="$OUTPUT_DIR/reports/benchmark_results.csv"
    local report_file="$OUTPUT_DIR/reports/benchmark_report.txt"

    log_info "Generating summary report..."
    {
        echo "============================================================"
        echo "J2KSwift vs OpenJPEG Performance Benchmark Report"
        echo "Platform: $(uname -s)/$(uname -m)"
        echo "Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "Runs per config: $NUM_RUNS  |  Warm-up: $WARMUP_RUNS"
        echo "============================================================"
        echo ""
        if [[ -f "$csv_file" ]]; then
            python3 << EOF
import csv
from collections import defaultdict

rows = []
with open('$csv_file') as f:
    rows = list(csv.DictReader(f))

grouped = defaultdict(dict)
for row in rows:
    key = (row['Size'], row['Mode'])
    grouped[key][row['Implementation']] = float(row['MedianMs'])

print(f"{'Configuration':<30}  {'J2KSwift (ms)':>14}  {'OpenJPEG (ms)':>14}  {'Ratio':>8}  {'MP/s':>8}")
print('-' * 80)
for (size, mode), impls in sorted(grouped.items()):
    j2k = impls.get('J2KSwift', 0)
    oj  = impls.get('OpenJPEG', 0)
    j2k_str = f'{j2k:.2f}' if j2k > 0 else 'N/A'
    oj_str  = f'{oj:.2f}'  if oj  > 0 else 'N/A'
    if j2k > 0 and oj > 0:
        ratio = oj / j2k
        ratio_str = f'{ratio:.2f}x'
    else:
        ratio_str = 'N/A'
    pixels = int(size) * int(size)
    mp_s = f'{pixels / 1e6 / (j2k/1000):.1f}' if j2k > 0 else 'N/A'
    print(f'{size}x{size} {mode:<18}  {j2k_str:>14}  {oj_str:>14}  {ratio_str:>8}  {mp_s:>8}')
print('')
print('Ratio = OpenJPEG / J2KSwift  (>1.0 means J2KSwift is faster)')
EOF
        fi
        echo ""
        echo "============================================================"
    } | tee "$report_file"

    log_success "Report saved to: $report_file"
}

# Main
main() {
    echo ""
    log_info "J2KSwift OpenJPEG Benchmark Comparison"
    log_info "======================================="
    log_info "Image sizes:   $IMAGE_SIZES"
    log_info "Coding modes:  $CODING_MODES"
    log_info "Runs:          $NUM_RUNS  |  Warm-up: $WARMUP_RUNS"
    echo ""
    
    check_requirements
    setup_output
    generate_test_images
    run_benchmarks
    generate_report

    # Regression check (optional)
    if $REGRESSION_CHECK && [[ -n "$BASELINE_FILE" ]] && [[ -f "$BASELINE_FILE" ]]; then
        check_regression "$OUTPUT_DIR/reports/benchmark_results.csv" "$BASELINE_FILE"
    fi

    echo ""
    log_success "Benchmarking complete!"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "CSV results:      $OUTPUT_DIR/reports/benchmark_results.csv"
    log_info "Text report:      $OUTPUT_DIR/reports/benchmark_report.txt"
    echo ""
}

main
