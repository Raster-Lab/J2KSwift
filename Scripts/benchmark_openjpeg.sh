#!/bin/bash
#
# J2KSwift OpenJPEG Benchmark Comparison Script
#
# This script automates performance comparison between J2KSwift and OpenJPEG.
# It generates test images, encodes/decodes them with both implementations,
# and produces a detailed comparison report.
#
# Requirements:
# - OpenJPEG (opj_compress, opj_decompress)
# - Swift 6.2+
# - ImageMagick (optional, for test image generation)
#
# Usage:
#   ./benchmark_openjpeg.sh [options]
#
# Options:
#   -h, --help          Show this help message
#   -o, --output DIR    Output directory for results (default: ./benchmark_results)
#   -s, --sizes SIZES   Comma-separated list of image sizes (default: 512,1024)
#   -r, --runs N        Number of benchmark runs (default: 3)
#   --no-openjpeg       Skip OpenJPEG benchmarks (J2KSwift only)
#

set -e

# Default configuration
OUTPUT_DIR="./benchmark_results"
IMAGE_SIZES="512,1024"
NUM_RUNS=3
RUN_OPENJPEG=true

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
        -r|--runs)
            NUM_RUNS="$2"
            shift 2
            ;;
        --no-openjpeg)
            RUN_OPENJPEG=false
            shift
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
    fi
    
    log_success "Requirements check complete"
}

# Setup
setup_output() {
    log_info "Setting up output directory: $OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR/test_images"
    mkdir -p "$OUTPUT_DIR/openjpeg"
    mkdir -p "$OUTPUT_DIR/reports"
}

# Generate test images
generate_test_images() {
    log_info "Generating test images..."
    
    IFS=',' read -ra SIZES <<< "$IMAGE_SIZES"
    for size in "${SIZES[@]}"; do
        local output_file="$OUTPUT_DIR/test_images/test_${size}x${size}.pgm"
        
        if [[ -f "$output_file" ]]; then
            log_info "  Test image ${size}×${size} already exists"
            continue
        fi
        
        log_info "  Generating ${size}×${size} test image..."
        python3 << EOF
import random
size = $size
with open('$output_file', 'wb') as f:
    f.write(f'P5\n{size} {size}\n255\n'.encode())
    data = bytes([random.randint(0, 255) for _ in range(size * size)])
    f.write(data)
EOF
        log_success "  Generated test_${size}x${size}.pgm"
    done
}

# Main
main() {
    echo ""
    log_info "J2KSwift OpenJPEG Benchmark Comparison"
    log_info "======================================="
    echo ""
    
    check_requirements
    setup_output
    generate_test_images
    
    // Build J2KSwift CLI tool
    log_info "Building J2KSwift CLI tool..."
    if command -v swift &> /dev/null; then
        cd "$(dirname "$0")/.." || exit 1
        swift build --product j2k --configuration release 2>&1 | grep -E "(error|Error)" || true
        if [ $? -eq 0 ] && [ -f ".build/release/j2k" ]; then
            J2K_CLI="$(pwd)/.build/release/j2k"
            log_success "J2KSwift CLI built: $J2K_CLI"
        else
            log_warning "Failed to build J2KSwift CLI, benchmarking will be incomplete"
            J2K_CLI=""
        fi
        cd - > /dev/null || exit 1
    else
        log_warning "Swift not found, skipping J2KSwift benchmarks"
        J2K_CLI=""
    fi
    
    # Benchmark J2KSwift
    if [ -n "$J2K_CLI" ]; then
        log_info "Running J2KSwift benchmarks..."
        IFS=',' read -ra SIZES <<< "$IMAGE_SIZES"
        for size in "${SIZES[@]}"; do
            local input_file="$OUTPUT_DIR/test_images/test_${size}x${size}.pgm"
            local output_file="$OUTPUT_DIR/j2kswift/test_${size}x${size}.json"
            
            mkdir -p "$OUTPUT_DIR/j2kswift"
            
            log_info "  Benchmarking ${size}×${size}..."
            "$J2K_CLI" benchmark -i "$input_file" -r "$NUM_RUNS" -o "$output_file" > /dev/null 2>&1
            
            if [ -f "$output_file" ]; then
                log_success "  Saved results to: $output_file"
            fi
        done
    fi
    
    # Benchmark OpenJPEG
    if $RUN_OPENJPEG && command -v opj_compress &> /dev/null; then
        log_info "Running OpenJPEG benchmarks..."
        IFS=',' read -ra SIZES <<< "$IMAGE_SIZES"
        for size in "${SIZES[@]}"; do
            local input_file="$OUTPUT_DIR/test_images/test_${size}x${size}.pgm"
            local output_file="$OUTPUT_DIR/openjpeg/test_${size}x${size}.j2k"
            
            log_info "  Benchmarking ${size}×${size}..."
            
            # Run encoding benchmark
            local total_time=0
            for ((i=1; i<=$NUM_RUNS; i++)); do
                local start=$(date +%s.%N)
                opj_compress -i "$input_file" -o "$output_file" > /dev/null 2>&1
                local end=$(date +%s.%N)
                local elapsed=$(echo "$end - $start" | bc)
                total_time=$(echo "$total_time + $elapsed" | bc)
            done
            
            local avg_time=$(echo "scale=3; $total_time / $NUM_RUNS" | bc)
            log_success "  Average encode time: ${avg_time}s"
        done
    fi
    
    echo ""
    log_success "Benchmarking complete! Results in: $OUTPUT_DIR"
    if [ -n "$J2K_CLI" ]; then
        log_info "J2KSwift results: $OUTPUT_DIR/j2kswift/"
    fi
    if $RUN_OPENJPEG && command -v opj_compress &> /dev/null; then
        log_info "OpenJPEG results: $OUTPUT_DIR/openjpeg/"
    fi
    echo ""
}

main
