#!/usr/bin/env python3
"""
Encoder Performance Profiling Tool

This script provides detailed profiling of the J2KSwift encoder pipeline to identify
performance bottlenecks and optimization opportunities.
"""

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path
from typing import Dict, List, Optional


def create_test_image(size: int, output_path: Path) -> bool:
    """Create a test PGM image with random data."""
    try:
        # Create simple grayscale gradient
        with open(output_path, 'wb') as f:
            f.write(f"P5\n{size} {size}\n255\n".encode('ascii'))
            # Write gradient pattern
            for y in range(size):
                for x in range(size):
                    value = (x + y) % 256
                    f.write(bytes([value]))
        return True
    except Exception as e:
        print(f"Error creating test image: {e}")
        return False


def build_cli_tool(verbose: bool = False) -> bool:
    """Build the j2k CLI tool in release mode."""
    print("Building j2k CLI tool in release mode...")
    cmd = ['swift', 'build', '-c', 'release', '--product', 'j2k']
    
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE if not verbose else None,
        stderr=subprocess.PIPE if not verbose else None
    )
    
    if result.returncode != 0:
        print("Error: Failed to build j2k CLI tool")
        if not verbose and result.stderr:
            print(result.stderr.decode('utf-8'))
        return False
    
    print("Build successful!")
    return True


