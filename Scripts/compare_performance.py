#!/usr/bin/env python3
"""
J2KSwift vs OpenJPEG Performance Comparison Tool

This script provides comprehensive performance benchmarking between J2KSwift
and OpenJPEG, including detailed comparison reports, charts, and analysis.
"""

import json
import subprocess
import time
import statistics
import sys
import os
from pathlib import Path
from typing import Dict, List, Tuple, Optional
import argparse


class BenchmarkResult:
    """Container for benchmark results."""
    
    def __init__(self, implementation: str, image_size: int, operation: str):
        self.implementation = implementation
        self.image_size = image_size
        self.operation = operation  # 'encode' or 'decode'
        self.times: List[float] = []
        self.compressed_size: Optional[int] = None
        self.memory_peak: Optional[int] = None
    
    @property
    def average(self) -> float:
        return statistics.mean(self.times) if self.times else 0.0
    
    @property
    def median(self) -> float:
        return statistics.median(self.times) if self.times else 0.0
    
    @property
    def std_dev(self) -> float:
        return statistics.stdev(self.times) if len(self.times) > 1 else 0.0
    
    @property
    def min_time(self) -> float:
        return min(self.times) if self.times else 0.0
    
    @property
    def max_time(self) -> float:
        return max(self.times) if self.times else 0.0
    
    @property
    def throughput(self) -> float:
        """Throughput in megapixels per second."""
        if self.average > 0:
            megapixels = (self.image_size * self.image_size) / 1_000_000
            return megapixels / self.average
        return 0.0