def run_profiling_test(
    cli_path: Path,
    input_path: Path,
    output_dir: Path,
    preset: str = "balanced",
    runs: int = 5
) -> Optional[Dict]:
    """Run encoder profiling and collect detailed timing data."""
    
    output_file = output_dir / f"profile_{input_path.stem}_{preset}.json"
    
    print(f"\nProfiling {input_path.stem} with preset '{preset}' ({runs} runs)...")
    
    cmd = [
        str(cli_path),
        'benchmark',
        '-i', str(input_path),
        '-o', str(output_file),
        '--preset', preset,
        '--runs', str(runs),
        '--encode-only'
    ]
    
    start = time.perf_counter()
    result = subprocess.run(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    elapsed = time.perf_counter() - start
    
    if result.returncode != 0:
        print(f"Error running profiling test: {result.stderr}")
        return None
    
    # Parse the JSON output
    try:
        with open(output_file, 'r') as f:
            data = json.load(f)
        data['total_wall_time'] = elapsed
        return data
    except Exception as e:
        print(f"Error reading results: {e}")
        return None


def analyze_results(results: Dict, image_size: int) -> Dict:
    """Analyze profiling results and compute statistics."""
    
    encode_stats = results.get('encode', {})
    times_ms = encode_stats.get('runs', [])
    
    if not times_ms:
        return {}
    
    avg_time = encode_stats.get('average_ms', 0)
    throughput = encode_stats.get('throughput_mpps', 0)
    compressed_size = encode_stats.get('compressed_size', 0)
    
    pixels = image_size * image_size
    input_bytes = pixels  # Grayscale image
    compression_ratio = input_bytes / compressed_size if compressed_size > 0 else 0
    
    return {
        'image_size': f'{image_size}×{image_size}',
        'pixels': pixels,
        'avg_time_ms': avg_time,
        'throughput_mpps': throughput,
        'compressed_size_bytes': compressed_size,
        'compression_ratio': compression_ratio,
        'times_ms': times_ms
    }


def generate_report(all_results: List[Dict], output_path: Path):
    """Generate a comprehensive profiling report."""
    
    report = []
    report.append("=" * 80)
    report.append("J2KSwift Encoder Performance Profile Report")
    report.append("=" * 80)
    report.append("")
    
    # Summary table
    report.append("## Encoding Performance Summary")
    report.append("")
    report.append("| Image Size  | Avg Time (ms) | Throughput (MP/s) | Compressed (KB) | Ratio |")
    report.append("|-------------|---------------|-------------------|-----------------|-------|")
    
    for result in all_results:
        size = result.get('image_size', 'N/A')
        avg_time = result.get('avg_time_ms', 0)
        throughput = result.get('throughput_mpps', 0)
        compressed_kb = result.get('compressed_size_bytes', 0) / 1024
        ratio = result.get('compression_ratio', 0)
        
        report.append(
            f"| {size:11} | {avg_time:13.2f} | {throughput:17.2f} | "
            f"{compressed_kb:15.1f} | {ratio:5.2f} |"
        )
    
    report.append("")
    report.append("## Performance Analysis")
    report.append("")
    
    # Identify bottlenecks
    if all_results:
        # Check if performance scales linearly
        if len(all_results) >= 2:
            first = all_results[0]
            last = all_results[-1]
            
            pixel_ratio = last['pixels'] / first['pixels']
            time_ratio = last['avg_time_ms'] / first['avg_time_ms']
            
            scaling_factor = time_ratio / pixel_ratio
            
            report.append(f"### Scalability Analysis")
            report.append(f"- Pixel count increase: {pixel_ratio:.2f}x")
            report.append(f"- Time increase: {time_ratio:.2f}x")
            report.append(f"- Scaling factor: {scaling_factor:.2f} (1.0 = perfect linear scaling)")
            report.append("")
            
            if scaling_factor < 0.9:
                report.append("✅ **Super-linear scaling** - Performance improves with larger images")
            elif scaling_factor < 1.1:
                report.append("✅ **Linear scaling** - Good performance characteristics")
            elif scaling_factor < 1.5:
                report.append("⚠️ **Sub-linear scaling** - Some overhead present")
            else:
                report.append("❌ **Poor scaling** - Significant bottlenecks present")
            report.append("")
    
    report.append("### Key Metrics")
    report.append("")
    
    avg_throughput = sum(r.get('throughput_mpps', 0) for r in all_results) / len(all_results)
    avg_ratio = sum(r.get('compression_ratio', 0) for r in all_results) / len(all_results)
    
    report.append(f"- **Average Throughput**: {avg_throughput:.2f} MP/s")
    report.append(f"- **Average Compression Ratio**: {avg_ratio:.2f}:1")
    report.append("")
    
    # Comparison with target
    target_throughput = 4.0  # Approximate OpenJPEG speed (will vary)
    performance_ratio = (avg_throughput / target_throughput) * 100
    
    report.append("### Performance vs. OpenJPEG Target")
    report.append(f"- **Target Throughput**: ~{target_throughput:.1f} MP/s (80% of OpenJPEG)")
    report.append(f"- **Current Performance**: {performance_ratio:.1f}% of target")
    report.append("")
    
    if performance_ratio >= 80:
        report.append("✅ **Target met!** Performance is within acceptable range.")
    elif performance_ratio >= 50:
        report.append("⚠️ **Approaching target** - Further optimization needed")
    else:
        report.append("❌ **Below target** - Significant optimization required")
    
    report.append("")
    report.append("## Optimization Recommendations")
    report.append("")
    
    # Generate recommendations based on results
    if avg_throughput < 2.0:
        report.append("### High Priority")
        report.append("1. Profile entropy coding (MQ-coder) - likely bottleneck")
        report.append("2. Optimize wavelet transform (DWT) - check for unnecessary allocations")
        report.append("3. Review quantization step - ensure efficient memory access")
        report.append("")
    
    if avg_ratio < 2.0:
        report.append("### Compression Efficiency")
        report.append("1. Review rate control parameters")
        report.append("2. Check quantization step sizes")
        report.append("3. Verify entropy coding is functioning correctly")
        report.append("")
    
    report.append("### General Optimizations")
    report.append("- Use `@inline(__always)` for hot path functions")
    report.append("- Pre-allocate buffers to avoid repeated allocations")
    report.append("- Consider SIMD operations for data-parallel operations")
    report.append("- Profile with Instruments to identify specific hot spots")
    report.append("")
    
    report.append("=" * 80)
    report.append(f"Report generated: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    report.append("=" * 80)
    
    # Write report
    with open(output_path, 'w') as f:
        f.write('\n'.join(report))
    
    print(f"\nReport saved to: {output_path}")
    print('\n'.join(report))


def main():
    parser = argparse.ArgumentParser(
        description='Profile J2KSwift encoder performance'
    )
    parser.add_argument(
        '-s', '--sizes',
        type=str,
        default='256,512,1024',
        help='Comma-separated list of image sizes to test (default: 256,512,1024)'
    )
    parser.add_argument(
        '-r', '--runs',
        type=int,
        default=5,
        help='Number of runs per test (default: 5)'
    )
    parser.add_argument(
        '-p', '--preset',
        type=str,
        default='balanced',
        choices=['fast', 'balanced', 'quality'],
        help='Encoding preset to use (default: balanced)'
    )
    parser.add_argument(
        '-o', '--output',
        type=str,
        default='./profile_results',
        help='Output directory for results (default: ./profile_results)'
    )
    parser.add_argument(
        '--skip-build',
        action='store_true',
        help='Skip building J2KCLI (use existing binary)'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Verbose output'
    )
    
    args = parser.parse_args()
    
    # Parse sizes
    try:
        sizes = [int(s.strip()) for s in args.sizes.split(',')]
    except ValueError:
        print("Error: Invalid size specification")
        return 1
    
    # Setup directories
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    test_images_dir = output_dir / 'test_images'
    test_images_dir.mkdir(exist_ok=True)
    
    # Build CLI tool
    if not args.skip_build:
        if not build_cli_tool(args.verbose):
            return 1
    
    # Find CLI tool
    cli_path = Path('.build/release/j2k')
    if not cli_path.exists():
        print(f"Error: CLI tool not found at {cli_path}")
        print("Try running without --skip-build")
        return 1
    
    # Create test images
    print("\nCreating test images...")
    test_images = []
    for size in sizes:
        img_path = test_images_dir / f'test_{size}x{size}.pgm'
        if not img_path.exists():
            print(f"  Creating {size}×{size} test image...")
            if not create_test_image(size, img_path):
                return 1
        test_images.append(img_path)
    
    # Run profiling tests
    print("\n" + "=" * 80)
    print("Starting Encoder Performance Profiling")
    print("=" * 80)
    
    all_results = []
    for img_path in test_images:
        result = run_profiling_test(
            cli_path, img_path, output_dir, args.preset, args.runs
        )
        if result:
            size = int(img_path.stem.split('_')[1].split('x')[0])
            analysis = analyze_results(result, size)
            all_results.append(analysis)
    
    # Generate report
    if all_results:
        report_path = output_dir / 'profile_report.txt'
        generate_report(all_results, report_path)
    else:
        print("\nError: No results collected")
        return 1
    
    print("\nProfiling complete!")
    return 0


if __name__ == '__main__':
    sys.exit(main())