def run_openjpeg_encode(input_file: Path, output_file: Path, runs: int) -> BenchmarkResult:
    """Benchmark OpenJPEG encoding."""
    result = BenchmarkResult('OpenJPEG', int(input_file.stem.split('_')[1].split('x')[0]), 'encode')
    
    for i in range(runs):
        start = time.perf_counter()
        subprocess.run(
            ['opj_compress', '-i', str(input_file), '-o', str(output_file)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True
        )
        elapsed = time.perf_counter() - start
        result.times.append(elapsed)
    
    if output_file.exists():
        result.compressed_size = output_file.stat().st_size
    
    return result


def run_openjpeg_decode(input_file: Path, output_file: Path, runs: int) -> BenchmarkResult:
    """Benchmark OpenJPEG decoding."""
    # Determine image size from the encoded file name
    size_str = input_file.stem.split('_')[1]
    image_size = int(size_str.split('x')[0])
    
    result = BenchmarkResult('OpenJPEG', image_size, 'decode')
    
    for i in range(runs):
        start = time.perf_counter()
        subprocess.run(
            ['opj_decompress', '-i', str(input_file), '-o', str(output_file)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True
        )
        elapsed = time.perf_counter() - start
        result.times.append(elapsed)
    
    return result


def run_j2kswift_benchmark(cli_path: Path, input_file: Path, output_file: Path, runs: int) -> Tuple[BenchmarkResult, Optional[BenchmarkResult]]:
    """Run J2KSwift benchmark and return encode and decode results."""
    # Run the j2k benchmark command
    result = subprocess.run(
        [str(cli_path), 'benchmark', '-i', str(input_file), '-r', str(runs), '-o', str(output_file)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    
    # Check if benchmark succeeded
    if result.returncode != 0:
        # Try encode-only if full benchmark failed
        print(f"    Warning: Full benchmark failed, trying encode-only...")
        result = subprocess.run(
            [str(cli_path), 'benchmark', '-i', str(input_file), '-r', str(runs), '-o', str(output_file), '--encode-only'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL
        )
        if result.returncode != 0:
            raise RuntimeError(f"J2KSwift benchmark failed even with encode-only")
    
    # Parse the JSON output
    with open(output_file, 'r') as f:
        data = json.load(f)
    
    image_size = data['image']['width']
    
    # Create encode result
    encode_result = BenchmarkResult('J2KSwift', image_size, 'encode')
    encode_result.times = [t / 1000.0 for t in data['encode']['runs']]  # Convert ms to seconds
    encode_result.compressed_size = data['encode'].get('compressed_size')
    
    # Create decode result if available
    decode_result = None
    if 'decode' in data:
        decode_result = BenchmarkResult('J2KSwift', image_size, 'decode')
        decode_result.times = [t / 1000.0 for t in data['decode']['runs']]  # Convert ms to seconds
    
    return encode_result, decode_result


def generate_markdown_report(results: List[BenchmarkResult], output_file: Path):
    """Generate a Markdown comparison report."""
    lines = []
    lines.append("# J2KSwift vs OpenJPEG Performance Comparison")
    lines.append("")
    lines.append(f"**Generated**: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    lines.append("")
    
    # Group results by operation
    encode_results = [r for r in results if r.operation == 'encode']
    decode_results = [r for r in results if r.operation == 'decode']
    
    # Encoding comparison
    lines.append("## Encoding Performance")
    lines.append("")
    lines.append("| Image Size | Implementation | Avg (ms) | Median (ms) | Min (ms) | Max (ms) | Throughput (MP/s) | Compressed Size (KB) | vs OpenJPEG |")
    lines.append("|------------|----------------|----------|-------------|----------|----------|-------------------|---------------------|-------------|")
    
    # Group by image size
    sizes = sorted(set(r.image_size for r in encode_results))
    for size in sizes:
        size_results = [r for r in encode_results if r.image_size == size]
        openjpeg = next((r for r in size_results if r.implementation == 'OpenJPEG'), None)
        j2kswift = next((r for r in size_results if r.implementation == 'J2KSwift'), None)
        
        if j2kswift:
            relative = f"{(openjpeg.average / j2kswift.average * 100):.1f}%" if openjpeg else "N/A"
            size_kb = f"{j2kswift.compressed_size / 1024:.1f}" if j2kswift.compressed_size else "N/A"
            lines.append(f"| {size}×{size} | J2KSwift | {j2kswift.average*1000:.1f} | {j2kswift.median*1000:.1f} | {j2kswift.min_time*1000:.1f} | {j2kswift.max_time*1000:.1f} | {j2kswift.throughput:.2f} | {size_kb} | {relative} |")
        
        if openjpeg:
            size_kb = f"{openjpeg.compressed_size / 1024:.1f}" if openjpeg.compressed_size else "N/A"
            lines.append(f"| {size}×{size} | OpenJPEG | {openjpeg.average*1000:.1f} | {openjpeg.median*1000:.1f} | {openjpeg.min_time*1000:.1f} | {openjpeg.max_time*1000:.1f} | {openjpeg.throughput:.2f} | {size_kb} | 100.0% |")
    
    lines.append("")
    
    # Decoding comparison
    lines.append("## Decoding Performance")
    lines.append("")
    lines.append("| Image Size | Implementation | Avg (ms) | Median (ms) | Min (ms) | Max (ms) | Throughput (MP/s) | vs OpenJPEG |")
    lines.append("|------------|----------------|----------|-------------|----------|----------|-------------------|-------------|")
    
    for size in sizes:
        size_results = [r for r in decode_results if r.image_size == size]
        openjpeg = next((r for r in size_results if r.implementation == 'OpenJPEG'), None)
        j2kswift = next((r for r in size_results if r.implementation == 'J2KSwift'), None)
        
        if j2kswift:
            relative = f"{(openjpeg.average / j2kswift.average * 100):.1f}%" if openjpeg else "N/A"
            lines.append(f"| {size}×{size} | J2KSwift | {j2kswift.average*1000:.1f} | {j2kswift.median*1000:.1f} | {j2kswift.min_time*1000:.1f} | {j2kswift.max_time*1000:.1f} | {j2kswift.throughput:.2f} | {relative} |")
        
        if openjpeg:
            lines.append(f"| {size}×{size} | OpenJPEG | {openjpeg.average*1000:.1f} | {openjpeg.median*1000:.1f} | {openjpeg.min_time*1000:.1f} | {openjpeg.max_time*1000:.1f} | {openjpeg.throughput:.2f} | 100.0% |")
    
    lines.append("")
    
    # Summary
    lines.append("## Summary")
    lines.append("")
    
    # Calculate overall performance
    j2k_encode_avg = statistics.mean([r.average for r in encode_results if r.implementation == 'J2KSwift'])
    opj_encode_avg = statistics.mean([r.average for r in encode_results if r.implementation == 'OpenJPEG'])
    encode_ratio = (opj_encode_avg / j2k_encode_avg) * 100 if j2k_encode_avg > 0 else 0
    
    j2k_decode_results = [r for r in decode_results if r.implementation == 'J2KSwift']
    opj_decode_results = [r for r in decode_results if r.implementation == 'OpenJPEG']
    
    decode_ratio = 0
    if j2k_decode_results and opj_decode_results:
        j2k_decode_avg = statistics.mean([r.average for r in j2k_decode_results])
        opj_decode_avg = statistics.mean([r.average for r in opj_decode_results])
        decode_ratio = (opj_decode_avg / j2k_decode_avg) * 100 if j2k_decode_avg > 0 else 0
    
    lines.append(f"- **Encoding**: J2KSwift is {encode_ratio:.1f}% of OpenJPEG speed")
    lines.append(f"  - Target: ≥80% (within 80% of OpenJPEG)")
    lines.append(f"  - Status: {'✅ PASS' if encode_ratio >= 80 else '❌ FAIL'}")
    lines.append("")
    
    if j2k_decode_results:
        lines.append(f"- **Decoding**: J2KSwift is {decode_ratio:.1f}% of OpenJPEG speed")
        lines.append(f"  - Target: ≥80% (within 80% of OpenJPEG)")
        lines.append(f"  - Status: {'✅ PASS' if decode_ratio >= 80 else '❌ FAIL'}")
    else:
        lines.append("- **Decoding**: J2KSwift decoder currently has errors preventing benchmark")
    lines.append("")
    
    # Write report
    output_file.write_text('\n'.join(lines))


def generate_csv_report(results: List[BenchmarkResult], output_file: Path):
    """Generate a CSV report for data analysis."""
    lines = []
    lines.append("ImageSize,Implementation,Operation,AvgTime(ms),MedianTime(ms),MinTime(ms),MaxTime(ms),StdDev(ms),Throughput(MP/s),CompressedSize(B)")
    
    for r in results:
        compressed_size = r.compressed_size if r.compressed_size else ''
        lines.append(f"{r.image_size},{r.implementation},{r.operation},{r.average*1000:.3f},{r.median*1000:.3f},{r.min_time*1000:.3f},{r.max_time*1000:.3f},{r.std_dev*1000:.3f},{r.throughput:.3f},{compressed_size}")
    
    output_file.write_text('\n'.join(lines))


def main():
    parser = argparse.ArgumentParser(description='J2KSwift vs OpenJPEG Performance Comparison')
    parser.add_argument('-s', '--sizes', default='256,512,1024', help='Comma-separated image sizes')
    parser.add_argument('-r', '--runs', type=int, default=5, help='Number of benchmark runs')
    parser.add_argument('-o', '--output', default='./benchmark_results', help='Output directory')
    parser.add_argument('--j2k-cli', help='Path to j2k CLI tool')
    
    args = parser.parse_args()
    
    # Setup paths
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    test_images_dir = output_dir / 'test_images'
    test_images_dir.mkdir(exist_ok=True)
    
    openjpeg_dir = output_dir / 'openjpeg'
    openjpeg_dir.mkdir(exist_ok=True)
    
    j2kswift_dir = output_dir / 'j2kswift'
    j2kswift_dir.mkdir(exist_ok=True)
    
    reports_dir = output_dir / 'reports'
    reports_dir.mkdir(exist_ok=True)
    
    # Find j2k CLI
    if args.j2k_cli:
        j2k_cli = Path(args.j2k_cli)
    else:
        j2k_cli = Path.cwd() / '.build' / 'release' / 'j2k'
        if not j2k_cli.exists():
            j2k_cli = Path.cwd() / '.build' / 'debug' / 'j2k'
    
    if not j2k_cli.exists():
        print(f"Error: j2k CLI not found at {j2k_cli}")
        sys.exit(1)
    
    print("J2KSwift vs OpenJPEG Performance Comparison")
    print("=" * 60)
    print(f"Output directory: {output_dir}")
    print(f"Benchmark runs: {args.runs}")
    print(f"Image sizes: {args.sizes}")
    print()
    
    # Parse image sizes
    sizes = [int(s.strip()) for s in args.sizes.split(',')]
    
    # Generate test images
    print("Generating test images...")
    for size in sizes:
        pgm_file = test_images_dir / f'test_{size}x{size}.pgm'
        if not pgm_file.exists():
            # Generate simple test image with Python
            with open(pgm_file, 'wb') as f:
                f.write(f'P5\n{size} {size}\n255\n'.encode())
                import random
                data = bytes([random.randint(0, 255) for _ in range(size * size)])
                f.write(data)
            print(f"  Generated {size}×{size} test image")
        else:
            print(f"  Using existing {size}×{size} test image")
    
    print()
    
    # Run benchmarks
    all_results = []
    
    for size in sizes:
        print(f"Benchmarking {size}×{size}...")
        
        pgm_file = test_images_dir / f'test_{size}x{size}.pgm'
        j2k_file = openjpeg_dir / f'test_{size}x{size}.j2k'
        decoded_pgm = openjpeg_dir / f'test_{size}x{size}_decoded.pgm'
        json_file = j2kswift_dir / f'test_{size}x{size}.json'
        
        # J2KSwift benchmark (both encode and decode)
        print(f"  Running J2KSwift benchmark...")
        encode_result, decode_result = run_j2kswift_benchmark(j2k_cli, pgm_file, json_file, args.runs)
        all_results.append(encode_result)
        print(f"    Encode: {encode_result.average*1000:.1f}ms avg ({encode_result.throughput:.2f} MP/s)")
        
        if decode_result:
            all_results.append(decode_result)
            print(f"    Decode: {decode_result.average*1000:.1f}ms avg ({decode_result.throughput:.2f} MP/s)")
        else:
            print(f"    Decode: FAILED (decoder error)")
        
        # OpenJPEG encode benchmark
        print(f"  Running OpenJPEG encode benchmark...")
        opj_encode_result = run_openjpeg_encode(pgm_file, j2k_file, args.runs)
        all_results.append(opj_encode_result)
        print(f"    Encode: {opj_encode_result.average*1000:.1f}ms avg ({opj_encode_result.throughput:.2f} MP/s)")
        
        # OpenJPEG decode benchmark
        print(f"  Running OpenJPEG decode benchmark...")
        opj_decode_result = run_openjpeg_decode(j2k_file, decoded_pgm, args.runs)
        all_results.append(opj_decode_result)
        print(f"    Decode: {opj_decode_result.average*1000:.1f}ms avg ({opj_decode_result.throughput:.2f} MP/s)")
        
        # Comparison
        encode_ratio = (opj_encode_result.average / encode_result.average) * 100
        print(f"  J2KSwift vs OpenJPEG:")
        print(f"    Encode: {encode_ratio:.1f}% of OpenJPEG speed")
        
        if decode_result:
            decode_ratio = (opj_decode_result.average / decode_result.average) * 100
            print(f"    Decode: {decode_ratio:.1f}% of OpenJPEG speed")
        print()
    
    # Generate reports
    print("Generating reports...")
    generate_markdown_report(all_results, reports_dir / 'performance_comparison.md')
    print(f"  Markdown report: {reports_dir / 'performance_comparison.md'}")
    
    generate_csv_report(all_results, reports_dir / 'performance_data.csv')
    print(f"  CSV report: {reports_dir / 'performance_data.csv'}")
    
    print()
    print("Benchmark complete!")


if __name__ == '__main__':
    main()
